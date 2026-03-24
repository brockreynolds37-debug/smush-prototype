extends PanelContainer

## Item Tooltip — floating panel showing item details + equipped comparison.
## Spawned by InventoryUI, positioned near hovered slot.

const TOOLTIP_WIDTH := 200.0
const COMPARE_WIDTH := 190.0
const PADDING := 6

var _name_label: Label
var _rarity_label: Label
var _type_label: Label
var _stats_label: RichTextLabel
var _desc_label: Label
var _compare_panel: PanelContainer
var _compare_name: Label
var _compare_stats: RichTextLabel

# Colors
const UP_COLOR := Color(0.2, 0.9, 0.3)    # green = better
const DOWN_COLOR := Color(0.95, 0.25, 0.2)  # red = worse
const SAME_COLOR := Color(0.6, 0.6, 0.65)   # grey = same

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(TOOLTIP_WIDTH, 0)
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	# Dark background
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.1, 0.95)
	style.border_color = Color(0.35, 0.35, 0.5, 0.8)
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_width_left = 1
	style.border_width_right = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = PADDING
	style.content_margin_right = PADDING
	style.content_margin_top = PADDING
	style.content_margin_bottom = PADDING
	add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vbox)

	# Item name
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 13)
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_name_label)

	# Rarity + type row
	var type_row := HBoxContainer.new()
	type_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(type_row)

	_rarity_label = Label.new()
	_rarity_label.add_theme_font_size_override("font_size", 10)
	_rarity_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	type_row.add_child(_rarity_label)

	_type_label = Label.new()
	_type_label.add_theme_font_size_override("font_size", 10)
	_type_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	_type_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	type_row.add_child(_type_label)

	# Separator
	var sep := HSeparator.new()
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sep)

	# Stats (RichTextLabel for colored arrows)
	_stats_label = RichTextLabel.new()
	_stats_label.bbcode_enabled = true
	_stats_label.fit_content = true
	_stats_label.scroll_active = false
	_stats_label.custom_minimum_size = Vector2(TOOLTIP_WIDTH - PADDING * 2, 0)
	_stats_label.add_theme_font_size_override("normal_font_size", 11)
	_stats_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_stats_label)

	# Description
	_desc_label = Label.new()
	_desc_label.add_theme_font_size_override("font_size", 10)
	_desc_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.custom_minimum_size = Vector2(TOOLTIP_WIDTH - PADDING * 2, 0)
	_desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_desc_label)

	# Comparison panel (separate panel to the left)
	_compare_panel = PanelContainer.new()
	_compare_panel.visible = false
	_compare_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_compare_panel.custom_minimum_size = Vector2(COMPARE_WIDTH, 0)
	var cstyle := StyleBoxFlat.new()
	cstyle.bg_color = Color(0.05, 0.05, 0.08, 0.93)
	cstyle.border_color = Color(0.3, 0.3, 0.4, 0.7)
	cstyle.border_width_top = 1
	cstyle.border_width_bottom = 1
	cstyle.border_width_left = 1
	cstyle.border_width_right = 1
	cstyle.corner_radius_top_left = 4
	cstyle.corner_radius_top_right = 4
	cstyle.corner_radius_bottom_left = 4
	cstyle.corner_radius_bottom_right = 4
	cstyle.content_margin_left = PADDING
	cstyle.content_margin_right = PADDING
	cstyle.content_margin_top = PADDING
	cstyle.content_margin_bottom = PADDING
	_compare_panel.add_theme_stylebox_override("panel", cstyle)

	var cvbox := VBoxContainer.new()
	cvbox.add_theme_constant_override("separation", 3)
	cvbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_compare_panel.add_child(cvbox)

	var equipped_header := Label.new()
	equipped_header.text = "Equipped"
	equipped_header.add_theme_font_size_override("font_size", 10)
	equipped_header.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	equipped_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cvbox.add_child(equipped_header)

	_compare_name = Label.new()
	_compare_name.add_theme_font_size_override("font_size", 12)
	_compare_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_compare_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cvbox.add_child(_compare_name)

	var csep := HSeparator.new()
	csep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cvbox.add_child(csep)

	_compare_stats = RichTextLabel.new()
	_compare_stats.bbcode_enabled = true
	_compare_stats.fit_content = true
	_compare_stats.scroll_active = false
	_compare_stats.custom_minimum_size = Vector2(COMPARE_WIDTH - PADDING * 2, 0)
	_compare_stats.add_theme_font_size_override("normal_font_size", 11)
	_compare_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cvbox.add_child(_compare_stats)

	add_child(_compare_panel)
	visible = false

## Show tooltip for an item. compare_item = currently equipped item in same slot (or empty).
func show_item(item: Dictionary, compare_item: Dictionary = {}) -> void:
	if item.is_empty():
		visible = false
		return

	var rarity: int = item.get("rarity", 0)
	var rarity_color: Color = LootManager.RARITY_COLORS.get(rarity, Color.WHITE)
	var rarity_name: String = LootManager.RARITY_NAMES.get(rarity, "Common")

	_name_label.text = item.get("name", "Unknown")
	_name_label.add_theme_color_override("font_color", rarity_color)

	_rarity_label.text = rarity_name + "  "
	_rarity_label.add_theme_color_override("font_color", rarity_color)

	var item_type: String = item.get("type", "")
	var subtype: String = item.get("subtype", "")
	if subtype != "":
		_type_label.text = subtype.capitalize()
	elif item_type == "armor":
		_type_label.text = item.get("equip_slot", "Armor").capitalize()
	elif item_type == "consumable":
		_type_label.text = "Consumable"
	elif item_type == "currency":
		_type_label.text = "Currency"
	else:
		_type_label.text = item_type.capitalize()

	# Build stats BBCode
	_stats_label.text = ""
	var stats_bbcode := _build_stats_bbcode(item, compare_item)
	_stats_label.text = stats_bbcode

	# Description — show the base description only (without rolled stat suffix)
	var desc: String = item.get("description", "")
	# The base description is the part before the rolled stats we appended
	# Items have their base_description in the template; rolled items append stats.
	# We already show stats above, so just show the flavor text
	var base_desc := desc
	# If description has appended stats (contains "+"), show only up to that
	var plus_idx := desc.find(" +")
	if plus_idx > 0 and (item_type == "weapon" or item_type == "armor"):
		base_desc = desc.substr(0, plus_idx).strip_edges()
	_desc_label.text = base_desc

	# Comparison panel
	if not compare_item.is_empty() and compare_item.get("type", "") in ["weapon", "armor"]:
		_show_comparison(compare_item)
	else:
		_compare_panel.visible = false

	visible = true

	# Wait a frame for size to update, then reposition comparison panel
	await get_tree().process_frame
	_position_compare_panel()

func _show_comparison(equipped: Dictionary) -> void:
	var eq_rarity: int = equipped.get("rarity", 0)
	var eq_color: Color = LootManager.RARITY_COLORS.get(eq_rarity, Color.WHITE)
	_compare_name.text = equipped.get("name", "?")
	_compare_name.add_theme_color_override("font_color", eq_color)

	_compare_stats.text = ""
	_compare_stats.text = _build_stats_bbcode(equipped, {})
	_compare_panel.visible = true

func _position_compare_panel() -> void:
	if not _compare_panel.visible:
		return
	# Place comparison panel to the left of main tooltip
	_compare_panel.position = Vector2(-_compare_panel.size.x - 4, 0)

func _build_stats_bbcode(item: Dictionary, compare_item: Dictionary) -> String:
	var lines: Array[String] = []
	var stat_defs := [
		["damage_bonus", "Damage", ""],
		["str_bonus", "STR", ""],
		["int_bonus", "INT", ""],
		["dex_bonus", "DEX", ""],
		["con_bonus", "CON", ""],
		["crit_bonus", "Crit", "%"],
		["spell_power_bonus", "Spell Power", ""],
		["armor_bonus", "Armor", ""],
		["hp_bonus", "HP", ""],
		["speed_bonus", "Speed", "%"],
		["heal_amount", "Heal", ""],
		["mana_amount", "Mana", ""],
	]

	for def in stat_defs:
		var key: String = def[0]
		var label: String = def[1]
		var suffix: String = def[2]
		var val: int = item.get(key, 0)
		if val == 0:
			continue

		var line := "+%d%s %s" % [val, suffix, label]

		# Comparison arrows
		if not compare_item.is_empty():
			var cmp_val: int = compare_item.get(key, 0)
			var diff := val - cmp_val
			if diff > 0:
				line = "[color=#33e855]" + line + " [/color][color=#33e855]+%d[/color]" % diff
			elif diff < 0:
				line = "[color=#f24040]" + line + " [/color][color=#f24040]%d[/color]" % diff
			else:
				line = "[color=#9999a5]" + line + "[/color]"
		else:
			line = "[color=#ccccdd]" + line + "[/color]"

		lines.append(line)

	if lines.is_empty():
		lines.append("[color=#9999a5]No stats[/color]")

	return "\n".join(lines)

func hide_tooltip() -> void:
	visible = false
	_compare_panel.visible = false
