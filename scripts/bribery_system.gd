extends Node

## BriberySystem — INT-gated dialogue option on non-boss enemies and NPCs.
## Pay gold to make them stand down, give intel, open doors, or hire temporarily.
## Price scales with target threat level and inverse of hero INT.
## Bosses, golems, and beasts cannot be bribed. Some enemies can be hired.

signal bribe_attempted(target: Node3D, success: bool, cost: int)
signal enemy_hired(target: Node3D, duration: float)
signal wave_delayed(wave_num: int, delay: float)
signal negotiation_failed(target: Node3D, reason: String)

## ── Bribe Outcome Types ──
enum BribeOutcome { STAND_DOWN, GIVE_INFO, OPEN_DOOR, HIRE_TEMPORARY, DELAY_WAVE }

## ── Config ──
const BASE_COST_PER_HP := 0.5  # Gold per enemy max_hp
const INT_DISCOUNT_PER_POINT := 0.04  # 4% discount per INT point
const MIN_COST := 10
const MAX_HIRE_DURATION := 30.0  # Seconds hired enemy fights for you
const WAVE_DELAY_COST_BASE := 80  # Gold to delay a Survival Arena wave
const WAVE_DELAY_SECONDS := 15.0

## Tags for unbribable enemies
const UNBRIBABLE_TAGS := ["boss", "golem", "beast", "undead", "construct", "mindless"]

## Narrator lines
const BRIBE_SUCCESS_LINES := [
	"Gold talks. The enemy walks.",
	"A wise investment in... peace.",
	"The Collective notes the bribery. Some viewers approve. Some don't.",
	"Coins change hands. Swords stay sheathed.",
	"That's not corruption, that's negotiation. Totally different.",
]
const BRIBE_FAIL_LINES := [
	"They spat at your gold. This one can't be bought.",
	"Some things money can't buy. Like this enemy's loyalty.",
	"The bribe attempt only made them angrier.",
	"Negotiation failed. Violence it is.",
]
const HIRE_LINES := [
	"A mercenary arrangement! The enemy now fights for you!",
	"Gold buys loyalty. Temporarily.",
	"The Collective loves a good betrayal arc!",
]
const WAVE_DELAY_LINES := [
	"A tribute to the arena! The next wave holds back!",
	"You bought time. Use it wisely.",
	"The audience groans — they wanted blood, not negotiation!",
]

var _rng := RandomNumberGenerator.new()
var _bribe_cooldown: float = 0.0
const BRIBE_COOLDOWN := 3.0  # Seconds between bribe attempts

## Track bribes this run
var bribes_attempted: int = 0
var bribes_successful: int = 0
var gold_spent_on_bribes: int = 0
var enemies_hired: int = 0
var waves_delayed: int = 0

func _ready() -> void:
	_rng.randomize()

func _process(delta: float) -> void:
	if _bribe_cooldown > 0:
		_bribe_cooldown -= delta

## ── Core API ──

func can_bribe(target: Node3D) -> bool:
	## Returns true if the target can potentially be bribed.
	if not is_instance_valid(target):
		return false
	if _bribe_cooldown > 0:
		return false

	# Check unbribable tags
	for tag in UNBRIBABLE_TAGS:
		if target.is_in_group(tag):
			return false
		if target.get("enemy_type") != null:
			var etype: String = target.enemy_type
			if tag in etype.to_lower():
				return false
		if target.get("boss_type") != null and target.boss_type != "":
			return false

	# Dead enemies can't be bribed
	if "is_dead" in target and target.is_dead:
		return false

	return true

func get_bribe_cost(target: Node3D) -> int:
	## Calculate bribe cost based on target stats and hero INT.
	var hero := GameManager.hero
	if not is_instance_valid(hero) or not is_instance_valid(target):
		return 999

	# Base cost from target HP
	var target_hp := 100
	if "max_hp" in target:
		target_hp = target.max_hp
	elif target.has_meta("max_hp"):
		target_hp = target.get_meta("max_hp")

	var base_cost := int(target_hp * BASE_COST_PER_HP)

	# INT discount
	var hero_int := 5
	if "stats" in hero:
		hero_int = hero.stats.get("INT", 5)
	elif hero.has_meta("INT"):
		hero_int = hero.get_meta("INT")

	var discount := hero_int * INT_DISCOUNT_PER_POINT
	var final_cost := int(base_cost * (1.0 - discount))

	# Floor scaling
	final_cost = int(final_cost * (1.0 + FloorManager.current_floor * 0.1))

	# Faction discount if applicable
	var _faction_name: String = _get_target_faction(target)
	var faction_discount := FactionManager.get_discount_multiplier(_faction_name)
	final_cost = int(final_cost * faction_discount)

	return maxi(final_cost, MIN_COST)

func attempt_bribe(target: Node3D, outcome: BribeOutcome = BribeOutcome.STAND_DOWN) -> bool:
	## Try to bribe a target. Returns true on success.
	if not can_bribe(target):
		negotiation_failed.emit(target, "Cannot be bribed")
		_say_fail_line()
		return false

	var cost := get_bribe_cost(target)

	# Check gold
	if LootManager.gold < cost:
		negotiation_failed.emit(target, "Not enough gold (%d needed)" % cost)
		Narrator.queue_line("You don't have enough gold. The enemy knows it.", Color.RED)
		return false

	# Pay and apply
	LootManager.gold -= cost
	LootManager.gold_changed.emit(LootManager.gold)
	_bribe_cooldown = BRIBE_COOLDOWN
	bribes_attempted += 1
	bribes_successful += 1
	gold_spent_on_bribes += cost

	# Success chance based on INT — higher INT = more reliable
	var hero := GameManager.hero
	var hero_int := 5
	if is_instance_valid(hero):
		if "stats" in hero:
			hero_int = hero.stats.get("INT", 5)
	var success_chance := 0.6 + hero_int * 0.04  # 60% base + 4% per INT
	success_chance = clampf(success_chance, 0.4, 0.95)

	if _rng.randf() > success_chance:
		# Failed — gold is gone, enemy attacks
		bribes_successful -= 1
		bribe_attempted.emit(target, false, cost)
		_say_fail_line()
		SolutionPathTracker.record_bribe()
		return false

	bribe_attempted.emit(target, true, cost)
	SolutionPathTracker.record_bribe()

	match outcome:
		BribeOutcome.STAND_DOWN:
			_apply_stand_down(target)
		BribeOutcome.GIVE_INFO:
			_apply_give_info(target)
		BribeOutcome.OPEN_DOOR:
			_apply_stand_down(target)  # Same as stand down for now
		BribeOutcome.HIRE_TEMPORARY:
			_apply_hire(target)

	AudienceManager.grant_vp(25, "Successful Bribe")
	var _bribe_faction: String = _get_target_faction(target)
	FactionManager.on_bribe_given(_bribe_faction)
	return true

func attempt_wave_delay() -> bool:
	## Try to delay a Survival Arena wave with a tribute.
	var cost := WAVE_DELAY_COST_BASE + FloorManager.current_floor * 20

	if LootManager.gold < cost:
		Narrator.queue_line("Not enough tribute gold. The arena demands %d." % cost, Color.RED)
		return false

	LootManager.gold -= cost
	LootManager.gold_changed.emit(LootManager.gold)
	gold_spent_on_bribes += cost
	waves_delayed += 1

	var line: String = WAVE_DELAY_LINES[_rng.randi() % WAVE_DELAY_LINES.size()]
	Narrator.queue_line(line, Color.GOLD)

	wave_delayed.emit(waves_delayed, WAVE_DELAY_SECONDS)
	AudienceManager.grant_vp(15, "Wave Tribute")
	SolutionPathTracker.record_bribe()
	return true

## ── Bribe Effects ──

func _apply_stand_down(target: Node3D) -> void:
	if not is_instance_valid(target):
		return

	_say_success_line()

	# Make the enemy passive — remove from enemy list, make them walk away
	if target.is_in_group("enemies"):
		GameManager.unregister_enemy(target)

	# Visual: turn them translucent and have them walk away
	var tw := target.create_tween()
	for child in target.get_children():
		if child is MeshInstance3D:
			var mat: Material = child.get_surface_override_material(0)
			if mat and mat is StandardMaterial3D:
				(mat as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				tw.parallel().tween_property(mat, "albedo_color:a", 0.3, 0.5)

	# Walk away from hero
	if is_instance_valid(GameManager.hero):
		var away_dir := (target.global_position - GameManager.hero.global_position).normalized()
		away_dir.y = 0
		tw.tween_property(target, "global_position",
			target.global_position + away_dir * 8.0, 2.0)
		tw.tween_callback(target.queue_free)

func _apply_give_info(target: Node3D) -> void:
	_apply_stand_down(target)
	# Give a hint about the floor
	var hints := [
		"The exit is to the north. Avoid the patrols near the center.",
		"There's a secret room behind the east wall. Look for cracks.",
		"The boss on this floor is weak to fire. Use it.",
		"A merchant hides in the shadows. They sell rare goods.",
		"The pressure plates trigger a trap. Lead enemies onto them.",
	]
	var hint: String = hints[_rng.randi() % hints.size()]
	Narrator.queue_line("Intel received: \"%s\"" % hint, Color.CYAN)

func _apply_hire(target: Node3D) -> void:
	if not is_instance_valid(target):
		return

	enemies_hired += 1
	var line: String = HIRE_LINES[_rng.randi() % HIRE_LINES.size()]
	Narrator.queue_line(line, Color.LIME_GREEN)
	enemy_hired.emit(target, MAX_HIRE_DURATION)

	# Remove from enemy list
	if target.is_in_group("enemies"):
		GameManager.unregister_enemy(target)
	target.add_to_group("allies")

	# Tint them green to show they're friendly
	for child in target.get_children():
		if child is MeshInstance3D:
			var mat: Material = child.get_surface_override_material(0)
			if mat and mat is StandardMaterial3D:
				(mat as StandardMaterial3D).albedo_color = Color(0.3, 0.8, 0.3)
				(mat as StandardMaterial3D).emission = Color(0.1, 0.4, 0.1)
				(mat as StandardMaterial3D).emission_enabled = true

	# Simple AI override: attack other enemies
	var hire_script_text := """
extends Node

var _target_node: Node3D = null
var _timer: float = %f
const SPEED := 3.5
const ATTACK_RANGE := 2.5
const ATTACK_CD := 1.8
var _cd: float = 0.0
var _parent: CharacterBody3D = null

func _ready() -> void:
	_parent = get_parent() as CharacterBody3D

func _physics_process(delta: float) -> void:
	_timer -= delta
	_cd -= delta
	if _timer <= 0 or _parent == null:
		if is_instance_valid(_parent):
			_parent.queue_free()
		return

	var enemy := GameManager.get_nearest_enemy(_parent.global_position, 10.0)
	if enemy and _parent.global_position.distance_to(enemy.global_position) < ATTACK_RANGE:
		if _cd <= 0:
			_cd = ATTACK_CD
			if enemy.has_method("take_damage"):
				var dmg := 20
				enemy.take_damage(dmg)
				GameManager.request_damage_number(enemy.global_position, dmg, false)
	elif enemy:
		var dir := (enemy.global_position - _parent.global_position).normalized()
		dir.y = 0
		_parent.velocity = dir * SPEED
		_parent.move_and_slide()
	else:
		# Follow hero
		var hero := GameManager.hero
		if is_instance_valid(hero):
			var dist := _parent.global_position.distance_to(hero.global_position)
			if dist > 4.0:
				var dir := (hero.global_position - _parent.global_position).normalized()
				dir.y = 0
				_parent.velocity = dir * SPEED
				_parent.move_and_slide()
			else:
				_parent.velocity = Vector3.ZERO
""" % MAX_HIRE_DURATION

	var script := GDScript.new()
	script.source_code = hire_script_text
	script.reload()
	var ai_node := Node.new()
	ai_node.name = "HiredAI"
	ai_node.set_script(script)
	target.add_child(ai_node)

## ── Faction Helpers ──

func _get_target_faction(target: Node3D) -> String:
	## Returns the faction name for the target, or empty string if none.
	if not is_instance_valid(target):
		return ""
	if target.has_method("get_faction"):
		return target.get_faction()
	if target.get("faction") != null:
		return target.faction
	if target.has_meta("faction"):
		return target.get_meta("faction")
	return ""

## ── Narrator Helpers ──

func _say_success_line() -> void:
	var line: String = BRIBE_SUCCESS_LINES[_rng.randi() % BRIBE_SUCCESS_LINES.size()]
	Narrator.queue_line(line, Color.GOLD)

func _say_fail_line() -> void:
	var line: String = BRIBE_FAIL_LINES[_rng.randi() % BRIBE_FAIL_LINES.size()]
	Narrator.queue_line(line, Color.RED)

## ── Query API ──

func get_stats_summary() -> String:
	return "Bribes: %d/%d | Gold spent: %d | Hired: %d | Waves delayed: %d" % [
		bribes_successful, bribes_attempted, gold_spent_on_bribes,
		enemies_hired, waves_delayed
	]

## ── Reset ──

func reset() -> void:
	bribes_attempted = 0
	bribes_successful = 0
	gold_spent_on_bribes = 0
	enemies_hired = 0
	waves_delayed = 0
	_bribe_cooldown = 0.0
