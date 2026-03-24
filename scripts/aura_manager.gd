extends Node

## AuraManager — autoload that ticks all active auras every 0.5s.
## Applies effects to hero, summons, and enemies within aura radius.

var _active_auras: Array[Aura] = []
var _tick_timer: float = 0.0
const TICK_INTERVAL: float = 0.5

func _process(delta: float) -> void:
	_tick_timer += delta
	if _tick_timer >= TICK_INTERVAL:
		_tick_timer -= TICK_INTERVAL
		_tick_auras()

func register_aura(aura: Aura) -> void:
	if aura not in _active_auras:
		_active_auras.append(aura)

func unregister_aura(aura: Aura) -> void:
	_active_auras.erase(aura)

func _tick_auras() -> void:
	for aura in _active_auras.duplicate():
		if not is_instance_valid(aura):
			_active_auras.erase(aura)
			continue

		var center = aura.get_world_center()
		var radius = aura.radius

		match aura.effect_type:
			Aura.EffectType.HEAL:
				_tick_heal(center, radius, aura.effect_value)
			Aura.EffectType.DAMAGE:
				_tick_damage(center, radius, aura.effect_value)
			Aura.EffectType.SPEED:
				_tick_speed(center, radius, aura.effect_value)

func _tick_heal(center: Vector3, radius: float, value: float) -> void:
	var heal_per_tick = int(value * TICK_INTERVAL)
	if heal_per_tick <= 0:
		heal_per_tick = 1

	# Heal hero
	var hero = GameManager.hero
	if hero and is_instance_valid(hero) and not hero.is_dead:
		if center.distance_to(hero.global_position) <= radius:
			hero.current_health = mini(hero.current_health + heal_per_tick, hero.max_health)
			hero.health_changed.emit(hero.current_health, hero.max_health)

	# Heal summons
	if hero and hero.get("_active_summons"):
		for minion in hero._active_summons:
			if is_instance_valid(minion) and not minion.is_dead:
				if center.distance_to(minion.global_position) <= radius:
					minion.current_health = mini(minion.current_health + heal_per_tick, minion.max_health)

func _tick_damage(center: Vector3, radius: float, value: float) -> void:
	var dmg_per_tick = int(value * TICK_INTERVAL)
	if dmg_per_tick <= 0:
		dmg_per_tick = 1

	var enemies = GameManager.get_enemies_in_range(center, radius)
	for e in enemies:
		if is_instance_valid(e) and not e.is_dead and e.has_method("take_damage"):
			e.take_damage(dmg_per_tick)

func _tick_speed(center: Vector3, radius: float, value: float) -> void:
	# Speed aura is handled as a buff; here we just boost hero if in range
	var hero = GameManager.hero
	if hero and is_instance_valid(hero) and not hero.is_dead:
		if center.distance_to(hero.global_position) <= radius:
			# Temporary speed buff (resets naturally via hero movement system)
			hero.move_speed = maxf(hero.move_speed, BalanceConfig.HERO_BASE_MOVE_SPEED * value)
