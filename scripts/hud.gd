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
@onready var smusher_label: Label = %SmusherTimerLabel
@onready var smusher_edge: ColorRect = %SmusherScreenEdge
@onready var game_over_overlay: ColorRect = $GameOverOverlay
@onready var game_over_label: Label = $GameOverOverlay/GameOverLabel
@onready var level_label: Label = %LevelLabel
@onready var xp_bar_bg: ColorRect = %XpBarBg
@onready var xp_bar_fill: ColorRect = %XpBarFill
@onready var vp_label: Label = %VpLabel
@onready var mood_label: Label = %MoodLabel
@onready var audience_chat: VBoxContainer = %AudienceChat
@onready var lock_e: ColorRect = %LockE
@onready var lock_r: ColorRect = %LockR

var _active_boss: Node3D = null
var _edge_pulse_tween: Tween = null
var _timer_flash_tween: Tween = null

# Status effect icon display
var _status_container: HBoxContainer = null
var _status_icons: Dictionary = {}  # EffectType -> Panel

# Summon counter label (built in code, no scene node needed)
var _summon_label: Label = null

const FLOOR_NAMES := {
	0: "Training Grounds",
	1: "The Sift",
	2: "The Crucible",
	3: "The Crush",
	4: "The Deep",
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
	# Wire game over buttons
	var retry_btn = game_over_overlay.get_node_or_null("RetryButton") if game_over_overlay else null
	var quit_btn = game_over_overlay.get_node_or_null("QuitButton") if game_over_overlay else null
	if retry_btn:
		retry_btn.pressed.connect(_on_retry_pressed)
	if quit_btn:
		quit_btn.pressed.connect(_on_quit_menu_pressed)
	LootManager.item_picked_up.connect(_on_item_picked_up)
	LootManager.gold_changed.connect(_on_gold_changed)
	# Accessibility: apply text scale to key labels
	_apply_text_scale()
	AccessibilitySettings.settings_changed.connect(_apply_text_scale)
	# Smusher Timer
	SmusherTimer.time_updated.connect(_on_smusher_time_updated)
	SmusherTimer.warning_phase_entered.connect(_on_smusher_warning)
	SmusherTimer.critical_phase_entered.connect(_on_smusher_critical)
	SmusherTimer.overtime_started.connect(_on_smusher_overtime)
	SmusherTimer.room_collapsed.connect(_on_room_collapsed)
	# XP system
	XpManager.xp_gained.connect(_on_xp_gained)
	XpManager.level_up.connect(_on_level_up)
	_update_xp_display()
	# Audience system
	AudienceManager.vp_gained.connect(_on_vp_gained)
	AudienceManager.mood_changed.connect(_on_mood_changed)
	AudienceManager.audience_comment.connect(_on_audience_comment)
	_update_vp_display()
	# Status effects — create icon container below health bar
	_setup_status_icons()
	StatusEffectManager.effect_applied.connect(_on_status_effect_applied)
	StatusEffectManager.effect_removed.connect(_on_status_effect_removed)
	# Narrator
	Narrator.narrator_says.connect(_on_narrator_says)
	# Summon counter
	_setup_summon_label()

func _connect_hero() -> void:
	var hero = GameManager.hero
	if hero:
		hero.health_changed.connect(_on_health_changed)
		hero.mana_changed.connect(_on_mana_changed)
		hero.spell_cooldown_updated.connect(_on_cooldown_updated)
		hero.spell_unlocked.connect(_on_spell_unlocked)
		_refresh_spell_locks()
		_refresh_ability_labels()

func _refresh_ability_labels() -> void:
	var spell_set = CharacterData.get_selected_spell_set()
	var names: Array = spell_set.get("names", ["Strike", "Fireball", "Heal", "Ground Slam"])
	var keys := ["Q", "W", "E", "R"]
	var buttons := [ability_q, ability_w, ability_e, ability_r]
	for i in range(4):
		if i < buttons.size() and buttons[i]:
			var n := names[i] if i < names.size() else "?"
			buttons[i].text = "%s\n%s" % [keys[i], n]

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

# ---------- SPELL LOCKS ----------

func _refresh_spell_locks() -> void:
	var hero = GameManager.hero
	if hero == null:
		return
	if lock_e:
		lock_e.visible = not hero.is_spell_unlocked(2)
	if lock_r:
		lock_r.visible = not hero.is_spell_unlocked(3)

func _on_spell_unlocked(spell_index: int) -> void:
	var lock_node: ColorRect = null
	match spell_index:
		2:
			lock_node = lock_e
		3:
			lock_node = lock_r
	# Get the actual spell name from the selected set
	var spell_set = CharacterData.get_selected_spell_set()
	var names: Array = spell_set.get("names", ["Strike", "Fireball", "Heal", "Ground Slam"])
	var spell_name: String = names[spell_index] if spell_index < names.size() else "Spell %d" % (spell_index + 1)

	if lock_node and lock_node.visible:
		# Animate lock removal: flash gold then hide
		var tween = create_tween()
		tween.tween_property(lock_node, "color", Color(1.0, 0.85, 0.2, 0.9), 0.15)
		tween.tween_property(lock_node, "color", Color(1.0, 0.85, 0.2, 0.0), 0.4)
		tween.tween_callback(func(): lock_node.visible = false)
		# Center message
		_show_center_message_colored("%s UNLOCKED!" % spell_name.to_upper(), Color(1.0, 0.85, 0.2))
		AudioManager.play_sfx("level_up")

func _on_floor_changed(floor_num: int) -> void:
	_update_floor_label(floor_num)
	hide_boss_bar()
	_reset_smusher_visuals()
	_update_vp_display()
	if mood_label:
		mood_label.text = "Audience: WATCHING"
		mood_label.add_theme_color_override("font_color", AudienceManager.MOOD_COLORS[AudienceManager.Mood.WATCHING])

func _reset_smusher_visuals() -> void:
	# Reset timer label to white/normal state for new floor
	if smusher_label:
		smusher_label.add_theme_color_override("font_color", Color.WHITE)
		smusher_label.modulate = Color(1, 1, 1, 1)
	if smusher_edge:
		smusher_edge.visible = false
		smusher_edge.color = Color(0.8, 0.0, 0.0, 0.0)
	if _edge_pulse_tween and _edge_pulse_tween.is_valid():
		_edge_pulse_tween.kill()
	if _timer_flash_tween and _timer_flash_tween.is_valid():
		_timer_flash_tween.kill()

func _update_floor_label(floor_num: int) -> void:
	if floor_label:
		var name = FLOOR_NAMES.get(floor_num, "Floor %d" % floor_num)
		floor_label.text = "Floor %d — %s" % [floor_num, name]
		# Brief flash animation
		floor_label.modulate = Color(1, 1, 1, 0)
		var tween = create_tween()
		tween.tween_property(floor_label, "modulate", Color(1, 1, 1, 1), 0.5)

func _on_game_over(won: bool) -> void:
	if game_over_overlay == null:
		return
	game_over_overlay.visible = true
	if won:
		game_over_label.text = "VICTORY!"
		game_over_overlay.color = Color(0.0, 0.08, 0.0, 0.85)
	else:
		game_over_label.text = "DEFEATED"
		game_over_overlay.color = Color(0.12, 0.0, 0.0, 0.85)

	# Build stats text from RunStats
	var char_name = CharacterData.get_selected().get("name", "Hero")
	var s = RunStats.get_summary()
	var stats_text = ""
	stats_text += "%s  —  Level %d\n" % [char_name, XpManager.current_level]
	stats_text += "Floor Reached: %d\n" % FloorManager.max_floor_reached
	stats_text += "Time: %s\n" % s["run_time"]
	stats_text += "\n"
	stats_text += "Enemies Slain: %d\n" % s["total_kills"]
	if s["boss_kills"] > 0:
		stats_text += "Bosses Defeated: %d\n" % s["boss_kills"]
	stats_text += "Damage Dealt: %d\n" % s["damage_dealt"]
	stats_text += "Damage Taken: %d\n" % s["damage_taken"]
	if s["largest_hit"] > 0:
		stats_text += "Biggest Hit: %d\n" % s["largest_hit"]
	stats_text += "\n"
	stats_text += "Spells Cast: %d\n" % s["total_spells"]
	stats_text += "Gold Earned: %d\n" % s["gold_earned"]
	stats_text += "Items Collected: %d\n" % s["items_collected"]
	stats_text += "\n"
	stats_text += "VP: %d  —  %s" % [AudienceManager.total_vp, AudienceManager.get_mood_name()]

	# Death recap highlights
	stats_text += "\n\n— HIGHLIGHTS —\n"
	var highlights := _build_highlights(s, won)
	for h in highlights:
		stats_text += h + "\n"

	# Narrator quip
	var quip := _get_death_quip(won)
	if quip != "":
		stats_text += "\n\"%s\"" % quip

	var stats_label = game_over_overlay.get_node_or_null("StatsLabel")
	if stats_label:
		stats_label.text = stats_text

	# Fade in the overlay
	game_over_overlay.modulate = Color(1, 1, 1, 0)
	var tween = create_tween()
	tween.tween_property(game_over_overlay, "modulate", Color(1, 1, 1, 1), 1.0)

func _build_highlights(s: Dictionary, won: bool) -> Array[String]:
	var highlights: Array[String] = []
	if s["largest_hit"] > 0:
		highlights.append("Biggest Hit: %d damage in one strike" % s["largest_hit"])
	var most_killed := RunStats.get_most_killed_enemy()
	if most_killed != "":
		var count: int = s["kills_by_type"].get(most_killed, 0)
		highlights.append("Nemesis: %s (%d slain)" % [most_killed.capitalize(), count])
	var floor_times: Dictionary = s.get("floor_times", {})
	if not floor_times.is_empty():
		var fastest_floor: int = 0
		var fastest_time: float = 999.0
		for fl in floor_times:
			if floor_times[fl] < fastest_time:
				fastest_time = floor_times[fl]
				fastest_floor = fl
		if fastest_floor > 0:
			highlights.append("Speed Demon: Floor %d in %d:%02d" % [fastest_floor, int(fastest_time) / 60, int(fastest_time) % 60])
	if s["gold_earned"] > 100:
		highlights.append("Treasure Hunter: %d gold earned" % s["gold_earned"])
	var spells_used: int = 0
	for sc in s["spells_cast"]:
		if sc > 0:
			spells_used += 1
	if spells_used >= 4:
		highlights.append("Arcane Mastery: All 4 spells used")
	elif spells_used == 0 and s["total_kills"] > 5:
		highlights.append("Pugilist: Never cast a single spell")
	if s["boss_kills"] >= 3:
		highlights.append("Boss Slayer: All bosses defeated")
	if AudienceManager.total_vp > 500:
		highlights.append("Fan Favorite: %d VP earned" % AudienceManager.total_vp)
	if highlights.is_empty():
		highlights.append("The arena remembers you." if not won else "A legend is born.")
	return highlights

const DEATH_QUIPS := [
	"Another gladiator falls. The crowd barely noticed.",
	"The dungeon claims yet another soul.",
	"So close... yet so very far.",
	"The Collective will find someone better.",
	"At least you provided some entertainment.",
	"The Smusher always wins eventually.",
	"Your corpse will make fine decoration.",
]
const VICTORY_QUIPS := [
	"Against all odds — a champion rises!",
	"The Collective roars! A legend forged in blood!",
	"The dungeon bows to its conqueror.",
	"You've earned a seat among the immortals.",
	"The crowd will speak your name for generations.",
]

func _get_death_quip(won: bool) -> String:
	var pool: Array = VICTORY_QUIPS if won else DEATH_QUIPS
	return pool[randi() % pool.size()]

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

# ---------- SMUSHER TIMER ----------

func _on_smusher_time_updated(seconds_remaining: float) -> void:
	if smusher_label == null:
		return
	smusher_label.text = SmusherTimer.get_time_string()

func _on_smusher_warning() -> void:
	# < 5 minutes: orange text, screen edges start pulsing red
	if smusher_label:
		smusher_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.0))
	_start_edge_pulse(0.12, 2.0)

func _on_smusher_critical() -> void:
	# < 1 minute: red flashing text, stronger edge pulse, heartbeat feel
	if smusher_label:
		smusher_label.add_theme_color_override("font_color", Color(1.0, 0.15, 0.15))
	_start_timer_flash()
	_start_edge_pulse(0.25, 0.8)

func _on_smusher_overtime() -> void:
	# Timer hit 0 — rooms collapsing
	if smusher_label:
		smusher_label.text = "OVERTIME"
		smusher_label.add_theme_color_override("font_color", Color(1.0, 0.0, 0.0))
	_start_edge_pulse(0.35, 0.5)

func _on_room_collapsed(_room_index: int, room_name: String) -> void:
	# Flash message when a room collapses
	_show_center_message("💀 %s COLLAPSED" % room_name.to_upper())

func _start_edge_pulse(max_alpha: float, period: float) -> void:
	if smusher_edge == null:
		return
	smusher_edge.visible = true
	smusher_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _edge_pulse_tween and _edge_pulse_tween.is_valid():
		_edge_pulse_tween.kill()
	_edge_pulse_tween = create_tween().set_loops()
	_edge_pulse_tween.tween_property(smusher_edge, "color:a", max_alpha, period * 0.5)
	_edge_pulse_tween.tween_property(smusher_edge, "color:a", 0.0, period * 0.5)

func _start_timer_flash() -> void:
	if smusher_label == null:
		return
	if _timer_flash_tween and _timer_flash_tween.is_valid():
		_timer_flash_tween.kill()
	_timer_flash_tween = create_tween().set_loops()
	_timer_flash_tween.tween_property(smusher_label, "modulate:a", 0.3, 0.4)
	_timer_flash_tween.tween_property(smusher_label, "modulate:a", 1.0, 0.4)

func _show_center_message(text: String) -> void:
	_show_center_message_colored(text, Color(1.0, 0.2, 0.2))

func _show_center_message_colored(text: String, color: Color) -> void:
	var msg := Label.new()
	msg.text = text
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg.anchors_preset = Control.PRESET_CENTER
	msg.offset_left = -300.0
	msg.offset_right = 300.0
	msg.offset_top = 60.0
	msg.offset_bottom = 100.0
	msg.add_theme_color_override("font_color", color)
	add_child(msg)
	var tween := create_tween()
	tween.tween_interval(1.5)
	tween.tween_property(msg, "modulate:a", 0.0, 0.5)
	tween.tween_callback(msg.queue_free)

# ---------- XP SYSTEM ----------

func _on_xp_gained(_amount: int, _total: int, _needed: int) -> void:
	_update_xp_display()

func _on_level_up(new_level: int) -> void:
	_update_xp_display()
	# Flash level-up message in gold
	_show_center_message_colored("LEVEL %d!" % new_level, Color(1.0, 0.85, 0.2))
	# Brief golden flash on the XP bar
	if xp_bar_fill:
		var original_color = xp_bar_fill.color
		xp_bar_fill.color = Color(1.0, 0.85, 0.2, 1.0)
		var tween = create_tween()
		tween.tween_property(xp_bar_fill, "color", original_color, 0.6)

func _update_xp_display() -> void:
	if level_label:
		level_label.text = "Lv. %d" % XpManager.current_level
	if xp_bar_fill and xp_bar_bg:
		var progress = XpManager.get_xp_progress()
		var max_width = xp_bar_bg.size.x
		xp_bar_fill.size.x = max_width * progress

# ---------- AUDIENCE SYSTEM ----------

func _on_vp_gained(_amount: int, _reason: String) -> void:
	_update_vp_display()

func _on_mood_changed(new_mood: int) -> void:
	if mood_label:
		mood_label.text = "Audience: %s" % AudienceManager.MOOD_NAMES[new_mood]
		mood_label.add_theme_color_override("font_color", AudienceManager.MOOD_COLORS[new_mood])
		# Pulse on mood change
		var tween = create_tween()
		tween.tween_property(mood_label, "scale", Vector2(1.15, 1.15), 0.1)
		tween.tween_property(mood_label, "scale", Vector2(1.0, 1.0), 0.15)

func _on_audience_comment(text: String, color: Color) -> void:
	if audience_chat == null:
		return
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.modulate = Color(1, 1, 1, 0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	audience_chat.add_child(label)
	# Fade in, hold, fade out
	var tween := create_tween()
	tween.tween_property(label, "modulate:a", 0.9, 0.15)
	tween.tween_interval(2.0)
	tween.tween_property(label, "modulate:a", 0.0, 0.8)
	tween.tween_callback(label.queue_free)
	# Cap to 4 visible comments
	while audience_chat.get_child_count() > 4:
		var oldest := audience_chat.get_child(0)
		audience_chat.remove_child(oldest)
		oldest.queue_free()

func _update_vp_display() -> void:
	if vp_label:
		vp_label.text = "VP: %d" % AudienceManager.total_vp
		# Brief flash on VP gain
		vp_label.add_theme_color_override("font_color", AudienceManager.get_mood_color())

# ---------- SUMMON COUNTER ----------

func _setup_summon_label() -> void:
	_summon_label = Label.new()
	_summon_label.name = "SummonCounter"
	_summon_label.text = ""
	_summon_label.anchors_preset = Control.PRESET_BOTTOM_LEFT
	_summon_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_summon_label.offset_left = 12.0
	_summon_label.offset_bottom = -120.0
	_summon_label.offset_right = 200.0
	_summon_label.offset_top = -148.0
	_summon_label.add_theme_font_size_override("font_size", 20)
	_summon_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	_summon_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_summon_label.add_theme_constant_override("shadow_offset_x", 1)
	_summon_label.add_theme_constant_override("shadow_offset_y", 1)
	_summon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_summon_label)

func _process(_delta: float) -> void:
	_update_summon_counter()

func _update_summon_counter() -> void:
	if _summon_label == null:
		return
	var hero = GameManager.hero
	if hero == null or not is_instance_valid(hero):
		_summon_label.text = ""
		return
	var count: int = hero.get("summon_count") if hero.get("summon_count") != null else 0
	if count <= 0:
		_summon_label.text = ""
	else:
		_summon_label.text = "⚔ Summons: %d/2" % count

# ---------- STATUS EFFECTS ----------

func _setup_status_icons() -> void:
	_status_container = HBoxContainer.new()
	_status_container.anchors_preset = Control.PRESET_TOP_LEFT
	_status_container.offset_left = 140.0
	_status_container.offset_top = 85.0
	_status_container.offset_right = 350.0
	_status_container.offset_bottom = 115.0
	_status_container.add_theme_constant_override("separation", 6)
	_status_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status_container)

func _on_status_effect_applied(target: Node3D, etype: int, _duration: float) -> void:
	# Only show hero's status effects on HUD
	if target != GameManager.hero:
		return
	if _status_icons.has(etype):
		return  # Already showing

	var icon := PanelContainer.new()
	icon.custom_minimum_size = Vector2(28, 28)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Colored background (colorblind-aware for poison)
	var style := StyleBoxFlat.new()
	var color: Color = StatusEffectManager.EFFECT_COLORS[etype]
	if etype == StatusEffectManager.EffectType.POISON:
		color = AccessibilitySettings.get_poison_color()
	style.bg_color = Color(color.r, color.g, color.b, 0.7)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_color = Color(1, 1, 1, 0.5)
	icon.add_theme_stylebox_override("panel", style)

	# Label with effect symbol
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	match etype:
		StatusEffectManager.EffectType.POISON:
			label.text = "P"
		StatusEffectManager.EffectType.SLOW:
			label.text = "S"
		StatusEffectManager.EffectType.STUN:
			label.text = "!"
	icon.add_child(label)

	_status_container.add_child(icon)
	_status_icons[etype] = icon

	# Pop-in animation
	icon.scale = Vector2(0.3, 0.3)
	var tween = create_tween()
	tween.tween_property(icon, "scale", Vector2(1.0, 1.0), 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func _on_status_effect_removed(target: Node3D, etype: int) -> void:
	if target != GameManager.hero:
		return
	if not _status_icons.has(etype):
		return

	var icon = _status_icons[etype]
	_status_icons.erase(etype)

	if is_instance_valid(icon):
		var tween = create_tween()
		tween.tween_property(icon, "scale", Vector2(0.0, 0.0), 0.1)
		tween.tween_callback(icon.queue_free)

# ---------- NARRATOR ----------

var _narrator_label: Label = null

func _on_narrator_says(text: String, color: Color, size: int) -> void:
	# Remove previous narrator text if still showing
	if _narrator_label and is_instance_valid(_narrator_label):
		_narrator_label.queue_free()

	_narrator_label = Label.new()
	_narrator_label.text = text
	_narrator_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_narrator_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_narrator_label.anchors_preset = Control.PRESET_CENTER_TOP
	_narrator_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_narrator_label.offset_left = -500.0
	_narrator_label.offset_right = 500.0
	_narrator_label.offset_top = 140.0
	_narrator_label.offset_bottom = 190.0
	_narrator_label.add_theme_color_override("font_color", color)
	_narrator_label.add_theme_font_size_override("font_size", size)
	_narrator_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_narrator_label.add_theme_constant_override("shadow_offset_x", 2)
	_narrator_label.add_theme_constant_override("shadow_offset_y", 2)
	_narrator_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_narrator_label.modulate = Color(1, 1, 1, 0)
	add_child(_narrator_label)

	# Dramatic fade: in → hold → out
	var tween := create_tween()
	tween.tween_property(_narrator_label, "modulate:a", 1.0, 0.4).set_ease(Tween.EASE_OUT)
	tween.tween_interval(2.5)
	tween.tween_property(_narrator_label, "modulate:a", 0.0, 1.0).set_ease(Tween.EASE_IN)
	tween.tween_callback(func():
		if _narrator_label and is_instance_valid(_narrator_label):
			_narrator_label.queue_free()
			_narrator_label = null
	)

func _on_retry_pressed() -> void:
	GameManager.reset_game_state()
	get_tree().change_scene_to_file("res://scenes/character_select.tscn")

func _on_quit_menu_pressed() -> void:
	GameManager.reset_game_state()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if GameManager.game_state != GameManager.GameState.PLAYING:
			if event.keycode == KEY_R or event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
				_on_retry_pressed()
			elif event.keycode == KEY_ESCAPE:
				_on_quit_menu_pressed()

func _apply_text_scale() -> void:
	## Rescale key HUD labels based on AccessibilitySettings.ui_text_scale.
	var scale := AccessibilitySettings.ui_text_scale
	var base_sizes := {
		"hp_label":      24,
		"mp_label":      24,
		"floor_label":   20,
		"gold_label":    22,
		"timer_label":   32,
		"level_label":   20,
		"xp_label":      18,
	}
	for node_name in base_sizes:
		var node = get_node_or_null(node_name)
		if node and node is Label:
			if node.get_theme_font_size("font_size") > 0 or true:
				node.add_theme_font_size_override("font_size", int(base_sizes[node_name] * scale))
