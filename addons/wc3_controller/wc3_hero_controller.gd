# ═══════════════════════════════════════════════════════════
# WC3HeroController — CharacterBody3D with WC3 movement feel
# ═══════════════════════════════════════════════════════════
# Attach to a CharacterBody3D node. Provides:
# - Turn rate system (unit must face target before moving/attacking)
# - Click-to-move with NavigationAgent3D
# - Attack animation with damage point / backswing
# - Cast point system for abilities
# - Order queue (shift-click)
# - Body blocking via physics collision
# - Acquisition range auto-aggro
#
# WC3 Internal Frame Rate: 1 tick = 0.03 seconds (~33.3 fps)
# All WC3 values in this file use that as reference.
# ═══════════════════════════════════════════════════════════
class_name WC3HeroController
extends CharacterBody3D

# ─── Configuration ───────────────────────────────────────
@export var stats: UnitStats

# ─── State Machine ───────────────────────────────────────
enum State {
	IDLE,
	TURNING,        # Rotating to face target before acting
	MOVING,         # Walking toward destination
	ATTACK_WINDUP,  # Frontswing — committed, damage hasn't landed yet
	ATTACK_DAMAGE,  # Damage point reached — damage applies this frame
	ATTACK_BACKSWING, # Backswing — can be animation-cancelled
	CAST_WINDUP,    # Cast point — committed to spell
	CAST_FIRE,      # Spell fires this frame
	CAST_BACKSWING, # Post-cast animation — can be cancelled
	DEAD,
	HOLD,           # Hold position — attack in range but don't move
}

var current_state: State = State.IDLE
var previous_state: State = State.IDLE

# ─── Order Queue ─────────────────────────────────────────
var current_order: OrderManager.Order = null
var order_queue: Array[OrderManager.Order] = []

# ─── Movement ────────────────────────────────────────────
var target_position: Vector3 = Vector3.ZERO
var target_facing: float = 0.0      # Desired facing angle (radians, Y-axis)
var current_facing: float = 0.0     # Actual facing angle (radians, Y-axis)
var is_turning: bool = false
var turn_callback: Callable         # What to do after turning completes

## The 11.5° threshold — WC3/Dota2 require facing within this angle to act
const FACING_THRESHOLD: float = deg_to_rad(11.5)

# ─── Combat ──────────────────────────────────────────────
var attack_target: Node3D = null
var attack_timer: float = 0.0       # Time into current attack animation
var attack_cooldown: float = 0.0    # Time until next attack allowed
var last_attack_time: float = 0.0

# ─── Casting ─────────────────────────────────────────────
var cast_timer: float = 0.0
var cast_ability_id: int = -1
var cast_target_pos: Vector3 = Vector3.ZERO
var cast_target_unit: Node3D = null

# ─── Health / Mana ───────────────────────────────────────
var health: float = 100.0
var mana: float = 100.0
var is_dead: bool = false

# ─── Speed Modifiers ─────────────────────────────────────
var move_speed_flat_bonus: float = 0.0
var move_speed_percent_bonus: float = 0.0
var turn_rate_modifier: float = 1.0  # Multiplier (for slows like Batrider)

# ─── Child Node References ───────────────────────────────
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var model_pivot: Node3D = $ModelPivot  # Rotate this, not the body
@onready var selection_circle: Node3D = $SelectionCircle


# ═══════════════════════════════════════════════════════════
# LIFECYCLE
# ═══════════════════════════════════════════════════════════
func _ready():
	if stats:
		health = stats.max_health
		mana = stats.max_mana
		# Set up collision shape radius for body blocking
		if collision_shape and collision_shape.shape is CylinderShape3D:
			collision_shape.shape.radius = stats.collision_radius * 0.01  # WC3 units to meters
		# Set up nav agent
		if nav_agent:
			nav_agent.path_desired_distance = 0.5
			nav_agent.target_desired_distance = 0.5
			nav_agent.radius = stats.collision_radius * 0.01

func _physics_process(delta: float):
	if is_dead:
		return

	# Regen
	_process_regen(delta)

	# Process current state
	match current_state:
		State.IDLE:
			_process_idle(delta)
		State.TURNING:
			_process_turning(delta)
		State.MOVING:
			_process_moving(delta)
		State.ATTACK_WINDUP:
			_process_attack_windup(delta)
		State.ATTACK_BACKSWING:
			_process_attack_backswing(delta)
		State.CAST_WINDUP:
			_process_cast_windup(delta)
		State.CAST_BACKSWING:
			_process_cast_backswing(delta)
		State.HOLD:
			_process_hold(delta)

	# Apply gravity
	if not is_on_floor():
		velocity.y -= 9.8 * delta

	# Move with physics (enables body blocking)
	move_and_slide()

	# Decay attack cooldown
	if attack_cooldown > 0.0:
		attack_cooldown -= delta


# ═══════════════════════════════════════════════════════════
# ORDER SYSTEM
# ═══════════════════════════════════════════════════════════
func issue_order(order: OrderManager.Order) -> void:
	if is_dead:
		return

	if order.queued and current_order != null:
		# Shift-queue: add to queue
		order_queue.append(order)
		return

	# Interrupt current action (unless in committed state)
	if current_state in [State.ATTACK_WINDUP, State.CAST_WINDUP]:
		# Can't cancel committed animations — queue instead
		order_queue.push_front(order)
		return

	# Clear queue on non-shift orders
	if not order.queued:
		order_queue.clear()

	_execute_order(order)

func _execute_order(order: OrderManager.Order) -> void:
	current_order = order

	match order.type:
		OrderManager.OrderType.MOVE:
			_begin_move(order.target_position)
		OrderManager.OrderType.ATTACK_MOVE:
			_begin_attack_move(order.target_position)
		OrderManager.OrderType.ATTACK_TARGET:
			_begin_attack_target(order.target_unit)
		OrderManager.OrderType.STOP:
			_full_stop()
		OrderManager.OrderType.HOLD_POSITION:
			_begin_hold()
		OrderManager.OrderType.CAST_POINT:
			_begin_cast_point(order.ability_id, order.target_position)
		OrderManager.OrderType.CAST_TARGET:
			_begin_cast_target(order.ability_id, order.target_unit)
		OrderManager.OrderType.CAST_IMMEDIATE:
			_begin_cast_immediate(order.ability_id)

	GameEvents.order_issued.emit(self, order.type, order)

func _advance_order_queue() -> void:
	current_order = null
	if order_queue.size() > 0:
		var next = order_queue.pop_front()
		_execute_order(next)
	else:
		_transition(State.IDLE)


# ═══════════════════════════════════════════════════════════
# TURN RATE SYSTEM
# ═══════════════════════════════════════════════════════════
# WC3's defining feature: units must FACE their target before acting.
# This creates the "weight" that separates WC3/Dota from League.

func _get_effective_turn_speed() -> float:
	"""Radians per second, capped like WC3"""
	if not stats:
		return deg_to_rad(382.0)
	return stats.get_turn_speed_rad_per_sec() * turn_rate_modifier

func _angle_to_target(target_pos: Vector3) -> float:
	"""Get the angle from current facing to the target position"""
	var dir = (target_pos - global_position).normalized()
	var target_angle = atan2(dir.x, dir.z)
	return _angle_difference(current_facing, target_angle)

func _angle_difference(from_angle: float, to_angle: float) -> float:
	"""Shortest signed angle between two angles"""
	var diff = fmod(to_angle - from_angle + PI, TAU) - PI
	return diff

func _is_facing_target(target_pos: Vector3) -> bool:
	"""Check if unit is within the 11.5° threshold to act"""
	return absf(_angle_to_target(target_pos)) <= FACING_THRESHOLD

func _face_toward(target_pos: Vector3, delta: float) -> bool:
	"""
	Rotate toward target. Returns true when facing is within threshold.
	This is the heart of the WC3 feel.
	"""
	var dir = (target_pos - global_position)
	dir.y = 0  # Only rotate on Y axis
	if dir.length_squared() < 0.001:
		return true

	var desired_angle = atan2(dir.normalized().x, dir.normalized().z)
	var diff = _angle_difference(current_facing, desired_angle)

	if absf(diff) <= FACING_THRESHOLD:
		current_facing = desired_angle
		_apply_facing()
		return true

	# Rotate at turn speed
	var turn_speed = _get_effective_turn_speed()
	var max_turn = turn_speed * delta
	var turn_amount = clampf(diff, -max_turn, max_turn)
	current_facing += turn_amount

	# Normalize angle
	current_facing = fmod(current_facing + PI, TAU) - PI

	_apply_facing()
	return false

func _apply_facing() -> void:
	"""Apply the facing angle to the visual model"""
	if model_pivot:
		model_pivot.rotation.y = current_facing
	# Note: We rotate the MODEL, not the CharacterBody3D
	# This lets physics collision stay axis-aligned for body blocking


# ═══════════════════════════════════════════════════════════
# MOVEMENT
# ═══════════════════════════════════════════════════════════

func _get_effective_move_speed() -> float:
	"""WC3 units per second with modifiers applied"""
	if not stats:
		return 300.0
	var base = stats.move_speed + move_speed_flat_bonus
	var modified = base * (1.0 + move_speed_percent_bonus)
	# WC3 cap: 100 min, 522 max (Alchemist ultimate)
	return clampf(modified, 100.0, 522.0)

func _begin_move(pos: Vector3) -> void:
	target_position = pos
	# Set navigation target
	if nav_agent:
		nav_agent.target_position = pos
	_transition(State.TURNING)
	turn_callback = _on_facing_move_target

func _process_moving(delta: float) -> void:
	if nav_agent and nav_agent.is_navigation_finished():
		_advance_order_queue()
		return

	# Get next path point from navigation
	var next_pos: Vector3
	if nav_agent:
		next_pos = nav_agent.get_next_path_position()
	else:
		next_pos = target_position

	# Must keep facing movement direction (re-check turn)
	if not _is_facing_target(next_pos):
		_face_toward(next_pos, delta)
		# WC3 behavior: unit still moves while turning, but slower
		# Actually WC3 stops and turns first. Let's be authentic.
		velocity.x = 0
		velocity.z = 0
		return

	# Face and move
	_face_toward(next_pos, delta)

	var direction = (next_pos - global_position)
	direction.y = 0
	direction = direction.normalized()

	# Convert WC3 speed to meters/sec (roughly 1 WC3 unit ≈ 0.01 meters in our scale)
	var speed = _get_effective_move_speed() * 0.01
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

func _begin_attack_move(pos: Vector3) -> void:
	"""Move to position but attack anything in acquisition range"""
	target_position = pos
	if nav_agent:
		nav_agent.target_position = pos
	_transition(State.MOVING)
	# TODO: Check for enemies in acquisition range each frame during movement

func _on_facing_move_target() -> void:
	_transition(State.MOVING)


# ═══════════════════════════════════════════════════════════
# ATTACK SYSTEM
# ═══════════════════════════════════════════════════════════
# WC3 attack animation phases:
# 1. WINDUP (frontswing): Unit is committed. Damage hasn't happened yet.
#    Duration = base_attack_time * damage_point
# 2. DAMAGE POINT: Damage applies (or projectile launches for ranged)
# 3. BACKSWING: Follow-through animation. CAN BE CANCELLED by moving.
#    Duration = base_attack_time * attack_backswing
#
# Animation cancelling the backswing is a core WC3/Dota skill.
# "Orb walking" / "attack moving" exploits this.

func _begin_attack_target(target: Node3D) -> void:
	if not target or not is_instance_valid(target):
		_advance_order_queue()
		return

	attack_target = target

	# Check range first
	var dist = global_position.distance_to(target.global_position)
	var attack_range_m = stats.attack_range * 0.01 if stats else 1.28

	if dist > attack_range_m:
		# Move into range first, then attack
		target_position = target.global_position
		if nav_agent:
			nav_agent.target_position = target.global_position
		_transition(State.TURNING)
		turn_callback = _on_facing_attack_approach
		return

	# In range — face target then attack
	_transition(State.TURNING)
	turn_callback = _on_facing_attack_target

func _on_facing_attack_approach() -> void:
	"""Moving toward attack target to get in range"""
	_transition(State.MOVING)
	# Re-check range in _process_moving or via a callback

func _on_facing_attack_target() -> void:
	"""Faced the target, begin attack windup"""
	if attack_cooldown > 0.0:
		# Still on cooldown — wait
		return

	attack_timer = 0.0
	_transition(State.ATTACK_WINDUP)

func _process_attack_windup(delta: float) -> void:
	"""Committed frontswing — can NOT be cancelled"""
	if not stats:
		_transition(State.IDLE)
		return

	attack_timer += delta
	var windup_duration = stats.base_attack_time * stats.damage_point

	# Keep facing the target during windup
	if attack_target and is_instance_valid(attack_target):
		_face_toward(attack_target.global_position, delta)

	if attack_timer >= windup_duration:
		# DAMAGE POINT — fire!
		_apply_attack_damage()
		attack_timer = 0.0
		attack_cooldown = stats.base_attack_time * (1.0 - stats.damage_point)
		_transition(State.ATTACK_BACKSWING)

func _apply_attack_damage() -> void:
	"""The actual damage application / projectile launch"""
	if not attack_target or not is_instance_valid(attack_target):
		return

	if stats.is_ranged:
		# Launch projectile — damage on arrival
		_launch_projectile(attack_target)
	else:
		# Melee — instant damage
		var damage = stats.get_random_damage() if stats else 25
		_deal_damage(attack_target, damage)

	GameEvents.unit_attacked.emit(attack_target, self)

func _process_attack_backswing(delta: float) -> void:
	"""Post-damage animation — CAN be cancelled by new orders"""
	attack_timer += delta
	var backswing_duration = stats.base_attack_time * stats.attack_backswing if stats else 0.5

	if attack_timer >= backswing_duration:
		# Backswing complete — check if we should auto-attack again
		if current_order and current_order.type == OrderManager.OrderType.ATTACK_TARGET:
			if attack_target and is_instance_valid(attack_target):
				_begin_attack_target(attack_target)
				return
		_advance_order_queue()

func _deal_damage(target: Node3D, amount: int) -> void:
	"""Apply damage to a target"""
	if target.has_method("receive_damage"):
		target.receive_damage(amount, self)
	GameEvents.unit_takes_damage.emit(target, self, float(amount), 0)

func _launch_projectile(target: Node3D) -> void:
	"""Spawn a projectile for ranged attacks"""
	# TODO: Instantiate projectile scene, set speed from stats.projectile_speed
	# For now, just deal damage directly (placeholder)
	var damage = stats.get_random_damage() if stats else 25
	_deal_damage(target, damage)

func receive_damage(amount: int, source: Node3D) -> void:
	"""Called when this unit takes damage"""
	health -= amount
	if health <= 0:
		health = 0
		_die(source)


# ═══════════════════════════════════════════════════════════
# CAST SYSTEM
# ═══════════════════════════════════════════════════════════
# Same concept as attack: cast point = committed windup, then spell fires,
# then backswing which can be animation cancelled.

func _begin_cast_point(ability_id: int, pos: Vector3) -> void:
	cast_ability_id = ability_id
	cast_target_pos = pos
	cast_target_unit = null

	# Face the target point first
	_transition(State.TURNING)
	turn_callback = func(): _start_cast_windup()

func _begin_cast_target(ability_id: int, target: Node3D) -> void:
	cast_ability_id = ability_id
	cast_target_unit = target
	cast_target_pos = target.global_position if target else Vector3.ZERO

	# Check range, face target
	_transition(State.TURNING)
	turn_callback = func(): _start_cast_windup()

func _begin_cast_immediate(ability_id: int) -> void:
	cast_ability_id = ability_id
	cast_target_unit = null
	cast_target_pos = global_position
	_start_cast_windup()

func _start_cast_windup() -> void:
	cast_timer = 0.0
	_transition(State.CAST_WINDUP)
	GameEvents.ability_cast_start.emit(self, cast_ability_id, cast_target_unit if cast_target_unit else cast_target_pos)

func _process_cast_windup(delta: float) -> void:
	"""Committed cast point — can NOT be cancelled"""
	cast_timer += delta
	var cast_point_duration = stats.cast_point if stats else 0.3

	if cast_timer >= cast_point_duration:
		# SPELL FIRES
		_fire_ability()
		cast_timer = 0.0
		_transition(State.CAST_BACKSWING)

func _fire_ability() -> void:
	"""The spell takes effect. Override or connect via signal."""
	GameEvents.ability_cast_finish.emit(self, cast_ability_id, cast_target_unit if cast_target_unit else cast_target_pos)
	# Subclasses or ability system should listen to this signal
	# and apply the actual spell effect

func _process_cast_backswing(delta: float) -> void:
	"""Post-cast animation — CAN be cancelled"""
	cast_timer += delta
	var backswing_duration = stats.cast_backswing if stats else 0.5

	if cast_timer >= backswing_duration:
		_advance_order_queue()


# ═══════════════════════════════════════════════════════════
# STOP / HOLD
# ═══════════════════════════════════════════════════════════

func _full_stop() -> void:
	"""S key — stop everything, clear queue"""
	velocity = Vector3.ZERO
	order_queue.clear()
	attack_target = null
	_transition(State.IDLE)

func _begin_hold() -> void:
	"""H key — stop but auto-attack things in range"""
	velocity = Vector3.ZERO
	order_queue.clear()
	_transition(State.HOLD)

func _process_hold(delta: float) -> void:
	"""Hold position — scan for enemies in attack range"""
	velocity.x = 0
	velocity.z = 0
	# TODO: Scan for nearest enemy in attack range and auto-attack
	# For now, just idle
	pass

func _process_idle(delta: float) -> void:
	"""Idle state — auto-attack enemies in acquisition range if not hold"""
	velocity.x = 0
	velocity.z = 0
	# TODO: Scan for enemies in acquisition_range for auto-aggro


# ═══════════════════════════════════════════════════════════
# TURNING STATE
# ═══════════════════════════════════════════════════════════

func _process_turning(delta: float) -> void:
	"""Rotate toward target, then execute callback"""
	var target_pos: Vector3

	# Determine what we're turning toward
	if attack_target and is_instance_valid(attack_target):
		target_pos = attack_target.global_position
	elif cast_target_unit and is_instance_valid(cast_target_unit):
		target_pos = cast_target_unit.global_position
	elif current_order:
		target_pos = current_order.target_position
	else:
		target_pos = target_position

	var faced = _face_toward(target_pos, delta)
	if faced and turn_callback.is_valid():
		var cb = turn_callback
		turn_callback = Callable()
		cb.call()


# ═══════════════════════════════════════════════════════════
# DEATH
# ═══════════════════════════════════════════════════════════

func _die(killer: Node3D) -> void:
	is_dead = true
	current_state = State.DEAD
	velocity = Vector3.ZERO
	order_queue.clear()
	GameEvents.unit_dies.emit(self, killer)
	# TODO: Play death animation, start decay timer


# ═══════════════════════════════════════════════════════════
# REGEN
# ═══════════════════════════════════════════════════════════

func _process_regen(delta: float) -> void:
	if not stats:
		return
	health = minf(health + stats.health_regen * delta, stats.max_health)
	mana = minf(mana + stats.mana_regen * delta, stats.max_mana)


# ═══════════════════════════════════════════════════════════
# STATE MACHINE
# ═══════════════════════════════════════════════════════════

func _transition(new_state: State) -> void:
	previous_state = current_state
	current_state = new_state
