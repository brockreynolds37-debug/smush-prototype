extends Node

## AStarGrid2D-based pathfinding on the XZ plane.
## Replaces NavigationAgent3D for WC3-style movement.
## Registered as autoload "PathfindingGrid".

var _grid: AStarGrid2D = AStarGrid2D.new()
var _initialized: bool = false

# Grid bounds (cell coordinates, not world)
var _grid_min: Vector2i = Vector2i.ZERO
var _grid_max: Vector2i = Vector2i.ZERO

# Must match dungeon_builder.gd TILE_SIZE
const TILE_SIZE: float = 2.0

# Occupied cells (units temporarily blocking tiles)
var _occupied_cells: Dictionary = {}  # Vector2i -> Node3D


func _ready() -> void:
	pass


## Called by dungeon_builder.gd after the dungeon is built.
## grid_data: Dictionary of Vector2i -> Tile enum value
## grid_min_bound: smallest cell coordinate
## grid_max_bound: largest cell coordinate
func initialize_from_dungeon(grid_data: Dictionary, grid_min_bound: Vector2i, grid_max_bound: Vector2i) -> void:
	_grid_min = grid_min_bound - Vector2i(1, 1)  # Pad 1 cell for wall border
	_grid_max = grid_max_bound + Vector2i(1, 1)
	_occupied_cells.clear()

	var region_size: Vector2i = _grid_max - _grid_min + Vector2i(1, 1)

	_grid = AStarGrid2D.new()
	_grid.region = Rect2i(_grid_min, region_size)
	_grid.cell_size = Vector2(TILE_SIZE, TILE_SIZE)
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	_grid.update()

	# By default all cells are walkable after update().
	# Mark cells that are NOT in the dungeon floor as solid.
	for x in range(_grid_min.x, _grid_max.x + 1):
		for y in range(_grid_min.y, _grid_max.y + 1):
			var cell := Vector2i(x, y)
			if not grid_data.has(cell):
				# Not part of the dungeon at all — solid
				_grid.set_point_solid(cell, true)
			else:
				# Tile types 0 (EMPTY) and 2 (WALL) are not walkable
				var tile_val: int = grid_data[cell]
				if tile_val == 0 or tile_val == 2:
					_grid.set_point_solid(cell, true)
				else:
					_grid.set_point_solid(cell, false)

	_initialized = true


## Convert a world position (Vector3 XZ) to a grid cell coordinate.
func world_to_cell(world_pos: Vector3) -> Vector2i:
	var cx: int = roundi(world_pos.x / TILE_SIZE)
	var cy: int = roundi(world_pos.z / TILE_SIZE)
	return Vector2i(cx, cy)


## Convert a grid cell coordinate to a world position (y = 0).
func cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3(cell.x * TILE_SIZE, 0.0, cell.y * TILE_SIZE)


## Find a path from one world position to another.
## Returns a PackedVector3Array of waypoints in world space.
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var result: PackedVector3Array = PackedVector3Array()

	if not _initialized:
		# Fallback: just return direct line
		result.append(from)
		result.append(to)
		return result

	var from_cell: Vector2i = world_to_cell(from)
	var to_cell: Vector2i = world_to_cell(to)

	# Clamp cells to grid region
	from_cell = _clamp_to_region(from_cell)
	to_cell = _clamp_to_region(to_cell)

	# If start cell is solid, find nearest walkable
	if _grid.is_point_solid(from_cell):
		from_cell = _find_nearest_walkable(from_cell)

	# If target cell is solid, find nearest walkable
	if _grid.is_point_solid(to_cell):
		to_cell = _find_nearest_walkable(to_cell)

	# Get path as cell coordinates
	var cell_path: PackedVector2Array = _grid.get_point_path(from_cell, to_cell)

	if cell_path.is_empty():
		# No path found — return direct line as fallback
		result.append(from)
		result.append(to)
		return result

	# Convert cell path to world coordinates
	# Keep the exact start position as first point
	result.append(from)

	# Add intermediate waypoints (skip first cell since we use exact start)
	for i in range(1, cell_path.size()):
		var cell_pos: Vector2 = cell_path[i]
		var world_point := Vector3(cell_pos.x, 0.0, cell_pos.y)
		result.append(world_point)

	return result


## Check if a world position is on a walkable cell.
func is_walkable(world_pos: Vector3) -> bool:
	if not _initialized:
		return true
	var cell: Vector2i = world_to_cell(world_pos)
	if not _is_in_region(cell):
		return false
	return not _grid.is_point_solid(cell)


## Mark a cell as temporarily occupied by a unit.
func occupy_cell(world_pos: Vector3, unit: Node3D) -> void:
	if not _initialized:
		return
	var cell: Vector2i = world_to_cell(world_pos)
	_occupied_cells[cell] = unit


## Clear a unit's cell occupation.
func vacate_cell(world_pos: Vector3, unit: Node3D) -> void:
	if not _initialized:
		return
	var cell: Vector2i = world_to_cell(world_pos)
	if _occupied_cells.has(cell):
		var occupant = _occupied_cells[cell]
		if occupant == unit:
			_occupied_cells.erase(cell)


## Check if a cell is occupied by another unit.
func is_cell_occupied(world_pos: Vector3, exclude_unit: Node3D) -> bool:
	if not _initialized:
		return false
	var cell: Vector2i = world_to_cell(world_pos)
	if not _occupied_cells.has(cell):
		return false
	var occupant = _occupied_cells[cell]
	if occupant == exclude_unit:
		return false
	if not is_instance_valid(occupant):
		_occupied_cells.erase(cell)
		return false
	return true


## Clamp a cell coordinate to within the grid region.
func _clamp_to_region(cell: Vector2i) -> Vector2i:
	return Vector2i(
		clampi(cell.x, _grid_min.x, _grid_max.x),
		clampi(cell.y, _grid_min.y, _grid_max.y)
	)


## Check if a cell is within the grid region.
func _is_in_region(cell: Vector2i) -> bool:
	return cell.x >= _grid_min.x and cell.x <= _grid_max.x and cell.y >= _grid_min.y and cell.y <= _grid_max.y


## Find the nearest walkable cell to a given solid cell (BFS).
func _find_nearest_walkable(cell: Vector2i) -> Vector2i:
	var checked: Dictionary = {}
	var queue: Array[Vector2i] = [cell]
	checked[cell] = true

	while queue.size() > 0:
		var current: Vector2i = queue.pop_front()
		if _is_in_region(current) and not _grid.is_point_solid(current):
			return current
		# Check neighbors
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var neighbor: Vector2i = current + offset
			if not checked.has(neighbor):
				checked[neighbor] = true
				queue.append(neighbor)

	# Fallback — shouldn't happen
	return cell
