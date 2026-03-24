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
@onready var gold_label: Label = %GoldLabel
@onready var loot_feed: VBoxContainer = %LootFeed
@onready var boss_bar_container: VBoxContainer = %BossBarContainer
@onready var boss_name_label: Label = %BossName
@onready var boss_health_bar: ProgressBar = %BossHealthBar
@onready var game_over_overlay: ColorRect = $GameOverOverlay
@onready var game_over_label: Label = $GameOverOverlay/GameOverLabel
@onready var restart_label: Label = $GameOverOverlay/RestartLabel

var _active_boss: Node3D = null

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
	LootManager.item_picked_up.connect(_on_item_picked_up)
	LootManager.gold_changed.connect(_on_gold_changed)

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
	hide_boss_bar()

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

func _on_gold_changed(amount: int) -> void:
	if gold_label:
		gold_label.text = "Gold: %d" % amount

func _on_item_picked_up(item: Dictionary) -> void:
	if loot_feed == null:
		return
	var label := Label.new()
	var item_name: String = item.get("name", "Item")
	var rarity: int = item.get("rarity", 0)
	var color: Color = LootManager.RARITY_COLORS.get(rarity, Color.WHITE)
	label.text = "+ %s" % item_name
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	loot_feed.add_child(label)
	# Fade out and remove after 3 seconds
	var tween := create_tween()
	tween.tween_interval(2.5)
	tween.tween_property(label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(label.queue_free)
	# Cap feed to 6 visible entries
	while loot_feed.get_child_count() > 6:
		var oldest := loot_feed.get_child(0)
		loot_feed.remove_child(oldest)
		oldest.queue_free()

func show_boss_bar(boss: Node3D) -> void:
	_active_boss = boss
	if boss_bar_container:
		boss_bar_container.visible = true
		boss_name_label.text = boss.boss_display_name
		boss_health_bar.max_value = boss.max_health
		boss_health_bar.value = boss.current_health
		boss.health_changed.connect(_on_boss_health_changed)
		boss.boss_defeated.connect(_on_boss_defeated)
		# Slide-in animation
		boss_bar_container.modulate = Color(1, 1, 1, 0)
		var tween = create_tween()
		tween.tween_property(boss_bar_container, "modulate", Color(1, 1, 1, 1), 0.5)

func hide_boss_bar() -> void:
	_active_boss = null
	if boss_bar_container:
		var tween = create_tween()
		tween.tween_property(boss_bar_container, "modulate", Color(1, 1, 1, 0), 0.3)
		tween.tween_callback(func(): boss_bar_container.visible = false)

func _on_boss_health_changed(current: int, maximum: int) -> void:
	if boss_health_bar:
		boss_health_bar.max_value = maximum
		boss_health_bar.value = current

func _on_boss_defeated(_boss_type: String) -> void:
	hide_boss_bar()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		if GameManager.game_state != GameManager.GameState.PLAYING:
			get_tree().reload_current_scene()
			GameManager.reset_game_state()
