extends Node3D

## WC3-style RTS camera: WASD/edge pan, scroll zoom, middle-mouse rotate.

@export var pan_speed: float = 30.0
@export var edge_pan_margin: int = 15
@export var edge_pan_speed: float = 20.0
@export var zoom_speed: float = 3.0
@export var zoom_min: float = 8.0
@export var zoom_max: float = 35.0
@export var rotate_speed: float = 0.005
@export var initial_pitch: float = -55.0  # degrees
@export var initial_distance: float = 20.0

var _camera_yaw: float = 0.0
var _camera_distance: float = 20.0
var _is_rotating: bool = false
var _target_position: Vector3 = Vector3.ZERO

@onready var _pivot: Node3D = $Pivot
@onready var _camera: Camera3D = $Pivot/Camera3D

func _ready() -> void:
	_camera_distance = initial_distance
	_target_position = global_position
	_pivot.rotation_degrees.x = initial_pitch
	_update_camera_position()

func _process(delta: float) -> void:
	_handle_keyboard_pan(delta)
	_handle_edge_pan(delta)
	# Smooth follow
	global_position = global_position.lerp(_target_position, 8.0 * delta)
	_update_camera_position()

func _unhandled_input(event: InputEvent) -> void:
	# Zoom
	if event.is_action_pressed("zoom_in"):
		_camera_distance = max(zoom_min, _camera_distance - zoom_speed)
	elif event.is_action_pressed("zoom_out"):
		_camera_distance = min(zoom_max, _camera_distance + zoom_speed)

	# Middle mouse rotate
	if event.is_action_pressed("camera_rotate"):
		_is_rotating = true
	elif event.is_action_released("camera_rotate"):
		_is_rotating = false

	if event is InputEventMouseMotion and _is_rotating:
		_camera_yaw -= event.relative.x * rotate_speed
		_pivot.rotation.y = _camera_yaw

func _handle_keyboard_pan(delta: float) -> void:
	var input_dir := Vector2.ZERO
	if Input.is_action_pressed("camera_up"):
		input_dir.y -= 1
	if Input.is_action_pressed("camera_down"):
		input_dir.y += 1
	if Input.is_action_pressed("camera_left"):
		input_dir.x -= 1
	if Input.is_action_pressed("camera_right"):
		input_dir.x += 1

	if input_dir != Vector2.ZERO:
		input_dir = input_dir.normalized()
		var forward := Vector3(sin(_camera_yaw), 0, cos(_camera_yaw))
		var right := Vector3(cos(_camera_yaw), 0, -sin(_camera_yaw))
		_target_position += (right * input_dir.x + forward * input_dir.y) * pan_speed * delta

func _handle_edge_pan(delta: float) -> void:
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var edge_dir := Vector2.ZERO

	if mouse_pos.x < edge_pan_margin:
		edge_dir.x = -1
	elif mouse_pos.x > vp_size.x - edge_pan_margin:
		edge_dir.x = 1
	if mouse_pos.y < edge_pan_margin:
		edge_dir.y = -1
	elif mouse_pos.y > vp_size.y - edge_pan_margin:
		edge_dir.y = 1

	if edge_dir != Vector2.ZERO:
		edge_dir = edge_dir.normalized()
		var forward := Vector3(sin(_camera_yaw), 0, cos(_camera_yaw))
		var right := Vector3(cos(_camera_yaw), 0, -sin(_camera_yaw))
		_target_position += (right * edge_dir.x + forward * edge_dir.y) * edge_pan_speed * delta

func _update_camera_position() -> void:
	if _camera:
		_camera.position.z = _camera_distance
		_camera.position.y = 0

## Utility: project a screen point to the ground plane (Y=0)
func screen_to_ground(screen_pos: Vector2) -> Vector3:
	var from: Vector3 = _camera.project_ray_origin(screen_pos)
	var dir: Vector3 = _camera.project_ray_normal(screen_pos)
	if abs(dir.y) < 0.001:
		return Vector3.ZERO
	var t: float = -from.y / dir.y
	return from + dir * t

func get_camera() -> Camera3D:
	return _camera
