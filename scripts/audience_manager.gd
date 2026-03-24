extends Node

## Audience/Entertainment Scoring System — core Smush mechanic.
## Tracks Viewership Points (VP) based on combat style, variety, and spectacle.
## The audience rewards entertaining play over efficient play.

signal vp_gained(amount: int, reason: String)
signal mood_changed(new_mood: int)
signal audience_comment(text: String, color: Color)
signal boredom_started()
signal boredom_ended()

# ----- VP State -----
var total_vp: int = 0
var floor_vp: int = 0
var is_bored: bool = false
var _bored_timer: float = 0.0
const BOREDOM_THRESHOLD: float = 60.0  # seconds without combat before boredom (shortened from bible's 300 for MVP pacing)

# ----- Audience Mood -----
# 0=Bored  1=Watching  2=Interested  3=Excited  4=ERUPTING
enum Mood { BORED, WATCHING, INTERESTED, EXCITED, ERUPTING }
var current_mood: int = Mood.WATCHING
const MOOD_THRESHOLDS := [0, 100, 500, 1500, 4000]  # VP thresholds per floor
const MOOD_NAMES := ["BORED", "WATCHING", "INTERESTED", "EXCITED", "ERUPTING"]
const MOOD_COLORS: Array[Color] = [
	Color(0.5, 0.5, 0.5),      # Bored - gray
	Color(0.8, 0.8, 0.8),      # Watching - white
	Color(0.3, 0.8, 1.0),      # Interested - cyan
	Color(1.0, 0.8, 0.0),      # Excited - gold
	Color(1.0, 0.2, 0.4),      # ERUPTING - hot pink/red
]

# ----- Kill Tracking -----
var _last_kill_time: float = 0.0
var _kill_chain: int = 0
const CHAIN_WINDOW: float = 4.0  # seconds between kills to maintain chain

# ----- Spell Variety -----
var _recent_spells: Array[int] = []  # last 4 spells used
const VARIETY_WINDOW: int = 4

# ----- Near-Death Tracking -----
var _near_death_active: bool = false
var _near_death_timer: float = 0.0
const NEAR_DEATH_HP_RATIO: float = 0.15  # below 15% HP
const NEAR_DEATH_VP_INTERVAL: float = 2.0  # VP every 2s while near-death

# ----- VP Rewards -----
const KILL_VP := {
	"goblin_scout": 15,
	"goblin_warrior": 20,
	"goblin_archer": 20,
	"skeleton_warrior": 25,
	"spider": 15,
	"slime": 10,
	"rat": 10,
	"boss_slime_lord": 300,
	"boss_forest_guardian": 250,
	"boss_crab_king": 350,
	"boss_kraken_spawn": 400,
}
const DEFAULT_KILL_VP: int = 20

const CHAIN_BONUS := [0, 0, 15, 30, 50, 75, 100]  # index = chain count, bonus VP
const MULTI_HIT_VP: int = 20      # per extra enemy hit by AOE (3+)
const SPELL_VARIETY_VP: int = 25   # using 3+ different spells in window
const NEAR_DEATH_VP: int = 30     # per tick while fighting below 15% HP
const BOSS_SPEED_KILL_VP: int = 150 # boss killed in under 60s on the floor
const FLOOR_CLEAR_VP: int = 100    # bonus for clearing all enemies

# ----- Audience Comments -----
const KILL_COMMENTS := [
	"LET'S GO", "SMUSH HIM", "ez clap", "POGGERS", "get rekt",
	"another one bites the dust", "clean kill", "nice",
]
const CHAIN_COMMENTS := [
	"KILL STREAK", "HE CAN'T BE STOPPED", "RAMPAGE", "UNSTOPPABLE",
	"the chat is going insane", "COMBO KING", "MULTI KILL",
]
const NEAR_DEATH_COMMENTS := [
	"HOW IS HE ALIVE", "clutch god", "ONE HP ANDY", "DON'T DIE",
	"this is CONTENT", "my heart can't take this", "HOLD ON",
]
const SPELL_COMMENTS := [
	"BEAUTIFUL SPELL WORK", "wizard mode", "the variety!",
	"mixing it up", "spellcaster diff", "ARCANE MASTERY",
]
const BORED_COMMENTS := [
	"ResidentSleeper", "zzz", "do something", "boring...",
	"where's the action?", "I'm switching streams", "wake me up",
]
const BOSS_COMMENTS := [
	"BOSS FIGHT BOSS FIGHT", "THIS IS IT", "can he do it?",
	"THE BIG ONE", "oh no oh no oh no", "LETS GOOOOO",
]
const ERUPTING_COMMENTS := [
	"ABSOLUTE CINEMA", "GAME OF THE YEAR", "I'M STANDING UP",
	"LEGENDARY", "THIS CRAWLER IS BUILT DIFFERENT", "GOAT STATUS",
]

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	GameManager.enemy_died.connect(_on_enemy_died)
	GameManager.all_enemies_cleared.connect(_on_floor_cleared)
	FloorManager.floor_changed.connect(_on_floor_changed)

func _process(delta: float) -> void:
	if GameManager.game_state != GameManager.GameState.PLAYING:
		return

	# Boredom tracking
	_bored_timer += delta
	if not is_bored and _bored_timer >= BOREDOM_THRESHOLD:
		is_bored = true
		boredom_started.emit()
		_emit_comment(BORED_COMMENTS, MOOD_COLORS[Mood.BORED])

	# Near-death VP ticks
	_update_near_death(delta)

# ----- Core VP Granting -----

func grant_vp(amount: int, reason: String) -> void:
	if is_bored:
		# Boredom halves VP gain (bible says pause, but half is more fun for MVP)
		amount = amount / 2

	total_vp += amount
	floor_vp += amount
	vp_gained.emit(amount, reason)
	_update_mood()

func _update_mood() -> void:
	var new_mood: int = Mood.BORED
	for i in range(MOOD_THRESHOLDS.size() - 1, -1, -1):
		if floor_vp >= MOOD_THRESHOLDS[i]:
			new_mood = i
			break
	if new_mood != current_mood:
		current_mood = new_mood
		mood_changed.emit(new_mood)
		if new_mood == Mood.ERUPTING:
			_emit_comment(ERUPTING_COMMENTS, MOOD_COLORS[Mood.ERUPTING])

# ----- Event Handlers -----

func _on_enemy_died(enemy: Node3D) -> void:
	# Reset boredom
	if is_bored:
		is_bored = false
		_bored_timer = 0.0
		boredom_ended.emit()
	else:
		_bored_timer = 0.0

	var now: float = Time.get_ticks_msec() / 1000.0

	# Determine enemy type
	var etype: String = ""
	if enemy != null and is_instance_valid(enemy):
		if enemy.get("boss_type") != null and enemy.boss_type != "":
			etype = "boss_" + enemy.boss_type
		elif enemy.get("enemy_type") != null:
			etype = enemy.enemy_type

	# Base kill VP
	var kill_vp: int = KILL_VP.get(etype, DEFAULT_KILL_VP)
	grant_vp(kill_vp, "Kill")

	# Kill chain bonus
	if now - _last_kill_time < CHAIN_WINDOW:
		_kill_chain += 1
	else:
		_kill_chain = 1
	_last_kill_time = now

	if _kill_chain >= 2:
		var chain_idx = mini(_kill_chain, CHAIN_BONUS.size() - 1)
		var bonus = CHAIN_BONUS[chain_idx]
		if bonus > 0:
			grant_vp(bonus, "%dx Chain" % _kill_chain)
			if _kill_chain >= 3:
				_emit_comment(CHAIN_COMMENTS, MOOD_COLORS[Mood.EXCITED])

	# Boss-specific comments
	if etype.begins_with("boss_"):
		_emit_comment(BOSS_COMMENTS, MOOD_COLORS[Mood.ERUPTING])
		# Speed kill check (boss killed within 60s of floor start)
		if GameManager.get_run_elapsed() > 0:
			# Use a simple heuristic: if total run time / floor count < 120s
			# it's a fast run. Better: track floor start time.
			grant_vp(BOSS_SPEED_KILL_VP, "Boss Takedown")
	else:
		# Random kill comment (30% chance to avoid spam)
		if _rng.randf() < 0.3:
			_emit_comment(KILL_COMMENTS, MOOD_COLORS[Mood.WATCHING])

func _on_floor_cleared() -> void:
	grant_vp(FLOOR_CLEAR_VP, "Floor Clear")

func _on_floor_changed(_floor_num: int) -> void:
	floor_vp = 0
	current_mood = Mood.WATCHING
	mood_changed.emit(current_mood)
	_kill_chain = 0
	_recent_spells.clear()
	_near_death_active = false
	_bored_timer = 0.0
	if is_bored:
		is_bored = false
		boredom_ended.emit()

# ----- Spell Variety -----

func on_spell_cast(spell_index: int) -> void:
	# Reset boredom on spell use
	_bored_timer = 0.0
	if is_bored:
		is_bored = false
		boredom_ended.emit()

	_recent_spells.append(spell_index)
	if _recent_spells.size() > VARIETY_WINDOW:
		_recent_spells.pop_front()

	# Count unique spells in window
	var unique := {}
	for s in _recent_spells:
		unique[s] = true
	if unique.size() >= 3:
		grant_vp(SPELL_VARIETY_VP, "Spell Variety")
		_emit_comment(SPELL_COMMENTS, MOOD_COLORS[Mood.INTERESTED])

# ----- AOE Multi-Hit -----

func on_aoe_hit(enemy_count: int) -> void:
	if enemy_count >= 3:
		var bonus = (enemy_count - 2) * MULTI_HIT_VP
		grant_vp(bonus, "Multi-Hit x%d" % enemy_count)

# ----- Near-Death Tracking -----

func _update_near_death(delta: float) -> void:
	var hero = GameManager.hero
	if hero == null or not is_instance_valid(hero) or hero.is_dead:
		_near_death_active = false
		return

	var hp_ratio: float = float(hero.current_health) / float(hero.max_health)
	if hp_ratio <= NEAR_DEATH_HP_RATIO and hp_ratio > 0:
		if not _near_death_active:
			_near_death_active = true
			_near_death_timer = 0.0
		_near_death_timer += delta
		if _near_death_timer >= NEAR_DEATH_VP_INTERVAL:
			_near_death_timer -= NEAR_DEATH_VP_INTERVAL
			grant_vp(NEAR_DEATH_VP, "Near Death")
			_emit_comment(NEAR_DEATH_COMMENTS, Color(1.0, 0.3, 0.3))
	else:
		_near_death_active = false

# ----- Audience Comments -----

func _emit_comment(pool: Array, color: Color) -> void:
	if pool.size() == 0:
		return
	var text: String = pool[_rng.randi() % pool.size()]
	audience_comment.emit(text, color)

# ----- Reward Tier -----

func get_reward_tier() -> int:
	# Returns 0-4 based on floor VP, used for between-floor loot quality
	for i in range(MOOD_THRESHOLDS.size() - 1, -1, -1):
		if floor_vp >= MOOD_THRESHOLDS[i]:
			return i
	return 0

func get_mood_name() -> String:
	return MOOD_NAMES[current_mood]

func get_mood_color() -> Color:
	return MOOD_COLORS[current_mood]

# ----- Reset -----

func reset() -> void:
	total_vp = 0
	floor_vp = 0
	current_mood = Mood.WATCHING
	is_bored = false
	_bored_timer = 0.0
	_kill_chain = 0
	_last_kill_time = 0.0
	_recent_spells.clear()
	_near_death_active = false
	_near_death_timer = 0.0
