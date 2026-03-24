extends CanvasLayer

## MultiplayerChat — in-game chat overlay + ping system + callout presets.
## Enter opens/sends chat. Q key or minimap click sends world ping.
## Callout wheel with presets: Help / Over here / Run / Boss.

var _chat_container: VBoxContainer = null
var _chat_input: LineEdit = null
var _chat_messages: VBoxContainer = null
var _is_chat_open: bool = false
var _callout_panel: PanelContainer = null
var _callout_visible: bool = false

## Ping markers: Array of { position, timer, marker_node }
var _ping_markers: Array = []
const PING_DURATION := 4.0

const CALLOUT_PRESETS := [
	{ "key": "1", "text": "Help!", "color": Color(1.0, 0.3, 0.3) },
	{ "key": "2", "text": "Over here!", "color": Color(0.3, 0.9, 0.4) },
	{ "key": "3", "text": "Run!", "color": Color(1.0, 0.7, 0.2) },
	{ "key": "4", "text": "Boss!", "color": Color(0.9, 0.3, 0.9) },
]

func _ready() -> void:
	layer = 80
	if not NetworkManager.is_multiplayer_active():
		queue_free()
		return
	_build_chat_ui()
	_build_callout_wheel()
	NetworkManager.chat_message_received.connect(_on_chat_message)
	NetworkManager.ping_received.connect(_on_ping_received)

func _process(delta: float) -> void:
	_update_ping_markers(delta)

# ---------- CHAT UI ----------

func _build_chat_ui() -> void:
	_chat_container = VBoxContainer.new()
	_chat_container.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_chat_container.offset_left = 10
	_chat_container.offset_right = 420
	_chat_container.offset_top = -300
	_chat_container.offset_bottom = -10
	_chat_container.add_theme_constant_override("separation", 4)
	add_child(_chat_container)

	# Message display area
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(400, 220)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_container.add_child(scroll)

	_chat_messages = VBoxContainer.new()
	_chat_messages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_messages.add_theme_constant_override("separation", 2)
	scroll.add_child(_chat_messages)

	# Input field (hidden until Enter pressed)
	_chat_input = LineEdit.new()
	_chat_input.placeholder_text = "Press Enter to chat..."
	_chat_input.max_length = 200
	_chat_input.custom_minimum_size = Vector2(400, 36)
	_chat_input.add_theme_font_size_override("font_size", 16)
	_chat_input.visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.04, 0.08, 0.85)
	style.border_color = Color(0.4, 0.35, 0.5, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	_chat_input.add_theme_stylebox_override("normal", style)
	_chat_input.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	_chat_input.add_theme_color_override("caret_color", Color(0.9, 0.8, 0.4))
	_chat_input.text_submitted.connect(_on_chat_submitted)
	_chat_container.add_child(_chat_input)

func _open_chat() -> void:
	_is_chat_open = true
	_chat_input.visible = true
	_chat_input.grab_focus()
	_chat_input.text = ""

func _close_chat() -> void:
	_is_chat_open = false
	_chat_input.visible = false
	_chat_input.release_focus()

func _on_chat_submitted(text: String) -> void:
	if text.strip_edges() != "":
		NetworkManager.send_chat_message(text.strip_edges())
	_close_chat()

func _on_chat_message(sender_id: int, message: String) -> void:
	var sender_name := NetworkManager.get_player_name(sender_id)
	var is_callout := message.begins_with("[CALLOUT] ")

	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.custom_minimum_size = Vector2(390, 0)
	label.add_theme_font_size_override("font_size", 14)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if is_callout:
		var callout_text := message.substr(10)
		label.text = "%s: %s" % [sender_name, callout_text]
		# Color based on callout type
		var color := Color(0.9, 0.8, 0.4)
		for preset in CALLOUT_PRESETS:
			if callout_text == preset["text"]:
				color = preset["color"]
				break
		label.add_theme_color_override("font_color", color)
	else:
		label.text = "%s: %s" % [sender_name, message]
		label.add_theme_color_override("font_color", Color(0.8, 0.75, 0.65))

	_chat_messages.add_child(label)

	# Fade out after 8 seconds
	var tween := create_tween()
	tween.tween_interval(8.0)
	tween.tween_property(label, "modulate:a", 0.0, 2.0)
	tween.tween_callback(label.queue_free)

	# Cap messages
	while _chat_messages.get_child_count() > 50:
		var oldest := _chat_messages.get_child(0)
		_chat_messages.remove_child(oldest)
		oldest.queue_free()

# ---------- CALLOUT WHEEL ----------

func _build_callout_wheel() -> void:
	_callout_panel = PanelContainer.new()
	_callout_panel.set_anchors_preset(Control.PRESET_CENTER)
	_callout_panel.offset_left = -120
	_callout_panel.offset_right = 120
	_callout_panel.offset_top = -80
	_callout_panel.offset_bottom = 80
	_callout_panel.visible = false

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.06, 0.05, 0.1, 0.9)
	panel_style.border_color = Color(0.5, 0.4, 0.6, 0.6)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(8)
	_callout_panel.add_theme_stylebox_override("panel", panel_style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_callout_panel.add_child(vbox)

	var title := Label.new()
	title.text = "CALLOUTS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.7, 0.65, 0.8))
	vbox.add_child(title)

	for preset in CALLOUT_PRESETS:
		var lbl := Label.new()
		lbl.text = "[%s] %s" % [preset["key"], preset["text"]]
		lbl.add_theme_font_size_override("font_size", 18)
		lbl.add_theme_color_override("font_color", preset["color"])
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(lbl)

	add_child(_callout_panel)

func _show_callout_wheel() -> void:
	_callout_visible = true
	_callout_panel.visible = true

func _hide_callout_wheel() -> void:
	_callout_visible = false
	_callout_panel.visible = false

func _send_callout(index: int) -> void:
	if index >= 0 and index < CALLOUT_PRESETS.size():
		NetworkManager.send_callout(CALLOUT_PRESETS[index]["text"])
	_hide_callout_wheel()

# ---------- PING SYSTEM ----------

func _send_ping_at_position(world_pos: Vector3) -> void:
	NetworkManager.send_ping(world_pos)

func _on_ping_received(sender_id: int, world_position: Vector3) -> void:
	var sender_name := NetworkManager.get_player_name(sender_id)

	# Create 3D ping marker in world
	var marker := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	marker.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.9, 0.2, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.9, 0.2)
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	marker.set_surface_override_material(0, mat)
	marker.position = world_position + Vector3(0, 2, 0)
	get_tree().current_scene.add_child(marker)

	_ping_markers.append({
		"marker": marker,
		"timer": PING_DURATION,
	})

	# Show chat message
	_on_chat_message(sender_id, "[PING] %s pinged a location" % sender_name)

func _update_ping_markers(delta: float) -> void:
	var to_remove: Array[int] = []
	for i in range(_ping_markers.size()):
		_ping_markers[i]["timer"] -= delta
		var marker: MeshInstance3D = _ping_markers[i]["marker"]
		if _ping_markers[i]["timer"] <= 0:
			to_remove.append(i)
			if is_instance_valid(marker):
				marker.queue_free()
		else:
			# Pulse effect
			if is_instance_valid(marker):
				var t: float = _ping_markers[i]["timer"]
				var s := 0.5 + sin(t * 6.0) * 0.15
				marker.scale = Vector3(s, s, s)
				# Fade out in last second
				if t < 1.0:
					var mat: StandardMaterial3D = marker.get_surface_override_material(0)
					if mat:
						mat.albedo_color.a = t

	# Remove expired (iterate backwards)
	for i in range(to_remove.size() - 1, -1, -1):
		_ping_markers.remove_at(to_remove[i])

# ---------- INPUT ----------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			if _is_chat_open:
				# Let the LineEdit handle submission
				pass
			else:
				_open_chat()
				get_viewport().set_input_as_handled()
			return

		if event.keycode == KEY_ESCAPE and _is_chat_open:
			_close_chat()
			get_viewport().set_input_as_handled()
			return

		# Callout wheel: V key to toggle
		if event.keycode == KEY_V:
			if _callout_visible:
				_hide_callout_wheel()
			else:
				_show_callout_wheel()
			get_viewport().set_input_as_handled()
			return

		# Callout selection while wheel is open
		if _callout_visible:
			match event.keycode:
				KEY_1: _send_callout(0)
				KEY_2: _send_callout(1)
				KEY_3: _send_callout(2)
				KEY_4: _send_callout(3)
			get_viewport().set_input_as_handled()
			return

		# Q key ping at mouse world position
		if event.keycode == KEY_Q and not _is_chat_open:
			# Use camera raycast to find world position
			var camera := get_viewport().get_camera_3d()
			if camera:
				var mouse_pos := get_viewport().get_mouse_position()
				var from := camera.project_ray_origin(mouse_pos)
				var to := from + camera.project_ray_normal(mouse_pos) * 100.0
				var space := camera.get_world_3d().direct_space_state
				var query := PhysicsRayQueryParameters3D.create(from, to)
				var result := space.intersect_ray(query)
				if not result.is_empty():
					_send_ping_at_position(result["position"])
