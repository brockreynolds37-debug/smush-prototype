extends Node

## FloorArchetypeManager — autoload that picks a floor archetype per floor
## from a weighted pool. Archetypes define win conditions and gameplay modes.
##
## Dynamic Collective Curation (Task 70):
## The Collective watches play patterns and biases archetype selection.
## - If last 3 floors used the same solution path → bias toward archetypes
##   that favor a different path (forces adaptation).
## - If recent VP has been low → Narrator calls it out + adds a handicap modifier.

signal curation_applied(reason: String)

## Weighted archetype pool: [ArchetypeClass, weight, preferred_path]
var _archetype_pool: Array = [
	[CrawlArchetype, 5, "combat"],
	[EscapeArchetype, 2, "speed"],
	[SurvivalArenaArchetype, 3, "combat"],
	[StealthArchetype, 2, "clever"],
	[EconomyArchetype, 2, "social"],
	[BossRushArchetype, 1, "combat"],
	[PoliticalArchetype, 2, "social"],
	[InversionArchetype, 2, "clever"],
	[RaceArchetype, 2, "speed"],
]

## Curation state
var _curation_active: bool = false
var _curation_reason: String = ""
var _handicap_modifier: Dictionary = {}

## VP tracking for "boring" detection
var _floor_vp_history: Array[int] = []
const BORING_VP_THRESHOLD := 200  # Average VP per floor below this = boring
const BORING_WINDOW := 3

## Handicap modifiers the Collective can impose
const COLLECTIVE_HANDICAPS := [
	{
		"id": "collective_fog",
		"name": "The Collective's Displeasure",
		"description": "The Collective has dimmed the lights. Reduced visibility.",
		"color": Color(0.5, 0.3, 0.6),
	},
	{
		"id": "collective_speed",
		"name": "Impatient Audience",
		"description": "The Smusher advances 20% faster. Entertain them!",
		"color": Color(0.9, 0.3, 0.3),
	},
	{
		"id": "collective_elites",
		"name": "Raised Stakes",
		"description": "More elite enemies spawn. The audience demands spectacle.",
		"color": Color(0.8, 0.5, 0.2),
	},
]

const CURATION_NARRATOR_STREAK := [
	"You've been awfully predictable lately. The Collective has... adjusted.",
	"Three floors of the same approach? The audience demands variety.",
	"The Collective has noticed your patterns. Expect something different.",
	"Repetition is the enemy of entertainment. The Collective adapts.",
]
const CURATION_NARRATOR_BORING := [
	"You've been dreadfully predictable. The Collective has added a complication.",
	"The audience is yawning. The Collective intervenes.",
	"Low entertainment value detected. The Collective is not pleased.",
	"The viewers are leaving. The Collective adds spice.",
]

func _ready() -> void:
	FloorManager.floor_changed.connect(_on_floor_changed)

func _on_floor_changed(_floor_num: int) -> void:
	_floor_vp_history.append(AudienceManager.floor_vp)

## Pick an archetype for the given floor number.
## Tutorial and floor 1 are always Crawl.
func get_archetype_for_floor(floor_num: int) -> FloorArchetype:
	_curation_active = false
	_curation_reason = ""
	_handicap_modifier = {}

	if floor_num <= 1:
		var arch := CrawlArchetype.new()
		SolutionPathTracker.archetype_preferred_path = arch.audience_favorite_path
		return arch

	# ── Collective Curation Logic ──
	var curated_weights := _get_curated_weights()
	_check_boring()

	var total_weight: float = 0.0
	for entry in curated_weights:
		total_weight += entry[1]

	var roll = randf() * total_weight
	var cumulative: float = 0.0
	for entry in curated_weights:
		cumulative += entry[1]
		if roll <= cumulative:
			var arch: FloorArchetype = entry[0].new()
			SolutionPathTracker.archetype_preferred_path = arch.audience_favorite_path
			_announce_curation()
			return arch

	var arch := CrawlArchetype.new()
	SolutionPathTracker.archetype_preferred_path = arch.audience_favorite_path
	return arch

## ── Curation Weight Adjustment ──

func _get_curated_weights() -> Array:
	var weights := _archetype_pool.duplicate(true)

	# Check if player has been using the same path for 3+ floors
	if SolutionPathTracker.was_same_path_streak(3):
		var repeated_path: String = SolutionPathTracker.get_dominant_path()
		_curation_active = true
		_curation_reason = "streak"

		# Reduce weight of archetypes that favor the repeated path
		# Increase weight of archetypes that favor different paths
		for i in range(weights.size()):
			var entry_path: String = weights[i][2]
			if entry_path == repeated_path:
				weights[i][1] = maxi(int(weights[i][1] * 0.3), 1)
			else:
				weights[i][1] = int(weights[i][1] * 2.0)

	# Also check last-2-floor patterns for softer bias
	elif SolutionPathTracker.last_three_paths.size() >= 2:
		var last_two := SolutionPathTracker.last_three_paths.slice(-2)
		if last_two.size() >= 2 and last_two[0] == last_two[1]:
			var repeated_path: String = last_two[0]
			for i in range(weights.size()):
				var entry_path: String = weights[i][2]
				if entry_path == repeated_path:
					weights[i][1] = int(weights[i][1] * 0.6)

	return weights

func _check_boring() -> bool:
	if _floor_vp_history.size() < BORING_WINDOW:
		return false

	var recent := _floor_vp_history.slice(-BORING_WINDOW)
	var avg_vp := 0.0
	for vp in recent:
		avg_vp += vp
	avg_vp /= recent.size()

	if avg_vp < BORING_VP_THRESHOLD:
		_curation_active = true
		_curation_reason = "boring"
		_handicap_modifier = COLLECTIVE_HANDICAPS[randi() % COLLECTIVE_HANDICAPS.size()]
		return true

	return false

func _announce_curation() -> void:
	if not _curation_active:
		return

	# Delay announcement so floor is loaded
	get_tree().create_timer(2.0).timeout.connect(func() -> void:
		match _curation_reason:
			"streak":
				var line: String = CURATION_NARRATOR_STREAK[randi() % CURATION_NARRATOR_STREAK.size()]
				Narrator.queue_line(line, Color(0.8, 0.4, 0.9))
				AudienceManager.grant_vp(10, "Collective Curation")
				curation_applied.emit("Path streak — archetype weights adjusted")

			"boring":
				var line: String = CURATION_NARRATOR_BORING[randi() % CURATION_NARRATOR_BORING.size()]
				Narrator.queue_line(line, Color(0.9, 0.3, 0.3))
				if not _handicap_modifier.is_empty():
					Narrator.queue_line(
						"Handicap: %s" % _handicap_modifier.get("description", ""),
						_handicap_modifier.get("color", Color.RED)
					)
				curation_applied.emit("Low VP — handicap: %s" % _handicap_modifier.get("name", ""))
	)

## ── Query API ──

func is_curation_active() -> bool:
	return _curation_active

func get_curation_reason() -> String:
	return _curation_reason

func get_handicap_modifier() -> Dictionary:
	return _handicap_modifier

func has_handicap(modifier_id: String) -> bool:
	return _handicap_modifier.get("id", "") == modifier_id

func reset() -> void:
	_curation_active = false
	_curation_reason = ""
	_handicap_modifier = {}
	_floor_vp_history.clear()
