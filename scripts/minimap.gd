extends Control

## Minimap — draws a top-down fog-of-war map of the dungeon.
## Reads grid data from DungeonBuilder, tracks explored cells,
## shows hero (green), enemies (red), and exit (yellow).
## v2: room names on hover, legend, soft fog edges, hero-centered panning.

const EXPLORE_RADIUS := 6
const ENEMY_VISIBLE_RADIUS := 8
const FOG_FADE_RADIUS := 2  # Extra cells around explored edge that fade in

# Colors
const COLOR_UNEXPLORED := Color(0.06, 0.06, 0.08, 1.0)
const COLOR_FLOOR := Color(0.25, 0.22, 0.2, 1.0)
const COLOR_WALL := Color(0.4, 0.36, 0.32, 1.0)
const COLOR_HERO := Color(0.2, 0.9, 0.3, 1.0)
const COLOR_ENEMY := Color(0.9, 0.15, 0.15, 1.0)
const COLOR_EXIT := Color(1.0, 0.85, 0.2, 1.0)
const COLOR_SPAWN := Color(0.3, 0.5, 1.0, 0.8)
const COLOR_TRAP := Color(1.0, 0.4, 0.1, 0.9)
const COLOR_CHEST := Color(1.0, 0.85, 0.2, 0.9)
const COLOR_BARREL := Color(0.55, 0.38, 0.2, 0.8)
const COLOR_ELITE := Color(0.8, 0.2, 0.8, 1.0)

# Grid data (copied from DungeonBuilder)
var grid: Dictionary = {}
var grid_min := Vector2i.ZERO
var grid_max := Vector2i.ZERO
var spawn_cell := Vector2i.ZERO
var exit_cell := Vector2i.ZERO
var tile_size := 2.0
var rooms: Array[Dictionary] = []

# Fog of war
var explored: Dictionary = {}  # Vector2i → true
var fog_alpha: Dictionary = {}  # Vector2i → float (0.0-1.0 for partially revealed cells)

# Rendering
var cell_px: float = 3.0
var map_offset := Vector2.ZERO

# Panning — offset map so hero stays centered
var pan_offset := Vector2.ZERO
var pan_enabled := true

# Hover tooltip
var _hovered_room_name := ""
var _tooltip_label: Label = null

# Legend
var _legend_panel: PanelContainer = null
var _legend_visible := false

func _ready() -> void:
	FloorManager.floor_changed.connect(_on_floor_changed)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_create_tooltip()
	_create_legend()
	await get_tree().create_timer(0.2).timeout
	_refresh_grid()

func _create_tooltip() -> void:
	_tooltip_label = Label.new()
	_tooltip_label.add_theme_font_size_override("font_size", 10)
	_tooltip_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	_tooltip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tooltip_label.visible = false
	_tooltip_label.z_index = 10
	add_child(_tooltip_label)

func _create_legend() -> void:
	_legend_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.85)
	style.border_color = Color(0.3, 0.28, 0.24)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(4)
	_legend_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 1)

	var entries := [
		[AccessibilitySettings.get_hero_color(), "Hero"],
		[AccessibilitySettings.get_enemy_color(), "Enemy"],
		[COLOR_EXIT, "Exit"],
		[COLOR_CHEST, "Chest"],
		[COLOR_TRAP, "Trap"],
		[COLOR_SPAWN, "Spawn"],
	]
	for entry in entries:
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 3)
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(8, 8)
		swatch.color = entry[0]
		hbox.add_child(swatch)
		var lbl := Label.new()
		lbl.text = entry[1]
		lbl.add_theme_font_size_override("font_size", 9)
		lbl.add_theme_color_override("font_color", Color(0.7, 0.65, 0.6))
		hbox.add_child(lbl)
		vbox.add_child(hbox)

	_legend_panel.add_child(vbox)
	_legend_panel.visible = false
	_legend_panel.z_index = 10
	add_child(_legend_panel)

func _on_floor_changed(_floor_num: int) -> void:
	await get_tree().create_timer(0.3).timeout
	explored.clear()
	fog_alpha.clear()
	_refresh_grid()

func _refresh_grid() -> void:
	var builder = _find_dungeon_builder()
	if builder == null:
		return

	grid = builder.grid.duplicate()
	grid_min = builder.grid_min
	grid_max = builder.grid_max
	spawn_cell = builder.spawn_cell
	exit_cell = builder.exit_cell
	tile_size = builder.TILE_SIZE
	rooms = builder.rooms.duplicate()

	var grid_width := grid_max.x - grid_min.x + 1
	var grid_height := grid_max.y - grid_min.y + 1
	if grid_width <= 0 or grid_height <= 0:
		return

	var available := size
	var scale_x := available.x / float(grid_width)
	var scale_y := available.y / float(grid_height)
	cell_px = minf(scale_x, scale_y)

	var map_w := grid_width * cell_px
	var map_h := grid_height * cell_px
	map_offset = Vector2((available.x - map_w) / 2.0, (available.y - map_h) / 2.0)

	queue_redraw()

func _find_dungeon_builder() -> Node:
	var root = get_tree().root
	return _find_node_recursive(root, "DungeonBuilder")

func _find_node_recursive(node: Node, target_name: String) -> Node:
	if node.name == target_name:
		return node
	for child in node.get_children():
		var result = _find_node_recursive(child, target_name)
		if result:
			return result
	return null

func _process(_delta: float) -> void:
	if grid.is_empty():
		return
	_update_explored()
	_update_pan()
	_update_hover()
	queue_redraw()

func _update_explored() -> void:
	var hero = GameManager.hero
	if hero == null or not is_instance_valid(hero):
		return

	var hero_cell := _world_to_cell(hero.global_position)

	# Reveal cells within explore radius (fully explored)
	var full_radius := EXPLORE_RADIUS + FOG_FADE_RADIUS
	for dx in range(-full_radius, full_radius + 1):
		for dy in range(-full_radius, full_radius + 1):
			var dist_sq := dx * dx + dy * dy
			if dist_sq > full_radius * full_radius:
				continue
			var cell := Vector2i(hero_cell.x + dx, hero_cell.y + dy)
			if not grid.has(cell):
				continue

			if dist_sq <= EXPLORE_RADIUS * EXPLORE_RADIUS:
				# Fully explored
				explored[cell] = true
				fog_alpha[cell] = 1.0
			elif not explored.has(cell):
				# Fade zone — partially revealed
				var dist := sqrt(float(dist_sq))
				var fade_start := float(EXPLORE_RADIUS)
				var fade_end := float(full_radius)
				var alpha := 1.0 - clampf((dist - fade_start) / (fade_end - fade_start), 0.0, 1.0)
				# Only increase alpha (don't dim previously explored cells)
				if not fog_alpha.has(cell) or fog_alpha[cell] < alpha:
					fog_alpha[cell] = alpha

func _update_pan() -> void:
	if not pan_enabled:
		pan_offset = Vector2.ZERO
		return

	var hero = GameManager.hero
	if hero == null or not is_instance_valid(hero):
		return

	var hero_cell := _world_to_cell(hero.global_position)
	var hero_screen := _cell_to_screen_raw(hero_cell)
	var center := size / 2.0

	# If hero dot is within 25% of any edge, pan to keep centered
	var margin := size * 0.25
	var need_pan := false
	if hero_screen.x < margin.x or hero_screen.x > size.x - margin.x:
		need_pan = true
	if hero_screen.y < margin.y or hero_screen.y > size.y - margin.y:
		need_pan = true

	if need_pan:
		var target_pan := center - hero_screen
		pan_offset = pan_offset.lerp(target_pan, 0.1)
	else:
		pan_offset = pan_offset.lerp(Vector2.ZERO, 0.05)

func _update_hover() -> void:
	var mouse_pos := get_local_mouse_position()
	if not Rect2(Vector2.ZERO, size).has_point(mouse_pos):
		_hovered_room_name = ""
		_tooltip_label.visible = false
		_legend_panel.visible = false
		return

	# Show legend when hovering the minimap
	if not _legend_panel.visible:
		_legend_panel.visible = true
		_legend_panel.position = Vector2(2, size.y - _legend_panel.size.y - 2)

	# Find which room the mouse is over
	var cell := _screen_to_cell(mouse_pos)
	_hovered_room_name = ""

	for room in rooms:
		var rpos: Vector2i = room.get("pos", Vector2i.ZERO)
		var rsize: Vector2i = room.get("size", Vector2i.ZERO)
		var rname: String = room.get("name", "")
		if rname.is_empty():
			continue
		if cell.x >= rpos.x and cell.x < rpos.x + rsize.x and \
		   cell.y >= rpos.y and cell.y < rpos.y + rsize.y:
			# Only show name if at least one cell of this room is explored
			for rx in range(rpos.x, rpos.x + rsize.x):
				for ry in range(rpos.y, rpos.y + rsize.y):
					if explored.has(Vector2i(rx, ry)):
						_hovered_room_name = rname
						break
				if not _hovered_room_name.is_empty():
					break
			break

	if _hovered_room_name.is_empty():
		_tooltip_label.visible = false
	else:
		_tooltip_label.text = _hovered_room_name
		_tooltip_label.visible = true
		# Position tooltip near mouse, clamped within minimap
		var tp := mouse_pos + Vector2(8, -16)
		tp.x = clampf(tp.x, 0, size.x - _tooltip_label.size.x)
		tp.y = clampf(tp.y, 0, size.y - _tooltip_label.size.y)
		_tooltip_label.position = tp

func _world_to_cell(world_pos: Vector3) -> Vector2i:
	return Vector2i(roundi(world_pos.x / tile_size), roundi(world_pos.z / tile_size))

func _cell_to_screen_raw(cell: Vector2i) -> Vector2:
	## Screen position WITHOUT pan offset (used for pan calculations)
	var local := Vector2(cell.x - grid_min.x, cell.y - grid_min.y)
	return map_offset + local * cell_px

func _cell_to_screen(cell: Vector2i) -> Vector2:
	return _cell_to_screen_raw(cell) + pan_offset

func _screen_to_cell(screen_pos: Vector2) -> Vector2i:
	var adjusted := screen_pos - map_offset - pan_offset
	var cx := int(adjusted.x / cell_px) + grid_min.x
	var cy := int(adjusted.y / cell_px) + grid_min.y
	return Vector2i(cx, cy)

func _draw() -> void:
	if grid.is_empty():
		return

	# Clip drawing to minimap bounds
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_UNEXPLORED)

	# Draw floor cells with fog alpha
	for cell in grid.keys():
		var alpha := fog_alpha.get(cell, 0.0)
		if alpha <= 0.01:
			continue
		var screen_pos := _cell_to_screen(cell)
		# Skip cells entirely outside visible area
		if screen_pos.x + cell_px < 0 or screen_pos.x > size.x:
			continue
		if screen_pos.y + cell_px < 0 or screen_pos.y > size.y:
			continue
		var rect := Rect2(screen_pos, Vector2(cell_px, cell_px))
		var col := COLOR_FLOOR
		col.a = alpha
		draw_rect(rect, col)

	# Draw walls with fog alpha
	for cell in fog_alpha.keys():
		var alpha: float = fog_alpha[cell]
		if alpha <= 0.01 or not grid.has(cell):
			continue
		var dirs := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
		for dir in dirs:
			var neighbor := cell + dir
			if not grid.has(neighbor):
				var screen_pos := _cell_to_screen(cell)
				var from := Vector2.ZERO
				var to := Vector2.ZERO
				if dir == Vector2i(0, -1):
					from = screen_pos
					to = screen_pos + Vector2(cell_px, 0)
				elif dir == Vector2i(1, 0):
					from = screen_pos + Vector2(cell_px, 0)
					to = screen_pos + Vector2(cell_px, cell_px)
				elif dir == Vector2i(0, 1):
					from = screen_pos + Vector2(0, cell_px)
					to = screen_pos + Vector2(cell_px, cell_px)
				elif dir == Vector2i(-1, 0):
					from = screen_pos
					to = screen_pos + Vector2(0, cell_px)
				var wall_col := COLOR_WALL
				wall_col.a = alpha
				draw_line(from, to, wall_col, 1.5)

	# Draw special tile markers
	for cell in explored.keys():
		if not grid.has(cell):
			continue
		var tile_type = grid[cell]
		var marker_pos := _cell_to_screen(cell) + Vector2(cell_px / 2.0, cell_px / 2.0)
		if tile_type >= 8 and tile_type <= 10:
			draw_circle(marker_pos, cell_px * 0.4, COLOR_TRAP)
		elif tile_type == 6:
			draw_circle(marker_pos, cell_px * 0.5, COLOR_CHEST)
		elif tile_type == 7:
			draw_circle(marker_pos, cell_px * 0.3, COLOR_BARREL)

	# Draw exit marker
	if explored.has(exit_cell):
		var exit_center := _cell_to_screen(exit_cell) + Vector2(cell_px / 2.0, cell_px / 2.0)
		draw_circle(exit_center, cell_px * 0.8, COLOR_EXIT)

	# Draw spawn marker
	if explored.has(spawn_cell):
		var spawn_center := _cell_to_screen(spawn_cell) + Vector2(cell_px / 2.0, cell_px / 2.0)
		draw_circle(spawn_center, cell_px * 0.6, COLOR_SPAWN)

	# Draw enemies
	var hero = GameManager.hero
	if hero and is_instance_valid(hero):
		var hero_cell := _world_to_cell(hero.global_position)

		for enemy in GameManager.enemies:
			if not is_instance_valid(enemy) or enemy.is_dead:
				continue
			var enemy_cell := _world_to_cell(enemy.global_position)
			if not explored.has(enemy_cell):
				continue
			var dist := absi(enemy_cell.x - hero_cell.x) + absi(enemy_cell.y - hero_cell.y)
			if dist > ENEMY_VISIBLE_RADIUS:
				continue
			var enemy_center := _cell_to_screen(enemy_cell) + Vector2(cell_px / 2.0, cell_px / 2.0)
			# Elite enemies get a different color (colorblind-aware)
			var ecol := AccessibilitySettings.get_enemy_color()
			if enemy.has_meta("elite_prefix"):
				ecol = AccessibilitySettings.get_elite_color()
			draw_circle(enemy_center, cell_px * 0.6, ecol)

		# Draw hero (on top, colorblind-aware)
		var hero_screen := _cell_to_screen(hero_cell)
		var hero_center := hero_screen + Vector2(cell_px / 2.0, cell_px / 2.0)
		draw_circle(hero_center, cell_px * 0.8, AccessibilitySettings.get_hero_color())

	# Draw hovered room outline
	if not _hovered_room_name.is_empty():
		for room in rooms:
			if room.get("name", "") == _hovered_room_name:
				var rpos: Vector2i = room.get("pos", Vector2i.ZERO)
				var rsize: Vector2i = room.get("size", Vector2i.ZERO)
				var tl := _cell_to_screen(rpos)
				var br := _cell_to_screen(Vector2i(rpos.x + rsize.x, rpos.y + rsize.y))
				var outline_rect := Rect2(tl, br - tl)
				draw_rect(outline_rect, Color(0.9, 0.8, 0.5, 0.4), false, 1.5)
				break
