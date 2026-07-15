class_name ControlsScreen
extends CanvasLayer

## Écran des CONTRÔLES : liste toutes les actions du jeu avec leur touche et à
## quoi elles correspondent, et permet de les REMAPPER (clic sur la touche →
## « appuie sur une touche » → capture). Le choix est sauvegardé
## (GameManager.key_bindings) et appliqué immédiatement.
##
## Une touche ne peut pas faire deux choses : si la touche choisie servait déjà
## à une autre action, celle-ci est libérée et signalée.

signal closed

var _listening_for: String = ""   # action en cours de remap ("" = aucune)
var _rows: Dictionary = {}        # action_id → Button (pastille de touche)
var _hint: Label = null
var _panel: Panel = null


func _ready() -> void:
	layer = 40
	add_child(MenuNav.make(func() -> void:
		if _listening_for != "":
			_cancel_listen()
		else:
			closed.emit()
	))
	_build()


func _build() -> void:
	for c in get_children():
		if not (c is MenuNav):
			c.queue_free()
	_rows.clear()

	var veil := ColorRect.new()
	veil.color = Color(0.04, 0.05, 0.03, 0.55)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(veil)

	_panel = UiKit.main_panel(Vector2(220, 40), Vector2(840, 660))
	add_child(_panel)
	UiKit.banner(_panel, "Contrôles")
	UiKit.pop_in(_panel)

	_hint = UiKit.label(_panel,
		"Clique sur une touche pour la réassigner  ·  Échap : annuler",
		Vector2(0, 66), 13, UiKit.CREAM, 840, HORIZONTAL_ALIGNMENT_CENTER)

	# Liste SCROLLABLE : les 15 actions + catégories dépassent la hauteur du
	# panneau (retour joueurs : on ne pouvait pas scroller). ScrollContainer +
	# Control dimensionné au contenu.
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(20, 92)
	scroll.size     = Vector2(800, 496)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	var inner := Control.new()
	scroll.add_child(inner)

	var y := 0.0
	for cat: String in Controls.CATEGORIES:
		UiKit.label(inner, cat.to_upper(), Vector2(16, y), 14, UiKit.GOLD, 300)
		y += 26.0
		for d: Dictionary in Controls.CATALOG:
			if str(d["cat"]) != cat:
				continue
			var id := str(d["id"])
			var card := UiKit.card(inner, Vector2(16, y), Vector2(760, 40))
			UiKit.label(card, str(d["label"]), Vector2(14, 9), 14, UiKit.TEXT_DARK, 560)

			var btn := UiKit.button(Controls.key_name(Controls.key_for(id)),
				Vector2(150, 30), false)
			btn.position = Vector2(596, 5)
			var cap := id
			btn.pressed.connect(func() -> void: _begin_listen(cap))
			card.add_child(btn)
			_rows[id] = btn
			y += 46.0
		y += 8.0
	inner.custom_minimum_size = Vector2(780, y + 8.0)

	var reset := UiKit.button("↺  Réinitialiser", Vector2(190, 40), false)
	reset.position = Vector2(36, 604)
	reset.pressed.connect(func() -> void:
		Controls.reset_defaults()
		_build()
	)
	_panel.add_child(reset)

	var close := UiKit.button("✕  Fermer", Vector2(170, 40), false)
	close.position = Vector2(634, 604)
	close.pressed.connect(func() -> void: closed.emit())
	_panel.add_child(close)


func _begin_listen(id: String) -> void:
	_listening_for = id
	if _rows.has(id):
		(_rows[id] as Button).text = "…"
	_hint.text = "Appuie sur la touche à assigner  ·  Échap : annuler"
	_hint.add_theme_color_override("font_color", UiKit.CYAN_SEL)


func _cancel_listen() -> void:
	_listening_for = ""
	_build()


## Capture la prochaine touche pressée pendant un remap. On passe par
## _input (et non _unhandled_input) pour intercepter AVANT que l'action
## elle-même ne se déclenche.
func _input(event: InputEvent) -> void:
	if _listening_for == "":
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).keycode
	get_viewport().set_input_as_handled()

	if key == KEY_ESCAPE:
		_cancel_listen()
		return

	var id := _listening_for
	_listening_for = ""
	var stolen := Controls.set_binding(id, key)
	_build()
	if stolen != "":
		var lbl := str(Controls.entry(stolen).get("label", stolen))
		_hint.text = "« %s » utilisait cette touche — elle n'a plus de raccourci." % lbl
		_hint.add_theme_color_override("font_color", UiKit.RED_SOFT)
