extends Node3D

## SummonSpell — spawns a SummonMinion near the hero.
## Called by hero spell system. Respects max summon count (2).

class_name SummonSpell

static func cast(hero: Node3D) -> void:
	if not is_instance_valid(hero):
		return

	# Check summon cap
	var summon_count: int = hero.get("summon_count") if hero.get("summon_count") != null else 0
	var max_summons: int = 2
	if summon_count >= max_summons:
		return

	var minion = SummonMinion.new()
	minion.name = "Summon_%d" % (summon_count + 1)

	# Spawn near hero
	var offset = Vector3(randf_range(-2.0, 2.0), 0, randf_range(-2.0, 2.0))
	minion.position = hero.global_position + offset

	# Add to scene tree
	var tree = hero.get_tree()
	if tree and tree.root:
		tree.root.add_child(minion)

	# Track on hero
	if hero.has_method("_on_summon_spawned"):
		hero._on_summon_spawned(minion)
	else:
		hero.summon_count = summon_count + 1
		minion.minion_died.connect(func(_m): hero.summon_count -= 1)

	GameManager.request_screen_shake(2.0, 0.15)
