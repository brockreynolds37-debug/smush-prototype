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

const MAGE_CASTING := [
	"The ground glows with arcane malice — MOVE!",
	"A caster! Watch the circles!",
	"Sorcery crackles in the air!",
	"The shaman conjures doom beneath your feet!",
	"Arcane circles! Don't stand in the fire!",
]

const SUMMON_SPAWNED := [
	"The champion calls upon dark allies!",
	"A loyal servant rises from nothing!",
	"Two can play at the numbers game!",
	"The dead fight for the living now.",
	"Reinforcements conjured from pure will!",
]

const OVERTIME := [
	"THE WALLS ARE CLOSING IN!",
	"Time has run out — the dungeon devours the slow!",
	"RUN. NOW. The floor collapses!",
]

# ----- PATH-AWARE REACTIONS -----
# Keyed by "archetype:path" or "any:path" for generic fallbacks.
# Minimum 5 lines per path per archetype as specified.

const PATH_REACTIONS := {
	# ── CRAWL ──
	"Dungeon Crawl:combat": [
		"A straightforward warrior. The arena appreciates simplicity.",
		"Kill everything. Classic approach. The crowd loves it.",
		"Blood and steel — the old-fashioned way.",
		"The champion paints the walls red. Efficient.",
		"No subtlety, all power. The audience approves.",
	],
	"Dungeon Crawl:speed": [
		"They sprint past danger. Bold or foolish?",
		"The speedrunner ignores the carnage. Risky.",
		"Not a single unnecessary step. Pure efficiency.",
		"The Collective watches a record attempt unfold.",
		"Less killing, more running. Unusual. Intriguing.",
	],
	"Dungeon Crawl:clever": [
		"Using traps against their makers. Poetic.",
		"The clever ones survive longer. Usually.",
		"Environment as weapon — a thinking warrior.",
		"Resourceful. The Collective admires creativity.",
		"Why fight when the dungeon fights for you?",
	],

	# ── STEALTH ──
	"Stealth:combat": [
		"A berserker in a stealth floor. The audience is... surprised.",
		"Stealth? What stealth? They chose violence.",
		"Fighting through patrols. Bold. Loud. Entertaining.",
		"The guards never expected a frontal assault. Neither did we.",
		"All that sneaking infrastructure, wasted on a brute.",
	],
	"Stealth:speed": [
		"A ghost. They passed through without a trace.",
		"The guards never saw them. Perfect speed.",
		"Sprint, slide, gone. The audience barely blinked.",
		"Too fast for the patrols. Too fast for the cameras.",
		"A phantom in the shadows. Poetry in motion.",
	],
	"Stealth:clever": [
		"Backstabs and distractions. A true operative.",
		"They turned the guards against themselves. Brilliant.",
		"Every distraction placed with surgical precision.",
		"A shadow that thinks. The Collective is impressed.",
		"Clever use of the environment. Silent and deadly.",
	],
	"Stealth:social": [
		"They walked right past the guards. In disguise. Audacious.",
		"Hidden in plain sight. The Collective approves.",
		"A silver tongue among the patrols. Unexpected.",
		"Blending in beats sneaking past. Sometimes.",
		"The disguise holds. For now.",
	],

	# ── ECONOMY ──
	"Economy:social": [
		"You conned the merchant. The Collective approves. The merchant does not.",
		"Trade, haggle, profit. A merchant warrior.",
		"The Merchant King has met their match.",
		"Silver tongue buys more than steel can take.",
		"An empire built on handshakes. For now.",
	],
	"Economy:combat": [
		"Rob the merchants? Bold. And very loud.",
		"Why pay when you can plunder?",
		"The guards fall. The prices don't matter to the dead.",
		"A hostile takeover in the most literal sense.",
		"The economy collapses. But you got what you needed.",
	],
	"Economy:clever": [
		"A gambler and a cheat. The audience loves it.",
		"They exploited every loophole in the market.",
		"Con artist supreme. The Collective takes notes.",
		"Price manipulation as an art form.",
		"The system was designed to be fair. You disagreed.",
	],
	"Economy:speed": [
		"Buy low, sell high, get out fast. Market speed.",
		"The fastest flipper in the dungeon.",
		"Gold changes hands so quickly the NPCs are dizzy.",
		"A flash trade. In and out before prices rose.",
		"Speed trader. The Collective is timing this.",
	],

	# ── POLITICAL ──
	"Political:social": [
		"A born politician. The factions fall in line.",
		"Alliances forged. Votes secured. Democracy in action.",
		"The champion rules by charisma, not force.",
		"Every handshake is a weapon in this one's arsenal.",
		"The election approaches. The polls look favorable.",
	],
	"Political:combat": [
		"Assassination. Direct and permanent.",
		"Why campaign when you can eliminate the competition?",
		"The guards fall. The mayor trembles.",
		"Politics through violence. Historically accurate.",
		"A coup d'état on the dungeon floor.",
	],
	"Political:clever": [
		"Puppet strings everywhere. Who really rules here?",
		"Bribery and blackmail — the invisible hand.",
		"The shadows move. The factions don't know who to trust.",
		"A manipulator behind every faction shift.",
		"The Collective recognizes a fellow puppeteer.",
	],

	# ── BOSS RUSH ──
	"Boss Rush:combat": [
		"Gladiator-born. Boss after boss falls.",
		"Pure combat mastery on display.",
		"Steel meets scale. Steel wins.",
		"The champion treats bosses like warmups.",
		"An arena legend in the making.",
	],
	"Boss Rush:clever": [
		"Using the arena against the bosses. Smart.",
		"Summons and traps versus titans. Clever.",
		"The tactician exploits every boss weakness.",
		"Why trade blows when you can trade strategies?",
		"A thinking fighter. Rare and effective.",
	],
	"Boss Rush:speed": [
		"Speedkilling bosses. The timer is the real opponent.",
		"Each boss falls faster than the last.",
		"A blur of violence. Incredible pace.",
		"The audience barely has time to cheer between kills.",
		"New record? The Collective starts the clock.",
	],

	# ── SURVIVAL ARENA ──
	"Survival Arena:combat": [
		"Wave after wave, they stand their ground.",
		"The slayer approach. No wave survives.",
		"Aggressive. Relentless. Every wave ends fast.",
		"The arena was designed to overwhelm. It failed.",
		"Steel and fury solve every wave.",
	],
	"Survival Arena:clever": [
		"Kiting the waves into traps. Survivor mentality.",
		"They outlast rather than overpower. Patience.",
		"The clever ones survive longest in the arena.",
		"Environment, positioning, timing. A survivor's toolkit.",
		"The waves break against tactical brilliance.",
	],
	"Survival Arena:speed": [
		"Clearing waves before they even form up.",
		"Wave rushing. The timer thanks you.",
		"Each wave melts faster than the last.",
		"Speed between waves. No rest needed.",
		"The fastest arena clear the Collective has witnessed.",
	],

	# ── ESCAPE ──
	"Escape:speed": [
		"Born to run. The wall can't keep up.",
		"A sprinter's dream. Not a scratch.",
		"Speed incarnate. The danger wall fades behind.",
		"They make escaping look effortless.",
		"The Collective clocks a record pace.",
	],
	"Escape:combat": [
		"Fighting through the escape. Unusual but entertaining.",
		"The wall advances. They stop to fight. BOLD.",
		"Bulldozing through obstacles instead of dodging.",
		"Dangerous approach on an escape floor.",
		"The audience loves a fighter who ignores the rules.",
	],
	"Escape:clever": [
		"Shortcuts found. The wall outmaneuvered.",
		"A pathfinder through chaos. Impressive.",
		"They know routes the builders didn't intend.",
		"Clever routing turns danger into a brisk walk.",
		"Every shortcut is a gift. This one found them all.",
	],

	# ── INVERSION ──
	"Inversion:combat": [
		"Defending from the front line. Hands-on management.",
		"The boss fights their own battles. Respect.",
		"Personal combat while the dungeon watches.",
		"A boss who leads from the front. Unusual.",
		"Traps? Minions? No. Just fists.",
	],
	"Inversion:clever": [
		"Traps and minions do the work. Perfect architecture.",
		"A dungeon mastermind. The crawlers never stood a chance.",
		"Every kill zone placed with surgical precision.",
		"The architect approach. Build it and they will die.",
		"The Collective recognizes dungeon design talent.",
	],

	# ── RACE ──
	"Race:speed": [
		"First place! A born racer.",
		"The ghosts eat dust. Pure speed.",
		"Every checkpoint hit with perfect momentum.",
		"The track belongs to the champion.",
		"A speed record that ghosts envy.",
	],
	"Race:clever": [
		"Shortcuts the ghosts don't know about.",
		"Boost pads chained together. Genius routing.",
		"The clever path is the fastest path.",
		"Route optimization at its finest.",
		"Finding the line the builders hid.",
	],
	"Race:combat": [
		"Smashing through obstacles instead of dodging.",
		"The enforcer approach. Obstacles fear this racer.",
		"Why dodge when you can destroy?",
		"A wrecking ball on a race track.",
		"The obstacles are the real losers here.",
	],
}

# Generic fallbacks when no archetype-specific reaction exists
const PATH_GENERIC := {
	"combat": [
		"The way of the warrior. Direct and effective.",
		"Blood and glory. The audience approves.",
		"Violence chosen where subtlety was available.",
		"A fighter's answer to every question.",
		"The path of most resistance, willingly taken.",
	],
	"speed": [
		"Speed over everything. An unusual priority.",
		"They chose velocity over violence.",
		"Fast feet, faster thinking.",
		"No time wasted. The Collective is timing.",
		"A blur through the dungeon.",
	],
	"social": [
		"Words instead of weapons. A rarity down here.",
		"The silver tongue finds a way.",
		"Charm as armor. Unusual in a dungeon.",
		"Social finesse in a world of steel.",
		"Talking their way through. The Collective is amused.",
	],
	"clever": [
		"Resourceful. Creative. The Collective takes notice.",
		"Using everything but brute force.",
		"The trickster approach. Entertaining.",
		"Unconventional methods yield unconventional results.",
		"Why fight fair when you can fight smart?",
	],
}

# ----- Core -----

var _last_path_announced: String = ""

func _ready() -> void:
	_rng.randomize()
	GameManager.enemy_died.connect(_on_enemy_died)
	GameManager.all_enemies_cleared.connect(_on_floor_cleared)
	GameManager.game_over.connect(_on_game_over)
	FloorManager.floor_changed.connect(_on_floor_changed)
	AudienceManager.boredom_started.connect(_on_boredom)
	AudienceManager.mood_changed.connect(_on_mood_changed)
	SmusherTimer.overtime_started.connect(_on_overtime)
	SolutionPathTracker.path_changed.connect(_on_path_changed)

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

	# Mage kill callout
	if enemy and is_instance_valid(enemy) and enemy.get("enemy_type") == "goblin_shaman":
		var mage_kill_lines := [
			"The sorcerer falls! No more circles!",
			"That shaman won't be casting again.",
			"Arcane threat neutralized!",
		]
		if _rng.randf() < 0.5:
			_say_line(mage_kill_lines, Color(0.7, 0.3, 1.0), 26)
			return

	# Elite kill callout
	if enemy and is_instance_valid(enemy) and EliteModifier.is_elite(enemy):
		var elite_lines := [
			"A champion falls! The crowd roars!",
			"That one had a name. Not anymore.",
			"The elite crumbles. Impressive.",
			"One less champion to worry about.",
			"They promoted that one. Didn't help.",
		]
		_say_line(elite_lines, Color(1.0, 0.6, 0.1), 28, true)
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
	_last_path_announced = ""
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

# ----- Solution Path Reactions -----

func _on_path_changed(new_path: String, _old_path: String) -> void:
	if new_path == _last_path_announced:
		return
	_last_path_announced = new_path
	# 60% chance to comment on path shift (avoid spam)
	if _rng.randf() > 0.6:
		return
	var pool := _get_path_lines(new_path)
	if pool.size() > 0:
		var color := SolutionPathTracker.get_path_color()
		_say_line(pool, color, 24)

func _get_path_lines(path: String) -> Array:
	## Get archetype-specific path lines, fall back to generic.
	var archetype_name := ""
	if FloorManager.current_archetype:
		archetype_name = FloorManager.current_archetype.archetype_name
	var key := "%s:%s" % [archetype_name, path]
	if PATH_REACTIONS.has(key):
		return PATH_REACTIONS[key]
	if PATH_GENERIC.has(path):
		return PATH_GENERIC[path]
	return []

# ----- Boss Entrance (called externally by boss_enemy.gd) -----

func announce_boss() -> void:
	_boss_active = true
	_say_line(BOSS_ENTRANCE, Color(0.8, 0.2, 0.6), 30, true)
	_cooldown = BOSS_COOLDOWN

# ----- Heal Commentary (called by hero when healing at low HP) -----

func on_hero_healed(hp_ratio_before: float) -> void:
	if hp_ratio_before <= 0.3:
		_say_line(HEAL_LOW_HP, Color(0.3, 1.0, 0.5), 24)

# ----- Mage Casting (called by mage_enemy.gd) -----

func announce_mage_cast() -> void:
	if _rng.randf() < 0.35:  # Don't spam — only 35% chance
		_say_line(MAGE_CASTING, Color(0.7, 0.2, 1.0), 26)

# ----- Summon (called by SummonSpell) -----

func on_summon_spawned() -> void:
	_say_line(SUMMON_SPAWNED, Color(0.4, 0.6, 1.0), 24)

# ----- Reset -----

## Public API — used by other scripts to trigger narrator lines.

func speak(text: String, color: Color = Color(0.85, 0.8, 0.7), size: int = 24) -> void:
	## Say a specific line directly (not from a pool).
	if _cooldown > 0:
		return
	narrator_says.emit(text, color, size)
	_cooldown = MIN_COOLDOWN

func queue_line(text: String, color: Color = Color.WHITE, size: int = 24) -> void:
	## Queue a specific line (alias for speak, overrides cooldown for important messages).
	narrator_says.emit(text, color, size)
	_cooldown = MIN_COOLDOWN

func show_commentary(text: String) -> void:
	## Show a commentary line (archetype messages, etc.)
	speak(text, Color(0.7, 0.65, 0.8), 22)

func reset() -> void:
	_cooldown = 0.0
	_kill_count_since_last = 0
	_kills_this_floor = 0
	_last_hp_ratio = 1.0
	_near_death_announced = false
	_first_kill_announced = false
	_boss_active = false
	_floor_start_time = 0.0
	_last_path_announced = ""
