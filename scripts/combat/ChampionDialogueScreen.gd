class_name ChampionDialogueScreen
extends CanvasLayer

## Boîte de dialogue d'intro d'un combat de boss — le champion s'adresse au
## joueur avant l'arrivée de ses Pokémon. Même kit visuel que tous les menus
## (UiKit : bois sombre, coins dorés) : pas un style à part pour une simple
## réplique. NON BLOQUANTE : le combat démarre en parallèle (cf.
## CombatArena._spawn_room_enemies, qui ne l'attend plus) ; le texte
## s'affiche en machine à écrire puis se referme tout seul.

signal dismissed

const PORTRAIT_SIZE := 128
const CHAR_INTERVAL := 0.022     # machine à écrire : s/caractère
const AUTO_DISMISS_DELAY := 2.2  # secondes de lecture une fois le texte entier affiché

## CHAMPION_TEAMS stocke le type en libellé FR ("Roche") — type_badge()
## attend le slug anglais ("rock") pour retrouver couleur/icône/nom.
const _TYPE_FR_TO_SLUG := {
	"Normal": "normal", "Feu": "fire", "Eau": "water", "Plante": "grass",
	"Électrik": "electric", "Glace": "ice", "Combat": "fighting",
	"Poison": "poison", "Sol": "ground", "Vol": "flying", "Psy": "psychic",
	"Insecte": "bug", "Roche": "rock", "Spectre": "ghost", "Dragon": "dragon",
	"Ténèbres": "dark", "Acier": "steel", "Fée": "fairy",
}


func setup(champ_name: String, champ_type: String) -> void:
	layer = 26
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.45)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	var panel := UiKit.main_panel(Vector2(140, 460), Vector2(1000, 210))
	root.add_child(panel)
	UiKit.pop_in(panel)

	# Portrait du champion — case neutre (bas, colonne 0) de sa planche
	var sprite_path := PokePools.champion_sprite_path(champ_name)
	var port_frame := UiKit.dark_card(panel, Vector2(20, 20), Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE + 40))
	if sprite_path != "":
		var img := Billboard3D.get_tileset_image(sprite_path)
		if img != null:
			var region := Rect2i(0, 0, Billboard3D.TRAINER_FRAME_W, Billboard3D.TRAINER_FRAME_H)
			var tex := ImageTexture.create_from_image(img.get_region(region))
			var tr := TextureRect.new()
			tr.texture         = tex
			tr.stretch_mode    = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.expand_mode     = TextureRect.EXPAND_IGNORE_SIZE
			tr.texture_filter  = CanvasItem.TEXTURE_FILTER_NEAREST
			tr.position        = Vector2(8, 8)
			tr.size            = Vector2(PORTRAIT_SIZE - 16, PORTRAIT_SIZE - 16)
			port_frame.add_child(tr)
	UiKit.label(port_frame, champ_name.to_upper(), Vector2(0, PORTRAIT_SIZE - 4),
		14, UiKit.GOLD, PORTRAIT_SIZE, HORIZONTAL_ALIGNMENT_CENTER)
	var type_slug: String = _TYPE_FR_TO_SLUG.get(champ_type, champ_type.to_lower())
	UiKit.type_badge(port_frame, Vector2((PORTRAIT_SIZE - 90) * 0.5, PORTRAIT_SIZE + 16), type_slug, 20.0)

	# Texte de la réplique — effet machine à écrire, puis fermeture automatique
	var line := PokePools.champion_intro_line(champ_name)
	_full_text = "« %s »" % line
	var text_area := UiKit.dark_card(panel, Vector2(170, 20), Vector2(810, PORTRAIT_SIZE + 40))
	_lbl = UiKit.label(text_area, _full_text, Vector2(20, 16), 18, UiKit.CREAM, 770,
		HORIZONTAL_ALIGNMENT_LEFT, true)
	_lbl.size = Vector2(770, PORTRAIT_SIZE + 8)
	_lbl.clip_text = true   # une réplique trop longue se coupe DANS la boîte
	_lbl.visible_characters = 0

	var hint := UiKit.label(panel, "Appuyer pour passer…",
		Vector2(170, PORTRAIT_SIZE + 46), 13, UiKit.CREAM.darkened(0.2), 600)
	hint.modulate.a = 0.0
	var blink := create_tween().set_loops()
	blink.tween_property(hint, "modulate:a", 1.0, 0.5)
	blink.tween_property(hint, "modulate:a", 0.3, 0.5)

	_type_tween = create_tween()
	_type_tween.tween_property(_lbl, "visible_characters", _full_text.length(),
		_full_text.length() * CHAR_INTERVAL)
	_type_tween.tween_callback(_on_typed_done)

	set_process_unhandled_input(true)


var _lbl: Label = null
var _full_text: String = ""
var _typed: bool = false
var _type_tween: Tween = null


func _on_typed_done() -> void:
	_typed = true
	get_tree().create_timer(AUTO_DISMISS_DELAY).timeout.connect(func() -> void:
		if is_instance_valid(self):
			_dismiss()
	)


func _skip_typing() -> void:
	if is_instance_valid(_type_tween):
		_type_tween.kill()
	if is_instance_valid(_lbl):
		_lbl.visible_characters = _full_text.length()
	_on_typed_done()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		if _typed:
			_dismiss()
		else:
			_skip_typing()


func _dismiss() -> void:
	set_process_unhandled_input(false)
	dismissed.emit()
	queue_free()
