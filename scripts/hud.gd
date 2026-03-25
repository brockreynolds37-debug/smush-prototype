extends CanvasLayer

## WC3-inspired HUD: bottom bar with portrait, stats, ability grid, minimap, selection panel.

# ── NODE REFERENCES (built in _ready) ──
var health_bar: ProgressBar
var mana_bar: ProgressBar
var portrait: ColorRect
var portrait_label: Label
var ability_buttons: Array[Button] = []
var cooldown_overlays: Array[ColorRect] = []
var lock_overlays: Array[ColorRect] = []  # index 2 = E, index 3 = R
var minimap_frame: ColorRect
var floor_label: Label
var gold_label: Label
var loot_feed: VBoxContainer
var boss_bar_container: VBoxContainer
var boss_name_label: Label
var boss_health_bar: ProgressBar
var smusher_label: Label
var smusher_edge: ColorRect
var game_over_overlay: ColorRect
var game_over_label: Label
var level_label: Label
var xp_bar_bg: ColorRect
var xp_bar_fill: ColorRect
var vp_label: Label
var mood_label: Label
var audience_chat: VBoxContainer
var hero_name_label: Label
var hero_stats_label: Label
# Selection panel
var _sel_panel: PanelContainer
var _sel_name: Label
var _sel_stats: Label
# Cooldown timer labels
var _cooldown_labels: Array[Label] = []
# Spell alert label
var _spell_alert: Label = null

var _active_boss: Node3D = null
var _edge_pulse_tween: Tween = null
var _timer_flash_tween: Tween = null
var _status_container: HBoxContainer = null
var _status_icons: Dictionary = {}
var _summon_label: Label = null
var _narrator_label: Label = null

const FLOOR_NAMES := {0: "Training Grounds", 1: "The Sift", 2: "The Crucible", 3: "The Crush", 4: "The Deep"}
const BAR_HEIGHT := 200
const PANEL_BG := Color(0.08, 0.06, 0.04, 0.95)
const PANEL_BORDER := Color(0.45, 0.35, 0.15)
const GOLD_TEXT := Color(0.9, 0.8, 0.5)
const DIM_TEXT := Color(0.6, 0.55, 0.5)

func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_hud()
	# Signals
	KeybindingManager.bindings_changed.connect(_refresh_ability_labels)
	FloorManager.floor_changed.connect(_on_floor_changed)
	_update_floor_label(FloorManager.current_floor)
	await get_tree().process_frame
	_connect_hero()
	GameManager.game_over.connect(_on_game_over)
	LootManager.item_picked_up.connect(_on_item_picked_up)
	LootManager.gold_changed.connect(_on_gold_changed)
	AccessibilitySettings.settings_changed.connect(_apply_text_scale)
	SmusherTimer.time_updated.connect(_on_smusher_time_updated)
	if TutorialOverlay:
		SmusherTimer.time_updated.connect(func(_t): TutorialOverlay.on_timer_started(), CONNECT_ONE_SHOT)
	SmusherTimer.warning_phase_entered.connect(_on_smusher_warning)
	SmusherTimer.critical_phase_entered.connect(_on_smusher_critical)
	SmusherTimer.overtime_started.connect(_on_smusher_overtime)
	SmusherTimer.room_collapsed.connect(_on_room_collapsed)
	XpManager.xp_gained.connect(_on_xp_gained)
	XpManager.level_up.connect(_on_level_up)
	_update_xp_display()
	AudienceManager.vp_gained.connect(_on_vp_gained)
	AudienceManager.mood_changed.connect(_on_mood_changed)
	AudienceManager.audience_comment.connect(_on_audience_comment)
	_update_vp_display()
	_setup_status_icons()
	StatusEffectManager.effect_applied.connect(_on_status_effect_applied)
	StatusEffectManager.effect_removed.connect(_on_status_effect_removed)
	Narrator.narrator_says.connect(_on_narrator_says)
	# Unit selection from input handler
	var input_handler = get_node_or_null("/root/InputHandler")
	if input_handler:
		if input_handler.has_signal("unit_selected"):
			input_handler.unit_selected.connect(_on_unit_selected)
		if input_handler.has_signal("unit_deselected"):
			input_handler.unit_deselected.connect(_on_unit_deselected)

# ── BUILD UI ──

func _build_hud() -> void:
	_build_top_bar()
	_build_bottom_bar()
	_build_boss_bar()
	_build_spell_alert()
	_build_smusher_edge()
	_build_game_over_overlay()
	_build_summon_label()

func _build_top_bar() -> void:
	# Top-left: Gold, Level, XP bar, VP, Mood
	var top_left = VBoxContainer.new()
	top_left.set_anchors_preset(Control.PRESET_TOP_LEFT)
	top_left.offset_left = 12; top_left.offset_top = 8
	top_left.offset_right = 280; top_left.offset_bottom = 120
	top_left.add_theme_constant_override("separation", 2)
	top_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_left)

	gold_label = _make_label("Gold: 0", 18, GOLD_TEXT)
	top_left.add_child(gold_label)

	var level_row = HBoxContainer.new()
	level_row.add_theme_constant_override("separation", 8)
	top_left.add_child(level_row)

	level_label = _make_label("Lv. 1", 18, Color.WHITE)
	level_row.add_child(level_label)

	xp_bar_bg = ColorRect.new()
	xp_bar_bg.custom_minimum_size = Vector2(140, 10)
	xp_bar_bg.color = Color(0.15, 0.15, 0.2)
	level_row.add_child(xp_bar_bg)
	xp_bar_fill = ColorRect.new()
	xp_bar_fill.color = Color(0.2, 0.4, 0.9)
	xp_bar_fill.size = Vector2(0, 10)
	xp_bar_fill.position = Vector2.ZERO
	xp_bar_bg.add_child(xp_bar_fill)

	vp_label = _make_label("VP: 0", 16, DIM_TEXT)
	top_left.add_child(vp_label)
	mood_label = _make_label("Audience: WATCHING", 14, DIM_TEXT)
	top_left.add_child(mood_label)

	# Top-right: Floor label + Loot feed
	floor_label = _make_label("Floor 1", 20, GOLD_TEXT)
	floor_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	floor_label.offset_left = -350; floor_label.offset_top = 8
	floor_label.offset_right = -12; floor_label.offset_bottom = 32
	floor_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(floor_label)

	loot_feed = VBoxContainer.new()
	loot_feed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	loot_feed.offset_left = -350; loot_feed.offset_top = 36
	loot_feed.offset_right = -12; loot_feed.offset_bottom = 200
	loot_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(loot_feed)

	# Top-center: Timer + audience chat
	smusher_label = _make_label("", 28, Color.WHITE)
	smusher_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	smusher_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	smusher_label.offset_left = -100; smusher_label.offset_top = 8
	smusher_label.offset_right = 100; smusher_label.offset_bottom = 42
	smusher_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(smusher_label)

	audience_chat = VBoxContainer.new()
	audience_chat.set_anchors_preset(Control.PRESET_CENTER_TOP)
	audience_chat.offset_left = -250; audience_chat.offset_top = 46
	audience_chat.offset_right = 250; audience_chat.offset_bottom = 160
	audience_chat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(audience_chat)

func _build_bottom_bar() -> void:
	# Full-width bottom panel
	var bar = PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -BAR_HEIGHT
	var bar_style = StyleBoxFlat.new()
	bar_style.bg_color = PANEL_BG
	bar_style.border_width_top = 2
	bar_style.border_color = PANEL_BORDER
	bar.add_theme_stylebox_override("panel", bar_style)
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bar)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 0)
	bar.add_child(hbox)

	# Section 1: Minimap (180x180)
	_build_minimap_section(hbox)
	hbox.add_child(_vdivider())
	# Section 2: Portrait + HP/MP
	_build_portrait_section(hbox)
	hbox.add_child(_vdivider())
	# Section 3: Hero info/stats
	_build_info_section(hbox)
	hbox.add_child(_vdivider())
	# Section 4: Ability grid (2x2)
	_build_ability_section(hbox)
	hbox.add_child(_vdivider())
	# Section 5: Selection info (right side, takes remaining space)
	_build_selection_section(hbox)

func _build_minimap_section(parent: HBoxContainer) -> void:
	var container = MarginContainer.new()
	container.add_theme_constant_override("margin_left", 4)
	container.add_theme_constant_override("margin_top", 4)
	container.add_theme_constant_override("margin_right", 4)
	container.add_theme_constant_override("margin_bottom", 4)
	parent.add_child(container)

	minimap_frame = ColorRect.new()
	minimap_frame.custom_minimum_size = Vector2(180, 180)
	minimap_frame.color = Color(0.05, 0.05, 0.08)
	container.add_child(minimap_frame)

	# The Minimap script will attach to this
	var minimap_control = Control.new()
	minimap_control.name = "Minimap"
	minimap_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	minimap_control.set_script(load("res://scripts/minimap.gd"))
	minimap_frame.add_child(minimap_control)

func _build_portrait_section(parent: HBoxContainer) -> void:
	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size.x = 160
	vbox.add_theme_constant_override("separation", 4)
	parent.add_child(vbox)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 4)
	vbox.add_child(margin)

	var inner = VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	margin.add_child(inner)

	# Portrait square
	portrait = ColorRect.new()
	portrait.custom_minimum_size = Vector2(130, 100)
	portrait.color = Color(0.12, 0.1, 0.08)
	inner.add_child(portrait)

	portrait_label = _make_label("HERO", 14, DIM_TEXT)
	portrait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	portrait_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	portrait.add_child(portrait_label)

	# HP bar
	health_bar = ProgressBar.new()
	health_bar.custom_minimum_size = Vector2(130, 20)
	health_bar.max_value = 500; health_bar.value = 500
	health_bar.show_percentage = false
	var hp_style = StyleBoxFlat.new()
	hp_style.bg_color = Color(0.0, 0.6, 0.0)
	hp_style.set_corner_radius_all(2)
	health_bar.add_theme_stylebox_override("fill", hp_style)
	var hp_bg = StyleBoxFlat.new()
	hp_bg.bg_color = Color(0.15, 0.05, 0.05)
	hp_bg.set_corner_radius_all(2)
	health_bar.add_theme_stylebox_override("background", hp_bg)
	inner.add_child(health_bar)

	# MP bar
	mana_bar = ProgressBar.new()
	mana_bar.custom_minimum_size = Vector2(130, 14)
	mana_bar.max_value = 200; mana_bar.value = 200
	mana_bar.show_percentage = false
	var mp_style = StyleBoxFlat.new()
	mp_style.bg_color = Color(0.1, 0.2, 0.8)
	mp_style.set_corner_radius_all(2)
	mana_bar.add_theme_stylebox_override("fill", mp_style)
	var mp_bg = StyleBoxFlat.new()
	mp_bg.bg_color = Color(0.05, 0.05, 0.15)
	mp_bg.set_corner_radius_all(2)
	mana_bar.add_theme_stylebox_override("background", mp_bg)
	inner.add_child(mana_bar)

func _build_info_section(parent: HBoxContainer) -> void:
	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size.x = 200
	vbox.add_theme_constant_override("separation", 2)
	parent.add_child(vbox)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	vbox.add_child(margin)

	var inner = VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	margin.add_child(inner)

	hero_name_label = _make_label("Hero", 18, GOLD_TEXT)
	inner.add_child(hero_name_label)

	hero_stats_label = _make_label("", 14, DIM_TEXT)
	hero_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	inner.add_child(hero_stats_label)

func _build_ability_section(parent: HBoxContainer) -> void:
	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size.x = 160
	parent.add_child(vbox)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	vbox.add_child(margin)

	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	margin.add_child(grid)

	ability_buttons.clear()
	cooldown_overlays.clear()
	lock_overlays.clear()

	for i in range(4):
		var cell = Control.new()
		cell.custom_minimum_size = Vector2(65, 65)
		grid.add_child(cell)

		var btn = Button.new()
		btn.custom_minimum_size = Vector2(65, 65)
		btn.size = Vector2(65, 65)
		btn.position = Vector2.ZERO
		btn.add_theme_font_size_override("font_size", 11)
		btn.clip_text = true
		# Dark style
		var btn_style = StyleBoxFlat.new()
		btn_style.bg_color = Color(0.12, 0.10, 0.08)
		btn_style.border_width_top = 1; btn_style.border_width_bottom = 1
		btn_style.border_width_left = 1; btn_style.border_width_right = 1
		btn_style.border_color = PANEL_BORDER
		btn_style.set_corner_radius_all(3)
		btn.add_theme_stylebox_override("normal", btn_style)
		var hover_style = btn_style.duplicate()
		hover_style.border_color = Color(0.8, 0.65, 0.2)
		btn.add_theme_stylebox_override("hover", hover_style)
		btn.add_theme_color_override("font_color", GOLD_TEXT)
		cell.add_child(btn)
		ability_buttons.append(btn)

		# Cooldown overlay (anchored top, shrinks downward)
		var cd = ColorRect.new()
		cd.position = Vector2.ZERO
		cd.size = Vector2(65, 65)
		cd.custom_minimum_size = Vector2(65, 0)
		cd.color = Color(0, 0, 0, 0.7)
		cd.visible = false
		cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(cd)
		cooldown_overlays.append(cd)

		# Cooldown timer label (centered on button)
		var cd_label = Label.new()
		cd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cd_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cd_label.position = Vector2.ZERO
		cd_label.size = Vector2(65, 65)
		cd_label.add_theme_font_size_override("font_size", 16)
		cd_label.add_theme_color_override("font_color", Color.WHITE)
		cd_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		cd_label.add_theme_constant_override("shadow_offset_x", 1)
		cd_label.add_theme_constant_override("shadow_offset_y", 1)
		cd_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cd_label.visible = false
		cd_label.text = ""
		cell.add_child(cd_label)
		_cooldown_labels.append(cd_label)

		# Lock overlay (for spell slots 2 and 3)
		var lock = ColorRect.new()
		lock.position = Vector2.ZERO
		lock.size = Vector2(65, 65)
		lock.color = Color(0.1, 0.08, 0.06, 0.9)
		lock.visible = false
		lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(lock)

		if i == 2:
			lock.visible = true
			var lbl = _make_label("Lv.5", 12, DIM_TEXT)
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
			lock.add_child(lbl)
		elif i == 3:
			lock.visible = true
			var lbl = _make_label("Lv.10", 12, DIM_TEXT)
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
			lock.add_child(lbl)
		lock_overlays.append(lock)

func _build_selection_section(parent: HBoxContainer) -> void:
	_sel_panel = PanelContainer.new()
	_sel_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.04, 0.8)
	_sel_panel.add_theme_stylebox_override("panel", style)
	parent.add_child(_sel_panel)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	_sel_panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	_sel_name = _make_label("", 18, GOLD_TEXT)
	vbox.add_child(_sel_name)

	_sel_stats = _make_label("Left-click a unit to inspect", 13, DIM_TEXT)
	_sel_stats.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_sel_stats)

func _build_boss_bar() -> void:
	boss_bar_container = VBoxContainer.new()
	boss_bar_container.set_anchors_preset(Control.PRESET_CENTER_TOP)
	boss_bar_container.offset_left = -250; boss_bar_container.offset_right = 250
	boss_bar_container.offset_top = 50; boss_bar_container.offset_bottom = 100
	boss_bar_container.visible = false
	boss_bar_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(boss_bar_container)

	boss_name_label = _make_label("BOSS", 18, Color(0.9, 0.2, 0.2))
	boss_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_bar_container.add_child(boss_name_label)

	boss_health_bar = ProgressBar.new()
	boss_health_bar.custom_minimum_size = Vector2(500, 20)
	boss_health_bar.show_percentage = false
	var boss_fill = StyleBoxFlat.new()
	boss_fill.bg_color = Color(0.8, 0.1, 0.1)
	boss_fill.set_corner_radius_all(3)
	boss_health_bar.add_theme_stylebox_override("fill", boss_fill)
	var boss_bg = StyleBoxFlat.new()
	boss_bg.bg_color = Color(0.15, 0.05, 0.05)
	boss_bg.set_corner_radius_all(3)
	boss_health_bar.add_theme_stylebox_override("background", boss_bg)
	boss_bar_container.add_child(boss_health_bar)

func _build_smusher_edge() -> void:
	smusher_edge = ColorRect.new()
	smusher_edge.set_anchors_preset(Control.PRESET_FULL_RECT)
	smusher_edge.color = Color(0.8, 0.0, 0.0, 0.0)
	smusher_edge.visible = false
	smusher_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(smusher_edge)

func _build_game_over_overlay() -> void:
	game_over_overlay = ColorRect.new()
	game_over_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	game_over_overlay.color = Color(0.12, 0.0, 0.0, 0.85)
	game_over_overlay.visible = false
	add_child(game_over_overlay)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.offset_left = -300; vbox.offset_right = 300
	vbox.offset_top = -250; vbox.offset_bottom = 250
	vbox.add_theme_constant_override("separation", 12)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	game_over_overlay.add_child(vbox)

	game_over_label = _make_label("DEFEATED", 42, Color(0.9, 0.2, 0.1))
	game_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_label.name = "GameOverLabel"
	vbox.add_child(game_over_label)

	var stats_label = _make_label("", 16, DIM_TEXT)
	stats_label.name = "StatsLabel"
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(stats_label)

	var btn_row = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 20)
	vbox.add_child(btn_row)

	var retry_btn = Button.new()
	retry_btn.name = "RetryButton"
	retry_btn.text = "TRY AGAIN"
	retry_btn.custom_minimum_size = Vector2(180, 44)
	retry_btn.add_theme_font_size_override("font_size", 20)
	retry_btn.pressed.connect(_on_retry_pressed)
	btn_row.add_child(retry_btn)

	var quit_btn = Button.new()
	quit_btn.name = "QuitButton"
	quit_btn.text = "QUIT TO MENU"
	quit_btn.custom_minimum_size = Vector2(180, 44)
	quit_btn.add_theme_font_size_override("font_size", 20)
	quit_btn.pressed.connect(_on_quit_menu_pressed)
	btn_row.add_child(quit_btn)

	var hint = _make_label("R / Enter = Retry  |  ESC = Menu", 14, DIM_TEXT)
	hint.name = "HintLabel"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

func _build_summon_label() -> void:
	_summon_label = _make_label("", 20, Color(0.6, 0.8, 1.0))
	_summon_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_summon_label.offset_left = 12; _summon_label.offset_bottom = -(BAR_HEIGHT + 8)
	_summon_label.offset_right = 200; _summon_label.offset_top = -(BAR_HEIGHT + 36)
	_summon_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_summon_label.add_theme_constant_override("shadow_offset_x", 1)
	_summon_label.add_theme_constant_override("shadow_offset_y", 1)
	_summon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_summon_label)

func _build_spell_alert() -> void:
	_spell_alert = _make_label("", 18, Color(1.0, 0.3, 0.3))
	_spell_alert.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_spell_alert.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spell_alert.offset_left = -200; _spell_alert.offset_right = 200
	_spell_alert.offset_top = -(BAR_HEIGHT + 40); _spell_alert.offset_bottom = -(BAR_HEIGHT + 16)
	_spell_alert.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_spell_alert.add_theme_constant_override("shadow_offset_x", 1)
	_spell_alert.add_theme_constant_override("shadow_offset_y", 1)
	_spell_alert.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spell_alert.visible = false
	add_child(_spell_alert)

func _on_spell_failed(reason: String) -> void:
	if _spell_alert == null:
		return
	_spell_alert.text = reason
	_spell_alert.visible = true
	_spell_alert.modulate = Color(1, 1, 1, 1)
	# Fade out after 1.5s
	var tween = create_tween()
	tween.tween_interval(1.2)
	tween.tween_property(_spell_alert, "modulate:a", 0.0, 0.4)
	tween.tween_callback(func(): _spell_alert.visible = false)

# ── HELPERS ──

func _make_label(text: String, size: int, color: Color) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl

func _vdivider() -> ColorRect:
	var div = ColorRect.new()
	div.custom_minimum_size = Vector2(2, 0)
	div.size_flags_vertical = Control.SIZE_EXPAND_FILL
	div.color = PANEL_BORDER
	div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return div

# ── HERO CONNECTION ──

func _connect_hero() -> void:
	var hero = GameManager.hero
	if hero:
		hero.health_changed.connect(_on_health_changed)
		hero.mana_changed.connect(_on_mana_changed)
		hero.spell_cooldown_updated.connect(_on_cooldown_updated)
		hero.spell_unlocked.connect(_on_spell_unlocked)
		if hero.has_signal("spell_failed"):
			hero.spell_failed.connect(_on_spell_failed)
		_refresh_spell_locks()
		_refresh_ability_labels()
		_update_hero_info()

func _update_hero_info() -> void:
	var hero = GameManager.hero
	if hero == null:
		return
	var char_data = CharacterData.get_selected()
	if hero_name_label:
		hero_name_label.text = char_data.get("name", "Hero")
	if portrait_label:
		portrait_label.text = char_data.get("name", "HERO")
	if hero_stats_label:
		var txt := "Damage: %d\n" % hero._get_melee_damage()
		var armor_val: int = hero.armor if "armor" in hero else 0
		txt += "Armor: %d\n" % armor_val
		var eq_str: int = hero.equipment_str_bonus if "equipment_str_bonus" in hero else 0
		var eq_dex: int = hero.equipment_dex_bonus if "equipment_dex_bonus" in hero else 0
		var eq_int: int = hero.equipment_int_bonus if "equipment_int_bonus" in hero else 0
		txt += "STR: %d  DEX: %d\nINT: %d" % [
			XpManager.bonus_str + eq_str,
			XpManager.bonus_dex + eq_dex,
			XpManager.bonus_int + eq_int,
		]
		hero_stats_label.text = txt

# ── ABILITY LABELS ──

func _refresh_ability_labels() -> void:
	var spell_set = CharacterData.get_selected_spell_set()
	var names: Array = spell_set.get("names", ["Strike", "Fireball", "Heal", "Ground Slam"])
	for i in range(4):
		if i < ability_buttons.size() and ability_buttons[i]:
			var key_label: String = KeybindingManager.get_key_label(i)
			var n: String = names[i] if i < names.size() else "?"
			ability_buttons[i].text = "%s\n%s" % [key_label, n]

# ── SIGNAL HANDLERS ──

func _on_health_changed(current: int, maximum: int) -> void:
	health_bar.max_value = maximum
	health_bar.value = current

func _on_mana_changed(current: int, maximum: int) -> void:
	mana_bar.max_value = maximum
	mana_bar.value = current

func _on_cooldown_updated(spell_index: int, remaining: float, total: float) -> void:
	if spell_index < cooldown_overlays.size():
		var cd_rect = cooldown_overlays[spell_index]
		if remaining > 0:
			cd_rect.visible = true
			var ratio = remaining / total
			cd_rect.custom_minimum_size.y = 65 * ratio
			cd_rect.size.y = 65 * ratio
		else:
			cd_rect.visible = false
	# Update timer label
	if spell_index < _cooldown_labels.size():
		var cd_lbl = _cooldown_labels[spell_index]
		if remaining > 0:
			cd_lbl.visible = true
			cd_lbl.text = "%.1f" % remaining if remaining < 10.0 else "%d" % ceili(remaining)
		else:
			cd_lbl.visible = false
			cd_lbl.text = ""

func _refresh_spell_locks() -> void:
	var hero = GameManager.hero
	if hero == null:
		return
	if lock_overlays.size() > 2:
		lock_overlays[2].visible = not hero.is_spell_unlocked(2)
	if lock_overlays.size() > 3:
		lock_overlays[3].visible = not hero.is_spell_unlocked(3)

func _on_spell_unlocked(spell_index: int) -> void:
	if spell_index < lock_overlays.size():
		var lock_node = lock_overlays[spell_index]
		if lock_node and lock_node.visible:
			var spell_set = CharacterData.get_selected_spell_set()
			var names: Array = spell_set.get("names", ["Strike", "Fireball", "Heal", "Ground Slam"])
			var spell_name: String = names[spell_index] if spell_index < names.size() else "Spell %d" % (spell_index + 1)
			var tween = create_tween()
			tween.tween_property(lock_node, "color", Color(1.0, 0.85, 0.2, 0.9), 0.15)
			tween.tween_property(lock_node, "color", Color(1.0, 0.85, 0.2, 0.0), 0.4)
			tween.tween_callback(func(): lock_node.visible = false)
			_show_center_message_colored("%s UNLOCKED!" % spell_name.to_upper(), Color(1.0, 0.85, 0.2))
			AudioManager.play_sfx("level_up")

func _on_floor_changed(floor_num: int) -> void:
	if TutorialOverlay and floor_num == 1:
		TutorialOverlay.on_exit_visible()
	_update_floor_label(floor_num)
	hide_boss_bar()
	_reset_smusher_visuals()
	_update_vp_display()
	if mood_label:
		mood_label.text = "Audience: WATCHING"
		mood_label.add_theme_color_override("font_color", AudienceManager.MOOD_COLORS[AudienceManager.Mood.WATCHING])

func _reset_smusher_visuals() -> void:
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
		var fname = FLOOR_NAMES.get(floor_num, "Floor %d" % floor_num)
		floor_label.text = "Floor %d — %s" % [floor_num, fname]
		floor_label.modulate = Color(1, 1, 1, 0)
		var tween = create_tween()
		tween.tween_property(floor_label, "modulate", Color(1, 1, 1, 1), 0.5)

func _on_game_over(won: bool) -> void:
	if won:
		await get_tree().create_timer(1.5).timeout
		get_tree().change_scene_to_file("res://scenes/victory_screen.tscn")
		return
	if game_over_overlay == null:
		return
	game_over_overlay.visible = true
	game_over_label.text = "DEFEATED"
	var char_name = CharacterData.get_selected().get("name", "Hero")
	var s = RunStats.get_summary()
	var stats_text = ""
	stats_text += "%s — Level %d\n" % [char_name, XpManager.current_level]
	stats_text += "Floor Reached: %d\nTime: %s\n\n" % [FloorManager.max_floor_reached, s["run_time"]]
	stats_text += "Enemies Slain: %d\n" % s["total_kills"]
	if s["boss_kills"] > 0:
		stats_text += "Bosses Defeated: %d\n" % s["boss_kills"]
	stats_text += "Damage Dealt: %d\nDamage Taken: %d\n\n" % [s["damage_dealt"], s["damage_taken"]]
	stats_text += "Spells Cast: %d\nGold: %d\nVP: %d" % [s["total_spells"], s["gold_earned"], AudienceManager.total_vp]
	var rank := Leaderboard.submit_run()
	if rank > 0:
		stats_text += "\n\nLEADERBOARD #%d" % rank
	var stats_label = game_over_overlay.get_node_or_null("VBoxContainer/StatsLabel")
	if stats_label == null:
		# Find it by path traversal
		for child in game_over_overlay.get_children():
			var sl = child.get_node_or_null("StatsLabel")
			if sl:
				stats_label = sl
				break
	if stats_label:
		stats_label.text = stats_text
	game_over_overlay.modulate = Color(1, 1, 1, 0)
	var tween = create_tween()
	tween.tween_property(game_over_overlay, "modulate", Color(1, 1, 1, 1), 1.0)

func _on_gold_changed(amount: int) -> void:
	if gold_label:
		gold_label.text = "Gold: %d" % amount
		_update_hero_info()

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
	var tween := create_tween()
	tween.tween_interval(2.5)
	tween.tween_property(label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(label.queue_free)
	while loot_feed.get_child_count() > 6:
		var oldest := loot_feed.get_child(0)
		loot_feed.remove_child(oldest)
		oldest.queue_free()

# ── BOSS BAR ──

func show_boss_bar(boss: Node3D) -> void:
	_active_boss = boss
	if boss_bar_container:
		boss_bar_container.visible = true
		boss_name_label.text = boss.boss_display_name
		boss_health_bar.max_value = boss.max_health
		boss_health_bar.value = boss.current_health
		boss.health_changed.connect(_on_boss_health_changed)
		boss.boss_defeated.connect(_on_boss_defeated)
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

# ── SMUSHER TIMER ──

func _on_smusher_time_updated(seconds_remaining: float) -> void:
	if smusher_label:
		smusher_label.text = SmusherTimer.get_time_string()

func _on_smusher_warning() -> void:
	if smusher_label:
		smusher_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.0))
	_start_edge_pulse(0.12, 2.0)

func _on_smusher_critical() -> void:
	if smusher_label:
		smusher_label.add_theme_color_override("font_color", Color(1.0, 0.15, 0.15))
	_start_timer_flash()
	_start_edge_pulse(0.25, 0.8)

func _on_smusher_overtime() -> void:
	if smusher_label:
		smusher_label.text = "OVERTIME"
		smusher_label.add_theme_color_override("font_color", Color(1.0, 0.0, 0.0))
	_start_edge_pulse(0.35, 0.5)

func _on_room_collapsed(_room_index: int, room_name: String) -> void:
	_show_center_message("💀 %s COLLAPSED" % room_name.to_upper())

func _start_edge_pulse(_max_alpha: float, _period: float) -> void:
	# Disabled — no screen pulsing during gameplay
	pass

func _start_timer_flash() -> void:
	# Disabled — no pulsing during gameplay
	pass

func _show_center_message(text: String) -> void:
	_show_center_message_colored(text, Color(1.0, 0.2, 0.2))

func _show_center_message_colored(text: String, color: Color) -> void:
	var msg := Label.new()
	msg.text = text
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg.anchors_preset = Control.PRESET_CENTER
	msg.offset_left = -300.0; msg.offset_right = 300.0
	msg.offset_top = 60.0; msg.offset_bottom = 100.0
	msg.add_theme_color_override("font_color", color)
	add_child(msg)
	var tween := create_tween()
	tween.tween_interval(1.5)
	tween.tween_property(msg, "modulate:a", 0.0, 0.5)
	tween.tween_callback(msg.queue_free)

# ── XP SYSTEM ──

func _on_xp_gained(_amount: int, _total: int, _needed: int) -> void:
	_update_xp_display()

func _on_level_up(new_level: int) -> void:
	_update_xp_display()
	_show_center_message_colored("LEVEL %d!" % new_level, Color(1.0, 0.85, 0.2))
	if xp_bar_fill:
		var original_color = xp_bar_fill.color
		xp_bar_fill.color = Color(1.0, 0.85, 0.2, 1.0)
		var tween = create_tween()
		tween.tween_property(xp_bar_fill, "color", original_color, 0.6)
	_update_hero_info()

func _update_xp_display() -> void:
	if level_label:
		level_label.text = "Lv. %d" % XpManager.current_level
	if xp_bar_fill and xp_bar_bg:
		var progress = XpManager.get_xp_progress()
		var max_width = xp_bar_bg.size.x
		xp_bar_fill.size.x = max_width * progress

# ── AUDIENCE ──

func _on_vp_gained(_amount: int, _reason: String) -> void:
	_update_vp_display()

func _on_mood_changed(new_mood: int) -> void:
	if mood_label:
		mood_label.text = "Audience: %s" % AudienceManager.MOOD_NAMES[new_mood]
		mood_label.add_theme_color_override("font_color", AudienceManager.MOOD_COLORS[new_mood])
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
	var tween := create_tween()
	tween.tween_property(label, "modulate:a", 0.9, 0.15)
	tween.tween_interval(2.0)
	tween.tween_property(label, "modulate:a", 0.0, 0.8)
	tween.tween_callback(label.queue_free)
	while audience_chat.get_child_count() > 4:
		var oldest := audience_chat.get_child(0)
		audience_chat.remove_child(oldest)
		oldest.queue_free()

func _update_vp_display() -> void:
	if vp_label:
		vp_label.text = "VP: %d" % AudienceManager.total_vp
		vp_label.add_theme_color_override("font_color", AudienceManager.get_mood_color())

# ── SUMMON COUNTER ──

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
	_summon_label.text = "⚔ Summons: %d/2" % count if count > 0 else ""

# ── STATUS EFFECTS ──

func _setup_status_icons() -> void:
	_status_container = HBoxContainer.new()
	_status_container.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_status_container.offset_left = 140; _status_container.offset_top = 85
	_status_container.offset_right = 350; _status_container.offset_bottom = 115
	_status_container.add_theme_constant_override("separation", 6)
	_status_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status_container)

func _on_status_effect_applied(target: Node3D, etype: int, _duration: float) -> void:
	if target != GameManager.hero:
		return
	if _status_icons.has(etype):
		return
	var icon := PanelContainer.new()
	icon.custom_minimum_size = Vector2(28, 28)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	var color: Color = StatusEffectManager.EFFECT_COLORS[etype]
	if etype == StatusEffectManager.EffectType.POISON:
		color = AccessibilitySettings.get_poison_color()
	style.bg_color = Color(color.r, color.g, color.b, 0.7)
	style.set_corner_radius_all(4)
	style.set_border_width_all(1)
	style.border_color = Color(1, 1, 1, 0.5)
	icon.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	match etype:
		StatusEffectManager.EffectType.POISON: label.text = "P"
		StatusEffectManager.EffectType.SLOW: label.text = "S"
		StatusEffectManager.EffectType.STUN: label.text = "!"
	icon.add_child(label)
	_status_container.add_child(icon)
	_status_icons[etype] = icon
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

# ── NARRATOR ──

func _on_narrator_says(text: String, color: Color, size: int) -> void:
	if _narrator_label and is_instance_valid(_narrator_label):
		_narrator_label.queue_free()
	_narrator_label = Label.new()
	_narrator_label.text = text
	_narrator_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_narrator_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_narrator_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_narrator_label.offset_left = -500; _narrator_label.offset_right = 500
	_narrator_label.offset_top = 140; _narrator_label.offset_bottom = 190
	_narrator_label.add_theme_color_override("font_color", color)
	_narrator_label.add_theme_font_size_override("font_size", size)
	_narrator_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_narrator_label.add_theme_constant_override("shadow_offset_x", 2)
	_narrator_label.add_theme_constant_override("shadow_offset_y", 2)
	_narrator_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_narrator_label.modulate = Color(1, 1, 1, 0)
	add_child(_narrator_label)
	var tween := create_tween()
	tween.tween_property(_narrator_label, "modulate:a", 1.0, 0.4).set_ease(Tween.EASE_OUT)
	tween.tween_interval(2.5)
	tween.tween_property(_narrator_label, "modulate:a", 0.0, 1.0).set_ease(Tween.EASE_IN)
	tween.tween_callback(func():
		if _narrator_label and is_instance_valid(_narrator_label):
			_narrator_label.queue_free()
			_narrator_label = null
	)

# ── UNIT SELECTION ──

func _on_unit_selected(unit: Node3D) -> void:
	if _sel_name == null:
		return
	var uname: String = ""
	if unit.has_method("get_display_name"):
		uname = unit.get_display_name()
	elif "boss_display_name" in unit:
		uname = unit.boss_display_name
	elif "enemy_name" in unit:
		uname = unit.enemy_name
	else:
		uname = unit.name
	_sel_name.text = uname

	var stats := ""
	if "current_health" in unit and "max_health" in unit:
		stats += "HP: %d / %d\n" % [unit.current_health, unit.max_health]
	if "attack_damage" in unit:
		stats += "Damage: %d\n" % unit.attack_damage
	if "move_speed" in unit:
		stats += "Speed: %.1f\n" % unit.move_speed
	if "is_dead" in unit:
		stats += "Dead" if unit.is_dead else "Alive"
	if stats == "":
		stats = "No info available"
	_sel_stats.text = stats

func _on_unit_deselected() -> void:
	if _sel_name:
		_sel_name.text = ""
	if _sel_stats:
		_sel_stats.text = "Left-click a unit to inspect"

# ── GAME OVER INPUTS ──

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
	var s := AccessibilitySettings.ui_text_scale
	var pairs := [[gold_label, 18], [level_label, 18], [floor_label, 20], [smusher_label, 28]]
	for pair in pairs:
		if pair[0] and pair[0] is Label:
			pair[0].add_theme_font_size_override("font_size", int(pair[1] * s))
