extends Node

## Tutorial Manager — guides the player through Floor 0 with narrator prompts.
## Tracks completion state so the tutorial only triggers on first "New Game".
## Persisted to user://settings.cfg.

signal tutorial_step_changed(step_index: int, text: String)
signal tutorial_completed

const SAVE_PATH := "user://settings.cfg"

var tutorial_completed_flag: bool = false
var is_tutorial_active: bool = false
var current_step: int = -1

# Step definitions: each step has a trigger condition and narrator text.
var steps: Array[Dictionary] = [
	{"id": "welcome", "text": "Welcome, gladiator. The Collective watches your every move.", "delay": 1.5},
	{"id": "move", "text": "Click on the ground to move. Explore this room.", "delay": 3.0},
	{"id": "attack", "text": "An enemy stands before you. Click on it to attack!", "delay": 0.0},
	{"id": "spells", "text": "Press Q, W, E, or R to cast your spells. Try one now.", "delay": 0.0},
	{"id": "loot", "text": "A treasure chest! Click on it to claim your reward.", "delay": 0.0},
	{"id": "timer", "text": "The Smusher Timer ticks above. When it hits zero... the floor collapses.", "delay": 1.0},
	{"id": "exit", "text": "Step into the glowing portal to descend deeper. Good luck.", "delay": 0.0},
]

func _ready() -> void:
	_load_settings()

func start_tutorial() -> void:
	is_tutorial_active = true
	current_step = -1
	_advance_step()

func _advance_step() -> void:
	current_step += 1
	if current_step >= steps.size():
		_complete_tutorial()
		return
	var step: Dictionary = steps[current_step]
	var delay: float = step.get("delay", 0.0)
	if delay > 0:
		await get_tree().create_timer(delay).timeout
	tutorial_step_changed.emit(current_step, step["text"])
	# Tell narrator to say this line
	Narrator.narrator_says.emit(step["text"], Color(0.9, 0.85, 0.6), 24)

func notify_event(event_id: String) -> void:
	if not is_tutorial_active:
		return
	if current_step < 0 or current_step >= steps.size():
		return
	var expected_id: String = steps[current_step]["id"]
	# Check if this event advances the current step
	match expected_id:
		"move":
			if event_id == "hero_moved":
				_advance_step()
		"attack":
			if event_id == "enemy_hit":
				_advance_step()
		"spells":
			if event_id == "spell_cast":
				_advance_step()
		"loot":
			if event_id == "chest_opened":
				_advance_step()
		"timer":
			# Auto-advance after showing the timer message
			await get_tree().create_timer(4.0).timeout
			if current_step < steps.size() and steps[current_step]["id"] == "timer":
				_advance_step()
		"exit":
			if event_id == "exit_entered":
				_advance_step()

func _complete_tutorial() -> void:
	is_tutorial_active = false
	tutorial_completed_flag = true
	_save_settings()
	tutorial_completed.emit()

func should_show_tutorial() -> bool:
	return not tutorial_completed_flag

func skip_tutorial() -> void:
	is_tutorial_active = false
	current_step = steps.size()
	tutorial_completed_flag = true
	_save_settings()
	tutorial_completed.emit()

func _load_settings() -> void:
	var config = ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		tutorial_completed_flag = config.get_value("tutorial", "completed", false)

func _save_settings() -> void:
	var config = ConfigFile.new()
	config.load(SAVE_PATH)  # Load existing settings first
	config.set_value("tutorial", "completed", true)
	config.save(SAVE_PATH)
