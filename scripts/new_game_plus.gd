extends Node

## New Game+ Manager — unlocked after first game completion.
## NG+: enemies +50% HP, Smusher 25% faster, loot quality 2x, audience starts at 80 VP.
## Each subsequent NG+ cycle further increases difficulty.

signal ngplus_unlocked()

const SAVE_PATH := "user://ngplus.json"

# Persistent state
var has_completed_game: bool = false  # True once game beaten at least once
var ngplus_level: int = 0  # 0 = normal, 1 = NG+, 2 = NG++, etc.
var is_ngplus_run: bool = false  # True if current run is NG+

# Multipliers per NG+ level
const ENEMY_HP_MULT_PER_LEVEL: float = 0.5  # +50% per NG+ level
const TIMER_SPEED_MULT_PER_LEVEL: float = 0.25  # +25% faster per level
const LOOT_QUALITY_MULT_PER_LEVEL: float = 1.0  # 2x at level 1, 3x at level 2, etc.
const AUDIENCE_START_VP_PER_LEVEL: int = 80  # Start VP per NG+ level

func _ready() -> void:
	_load()
	GameManager.game_over.connect(_on_game_over)

func _on_game_over(won: bool) -> void:
	if won:
		if not has_completed_game:
			has_completed_game = true
			ngplus_unlocked.emit()
		if is_ngplus_run:
			ngplus_level += 1
		_save()

## Call when starting a NG+ run
func start_ngplus_run() -> void:
	if not has_completed_game:
		return
	if ngplus_level == 0:
		ngplus_level = 1
	is_ngplus_run = true

## Call when starting a normal new game
func start_normal_run() -> void:
	is_ngplus_run = false

## Enemy HP multiplier for current NG+ run
func get_enemy_hp_multiplier() -> float:
	if not is_ngplus_run:
		return 1.0
	return 1.0 + ngplus_level * ENEMY_HP_MULT_PER_LEVEL

## Smusher timer speed multiplier (higher = faster countdown)
func get_timer_speed_multiplier() -> float:
	if not is_ngplus_run:
		return 1.0
	return 1.0 + ngplus_level * TIMER_SPEED_MULT_PER_LEVEL

## Loot rarity roll bonus (shifts rarity table upward)
func get_loot_quality_multiplier() -> float:
	if not is_ngplus_run:
		return 1.0
	return 1.0 + ngplus_level * LOOT_QUALITY_MULT_PER_LEVEL

## Starting audience VP
func get_starting_vp() -> int:
	if not is_ngplus_run:
		return 0
	return ngplus_level * AUDIENCE_START_VP_PER_LEVEL

## Display label for menu
func get_ngplus_label() -> String:
	if ngplus_level <= 1:
		return "NEW GAME+"
	return "NEW GAME+" + str(ngplus_level)

func reset_run_state() -> void:
	is_ngplus_run = false

func _save() -> void:
	var data := {
		"has_completed_game": has_completed_game,
		"ngplus_level": ngplus_level,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		return
	var data: Dictionary = json.data
	has_completed_game = data.get("has_completed_game", false)
	ngplus_level = int(data.get("ngplus_level", 0))
