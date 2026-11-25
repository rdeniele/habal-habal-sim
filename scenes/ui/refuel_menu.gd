class_name RefuelMenu
extends PanelContainer
## Gas station pump menu: buy ₱100 / ₱200 worth, or a full tank.
## Keys 1 / 2 / 3 or click. Esc or E closes it.

signal amount_chosen(liters: float)
signal closed

const OPTION_PESOS := [100, 200]

var _info: Label
var _buttons: Array[Button] = []
var _liters: Array[float] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	custom_minimum_size = Vector2(340, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.09, 0.13, 0.92)
	sb.set_corner_radius_all(16)
	sb.set_content_margin_all(18)
	add_theme_stylebox_override("panel", sb)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	var title := Label.new()
	title.text = "⛽ Gasolinahan · Regular ₱%d/L" % Economy.GAS_PRICE_PER_LITER
	title.add_theme_font_size_override("font_size", 20)
	col.add_child(title)
	_info = Label.new()
	_info.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	col.add_child(_info)
	for i in 3:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size.y = 40
		var idx := i
		b.pressed.connect(func() -> void: choose(idx))
		col.add_child(b)
		_buttons.append(b)
	var cancel := Button.new()
	cancel.text = "Cancel  [Esc]"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(close_menu)
	col.add_child(cancel)
	visible = false


## Show the menu for a tank that has `fuel` of `tank` liters, with `money` in the wallet.
func open_menu(fuel: float, tank: float, money: int) -> void:
	var price := float(Economy.GAS_PRICE_PER_LITER)
	var space := maxf(0.0, tank - fuel)
	_info.text = "Tank: %.1f / %.1f L    Wallet: %s" % [fuel, tank, Economy.format_peso(money)]
	_liters.clear()
	for i in OPTION_PESOS.size():
		var pesos: int = OPTION_PESOS[i]
		var liters := minf(pesos / price, space)
		_liters.append(liters)
		_buttons[i].text = "[%d]  ₱%d worth  (%.1f L)" % [i + 1, pesos, pesos / price]
		_buttons[i].disabled = space < 0.05
	_liters.append(space)
	_buttons[2].text = "[3]  Full tank  (%.1f L · ₱%d)" % [space, int(ceil(space * price))]
	_buttons[2].disabled = space < 0.05
	visible = true


func choose(index: int) -> void:
	if not visible or index < 0 or index >= _liters.size() or _buttons[index].disabled:
		return
	amount_chosen.emit(_liters[index])
	close_menu()


func close_menu() -> void:
	if visible:
		visible = false
		closed.emit()
