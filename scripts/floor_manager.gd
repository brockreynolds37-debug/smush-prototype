extends Node

## Floor Manager singleton — tracks dungeon progress and handles floor transitions.
## Manages fade-to-black transitions between floors.

signal floor_changing(from_floor: int, to_floor: int)
signal floor_changed(floor_number: int)
signal transition_fade_midpoint  # Emitted when screen is fully black (time to swap level)
signal show_merchant(floor_number: int)  # Emitted to show merchant UI between floors

var current_floor: int = 1
var max_floor_reached: int = 1
var is_transitioning: bool = false
var _waiting_for_merchant: bool = false

# Transition overlay (injected by scene script or HUD)
var _overlay: ColorRect = null

func set_overlay(overlay: ColorRect) -> void:
	_overlay = overlay
	_overlay.color = Color(0, 0, 0, 1)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

func go_to_next_floor() -> void:
	if is_transitioning:
		return
	var next_floor = current_floor + 1
	_transition_to_floor(next_floor)

func _transition_to_floor(floor_number: int) -> void:
	is_transitioning = true
	floor_changing.emit(current_floor, floor_number)

	# Freeze hero movement during transition
	if GameManager.hero and not GameManager.hero.is_dead:
		GameManager.hero.is_moving = false
		GameManager.hero.velocity = Vector3.ZERO
		GameManager.hero.current_speed = 0.0

	# Fade to black
	if _overlay:
		_overlay.visible = true
		_overlay.modulate = Color(1, 1, 1, 0)
		var fade_out = create_tween()
		fade_out.tween_property(_overlay, "modulate", Color(1, 1, 1, 1), 0.6)
		await fade_out.finished

	# Show merchant shop between floors
	_waiting_for_merchant = true
	show_merchant.emit(floor_number)
	# Wait until merchant UI is dismissed
	while _waiting_for_merchant:
		await get_tree().process_frame

	# Midpoint — screen is black, swap level content
	current_floor = floor_number
	max_floor_reached = maxi(max_floor_reached, floor_number)
	transition_fade_midpoint.emit()

	# Small pause while black
	await get_tree().create_timer(0.3).timeout

	floor_changed.emit(current_floor)

	# Fade back in
	if _overlay:
		var fade_in = create_tween()
		fade_in.tween_property(_overlay, "modulate", Color(1, 1, 1, 0), 0.6)
		await fade_in.finished
		_overlay.visible = false

	is_transitioning = false

func on_merchant_closed() -> void:
	_waiting_for_merchant = false

func reset() -> void:
	current_floor = 1
	max_floor_reached = 1
	is_transitioning = false
	_waiting_for_merchant = false
