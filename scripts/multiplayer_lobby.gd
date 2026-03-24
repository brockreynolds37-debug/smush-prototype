extends Node3D

## Multiplayer Lobby — Host/Join screen with player list, character selection,
## ready toggles, room code display, and ping. Styled to match main_menu.

enum LobbyMode { CHOOSE, HOST, JOIN }

var mode: LobbyMode = LobbyMode.CHOOSE
var cam: Camera3D = null
var cam_angle: float = 0.0
var is_transitioning: bool = false

# UI nodes kept for updates
var canvas: CanvasLayer = null
var mode_panel: VBoxContainer = null          # Host/Join choice
var lobby_panel: VBoxContainer = null          # Connected player list
var room_code_label: Label = null
var ip_label: Label = null
var status_label: Label = null
var player_list_container: VBoxContainer = null
var start_button: Button = null
var ready_button: Button = null
var join_address_edit: LineEdit = null
var join_code_edit: LineEdit = null
var join_error_label: Label = null
var join_panel: VBoxContainer = null
var name_edit: LineEdit = null

# Per-player character browse (local)
var _local_char_index: int = 0
var _local_spell_set: int = 0
var _local_char_label: Label = null
var _local_ready: bool = false
var _local_player_name: String = ""

func _ready() -> void:
	_build_3d_backdrop()
	_build_ui()
	_connect_network_signals()

func _process(delta: float) -> void:
	cam_angle += delta * 0.12
	if cam:
		cam.position.x = sin(cam_angle) * 8.0
		cam.position.z = cos(cam_angle) * 8.0
		cam.look_at(Vector3(0, 0.5, 0), Vector3.UP)

func _exit_tree() -> void:
	_disconnect_network_signals()

# ── 3D BACKDROP (reuse main menu vibe) ──

func _build_3d_backdrop() -> void:
	cam = Camera3D.new()
	cam.position = Vector3(0, 4.0, 8.0)
	cam.fov = 45.0
	cam.current = true
	add_child(cam)

	var world_env = WorldEnvironment.new()
	var environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.02, 0.02, 0.04)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.08, 0.06, 0.12)
	environment.ambient_light_energy = 0.2
	environment.tonemap_mode = Environment.TONE_MAP_ACES
	environment.glow_enabled = true
	environment.glow_intensity = 0.6
	environment.glow_bloom = 0.15
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.05, 0.03, 0.08)
	environment.fog_density = 0.02
	world_env.environment = environment
	add_child(world_env)

	var ground = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(30, 30)
	ground.mesh = plane
	var gm = StandardMaterial3D.new()
	gm.albedo_color = Color(0.06, 0.05, 0.08)
	gm.roughness = 0.95
	ground.set_surface_override_material(0, gm)
	add_child(ground)

	for i in range(8):
		var angle = i * TAU / 8.0
		var pillar = MeshInstance3D.new()
		var cyl = CylinderMesh.new()
		cyl.top_radius = 0.4
		cyl.bottom_radius = 0.5
		cyl.height = 5.0
		cyl.radial_segments = 8
		pillar.mesh = cyl
		pillar.position = Vector3(cos(angle) * 5.0, 2.5, sin(angle) * 5.0)
		var pm = StandardMaterial3D.new()
		pm.albedo_color = Color(0.12, 0.1, 0.14)
		pm.roughness = 0.8
		pillar.set_surface_override_material(0, pm)
		add_child(pillar)

	# Torches
	for i in range(0, 8, 2):
		var angle = i * TAU / 8.0
		var torch = OmniLight3D.new()
		torch.position = Vector3(cos(angle) * 4.5, 3.5, sin(angle) * 4.5)
		torch.light_color = Color(1.0, 0.6, 0.2)
		torch.light_energy = 1.5
		torch.omni_range = 5.0
		add_child(torch)
		var tw = create_tween().set_loops()
		tw.tween_property(torch, "light_energy", 1.0 + randf() * 0.5, 0.3 + randf() * 0.4)
		tw.tween_property(torch, "light_energy", 1.5 + randf() * 0.5, 0.3 + randf() * 0.4)

# ── UI ──

func _build_ui() -> void:
	canvas = CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)

	# Title
	var title = Label.new()
	title.text = "MULTIPLAYER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(0.95, 0.8, 0.4))
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 60
	title.offset_bottom = 140
	canvas.add_child(title)

	_build_mode_panel()
	_build_join_panel()
	_build_lobby_panel()

	# Back button (always visible, bottom-left)
	var back_btn = _make_button("BACK", true)
	back_btn.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	back_btn.offset_left = 40
	back_btn.offset_right = 240
	back_btn.offset_top = -80
	back_btn.offset_bottom = -20
	back_btn.pressed.connect(_on_back)
	canvas.add_child(back_btn)

	_show_mode(LobbyMode.CHOOSE)

func _build_mode_panel() -> void:
	mode_panel = VBoxContainer.new()
	mode_panel.set_anchors_preset(Control.PRESET_CENTER)
	mode_panel.offset_left = -180
	mode_panel.offset_right = 180
	mode_panel.offset_top = -100
	mode_panel.offset_bottom = 160
	mode_panel.add_theme_constant_override("separation", 16)
	canvas.add_child(mode_panel)

	# Player name input
	var name_lbl = Label.new()
	name_lbl.text = "Your Name:"
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", Color(0.7, 0.65, 0.8))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mode_panel.add_child(name_lbl)

	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Enter your name"
	name_edit.text = "Player %d" % randi_range(1, 999)
	name_edit.add_theme_font_size_override("font_size", 22)
	name_edit.custom_minimum_size = Vector2(320, 46)
	name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_edit.max_length = 20
	var name_style = StyleBoxFlat.new()
	name_style.bg_color = Color(0.08, 0.06, 0.12, 0.9)
	name_style.border_color = Color(0.5, 0.4, 0.6)
	name_style.set_border_width_all(2)
	name_style.set_corner_radius_all(6)
	name_style.set_content_margin_all(8)
	name_edit.add_theme_stylebox_override("normal", name_style)
	name_edit.add_theme_color_override("font_color", Color(0.95, 0.9, 0.8))
	name_edit.add_theme_color_override("font_placeholder_color", Color(0.4, 0.4, 0.45))
	mode_panel.add_child(name_edit)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	mode_panel.add_child(spacer)

	var host_btn = _make_button("HOST GAME")
	host_btn.pressed.connect(_on_host)
	mode_panel.add_child(host_btn)

	var join_btn = _make_button("JOIN GAME")
	join_btn.pressed.connect(_on_show_join)
	mode_panel.add_child(join_btn)

func _build_join_panel() -> void:
	join_panel = VBoxContainer.new()
	join_panel.set_anchors_preset(Control.PRESET_CENTER)
	join_panel.offset_left = -220
	join_panel.offset_right = 220
	join_panel.offset_top = -120
	join_panel.offset_bottom = 160
	join_panel.add_theme_constant_override("separation", 12)
	join_panel.visible = false
	canvas.add_child(join_panel)

	var ip_lbl = Label.new()
	ip_lbl.text = "Host IP Address:"
	ip_lbl.add_theme_font_size_override("font_size", 18)
	ip_lbl.add_theme_color_override("font_color", Color(0.7, 0.65, 0.8))
	ip_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	join_panel.add_child(ip_lbl)

	var edit_style = StyleBoxFlat.new()
	edit_style.bg_color = Color(0.08, 0.06, 0.12, 0.9)
	edit_style.border_color = Color(0.5, 0.4, 0.6)
	edit_style.set_border_width_all(2)
	edit_style.set_corner_radius_all(6)
	edit_style.set_content_margin_all(8)

	join_address_edit = LineEdit.new()
	join_address_edit.placeholder_text = "192.168.1.100"
	join_address_edit.add_theme_font_size_override("font_size", 22)
	join_address_edit.custom_minimum_size = Vector2(400, 46)
	join_address_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	join_address_edit.add_theme_stylebox_override("normal", edit_style)
	join_address_edit.add_theme_color_override("font_color", Color(0.95, 0.9, 0.8))
	join_address_edit.add_theme_color_override("font_placeholder_color", Color(0.4, 0.4, 0.45))
	join_panel.add_child(join_address_edit)

	var code_lbl = Label.new()
	code_lbl.text = "Room Code (optional — to verify):"
	code_lbl.add_theme_font_size_override("font_size", 14)
	code_lbl.add_theme_color_override("font_color", Color(0.55, 0.5, 0.6))
	code_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	join_panel.add_child(code_lbl)

	var code_style = edit_style.duplicate()
	code_style.border_color = Color(0.4, 0.5, 0.3)

	join_code_edit = LineEdit.new()
	join_code_edit.placeholder_text = "ABC123"
	join_code_edit.add_theme_font_size_override("font_size", 28)
	join_code_edit.custom_minimum_size = Vector2(220, 46)
	join_code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	join_code_edit.max_length = 6
	join_code_edit.add_theme_stylebox_override("normal", code_style)
	join_code_edit.add_theme_color_override("font_color", Color(0.4, 0.9, 0.6))
	join_code_edit.add_theme_color_override("font_placeholder_color", Color(0.3, 0.4, 0.35))
	join_panel.add_child(join_code_edit)

	join_error_label = Label.new()
	join_error_label.text = ""
	join_error_label.add_theme_font_size_override("font_size", 14)
	join_error_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	join_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	join_panel.add_child(join_error_label)

	var connect_btn = _make_button("CONNECT")
	connect_btn.pressed.connect(_on_join_connect)
	join_panel.add_child(connect_btn)

func _build_lobby_panel() -> void:
	lobby_panel = VBoxContainer.new()
	lobby_panel.set_anchors_preset(Control.PRESET_CENTER)
	lobby_panel.offset_left = -320
	lobby_panel.offset_right = 320
	lobby_panel.offset_top = -200
	lobby_panel.offset_bottom = 260
	lobby_panel.add_theme_constant_override("separation", 10)
	lobby_panel.visible = false
	canvas.add_child(lobby_panel)

	# Room code
	room_code_label = Label.new()
	room_code_label.text = "Room: ------"
	room_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	room_code_label.add_theme_font_size_override("font_size", 40)
	room_code_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.6))
	lobby_panel.add_child(room_code_label)

	# IP address hint for host
	ip_label = Label.new()
	ip_label.text = ""
	ip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ip_label.add_theme_font_size_override("font_size", 14)
	ip_label.add_theme_color_override("font_color", Color(0.55, 0.5, 0.6))
	lobby_panel.add_child(ip_label)

	# Status
	status_label = Label.new()
	status_label.text = "Waiting for players..."
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 16)
	status_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	lobby_panel.add_child(status_label)

	var sep = HSeparator.new()
	sep.add_theme_color_override("separator", Color(0.3, 0.3, 0.4, 0.5))
	lobby_panel.add_child(sep)

	# Player list header
	var header = Label.new()
	header.text = "  Player                 Character          Ready   Ping"
	header.add_theme_font_size_override("font_size", 13)
	header.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	lobby_panel.add_child(header)

	# Player rows
	player_list_container = VBoxContainer.new()
	player_list_container.add_theme_constant_override("separation", 4)
	lobby_panel.add_child(player_list_container)

	var sep2 = HSeparator.new()
	sep2.add_theme_color_override("separator", Color(0.3, 0.3, 0.4, 0.5))
	lobby_panel.add_child(sep2)

	# Local character selector row
	var char_row = HBoxContainer.new()
	char_row.alignment = BoxContainer.ALIGNMENT_CENTER
	char_row.add_theme_constant_override("separation", 12)
	lobby_panel.add_child(char_row)

	var char_lbl = Label.new()
	char_lbl.text = "Your character:"
	char_lbl.add_theme_font_size_override("font_size", 16)
	char_lbl.add_theme_color_override("font_color", Color(0.7, 0.65, 0.8))
	char_row.add_child(char_lbl)

	var prev_btn = _make_small_button("<")
	prev_btn.pressed.connect(_on_char_prev)
	char_row.add_child(prev_btn)

	_local_char_label = Label.new()
	_local_char_label.text = "Fat Nate"
	_local_char_label.add_theme_font_size_override("font_size", 20)
	_local_char_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	_local_char_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_local_char_label.custom_minimum_size = Vector2(160, 0)
	char_row.add_child(_local_char_label)

	var next_btn = _make_small_button(">")
	next_btn.pressed.connect(_on_char_next)
	char_row.add_child(next_btn)

	# Button row
	var btn_row = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 20)
	lobby_panel.add_child(btn_row)

	# Ready toggle
	ready_button = _make_button("READY", true)
	ready_button.custom_minimum_size = Vector2(200, 50)
	ready_button.pressed.connect(_on_ready_toggle)
	btn_row.add_child(ready_button)

	# Start button (host only)
	start_button = _make_button("START GAME")
	start_button.custom_minimum_size = Vector2(200, 50)
	start_button.pressed.connect(_on_start_game)
	start_button.visible = false
	btn_row.add_child(start_button)

func _show_mode(m: LobbyMode) -> void:
	mode = m
	mode_panel.visible = m == LobbyMode.CHOOSE
	join_panel.visible = m == LobbyMode.JOIN
	lobby_panel.visible = m == LobbyMode.HOST

# ── NETWORK SIGNAL WIRING ──

func _connect_network_signals() -> void:
	NetworkManager.player_connected.connect(_on_network_player_connected)
	NetworkManager.player_disconnected.connect(_on_network_player_disconnected)
	NetworkManager.player_info_updated.connect(_on_network_player_info_updated)
	NetworkManager.all_players_ready.connect(_on_network_all_ready)
	NetworkManager.connection_state_changed.connect(_on_network_state_changed)
	NetworkManager.lobby_room_code_generated.connect(_on_room_code)

func _disconnect_network_signals() -> void:
	if NetworkManager.player_connected.is_connected(_on_network_player_connected):
		NetworkManager.player_connected.disconnect(_on_network_player_connected)
	if NetworkManager.player_disconnected.is_connected(_on_network_player_disconnected):
		NetworkManager.player_disconnected.disconnect(_on_network_player_disconnected)
	if NetworkManager.player_info_updated.is_connected(_on_network_player_info_updated):
		NetworkManager.player_info_updated.disconnect(_on_network_player_info_updated)
	if NetworkManager.all_players_ready.is_connected(_on_network_all_ready):
		NetworkManager.all_players_ready.disconnect(_on_network_all_ready)
	if NetworkManager.connection_state_changed.is_connected(_on_network_state_changed):
		NetworkManager.connection_state_changed.disconnect(_on_network_state_changed)
	if NetworkManager.lobby_room_code_generated.is_connected(_on_room_code):
		NetworkManager.lobby_room_code_generated.disconnect(_on_room_code)

# ── ACTIONS ──

func _on_host() -> void:
	_local_player_name = name_edit.text.strip_edges() if name_edit else "Host"
	if _local_player_name.is_empty():
		_local_player_name = "Host"
	NetworkManager.set_player_name(_local_player_name)
	var err := NetworkManager.host_game()
	if err != OK:
		return
	_show_mode(LobbyMode.HOST)
	start_button.visible = true
	_update_start_button()
	# Show local IP addresses for players to connect
	var ips := _get_local_ips()
	if ips.is_empty():
		ip_label.text = "Share your IP address with friends (port %d)" % NetworkManager.DEFAULT_PORT
	else:
		ip_label.text = "Your IP: %s  (port %d)" % [ips[0], NetworkManager.DEFAULT_PORT]
	_refresh_player_list()

func _on_show_join() -> void:
	join_error_label.text = ""
	_show_mode(LobbyMode.JOIN)
	join_address_edit.grab_focus()

func _on_join_connect() -> void:
	var address := join_address_edit.text.strip_edges()
	if address.is_empty():
		join_error_label.text = "Enter a valid IP address"
		join_error_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		return
	_local_player_name = name_edit.text.strip_edges() if name_edit else ""
	if _local_player_name.is_empty():
		_local_player_name = "Player %d" % randi_range(1, 999)
	join_error_label.text = "Connecting to %s..." % address
	join_error_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.4))
	NetworkManager.set_player_name(_local_player_name)
	var err := NetworkManager.join_game(address)
	if err != OK:
		join_error_label.text = "Failed to connect: %s" % error_string(err)
		join_error_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))

func _on_back() -> void:
	if is_transitioning:
		return
	# Disconnect if connected
	if NetworkManager.state != NetworkManager.ConnectionState.DISCONNECTED:
		NetworkManager.disconnect_from_game()
	is_transitioning = true
	_fade_to_scene("res://scenes/main_menu.tscn")

func _on_char_prev() -> void:
	_local_char_index = (_local_char_index - 1 + CharacterData.characters.size()) % CharacterData.characters.size()
	_update_local_char()

func _on_char_next() -> void:
	_local_char_index = (_local_char_index + 1) % CharacterData.characters.size()
	_update_local_char()

func _update_local_char() -> void:
	var data = CharacterData.characters[_local_char_index]
	if _local_char_label:
		_local_char_label.text = data["name"]
	# Sync to network
	if NetworkManager.state == NetworkManager.ConnectionState.LOBBY:
		NetworkManager.set_player_character(_local_char_index, _local_spell_set)

func _on_ready_toggle() -> void:
	_local_ready = not _local_ready
	NetworkManager.set_player_ready(_local_ready)
	_update_ready_button()

func _update_ready_button() -> void:
	if ready_button:
		if _local_ready:
			ready_button.text = "READY!"
			ready_button.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
		else:
			ready_button.text = "READY"
			ready_button.add_theme_color_override("font_color", Color(0.6, 0.55, 0.65))

func _on_start_game() -> void:
	if not NetworkManager.is_host:
		return
	if not NetworkManager.are_all_players_ready():
		return
	# Set character selection for local player before starting
	CharacterData.select(CharacterData.characters[_local_char_index]["id"], _local_spell_set)
	NetworkManager.start_game()

func _update_start_button() -> void:
	if not start_button or not start_button.visible:
		return
	var all_ready := NetworkManager.are_all_players_ready()
	var enough := NetworkManager.get_player_count() >= 1
	start_button.disabled = not (all_ready and enough)
	if all_ready and enough:
		start_button.add_theme_color_override("font_color", Color(1.0, 0.9, 0.7))
	else:
		start_button.add_theme_color_override("font_color", Color(0.5, 0.45, 0.4))

# ── NETWORK CALLBACKS ──

func _on_network_player_connected(_pid: int) -> void:
	_refresh_player_list()
	_update_start_button()

func _on_network_player_disconnected(_pid: int) -> void:
	_refresh_player_list()
	_update_start_button()

func _on_network_player_info_updated(_pid: int, _info: Dictionary) -> void:
	_refresh_player_list()
	_update_start_button()

func _on_network_all_ready() -> void:
	_update_start_button()
	if status_label:
		status_label.text = "All players ready!"
		status_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))

func _on_network_state_changed(new_state: NetworkManager.ConnectionState) -> void:
	match new_state:
		NetworkManager.ConnectionState.LOBBY:
			if mode == LobbyMode.JOIN:
				# Verify room code if provided
				if join_code_edit and not join_code_edit.text.strip_edges().is_empty():
					var entered_code := join_code_edit.text.strip_edges().to_upper()
					if entered_code != NetworkManager.room_code and not NetworkManager.room_code.is_empty():
						# Room code mismatch — warn but still connect
						if status_label:
							status_label.text = "Connected (room code mismatch — expected %s)" % entered_code
							status_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
				# Successfully connected — switch to lobby view
				_show_mode(LobbyMode.HOST)
				start_button.visible = NetworkManager.is_host
				if room_code_label and not NetworkManager.room_code.is_empty():
					room_code_label.text = "Room: %s" % NetworkManager.room_code
				_update_local_char()
				_refresh_player_list()
		NetworkManager.ConnectionState.IN_GAME:
			# Game starting! Transition to character select (or dungeon)
			if not is_transitioning:
				is_transitioning = true
				# In multiplayer, go straight to dungeon (character already chosen in lobby)
				CharacterData.select(CharacterData.characters[_local_char_index]["id"], _local_spell_set)
				FloorManager.current_floor = 1
				_fade_to_scene("res://scenes/dungeon_floor1.tscn")
		NetworkManager.ConnectionState.DISCONNECTED:
			if mode != LobbyMode.CHOOSE and not is_transitioning:
				if join_error_label:
					join_error_label.text = "Disconnected from server"
					join_error_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
				_show_mode(LobbyMode.CHOOSE)

func _on_room_code(code: String) -> void:
	if room_code_label:
		room_code_label.text = "Room: %s" % code

# ── PLAYER LIST ──

func _refresh_player_list() -> void:
	if not player_list_container:
		return

	# Clear
	for child in player_list_container.get_children():
		child.queue_free()

	if status_label:
		var count := NetworkManager.get_player_count()
		status_label.text = "%d / %d players" % [count, NetworkManager.MAX_PLAYERS]
		status_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))

	# Build rows
	var my_id := NetworkManager.get_my_id()
	for pid in NetworkManager.players:
		var info: Dictionary = NetworkManager.players[pid]
		var row = Label.new()

		var name_str: String = info.get("name", "Player %d" % pid)
		if pid == my_id:
			name_str += " (you)"
		if pid == 1:
			name_str += " [HOST]"
		name_str = name_str.left(22).rpad(22)

		var char_idx: int = info.get("character_index", 0)
		var char_name := "?"
		if char_idx >= 0 and char_idx < CharacterData.characters.size():
			char_name = CharacterData.characters[char_idx]["name"]
		char_name = char_name.left(16).rpad(16)

		var ready_str := "YES" if info.get("is_ready", false) else "---"
		ready_str = ready_str.rpad(6)

		var ping_str := "%dms" % info.get("ping", 0) if pid != 1 else "host"
		ping_str = ping_str.rpad(6)

		row.text = "  %s  %s  %s  %s" % [name_str, char_name, ready_str, ping_str]
		row.add_theme_font_size_override("font_size", 16)

		var is_ready: bool = info.get("is_ready", false)
		if pid == my_id:
			row.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
		elif is_ready:
			row.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
		else:
			row.add_theme_color_override("font_color", Color(0.7, 0.65, 0.7))

		player_list_container.add_child(row)

# ── HELPERS ──

func _make_button(text: String, subdued: bool = false) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 24)
	btn.custom_minimum_size = Vector2(320, 56)

	var style_normal = StyleBoxFlat.new()
	if subdued:
		style_normal.bg_color = Color(0.12, 0.1, 0.15, 0.85)
		style_normal.border_color = Color(0.3, 0.25, 0.35, 0.5)
	else:
		style_normal.bg_color = Color(0.45, 0.3, 0.1, 0.9)
		style_normal.border_color = Color(0.75, 0.55, 0.2)
	style_normal.set_border_width_all(2)
	style_normal.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", style_normal)

	var style_hover = style_normal.duplicate()
	if subdued:
		style_hover.bg_color = Color(0.18, 0.15, 0.22, 0.9)
		style_hover.border_color = Color(0.5, 0.4, 0.55, 0.7)
	else:
		style_hover.bg_color = Color(0.6, 0.42, 0.15, 0.95)
		style_hover.border_color = Color(1.0, 0.8, 0.3)
	btn.add_theme_stylebox_override("hover", style_hover)

	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = style_normal.bg_color.darkened(0.3)
	btn.add_theme_stylebox_override("pressed", style_pressed)

	var font_color = Color(1.0, 0.9, 0.7) if not subdued else Color(0.6, 0.55, 0.65)
	btn.add_theme_color_override("font_color", font_color)
	btn.add_theme_color_override("font_hover_color", font_color.lightened(0.2))

	return btn

func _make_small_button(text: String) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 22)
	btn.custom_minimum_size = Vector2(44, 44)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.12, 0.2, 0.85)
	style.border_color = Color(0.4, 0.35, 0.5, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", style)
	var hover = style.duplicate()
	hover.bg_color = Color(0.25, 0.2, 0.3, 0.9)
	hover.border_color = Color(0.6, 0.5, 0.7)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_color_override("font_color", Color(0.8, 0.75, 0.9))
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
	tween.tween_property(overlay, "color:a", 1.0, 0.6)
	tween.tween_callback(func():
		get_tree().change_scene_to_file(scene_path)
	)

func _get_local_ips() -> Array[String]:
	var result: Array[String] = []
	for addr in IP.get_local_addresses():
		# Filter to private IPv4 addresses (skip loopback and IPv6)
		if addr.begins_with("127.") or addr.contains(":"):
			continue
		if addr.begins_with("192.168.") or addr.begins_with("10.") or addr.begins_with("172."):
			result.append(addr)
	return result

func _unhandled_input(event: InputEvent) -> void:
	if is_transitioning:
		return
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE:
				_on_back()
			KEY_ENTER:
				if mode == LobbyMode.JOIN:
					_on_join_connect()
				elif mode == LobbyMode.HOST and NetworkManager.is_host:
					_on_start_game()
