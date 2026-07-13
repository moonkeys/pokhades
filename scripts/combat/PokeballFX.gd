class_name PokeballFX
extends RefCounted

## Envoi de Pokémon façon dresseur : la pokéball apparaît avec un flash,
## tournoie, s'ouvre (burst de particules + éclat) puis le Pokémon se
## matérialise et la ball disparaît. Assets du pack Essentials
## (Graphics/Battle animations, cf. demande utilisateur). Utilisé par les
## combats de boss (CombatArena._spawn_from_pool en salle de dresseur).

const DIR := "res://Pokemon Essentials v21.1 2023-07-30/Graphics/Battle animations/"
const TEX_BALL      := DIR + "ball_BEASTBALL.png"        # strip 8 frames 32×64
const TEX_BALL_OPEN := DIR + "ball_BEASTBALL_open.png"   # 32×64
const TEX_PARTICLE  := DIR + "ballBurst_particle.png"
const TEX_PARTICLE_S := DIR + "ballBurst_particle_s.png"
const TEX_DAZZLE    := DIR + "ballBurst_dazzle.png"

const SE_THROW := "res://Pokemon Essentials v21.1 2023-07-30/Audio/SE/Battle throw.ogg"
const SE_DROP  := "res://Pokemon Essentials v21.1 2023-07-30/Audio/SE/Battle ball drop.ogg"

const SPIN_TIME := 0.55   # ball fermée qui tournoie avant l'ouverture


## Séquence complète : flash d'apparition → spin → ouverture (burst +
## éclat + `on_open` appelé, le Pokémon apparaît) → la ball s'efface.
static func play_send(parent: Node3D, pos: Vector3, on_open: Callable) -> void:
	var root := Node3D.new()
	root.position = pos
	parent.add_child(root)
	Sfx.play_file(SE_THROW, -4.0)

	var ball := _sprite(TEX_BALL, 0.9)
	ball.hframes = 8
	ball.frame = 0
	root.add_child(ball)

	# Flash d'apparition autour de la ball
	var flash := _sprite(TEX_DAZZLE, 0.9)
	flash.modulate = Color(1.0, 1.0, 0.85, 0.9)
	flash.scale = Vector3.ONE * 0.3
	root.add_child(flash)
	var ftw := flash.create_tween().set_parallel(true)
	ftw.tween_property(flash, "scale", Vector3.ONE * 1.4, 0.22).set_ease(Tween.EASE_OUT)
	ftw.tween_property(flash, "modulate:a", 0.0, 0.26)
	ftw.chain().tween_callback(flash.queue_free)

	# Spin : fait défiler les 8 frames du strip pendant SPIN_TIME
	var spin := ball.create_tween()
	spin.tween_method(func(f: float) -> void:
		if is_instance_valid(ball):
			ball.frame = int(f) % 8
	, 0.0, 16.0, SPIN_TIME)
	spin.tween_callback(func() -> void:
		if not is_instance_valid(root):
			return
		_open(root, ball)
		if on_open.is_valid():
			on_open.call()
	)


## Version instantanée (clients multijoueur : le Pokémon arrive déjà
## matérialisé par l'hôte) — juste le burst d'ouverture au point donné.
static func play_burst(parent: Node3D, pos: Vector3) -> void:
	var root := Node3D.new()
	root.position = pos
	parent.add_child(root)
	_burst(root)
	root.get_tree().create_timer(1.0).timeout.connect(func() -> void:
		if is_instance_valid(root):
			root.queue_free()
	)


static func _open(root: Node3D, ball: Sprite3D) -> void:
	Sfx.play_file(SE_DROP, -4.0)
	ball.texture = load(TEX_BALL_OPEN)
	ball.hframes = 1
	ball.frame = 0
	_burst(root)
	# La ball ouverte s'efface en flottant légèrement vers le haut
	var tw := ball.create_tween().set_parallel(true)
	tw.tween_property(ball, "position:y", ball.position.y + 0.5, 0.45).set_ease(Tween.EASE_OUT)
	tw.tween_property(ball, "modulate:a", 0.0, 0.45)
	tw.chain().tween_callback(func() -> void:
		if is_instance_valid(root):
			root.queue_free()
	)


## Burst d'ouverture : éclat central + particules projetées en couronne.
static func _burst(root: Node3D) -> void:
	var dazzle := _sprite(TEX_DAZZLE, 0.9)
	dazzle.scale = Vector3.ONE * 0.4
	root.add_child(dazzle)
	var dtw := dazzle.create_tween().set_parallel(true)
	dtw.tween_property(dazzle, "scale", Vector3.ONE * 1.8, 0.3).set_ease(Tween.EASE_OUT)
	dtw.tween_property(dazzle, "modulate:a", 0.0, 0.34)
	dtw.chain().tween_callback(dazzle.queue_free)

	for i in 8:
		var p := _sprite(TEX_PARTICLE if i % 2 == 0 else TEX_PARTICLE_S, 0.9)
		p.scale = Vector3.ONE * 0.5
		root.add_child(p)
		var ang := TAU * i / 8.0 + randf_range(-0.2, 0.2)
		var dir := Vector3(cos(ang), randf_range(0.3, 0.9), sin(ang))
		var ptw := p.create_tween().set_parallel(true)
		ptw.tween_property(p, "position", p.position + dir * randf_range(0.9, 1.5), 0.4) \
			.set_ease(Tween.EASE_OUT)
		ptw.tween_property(p, "modulate:a", 0.0, 0.42)
		ptw.chain().tween_callback(p.queue_free)


static func _sprite(tex_path: String, y: float) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture        = load(tex_path)
	s.billboard      = BaseMaterial3D.BILLBOARD_ENABLED
	s.pixel_size     = 0.022
	s.no_depth_test  = true
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.position.y     = y
	s.shaded         = false
	return s
