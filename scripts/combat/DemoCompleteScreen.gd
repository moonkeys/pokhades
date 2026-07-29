class_name DemoCompleteScreen
extends CanvasLayer

## Fin de la démo web (biome 1 nettoyé, boss d'acte vaincu) — pas de retour
## au hub comme _run_victory() : la démo s'arrête là où le contenu gratuit
## s'arrête, avec un renvoi vers le téléchargement du jeu complet.

const DOWNLOAD_URL := "https://moonkeys.github.io/pokhades/"


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true

	var veil := ColorRect.new()
	veil.color = Color(0.04, 0.03, 0.02, 0.85)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)

	var panel := UiKit.main_panel(Vector2(220, 170), Vector2(760, 340))
	add_child(panel)
	UiKit.pop_in(panel)
	UiKit.banner(panel, "MERCI D'AVOIR JOUÉ !")

	UiKit.label(panel, "Tu viens de terminer la démo de Pokhades — le jeu complet\ncontinue avec 3 biomes supplémentaires, le multijoueur en ligne,\nla progression entre les runs et bien plus.",
		Vector2(40, 74), 16, UiKit.TEXT_DARK, 680, HORIZONTAL_ALIGNMENT_CENTER, true)

	var dl := UiKit.button("⬇  Télécharger le jeu complet", Vector2(400, 56))
	dl.position = Vector2(180, 250)
	panel.add_child(dl)
	dl.pressed.connect(_open_download_page)

	Sfx.play("victory")


func _open_download_page() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval(
			"window.open('%s', '_blank')" % DOWNLOAD_URL, true)
	else:
		OS.shell_open(DOWNLOAD_URL)
