extends CanvasLayer

## Merchant shop UI — appears between floors during transitions.
## Player can buy potions and weapons with gold before continuing.

signal merchant_closed

var _panel: PanelContainer
var _gold_label: Label
var _items_container: VBoxContainer
var _shop_items: Array[Dictionary] = []

const SHOP_STOCK := {
	"health_potion": {"price": 50, "always": true},
	"mana_potion": {"price": 40, "always": true},
	"iron_sword": {"price": 80, "floor_min": 1},
	"rusty_dagger": {"price": 45, "floor_min": 1},
	"steel_sword": {"price": 150, "floor_min": 2},
	"iron_axe": {"price": 120, "floor_min": 1},
	"longbow": {"price": 250, "floor_min": 2},
}

func _ready() -> void:
	layer = 90  # Above HUD (10), below transition overlay (100)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

func show_shop(floor_number: int) -> void:
	# Clear previous UI
	for child in get_children():
		child.queue_free()

	_build_shop_ui(floor_number)
	visible = true

func _build_shop_ui(floor_number: int) -> void:
	# Full-screen dark backdrop
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.06, 0.04, 0.08, 0.95)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	# Center panel
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(420, 480)
	_panel.offset_left = -210
	_panel.offset_top = -240
	_panel.offset_right = 210
	_panel.offset_bottom = 240
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.08, 0.14, 0.95)
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_color = Color(0.7, 0.55, 0.2, 0.8)
	panel_style.content_margin_left = 20
	panel_style.content_margin_right = 20
	panel_style.content_margin_top = 16
	panel_style.content_margin_bottom = 16
	_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "MERCHANT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	vbox.add_child(title)

	# Subtitle
	var subtitle := Label.new()
	subtitle.text = "\"Got coin? I've got wares.\""
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.55, 0.5))
	vbox.add_child(subtitle)

	# Separator
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 6)
	vbox.add_child(sep)

	# Gold display
	_gold_label = Label.new()
	_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gold_label.add_theme_font_size_override("font_size", 16)
	_gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.1))
	_update_gold_label()
	vbox.add_child(_gold_label)

	# Items scroll container
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(380, 280)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_items_container = VBoxContainer.new()
	_items_container.add_theme_constant_override("separation", 6)
	_items_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_items_container)

	# Build shop stock
	_populate_shop(floor_number)

	# Continue button
	var continue_btn := Button.new()
	continue_btn.text = "CONTINUE TO NEXT FLOOR"
	continue_btn.custom_minimum_size = Vector2(380, 44)
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.15, 0.5, 0.2, 0.9)
	btn_style.corner_radius_top_left = 6
	btn_style.corner_radius_top_right = 6
	btn_style.corner_radius_bottom_left = 6
	btn_style.corner_radius_bottom_right = 6
	continue_btn.add_theme_stylebox_override("normal", btn_style)
	var btn_hover := StyleBoxFlat.new()
	btn_hover.bg_color = Color(0.2, 0.6, 0.25, 0.95)
	btn_hover.corner_radius_top_left = 6
	btn_hover.corner_radius_top_right = 6
	btn_hover.corner_radius_bottom_left = 6
	btn_hover.corner_radius_bottom_right = 6
	continue_btn.add_theme_stylebox_override("hover", btn_hover)
	continue_btn.add_theme_font_size_override("font_size", 16)
	continue_btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	continue_btn.pressed.connect(_on_continue_pressed)
	vbox.add_child(continue_btn)

	# Hint
	var hint := Label.new()
	hint.text = "Press Space or Enter to continue"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	vbox.add_child(hint)

	# Fade in
	_panel.modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.tween_property(_panel, "modulate", Color(1, 1, 1, 1), 0.4)

func _populate_shop(floor_number: int) -> void:
	_shop_items.clear()

	# Always-available items (potions — unlimited stock)
	for item_id in ["health_potion", "mana_potion"]:
		var shop_entry: Dictionary = SHOP_STOCK[item_id]
		var item_def: Dictionary = LootManager.ITEMS.get(item_id, {})
		if item_def.is_empty():
			continue
		_add_shop_row(item_def, shop_entry["price"], -1)  # -1 = unlimited

	# Weapons available based on floor
	var available_weapons: Array[String] = []
	for item_id in SHOP_STOCK:
		var entry: Dictionary = SHOP_STOCK[item_id]
		if entry.get("always", false):
			continue
		var floor_min: int = entry.get("floor_min", 1)
		if floor_number >= floor_min:
			available_weapons.append(item_id)

	# Offer 3 random weapons from the pool (or all if fewer)
	available_weapons.shuffle()
	var weapon_count := mini(3, available_weapons.size())
	for i in range(weapon_count):
		var wid: String = available_weapons[i]
		var item_def: Dictionary = LootManager.ITEMS.get(wid, {})
		var price: int = SHOP_STOCK[wid]["price"]
		# Scale price slightly with floor
		price = int(price * (1.0 + (floor_number - 1) * 0.15))
		if item_def.is_empty():
			continue
		_add_shop_row(item_def, price, 1)

func _add_shop_row(item_def: Dictionary, price: int, stock: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.custom_minimum_size = Vector2(360, 40)

	# Rarity color indicator
	var rarity: int = item_def.get("rarity", 0)
	var rarity_color: Color = LootManager.RARITY_COLORS.get(rarity, Color.WHITE)

	var indicator := ColorRect.new()
	indicator.custom_minimum_size = Vector2(4, 36)
	indicator.color = rarity_color
	row.add_child(indicator)

	# Item info (name + description)
	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.add_theme_constant_override("separation", 0)

	var name_label := Label.new()
	name_label.text = item_def.get("name", "?")
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", rarity_color)
	info_vbox.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = item_def.get("description", "")
	desc_label.add_theme_font_size_override("font_size", 10)
	desc_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
	info_vbox.add_child(desc_label)

	row.add_child(info_vbox)

	# Price label
	var price_label := Label.new()
	price_label.text = "%d g" % price
	price_label.custom_minimum_size = Vector2(55, 0)
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price_label.add_theme_font_size_override("font_size", 14)
	price_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.1))
	row.add_child(price_label)

	# Buy button
	var buy_btn := Button.new()
	buy_btn.text = "BUY"
	buy_btn.custom_minimum_size = Vector2(60, 32)
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.5, 0.35, 0.1, 0.8)
	btn_style.corner_radius_top_left = 4
	btn_style.corner_radius_top_right = 4
	btn_style.corner_radius_bottom_left = 4
	btn_style.corner_radius_bottom_right = 4
	buy_btn.add_theme_stylebox_override("normal", btn_style)
	var btn_hover := StyleBoxFlat.new()
	btn_hover.bg_color = Color(0.6, 0.45, 0.15, 0.9)
	btn_hover.corner_radius_top_left = 4
	btn_hover.corner_radius_top_right = 4
	btn_hover.corner_radius_bottom_left = 4
	btn_hover.corner_radius_bottom_right = 4
	buy_btn.add_theme_stylebox_override("hover", btn_hover)
	buy_btn.add_theme_font_size_override("font_size", 12)
	buy_btn.pressed.connect(_on_buy_pressed.bind(item_def, price, stock, buy_btn, row))
	row.add_child(buy_btn)

	_items_container.add_child(row)

	var entry := {"item": item_def, "price": price, "stock": stock, "button": buy_btn, "row": row}
	_shop_items.append(entry)

	# Disable if can't afford
	if LootManager.gold < price:
		buy_btn.disabled = true
		buy_btn.modulate = Color(0.5, 0.5, 0.5, 0.7)

func _on_buy_pressed(item_def: Dictionary, price: int, stock: int, btn: Button, row: HBoxContainer) -> void:
	if LootManager.gold < price:
		return

	# Deduct gold
	LootManager.gold -= price
	LootManager.gold_changed.emit(LootManager.gold)
	RunStats.record_gold_spent(price)

	# Give item to player
	if item_def["type"] == "consumable":
		# Consumables go straight to hero
		LootManager._apply_consumable(item_def)
		LootManager.item_picked_up.emit(item_def)
	elif item_def["type"] == "weapon":
		if LootManager.inventory.size() < LootManager.max_inventory_size:
			LootManager.inventory.append(item_def.duplicate())
			LootManager.inventory_changed.emit()
			LootManager.item_picked_up.emit(item_def)
		else:
			# Inventory full — refund
			LootManager.gold += price
			LootManager.gold_changed.emit(LootManager.gold)
			return

	# Play purchase sound
	AudioManager.play_sfx("loot_pickup")

	_update_gold_label()

	# Handle stock: -1 = unlimited (potions), positive = limited (weapons)
	if stock > 0:
		# Remove the weapon from shop (one-time purchase)
		btn.disabled = true
		btn.text = "SOLD"
		btn.modulate = Color(0.4, 0.4, 0.4, 0.6)

	# Update all buy buttons affordability
	_update_button_states()

func _update_button_states() -> void:
	for entry in _shop_items:
		var btn: Button = entry["button"]
		if btn.text == "SOLD":
			continue
		if LootManager.gold < entry["price"]:
			btn.disabled = true
			btn.modulate = Color(0.5, 0.5, 0.5, 0.7)
		else:
			btn.disabled = false
			btn.modulate = Color(1, 1, 1, 1)

func _update_gold_label() -> void:
	if _gold_label:
		_gold_label.text = "Your Gold: %d" % LootManager.gold

func _on_continue_pressed() -> void:
	visible = false
	merchant_closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			_on_continue_pressed()
			get_viewport().set_input_as_handled()
