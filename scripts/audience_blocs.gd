extends Node

## AudienceBlocs — civilizational viewer groups in the Collective's audience.
## Each bloc has a favorite character class, preferred play path, and a mood score.
## High bloc mood = bonus VP + specialized gifts + Narrator acknowledgment.
## Built on top of AudienceManager.

signal bloc_mood_changed(bloc_id: String, new_mood: int)
signal bloc_cheer(bloc_id: String, text: String, color: Color)

## ── Bloc Definitions ──
## Each bloc: { name, color, fav_classes, fav_paths, mood, comments_cheer, comments_taunt }

var blocs: Dictionary = {}

const BLOC_DEFS := {
	"viking": {
		"name": "Viking Stands",
		"color": Color(0.9, 0.5, 0.2),
		"fav_classes": ["Berserker", "Brawler"],
		"fav_paths": ["combat"],
		"cheer_lines": [
			"SKÅL! Blood for the arena!",
			"The Northborn approve! MORE CARNAGE!",
			"Vikings are STANDING. This is a warrior!",
			"That hit was worthy of Valhalla!",
			"The Viking bloc is going absolutely feral!",
		],
		"taunt_lines": [
			"The Vikings are booing. They expected blood.",
			"Too much talking, not enough fighting — Viking bloc restless.",
			"The Northborn section is throwing mead at the screen.",
		],
	},
	"roman": {
		"name": "Imperial Senate",
		"color": Color(0.8, 0.7, 0.3),
		"fav_classes": ["Paladin"],
		"fav_paths": ["social"],
		"cheer_lines": [
			"The Senate nods in approval. Order prevails.",
			"Imperial viewers applaud the tactical execution!",
			"Disciplined. Efficient. The Senate is impressed.",
			"A commander worthy of the Empire!",
			"The Roman bloc has risen from their seats!",
		],
		"taunt_lines": [
			"The Senate finds this... undisciplined.",
			"Roman viewers are filing complaints about the chaos.",
			"The Imperial bloc expected strategy, not flailing.",
		],
	},
	"elven": {
		"name": "Arcane Conclave",
		"color": Color(0.4, 0.3, 0.9),
		"fav_classes": ["Sorcerer"],
		"fav_paths": ["clever"],
		"cheer_lines": [
			"The Conclave senses true arcane mastery!",
			"Elven viewers are weaving approval sigils!",
			"Such spell variety! The Arcane Conclave applauds!",
			"The mages in the audience are taking notes.",
			"The Elven bloc is channeling collective approval!",
		],
		"taunt_lines": [
			"The Conclave is disappointed by the lack of magical finesse.",
			"Elven viewers are muttering about brute-force solutions.",
			"The Arcane section expected subtlety, not barbarism.",
		],
	},
	"shadow": {
		"name": "Shadow Court",
		"color": Color(0.3, 0.2, 0.35),
		"fav_classes": ["Assassin"],
		"fav_paths": ["clever", "speed"],
		"cheer_lines": [
			"The Shadow Court whispers approval from the darkness.",
			"Silent. Efficient. The assassin bloc is pleased.",
			"The Court appreciates the... subtlety.",
			"Shadow viewers are sharing this kill on the dark net.",
			"The Shadow Court is invisible, but you can feel their approval.",
		],
		"taunt_lines": [
			"The Shadow Court sighs. Too loud. Too messy.",
			"Shadow viewers expected finesse, not a brawl.",
			"The Court has gone silent. That's not a good sign.",
		],
	},
	"frontier": {
		"name": "Frontier Lodge",
		"color": Color(0.3, 0.6, 0.3),
		"fav_classes": ["Marksman"],
		"fav_paths": ["speed"],
		"cheer_lines": [
			"The Frontier Lodge is impressed by the speed!",
			"Scouts in the audience are tracking every move!",
			"That precision! The Lodge gives a standing ovation!",
			"The rangers in the stands are comparing times.",
			"Frontier bloc: 'Now THAT'S how you clear a floor!'",
		],
		"taunt_lines": [
			"The Lodge is restless. Too slow, too cautious.",
			"Frontier viewers expected more mobility.",
			"The scouts are yawning. Pick up the pace.",
		],
	},
	"chaos": {
		"name": "Chaos Engine",
		"color": Color(1.0, 0.2, 0.6),
		"fav_classes": [],  # Loves everyone who plays creatively
		"fav_paths": ["clever"],
		"cheer_lines": [
			"CHAOS ENGINE OVERLOAD! They love the madness!",
			"The AI viewers are calculating maximum entertainment!",
			"Chaos Engine: 'PROBABILITY OF ENTERTAINMENT: 99.7%'",
			"The post-singularity bloc is losing its collective mind!",
			"Chaos Engine bloc is streaming this to 47 civilizations!",
		],
		"taunt_lines": [
			"Chaos Engine: 'ENTROPY LEVELS INSUFFICIENT.'",
			"The AI bloc predicted this 3 moves ago. Boring.",
			"Chaos Engine is threatening to switch to another dungeon.",
		],
	},
}

## Mood tiers per bloc: 0=Disinterested, 1=Watching, 2=Engaged, 3=Roaring
enum BlocMood { DISINTERESTED, WATCHING, ENGAGED, ROARING }
const MOOD_NAMES := ["Disinterested", "Watching", "Engaged", "ROARING"]
const MOOD_THRESHOLDS := [0, 30, 80, 150]  # Per-bloc VP thresholds

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_init_blocs()

	AudienceManager.vp_gained.connect(_on_vp_gained)
	GameManager.enemy_died.connect(_on_enemy_died)
	FloorManager.floor_changed.connect(_on_floor_changed)
	SolutionPathTracker.path_changed.connect(_on_path_changed)

func _init_blocs() -> void:
	for bloc_id in BLOC_DEFS:
		blocs[bloc_id] = {
			"vp": 0,
			"mood": BlocMood.WATCHING,
			"bonus_given": false,
		}

## ── VP Distribution ──
## When the player earns VP, distribute to blocs based on affinity.

func _on_vp_gained(amount: int, reason: String) -> void:
	var char_data := CharacterData.get_selected()
	var char_class: String = char_data.get("class", "")
	var current_path: String = SolutionPathTracker.get_dominant_path()

	for bloc_id in BLOC_DEFS:
		var def: Dictionary = BLOC_DEFS[bloc_id]
		var multiplier := 0.5  # Base: every bloc gets something

		# Class affinity bonus
		var fav_classes: Array = def.get("fav_classes", [])
		if char_class in fav_classes:
			multiplier += 0.5

		# Path affinity bonus
		var fav_paths: Array = def.get("fav_paths", [])
		if current_path in fav_paths:
			multiplier += 0.3

		# Chaos Engine bonus for environmental/creative kills
		if bloc_id == "chaos":
			if "Barrel" in reason or "Pillar" in reason or "Environment" in reason \
					or "Chain" in reason or "Multi-Hit" in reason or "Variety" in reason:
				multiplier += 0.5

		var bloc_vp := int(amount * multiplier)
		if bloc_vp > 0:
			_add_bloc_vp(bloc_id, bloc_vp)

func _add_bloc_vp(bloc_id: String, amount: int) -> void:
	if not blocs.has(bloc_id):
		return
	blocs[bloc_id]["vp"] += amount
	var new_mood := _calc_mood(blocs[bloc_id]["vp"])

	if new_mood != blocs[bloc_id]["mood"]:
		var old_mood: int = blocs[bloc_id]["mood"]
		blocs[bloc_id]["mood"] = new_mood
		bloc_mood_changed.emit(bloc_id, new_mood)

		# On mood upgrade, emit cheer + bonus VP
		if new_mood > old_mood:
			_bloc_cheer(bloc_id, new_mood)

		# On reaching ROARING, grant bonus VP and Narrator line
		if new_mood == BlocMood.ROARING and not blocs[bloc_id]["bonus_given"]:
			blocs[bloc_id]["bonus_given"] = true
			var def: Dictionary = BLOC_DEFS[bloc_id]
			var bonus := 50
			AudienceManager.grant_vp(bonus, "%s ROARING!" % def["name"])
			Narrator.queue_line(
				"The %s section has erupted! The Collective feeds on their energy!" % def["name"],
				def.get("color", Color.WHITE)
			)

func _calc_mood(vp: int) -> int:
	var mood := BlocMood.DISINTERESTED
	for i in range(MOOD_THRESHOLDS.size() - 1, -1, -1):
		if vp >= MOOD_THRESHOLDS[i]:
			mood = i
			break
	return mood

## ── Event Reactions ──

func _on_enemy_died(_enemy: Node3D) -> void:
	# Viking bloc loves kills
	_add_bloc_vp("viking", 5)
	# Chaos Engine gets a small bump for any death
	_add_bloc_vp("chaos", 3)

func _on_floor_changed(_floor_number: int) -> void:
	# Reset per-floor bloc VP and mood
	for bloc_id in blocs:
		blocs[bloc_id]["vp"] = 0
		blocs[bloc_id]["mood"] = BlocMood.WATCHING
		blocs[bloc_id]["bonus_given"] = false

func _on_path_changed(new_path: String, _old_path: String) -> void:
	# When player switches path, blocs that like the new path get excited
	for bloc_id in BLOC_DEFS:
		var fav_paths: Array = BLOC_DEFS[bloc_id].get("fav_paths", [])
		if new_path in fav_paths:
			_add_bloc_vp(bloc_id, 15)
	# Chaos Engine loves path switches (unpredictability)
	_add_bloc_vp("chaos", 10)

## ── Cheer / Taunt ──

func _bloc_cheer(bloc_id: String, mood: int) -> void:
	if not BLOC_DEFS.has(bloc_id):
		return
	var def: Dictionary = BLOC_DEFS[bloc_id]

	if mood >= BlocMood.ENGAGED:
		var lines: Array = def.get("cheer_lines", [])
		if not lines.is_empty():
			var line: String = lines[_rng.randi() % lines.size()]
			bloc_cheer.emit(bloc_id, line, def.get("color", Color.WHITE))
			# 40% chance Narrator relays the cheer
			if _rng.randf() < 0.4:
				Narrator.queue_line(line, def.get("color", Color.WHITE))

func emit_taunt(bloc_id: String) -> void:
	if not BLOC_DEFS.has(bloc_id):
		return
	var def: Dictionary = BLOC_DEFS[bloc_id]
	var lines: Array = def.get("taunt_lines", [])
	if not lines.is_empty():
		var line: String = lines[_rng.randi() % lines.size()]
		bloc_cheer.emit(bloc_id, line, def.get("color", Color.WHITE))
		Narrator.queue_line(line, def.get("color", Color.WHITE))

## ── Query API ──

func get_bloc_mood(bloc_id: String) -> int:
	if blocs.has(bloc_id):
		return blocs[bloc_id]["mood"]
	return BlocMood.DISINTERESTED

func get_bloc_mood_name(bloc_id: String) -> String:
	var mood := get_bloc_mood(bloc_id)
	return MOOD_NAMES[mood]

func get_loudest_bloc() -> String:
	var best_id := ""
	var best_vp := -1
	for bloc_id in blocs:
		if blocs[bloc_id]["vp"] > best_vp:
			best_vp = blocs[bloc_id]["vp"]
			best_id = bloc_id
	return best_id

func get_summary() -> String:
	var lines: Array[String] = []
	for bloc_id in BLOC_DEFS:
		var def: Dictionary = BLOC_DEFS[bloc_id]
		var state: Dictionary = blocs.get(bloc_id, {})
		var mood_name := MOOD_NAMES[state.get("mood", 0)]
		lines.append("%s: %s (VP: %d)" % [def["name"], mood_name, state.get("vp", 0)])
	return "\n".join(lines)

## ── Gift Bonus ──
## When a bloc is ROARING, gifts from AudienceManager have a bonus chance.

func get_gift_chance_bonus() -> float:
	var bonus := 0.0
	for bloc_id in blocs:
		if blocs[bloc_id]["mood"] == BlocMood.ROARING:
			bonus += 0.1  # Each roaring bloc adds 10% gift chance
	return minf(bonus, 0.4)  # Cap at 40% bonus

## ── Reset ──

func reset() -> void:
	_init_blocs()
