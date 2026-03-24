extends Node3D

## Floating Damage Numbers — spawns 3D text that floats upward and fades out.
## Connects to GameManager.damage_number_requested signal.
## Crits are bigger, golden. Heals are green. Normal hits are white.

const FLOAT_SPEED := 2.5  # Units per second upward
const FLOAT_DURATION := 0.9  # Seconds before fully faded
const SPREAD_RANGE := 0.6  # Random horizontal offset to avoid stacking
const CRIT_SCALE := 1.6  # Scale multiplier for crits
const BASE_FONT_SIZE := 48
const CRIT_FONT_SIZE := 72
const MAX_ACTIVE := 24  # Performance cap

var _active_count: int = 0

func _ready() -> void:
	GameManager.damage_number_requested.connect(_on_damage_number_requested)

func _on_damage_number_requested(position: Vector3, amount: int, is_crit: bool) -> void:
	if _active_count >= MAX_ACTIVE:
		return

	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.004
	label.render_priority = 10

	# Text content
	if amount == 0:
		# Miss / block / zero-damage event
		label.text = "MISS"
		label.font_size = 32
		label.modulate = Color(0.6, 0.6, 0.6, 0.8)
	elif amount < 0:
		# Healing (negative = heal amount in our convention, but signals send positive)
		label.text = "+%d" % abs(amount)
		label.font_size = BASE_FONT_SIZE
		label.modulate = Color(0.3, 1.0, 0.4, 1.0)
	else:
		label.text = "%d" % amount
		if is_crit:
			label.font_size = CRIT_FONT_SIZE
			label.modulate = Color(1.0, 0.85, 0.15, 1.0)  # Gold
		else:
			label.font_size = BASE_FONT_SIZE
			label.modulate = Color(1.0, 1.0, 1.0, 1.0)

	label.outline_modulate = Color(0, 0, 0, 0.8)
	label.outline_size = 6

	# Random spread to avoid numbers stacking
	var offset := Vector3(
		randf_range(-SPREAD_RANGE, SPREAD_RANGE),
		randf_range(0.0, 0.3),
		randf_range(-SPREAD_RANGE, SPREAD_RANGE)
	)
	label.global_position = position + offset

	add_child(label)
	_active_count += 1

	# Animate: float up, scale pop, fade out
	var start_scale := Vector3.ONE
	if is_crit:
		start_scale = Vector3.ONE * CRIT_SCALE
		# Crits get a quick punch scale
		label.scale = start_scale * 1.4

	var tween := create_tween()
	tween.set_parallel(true)

	# Float upward
	tween.tween_property(label, "global_position:y",
		label.global_position.y + FLOAT_SPEED * FLOAT_DURATION,
		FLOAT_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# Fade out (start fading at 40% through)
	tween.tween_property(label, "modulate:a", 0.0, FLOAT_DURATION * 0.6).set_delay(FLOAT_DURATION * 0.4)

	# Crit scale punch: pop in then settle
	if is_crit:
		tween.tween_property(label, "scale", start_scale, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	# Slight horizontal drift for visual variety
	var drift_x := randf_range(-0.3, 0.3)
	tween.tween_property(label, "global_position:x",
		label.global_position.x + drift_x,
		FLOAT_DURATION)

	# Cleanup
	tween.chain().tween_callback(func():
		label.queue_free()
		_active_count -= 1
	)
