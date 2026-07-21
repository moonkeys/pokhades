class_name StoryScreen
extends CanvasLayer
## Chronique de la Rébellion — écran narratif du hub. Montre le chapitre courant
## (récit + objectif + avancement), le rang de rébellion et les dresseurs
## vaincus. Purement contemplatif : aucune action, juste « fermer ». Même kit
## visuel que tous les autres écrans du hub (UiKit).

signal closed

const C_DIM   := Color(0.62, 0.55, 0.42)
const C_GOLD  := Color(0.95, 0.76, 0.31)
const C_CREAM := Color(0.96, 0.90, 0.78)
const C_GOOD  := Color(0.42, 0.82, 0.48)
const C_BAR_BG := Color(0, 0, 0, 0.45)


func _ready() -> void:
	add_child(MenuNav.make(func() -> void: closed.emit()))
	_build()
	MenuNav.focus_first(self)


func _build() -> void:
	var veil := ColorRect.new()
	veil.color = Color(0.04, 0.05, 0.03, 0.45)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(veil)

	var panel := UiKit.main_panel(Vector2(300, 70), Vector2(680, 580))
	add_child(panel)
	UiKit.banner(panel, "Chronique de la Rébellion")
	UiKit.pop_in(panel)

	# ── Rang de rébellion ───────────────────────────────────────────────
	var rk := StoryManager.rank()
	var size := StoryManager.rebellion_size()
	UiKit.label(panel, "★  %s" % str(rk["name"]).to_upper(), Vector2(28, 70), 22, C_GOLD, 420)
	UiKit.label(panel, "%d Pokémon libéré%s" % [size, "s" if size != 1 else ""],
		Vector2(28, 104), 15, C_CREAM, 420)
	UiKit.label(panel, str(rk["perk"]), Vector2(28, 128), 13, C_DIM, 620, HORIZONTAL_ALIGNMENT_LEFT, true)

	# Progression vers le prochain rang (barre).
	_rank_bar(panel, 28, 158, 624, size)

	# ── Chapitre courant ────────────────────────────────────────────────
	var card := UiKit.dark_card(panel, Vector2(28, 196), Vector2(624, 250))
	if StoryManager.is_finished():
		UiKit.label(card, "ÉPILOGUE", Vector2(20, 16), 13, C_GOLD, 580)
		UiKit.label(card, "Un Monde Libre", Vector2(20, 36), 22, C_CREAM, 580)
		UiKit.label(card,
			"La Ligue est tombée. Les Pokémon choisissent désormais leur destin : "
			+ "suivre un dresseur… ou vivre libres. La rébellion a gagné — mais "
			+ "chaque nouveau libéré fait vivre ce monde un peu plus.",
			Vector2(20, 76), 15, C_CREAM, 584, HORIZONTAL_ALIGNMENT_LEFT, true)
	else:
		var idx := StoryManager.current_chapter
		var ch := StoryManager.chapter()
		StoryManager.mark_intro_seen(idx)
		UiKit.label(card, "CHAPITRE %d" % (idx + 1), Vector2(20, 16), 13, C_GOLD, 580)
		UiKit.label(card, str(ch["title"]), Vector2(20, 36), 22, C_CREAM, 580)
		UiKit.label(card, str(ch["intro"]), Vector2(20, 76), 15, C_CREAM, 584,
			HORIZONTAL_ALIGNMENT_LEFT, true)

		# Objectif + avancement.
		var prog := StoryManager.objective_progress()
		var done: bool = prog["done"]
		var obj_col := C_GOOD if done else C_GOLD
		UiKit.label(card, "OBJECTIF", Vector2(20, 168), 12, C_DIM, 580)
		UiKit.label(card, str(ch["objective"]), Vector2(20, 186), 14, C_CREAM, 584,
			HORIZONTAL_ALIGNMENT_LEFT, true)
		var pct: String = "  ✔ Accompli !" if done else "   %d / %d" % [prog["current"], prog["target"]]
		UiKit.label(card, pct, Vector2(430, 168), 15, obj_col, 174, HORIZONTAL_ALIGNMENT_RIGHT)
		_obj_bar(card, 20, 222, 584, float(prog["current"]) / maxf(1.0, float(prog["target"])), obj_col)

	# ── Dresseurs vaincus ───────────────────────────────────────────────
	var badges := GameManager.champion_badges
	var badge_txt := "Aucun dresseur vaincu — le système tient encore." if badges.is_empty() \
		else "Dresseurs vaincus : " + ", ".join(badges)
	UiKit.label(panel, "🎖  " + badge_txt, Vector2(28, 460), 13, C_DIM, 624,
		HORIZONTAL_ALIGNMENT_LEFT, true)

	var close := UiKit.button("✕  Fermer", Vector2(200, 44), false)
	close.position = Vector2(240, 512)
	close.pressed.connect(func() -> void: closed.emit())
	panel.add_child(close)


## Barre de progression vers le prochain palier de rang.
func _rank_bar(parent: Control, x: float, y: float, w: float, size: int) -> void:
	var ranks := StoryManager.RANKS
	var i := StoryManager.rank_index()
	var lo := int(ranks[i]["min"])
	var hi := int(ranks[i + 1]["min"]) if i + 1 < ranks.size() else lo
	var frac := 1.0
	var caption := "Rang maximal atteint"
	if hi > lo:
		frac = clampf(float(size - lo) / float(hi - lo), 0.0, 1.0)
		caption = "Prochain rang : %s  (%d / %d)" % [str(ranks[i + 1]["name"]), size, hi]
	_bar(parent, x, y, w, frac, C_GOLD)
	UiKit.label(parent, caption, Vector2(x, y + 16), 11, C_DIM, w)


func _obj_bar(parent: Control, x: float, y: float, w: float, frac: float, col: Color) -> void:
	_bar(parent, x, y, w, clampf(frac, 0.0, 1.0), col)


func _bar(parent: Control, x: float, y: float, w: float, frac: float, col: Color) -> void:
	var bg := ColorRect.new()
	bg.position = Vector2(x, y)
	bg.size = Vector2(w, 10)
	bg.color = C_BAR_BG
	parent.add_child(bg)
	var fill := ColorRect.new()
	fill.position = Vector2(x, y)
	fill.size = Vector2(maxf(2.0, w * clampf(frac, 0.0, 1.0)), 10)
	fill.color = col
	parent.add_child(fill)
