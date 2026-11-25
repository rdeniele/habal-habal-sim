class_name FoodMenu
extends PanelContainer
## Sari-sari store menu: pick food or drinks with keys 1-6 or click. Esc / E closes.
## Items and prices come from Economy.FOOD_ITEMS.

signal item_chosen(item: Dictionary)
signal closed

var _info: Label
var _list: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	custom_minimum_size = Vector2(380, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.09, 0.13, 0.94)
	sb.set_corner_radius_all(16)
	sb.set_content_margin_all(18)
	sb.border_color = Color("#f4a261")
	sb.border_width_top = 4
	add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	var title := Label.new()
	title.text = "Sari-sari store"
	title.add_theme_font_size_override("font_size", 22)
	col.add_child(title)
	_info = Label.new()
	_info.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	_info.add_theme_font_size_override("font_size", 14)
	col.add_child(_info)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	col.add_child(_list)
	var close := Button.new()
	close.text = "Done  [Esc]"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(close_menu)
	col.add_child(close)
	visible = false


func open_menu() -> void:
	_refresh()
	visible = true
	_center_on_screen.call_deferred()


func _refresh() -> void:
	_info.text = "Wallet %s   ·   Food %d%%  ·  Water %d%%  ·  Energy %d%%" % [
		Economy.format_peso(GameState.money), int(GameState.hunger), int(GameState.thirst), int(GameState.energy)]
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var items: Array = Economy.FOOD_ITEMS
	for i in items.size():
		var item: Dictionary = items[i]
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = 36
		b.text = "[%d]  %s   %s   %s" % [i + 1, item["name"], Economy.format_peso(int(item["price"])), _effects(item)]
		b.disabled = int(item["price"]) > GameState.money
		var idx := i
		b.pressed.connect(func() -> void: choose(idx))
		_list.add_child(b)


## Put the panel in the middle of the screen (after its size is known).
func _center_on_screen() -> void:
	reset_size()
	position = (get_viewport_rect().size - size) * 0.5


func choose(index: int) -> void:
	var items: Array = Economy.FOOD_ITEMS
	if not visible or index < 0 or index >= items.size():
		return
	var item: Dictionary = items[index]
	if int(item["price"]) > GameState.money:
		return
	item_chosen.emit(item)
	_refresh()


func close_menu() -> void:
	if visible:
		visible = false
		closed.emit()


func _effects(item: Dictionary) -> String:
	var parts: Array[String] = []
	for key: String in ["hunger", "thirst", "energy"]:
		var v := int(item[key])
		if v > 0:
			parts.append("+%d %s" % [v, {"hunger": "food", "thirst": "water", "energy": "energy"}[key]])
	return "(" + ", ".join(parts) + ")"
