extends CanvasLayer

## WC3-style HUD with portrait, bars, ability buttons, minimap placeholder.

@onready var health_bar: ProgressBar = %HealthBar
@onready var mana_bar: ProgressBar = %ManaBar
@onready var portrait: ColorRect = %Portrait
@onready var ability_q: Button = %AbilityQ
@onready var ability_w: Button = %AbilityW
@onready var ability_e: Button = %AbilityE
@onready var ability_r: Button = %AbilityR
@onready var cooldown_q: ColorRect = %CooldownQ
@onready var cooldown_w: ColorRect = %CooldownW
@onready var cooldown_e: ColorRect = %CooldownE
@onready var cooldown_r: ColorRect = %CooldownR
@onready var minimap_frame: ColorRect = %MinimapFrame
@onready var floor_label: Label = %FloorLabel
@onready var game_over_overlay: ColorRect = $GameOverOverlay
@onready var game_over_label: Label = $GameOverOverlay/GameOverLabel
@onready var restart_label: Label = $GameOverOverlay/RestartLabel

const FLOOR_NAMES := {
	1: "The Sift",
	2: "The Crucible",
	3: "The Deep",
}

var cooldown_labels: Array[ColorRect] = []

func _ready() -> void:
	cooldown_labels = [cooldown_q, cooldown_w, cooldown_e, cooldown_r]
	if game_over_overlay:
		game_over_overlay.visible = false
	_update_floor_label(FloorManager.current_floor)
	FloorManager.floor_changed.connect(_on_floor_changed)
	# Connect to hero when available
	await get_tree().process_frame
	_connect_hero()
	GameManager.game_over.connect(_on_game_over)

func _connect_hero() -> void:
	var hero = GameManager.hero
	if hero:
		hero.health_changed.connect(_on_health_changed)
		hero.mana_changed.connect(_on_mana_changed)
		hero.spell_cooldown_updated.connect(_on_cooldown_updated)

func _on_health_changed(current: int, maximum: int) -> void:
	health_bar.max_value = maximum
	health_bar.value = current

func _on_mana_changed(current: int, maximum: int) -> void:
	mana_bar.max_value = maximum
	mana_bar.value = current

func _on_cooldown_updated(spell_index: int, remaining: float, total: float) -> void:
	if spell_index < cooldown_labels.size():
		var cd_rect = cooldown_labels[spell_index]
		if remaining > 0:
			cd_rect.visible = true
			# Shrink the overlay from full to zero as cooldown completes
			var ratio = remaining / total
			cd_rect.custom_minimum_size.y = 60 * ratio
			cd_rect.size.y = 60 * ratio
		else:
			cd_rect.visible = false

func _on_floor_changed(floor_num: int) -> void:
	_update_floor_label(floor_num)

func _update_floor_label(floor_num: int) -> void:
	if floor_label:
		var name = FLOOR_NAMES.get(floor_num, "Floor %d" % floor_num)
		floor_label.text = "Floor %d — %s" % [floor_num, name]
		# Brief flash animation
		floor_label.modulate = Color(1, 1, 1, 0)
		var tween = create_tween()
		tween.tween_property(floor_label, "modulate", Color(1, 1, 1, 1), 0.5)

func _on_game_over(won: bool) -> void:
	if game_over_overlay:
		game_over_overlay.visible = true
		if won:
			game_over_label.text = "VICTORY!"
			game_over_overlay.color = Color(0.0, 0.1, 0.0, 0.7)
		else:
			game_over_label.text = "DEFEATED"
			game_over_overlay.color = Color(0.15, 0.0, 0.0, 0.7)
		# Fade in the overlay
		game_over_overlay.modulate = Color(1, 1, 1, 0)
		var tween = create_tween()
		tween.tween_property(game_over_overlay, "modulate", Color(1, 1, 1, 1), 1.0)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		if GameManager.game_state != GameManager.GameState.PLAYING:
			get_tree().reload_current_scene()
			GameManager.reset_game_state()
