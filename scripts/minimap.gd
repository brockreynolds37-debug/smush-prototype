extends Control

## Minimap — draws a top-down fog-of-war map of the dungeon.
## Reads grid data from DungeonBuilder, tracks explored cells,
## shows hero (green), enemies (red), and exit (yellow).

const EXPLORE_RADIUS := 6  # Grid cells revealed around hero
const ENEMY_VISIBLE_RADIUS := 8  # Grid cells within which enemies show on map

# Colors
const COLOR_UNEXPLORED := Color(0.06, 0.06, 0.08, 1.0)
const COLOR_FLOOR := Color(0.25, 0.22, 0.2, 1.0)
const COLOR_WALL := Color(0.4, 0.36, 0.32, 1.0)
const COLOR_HERO := Color(0.2, 0.9, 0.3, 1.0)
const COLOR_ENEMY := Color(0.9, 0.15, 0.15, 1.0)
const COLOR_EXIT := Color(1.0, 0.85, 0.2, 1.0)
const COLOR_SPAWN := Color(0.3, 0.5, 1.0, 0.8)

# Grid data (copied from DungeonBuilder)
var grid: Dictionary = {}
var grid_min := Vector2i.ZERO
var grid_max := Vector2i.ZERO
var spawn_cell := Vector2i.ZERO
var exit_cell := Vector2i.ZERO
var tile_size := 2.0  # World units per grid cell (from DungeonBuilder)

# Fog of war
var explored: Dictionary = {}  # Vector2i → true

# Rendering
var cell_px: float = 3.0  # Pixels per grid cell (auto-calculated)
var map_offset := Vector2.ZERO  # Offset to center the map

func _ready() -> void:
	# Refresh grid when floor changes
	FloorManager.floor_changed.connect(_on_floor_changed)
	# Initial load after a frame (DungeonBuilder needs to build first)
	await get_tree().create_timer(0.2).timeout
	_refresh_grid()

func _on_floor_changed(_floor_num: int) -> void:
	# Wait for dungeon to rebuild
	await get_tree().create_timer(0.3).timeout
	explored.clear()
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

	# Calculate cell pixel size to fit the available area
	var grid_width := grid_max.x - grid_min.x + 1
	var grid_height := grid_max.y - grid_min.y + 1
	if grid_width <= 0 or grid_height <= 0:
		return

	var available := size
	var scale_x := available.x / float(grid_width)
	var scale_y := available.y / float(grid_height)
	cell_px = minf(scale_x, scale_y)

	# Center offset
	var map_w := grid_width * cell_px
	var map_h := grid_height * cell_px
	map_offset = Vector2((available.x - map_w) / 2.0, (available.y - map_h) / 2.0)

	queue_redraw()

func _find_dungeon_builder() -> Node:
	# Search scene tree for the DungeonBuilder node
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
	queue_redraw()

func _update_explored() -> void:
	var hero = GameManager.hero
	if hero == null or not is_instance_valid(hero):
		return

	var hero_cell := _world_to_cell(hero.global_position)

	# Reveal cells within explore radius
	for dx in range(-EXPLORE_RADIUS, EXPLORE_RADIUS + 1):
		for dy in range(-EXPLORE_RADIUS, EXPLORE_RADIUS + 1):
			if dx * dx + dy * dy <= EXPLORE_RADIUS * EXPLORE_RADIUS:
				var cell := Vector2i(hero_cell.x + dx, hero_cell.y + dy)
				if grid.has(cell):
					explored[cell] = true

func _world_to_cell(world_pos: Vector3) -> Vector2i:
	return Vector2i(roundi(world_pos.x / tile_size), roundi(world_pos.z / tile_size))

func _cell_to_screen(cell: Vector2i) -> Vector2:
	var local := Vector2(cell.x - grid_min.x, cell.y - grid_min.y)
	return map_offset + local * cell_px

func _draw() -> void:
	if grid.is_empty():
		return

	# Background
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_UNEXPLORED)

	# Draw explored floor cells
	for cell in grid.keys():
		if not explored.has(cell):
			continue
		var screen_pos := _cell_to_screen(cell)
		var rect := Rect2(screen_pos, Vector2(cell_px, cell_px))
		draw_rect(rect, COLOR_FLOOR)

	# Draw walls (explored cells that border empty space)
	for cell in explored.keys():
		if not grid.has(cell):
			continue
		var dirs := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
		for dir in dirs:
			var neighbor := cell + dir
			if not grid.has(neighbor):
				# Draw a thin wall line on this edge
				var screen_pos := _cell_to_screen(cell)
				var from := Vector2.ZERO
				var to := Vector2.ZERO
				if dir == Vector2i(0, -1):  # North
					from = screen_pos
					to = screen_pos + Vector2(cell_px, 0)
				elif dir == Vector2i(1, 0):  # East
					from = screen_pos + Vector2(cell_px, 0)
					to = screen_pos + Vector2(cell_px, cell_px)
				elif dir == Vector2i(0, 1):  # South
					from = screen_pos + Vector2(0, cell_px)
					to = screen_pos + Vector2(cell_px, cell_px)
				elif dir == Vector2i(-1, 0):  # West
					from = screen_pos
					to = screen_pos + Vector2(0, cell_px)
				draw_line(from, to, COLOR_WALL, 1.5)

	# Draw exit marker (if explored)
	if explored.has(exit_cell):
		var exit_screen := _cell_to_screen(exit_cell)
		var exit_center := exit_screen + Vector2(cell_px / 2.0, cell_px / 2.0)
		draw_circle(exit_center, cell_px * 0.8, COLOR_EXIT)

	# Draw spawn marker (if explored)
	if explored.has(spawn_cell):
		var spawn_screen := _cell_to_screen(spawn_cell)
		var spawn_center := spawn_screen + Vector2(cell_px / 2.0, cell_px / 2.0)
		draw_circle(spawn_center, cell_px * 0.6, COLOR_SPAWN)

	# Draw enemies
	var hero = GameManager.hero
	if hero and is_instance_valid(hero):
		var hero_cell := _world_to_cell(hero.global_position)

		for enemy in GameManager.enemies:
			if not is_instance_valid(enemy) or enemy.is_dead:
				continue
			var enemy_cell := _world_to_cell(enemy.global_position)
			# Only show enemies in explored area and within visible radius of hero
			if not explored.has(enemy_cell):
				continue
			var dist := absi(enemy_cell.x - hero_cell.x) + absi(enemy_cell.y - hero_cell.y)
			if dist > ENEMY_VISIBLE_RADIUS:
				continue
			var enemy_screen := _cell_to_screen(enemy_cell)
			var enemy_center := enemy_screen + Vector2(cell_px / 2.0, cell_px / 2.0)
			draw_circle(enemy_center, cell_px * 0.6, COLOR_ENEMY)

		# Draw hero (on top of everything)
		var hero_screen := _cell_to_screen(hero_cell)
		var hero_center := hero_screen + Vector2(cell_px / 2.0, cell_px / 2.0)
		draw_circle(hero_center, cell_px * 0.8, COLOR_HERO)
