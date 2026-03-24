extends Node3D

## Victory Screen — shown after Floor 3 boss is defeated.
## Displays run stats, audience score/verdict, and lets player play again or return to menu.
## Style: The Collective commentates on your performance.

const COLLECTIVE_VERDICTS := {
	"legendary": {
		"title": "LEGENDARY PERFORMANCE",
		"color": Color(1.0, 0.85, 0.0),  # Gold
		"lines": [
			"The Collective has not seen such a display in centuries.",
			"Your name will echo through the Archives. Well played.",
			"The audience will speak of this run for generations.",
			"Unprecedented. The Smusher itself hesitated to claim you.",
		],
		"vp_min": 4000,
	},
	"crowd_pleaser": {
		"title": "CROWD PLEASER",
		"color": Color(0.4, 0.9, 0.5),  # Green
		"lines": [
			"The audience got their money's worth. A solid show.",
			"Entertaining, competent, occasionally brilliant. Well done.",
			"You kept them watching. That's more than most manage.",
			"A satisfying run. The Collective is pleased.",
		],
		"vp_min": 1500,
	},
	"decent": {
		"title": "DECENT SHOW",
		"color": Color(0.6, 0.7, 0.9),  # Blue-ish
		"lines": [
			"You survived. The audience remained awake. Barely.",
			"Functional. Unspectacular. The Collective has noted your... effort.",
			"You cleared the floors. Whether you *entertained*... debatable.",
			"A middling performance. Next time, put on a show.",
		],
		"vp_min": 500,
	},
	"lackluster": {
		"title": "LACKLUSTER",
		"color": Color(0.75, 0.4, 0.3),  # Dim red
		"lines": [
			"The audience was not impressed. Neither are we.",
			"You survived, technically. The Collective is underwhelmed.",
			"Is that all? The Smusher showed more enthusiasm than you did.",
			"Dull. Predictable. The Collective suggests remedial entertainment training.",
		],
		"vp_min": 0,
	},
}

var cam: Camera3D = null
var canvas: CanvasLayer = null
var _fade_overlay: ColorRect = null
var _cam_angle: float = 0.0
var _is_transitioning: bool = false

# Stat data populated before entering scene
# These are set by GameManager or FloorManager before scene load
static var pending_stats: Dictionary = {}

func _ready() -> void:
	_build_3d_backdrop()
	_build_ui()
	_play_entrance_animation()

func _process(delta: float) -> void:
	_cam_angle += delta * 0.08
	if cam:
		cam.position.x = sin(_cam_angle) * 10.0
		cam.position.z = cos(_cam_angle) * 10.0
		cam.look_at(Vector3(0, 1.0, 0), Vector3.UP)

# ── 3D BACKDROP ──

func _build_3d_backdrop() -> void:
	cam = Camera3D.new()
	cam.position = Vector3(0, 5.0, 10.0)
	cam.fov = 50.0
	cam.current = true
	add_child(cam)

	# Deep purple sky — triumphant but ominous Collective vibe
	var world_env = WorldEnvironment.new()
	var environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.03, 0.02, 0.06)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.15, 0.1, 0.25)
	environment.ambient_light_energy = 0.3
	environment.tonemap_mode = Environment.TONE_MAP_ACES
	environment.glow_enabled = true
	environment.glow_intensity = 0.8
	environment.glow_bloom = 0.2
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.08, 0.04, 0.15)
	environment.fog_density = 0.015
	world_env.environment = environment
	add_child(world_env)

	# Floor
	var ground = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(40, 40)
	ground.mesh = plane
	var gm = StandardMaterial3D.new()
	gm.albedo_color = Color(0.08, 0.06, 0.1)
	gm.roughness = 0.9
	gm.metallic = 0.15
	ground.set_surface_override_material(0, gm)
	add_child(ground)

	# Victory torch ring — golden lights
	for i in range(12):
		var angle = i * TAU / 12.0
		var torch = OmniLight3D.new()
		torch.position = Vector3(cos(angle) * 7.0, 2.0, sin(angle) * 7.0)
		torch.light_color = Color(1.0, 0.75, 0.2)
		torch.light_energy = 2.0
		torch.omni_range = 6.0
		add_child(torch)
		# Flicker
		var tw = create_tween().set_loops()
		tw.tween_property(torch, "light_energy", 1.5 + randf() * 0.8, 0.2 + randf() * 0.3)
		tw.tween_property(torch, "light_energy", 2.0 + randf() * 0.8, 0.2 + randf() * 0.3)

	# Central victory spotlight — white/gold
	var spotlight = SpotLight3D.new()
	spotlight.position = Vector3(0, 12, 0)
	spotlight.rotation_degrees = Vector3(-90, 0, 0)
	spotlight.light_color = Color(1.0, 0.95, 0.85)
	spotlight.light_energy = 4.0
	spotlight.spot_range = 20.0
	spotlight.spot_angle = 25.0
	add_child(spotlight)

	# Floating particles — golden motes
	var particles = GPUParticles3D.new()
	particles.amount = 60
	particles.lifetime = 5.0
	particles.position = Vector3(0, 2, 0)
	var pm = ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 60.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.5
	pm.gravity = Vector3(0, -0.1, 0)
	pm.scale_min = 0.04
	pm.scale_max = 0.1
	pm.color = Color(1.0, 0.85, 0.3, 0.8)
	particles.process_material = pm
	var quad = QuadMesh.new()
	quad.size = Vector2(0.1, 0.1)
	particles.draw_pass_1 = quad
	add_child(particles)

# ── UI ──

func _build_ui() -> void:
	canvas = CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)

	# Fade overlay (starts black, fades out)
	_fade_overlay = ColorRect.new()
	_fade_overlay.color = Color(0, 0, 0, 1)
	_fade_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(_fade_overlay)

	# Collect stats
	var stats := _gather_stats()
	var verdict := _determine_verdict(stats.vp)

	# === TITLE ===
	var title = Label.new()
	title.text = "VICTORY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 88)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 40
	title.offset_bottom = 140
	canvas.add_child(title)

	# Audience applause sub-text
	var applause = Label.new()
	applause.text = "*thunderous applause*"
	applause.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	applause.add_theme_font_size_override("font_size", 18)
	applause.add_theme_color_override("font_color", Color(0.7, 0.6, 0.8))
	applause.set_anchors_preset(Control.PRESET_TOP_WIDE)
	applause.offset_top = 140
	applause.offset_bottom = 175
	canvas.add_child(applause)

	# === VERDICT BOX ===
	var verdict_bg = PanelContainer.new()
	verdict_bg.set_anchors_preset(Control.PRESET_TOP_WIDE)
	verdict_bg.offset_left = 200
	verdict_bg.offset_right = -200
	verdict_bg.offset_top = 185
	verdict_bg.offset_bottom = 280
	var vbg_style = StyleBoxFlat.new()
	vbg_style.bg_color = Color(verdict.color.r, verdict.color.g, verdict.color.b, 0.15)
	vbg_style.border_color = verdict.color
	vbg_style.set_border_width_all(2)
	vbg_style.set_corner_radius_all(8)
	vbg_style.set_content_margin_all(12)
	verdict_bg.add_theme_stylebox_override("panel", vbg_style)
	canvas.add_child(verdict_bg)

	var verdict_vbox = VBoxContainer.new()
	verdict_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	verdict_bg.add_child(verdict_vbox)

	var verdict_label = Label.new()
	verdict_label.text = verdict.title
	verdict_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	verdict_label.add_theme_font_size_override("font_size", 32)
	verdict_label.add_theme_color_override("font_color", verdict.color)
	verdict_vbox.add_child(verdict_label)

	var verdict_quote = Label.new()
	verdict_quote.text = "\"" + verdict.lines.pick_random() + "\""
	verdict_quote.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	verdict_quote.add_theme_font_size_override("font_size", 15)
	verdict_quote.add_theme_color_override("font_color", Color(0.7, 0.65, 0.8))
	verdict_quote.autowrap_mode = TextServer.AUTOWRAP_WORD
	verdict_vbox.add_child(verdict_quote)

	# === STATS PANEL ===
	var stats_bg = PanelContainer.new()
	stats_bg.set_anchors_preset(Control.PRESET_CENTER_WIDE)
	stats_bg.offset_left = 80
	stats_bg.offset_right = -80
	stats_bg.offset_top = -70
	stats_bg.offset_bottom = 90
	var sbg_style = StyleBoxFlat.new()
	sbg_style.bg_color = Color(0.06, 0.05, 0.1, 0.85)
	sbg_style.border_color = Color(0.3, 0.25, 0.4, 0.6)
	sbg_style.set_border_width_all(1)
	sbg_style.set_corner_radius_all(8)
	sbg_style.set_content_margin_all(20)
	stats_bg.add_theme_stylebox_override("panel", sbg_style)
	canvas.add_child(stats_bg)

	var stats_grid = GridContainer.new()
	stats_grid.columns = 3
	stats_grid.add_theme_constant_override("h_separation", 40)
	stats_grid.add_theme_constant_override("v_separation", 10)
	stats_bg.add_child(stats_grid)

	var stat_entries := [
		["KILLS", str(stats.kills), Color(0.9, 0.5, 0.5)],
		["DAMAGE DEALT", _format_number(stats.damage_dealt), Color(1.0, 0.7, 0.3)],
		["AUDIENCE SCORE", _format_number(stats.vp) + " VP", verdict.color],
		["FLOORS CLEARED", str(stats.floors_cleared) + " / 3", Color(0.5, 0.8, 0.6)],
		["GOLD EARNED", str(stats.gold_earned) + "g", Color(1.0, 0.9, 0.4)],
		["TIME SURVIVED", stats.time_str, Color(0.6, 0.75, 0.9)],
		["BOSS KILLS", str(stats.boss_kills), Color(1.0, 0.4, 0.6)],
		["ELITE KILLS", str(stats.elite_kills), Color(0.8, 0.5, 1.0)],
		["CHARACTER", stats.char_name, Color(0.85, 0.8, 0.7)],
	]

	for entry in stat_entries:
		var lbl_title = Label.new()
		lbl_title.text = entry[0]
		lbl_title.add_theme_font_size_override("font_size", 13)
		lbl_title.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
		stats_grid.add_child(lbl_title)

		var lbl_sep = Label.new()
		lbl_sep.text = "→"
		lbl_sep.add_theme_font_size_override("font_size", 13)
		lbl_sep.add_theme_color_override("font_color", Color(0.3, 0.3, 0.4))
		stats_grid.add_child(lbl_sep)

		var lbl_val = Label.new()
		lbl_val.text = entry[1]
		lbl_val.add_theme_font_size_override("font_size", 18)
		lbl_val.add_theme_color_override("font_color", entry[2])
		stats_grid.add_child(lbl_val)

	# === CHARACTER + Mood line ===
	var mood_label = Label.new()
	var mood_name := "WATCHING"
	if AudienceManager:
		mood_name = AudienceManager.MOOD_NAMES[AudienceManager.current_mood]
	mood_label.text = "Final audience mood: %s" % mood_name
	mood_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mood_label.add_theme_font_size_override("font_size", 15)
	mood_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	mood_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	mood_label.offset_top = -170
	mood_label.offset_bottom = -140
	canvas.add_child(mood_label)

	# Submit to leaderboard
	var rank := Leaderboard.submit_run()
	var rank_label = Label.new()
	if rank > 0 and rank <= 10:
		rank_label.text = "LEADERBOARD RANK #%d" % rank
		rank_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	else:
		rank_label.text = "Did not make the Top 10."
		rank_label.add_theme_color_override("font_color", Color(0.5, 0.45, 0.55))
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank_label.add_theme_font_size_override("font_size", 16)
	rank_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	rank_label.offset_top = -145
	rank_label.offset_bottom = -120
	canvas.add_child(rank_label)

	# === BUTTONS ===
	var btn_row = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 30)
	btn_row.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	btn_row.offset_top = -120
	btn_row.offset_bottom = -40
	canvas.add_child(btn_row)

	var play_again_btn = _make_button("PLAY AGAIN", false)
	play_again_btn.pressed.connect(_on_play_again)
	btn_row.add_child(play_again_btn)

	var menu_btn = _make_button("MAIN MENU", true)
	menu_btn.pressed.connect(_on_main_menu)
	btn_row.add_child(menu_btn)

# ── DATA ──

func _gather_stats() -> Dictionary:
	var stats := {
		"kills": 0,
		"damage_dealt": 0,
		"vp": 0,
		"floors_cleared": 3,
		"gold_earned": 0,
		"time_str": "0:00",
		"boss_kills": 0,
		"elite_kills": 0,
		"char_name": "Unknown",
	}

	# Pull from RunStats autoload
	if Engine.has_singleton("RunStats") or get_node_or_null("/root/RunStats"):
		var rs = get_node("/root/RunStats")
		stats.kills = rs.total_kills
		stats.damage_dealt = rs.damage_dealt
		stats.floors_cleared = rs.floors_cleared
		stats.gold_earned = rs.gold_earned
		stats.time_str = rs.get_run_time_string()
		stats.boss_kills = rs.boss_kills
		stats.elite_kills = rs.elite_kills

	# VP from AudienceManager
	if get_node_or_null("/root/AudienceManager"):
		stats.vp = AudienceManager.total_vp

	# Character from CharacterData
	if get_node_or_null("/root/CharacterData"):
		stats.char_name = CharacterData.get_selected_name() if CharacterData.has_method("get_selected_name") else "Adventurer"

	# Override with pending_stats if populated (for cutscene transitions)
	for key in pending_stats:
		if stats.has(key):
			stats[key] = pending_stats[key]

	return stats

func _determine_verdict(vp: int) -> Dictionary:
	for key in ["legendary", "crowd_pleaser", "decent", "lackluster"]:
		if vp >= COLLECTIVE_VERDICTS[key]["vp_min"]:
			return COLLECTIVE_VERDICTS[key]
	return COLLECTIVE_VERDICTS["lackluster"]

# ── ANIMATIONS ──

func _play_entrance_animation() -> void:
	# Fade in from black
	var tween = create_tween()
	tween.tween_property(_fade_overlay, "color:a", 0.0, 1.2)

# ── ACTIONS ──

func _on_play_again() -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	GameManager.reset_game_state()
	_fade_to_scene("res://scenes/character_select.tscn")

func _on_main_menu() -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	_fade_to_scene("res://scenes/main_menu.tscn")

# ── HELPERS ──

func _make_button(text: String, subdued: bool = false) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 24)
	btn.custom_minimum_size = Vector2(240, 56)

	var style_normal = StyleBoxFlat.new()
	if subdued:
		style_normal.bg_color = Color(0.12, 0.1, 0.15, 0.85)
		style_normal.border_color = Color(0.35, 0.3, 0.4, 0.5)
	else:
		style_normal.bg_color = Color(0.45, 0.3, 0.1, 0.9)
		style_normal.border_color = Color(0.75, 0.55, 0.2)
	style_normal.set_border_width_all(2)
	style_normal.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", style_normal)

	var style_hover = style_normal.duplicate()
	if subdued:
		style_hover.bg_color = Color(0.2, 0.16, 0.26, 0.9)
		style_hover.border_color = Color(0.55, 0.45, 0.6)
	else:
		style_hover.bg_color = Color(0.6, 0.42, 0.15, 0.95)
		style_hover.border_color = Color(1.0, 0.8, 0.3)
	btn.add_theme_stylebox_override("hover", style_hover)

	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = style_normal.bg_color.darkened(0.3)
	btn.add_theme_stylebox_override("pressed", style_pressed)

	btn.add_theme_color_override("font_color",
		Color(1.0, 0.9, 0.7) if not subdued else Color(0.6, 0.55, 0.65))
	return btn

func _fade_to_scene(scene_path: String) -> void:
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var fade_canvas = CanvasLayer.new()
	fade_canvas.layer = 100
	add_child(fade_canvas)
	fade_canvas.add_child(overlay)

	var tween = create_tween()
	tween.tween_property(overlay, "color:a", 1.0, 0.7)
	tween.tween_callback(func():
		get_tree().change_scene_to_file(scene_path)
	)

func _format_number(n: int) -> String:
	if n >= 1000000:
		return "%.1fM" % (n / 1000000.0)
	elif n >= 1000:
		return "%.1fK" % (n / 1000.0)
	return str(n)

func _unhandled_input(event: InputEvent) -> void:
	if _is_transitioning:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_main_menu()
