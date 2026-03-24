extends Node3D

## WC3-style isometric camera with WASD/edge scrolling, zoom, camera punch, and smusher shake.

@export var pan_speed: float = 25.0
@export var edge_scroll_speed: float = 20.0
@export var edge_scroll_margin: int = 30
@export var zoom_speed: float = 2.0
@export var min_zoom: float = 8.0
@export var max_zoom: float = 30.0
@export var camera_angle: float = 55.0  # Degrees from horizontal
@export var camera_rotation_y: float = -45.0  # Y rotation for isometric feel
@export var smoothing: float = 8.0

var target_position: Vector3 = Vector3.ZERO
var current_zoom: float = 18.0
var target_zoom: float = 18.0

# Screen shake (event-based)
var shake_intensity: float = 0.0
var shake_duration: float = 0.0
var shake_timer: float = 0.0

# Camera punch (directional, crits)
var punch_offset := Vector2.ZERO

# Smusher persistent shake
var _smusher_shake: float = 0.0

@onready var camera_arm: Node3D = $CameraArm
@onready var camera: Camera3D = $CameraArm/Camera3D

func _ready() -> void:
	GameManager.register_camera(self)
	GameManager.screen_shake_requested.connect(_on_screen_shake)
	GameManager.camera_punch_requested.connect(_on_camera_punch)
	SmusherTimer.warning_phase_entered.connect(_on_smusher_warning)
	SmusherTimer.critical_phase_entered.connect(_on_smusher_critical)
	SmusherTimer.overtime_started.connect(_on_smusher_overtime)
	SmusherTimer.room_collapsed.connect(_on_room_collapsed)
	FloorManager.floor_changed.connect(_on_floor_changed)
	target_position = global_position
	_update_camera_transform()

func _process(delta: float) -> void:
	_handle_keyboard_pan(delta)
	_handle_edge_scroll(delta)
	_handle_zoom(delta)

	# Smooth position
	global_position = global_position.lerp(target_position, smoothing * delta)

	# Smooth zoom
	current_zoom = lerp(current_zoom, target_zoom, smoothing * delta)
	_update_camera_transform()

	# Screen shake + camera punch
	_process_screen_shake(delta)

func _handle_keyboard_pan(delta: float) -> void:
	var input_dir := Vector2.ZERO
	if Input.is_action_pressed("move_camera_up"):
		input_dir.y -= 1
	if Input.is_action_pressed("move_camera_down"):
		input_dir.y += 1
	if Input.is_action_pressed("move_camera_left"):
		input_dir.x -= 1
	if Input.is_action_pressed("move_camera_right"):
		input_dir.x += 1

	if input_dir != Vector2.ZERO:
		input_dir = input_dir.normalized()
		var rad = deg_to_rad(camera_rotation_y)
		var forward = Vector3(sin(rad), 0, cos(rad))
		var right_vec = Vector3(cos(rad), 0, -sin(rad))
		target_position += (right_vec * input_dir.x + forward * input_dir.y) * pan_speed * delta

func _handle_edge_scroll(delta: float) -> void:
	var viewport = get_viewport()
	if not viewport:
		return
	var mouse_pos = viewport.get_mouse_position()
	var screen_size = viewport.get_visible_rect().size

	var scroll_dir := Vector2.ZERO
	if mouse_pos.x < edge_scroll_margin:
		scroll_dir.x -= 1
	elif mouse_pos.x > screen_size.x - edge_scroll_margin:
		scroll_dir.x += 1
	if mouse_pos.y < edge_scroll_margin:
		scroll_dir.y -= 1
	elif mouse_pos.y > screen_size.y - edge_scroll_margin:
		scroll_dir.y += 1

	if scroll_dir != Vector2.ZERO:
		scroll_dir = scroll_dir.normalized()
		var rad = deg_to_rad(camera_rotation_y)
		var forward = Vector3(sin(rad), 0, cos(rad))
		var right_vec = Vector3(cos(rad), 0, -sin(rad))
		target_position += (right_vec * scroll_dir.x + forward * scroll_dir.y) * edge_scroll_speed * delta

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_zoom = clamp(target_zoom - zoom_speed, min_zoom, max_zoom)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_zoom = clamp(target_zoom + zoom_speed, min_zoom, max_zoom)

func _handle_zoom(_delta: float) -> void:
	pass  # Zoom handled in _unhandled_input

func _update_camera_transform() -> void:
	if not camera_arm or not camera:
		return
	camera_arm.rotation_degrees = Vector3(-camera_angle, camera_rotation_y, 0)
	camera.position = Vector3(0, 0, current_zoom)

func _on_screen_shake(intensity: float, duration: float) -> void:
	var scale := AccessibilitySettings.get_shake_multiplier()
	shake_intensity = intensity * scale
	shake_duration = duration
	shake_timer = 0.0

func _on_camera_punch(direction: Vector3, strength: float) -> void:
	var scale := AccessibilitySettings.get_shake_multiplier()
	punch_offset = Vector2(direction.x, direction.z) * strength * 0.015 * scale

func _process_screen_shake(delta: float) -> void:
	var offset_x := 0.0
	var offset_y := 0.0

	# Event-based shake (hits, slams, etc.)
	if shake_timer < shake_duration:
		shake_timer += delta
		var progress = shake_timer / shake_duration
		var current_intensity = shake_intensity * (1.0 - progress)
		offset_x += randf_range(-current_intensity, current_intensity) * 0.02
		offset_y += randf_range(-current_intensity, current_intensity) * 0.02

	# Smusher persistent shake (warning/critical/overtime)
	if _smusher_shake > 0.0:
		offset_x += randf_range(-_smusher_shake, _smusher_shake) * 0.003
		offset_y += randf_range(-_smusher_shake, _smusher_shake) * 0.003

	# Camera punch decay
	punch_offset = punch_offset.lerp(Vector2.ZERO, 8.0 * delta)
	offset_x += punch_offset.x
	offset_y += punch_offset.y

	camera.h_offset = offset_x
	camera.v_offset = offset_y

func _on_smusher_warning() -> void:
	_smusher_shake = 0.5 * AccessibilitySettings.get_shake_multiplier()

func _on_smusher_critical() -> void:
	_smusher_shake = 1.5 * AccessibilitySettings.get_shake_multiplier()

func _on_smusher_overtime() -> void:
	_smusher_shake = 3.0 * AccessibilitySettings.get_shake_multiplier()

func _on_room_collapsed(_room_index: int, _room_name: String) -> void:
	_on_screen_shake(12.0, 0.5)

func _on_floor_changed(_floor_number: int) -> void:
	_smusher_shake = 0.0

func get_ground_position_from_mouse() -> Vector3:
	var mouse_pos = get_viewport().get_mouse_position()
	var from = camera.project_ray_origin(mouse_pos)
	var dir = camera.project_ray_normal(mouse_pos)
	if dir.y != 0:
		var t = -from.y / dir.y
		if t > 0:
			return from + dir * t
	return Vector3.ZERO
