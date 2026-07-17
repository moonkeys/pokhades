class_name BiomeTestScreen
extends CanvasLayer

## Menu de TEST de biome présenté par Dracolosse (PNJ de départ du hub).
## Choisir un biome lance une run solo forcée sur ce biome pour tous les actes
## (cf. RunManager.test_biome_override) — utilitaire de développement pour
## juger le rendu d'un biome sans dérouler une run complète. Construit avec le
## kit UI partagé (UiKit) pour rester cohérent avec les autres écrans du hub.

signal biome_chosen(theme: int)
signal closed

const DRACOLOSSE_ID := 149

# (theme MapGenerator.MapTheme, libellé FR) — ordre de progression douce → dure.
const BIOMES: Array = [
	[MapGenerator.MapTheme.MEADOW,  "Prairie"],
	[MapGenerator.MapTheme.FOREST,  "Forêt"],
	[MapGenerator.MapTheme.AUTUMN,  "Bois d'automne"],
	[MapGenerator.MapTheme.LAKE,    "Lac"],
	[MapGenerator.MapTheme.SWAMP,   "Marécage"],
	[MapGenerator.MapTheme.ROCKY,   "Montagne"],
	[MapGenerator.MapTheme.VOLCANO, "Volcan"],
	[MapGenerator.MapTheme.VILLAGE, "Village"],
]


func _ready() -> void:
	layer = 30
	add_child(MenuNav.make(func() -> void: closed.emit()))   # Échap = fermer
	_build()
	# Échap fonctionnait déjà, mais SANS focus initial la navigation clavier de
	# Godot est inerte : les flèches n'ont aucun point de départ à partir duquel
	# résoudre le bouton voisin.
	MenuNav.focus_first(self)


func _build() -> void:
	var veil := ColorRect.new()
	veil.color = Color(0.04, 0.05, 0.03, 0.55)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(veil)

	var panel := UiKit.main_panel(Vector2(240, 110), Vector2(800, 540))
	add_child(panel)
	UiKit.banner(panel, "Salle d'entraînement de Dracolosse")
	UiKit.pop_in(panel)
	UiKit.label(panel, "Choisis un biome à tester (run solo forcée)",
		Vector2(0, 66), 14, UiKit.CREAM, 800, HORIZONTAL_ALIGNMENT_CENTER)

	# Sprite animé de Dracolosse (colonne gauche).
	var frame := UiKit.dark_card(panel, Vector2(40, 110), Vector2(230, 300))
	var draco := AnimatedSprite2D.new()
	draco.position = Vector2(115, 170)
	draco.scale = Vector2(3.0, 3.0)
	frame.add_child(draco)
	PMDSprites.get_walk_sprites(DRACOLOSSE_ID, self, func(result: Dictionary) -> void:
		if result.is_empty() or not is_instance_valid(draco):
			return
		var frames: SpriteFrames = result.get("frames")
		if frames == null:
			return
		draco.sprite_frames = frames
		if frames.has_animation("idle"):
			draco.play("idle")
		elif frames.has_animation("walk_down"):
			draco.play("walk_down")
	)
	UiKit.label(frame, "« Quel terrain veux-tu\néprouver, dresseur ? »",
		Vector2(6, 250), 13, UiKit.CREAM, 218, HORIZONTAL_ALIGNMENT_CENTER)

	# Grille de biomes (2 colonnes × 4) — colonne droite.
	var bx := 310.0
	var by := 118.0
	var bw := 220.0
	var bh := 54.0
	var gap := 12.0
	for i in BIOMES.size():
		var theme: int   = BIOMES[i][0]
		var name: String = BIOMES[i][1]
		var col := i % 2
		var row := i / 2
		var btn := UiKit.button(name, Vector2(bw, bh))
		btn.position = Vector2(bx + col * (bw + gap), by + row * (bh + gap))
		var cap := theme
		btn.pressed.connect(func() -> void: biome_chosen.emit(cap))
		panel.add_child(btn)

	var close := UiKit.button("✕  Fermer", Vector2(180, 40), false)
	close.position = Vector2(310, 468)
	close.pressed.connect(func() -> void: closed.emit())
	panel.add_child(close)
