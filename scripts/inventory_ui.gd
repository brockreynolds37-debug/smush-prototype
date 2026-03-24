extends PanelContainer

## Inventory UI — grid-based bag + equipment slots, toggled with I/Tab.
## Reads from LootManager.inventory, supports drag-and-drop reordering
## and equipping weapons.

const InventorySlotScript = preload("res://scripts/inventory_slot.gd")
const SlotType = preload("res://scripts/inventory_slot.gd").SlotType

const BAG_COLS := 5
const BAG_ROWS := 4  # 20 slots total = max_inventory_size

var bag_slots: Array[Panel] = []
var equip_slots: Dictionary = {}  # SlotType → Panel
var tooltip_label: Label
var equipped_items: Dictionary = {}  # SlotType → item_data

var _selected_slot: Panel = null  # For click-to-move (alt to drag)

func _ready() -> void:
	# Panel styling
	visible = false
	set_anchors_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(450, 420)
	offset_left = -225
	offset_top = -210
	offset_right = 225
	offset_bottom = 210
	mouse_filter = Control.MOUSE_FILTER_STOP

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	add_child(main_vbox)

	# Title bar
	var title := Label.new()
	title.text = "Inventory [I]"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.65))
	main_vbox.add_child(title)

	# Split: equipment on left, bag grid on right
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 16)
	main_vbox.add_child(split)

	# Equipment panel
	var equip_panel := _build_equipment_panel()
	split.add_child(equip_panel)

	# Bag grid
	var bag_panel := _build_bag_grid()
	split.add_child(bag_panel)

	# Tooltip at bottom
	tooltip_label = Label.new()
	tooltip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tooltip_label.custom_minimum_size = Vector2(430, 40)
	tooltip_label.add_theme_font_size_override("font_size", 11)
	tooltip_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	tooltip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_vbox.add_child(tooltip_label)

	# Connect to LootManager
	LootManager.inventory_changed.connect(_refresh_bag)
	_refresh_bag()

func _build_equipment_panel() -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var header := Label.new()
	header.text = "Equipment"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", Color(0.6, 0.8, 0.6))
	vbox.add_child(header)

	# Equipment slots layout: centered column
	var equip_types: Array[int] = [
		SlotType.HEAD,
		SlotType.CHEST,
		SlotType.HANDS,
		SlotType.WEAPON,
		SlotType.OFFHAND,
		SlotType.FEET,
		SlotType.RING,
		SlotType.TRINKET,
	]

	for st in equip_types:
		var slot := Panel.new()
		slot.set_script(InventorySlotScript)
		slot.slot_type = st
		slot.slot_clicked.connect(_on_slot_clicked)
		slot.item_dropped.connect(_on_item_dropped)
		vbox.add_child(slot)
		equip_slots[st] = slot

	return vbox

func _build_bag_grid() -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var header := Label.new()
	header.text = "Bag (%d slots)" % (BAG_COLS * BAG_ROWS)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	vbox.add_child(header)

	var grid := GridContainer.new()
	grid.columns = BAG_COLS
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	vbox.add_child(grid)

	for i in range(BAG_COLS * BAG_ROWS):
		var slot := Panel.new()
		slot.set_script(InventorySlotScript)
		slot.slot_type = SlotType.BAG
		slot.slot_index = i
		slot.slot_clicked.connect(_on_slot_clicked)
		slot.item_dropped.connect(_on_item_dropped)
		grid.add_child(slot)
		bag_slots.append(slot)

	return vbox

func _refresh_bag() -> void:
	var inv: Array = LootManager.inventory
	for i in range(bag_slots.size()):
		if i < inv.size():
			bag_slots[i].set_item(inv[i])
		else:
			bag_slots[i].clear_item()
	_update_tooltip(null)

func _on_slot_clicked(slot: Panel) -> void:
	if _selected_slot == null:
		# First click — select if has item
		if slot.has_item():
			_selected_slot = slot
			_update_tooltip(slot)
	else:
		# Second click — move/swap/equip
		if slot == _selected_slot:
			# Deselect
			_selected_slot = null
			_update_tooltip(null)
			return
		_do_move(_selected_slot, slot)
		_selected_slot = null
		_update_tooltip(null)

func _on_item_dropped(from_slot: Panel, to_slot: Panel) -> void:
	_do_move(from_slot, to_slot)

func _do_move(from_slot: Panel, to_slot: Panel) -> void:
	if from_slot == to_slot:
		return
	if not from_slot.has_item():
		return

	var from_item := from_slot.item_data.duplicate()
	var to_item := to_slot.item_data.duplicate() if to_slot.has_item() else {}

	# Equipping: bag → equip slot
	if not from_slot.is_equipment_slot() and to_slot.is_equipment_slot():
		if from_item.get("type", "") != "weapon":
			return  # Only weapons for now
		if to_slot.slot_type != SlotType.WEAPON and to_slot.slot_type != SlotType.OFFHAND:
			return
		_equip_item(from_slot, to_slot, from_item, to_item)
		return

	# Unequipping: equip → bag
	if from_slot.is_equipment_slot() and not to_slot.is_equipment_slot():
		_unequip_item(from_slot, to_slot, from_item, to_item)
		return

	# Bag reorder: bag → bag (swap)
	if not from_slot.is_equipment_slot() and not to_slot.is_equipment_slot():
		_swap_bag_slots(from_slot, to_slot, from_item, to_item)
		return

func _equip_item(from_slot: Panel, to_slot: Panel, from_item: Dictionary, to_item: Dictionary) -> void:
	# Put from_item in equip slot
	to_slot.set_item(from_item)
	equipped_items[to_slot.slot_type] = from_item

	# If equip slot had something, put it back in bag
	if not to_item.is_empty():
		from_slot.set_item(to_item)
		LootManager.inventory[from_slot.slot_index] = to_item
	else:
		from_slot.clear_item()
		_remove_from_inventory(from_slot.slot_index)

	# Apply damage bonus
	_apply_equipment_stats()
	LootManager.inventory_changed.emit()

func _unequip_item(from_slot: Panel, to_slot: Panel, from_item: Dictionary, to_item: Dictionary) -> void:
	if to_slot.has_item():
		# Swap — put bag item into equip if it's a weapon
		if to_item.get("type", "") == "weapon":
			from_slot.set_item(to_item)
			equipped_items[from_slot.slot_type] = to_item
		else:
			return  # Can't swap non-weapon into equip slot
	else:
		from_slot.clear_item()
		equipped_items.erase(from_slot.slot_type)

	# Put unequipped item in bag
	to_slot.set_item(from_item)
	if to_slot.slot_index >= 0 and to_slot.slot_index < LootManager.inventory.size():
		LootManager.inventory[to_slot.slot_index] = from_item
	else:
		LootManager.inventory.append(from_item)

	_apply_equipment_stats()
	LootManager.inventory_changed.emit()

func _swap_bag_slots(from_slot: Panel, to_slot: Panel, from_item: Dictionary, to_item: Dictionary) -> void:
	var fi := from_slot.slot_index
	var ti := to_slot.slot_index
	var inv := LootManager.inventory

	if not to_item.is_empty():
		# Swap
		from_slot.set_item(to_item)
		to_slot.set_item(from_item)
		if fi < inv.size():
			inv[fi] = to_item
		if ti < inv.size():
			inv[ti] = from_item
	else:
		# Move to empty slot
		from_slot.clear_item()
		to_slot.set_item(from_item)
		if fi < inv.size():
			inv.remove_at(fi)
		if ti <= inv.size():
			inv.insert(ti, from_item)
		# Re-sync after index shift
		LootManager.inventory_changed.emit()

func _remove_from_inventory(idx: int) -> void:
	if idx >= 0 and idx < LootManager.inventory.size():
		LootManager.inventory.remove_at(idx)

func _apply_equipment_stats() -> void:
	var hero = GameManager.hero
	if hero == null:
		return
	var total_bonus := 0
	for slot_type in equipped_items:
		var item: Dictionary = equipped_items[slot_type]
		total_bonus += item.get("damage_bonus", 0)
	if "equipment_damage_bonus" in hero:
		hero.equipment_damage_bonus = total_bonus

func _update_tooltip(slot: Panel) -> void:
	if slot == null or not slot.has_item():
		tooltip_label.text = "Click an item, then click a slot to move it."
		return
	var item: Dictionary = slot.item_data
	var rarity: int = item.get("rarity", 0)
	var rarity_name: String = LootManager.RARITY_NAMES.get(rarity, "Common")
	var desc: String = item.get("description", "")
	tooltip_label.text = "[%s] %s — %s" % [rarity_name, item.get("name", "?"), desc]
	tooltip_label.add_theme_color_override("font_color", LootManager.RARITY_COLORS.get(rarity, Color.WHITE))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_I or event.keycode == KEY_TAB:
			visible = not visible
			_selected_slot = null
			if visible:
				_refresh_bag()
			get_viewport().set_input_as_handled()
