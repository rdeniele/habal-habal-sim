extends Node
## Registers every input action (keyboard, mouse and Xbox gamepad) in code.
## This is like Godot's Project Settings > Input Map, but readable in one file.
## Later we'll add a rebinding menu that changes these at runtime.

const DEADZONE := 0.25


func _enter_tree() -> void:
	# --- On foot movement (also used by menus later) ---
	_keys("move_forward", [KEY_W, KEY_UP])
	_keys("move_back", [KEY_S, KEY_DOWN])
	_keys("move_left", [KEY_A, KEY_LEFT])
	_keys("move_right", [KEY_D, KEY_RIGHT])
	_axis("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_axis("move_back", JOY_AXIS_LEFT_Y, 1.0)
	_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_keys("run", [KEY_SHIFT])
	_buttons("run", [JOY_BUTTON_LEFT_STICK])

	# --- Camera look (mouse look is handled directly in FollowCamera) ---
	_axis("look_left", JOY_AXIS_RIGHT_X, -1.0)
	_axis("look_right", JOY_AXIS_RIGHT_X, 1.0)
	_axis("look_up", JOY_AXIS_RIGHT_Y, -1.0)
	_axis("look_down", JOY_AXIS_RIGHT_Y, 1.0)
	_keys("camera_change", [KEY_C])
	_buttons("camera_change", [JOY_BUTTON_RIGHT_STICK])

	# --- Motorcycle ---
	_keys("accelerate", [KEY_W, KEY_UP])
	_axis("accelerate", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_keys("brake", [KEY_S, KEY_DOWN])
	_axis("brake", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_keys("steer_left", [KEY_A, KEY_LEFT])
	_axis("steer_left", JOY_AXIS_LEFT_X, -1.0)
	_keys("steer_right", [KEY_D, KEY_RIGHT])
	_axis("steer_right", JOY_AXIS_LEFT_X, 1.0)
	_keys("handbrake", [KEY_SPACE])
	_buttons("handbrake", [JOY_BUTTON_RIGHT_SHOULDER])
	_keys("horn", [KEY_H])
	_buttons("horn", [JOY_BUTTON_LEFT_STICK])

	# --- Interaction ---
	_keys("enter_exit", [KEY_F])
	_buttons("enter_exit", [JOY_BUTTON_Y])
	_keys("interact", [KEY_E])
	_buttons("interact", [JOY_BUTTON_A])

	# --- Fighting (used in Milestone 5) ---
	_keys("punch", [KEY_J])
	_mouse("punch", MOUSE_BUTTON_LEFT)
	_buttons("punch", [JOY_BUTTON_X])
	_keys("block", [KEY_K])
	_mouse("block", MOUSE_BUTTON_RIGHT)
	_buttons("block", [JOY_BUTTON_B])
	_keys("dodge", [KEY_L])
	_buttons("dodge", [JOY_BUTTON_RIGHT_SHOULDER])

	# --- Menus / UI ---
	_keys("phone", [KEY_TAB])
	_buttons("phone", [JOY_BUTTON_BACK])
	_keys("map", [KEY_M])
	_keys("pause", [KEY_ESCAPE])
	_buttons("pause", [JOY_BUTTON_START])
	_keys("toggle_help", [KEY_F1])
	# Quick choices: accept/decline bookings, gas amounts
	_keys("option_1", [KEY_1])
	_buttons("option_1", [JOY_BUTTON_DPAD_UP])
	_keys("option_2", [KEY_2])
	_buttons("option_2", [JOY_BUTTON_DPAD_DOWN])
	_keys("option_3", [KEY_3])
	_buttons("option_3", [JOY_BUTTON_DPAD_LEFT])
	_keys("option_4", [KEY_4])
	_buttons("option_4", [JOY_BUTTON_DPAD_RIGHT])
	_keys("option_5", [KEY_5])
	_keys("option_6", [KEY_6])

	# --- Debug (handy while building the game) ---
	_keys("debug_respawn", [KEY_F8])


func _ensure(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, DEADZONE)


func _keys(action: StringName, keys: Array) -> void:
	_ensure(action)
	for k: int in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k as Key  # physical = same position on any keyboard layout
		InputMap.action_add_event(action, ev)


func _mouse(action: StringName, button: MouseButton) -> void:
	_ensure(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


func _buttons(action: StringName, buttons: Array) -> void:
	_ensure(action)
	for b: int in buttons:
		var ev := InputEventJoypadButton.new()
		ev.device = -1  # any controller
		ev.button_index = b as JoyButton
		InputMap.action_add_event(action, ev)


func _axis(action: StringName, axis: JoyAxis, direction: float) -> void:
	_ensure(action)
	var ev := InputEventJoypadMotion.new()
	ev.device = -1
	ev.axis = axis
	ev.axis_value = direction
	InputMap.action_add_event(action, ev)
