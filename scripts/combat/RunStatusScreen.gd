class_name RunStatusScreen
extends CanvasLayer

## Écran de fin de salle — BOUTIQUE EN RUN : l'équipe est affichée en haut,
## et une grille d'améliorations/soins achetables avec les Pokédollars ₽
## accumulés occupe le centre. Achats multiples ; « Continuer » poursuit la
## run. CombatArena applique chaque achat (cf. _apply_bonus) et rafraîchit
## le solde/les cartes via refresh().

signal purchase(item_id: String)   # émis à chaque achat (CombatArena débite ₽ + applique)
signal continued                   # « Continuer » — poursuivre la run

const C_BG     := Color(0.08, 0.06, 0.03, 0.92)
const C_CARD   := Color(0.14, 0.11, 0.07, 0.95)
const C_GOLD   := Color(0.88, 0.72, 0.25)
const C_TEXT   := Color(0.94, 0.88, 0.72)
const C_DIM    := Color(0.58, 0.50, 0.36)
const C_HP_OK  := Color(0.30, 0.85, 0.40)
const C_HP_LOW := Color(0.90, 0.55, 0.15)
const C_HP_KO  := Color(0.75, 0.20, 0.20)
const C_BOOST  := Color(0.45, 0.90, 0.55)

var _team: Array = []
var _gold_earned: int = 0
var _root: Control = null


func setup(team: Array, gold_earned: int, _offers: Array = []) -> void:
	layer = 22
	_team = team
	_gold_earned = gold_earned
	_rebuild()


## Reconstruit tout l'écran (après un achat : PV/solde à jour).
func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	_root = _bg_panel()

	# ── Titre + bourse ────────────────────────────────────────────────────
	_label(_root, "✦  Salle libérée  ✦",
		Vector2(640, 26), 26, C_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_label(_root, "Gagné : +%d ₽      Bourse : %d ₽" % [_gold_earned, GameManager.run_money],
		Vector2(640, 62), 17, C_GOLD.lightened(0.3), HORIZONTAL_ALIGNMENT_CENTER)

	# ── Cartes membres (compactes, une rangée) ────────────────────────────
	var live: Array = []
	for m in _team:
		if is_instance_valid(m):
			live.append(m)

	var card_w := 232.0
	var card_h := 96.0
	var cols   := mini(maxi(live.size(), 1), 5)
	var gap    := (1280.0 - cols * card_w) / (cols + 1)
	for i in live.size():
		var inst: PokemonInstance = live[i].pokemon_instance
		var col := i % cols
		var row := i / cols
		var cx  := gap + col * (card_w + gap)
		var cy  := 92.0 + row * (card_h + 10)
		_build_card(_root, inst, Vector2(cx, cy), card_w, card_h)

	# (Plus de boutique ici : les achats se font désormais dans la salle-BOUTIQUE
	# dédiée, chez le Perrserker — évite le doublon en fin de chaque salle.)
	_label(_root, "Choisis une sortie pour continuer la run.", Vector2(640, 340), 16, C_DIM,
		HORIZONTAL_ALIGNMENT_CENTER)

	# ── Continuer ─────────────────────────────────────────────────────────
	var cont := Button.new()
	cont.text     = "Continuer  →"
	cont.position = Vector2(520, 636)
	cont.size     = Vector2(240, 58)
	cont.add_theme_font_size_override("font_size", 22)
	cont.add_theme_color_override("font_color",       C_TEXT)
	cont.add_theme_color_override("font_hover_color", C_GOLD)
	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(0.22, 0.17, 0.09); sn.border_color = C_GOLD
	sn.set_border_width_all(2); sn.set_corner_radius_all(12)
	var sh := sn.duplicate() as StyleBoxFlat
	sh.bg_color = Color(0.30, 0.24, 0.12)
	cont.add_theme_stylebox_override("normal", sn)
	cont.add_theme_stylebox_override("hover",  sh)
	cont.add_theme_stylebox_override("pressed", sh)
	cont.pressed.connect(func() -> void: continued.emit())
	_root.add_child(cont)


func _build_shop_card(parent: Node, it: Dictionary, pos: Vector2, w: float, h: float) -> void:
	var price: int = int(it["price"])
	var afford := GameManager.run_money >= price

	var card := Panel.new()
	card.position = pos
	card.size     = Vector2(w, h)
	var st := StyleBoxFlat.new()
	st.bg_color = C_CARD if afford else Color(0.11, 0.09, 0.06, 0.95)
	st.border_color = (it["col"] as Color) if afford else C_DIM
	st.set_border_width_all(2); st.set_corner_radius_all(8)
	card.add_theme_stylebox_override("panel", st)
	parent.add_child(card)

	_label(card, "%s  %s" % [it["sym"], it["label"]], Vector2(12, 10), 15,
		C_TEXT if afford else C_DIM)
	_label(card, "%d ₽" % price, Vector2(12, 36), 16, C_GOLD if afford else C_DIM)

	var btn := Button.new()
	btn.text     = "Acheter"
	btn.position = Vector2(w - 104, 52)
	btn.size     = Vector2(92, 30)
	btn.disabled = not afford
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", C_GOLD if afford else C_DIM)
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.22, 0.17, 0.09); bs.border_color = it["col"] if afford else C_DIM
	bs.set_border_width_all(2); bs.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", bs)
	btn.add_theme_stylebox_override("hover",  bs)
	var cap_id: String = it["id"]
	btn.pressed.connect(func() -> void: purchase.emit(cap_id))
	card.add_child(btn)


## Appelé par CombatArena après un achat traité — reconstruit avec les
## nouvelles valeurs (solde ₽, PV soignés…).
func refresh() -> void:
	_rebuild()


func _bg_panel() -> Control:
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	return bg


func _build_card(parent: Node, inst: PokemonInstance, pos: Vector2,
		w: float, h: float) -> void:
	var card := Panel.new()
	card.position = pos
	card.size     = Vector2(w, h)
	var st := StyleBoxFlat.new()
	st.bg_color = C_CARD
	st.border_color = C_GOLD.darkened(0.3)
	st.set_border_width_all(1); st.set_corner_radius_all(8)
	card.add_theme_stylebox_override("panel", st)
	parent.add_child(card)

	var fainted := inst.is_fainted()

	if is_instance_valid(inst.portrait_texture):
		var tex := TextureRect.new()
		tex.texture      = inst.portrait_texture
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.position     = Vector2(4, 4)
		tex.size         = Vector2(66, 66)
		tex.modulate.a   = 0.5 if fainted else 1.0
		card.add_child(tex)

	var tx := 78.0
	var name_col := C_HP_KO if fainted else C_TEXT
	_label(card, inst.data.name_fr.capitalize() + ("  [KO]" if fainted else ""),
		Vector2(tx, 8), 15, name_col)
	_label(card, "Niv. %d" % inst.level, Vector2(tx, 28), 12, C_DIM)

	var ratio   := inst.hp_ratio()
	var bar_col := C_HP_OK if ratio > 0.5 else (C_HP_LOW if ratio > 0.2 else C_HP_KO)
	_draw_bar(card, Vector2(tx, 50), w - tx - 12.0, 11, ratio, bar_col)
	_label(card, "%d / %d PV" % [inst.current_hp, inst.max_hp], Vector2(tx, 62), 11, C_DIM)

	var boosts: Array[String] = []
	if inst.attack_mult  > 1.05: boosts.append("ATQ×%.1f" % inst.attack_mult)
	if inst.defense_mult > 1.05: boosts.append("DÉF×%.1f" % inst.defense_mult)
	if inst.speed_mult   > 1.05: boosts.append("VIT×%.1f" % inst.speed_mult)
	if not boosts.is_empty():
		_label(card, "✦ " + " ".join(boosts), Vector2(4, 78), 11, C_BOOST)


func _draw_bar(parent: Node, pos: Vector2, w: float, h: float,
		ratio: float, col: Color) -> void:
	var bg := ColorRect.new()
	bg.color    = Color(0.18, 0.14, 0.08)
	bg.position = pos
	bg.size     = Vector2(w, h)
	parent.add_child(bg)
	var fill := ColorRect.new()
	fill.color    = col
	fill.position = pos + Vector2(1, 1)
	fill.size     = Vector2(maxf(0.0, (w - 2) * ratio), h - 2)
	parent.add_child(fill)


func _label(parent: Node, text: String, pos: Vector2,
		font_size: int, col: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text     = text
	l.position = pos
	l.size     = Vector2(600, 40)
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		l.position.x -= 300
		l.size.x      = 1280
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	parent.add_child(l)
	return l
