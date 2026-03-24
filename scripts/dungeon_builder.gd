extends Node3D

## Dungeon Floor Builder — generates a tile-based dungeon layout at runtime
## using Kenney Mini-Dungeon and KayKit dungeon GLB/GLTF assets.
##
## Attach this to a Node3D. It will generate floor tiles, walls, doorways,
## props, and collision, then bake a navigation mesh.
## Supports multiple floor layouts via floor_number.

const TILE_SIZE := 2.0  # World units per grid cell

@export var floor_number: int = 1

# ---------- FLOOR THEMES ----------
# Tier 1 "The Sift" = grey stone dungeon (Floor 1)
# Tier 2 "The Spectacle" = arena gold/red (Floor 2)
# Tier 3 "The Crush" = corrupted glitch purple (Floor 3+)

var _theme: Dictionary = {}

static func _get_theme_for_floor(floor_num: int) -> Dictionary:
	match floor_num:
		1:
			return {
				"name": "The Sift",
				"floor_color": Color(0.30, 0.28, 0.25),
				"floor_roughness": 0.85,
				"wall_color": Color(0.40, 0.37, 0.33),
				"wall_roughness": 0.80,
				"accent_color": Color(0.55, 0.50, 0.42),
				"ambient_color": Color(0.6, 0.55, 0.45),
				"ambient_energy": 0.15,
				"fog_color": Color(0.15, 0.13, 0.10),
				"fog_density": 0.02,
				"light_color": Color(1.0, 0.85, 0.6),
				"light_energy": 0.8,
			}
		2:
			return {
				"name": "The Spectacle",
				"floor_color": Color(0.35, 0.22, 0.12),
				"floor_roughness": 0.70,
				"wall_color": Color(0.50, 0.30, 0.15),
				"wall_roughness": 0.65,
				"accent_color": Color(0.85, 0.65, 0.20),
				"ambient_color": Color(0.8, 0.5, 0.2),
				"ambient_energy": 0.20,
				"fog_color": Color(0.20, 0.10, 0.05),
				"fog_density": 0.015,
				"light_color": Color(1.0, 0.75, 0.4),
				"light_energy": 1.0,
			}
		_:
			return {
				"name": "The Crush",
				"floor_color": Color(0.18, 0.12, 0.22),
				"floor_roughness": 0.60,
				"wall_color": Color(0.25, 0.15, 0.30),
				"wall_roughness": 0.55,
				"accent_color": Color(0.60, 0.20, 0.80),
				"ambient_color": Color(0.5, 0.2, 0.7),
				"ambient_energy": 0.25,
				"fog_color": Color(0.10, 0.05, 0.15),
				"fog_density": 0.025,
				"light_color": Color(0.8, 0.5, 1.0),
				"light_energy": 0.9,
			}

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
	TRAP_SPIKE = 8,
	TRAP_POISON = 9,
	TRAP_FIRE = 10,
}

# Room definitions: {pos: Vector2i, size: Vector2i, name: String}
var rooms: Array[Dictionary] = []

# The 2D grid — populated from room defs
var grid: Dictionary = {}  # Vector2i → Tile
var grid_min := Vector2i.ZERO
var grid_max := Vector2i.ZERO

# Spawn/exit cell positions (set by layout)
var spawn_cell := Vector2i(4, 4)
var exit_cell := Vector2i(19, 29)

# Exit zone node — exposed so scene script can connect signals
var exit_zone: Area3D = null

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
	_theme = _get_theme_for_floor(floor_number)
	_load_assets()
	match floor_number:
		1: _define_floor1_layout()
		2: _define_floor2_layout()
		3: _define_floor3_layout()
		_: _define_floor1_layout()
	_build_grid_from_rooms()
	_generate_geometry()
	_apply_theme_lighting()
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
			{"type": "trap_spike", "offset": Vector2i(5, 5)},
			{"type": "trap_spike", "offset": Vector2i(6, 6)},
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
			{"type": "trap_poison", "offset": Vector2i(4, 3)},
		]},

		# Corridor: Guard Room → Boss Room (vertical) — trapped!
		{"pos": Vector2i(17, 20), "size": Vector2i(2, 4), "name": "corridor_4",
		 "props": [
			{"type": "trap_fire", "offset": Vector2i(0, 1)},
			{"type": "trap_fire", "offset": Vector2i(1, 2)},
		]},

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

func _define_floor2_layout() -> void:
	# Floor 2: "The Crucible" — tighter, more dangerous layout
	#
	#           [Spawn 6x6]
	#               |
	#           corridor
	#               |
	#  [Side Room 6x6] --corridor-- [Central Hall 10x10] --corridor-- [Armory 6x6]
	#                                     |
	#                                 corridor
	#                                     |
	#                              [Boss Pit 12x12]
	#
	spawn_cell = Vector2i(3, 3)
	exit_cell = Vector2i(3, 33)  # Inside boss pit (room at -3,24 size 12x12)

	rooms = [
		# Room 0: Spawn
		{"pos": Vector2i(0, 0), "size": Vector2i(6, 6), "name": "spawn",
		 "props": [
			{"type": "candle", "offset": Vector2i(0, 0)},
			{"type": "candle", "offset": Vector2i(5, 0)},
			{"type": "barrel", "offset": Vector2i(1, 4)},
		]},

		# Corridor: Spawn → Central Hall
		{"pos": Vector2i(2, 6), "size": Vector2i(2, 4), "name": "corridor_1"},

		# Room 1: Central Hall
		{"pos": Vector2i(-2, 10), "size": Vector2i(10, 10), "name": "arena",
		 "props": [
			{"type": "column", "offset": Vector2i(2, 2)},
			{"type": "column", "offset": Vector2i(7, 2)},
			{"type": "column", "offset": Vector2i(2, 7)},
			{"type": "column", "offset": Vector2i(7, 7)},
			{"type": "candle", "offset": Vector2i(0, 0)},
			{"type": "candle", "offset": Vector2i(9, 0)},
			{"type": "rocks", "offset": Vector2i(4, 5)},
			{"type": "trap_spike", "offset": Vector2i(4, 4)},
			{"type": "trap_spike", "offset": Vector2i(5, 5)},
			{"type": "trap_poison", "offset": Vector2i(5, 8)},
		]},

		# Corridor: Central → Side Room (west)
		{"pos": Vector2i(-6, 14), "size": Vector2i(4, 2), "name": "corridor_2"},

		# Room 2: Side Room
		{"pos": Vector2i(-12, 12), "size": Vector2i(6, 6), "name": "guard",
		 "props": [
			{"type": "barrel", "offset": Vector2i(1, 1)},
			{"type": "barrel", "offset": Vector2i(4, 1)},
			{"type": "chest", "offset": Vector2i(2, 3)},
			{"type": "candle", "offset": Vector2i(0, 0)},
			{"type": "candle", "offset": Vector2i(5, 5)},
		]},

		# Corridor: Central → Armory (east)
		{"pos": Vector2i(8, 14), "size": Vector2i(4, 2), "name": "corridor_3"},

		# Room 3: Armory
		{"pos": Vector2i(12, 12), "size": Vector2i(6, 6), "name": "loot",
		 "props": [
			{"type": "chest", "offset": Vector2i(1, 2)},
			{"type": "chest", "offset": Vector2i(4, 2)},
			{"type": "banner", "offset": Vector2i(2, 0)},
			{"type": "candle", "offset": Vector2i(0, 0)},
			{"type": "candle", "offset": Vector2i(5, 0)},
		]},

		# Corridor: Central → Boss Pit — fire gauntlet
		{"pos": Vector2i(2, 20), "size": Vector2i(2, 4), "name": "corridor_4",
		 "props": [
			{"type": "trap_fire", "offset": Vector2i(0, 1)},
			{"type": "trap_fire", "offset": Vector2i(1, 2)},
		]},

		# Room 4: Boss Pit
		{"pos": Vector2i(-3, 24), "size": Vector2i(12, 12), "name": "boss",
		 "props": [
			{"type": "column", "offset": Vector2i(2, 2)},
			{"type": "column", "offset": Vector2i(9, 2)},
			{"type": "column", "offset": Vector2i(2, 9)},
			{"type": "column", "offset": Vector2i(9, 9)},
			{"type": "gate", "offset": Vector2i(5, 0)},
			{"type": "gate", "offset": Vector2i(6, 0)},
			{"type": "banner", "offset": Vector2i(5, 10)},
			{"type": "banner", "offset": Vector2i(6, 10)},
			{"type": "candle", "offset": Vector2i(0, 0)},
			{"type": "candle", "offset": Vector2i(11, 0)},
			{"type": "candle", "offset": Vector2i(0, 11)},
			{"type": "candle", "offset": Vector2i(11, 11)},
		]},
	]

func _define_floor3_layout() -> void:
	# Floor 3: "The Deep" — sprawling, dangerous, multiple paths to boss
	#
	#                    [Spawn 6x6]
	#                        |
	#                    corridor
	#                        |
	#  [Tomb 8x6] --corridor-- [Crossroads 8x8] --corridor-- [Shrine 8x6]
	#                        |
	#                    corridor
	#                        |
	#              [Gauntlet 16x6]
	#                        |
	#                    corridor
	#                        |
	#              [Boss Lair 16x14]
	#
	spawn_cell = Vector2i(3, 3)
	exit_cell = Vector2i(4, 44)

	rooms = [
		# Room 0: Spawn
		{"pos": Vector2i(0, 0), "size": Vector2i(6, 6), "name": "spawn",
		 "props": [
			{"type": "candle", "offset": Vector2i(0, 0)},
			{"type": "candle", "offset": Vector2i(5, 0)},
			{"type": "barrel", "offset": Vector2i(1, 4)},
			{"type": "barrel", "offset": Vector2i(4, 4)},
		]},

		# Corridor: Spawn → Crossroads
		{"pos": Vector2i(2, 6), "size": Vector2i(2, 3), "name": "corridor_1"},

		# Room 1: Crossroads (center hub)
		{"pos": Vector2i(-1, 9), "size": Vector2i(8, 8), "name": "arena",
		 "props": [
			{"type": "column", "offset": Vector2i(2, 2)},
			{"type": "column", "offset": Vector2i(5, 2)},
			{"type": "column", "offset": Vector2i(2, 5)},
			{"type": "column", "offset": Vector2i(5, 5)},
			{"type": "candle", "offset": Vector2i(0, 0)},
			{"type": "candle", "offset": Vector2i(7, 0)},
			{"type": "candle", "offset": Vector2i(0, 7)},
			{"type": "candle", "offset": Vector2i(7, 7)},
			{"type": "trap_spike", "offset": Vector2i(3, 3)},
			{"type": "trap_spike", "offset": Vector2i(4, 4)},
			{"type": "trap_poison", "offset": Vector2i(3, 6)},
		]},

		# Corridor: Crossroads → Tomb (west)
		{"pos": Vector2i(-5, 12), "size": Vector2i(4, 2), "name": "corridor_2"},

		# Room 2: Tomb (west wing)
		{"pos": Vector2i(-13, 10), "size": Vector2i(8, 6), "name": "guard",
		 "props": [
			{"type": "chest", "offset": Vector2i(3, 2)},
			{"type": "chest", "offset": Vector2i(4, 2)},
			{"type": "rocks", "offset": Vector2i(1, 4)},
			{"type": "banner", "offset": Vector2i(3, 0)},
			{"type": "banner", "offset": Vector2i(4, 0)},
			{"type": "candle", "offset": Vector2i(0, 0)},
			{"type": "candle", "offset": Vector2i(7, 0)},
		]},

		# Corridor: Crossroads → Shrine (east)
		{"pos": Vector2i(7, 12), "size": Vector2i(4, 2), "name": "corridor_3"},

		# Room 3: Shrine (east wing)
		{"pos": Vector2i(11, 10), "size": Vector2i(8, 6), "name": "loot",
		 "props": [
			{"type": "chest", "offset": Vector2i(3, 3)},
			{"type": "column", "offset": Vector2i(1, 1)},
			{"type": "column", "offset": Vector2i(6, 1)},
			{"type": "candle", "offset": Vector2i(0, 0)},
			{"type": "candle", "offset": Vector2i(7, 0)},
			{"type": "banner", "offset": Vector2i(3, 0)},
		]},

		# Corridor: Crossroads → Gauntlet (south)
		{"pos": Vector2i(2, 17), "size": Vector2i(2, 4), "name": "corridor_4"},

		# Room 4: Gauntlet (long narrow hallway with enemies + traps)
		{"pos": Vector2i(-5, 21), "size": Vector2i(16, 6), "name": "gauntlet",
		 "props": [
			{"type": "column", "offset": Vector2i(3, 1)},
			{"type": "column", "offset": Vector2i(3, 4)},
			{"type": "column", "offset": Vector2i(7, 1)},
			{"type": "column", "offset": Vector2i(7, 4)},
			{"type": "column", "offset": Vector2i(11, 1)},
			{"type": "column", "offset": Vector2i(11, 4)},
			{"type": "barrel", "offset": Vector2i(0, 0)},
			{"type": "barrel", "offset": Vector2i(15, 0)},
			{"type": "candle", "offset": Vector2i(0, 5)},
			{"type": "candle", "offset": Vector2i(15, 5)},
			{"type": "trap_fire", "offset": Vector2i(5, 2)},
			{"type": "trap_fire", "offset": Vector2i(5, 3)},
			{"type": "trap_spike", "offset": Vector2i(9, 2)},
			{"type": "trap_spike", "offset": Vector2i(9, 3)},
			{"type": "trap_poison", "offset": Vector2i(13, 2)},
			{"type": "trap_poison", "offset": Vector2i(13, 3)},
		]},

		# Corridor: Gauntlet → Boss Lair
		{"pos": Vector2i(2, 27), "size": Vector2i(2, 4), "name": "corridor_5"},

		# Room 5: Boss Lair (massive)
		{"pos": Vector2i(-5, 31), "size": Vector2i(16, 14), "name": "boss",
		 "props": [
			{"type": "column", "offset": Vector2i(3, 3)},
			{"type": "column", "offset": Vector2i(12, 3)},
			{"type": "column", "offset": Vector2i(3, 10)},
			{"type": "column", "offset": Vector2i(12, 10)},
			{"type": "gate", "offset": Vector2i(7, 0)},
			{"type": "gate", "offset": Vector2i(8, 0)},
			{"type": "banner", "offset": Vector2i(7, 12)},
			{"type": "banner", "offset": Vector2i(8, 12)},
			{"type": "candle", "offset": Vector2i(0, 0)},
			{"type": "candle", "offset": Vector2i(15, 0)},
			{"type": "candle", "offset": Vector2i(0, 13)},
			{"type": "candle", "offset": Vector2i(15, 13)},
			{"type": "rocks", "offset": Vector2i(6, 6)},
			{"type": "rocks", "offset": Vector2i(9, 6)},
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
	grid[spawn_cell] = Tile.SPAWN
	grid[exit_cell] = Tile.EXIT

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
				"trap_spike": grid[cell] = Tile.TRAP_SPIKE
				"trap_poison": grid[cell] = Tile.TRAP_POISON
				"trap_fire": grid[cell] = Tile.TRAP_FIRE
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

	# Generate props and traps from room definitions
	for room in rooms:
		if not room.has("props"):
			continue
		var rpos: Vector2i = room["pos"]
		for prop in room["props"]:
			var cell := Vector2i(rpos.x + prop["offset"].x, rpos.y + prop["offset"].y)
			if prop["type"].begins_with("trap_"):
				_place_trap(cell, prop["type"])
			else:
				_place_prop(cell, prop["type"])

	# Place entrance stairs at spawn (visual only — where you arrived from)
	if floor_number > 1:
		_place_entrance_stairs(spawn_cell)

	# Place exit stairs with interactive zone
	_place_exit_stairs(exit_cell)

func _cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3(cell.x * TILE_SIZE, 0.0, cell.y * TILE_SIZE)

func _make_floor_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _theme["floor_color"]
	mat.roughness = _theme["floor_roughness"]
	# Subtle variation per tile for visual interest
	mat.albedo_color = mat.albedo_color.lerp(Color.WHITE, randf_range(-0.03, 0.03))
	return mat

func _make_wall_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _theme["wall_color"]
	mat.roughness = _theme["wall_roughness"]
	mat.albedo_color = mat.albedo_color.lerp(Color.WHITE, randf_range(-0.02, 0.02))
	return mat

func _apply_material_recursive(node: Node, mat: StandardMaterial3D) -> void:
	if node is MeshInstance3D:
		for i in range(node.get_surface_override_material_count()):
			node.set_surface_override_material(i, mat)
		if node.mesh:
			for i in range(node.mesh.get_surface_count()):
				node.set_surface_override_material(i, mat)
	for child in node.get_children():
		_apply_material_recursive(child, mat)

func _place_floor_tile(cell: Vector2i) -> void:
	if _floor_scene == null:
		# Fallback: use a simple plane mesh
		var mi := MeshInstance3D.new()
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(TILE_SIZE, TILE_SIZE)
		mi.mesh = mesh
		mi.set_surface_override_material(0, _make_floor_material())
		mi.position = _cell_to_world(cell)
		_floor_container.add_child(mi)
		return

	var instance := _floor_scene.instantiate()
	instance.position = _cell_to_world(cell)
	instance.scale = Vector3(TILE_SIZE, TILE_SIZE, TILE_SIZE)
	_apply_material_recursive(instance, _make_floor_material())
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
		mi.set_surface_override_material(0, _make_wall_material())
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
	_apply_material_recursive(instance, _make_wall_material())
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

	# Chests and barrels become interactable objects
	if prop_type in ["chest", "barrel"]:
		_place_interactable(cell, prop_type, scene)
		return

	var instance := scene.instantiate()
	instance.position = _cell_to_world(cell) + Vector3.UP * y_offset
	instance.scale = Vector3(TILE_SIZE, TILE_SIZE, TILE_SIZE)

	# Theme-tint structural props (columns, rocks) to match tier
	if prop_type in ["column", "rocks"]:
		var prop_mat := StandardMaterial3D.new()
		prop_mat.albedo_color = _theme["accent_color"]
		prop_mat.roughness = _theme["wall_roughness"]
		_apply_material_recursive(instance, prop_mat)

	# Add collision for blocking props
	if prop_type in ["column", "rocks"]:
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

func _place_interactable(cell: Vector2i, prop_type: String, scene: PackedScene) -> void:
	var interactable_script = load("res://scripts/interactable.gd")
	var body := StaticBody3D.new()
	body.set_script(interactable_script)
	body.position = _cell_to_world(cell)

	# Set type
	if prop_type == "chest":
		body.interactable_type = 0  # Type.CHEST
	else:
		body.interactable_type = 1  # Type.BARREL

	# Add the model
	var model := scene.instantiate()
	model.scale = Vector3(TILE_SIZE, TILE_SIZE, TILE_SIZE)
	body.add_child(model)
	body.setup_model(model)

	# Collision shape for raycasting and blocking
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = TILE_SIZE * 0.35
	shape.height = 1.5
	col.shape = shape
	col.position.y = 0.75
	body.add_child(col)

	_prop_container.add_child(body)

func _place_trap(cell: Vector2i, trap_type_name: String) -> void:
	var trap_script = load("res://scripts/trap_hazard.gd")
	var trap := Area3D.new()
	trap.set_script(trap_script)
	trap.position = _cell_to_world(cell)

	# Set trap type enum
	match trap_type_name:
		"trap_spike": trap.trap_type = 0   # TrapType.SPIKE_TRAP
		"trap_poison": trap.trap_type = 1  # TrapType.POISON_POOL
		"trap_fire": trap.trap_type = 2    # TrapType.FIRE_VENT

	# Collision shape for hero detection
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.9
	shape.height = 2.0
	col.shape = shape
	col.position.y = 1.0
	trap.add_child(col)

	_prop_container.add_child(trap)

func _place_entrance_stairs(cell: Vector2i) -> void:
	if _stairs_scene == null:
		return
	var instance := _stairs_scene.instantiate()
	instance.position = _cell_to_world(cell)
	instance.scale = Vector3(TILE_SIZE, TILE_SIZE, TILE_SIZE)
	# Rotate 180° — entrance stairs face opposite direction
	instance.rotation_degrees.y = 180.0
	_prop_container.add_child(instance)

func _place_exit_stairs(cell: Vector2i) -> void:
	if _stairs_scene == null:
		return
	var instance := _stairs_scene.instantiate()
	instance.position = _cell_to_world(cell)
	instance.scale = Vector3(TILE_SIZE, TILE_SIZE, TILE_SIZE)
	_prop_container.add_child(instance)

	# Create interactive exit zone on top of stairs
	var exit_zone_script = load("res://scripts/exit_zone.gd")
	exit_zone = Area3D.new()
	exit_zone.set_script(exit_zone_script)
	exit_zone.name = "ExitZone"
	exit_zone.position = _cell_to_world(cell) + Vector3.UP * 0.3

	# Collision shape for hero detection
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = TILE_SIZE * 0.8
	shape.height = 2.0
	col.shape = shape
	col.position.y = 1.0
	exit_zone.add_child(col)

	add_child(exit_zone)

func _apply_theme_lighting() -> void:
	# Ambient fill light colored to theme
	var ambient := DirectionalLight3D.new()
	ambient.name = "ThemeAmbient"
	ambient.light_color = _theme["ambient_color"]
	ambient.light_energy = _theme["ambient_energy"]
	ambient.rotation_degrees = Vector3(-45, 30, 0)
	ambient.shadow_enabled = false
	add_child(ambient)

	# Fog volume via WorldEnvironment
	var env := Environment.new()
	env.fog_enabled = true
	env.fog_light_color = _theme["fog_color"]
	env.fog_density = _theme["fog_density"]
	env.fog_light_energy = 0.5
	env.ambient_light_color = _theme["ambient_color"]
	env.ambient_light_energy = _theme["ambient_energy"]
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR

	# Tier-specific post-processing
	match floor_number:
		2:
			# The Spectacle: warm glow
			env.glow_enabled = true
			env.glow_intensity = 0.6
			env.glow_bloom = 0.3
			env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
		3:
			# The Crush: eerie purple glow + stronger bloom
			env.glow_enabled = true
			env.glow_intensity = 0.8
			env.glow_bloom = 0.5
			env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
			env.glow_hdr_threshold = 0.8

	var world_env := WorldEnvironment.new()
	world_env.name = "ThemeEnvironment"
	world_env.environment = env
	add_child(world_env)

	# Accent lights at room centers for color wash
	for room in rooms:
		if room["name"].begins_with("corridor"):
			continue
		var rpos: Vector2i = room["pos"]
		var rsize: Vector2i = room["size"]
		var center_cell := Vector2i(rpos.x + rsize.x / 2, rpos.y + rsize.y / 2)
		var light := OmniLight3D.new()
		light.position = _cell_to_world(center_cell) + Vector3.UP * 4.0
		light.light_color = _theme["light_color"]
		light.light_energy = _theme["light_energy"]
		# Scale range to room size
		light.omni_range = maxf(rsize.x, rsize.y) * TILE_SIZE * 0.6
		light.omni_attenuation = 1.5
		light.shadow_enabled = false
		add_child(light)

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
	return _cell_to_world(spawn_cell) + Vector3.UP * 0.5

func get_exit_position() -> Vector3:
	return _cell_to_world(exit_cell)

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
