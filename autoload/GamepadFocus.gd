extends Node
## Makes every menu usable with a controller, without changing each menu.
## Godot menus are moved with "focus" (the highlighted button): D-pad/left stick moves it,
## A presses it. But a menu only gets focus if something gives it one. This helper does:
## when you press anything on the controller while a menu is open (mouse cursor visible)
## and nothing is focused, it focuses the top-most visible button.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # also works while the game is paused


func _input(event: InputEvent) -> void:
	var from_pad := event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5)
	if not from_pad:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		return   # playing (mouse captured): controller drives the game, not menus
	var vp := get_viewport()
	var focused := vp.gui_get_focus_owner()
	if focused != null and focused.is_visible_in_tree():
		return
	var button := _last_button(get_tree().root)
	if button != null:
		button.grab_focus()
		vp.set_input_as_handled()   # this press only picks the button; the next one moves/presses


## The last visible, enabled button in the tree = usually the top-most menu (drawn last).
func _last_button(node: Node) -> BaseButton:
	for i in range(node.get_child_count() - 1, -1, -1):
		var child := node.get_child(i)
		if child is CanvasItem and not (child as CanvasItem).visible:
			continue
		var found := _last_button(child)
		if found != null:
			return _first_button_near(found)
	if node is BaseButton and (node as BaseButton).is_visible_in_tree() and not (node as BaseButton).disabled \
			and (node as Control).focus_mode != Control.FOCUS_NONE:
		return node
	return null


## Prefer the first button of the same menu (so focus starts at the top of a list).
func _first_button_near(b: BaseButton) -> BaseButton:
	var parent := b.get_parent()
	if parent == null:
		return b
	for c in parent.get_children():
		if c is BaseButton and (c as BaseButton).is_visible_in_tree() and not (c as BaseButton).disabled \
				and (c as Control).focus_mode != Control.FOCUS_NONE:
			return c
	return b
