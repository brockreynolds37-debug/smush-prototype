extends CanvasLayer

## CraftingUI — forge station interface.
## Shows known recipes, ingredient slots, and discovered/undiscovered recipes.
## Triggered by interacting with a ForgeStation in the world.

signal crafting_closed
signal item_crafted(result_item: Dictionary)

var _panel: PanelContainer
var _slot_a_item: Dictionary = {}
var _slot_b_item: Dictionary = {}
var _result_panel: PanelContainer
var _result_label: Label
var _craft_button: Button
var _recipe_list: VBoxContainer
var _status_label: Label

## Recipes are keyed by sorted ingredient pair, e.g. "iron_sword+rusty_dagger"
const RECIPES := {
	"rusty_dagger+iron_sword": {
		"result_id": "twin_blade",
		"name": "Twin Blade",
		"description": "A double-edged blade forged from two lesser swords. +15% attack speed.",
		"rarity": 2,  # RARE
		"type": "weapon",
		"damage": 38,
		"attack_speed_bonus": 0.15,
		"mesh_color": Color(0.7, 0.7, 0.9),
		"model": "",
		"hint": "Rusty Dagger + Iron Sword",
	},
	"iron_axe+rusty_dagger": {
		"result_id": "cleave_axe",
		"name": "Cleave Axe",
		"description": "A brutal axe with a notched blade that tears through crowds. Cleave hits adjacent enemies.",
		"rarity": 2,
		"type": "weapon",
		"damage": 44,
		"cleave": true,
		"mesh_color": Color(0.6, 0.3, 0.1),
		"model": "",
		"hint": "Iron Axe + Rusty Dagger",
	},
	"iron_axe+steel_sword": {
		"result_id": "vorpal_blade",
		"name": "Vorpal Blade",
		"description": "An impossibly sharp edge. 25% chance to deal triple damage on hit.",
		"rarity": 3,  # EPIC
		"type": "weapon",
		"damage": 62,
		"crit_chance": 0.25,
		"crit_multiplier": 3.0,
		"mesh_color": Color(0.5, 0.8, 1.0),
		"model": "",
		"hint": "Iron Axe + Steel Sword",
	},
	"health_potion+mana_potion": {
		"result_id": "elixir_vial",
		"name": "Elixir Vial",
		"description": "A shimmering dual-phase potion. Restores 80 health AND 50 mana.",
		"rarity": 1,  # UNCOMMON
		"type": "consumable",
		"heal_amount": 80,
		"mana_amount": 50,
		"mesh_color": Color(0.7, 0.3, 0.9),
		"model": "",
		"hint": "Health Potion + Mana Potion",
	},
	"iron_sword+steel_sword": {
		"result_id": "reforged_broadsword",
		"name": "Reforged Broadsword",
		"description": "Two swords melted down and recast into a powerful broadsword.",
		"rarity": 2,
		"type": "weapon",
		"damage": 52,
		"mesh_color": Color(0.85, 0.85, 0.5),
		"model": "",
		"hint": "Iron Sword + Steel Sword",
	},
	"iron_axe+iron_axe": {
		"result_id": "twin_fury",
		"name": "Twin Fury",
		"description": "Two axes fused into a spinning death wheel. Crits apply bleed.",
		"rarity": 3,
		"type": "weapon",
		"damage": 55,
		"bleed_on_crit": true,
		"mesh_color": Color(0.9, 0.2, 0.2),
		"model": "",
		"hint": "Iron Axe + Iron Axe",
	},
}

## Recipes Brock has discovered this run (persisted to LootManager)
var _discovered_recipe_keys: Array[String] = []

func _ready() -> void:
	layer = 95
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

func open_forge() -> void:
	for child in get_children():
		child.queue_free()

	_build_ui()
	visible = true
	get_tree().paused = true

func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.05, 0.03, 0.06, 0.97)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_CENTER)
	root.custom_minimum_size = Vector2(700, 520)
	root.offset_left = -350
	root.offset_top = -260
	root.offset_right = 350
	root.offset_bottom = 260
	add_child(root)

	# Title
	var title := Label.new()
	title.text = "⚒  THE FORGE"
	title.add_theme_font_size_override("font_size", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.modulate = Color(1.0, 0.75, 0.2)
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Combine two items to forge something greater"
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(0.7, 0.7, 0.7)
	root.add_child(subtitle)

	root.add_child(_spacer(8))

	# Main HBox: left inventory | center forge | right recipes
	var hbox := HBoxContainer.new()
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(hbox)

	# Left: Inventory picker
	var inv_panel := _make_panel(Color(0.1, 0.08, 0.12))
	inv_panel.custom_minimum_size = Vector2(200, 0)
	hbox.add_child(inv_panel)
	var inv_vbox := VBoxContainer.new()
	inv_panel.add_child(inv_vbox)
	var inv_title := Label.new()
	inv_title.text = "Your Items"
	inv_title.add_theme_font_size_override("font_size", 14)
	inv_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inv_vbox.add_child(inv_title)
	_build_inventory_list(inv_vbox)

	# Center: Forge slots
	var forge_vbox := VBoxContainer.new()
	forge_vbox.custom_minimum_size = Vector2(220, 0)
	forge_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(forge_vbox)

	var slot_label_a := Label.new()
	slot_label_a.text = "SLOT A"
	slot_label_a.add_theme_font_size_override("font_size", 11)
	slot_label_a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot_label_a.modulate = Color(0.6, 0.6, 0.6)
	forge_vbox.add_child(slot_label_a)

	var slot_a := _make_item_slot("slot_a")
	forge_vbox.add_child(slot_a)

	var plus := Label.new()
	plus.text = "+"
	plus.add_theme_font_size_override("font_size", 24)
	plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plus.modulate = Color(1.0, 0.75, 0.2)
	forge_vbox.add_child(plus)

	var slot_label_b := Label.new()
	slot_label_b.text = "SLOT B"
	slot_label_b.add_theme_font_size_override("font_size", 11)
	slot_label_b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot_label_b.modulate = Color(0.6, 0.6, 0.6)
	forge_vbox.add_child(slot_label_b)

	var slot_b := _make_item_slot("slot_b")
	forge_vbox.add_child(slot_b)

	forge_vbox.add_child(_spacer(12))

	var arrow := Label.new()
	arrow.text = "▼"
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrow.modulate = Color(1.0, 0.75, 0.2)
	forge_vbox.add_child(arrow)

	# Result slot
	var result_label_header := Label.new()
	result_label_header.text = "RESULT"
	result_label_header.add_theme_font_size_override("font_size", 11)
	result_label_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label_header.modulate = Color(0.6, 0.6, 0.6)
	forge_vbox.add_child(result_label_header)

	_result_panel = _make_panel(Color(0.08, 0.12, 0.08))
	_result_panel.custom_minimum_size = Vector2(160, 60)
	forge_vbox.add_child(_result_panel)
	_result_label = Label.new()
	_result_label.text = "—"
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_result_label.add_theme_font_size_override("font_size", 13)
	_result_label.modulate = Color(0.5, 0.5, 0.5)
	_result_panel.add_child(_result_label)

	forge_vbox.add_child(_spacer(8))

	_craft_button = Button.new()
	_craft_button.text = "FORGE"
	_craft_button.disabled = true
	_craft_button.add_theme_font_size_override("font_size", 16)
	_craft_button.custom_minimum_size = Vector2(160, 44)
	_craft_button.pressed.connect(_on_craft_pressed)
	forge_vbox.add_child(_craft_button)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 12)
	forge_vbox.add_child(_status_label)

	# Right: Recipe book
	var recipe_panel := _make_panel(Color(0.08, 0.06, 0.12))
	recipe_panel.custom_minimum_size = Vector2(200, 0)
	hbox.add_child(recipe_panel)
	var recipe_vbox := VBoxContainer.new()
	recipe_panel.add_child(recipe_vbox)
	var recipe_title := Label.new()
	recipe_title.text = "Recipe Book"
	recipe_title.add_theme_font_size_override("font_size", 14)
	recipe_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	recipe_vbox.add_child(recipe_title)
	_recipe_list = VBoxContainer.new()
	recipe_vbox.add_child(_recipe_list)
	_refresh_recipe_book()

	# Close button
	root.add_child(_spacer(8))
	var close_btn := Button.new()
	close_btn.text = "Leave Forge"
	close_btn.pressed.connect(_on_close)
	root.add_child(close_btn)

func _build_inventory_list(parent: VBoxContainer) -> void:
	var inv: Array = LootManager.inventory if LootManager else []
	if inv.is_empty():
		var empty := Label.new()
		empty.text = "(no items)"
		empty.modulate = Color(0.5, 0.5, 0.5)
		parent.add_child(empty)
		return

	for item in inv:
		var btn := Button.new()
		var rarity_names := ["", "★", "★★", "★★★", "★★★★"]
		var r := item.get("rarity", 0)
		btn.text = "%s %s" % [rarity_names[mini(r, 4)], item.get("name", "?")]
		btn.custom_minimum_size = Vector2(0, 28)
		btn.pressed.connect(_on_inventory_item_clicked.bind(item))
		parent.add_child(btn)

func _make_item_slot(slot_id: String) -> PanelContainer:
	var panel := _make_panel(Color(0.12, 0.1, 0.15))
	panel.custom_minimum_size = Vector2(160, 52)
	panel.set_meta("slot_id", slot_id)

	var lbl := Label.new()
	lbl.name = "SlotLabel"
	lbl.text = "[ Empty ]"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.modulate = Color(0.4, 0.4, 0.4)
	panel.add_child(lbl)

	if slot_id == "slot_a":
		panel.set_meta("label_ref", lbl)
		panel.name = "SlotA"
	else:
		panel.set_meta("label_ref", lbl)
		panel.name = "SlotB"

	return panel

func _make_panel(bg: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _spacer(h: int) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	return s

func _on_inventory_item_clicked(item: Dictionary) -> void:
	if _slot_a_item.is_empty():
		_slot_a_item = item
		_update_slot_label("SlotA", item)
	elif _slot_b_item.is_empty() and item.get("id", "") != _slot_a_item.get("id", "__"):
		_slot_b_item = item
		_update_slot_label("SlotB", item)
	else:
		# Clear and re-assign
		_slot_a_item = item
		_slot_b_item = {}
		_update_slot_label("SlotA", item)
		_update_slot_label("SlotB", {})
	_check_recipe()

func _update_slot_label(slot_name: String, item: Dictionary) -> void:
	var panel := _find_slot(slot_name)
	if panel == null:
		return
	var lbl: Label = panel.get_node_or_null("SlotLabel")
	if lbl == null:
		return
	if item.is_empty():
		lbl.text = "[ Empty ]"
		lbl.modulate = Color(0.4, 0.4, 0.4)
	else:
		lbl.text = item.get("name", "?")
		lbl.modulate = Color(1.0, 1.0, 1.0)

func _find_slot(slot_name: String) -> PanelContainer:
	return get_node_or_null("../." + slot_name) if false else _find_node_by_name(get_children(), slot_name)

func _find_node_by_name(nodes: Array, target: String) -> Node:
	for n in nodes:
		if n.name == target:
			return n
		var found := _find_node_by_name(n.get_children(), target)
		if found:
			return found
	return null

func _check_recipe() -> void:
	if _slot_a_item.is_empty() or _slot_b_item.is_empty():
		_result_label.text = "—"
		_result_label.modulate = Color(0.5, 0.5, 0.5)
		_craft_button.disabled = true
		return

	var key := _recipe_key(_slot_a_item.get("id", ""), _slot_b_item.get("id", ""))
	if RECIPES.has(key):
		var recipe: Dictionary = RECIPES[key]
		_result_label.text = recipe["name"]
		_result_label.modulate = Color(1.0, 0.85, 0.3)
		_craft_button.disabled = false
		_status_label.text = recipe["description"]
		_status_label.modulate = Color(0.7, 0.9, 0.7)

		# Discover recipe
		if key not in _discovered_recipe_keys:
			_discovered_recipe_keys.append(key)
			_refresh_recipe_book()
	else:
		_result_label.text = "No recipe found"
		_result_label.modulate = Color(0.9, 0.4, 0.4)
		_craft_button.disabled = true
		_status_label.text = ""

func _recipe_key(id_a: String, id_b: String) -> String:
	var ids := [id_a, id_b]
	ids.sort()
	return "%s+%s" % [ids[0], ids[1]]

func _on_craft_pressed() -> void:
	var key := _recipe_key(_slot_a_item.get("id", ""), _slot_b_item.get("id", ""))
	if not RECIPES.has(key):
		return

	var recipe: Dictionary = RECIPES[key].duplicate()

	# Remove the two ingredients from inventory
	if LootManager:
		LootManager.remove_item(_slot_a_item)
		LootManager.remove_item(_slot_b_item)
		# Add the crafted item
		LootManager.inventory.append(recipe)
		LootManager.inventory_changed.emit()

	item_crafted.emit(recipe)

	# Show result flash
	_status_label.text = "✔ Forged: %s!" % recipe["name"]
	_status_label.modulate = Color(0.3, 1.0, 0.4)

	# Reset slots
	_slot_a_item = {}
	_slot_b_item = {}
	_update_slot_label("SlotA", {})
	_update_slot_label("SlotB", {})
	_result_label.text = "—"
	_result_label.modulate = Color(0.5, 0.5, 0.5)
	_craft_button.disabled = true

	# Rebuild inventory list so used items are gone
	var inv_panel := _find_node_by_name(get_children(), "VBoxContainer")
	# Just close and reopen for simplicity — the player sees the result
	await get_tree().create_timer(1.2).timeout
	_on_close()

func _refresh_recipe_book() -> void:
	if _recipe_list == null:
		return
	for child in _recipe_list.get_children():
		child.queue_free()

	var all_keys := RECIPES.keys()
	for key in all_keys:
		var recipe: Dictionary = RECIPES[key]
		var is_known := key in _discovered_recipe_keys
		var entry := Label.new()
		if is_known:
			entry.text = "✔ %s\n  %s" % [recipe["name"], recipe["hint"]]
			entry.modulate = Color(0.9, 0.9, 0.5)
		else:
			entry.text = "??? (undiscovered)"
			entry.modulate = Color(0.4, 0.4, 0.4)
		entry.add_theme_font_size_override("font_size", 11)
		_recipe_list.add_child(entry)

		var sep := HSeparator.new()
		_recipe_list.add_child(sep)

func _on_close() -> void:
	get_tree().paused = false
	visible = false
	crafting_closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_close()
		get_viewport().set_input_as_handled()
