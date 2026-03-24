extends Node

## Gamepad/Controller Handler — translates joypad input to game actions.
## Left stick: direct hero movement (WASD-style, relative to camera).
## Face buttons: spells (X=Q, Y=W, A=E, B=R on Xbox; ☐=Q, △=W, ✕=E, ○=R on PS).
## Right trigger: auto-attack nearest enemy. Left trigger: interact with nearest.
## Start/Options: pause. Right stick: camera pan.

const STICK_DEADZONE := 0.25
const ATTACK_AUTO_RANGE := 8.0
const INTERACT_RANGE := 3.0

var _attack_held: bool = false

func _process(_delta: float) -> void:
	var hero = GameManager.hero
	if hero == null or hero.is_dead:
		return

	_handle_left_stick_movement(hero)
	_handle_triggers(hero)

func _handle_left_stick_movement(hero: Node3D) -> void:
	# Left stick (axes 0/1) for direct hero movement
	var stick_x := Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	var stick_y := Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)

	if absf(stick_x) < STICK_DEADZONE:
		stick_x = 0.0
	if absf(stick_y) < STICK_DEADZONE:
		stick_y = 0.0

	if stick_x == 0.0 and stick_y == 0.0:
		return

	# Convert stick direction to world direction relative to camera angle
	var cam = GameManager.camera
	if cam == null:
		return

	var cam_rot_y: float = -45.0  # Default isometric rotation
	if cam.has_method("get") and cam.get("camera_rotation_y") != null:
		cam_rot_y = cam.camera_rotation_y

	var rad = deg_to_rad(cam_rot_y)
	var forward = Vector3(sin(rad), 0, cos(rad))
	var right_vec = Vector3(cos(rad), 0, -sin(rad))

	var move_dir = (right_vec * stick_x + forward * stick_y).normalized()
	var target_pos = hero.global_position + move_dir * 3.0

	hero.move_to(target_pos)
	TutorialManager.notify_event("hero_moved")

func _handle_triggers(hero: Node3D) -> void:
	# Right trigger (axis 5) — auto-attack nearest enemy
	if Input.is_action_pressed("gamepad_attack"):
		if not _attack_held:
			_attack_held = true
			var nearest = GameManager.get_nearest_enemy(hero.global_position, ATTACK_AUTO_RANGE)
			if nearest:
				hero.set_attack_target(nearest)
				TutorialManager.notify_event("enemy_hit")
	else:
		_attack_held = false

	# Left trigger (axis 4) — interact with nearest interactable
	if Input.is_action_just_pressed("gamepad_interact"):
		_interact_nearest(hero)

func _interact_nearest(hero: Node3D) -> void:
	# Find nearest interactable within range
	var nearest: Node3D = null
	var nearest_dist: float = INTERACT_RANGE
	for node in get_tree().get_nodes_in_group("interactables"):
		if not is_instance_valid(node):
			continue
		var dist = hero.global_position.distance_to(node.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = node
	if nearest and nearest.has_method("interact"):
		nearest.interact()
		TutorialManager.notify_event("chest_opened")

func _unhandled_input(event: InputEvent) -> void:
	# Gamepad pause button
	if event.is_action_pressed("gamepad_pause"):
		# Toggle pause — find PauseMenu node
		var pause_menu = get_tree().current_scene.get_node_or_null("PauseMenu")
		if pause_menu and pause_menu.has_method("toggle_pause"):
			pause_menu.toggle_pause()
