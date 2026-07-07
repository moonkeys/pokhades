class_name ItemRewardScreen
extends CanvasLayer

## Récompense de coffre — habillage « bois & parchemin » (cf. UiKit) :
## l'objet trouvé en bannière, sa description, puis les cartes des membres
## de l'équipe pour choisir QUI le reçoit (flèches + Entrée au clavier).

signal member_chosen(team_index: int)


func setup(item: Dictionary, team: Array) -> void:
	layer = 24

	var veil := ColorRect.new()
	veil.color = Color(0.04, 0.05, 0.03, 0.5)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)

	var live: Array = []
	for m in team:
		if is_instance_valid(m):
			live.append(m)

	var panel := UiKit.main_panel(Vector2(170, 60), Vector2(940, 600))
	add_child(panel)
	UiKit.pop_in(panel)

	var name_str: String = item.get("name_fr", item.get("api_name", "Objet"))
	UiKit.banner(panel, name_str)

	var icon_tex: Texture2D = item.get("icon", null)
	if icon_tex != null and icon_tex.get_height() > 0:
		var tex := TextureRect.new()
		tex.texture      = icon_tex
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tex.position     = Vector2(438, 70)
		tex.size         = Vector2(64, 64)
		panel.add_child(tex)

	var info := UiKit.dark_card(panel, Vector2(120, 142), Vector2(700, 66))
	UiKit.label(info, _describe_item(item), Vector2(0, 10), 15, UiKit.CREAM,
		700, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.label(info, "À qui donner cet objet ?", Vector2(0, 36), 14,
		UiKit.GOLD, 700, HORIZONTAL_ALIGNMENT_CENTER)

	var card_w := 280.0
	var card_h := 168.0
	var cols   := mini(live.size(), 3) if live.size() > 0 else 1
	var pad_x  := (940.0 - cols * card_w) / (cols + 1)
	for i in live.size():
		var m = live[i]
		var cx := pad_x + (i % cols) * (card_w + pad_x)
		var cy := 232.0 + (i / cols) * (card_h + 16.0)
		_build_card(panel, m.pokemon_instance, m.team_index, Vector2(cx, cy), card_w, card_h)

	MenuNav.focus_first(panel)


func _describe_item(item: Dictionary) -> String:
	var mult: float = item.get("mult", 1.0)
	match item.get("effect", ""):
		"atk": return "Objet tenu — Attaque ×%.1f en permanence" % mult
		"def": return "Objet tenu — Défense ×%.1f en permanence" % mult
		"spd": return "Objet tenu — Vitesse ×%.1f en permanence" % mult
		"hp":  return "Consommable — soigne %d%% des PV max immédiatement" % int(mult * 100)
	return ""


func _build_card(parent: Control, inst: PokemonInstance, team_idx: int,
		pos: Vector2, w: float, h: float) -> void:
	var fainted := inst.is_fainted()
	var card := UiKit.card(parent, pos, Vector2(w, h))

	if is_instance_valid(inst.portrait_texture):
		var tex := TextureRect.new()
		tex.texture      = inst.portrait_texture
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.position     = Vector2(8, 8)
		tex.size         = Vector2(56, 56)
		tex.modulate.a   = 0.5 if fainted else 1.0
		card.add_child(tex)

	var tx := 72.0
	var name_col := UiKit.RED_SOFT if fainted else UiKit.TEXT_DARK
	UiKit.label(card, inst.data.name_fr.capitalize() + ("  [KO]" if fainted else ""),
		Vector2(tx, 8), 15, name_col, w - tx - 10)
	UiKit.label(card, "Niv. %d" % inst.level, Vector2(tx, 28), 12,
		UiKit.TEXT_DARK.lightened(0.25), 100)
	if not inst.data.types.is_empty():
		UiKit.type_badge(card, Vector2(tx + 62, 27), inst.data.types[0], 17.0)

	var ratio := inst.hp_ratio()
	var bar_col := UiKit.GREEN if ratio > 0.5 else (Color(0.90, 0.55, 0.15) if ratio > 0.2 else UiKit.RED_SOFT)
	_draw_bar(card, Vector2(tx, 52), w - tx - 12.0, 10, ratio, bar_col)
	UiKit.label(card, "%d / %d PV" % [inst.current_hp, inst.max_hp],
		Vector2(tx, 64), 11, UiKit.TEXT_DARK.lightened(0.25), 160)

	var held_str: String = "Aucun objet"
	if not inst.held_item.is_empty():
		held_str = "Tient : %s" % str(inst.held_item.get("name_fr",
			inst.held_item.get("api_name", "?")))
	UiKit.label(card, held_str, Vector2(10, 92), 11, UiKit.TEXT_DARK.lightened(0.25), w - 20)

	var btn := UiKit.button("K.O." if fainted else
		("Remplacer" if not inst.held_item.is_empty() else "Donner"),
		Vector2(w - 16, 32))
	btn.position = Vector2(8, h - 42)
	btn.disabled = fainted
	var captured_idx: int = team_idx
	btn.pressed.connect(func() -> void: member_chosen.emit(captured_idx))
	card.add_child(btn)


func _draw_bar(parent: Node, pos: Vector2, w: float, h: float,
		ratio: float, col: Color) -> void:
	var bg := ColorRect.new()
	bg.color    = Color(0.25, 0.18, 0.10)
	bg.position = pos
	bg.size     = Vector2(w, h)
	parent.add_child(bg)
	var fill := ColorRect.new()
	fill.color    = col
	fill.position = pos + Vector2(1, 1)
	fill.size     = Vector2(maxf(0.0, (w - 2) * ratio), h - 2)
	parent.add_child(fill)
