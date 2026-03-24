extends Node

## CrossFloorConsequences — choices on one floor echo forward.
## Tracks 8 choice tags accumulated during a run. On floor transitions,
## applies consequences: bounty hunters, refugees, vendor discounts,
## inflated prices, extra patrols, ally NPCs, VP bonuses, stealth buffs.

signal consequence_applied(tag: String, description: String)

## ── Choice Tags ──
## Each tag stores: { floor_set: int, data: Dictionary }
## floor_set = floor where the choice was made
var tags: Dictionary = {}

## Pending consequences keyed by "target floor offset from tag floor"
## e.g. bounty hunters spawn 2 floors after assassination
var _pending: Array[Dictionary] = []  # { trigger_floor: int, type: String, data: Dictionary }

## Active buffs/debuffs applied to current floor
var _active_effects: Array[Dictionary] = []

## ── Tag Constants ──
const TAG_MAYOR_ELECTED := "mayor_elected"
const TAG_MAYOR_ASSASSINATED := "mayor_assassinated"
const TAG_TOWN_BRUTE_FORCED := "town_brute_forced"
const TAG_GUARDS_ALERTED := "guards_alerted"
const TAG_MERCHANT_ROBBED := "merchant_robbed"
const TAG_FACTION_ALLIED := "faction_allied"
const TAG_ENV_MASSACRE := "environmental_massacre"
const TAG_STEALTH_PERFECT := "stealth_perfect"

func _ready() -> void:
	FloorManager.floor_changed.connect(_on_floor_changed)
	SolutionPathTracker.floor_path_finalized.connect(_on_path_finalized)

## ── Public API: Set Tags ──

func set_tag(tag: String, data: Dictionary = {}) -> void:
	tags[tag] = {
		"floor_set": FloorManager.current_floor,
		"data": data,
	}
	_schedule_consequences(tag)

func has_tag(tag: String) -> bool:
	return tags.has(tag)

func get_tag_data(tag: String) -> Dictionary:
	if tags.has(tag):
		return tags[tag].get("data", {})
	return {}

func get_active_effects() -> Array[Dictionary]:
	return _active_effects

func has_active_effect(effect_type: String) -> bool:
	for e in _active_effects:
		if e.get("type", "") == effect_type:
			return true
	return false

## ── Consequence Scheduling ──

func _schedule_consequences(tag: String) -> void:
	var current := FloorManager.current_floor

	match tag:
		TAG_MAYOR_ELECTED:
			# Mayor's Signet — vendor discount on next merchant floor (immediate next)
			_pending.append({
				"trigger_floor": current + 1,
				"type": "vendor_discount",
				"data": { "multiplier": 0.6, "reason": "Mayor's Signet" },
			})
			_pending.append({
				"trigger_floor": current + 2,
				"type": "ally_npcs",
				"data": { "count": 2, "reason": "Loyal subjects follow the mayor" },
			})

		TAG_MAYOR_ASSASSINATED:
			# Bounty hunters appear 2 floors later
			_pending.append({
				"trigger_floor": current + 2,
				"type": "bounty_hunters",
				"data": { "count": 2, "reason": "The assassination didn't go unnoticed" },
			})
			# Immediate next floor: fearful NPCs give better prices
			_pending.append({
				"trigger_floor": current + 1,
				"type": "vendor_discount",
				"data": { "multiplier": 0.75, "reason": "Merchants fear the assassin" },
			})

		TAG_TOWN_BRUTE_FORCED:
			# Next floor spawns refugees — some hostile, some friendly
			_pending.append({
				"trigger_floor": current + 1,
				"type": "refugees",
				"data": { "hostile": 2, "friendly": 2, "reason": "Refugees from the sacked town" },
			})

		TAG_GUARDS_ALERTED:
			# Next floor has extra patrols
			_pending.append({
				"trigger_floor": current + 1,
				"type": "extra_patrols",
				"data": { "count": 3, "reason": "Word spread about an intruder" },
			})

		TAG_MERCHANT_ROBBED:
			# Shop prices inflated on next economy-type floor
			_pending.append({
				"trigger_floor": current + 1,
				"type": "price_inflation",
				"data": { "multiplier": 1.5, "reason": "Merchants heard about the thief" },
			})
			_pending.append({
				"trigger_floor": current + 2,
				"type": "price_inflation",
				"data": { "multiplier": 1.25, "reason": "Rumors of theft linger" },
			})

		TAG_FACTION_ALLIED:
			# Ally NPCs appear for 3 floors
			for offset in range(1, 4):
				_pending.append({
					"trigger_floor": current + offset,
					"type": "ally_npcs",
					"data": { "count": 1, "reason": "An allied faction member follows you" },
				})

		TAG_ENV_MASSACRE:
			# Audience remembers — bonus VP for environment kills for 2 floors
			for offset in range(1, 3):
				_pending.append({
					"trigger_floor": current + offset,
					"type": "env_vp_bonus",
					"data": { "multiplier": 1.5, "reason": "The audience craves more destruction!" },
				})

		TAG_STEALTH_PERFECT:
			# Shadow cloak: first detection on next floor is forgiven
			_pending.append({
				"trigger_floor": current + 1,
				"type": "shadow_cloak",
				"data": { "charges": 1, "reason": "Your stealth reputation precedes you" },
			})

## ── Floor Transition: Apply Pending Consequences ──

func _on_floor_changed(floor_number: int) -> void:
	_active_effects.clear()

	var remaining: Array[Dictionary] = []
	for p in _pending:
		if p["trigger_floor"] == floor_number:
			_apply_consequence(p, floor_number)
		elif p["trigger_floor"] > floor_number:
			remaining.append(p)
		# else: expired, discard
	_pending = remaining

func _apply_consequence(pending: Dictionary, _floor_number: int) -> void:
	var type: String = pending["type"]
	var data: Dictionary = pending["data"]
	var reason: String = data.get("reason", "")

	_active_effects.append({ "type": type, "data": data })
	consequence_applied.emit(type, reason)

	match type:
		"vendor_discount":
			# LootManager or merchant can query has_active_effect("vendor_discount")
			Narrator.queue_line("The Collective notes your... reputation precedes you. Prices adjusted.", Color.GOLD)

		"bounty_hunters":
			var count: int = data.get("count", 2)
			Narrator.queue_line("Bounty hunters have tracked you down. %d of them." % count, Color.RED)
			# Spawn extra hostile enemies after a short delay (let floor build finish)
			_spawn_bounty_hunters_deferred(count)

		"refugees":
			var hostile: int = data.get("hostile", 2)
			var friendly: int = data.get("friendly", 2)
			Narrator.queue_line("Refugees from the town you... visited. Some are grateful. Some are not.", Color.YELLOW)
			_spawn_refugees_deferred(hostile, friendly)

		"extra_patrols":
			var count: int = data.get("count", 3)
			Narrator.queue_line("Extra patrols. Someone reported suspicious activity.", Color.ORANGE_RED)
			_spawn_extra_patrols_deferred(count)

		"price_inflation":
			Narrator.queue_line("Merchants seem... wary. Prices are higher.", Color.YELLOW)

		"ally_npcs":
			var count: int = data.get("count", 1)
			Narrator.queue_line("An ally has joined you for this floor.", Color.GREEN)
			_spawn_ally_npcs_deferred(count)

		"env_vp_bonus":
			Narrator.queue_line("The audience is still buzzing about your last... creative display.", Color.GOLD)

		"shadow_cloak":
			Narrator.queue_line("Your shadow reputation grants you one free pass.", Color.CYAN)

## ── Auto-detection from Path Finalization ──

func _on_path_finalized(floor_num: int, path: String, archetype_name: String) -> void:
	# Auto-set tags based on path + archetype combos
	match archetype_name:
		"Political":
			if path == "combat":
				if not has_tag(TAG_TOWN_BRUTE_FORCED):
					set_tag(TAG_TOWN_BRUTE_FORCED, { "floor": floor_num })
		"Stealth":
			# Check if player had zero detection (path stayed "clever" throughout)
			if path == "clever":
				set_tag(TAG_STEALTH_PERFECT, { "floor": floor_num })
		"Economy":
			# Stealing path detection handled by economy archetype calling set_tag directly
			pass

	# Environmental massacre auto-detection
	var env_kills := SolutionPathTracker.scores.get("clever", 0)
	if env_kills >= 15 and not has_tag(TAG_ENV_MASSACRE):
		set_tag(TAG_ENV_MASSACRE, { "floor": floor_num })

## ── Spawning Helpers (deferred to let floor finish building) ──

func _spawn_bounty_hunters_deferred(count: int) -> void:
	await get_tree().create_timer(1.5).timeout
	if not is_instance_valid(GameManager.hero):
		return
	var hero_pos: Vector3 = GameManager.hero.global_position
	for i in range(count):
		var offset := Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
		_spawn_hostile_npc(hero_pos + offset, "Bounty Hunter", Color.DARK_RED, 1.5)

func _spawn_refugees_deferred(hostile_count: int, friendly_count: int) -> void:
	await get_tree().create_timer(1.5).timeout
	if not is_instance_valid(GameManager.hero):
		return
	var hero_pos: Vector3 = GameManager.hero.global_position
	for i in range(hostile_count):
		var offset := Vector3(randf_range(-8, 8), 0, randf_range(-8, 8))
		_spawn_hostile_npc(hero_pos + offset, "Angry Refugee", Color.ORANGE_RED, 0.8)
	for i in range(friendly_count):
		var offset := Vector3(randf_range(-8, 8), 0, randf_range(-8, 8))
		_spawn_friendly_npc(hero_pos + offset, "Grateful Refugee", Color.GREEN)

func _spawn_extra_patrols_deferred(count: int) -> void:
	await get_tree().create_timer(1.5).timeout
	if not is_instance_valid(GameManager.hero):
		return
	var hero_pos: Vector3 = GameManager.hero.global_position
	for i in range(count):
		var offset := Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))
		_spawn_hostile_npc(hero_pos + offset, "Patrol Guard", Color.STEEL_BLUE, 1.2)

func _spawn_ally_npcs_deferred(count: int) -> void:
	await get_tree().create_timer(1.0).timeout
	if not is_instance_valid(GameManager.hero):
		return
	var hero_pos: Vector3 = GameManager.hero.global_position
	for i in range(count):
		var offset := Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
		_spawn_ally_npc(hero_pos + offset, "Faction Ally", Color.LIME_GREEN)

## ── NPC Spawning Primitives ──

func _spawn_hostile_npc(pos: Vector3, label: String, color: Color, stat_mult: float = 1.0) -> void:
	var npc := CharacterBody3D.new()
	npc.name = label.replace(" ", "_")
	npc.add_to_group("enemies")

	# Simple mesh
	var mesh_inst := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.6
	mesh_inst.mesh = capsule
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color * 0.3
	mat.emission_energy_multiplier = 0.5
	mesh_inst.set_surface_override_material(0, mat)
	mesh_inst.position.y = 0.8
	npc.add_child(mesh_inst)

	# Label
	var lbl := Label3D.new()
	lbl.text = label
	lbl.font_size = 28
	lbl.position.y = 2.0
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	npc.add_child(lbl)

	# Collision
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.6
	col.shape = shape
	col.position.y = 0.8
	npc.add_child(col)

	# Stats
	var base_hp := int(60 * stat_mult * (1.0 + FloorManager.current_floor * 0.15))
	var base_dmg := int(15 * stat_mult * (1.0 + FloorManager.current_floor * 0.1))
	npc.set_meta("max_hp", base_hp)
	npc.set_meta("hp", base_hp)
	npc.set_meta("damage", base_dmg)
	npc.set_meta("is_consequence_enemy", true)

	# Simple chase AI script
	var script_text := """
extends CharacterBody3D

var hp: int = %d
var max_hp: int = %d
var damage: int = %d
var is_dead: bool = false
var _attack_cd: float = 0.0
const SPEED := 4.0
const ATTACK_RANGE := 2.0
const ATTACK_COOLDOWN := 1.5

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	GameManager.register_enemy(self)

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_attack_cd -= delta
	var hero := GameManager.hero
	if not is_instance_valid(hero):
		return
	var dir := (hero.global_position - global_position)
	dir.y = 0
	var dist := dir.length()
	if dist > ATTACK_RANGE:
		dir = dir.normalized()
		velocity = dir * SPEED
		move_and_slide()
	elif _attack_cd <= 0:
		_attack_cd = ATTACK_COOLDOWN
		if hero.has_method(\"take_damage\"):
			hero.take_damage(damage)
			GameManager.request_damage_number(hero.global_position, damage, false)

func take_damage(amount: int) -> void:
	if is_dead:
		return
	hp -= amount
	if hp <= 0:
		hp = 0
		is_dead = true
		GameManager.unregister_enemy(self)
		AudienceManager.grant_vp(15, \"Consequence enemy slain\")
		var tw := create_tween()
		tw.tween_property(self, \"scale\", Vector3.ZERO, 0.3)
		tw.tween_callback(queue_free)
""" % [base_hp, base_hp, base_dmg]

	var script := GDScript.new()
	script.source_code = script_text
	script.reload()
	npc.set_script(script)

	npc.global_position = pos
	get_tree().root.add_child(npc)

func _spawn_friendly_npc(pos: Vector3, label: String, color: Color) -> void:
	var npc := StaticBody3D.new()
	npc.name = label.replace(" ", "_")
	npc.add_to_group("npcs")

	var mesh_inst := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.3
	capsule.height = 1.4
	mesh_inst.mesh = capsule
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh_inst.set_surface_override_material(0, mat)
	mesh_inst.position.y = 0.7
	npc.add_child(mesh_inst)

	var lbl := Label3D.new()
	lbl.text = label
	lbl.font_size = 24
	lbl.position.y = 1.8
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	npc.add_child(lbl)

	npc.global_position = pos
	get_tree().root.add_child(npc)

	# Friendly refugees grant a small heal on approach
	var area := Area3D.new()
	var area_col := CollisionShape3D.new()
	var area_shape := SphereShape3D.new()
	area_shape.radius = 2.0
	area_col.shape = area_shape
	area.add_child(area_col)
	npc.add_child(area)
	area.body_entered.connect(func(body: Node3D) -> void:
		if body == GameManager.hero and body.has_method("heal"):
			body.heal(10)
			Narrator.queue_line("The refugee whispers a blessing.", Color.GREEN)
			npc.queue_free()
	)

func _spawn_ally_npc(pos: Vector3, label: String, color: Color) -> void:
	var npc := CharacterBody3D.new()
	npc.name = label.replace(" ", "_")
	npc.add_to_group("allies")

	var mesh_inst := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.3
	capsule.height = 1.4
	mesh_inst.mesh = capsule
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color * 0.4
	mesh_inst.set_surface_override_material(0, mat)
	mesh_inst.position.y = 0.7
	npc.add_child(mesh_inst)

	var lbl := Label3D.new()
	lbl.text = label
	lbl.font_size = 24
	lbl.position.y = 1.8
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	npc.add_child(lbl)

	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.4
	col.shape = shape
	col.position.y = 0.7
	npc.add_child(col)

	# Simple ally AI: follow hero, attack nearest enemy
	var ally_hp := 80 + FloorManager.current_floor * 10
	var ally_dmg := 12 + FloorManager.current_floor * 2
	var script_text := """
extends CharacterBody3D

var hp: int = %d
var damage: int = %d
var is_dead: bool = false
var _attack_cd: float = 0.0
const SPEED := 3.5
const FOLLOW_DIST := 4.0
const ATTACK_RANGE := 2.5
const ATTACK_COOLDOWN := 2.0

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_attack_cd -= delta
	var hero := GameManager.hero
	if not is_instance_valid(hero):
		return

	# Find nearest enemy
	var target := GameManager.get_nearest_enemy(global_position, 8.0)
	if target and global_position.distance_to(target.global_position) < ATTACK_RANGE:
		if _attack_cd <= 0:
			_attack_cd = ATTACK_COOLDOWN
			if target.has_method(\"take_damage\"):
				target.take_damage(damage)
				GameManager.request_damage_number(target.global_position, damage, false)
	elif target and global_position.distance_to(target.global_position) < 8.0:
		var dir := (target.global_position - global_position).normalized()
		dir.y = 0
		velocity = dir * SPEED
		move_and_slide()
	else:
		# Follow hero
		var dist_to_hero := global_position.distance_to(hero.global_position)
		if dist_to_hero > FOLLOW_DIST:
			var dir := (hero.global_position - global_position).normalized()
			dir.y = 0
			velocity = dir * SPEED
			move_and_slide()
		else:
			velocity = Vector3.ZERO

func take_damage(amount: int) -> void:
	if is_dead:
		return
	hp -= amount
	if hp <= 0:
		is_dead = true
		var tw := create_tween()
		tw.tween_property(self, \"scale\", Vector3.ZERO, 0.3)
		tw.tween_callback(queue_free)
""" % [ally_hp, ally_dmg]

	var script := GDScript.new()
	script.source_code = script_text
	script.reload()
	npc.set_script(script)

	npc.global_position = pos
	get_tree().root.add_child(npc)

## ── Query Helpers for Other Systems ──

func get_vendor_discount() -> float:
	## Returns multiplier for vendor prices. < 1.0 = discount, > 1.0 = inflation.
	var mult := 1.0
	for e in _active_effects:
		if e["type"] == "vendor_discount":
			mult = minf(mult, e["data"].get("multiplier", 1.0))
		elif e["type"] == "price_inflation":
			mult *= e["data"].get("multiplier", 1.0)
	return mult

func get_env_vp_multiplier() -> float:
	for e in _active_effects:
		if e["type"] == "env_vp_bonus":
			return e["data"].get("multiplier", 1.0)
	return 1.0

func has_shadow_cloak() -> bool:
	return has_active_effect("shadow_cloak")

func consume_shadow_cloak() -> void:
	for i in range(_active_effects.size() - 1, -1, -1):
		if _active_effects[i]["type"] == "shadow_cloak":
			_active_effects.remove_at(i)
			Narrator.queue_line("Your shadow cloak flickers and fades.", Color.CYAN)
			return

func get_ally_count() -> int:
	var count := 0
	for e in _active_effects:
		if e["type"] == "ally_npcs":
			count += e["data"].get("count", 0)
	return count

## ── Reset ──

func reset() -> void:
	tags.clear()
	_pending.clear()
	_active_effects.clear()
