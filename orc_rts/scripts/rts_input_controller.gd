extends Node

## RTS input controller: click select, box select, right-click move,
## attack-move, stop, hold, shift-queue.

@export var camera_rig: Node3D  # RTSCamera node
@export var selection_box_color: Color = Color(0.2, 0.8, 0.2, 0.3)
@export var selection_box_border: Color = Color(0.3, 1.0, 0.3, 0.8)

var selected_units: Array[RTSUnit] = []
var _is_box_selecting: bool = false
var _box_start: Vector2 = Vector2.ZERO
var _attack_move_mode: bool = false

# Box select visual
var _box_rect: ColorRect = null
var _box_border: ReferenceRect = null

func _ready() -> void:
	# Create box select overlay
	var canvas := CanvasLayer.new()
	canvas.layer = 100
	add_child(canvas)

	_box_rect = ColorRect.new()
	_box_rect.color = selection_box_color
	_box_rect.visible = false
	_box_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(_box_rect)

func _unhandled_input(event: InputEvent) -> void:
	# Attack-move hotkey
	if event.is_action_pressed("attack_move"):
		_attack_move_mode = true
		return

	# Stop
	if event.is_action_pressed("stop"):
		for unit in selected_units:
			if is_instance_valid(unit):
				unit.issue_stop()
		return

	# Hold position
	if event.is_action_pressed("hold_position"):
		for unit in selected_units:
			if is_instance_valid(unit):
				unit.issue_hold()
		return

	# Left click — select / box select / attack-move click
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _attack_move_mode:
				_handle_attack_move_click(event)
				_attack_move_mode = false
				return
			_box_start = event.position
			_is_box_selecting = true
		else:
			if _is_box_selecting:
				_finish_box_select(event.position)
				_is_box_selecting = false
				_box_rect.visible = false

	# Update box select visual
	if event is InputEventMouseMotion and _is_box_selecting:
		_update_box_visual(event.position)

	# Right click — move / attack target
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_handle_right_click(event)

func _handle_right_click(event: InputEventMouseButton) -> void:
	if selected_units.is_empty():
		return
	var cam: Node3D = camera_rig as Node3D
	if cam == null or not cam.has_method("screen_to_ground"):
		return

	var queue: bool = Input.is_key_pressed(KEY_SHIFT)

	# Check if clicking on an enemy unit
	var clicked_unit: RTSUnit = _raycast_unit(event.position)
	if clicked_unit and clicked_unit.team != Team.PLAYER:
		for unit in selected_units:
			if is_instance_valid(unit):
				unit.issue_attack_target(clicked_unit, queue)
		return

	# Move to ground position
	var ground_pos: Vector3 = cam.screen_to_ground(event.position)
	# Formation: spread units slightly
	var center := ground_pos
	for i in range(selected_units.size()):
		var unit := selected_units[i]
		if not is_instance_valid(unit):
			continue
		var offset := _formation_offset(i, selected_units.size())
		unit.issue_move(center + offset, queue)

func _handle_attack_move_click(event: InputEventMouseButton) -> void:
	if selected_units.is_empty():
		return
	var cam: Node3D = camera_rig as Node3D
	if cam == null or not cam.has_method("screen_to_ground"):
		return
	var queue: bool = Input.is_key_pressed(KEY_SHIFT)
	var ground_pos: Vector3 = cam.screen_to_ground(event.position)
	for unit in selected_units:
		if is_instance_valid(unit):
			unit.issue_attack_move(ground_pos, queue)

func _finish_box_select(end_pos: Vector2) -> void:
	var queue: bool = Input.is_key_pressed(KEY_SHIFT)
	if not queue:
		_deselect_all()

	var box_size: float = (_box_start - end_pos).length()

	if box_size < 5.0:
		# Click select (not a drag)
		var clicked: RTSUnit = _raycast_unit(_box_start)
		if clicked and clicked.team == Team.PLAYER:
			_select_unit(clicked)
		elif not queue:
			_deselect_all()
		return

	# Box select: find all player units within the screen rect
	var rect := Rect2(_box_start, end_pos - _box_start).abs()
	var cam: Node3D = camera_rig as Node3D
	if cam == null or not cam.has_method("get_camera"):
		return
	var camera: Camera3D = cam.get_camera()

	for unit in get_tree().get_nodes_in_group("rts_units"):
		var ru: RTSUnit = unit as RTSUnit
		if ru == null or ru.is_dead or ru.team != Team.PLAYER:
			continue
		var screen_pos: Vector2 = camera.unproject_position(ru.global_position)
		if rect.has_point(screen_pos):
			_select_unit(ru)

func _select_unit(unit: RTSUnit) -> void:
	if unit not in selected_units:
		selected_units.append(unit)
	unit.set_selected(true)

func _deselect_all() -> void:
	for unit in selected_units:
		if is_instance_valid(unit):
			unit.set_selected(false)
	selected_units.clear()

func _update_box_visual(current_pos: Vector2) -> void:
	if _box_rect == null:
		return
	var rect := Rect2(_box_start, current_pos - _box_start).abs()
	if rect.size.length() > 5.0:
		_box_rect.visible = true
		_box_rect.position = rect.position
		_box_rect.size = rect.size
	else:
		_box_rect.visible = false

func _raycast_unit(screen_pos: Vector2) -> RTSUnit:
	var cam: Node3D = camera_rig as Node3D
	if cam == null or not cam.has_method("get_camera"):
		return null
	var camera: Camera3D = cam.get_camera()
	var from: Vector3 = camera.project_ray_origin(screen_pos)
	var dir: Vector3 = camera.project_ray_normal(screen_pos)

	var space: PhysicsDirectSpaceState3D = get_viewport().get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 200.0)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var result: Dictionary = space.intersect_ray(query)
	if result.is_empty():
		return null
	var collider = result.get("collider")
	if collider is RTSUnit:
		return collider
	# Check parent
	if collider and collider.get_parent() is RTSUnit:
		return collider.get_parent()
	return null

func _formation_offset(index: int, total: int) -> Vector3:
	if total <= 1:
		return Vector3.ZERO
	# Simple grid formation
	var cols: int = ceili(sqrt(float(total)))
	var row: int = index / cols
	var col: int = index % cols
	var spacing: float = 1.5
	var offset_x: float = (col - (cols - 1) * 0.5) * spacing
	var offset_z: float = (row) * spacing
	return Vector3(offset_x, 0, offset_z)

# Expose Team enum at module level for comparisons
const Team = RTSUnit.Team
