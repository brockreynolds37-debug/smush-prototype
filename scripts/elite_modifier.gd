extends RefCounted
class_name EliteModifier

## Applies elite/champion prefixes to enemies.
## Prefixes: Frenzied (+speed/damage), Armored (+HP/defense), Venomous (+poison),
## Giant (+size/HP), Vampiric (+lifesteal). 15% base chance per mob.

const ELITE_CHANCE := 0.15

enum EliteType { NONE, FRENZIED, ARMORED, VENOMOUS, GIANT, VAMPIRIC }

static var _prefix_names := {
	EliteType.FRENZIED: "Frenzied",
	EliteType.ARMORED: "Armored",
	EliteType.VENOMOUS: "Venomous",
	EliteType.GIANT: "Giant",
	EliteType.VAMPIRIC: "Vampiric",
}

static var _prefix_tints := {
	EliteType.FRENZIED: Color(1.0, 0.3, 0.1),    # Fiery red-orange
	EliteType.ARMORED: Color(0.6, 0.6, 0.7),      # Steel grey-blue
	EliteType.VENOMOUS: Color(0.2, 0.9, 0.1),     # Toxic green
	EliteType.GIANT: Color(0.8, 0.5, 0.2),         # Earthy brown-orange
	EliteType.VAMPIRIC: Color(0.6, 0.0, 0.3),     # Dark crimson
}

## Roll for elite status and apply if lucky. Returns the EliteType applied.
static func try_promote(enemy: Node3D, floor_number: int = 1) -> EliteType:
	# Higher floors = slightly higher elite chance
	var chance := ELITE_CHANCE + (floor_number - 1) * 0.02
	if randf() > chance:
		return EliteType.NONE

	# Pick a random prefix
	var types := [EliteType.FRENZIED, EliteType.ARMORED, EliteType.VENOMOUS, EliteType.GIANT, EliteType.VAMPIRIC]
	var elite_type: EliteType = types[randi() % types.size()]

	_apply_prefix(enemy, elite_type)
	return elite_type

## Force-apply a specific elite type (for testing or scripted encounters).
static func apply(enemy: Node3D, elite_type: EliteType) -> void:
	_apply_prefix(enemy, elite_type)

static func _apply_prefix(enemy: Node3D, elite_type: EliteType) -> void:
	# Tag the enemy so other systems can check
	enemy.set_meta("elite_type", elite_type)
	enemy.set_meta("elite_name", _prefix_names[elite_type])

	match elite_type:
		EliteType.FRENZIED:
			# +40% speed, +25% damage, -10% HP — fast and deadly
			enemy.move_speed *= 1.4
			enemy.attack_damage = int(enemy.attack_damage * 1.25)
			enemy.max_health = int(enemy.max_health * 0.9)
			enemy.current_health = enemy.max_health
			if enemy.has("attack_cooldown"):
				enemy.attack_cooldown *= 0.7  # Attacks faster

		EliteType.ARMORED:
			# +80% HP, -15% speed — tanky, slow
			enemy.max_health = int(enemy.max_health * 1.8)
			enemy.current_health = enemy.max_health
			enemy.move_speed *= 0.85

		EliteType.VENOMOUS:
			# +20% HP, applies poison on hit (handled via meta check in enemy attack)
			enemy.max_health = int(enemy.max_health * 1.2)
			enemy.current_health = enemy.max_health
			enemy.set_meta("venomous_dot", true)

		EliteType.GIANT:
			# +100% HP, +50% damage, +30% size, slower
			enemy.max_health = int(enemy.max_health * 2.0)
			enemy.current_health = enemy.max_health
			enemy.attack_damage = int(enemy.attack_damage * 1.5)
			enemy.move_speed *= 0.8
			# Scale up the model
			if enemy.has_node("EnemyModel"):
				enemy.get_node("EnemyModel").scale *= 1.3

		EliteType.VAMPIRIC:
			# +30% HP, heals 20% of damage dealt
			enemy.max_health = int(enemy.max_health * 1.3)
			enemy.current_health = enemy.max_health
			enemy.set_meta("vampiric_leech", 0.2)

	# Apply tint — defer to next frame so model is loaded
	var tint: Color = _prefix_tints[elite_type]
	enemy.set_meta("elite_tint", tint)

	# Visual: scale selection circle slightly for elites
	if enemy.has_node("SelectionCircle"):
		var circle: MeshInstance3D = enemy.get_node("SelectionCircle")
		circle.scale *= 1.2
		var mat := StandardMaterial3D.new()
		mat.albedo_color = tint
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = 0.5
		circle.set_surface_override_material(0, mat)

	# Add glowing outline effect — create a point light above the enemy with the tint color
	var light := OmniLight3D.new()
	light.name = "EliteGlow"
	light.light_color = tint
	light.light_energy = 1.5
	light.omni_range = 3.0
	light.position = Vector3.UP * 2.0
	enemy.add_child(light)

	# Nav agent speed update
	if enemy.has_node("NavigationAgent3D"):
		enemy.get_node("NavigationAgent3D").max_speed = enemy.move_speed

	# Schedule tint application after model is ready
	if enemy.is_inside_tree():
		enemy.call_deferred("_apply_elite_tint")
	else:
		# Connect to tree_entered to apply when added
		enemy.tree_entered.connect(func(): enemy.call_deferred("_apply_elite_tint"), CONNECT_ONE_SHOT)

## Get display name for an elite enemy (e.g., "Frenzied Goblin")
static func get_display_name(enemy: Node3D) -> String:
	if enemy.has_meta("elite_name"):
		var prefix: String = enemy.get_meta("elite_name")
		var base_name: String = enemy.enemy_type.capitalize().replace("_", " ")
		return prefix + " " + base_name
	return ""

## Check if an enemy is elite
static func is_elite(enemy: Node3D) -> bool:
	return enemy.has_meta("elite_type") and enemy.get_meta("elite_type") != EliteType.NONE
