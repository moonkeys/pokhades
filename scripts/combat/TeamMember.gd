extends CharacterBody3D

## Membre d'équipe en combat — HD-2D (phase 2) : CharacterBody3D + sprite PMD
## billboardé via Billboard3D, comme HubPlayer. La logique (IA compagnon,
## attaques, XP, évolution) est inchangée ; seules les coordonnées passent en
## 3D (plan XZ, 1 unité monde = 1 ancienne tuile de 16 px — toutes les
## distances/vitesses ci-dessous sont les valeurs 2D divisées par 16).

const SPEED           := 9.4
const ATTACK_RANGE    := 4.0   # secours : Pokémon sans move équipé
const ATTACK_COOLDOWN := 1.0   # idem — aligné sur les cadences rallongées

# ── Cadence & portée par ATTAQUE ──────────────────────────────────────
# Chaque move a sa portée / portée mini / cadence (cf. MoveData.tune()).
# Deux verrous distincts empêchent le spam :
#   _move_cd[i]  : cadence PROPRE à chaque capacité (elles rechargent en
#                  parallèle) — une grosse frappe reste indisponible longtemps ;
#   _global_lock : court verrou APRÈS n'importe quelle attaque — sans lui on
#                  pourrait enchaîner les 4 capacités d'un coup (retour joueurs).
const GLOBAL_LOCK := 0.5   # rallongé avec les cadences (cf. MoveData.tune)

var _move_cd:     PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _move_cd_max: PackedFloat32Array = PackedFloat32Array([1.0, 1.0, 1.0, 1.0])
var _global_lock: float = 0.0
const DISPLAY_UNITS   := 1.75   # largeur monde cible du sprite (28 px / 16)
const FOOT_LIFT        := 0.05

# Dash — esquive rapide dans la direction de déplacement (membre contrôlé)
const DASH_SPEED    := 26.0
const DASH_TIME     := 0.16
const DASH_RECHARGE := 2.5   # secondes pour regagner une charge

# IA compagnon
const AI_SPEED        := 7.5
const AI_SEEK_RADIUS  := 18.75  # cherche un ennemi dans ce rayon
const AI_FOLLOW_DIST  := 5.6    # se rapproche du leader si plus loin que ça
const REPATH_INTERVAL := 0.4

var pokemon_instance: PokemonInstance
var team_index: int  = 0
var is_active:  bool = false
var _leader: Node3D = null        # membre actif à suivre (compagnons seulement)

# ── Modificateurs de run (bonus de fin de zone, cf. CombatArena._apply_bonus) ──
# Base du Dash = charges ACHETÉES au hub (0 au départ, jusqu'à 3) ; le bonus
# de run "dash_plus" peut encore en ajouter temporairement.
var dash_max_charges: int   = GameManager.dash_charges_bought
var cooldown_mult:    float = 1.0   # ×0.85 par bonus "atk_rate"
var xp_mult:          float = 1.0   # ×1.25 par bonus "xp_up"

var _dash_charges:  int   = GameManager.dash_charges_bought
var _dash_recharge: float = 0.0
var _dash_timer:    float = 0.0
var _dash_dir:      Vector3 = Vector3.ZERO

## Verrou d'animation d'action (attaque/dégâts PMD) — tant qu'il court,
## _update_anim ne reprend pas la main sur l'animation en cours.
var _action_lock: float = 0.0

var _attack_timer:       float = 0.0
var _attack_flash:       float = 0.0
var _current_anim:       String = "idle"
var _has_directional:    bool = false
var _evolving:           bool = false
var _selected_move_idx:  int  = 0   # capacité active (touches 1-4)
var _sprite_base_pos:    Vector3 = Vector3.ZERO   # position du sprite après ancrage des pieds

# Pathfinding (contournement d'obstacles, mode compagnon)
var _map:               MapBase = null
var _path_repath_timer: float   = 0.0
var _path_waypoint:     Vector3 = Vector3.ZERO

var _range_ring: MeshInstance3D       = null
var _min_ring:     MeshInstance3D       = null   # portée MINI (rouge), si le move en a une
var _min_ring_mat: StandardMaterial3D   = null
var _ring_mat:   StandardMaterial3D   = null

signal hp_changed(ratio: float)
## `ready` = _move_ready() de la capacité concernée : PAS que la cadence
## (ratio) est écoulée, mais aussi qu'aucun verrou (anim en cours, statut) ne
## bloque l'enchaînement. Le seul ratio ne suffisait pas à distinguer "en
## recharge" de "verrouillé" — retour joueurs : « le cooldown n'est pas
## toujours visible », d'où l'indicateur dédié (cf. HUD.update_cooldown).
signal cooldown_changed(ratio: float, ready: bool)
signal xp_changed(ratio: float, level: int)
signal leveled_up(level: int)
signal evolved(name_fr: String)
signal portrait_ready(idx: int, texture: Texture2D)
signal move_selected(idx: int)
signal dash_changed(charges: int, max_charges: int)
signal died

@onready var sprite: AnimatedSprite3D = $AnimatedSprite3D


## ── Multijoueur ───────────────────────────────────────────────────────
## remote_peer != 0 → ce membre est la copie locale du Pokémon d'un AUTRE
## joueur : pas d'input ni d'IA, il rejoue l'état diffusé par son
## propriétaire (position/anim à NET_SEND_HZ, PV en fiable).
const NET_SEND_HZ := 15.0
var remote_peer:  int     = 0
var _net_target:  Vector3 = Vector3.ZERO
var _net_anim:    String  = "idle"
var _net_flip:    bool    = false
var _net_accum:   float   = 0.0


func setup(instance: PokemonInstance, idx: int, active: bool) -> void:
	add_to_group("players")
	pokemon_instance = instance
	team_index = idx
	is_active  = active
	Billboard3D.setup_sprite(sprite)
	_add_shadow()
	_build_range_ring()
	var col := Color(1.0, 0.55, 0.0) if active else Color(0.35, 0.55, 1.0)
	_add_placeholder(col)
	PMDSprites.get_walk_sprites(instance.data.id, self, _on_pmd_loaded)
	_map = get_tree().get_first_node_in_group("combat_map") as MapBase
	_net_target = global_position
	if active:
		_register_move_keys()


func _remote_process(delta: float) -> void:
	var to := _net_target - global_position
	global_position = global_position.lerp(_net_target, minf(1.0, delta * 12.0))
	if sprite.sprite_frames != null:
		var anim := _net_anim if to.length() > 0.06 else "idle"
		if anim != _current_anim and sprite.sprite_frames.has_animation(anim):
			_current_anim = anim
			sprite.play(anim)
		if not _has_directional:
			sprite.flip_h = _net_flip


## État de mouvement diffusé par le propriétaire — appliqué sur ses copies.
@rpc("any_peer", "call_remote", "unreliable")
func _net_state(pos: Vector3, anim: String, flip: bool) -> void:
	_net_target = pos
	_net_anim   = anim
	_net_flip   = flip


## PV diffusés par le propriétaire (source de vérité de SON Pokémon) — met
## à jour la copie locale + le HUD (via hp_changed) + détection de mort.
@rpc("any_peer", "call_remote", "reliable")
func _net_hp(hp: int, max_hp_v: int) -> void:
	pokemon_instance.max_hp     = max_hp_v
	pokemon_instance.current_hp = hp
	hp_changed.emit(pokemon_instance.hp_ratio())
	if hp <= 0:
		_play_faint_anim()


## Dégâts calculés par l'hôte (les ennemis ne vivent que chez lui) et
## relayés au propriétaire du Pokémon touché — qui les applique pour de
## vrai puis rediffuse ses PV à tout le monde.
@rpc("any_peer", "call_remote", "reliable")
func _net_take_damage(amount: int, source_pos: Vector3) -> void:
	if remote_peer != 0:
		return   # seul le propriétaire applique
	take_damage(amount, source_pos)


## Diffuse nos PV après tout changement local (dégâts, soin, level up).
func net_broadcast_hp() -> void:
	if Net.in_run and remote_peer == 0:
		_net_hp.rpc(pokemon_instance.current_hp, pokemon_instance.max_hp)


## Niveau/XP/espèce diffusés par le propriétaire à chaque gain d'XP — sans
## ça, les copies des AUTRES joueurs restaient bloquées à leur niveau et
## sprite de départ pour tout le monde sauf leur propriétaire (retour
## joueurs : "le sprite et le niveau de l'allié ne se mettent pas à jour").
@rpc("any_peer", "call_remote", "reliable")
func _net_progress(level: int, xp_r: float, species_id: int) -> void:
	if remote_peer == 0:
		return
	if species_id != pokemon_instance.data.id:
		_remote_evolve_to(species_id)
	pokemon_instance.level = level
	xp_changed.emit(xp_r, level)
	leveled_up.emit(level)


## Applique une évolution reçue de l'hôte/propriétaire sur une copie
## distante — recharge les VRAIES données + le sprite (comme
## _start_evolution, mais sans l'animation de flash : ce n'est pas NOTRE
## Pokémon qui évolue sous nos yeux, juste une mise à jour d'état).
func _remote_evolve_to(new_id: int) -> void:
	PokemonAPI.get_pokemon(new_id, func(api_data: Dictionary) -> void:
		if not is_instance_valid(self) or api_data.is_empty():
			return
		var new_data := PokemonData.from_api(api_data)
		pokemon_instance.evolve_to(new_data)
		hp_changed.emit(pokemon_instance.hp_ratio())
		PMDSprites.get_walk_sprites(new_id, self, func(result: Dictionary) -> void:
			if not is_instance_valid(self) or result.is_empty():
				return
			_has_directional = true
			sprite.sprite_frames = result.frames
			_apply_sprite_scale(result)
			if result.frames.has_animation("walk_down") and result.frames.get_frame_count("walk_down") > 0:
				portrait_ready.emit(team_index, result.frames.get_frame_texture("walk_down", 0))
			evolved.emit(new_data.name_fr)
		)
	)


## Diffuse notre progression (niveau/XP/espèce) après tout gain d'XP —
## suit le même garde-fou que net_broadcast_hp (seul le propriétaire émet).
func net_broadcast_progress() -> void:
	if Net.in_run and remote_peer == 0:
		_net_progress.rpc(pokemon_instance.level, pokemon_instance.xp_ratio(), pokemon_instance.data.id)


func _add_shadow() -> void:
	add_child(Billboard3D.make_blob_shadow(Vector2(1.25, 0.7)))


## Anneau de portée d'attaque au sol — remplace l'ancien _draw() 2D. Visible
## seulement pour le membre contrôlé, pulse brièvement à chaque attaque.
## Anneaux au sol de la capacité SÉLECTIONNÉE : un anneau doré = sa portée
## MAX, un anneau rouge (seulement si le move en a une) = sa portée MINI, en
## deçà de laquelle l'attaque ne part pas. Les tores sont construits au rayon
## 1.0 puis MIS À L'ÉCHELLE — le rayon change à chaque changement de capacité.
func _build_range_ring() -> void:
	_range_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.985
	torus.outer_radius = 1.015
	_range_ring.mesh = torus
	_range_ring.position.y = 0.03
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.albedo_color   = Color(1.0, 0.85, 0.0, 0.18)
	_ring_mat.transparency    = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	_range_ring.material_override = _ring_mat
	_range_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_range_ring)

	_min_ring = MeshInstance3D.new()
	var torus2 := TorusMesh.new()
	torus2.inner_radius = 0.975
	torus2.outer_radius = 1.025
	_min_ring.mesh = torus2
	_min_ring.position.y = 0.035
	_min_ring_mat = StandardMaterial3D.new()
	_min_ring_mat.albedo_color  = Color(1.0, 0.25, 0.20, 0.30)
	_min_ring_mat.transparency   = BaseMaterial3D.TRANSPARENCY_ALPHA
	_min_ring_mat.shading_mode   = BaseMaterial3D.SHADING_MODE_UNSHADED
	_min_ring.material_override = _min_ring_mat
	_min_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_min_ring.visible = false
	add_child(_min_ring)


## Les touches (capacités 1-4, dash…) sont déclarées UNE seule fois dans
## Controls.CATALOG et appliquées au démarrage par GameManager — plus de
## déclaration locale (c'est ce qui avait causé le conflit Tab).
func _register_move_keys() -> void:
	Controls.apply()


func _add_placeholder(color: Color) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.9, 0.9, 0.2)
	mi.mesh = box
	mi.position = Vector3(0, 0.45, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	mi.name = "Placeholder"
	add_child(mi)


func _on_pmd_loaded(result: Dictionary) -> void:
	if result.is_empty():
		_load_fallback_sprite(pokemon_instance.data.sprite_url)
		return
	_has_directional = true
	sprite.sprite_frames = result.frames
	_apply_sprite_scale(result)
	sprite.play("idle")
	_remove_placeholder()
	if result.frames.has_animation("walk_down") and result.frames.get_frame_count("walk_down") > 0:
		portrait_ready.emit(team_index, result.frames.get_frame_texture("walk_down", 0))


## Dimensionne le sprite pour occuper DISPLAY_UNITS de large (équivalent du
## scale 2D DISPLAY_SIZE/frame_w) et ancre les pieds au sol.
func _apply_sprite_scale(result: Dictionary) -> void:
	var frame_size: Vector2i = result.get("frame_size", Vector2i(32, 40))
	var ps := DISPLAY_UNITS / float(maxi(frame_size.x, 1))
	sprite.pixel_size = ps
	Billboard3D.align_feet(sprite, result, FOOT_LIFT, ps)
	_sprite_base_pos = sprite.position


func _load_fallback_sprite(url: String) -> void:
	if url.is_empty():
		_remove_placeholder()
		return
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(result, code, _h, body):
		if result == OK and code == 200:
			var img := Image.new()
			if img.load_png_from_buffer(body) == OK:
				var tex := ImageTexture.create_from_image(img)
				var frames := SpriteFrames.new()
				for anim in ["idle", "walk_down", "walk_up", "walk_left", "walk_right",
						"walk_downright", "walk_upright", "walk_upleft", "walk_downleft"]:
					frames.add_animation(anim)
					frames.set_animation_loop(anim, true)
					frames.add_frame(anim, tex)
				sprite.sprite_frames = frames
				var ps := DISPLAY_UNITS / float(maxi(maxi(img.get_width(), img.get_height()), 1))
				sprite.pixel_size = ps
				sprite.position.y = img.get_height() * ps * 0.5   # sprite centré → pieds ~au sol
				_sprite_base_pos = sprite.position
				sprite.play("idle")
				_remove_placeholder()
				portrait_ready.emit(team_index, tex)
		http.queue_free()
	)
	http.request(url)


func _remove_placeholder() -> void:
	var ph := get_node_or_null("Placeholder")
	if ph:
		ph.queue_free()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(pokemon_instance) or pokemon_instance.is_fainted():
		return

	# Copie d'un joueur distant (multijoueur) : pas d'IA ni de statut local —
	# on suit simplement l'état diffusé par son propriétaire.
	if remote_peer != 0:
		_remote_process(delta)
		return

	# Capturé par un dresseur (village) : figé, PV qui baissent ; le membre
	# ACTIF s'échappe en martelant ← → (les alliés IA ne peuvent pas seuls —
	# il faut passer sur eux pour les libérer). Prioritaire sur tout le reste.
	if captured:
		_capture_process(delta)
		return

	_attack_timer = max(0.0, _attack_timer - delta)
	_attack_flash = max(0.0, _attack_flash - delta * 4.0)
	_action_lock  = max(0.0, _action_lock - delta)
	_global_lock  = max(0.0, _global_lock - delta)
	for i in _move_cd.size():
		_move_cd[i] = max(0.0, _move_cd[i] - delta)
	_update_range_ring()
	_update_grass_hiding(delta)
	_update_puddle_steps(delta)

	# Diffusion de notre état aux autres joueurs (membre contrôlé localement)
	if is_active and Net.in_run:
		_net_accum += delta
		if _net_accum >= 1.0 / NET_SEND_HZ:
			_net_accum = 0.0
			_net_state.rpc(global_position, _current_anim, sprite.flip_h)

	# Recharge des dashs (chaque membre garde ses charges, actif ou non)
	if _dash_charges < dash_max_charges:
		_dash_recharge += delta
		if _dash_recharge >= DASH_RECHARGE:
			_dash_recharge = 0.0
			_dash_charges += 1
			dash_changed.emit(_dash_charges, dash_max_charges)
	if _dash_timer > 0.0:
		_dash_timer -= delta

	# Altération de statut : dégâts sur la durée + blocage (sommeil/gel)
	if _tick_status(delta):
		return   # bloqué cette frame — pas d'action

	if is_active:
		_player_process()
		# La jauge du HUD suit la capacité SÉLECTIONNÉE (chacune a sa cadence).
		var i := clampi(_selected_move_idx, 0, _move_cd.size() - 1)
		cooldown_changed.emit(cooldown_ratio(i), _move_ready(i))
	else:
		_companion_process(delta)


# ── Portée / cadence de la capacité sélectionnée ──────────────────────

## Move équipé à l'index `idx`, ou null (Pokémon sans capacité → attaque de base).
func _move_at(idx: int) -> MoveData:
	var moves: Array = pokemon_instance.equipped_moves
	if idx < 0 or idx >= moves.size():
		return null
	return moves[idx]


## `range_mult` (bonus de fin de zone « Portée des attaques ») n'étend QUE la
## portée maximale — l'appliquer aussi à range_min repousserait le seuil de
## trop-près, ce qui pénaliserait les grosses attaques spéciales au lieu de
## les aider.
func _move_range_max(idx: int) -> float:
	var m := _move_at(idx)
	var base: float = m.range_max if m != null else ATTACK_RANGE
	return base * pokemon_instance.range_mult


func _move_range_min(idx: int) -> float:
	var m := _move_at(idx)
	return m.range_min if m != null else 0.0


## Cadence effective : celle du move, réduite par la VITESSE du Pokémon (une
## bête rapide enchaîne plus vite) et par les bonus d'objets (cooldown_mult).
## Vitesse 60 = neutre ; 140 → ×0.73 ; 20 → ×1.13.
func _move_cooldown(idx: int) -> float:
	var m := _move_at(idx)
	var base: float = m.cooldown if m != null else ATTACK_COOLDOWN
	var spd := float(pokemon_instance.get_effective_speed())
	var spd_scale := clampf(1.0 - (spd - 60.0) / 300.0, 0.6, 1.3)
	return base * spd_scale * cooldown_mult


## Ratio de recharge de la capacité `idx` (1.0 = cadence entièrement écoulée).
## Public : CombatArena s'en sert pour rafraîchir IMMÉDIATEMENT le HUD au
## changement de capacité sélectionnée/de membre actif, sans attendre le
## prochain _physics_process (retour joueurs : « le cooldown visuel se fige
## si on change de focus dans le menu d'attaque »).
func cooldown_ratio(idx: int) -> float:
	if idx < 0 or idx >= _move_cd.size():
		return 1.0
	return 1.0 - (_move_cd[idx] / maxf(_move_cd_max[idx], 0.01))


func active_cooldown_ratio() -> float:
	return cooldown_ratio(clampi(_selected_move_idx, 0, _move_cd.size() - 1))


func active_move_ready() -> bool:
	return _move_ready(clampi(_selected_move_idx, 0, _move_cd.size() - 1))


## Enveloppe publique de _move_ready(), pour un slot arbitraire (cf.
## CombatArena._connect_move_signal, qui rafraîchit le HUD au changement de
## capacité SÉLECTIONNÉE, pas seulement celle actuellement active).
func move_ready(idx: int) -> bool:
	return _move_ready(idx)


## La capacité `idx` est-elle lançable MAINTENANT ? (verrou global + sa propre
## cadence). La portée mini est vérifiée séparément, à la cible.
func _move_ready(idx: int) -> bool:
	# _action_lock : le sprite est ENCORE dans son anim d'attaque/dégâts — la
	# capacité suivante attend qu'il ait fini son geste (retour joueurs : « on
	# peut faire plusieurs attaques en même temps »).
	if _evolving or _global_lock > 0.0 or _action_lock > 0.0:
		return false
	if idx < 0 or idx >= _move_cd.size():
		return false
	return _move_cd[idx] <= 0.0


## Portée mini : une grosse frappe à distance ne part pas si l'ennemi le plus
## proche est collé à nous (il faut prendre du recul).
func _min_range_ok(idx: int) -> bool:
	var rmin := _move_range_min(idx)
	if rmin <= 0.0:
		return true
	var near := _nearest_enemy(rmin)
	return not is_instance_valid(near)


var _status_icon: Label3D = null
var _status_shown: String = ""

# ── Capture (dresseurs de village) ────────────────────────────────────
signal capture_changed(capturing: bool, escape: float, active: bool)
signal capture_began   # émis UNE fois au début (la notif ne doit sortir qu'une fois)

var captured: bool = false
var _cap_escape: float = 0.0        # 0..1 — barre d'évasion
var _cap_last_dir: int = 0          # dernière flèche (alternance ← →)
var _cap_dmg_accum: float = 0.0
var _cap_ball: Node3D = null
const CAP_DRAIN_PER_SEC := 0.06     # fraction PV max drainée / s
const CAP_ESCAPE_GAIN   := 0.13     # gain par alternance de flèche
const CAP_ESCAPE_DECAY  := 0.22     # décroissance / s si on n'appuie pas


## Un dresseur nous a touché avec une pokéball → capture.
func begin_capture() -> void:
	if captured or _evolving or pokemon_instance == null or pokemon_instance.is_fainted():
		return
	captured = true
	_cap_escape = 0.0
	_cap_last_dir = 0
	_cap_dmg_accum = 0.0
	_spawn_capture_ball()
	capture_began.emit()
	capture_changed.emit(true, 0.0, is_active)


func _end_capture() -> void:
	captured = false
	if is_instance_valid(_cap_ball):
		# La ball s'ouvre : burst d'éclat + particules, comme un envoi.
		PokeballFX.play_burst(get_parent(), global_position + Vector3(0, 0.9, 0))
		_cap_ball.queue_free()
		_cap_ball = null
	# Le Pokémon ressort de la ball.
	sprite.scale    = Vector3.ONE
	sprite.modulate = Color.WHITE
	capture_changed.emit(false, 0.0, is_active)


func _capture_process(delta: float) -> void:
	# La pokéball TREMBLE tant que le Pokémon est dedans (bascule gauche/droite
	# + petit sursaut), comme une capture en cours.
	if is_instance_valid(_cap_ball):
		var t := float(Time.get_ticks_msec()) * 0.006
		_cap_ball.rotation_degrees.z = sin(t) * 20.0
		_cap_ball.position.x = sin(t * 1.3) * 0.07
		_cap_ball.position.y = 0.9 + absf(sin(t * 2.0)) * 0.05

	# Drain de PV.
	_cap_dmg_accum += float(pokemon_instance.max_hp) * CAP_DRAIN_PER_SEC * delta
	if _cap_dmg_accum >= 1.0:
		var d := int(_cap_dmg_accum)
		_cap_dmg_accum -= float(d)
		pokemon_instance.current_hp = maxi(0, pokemon_instance.current_hp - d)
		hp_changed.emit(pokemon_instance.hp_ratio())
		net_broadcast_hp()   # les alliés voient les PV baisser en multijoueur
		if pokemon_instance.is_fainted():
			_end_capture()
			_play_faint_anim()
			return

	# Évasion : seul le membre ACTIF peut marteler ← → (alliés IA = piégés).
	_cap_escape = maxf(0.0, _cap_escape - CAP_ESCAPE_DECAY * delta)
	if is_active:
		var dir := 0
		if Input.is_action_just_pressed("ui_left"):
			dir = -1
		elif Input.is_action_just_pressed("ui_right"):
			dir = 1
		if dir != 0 and dir != _cap_last_dir:
			_cap_last_dir = dir
			_cap_escape = minf(1.0, _cap_escape + CAP_ESCAPE_GAIN)
		if _cap_escape >= 1.0:
			_end_capture()
			sprite.modulate = Color(2.2, 2.2, 2.2)
			get_tree().create_timer(0.15).timeout.connect(func() -> void:
				if is_instance_valid(self): sprite.modulate = Color.WHITE)
			return
	capture_changed.emit(true, _cap_escape, is_active)


## Vraie séquence de CAPTURE (planches Essentials) : le Pokémon est ASPIRÉ
## dans la pokéball (il rétrécit et s'efface), la ball se referme et TREMBLE
## tant qu'il est dedans (cf. _capture_process). L'évasion la fait éclater
## (burst dans _end_capture). Remplace l'ancienne bulle rouge translucide.
func _spawn_capture_ball() -> void:
	# Aspiration : le sprite rétrécit vers le point de la ball puis s'efface.
	var tw := sprite.create_tween().set_parallel(true)
	tw.tween_property(sprite, "scale", Vector3.ONE * 0.15, 0.20).set_ease(Tween.EASE_IN)
	tw.tween_property(sprite, "modulate:a", 0.0, 0.20)

	var ball := Sprite3D.new()
	ball.texture        = load(PokeballFX.TEX_BALL)
	ball.hframes        = 8
	ball.frame          = 0
	ball.billboard      = BaseMaterial3D.BILLBOARD_ENABLED
	ball.pixel_size     = 0.032
	ball.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	ball.no_depth_test  = true
	ball.shaded         = false
	ball.position       = Vector3(0, 0.9, 0)
	add_child(ball)
	_cap_ball = ball
	Sfx.play_file(PokeballFX.SE_DROP, -4.0)

## Applique le statut courant : dégâts périodiques, gestion du logo flottant.
## Retourne true si le Pokémon est bloqué (sommeil/gel) → pas d'action.
func _tick_status(delta: float) -> bool:
	var inst := pokemon_instance
	var dot := inst.tick_status(delta)
	if dot > 0 and not _evolving:   # invincible pendant l'évolution (statuts inclus)
		inst.take_damage(dot)
		hp_changed.emit(inst.hp_ratio())
		CombatVFX.spawn_damage_number(get_parent(), global_position, dot, "player")
		if inst.is_fainted():
			_play_faint_anim()
			return true

	# Logo flottant synchronisé avec l'état courant
	if inst.status != _status_shown:
		_status_shown = inst.status
		if is_instance_valid(_status_icon):
			_status_icon.queue_free()
			_status_icon = null
		if inst.status != "":
			_status_icon = StatusFx.make_icon(inst.status)
			_status_icon.position = Vector3(0, 2.5, 0)
			add_child(_status_icon)

	return not inst.status_can_act()


func _update_range_ring() -> void:
	if not is_instance_valid(_range_ring):
		return
	_range_ring.visible = is_active
	if not is_active:
		if is_instance_valid(_min_ring):
			_min_ring.visible = false
		return

	# Rayon = portée de la capacité SÉLECTIONNÉE (change à chaque touche 1-4).
	var slot := clampi(_selected_move_idx, 0, 3)
	var rmax := _move_range_max(slot)
	_range_ring.scale = Vector3(rmax, 0.05, rmax)
	# Doré normalement ; ROUGE quand la capacité n'est pas prête (verrou/cadence).
	var ready := _move_ready(slot)
	var base_col := Color(1.0, 0.85, 0.0) if ready else Color(0.85, 0.35, 0.25)
	_ring_mat.albedo_color = Color(base_col.r, base_col.g, base_col.b,
		0.16 + _attack_flash * 0.45)

	if is_instance_valid(_min_ring):
		var rmin := _move_range_min(slot)
		_min_ring.visible = rmin > 0.0
		if rmin > 0.0:
			_min_ring.scale = Vector3(rmin, 0.05, rmin)


# ── Mode joueur ───────────────────────────────────────────────────────

func _player_process() -> void:
	# Capacités 1-4 : chaque touche LANCE directement sa capacité (et la
	# garde sélectionnée pour l'auto-attaque qui suit)
	for i in 4:
		if Input.is_action_just_pressed("use_move_%d" % (i + 1)):
			if i < pokemon_instance.equipped_moves.size():
				_selected_move_idx = i
				move_selected.emit(_selected_move_idx)
				# Lançable ? (verrou global + cadence propre + portée MINI :
				# une grosse frappe à distance ne part pas si un ennemi est collé)
				if _move_ready(i) and _min_range_ok(i):
					_attack()
			break

	var dir := Vector3(
		Input.get_axis("ui_left", "ui_right"),
		0.0,
		Input.get_axis("ui_up", "ui_down")
	)
	if dir.length() > 1.0:
		dir = dir.normalized()

	# Dash — burst de vitesse dans la direction courante, consomme une charge
	if Input.is_action_just_pressed("dash") and _dash_charges > 0 \
			and dir.length() > 0.1 and _dash_timer <= 0.0:
		_dash_charges -= 1
		_dash_timer = DASH_TIME
		_dash_dir = dir.normalized()
		dash_changed.emit(_dash_charges, dash_max_charges)
		Sfx.play("dash", -6.0)
		sprite.modulate = Color(1.7, 1.7, 2.2)   # flash bleuté pendant l'esquive
		get_tree().create_timer(DASH_TIME + 0.05).timeout.connect(func():
			if is_instance_valid(self) and not _evolving:
				sprite.modulate = Color.WHITE
		)
		# Game feel : traînée de vitesse + rémanences (façon Hades), petite
		# secousse de caméra — et on traverse les obstacles pendant le burst
		# (mais jamais l'eau, cf. _dash_phase_through).
		var parent := get_parent()
		CombatVFX.spawn_dash_streaks(parent, global_position, _dash_dir)
		CombatVFX.spawn_dash_afterimage(parent, sprite)
		get_tree().create_timer(DASH_TIME * 0.5).timeout.connect(func():
			if is_instance_valid(self):
				CombatVFX.spawn_dash_afterimage(parent, sprite)
		)
		get_tree().call_group("combat_arena", "add_camera_shake", 0.05)
		_dash_phase_through()

	if _dash_timer > 0.0:
		velocity = _dash_dir * DASH_SPEED
	else:
		# paralysie = ralenti ; boue du marécage = ralentie aussi (cf.
		# MapGenerator.terrain_speed_mult) ; speed_mult = bonus de fin de zone
		# « Vitesse de déplacement » / objets à effet "spd" — jusqu'ici ce
		# multiplicateur n'affectait QUE la cadence d'attaque (cf.
		# _move_cooldown), jamais le déplacement à proprement parler.
		velocity = dir * SPEED * pokemon_instance.speed_mult * pokemon_instance.status_speed_mult() * _terrain_speed_mult()
	_update_anim(Vector2(dir.x, dir.z))
	move_and_slide()
	_snap_to_ground()

	# Plus d'attaque automatique : le membre contrôlé n'attaque que sur
	# pression de touche (Q/Z/S/D ou 1-4) — le cooldown limite le spam.
	# Les compagnons IA, eux, attaquent toujours seuls (cf. _companion_process).


## Pendant le burst du dash, on ignore les obstacles (arbres, rochers,
## coffres — layer 1, cf. MapBase/MapGenerator) façon Hades : on traverse
## le décor sans s'y accrocher. L'eau (WATER_LAYER, cf. CombatArena) reste
## TOUJOURS bloquante — seul ce bit est retiré du masque, jamais les autres.
func _dash_phase_through() -> void:
	var saved_mask := collision_mask
	collision_mask = saved_mask & ~1
	get_tree().create_timer(DASH_TIME).timeout.connect(func() -> void:
		if is_instance_valid(self):
			collision_mask = saved_mask
	)


# ── IA compagnon ──────────────────────────────────────────────────────

## Première capacité disponible (cadence écoulée + portée mini respectée) —
## sinon celle dont la recharge finit le plus tôt, pour rester en position.
## Sans capacité équipée : slot 0, qui retombe sur l'attaque de base
## (ATTACK_RANGE / ATTACK_COOLDOWN via _move_at() == null).
func _companion_pick_move() -> int:
	var n: int = mini(pokemon_instance.equipped_moves.size(), _move_cd.size())
	if n <= 0:
		return 0
	var best := -1
	for i in n:
		if _move_ready(i) and _min_range_ok(i):
			return i
		if best < 0 or _move_cd[i] < _move_cd[best]:
			best = i
	return best


func _companion_process(delta: float) -> void:
	var nearest := _nearest_enemy(AI_SEEK_RADIUS)

	if nearest:
		# Le compagnon choisit une capacité PRÊTE (cadences indépendantes) et
		# s'engage à la portée de CETTE capacité, pas à une portée fixe.
		var slot := _companion_pick_move()
		if slot >= 0:
			_selected_move_idx = slot
		var dist := global_position.distance_to(nearest.global_position)
		if dist <= _move_range_max(_selected_move_idx):
			velocity = Vector3.ZERO
			_update_anim(Vector2.ZERO)
			if slot >= 0 and _move_ready(slot) and _min_range_ok(slot):
				_attack()
		else:
			_steer_toward(nearest.global_position, delta)
	elif is_instance_valid(_leader):
		var dist_leader := global_position.distance_to(_leader.global_position)
		if dist_leader > AI_FOLLOW_DIST:
			_steer_toward(_leader.global_position, delta)
		else:
			velocity = Vector3.ZERO
			_update_anim(Vector2.ZERO)
	else:
		velocity = Vector3.ZERO
		_update_anim(Vector2.ZERO)


func _steer_toward(target_pos: Vector3, delta: float) -> void:
	var steer_pos := _get_steer_target(target_pos, delta)
	var dir := (steer_pos - global_position)
	dir.y = 0.0
	dir = dir.normalized()
	velocity = dir * AI_SPEED * pokemon_instance.status_speed_mult() * _terrain_speed_mult()
	_update_anim(Vector2(dir.x, dir.z))
	move_and_slide()
	_snap_to_ground()


## Ralentissement dû au TERRAIN sous les pattes (boue du marécage). Vaut pour
## le joueur ET pour l'IA : une mécanique de terrain qui n'affecterait qu'un
## camp serait un avantage déguisé, pas un terrain.
## `has_method` : les scènes de map legacy (MapBase nu) ne l'exposent pas.

## ÉCLABOUSSURES DE PAS sur l'eau peu profonde (Forêt/Marécage) : une petite
## ondulation sous les pattes à cadence fixe tant qu'on se déplace dans une
## flaque. Cadence et non par-frame : à 60 fps ce serait un sillage opaque.
var _puddle_cd: float = 0.0
var _step_side: int = 1     # alternance patte gauche/droite des empreintes

func _update_puddle_steps(delta: float) -> void:
	_puddle_cd = maxf(0.0, _puddle_cd - delta)
	if _puddle_cd > 0.0 or velocity.length() < 1.5:
		return
	if not is_instance_valid(_map) or not _map.has_method("is_shallow_cell"):
		return
	var here := _map.world3_to_cell(global_position)
	if _map.is_shallow_cell(here):
		_puddle_cd = 0.24
		var tint := Color(0.80, 0.88, 0.66, 0.85) \
			if _map.get("theme") == MapGenerator.MapTheme.SWAMP \
			else Color(0.94, 0.98, 1.0, 0.85)
		CombatVFX.spawn_puddle_ripple(get_parent(), global_position, tint)
	elif _map.has_method("is_mud_cell") and _map.is_mud_cell(global_position):
		# Boue nue : une EMPREINTE qui reste, pattes alternées (cf. _step_side).
		_puddle_cd = 0.24
		_step_side = -_step_side
		CombatVFX.spawn_mud_footprint(get_parent(), global_position, velocity, _step_side)


func _terrain_speed_mult() -> float:
	if not is_instance_valid(_map) or not _map.has_method("terrain_speed_mult"):
		return 1.0
	return _map.terrain_speed_mult(global_position)


## Colle le personnage au relief procédural (collines douces) sous ses pieds
## — la map reste plate par défaut (arène) donc ce suivi ne fait rien de
## visible en dehors des maps normales.
func _snap_to_ground() -> void:
	position.y = _map.ground_anchor_y(global_position) \
		if is_instance_valid(_map) and _map.has_method("ground_anchor_y") else 0.0


## Renvoie le point vers lequel diriger le compagnon : ligne droite si la vue
## est dégagée, sinon le prochain point de détour via la grille A* de la map.
func _get_steer_target(target_pos: Vector3, delta: float) -> Vector3:
	_path_repath_timer -= delta
	if _has_clear_line_of_sight(target_pos):
		_path_repath_timer = 0.0
		return target_pos

	if not is_instance_valid(_map):
		return target_pos

	if _path_repath_timer <= 0.0:
		_path_repath_timer = REPATH_INTERVAL
		_path_waypoint = _map.get_next_path_point_3d(global_position, target_pos)

	if global_position.distance_to(_path_waypoint) < 0.6:
		return target_pos

	return _path_waypoint


func _has_clear_line_of_sight(target_pos: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var lift := Vector3(0, 0.5, 0)   # rayon à mi-hauteur, au-dessus du sol
	var query := PhysicsRayQueryParameters3D.create(global_position + lift, target_pos + lift)
	query.collision_mask = 1
	query.exclude        = [get_rid()]
	var result := space.intersect_ray(query)
	return result.is_empty()


## Un ennemi tapi dans les hautes herbes ne peut être ni ciblé ni frappé tant
## qu'il ne s'est pas montré : l'embuscade doit tromper l'ÉQUIPE, pas seulement
## l'œil du joueur. Il se révèle de lui-même dès qu'on l'approche (cf.
## EnemyAI.GRASS_REVEAL_DIST) — la mêlée reste donc toujours possible.
func _enemy_visible(enemy: Node) -> bool:
	return not (enemy.has_method("is_grass_hidden") and enemy.is_grass_hidden())


func _nearest_enemy(max_dist: float) -> CharacterBody3D:
	var nearest: CharacterBody3D = null
	var min_d := max_dist
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		if not _enemy_visible(enemy):
			continue
		var d := global_position.distance_to(enemy.global_position)
		if d < min_d:
			min_d = d
			nearest = enemy
	return nearest


# ── Animation ─────────────────────────────────────────────────────────

func _update_anim(dir: Vector2) -> void:
	if not sprite.sprite_frames or _evolving:
		return
	if _action_lock > 0.0:
		return   # une animation d'attaque/dégâts est en cours
	var anim := Billboard3D.dir_to_anim(dir)

	if not _has_directional and dir.x != 0:
		sprite.flip_h = dir.x < 0

	if anim != _current_anim:
		_current_anim = anim
		if sprite.sprite_frames.has_animation(anim):
			sprite.play(anim)


## Joue la première animation d'action PMD disponible parmi `prefixes`
## (chaîne de repli, ex ["shoot","charge","attack"]), orientée vers `dir`
## (Vector2 XZ, ZERO = garder l'orientation courante) — no-op si aucune
## feuille ne la fournit (le lunge/flash existants restent).
func _play_action_anim(prefixes: Array, dir: Vector2, lock: float) -> void:
	if not sprite.sprite_frames or _evolving:
		return
	var suffix := _facing_suffix() if dir.length() < 0.1 else \
		Billboard3D.dir_to_anim(dir).trim_prefix("walk_")
	for prefix: String in prefixes:
		var anim := "%s_%s" % [prefix, suffix]
		if sprite.sprite_frames.has_animation(anim) \
				and sprite.sprite_frames.get_frame_count(anim) > 0:
			_action_lock  = lock
			_current_anim = anim
			sprite.play(anim)
			return


## Suffixe directionnel de l'animation courante ("walk_downright" → "downright").
func _facing_suffix() -> String:
	for s in ["downright", "downleft", "upright", "upleft", "down", "up", "left", "right"]:
		if _current_anim.ends_with(s):
			return s
	return "down"


# ── Attaque ───────────────────────────────────────────────────────────

func _attack() -> void:
	_attack_flash = 1.0
	# Tirer depuis les hautes herbes TRAHIT la position : on redevient visible
	# pour les ennemis pendant GRASS_REVEAL_TIME (cf. is_grass_concealed). Sans
	# ça, l'herbe permettait de mitrailler indéfiniment une cible incapable de
	# riposter. Contrairement à l'ennemi, dont l'embuscade est à usage unique,
	# le joueur peut se re-fondre après le délai — l'herbe reste un outil, elle
	# se paie juste à chaque coup.
	_grass_reveal = GRASS_REVEAL_TIME

	var moves: Array = pokemon_instance.equipped_moves
	# Verrous : cadence PROPRE au move joué + court verrou global (pas
	# d'enchaînement instantané des 4 capacités).
	var slot := clampi(_selected_move_idx, 0, maxi(0, _move_cd.size() - 1))
	var cd := _move_cooldown(slot)
	_move_cd[slot]     = cd
	_move_cd_max[slot] = cd
	_global_lock       = GLOBAL_LOCK
	_attack_timer      = cd   # conservé : anim/IA s'y réfèrent encore

	var reach := _move_range_max(slot)

	var move_type:  String
	var move_power: int
	var move_class: String = "physical"
	if not moves.is_empty():
		var idx  := clampi(_selected_move_idx, 0, moves.size() - 1)
		var move: MoveData = moves[idx]
		# CT de statut à effet réel (soin, altération garantie) — cf.
		# MoveShopScreen.MOVE_LIST. Une CT de statut sans effet connu (moves
		# d'espèce type Rugissement, non achetables) retombe sur l'attaque de
		# base pour ne jamais laisser un slot inerte.
		if move and move.power <= 0 and move.damage_class == "status" and not move.effect.is_empty():
			_use_status_move(move)
			return
		if move and move.power > 0:
			move_type  = move.type
			move_power = move.power
			move_class = move.damage_class
		else:
			move_type  = pokemon_instance.get_attack_type()
			move_power = pokemon_instance.get_attack_power()
	else:
		move_type  = pokemon_instance.get_attack_type()
		move_power = pokemon_instance.get_attack_power()

	# Attaque SPÉCIALE = À DISTANCE (convention PokeAPI damage_class) :
	# projectile guidé vers l'ennemi le plus proche, anim Shoot/Charge.
	# Attaque PHYSIQUE = corps à corps (zone autour de soi, comme avant).
	if move_class == "special":
		_ranged_attack(move_type, move_power, reach)
		return

	var anim_prefixes: Array = ["attack"]

	var lunge_pos := Vector3.ZERO
	var hit_count := 0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		if not _enemy_visible(enemy):
			continue   # tapi : le coup passe au travers, on ne le voit pas
		if global_position.distance_to(enemy.global_position) <= reach:
			var result := DamageCalculator.calculate(pokemon_instance, enemy.pokemon_instance, move_power, move_type, move_class)
			var dmg:  int  = result["damage"]
			var crit: bool = result["crit"]
			enemy.take_damage(dmg, global_position, CombatVFX.type_color(move_type), Net.local_id(), self)
			# Animation d'attaque Essentials (planche du type) jouée sur la cible
			AttackAnim.play(get_parent(), enemy.global_position, move_type)
			# Chance d'infliger un statut selon le type de l'attaque
			var st := StatusFx.roll(move_type)
			if st != "":
				enemy.pokemon_instance.apply_status(st, StatusFx.duration(st))
			# Chiffre de dégâts coloré selon l'efficacité de type — le retour
			# visuel apprend au joueur les matchups sans ouvrir de menu. Un coup
			# critique prime sur l'efficacité de type (le moment se sent d'abord).
			var mult := DamageCalculator.type_multiplier(move_type, enemy.pokemon_instance.data.types)
			CombatVFX.spawn_damage_number(get_parent(), enemy.global_position, dmg,
				"crit" if crit else CombatVFX.kind_from_multiplier(mult))
			lunge_pos += enemy.global_position
			hit_count += 1

	# Les attaques cassent aussi les arbres à baies à portée (récolte de Baies)
	for tree in get_tree().get_nodes_in_group("berry_trees"):
		if not is_instance_valid(tree):
			continue
		if global_position.distance_to(tree.global_position) <= reach:
			tree.take_hit(global_position)
			if hit_count == 0:
				lunge_pos += tree.global_position
				hit_count += 1

	# … et les décors cassables (souches, rondins, champignons — cosmétique)
	for prop in get_tree().get_nodes_in_group("breakables"):
		if not is_instance_valid(prop):
			continue
		if global_position.distance_to(prop.global_position) <= reach:
			prop.take_hit(global_position)
			if hit_count == 0:
				lunge_pos += prop.global_position
				hit_count += 1

	# Dresseurs de village : on peut les ASSOMMER (jamais les tuer) — à terre,
	# ils cessent de lancer des pokéballs et lâchent une clé.
	for tr in get_tree().get_nodes_in_group("village_trainers"):
		if not is_instance_valid(tr):
			continue
		if global_position.distance_to(tr.global_position) <= reach:
			var tdmg := maxi(1, int(float(move_power) * 0.5) + 4)
			tr.take_hit(tdmg)
			CombatVFX.spawn_damage_number(get_parent(), tr.global_position, tdmg, "normal")
			lunge_pos += tr.global_position
			hit_count += 1

	if not _evolving:
		if hit_count > 0:
			_play_attack_lunge(lunge_pos / hit_count, anim_prefixes)
		else:
			# COUP DANS LE VIDE : même langage visuel qu'un coup qui porte —
			# fente, anim d'attaque PMD et effet du type devant soi. L'ancien
			# simple flash blanc faisait croire que l'attaque n'était pas
			# partie (retour joueurs : « je veux voir l'animation »).
			var swing := _swing_point()
			_play_attack_lunge(swing, anim_prefixes)
			AttackAnim.play(get_parent(), swing, move_type)


## CT de statut à effet réel (cf. MoveData.effect) : soin (soi/équipe) ou
## altération GARANTIE sur l'ennemi le plus proche à portée — contrairement
## au tirage par type des attaques normales (StatusFx.roll), ces CT
## réussissent toujours, ce qui justifie leur coût et fait un vrai choix de
## rôle (soigneur/contrôle) à l'achat chez le Tuteur de capacités.
const STATUS_MOVE_RANGE := 9.0
const HEAL_TEAM_RADIUS  := 7.0

func _use_status_move(move: MoveData) -> void:
	_attack_flash = 1.0
	var kind: String = move.effect.get("kind", "")
	match kind:
		"heal_self":
			pokemon_instance.heal_percent(float(move.effect.get("pct", 0.3)))
			CombatVFX.spawn_damage_number(get_parent(), global_position, 0, "heal")
			AttackAnim.play(get_parent(), global_position, "fx_heal")
		"heal_team":
			var pct: float = float(move.effect.get("pct", 0.3))
			pokemon_instance.heal_percent(pct)
			CombatVFX.spawn_damage_number(get_parent(), global_position, 0, "heal")
			AttackAnim.play(get_parent(), global_position, "fx_heal")
			for ally in get_tree().get_nodes_in_group("players"):
				if not is_instance_valid(ally) or ally == self: continue
				if global_position.distance_to(ally.global_position) > HEAL_TEAM_RADIUS: continue
				ally.pokemon_instance.heal_percent(pct)
				CombatVFX.spawn_damage_number(get_parent(), ally.global_position, 0, "heal")
				AttackAnim.play(get_parent(), ally.global_position, "fx_heal")
		"status":
			var target := _nearest_enemy(STATUS_MOVE_RANGE)
			if is_instance_valid(target):
				target.pokemon_instance.apply_status(
					str(move.effect.get("status", "")),
					StatusFx.duration(str(move.effect.get("status", ""))))
				AttackAnim.play(get_parent(), target.global_position, move.type)

	if not _evolving:
		# Anim PMD DIFFÉRENTE d'une frappe : Charge (concentration) — une CT
		# de soutien ne « donne pas un coup » (retour joueurs). Repli attack
		# pour les planches sans action Charge.
		_play_action_anim(["charge", "attack"], Vector2.ZERO, 0.5)
		sprite.modulate = Color(1.4, 2.0, 1.4)
		get_tree().create_timer(0.12).timeout.connect(func():
			if is_instance_valid(self) and not _evolving:
				sprite.modulate = Color.WHITE
		)


## Attaque à distance : tire un Projectile sur l'ennemi le plus proche, dans la
## portée PROPRE au move (`reach`), anim PMD Shoot→Charge→Attack. Dégâts,
## statut, chiffre coloré et animation de type appliqués À L'IMPACT.
const RANGED_RANGE := 9.0   # secours (Pokémon sans move équipé)

func _ranged_attack(move_type: String, move_power: int, reach: float = RANGED_RANGE) -> void:
	var target := _nearest_enemy(reach)
	if target == null:
		# TIR À VIDE : anim de tir + projectile qui part réellement devant soi
		# et se perd (launch_point, esquivable/rien à toucher). Le simple flash
		# blanc laissait croire que rien n'était parti (retour joueurs).
		var ahead := _swing_point(minf(reach, 7.0))
		if not _evolving:
			var vdir := ahead - global_position
			_play_action_anim(["shoot", "charge", "attack"], Vector2(vdir.x, vdir.z), 0.4)
		Projectile.launch_point(get_parent(), global_position, ahead,
			CombatVFX.type_color(move_type), func() -> void: pass)
		return

	var dir := target.global_position - global_position
	if not _evolving:
		_play_action_anim(["shoot", "charge", "attack"], Vector2(dir.x, dir.z), 0.4)

	# Attaque à distance = toujours SPÉCIALE (cf. le tri physique/spécial dans
	# _try_attack, seul appelant) : Atq. Spé de l'attaquant vs Déf. Spé de la cible.
	var result := DamageCalculator.calculate(pokemon_instance, target.pokemon_instance, move_power, move_type, "special")
	var dmg:  int  = result["damage"]
	var crit: bool = result["crit"]
	var mult := DamageCalculator.type_multiplier(move_type, target.pokemon_instance.data.types)
	var kind := "crit" if crit else CombatVFX.kind_from_multiplier(mult)
	var tint := CombatVFX.type_color(move_type)
	var from := global_position
	var parent := get_parent()
	var tgt := target
	var shooter := self   # auteur du tir → XP créditée au seul tueur
	Projectile.launch(parent, global_position, target, tint, func() -> void:
		if not is_instance_valid(tgt) or not is_instance_valid(parent):
			return
		tgt.take_damage(dmg, from, tint, Net.local_id(), shooter)
		var st := StatusFx.roll(move_type)
		if st != "":
			tgt.pokemon_instance.apply_status(st, StatusFx.duration(st))
		CombatVFX.spawn_damage_number(parent, tgt.global_position, dmg, kind)
		AttackAnim.play(parent, tgt.global_position, move_type)
	)


## Point « devant soi » pour un coup dans le VIDE : dernière direction de
## déplacement si on bouge, sinon le côté vers lequel le sprite regarde.
func _swing_point(dist: float = 1.6) -> Vector3:
	var v := velocity
	v.y = 0.0
	if v.length() > 0.5:
		return global_position + v.normalized() * dist
	return global_position + Vector3(-dist if sprite.flip_h else dist, 0, 0)


func _play_attack_lunge(target_pos: Vector3, anim_prefixes: Array = ["attack"]) -> void:
	var dir := (target_pos - global_position)
	dir.y = 0.0
	dir = dir.normalized()
	_play_action_anim(anim_prefixes, Vector2(dir.x, dir.z), 0.4)
	var tw := create_tween()
	tw.tween_property(sprite, "position", _sprite_base_pos + dir * 0.9, 0.07).set_ease(Tween.EASE_OUT)
	tw.tween_property(sprite, "position", _sprite_base_pos, 0.14).set_ease(Tween.EASE_IN)
	sprite.modulate = Color(2.2, 2.2, 2.2)
	get_tree().create_timer(0.1).timeout.connect(func():
		if is_instance_valid(self) and not _evolving:
			sprite.modulate = Color.WHITE
	)


# ── Furtivité dans la haute herbe ─────────────────────────────────────
# Dans une case de haute herbe, le sprite devient PLUS CLAIR et translucide :
# le joueur voit qu'il est caché. Réappliqué chaque frame car les flashes de
# combat (dégâts, attaque, dash) réécrivent modulate puis restaurent WHITE.
# SEULEMENT de la transparence, PAS d'éclaircissement — le signal doit dire
# « tu es dans l'herbe », rien de plus.
#
# Les essais précédents poussaient le tint jusqu'à 2.4 pour « mieux voir » le
# Pokémon : ça produisait l'inverse. Un sprite multiplié par 2.4 est cramé en
# blanc, et sur le fond clair d'une prairie il DISPARAÎT — ce qu'on prenait à
# tort pour un excès de transparence. Le tint n'éclaircit pas un sprite déjà
# clair, il l'efface. On garde donc rgb neutre et on ne joue que sur l'alpha.
const GRASS_HIDDEN_TINT := Color(1.0, 1.0, 1.0, 0.6)

## Durée pendant laquelle une attaque nous trahit (cf. _attack).
const GRASS_REVEAL_TIME := 2.5
var _grass_reveal: float = 0.0

## Ce Pokémon est-il DISSIMULÉ dans les hautes herbes ? Source unique de vérité :
## le rendu (ci-dessous) ET le ciblage ennemi (EnemyAI._player_concealed) la
## consultent. Si les deux la calculaient chacun de leur côté, on finirait avec
## un Pokémon qui a l'air caché mais que l'IA voit — ou l'inverse.
func is_grass_concealed() -> bool:
	if _grass_reveal > 0.0:
		return false   # on vient d'attaquer : on s'est trahi
	return is_instance_valid(_map) and _map.has_method("is_tall_grass_3d") \
		and _map.is_tall_grass_3d(global_position)


func _update_grass_hiding(delta: float) -> void:
	_grass_reveal = maxf(0.0, _grass_reveal - delta)
	if _evolving or not is_instance_valid(sprite):
		return
	if is_grass_concealed():
		if sprite.modulate == Color.WHITE:
			sprite.modulate = GRASS_HIDDEN_TINT
	elif sprite.modulate == GRASS_HIDDEN_TINT:
		sprite.modulate = Color.WHITE


## Retourne true si le coup a bien porté (false = évité — esquive ou
## évolution en cours) — les appelants s'en servent pour savoir s'il faut
## afficher LEUR PROPRE retour visuel (chiffre de dégâts, statut…), déjà
## inutile ici puisque l'esquive affiche son propre texte dédié.
func take_damage(amount: int, source_pos: Vector3 = Vector3(INF, INF, INF)) -> bool:
	# Multijoueur : les ennemis (hôte) frappent la COPIE locale d'un joueur
	# distant → on relaie au propriétaire, qui applique et rediffuse ses PV.
	if remote_peer != 0:
		if multiplayer.is_server():
			_net_take_damage.rpc_id(remote_peer, amount, source_pos)
		return true   # résultat réel décidé côté propriétaire, pas ici
	# INVINCIBLE pendant l'évolution : la transformation est un moment
	# protégé — en contrepartie le Pokémon ne peut pas attaquer non plus
	# (cf. les gardes _evolving sur _attack_timer).
	if _evolving:
		return false
	# Esquive : chance d'ignorer TOTALEMENT le coup (cf. PokemonInstance.
	# dodge_chance, bonus de fin de zone « Chances d'esquive »). Retour visuel
	# dédié — sans lui, un coup qui ne fait rien passerait pour un bug.
	if randf() < pokemon_instance.dodge_chance:
		CombatVFX.spawn_damage_number(get_parent(), global_position, 0, "dodge")
		return false
	pokemon_instance.take_damage(amount)
	net_broadcast_hp()
	if not _evolving:
		_play_action_anim(["hurt"], Vector2.ZERO, 0.3)
		Sfx.play("hurt", 0.0 if is_active else -6.0)
		sprite.modulate = Color(2.0, 0.3, 0.3)
		get_tree().create_timer(0.15).timeout.connect(func():
			if is_instance_valid(self) and not _evolving:
				sprite.modulate = Color.WHITE
		)
		# Étincelle d'impact orientée vers l'agresseur (teinte "dégâts subis")
		var dir := Vector3.ZERO
		if source_pos.x != INF:
			dir = global_position - source_pos
			dir.y = 0.0
			dir = dir.normalized() if dir.length() > 0.01 else Vector3.ZERO
		CombatVFX.spawn_impact(get_parent(), global_position + Vector3(0, 0.6, 0) - dir * 0.35,
			Color(1.0, 0.42, 0.35))
		# Hit-pause seulement quand le Pokémon CONTRÔLÉ encaisse (le coup se sent)
		if is_active:
			get_tree().call_group("combat_arena", "request_hitstop", 0.05)
	hp_changed.emit(pokemon_instance.hp_ratio())
	if pokemon_instance.is_fainted():
		_play_faint_anim()
	return true


func _play_faint_anim() -> void:
	set_physics_process(false)
	remove_from_group("players")
	if is_instance_valid(_range_ring):
		_range_ring.visible = false
	CombatVFX.spawn_death_poof(get_parent(), global_position, Color(0.95, 0.55, 0.50))
	# Le membre K.O. ne DISPARAÎT plus : il reste couché sur place (anim
	# Sleep PMD, repli Hurt figée), grisé — visuellement ranimable (revive).
	_action_lock = INF   # verrouille l'anim (rien ne doit l'écraser)
	_play_action_anim(["sleep", "hurt"], Vector2.ZERO, INF)
	sprite.modulate = Color(0.52, 0.52, 0.60, 0.9)
	sprite.position = _sprite_base_pos
	died.emit()


## Ranime un membre K.O. (bonus de fin de zone "revive") — restaure les PV
## au pourcentage donné et réactive le membre là où il est tombé.
func revive(hp_pct: float) -> void:
	if not is_instance_valid(pokemon_instance) or not pokemon_instance.is_fainted():
		return
	pokemon_instance.current_hp = maxi(1, int(pokemon_instance.max_hp * hp_pct))
	add_to_group("players")
	set_physics_process(true)
	sprite.modulate = Color.WHITE
	sprite.position = _sprite_base_pos
	# Réveil : déverrouille l'anim Sleep du K.O. et repart sur idle
	_action_lock = 0.0
	if sprite.sprite_frames and sprite.sprite_frames.has_animation("idle"):
		_current_anim = "idle"
		sprite.play("idle")
	if is_instance_valid(_range_ring):
		_range_ring.visible = true
	hp_changed.emit(pokemon_instance.hp_ratio())
	CombatVFX.spawn_death_poof(get_parent(), global_position, Color(0.55, 1.0, 0.60))


# ── XP & Évolution ───────────────────────────────────────────────────

func gain_xp(amount: int) -> void:
	var leveled := pokemon_instance.add_xp(maxi(1, int(amount * xp_mult)))
	xp_changed.emit(pokemon_instance.xp_ratio(), pokemon_instance.level)
	net_broadcast_progress()
	if leveled:
		Sfx.play("levelup", -3.0)
		leveled_up.emit(pokemon_instance.level)
		hp_changed.emit(pokemon_instance.hp_ratio())
		_check_evolution()


func _check_evolution() -> void:
	var evo: Variant = GameManager.EVOLUTIONS.get(pokemon_instance.data.id)
	if evo == null:
		return
	if pokemon_instance.level >= evo["level"]:
		_start_evolution(evo["evolves_to"])


func _start_evolution(new_id: int) -> void:
	_evolving = true
	Sfx.play_file(Sfx.ME_EVO_START)
	var tween := create_tween().set_loops()
	tween.tween_property(sprite, "modulate", Color(4.0, 4.0, 4.0), 0.12)
	tween.tween_property(sprite, "modulate", Color(0.8, 0.8, 1.0), 0.12)

	PokemonAPI.get_pokemon(new_id, func(api_data: Dictionary) -> void:
		if not is_instance_valid(self):
			return
		if api_data.is_empty():
			tween.kill()
			sprite.modulate = Color.WHITE
			_evolving = false
			return
		var new_data := PokemonData.from_api(api_data)
		pokemon_instance.evolve_to(new_data)
		hp_changed.emit(pokemon_instance.hp_ratio())

		PMDSprites.get_walk_sprites(new_id, self, func(result: Dictionary) -> void:
			if not is_instance_valid(self):
				return
			tween.kill()
			_has_directional = false
			if not result.is_empty():
				_has_directional = true
				sprite.sprite_frames = result.frames
				_apply_sprite_scale(result)
				if result.frames.has_animation("walk_down") and result.frames.get_frame_count("walk_down") > 0:
					portrait_ready.emit(team_index, result.frames.get_frame_texture("walk_down", 0))
			else:
				_load_fallback_sprite(new_data.sprite_url)
			sprite.modulate = Color.WHITE
			_current_anim = ""
			sprite.play("idle")
			_evolving = false
			Sfx.play_file(Sfx.ME_EVO_SUCCESS)
			evolved.emit(new_data.name_fr)
			net_broadcast_progress()   # diffuse la NOUVELLE espèce aux autres joueurs
		)
	)
