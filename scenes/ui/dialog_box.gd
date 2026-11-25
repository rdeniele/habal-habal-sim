class_name DialogBox
extends PanelContainer
## Story dialog at the bottom of the screen. Used with `await`:
##     await dialog.say("Nanay", "Maayong aga, 'Nak!")
##     var pick := await dialog.choose("Nanay", "Ready?", ["Yes", "No"])
##     var player_name := await dialog.ask_text("Clerk", "What's your name?", "Juan")
## Continue with E / Enter / Space / click. Choices with 1 / 2 / 3 or click.

signal advanced
signal chosen(index: int)
signal text_entered(text: String)

const SPEAKER_COLOR := Color("#7fe3d9")

var is_open := false

var _speaker: Label
var _text: Label
var _hint: Label
var _choices: VBoxContainer
var _edit: LineEdit
var _mode := ""
var _opened_msec := 0
var _close_pending := false


func _ready() -> void:
	# Bottom center, grows upward with longer text.
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -390
	offset_right = 390
	offset_top = -160
	offset_bottom = -160
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.12, 0.93)
	sb.set_corner_radius_all(16)
	sb.set_content_margin_all(18)
	sb.border_color = Color("#14a39a")
	sb.border_width_left = 4
	add_theme_stylebox_override("panel", sb)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	_speaker = _make_label(col, 18, SPEAKER_COLOR)
	_text = _make_label(col, 20, Color.WHITE)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size.x = 740
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 6)
	col.add_child(_choices)
	_edit = LineEdit.new()
	_edit.custom_minimum_size = Vector2(360, 40)
	_edit.max_length = 28
	_edit.add_theme_font_size_override("font_size", 20)
	_edit.text_submitted.connect(func(t: String) -> void: _submit_text(t))
	col.add_child(_edit)
	_hint = _make_label(col, 13, Color(0.7, 0.75, 0.8))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	visible = false


# --- Public API (use with await) ---------------------------------------------

func say(speaker: String, text: String) -> void:
	_open("say", speaker, text)
	_hint.text = "▶  E / Enter / click"
	await advanced


func choose(speaker: String, text: String, options: Array) -> int:
	_open("choose", speaker, text)
	_hint.text = "Press 1 / 2 / 3 or click"
	for i in options.size():
		var b := Button.new()
		b.text = "[%d]  %s" % [i + 1, options[i]]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size.y = 38
		b.add_theme_font_size_override("font_size", 17)
		var idx := i
		b.pressed.connect(func() -> void: _pick(idx))
		_choices.add_child(b)
	var picked: int = await chosen
	return picked


func ask_text(speaker: String, text: String, default_text: String) -> String:
	_open("text", speaker, text)
	_hint.text = "Type, then press Enter"
	_edit.visible = true
	_edit.text = default_text
	_edit.grab_focus()
	_edit.select_all()
	var result: String = await text_entered
	return result


# --- Internals ---------------------------------------------------------------

func _open(mode: String, speaker: String, text: String) -> void:
	_mode = mode
	_close_pending = false
	_speaker.text = speaker
	_speaker.visible = speaker != ""
	_text.text = text
	for c in _choices.get_children():
		_choices.remove_child(c)
		c.queue_free()
	_edit.visible = false
	visible = true
	is_open = true
	_opened_msec = Time.get_ticks_msec()


## Close at the end of the frame, unless the next line opens right away (no flicker).
func _finish() -> void:
	_mode = ""
	_close_pending = true


func _process(_delta: float) -> void:
	if _close_pending:
		_close_pending = false
		visible = false
		is_open = false


func _pick(index: int) -> void:
	if _mode != "choose":
		return
	_finish()
	chosen.emit(index)


func _submit_text(t: String) -> void:
	if _mode != "text":
		return
	var cleaned := t.strip_edges()
	if cleaned == "":
		return
	_edit.release_focus()
	_finish()
	text_entered.emit(cleaned)


## Clicking on the dialog panel itself also continues.
func _gui_input(event: InputEvent) -> void:
	if _mode == "say" and event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT and Time.get_ticks_msec() - _opened_msec > 200:
		accept_event()
		_finish()
		advanced.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open or _mode == "":
		return
	# Ignore the same key press that opened the dialog.
	if Time.get_ticks_msec() - _opened_msec < 200:
		if event.is_pressed():
			get_viewport().set_input_as_handled()
		return
	match _mode:
		"say":
			var click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
			if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept") or click:
				get_viewport().set_input_as_handled()
				_finish()
				advanced.emit()
		"choose":
			for i in 3:
				if event.is_action_pressed("option_%d" % (i + 1)) and i < _choices.get_child_count():
					get_viewport().set_input_as_handled()
					_pick(i)
					return
	# While a dialog is open, swallow gameplay keys.
	if event is InputEventKey and event.is_pressed() and _mode != "text":
		get_viewport().set_input_as_handled()


func _make_label(parent: Control, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l
