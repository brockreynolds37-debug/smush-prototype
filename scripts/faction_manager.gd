extends Node

## FactionManager — tracks per-faction reputation scores across floors.
## Actions affect reputation: killing guards = guard rep down, helping citizens = up.
## High rep unlocks shortcuts, discounts, ally buffs. Low rep = hostile on sight.
## Rep persists if Collective recycles a faction on later floors.

signal reputation_changed(faction: String, old_rep: int, new_rep: int)
signal faction_status_changed(faction: String, status: String)

## Reputation ranges: -100 to +100
const REP_MIN := -100
const REP_MAX := 100

## Status thresholds
const HOSTILE_THRESHOLD := -50
const UNFRIENDLY_THRESHOLD := -20
const NEUTRAL_LOW := -19
const NEUTRAL_HIGH := 19
const FRIENDLY_THRESHOLD := 20
const ALLIED_THRESHOLD := 50
const REVERED_THRESHOLD := 80

enum Status { HOSTILE, UNFRIENDLY, NEUTRAL, FRIENDLY, ALLIED, REVERED }

const STATUS_NAMES := {
	Status.HOSTILE: "Hostile",
	Status.UNFRIENDLY: "Unfriendly",
	Status.NEUTRAL: "Neutral",
	Status.FRIENDLY: "Friendly",
	Status.ALLIED: "Allied",
	Status.REVERED: "Revered",
}

const STATUS_COLORS := {
	Status.HOSTILE: Color(1.0, 0.2, 0.2),
	Status.UNFRIENDLY: Color(1.0, 0.5, 0.3),
	Status.NEUTRAL: Color(0.7, 0.7, 0.7),
	Status.FRIENDLY: Color(0.4, 0.8, 0.4),
	Status.ALLIED: Color(0.3, 0.6, 1.0),
	Status.REVERED: Color(1.0, 0.85, 0.2),
}

## Faction definitions — each can appear on certain archetype floors
const FACTIONS := [
	"Merchants Guild",
	"Soldiers Order",
	"Mystics Circle",
	"Common Folk",
	"Thieves Network",
	"Dungeon Guards",
]

## Reputation scores: faction_name → int (-100 to +100)
var reputation: Dictionary = {}

## Track which factions have appeared on which floors
var faction_floor_history: Dictionary = {}  # faction → Array[int] of floor numbers

func _ready() -> void:
	_init_all_factions()
	FloorManager.floor_changed.connect(_on_floor_changed)

func _init_all_factions() -> void:
	for faction in FACTIONS:
		if not reputation.has(faction):
			reputation[faction] = 0

# ── Reputation API ──

func get_reputation(faction: String) -> int:
	return reputation.get(faction, 0)

func get_status(faction: String) -> int:
	var rep := get_reputation(faction)
	if rep <= HOSTILE_THRESHOLD:
		return Status.HOSTILE
	elif rep <= UNFRIENDLY_THRESHOLD:
		return Status.UNFRIENDLY
	elif rep >= REVERED_THRESHOLD:
		return Status.REVERED
	elif rep >= ALLIED_THRESHOLD:
		return Status.ALLIED
	elif rep >= FRIENDLY_THRESHOLD:
		return Status.FRIENDLY
	return Status.NEUTRAL

func get_status_name(faction: String) -> String:
	return STATUS_NAMES.get(get_status(faction), "Neutral")

func get_status_color(faction: String) -> Color:
	return STATUS_COLORS.get(get_status(faction), Color.WHITE)

func is_hostile(faction: String) -> bool:
	return get_status(faction) == Status.HOSTILE

func is_friendly(faction: String) -> bool:
	var s := get_status(faction)
	return s == Status.FRIENDLY or s == Status.ALLIED or s == Status.REVERED

func is_allied(faction: String) -> bool:
	var s := get_status(faction)
	return s == Status.ALLIED or s == Status.REVERED

func modify_reputation(faction: String, amount: int, reason: String = "") -> void:
	if not reputation.has(faction):
		reputation[faction] = 0
	var old_rep: int = reputation[faction]
	reputation[faction] = clampi(old_rep + amount, REP_MIN, REP_MAX)
	var new_rep: int = reputation[faction]
	if new_rep != old_rep:
		reputation_changed.emit(faction, old_rep, new_rep)
		# Check for status transitions
		var old_status := _status_for_rep(old_rep)
		var new_status := _status_for_rep(new_rep)
		if old_status != new_status:
			faction_status_changed.emit(faction, STATUS_NAMES[new_status])
			# VP for significant reputation shifts
			if new_status == Status.ALLIED:
				AudienceManager.grant_vp(30, "Allied with %s!" % faction)
			elif new_status == Status.HOSTILE:
				AudienceManager.grant_vp(20, "Now hostile with %s!" % faction)

func _status_for_rep(rep: int) -> int:
	if rep <= HOSTILE_THRESHOLD:
		return Status.HOSTILE
	elif rep <= UNFRIENDLY_THRESHOLD:
		return Status.UNFRIENDLY
	elif rep >= REVERED_THRESHOLD:
		return Status.REVERED
	elif rep >= ALLIED_THRESHOLD:
		return Status.ALLIED
	elif rep >= FRIENDLY_THRESHOLD:
		return Status.FRIENDLY
	return Status.NEUTRAL

# ── Common Actions ──

func on_guard_killed(faction: String = "Dungeon Guards") -> void:
	modify_reputation(faction, -15, "Killed a guard")
	modify_reputation("Soldiers Order", -10, "Violence against soldiers")

func on_citizen_helped(faction: String = "Common Folk") -> void:
	modify_reputation(faction, 10, "Helped a citizen")

func on_merchant_trade(faction: String = "Merchants Guild") -> void:
	modify_reputation(faction, 5, "Completed trade")

func on_stolen_from(faction: String) -> void:
	modify_reputation(faction, -20, "Theft detected")
	modify_reputation("Dungeon Guards", -10, "Criminal activity")

func on_quest_completed(faction: String) -> void:
	modify_reputation(faction, 25, "Quest completed")
	SolutionPathTracker.record_quest_complete()

func on_bribe_given(faction: String) -> void:
	modify_reputation(faction, 15, "Bribed")
	SolutionPathTracker.record_bribe()

func on_faction_member_killed(faction: String) -> void:
	modify_reputation(faction, -25, "Killed a member")

# ── Gameplay Effects ──

func get_discount_multiplier(faction: String) -> float:
	## Returns price multiplier for shops belonging to this faction.
	## Allied = 20% discount, Revered = 35% discount, Hostile = 50% markup
	var status := get_status(faction)
	match status:
		Status.REVERED: return 0.65
		Status.ALLIED: return 0.80
		Status.FRIENDLY: return 0.90
		Status.NEUTRAL: return 1.0
		Status.UNFRIENDLY: return 1.15
		Status.HOSTILE: return 1.50
	return 1.0

func can_access_shortcut(faction: String) -> bool:
	## Faction shortcuts require at least Friendly status.
	return is_friendly(faction)

func get_ally_buff_multiplier(faction: String) -> float:
	## Friendly/Allied factions give damage/defense buffs on their floors.
	var status := get_status(faction)
	match status:
		Status.REVERED: return 1.20
		Status.ALLIED: return 1.10
		Status.FRIENDLY: return 1.05
	return 1.0

# ── Floor Tracking ──

func _on_floor_changed(floor_num: int) -> void:
	# Record which factions appeared on this floor (set by archetypes)
	pass

func register_floor_factions(floor_num: int, faction_names: Array) -> void:
	## Called by archetypes to register which factions appear on this floor.
	for f in faction_names:
		if not faction_floor_history.has(f):
			faction_floor_history[f] = []
		faction_floor_history[f].append(floor_num)

# ── Summary ──

func get_reputation_summary() -> String:
	var lines: Array[String] = []
	for faction in FACTIONS:
		var rep := get_reputation(faction)
		if rep != 0:
			var status_name := get_status_name(faction)
			lines.append("%s: %d (%s)" % [faction, rep, status_name])
	if lines.is_empty():
		return "No faction reputation yet."
	return "\n".join(lines)

# ── Reset ──

func reset() -> void:
	reputation.clear()
	faction_floor_history.clear()
	_init_all_factions()
