extends Node

## Narrator / Collective Voice — the dungeon's dramatic commentator.
## Distinct from audience chat (Twitch-style): this is the formal announcer.
## Floating text popups that commentate on player actions with dramatic flair.

signal narrator_says(text: String, color: Color, size: int)

# ----- Cooldown -----
var _cooldown: float = 0.0
const MIN_COOLDOWN: float = 4.0  # Seconds between narrator lines (prevent spam)
const BOSS_COOLDOWN: float = 6.0  # Longer cooldown for boss-related lines

# ----- State Tracking -----
var _kill_count_since_last: int = 0
var _kills_this_floor: int = 0
var _last_hp_ratio: float = 1.0
var _near_death_announced: bool = false
var _floor_start_time: float = 0.0
var _first_kill_announced: bool = false
var _boss_active: bool = false

var _rng := RandomNumberGenerator.new()

# ----- Line Pools (30+ lines organized by trigger) -----

const FIRST_BLOOD := [
	"The carnage begins.",
	"First blood has been drawn.",
	"And so it starts...",
	"The arena claims its first.",
]

const MULTI_KILL := [
	"A devastating display of power!",
	"Bodies hit the floor — plural.",
	"The champion shows no mercy!",
	"Efficient. Brutal. Beautiful.",
	"They fall like wheat before the scythe.",
]

const KILL_STREAK := [
	"An unstoppable force of nature!",
	"Is there no one who can stand against this warrior?",
	"The arena trembles before such fury!",
	"Relentless. Absolutely relentless.",
	"A storm of steel and fury!",
]

const NEAR_DEATH := [
	"One wrong step and it's over...",
	"The crowd holds its breath.",
	"Death's shadow looms close.",
	"How much longer can they hold on?",
	"Clinging to life by a thread!",
]

const SURVIVED_NEAR_DEATH := [
	"Against all odds — ALIVE!",
	"Snatched from the jaws of death!",
	"The crowd erupts! What a survivor!",
	"They refuse to die!",
]

const BOSS_ENTRANCE := [
	"A terrible presence stirs in the depths...",
	"The air grows heavy. Something massive approaches.",
	"RUN... or FIGHT. There is no hiding now.",
	"The champion faces their greatest test!",
	"The ground shakes. A colossus awakens.",
]

const BOSS_KILLED := [
	"THE BEAST FALLS! What a magnificent display!",
	"Against all odds — VICTORY over the titan!",
	"A legendary takedown! The arena roars!",
	"The floor guardian has been vanquished!",
]

const BOREDOM := [
	"The audience grows restless...",
	"Is the champion lost? Or merely cowardly?",
	"Somewhere, a spectator yawns audibly.",
	"The Collective demands entertainment. This is not it.",
	"Even the torches flicker with boredom.",
]

const FLOOR_ENTER := [
	"A new floor. New dangers await.",
	"Deeper into the dungeon. Deeper into madness.",
	"The walls close in. The air thickens.",
	"Another floor conquered — but at what cost?",
]

const FLOOR_CLEARED := [
	"The floor is cleansed! None remain standing.",
	"Every soul on this floor... silenced.",
	"Total domination. The exit awaits.",
	"The champion owns this ground now.",
]

const SPELL_MASTERY := [
	"Arcane mastery on full display!",
	"The elements bend to their will!",
	"A symphony of destruction!",
	"Spellwork that would make a mage weep!",
]

const HEAL_LOW_HP := [
	"A desperate heal — just in time!",
	"Wisdom in the chaos. A moment to recover.",
	"The champion knows when to mend, not rend.",
]

const OVERTIME := [
	"THE WALLS ARE CLOSING IN!",
	"Time has run out — the dungeon devours the slow!",
	"RUN. NOW. The floor collapses!",
]

# ----- Core -----

func _ready() -> void:
	_rng.randomize()
	GameManager.enemy_died.connect(_on_enemy_died)
	GameManager.all_enemies_cleared.connect(_on_floor_cleared)
	GameManager.game_over.connect(_on_game_over)
	FloorManager.floor_changed.connect(_on_floor_changed)
	AudienceManager.boredom_started.connect(_on_boredom)
	AudienceManager.mood_changed.connect(_on_mood_changed)
	SmusherTimer.overtime_started.connect(_on_overtime)

func _process(delta: float) -> void:
	if _cooldown > 0:
		_cooldown -= delta

	# Track near-death state
	var hero = GameManager.hero
	if hero and is_instance_valid(hero) and not hero.is_dead:
		var hp_ratio: float = float(hero.current_health) / float(hero.max_health)
		# Announce near-death when dropping below 15%
		if hp_ratio <= 0.15 and _last_hp_ratio > 0.15 and not _near_death_announced:
			_near_death_announced = true
			_say_line(NEAR_DEATH, Color(1.0, 0.3, 0.3), 28)
		# Announce survival when recovering above 40% after near-death
		elif hp_ratio > 0.4 and _near_death_announced:
			_near_death_announced = false
			_say_line(SURVIVED_NEAR_DEATH, Color(0.3, 1.0, 0.5), 30)
		_last_hp_ratio = hp_ratio

# ----- Say a line -----

func _say_line(pool: Array, color: Color, size: int = 24, override_cooldown: bool = false) -> void:
	if not override_cooldown and _cooldown > 0:
		return
	if pool.size() == 0:
		return

	var text: String = pool[_rng.randi() % pool.size()]
	narrator_says.emit(text, color, size)
	_cooldown = MIN_COOLDOWN

# ----- Event Handlers -----

func _on_enemy_died(enemy: Node3D) -> void:
	_kills_this_floor += 1
	_kill_count_since_last += 1

	# First kill on the floor
	if _kills_this_floor == 1 and not _first_kill_announced:
		_first_kill_announced = true
		_say_line(FIRST_BLOOD, Color(0.8, 0.2, 0.2), 26)
		return

	# Check if it's a boss
	if enemy and is_instance_valid(enemy) and enemy.get("boss_type") != null and enemy.boss_type != "":
		_boss_active = false
		_say_line(BOSS_KILLED, Color(1.0, 0.85, 0.2), 32, true)  # Override cooldown for boss kills
		_cooldown = BOSS_COOLDOWN
		_kill_count_since_last = 0
		return

	# Kill streak announcements (every 5 kills)
	if _kill_count_since_last >= 5 and _kill_count_since_last % 5 == 0:
		_say_line(KILL_STREAK, Color(1.0, 0.6, 0.0), 28)
		return

func _on_floor_cleared() -> void:
	_say_line(FLOOR_CLEARED, Color(0.2, 1.0, 0.8), 28, true)

func _on_floor_changed(floor_num: int) -> void:
	_kills_this_floor = 0
	_kill_count_since_last = 0
	_first_kill_announced = false
	_near_death_announced = false
	_boss_active = false
	_floor_start_time = Time.get_ticks_msec() / 1000.0
	if floor_num > 1:
		_say_line(FLOOR_ENTER, Color(0.6, 0.7, 1.0), 26, true)

func _on_boredom() -> void:
	_say_line(BOREDOM, Color(0.5, 0.5, 0.5), 24, true)

func _on_mood_changed(new_mood: int) -> void:
	# Announce spell mastery when audience gets excited
	if new_mood == AudienceManager.Mood.EXCITED:
		if _rng.randf() < 0.4:
			_say_line(SPELL_MASTERY, Color(0.4, 0.8, 1.0), 26)

func _on_overtime() -> void:
	_say_line(OVERTIME, Color(1.0, 0.0, 0.0), 32, true)

func _on_game_over(won: bool) -> void:
	_cooldown = 0.0  # Reset for final line

# ----- Boss Entrance (called externally by boss_enemy.gd) -----

func announce_boss() -> void:
	_boss_active = true
	_say_line(BOSS_ENTRANCE, Color(0.8, 0.2, 0.6), 30, true)
	_cooldown = BOSS_COOLDOWN

# ----- Heal Commentary (called by hero when healing at low HP) -----

func on_hero_healed(hp_ratio_before: float) -> void:
	if hp_ratio_before <= 0.3:
		_say_line(HEAL_LOW_HP, Color(0.3, 1.0, 0.5), 24)

# ----- Reset -----

func reset() -> void:
	_cooldown = 0.0
	_kill_count_since_last = 0
	_kills_this_floor = 0
	_last_hp_ratio = 1.0
	_near_death_announced = false
	_first_kill_announced = false
	_boss_active = false
	_floor_start_time = 0.0
