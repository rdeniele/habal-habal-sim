class_name HUD
extends CanvasLayer
## On-screen info: wallet, day/time, speedometer, fuel, health, prompts, toasts, help.
## Built in code so it's easy to read. Layout:
##   top-left: wallet + day/time        top-right: controls help (F1)
##   top-center: GPS arrow to pickup/drop-off
##   center:   toast messages          right: Sakay phone (slides in)
##   bottom:   passenger speech, interaction prompt, health (left), speedometer + fuel (right)

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
  E  refuel (stop at a gas pump)
Sakay app
  Tab  phone      1 / 2  accept / decline
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
var _nav_panel: PanelContainer
var _nav_arrow: NavArrow
var _nav_label: Label
var _dialog_panel: PanelContainer
var _dialog_label: RichTextLabel
var _dialog_time := 0.0

var _objective_panel: PanelContainer
var _objective_title: Label
var _objective_text: Label
var _meter_box: VBoxContainer
var _meter_label: Label
var _meter_bar: ProgressBar
var _meter_fill: StyleBoxFlat
var _fade: ColorRect
var _caption: Label

var phone: Phone
var refuel_menu: RefuelMenu
var dialog_box: DialogBox
var license_card: LicenseCard
var shop: MotorShopUI
var end_of_day: EndOfDayScreen
var pause_menu: PauseMenu


## Small arrow that points toward the GPS target (rotated by the HUD).
class NavArrow extends Control:
	var color := Color.WHITE

	func _init() -> void:
		custom_minimum_size = Vector2(34, 34)
		pivot_offset = Vector2(17, 17)

	func _draw() -> void:
		var c := Vector2(17, 17)
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(0, -15), c + Vector2(11, 11), c + Vector2(0, 5), c + Vector2(-11, 11)]), color)


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
	var left_col := VBoxContainer.new()
	left_col.add_theme_constant_override("separation", 10)
	left_col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(left_col)
	var wallet := _panel(left_col)
	wallet.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var wallet_box := VBoxContainer.new()
	wallet.add_child(wallet_box)
	_money_label = _label(wallet_box, "₱0", 30, MONEY_COLOR)
	_clock_label = _label(wallet_box, "Day 1 · 7:00 AM", 18, Color.WHITE)
	# Objective (story / tutorial steps)
	_objective_panel = _panel(left_col)
	var obj_box := VBoxContainer.new()
	obj_box.custom_minimum_size.x = 320
	_objective_panel.add_child(obj_box)
	_objective_title = _label(obj_box, "", 13, ACCENT.lightened(0.3))
	_objective_text = _label(obj_box, "", 17, Color.WHITE)
	_objective_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective_text.custom_minimum_size.x = 320
	_meter_box = VBoxContainer.new()
	obj_box.add_child(_meter_box)
	_meter_label = _label(_meter_box, "", 13, Color(0.8, 0.85, 0.9))
	_meter_bar = _bar(_meter_box, Color("#2ecc71"))
	_meter_fill = _meter_bar.get_theme_stylebox("fill") as StyleBoxFlat
	_meter_box.visible = false
	_objective_panel.visible = false

	_spacer(top, true)

	# --- Toast (center) ---
	var toast_center := CenterContainer.new()
	toast_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(toast_center)
	_toast_label = _label(toast_center, "", 22, Color.WHITE)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.modulate.a = 0.0

	# --- Passenger speech ---
	var dialog_center := CenterContainer.new()
	column.add_child(dialog_center)
	_dialog_panel = _panel(dialog_center)
	_dialog_label = RichTextLabel.new()
	_dialog_label.bbcode_enabled = true
	_dialog_label.fit_content = true
	_dialog_label.scroll_active = false
	_dialog_label.custom_minimum_size = Vector2(520, 0)
	_dialog_label.add_theme_font_size_override("normal_font_size", 19)
	_dialog_panel.add_child(_dialog_label)
	_dialog_panel.visible = false

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

	# --- GPS (top center, separate layer so it stays centered) ---
	var top_center := CenterContainer.new()
	top_center.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top_center.offset_top = 18
	top_center.offset_bottom = 90
	add_child(top_center)
	_nav_panel = _panel(top_center)
	var nav_row := HBoxContainer.new()
	nav_row.add_theme_constant_override("separation", 10)
	_nav_panel.add_child(nav_row)
	_nav_arrow = NavArrow.new()
	nav_row.add_child(_nav_arrow)
	_nav_label = _label(nav_row, "", 18, Color.WHITE)
	_nav_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_nav_panel.visible = false

	# --- Controls help (top right, overlay so it never pushes other panels) ---
	var help_box := VBoxContainer.new()
	help_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	help_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	help_box.offset_left = -18
	help_box.offset_right = -18
	help_box.offset_top = 18
	add_child(help_box)
	_help_panel = _panel(help_box)
	_label(_help_panel, HELP_TEXT, 13, Color(0.92, 0.95, 1.0))
	_help_hint = _panel(help_box)
	_label(_help_hint, "F1  Controls", 14, Color(0.9, 0.9, 0.9))
	_help_hint.size_flags_horizontal = Control.SIZE_SHRINK_END
	_help_panel.visible = false   # starts hidden: press F1 to show

	_ignore_mouse(margin)
	_ignore_mouse(top_center)
	_ignore_mouse(help_box)

	# --- Interactive UI (these DO take mouse clicks) ---
	phone = Phone.new()
	add_child(phone)
	refuel_menu = RefuelMenu.new()
	add_child(refuel_menu)
	shop = MotorShopUI.new()
	add_child(shop)
	dialog_box = DialogBox.new()
	add_child(dialog_box)
	license_card = LicenseCard.new()
	add_child(license_card)

	# --- Fade to black + big caption (on top of everything) ---
	_fade = ColorRect.new()
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	_caption = Label.new()
	_caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.add_theme_font_size_override("font_size", 34)
	_caption.add_theme_color_override("font_color", Color.WHITE)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.modulate.a = 0.0
	add_child(_caption)

	# --- Full-screen menus (on top of everything) ---
	end_of_day = EndOfDayScreen.new()
	add_child(end_of_day)
	pause_menu = PauseMenu.new()
	add_child(pause_menu)


func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		_toast_label.modulate.a = clampf(_toast_time / 0.5, 0.0, 1.0)   # fade out at the end
	if _dialog_time > 0.0:
		_dialog_time -= delta
		_dialog_panel.visible = _dialog_time > 0.0
	# The phone slides over the help panel, so hide help while the phone is out.
	_help_panel.get_parent().visible = not phone.is_open


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


## GPS arrow + text. `angle` = radians, 0 = straight ahead, positive = to the left.
func set_nav(text: String, color: Color, angle: float) -> void:
	_nav_panel.visible = true
	_nav_label.text = text
	_nav_arrow.color = color
	_nav_arrow.rotation = -angle
	_nav_arrow.queue_redraw()


func hide_nav() -> void:
	_nav_panel.visible = false


## Passenger (or anyone) says something at the bottom of the screen.
func show_dialog(speaker: String, text: String, seconds: float = 4.5) -> void:
	_dialog_label.text = "[color=#7fe3d9][b]%s:[/b][/color]  %s" % [speaker, text]
	_dialog_panel.visible = true
	_dialog_time = seconds


## Story objective in the top-left. Empty text hides it.
func set_objective(title: String, text: String) -> void:
	_objective_panel.visible = text != ""
	_objective_title.text = title.to_upper()
	_objective_text.text = text


## Optional meter under the objective (e.g. passenger comfort). ratio < 0 hides it.
func set_objective_meter(label_text: String, ratio: float) -> void:
	_meter_box.visible = ratio >= 0.0
	_meter_label.text = label_text
	_meter_bar.value = clampf(ratio, 0.0, 1.0) * 100.0
	_meter_fill.bg_color = Color("#2ecc71") if ratio > 0.6 else (Color("#ffd166") if ratio > 0.35 else Color("#ef476f"))


## Fade the screen to black. Use with await.
func fade_out(seconds: float = 0.5) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, seconds)
	await tw.finished


func fade_in(seconds: float = 0.5) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, seconds)
	tw.parallel().tween_property(_caption, "modulate:a", 0.0, seconds)
	await tw.finished


## Big centered text, best shown while faded out.
func show_caption(text: String) -> void:
	_caption.text = text
	var tw := create_tween()
	tw.tween_property(_caption, "modulate:a", 1.0, 0.3)
	await tw.finished


## True when any clickable/blocking UI is open.
func is_menu_open() -> bool:
	return dialog_box.is_open or license_card.visible or shop.visible or refuel_menu.visible \
		or end_of_day.visible or pause_menu.visible or (phone.is_open and phone.has_mouse)


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
		status = "WALA NA GASOLINA! Tulod anay! (Out of gas: push it)"
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
