extends CanvasLayer

## Skill Tree UI — accessible from inventory (Tab key). Shows 3 branches with nodes.

var _panel: PanelContainer = null
var _is_visible: bool = false
var _skill_buttons: Dictionary = {}  # skill_id -> Button

func _ready() -> void:
	layer = 50
	visible = false
	SkillTree.skill_unlocked.connect(_on_skill_unlocked)
	SkillTree.skill_points_changed.connect(_on_points_changed)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		if _is_visible:
			hide_tree()
		else:
			show_tree()
		get_viewport().set_input_as_handled()

func show_tree() -> void:
	if _is_visible:
		return
	_is_visible = true
	visible = true
	_build_ui()

func hide_tree() -> void:
	_is_visible = false
	visible = false
	if _panel:
		_panel.queue_free()
		_panel = null
	_skill_buttons.clear()

func _build_ui() -> void:
	if _panel:
		_panel.queue_free()

	_skill_buttons.clear()
	var tree_data = SkillTree.get_tree_for_character()
	var char_data = CharacterData.get_selected()

	# Dark overlay background
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.7)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	# Main panel
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -450
	_panel.offset_right = 450
	_panel.offset_top = -300
	_panel.offset_bottom = 300
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.1, 0.95)
	style.border_color = Color(0.5, 0.4, 0.6)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(16)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	_panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "%s — Skill Tree" % char_data.get("name", "Hero")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	vbox.add_child(title)

	# Skill points label
	var points_label := Label.new()
	points_label.name = "PointsLabel"
	points_label.text = "Skill Points: %d" % SkillTree.skill_points
	points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	points_label.add_theme_font_size_override("font_size", 18)
	points_label.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	vbox.add_child(points_label)

	# Branch columns
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 20)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(hbox)

	var branch_names := ["offensive", "defensive", "utility"]
	var branch_colors := [Color(1.0, 0.4, 0.3), Color(0.3, 0.7, 1.0), Color(0.4, 1.0, 0.5)]
	var branch_labels := ["Offense", "Defense", "Utility"]

	for i in range(3):
		var branch_name: String = branch_names[i]
		if not tree_data.has(branch_name):
			continue
		var branch_data: Array = tree_data[branch_name]

		var branch_vbox := VBoxContainer.new()
		branch_vbox.add_theme_constant_override("separation", 8)
		branch_vbox.custom_minimum_size = Vector2(260, 0)
		hbox.add_child(branch_vbox)

		# Branch header
		var header := Label.new()
		header.text = branch_labels[i]
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header.add_theme_font_size_override("font_size", 20)
		header.add_theme_color_override("font_color", branch_colors[i])
		branch_vbox.add_child(header)

		# Skill nodes
		for skill in branch_data:
			var btn := _make_skill_button(skill, branch_colors[i])
			branch_vbox.add_child(btn)
			_skill_buttons[skill["id"]] = btn

	# Close button
	var close_btn := Button.new()
	close_btn.text = "Close (Tab)"
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.pressed.connect(hide_tree)
	var close_style := StyleBoxFlat.new()
	close_style.bg_color = Color(0.3, 0.2, 0.15, 0.8)
	close_style.set_corner_radius_all(4)
	close_btn.add_theme_stylebox_override("normal", close_style)
	vbox.add_child(close_btn)

func _make_skill_button(skill: Dictionary, branch_color: Color) -> Button:
	var btn := Button.new()
	var is_unlocked := skill["id"] in SkillTree.unlocked_skills
	var can_buy := SkillTree.can_unlock(skill["id"])

	btn.text = "%s\n%s" % [skill["name"], skill["desc"]]
	btn.add_theme_font_size_override("font_size", 13)
	btn.custom_minimum_size = Vector2(250, 60)
	btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	var style := StyleBoxFlat.new()
	if is_unlocked:
		style.bg_color = Color(branch_color.r, branch_color.g, branch_color.b, 0.3)
		style.border_color = branch_color
		btn.add_theme_color_override("font_color", Color.WHITE)
	elif can_buy:
		style.bg_color = Color(0.15, 0.12, 0.18, 0.9)
		style.border_color = Color(branch_color.r, branch_color.g, branch_color.b, 0.6)
		btn.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	else:
		style.bg_color = Color(0.08, 0.07, 0.09, 0.8)
		style.border_color = Color(0.3, 0.3, 0.3, 0.4)
		btn.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
		btn.disabled = true

	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", style)

	if not is_unlocked and can_buy:
		var sid = skill["id"]
		btn.pressed.connect(func(): _on_skill_pressed(sid))

	return btn

func _on_skill_pressed(skill_id: String) -> void:
	SkillTree.unlock_skill(skill_id)
	# Rebuild UI to reflect changes
	hide_tree()
	show_tree()

func _on_skill_unlocked(_skill_id: String) -> void:
	pass  # Rebuilt on next show

func _on_points_changed(_points: int) -> void:
	if _is_visible:
		hide_tree()
		show_tree()
