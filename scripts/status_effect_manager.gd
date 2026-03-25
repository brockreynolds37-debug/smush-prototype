extends Node

## Status Effect Manager — applies, ticks, and removes status effects on any entity.
## Effects: poison (DOT), slow (reduced movement), stun (can't act).
## Supports both hero and enemies as targets.

signal effect_applied(target: Node3D, effect_type: int, duration: float)
signal effect_removed(target: Node3D, effect_type: int)
signal effect_ticked(target: Node3D, effect_type: int, damage: int)

enum EffectType { POISON, SLOW, STUN }

const EFFECT_NAMES := {
	EffectType.POISON: "Poison",
	EffectType.SLOW: "Slow",
	EffectType.STUN: "Stun",
}

const EFFECT_COLORS := {
	EffectType.POISON: Color(0.2, 0.85, 0.15),
	EffectType.SLOW: Color(0.3, 0.5, 1.0),
	EffectType.STUN: Color(1.0, 0.9, 0.2),
}

# Active effects: { node_instance_id: { EffectType: { duration, tick_timer, damage, slow_pct, tint_node } } }
var _active_effects: Dictionary = {}

# Visual tint nodes: instance_id -> OmniLight3D (for 3D color tint)
var _tint_lights: Dictionary = {}

func _process(delta: float) -> void:
	var to_remove: Array = []

	for inst_id in _active_effects:
		var effects: Dictionary = _active_effects[inst_id]
		var target = instance_from_id(inst_id)
		if not is_instance_valid(target):
			to_remove.append(inst_id)
			continue

		for etype in effects.keys():
			var data: Dictionary = effects[etype]
			data["duration"] -= delta

			if data["duration"] <= 0:
				_remove_effect(target, etype)
				effects.erase(etype)
				continue

			# Tick poison DOT
			if etype == EffectType.POISON:
				data["tick_timer"] -= delta
				if data["tick_timer"] <= 0:
					data["tick_timer"] += data["tick_interval"]
					_apply_dot_damage(target, data["damage"])
					effect_ticked.emit(target, etype, data["damage"])

			# Pulse tint for visual feedback
			_update_visual(target, etype, data)

		if effects.is_empty():
			to_remove.append(inst_id)

	for id in to_remove:
		_active_effects.erase(id)
		_cleanup_tint(id)


## Apply a status effect to a target node.
## target must have is_dead, and take_damage for poison.
func apply_poison(target: Node3D, duration: float = 5.0, damage_per_tick: int = 8, tick_interval: float = 1.0) -> void:
	_apply_effect(target, EffectType.POISON, duration, {
		"damage": damage_per_tick,
		"tick_interval": tick_interval,
		"tick_timer": tick_interval,
	})

func apply_slow(target: Node3D, duration: float = 3.0, slow_percent: float = 0.5) -> void:
	_apply_effect(target, EffectType.SLOW, duration, {
		"slow_percent": slow_percent,
	})

func apply_stun(target: Node3D, duration: float = 1.5) -> void:
	_apply_effect(target, EffectType.STUN, duration, {})

func _apply_effect(target: Node3D, etype: int, duration: float, params: Dictionary) -> void:
	if not is_instance_valid(target):
		return
	if target.get("is_dead"):
		return

	var inst_id = target.get_instance_id()
	if not _active_effects.has(inst_id):
		_active_effects[inst_id] = {}

	var data := { "duration": duration }
	data.merge(params)

	# If already has this effect, refresh duration (take the longer one)
	if _active_effects[inst_id].has(etype):
		var existing = _active_effects[inst_id][etype]
		data["duration"] = maxf(existing["duration"], duration)
		# Keep existing tick timer for poison
		if etype == EffectType.POISON and existing.has("tick_timer"):
			data["tick_timer"] = existing["tick_timer"]

	_active_effects[inst_id][etype] = data

	# Apply immediate gameplay effect
	match etype:
		EffectType.SLOW:
			_apply_slow_to_target(target, params.get("slow_percent", 0.5))
		EffectType.STUN:
			_apply_stun_to_target(target)

	# Visual indicator
	_add_tint_light(target, etype)

	effect_applied.emit(target, etype, duration)

func _apply_dot_damage(target: Node3D, damage: int) -> void:
	if not is_instance_valid(target) or target.get("is_dead"):
		return
	if target.has_method("take_damage"):
		target.take_damage(damage)
		# Green flash for poison
		if target.has_method("_flash_color"):
			target._flash_color(EFFECT_COLORS[EffectType.POISON], 0.1)

func _apply_slow_to_target(target: Node3D, slow_pct: float) -> void:
	if target.has_method("_apply_status_slow"):
		target._apply_status_slow(slow_pct)

func _apply_stun_to_target(target: Node3D) -> void:
	if target.has_method("_apply_status_stun"):
		target._apply_status_stun(true)

func _remove_effect(target: Node3D, etype: int) -> void:
	if not is_instance_valid(target):
		return

	match etype:
		EffectType.SLOW:
			if target.has_method("_remove_status_slow"):
				target._remove_status_slow()
		EffectType.STUN:
			if target.has_method("_apply_status_stun"):
				target._apply_status_stun(false)

	effect_removed.emit(target, etype)

func _add_tint_light(target: Node3D, etype: int) -> void:
	var inst_id = target.get_instance_id()
	# Use a simple OmniLight3D parented to the target for a color tint
	var key = "%d_%d" % [inst_id, etype]
	if _tint_lights.has(key):
		return  # Already has tint

	var light := OmniLight3D.new()
	light.light_color = EFFECT_COLORS[etype]
	light.light_energy = 2.5
	light.omni_range = 2.0
	light.omni_attenuation = 1.5
	light.shadow_enabled = false
	light.position = Vector3.UP * 1.0
	target.add_child(light)
	_tint_lights[key] = light

func _update_visual(_target: Node3D, etype: int, data: Dictionary) -> void:
	# Pulse the tint light intensity for visual feedback
	if not is_instance_valid(_target):
		return
	var key = "%d_%d" % [_target.get_instance_id(), etype]
	if _tint_lights.has(key) and is_instance_valid(_tint_lights[key]):
		var light: OmniLight3D = _tint_lights[key]
		# Steady status effect glow
		light.light_energy = 2.5

func _cleanup_tint(inst_id: int) -> void:
	# Remove all tint lights for this instance
	var keys_to_remove: Array = []
	for key in _tint_lights:
		if str(key).begins_with(str(inst_id)):
			if is_instance_valid(_tint_lights[key]):
				_tint_lights[key].queue_free()
			keys_to_remove.append(key)
	for key in keys_to_remove:
		_tint_lights.erase(key)

## Query: does target have a specific effect active?
func has_effect(target: Node3D, etype: int) -> bool:
	if not is_instance_valid(target):
		return false
	var inst_id = target.get_instance_id()
	if _active_effects.has(inst_id):
		return _active_effects[inst_id].has(etype)
	return false

## Get remaining duration of an effect on target
func get_effect_duration(target: Node3D, etype: int) -> float:
	if not is_instance_valid(target):
		return 0.0
	var inst_id = target.get_instance_id()
	if _active_effects.has(inst_id) and _active_effects[inst_id].has(etype):
		return _active_effects[inst_id][etype]["duration"]
	return 0.0

## Get all active effects on a target: Array of EffectType ints
func get_active_effects(target: Node3D) -> Array:
	if not is_instance_valid(target):
		return []
	var inst_id = target.get_instance_id()
	if _active_effects.has(inst_id):
		return _active_effects[inst_id].keys()
	return []

## Clear all effects from a target (e.g. on death or floor change)
func clear_effects(target: Node3D) -> void:
	if not is_instance_valid(target):
		return
	var inst_id = target.get_instance_id()
	if _active_effects.has(inst_id):
		for etype in _active_effects[inst_id].keys():
			_remove_effect(target, etype)
		_active_effects.erase(inst_id)
	_cleanup_tint(inst_id)

func reset() -> void:
	# Clear everything — used on game restart
	for inst_id in _active_effects.keys():
		var target = instance_from_id(inst_id)
		if is_instance_valid(target):
			for etype in _active_effects[inst_id].keys():
				_remove_effect(target, etype)
	_active_effects.clear()
	for key in _tint_lights:
		if is_instance_valid(_tint_lights[key]):
			_tint_lights[key].queue_free()
	_tint_lights.clear()
