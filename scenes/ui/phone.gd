class_name Phone
extends PanelContainer
## The "Sakay" rider app on your phone (our own fictional ride-hailing brand).
## Slides in from the right. Two ways it can be open:
##   - "peek": pops up by itself for a new booking; mouse stays locked (use keys 1 / 2)
##   - focused: opened with Tab; mouse is free so you can click buttons
## The BookingSystem tells the phone what to show; the phone sends back button presses.

signal online_toggled(go_online: bool)
signal accept_pressed
signal decline_pressed
signal cancel_pressed
signal last_ride_pressed

const W := 330.0
const H := 520.0
const TEAL := Color("#14a39a")
const TEAL_DARK := Color("#0e7c75")
const INK := Color("#1d2733")
const MUTED := Color("#6b7785")
const SCREEN_BG := Color("#f4f7f9")
const GREEN := Color("#2ecc71")
const ORANGE := Color("#ff8c42")
const RED := Color("#ef476f")

var is_open := false
var has_mouse := false   # opened with Tab (mouse visible)

var _slide := 0.0        # 0 = hidden, 1 = shown
var _tween: Tween
var _online := false
var _status_pill: Label
var _toggle_btn: Button
var _last_ride_btn: Button
var _earn_label: Label
var _rides_label: Label
var _rating_label: Label
var _content: VBoxContainer
var _timer_bar: ProgressBar
var _detail_label: Label


func _ready() -> void:
	# Anchor to the right edge, vertically centered (a bit above center).
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_top = -H * 0.5 - 70.0
	offset_bottom = H * 0.5 - 70.0
	custom_minimum_size = Vector2(W, H)
	_apply_slide(0.0)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Phone body (dark bezel)
	add_theme_stylebox_override("panel", _box(Color("#111418"), 30, 10))
	var screen := PanelContainer.new()
	screen.add_theme_stylebox_override("panel", _box(SCREEN_BG, 22, 0))
	add_child(screen)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	screen.add_child(col)

	# App bar
	var bar := PanelContainer.new()
	var bar_style := _box(TEAL, 0, 14)
	bar_style.corner_radius_top_left = 22
	bar_style.corner_radius_top_right = 22
	bar.add_theme_stylebox_override("panel", bar_style)
	col.add_child(bar)
	var bar_row := HBoxContainer.new()
	bar.add_child(bar_row)
	_label(bar_row, "sakay", 28, Color.WHITE)
	var sub := _label(bar_row, " rider", 15, Color(1, 1, 1, 0.8))
	sub.size_flags_vertical = Control.SIZE_SHRINK_END
	_spacer_h(bar_row)
	_status_pill = _label(bar_row, " OFFLINE ", 13, Color.WHITE)
	_status_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	# Body
	var body_margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		body_margin.add_theme_constant_override("margin_" + side, 14)
	body_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body_margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body_margin.add_child(body)

	_toggle_btn = _button(body, "GO ONLINE", TEAL)
	_toggle_btn.custom_minimum_size.y = 46
	_toggle_btn.pressed.connect(func() -> void: online_toggled.emit(not _online))
	_last_ride_btn = _button(body, "LAST RIDE  (end the day near home)", Color("#8338ec"))
	_last_ride_btn.pressed.connect(func() -> void: last_ride_pressed.emit())
	_last_ride_btn.visible = false

	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 8)
	body.add_child(stats)
	_earn_label = _stat_card(stats, "TODAY")
	_rides_label = _stat_card(stats, "RIDES")
	_rating_label = _stat_card(stats, "RATING")

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 6)
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_content)

	var hint := _label(body, "Tab  open/close phone  ·  1 accept  ·  2 decline", 11, MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	set_online(false)
	show_message("You're offline", "Go online to start getting bookings from passengers around Bacolod.")


# --- Opening / closing -------------------------------------------------------

## Slide in. `with_mouse` = the player wants to click (opened with Tab).
func open(with_mouse: bool) -> void:
	has_mouse = with_mouse
	if is_open:
		return
	is_open = true
	_animate(1.0)


func close() -> void:
	has_mouse = false
	if not is_open:
		return
	is_open = false
	_animate(0.0)


func _animate(to: float) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_method(_apply_slide, _slide, to, 0.25)


func _apply_slide(v: float) -> void:
	_slide = v
	# Hidden: just off the right edge. Shown: 24px from the right edge.
	offset_left = lerpf(20.0, -W - 24.0, v)
	offset_right = offset_left + W


# --- What the app shows ------------------------------------------------------

func set_online(on: bool) -> void:
	_online = on
	_toggle_btn.text = "GO OFFLINE" if on else "GO ONLINE"
	_set_button_color(_toggle_btn, Color("#5c6773") if on else TEAL)
	_status_pill.text = " ● ONLINE " if on else " OFFLINE "
	_status_pill.add_theme_color_override("font_color", Color("#c8ffd9") if on else Color(1, 1, 1, 0.7))


## Show the Last Ride button while online; grey it out once it's switched on.
func set_last_ride_state(online: bool, active: bool) -> void:
	_last_ride_btn.visible = online
	_last_ride_btn.disabled = active
	_last_ride_btn.text = "LAST RIDE ON  ·  next trip ends near home" if active else "LAST RIDE  (end the day near home)"


func set_toggle_enabled(enabled: bool) -> void:
	_toggle_btn.disabled = not enabled


func set_stats(earnings: int, rides: int, rating: float) -> void:
	_earn_label.text = Economy.format_peso(earnings)
	_rides_label.text = str(rides)
	_rating_label.text = "★ %.2f" % rating


func show_message(title: String, body: String) -> void:
	_clear()
	_label(_content, title, 20, INK)
	_wrap_label(_content, body, 14, MUTED)


## A new booking request card. `req` comes from BookingSystem.
func show_request(req: Dictionary) -> void:
	_clear()
	var tag := _label(_content, " NEW BOOKING ", 12, Color.WHITE)
	tag.add_theme_stylebox_override("normal", _box(ORANGE, 6, 2))
	tag.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	var who := HBoxContainer.new()
	_content.add_child(who)
	_label(who, str(req["name"]), 22, INK)
	_spacer_h(who)
	_label(who, "★ %.1f" % float(req["rating"]), 16, Color("#e0a800"))

	_wrap_label(_content, "● Pickup: %s  (%s away)" % [req["pickup"]["label"], _dist(req["pickup_m"])], 14, Color("#1e8f4e"))
	_wrap_label(_content, "● Drop-off: %s" % req["dropoff"]["label"], 14, Color("#d9601a"))

	var fare_row := HBoxContainer.new()
	_content.add_child(fare_row)
	_label(fare_row, Economy.format_peso(int(req["fare"])), 30, INK)
	var trip := _label(fare_row, "   %s trip" % _dist(req["trip_m"]), 14, MUTED)
	trip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if bool(req["surge"]):
		var surge := _label(fare_row, " SURGE ", 11, Color.WHITE)
		surge.add_theme_stylebox_override("normal", _box(RED, 6, 2))
		surge.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	_timer_bar = ProgressBar.new()
	_timer_bar.show_percentage = false
	_timer_bar.custom_minimum_size.y = 8
	_timer_bar.max_value = 1.0
	_timer_bar.value = 1.0
	_timer_bar.add_theme_stylebox_override("background", _box(Color(0, 0, 0, 0.08), 4, 0))
	_timer_bar.add_theme_stylebox_override("fill", _box(ORANGE, 4, 0))
	_content.add_child(_timer_bar)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	_content.add_child(buttons)
	var decline := _button(buttons, "Decline  [2]", Color("#9aa5b1"))
	decline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	decline.pressed.connect(func() -> void: decline_pressed.emit())
	var accept := _button(buttons, "Accept  [1]", GREEN)
	accept.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	accept.pressed.connect(func() -> void: accept_pressed.emit())


func update_request_timer(ratio: float) -> void:
	if _timer_bar != null and is_instance_valid(_timer_bar):
		_timer_bar.value = ratio


## Active trip screen. `rows` are extra info lines.
func show_trip(title: String, rows: Array, can_cancel: bool) -> void:
	_clear()
	_label(_content, title, 20, INK)
	for r in rows:
		_wrap_label(_content, str(r), 14, MUTED)
	_detail_label = _label(_content, "", 26, TEAL_DARK)
	if can_cancel:
		var cancel := _button(_content, "Cancel trip", Color("#9aa5b1"))
		cancel.pressed.connect(func() -> void: cancel_pressed.emit())


## Live line on the trip screen (distance left, etc.)
func set_trip_detail(text: String) -> void:
	if _detail_label != null and is_instance_valid(_detail_label):
		_detail_label.text = text


# --- Small UI builders -------------------------------------------------------

func _clear() -> void:
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	_timer_bar = null
	_detail_label = null


func _dist(meters: Variant) -> String:
	var m := float(meters)
	return "%d m" % int(m) if m < 1000.0 else "%.1f km" % (m / 1000.0)


func _box(color: Color, radius: int, margin: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb


func _label(parent: Control, text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


func _wrap_label(parent: Control, text: String, font_size: int, color: Color) -> Label:
	var l := _label(parent, text, font_size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = W - 60.0
	return l


func _stat_card(parent: Control, title: String) -> Label:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _box(Color.WHITE, 12, 8))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	card.add_child(v)
	_label(v, title, 10, MUTED)
	return _label(v, "-", 16, INK)


func _button(parent: Control, text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE   # so Space (handbrake) never "clicks" a button
	b.custom_minimum_size.y = 40
	b.add_theme_font_size_override("font_size", 15)
	for c: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(c, Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.5))
	_set_button_color(b, color)
	parent.add_child(b)
	return b


func _set_button_color(b: Button, color: Color) -> void:
	b.add_theme_stylebox_override("normal", _box(color, 12, 8))
	b.add_theme_stylebox_override("hover", _box(color.lightened(0.1), 12, 8))
	b.add_theme_stylebox_override("pressed", _box(color.darkened(0.15), 12, 8))
	b.add_theme_stylebox_override("disabled", _box(color.darkened(0.3), 12, 8))


func _spacer_h(parent: Control) -> void:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(s)
