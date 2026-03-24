extends Node3D

## Dungeon Floor Builder — generates a tile-based dungeon layout at runtime
## using Kenney Mini-Dungeon and KayKit dungeon GLB/GLTF assets.
##
## Attach this to a Node3D. It will generate floor tiles, walls, doorways,
## props, and collision, then bake a navigation mesh.

const TILE_SIZE := 2.0  # World units per grid cell

# Tile types for the grid map
enum Tile {
	EMPTY = 0,
	FLOOR = 1,
	WALL = 2,
	DOOR = 3,
	SPAWN = 4,
	EXIT = 5,
	CHEST = 6,
	BARREL = 7,
}

# Room definitions: {pos: Vector2i, size: Vector2i, name: String}
var rooms: Array[Dictionary] = []

# The 2D grid — populated from room defs
var grid: Dictionary = {}  # Vector2i → Tile
var grid_min := Vector2i.ZERO
var grid_max := Vector2i.ZERO

# Loaded scenes (cached)
var _floor_scene: PackedScene
var _wall_scene: PackedScene
var _wall_opening_scene: PackedScene
var _column_scene: PackedScene
var _stairs_scene: PackedScene
var _barrel_scene: PackedScene
var _chest_scene: PackedScene
var _banner_scene: PackedScene
var _candle_scene: PackedScene
var _rocks_scene: PackedScene
var _gate_scene: PackedScene

# Node containers
var _floor_container: Node3D
var _wall_container: Node3D
var _prop_container: Node3D
var _nav_region: NavigationRegion3D

func _ready() -> void:
	_load_assets()
	_define_floor1_layout()
	_build_grid_from_rooms()
	_generate_geometry()
	_bake_navigation()

func _load_assets() -> void:
	_floor_scene = load("res://assets/models/dungeon/kenney_floor.glb")
	_wall_scene = load("res://assets/models/dungeon/kenney_wall.glb")
	_wall_opening_scene = load("res://assets/models/dungeon/kenney_wall-opening.glb")
	_column_scene = load("res://assets/models/dungeon/kenney_column.glb")
	_stairs_scene = load("res://assets/models/dungeon/kenney_stairs.glb")
	_barrel_scene = load("res://assets/models/dungeon/kenney_barrel.glb")
	_chest_scene = load("res://assets/models/dungeon/kenney_chest.glb")
	_banner_scene = load("res://assets/models/dungeon/kenney_banner.glb")
	_candle_scene = load("res://assets/models/dungeon/candle_lit.gltf")
	_rocks_scene = load("res://assets/models/dungeon/kenney_rocks.glb")
	_gate_scene = load("res://assets/models/dungeon/kenney_gate.glb")

func _define_floor1_layout() -> void:
	# Floor 1: "The Sift" — 5 rooms connected by corridors
	#
	#  [Spawn 8x8] --corridor-- [Arena 12x12] --corridor-- [Loot 6x6]
	#                                 |
	#                             corridor
	#                                 |
	#                          [Guard Room 8x6]
	#                                 |
	#                             corridor
	#                                 |
	#                         [Boss Room 14x10]
	#
	rooms = [
		# Room 0: Spawn room (top-left area)
		{"pos": Vector2i(0, 0), "size": Vector2i(8, 8), "name": "spawn",
		 "props": [
			{"type": "barrel", "offset": Vector2i(1, 1)},
			{"type": "barrel", "offset": Vector2i(2, 1)},
			{"type": "candle", "offset": Vector2i(6, 1)},
			{"type": "candle", "offset": Vector2i(6, 6)},
		]},

		# Corridor: Spawn → Arena (horizontal)
		{"pos": Vector2i(8, 3), "size": Vector2i(4, 2), "name": "corridor_1"},

		# Room 1: Main Arena (center)
		{"pos": Vector2i(12, -2), "size": Vector2i(12, 12), "name": "arena",
		 "props": [
			{"type": "column", "offset": Vector2i(3, 3)},
			{"type": "column", "offset": Vector2i(8, 3)},
			{"type": "column", "offset": Vector2i(3, 8)},
			{"type": "column", "offset": Vector2i(8, 8)},
			{"type": "rocks", "offset": Vector2i(1, 1)},
			{"type": "barrel", "offset": Vector2i(10, 1)},
			{"type": "barrel", "offset": Vector2i(10, 2)},
			{"type": "candle", "offset": Vector2i(3, 0)},
			{"type": "candle", "offset": Vector2i(8, 0)},
		]},

		# Corridor: Arena → Loot (horizontal)
		{"pos": Vector2i(24, 2), "size": Vector2i(4, 2), "name": "corridor_2"},

		# Room 2: Loot room (right side)
		{"pos": Vector2i(28, 0), "size": Vector2i(6, 6), "name": "loot",
		 "props": [
			{"type": "chest", "offset": Vector2i(2, 2)},
			{"type": "chest", "offset": Vector2i(3, 2)},
			{"type": "candle", "offset": Vector2i(1, 0)},
			{"type": "candle", "offset": Vector2i(4, 0)},
			{"type": "barrel", "offset": Vector2i(0, 4)},
			{"type": "banner", "offset": Vector2i(2, 0)},
		]},

		# Corridor: Arena → Guard Room (vertical, going south)
		{"pos": Vector2i(17, 10), "size": Vector2i(2, 4), "name": "corridor_3"},

		# Room 3: Guard room
		{"pos": Vector2i(14, 14), "size": Vector2i(8, 6), "name": "guard",
		 "props": [
			{"type": "barrel", "offset": Vector2i(1, 1)},
			{"type": "barrel", "offset": Vector2i(6, 1)},
			{"type": "rocks", "offset": Vector2i(3, 4)},
			{"type": "candle", "offset": Vector2i(0, 0)},
			{"type": "candle", "offset": Vector2i(7, 0)},
		]},

		# Corridor: Guard Room → Boss Room (vertical)
		{"pos": Vector2i(17, 20), "size": Vector2i(2, 4), "name": "corridor_4"},

		# Room 4: Boss room (bottom)
		{"pos": Vector2i(12, 24), "size": Vector2i(14, 10), "name": "boss",
		 "props": [
			{"type": "column", "offset": Vector2i(3, 2)},
			{"type": "column", "offset": Vector2i(10, 2)},
			{"type": "column", "offset": Vector2i(3, 7)},
			{"type": "column", "offset": Vector2i(10, 7)},
			{"type": "gate", "offset": Vector2i(6, 0)},
			{"type": "gate", "offset": Vector2i(7, 0)},
			{"type": "banner", "offset": Vector2i(6, 8)},
			{"type": "banner", "offset": Vector2i(7, 8)},
			{"type": "candle", "offset": Vector2i(0, 0)},
			{"type": "candle", "offset": Vector2i(13, 0)},
			{"type": "candle", "offset": Vector2i(0, 9)},
			{"type": "candle", "offset": Vector2i(13, 9)},
		]},
	]

func _build_grid_from_rooms() -> void:
	grid.clear()

	# Place floor tiles for each room
	for room in rooms:
		var rpos: Vector2i = room["pos"]
		var rsize: Vector2i = room["size"]
		for x in range(rsize.x):
			for y in range(rsize.y):
				var cell := Vector2i(rpos.x + x, rpos.y + y)
				grid[cell] = Tile.FLOOR

	# Mark spawn and exit
	grid[Vector2i(4, 4)] = Tile.SPAWN  # Center of spawn room
	grid[Vector2i(19, 29)] = Tile.EXIT  # Center of boss room, far side

	# Mark props from room definitions
	for room in rooms:
		if not room.has("props"):
			continue
		var rpos: Vector2i = room["pos"]
		for prop in room["props"]:
			var cell := Vector2i(rpos.x + prop["offset"].x, rpos.y + prop["offset"].y)
			match prop["type"]:
				"chest": grid[cell] = Tile.CHEST
				"barrel": grid[cell] = Tile.BARREL
				# Other props placed on top of floor tiles (handled in geometry pass)

	# Compute grid bounds
	grid_min = Vector2i(999, 999)
	grid_max = Vector2i(-999, -999)
	for cell in grid.keys():
		grid_min.x = mini(grid_min.x, cell.x)
		grid_min.y = mini(grid_min.y, cell.y)
		grid_max.x = maxi(grid_max.x, cell.x)
		grid_max.y = maxi(grid_max.y, cell.y)

func _generate_geometry() -> void:
	# Create containers
	_floor_container = Node3D.new()
	_floor_container.name = "Floors"
	add_child(_floor_container)

	_wall_container = Node3D.new()
	_wall_container.name = "Walls"
	add_child(_wall_container)

	_prop_container = Node3D.new()
	_prop_container.name = "Props"
	add_child(_prop_container)

	_nav_region = NavigationRegion3D.new()
	_nav_region.name = "NavRegion"
	add_child(_nav_region)

	# Generate floor tiles
	for cell in grid.keys():
		_place_floor_tile(cell)

	# Generate walls (any floor cell adjacent to empty gets a wall on that edge)
	for cell in grid.keys():
		_place_walls_for_cell(cell)

	# Generate props from room definitions
	for room in rooms:
		if not room.has("props"):
			continue
		var rpos: Vector2i = room["pos"]
		for prop in room["props"]:
			var cell := Vector2i(rpos.x + prop["offset"].x, rpos.y + prop["offset"].y)
			_place_prop(cell, prop["type"])

	# Place exit stairs
	_place_exit_stairs(Vector2i(19, 29))

func _cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3(cell.x * TILE_SIZE, 0.0, cell.y * TILE_SIZE)

func _place_floor_tile(cell: Vector2i) -> void:
	if _floor_scene == null:
		# Fallback: use a simple plane mesh
		var mi := MeshInstance3D.new()
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(TILE_SIZE, TILE_SIZE)
		mi.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.28, 0.25)
		mi.set_surface_override_material(0, mat)
		mi.position = _cell_to_world(cell)
		_floor_container.add_child(mi)
		return

	var instance := _floor_scene.instantiate()
	instance.position = _cell_to_world(cell)
	# Scale to match TILE_SIZE (Kenney tiles are ~1 unit)
	instance.scale = Vector3(TILE_SIZE, TILE_SIZE, TILE_SIZE)
	_floor_container.add_child(instance)

func _is_floor(cell: Vector2i) -> bool:
	return grid.has(cell)

func _place_walls_for_cell(cell: Vector2i) -> void:
	# Check 4 cardinal directions — place wall segment facing outward if neighbor is empty
	var directions := [
		Vector2i(0, -1),  # North
		Vector2i(1, 0),   # East
		Vector2i(0, 1),   # South
		Vector2i(-1, 0),  # West
	]
	var rotations := [0.0, 90.0, 180.0, 270.0]

	for i in range(4):
		var neighbor := cell + directions[i]
		if not _is_floor(neighbor):
			# Check if this edge is a doorway (both sides of a corridor entrance)
			# For now, place solid walls — doorways are handled by corridor connectivity
			_place_wall_segment(cell, rotations[i])

func _place_wall_segment(cell: Vector2i, rotation_deg: float) -> void:
	var scene := _wall_scene
	if scene == null:
		# Fallback: box mesh
		var body := StaticBody3D.new()
		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(TILE_SIZE, 2.5, 0.3)
		mi.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.45, 0.4, 0.35)
		mi.set_surface_override_material(0, mat)
		body.add_child(mi)
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(TILE_SIZE, 2.5, 0.3)
		col.shape = shape
		body.add_child(col)
		body.position = _cell_to_world(cell) + Vector3.UP * 1.25
		body.rotation_degrees.y = rotation_deg
		# Offset wall to edge of tile
		var offset := Vector3.ZERO
		match int(rotation_deg):
			0: offset = Vector3(0, 0, -TILE_SIZE / 2.0)
			90: offset = Vector3(TILE_SIZE / 2.0, 0, 0)
			180: offset = Vector3(0, 0, TILE_SIZE / 2.0)
			270: offset = Vector3(-TILE_SIZE / 2.0, 0, 0)
		body.position += offset
		_wall_container.add_child(body)
		return

	# Use the GLB wall model
	var wall_root := Node3D.new()
	var instance := scene.instantiate()
	instance.scale = Vector3(TILE_SIZE, TILE_SIZE, TILE_SIZE)
	wall_root.add_child(instance)

	# Add collision
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(TILE_SIZE, 2.5, 0.4)
	col.shape = shape
	col.position.y = 1.25
	body.add_child(col)
	wall_root.add_child(body)

	wall_root.position = _cell_to_world(cell)
	wall_root.rotation_degrees.y = rotation_deg
	# Offset to edge
	var offset := Vector3.ZERO
	match int(rotation_deg):
		0: offset = Vector3(0, 0, -TILE_SIZE / 2.0)
		90: offset = Vector3(TILE_SIZE / 2.0, 0, 0)
		180: offset = Vector3(0, 0, TILE_SIZE / 2.0)
		270: offset = Vector3(-TILE_SIZE / 2.0, 0, 0)
	wall_root.position += offset
	_wall_container.add_child(wall_root)

func _place_prop(cell: Vector2i, prop_type: String) -> void:
	var scene: PackedScene = null
	var y_offset := 0.0

	match prop_type:
		"barrel":
			scene = _barrel_scene
		"chest":
			scene = _chest_scene
		"column":
			scene = _column_scene
		"candle":
			scene = _candle_scene
		"banner":
			scene = _banner_scene
		"rocks":
			scene = _rocks_scene
		"gate":
			scene = _gate_scene

	if scene == null:
		return

	var instance := scene.instantiate()
	instance.position = _cell_to_world(cell) + Vector3.UP * y_offset
	instance.scale = Vector3(TILE_SIZE, TILE_SIZE, TILE_SIZE)

	# Add collision for blocking props
	if prop_type in ["column", "barrel", "rocks"]:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		var col := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = TILE_SIZE * 0.3
		shape.height = 2.0
		col.shape = shape
		col.position.y = 1.0
		body.add_child(col)
		var wrapper := Node3D.new()
		wrapper.position = instance.position
		instance.position = Vector3.ZERO
		wrapper.add_child(instance)
		wrapper.add_child(body)
		_prop_container.add_child(wrapper)
	else:
		_prop_container.add_child(instance)

func _place_exit_stairs(cell: Vector2i) -> void:
	if _stairs_scene == null:
		return
	var instance := _stairs_scene.instantiate()
	instance.position = _cell_to_world(cell)
	instance.scale = Vector3(TILE_SIZE, TILE_SIZE, TILE_SIZE)
	_prop_container.add_child(instance)

func _bake_navigation() -> void:
	var nav_mesh := NavigationMesh.new()
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.1
	nav_mesh.agent_radius = 0.5
	nav_mesh.agent_height = 1.8
	nav_mesh.agent_max_climb = 0.3
	nav_mesh.agent_max_slope = 45.0

	# Set baking bounds from grid extents
	var min_world := _cell_to_world(grid_min) - Vector3(TILE_SIZE, 1.0, TILE_SIZE)
	var max_world := _cell_to_world(grid_max) + Vector3(TILE_SIZE * 2, 10.0, TILE_SIZE * 2)
	var aabb_pos := min_world
	var aabb_size := max_world - min_world
	nav_mesh.filter_baking_aabb = AABB(aabb_pos, aabb_size)

	_nav_region.navigation_mesh = nav_mesh

	# Move floor + wall geometry under NavRegion so it gets baked
	# We reparent the containers
	remove_child(_floor_container)
	_nav_region.add_child(_floor_container)
	remove_child(_wall_container)
	_nav_region.add_child(_wall_container)

	# Bake after a frame so all geometry is ready
	await get_tree().process_frame
	_nav_region.bake_navigation_mesh()

# ---------- PUBLIC API ----------

func get_spawn_position() -> Vector3:
	return _cell_to_world(Vector2i(4, 4)) + Vector3.UP * 0.5

func get_exit_position() -> Vector3:
	return _cell_to_world(Vector2i(19, 29))

func get_room_center(room_name: String) -> Vector3:
	for room in rooms:
		if room["name"] == room_name:
			var rpos: Vector2i = room["pos"]
			var rsize: Vector2i = room["size"]
			var center := Vector2i(rpos.x + rsize.x / 2, rpos.y + rsize.y / 2)
			return _cell_to_world(center) + Vector3.UP * 0.5
	return Vector3.ZERO

func get_room_random_floor(room_name: String) -> Vector3:
	for room in rooms:
		if room["name"] == room_name:
			var rpos: Vector2i = room["pos"]
			var rsize: Vector2i = room["size"]
			# Pick a random interior cell (1 tile from edges)
			var rx := randi_range(rpos.x + 1, rpos.x + rsize.x - 2)
			var ry := randi_range(rpos.y + 1, rpos.y + rsize.y - 2)
			return _cell_to_world(Vector2i(rx, ry)) + Vector3.UP * 0.5
	return Vector3.ZERO
