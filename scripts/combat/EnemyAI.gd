extends CharacterBody3D

## Ennemi en combat — HD-2D (phase 2) : CharacterBody3D + sprite PMD
## billboardé via Billboard3D. Logique de ciblage/attaque inchangée ;
## coordonnées sur le plan XZ, 1 unité monde = 1 ancienne tuile de 16 px
## (valeurs 2D divisées par 16).

const SPEED           := 3.4
const ATTACK_RANGE    := 2.8
const ATTACK_COOLDOWN := 1.8
const DISPLAY_UNITS   := 1.75
const FOOT_LIFT        := 0.05

const HP_BAR_W := 1.5
const HP_BAR_H := 0.14

var pokemon_instance: PokemonInstance
var is_champion: bool = false   # élite de salle : plus grand, anneau rouge, meilleur butin
var is_boss:     bool = false   # boss de palier : encore plus grand, anneau doré
var is_demi_boss: bool = false  # demi-boss de grotte : aura rouge, débloque une espèce

# ── ARCHÉTYPES DE DÉPLACEMENT ────────────────────────────────────────
# Avant, TOUS les ennemis avaient le même comportement : foncer sur le joueur
# et s'arrêter à portée — des vagues denses d'ennemis identiques qui
# s'agglutinent. Chaque ennemi adopte désormais une tactique :
#   CHASER     : fonce et frappe (défaut, le gros des troupes)
#   KITER      : tireur — garde ses distances, recule si on l'approche
#   CHARGER    : télégraphe long puis RUÉE rapide (esquivable)
#   SKIRMISHER : frappe puis se replie brièvement (harcèlement)
# Boss/champions restent CHASER : lisibles et prévisibles.
enum Behavior { CHASER, KITER, CHARGER, SKIRMISHER }
var behavior: int = Behavior.CHASER

const KITE_MIN := 5.0            # le tireur recule en deçà de cette distance
const SKIRMISH_RETREAT_TIME := 0.9
const SKIRMISH_RETREAT_DIST := 4.5
const CHARGE_RANGE := 11.0       # distance d'où le chargeur peut s'élancer
const CHARGE_SPEED := 15.0
const CHARGE_TIME  := 0.35

var _retreat_timer:  float = 0.0
var _charge_timer:   float = 0.0
var _charge_dir:     Vector3 = Vector3.ZERO
var _charge_pending: bool = false
var _attack_timer: float = 0.0
var _current_anim: String = "idle"
var _action_lock:  float = 0.0   # verrou d'anim attaque/dégâts (cf. _update_anim)
var _hp_fill:     MeshInstance3D = null
var _sprite_base_pos: Vector3 = Vector3.ZERO

# Knockback (recul à l'impact) — vitesse portée par move_and_slide (donc
# stoppée par les murs, aucun risque de coincer l'ennemi hors de la map) et
# amortie sur ~0.15 s pendant lesquelles l'IA ne pilote pas.
const KNOCKBACK_BASE := 9.0
var _knockback_vel:   Vector3 = Vector3.ZERO
var _knockback_timer: float   = 0.0

# Pathfinding (contournement d'obstacles)
var _map:               MapBase = null
var _path_repath_timer: float   = 0.0
var _path_waypoint:     Vector3 = Vector3.ZERO
const REPATH_INTERVAL := 0.4

## `attacker_peer` = peer_id de qui a réellement donné le coup fatal — sert
## à ne créditer l'XP qu'à SON auteur en multijoueur (cf. CombatArena.
## _on_enemy_died), pas à toute l'équipe pour chaque kill.
signal died(xp_reward: int, attacker_peer: int)

@onready var sprite: AnimatedSprite3D = $AnimatedSprite3D


func _ready() -> void:
	add_to_group("enemies")
	Billboard3D.setup_sprite(sprite)
	_create_hp_bar()
	_add_shadow()
	_map = get_tree().get_first_node_in_group("combat_map") as MapBase


func _add_shadow() -> void:
	add_child(Billboard3D.make_blob_shadow(Vector2(1.25, 0.7)))


## Barre de PV en quads 3D légèrement inclinés vers la caméra (angle fixe
## façon Octopath : pas besoin de vrai billboard).
func _create_hp_bar() -> void:
	var container := Node3D.new()
	container.name = "HPBar"
	container.position = Vector3(0, 2.2, 0)
	container.rotation_degrees = Vector3(-28, 0, 0)
	add_child(container)

	var bg := MeshInstance3D.new()
	var bg_quad := QuadMesh.new()
	bg_quad.size = Vector2(HP_BAR_W + 0.06, HP_BAR_H + 0.05)
	bg.mesh = bg_quad
	bg.material_override = _bar_material(Color(0.15, 0.15, 0.15, 0.85))
	container.add_child(bg)

	_hp_fill = MeshInstance3D.new()
	var fill_quad := QuadMesh.new()
	fill_quad.size = Vector2(HP_BAR_W, HP_BAR_H)
	_hp_fill.mesh = fill_quad
	_hp_fill.material_override = _bar_material(Color(0.85, 0.15, 0.15))
	_hp_fill.position.z = 0.01
	container.add_child(_hp_fill)


func _bar_material(col: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color  = col
	mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency   = BaseMaterial3D.TRANSPARENCY_ALPHA if col.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.cull_mode      = BaseMaterial3D.CULL_DISABLED
	return mat


func _set_hp_ratio(ratio: float) -> void:
	if not is_instance_valid(_hp_fill):
		return
	ratio = clampf(ratio, 0.0, 1.0)
	_hp_fill.scale.x    = maxf(ratio, 0.001)
	_hp_fill.position.x = -HP_BAR_W * 0.5 * (1.0 - ratio)   # la barre se vide vers la gauche


func setup(instance: PokemonInstance, champion: bool = false, boss: bool = false, demi_boss: bool = false) -> void:
	pokemon_instance = instance
	# Un move SPÉCIAL dans le set → cet ennemi attaque À DISTANCE (projectile,
	# il s'arrête plus loin) ; sinon corps à corps classique.
	for md: MoveData in instance.equipped_moves:
		if md.damage_class == "special" and md.power > 0:
			_ranged_move = md
			break
	is_champion = champion or boss or demi_boss
	is_boss = boss
	is_demi_boss = demi_boss

	# Archétype : les tireurs kitent ; les boss/champions restent des CHASER
	# lisibles ; le reste se répartit chasseur / chargeur / harceleur (tiré par
	# ESPÈCE → un Racaillou se joue toujours pareil, c'est apprenable).
	if _ranged_move != null:
		behavior = Behavior.KITER
	elif is_champion:
		behavior = Behavior.CHASER
	else:
		match abs(hash(instance.data.id)) % 5:
			0: behavior = Behavior.CHARGER
			1: behavior = Behavior.SKIRMISHER
			_: behavior = Behavior.CHASER

	if is_champion:
		var ring_col := Color(1.0, 0.25, 0.15, 0.55)
		if boss:      ring_col = Color(1.0, 0.78, 0.15, 0.65)
		elif demi_boss: ring_col = Color(1.0, 0.12, 0.10, 0.70)
		_add_champion_ring(ring_col)
	if demi_boss:
		_add_red_aura()
	_add_placeholder(Color(0.85, 0.1, 0.1))
	PMDSprites.get_walk_sprites(instance.data.id, self, _on_pmd_loaded)


## Aura rouge pulsante d'un demi-boss de grotte — sphère translucide + halo
## lumineux rouge (le glow de l'Environment la fait rayonner).
func _add_red_aura() -> void:
	var aura := MeshInstance3D.new()
	aura.name = "RedAura"
	var sph := SphereMesh.new()
	sph.radius = 1.2
	sph.height = 2.4
	aura.mesh = sph
	aura.position.y = 1.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.15, 0.10, 0.22)
	mat.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.10, 0.05)
	mat.emission_energy_multiplier = 0.6
	mat.cull_mode = BaseMaterial3D.CULL_FRONT   # vue de l'intérieur → englobe le sprite
	aura.material_override = mat
	aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(aura)

	var light := OmniLight3D.new()
	light.light_color  = Color(1.0, 0.20, 0.12)
	light.light_energy = 1.4
	light.omni_range   = 5.0
	light.position.y   = 1.2
	add_child(light)


## Anneau rouge au sol — signale l'élite d'un coup d'œil, avant même de
## remarquer sa taille.
func _add_champion_ring(ring_color: Color = Color(1.0, 0.25, 0.15, 0.55)) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.72
	torus.outer_radius = 0.85
	ring.mesh = torus
	ring.scale = Vector3(1.0, 0.06, 1.0)
	ring.position.y = 0.03
	var mat := StandardMaterial3D.new()
	mat.albedo_color = ring_color
	mat.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)


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
	sprite.sprite_frames = result.frames
	var frame_size: Vector2i = result.get("frame_size", Vector2i(32, 40))
	var units := DISPLAY_UNITS * (1.7 if is_boss else (1.6 if is_demi_boss else (1.35 if is_champion else 1.0)))
	var ps := units / float(maxi(frame_size.x, 1))
	sprite.pixel_size = ps
	Billboard3D.align_feet(sprite, result, FOOT_LIFT, ps)
	_sprite_base_pos = sprite.position
	sprite.play("idle")
	_remove_placeholder()


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
				sprite.position.y = img.get_height() * ps * 0.5
				_sprite_base_pos = sprite.position
				sprite.play("idle")
				_remove_placeholder()
		http.queue_free()
	)
	http.request(url)


func _remove_placeholder() -> void:
	var ph := get_node_or_null("Placeholder")
	if ph:
		ph.queue_free()


## ── Multijoueur — coquille (clients) ─────────────────────────────────
## L'IA ne tourne que chez l'hôte. Sur les clients, l'ennemi suit la
## position diffusée par l'hôte ; les dégâts locaux lui sont relayés.
var net_shell: bool = false
var net_target: Vector3 = Vector3.ZERO
var _last_attacker_peer: int = 1   # qui a frappé en dernier (cf. take_damage)


func set_net_shell() -> void:
	net_shell = true
	net_target = global_position
	collision_layer = 0
	collision_mask  = 0


## Relais client → hôte : le montant est calculé par l'attaquant local
## (mêmes données de base des deux côtés), l'hôte l'applique pour de vrai.
@rpc("any_peer", "call_remote", "reliable")
func _net_request_damage(amount: int, source_pos: Vector3) -> void:
	if multiplayer.is_server():
		take_damage(amount, source_pos, Color(1.0, 0.95, 0.78), multiplayer.get_remote_sender_id())


## PV diffusés par l'hôte après chaque dégât — flash + barre sur les clients.
@rpc("authority", "call_remote", "reliable")
func _net_hp(hp: int) -> void:
	pokemon_instance.current_hp = hp
	_set_hp_ratio(pokemon_instance.hp_ratio())
	sprite.modulate = Color(2.0, 0.3, 0.3)
	get_tree().create_timer(0.12).timeout.connect(func():
		if is_instance_valid(self):
			sprite.modulate = Color.WHITE
	)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(pokemon_instance) or pokemon_instance.is_fainted():
		return

	if net_shell:
		var to := net_target - global_position
		global_position = global_position.lerp(net_target, minf(1.0, delta * 10.0))
		_update_anim(Vector2(to.x, to.z) if to.length() > 0.08 else Vector2.ZERO)
		return

	_attack_timer = max(0.0, _attack_timer - delta)
	_action_lock  = max(0.0, _action_lock - delta)

	# Altération de statut : dégâts sur la durée + blocage (sommeil/gel)
	if _tick_status(delta):
		velocity = Vector3.ZERO
		return

	_update_grass_hiding()

	# Recul en cours : l'IA lâche les commandes, le corps glisse (move_and_slide
	# gère les collisions) puis la vitesse s'amortit.
	if _knockback_timer > 0.0:
		_knockback_timer -= delta
		velocity = _knockback_vel
		move_and_slide()
		_knockback_vel = _knockback_vel.lerp(Vector3.ZERO, minf(1.0, delta * 12.0))
		position.y = _map.get_height_at_world(global_position) if is_instance_valid(_map) else 0.0
		return

	# Anticipation d'attaque (windup) : l'ennemi est ENGAGÉ — immobile, le
	# coup part à la fin (et RATE si la cible s'est échappée entre-temps).
	# C'est la fenêtre d'esquive du joueur.
	if _windup > 0.0:
		_windup -= delta
		velocity = Vector3.ZERO
		if _windup <= 0.0:
			_finish_windup()
		return

	# RUÉE du chargeur : il glisse vite en ligne droite ; percuter la cible
	# déclenche le coup. Comme le recul, l'IA ne pilote pas pendant ce temps.
	if _charge_timer > 0.0:
		_charge_timer -= delta
		velocity = _charge_dir * CHARGE_SPEED * pokemon_instance.status_speed_mult()
		_update_anim(Vector2(velocity.x, velocity.z))
		move_and_slide()
		position.y = _map.get_height_at_world(global_position) if is_instance_valid(_map) else 0.0
		var hit := _find_target()
		if is_instance_valid(hit) \
				and global_position.distance_to(hit.global_position) <= ATTACK_RANGE * 0.9:
			_charge_timer = 0.0
			_do_attack(hit)
		return

	var target := _find_target()
	if not is_instance_valid(target):
		return

	var dist := global_position.distance_to(target.global_position)

	match behavior:
		Behavior.KITER:      _move_kiter(target, dist, delta)
		Behavior.CHARGER:    _move_charger(target, dist, delta)
		Behavior.SKIRMISHER: _move_skirmisher(target, dist, delta)
		_:                   _move_chaser(target, dist, delta)


## Avance vers `pos` (via l'A* de la map si la vue est bouchée).
func _steer_to(pos: Vector3, delta: float, speed_mult: float = 1.0) -> void:
	var steer_pos := _get_steer_target(pos, delta)
	var dir := (steer_pos - global_position)
	dir.y = 0.0
	dir = dir.normalized()
	velocity = dir * SPEED * speed_mult * pokemon_instance.status_speed_mult()
	_update_anim(Vector2(velocity.x, velocity.z))
	move_and_slide()
	position.y = _map.get_height_at_world(global_position) if is_instance_valid(_map) else 0.0


## S'éloigne en ligne droite de `pos` (pas d'A* : on fuit, on ne contourne pas).
func _flee_from(pos: Vector3, speed_mult: float = 1.0) -> void:
	var away := global_position - pos
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3(1, 0, 0)
	velocity = away * SPEED * speed_mult * pokemon_instance.status_speed_mult()
	_update_anim(Vector2(velocity.x, velocity.z))
	move_and_slide()
	position.y = _map.get_height_at_world(global_position) if is_instance_valid(_map) else 0.0


func _hold_and_attack(target: CharacterBody3D) -> void:
	velocity = Vector3.ZERO
	_update_anim(Vector2.ZERO)
	if _windup <= 0.0 and _attack_timer <= 0.0:
		_start_windup(target)


func _move_chaser(target: CharacterBody3D, dist: float, delta: float) -> void:
	if dist > _attack_range():
		_steer_to(target.global_position, delta)
	else:
		_hold_and_attack(target)


## Tireur : maintient une bande de distance — recule si on le colle, avance
## s'il est trop loin, tire quand il est bien placé.
func _move_kiter(target: CharacterBody3D, dist: float, delta: float) -> void:
	if dist < KITE_MIN:
		_flee_from(target.global_position, 0.95)
	elif dist > _attack_range():
		_steer_to(target.global_position, delta)
	else:
		_hold_and_attack(target)


## Chargeur : au corps à corps il frappe normalement ; à moyenne distance il
## TÉLÉGRAPHE longuement (gros anneau) puis s'élance — c'est esquivable.
func _move_charger(target: CharacterBody3D, dist: float, delta: float) -> void:
	if dist <= ATTACK_RANGE:
		_hold_and_attack(target)
	elif dist < CHARGE_RANGE and _windup <= 0.0 and _attack_timer <= 0.0:
		_charge_pending = true
		_start_windup(target, 2.2)   # anticipation longue = lisible
	else:
		_steer_to(target.global_position, delta, 0.85)


## Harceleur : vif, frappe puis se replie un instant avant de revenir.
func _move_skirmisher(target: CharacterBody3D, dist: float, delta: float) -> void:
	if _retreat_timer > 0.0:
		_retreat_timer -= delta
		if dist < SKIRMISH_RETREAT_DIST:
			_flee_from(target.global_position, 1.1)
		else:
			velocity = Vector3.ZERO
			_update_anim(Vector2.ZERO)
		return
	if dist > ATTACK_RANGE:
		_steer_to(target.global_position, delta, 1.15)
	else:
		_hold_and_attack(target)


var _status_icon: Label3D = null
var _status_shown: String = ""

## Applique le statut : dégâts périodiques + logo flottant. Retourne true si
## bloqué (sommeil/gel).
func _tick_status(delta: float) -> bool:
	var inst := pokemon_instance
	var dot := inst.tick_status(delta)
	if dot > 0:
		inst.take_damage(dot)
		_set_hp_ratio(inst.hp_ratio())
		CombatVFX.spawn_damage_number(get_parent(), global_position, dot, "normal")
		if inst.is_fainted():
			_play_death_anim()
			return true

	if inst.status != _status_shown:
		_status_shown = inst.status
		if is_instance_valid(_status_icon):
			_status_icon.queue_free()
			_status_icon = null
		if inst.status != "":
			_status_icon = StatusFx.make_icon(inst.status)
			_status_icon.position = Vector3(0, 2.6, 0)
			add_child(_status_icon)

	return not inst.status_can_act()


## Renvoie le point vers lequel diriger l'ennemi : ligne droite si la vue est
## dégagée, sinon le prochain point de détour calculé via la grille A* de la map.
func _get_steer_target(target_pos: Vector3, delta: float) -> Vector3:
	_path_repath_timer -= delta
	if _has_clear_line_of_sight(target_pos):
		_path_repath_timer = 0.0   # ligne dégagée — pas besoin de chemin mémorisé
		return target_pos

	if not is_instance_valid(_map):
		return target_pos

	if _path_repath_timer <= 0.0:
		_path_repath_timer = REPATH_INTERVAL
		_path_waypoint = _map.get_next_path_point_3d(global_position, target_pos)

	# Si on est arrivé près du point de détour, on continue tout droit en attendant le recalcul
	if global_position.distance_to(_path_waypoint) < 0.6:
		return target_pos

	return _path_waypoint


func _has_clear_line_of_sight(target_pos: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var lift := Vector3(0, 0.5, 0)
	var query := PhysicsRayQueryParameters3D.create(global_position + lift, target_pos + lift)
	query.collision_mask = 1   # murs/obstacles uniquement
	query.exclude        = [get_rid()]
	var result := space.intersect_ray(query)
	return result.is_empty()


func _get_attack_type() -> String:
	return pokemon_instance.get_attack_type()


# Cible le joueur dont ce Pokémon est super efficace — sinon le plus proche.
# Score = multiplicateur × 44 − distance  (SE = +44 unités de préférence max,
# soit l'équivalent des 700 px de la version 2D)
func _find_target() -> CharacterBody3D:
	var attack_type := _get_attack_type()
	var best: CharacterBody3D = null
	var best_score := -INF

	for p in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(p):
			continue
		if p.pokemon_instance == null or p.pokemon_instance.is_fainted():
			continue
		var mult := DamageCalculator.type_multiplier(attack_type, p.pokemon_instance.data.types)
		if mult <= 0.0:
			continue   # immunité — ne pas cibler
		var dist := global_position.distance_to(p.global_position)
		var score := mult * 44.0 - dist
		if score > best_score:
			best_score = score
			best = p

	# Fallback si tous les joueurs sont immunisés
	if best == null:
		var min_d := INF
		for p in get_tree().get_nodes_in_group("players"):
			if not is_instance_valid(p): continue
			if p.pokemon_instance == null or p.pokemon_instance.is_fainted(): continue
			var d := global_position.distance_to(p.global_position)
			if d < min_d:
				min_d = d
				best = p

	return best


func _update_anim(vel: Vector2) -> void:
	if not sprite.sprite_frames:
		return
	if _action_lock > 0.0:
		return   # animation d'attaque/dégâts en cours
	var anim: String
	if vel.length() < 0.6:
		anim = "idle"
	else:
		anim = Billboard3D.dir_to_anim(vel)

	if anim != _current_anim:
		_current_anim = anim
		if sprite.sprite_frames.has_animation(anim):
			sprite.play(anim)


## Joue la première animation d'action PMD disponible parmi `prefixes`
## (chaîne de repli), orientée vers `dir` (ZERO = orientation courante).
func _play_action_anim(prefixes: Array, dir: Vector2, lock: float) -> void:
	if not sprite.sprite_frames:
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


func _facing_suffix() -> String:
	for s in ["downright", "downleft", "upright", "upleft", "down", "up", "left", "right"]:
		if _current_anim.ends_with(s):
			return s
	return "down"


# ── Anticipation d'attaque (télégraphie) ──────────────────────────────
# Avant CHAQUE coup : l'ennemi se contracte, blanchit progressivement et un
# anneau rouge grandit à ses pieds pendant WINDUP_TIME — le joueur voit le
# coup venir et peut dash hors de portée (l'attaque rate alors).

const WINDUP_TIME := 0.32

var _windup: float = 0.0
var _windup_target: CharacterBody3D = null
var _windup_ring: MeshInstance3D = null


## `mult` allonge l'anticipation (le chargeur télégraphe 2× plus longtemps).
func _start_windup(target: CharacterBody3D, mult: float = 1.0) -> void:
	_windup_target = target
	_windup = WINDUP_TIME * (1.6 if is_boss else (1.25 if is_champion else 1.0)) * mult

	# Contraction + montée de blanc pendant toute l'anticipation
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(sprite, "scale", Vector3(1.14, 0.82, 1.14), _windup * 0.8) \
		.set_ease(Tween.EASE_OUT)
	tw.tween_property(sprite, "modulate", Color(1.7, 1.6, 1.4), _windup * 0.8)

	# Anneau d'alerte au sol qui grandit (plus large et plus long pour un boss)
	_windup_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.30
	torus.outer_radius = 0.44
	_windup_ring.mesh = torus
	_windup_ring.scale = Vector3(0.4, 0.05, 0.4)
	_windup_ring.position = Vector3(0, 0.04, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.22, 0.15, 0.55)
	mat.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	_windup_ring.material_override = mat
	_windup_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_windup_ring)
	var target_s := 2.2 if is_boss else 1.4
	var tw2 := create_tween()
	tw2.tween_property(_windup_ring, "scale", Vector3(target_s, 0.05, target_s), _windup) \
		.set_ease(Tween.EASE_IN)


func _finish_windup() -> void:
	if is_instance_valid(_windup_ring):
		_windup_ring.queue_free()
		_windup_ring = null
	sprite.scale    = Vector3.ONE
	sprite.modulate = Color.WHITE
	_windup = 0.0

	var target := _windup_target
	_windup_target = null

	# Chargeur : la ruée part MÊME DE LOIN (c'est tout son principe) — donc
	# avant le test de portée ci-dessous.
	if _charge_pending:
		_charge_pending = false
		if is_instance_valid(target):
			var d := target.global_position - global_position
			d.y = 0.0
			if d.length() > 0.01:
				_charge_dir   = d.normalized()
				_charge_timer = CHARGE_TIME
				_attack_timer = ATTACK_COOLDOWN
		return

	# La cible s'est échappée pendant l'anticipation → le coup RATE
	# (petit lunge dans le vide pour que l'esquive se lise à l'écran).
	# BUG CORRIGÉ : on comparait à ATTACK_RANGE (2.8) en dur, alors qu'un
	# TIREUR engage depuis RANGED_RANGE (6.5) — son coup était donc TOUJOURS
	# compté comme raté : les attaquants spéciaux ne touchaient jamais.
	if not is_instance_valid(target) \
			or global_position.distance_to(target.global_position) > _attack_range() * 1.35:
		_attack_timer = ATTACK_COOLDOWN * 0.6   # raté = récupération plus courte
		if is_instance_valid(target):
			_play_attack_lunge(target.global_position)
		return
	_do_attack(target)
	if behavior == Behavior.SKIRMISHER:
		_retreat_timer = SKIRMISH_RETREAT_TIME   # frappe → repli


# Move spécial du set (le cas échéant) — l'ennemi devient un TIREUR :
# il s'arrête à RANGED_RANGE et envoie des projectiles (cf. setup).
var _ranged_move: MoveData = null
const RANGED_RANGE := 6.5

## Portée d'engagement effective (tireur ou corps à corps).
func _attack_range() -> float:
	return RANGED_RANGE if _ranged_move != null else ATTACK_RANGE


func _do_attack(target: CharacterBody3D) -> void:
	_attack_timer = ATTACK_COOLDOWN
	var move_type:  String
	var move_power: int
	if _ranged_move != null:
		move_type  = _ranged_move.type
		move_power = _ranged_move.power
	else:
		move_type  = pokemon_instance.get_attack_type()
		move_power = pokemon_instance.get_attack_power()
	var dmg := DamageCalculator.calculate(pokemon_instance, target.pokemon_instance, move_power, move_type)

	# Effets à l'impact (partagés mêlée/projectile)
	var parent := get_parent()
	var tgt := target
	var from := global_position
	var apply_hit := func() -> void:
		if not is_instance_valid(tgt) or not is_instance_valid(parent):
			return
		tgt.take_damage(dmg, from)
		var st := StatusFx.roll(move_type)
		if st != "":
			tgt.pokemon_instance.apply_status(st, StatusFx.duration(st))
		CombatVFX.spawn_damage_number(parent, tgt.global_position, dmg, "player")
		# Secousse caméra seulement quand le Pokémon CONTRÔLÉ encaisse — un
		# compagnon touché à l'autre bout de la map ne doit pas secouer l'écran.
		if tgt.get("is_active") == true:
			get_tree().call_group("combat_arena", "add_camera_shake", 0.12)

	if _ranged_move != null:
		var dir := target.global_position - global_position
		_play_action_anim(["shoot", "charge", "attack"], Vector2(dir.x, dir.z), 0.4)
		Projectile.launch(parent, global_position, target,
			CombatVFX.type_color(move_type), apply_hit, 10.0)
	else:
		apply_hit.call()
		_play_attack_lunge(target.global_position)


func _play_attack_lunge(target_pos: Vector3) -> void:
	var dir := (target_pos - global_position)
	dir.y = 0.0
	dir = dir.normalized()
	_play_action_anim(["attack"], Vector2(dir.x, dir.z), 0.4)
	var tw := create_tween()
	tw.tween_property(sprite, "position", _sprite_base_pos + dir * 0.6, 0.07).set_ease(Tween.EASE_OUT)
	tw.tween_property(sprite, "position", _sprite_base_pos, 0.14).set_ease(Tween.EASE_IN)
	sprite.modulate = Color(2.2, 2.2, 2.2)
	get_tree().create_timer(0.1).timeout.connect(func():
		if is_instance_valid(self):
			sprite.modulate = Color.WHITE
	)


# ── Furtivité dans la haute herbe (embuscade) ─────────────────────────
# Un ennemi dans une case de haute herbe est TOTALEMENT invisible (sprite,
# barre de PV, statut) tant qu'aucun joueur n'est proche — il se révèle en
# approche (GRASS_REVEAL_DIST > portée d'attaque : on le voit toujours
# AVANT qu'il ne frappe, l'embuscade reste équitable). Les boss/champions
# ne se cachent pas (lisibilité des menaces majeures).
const GRASS_REVEAL_DIST := 3.6
var _grass_hidden: bool = false

func _update_grass_hiding() -> void:
	var hidden := false
	if not is_champion and not is_boss \
			and is_instance_valid(_map) and _map.has_method("is_tall_grass_3d") \
			and _map.is_tall_grass_3d(global_position):
		hidden = true
		for p in get_tree().get_nodes_in_group("players"):
			if is_instance_valid(p) \
					and global_position.distance_to(p.global_position) < GRASS_REVEAL_DIST:
				hidden = false
				break
	if hidden != _grass_hidden:
		_grass_hidden = hidden
		visible = not hidden


## `attacker_peer` = peer_id du joueur qui inflige ce coup — retenu pour
## créditer l'XP au bon joueur si ce coup s'avère fatal (cf. signal died).
## Par défaut 1 (hôte) : couvre le solo et les attaques locales de l'hôte,
## qui n'ont pas besoin de préciser leur propre peer_id.
func take_damage(amount: int, source_pos: Vector3 = Vector3(INF, INF, INF),
		tint: Color = Color(1.0, 0.95, 0.78), attacker_peer: int = 1) -> void:
	# Client multijoueur : la coquille ne s'endommage pas elle-même — elle
	# relaie à l'hôte (qui connaît l'expéditeur via get_remote_sender_id,
	# cf. _net_request_damage), qui appliquera et rediffusera les PV (_net_hp).
	if net_shell:
		_net_request_damage.rpc_id(1, amount, source_pos)
		return
	_last_attacker_peer = attacker_peer
	pokemon_instance.take_damage(amount)
	if Net.in_run:
		_net_hp.rpc(pokemon_instance.current_hp)
	_set_hp_ratio(pokemon_instance.hp_ratio())
	_play_action_anim(["hurt"], Vector2.ZERO, 0.3)
	Sfx.play("hit", -4.0)
	sprite.modulate = Color(2.0, 0.3, 0.3)
	get_tree().create_timer(0.12).timeout.connect(func():
		if is_instance_valid(self):
			sprite.modulate = Color.WHITE
	)

	var fatal := pokemon_instance.is_fainted()

	# Impact directionnel : étincelle au point de contact + recul (sauf mort,
	# où l'anim de chute prend le relais). Les gros gabarits encaissent mieux.
	var dir := Vector3.ZERO
	if source_pos.x != INF:
		dir = global_position - source_pos
		dir.y = 0.0
		if dir.length() > 0.01:
			dir = dir.normalized()
			if not fatal:
				var kb := KNOCKBACK_BASE
				if is_boss:        kb *= 0.15
				elif is_champion:  kb *= 0.5
				_knockback_vel   = dir * kb
				_knockback_timer = 0.15
		else:
			dir = Vector3.ZERO
	var impact := global_position + Vector3(0, 0.6, 0) - dir * 0.35
	CombatVFX.spawn_impact(get_parent(), impact, tint)

	# Hit-pause : gel plus long sur le coup fatal (le kill "claque").
	get_tree().call_group("combat_arena", "request_hitstop", 0.09 if fatal else 0.045)

	if fatal:
		_play_death_anim()


func _play_death_anim() -> void:
	set_physics_process(false)
	remove_from_group("enemies")
	# Tué en pleine anticipation : nettoie l'anneau d'alerte et rend le
	# sprite à l'anim de mort (sinon les tweens de windup se battraient avec).
	if is_instance_valid(_windup_ring):
		_windup_ring.queue_free()
		_windup_ring = null
	_windup = 0.0
	sprite.scale = Vector3.ONE
	var bar := get_node_or_null("HPBar")
	if bar:
		bar.visible = false
	Sfx.play("death", -4.0)
	CombatVFX.spawn_death_poof(get_parent(), global_position)
	CombatVFX.spawn_gold_orbs(get_parent(), global_position, randi_range(7, 9) if is_champion else randi_range(3, 5))
	get_tree().call_group("combat_arena", "add_camera_shake", 0.05)
	var xp_reward := pokemon_instance.level * GameManager.XP_MULTIPLIER
	# Chute : s'enfonce dans le sol + fondu rouge
	var tw := create_tween().set_parallel(true)
	tw.tween_property(sprite, "modulate", Color(1.0, 0.2, 0.2, 0.0), 0.5).set_ease(Tween.EASE_IN)
	tw.tween_property(sprite, "position", _sprite_base_pos + Vector3(0, -0.45, 0), 0.4).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func() -> void:
		died.emit(xp_reward, _last_attacker_peer)
		queue_free()
	)
