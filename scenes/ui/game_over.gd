class_name GameOver
extends CanvasLayer
## The screen when you die in an accident or a fight. The game is paused behind it; you can
## load your last save or go back to the main menu.

const MENU_SCENE := "res://scenes/main_menu/main_menu.tscn"
const GAME_SCENE := "res://scenes/main/game.tscn"

var reason := ""
var _message: Label


func _init(p_reason: String = "") -> void:
	reason = p_reason
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS   # works while the game is paused


func _ready() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.07, 0.0, 0.0, 0.0)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).tween_property(shade, "color:a", 0.86, 0.8)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	_text(box, "GAME OVER", 64, Color("#ef476f"))
	_text(box, reason, 20, Color(0.92, 0.92, 0.92))
	_text(box, "Day %d" % GameState.day, 15, Color(0.65, 0.68, 0.72))
	# the guilt trip, one line at a time
	var delay := 1.0
	for line: String in guilt_lines():
		var l := _text(box, line, 22, Color(1.0, 0.86, 0.6))
		l.modulate.a = 0.0
		_fade_in(l, delay)
		delay += 1.1
	var slot := GameState.save_slot if GameState.save_slot > 0 and SaveManager.has_save(GameState.save_slot) \
		else SaveManager.latest_slot()
	if slot > 0 and SaveManager.has_save(slot):
		_button(box, "Load last save", func() -> void:
			if SaveManager.load_game(slot):
				_leave(GAME_SCENE)
			else:
				_message.text = "Could not load slot %d." % slot)
	_button(box, "Main menu", func() -> void: _leave(MENU_SCENE))
	for c in box.get_children():
		if c is Button:
			c.modulate.a = 0.0
			_fade_in(c, delay)
	_message = _text(box, "", 14, Color("#ffb4a2"))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## What you left behind. Debt = unpaid boundary rent, or a wallet below zero.
static func guilt_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	var debt := GameState.debt + maxi(-GameState.money, 0)
	if GameState.money > 0:
		lines.append("You died with %s in your pocket." % Economy.format_peso(GameState.money))
	else:
		lines.append("You died without a single peso.")
	lines.append("Was your life worth it?")
	if debt > 0:
		lines.append("Your Nanay is left with your debt of %s." % Economy.format_peso(debt))
	else:
		lines.append("Nanay is still waiting for you to come home.")
	lines.append("Well, anyways... rest in peace.")
	lines.append("Better luck next life.")
	return lines


func _fade_in(item: CanvasItem, delay: float) -> void:
	var t := create_tween()
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_interval(delay)
	t.tween_property(item, "modulate:a", 1.0, 0.7)


func _leave(scene: String) -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(scene)


func _text(parent: Control, text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(300, 46)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(action)
	parent.add_child(b)
