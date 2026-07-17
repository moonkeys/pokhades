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
## `interior_house` : l'arène est un INTÉRIEUR DE MAISON (biome Village) et non
## une grotte — lumière chaude de lampe, pas la brume froide d'une caverne.
func apply_theme(theme: int, map_cell_size: Vector2i, is_cave: bool = false,
		terrain: Node = null, interior_house: bool = false) -> void:
	_map_size = map_cell_size
	_terrain  = terrain
	var cfg := _merged(_HOUSE_PALETTE) if (is_cave and interior_house) \
		else _theme_ambiance(theme, is_cave)
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
		MapGenerator.MapTheme.VOLCANO: return _merged(_VOLCANO_PALETTE)
		MapGenerator.MapTheme.VILLAGE: return _merged(_VILLAGE_PALETTE)
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
	# Chaîne de montagnes à l'horizon. Vrai par défaut (rocailleux, volcan…),
	# mais une PRAIRIE cernée de pics n'a aucun sens (retour joueurs) : les
	# biomes qui la désactivent reçoivent à la place une forêt lointaine en
	# anneaux (cf. _build_distant_forest).
	"backdrop_mountains": true,
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
	# Pas de montagnes en prairie : l'horizon est fermé par une forêt lointaine
	# qui s'estompe dans la brume (cf. _build_distant_forest).
	"backdrop_mountains": false,
}

const _VOLCANO_PALETTE := {
	# Volcan : ciel de cendre rougeoyant, brume orange dense, lumière chaude
	# rasante, braises flottantes (fireflies détournées en orange). Le glow
	# accentué fait ressortir la lave émissive (cf. MapRender3D). Collines/
	# ground très sombres (basalte/cendre).
	"sky_top":      Color(0.20, 0.10, 0.12),
	"sky_horizon":  Color(0.55, 0.22, 0.12),
	"ambient_energy": 0.26,
	"fog_color":    Color(0.55, 0.24, 0.14),
	"fog_density":  0.014,
	"glow_intensity": 0.32,
	"glow_bloom":   0.12,
	"sun_color":    Color(1.0, 0.62, 0.40),
	"sun_energy":   0.60,
	"hill_a":       Color(0.26, 0.17, 0.16),
	"hill_b":       Color(0.18, 0.12, 0.12),
	"cloud_alpha":  0.35,
	"cloud_tint":   Color(0.5, 0.32, 0.28),
	"mist":         true,
	"mist_color":   Color(0.55, 0.30, 0.18, 0.06),   # fumerolles
	"fireflies":    Color(1.0, 0.55, 0.18),          # braises
	"midground_cliffs": true,
	"ground_tint":  Color(0.30, 0.18, 0.16),
}

const _VILLAGE_PALETTE := {
	# Village : plein jour dégagé et chaleureux, ciel bleu franc — ambiance
	# accueillante de bourgade (contraste avec les biomes sauvages).
	"sky_top":      Color(0.42, 0.66, 0.95),
	"sky_horizon":  Color(0.82, 0.84, 0.78),
	"fog_color":    Color(0.78, 0.80, 0.74),
	"fog_density":  0.006,
	"sun_color":    Color(1.0, 0.95, 0.84),
	"hill_a":       Color(0.46, 0.58, 0.44),
	"hill_b":       Color(0.40, 0.52, 0.42),
	"cloud_alpha":  0.60,
	"butterflies":  4,
	"ground_tint":  Color(0.44, 0.60, 0.36),
}

const _HOUSE_PALETTE := {
	# Intérieur de MAISON (Village) : lumière chaude de lampe, air clair — sans
	# ça, une maison rendait exactement comme une caverne (froide et brumeuse).
	"sky_top":      Color(0.30, 0.24, 0.20),
	"sky_horizon":  Color(0.42, 0.34, 0.26),
	"ambient_energy": 0.42,
	"fog_color":    Color(0.50, 0.40, 0.30),
	"fog_density":  0.004,
	"fog_scatter":  0.0,
	"glow_intensity": 0.20,
	"sun_color":    Color(1.0, 0.88, 0.68),
	"sun_energy":   0.62,
	"hill_a":       Color(0.34, 0.26, 0.20),
	"hill_b":       Color(0.28, 0.21, 0.16),
	"cloud_alpha":  0.0,
	"mist":         false,
	"ground_tint":  Color(0.52, 0.36, 0.23),
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
	# Densité calibrée pour la caméra HD-2D dézoomée du jeu (CombatArena :
	# hauteur/recul fixes) — dans le viewport 3D de l'ÉDITEUR, la caméra libre
	# est souvent bien plus proche/à un autre angle, ce qui rend ce même
	# brouillard écrasant ("tout embrumé" en régénérant la map). Atténué
	# fortement UNIQUEMENT en preview éditeur ; inchangé en jeu.
	e.fog_density = cfg["fog_density"] * (0.12 if Engine.is_editor_hint() else 1.0)
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
	_build_exit_trails(cfg, center)
	_build_midground(cfg, rng, center)
	if cfg.get("backdrop_mountains", true):
		_build_mountains(cfg, rng, center)
	else:
		_build_distant_forest(cfg, rng, center)
	_build_clouds(cfg, rng, center)
	_build_butterflies(cfg, rng)


## Feuillage/écorce fondus vers la couleur de brouillard du biome, d'un facteur
## `amount` (0 = net, 1 = noyé dans la brume). C'est notre PROFONDEUR DE CHAMP :
## le projet tourne en GL Compatibility (cf. project.godot), où le vrai flou DOF
## n'est pas rendu — comme le SSAO. On simule donc la distance par perspective
## atmosphérique (le lointain se délave et perd son contraste), ce qui est de
## toute façon plus proche du rendu peint HD-2D qu'un flou optique.
##
## `amount` doit rester DISCRET (une valeur par anneau, pas par arbre) :
## KitProps.prepare_mesh met en cache par combinaison (fichier, teintes) — une
## teinte continue créerait un mesh unique par arbre.
func _haze_tints(cfg: Dictionary, amount: float) -> Dictionary:
	var fog: Color = cfg["fog_color"]
	return {
		"leafsGreen": Color(0.22, 0.55, 0.16).lerp(fog, amount),
		"leafsDark":  Color(0.14, 0.40, 0.14).lerp(fog, amount),
		"woodBark":   Color(0.36, 0.30, 0.26).lerp(fog, amount),
	}


## FORÊT LOINTAINE — remplace la chaîne de montagnes pour les biomes qui n'en
## veulent pas (prairie). Anneaux concentriques d'arbres de plus en plus hauts
## et de plus en plus délavés vers la brume : c'est l'étagement des teintes qui
## crée la sensation de distance, pas la taille seule. Ferme l'horizon sur 360°
## — le joueur voit de la forêt partout où il ne peut pas marcher.
func _build_distant_forest(cfg: Dictionary, rng: RandomNumberGenerator, center: Vector3) -> void:
	var base_r := maxf(_map_size.x, _map_size.y) * 0.5
	for layer in 4:
		# Les anneaux se chevauchent (jitter de rayon > pas entre anneaux) :
		# une haie régulière se lirait comme une palissade, pas comme une forêt.
		var dist := base_r + 16.0 + layer * 24.0
		var count := 90 + layer * 30
		var positions: Array[Vector3] = []
		var heights: Array[float] = []
		for i in count:
			var ang := TAU * (float(i) + rng.randf_range(-0.42, 0.42)) / float(count)
			var r := dist + rng.randf_range(-9.0, 9.0)
			positions.append(center + Vector3(cos(ang) * r, 0, sin(ang) * r))
			# Plus loin = plus grand, pour rester visible par-dessus l'anneau
			# précédent (sinon les rangs du fond sont entièrement masqués).
			heights.append((6.5 + layer * 3.2) * rng.randf_range(0.72, 1.35))
		_add_tree_batch(cfg, rng, positions, heights, _haze_tints(cfg, 0.28 + 0.19 * layer))


## Pose un lot d'arbres en MULTIMESH — un seul draw call par (fichier, teinte),
## quel que soit le nombre d'arbres. Indispensable ici : la ceinture + la forêt
## lointaine dépassent le millier d'arbres, et autant de MeshInstance3D
## individuels (l'ancienne approche, ~140 arbres) ne passerait pas à l'échelle.
## C'est ce qui permet la densité demandée (retour joueurs : « plus d'arbres,
## plus proches, plus condensés »).
##
## Effet de bord assumé : build_multimesh applique le shader de vent, calibré
## pour l'herbe (height_ref = 0.22). Sur un arbre, tout ce qui dépasse cette
## hauteur locale oscille en bloc — soit ~3 % de sa hauteur : ça se lit comme
## une brise, pas comme une déformation.
func _add_tree_batch(cfg: Dictionary, rng: RandomNumberGenerator, positions: Array[Vector3],
		heights: Array[float], tints: Dictionary) -> void:
	var pool: Array = KitProps.TREES_PINE if cfg.get("midground_cliffs", false) else KitProps.TREES_ROUND
	var by_file: Dictionary = {}   # fichier -> {"t": Array[Transform3D], "p": Array[float]}
	for i in positions.size():
		var file: String = pool[rng.randi() % pool.size()]
		var native_h: float = KitProps.TREE_NATIVE_HEIGHT.get(file, 1.7)
		var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(
			Vector3.ONE * (heights[i] / native_h))
		if not by_file.has(file):
			by_file[file] = {"t": [], "p": []}
		by_file[file]["t"].append(Transform3D(basis, positions[i]))
		by_file[file]["p"].append(rng.randf_range(0.0, TAU))   # déphasage du vent
	for file: String in by_file:
		_backdrop.add_child(
			KitProps.build_multimesh(file, by_file[file]["t"], by_file[file]["p"], tints))


const _GRASS_TEX_PATH := "res://assets/nature/grass.png"
static var _grass_tex_cache: Texture2D = null
static var _grass_lum: float = -1.0


static func _grass_tex() -> Texture2D:
	if _grass_tex_cache == null:
		_grass_tex_cache = load(_GRASS_TEX_PATH)
	return _grass_tex_cache


## Teinte à passer au shader pour que le tablier SORTE effectivement à la
## couleur `target`.
##
## Le shader de sol (cf. GrassPatch._GROUND_SHADER) ne peint pas `tint` tel
## quel : à tint_strength=1 il calcule `luminance(grass.png) * tint * 1.7`.
## Passer directement la couleur mesurée du sol jouable donnait donc un tablier
## à `lum_moyenne * 1.7` fois cette couleur — proche mais JAMAIS égal, et l'œil
## voit très bien ce résidu d'écart : la dalle rectangulaire ressortait encore
## (retour joueurs : « les deux sols ne sont toujours pas de la même couleur »).
## On divise par le facteur du shader pour annuler exactement sa transformation.
static func _apron_tint(target: Color) -> Color:
	if _grass_lum < 0.0:
		var img := _grass_tex().get_image()
		# grass.png est importée COMPRESSÉE (cf. import_etc2_astc dans
		# project.godot) : sans décompression, get_pixel ne renvoie rien
		# d'exploitable et la moyenne tombait à ~0 — la division donnait alors
		# une teinte énorme, donc un tablier BLANC après clamp du shader.
		if img.is_compressed():
			img.decompress()
		img.resize(16, 16, Image.INTERPOLATE_BILINEAR)
		var sum := 0.0
		for y in 16:
			for x in 16:
				var px: Color = img.get_pixel(x, y)
				sum += 0.299 * px.r + 0.587 * px.g + 0.114 * px.b
		_grass_lum = sum / 256.0
	# Garde-fou : une luminance aberrante (texture illisible) doit dégrader vers
	# "teinte telle quelle" plutôt que vers un tablier blanc.
	if _grass_lum < 0.08:
		push_warning("BiomeAmbiance: luminance de grass.png illisible (%.3f) — tablier non compensé." % _grass_lum)
		return target
	var k := _grass_lum * 1.7
	# Pas de clamp à 1 : le shader clampe déjà l'ALBEDO final, et brider ici
	# rendrait les sols clairs (prairie ≈ 0.75) impossibles à atteindre.
	return Color(target.r / k, target.g / k, target.b / k, 1.0)


## Grand tablier de sol plat sous tout le décor lointain — comble le "vide"
## qu'on voyait entre le bord jouable et l'anneau de collines/arbres (on
## voyait à travers, jusqu'au ciel). Teinté avec la couleur de collines du
## biome (déjà accordée au thème) pour se fondre dans l'horizon.
func _build_ground_apron(cfg: Dictionary, center: Vector3) -> void:
	# Large marge : le bord du tablier ne doit jamais être visible, même à la
	# caméra dézoomée en éditeur — le brouillard (cfg["fog_density"]) fait
	# disparaître le lointain avant qu'on puisse en voir la limite.
	var span := maxf(_map_size.x, _map_size.y) * 16.0
	# Même texture d'herbe/shader que le sol jouable (cf. GrassPatch.
	# ground_material) au lieu d'un aplat de couleur : le tablier lointain
	# se lisait comme du vide/de la terre nue à côté du sol texturé de la
	# map. Recoloré (tint_strength=1) exactement à la couleur d'herbe/sol
	# du biome (`ground_tint`, cf. palettes) — pas un dérivé des couleurs
	# de collines qui pouvait diverger du vert (ou de l'ocre, etc.) réel.
	# Couleur MESURÉE sur le sol baké de la map courante quand elle est
	# disponible (cf. MapGenerator.ground_avg_color) — la constante `ground_tint`
	# de la palette ne suivait pas le sol réel (qui mêle herbe, chemins et
	# décors), et le moindre écart faisait ressortir le contour RECTANGULAIRE de
	# la dalle jouable sur la plaine. Repli sur la palette pour les scènes qui
	# n'exposent pas la propriété (maps legacy).
	var plain: Color = cfg.get("ground_tint", (cfg["hill_a"] as Color).lerp(cfg["hill_b"], 0.4))
	if _terrain != null and "ground_avg_color" in _terrain:
		plain = _terrain.ground_avg_color
	var mat := GrassPatch.ground_material(
		_grass_tex(), 1.45, 0.88, span, _apron_tint(plain), 1.0)

	# ANNEAU de 4 quads qui ENTOURE la dalle, au lieu d'un unique plan géant
	# glissé DESSOUS à y=-1.2. Ce plan créait une marche de 1,2 u tout autour du
	# rectangle jouable (le champ de hauteur verrouille à plat, y=0, toutes les
	# cases occupées — donc TOUT le pourtour de la map est exactement à 0), et
	# les arbres de la ceinture, posés à y=0, FLOTTAIENT au-dessus de lui.
	# En anneau, on peut affleurer le bord (y=-0.02) sans jamais recouvrir les
	# creux du relief intérieur (qui descendent à -0.55) : c'était la raison
	# d'être du -1.2, et elle disparaît puisqu'on ne passe plus sous la dalle.
	var hx := _map_size.x * 0.5
	var hz := _map_size.y * 0.5
	var s := span * 0.5
	for band: Dictionary in [
		{"size": Vector2(2.0 * s, s - hz), "at": Vector2(0.0, -(s + hz) * 0.5)},   # nord
		{"size": Vector2(2.0 * s, s - hz), "at": Vector2(0.0,  (s + hz) * 0.5)},   # sud
		{"size": Vector2(s - hx, 2.0 * hz), "at": Vector2(-(s + hx) * 0.5, 0.0)},  # ouest
		{"size": Vector2(s - hx, 2.0 * hz), "at": Vector2( (s + hx) * 0.5, 0.0)},  # est
	]:
		var band_size: Vector2 = band["size"]
		var at: Vector2 = band["at"]
		var quad := MeshInstance3D.new()
		quad.name = "GroundApron"
		var plane := PlaneMesh.new()
		plane.size = band_size
		quad.mesh = plane
		# -0.06 : sous le sentier de sortie (-0.03), lui-même sous la dalle (0).
		# Cf. _build_exit_trails pour l'étagement des trois plans de sol.
		quad.position = Vector3(center.x + at.x, -0.06, center.z + at.y)
		quad.material_override = mat
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_backdrop.add_child(quad)
	# NB : plus de "bosses de relief" (sphères) sur la plaine. Elles étaient là
	# pour meubler un tablier trop plat, mais lisaient comme de grosses boules
	# vertes posées dans l'herbe (retour joueurs). C'est la CEINTURE D'ARBRES
	# dense (cf. _build_midground) qui remplit désormais ce rôle — un décor
	# lisible plutôt qu'une géométrie abstraite.


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


## SENTIER DE TERRE prolongé au-delà de chaque portail, dans la trouée ouverte
## par _in_portal_gap. Le chemin carvé s'arrêtait NET au bord de la map : on
## voyait une allée qui butait sur de l'herbe, ce qui ne disait pas « la suite
## est par là » (retour joueurs). Il file maintenant vers le lointain et se perd
## dans le brouillard.
##
## Teinté avec la couleur MESURÉE du chemin jouable (cf.
## MapRender3D._path_average_color) et compensé comme le tablier : il doit se
## lire comme le PROLONGEMENT du chemin, donc aucun écart de teinte n'est
## admissible.
const TRAIL_WIDTH := 4.2
const TRAIL_LEN   := 26.0

func _build_exit_trails(cfg: Dictionary, center: Vector3) -> void:
	if _terrain == null or not ("path_avg_color" in _terrain):
		return
	var trail_col: Color = _terrain.path_avg_color
	var mat := GrassPatch.ground_material(
		_grass_tex(), 1.45, 0.88, TRAIL_LEN, _apron_tint(trail_col), 1.0)
	for g: Vector3 in _portal_gaps():
		# Direction SORTANTE : les portails sont sur les bords nord/sud (cf.
		# _in_portal_gap), donc le sentier file vers l'extérieur en Z.
		var dir := -1.0 if g.z < center.z else 1.0
		var strip := MeshInstance3D.new()
		strip.name = "ExitTrail"
		var plane := PlaneMesh.new()
		plane.size = Vector2(TRAIL_WIDTH, TRAIL_LEN)
		strip.mesh = plane
		# Chevauche légèrement la map (départ 1 u AVANT le bord) pour qu'aucun
		# liseré d'herbe ne s'intercale entre le chemin carvé et son prolongement.
		# Étagement des 3 plans de sol : dalle jouable à 0, sentier à -0.03,
		# tablier à -0.06. Assez serré pour rester invisible à l'œil, assez
		# écarté pour ne pas z-fighter.
		strip.position = Vector3(g.x, -0.03, g.z + dir * (TRAIL_LEN * 0.5 - 1.0))
		strip.material_override = mat
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_backdrop.add_child(strip)


## Positions monde des portails (entrée + 3 sorties) de la map courante.
## La ceinture d'arbres doit S'ÉCARTER devant eux : sinon elle referme un mur
## opaque juste derrière chaque porte, et l'arche de sortie se noie dedans — on
## ne comprend plus que c'est par là qu'on continue (retour joueurs : « c'est
## dur de voir que c'est une allée pour aller à la suite »). Le trou perce une
## trouée dans la forêt, qui prolonge visuellement le chemin.
func _portal_gaps() -> Array[Vector3]:
	var out: Array[Vector3] = []
	if _terrain == null or not _terrain.has_method("cell_to_world3"):
		return out
	for prop: String in ["entry_tile", "exit_A", "exit_B", "exit_C"]:
		if prop in _terrain:
			out.append(_terrain.cell_to_world3(_terrain.get(prop)))
	return out


## Demi-largeur et profondeur (unités monde) de la trouée devant un portail.
## C'est un COULOIR, pas un disque : il doit traverser les 5 rangs de la
## ceinture (le plus lointain est à ~11 u du bord) pour qu'on voie la forêt
## s'ouvrir et le chemin filer au loin. Un disque assez large pour ça aurait
## rasé tout le côté nord d'un coup — les 3 sorties y sont alignées.
const PORTAL_GAP_HALF_W := 4.0
const PORTAL_GAP_DEPTH  := 14.0

## Suppose que les portails sont sur les bords NORD/SUD (cf.
## MapGenerator._compute_portals : entrée en bas-centre, sorties sur la rangée
## 0) — d'où un couloir étiré sur Z. À revoir si des sorties latérales arrivent.
func _in_portal_gap(gaps: Array[Vector3], pos: Vector3) -> bool:
	for g: Vector3 in gaps:
		var dx := (pos.x - g.x) / PORTAL_GAP_HALF_W
		var dz := (pos.z - g.z) / PORTAL_GAP_DEPTH
		if dx * dx + dz * dz < 1.0:
			return true
	return false


## Point du périmètre d'un rectangle centré (demi-extents `hx`/`hz`), paramétré
## par `t` ∈ [0,1) : 0 = coin haut-gauche, puis sens horaire. Sert à poser un
## décor qui LONGE la dalle jouable au lieu de la cercler.
func _rect_perimeter_point(center: Vector3, hx: float, hz: float, t: float) -> Vector3:
	var w := 2.0 * hx
	var h := 2.0 * hz
	var p := t * 2.0 * (w + h)
	var x := 0.0
	var z := 0.0
	if p < w:                 # bord nord, vers l'est
		x = -hx + p;            z = -hz
	elif p < w + h:           # bord est, vers le sud
		x = hx;                 z = -hz + (p - w)
	elif p < 2.0 * w + h:     # bord sud, vers l'ouest
		x = hx - (p - w - h);   z = hz
	else:                     # bord ouest, vers le nord
		x = -hx;                z = hz - (p - 2.0 * w - h)
	return center + Vector3(x, 0, z)


## Second plan tout autour de la map, juste au-delà des murs de bordure —
## mélange d'arbres (silhouette hazy) et de falaises étagées selon le thème,
## pour qu'on ne voie jamais le vide entre le bord jouable et les collines
## lointaines.
func _build_midground(cfg: Dictionary, rng: RandomNumberGenerator, center: Vector3) -> void:
	# Proportion de falaises étagées vs arbres — le rocailleux est surtout
	# fait de falaises, les thèmes végétaux surtout d'arbres.
	# 0 hors biomes rocheux : la lisière d'une PRAIRIE ne contient aucune
	# falaise. L'ancien 0.12 en semait quand même une sur huit un peu partout
	# (retour joueurs : « dans la prairie tu peux enlever les falaises »).
	var cliff_ratio := 0.75 if cfg.get("midground_cliffs", false) else 0.0
	var base_r := maxf(_map_size.x, _map_size.y) * 0.5
	# CEINTURE DENSE qui épouse le RECTANGLE de la dalle jouable, et non plus un
	# cercle de rayon max(W,H)/2 : sur une map large (ex. 56×35), ce cercle
	# collait au bord sur l'axe long mais laissait ~10 unités de plaine NUE sur
	# l'axe court — le bord rectangulaire de la dalle restait donc à découvert
	# sur deux côtés, et c'est précisément lui qu'on lisait comme « la zone est
	# un rectangle » (retour joueurs). En suivant le périmètre, les arbres
	# masquent la jointure dalle/plaine sur les quatre côtés.
	var gaps := _portal_gaps()
	for ring in 5:
		var inflate := 1.0 + ring * 2.6
		var hx := _map_size.x * 0.5 + inflate
		var hz := _map_size.y * 0.5 + inflate
		# Espacement serré (~1.7 u) : c'est la DENSITÉ qui rend la lisière
		# opaque — un anneau clairsemé laisse voir la plaine au travers.
		var n := int(4.0 * (hx + hz) / 1.7)
		var positions: Array[Vector3] = []
		var heights: Array[float] = []
		for i in n:
			var t := (float(i) + rng.randf_range(-0.35, 0.35)) / float(n)
			var pos := _rect_perimeter_point(center, hx, hz, fposmod(t, 1.0))
			pos += Vector3(rng.randf_range(-1.3, 1.3), 0, rng.randf_range(-1.3, 1.3))
			# Trouée devant les portails : la forêt doit s'ouvrir là où le chemin
			# sort, sinon l'arche est plaquée contre un mur d'arbres opaque.
			if _in_portal_gap(gaps, pos):
				continue
			if ring == 1 and rng.randf() < cliff_ratio:
				_add_cliff_tier(cfg, rng, pos, atan2(pos.z - center.z, pos.x - center.x))
				continue
			positions.append(pos)
			# L'anneau collé au bord reste BAS (sous-bois/lisière) ; les grands
			# arbres commencent au rang suivant, sinon ils masquent la map.
			heights.append(rng.randf_range(2.2, 4.2) if ring == 0 \
				else rng.randf_range(3.5, 7.0))
		# Estompage progressif dès la lisière (0 → 0.24), qui enchaîne avec
		# _build_distant_forest (reprend à 0.28). Le rang 0 partage la teinte
		# exacte des arbres de la map (cf. MapRender3D._kit_tree_config) : la
		# jointure dalle/plaine doit être invisible, donc pas de rupture de
		# feuillage non plus.
		_add_tree_batch(cfg, rng, positions, heights, _haze_tints(cfg, ring * 0.06))

	# ROCKY : contreforts bas entre la lisière et les vrais pics lointains
	# (cf. _build_mountains) — comble le "vide" entre le sol jouable et la
	# chaîne, sans toucher aux distances des pics (déjà calées pour éviter
	# qu'une montagne ne traverse la caméra, cf. commentaire plus bas).
	if cfg.get("midground_cliffs", false):
		var ground_tint: Color = cfg.get("ground_tint", cfg["hill_b"])
		var foot_col: Color = (ground_tint as Color).darkened(0.15)
		var fn := 26
		for i in fn:
			var ang := (TAU / float(fn)) * i + rng.randf_range(-0.1, 0.1)
			var r := base_r + rng.randf_range(9.0, 20.0)
			var pos := center + Vector3(cos(ang) * r, 0, sin(ang) * r)
			var foot := MeshInstance3D.new()
			var mesh := SphereMesh.new()
			mesh.radius = rng.randf_range(3.0, 6.0)
			mesh.height = mesh.radius * 1.3
			mesh.radial_segments = 8
			mesh.rings = 5
			foot.mesh = mesh
			foot.position = pos + Vector3(0, -mesh.radius * 0.5, 0)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = foot_col.lerp(Color(0.55, 0.52, 0.48), rng.randf_range(0.0, 0.3))
			mat.roughness = 1.0
			foot.material_override = mat
			_backdrop.add_child(foot)
			_disable_shadows(foot)


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
