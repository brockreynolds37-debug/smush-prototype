extends Node

## BalanceConfig — centralized tuning knobs for all game systems.
## Every numeric constant that affects gameplay difficulty lives here.
## Tweak one file instead of hunting through dozens of scripts.

# ---------- HERO ----------

# Base melee damage before STR/equipment scaling
const HERO_BASE_MELEE_DAMAGE: int = 35
# STR bonus per point: +N damage per STR
const HERO_STR_DAMAGE_PER_POINT: int = 3
# Crit multiplier (1.8 = +80%)
const HERO_CRIT_MULTIPLIER: float = 1.8
# Mana regen per tick (1 tick = 1 second)
const HERO_MANA_REGEN_PER_TICK: int = 5
# Mana regen tick interval (seconds)
const HERO_MANA_REGEN_INTERVAL: float = 1.0

# INT scaling: spell power per point (+N% per INT)
const HERO_INT_SPELL_POWER_PER_POINT: float = 0.08
# Equipment spell power bonus per point (+N%)
const HERO_EQUIP_SPELL_POWER_PER_POINT: float = 0.01

# Movement (WC3-style: slower, weightier units with visible turning)
const HERO_BASE_MOVE_SPEED: float = 5.0
const HERO_ACCELERATION: float = 25.0
const HERO_DECELERATION: float = 35.0
const HERO_ROTATION_SPEED: float = 10.0
const HERO_TURN_RATE: float = 180.0  # Degrees per second

# ---------- DEFAULT SPELL VALUES (Elementalist / Set 0) ----------

const SPELL_STRIKE_RANGE: float = 3.5
const SPELL_FIREBALL_DAMAGE_BASE: int = 60  # Before spell power mult
const SPELL_HEAL_AMOUNT_BASE: int = 150
const SPELL_GROUND_SLAM_DAMAGE_BASE: int = 80
const SPELL_GROUND_SLAM_RADIUS: float = 6.0
const SPELL_GROUND_SLAM_SLOW_DURATION: float = 3.0
const SPELL_GROUND_SLAM_STUN_DURATION: float = 1.0

# ---------- ENEMY STATS ----------

# Melee enemies (goblin_warrior, skeleton, orc, etc.)
const ENEMY_MELEE_HP: int = 150
const ENEMY_MELEE_DAMAGE: int = 15
const ENEMY_MELEE_SPEED: float = 3.25
const ENEMY_MELEE_AGGRO_RANGE: float = 10.0
const ENEMY_MELEE_ATTACK_RANGE: float = 2.5
const ENEMY_MELEE_ATTACK_COOLDOWN: float = 1.5

# Ranged enemies (goblin_archer)
const ENEMY_RANGED_HP: int = 100
const ENEMY_RANGED_DAMAGE: int = 12
const ENEMY_RANGED_SPEED: float = 2.9
const ENEMY_RANGED_AGGRO_RANGE: float = 14.0
const ENEMY_RANGED_ATTACK_RANGE: float = 10.0
const ENEMY_RANGED_ATTACK_COOLDOWN: float = 2.0
const ENEMY_RANGED_KITE_DISTANCE: float = 6.0

# Mage enemies
const ENEMY_MAGE_HP: int = 120
const ENEMY_MAGE_DAMAGE: int = 25
const ENEMY_MAGE_SPEED: float = 2.3
const ENEMY_MAGE_AGGRO_RANGE: float = 12.0
const ENEMY_MAGE_ATTACK_RANGE: float = 9.0
const ENEMY_MAGE_ATTACK_COOLDOWN: float = 3.0
const ENEMY_MAGE_AOE_RADIUS: float = 3.0
const ENEMY_MAGE_TELEGRAPH_DURATION: float = 1.2

# ---------- BOSS STATS ----------

const BOSS_BASE_HP: int = 800
const BOSS_BASE_DAMAGE: int = 30
const BOSS_MOVE_SPEED: float = 2.6
const BOSS_AGGRO_RANGE: float = 18.0
const BOSS_ATTACK_RANGE: float = 3.0
const BOSS_ATTACK_COOLDOWN: float = 2.0
const BOSS_SLAM_COOLDOWN: float = 8.0
const BOSS_SLAM_RADIUS: float = 5.0
const BOSS_SLAM_DAMAGE: int = 50
const BOSS_ENRAGE_THRESHOLD: float = 0.25  # Enrage at 25% HP
const BOSS_ENRAGE_DAMAGE_MULT: float = 1.5
const BOSS_ENRAGE_SPEED_MULT: float = 1.3

# HP scaling per floor (boss HP multiplied by this per floor)
const BOSS_HP_SCALE_PER_FLOOR: float = 1.3

# ---------- ELITE ENEMIES ----------

const ELITE_SPAWN_CHANCE: float = 0.15  # 15% per mob
const ELITE_HP_MULT: float = 2.0
const ELITE_DAMAGE_MULT: float = 1.5
const ELITE_SPEED_MULT: float = 1.15
const ELITE_XP_MULT: float = 2.5
const ELITE_SCALE_MULT: float = 1.3

# ---------- XP & LEVELING ----------

const XP_MAX_LEVEL: int = 20
# Formula: level * BASE + (level-1)^2 * QUADRATIC
const XP_BASE_PER_LEVEL: int = 100
const XP_QUADRATIC_PER_LEVEL: int = 20
const XP_FLOOR_BONUS_PER_FLOOR: float = 0.25  # +25% XP per floor beyond 1
const LEVEL_UP_HP_BONUS: int = 15
const LEVEL_UP_MANA_BONUS: int = 10

# XP rewards by enemy type
const XP_REWARDS := {
	"rat": 15,
	"slime": 20,
	"spider": 25,
	"wolf": 30,
	"goblin": 25,
	"goblin_warrior": 35,
	"goblin_archer": 30,
	"goblin_shaman": 40,
	"skeleton": 30,
	"animated_armor": 45,
	"mimic": 50,
	"orc": 35,
	"boss_goblin_king": 200,
	"boss_spider_queen": 250,
	"boss_slime_lord": 300,
	"boss_forest_guardian": 250,
	"boss_crab_king": 350,
	"boss_kraken_spawn": 400,
}

# ---------- LOOT & ECONOMY ----------

const LOOT_DROP_CHANCE: float = 0.4  # 40% chance non-boss enemies drop loot
const BOSS_DROP_COUNT: int = 3
const GOLD_PER_ENEMY_MIN: int = 5
const GOLD_PER_ENEMY_MAX: int = 25

# Rarity stat multipliers
const RARITY_MULT_COMMON: float = 1.0
const RARITY_MULT_UNCOMMON: float = 1.5
const RARITY_MULT_RARE: float = 2.2
const RARITY_MULT_EPIC: float = 3.0
const RARITY_MULT_LEGENDARY: float = 4.5

# Stat roll variance (item stat rolls are +-15% random)
const ITEM_STAT_ROLL_MIN: float = 0.85
const ITEM_STAT_ROLL_MAX: float = 1.15

# ---------- SMUSHER TIMER ----------

const SMUSHER_DEFAULT_DURATION: float = 1800.0  # 30 minutes
const SMUSHER_OVERTIME_DURATION: float = 60.0
const SMUSHER_ROOM_COLLAPSE_INTERVAL: float = 3.0
const SMUSHER_WARNING_THRESHOLD: float = 300.0  # 5 minutes
const SMUSHER_CRITICAL_THRESHOLD: float = 60.0  # 1 minute

# ---------- AUDIENCE / VP ----------

const VP_PER_KILL: int = 5
const VP_PER_MULTI_KILL_BONUS: int = 10  # Bonus per extra enemy in multi-kill
const VP_PER_SPELL_CAST: int = 3
const VP_PER_AOE_HIT: int = 8  # Per enemy hit with AoE
const VP_PER_BOSS_KILL: int = 50
const VP_BOREDOM_DECAY_RATE: float = 1.0  # VP lost per second of inaction
const VP_BOREDOM_THRESHOLD: float = 10.0  # Seconds of no combat before boredom

const AUDIENCE_MOOD_THRESHOLDS := {
	"bored": 0,
	"watching": 50,
	"interested": 150,
	"excited": 350,
	"erupting": 600,
}

# ---------- SPONSOR SYSTEM ----------

const SPONSOR_MIN_MOOD_LEVEL: int = 2  # "Interested" or higher
const SPONSOR_OFFER_COUNT: int = 2

# ---------- TRAIT VALUES ----------

# Exoskeleton: flat damage reduction %
const TRAIT_EXOSKELETON_REDUCTION: float = 0.20
# Berserker Rage: HP threshold and bonus
const TRAIT_BERSERKER_HP_THRESHOLD: float = 0.30
const TRAIT_BERSERKER_DAMAGE_MULT: float = 1.50
# Arcane Surge: mana on kill + cooldown reduction
const TRAIT_ARCANE_SURGE_MANA_ON_KILL: int = 20
const TRAIT_ARCANE_SURGE_CD_REDUCTION: float = 0.15  # 15% faster cooldowns
# Eagle Eye: range bonus
const TRAIT_EAGLE_EYE_RANGE_MULT: float = 1.30
# Phase Walk: dodge chance per proc + charges per floor
const TRAIT_PHASE_WALK_DODGE_CHANCE: float = 0.25
const TRAIT_PHASE_WALK_CHARGES: int = 5
# Adaptable: stat points gained per floor
const TRAIT_ADAPTABLE_STATS_PER_FLOOR: int = 1

# ---------- STATUS EFFECTS ----------

const POISON_DAMAGE_PER_TICK: int = 5
const POISON_TICK_INTERVAL: float = 1.0
const SLOW_DEFAULT_AMOUNT: float = 0.5  # 50% movement speed reduction
const STUN_DEFAULT_DURATION: float = 1.0

# ---------- SPELL UNLOCK LEVELS ----------

const SPELL_UNLOCK_SLOT_3: int = 5   # Level 5 to unlock spell slot 3 (E)
const SPELL_UNLOCK_SLOT_4: int = 10  # Level 10 to unlock spell slot 4 (R)

# ---------- FLOOR SCALING ----------

# Enemy count base + per floor increment
const ENEMIES_BASE_COUNT: int = 4
const ENEMIES_PER_FLOOR_INCREMENT: int = 2
# Enemy HP scaling per floor (multiplicative)
const ENEMY_HP_SCALE_PER_FLOOR: float = 1.15
# Enemy damage scaling per floor (multiplicative)
const ENEMY_DAMAGE_SCALE_PER_FLOOR: float = 1.10

# ---------- MERCHANT PRICES ----------

const MERCHANT_HEALTH_POTION_COST: int = 30
const MERCHANT_MANA_POTION_COST: int = 25
const MERCHANT_WEAPON_COST_MULT: float = 1.5  # Base cost * rarity mult
const MERCHANT_ARMOR_COST_MULT: float = 1.2

# ---------- INVENTORY ----------

const MAX_INVENTORY_SIZE: int = 20

# ---------- GAME SETTINGS ----------

const MAX_FLOOR: int = 4
