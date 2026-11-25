class_name MotorShopUI
extends ColorRect
## The Motor Shop screen: buy or rent a motor (pick a color), repair damage, sell yours.
## Only shows choices; the game does the money math (see game.gd `_on_shop_purchase`).

signal purchase(motor_id: String, color_index: int, mode: String)   # mode: "buy" / "rent"
signal repair_pressed
signal sell_pressed
signal closed

const INK := Color("#1d2733")
const MUTED := Color("#6b7785")
const TEAL := Color("#14a39a")

var _ctx: Dictionary = {}
var _rows: VBoxContainer
var _wallet: Label
var _footer: HBoxContainer
var _subtitle: Label
var _color_choice: Dictionary = {}   # motor id -> chosen color index


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color(0, 0, 0, 0.5)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 0)
	panel.add_theme_stylebox_override("panel", _box(Color("#f4f7f9"), 20, 20))
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)

	var head := HBoxContainer.new()
	col.add_child(head)
	var titles := VBoxContainer.new()
	head.add_child(titles)
	_label(titles, "MOTOR SHOP", 26, INK)
	_subtitle = _label(titles, "", 14, MUTED)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	_wallet = _label(head, "", 24, Color("#e0a800"))
	_wallet.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 430)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 8)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)

	_footer = HBoxContainer.new()
	_footer.add_theme_constant_override("separation", 8)
	col.add_child(_footer)


## ctx: money, mode ("none"/"rent"/"own"), current_id, color_index, damage, motor_near, tutorial
func open_shop(ctx: Dictionary) -> void:
	_ctx = ctx
	_rebuild()
	visible = true


func close_shop() -> void:
	if visible:
		visible = false
		closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause") and not bool(_ctx.get("tutorial", false)):
		get_viewport().set_input_as_handled()
		close_shop()


func _rebuild() -> void:
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	for c in _footer.get_children():
		_footer.remove_child(c)
		c.queue_free()

	var money: int = _ctx["money"]
	var mode: String = _ctx["mode"]
	var current_id: String = _ctx["current_id"]
	var tutorial: bool = _ctx.get("tutorial", false)
	_wallet.text = Economy.format_peso(money)
	_subtitle.text = "Buy = pay once, yours forever.  Rent = %s/day boundary, paid at end of day." \
		% Economy.format_peso(Economy.RENT_PER_DAY)

	var trade_in := 0
	if mode == "own":
		trade_in = int(int(Motors.get_motor(current_id)["price"]) * Economy.SELL_BACK_RATIO)

	for m: Dictionary in Motors.LIST:
		_rows.add_child(_make_row(m, money, mode, current_id, trade_in))

	# Footer: repair / sell / close
	var damage: float = _ctx.get("damage", 0.0)
	if mode != "none" and damage >= 1.0:
		var cost := int(ceil(damage)) * Economy.REPAIR_COST_PER_DAMAGE_POINT
		var repair := _button(_footer, "Repair damage %d%%  (%s)" % [int(damage), Economy.format_peso(cost)], Color("#3a86ff"))
		repair.disabled = cost > money or not bool(_ctx.get("motor_near", false))
		if not bool(_ctx.get("motor_near", false)):
			repair.text = "Bring your motor here to repair it"
		repair.pressed.connect(func() -> void: repair_pressed.emit())
	if mode == "own":
		var sell := _button(_footer, "Sell your motor (+%s)" % Economy.format_peso(trade_in), Color("#9aa5b1"))
		sell.pressed.connect(func() -> void: sell_pressed.emit())
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer.add_child(gap)
	if not tutorial:
		var close := _button(_footer, "Close  [Esc]", Color("#5c6773"))
		close.pressed.connect(close_shop)


func _make_row(m: Dictionary, money: int, mode: String, current_id: String, trade_in: int) -> Control:
	var id: String = m["id"]
	var colors: Array = m["colors"]
	var chosen: int = _color_choice.get(id, int(_ctx.get("color_index", 0)) if id == current_id else 0)
	chosen = clampi(chosen, 0, colors.size() - 1)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _box(Color.WHITE, 14, 12))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)

	# Big color preview
	var preview := ColorRect.new()
	preview.custom_minimum_size = Vector2(54, 54)
	preview.color = Color(str(colors[chosen]))
	preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(preview)

	# Name, stats, color swatches
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 3)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var name_row := HBoxContainer.new()
	info.add_child(name_row)
	_label(name_row, str(m["name"]), 19, INK)
	var tier := _label(name_row, "  %s" % str(m["tier"]).to_upper(), 12, TEAL)
	tier.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if id == current_id and mode != "none":
		var tag := _label(name_row, "   YOURS" if mode == "own" else "   RENTING", 12, Color("#e0a800"))
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_label(info, "Top %d km/h  ·  Accel %s  ·  Handling %s  ·  %d km/L  ·  %.1f L tank" % [
		int(m["top_speed_kmh"]), _stars(float(m["acceleration"]), 3.4, 5.4),
		_stars(float(m["handling"]), 0.9, 1.2), int(m["km_per_liter"]), float(m["tank_liters"])], 13, MUTED)
	var swatches := HBoxContainer.new()
	swatches.add_theme_constant_override("separation", 6)
	info.add_child(swatches)
	for i in colors.size():
		var sw := Button.new()
		sw.custom_minimum_size = Vector2(26, 20)
		sw.focus_mode = Control.FOCUS_NONE
		var c := Color(str(colors[i]))
		var sb := _box(c, 5, 0)
		if i == chosen:
			sb.border_color = INK
			sb.set_border_width_all(2)
		for st: String in ["normal", "hover", "pressed"]:
			sw.add_theme_stylebox_override(st, sb)
		var idx := i
		sw.pressed.connect(func() -> void:
			_color_choice[id] = idx
			_rebuild())
		swatches.add_child(sw)

	# Price + buttons
	var buy_col := VBoxContainer.new()
	buy_col.add_theme_constant_override("separation", 4)
	row.add_child(buy_col)
	var price: int = m["price"]
	var owns_this := mode == "own" and id == current_id
	var net := price - trade_in if mode == "own" else price
	var buy_text := "Buy %s" % Economy.format_peso(price)
	if mode == "own" and not owns_this:
		buy_text = "Buy %s (trade-in)" % Economy.format_peso(net)
	var buy := _button(buy_col, buy_text, Color("#2ecc71"))
	buy.custom_minimum_size.x = 210
	buy.disabled = owns_this or net > money
	buy.pressed.connect(func() -> void: purchase.emit(id, chosen, "buy"))
	var rent := _button(buy_col, "Rent %s/day" % Economy.format_peso(Economy.RENT_PER_DAY), Color("#ff8c42"))
	rent.disabled = mode == "rent" and id == current_id
	rent.pressed.connect(func() -> void: purchase.emit(id, chosen, "rent"))
	return card


## Turns a stat into 1-5 stars text between lo and hi.
func _stars(v: float, lo: float, hi: float) -> String:
	var n := clampi(int(round(remap(v, lo, hi, 1.0, 5.0))), 1, 5)
	return "★".repeat(n) + "☆".repeat(5 - n)


func _box(c: Color, radius: int, margin: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb


func _label(parent: Control, text: String, size: int, c: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, c: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = 34
	b.add_theme_font_size_override("font_size", 14)
	for k: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(k, Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.6))
	b.add_theme_stylebox_override("normal", _box(c, 10, 6))
	b.add_theme_stylebox_override("hover", _box(c.lightened(0.1), 10, 6))
	b.add_theme_stylebox_override("pressed", _box(c.darkened(0.15), 10, 6))
	b.add_theme_stylebox_override("disabled", _box(Color("#c3cbd3"), 10, 6))
	parent.add_child(b)
	return b
