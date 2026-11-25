class_name LicenseCard
extends ColorRect
## Shows your new driver's license (a fictional game card, not a real ID design).
##     await license_card.show_card("Juan Dela Cruz", "G07-26-001234")

signal dismissed

var _name_label: Label
var _number_label: Label
var _shown_msec := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color(0, 0, 0, 0.55)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	center.add_child(outer)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(520, 300)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#e9f5f2")
	sb.set_corner_radius_all(18)
	sb.set_content_margin_all(0)
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 12
	card.add_theme_stylebox_override("panel", sb)
	outer.add_child(card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	card.add_child(col)
	# Header band
	var header := PanelContainer.new()
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = Color("#14a39a")
	hsb.corner_radius_top_left = 18
	hsb.corner_radius_top_right = 18
	hsb.set_content_margin_all(14)
	header.add_theme_stylebox_override("panel", hsb)
	col.add_child(header)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 0)
	header.add_child(hv)
	_label(hv, "NEGROS TRANSPORT OFFICE", 13, Color(1, 1, 1, 0.85))
	_label(hv, "DRIVER'S LICENSE", 26, Color.WHITE)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	margin.add_child(body)
	col.add_child(margin)

	# "Photo": a little blocky rider portrait made of colored boxes
	var photo := Panel.new()
	photo.custom_minimum_size = Vector2(110, 130)
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color("#cfe8f5")
	psb.set_corner_radius_all(8)
	photo.add_theme_stylebox_override("panel", psb)
	body.add_child(photo)
	_rect(photo, Rect2(30, 70, 50, 60), Color("#14a39a"))   # jacket
	_rect(photo, Rect2(38, 30, 34, 38), Color("#c68c5a"))   # face
	_rect(photo, Rect2(34, 22, 42, 16), Color("#1a1410"))   # hair
	_rect(photo, Rect2(45, 44, 5, 5), Color("#1a1410"))     # eyes
	_rect(photo, Rect2(60, 44, 5, 5), Color("#1a1410"))

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 4)
	body.add_child(info)
	_label(info, "NAME", 11, Color("#6b7785"))
	_name_label = _label(info, "", 22, Color("#1d2733"))
	_label(info, "LICENSE NO.", 11, Color("#6b7785"))
	_number_label = _label(info, "", 18, Color("#1d2733"))
	_label(info, "RESTRICTION", 11, Color("#6b7785"))
	_label(info, "A - Motorcycle", 16, Color("#1d2733"))
	_label(info, "CITY", 11, Color("#6b7785"))
	_label(info, "Bacolod", 16, Color("#1d2733"))

	var hint := _label(outer, "Congratulations, rider!   (E / Enter / click to continue)", 16, Color.WHITE)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func show_card(holder_name: String, number: String) -> void:
	_name_label.text = holder_name.to_upper()
	_number_label.text = number
	visible = true
	_shown_msec = Time.get_ticks_msec()
	await dismissed


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_dismiss()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_dismiss()


func _dismiss() -> void:
	if not visible or Time.get_ticks_msec() - _shown_msec < 400:
		return
	visible = false
	dismissed.emit()


func _label(parent: Control, text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


func _rect(parent: Control, r: Rect2, c: Color) -> void:
	var cr := ColorRect.new()
	cr.position = r.position
	cr.size = r.size
	cr.color = c
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(cr)
