class_name MpDefeatScreen
extends CanvasLayer

## Écran de fin de run en multijoueur (après une défaite) — SEUL L'HÔTE
## choisit la suite pour tout le groupe (cf. réponse produit : plus simple
## et cohérent avec le reste, où l'hôte fait déjà autorité). Les invités
## voient juste un message d'attente ; la décision arrive par RPC
## (Net.request_retry / request_return_hub) et bascule tout le monde.

func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true

	var veil := ColorRect.new()
	veil.color = Color(0.04, 0.03, 0.02, 0.80)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)

	var panel := UiKit.main_panel(Vector2(340, 220), Vector2(600, 280))
	add_child(panel)
	UiKit.pop_in(panel)
	UiKit.banner(panel, "DÉFAITE")

	if Net.is_host():
		UiKit.label(panel, "Que fait l'équipe ?", Vector2(0, 66), 16,
			UiKit.TEXT_DARK, 600, HORIZONTAL_ALIGNMENT_CENTER)

		var retry := UiKit.button("↻  Retenter sa chance", Vector2(440, 60))
		retry.position = Vector2(80, 108)
		panel.add_child(retry)
		retry.pressed.connect(func() -> void:
			get_tree().paused = false
			Net.request_retry()
		)

		var hub := UiKit.button("🏠  Revenir au hub", Vector2(440, 54), false)
		hub.position = Vector2(80, 182)
		panel.add_child(hub)
		hub.pressed.connect(func() -> void:
			get_tree().paused = false
			Net.request_return_hub()
		)
	else:
		UiKit.label(panel, "En attente de la décision de l'hôte…", Vector2(0, 100),
			16, UiKit.TEXT_DARK, 600, HORIZONTAL_ALIGNMENT_CENTER)


func _exit_tree() -> void:
	get_tree().paused = false
