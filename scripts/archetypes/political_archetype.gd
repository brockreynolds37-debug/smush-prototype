extends FloorArchetype

## PoliticalArchetype — a town with NPC factions. Become mayor or assassinate the
## current one before stairs appear. Dialogue choices, bribe system, faction reputation.
## Can brute force it but guards are tough. WC3 Life of a Peasant meets Among Us.

class_name PoliticalArchetype

# ── Win conditions ──
enum WinPath { NONE, ELECTED, ASSASSINATED, BRUTE_FORCED }
var _win_path: int = WinPath.NONE

# ── Factions ──
# Each faction has a name, color, reputation (starts 0), vote threshold, and NPC positions
const ELECTION_THRESHOLD := 3  # Factions needed voting for you
const BRIBE_COST_BASE := 20
const ASSASSINATE_HP_FRACTION := 0.35  # Mayor HP = hero max HP * this (per floor scale)
const GUARD_DAMAGE := 25
const GUARD_COUNT := 4

var _factions: Array[Dictionary] = []
var _reputation: Dictionary = {}  # faction_name → int
var _mayor: Node3D = null
var _mayor_alive: bool = true
var _guards: Array[Node3D] = []
var _faction_npcs: Array[Node3D] = []
var _exit_portal: Node3D = null
var _exit_unlocked: bool = false
var _election_called: bool = false
var _hud_overlay: Control = null
var _dialogue_timer: float = 0.0  # Cooldown between interactions

func _init() -> void:
	archetype_name = "Political"
	flavor_text = "Become mayor. Or remove the current one."
	accent_color = Color(0.6, 0.3, 0.9)
	solution_paths = {"combat": true, "speed": false, "social": true, "clever": true}
	audience_favorite_path = "social"

func _register_solution_paths() -> void:
	SolutionPathTracker.register_floor_paths(
		SolutionPathTracker.paths_political(), "social"
	)

func start() -> void:
	super.start()
	_win_path = WinPath.NONE
	_mayor_alive = true
	_exit_unlocked = false
	_election_called = false
	_dialogue_timer = 0.0

	_build_factions()
	_spawn_faction_npcs()
	_spawn_mayor()
	_spawn_guards()
	_spawn_exit_portal()

	show_message("POLITICAL FLOOR — Win the election or remove the mayor.", accent_color, 4.0)
	show_message("[E] Talk / Bribe  |  Attack mayor to assassinate", Color(0.7, 0.7, 0.7), 3.0)

	GameManager.enemy_died.connect(_on_enemy_died)

func _build_factions() -> void:
	_factions = [
		{
			"name": "Merchants Guild",
			"color": Color(1.0, 0.85, 0.2),
			"bribe_cost": BRIBE_COST_BASE + floor_number * 5,
			"persuade_dc": 0.5,  # Base chance of persuasion
			"quest": "deliver",  # Quest type for reputation
			"position": Vector3(-12, 0, 10),
			"flavor": "Gold speaks louder than words.",
		},
		{
			"name": "Soldiers Order",
			"color": Color(0.3, 0.4, 0.7),
			"bribe_cost": BRIBE_COST_BASE + floor_number * 8,
			"persuade_dc": 0.35,
			"quest": "kill",
			"position": Vector3(12, 0, 10),
			"flavor": "Prove your strength.",
		},
		{
			"name": "Mystics Circle",
			"color": Color(0.7, 0.2, 0.8),
			"bribe_cost": BRIBE_COST_BASE + floor_number * 6,
			"persuade_dc": 0.45,
			"quest": "riddle",
			"position": Vector3(-12, 0, 22),
			"flavor": "Knowledge is the only currency that matters.",
		},
		{
			"name": "Common Folk",
			"color": Color(0.5, 0.7, 0.3),
			"bribe_cost": int((BRIBE_COST_BASE + floor_number * 3) * 0.6),
			"persuade_dc": 0.6,
			"quest": "help",
			"position": Vector3(12, 0, 22),
			"flavor": "We just want someone who listens.",
		},
		{
			"name": "Thieves Network",
			"color": Color(0.3, 0.3, 0.3),
			"bribe_cost": BRIBE_COST_BASE + floor_number * 4,
			"persuade_dc": 0.4,
			"quest": "steal",
			"position": Vector3(0, 0, 28),
			"flavor": "Everyone has a price. Find the mayor's.",
		},
	]

	_reputation.clear()
	for f in _factions:
		_reputation[f["name"]] = 0

func _spawn_faction_npcs() -> void:
	if not builder:
		return

	for faction in _factions:
		var npc = CharacterBody3D.new()
		npc.name = faction["name"].replace(" ", "_")

		# Collision
		var col = CollisionShape3D.new()
		var capsule = CapsuleShape3D.new()
		capsule.radius = 0.4
		capsule.height = 1.8
		col.shape = capsule
		npc.add_child(col)

		# Visual
		var mesh = MeshInstance3D.new()
		var capsule_mesh = CapsuleMesh.new()
		capsule_mesh.radius = 0.4
		capsule_mesh.height = 1.8
		mesh.mesh = capsule_mesh
		var mat = StandardMaterial3D.new()
		mat.albedo_color = faction["color"]
		mat.emission_enabled = true
		mat.emission = faction["color"] * 0.4
		mat.emission_energy_multiplier = 0.6
		mesh.material_override = mat
		npc.add_child(mesh)

		# Name label
		var label = Label3D.new()
		label.text = faction["name"]
		label.font_size = 44
		label.position = Vector3(0, 1.8, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = faction["color"]
		label.name = "NameLabel"
		npc.add_child(label)

		# Rep label (below name)
		var rep_label = Label3D.new()
		rep_label.text = "Neutral"
		rep_label.font_size = 32
		rep_label.position = Vector3(0, 1.5, 0)
		rep_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		rep_label.modulate = Color(0.6, 0.6, 0.6)
		rep_label.name = "RepLabel"
		npc.add_child(rep_label)

		npc.set_meta("faction", faction)
		npc.position = faction["position"]
		npc.position.y = 0.0
		builder.add_child(npc)
		_faction_npcs.append(npc)

func _spawn_mayor() -> void:
	if not builder:
		return

	_mayor = CharacterBody3D.new()
	_mayor.name = "Mayor"

	var col = CollisionShape3D.new()
	var capsule = CapsuleShape3D.new()
	capsule.radius = 0.5
	capsule.height = 2.0
	col.shape = capsule
	_mayor.add_child(col)

	var mesh = MeshInstance3D.new()
	var capsule_mesh = CapsuleMesh.new()
	capsule_mesh.radius = 0.5
	capsule_mesh.height = 2.0
	mesh.mesh = capsule_mesh
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.1, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.2, 0.1)
	mat.emission_energy_multiplier = 1.0
	mat.metallic = 0.5
	mesh.material_override = mat
	_mayor.add_child(mesh)

	var label = Label3D.new()
	label.text = "Mayor Krell"
	label.font_size = 52
	label.position = Vector3(0, 2.0, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(1.0, 0.3, 0.3)
	label.name = "MayorLabel"
	_mayor.add_child(label)

	# Mayor has HP — can be assassinated by attacking
	var mayor_hp := int(100 + floor_number * 40)
	_mayor.set_meta("max_health", mayor_hp)
	_mayor.set_meta("current_health", mayor_hp)
	_mayor.set_meta("is_enemy", true)  # So hero can target
	_mayor.set_meta("interact_cooldown", 0.0)

	# HP label
	var hp_label = Label3D.new()
	hp_label.text = "HP: %d/%d" % [mayor_hp, mayor_hp]
	hp_label.font_size = 36
	hp_label.position = Vector3(0, 2.4, 0)
	hp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hp_label.modulate = Color(1.0, 0.5, 0.5)
	hp_label.name = "HPLabel"
	_mayor.add_child(hp_label)

	_mayor.position = Vector3(0, 0, 16)
	builder.add_child(_mayor)

func _spawn_guards() -> void:
	if not builder:
		return

	var positions := [
		Vector3(-3, 0, 16), Vector3(3, 0, 16),
		Vector3(-2, 0, 19), Vector3(2, 0, 19),
	]

	for i in range(GUARD_COUNT):
		var guard = CharacterBody3D.new()
		guard.name = "TownGuard_%d" % i

		var col = CollisionShape3D.new()
		var capsule = CapsuleShape3D.new()
		capsule.radius = 0.4
		capsule.height = 1.8
		col.shape = capsule
		guard.add_child(col)

		var mesh = MeshInstance3D.new()
		var capsule_mesh = CapsuleMesh.new()
		capsule_mesh.radius = 0.4
		capsule_mesh.height = 1.8
		mesh.mesh = capsule_mesh
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.5, 0.2, 0.2)
		mat.emission_enabled = true
		mat.emission = Color(0.5, 0.15, 0.15)
		mat.emission_energy_multiplier = 0.5
		mesh.material_override = mat
		guard.add_child(mesh)

		var label = Label3D.new()
		label.text = "Town Guard"
		label.font_size = 36
		label.position = Vector3(0, 1.6, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color(0.8, 0.4, 0.4)
		guard.add_child(label)

		var pos = positions[i] if i < positions.size() else Vector3(randf_range(-6, 6), 0, randf_range(14, 20))
		guard.position = pos
		guard.set_meta("home_pos", pos)
		guard.set_meta("is_chasing", false)
		guard.set_meta("alert_timer", 0.0)
		guard.set_meta("patrol_angle", (TAU / GUARD_COUNT) * i)
		guard.set_meta("attack_cd", 0.0)
		# Guards are tough — scaled with floor
		guard.set_meta("max_health", 80 + floor_number * 30)
		guard.set_meta("current_health", 80 + floor_number * 30)
		guard.set_meta("damage", GUARD_DAMAGE + floor_number * 5)
		builder.add_child(guard)
		_guards.append(guard)

func _spawn_exit_portal() -> void:
	if not builder:
		return

	_exit_portal = Node3D.new()
	_exit_portal.name = "ExitPortal"

	var mesh = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 0.8
	torus.outer_radius = 1.4
	mesh.mesh = torus
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.2, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.3, 0.3)
	mat.emission_energy_multiplier = 0.5
	mesh.material_override = mat
	mesh.name = "PortalMesh"
	_exit_portal.add_child(mesh)

	var label = Label3D.new()
	label.text = "LOCKED"
	label.font_size = 52
	label.position = Vector3(0, 2.2, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(0.5, 0.5, 0.5)
	label.name = "PortalLabel"
	_exit_portal.add_child(label)

	_exit_portal.position = Vector3(0, 0, 34)
	builder.add_child(_exit_portal)

# ── MAIN UPDATE ──

func update(delta: float) -> void:
	if not _is_active:
		return

	_dialogue_timer = maxf(_dialogue_timer - delta, 0.0)

	var hero = GameManager.hero
	if not hero or hero.is_dead:
		return

	# Check for interaction
	if Input.is_action_just_pressed("interact") and _dialogue_timer <= 0:
		_try_interact(hero)

	# Check mayor assassination (hero attacking mayor)
	if _mayor_alive and is_instance_valid(_mayor):
		_check_mayor_hp()

	# Update guards
	_update_guards(hero, delta)

	# Check exit portal
	if _exit_unlocked and is_instance_valid(_exit_portal):
		var dist = hero.global_position.distance_to(_exit_portal.global_position)
		if dist < 2.5:
			_win_floor()

	_update_npc_labels()
	_update_hud()

# ── INTERACTION ──

func _try_interact(hero: Node3D) -> void:
	# Check faction NPCs
	for npc in _faction_npcs:
		if not is_instance_valid(npc):
			continue
		var dist = hero.global_position.distance_to(npc.global_position)
		if dist < 3.0:
			_interact_faction(npc, hero)
			return

	# Check mayor (for dialogue option, not attack)
	if _mayor_alive and is_instance_valid(_mayor):
		var dist = hero.global_position.distance_to(_mayor.global_position)
		if dist < 3.0:
			_interact_mayor(hero)
			return

func _interact_faction(npc: Node3D, hero: Node3D) -> void:
	var faction: Dictionary = npc.get_meta("faction", {})
	if faction.is_empty():
		return

	var fname: String = faction.get("name", "")
	var rep: int = _reputation.get(fname, 0)

	# If already allied (rep >= 3), they'll vote for you
	if rep >= 3:
		show_message("%s: \"You have our vote!\"" % fname, faction["color"], 2.0)
		_dialogue_timer = 1.0
		_check_election()
		return

	# Interaction: random between persuade, bribe, or quest
	var roll := randf()
	if roll < 0.4:
		# Persuade attempt
		_attempt_persuade(faction, hero)
	elif roll < 0.7:
		# Bribe option
		_attempt_bribe(faction, hero)
	else:
		# Quick quest
		_do_quest(faction, hero)

	_dialogue_timer = 1.5

func _attempt_persuade(faction: Dictionary, _hero: Node3D) -> void:
	var fname: String = faction.get("name", "")
	var dc: float = faction.get("persuade_dc", 0.5)
	# Reputation makes persuasion easier
	var rep: int = _reputation.get(fname, 0)
	dc += rep * 0.1

	if randf() < dc:
		_reputation[fname] = rep + 1
		var new_rep = _reputation[fname]
		show_message("%s impressed! (Rep: %d/3)" % [fname, new_rep], faction["color"], 2.0)
		AudienceManager.grant_vp(10, "Political persuasion!")
	else:
		show_message("\"%s\" is unconvinced." % fname, Color(0.6, 0.5, 0.4), 2.0)

func _attempt_bribe(faction: Dictionary, _hero: Node3D) -> void:
	var fname: String = faction.get("name", "")
	var cost: int = faction.get("bribe_cost", 30)

	if LootManager.gold >= cost:
		LootManager.gold -= cost
		LootManager.gold_changed.emit(LootManager.gold)
		_reputation[fname] = _reputation.get(fname, 0) + 2  # Bribes give +2 rep
		var new_rep = mini(_reputation[fname], 3)
		_reputation[fname] = new_rep
		show_message("Bribed %s for %dg! (Rep: %d/3)" % [fname, cost, new_rep], faction["color"], 2.5)
		AudienceManager.grant_vp(15, "Political bribery!")
	else:
		show_message("Need %dg to bribe %s. (Have: %dg)" % [cost, fname, LootManager.gold], Color(1.0, 0.4, 0.2), 2.0)

func _do_quest(faction: Dictionary, hero: Node3D) -> void:
	var fname: String = faction.get("name", "")
	var quest_type: String = faction.get("quest", "help")

	# Simplified quest — instant resolution based on hero stats/chance
	var success := false
	match quest_type:
		"deliver":
			# Merchants want gold tribute
			var tribute := 10 + floor_number * 2
			if LootManager.gold >= tribute:
				LootManager.gold -= tribute
				LootManager.gold_changed.emit(LootManager.gold)
				success = true
				show_message("Delivered %dg tribute to %s." % [tribute, fname], faction["color"], 2.0)
		"kill":
			# Soldiers respect combat prowess — check recent kills
			if GameManager.run_kills >= 5:
				success = true
				show_message("%s respects your combat record." % fname, faction["color"], 2.0)
			else:
				show_message("%s: \"Come back when you've proven yourself.\"" % fname, Color(0.5, 0.5, 0.5), 2.0)
		"riddle":
			# Mystics — random chance (simulating answering a riddle)
			if randf() < 0.6:
				success = true
				show_message("You answered the Mystics' riddle correctly!", faction["color"], 2.0)
			else:
				show_message("The riddle stumps you. Try again.", Color(0.5, 0.3, 0.6), 2.0)
		"help":
			# Common Folk — always succeed if you show up
			success = true
			show_message("You helped the Common Folk with their troubles.", faction["color"], 2.0)
		"steal":
			# Thieves — risky, check if guards are nearby
			var near_guard := false
			for guard in _guards:
				if is_instance_valid(guard):
					if guard.global_position.distance_to(hero.global_position) < 6.0:
						near_guard = true
						break
			if near_guard:
				show_message("Too many guards nearby for the Thieves' job.", Color(0.5, 0.5, 0.5), 2.0)
			else:
				success = true
				show_message("Completed a job for the Thieves Network.", faction["color"], 2.0)

	if success:
		_reputation[fname] = _reputation.get(fname, 0) + 1
		AudienceManager.grant_vp(12, "Political quest completed!")

func _check_election() -> void:
	if _election_called or _exit_unlocked:
		return

	var votes := 0
	for fname in _reputation:
		if _reputation[fname] >= 3:
			votes += 1

	if votes >= ELECTION_THRESHOLD:
		_election_called = true
		_win_path = WinPath.ELECTED
		show_message("ELECTION WON! You are the new mayor!", Color(0.2, 1.0, 0.4), 4.0)
		AudienceManager.grant_vp(80, "Elected mayor!")
		CrossFloorConsequences.set_tag(CrossFloorConsequences.TAG_MAYOR_ELECTED)
		GameManager.request_screen_shake(3.0, 0.2)
		_unlock_exit()

func _interact_mayor(_hero: Node3D) -> void:
	if not _mayor_alive:
		return

	# Taunt dialogue
	var taunts := [
		"Mayor Krell: \"You'll never take my seat.\"",
		"Mayor Krell: \"The factions are loyal to ME.\"",
		"Mayor Krell: \"Guards! Keep an eye on this one.\"",
		"Mayor Krell: \"Bribery won't work on me... much.\"",
		"Mayor Krell: \"I've survived worse than you.\"",
	]
	show_message(taunts[randi() % taunts.size()], Color(1.0, 0.3, 0.3), 2.5)
	_dialogue_timer = 2.0

	# Talking to mayor alerts nearby guards (mild)
	for guard in _guards:
		if is_instance_valid(guard):
			var dist = guard.global_position.distance_to(_mayor.global_position)
			if dist < 8.0 and not guard.get_meta("is_chasing", false):
				# Guards move closer to mayor
				guard.set_meta("home_pos", _mayor.global_position + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)))

# ── MAYOR ASSASSINATION ──

func _check_mayor_hp() -> void:
	if not is_instance_valid(_mayor):
		_on_mayor_killed()
		return

	var hp_label = _mayor.get_node_or_null("HPLabel")
	var current_hp: int = _mayor.get_meta("current_health", 0)
	var max_hp: int = _mayor.get_meta("max_health", 1)

	if hp_label:
		hp_label.text = "HP: %d/%d" % [current_hp, max_hp]

	if current_hp <= 0:
		_on_mayor_killed()

func _on_mayor_killed() -> void:
	if not _mayor_alive:
		return
	_mayor_alive = false
	_win_path = WinPath.ASSASSINATED

	show_message("MAYOR ASSASSINATED! Chaos erupts!", Color(1.0, 0.1, 0.1), 4.0)
	AudienceManager.grant_vp(60, "Mayor assassinated!")
	CrossFloorConsequences.set_tag(CrossFloorConsequences.TAG_MAYOR_ASSASSINATED)
	GameManager.request_screen_shake(5.0, 0.3)

	# All guards go hostile
	_alert_all_guards()

	# Clean up mayor node
	if is_instance_valid(_mayor):
		_mayor.queue_free()
	_mayor = null

	# Unlock exit after a brief delay (guards are the punishment)
	_unlock_exit()

func _on_enemy_died(enemy: Node3D) -> void:
	if not _is_active:
		return

	# Check if mayor was killed through combat system
	if enemy == _mayor:
		_on_mayor_killed()

	# Check if a guard was killed — audience loves it
	for i in range(_guards.size()):
		if _guards[i] == enemy:
			_guards.remove_at(i)
			AudienceManager.grant_vp(15, "Guard defeated!")
			break

# ── GUARDS ──

func _update_guards(hero: Node3D, delta: float) -> void:
	for guard in _guards:
		if not is_instance_valid(guard):
			continue

		var is_chasing: bool = guard.get_meta("is_chasing", false)
		var alert_timer: float = guard.get_meta("alert_timer", 0.0)

		if is_chasing:
			var dir = (hero.global_position - guard.global_position).normalized()
			dir.y = 0
			guard.velocity = dir * 5.5
			guard.move_and_slide()

			var dist = guard.global_position.distance_to(hero.global_position)
			if dist < 2.0:
				var atk_cd: float = guard.get_meta("attack_cd", 0.0) - delta
				guard.set_meta("attack_cd", atk_cd)
				if atk_cd <= 0:
					var dmg: int = guard.get_meta("damage", GUARD_DAMAGE)
					if hero.has_method("take_damage"):
						hero.take_damage(dmg)
					guard.set_meta("attack_cd", 1.2)

			alert_timer -= delta
			guard.set_meta("alert_timer", alert_timer)
			if alert_timer <= 0:
				guard.set_meta("is_chasing", false)
		else:
			var home: Vector3 = guard.get_meta("home_pos", guard.global_position)
			var angle: float = guard.get_meta("patrol_angle", 0.0) + delta * 0.4
			guard.set_meta("patrol_angle", angle)
			var target = home + Vector3(cos(angle) * 2.5, 0, sin(angle) * 2.5)
			var dir = (target - guard.global_position).normalized()
			dir.y = 0
			guard.velocity = dir * 1.5
			guard.move_and_slide()

			# Guards detect hero attacking mayor
			if _mayor_alive and is_instance_valid(_mayor):
				var hero_dist = guard.global_position.distance_to(hero.global_position)
				var mayor_dist = hero.global_position.distance_to(_mayor.global_position)
				if hero_dist < 10.0 and mayor_dist < 3.0:
					# Hero is close to mayor — guards get suspicious
					if Input.is_action_pressed("attack"):
						_alert_all_guards()

func _alert_all_guards() -> void:
	for guard in _guards:
		if is_instance_valid(guard):
			guard.set_meta("is_chasing", true)
			guard.set_meta("alert_timer", 15.0)
	show_message("GUARDS ALERTED!", Color(1.0, 0.2, 0.2), 2.0)

# ── EXIT ──

func _unlock_exit() -> void:
	_exit_unlocked = true

	if not is_instance_valid(_exit_portal):
		return

	var mesh = _exit_portal.get_node_or_null("PortalMesh")
	if mesh and mesh.material_override:
		mesh.material_override.albedo_color = Color(0.2, 0.8, 1.0)
		mesh.material_override.emission = Color(0.2, 0.8, 1.0)
		mesh.material_override.emission_energy_multiplier = 2.5

	var label = _exit_portal.get_node_or_null("PortalLabel")
	if label:
		label.text = "EXIT OPEN"
		label.modulate = Color(0.3, 1.0, 0.5)

func _win_floor() -> void:
	match _win_path:
		WinPath.ELECTED:
			show_message("The people have spoken. Long live the new mayor!", accent_color, 3.0)
		WinPath.ASSASSINATED:
			show_message("The mayor is dead. Power vacuum filled.", Color(1.0, 0.3, 0.1), 3.0)
		_:
			show_message("You escaped the political floor.", Color(0.7, 0.7, 0.7), 2.0)
	complete()

# ── NPC LABELS ──

func _update_npc_labels() -> void:
	for npc in _faction_npcs:
		if not is_instance_valid(npc):
			continue
		var faction: Dictionary = npc.get_meta("faction", {})
		var fname: String = faction.get("name", "")
		var rep: int = _reputation.get(fname, 0)

		var rep_label = npc.get_node_or_null("RepLabel")
		if rep_label:
			if rep >= 3:
				rep_label.text = "ALLIED (Will vote for you)"
				rep_label.modulate = Color(0.2, 1.0, 0.4)
			elif rep >= 1:
				rep_label.text = "Friendly (%d/3)" % rep
				rep_label.modulate = Color(0.7, 0.9, 0.4)
			else:
				rep_label.text = "Neutral (%d/3)" % rep
				rep_label.modulate = Color(0.6, 0.6, 0.6)

# ── HUD ──

func _update_hud() -> void:
	if not _hud_overlay:
		return

	var votes := 0
	for fname in _reputation:
		if _reputation[fname] >= 3:
			votes += 1

	var vote_label = _hud_overlay.get_node_or_null("VoteLabel")
	if vote_label:
		vote_label.text = "Faction Votes: %d / %d needed" % [votes, ELECTION_THRESHOLD]
		if votes >= ELECTION_THRESHOLD:
			vote_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
		else:
			vote_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))

	var mayor_label = _hud_overlay.get_node_or_null("MayorStatus")
	if mayor_label:
		if _mayor_alive:
			mayor_label.text = "Mayor Krell: ALIVE"
			mayor_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
		else:
			mayor_label.text = "Mayor Krell: DEAD"
			mayor_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))

	var path_label = _hud_overlay.get_node_or_null("PathLabel")
	if path_label:
		if _exit_unlocked:
			match _win_path:
				WinPath.ELECTED:
					path_label.text = "EXIT OPEN — Elected mayor!"
					path_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
				WinPath.ASSASSINATED:
					path_label.text = "EXIT OPEN — Mayor eliminated!"
					path_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.2))
		else:
			path_label.text = "[E] Talk to factions  |  Attack mayor to assassinate"
			path_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))

# ── OVERRIDES ──

func stop() -> void:
	super.stop()
	if GameManager.enemy_died.is_connected(_on_enemy_died):
		GameManager.enemy_died.disconnect(_on_enemy_died)
	for npc in _faction_npcs:
		if is_instance_valid(npc):
			npc.queue_free()
	_faction_npcs.clear()
	for guard in _guards:
		if is_instance_valid(guard):
			guard.queue_free()
	_guards.clear()
	if is_instance_valid(_mayor):
		_mayor.queue_free()
	_mayor = null
	if is_instance_valid(_exit_portal):
		_exit_portal.queue_free()
	_exit_portal = null

func has_boss() -> bool:
	return false

func has_merchant() -> bool:
	return true  # Merchant before political floor is fine

func has_smusher() -> bool:
	return true  # Smusher adds time pressure to politicking

func exit_visible_at_start() -> bool:
	return true  # Portal visible but locked

func uses_default_enemy_spawning() -> bool:
	return false  # We spawn guards + NPCs ourselves

func create_hud_overlay() -> Control:
	_hud_overlay = Control.new()
	_hud_overlay.name = "PoliticalHUD"
	_hud_overlay.set_anchors_preset(Control.PRESET_CENTER_TOP)

	var title = Label.new()
	title.name = "TitleLabel"
	title.text = "POLITICAL FLOOR"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", accent_color)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(-120, 8)
	_hud_overlay.add_child(title)

	var vote = Label.new()
	vote.name = "VoteLabel"
	vote.text = "Faction Votes: 0 / %d needed" % ELECTION_THRESHOLD
	vote.add_theme_font_size_override("font_size", 16)
	vote.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))
	vote.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vote.position = Vector2(-140, 32)
	_hud_overlay.add_child(vote)

	var mayor = Label.new()
	mayor.name = "MayorStatus"
	mayor.text = "Mayor Krell: ALIVE"
	mayor.add_theme_font_size_override("font_size", 14)
	mayor.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	mayor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mayor.position = Vector2(-100, 52)
	_hud_overlay.add_child(mayor)

	var path_hint = Label.new()
	path_hint.name = "PathLabel"
	path_hint.text = "[E] Talk to factions  |  Attack mayor to assassinate"
	path_hint.add_theme_font_size_override("font_size", 12)
	path_hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	path_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	path_hint.position = Vector2(-200, 70)
	_hud_overlay.add_child(path_hint)

	return _hud_overlay

func destroy_hud_overlay() -> void:
	if _hud_overlay and is_instance_valid(_hud_overlay):
		_hud_overlay.queue_free()
		_hud_overlay = null
