extends FloorArchetype

## BossRushArchetype — back-to-back boss fights. No rooms, no loot between.
## 3 bosses per floor with 10-second breather between each.
## No merchant. Pure skill check. Audience goes wild.

class_name BossRushArchetype

const BOSSES_PER_FLOOR := 3
const BREATHER_DURATION := 10.0

var _boss_pool: Array = [
	preload("res://scenes/boss_goblin_king.tscn"),
	preload("res://scenes/boss_spider_queen.tscn"),
	preload("res://scenes/boss_slime_lord.tscn"),
	preload("res://scenes/boss_forest_guardian.tscn"),
	preload("res://scenes/boss_crab_king.tscn"),
	preload("res://scenes/boss_kraken_spawn.tscn"),
]

var _bosses_defeated: int = 0
var _current_boss: Node3D = null
var _breather_timer: float = 0.0
var _is_breather: bool = false
var _boss_queue: Array = []  # Scenes to instantiate in order
var _hud_overlay: Control = null
var _boss_count_label: Label = null
var _status_label: Label = null
var _breather_label: Label = null

func _init() -> void:
	archetype_name = "Boss Rush"
	flavor_text = "No rest. No loot. Only bosses."
	accent_color = Color(1.0, 0.2, 0.2)

func start() -> void:
	super.start()
	_bosses_defeated = 0
	_build_boss_queue()

	show_message("BOSS RUSH — Defeat %d bosses!" % BOSSES_PER_FLOOR, accent_color, 4.0)

	# Audience loves boss rush — big VP burst on start
	AudienceManager.grant_vp(30, "Boss Rush begins!")

	# Connect boss defeat tracking
	GameManager.enemy_died.connect(_on_enemy_died)

	# Spawn first boss after a brief grace period
	_is_breather = true
	_breather_timer = 3.0

func _build_boss_queue() -> void:
	# Pick BOSSES_PER_FLOOR random bosses from pool (allow repeats if pool is small)
	_boss_queue.clear()
	var pool = _boss_pool.duplicate()
	pool.shuffle()
	for i in range(BOSSES_PER_FLOOR):
		_boss_queue.append(pool[i % pool.size()])

	# Scale boss difficulty with floor number — later bosses in queue are tougher
	# (actual stat scaling happens at spawn time)

func update(delta: float) -> void:
	if not _is_active:
		return

	if _is_breather:
		_breather_timer -= delta

		if _breather_label:
			if _breather_timer > 0:
				_breather_label.text = "Next boss in %.0f..." % ceil(_breather_timer)
				_breather_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
			else:
				_breather_label.text = ""

		if _breather_timer <= 0:
			_is_breather = false
			_spawn_next_boss()

func _spawn_next_boss() -> void:
	if _boss_queue.is_empty() or not units_node or not builder:
		return

	var boss_scene: PackedScene = _boss_queue.pop_front()
	_current_boss = boss_scene.instantiate()

	# Scale boss HP and damage with floor number
	var floor_scale := 1.0 + (floor_number - 1) * 0.3
	# Each successive boss in the rush is slightly tougher
	var rush_scale := 1.0 + _bosses_defeated * 0.25
	var total_scale := floor_scale * rush_scale

	_current_boss.max_health = int(_current_boss.max_health * total_scale)
	_current_boss.current_health = _current_boss.max_health
	if "attack_damage" in _current_boss:
		_current_boss.attack_damage = int(_current_boss.attack_damage * total_scale)

	# Apply difficulty multiplier
	var diff_mult := GameManager.get_difficulty_multiplier()
	if diff_mult != 1.0:
		_current_boss.max_health = int(_current_boss.max_health * diff_mult)
		_current_boss.current_health = _current_boss.max_health
		if "attack_damage" in _current_boss:
			_current_boss.attack_damage = int(_current_boss.attack_damage * diff_mult)

	# Spawn at arena/boss room center
	var spawn_pos = builder.get_room_center("boss")
	if spawn_pos == Vector3.ZERO:
		spawn_pos = builder.get_room_center("arena")
	if spawn_pos == Vector3.ZERO:
		spawn_pos = builder.get_spawn_position() + Vector3(10, 0, 10)
	_current_boss.global_position = spawn_pos
	units_node.add_child(_current_boss)

	# Wire boss HUD bar
	_connect_boss_hud(_current_boss)

	var boss_num := _bosses_defeated + 1
	show_message("BOSS %d / %d" % [boss_num, BOSSES_PER_FLOOR], accent_color, 2.5)

	if _boss_count_label:
		_boss_count_label.text = "Boss %d / %d" % [boss_num, BOSSES_PER_FLOOR]

	if _status_label:
		_status_label.text = "FIGHT!"
		_status_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))

	# Audience excitement per boss spawn
	AudienceManager.grant_vp(20, "New boss enters!")

func _on_enemy_died(enemy: Node3D) -> void:
	if not _is_active:
		return
	# Check if the dead enemy is the current boss
	if enemy == _current_boss or not is_instance_valid(_current_boss):
		_current_boss = null
		_bosses_defeated += 1

		# Audience goes wild for boss kills
		AudienceManager.grant_vp(50, "Boss defeated in Boss Rush!")

		if _bosses_defeated >= BOSSES_PER_FLOOR:
			_on_all_bosses_defeated()
		else:
			_on_boss_defeated()

func _on_boss_defeated() -> void:
	var remaining := BOSSES_PER_FLOOR - _bosses_defeated
	show_message("BOSS DOWN! %d remaining..." % remaining, Color(1.0, 0.8, 0.2), 2.5)

	if _status_label:
		_status_label.text = "Breathe..."
		_status_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))

	# Small heal between bosses (10% max HP)
	if GameManager.hero and GameManager.hero.has_method("heal"):
		GameManager.hero.heal(int(GameManager.hero.max_health * 0.10))

	# Start breather before next boss
	_is_breather = true
	_breather_timer = BREATHER_DURATION

func _on_all_bosses_defeated() -> void:
	show_message("ALL BOSSES DEFEATED! EXIT UNLOCKED!", Color(0.2, 1.0, 0.4), 4.0)

	if _status_label:
		_status_label.text = "VICTORY!"
		_status_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))

	if _boss_count_label:
		_boss_count_label.text = "All %d bosses defeated!" % BOSSES_PER_FLOOR

	# Audience erupts
	AudienceManager.grant_vp(100, "Boss Rush cleared!")

	# Heal reward (30% max HP)
	if GameManager.hero and GameManager.hero.has_method("heal"):
		GameManager.hero.heal(int(GameManager.hero.max_health * 0.30))

	complete()

func _connect_boss_hud(boss: Node3D) -> void:
	var hud = boss.get_tree().current_scene.get_node_or_null("HUD")
	if hud and hud.has_method("show_boss_bar"):
		hud.show_boss_bar(boss)
	if boss.has_signal("boss_defeated"):
		boss.boss_defeated.connect(GameManager.on_boss_defeated)

func stop() -> void:
	super.stop()
	if GameManager.enemy_died.is_connected(_on_enemy_died):
		GameManager.enemy_died.disconnect(_on_enemy_died)
	_current_boss = null

func has_boss() -> bool:
	return false  # We handle boss spawning ourselves

func has_merchant() -> bool:
	return false  # No merchant — pure skill check

func has_smusher() -> bool:
	return true  # Smusher adds urgency

func exit_visible_at_start() -> bool:
	return false  # Exit appears only after all bosses defeated

func uses_default_enemy_spawning() -> bool:
	return false  # No regular enemies — only bosses

func create_hud_overlay() -> Control:
	_hud_overlay = Control.new()
	_hud_overlay.name = "BossRushHUD"
	_hud_overlay.set_anchors_preset(Control.PRESET_TOP_CENTER)

	_boss_count_label = Label.new()
	_boss_count_label.name = "BossCountLabel"
	_boss_count_label.text = "Boss Rush — 0 / %d" % BOSSES_PER_FLOOR
	_boss_count_label.add_theme_font_size_override("font_size", 22)
	_boss_count_label.add_theme_color_override("font_color", accent_color)
	_boss_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_count_label.position = Vector2(-120, 8)
	_hud_overlay.add_child(_boss_count_label)

	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.text = "Preparing..."
	_status_label.add_theme_font_size_override("font_size", 16)
	_status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.position = Vector2(-120, 36)
	_hud_overlay.add_child(_status_label)

	_breather_label = Label.new()
	_breather_label.name = "BreatherLabel"
	_breather_label.text = ""
	_breather_label.add_theme_font_size_override("font_size", 14)
	_breather_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
	_breather_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_breather_label.position = Vector2(-120, 58)
	_hud_overlay.add_child(_breather_label)

	return _hud_overlay

func destroy_hud_overlay() -> void:
	if _hud_overlay and is_instance_valid(_hud_overlay):
		_hud_overlay.queue_free()
		_hud_overlay = null
