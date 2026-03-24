extends Node

## Manages spell hotkey bindings with persistence and rebinding support.
## Autoload singleton — access via KeybindingManager.

signal bindings_changed

const SETTINGS_PATH := "user://settings.cfg"
const SPELL_ACTIONS: Array[String] = ["spell_0", "spell_1", "spell_2", "spell_3"]
const DEFAULT_KEYS: Array[Key] = [KEY_Q, KEY_E, KEY_R, KEY_T]

func _ready() -> void:
	_load_bindings()

# ── PUBLIC API ──

func get_key_label(spell_index: int) -> String:
	if spell_index < 0 or spell_index >= SPELL_ACTIONS.size():
		return "?"
	var action: String = SPELL_ACTIONS[spell_index]
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return OS.get_keycode_string(event.keycode)
	return "?"

func rebind_spell(spell_index: int, new_keycode: Key) -> void:
	if spell_index < 0 or spell_index >= SPELL_ACTIONS.size():
		return
	# Check for conflicts — swap if another spell uses this key
	for i in range(SPELL_ACTIONS.size()):
		if i == spell_index:
			continue
		var old_keycode: Key = _get_current_keycode(spell_index)
		for event in InputMap.action_get_events(SPELL_ACTIONS[i]):
			if event is InputEventKey and event.keycode == new_keycode:
				# Swap: give the conflicting slot our old key
				_apply_key(i, old_keycode)
				break
	_apply_key(spell_index, new_keycode)
	_save_bindings()
	bindings_changed.emit()

func reset_defaults() -> void:
	for i in range(SPELL_ACTIONS.size()):
		_apply_key(i, DEFAULT_KEYS[i])
	_save_bindings()
	bindings_changed.emit()

# ── INTERNAL ──

func _get_current_keycode(spell_index: int) -> Key:
	for event in InputMap.action_get_events(SPELL_ACTIONS[spell_index]):
		if event is InputEventKey:
			return event.keycode
	return DEFAULT_KEYS[spell_index]

func _apply_key(spell_index: int, keycode: Key) -> void:
	var action: String = SPELL_ACTIONS[spell_index]
	# Remove only keyboard events (preserve gamepad)
	var to_remove: Array[InputEvent] = []
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			to_remove.append(event)
	for event in to_remove:
		InputMap.action_erase_event(action, event)
	# Add new key
	var key_event := InputEventKey.new()
	key_event.keycode = keycode
	InputMap.action_add_event(action, key_event)

func _save_bindings() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)  # preserve other sections
	for i in range(SPELL_ACTIONS.size()):
		config.set_value("keybindings", SPELL_ACTIONS[i], _get_current_keycode(i))
	config.save(SETTINGS_PATH)

func _load_bindings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	for i in range(SPELL_ACTIONS.size()):
		if config.has_section_key("keybindings", SPELL_ACTIONS[i]):
			var keycode: Key = config.get_value("keybindings", SPELL_ACTIONS[i])
			_apply_key(i, keycode)
