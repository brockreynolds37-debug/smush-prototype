# ═══════════════════════════════════════════════════════════
# WC3Camera — Isometric camera with WC3-style controls
# ═══════════════════════════════════════════════════════════
# Attach to a Camera3D node. Provides:
# - Fixed angle (56° like WC3, adjustable)
# - Edge-of-screen panning
# - Mouse wheel zoom
# - Middle mouse drag pan
# - Follows selected hero (spacebar snaps to hero)
# - Ground plane raycasting for click-to-move
# ═══════════════════════════════════════════════════════════
class_name WC3Camera
extends Camera3D

@export_group("Camera Angle")
## Pitch angle in degrees (WC3 ≈ 56°, Dota2 ≈ 60°)
@export_range(30, 80) var camera_pitch: float = 56.0
## Camera distance from look-at point
@export var camera_distance: float = 20.0
## Min/max zoom
@export var zoom_min: float = 10.0
@export var zoom_max: float = 35.0
@export var zoom_speed: float = 2.0

@export_group("Panning")
## Pixels from screen edge to trigger pan
@export var edge_pan_margin: int = 20
## Pan speed in world units per second
@export var pan_speed: float = 20.0
## Enable edge-of-screen panning
@export var edge_pan_enabled: bool = true
## Enable middle mouse drag panning
@export var drag_pan_enabled: bool = true
@export var drag_pan_sensitivity: float = 0.05

@export_group("Follow")
## The hero to follow (spacebar snaps here)
@export var follow_target: Node3D = null
## Whether camera is currently locked to hero
var is_following: bool = false

# ─── Internal State ──────────────────────────────────────
var look_at_point: Vector3 = Vector3.ZERO
var is_drag_panning: bool = false
var drag_start_mouse: Vector2 = Vector2.ZERO
var drag_start_look: Vector3 = Vector3.ZERO

# ─── Ground Plane ────────────────────────────────────────
## Y coordinate of the ground plane for raycasting
@export var ground_y: float = 0.0


func _ready():
	# Set initial position
	_update_camera_position()


func _process(delta: float):
	var panned: bool = false

	# Edge panning
	if edge_pan_enabled and not is_drag_panning:
		panned = _process_edge_pan(delta)

	# Drag panning
	if drag_pan_enabled:
		_process_drag_pan()

	# Follow target
	if is_following and follow_target and not panned:
		look_at_point = follow_target.global_position
		look_at_point.y = ground_y

	_update_camera_position()


func _unhandled_input(event: InputEvent):
	# Zoom
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				camera_distance = maxf(camera_distance - zoom_speed, zoom_min)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				camera_distance = minf(camera_distance + zoom_speed, zoom_max)
			elif mb.button_index == MOUSE_BUTTON_MIDDLE:
				is_drag_panning = true
				drag_start_mouse = mb.position
				drag_start_look = look_at_point
		else:
			if mb.button_index == MOUSE_BUTTON_MIDDLE:
				is_drag_panning = false

	# Spacebar — snap to hero
	if event is InputEventKey:
		var key = event as InputEventKey
		if key.pressed and key.keycode == KEY_SPACE:
			if follow_target:
				is_following = true
				look_at_point = follow_target.global_position
				look_at_point.y = ground_y


func _process_edge_pan(delta: float) -> bool:
	var viewport = get_viewport()
	if not viewport:
		return false

	var mouse_pos = viewport.get_mouse_position()
	var screen_size = viewport.get_visible_rect().size
	var pan_dir = Vector3.ZERO

	if mouse_pos.x < edge_pan_margin:
		pan_dir.x -= 1.0
	elif mouse_pos.x > screen_size.x - edge_pan_margin:
		pan_dir.x += 1.0
	if mouse_pos.y < edge_pan_margin:
		pan_dir.z -= 1.0
	elif mouse_pos.y > screen_size.y - edge_pan_margin:
		pan_dir.z += 1.0

	if pan_dir.length_squared() > 0:
		# Rotate pan direction to match camera orientation
		var cam_yaw = rotation.y
		var rotated = Vector3(
			pan_dir.x * cos(cam_yaw) - pan_dir.z * sin(cam_yaw),
			0,
			pan_dir.x * sin(cam_yaw) + pan_dir.z * cos(cam_yaw)
		)
		look_at_point += rotated.normalized() * pan_speed * delta
		is_following = false
		return true

	return false


func _process_drag_pan():
	if not is_drag_panning:
		return

	var current_mouse = get_viewport().get_mouse_position()
	var delta_mouse = current_mouse - drag_start_mouse
	var pan_offset = Vector3(-delta_mouse.x, 0, -delta_mouse.y) * drag_pan_sensitivity
	look_at_point = drag_start_look + pan_offset
	is_following = false


func _update_camera_position():
	var pitch_rad = deg_to_rad(camera_pitch)
	var offset = Vector3(
		0,
		sin(pitch_rad) * camera_distance,
		cos(pitch_rad) * camera_distance
	)
	global_position = look_at_point + offset
	look_at(look_at_point)


# ═══════════════════════════════════════════════════════════
# GROUND RAYCASTING — For click-to-move
# ═══════════════════════════════════════════════════════════

func get_ground_position(screen_pos: Vector2) -> Vector3:
	"""
	Raycast from screen position to the ground plane.
	Returns the world-space position where the ray hits y=ground_y.
	"""
	var from = project_ray_origin(screen_pos)
	var dir = project_ray_normal(screen_pos)

	# Intersect with horizontal plane at ground_y
	if absf(dir.y) < 0.001:
		return Vector3.ZERO  # Ray is parallel to ground

	var t = (ground_y - from.y) / dir.y
	if t < 0:
		return Vector3.ZERO  # Behind camera

	return from + dir * t


func get_unit_at_screen_pos(screen_pos: Vector2, collision_mask: int = 1) -> Node3D:
	"""
	Raycast from screen position to find a unit (physics body).
	Returns the first CharacterBody3D or StaticBody3D hit.
	"""
	var space_state = get_world_3d().direct_space_state
	var from = project_ray_origin(screen_pos)
	var to = from + project_ray_normal(screen_pos) * 1000.0

	var query = PhysicsRayQueryParameters3D.create(from, to, collision_mask)
	var result = space_state.intersect_ray(query)

	if result:
		return result.collider
	return null
