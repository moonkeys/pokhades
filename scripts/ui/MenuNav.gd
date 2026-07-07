class_name MenuNav
extends Node

## Navigation clavier des menus : Échap déclenche un callback (fermer /
## revenir en arrière) et le focus initial est posé sur le premier bouton —
## ensuite les FLÈCHES directionnelles naviguent nativement entre les
## boutons (résolution géométrique de Godot) et Entrée/Espace active.
## Usage :
##   add_child(MenuNav.make(func(): closed.emit()))
##   … après chaque (re)construction : MenuNav.focus_first(self)

var _on_cancel: Callable


static func make(on_cancel: Callable) -> MenuNav:
	var n := MenuNav.new()
	n._on_cancel = on_cancel
	return n


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _on_cancel.is_valid():
			_on_cancel.call()


## Pose le focus sur le premier Button activable sous `root` (les flèches
## prennent le relais ensuite). Sans bouton focalisé, la navigation clavier
## de Godot est inerte.
static func focus_first(root: Node) -> void:
	var btn := _find_button(root)
	if btn != null:
		btn.grab_focus.call_deferred()


static func _find_button(n: Node) -> Button:
	if n is Button and not (n as Button).disabled and (n as Button).visible:
		return n
	for c in n.get_children():
		var b := _find_button(c)
		if b != null:
			return b
	return null
