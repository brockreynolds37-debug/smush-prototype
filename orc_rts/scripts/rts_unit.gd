class_name RTSUnit
extends CharacterBody3D

## WC3-style RTS unit with order queue, turn-before-move, auto-acquisition,
## melee/ranged attack, and AnimationTree state machine integration.

signal died(unit: RTSUnit)
signal health_changed(current: int, maximum: int)
signal order_completed()

enum Team { PLAYER, ENEMY }
enum OrderType { MOVE, ATTACK_MOVE, ATTACK_TARGET, STOP, HOLD }

@export_group("Identity")
@export var unit_name: String = "Unit"
@export var team: Team = Team.PLAYER

@export_group("Stats")
@export var max_hp: int = 100
@export var move_speed: float = 4.5
@export var turn_rate: float = PI  # ~180 deg/sec (WC3 footman-style pivot)
@export var attack_damage: int = 12
@export var attack_range: float = 2.0
@export var attack_cooldown: float = 1.5
@export var acquisition_range: float = 15.0
@export var is_ranged: bool = false
@export var projectile_speed: float = 15.0

@export_group("Collision")
@export var unit_radius: float = 0.5
@export var separation_strength: float = 4.0

var current_hp: int
var is_dead: bool = false
var is_selected: bool = false
var is_holding: bool = false  # Hold position — no auto-acquire

# Order queue
var _order_queue: Array[Dictionary] = []
var _current_order: Dictionary = {}

# Combat
var _attack_timer: float = 0.0
var _attack_target: RTSUnit = null
var _in_acquisition: Array[RTSUnit] = []

# Navigation
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var _anim_tree: AnimationTree = $AnimationTree
@onready var _acquisition_area: Area3D = $AcquisitionRange
@onready var _attack_area: Area3D = $AttackRange
@onready var _selection_ring: MeshInstance3D = $SelectionRing
@onready var _model_root: Node3D = $ModelRoot
@onready var _hp_bar_bg: MeshInstance3D = $HPBarBG
@onready var _hp_bar_fill: MeshInstance3D = $HPBarFill

func _ready() -> void:
	add_to_group("rts_units")
	current_hp = max_hp

	# Configure nav agent
	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = 0.5
	nav_agent.max_speed = move_speed

	# Configure acquisition area
	var acq_shape: SphereShape3D = _acquisition_area.get_child(0).shape as SphereShape3D
	acq_shape.radius = acquisition_range
	_acquisition_area.body_entered.connect(_on_acquisition_entered)
	_acquisition_area.body_exited.connect(_on_acquisition_exited)

	# Configure attack area
	var atk_shape: SphereShape3D = _attack_area.get_child(0).shape as SphereShape3D
	atk_shape.radius = attack_range + 0.5  # small buffer

	# Selection ring starts hidden
	if _selection_ring:
		_selection_ring.visible = false

	_update_hp_bar()

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	_attack_timer = max(0.0, _attack_timer - delta)
	_process_orders(delta)
	_apply_soft_separation(delta)
	_update_animation_state()
	move_and_slide()

# ── ORDER SYSTEM ──

func issue_order(order: Dictionary, queue: bool = false) -> void:
	if is_dead:
		return
	if not queue:
		_order_queue.clear()
		_attack_target = null
	_order_queue.append(order)
	is_holding = order.get("type", OrderType.MOVE) == OrderType.HOLD

func issue_move(target_pos: Vector3, queue: bool = false) -> void:
	issue_order({"type": OrderType.MOVE, "position": target_pos}, queue)

func issue_attack_move(target_pos: Vector3, queue: bool = false) -> void:
	issue_order({"type": OrderType.ATTACK_MOVE, "position": target_pos}, queue)

func issue_attack_target(target: RTSUnit, queue: bool = false) -> void:
	issue_order({"type": OrderType.ATTACK_TARGET, "target": target}, queue)

func issue_stop() -> void:
	_order_queue.clear()
	_current_order = {}
	_attack_target = null
	velocity = Vector3.ZERO
	is_holding = false

func issue_hold() -> void:
	issue_stop()
	is_holding = true

func _process_orders(delta: float) -> void:
	# Advance to next order if current is empty
	if _current_order.is_empty() and not _order_queue.is_empty():
		_current_order = _order_queue.pop_front()

	if _current_order.is_empty():
		# No orders — try auto-acquire if not holding
		velocity = Vector3.ZERO
		if not is_holding:
			_try_auto_acquire()
		if _attack_target and is_instance_valid(_attack_target) and not _attack_target.is_dead:
			_execute_attack(delta)
		return

	match _current_order.get("type", OrderType.STOP):
		OrderType.MOVE:
			_execute_move(delta)
		OrderType.ATTACK_MOVE:
			_execute_attack_move(delta)
		OrderType.ATTACK_TARGET:
			var target: RTSUnit = _current_order.get("target")
			if target and is_instance_valid(target) and not target.is_dead:
				_attack_target = target
				_execute_attack(delta)
			else:
				_complete_current_order()
		OrderType.STOP, OrderType.HOLD:
			velocity = Vector3.ZERO
			_complete_current_order()

func _complete_current_order() -> void:
	_current_order = {}
	order_completed.emit()

func _execute_move(delta: float) -> void:
	var target_pos: Vector3 = _current_order.get("position", global_position)
	nav_agent.target_position = target_pos

	if nav_agent.is_navigation_finished():
		velocity = Vector3.ZERO
		_complete_current_order()
		return

	var next_pos: Vector3 = nav_agent.get_next_path_position()
	var direction: Vector3 = (next_pos - global_position)
	direction.y = 0.0
	if direction.length_squared() < 0.01:
		velocity = Vector3.ZERO
		return

	direction = direction.normalized()

	# Turn before moving (WC3 pivot feel)
	if _turn_toward(direction, delta):
		velocity = direction * move_speed
	else:
		velocity = direction * move_speed * 0.3  # slow while turning

func _execute_attack_move(delta: float) -> void:
	# Attack-move: move toward position but engage any enemy in acquisition range
	if _try_auto_acquire():
		_execute_attack(delta)
		return
	_execute_move(delta)

func _execute_attack(delta: float) -> void:
	if _attack_target == null or not is_instance_valid(_attack_target) or _attack_target.is_dead:
		_attack_target = null
		velocity = Vector3.ZERO
		if _current_order.get("type") == OrderType.ATTACK_TARGET:
			_complete_current_order()
		return

	var to_target: Vector3 = _attack_target.global_position - global_position
	to_target.y = 0.0
	var dist: float = to_target.length()

	if dist <= attack_range + unit_radius + _attack_target.unit_radius:
		# In range — face target and attack
		velocity = Vector3.ZERO
		if to_target.length_squared() > 0.01:
			_turn_toward(to_target.normalized(), delta)
		if _attack_timer <= 0.0:
			_perform_attack()
	else:
		# Chase target
		nav_agent.target_position = _attack_target.global_position
		if not nav_agent.is_navigation_finished():
			var next_pos: Vector3 = nav_agent.get_next_path_position()
			var direction: Vector3 = (next_pos - global_position)
			direction.y = 0.0
			if direction.length_squared() > 0.01:
				direction = direction.normalized()
				_turn_toward(direction, delta)
				velocity = direction * move_speed
		else:
			velocity = Vector3.ZERO

func _perform_attack() -> void:
	_attack_timer = attack_cooldown
	if _anim_tree:
		var sm: AnimationNodeStateMachinePlayback = _anim_tree.get("parameters/playback")
		if sm:
			sm.travel("attack")

	if is_ranged and _attack_target:
		_spawn_projectile()
	elif _attack_target:
		_attack_target.take_damage(attack_damage, self)

func _spawn_projectile() -> void:
	var proj = preload("res://scenes/rts_projectile.tscn").instantiate()
	proj.global_position = global_position + Vector3.UP * 1.2
	proj.setup(_attack_target, attack_damage, projectile_speed, self)
	get_tree().root.add_child(proj)

# ── TURNING ──

func _turn_toward(direction: Vector3, delta: float) -> bool:
	## Returns true if facing close enough to move at full speed.
	if direction.length_squared() < 0.001:
		return true
	var target_angle: float = atan2(direction.x, direction.z)
	var current_angle: float = rotation.y
	var diff: float = wrapf(target_angle - current_angle, -PI, PI)
	var max_turn: float = turn_rate * delta
	if absf(diff) <= max_turn:
		rotation.y = target_angle
		return true
	else:
		rotation.y += signf(diff) * max_turn
		return absf(diff) < PI * 0.3  # within ~54 degrees

# ── AUTO-ACQUISITION ──

func _try_auto_acquire() -> bool:
	if _attack_target and is_instance_valid(_attack_target) and not _attack_target.is_dead:
		return true
	# Find closest enemy in acquisition range
	var closest: RTSUnit = null
	var closest_dist: float = INF
	for unit in _in_acquisition:
		if not is_instance_valid(unit) or unit.is_dead or unit.team == team:
			continue
		var d: float = global_position.distance_squared_to(unit.global_position)
		if d < closest_dist:
			closest_dist = d
			closest = unit
	if closest:
		_attack_target = closest
		return true
	return false

func _on_acquisition_entered(body: Node3D) -> void:
	if body is RTSUnit and body != self and body.team != team:
		if body not in _in_acquisition:
			_in_acquisition.append(body)

func _on_acquisition_exited(body: Node3D) -> void:
	if body is RTSUnit:
		_in_acquisition.erase(body)

# ── SOFT COLLISION SEPARATION ──

func _apply_soft_separation(delta: float) -> void:
	var push := Vector3.ZERO
	for unit in get_tree().get_nodes_in_group("rts_units"):
		if unit == self or not is_instance_valid(unit):
			continue
		var ru: RTSUnit = unit as RTSUnit
		if ru == null or ru.is_dead:
			continue
		var to_other: Vector3 = ru.global_position - global_position
		to_other.y = 0.0
		var dist: float = to_other.length()
		var min_dist: float = unit_radius + ru.unit_radius
		if dist < min_dist and dist > 0.01:
			var overlap: float = min_dist - dist
			push -= to_other.normalized() * overlap * separation_strength
	velocity += push * delta * 60.0  # frame-rate independent

# ── DAMAGE & DEATH ──

func take_damage(amount: int, _attacker: RTSUnit = null) -> void:
	if is_dead:
		return
	current_hp = max(0, current_hp - amount)
	health_changed.emit(current_hp, max_hp)
	_update_hp_bar()

	# Flash red
	if _model_root:
		var tween := create_tween()
		tween.tween_property(_model_root, "modulate", Color(1.5, 0.3, 0.3), 0.05) # doesn't work on 3D but harmless
		tween.tween_interval(0.1)

	if current_hp <= 0:
		_die()

func _die() -> void:
	is_dead = true
	velocity = Vector3.ZERO
	_order_queue.clear()
	_current_order = {}
	set_physics_process(false)

	# Play death animation
	if _anim_tree:
		var sm: AnimationNodeStateMachinePlayback = _anim_tree.get("parameters/playback")
		if sm:
			sm.travel("death")

	# Disable collision
	var col: CollisionShape3D = get_node_or_null("CollisionShape3D")
	if col:
		col.set_deferred("disabled", true)

	died.emit(self)

	# Remove after animation
	var tween := create_tween()
	tween.tween_interval(3.0)
	tween.tween_property(self, "global_position:y", global_position.y - 2.0, 1.5)
	tween.tween_callback(queue_free)

# ── SELECTION ──

func set_selected(selected: bool) -> void:
	is_selected = selected
	if _selection_ring:
		_selection_ring.visible = selected

# ── HP BAR ──

func _update_hp_bar() -> void:
	if _hp_bar_fill == null:
		return
	var ratio: float = float(current_hp) / float(max_hp) if max_hp > 0 else 0.0
	_hp_bar_fill.scale.x = ratio
	# Color: green > yellow > red
	var mat: StandardMaterial3D = _hp_bar_fill.get_surface_override_material(0)
	if mat:
		if ratio > 0.5:
			mat.albedo_color = Color(0.1, 0.8, 0.1)
		elif ratio > 0.25:
			mat.albedo_color = Color(0.9, 0.8, 0.1)
		else:
			mat.albedo_color = Color(0.9, 0.1, 0.1)

# ── ANIMATION ──

func _update_animation_state() -> void:
	if _anim_tree == null:
		return
	var sm: AnimationNodeStateMachinePlayback = _anim_tree.get("parameters/playback")
	if sm == null:
		return
	if is_dead:
		return  # death handled in _die()
	var speed: float = Vector3(velocity.x, 0, velocity.z).length()
	if speed > 0.5:
		if sm.get_current_node() != "walk" and sm.get_current_node() != "attack":
			sm.travel("walk")
	else:
		if sm.get_current_node() != "idle" and sm.get_current_node() != "attack":
			sm.travel("idle")
