extends Node

## DisguiseSystem — loot enemy/civilian gear to temporarily pass as a different faction.
## Guards check disguise vs hero INT stat. High INT = walk past everything.
## Low INT = "wait, something's off" + alarm. Breaks on attacking.
## Works on Stealth and Political floors.

signal disguise_equipped(faction: String)
signal disguise_broken(reason: String)
signal disguise_checked(success: bool, guard: Node3D)

## Whether the hero is currently disguised
var is_disguised: bool = false
## Which faction the disguise belongs to (matches archetype faction names)
var disguise_faction: String = ""
## Visual tint applied while disguised
var disguise_color: Color = Color(0.5, 0.5, 0.7)
## How many checks the disguise has survived
var checks_passed: int = 0
## Number of disguises used this floor
var disguises_used_this_floor: int = 0

## Base detection chance (0.0 = never detected, 1.0 = always detected)
const BASE_DETECTION_CHANCE := 0.4
## INT reduces detection: each point of INT reduces chance by this amount
const INT_REDUCTION_PER_POINT := 0.04
## Detection chance increases per check passed (guards get suspicious)
const SUSPICION_PER_CHECK := 0.05
## Maximum number of disguises that can drop per floor
const MAX_DISGUISE_DROPS := 3

var _rng := RandomNumberGenerator.new()
var _disguise_drops_this_floor: int = 0
var _original_hero_color: Color = Color.WHITE
var _hero_tint_applied: bool = false

func _ready() -> void:
	_rng.randomize()
	FloorManager.floor_changed.connect(_on_floor_changed)
	GameManager.enemy_died.connect(_on_enemy_died)

# ── Equipping ──

func equip_disguise(faction: String, color: Color = Color(0.5, 0.5, 0.7)) -> void:
	if is_disguised:
		break_disguise("Swapped disguise")
	is_disguised = true
	disguise_faction = faction
	disguise_color = color
	checks_passed = 0
	disguises_used_this_floor += 1
	_apply_visual()
	disguise_equipped.emit(faction)
	SolutionPathTracker.record_disguise_used()
	AudienceManager.grant_vp(15, "Disguise equipped!")

func break_disguise(reason: String = "Attacked") -> void:
	if not is_disguised:
		return
	is_disguised = false
	_remove_visual()
	disguise_broken.emit(reason)
	disguise_faction = ""

# ── Guard Check ──

func check_disguise(guard: Node3D) -> bool:
	## Returns true if the disguise fools the guard. False = spotted.
	if not is_disguised:
		return false

	# Get hero INT stat
	var hero_int := 5  # Default
	var hero = GameManager.hero
	if hero and is_instance_valid(hero):
		var char_data = CharacterData.get_selected()
		if char_data:
			hero_int = char_data.get("stats", {}).get("INT", 5)
		# Add equipment INT bonus
		if "equip_int" in hero:
			hero_int += hero.equip_int

	# Calculate detection chance
	var detect_chance := BASE_DETECTION_CHANCE
	detect_chance -= hero_int * INT_REDUCTION_PER_POINT
	detect_chance += checks_passed * SUSPICION_PER_CHECK
	detect_chance = clampf(detect_chance, 0.05, 0.95)  # Always 5-95% range

	var roll := _rng.randf()
	var success := roll > detect_chance

	if success:
		checks_passed += 1
		disguise_checked.emit(true, guard)
		# Small VP for each check passed
		if checks_passed >= 2:
			AudienceManager.grant_vp(10, "Disguise holds!")
	else:
		# Busted!
		disguise_checked.emit(false, guard)
		break_disguise("Guard saw through the disguise!")

	return success

# ── Drop Logic ──

func _on_enemy_died(enemy: Node3D) -> void:
	# Enemies on Stealth/Political floors have a chance to drop a disguise
	if _disguise_drops_this_floor >= MAX_DISGUISE_DROPS:
		return

	var archetype = FloorManager.current_archetype
	if not archetype:
		return

	var arch_name: String = archetype.archetype_name
	if arch_name != "Stealth" and arch_name != "Political":
		return

	# 25% chance to drop a disguise from a killed enemy
	if _rng.randf() < 0.25:
		_disguise_drops_this_floor += 1
		_spawn_disguise_pickup(enemy)

func _spawn_disguise_pickup(enemy: Node3D) -> void:
	if not enemy or not is_instance_valid(enemy):
		return

	# Create a simple pickup item near the dead enemy
	var pickup := Area3D.new()
	pickup.name = "DisguisePickup"
	pickup.collision_layer = 0
	pickup.collision_mask = 2  # Units layer

	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.5
	col.shape = sphere
	pickup.add_child(col)

	# Visual — small glowing cloak mesh
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.4, 0.3, 0.4)
	mesh_inst.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.4, 0.7, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.3, 0.8)
	mat.emission_energy_multiplier = 0.5
	mesh_inst.set_surface_override_material(0, mat)
	mesh_inst.position.y = 0.3
	pickup.add_child(mesh_inst)

	# Determine faction based on archetype
	var faction := "guard"
	var color := Color(0.4, 0.4, 0.7)
	var archetype = FloorManager.current_archetype
	if archetype and archetype.archetype_name == "Political":
		var factions := ["Merchants Guild", "Soldiers Order", "Common Folk"]
		faction = factions[_rng.randi() % factions.size()]
		color = Color(0.5, 0.6, 0.3)

	pickup.set_meta("disguise_faction", faction)
	pickup.set_meta("disguise_color", color)

	# Auto-pickup on body enter
	pickup.body_entered.connect(func(body: Node3D) -> void:
		if body == GameManager.hero:
			equip_disguise(faction, color)
			pickup.queue_free()
	)

	pickup.global_position = enemy.global_position + Vector3(0, 0.3, 0)

	# Add to scene tree
	var tree := get_tree()
	if tree and tree.root:
		tree.root.add_child(pickup)

	# Despawn after 30 seconds
	var timer := get_tree().create_timer(30.0)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(pickup):
			pickup.queue_free()
	)

# ── Visual Effects ──

func _apply_visual() -> void:
	var hero = GameManager.hero
	if not hero or not is_instance_valid(hero):
		return
	# Apply a subtle color overlay to indicate disguised state
	if hero.has_method("set_tint_color"):
		hero.set_tint_color(disguise_color)
	_hero_tint_applied = true

func _remove_visual() -> void:
	var hero = GameManager.hero
	if not hero or not is_instance_valid(hero):
		return
	if hero.has_method("clear_tint_color"):
		hero.clear_tint_color()
	_hero_tint_applied = false

# ── Attack Detection (breaks disguise) ──

func on_hero_attacked() -> void:
	## Call this from hero.gd when the hero attacks anything.
	if is_disguised:
		break_disguise("Attacked while disguised")

# ── Floor Reset ──

func _on_floor_changed(_floor_num: int) -> void:
	if is_disguised:
		break_disguise("Floor transition")
	is_disguised = false
	disguise_faction = ""
	checks_passed = 0
	disguises_used_this_floor = 0
	_disguise_drops_this_floor = 0
	_hero_tint_applied = false

# ── Reset ──

func reset() -> void:
	if is_disguised:
		break_disguise("Run reset")
	is_disguised = false
	disguise_faction = ""
	checks_passed = 0
	disguises_used_this_floor = 0
	_disguise_drops_this_floor = 0
	_hero_tint_applied = false
