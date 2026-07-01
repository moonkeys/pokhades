class_name TypeIcon
extends RefCounted

const TYPE_COLORS: Dictionary = {
	"normal":   Color(0.66, 0.66, 0.60), "fire":     Color(0.95, 0.40, 0.10),
	"water":    Color(0.20, 0.50, 0.92), "electric": Color(0.95, 0.80, 0.08),
	"grass":    Color(0.24, 0.70, 0.24), "ice":      Color(0.55, 0.85, 0.92),
	"fighting": Color(0.80, 0.22, 0.16), "poison":   Color(0.62, 0.22, 0.72),
	"ground":   Color(0.82, 0.66, 0.34), "flying":   Color(0.56, 0.66, 0.94),
	"psychic":  Color(0.93, 0.26, 0.54), "bug":      Color(0.56, 0.70, 0.10),
	"rock":     Color(0.72, 0.60, 0.32), "ghost":    Color(0.42, 0.30, 0.62),
	"dragon":   Color(0.40, 0.24, 0.92), "dark":     Color(0.34, 0.26, 0.22),
	"steel":    Color(0.68, 0.68, 0.78), "fairy":    Color(0.92, 0.52, 0.72),
}

const TYPE_LABELS_FR: Dictionary = {
	"normal": "Normal", "fire": "Feu", "water": "Eau", "electric": "Électrique",
	"grass": "Plante", "ice": "Glace", "fighting": "Combat", "poison": "Poison",
	"ground": "Sol", "flying": "Vol", "psychic": "Psy", "bug": "Insecte",
	"rock": "Roche", "ghost": "Spectre", "dragon": "Dragon", "dark": "Ténèbres",
	"steel": "Acier", "fairy": "Fée",
}


static func color_for(type: String) -> Color:
	return TYPE_COLORS.get(type, Color(0.60, 0.60, 0.58))


static func label_fr(type: String) -> String:
	return TYPE_LABELS_FR.get(type, type.capitalize())


## Badge pilule façon logo officiel — fond coloré, bordure sombre, nom FR en majuscules.
static func make_pill(type: String, w: float = 84.0, h: float = 24.0, font_size: int = 12) -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(w, h)
	root.size = Vector2(w, h)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var col := color_for(type)

	var pill := Panel.new()
	pill.position = Vector2.ZERO
	pill.size     = Vector2(w, h)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color     = col
	sb.border_color = Color(0.05, 0.05, 0.08)
	sb.set_border_width_all(max(2.0, h * 0.11))
	sb.set_corner_radius_all(int(h * 0.5))
	sb.shadow_color = Color(0, 0, 0, 0.30)
	sb.shadow_size  = 2
	pill.add_theme_stylebox_override("panel", sb)
	root.add_child(pill)

	# Reflet glossy
	var gloss := Panel.new()
	gloss.position = Vector2(h * 0.20, h * 0.12)
	gloss.size     = Vector2(max(w - h * 0.4, 4.0), h * 0.32)
	gloss.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gsb := StyleBoxFlat.new()
	gsb.bg_color = Color(1, 1, 1, 0.22)
	gsb.set_corner_radius_all(int(h * 0.3))
	gloss.add_theme_stylebox_override("panel", gsb)
	root.add_child(gloss)

	var lbl := Label.new()
	lbl.text = label_fr(type).to_upper()
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.clip_text = true
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	lbl.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.08))
	lbl.add_theme_constant_override("outline_size", maxi(2, int(font_size * 0.24)))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(lbl)

	return root
