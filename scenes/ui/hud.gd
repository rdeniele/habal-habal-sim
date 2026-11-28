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
  Ctrl (hold)  crouch / sneak
  E  lift or pet a dog / cat
  1  adopt    2  put down
  Mouse  look     F  get on motor
  E  interact
On motor
  W  gas          S  brake / reverse
  A / D  steer    Space  handbrake
  H  horn         F  get off (when stopped)
  E  refuel (stop at a gas pump)
Sakay app
  Tab  phone      1 / 2  accept / decline
Map & needs
  M  full map (click: pin a place, right click: remove)
  E  buy food at sari-sari
  Stand still on foot to rest (energy)
Fight
  J / LMB punch   K / RMB block   L dodge
Camera
  C  change view (starts in first person)
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
var _status_label: Label
var _light_label: Label
var _health_panel: PanelContainer
var _health_bar: ProgressBar
var _food_bar: ProgressBar
var _water_bar: ProgressBar
var _energy_bar: ProgressBar
var _gas_bar: ProgressBar
var _gas_row: Control
var _gas_text: Label
var _resting_label: Label
var _full_map_layer: ColorRect

var minimap: Minimap
var full_map: Minimap
var food_menu: FoodMenu
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
var _wanted_label: Label
var _wanted := 0
var _wanted_panel: PanelContainer
var _offense_label: Label
var _pull_over_label: Label
var _fight_panel: PanelContainer
var _fight_you: ProgressBar
var _fight_them: ProgressBar
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

	# Minimap (bottom-left)
	minimap = Minimap.new()
	minimap.custom_minimum_size = Vector2(200, 200)
	minimap.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.add_child(minimap)

	# Body needs: health, food, water, energy
	_health_panel = _panel(bottom)
	_health_panel.size_flags_vertical = Control.SIZE_SHRINK_END
	var hb := VBoxContainer.new()
	hb.add_theme_constant_override("separation", 2)
	_health_panel.add_child(hb)
	_health_bar = _need_bar(hb, "HEALTH", Color("#ef476f"))
	_food_bar = _need_bar(hb, "FOOD", Color("#f4a261"))
	_water_bar = _need_bar(hb, "WATER", Color("#4cc9f0"))
	_energy_bar = _need_bar(hb, "ENERGY", Color("#ffd166"))
	# your motor's gas, visible on foot too
	_gas_bar = _need_bar(hb, "GAS", ACCENT)
	_gas_row = _gas_bar.get_parent() as Control
	_gas_text = _label(hb, "", 12, Color(0.85, 0.9, 0.95))
	_resting_label = _label(hb, "Resting...  (energy coming back)", 12, Color("#b8f2e6"))
	_resting_label.visible = false

	_spacer(bottom, true)

	_vehicle_panel = _panel(bottom)
	_vehicle_panel.size_flags_vertical = Control.SIZE_SHRINK_END
	var vb := VBoxContainer.new()
	_vehicle_panel.add_child(vb)
	_motor_label = _label(vb, "Motor", 14, Color(0.8, 0.85, 0.9))
	var speed_row := HBoxContainer.new()
	vb.add_child(speed_row)
	_speed_label = _label(speed_row, "0", 44, Color.WHITE)
	var unit := _label(speed_row, " km/h", 18, Color(0.8, 0.85, 0.9))
	unit.size_flags_vertical = Control.SIZE_SHRINK_END
	_status_label = _label(vb, "", 13, Color("#ffb4a2"))
	_light_label = _label(vb, "", 15, Color.WHITE)
	_light_label.visible = false

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

	# --- Wanted stars + offenses, and the enforcer pull-over timer (top center, under the GPS) ---
	var wanted_center := CenterContainer.new()
	wanted_center.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	wanted_center.offset_top = 80
	wanted_center.offset_bottom = 200
	add_child(wanted_center)
	var wanted_col := VBoxContainer.new()
	wanted_col.alignment = BoxContainer.ALIGNMENT_BEGIN
	wanted_center.add_child(wanted_col)
	_wanted_panel = _panel(wanted_col)
	var wv := VBoxContainer.new()
	wv.add_theme_constant_override("separation", 0)
	_wanted_panel.add_child(wv)
	_wanted_label = _label(wv, "", 30, Color("#ffd23f"))
	_wanted_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_offense_label = _label(wv, "", 14, Color("#ffb4a2"))
	_offense_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wanted_panel.visible = false
	_pull_over_label = _label(wanted_col, "", 20, Color("#d4ff3a"))
	_pull_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pull_over_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_pull_over_label.add_theme_constant_override("outline_size", 8)
	_pull_over_label.visible = false
	_ignore_mouse(wanted_center)

	# --- Fist fight health bars (top center, under the GPS) ---
	var fight_center := CenterContainer.new()
	fight_center.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	fight_center.offset_top = 112
	fight_center.offset_bottom = 210
	add_child(fight_center)
	_fight_panel = _panel(fight_center)
	var fv := VBoxContainer.new()
	_fight_panel.add_child(fv)
	var fr := HBoxContainer.new()
	fr.add_theme_constant_override("separation", 16)
	fv.add_child(fr)
	_label(fr, "YOU", 16, Color.WHITE)
	_fight_you = _bar(fr, Color("#2ecc71"))
	_label(fr, "VS", 16, Color("#ffd166"))
	_fight_them = _bar(fr, Color("#ef476f"))
	_label(fr, "DRIVER", 16, Color.WHITE)
	var hint := _label(fv, "J / Left mouse: punch (combo x3)   K / Right mouse: block   L: dodge", 13, Color(0.85, 0.88, 0.92))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fight_panel.visible = false
	_ignore_mouse(fight_center)

	_ignore_mouse(margin)
	_ignore_mouse(top_center)
	_ignore_mouse(help_box)

	# --- Interactive UI (these DO take mouse clicks) ---
	phone = Phone.new()
	add_child(phone)
	refuel_menu = RefuelMenu.new()
	add_child(refuel_menu)
	food_menu = FoodMenu.new()
	add_child(food_menu)

	# Full-screen map (M)
	_full_map_layer = ColorRect.new()
	_full_map_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_full_map_layer.color = Color(0, 0, 0, 0.55)
	_full_map_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full_map_layer.visible = false
	add_child(_full_map_layer)
	var map_center := CenterContainer.new()
	map_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full_map_layer.add_child(map_center)
	full_map = Minimap.new()
	full_map.full = true
	full_map.custom_minimum_size = Vector2(620, 620)
	map_center.add_child(full_map)
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
	if _wanted > 0:
		# stars blink red/yellow like a police light
		var blink := absf(sin(Time.get_ticks_msec() * 0.006))
		_wanted_label.add_theme_color_override("font_color", Color("#ffd23f").lerp(Color("#ff4d5e"), blink))
	if _dialog_time > 0.0:
		_dialog_time -= delta
		_dialog_panel.visible = _dialog_time > 0.0
	# The phone slides over the help panel, so hide help while the phone is out.
	_help_panel.get_parent().visible = not phone.is_open


# --- Public API (called by the game) -----------------------------------------

func set_money(amount: int) -> void:
	_money_label.text = Economy.format_peso(amount)
	# Negative = you owe money (fines): shown in red until you work it off.
	_money_label.add_theme_color_override("font_color", Color("#ff5d6c") if amount < 0 else MONEY_COLOR)


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
	return dialog_box.is_open or license_card.visible or shop.visible or refuel_menu.visible or food_menu.visible \
		or end_of_day.visible or pause_menu.visible or (phone.is_open and phone.has_mouse) or _full_map_layer.visible


## Police wanted level (0-3 stars) and what you did, top center. Stars blink while wanted.
func set_wanted(stars: int, offenses: Array = []) -> void:
	_wanted = stars
	_wanted_panel.visible = stars > 0
	_wanted_label.text = "WANTED  " + "★".repeat(stars) + "☆".repeat(3 - stars)
	_offense_label.text = "\n".join(offenses.map(func(o: String) -> String: return "• " + o))
	_offense_label.visible = not offenses.is_empty()


## "PULL OVER! 8s" while a traffic enforcer waits for you (0 = hide).
func set_pull_over(seconds: float) -> void:
	_pull_over_label.visible = seconds > 0.0
	if seconds > 0.0:
		_pull_over_label.text = "PRRT! Pull over by the enforcer: %ds   (or run!)" % ceili(seconds)


func show_fight(you: float, them: float) -> void:
	_fight_panel.visible = true
	_fight_you.value = clampf(you, 0.0, 1.0) * 100.0
	_fight_them.value = clampf(them, 0.0, 1.0) * 100.0


func hide_fight() -> void:
	_fight_panel.visible = false


func toggle_help() -> void:
	_help_panel.visible = not _help_panel.visible
	_help_hint.visible = not _help_panel.visible


## (Gas is shown by update_gas() in the health panel.)
func update_vehicle(is_shown: bool, speed_kmh: float, fuel_ratio: float, motor_name: String, damage: float) -> void:
	_vehicle_panel.visible = is_shown
	if not is_shown:
		return
	_speed_label.text = str(int(round(speed_kmh)))
	_motor_label.text = motor_name.to_upper()
	var status := ""
	if fuel_ratio <= 0.0:
		status = "WALA NA GASOLINA! Tulod anay! (Out of gas: push it)"
	elif damage >= 1.0:
		status = "Damage %d%%" % int(damage)
	_status_label.text = status
	_status_label.visible = status != ""


## The gas bar in the health panel: shown whenever you have a motor.
func update_gas(has_motor: bool, ratio: float, liters: float, tank: float, range_km: float) -> void:
	_gas_row.visible = has_motor
	_gas_text.visible = has_motor
	if not has_motor:
		return
	_gas_bar.value = ratio * 100.0
	var low := ratio < 0.2
	_gas_bar.modulate = Color(1.0, 0.45, 0.5) if low else Color.WHITE
	_gas_text.text = "%.1f / %.1f L  ·  %.1f km left%s" % [liters, tank, range_km, "  ·  LOW!" if low else ""]


## Health / food / water / energy bars (all 0..1).
## "LIGHT AHEAD: RED 12s" on the speedometer while riding toward a traffic light.
func set_light_ahead(info: Dictionary) -> void:
	_light_label.visible = not info.is_empty()
	if info.is_empty():
		return
	var state: int = info["state"]
	_light_label.text = "LIGHT AHEAD:  %s  %ds   (%d m)" % [["GREEN", "YELLOW", "RED"][state], ceili(float(info["secs"])), int(info["dist"])]
	_light_label.add_theme_color_override("font_color", [Color("#5ee38a"), Color("#ffd23f"), Color("#ff5d6c")][state])


func update_needs(health: float, food: float, water: float, energy: float, resting: bool) -> void:
	_health_bar.value = health * 100.0
	_food_bar.value = food * 100.0
	_water_bar.value = water * 100.0
	_energy_bar.value = energy * 100.0
	_resting_label.visible = resting and energy < 0.99


## Feed the minimap + full map. Called every frame by the game.
func update_map(center: Vector3, view_yaw: float, facing_yaw: float, route: PackedVector3Array,
		has_target: bool, target: Vector3, target_color: Color) -> void:
	for m: Minimap in [minimap, full_map]:
		m.center = center
		m.view_yaw = view_yaw
		m.facing_yaw = facing_yaw
		m.route = route
		m.has_target = has_target
		m.target = target
		m.target_color = target_color
	minimap.refresh()
	if _full_map_layer.visible:
		full_map.refresh()


## Your map pin (both maps) and nearby traffic enforcers (minimap).
func set_map_pin(on: bool, pos: Vector3) -> void:
	for m: Minimap in [minimap, full_map]:
		m.has_pin = on
		m.pin = pos


func set_map_enforcers(positions: PackedVector3Array) -> void:
	minimap.enforcers = positions


func set_map_world(world: GameWorld) -> void:
	minimap.world = world
	full_map.world = world
	full_map._pack_full_map()   # pack the whole city's roads now (while loading), not on the first M press


func toggle_full_map() -> void:
	_full_map_layer.visible = not _full_map_layer.visible
	if _full_map_layer.visible:
		full_map.redraw_roads()


func is_full_map_open() -> bool:
	return _full_map_layer.visible


## A small labeled bar for the needs panel.
func _need_bar(parent: Control, title: String, color: Color) -> ProgressBar:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := _label(row, title, 11, Color(0.8, 0.85, 0.9))
	l.custom_minimum_size.x = 58
	var bar := _bar(row, color)
	bar.custom_minimum_size = Vector2(150, 10)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return bar


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
