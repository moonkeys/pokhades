class_name UiKit
extends RefCounted

## Kit d'interface « bois & parchemin » — le style des mockups utilisateur :
## grand panneau de bois sombre à coins dorés, bannière-titre à étoiles,
## cartes parchemin, boutons verts « Continuer/Apprendre ». Toutes les
## surfaces sont procédurales (StyleBoxFlat) — aucun asset requis.
## À utiliser par TOUS les menus pour un langage visuel unique.

const WOOD       := Color(0.33, 0.22, 0.14)   # panneau principal
const WOOD_DARK  := Color(0.22, 0.14, 0.09)   # bandeaux / encarts sombres
const WOOD_EDGE  := Color(0.14, 0.09, 0.05)   # bordures
const TAN        := Color(0.89, 0.76, 0.53)   # carte parchemin
const TAN_DARK   := Color(0.77, 0.62, 0.40)   # parchemin appuyé/hover
const BROWN_CARD := Color(0.55, 0.38, 0.22)   # carte brune (liste)
const GOLD       := Color(0.95, 0.76, 0.31)
const CREAM      := Color(0.96, 0.90, 0.78)
const TEXT_DARK  := Color(0.28, 0.17, 0.08)
const GREEN      := Color(0.34, 0.69, 0.29)
const GREEN_DARK := Color(0.18, 0.45, 0.16)
const CYAN_SEL   := Color(0.25, 0.88, 0.82)   # surbrillance de sélection
const RED_SOFT   := Color(0.80, 0.33, 0.25)


static func style(bg: Color, border: Color, radius: int = 10, bw: int = 3) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	return s


## Grand panneau de bois à coins dorés (les 4 pastilles des mockups).
static func main_panel(pos: Vector2, size: Vector2) -> Panel:
	var p := Panel.new()
	p.position = pos
	p.size     = size
	p.add_theme_stylebox_override("panel", style(WOOD, WOOD_EDGE, 14, 4))
	for corner in [Vector2(10, 10), Vector2(size.x - 22, 10),
			Vector2(10, size.y - 22), Vector2(size.x - 22, size.y - 22)]:
		var dot := Panel.new()
		dot.position = corner
		dot.size     = Vector2(12, 12)
		dot.add_theme_stylebox_override("panel", style(GOLD, WOOD_EDGE, 6, 2))
		p.add_child(dot)
	return p


## Bannière-titre « ⭐ Titre ⭐ » en tête de panneau.
static func banner(parent: Control, text: String, y: float = 14.0) -> void:
	var w := parent.size.x
	var bar := Panel.new()
	bar.position = Vector2(w * 0.14, y)
	bar.size     = Vector2(w * 0.72, 46)
	bar.add_theme_stylebox_override("panel", style(WOOD_DARK, WOOD_EDGE, 10, 3))
	parent.add_child(bar)
	var l := Label.new()
	l.text = "⭐  %s  ⭐" % text
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 24)
	l.add_theme_color_override("font_color", GOLD)
	bar.add_child(l)


## Carte parchemin (fond clair, liseré brun) — le conteneur standard.
static func card(parent: Control, pos: Vector2, size: Vector2,
		selected: bool = false) -> Panel:
	var c := Panel.new()
	c.position = pos
	c.size     = size
	c.add_theme_stylebox_override("panel",
		style(TAN, CYAN_SEL if selected else WOOD_EDGE, 10, 3 if not selected else 4))
	parent.add_child(c)
	return c


## Encart sombre (instructions, liste) sur le panneau bois.
static func dark_card(parent: Control, pos: Vector2, size: Vector2) -> Panel:
	var c := Panel.new()
	c.position = pos
	c.size     = size
	c.add_theme_stylebox_override("panel", style(BROWN_CARD, WOOD_EDGE, 10, 3))
	parent.add_child(c)
	return c


## Bouton style mockup — vert (action positive) ou parchemin (neutre).
static func button(text: String, size: Vector2, green: bool = true) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.size = size
	var bg     := GREEN if green else TAN
	var bg_hov := GREEN.lightened(0.15) if green else TAN_DARK
	var border := GREEN_DARK if green else WOOD_EDGE
	b.add_theme_stylebox_override("normal",  style(bg, border, 10, 3))
	b.add_theme_stylebox_override("hover",   style(bg_hov, border, 10, 3))
	b.add_theme_stylebox_override("pressed", style(bg.darkened(0.15), border, 10, 3))
	b.add_theme_stylebox_override("disabled", style(bg.darkened(0.35), border.darkened(0.2), 10, 3))
	b.add_theme_stylebox_override("focus",   style(bg_hov, CYAN_SEL, 10, 4))
	b.add_theme_color_override("font_color", Color.WHITE if green else TEXT_DARK)
	b.add_theme_color_override("font_hover_color", Color.WHITE if green else TEXT_DARK)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.45) if green else TEXT_DARK.lightened(0.3))
	b.add_theme_font_size_override("font_size", 17)
	return b


## Petit carré-icône parchemin (symbole/emoji dedans) façon mockup.
static func icon_square(parent: Control, pos: Vector2, sym: String,
		size: float = 44.0, bg: Color = TAN_DARK) -> void:
	var sq := Panel.new()
	sq.position = pos
	sq.size     = Vector2(size, size)
	sq.add_theme_stylebox_override("panel", style(bg, WOOD_EDGE, 8, 3))
	parent.add_child(sq)
	var l := Label.new()
	l.text = sym
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", int(size * 0.5))
	sq.add_child(l)


static func label(parent: Control, text: String, pos: Vector2, fs: int,
		col: Color = TEXT_DARK, w: float = 400.0,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = Vector2(w, fs + 12)
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


## Symbole d'un type d'attaque (icônes des mockups).
const TYPE_SYMS := {
	"normal": "◎", "fire": "🔥", "water": "💧", "grass": "🍃", "electric": "⚡",
	"ice": "❄", "fighting": "🥊", "poison": "☠", "ground": "⛰", "flying": "🪶",
	"psychic": "🌀", "bug": "🐛", "rock": "🪨", "ghost": "👻", "dragon": "🐉",
	"dark": "🌙", "steel": "⚙", "fairy": "✨",
}

static func type_sym(t: String) -> String:
	return TYPE_SYMS.get(t, "◎")
