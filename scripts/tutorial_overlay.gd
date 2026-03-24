extends CanvasLayer

## TutorialOverlay — non-intrusive tooltip bubbles for first-time players.
## Shows contextual hints on first encounter, persists dismissed state to settings.
## Each hint has a screen anchor position and auto-dismiss after a few seconds.

const SAVE_PATH := "user://settings.cfg"
const HINT_DURATION := 6.0  # seconds before auto-dismiss

# Hint definitions: id, text, anchor (0=bottom-left, 1=bottom-center, 2=bottom-right, 3=top-right)
const HINTS: Array = [
	{"id": "move",      "text": "Click the ground to move",              "anchor": 1},
	{"id": "attack",    "text": "Right-click an enemy to attack",        "anchor": 1},
	{"id": "spells",    "text": "Press 1 / 2 / 3 / 4 to cast spells",  "anchor": 0},
	{"id": "inventory", "text": "Press I to open your inventory",        "anchor": 0},
	{"id": "timer",     "text": "⚠ The Smusher — rooms collapse when it hits zero!", "anchor": 2},
	{"id": "exit",      "text": "Step into the glowing portal to go deeper", "anchor": 1},
]

var _shown: Dictionary = {}   # id -> bool (already shown this session or ever)
var _queue: Array = []        # hints waiting to display
var _current_bubble: Control = null
var _auto_timer: SceneTreeTimer = null

func _ready() -> void:
	layer = 200  # Above everything else
	_load_shown()
	# Listen to TutorialManager events
	if TutorialManager:
		TutorialManager.tutorial_step_changed.connect(_on_tutorial_step)
	# Also listen for direct hint requests from game systems
	# (other scripts call TutorialOverlay.show_hint("id"))

func show_hint(hint_id: String) -> void:
	# Don't show if already seen or overlay disabled in accessibility
	if _shown.get(hint_id, false):
		return
	if AccessibilitySettings and not AccessibilitySettings.hints_enabled:
		return
	# Find the hint definition
	var hint_def: Dictionary = {}
	for h in HINTS:
		if h["id"] == hint_id:
			hint_def = h
			break
	if hint_def.is_empty():
		return
	# Queue it — show immediately if nothing active
	_queue.append(hint_def)
	if _current_bubble == null:
		_show_next()

func _on_tutorial_step(step_index: int, text: String) -> void:
	# Map tutorial steps to hint IDs
	var step_map: Array = ["move", "attack", "spells", "timer", "exit"]
	if step_index < step_map.size():
		show_hint(step_map[step_index])

func _show_next() -> void:
	if _queue.is_empty():
		return
	var hint_def: Dictionary = _queue.pop_front()
	_build_bubble(hint_def)

func _build_bubble(hint_def: Dictionary) -> void:
	var bubble := PanelContainer.new()
	bubble.name = "HintBubble"
	
	# Style
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.06, 0.12, 0.92)
	style.border_color = Color(0.6, 0.5, 0.9, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	bubble.add_theme_stylebox_override("panel", style)
	
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	bubble.add_child(hbox)
	
	# Text
	var label := Label.new()
	label.text = hint_def["text"]
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.95, 0.92, 1.0))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(260, 0)
	hbox.add_child(label)
	
	# Dismiss button
	var dismiss := Button.new()
	dismiss.text = "✕"
	dismiss.flat = true
	dismiss.add_theme_font_size_override("font_size", 12)
	dismiss.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	dismiss.pressed.connect(_dismiss_current.bind(hint_def["id"]))
	dismiss.custom_minimum_size = Vector2(24, 24)
	hbox.add_child(dismiss)
	
	add_child(bubble)
	_current_bubble = bubble
	
	# Position based on anchor
	await get_tree().process_frame
	_position_bubble(bubble, hint_def["anchor"])
	
	# Fade in
	bubble.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(bubble, "modulate:a", 1.0, 0.3)
	
	# Auto-dismiss
	_auto_timer = get_tree().create_timer(HINT_DURATION)
	_auto_timer.timeout.connect(_dismiss_current.bind(hint_def["id"]))

func _position_bubble(bubble: Control, anchor: int) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var bubble_size := bubble.get_combined_minimum_size()
	const MARGIN := 20.0
	const HUD_BOTTOM_HEIGHT := 110.0  # clear the bottom HUD bar
	
	match anchor:
		0:  # bottom-left (above ability bar)
			bubble.position = Vector2(MARGIN, viewport_size.y - HUD_BOTTOM_HEIGHT - bubble_size.y - MARGIN)
		1:  # bottom-center
			bubble.position = Vector2(
				(viewport_size.x - bubble_size.x) * 0.5,
				viewport_size.y - HUD_BOTTOM_HEIGHT - bubble_size.y - MARGIN
			)
		2:  # top-right (near timer)
			bubble.position = Vector2(viewport_size.x - bubble_size.x - MARGIN, MARGIN + 80)
		3:  # top-center
			bubble.position = Vector2((viewport_size.x - bubble_size.x) * 0.5, MARGIN + 60)
		_:
			bubble.position = Vector2(MARGIN, MARGIN)

func _dismiss_current(hint_id: String) -> void:
	if _current_bubble == null:
		return
	_shown[hint_id] = true
	_save_shown()
	# Fade out and free
	var bubble := _current_bubble
	_current_bubble = null
	if _auto_timer and not _auto_timer.is_connected("timeout", _dismiss_current):
		pass  # already fired or disconnected
	var tween := create_tween()
	tween.tween_property(bubble, "modulate:a", 0.0, 0.25)
	tween.tween_callback(bubble.queue_free)
	# Show next in queue after short delay
	await get_tree().create_timer(0.5).timeout
	_show_next()

func _load_shown() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		var seen: Array = config.get_value("tutorial_hints", "shown", [])
		for id in seen:
			_shown[id] = true

func _save_shown() -> void:
	var config := ConfigFile.new()
	config.load(SAVE_PATH)
	var seen: Array = _shown.keys()
	config.set_value("tutorial_hints", "shown", seen)
	config.save(SAVE_PATH)

## Called by game systems to trigger contextual hints
func on_hero_moved() -> void:
	show_hint("move")

func on_enemy_visible() -> void:
	show_hint("attack")

func on_spell_bar_visible() -> void:
	show_hint("spells")

func on_inventory_opened() -> void:
	show_hint("inventory")

func on_timer_started() -> void:
	show_hint("timer")

func on_exit_visible() -> void:
	show_hint("exit")

## Reset all hints (for testing / new game)
func reset_hints() -> void:
	_shown.clear()
	var config := ConfigFile.new()
	config.load(SAVE_PATH)
	config.set_value("tutorial_hints", "shown", [])
	config.save(SAVE_PATH)
