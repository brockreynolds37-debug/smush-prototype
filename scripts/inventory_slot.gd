extends Panel

## A single inventory slot — shows an item, supports drag-and-drop.
## Used for both bag slots and equipment slots.

signal slot_clicked(slot: Panel)
signal item_dropped(from_slot: Panel, to_slot: Panel)

enum SlotType { BAG, HEAD, CHEST, HANDS, FEET, RING, TRINKET, WEAPON, OFFHAND }

@export var slot_type: SlotType = SlotType.BAG
@export var slot_index: int = -1  # bag position, -1 for equipment slots

var item_data: Dictionary = {}  # Empty = no item
var is_hovered: bool = false

const SLOT_SIZE := Vector2(52, 52)
const EMPTY_COLOR := Color(0.12, 0.12, 0.18, 0.9)
const HOVER_COLOR := Color(0.2, 0.2, 0.35, 0.95)
const EQUIP_EMPTY_COLOR := Color(0.08, 0.15, 0.08, 0.9)

# Equipment type labels for empty equipment slots
const EQUIP_LABELS := {
	SlotType.HEAD: "Head",
	SlotType.CHEST: "Chest",
	SlotType.HANDS: "Hands",
	SlotType.FEET: "Feet",
	SlotType.RING: "Ring",
	SlotType.TRINKET: "Trinket",
	SlotType.WEAPON: "Wpn",
	SlotType.OFFHAND: "Off",
}

var _item_label: Label
var _rarity_border: ColorRect
var _slot_label: Label  # shows slot type when empty (equip slots only)

func _ready() -> void:
	custom_minimum_size = SLOT_SIZE
	size = SLOT_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Rarity border (behind content)
	_rarity_border = ColorRect.new()
	_rarity_border.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rarity_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rarity_border.visible = false
	add_child(_rarity_border)

	# Item name label (centered)
	_item_label = Label.new()
	_item_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_item_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_item_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_item_label.add_theme_font_size_override("font_size", 9)
	_item_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_item_label)

	# Slot type label (equipment slots only, shown when empty)
	_slot_label = Label.new()
	_slot_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_slot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_slot_label.add_theme_font_size_override("font_size", 10)
	_slot_label.add_theme_color_override("font_color", Color(0.4, 0.5, 0.4, 0.6))
	_slot_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_slot_label)

	_refresh()

func set_item(data: Dictionary) -> void:
	item_data = data
	_refresh()

func clear_item() -> void:
	item_data = {}
	_refresh()

func has_item() -> bool:
	return not item_data.is_empty()

func is_equipment_slot() -> bool:
	return slot_type != SlotType.BAG

func _refresh() -> void:
	if has_item():
		_item_label.text = item_data.get("name", "?")
		var rarity: int = item_data.get("rarity", 0)
		var color: Color = LootManager.RARITY_COLORS.get(rarity, Color.WHITE)
		_item_label.add_theme_color_override("font_color", color)
		_rarity_border.color = Color(color, 0.15)
		_rarity_border.visible = true
		_slot_label.visible = false
	else:
		_item_label.text = ""
		_rarity_border.visible = false
		if is_equipment_slot():
			_slot_label.text = EQUIP_LABELS.get(slot_type, "")
			_slot_label.visible = true
		else:
			_slot_label.visible = false
	queue_redraw()

func _draw() -> void:
	var bg := EMPTY_COLOR
	if is_equipment_slot() and not has_item():
		bg = EQUIP_EMPTY_COLOR
	if is_hovered:
		bg = HOVER_COLOR
	draw_rect(Rect2(Vector2.ZERO, size), bg)
	# Border
	var border_color := Color(0.35, 0.35, 0.45, 0.8)
	if has_item():
		var rarity: int = item_data.get("rarity", 0)
		border_color = LootManager.RARITY_COLORS.get(rarity, border_color)
	draw_rect(Rect2(Vector2.ZERO, size), border_color, false, 2.0)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		slot_clicked.emit(self)
		accept_event()

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER:
		is_hovered = true
		queue_redraw()
	elif what == NOTIFICATION_MOUSE_EXIT:
		is_hovered = false
		queue_redraw()

# Drag-and-drop support
func _get_drag_data(_at_position: Vector2) -> Variant:
	if not has_item():
		return null
	# Create drag preview
	var preview := Label.new()
	preview.text = item_data.get("name", "?")
	var rarity: int = item_data.get("rarity", 0)
	preview.add_theme_color_override("font_color", LootManager.RARITY_COLORS.get(rarity, Color.WHITE))
	preview.add_theme_font_size_override("font_size", 12)
	set_drag_preview(preview)
	return {"source_slot": self, "item": item_data}

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if data is not Dictionary or not data.has("source_slot"):
		return false
	# Equipment slots only accept matching types
	if is_equipment_slot() and data["item"].get("type", "") != "weapon":
		# For now, only weapon/offhand equip slots accept weapons
		if slot_type == SlotType.WEAPON or slot_type == SlotType.OFFHAND:
			return data["item"].get("type", "") == "weapon"
		return false  # Other equip slots — no armor items yet
	return true

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if data is Dictionary and data.has("source_slot"):
		item_dropped.emit(data["source_slot"], self)
