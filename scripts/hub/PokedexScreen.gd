class_name PokedexScreen
extends CanvasLayer

signal closed

const C_BG      := Color(0.10, 0.08, 0.05, 0.90)
const C_PANEL   := Color(0.91, 0.85, 0.70)
const C_BORDER  := Color(0.62, 0.50, 0.32)
const C_TEXT    := Color(0.18, 0.13, 0.06)
const C_DIM     := Color(0.48, 0.38, 0.22)
const C_GOLD    := Color(0.76, 0.53, 0.17)
const C_GOLD_LT := Color(0.94, 0.88, 0.72)


func _ready() -> void:
	_build()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var panel := Panel.new()
	panel.position = Vector2(100, 50)
	panel.size     = Vector2(1080, 620)
	_style(panel, C_PANEL, C_BORDER, 14)
	add_child(panel)

	# Header
	var hdr := Panel.new()
	hdr.position = Vector2(0, 0)
	hdr.size     = Vector2(1080, 72)
	_style_col(hdr, Color(0.24, 0.18, 0.08), 14, true)
	panel.add_child(hdr)

	_lbl(panel, "⊕  POKÉMON LIBÉRÉS", 24, 14, 700, 44, 24, C_GOLD_LT)

	var count_str := "%d Pokémon dans la Rébellion" % GameManager.unlocked_pokemon.size()
	_lbl(panel, count_str, 700, 22, 360, 28, 16, C_DIM, true)

	# Grille Pokémon
	if GameManager.unlocked_pokemon.is_empty():
		_lbl(panel,
			"Aucun Pokémon libéré pour l'instant.\n\nTermine une run pour en recruter !",
			0, 280, 1080, 80, 18, C_DIM, true)
	else:
		var cw := 188
		var ch := 76
		var gap := 12
		var cols := 5
		var sx := 20
		for i in GameManager.unlocked_pokemon.size():
			var pid: int = GameManager.unlocked_pokemon[i]
			var col: int = i % cols
			var row: int = i / cols
			_build_entry(panel, pid, sx + col * (cw + gap), 90 + row * (ch + gap), cw, ch)

	# Progression slots équipe
	var n := GameManager.unlocked_pokemon.size()
	var next := GameManager.get_next_unlock_threshold()
	var prg_str := "Prochain slot d'équipe à %d Pokémon libérés  (%d / %d)" % [next, n, next]
	_lbl(panel, prg_str, 0, 562, 1080, 24, 14, C_DIM, true)

	var close := Button.new()
	close.text     = "✕  Fermer"
	close.position = Vector2(24, 556)
	close.size     = Vector2(160, 40)
	close.add_theme_font_size_override("font_size", 15)
	close.add_theme_color_override("font_color", C_DIM)
	_btn_neutral(close)
	close.pressed.connect(func() -> void: closed.emit())
	panel.add_child(close)


func _build_entry(parent: Panel, pid: int, x: int, y: int, w: int, h: int) -> void:
	var card := Panel.new()
	card.position = Vector2(x, y)
	card.size     = Vector2(w, h)
	_style(card, Color(0.86, 0.80, 0.65), C_BORDER, 8)
	parent.add_child(card)

	var ph := ColorRect.new()
	ph.position = Vector2(6, 6)
	ph.size     = Vector2(56, 56)
	ph.color    = Color(0.74, 0.66, 0.50)
	card.add_child(ph)

	_lbl(card, "#%d" % pid, 68, 10, w - 74, 20, 14, C_GOLD)
	_lbl(card, "Pokémon libéré", 68, 34, w - 74, 18, 12, C_DIM)


# ── Helpers ───────────────────────────────────────────────────────────

func _lbl(parent: Node, text: String, x: float, y: float, w: float, h: float,
		fs: int, color: Color, centered: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.position = Vector2(x, y)
	l.size     = Vector2(w, h)
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if centered:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l


func _style(p: Panel, bg: Color, border: Color, radius: int) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = bg; s.border_color = border
	s.set_border_width_all(2 if border != Color.TRANSPARENT else 0)
	s.set_corner_radius_all(radius)
	s.shadow_color = Color(0, 0, 0, 0.14); s.shadow_size = 3
	p.add_theme_stylebox_override("panel", s)


func _style_col(p: Panel, bg: Color, radius: int, top_only: bool = false) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	if top_only:
		s.corner_radius_top_left = radius; s.corner_radius_top_right = radius
	else:
		s.set_corner_radius_all(radius)
	p.add_theme_stylebox_override("panel", s)


func _btn_neutral(btn: Button) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.74, 0.66, 0.52); s.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = Color(0.82, 0.74, 0.60)
	btn.add_theme_stylebox_override("hover", sh)
