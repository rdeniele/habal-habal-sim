class_name PauseMenu
extends ColorRect
## Esc menu: Resume, Settings, Save (only at home), Quit to Menu.
## Pauses the whole game (get_tree().paused) while open.

signal save_requested
signal quit_to_menu_requested

## The game sets this every frame: can we save right now? (and why not)
var can_save := false
var save_hint := ""

var _menu: VBoxContainer
var _save_btn: Button
var _info: Label
var _settings: SettingsPanel
var _confirm_quit := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # keeps working while the game is paused
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color(0, 0, 0, 0.6)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.09, 0.13, 0.95)
	sb.set_corner_radius_all(18)
	sb.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(340, 0)
	center.add_child(panel)
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 10)
	panel.add_child(_menu)
	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_size_override("font_size", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu.add_child(title)
	_button("Resume", close)
	_button("Settings", _open_settings)
	_save_btn = _button("Save game", func() -> void: save_requested.emit())
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 13)
	_info.add_theme_color_override("font_color", Color(0.75, 0.8, 0.85))
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size.x = 290
	_menu.add_child(_info)
	_button("Quit to Menu", _quit_pressed)

	_settings = SettingsPanel.new()
	_settings.visible = false
	_settings.closed.connect(_close_settings)
	center.add_child(_settings)


func open() -> void:
	visible = true
	_confirm_quit = false
	_settings.visible = false
	_menu.get_parent().visible = true
	_refresh()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func show_info(text: String) -> void:
	_info.text = text


func _refresh() -> void:
	_save_btn.disabled = not can_save
	_info.text = "Saves to slot %d." % maxi(GameState.save_slot, 1) if can_save else save_hint


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if _settings.visible:
			_close_settings()
		else:
			close()


func _open_settings() -> void:
	_menu.get_parent().visible = false
	_settings.visible = true


func _close_settings() -> void:
	_settings.visible = false
	_menu.get_parent().visible = true


func _quit_pressed() -> void:
	if not _confirm_quit:
		_confirm_quit = true
		_info.text = "Progress since your last save will be lost. Press Quit to Menu again to confirm."
		return
	get_tree().paused = false
	quit_to_menu_requested.emit()


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 42)
	b.add_theme_font_size_override("font_size", 17)
	b.pressed.connect(action)
	_menu.add_child(b)
	return b
