class_name EndOfDayScreen
extends ColorRect
## Summary after you go home and sleep:
## rides, fares, tips, gas, rent, clinic/repairs, net earnings, wallet, rating.
##     await end_of_day.show_summary(data)

signal dismissed

const INK := Color("#1d2733")
const MUTED := Color("#6b7785")
const GOOD := Color("#1e8f4e")
const BAD := Color("#d1435b")

var _title: Label
var _rows: GridContainer
var _notes: VBoxContainer
var _button: Button
var _shown_msec := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color("#0b1026")
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(480, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#f4f7f9")
	sb.set_corner_radius_all(20)
	sb.set_content_margin_all(26)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	_title = _label(col, "", 28, INK)
	_label(col, "Summary sang adlaw (Today's summary)", 14, MUTED)
	_rows = GridContainer.new()
	_rows.columns = 2
	_rows.add_theme_constant_override("h_separation", 40)
	_rows.add_theme_constant_override("v_separation", 6)
	col.add_child(_rows)
	_notes = VBoxContainer.new()
	col.add_child(_notes)
	_button = Button.new()
	_button.focus_mode = Control.FOCUS_NONE
	_button.custom_minimum_size.y = 46
	_button.add_theme_font_size_override("font_size", 17)
	_button.pressed.connect(_dismiss)
	col.add_child(_button)


## data: day, rides, fares, tips, gas_spent, rent_paid, clinic, repairs, money, debt, rating, notes (Array)
func show_summary(data: Dictionary) -> void:
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	for c in _notes.get_children():
		_notes.remove_child(c)
		c.queue_free()
	_title.text = "End of Day %d" % int(data["day"])
	var income := int(data["fares"]) + int(data["tips"])
	var costs := int(data["gas_spent"]) + int(data["rent_paid"]) + int(data["clinic"]) + int(data["repairs"]) \
		+ int(data.get("food", 0)) + int(data.get("fines", 0))
	var net := income - costs
	_row("Rides completed", str(int(data["rides"])), INK)
	_row("Fares", Economy.format_peso(int(data["fares"])), GOOD)
	_row("Tips", Economy.format_peso(int(data["tips"])), GOOD)
	_row("Gas", "-" + Economy.format_peso(int(data["gas_spent"])), BAD)
	_row("Rent / boundary", "-" + Economy.format_peso(int(data["rent_paid"])), BAD)
	_row("Food & drinks", "-" + Economy.format_peso(int(data.get("food", 0))), BAD)
	_row("Traffic fines", "-" + Economy.format_peso(int(data.get("fines", 0))), BAD)
	_row("Clinic & repairs", "-" + Economy.format_peso(int(data["clinic"]) + int(data["repairs"])), BAD)
	_row("NET TODAY", Economy.format_peso(net), GOOD if net >= 0 else BAD, 22)
	_row("Wallet", Economy.format_peso(int(data["money"])), INK)
	if int(data["debt"]) > 0:
		_row("Unpaid rent (debt)", Economy.format_peso(int(data["debt"])), BAD)
	_row("Rating", "★ %.2f" % float(data["rating"]), Color("#e0a800"))
	for n in data.get("notes", []):
		var l := _label(_notes, str(n), 14, BAD)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 420
	_button.text = "Matulog (Sleep)  →  Day %d      [E / Enter]" % (int(data["day"]) + 1)
	visible = true
	_shown_msec = Time.get_ticks_msec()
	await dismissed


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("interact") or event.is_action_pressed("ui_accept")):
		get_viewport().set_input_as_handled()
		_dismiss()


func _dismiss() -> void:
	if not visible or Time.get_ticks_msec() - _shown_msec < 500:
		return
	visible = false
	dismissed.emit()


func _row(label_text: String, value: String, value_color: Color, size: int = 17) -> void:
	_label(_rows, label_text, size, MUTED if size < 20 else INK)
	var v := _label(_rows, value, size, value_color)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _label(parent: Control, text: String, size: int, c: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	parent.add_child(l)
	return l
