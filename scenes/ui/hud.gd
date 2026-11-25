class_name HUD
extends CanvasLayer
## On-screen info: wallet, day/time, speedometer, fuel, health, prompts, toasts, help.
## Built in code so it's easy to read. Layout:
##   top-left: wallet + day/time        top-right: controls help (F1)
##   center:   toast messages
##   bottom:   interaction prompt, health (left), speedometer + fuel (right)

const PANEL_BG := Color(0.07, 0.09, 0.13, 0.72)
const ACCENT := Color("#14a39a")   # Sakay teal
const MONEY_COLOR := Color("#ffd166")

const HELP_TEXT := """CONTROLS
On foot
  WASD  walk      Shift  run
  Mouse  look     F  get on motor
  E  interact
On motor
  W  gas          S  brake / reverse
  A / D  steer    Space  handbrake
  H  horn         F  get off (when stopped)
Camera
  C  change view  Mouse  look around
Other
  F1  hide this   Esc  free the mouse
  F8  respawn at home
Gamepad
  LS move/steer  RT gas  LT brake
  Y get on/off   A interact  RB handbrake"""

var _money_label: Label
var _clock_label: Label
var _toast_label: Label
var _prompt_label: Label
var _prompt_panel: PanelContainer
var _help_panel: PanelContainer
var _help_hint: PanelContainer
var _vehicle_panel: PanelContainer
var _speed_label: Label
var _motor_label: Label
var _fuel_bar: ProgressBar
var _fuel_fill: StyleBoxFlat
var _status_label: Label
var _health_panel: PanelContainer
var _health_bar: ProgressBar
var _toast_time := 0.0


func _ready() -> void:
	layer = 10
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)

	var column := VBoxContainer.new()
	margin.add_child(column)

	# --- Top row ---
	var top := HBoxContainer.new()
	column.add_child(top)
	var wallet := _panel(top)
	wallet.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var wallet_box := VBoxContainer.new()
	wallet.add_child(wallet_box)
	_money_label = _label(wallet_box, "₱0", 30, MONEY_COLOR)
	_clock_label = _label(wallet_box, "Day 1 · 7:00 AM", 18, Color.WHITE)
	_spacer(top, true)
	_help_panel = _panel(top)
	_label(_help_panel, HELP_TEXT, 14, Color(0.92, 0.95, 1.0))
	_help_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_help_hint = _panel(top)
	_help_hint.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_label(_help_hint, "F1  Controls", 14, Color(0.9, 0.9, 0.9))
	_help_hint.visible = false

	# --- Toast (center) ---
	var toast_center := CenterContainer.new()
	toast_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(toast_center)
	_toast_label = _label(toast_center, "", 22, Color.WHITE)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.modulate.a = 0.0

	# --- Prompt ---
	var prompt_center := CenterContainer.new()
	column.add_child(prompt_center)
	_prompt_panel = _panel(prompt_center)
	_prompt_label = _label(_prompt_panel, "", 20, Color.WHITE)
	_prompt_panel.visible = false

	# --- Bottom row ---
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(bottom)

	_health_panel = _panel(bottom)
	_health_panel.size_flags_vertical = Control.SIZE_SHRINK_END
	var hb := VBoxContainer.new()
	_health_panel.add_child(hb)
	_label(hb, "HEALTH", 13, Color(0.8, 0.85, 0.9))
	_health_bar = _bar(hb, Color("#ef476f"))

	_spacer(bottom, true)

	_vehicle_panel = _panel(bottom)
	var vb := VBoxContainer.new()
	_vehicle_panel.add_child(vb)
	_motor_label = _label(vb, "Motor", 14, Color(0.8, 0.85, 0.9))
	var speed_row := HBoxContainer.new()
	vb.add_child(speed_row)
	_speed_label = _label(speed_row, "0", 44, Color.WHITE)
	var unit := _label(speed_row, " km/h", 18, Color(0.8, 0.85, 0.9))
	unit.size_flags_vertical = Control.SIZE_SHRINK_END
	_label(vb, "FUEL", 13, Color(0.8, 0.85, 0.9))
	_fuel_bar = _bar(vb, ACCENT)
	_fuel_fill = _fuel_bar.get_theme_stylebox("fill") as StyleBoxFlat
	_status_label = _label(vb, "", 13, Color("#ffb4a2"))

	_ignore_mouse(margin)


func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		_toast_label.modulate.a = clampf(_toast_time / 0.5, 0.0, 1.0)   # fade out at the end


# --- Public API (called by the game) -----------------------------------------

func set_money(amount: int) -> void:
	_money_label.text = Economy.format_peso(amount)


func set_clock(day: int, time_text: String) -> void:
	_clock_label.text = "Day %d · %s" % [day, time_text]


func set_prompt(text: String) -> void:
	_prompt_panel.visible = text != ""
	_prompt_label.text = text


func show_toast(text: String, seconds: float = 3.0) -> void:
	_toast_label.text = text
	_toast_time = seconds
	_toast_label.modulate.a = 1.0


func toggle_help() -> void:
	_help_panel.visible = not _help_panel.visible
	_help_hint.visible = not _help_panel.visible


func update_vehicle(is_shown: bool, speed_kmh: float, fuel_ratio: float, motor_name: String, damage: float) -> void:
	_vehicle_panel.visible = is_shown
	if not is_shown:
		return
	_speed_label.text = str(int(round(speed_kmh)))
	_motor_label.text = motor_name.to_upper()
	_fuel_bar.value = fuel_ratio * 100.0
	_fuel_fill.bg_color = Color("#ef476f") if fuel_ratio < 0.2 else ACCENT
	var status := ""
	if fuel_ratio <= 0.0:
		status = "WALA NA GASOLINA! (Out of gas)"
	elif damage >= 1.0:
		status = "Damage %d%%" % int(damage)
	_status_label.text = status
	_status_label.visible = status != ""


func update_health(is_shown: bool, ratio: float) -> void:
	_health_panel.visible = is_shown
	_health_bar.value = ratio * 100.0


# --- Small UI builders -------------------------------------------------------

func _panel(parent: Control) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", sb)
	parent.add_child(p)
	return p


func _label(parent: Control, text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("outline_size", 4)
	parent.add_child(l)
	return l


func _bar(parent: Control, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(220, 12)
	bar.show_percentage = false
	bar.max_value = 100.0
	bar.value = 100.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.15)
	bg.set_corner_radius_all(6)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	parent.add_child(bar)
	return bar


func _spacer(parent: Control, expand: bool) -> void:
	var s := Control.new()
	if expand:
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(s)


## The HUD should never block mouse clicks meant for the game.
func _ignore_mouse(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)
