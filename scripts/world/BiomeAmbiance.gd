@tool
class_name BiomeAmbiance
extends Node3D

## Ambiance HD-2D des scènes de combat : chaque MapTheme a une signature
## atmosphérique distincte (chantier 1), pas seulement des tuiles différentes.
##
## Regroupe tout le "météo/lumière" de la scène :
##   - WorldEnvironment (ciel procédural, fog, glow, tonemap filmique, SSAO) ;
##   - DirectionalLight3D avec ombres portées (requis par le relief 3D) ;
##   - brume au ras du sol pour le marécage (GPUParticles3D discret) ;
##   - collines lointaines + nuages dérivants (chantier 3), rayon adapté à
##     la taille de la map.
##
## CombatArena crée ce nœud une fois puis appelle apply_theme() après chaque
## génération de zone — cohérent avec _theme_config()/_apply_theme() côté tuiles.
## NB : le SSAO est configuré mais n'a d'effet que hors renderer Compatibility
## (le projet est en GL Compatibility — il s'activera en passant en Forward+).
##
## Lisibilité gameplay : le combat est en temps réel — les presets gardent un
## plancher d'ambiance/énergie solaire pour ne jamais noyer ennemis/attaques.

const CLOUD_COUNT := 9

var _world_env: WorldEnvironment   = null
var _sun:       DirectionalLight3D = null
var _mist:      GPUParticles3D     = null
var _leaves:    GPUParticles3D     = null
var _fireflies: GPUParticles3D     = null
var _terrain:   Node               = null   # map courante (relief) — pour les papillons
var _backdrop:  Node3D             = null
var _clouds:    Array              = []   # [{node, speed}, ...]
var _map_size:  Vector2i           = Vector2i(80, 45)

static var _cloud_tex: GradientTexture2D = null
static var _mist_tex:  GradientTexture2D = null


## Reconfigure toute l'ambiance pour `theme` (MapGenerator.MapTheme) et une
## map de `map_cell_size` cases. `is_cave` = arène de grotte : variante
## rocheuse assombrie, sans nuages ni collines (on est "sous terre").
## `terrain` (optionnel) = la map courante, pour que la vie ambiante
## (papillons) suive le relief.
func apply_theme(theme: int, map_cell_size: Vector2i, is_cave: bool = false, terrain: Node = null) -> void:
	_map_size = map_cell_size
	_terrain  = terrain
	var cfg := _theme_ambiance(theme, is_cave)
	_apply_environment(cfg)
	_apply_sun(cfg)
	_apply_mist(cfg)
	_apply_leaves(cfg)
	_apply_fireflies(cfg)
	_rebuild_backdrop(cfg, is_cave)


## ── Presets — mêmes clés pour les 4 thèmes + variante grotte ──────────────

func _theme_ambiance(theme: int, is_cave: bool) -> Dictionary:
	if is_cave:
		return _merged(_CAVE_PALETTE)
	match theme:
		MapGenerator.MapTheme.SWAMP:  return _merged(_SWAMP_PALETTE)
		MapGenerator.MapTheme.FOREST: return _merged(_FOREST_PALETTE)
		MapGenerator.MapTheme.ROCKY:  return _merged(_ROCKY_PALETTE)
		MapGenerator.MapTheme.AUTUMN: return _merged(_AUTUMN_PALETTE)
		MapGenerator.MapTheme.LAKE:   return _merged(_LAKE_PALETTE)
		_:                            return _merged(_MEADOW_PALETTE)


## ── Base commune à TOUS les biomes ─────────────────────────────────────────
## La cohérence est structurelle : luminosité, exposition, angle du soleil
## (→ direction d'ombres IDENTIQUE d'une zone à l'autre — les zones
## s'enchaînent dans une même run), grain de brouillard et intensité de glow
## sont réglés UNE fois ici. Chaque biome ne définit plus que sa PALETTE
## (teintes ciel / brouillard / soleil / collines) et sa signature de vie
## ambiante (brume, feuilles, lucioles, papillons). Ajuster le "feel" global
## = toucher uniquement cette table.

const _BASE_AMBIANCE := {
	# Ambiance volontairement SOMBRE et voilée (retour joueur : trop clair =
	# illisible) : exposition et soleil baissés, brume légère PARTOUT par
	# défaut — chaque palette ne fait qu'accentuer ou teinter.
	"ambient_energy": 0.22,
	"fog_density":    0.010,
	"fog_scatter":    0.10,
	"glow_intensity": 0.22,
	"glow_bloom":     0.06,
	"sun_energy":     0.52,
	"sun_angles":     Vector3(-52, -32, 0),
	"exposure":       0.74,
	"mist":           true,   # nappe discrète au ras du sol, partout
	"mist_color":     Color(0.70, 0.72, 0.68, 0.05),
	"cloud_alpha":    0.55,
	"cloud_tint":     Color(1.0, 1.0, 1.0),
}

## Palettes — uniquement des TEINTES + signatures. Les écarts de densité de
## brouillard sont volontairement bornés (0.003–0.011) pour que le passage
## d'une zone à l'autre ne saute jamais aux yeux.

const _FOREST_PALETTE := {
	# Sous-bois frais : verts doux, soleil filtré légèrement chlorophylle.
	"sky_top":      Color(0.42, 0.60, 0.80),
	"sky_horizon":  Color(0.74, 0.80, 0.66),
	"fog_color":    Color(0.58, 0.66, 0.54),
	"sun_color":    Color(0.95, 1.0, 0.85),
	"hill_a":       Color(0.33, 0.46, 0.40),
	"hill_b":       Color(0.27, 0.40, 0.35),
	"cloud_tint":   Color(0.95, 0.97, 0.95),
	"leaves":       true,
	"leaves_color": Color(0.45, 0.58, 0.22, 0.85),
	"ground_tint":  Color(0.30, 0.50, 0.26),
}

const _SWAMP_PALETTE := {
	# Marécage : mêmes verts que la forêt mais DÉSATURÉS et voilés — la
	# signature est la brume au sol + le brouillard plus dense, pas un
	# changement de luminosité.
	"sky_top":      Color(0.48, 0.55, 0.58),
	"sky_horizon":  Color(0.68, 0.70, 0.62),
	"fog_color":    Color(0.55, 0.60, 0.52),
	"fog_density":  0.014,
	"sun_color":    Color(0.90, 0.94, 0.82),
	"hill_a":       Color(0.36, 0.42, 0.38),
	"hill_b":       Color(0.30, 0.36, 0.34),
	"cloud_alpha":  0.42,
	"cloud_tint":   Color(0.82, 0.84, 0.80),
	"mist":         true,
	"mist_color":   Color(0.72, 0.78, 0.66, 0.09),
	"fireflies":    Color(0.85, 1.0, 0.45),
	"ground_tint":  Color(0.36, 0.40, 0.28),
}

const _ROCKY_PALETTE := {
	# Rocailleux : ocres secs, air limpide (peu de fog) — le relief 3D des
	# falaises travaille avec la même lumière que partout ailleurs.
	"sky_top":      Color(0.44, 0.60, 0.82),
	"sky_horizon":  Color(0.84, 0.76, 0.62),
	"fog_color":    Color(0.72, 0.66, 0.56),
	"fog_density":  0.007,
	"sun_color":    Color(1.0, 0.90, 0.74),
	"hill_a":       Color(0.52, 0.46, 0.40),
	"hill_b":       Color(0.44, 0.40, 0.36),
	"cloud_tint":   Color(1.0, 0.98, 0.94),
	"midground_cliffs": true,
	"ground_tint":  Color(0.44, 0.48, 0.34),
}

const _AUTUMN_PALETTE := {
	# Automne : mêmes réglages, teintes dorées — l'heure dorée vient de la
	# COULEUR du soleil et du ciel, pas d'un soleil plus bas (ombres cohérentes).
	"sky_top":      Color(0.48, 0.56, 0.74),
	"sky_horizon":  Color(0.88, 0.74, 0.54),
	"fog_color":    Color(0.70, 0.62, 0.50),
	"sun_color":    Color(1.0, 0.84, 0.58),
	"hill_a":       Color(0.55, 0.44, 0.30),
	"hill_b":       Color(0.46, 0.36, 0.26),
	"cloud_tint":   Color(1.0, 0.94, 0.85),
	"leaves":       true,
	"leaves_color": Color(0.85, 0.45, 0.12, 0.9),
	"butterflies":  3,
	"ground_tint":  Color(0.72, 0.56, 0.24),
}

const _LAKE_PALETTE := {
	# Lac : bleus francs et air clair — le pendant "eau" de la prairie.
	"sky_top":      Color(0.38, 0.62, 0.94),
	"sky_horizon":  Color(0.78, 0.88, 0.94),
	"fog_color":    Color(0.70, 0.82, 0.90),
	"fog_density":  0.007,
	"sun_color":    Color(1.0, 0.96, 0.86),
	"hill_a":       Color(0.42, 0.58, 0.66),
	"hill_b":       Color(0.36, 0.52, 0.62),
	"cloud_alpha":  0.62,
	"butterflies":  4,
	"ground_tint":  Color(0.30, 0.52, 0.46),
}

const _MEADOW_PALETTE := {
	# Prairie : la référence "beau temps" — palette neutre chaude.
	"sky_top":      Color(0.44, 0.66, 0.92),
	"sky_horizon":  Color(0.84, 0.82, 0.68),
	"fog_color":    Color(0.72, 0.72, 0.64),
	"fog_density":  0.007,
	"sun_color":    Color(1.0, 0.93, 0.80),
	"hill_a":       Color(0.46, 0.60, 0.58),
	"hill_b":       Color(0.40, 0.54, 0.56),
	"cloud_alpha":  0.62,
	"butterflies":  6,
	"ground_tint":  Color(0.42, 0.64, 0.32),
}

const _CAVE_PALETTE := {
	# Grotte : même exposition que dehors (pas de coup de pompe en entrant),
	# lumière froide tamisée, halo de spores — pas de ciel visible de toute
	# façon (le backdrop est coupé en grotte).
	"sky_top":      Color(0.16, 0.15, 0.20),
	"sky_horizon":  Color(0.28, 0.25, 0.24),
	"ambient_energy": 0.30,
	"fog_color":    Color(0.30, 0.28, 0.30),
	"fog_density":  0.010,
	"fog_scatter":  0.0,
	"glow_intensity": 0.28,
	"glow_bloom":   0.09,
	"sun_color":    Color(0.80, 0.82, 0.95),
	"sun_energy":   0.44,
	"hill_a":       Color(0.20, 0.18, 0.20),
	"hill_b":       Color(0.14, 0.13, 0.16),
	"cloud_alpha":  0.0,
	"mist":         true,
	"mist_color":   Color(0.55, 0.55, 0.62, 0.06),
	"fireflies":    Color(0.55, 0.75, 1.0),
	"ground_tint":  Color(0.20, 0.18, 0.20),
}


## Base commune + palette du biome (la palette peut surcharger toute clé).
func _merged(palette: Dictionary) -> Dictionary:
	var cfg := _BASE_AMBIANCE.duplicate()
	cfg.merge(palette, true)
	return cfg


## ── Environment / lumière ─────────────────────────────────────────────────

func _apply_environment(cfg: Dictionary) -> void:
	if _world_env == null:
		_world_env = WorldEnvironment.new()
		add_child(_world_env)

	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color        = cfg["sky_top"]
	sky_mat.sky_horizon_color    = cfg["sky_horizon"]
	sky_mat.ground_bottom_color  = Color(0.30, 0.28, 0.24)
	sky_mat.ground_horizon_color = cfg["sky_horizon"]
	sky.sky_material = sky_mat
	e.sky = sky

	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = cfg["ambient_energy"]
	e.fog_enabled     = true
	e.fog_light_color = cfg["fog_color"]
	e.fog_density     = cfg["fog_density"]
	e.fog_sun_scatter = cfg["fog_scatter"]
	e.glow_enabled    = true
	e.glow_intensity  = cfg["glow_intensity"]
	e.glow_bloom      = cfg["glow_bloom"]
	e.tonemap_mode    = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = cfg["exposure"]
	# Couleurs plus SATURÉES (retour utilisateur : le rendu délavé manquait
	# de punch — référence : verts francs des mockups).
	e.adjustment_enabled    = true
	e.adjustment_saturation = cfg.get("saturation", 1.3)

	# Contact-shadowing léger au pied des falaises/structures (chantier 2).
	# Sans effet en GL Compatibility — prêt pour un passage en Forward+.
	e.ssao_enabled   = true
	e.ssao_intensity = 1.2
	e.ssao_radius    = 1.5

	_world_env.environment = e


func _apply_sun(cfg: Dictionary) -> void:
	if _sun == null:
		_sun = DirectionalLight3D.new()
		_sun.shadow_enabled = true   # ombres portées aussi en combat, pas que dans le Hub
		# Mode orthogonal borné : ombres stables pendant les déplacements de
		# caméra (cf. même réglage côté Hub).
		_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		_sun.directional_shadow_max_distance = 44.0   # resserré sur la vue réelle → texels fins, plus de "respiration" des bords
		_sun.shadow_blur = 1.8
		add_child(_sun)
	_sun.rotation_degrees = cfg["sun_angles"]
	_sun.light_color      = cfg["sun_color"]
	_sun.light_energy     = cfg["sun_energy"]


## ── Brume au ras du sol (marécage / grotte) ───────────────────────────────

func _apply_mist(cfg: Dictionary) -> void:
	var want: bool = cfg["mist"]
	if not want:
		if is_instance_valid(_mist):
			_mist.queue_free()
			_mist = null
		return

	if is_instance_valid(_mist):
		_mist.queue_free()
	_mist = GPUParticles3D.new()
	_mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mist.name = "GroundMist"
	_mist.amount   = 42
	_mist.lifetime = 14.0
	_mist.preprocess = 14.0   # la nappe est déjà en place à l'arrivée du joueur
	_mist.position = Vector3(_map_size.x * 0.5, 0.5, _map_size.y * 0.5)

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(_map_size.x * 0.5, 0.15, _map_size.y * 0.5)
	pm.gravity = Vector3.ZERO
	pm.direction = Vector3(1, 0, 0.2)
	pm.initial_velocity_min = 0.25   # dérive lente au ras du sol
	pm.initial_velocity_max = 0.6
	pm.scale_min = 4.0
	pm.scale_max = 9.0
	_mist.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _get_mist_texture()
	mat.albedo_color   = cfg["mist_color"]
	mat.transparency    = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode  = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.cull_mode       = BaseMaterial3D.CULL_DISABLED
	quad.material = mat
	_mist.draw_pass_1 = quad
	add_child(_mist)


## ── Feuilles qui tombent (forêt) — vie ambiante discrète sous la canopée ──

func _apply_leaves(cfg: Dictionary) -> void:
	var want: bool = cfg.get("leaves", false)
	if is_instance_valid(_leaves):
		_leaves.queue_free()
		_leaves = null
	if not want:
		return

	_leaves = GPUParticles3D.new()
	_leaves.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_leaves.name = "FallingLeaves"
	_leaves.amount   = 28
	_leaves.lifetime = 8.0
	_leaves.preprocess = 8.0   # déjà en train de tomber à l'arrivée du joueur
	_leaves.position = Vector3(_map_size.x * 0.5, 4.5, _map_size.y * 0.5)

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(_map_size.x * 0.5, 0.5, _map_size.y * 0.5)
	pm.direction = Vector3(0.4, -1.0, 0.15)
	pm.spread    = 20.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.7
	pm.gravity = Vector3(0, -0.45, 0)
	pm.angular_velocity_min = -120.0   # les feuilles tournoient en tombant
	pm.angular_velocity_max = 120.0
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	_leaves.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.14)
	var mat := StandardMaterial3D.new()
	mat.albedo_color   = cfg.get("leaves_color", Color(0.45, 0.58, 0.22, 0.85))
	mat.transparency    = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode  = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.cull_mode       = BaseMaterial3D.CULL_DISABLED
	quad.material = mat
	_leaves.draw_pass_1 = quad
	add_child(_leaves)


## ── Lucioles / spores lumineuses (marécage, grotte) ───────────────────────
## Petits points lumineux qui dérivent lentement à hauteur d'homme et
## clignotent (fondu entrée/sortie sur la durée de vie, désynchronisé) —
## le glow de l'Environment leur donne leur halo.

func _apply_fireflies(cfg: Dictionary) -> void:
	if is_instance_valid(_fireflies):
		_fireflies.queue_free()
		_fireflies = null
	if not cfg.has("fireflies"):
		return
	var col: Color = cfg["fireflies"]

	_fireflies = GPUParticles3D.new()
	_fireflies.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fireflies.name = "Fireflies"
	_fireflies.amount   = 34
	_fireflies.lifetime = 7.0
	_fireflies.preprocess = 7.0
	_fireflies.position = Vector3(_map_size.x * 0.5, 1.0, _map_size.y * 0.5)

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(_map_size.x * 0.5, 0.6, _map_size.y * 0.5)
	pm.lifetime_randomness = 0.6   # clignotements désynchronisés
	pm.gravity = Vector3.ZERO
	pm.direction = Vector3(1, 0.1, 0.4)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.15
	pm.initial_velocity_max = 0.45
	# Fondu entrée/sortie : la luciole "s'allume" puis "s'éteint"
	var ramp := Gradient.new()
	ramp.set_color(0, Color(col.r, col.g, col.b, 0.0))
	ramp.add_point(0.25, col)
	ramp.add_point(0.75, col)
	ramp.set_color(1, Color(col.r, col.g, col.b, 0.0))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	pm.color_ramp = ramp_tex
	_fireflies.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _get_mist_texture()   # même dégradé radial doux
	mat.albedo_color   = col
	mat.transparency    = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode  = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true   # applique le color_ramp du process material
	quad.material = mat
	_fireflies.draw_pass_1 = quad
	add_child(_fireflies)


## ── Décor lointain : forêt/falaises étagées + collines de fond + nuages ───
## (chantier 3). Trois couches, de la plus proche à la plus lointaine, pour
## qu'on ne voie jamais de vide en regardant vers l'horizon :
##   1. Arbres/falaises en "second plan" (ce que le joueur distingue le
##      mieux) — anneau dense d'arbres billboardés (thèmes végétaux) ou de
##      falaises étagées en escalier façon "wedding cake" (thème rocheux) ;
##   2. Collines lointaines brumeuses (existant) — arrière-plan flou ;
##   3. Nuages, remontés dans le ciel pour ne plus se confondre avec la ligne
##      d'horizon.

func _rebuild_backdrop(cfg: Dictionary, is_cave: bool) -> void:
	if is_instance_valid(_backdrop):
		_backdrop.queue_free()
	_clouds.clear()
	_backdrop = Node3D.new()
	_backdrop.name = "Backdrop"
	add_child(_backdrop)
	if is_cave:
		return   # sous terre : pas d'horizon

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_map_size) + 99
	var center := Vector3(_map_size.x * 0.5, 0, _map_size.y * 0.5)

	_build_ground_apron(cfg, center)
	_build_midground(cfg, rng, center)
	_build_mountains(cfg, rng, center)
	_build_clouds(cfg, rng, center)
	_build_butterflies(cfg, rng)


## Grand tablier de sol plat sous tout le décor lointain — comble le "vide"
## qu'on voyait entre le bord jouable et l'anneau de collines/arbres (on
## voyait à travers, jusqu'au ciel). Teinté avec la couleur de collines du
## biome (déjà accordée au thème) pour se fondre dans l'horizon.
func _build_ground_apron(cfg: Dictionary, center: Vector3) -> void:
	var apron := MeshInstance3D.new()
	apron.name = "GroundApron"
	var plane := PlaneMesh.new()
	# Large marge : le bord du tablier ne doit jamais être visible, même à la
	# caméra dézoomée en éditeur — le brouillard (cfg["fog_density"]) fait
	# disparaître le lointain avant qu'on puisse en voir la limite.
	var span := maxf(_map_size.x, _map_size.y) * 16.0
	plane.size = Vector2(span, span)
	apron.mesh = plane
	# NETTEMENT sous le sol jouable : le relief procédural descend jusqu'à
	# ~-0,55 (MapGenerator.HEIGHT_AMPLITUDE) — à -0,08 le tablier transperçait
	# les creux de collines en grandes taches sombres z-fightantes qui
	# "respiraient" avec la caméra (bug "nuage qui grossit/rétrécit", forêt).
	apron.position = Vector3(center.x, -1.2, center.z)
	# Même texture d'herbe/shader que le sol jouable (cf. GrassPatch.
	# ground_material) au lieu d'un aplat de couleur : le tablier lointain
	# se lisait comme du vide/de la terre nue à côté du sol texturé de la
	# map. Recoloré (tint_strength=1) exactement à la couleur d'herbe/sol
	# du biome (`ground_tint`, cf. palettes) — pas un dérivé des couleurs
	# de collines qui pouvait diverger du vert (ou de l'ocre, etc.) réel.
	var plain: Color = cfg.get("ground_tint", (cfg["hill_a"] as Color).lerp(cfg["hill_b"], 0.4))
	apron.material_override = GrassPatch.ground_material(
		load("res://assets/nature/grass.png"), 1.45, 0.88, span, plain, 1.0)
	apron.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_backdrop.add_child(apron)

	# Bosses de relief doux SUR la plaine (loin, au-delà des murs) — évite le
	# tablier parfaitement plat qui « lisait » comme du vide entre la lisière
	# et les montagnes.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_map_size) * 5 + 71
	var base_r := maxf(_map_size.x, _map_size.y) * 0.5
	for i in 22:
		var ang := rng.randf_range(0.0, TAU)
		var rr := base_r + rng.randf_range(10.0, 40.0)
		var mound := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = rng.randf_range(6.0, 13.0)
		sph.height = sph.radius * 0.9
		sph.radial_segments = 8
		sph.rings = 4
		mound.mesh = sph
		mound.position = Vector3(center.x + cos(ang) * rr, -sph.radius * 0.62 - 1.0,
			center.z + sin(ang) * rr)
		var mm := StandardMaterial3D.new()
		mm.albedo_color = plain.lerp(cfg["hill_b"], rng.randf_range(0.0, 0.4)) * rng.randf_range(0.9, 1.06)
		mm.roughness = 1.0
		mound.material_override = mm
		mound.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_backdrop.add_child(mound)


## Papillons qui voltigent au-dessus de la map (prairie, automne) — enfants
## du backdrop : détruits/recréés proprement à chaque changement de zone.
func _build_butterflies(cfg: Dictionary, rng: RandomNumberGenerator) -> void:
	var count: int = cfg.get("butterflies", 0)
	for i in count:
		var b := Butterfly.new()
		b.anchor = Vector3(
			rng.randf_range(8.0, _map_size.x - 8.0),
			0.0,
			rng.randf_range(8.0, _map_size.y - 8.0)
		)
		b.terrain = _terrain
		_backdrop.add_child(b)


## Second plan tout autour de la map, juste au-delà des murs de bordure —
## mélange d'arbres (silhouette hazy) et de falaises étagées selon le thème,
## pour qu'on ne voie jamais le vide entre le bord jouable et les collines
## lointaines.
func _build_midground(cfg: Dictionary, rng: RandomNumberGenerator, center: Vector3) -> void:
	# Proportion de falaises étagées vs arbres — le rocailleux est surtout
	# fait de falaises, les thèmes végétaux surtout d'arbres.
	var cliff_ratio := 0.75 if cfg.get("midground_cliffs", false) else 0.12
	var base_r := maxf(_map_size.x, _map_size.y) * 0.5
	# CEINTURE DENSE d'arbres sur 2 anneaux entrelacés, juste au-delà des murs
	# de bordure — plus de trou entre la zone jouable et l'horizon.
	for ring in 2:
		var n := 46 - ring * 8
		for i in n:
			var ang := (TAU / float(n)) * i + rng.randf_range(-0.09, 0.09)
			var r := base_r + 2.5 + ring * 6.0 + rng.randf_range(-1.5, 3.5)
			var pos := center + Vector3(cos(ang) * r, 0, sin(ang) * r)
			if ring == 0 and rng.randf() < cliff_ratio:
				_add_cliff_tier(cfg, rng, pos, ang)
			else:
				_add_backdrop_tree(cfg, rng, pos)


## Petit affleurement rocheux en second plan — empile 2-3 vrais blocs de
## falaise du kit nature (mêmes assets que le relief jouable, cf.
## MapRender3D.KIT_CLIFF_FULL), légèrement désaxés, au lieu d'un empilement
## de boîtes plates qui ressemblait à un gâteau de mariage.
func _add_cliff_tier(cfg: Dictionary, rng: RandomNumberGenerator, pos: Vector3, ang: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rng.randf_range(0.0, TAU)
	_backdrop.add_child(root)

	var levels := rng.randi_range(2, 3)
	var s := rng.randf_range(2.4, 3.6)
	var y := 0.0
	for lvl in levels:
		var block := KitProps.instance("cliff_block_rock.glb")
		block.scale    = Vector3.ONE * s
		block.rotation.y = rng.randf_range(0.0, TAU)
		block.position = Vector3(
			rng.randf_range(-0.25, 0.25) * s, y, rng.randf_range(-0.25, 0.25) * s
		)
		root.add_child(block)
		y += s * 0.82
		s *= 0.78
	_disable_shadows(root)   # décor lointain : pas d'ombre intrusive


## Arbre lointain — vrai mesh 3D du kit nature (mêmes assets que le premier
## plan, cf. KitProps), pas d'ombre portée pour rester léger en second plan.
## Le brouillard de la scène (cf. _apply_environment) assure à lui seul la
## perspective atmosphérique — pas besoin de teinter/désaturer à la main.
func _add_backdrop_tree(cfg: Dictionary, rng: RandomNumberGenerator, pos: Vector3) -> void:
	var pool: Array = KitProps.TREES_PINE if cfg.get("midground_cliffs", false) else KitProps.TREES_ROUND
	var file: String = pool[rng.randi() % pool.size()]
	var native_h: float = KitProps.TREE_NATIVE_HEIGHT.get(file, 1.7)
	var tree := KitProps.instance(file)
	var target_h := rng.randf_range(3.0, 6.5)
	tree.scale       = Vector3.ONE * (target_h / native_h)
	tree.rotation.y  = rng.randf_range(0.0, TAU)
	tree.position    = pos
	_backdrop.add_child(tree)
	_disable_shadows(tree)


## Désactive récursivement les ombres portées d'un sous-arbre — pour le
## décor lointain, dont l'ombre ne ferait qu'ajouter du bruit visuel.
func _disable_shadows(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_disable_shadows(child)


## CHAÎNE DE MONTAGNES lointaine — pics low-poly (cônes à 6 facettes) en 2
## anneaux étagés (les plus lointains, plus hauts, se voient derrière les
## premiers), sommets enneigés, teinte de plus en plus bleutée/brumeuse avec
## la distance (perspective atmosphérique). C'est LE point de fuite qui
## comble le vide de l'horizon.
func _build_mountains(cfg: Dictionary, rng: RandomNumberGenerator, center: Vector3) -> void:
	# Roche de base ASSOMBRIE à partir de la couleur de sol du biome
	# (`ground_tint`) — les montagnes doivent trancher sur le ciel pâle tout
	# en restant dans la même famille de teinte que l'herbe/le sol (avant :
	# un bleu-gris fixe qui ne matchait aucun biome, ex. gris sur prairie).
	var ground_tint: Color = cfg.get("ground_tint", cfg["hill_b"])
	var rock: Color = (ground_tint as Color).darkened(0.35).lerp(cfg["hill_b"], 0.25)
	var base_r := maxf(_map_size.x, _map_size.y) * 0.5
	var big: bool = cfg.get("midground_cliffs", false)

	for layer in 2:
		# Distances SÛRES : l'anneau proche reste au-delà de la caméra (qui suit
		# le joueur, ~32 u derrière lui) — sinon une montagne surgit juste à côté
		# de la caméra et barre l'écran d'une bande. Elles ferment l'horizon en
		# masse bleutée derrière la lisière d'arbres.
		var dist := base_r + (30.0 if big else 34.0) + layer * 30.0
		var peak_h := (30.0 if big else 26.0) + layer * 18.0
		var count := 28 + layer * 8
		# Perspective atmosphérique LÉGÈRE seulement (sinon elles disparaissent
		# dans le ciel) : l'anneau lointain à peine bleuté.
		var col := rock.lerp(cfg["fog_color"], 0.06 + 0.12 * layer)
		for i in count:
			var ang := TAU * (float(i) + rng.randf_range(-0.35, 0.35)) / float(count)
			var r := dist + rng.randf_range(-7.0, 7.0)
			var pos := center + Vector3(cos(ang) * r, 0, sin(ang) * r)
			# Grande variation de hauteur → silhouette dentelée (des pics, pas
			# un mur) ; les plus hauts (>1.1×) coiffés de neige.
			var hf := rng.randf_range(0.6, 1.5)
			var h := peak_h * hf
			var bw := h * rng.randf_range(0.5, 0.78)
			_add_mountain(pos, h, bw, col, hf > 1.1)


func _add_mountain(pos: Vector3, h: float, base_w: float, col: Color, snow: bool) -> void:
	var m := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius      = 0.0
	cone.bottom_radius   = base_w
	cone.height          = h
	cone.radial_segments = 6     # facettes low-poly, accordées aux arbres
	cone.rings           = 1
	m.mesh = cone
	m.position = pos + Vector3(0, h * 0.5 - 1.5, 0)   # base enfoncée sous la plaine
	m.rotation.y = randf() * TAU
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 1.0
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_backdrop.add_child(m)
	if snow:
		var cap := MeshInstance3D.new()
		var c2 := CylinderMesh.new()
		c2.top_radius      = 0.0
		c2.bottom_radius   = base_w * 0.40
		c2.height          = h * 0.30
		c2.radial_segments = 6
		c2.rings           = 1
		cap.mesh = c2
		cap.position = pos + Vector3(0, h - h * 0.15 - 1.5, 0)
		cap.rotation.y = m.rotation.y
		var sm := StandardMaterial3D.new()
		sm.albedo_color = col.lerp(Color(0.95, 0.97, 1.0), 0.8)
		sm.roughness = 1.0
		cap.material_override = sm
		cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_backdrop.add_child(cap)


## Nuages — billboards doux qui dérivent lentement (déplacés dans _process),
## remontés bien au-dessus du second plan/des collines pour se lire comme du
## ciel et ne plus se fondre visuellement dans l'horizon.
func _build_clouds(cfg: Dictionary, rng: RandomNumberGenerator, center: Vector3) -> void:
	var alpha: float = cfg["cloud_alpha"]
	if alpha <= 0.0:
		return
	var tint: Color = cfg.get("cloud_tint", Color.WHITE)
	for i in CLOUD_COUNT:
		var spr := Sprite3D.new()
		spr.texture = _get_cloud_texture()
		# FIXED_Y (rotation autour de Y seulement) : avec l'étirement ×2,6 en
		# largeur, un billboard complet ferait "gonfler/dégonfler" le nuage à
		# chaque mouvement de caméra (l'axe étiré pivote face à l'œil).
		spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		spr.shaded    = false
		spr.modulate  = Color(tint.r, tint.g, tint.b, alpha * rng.randf_range(0.7, 1.0))
		# Petits et discrets (mêmes réglages que le Hub) : les grands quads
		# translucides qui se chevauchaient faisaient basculer le tri de
		# transparence d'une frame à l'autre → clignotement.
		spr.pixel_size = rng.randf_range(0.05, 0.10)
		spr.scale = Vector3(2.6, 1.0, 1.0)              # étirés horizontalement
		# Ordre de rendu FIXE par nuage : deux transparents à distance quasi
		# égale de la caméra ne peuvent plus alterner leur ordre de dessin.
		spr.render_priority = i
		# JAMAIS d'ombre portée sur un billboard plein-écran : il pivote face
		# caméra, son ombre changerait de forme à chaque mouvement (tache
		# sombre qui "nage"/clignote au sol).
		spr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# LOIN AU NORD, jamais au-dessus de l'aire de jeu : un nuage qui
		# flotte entre la caméra et le sol fait une tache translucide en
		# plein écran (cf. retour joueur). Près de l'horizon uniquement.
		spr.position = center + Vector3(
			rng.randf_range(-_map_size.x * 0.9, _map_size.x * 0.9),
			rng.randf_range(45.0, 62.0),
			rng.randf_range(-_map_size.y * 1.6, -_map_size.y * 0.6)
		)
		_backdrop.add_child(spr)
		_clouds.append({"node": spr, "speed": rng.randf_range(0.25, 0.7)})


func _process(delta: float) -> void:
	if _clouds.is_empty():
		return
	var wrap := _map_size.x * 1.1
	for c: Dictionary in _clouds:
		var spr: Sprite3D = c["node"]
		if not is_instance_valid(spr):
			continue
		spr.position.x += c["speed"] * delta
		if spr.position.x > _map_size.x * 0.5 + wrap:
			spr.position.x -= wrap * 2.0


## ── Textures douces générées (partagées) ─────────────────────────────────

static func _get_cloud_texture() -> GradientTexture2D:
	if _cloud_tex == null:
		_cloud_tex = _soft_radial(Color(1, 1, 1, 0.9), 96)
	return _cloud_tex


static func _get_mist_texture() -> GradientTexture2D:
	if _mist_tex == null:
		_mist_tex = _soft_radial(Color(1, 1, 1, 1.0), 64)
	return _mist_tex


static func _soft_radial(col: Color, size: int) -> GradientTexture2D:
	var grad := Gradient.new()
	grad.set_color(0, col)
	grad.set_color(1, Color(col.r, col.g, col.b, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient  = grad
	tex.fill      = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to   = Vector2(1.0, 0.5)
	tex.width     = size
	tex.height    = size
	return tex
