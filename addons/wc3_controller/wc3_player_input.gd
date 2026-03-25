# ═══════════════════════════════════════════════════════════
# WC3PlayerInput — Translates mouse/keyboard to WC3 orders
# ═══════════════════════════════════════════════════════════
# Attach to a Node in the scene. Requires references to the
# camera and the controlled hero.
#
# Controls (WC3/Dota standard):
# - Right click ground: Move
# - Right click enemy: Attack
# - Right click ally: Follow
# - A + click: Attack move
# - S: Stop
# - H: Hold position
# - Q/W/E/R: Abilities
# - Shift + any: Queue order
# ═══════════════════════════════════════════════════════════
class_name WC3PlayerInput
extends Node

@export var camera: WC3Camera
@export var hero: WC3HeroController

# ─── Input Modes ─────────────────────────────────────────
enum InputMode {
	NORMAL,        # Default — right click to move/attack
	ATTACK_MOVE,   # A pressed — next click is attack-move
	CASTING_Q,     # Q pressed — next click targets ability
	CASTING_W,
	CASTING_E,
	CASTING_R,
}

var input_mode: InputMode = InputMode.NORMAL

# ─── Click Indicator ─────────────────────────────────────
signal move_click(position: Vector3)       # For visual feedback
signal attack_click(target: Node3D)
signal ground_click(position: Vector3)


func _unhandled_input(event: InputEvent):
	if not hero or not camera:
		return

	# ─── Mouse Input ─────────────────────────────────
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if not mb.pressed:
			return

		var is_queued = Input.is_action_pressed("queue_modifier")  # Shift

		# Right click
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_handle_right_click(mb.position, is_queued)

		# Left click (for attack-move and ability targeting)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_handle_left_click(mb.position, is_queued)

	# ─── Keyboard Input ─────────────────────────────
	if event is InputEventKey:
		var key = event as InputEventKey
		if not key.pressed or key.echo:
			return

		# Stop
		if key.keycode == KEY_S:
			hero.issue_order(OrderManager.Order.stop())
			input_mode = InputMode.NORMAL

		# Hold
		elif key.keycode == KEY_H:
			hero.issue_order(OrderManager.Order.hold())
			input_mode = InputMode.NORMAL

		# Attack move mode
		elif key.keycode == KEY_A:
			input_mode = InputMode.ATTACK_MOVE
			# TODO: Change cursor to attack-move crosshair

		# Abilities
		elif key.keycode == KEY_Q:
			input_mode = InputMode.CASTING_Q
		elif key.keycode == KEY_W:
			input_mode = InputMode.CASTING_W
		elif key.keycode == KEY_E:
			input_mode = InputMode.CASTING_E
		elif key.keycode == KEY_R:
			input_mode = InputMode.CASTING_R

		# Escape cancels current mode
		elif key.keycode == KEY_ESCAPE:
			input_mode = InputMode.NORMAL


func _handle_right_click(screen_pos: Vector2, is_queued: bool) -> void:
	"""Right click — context-sensitive like WC3"""
	# Cancel any special input mode
	input_mode = InputMode.NORMAL

	# Check if we clicked a unit first
	var clicked_unit = camera.get_unit_at_screen_pos(screen_pos)

	if clicked_unit and clicked_unit != hero:
		if _is_enemy(clicked_unit):
			# Right-click enemy = attack
			var order = OrderManager.Order.attack_unit(clicked_unit, is_queued)
			hero.issue_order(order)
			attack_click.emit(clicked_unit)
		else:
			# Right-click ally = follow
			var order = OrderManager.Order.follow_unit(clicked_unit, is_queued)
			hero.issue_order(order)
	else:
		# Right-click ground = move
		var ground_pos = camera.get_ground_position(screen_pos)
		var order = OrderManager.Order.move_to(ground_pos, is_queued)
		hero.issue_order(order)
		move_click.emit(ground_pos)


func _handle_left_click(screen_pos: Vector2, is_queued: bool) -> void:
	"""Left click — depends on current input mode"""
	match input_mode:
		InputMode.ATTACK_MOVE:
			var clicked_unit = camera.get_unit_at_screen_pos(screen_pos)
			if clicked_unit and clicked_unit != hero and _is_enemy(clicked_unit):
				# Click on enemy during attack-move = direct attack
				var order = OrderManager.Order.attack_unit(clicked_unit, is_queued)
				hero.issue_order(order)
			else:
				# Click ground during attack-move
				var ground_pos = camera.get_ground_position(screen_pos)
				var order = OrderManager.Order.attack_move_to(ground_pos, is_queued)
				hero.issue_order(order)
			input_mode = InputMode.NORMAL

		InputMode.CASTING_Q, InputMode.CASTING_W, InputMode.CASTING_E, InputMode.CASTING_R:
			var ability_slot = input_mode - InputMode.CASTING_Q  # 0=Q, 1=W, 2=E, 3=R
			_handle_ability_click(screen_pos, ability_slot, is_queued)
			input_mode = InputMode.NORMAL

		InputMode.NORMAL:
			# Normal left click — select unit (TODO)
			pass


func _handle_ability_click(screen_pos: Vector2, slot: int, is_queued: bool) -> void:
	"""Handle ability targeting click"""
	# For now, treat all abilities as point-targeted
	# TODO: Check ability type (point, target, immediate, passive)
	var ground_pos = camera.get_ground_position(screen_pos)
	var clicked_unit = camera.get_unit_at_screen_pos(screen_pos)

	if clicked_unit and clicked_unit != hero:
		# Unit-targeted ability
		var order = OrderManager.Order.cast_target(slot, clicked_unit, is_queued)
		hero.issue_order(order)
	else:
		# Point-targeted ability
		var order = OrderManager.Order.cast_point(slot, ground_pos, is_queued)
		hero.issue_order(order)

	ground_click.emit(ground_pos)


func _is_enemy(unit: Node3D) -> bool:
	"""Check if a unit is an enemy. Override for team logic."""
	# Simple placeholder — check for an "team" property or group
	if unit.has_method("get_team"):
		return unit.get_team() != hero.get_team() if hero.has_method("get_team") else true
	# Or check groups
	if unit.is_in_group("enemies"):
		return true
	return false
