extends Node

## MultiplayerStability — disconnect handler, host migration, netstat HUD,
## and graceful solo fallback.
##
## Disconnect handler: 30s reconnect window, disconnected hero goes AI idle,
## notification banner. If timeout expires, hero drops loot and despawns.
##
## Host migration: when host disconnects, lowest-ID remaining player becomes
## new host. Re-creates ENet server, notifies remaining players.
##
## Netstat HUD: toggle with F3 — shows ping, packet counts, player states,
## connection quality indicator (green/yellow/red).
##
## Solo fallback: if all other players disconnect, switch to singleplayer mode
## seamlessly (disable MP sync, hero keeps all state).

signal player_reconnected(peer_id: int)
signal solo_mode_activated
signal host_migrated(new_host_id: int)

const RECONNECT_TIMEOUT := 30.0
const AI_IDLE_MOVE_RANGE := 3.0  # Idle AI wanders within this radius
const NETSTAT_UPDATE_INTERVAL := 0.5

## Disconnected hero tracking: peer_id -> { hero, idle_center, timer, notif_label }
var _dc_heroes: Dictionary = {}

## Netstat state
var _netstat_visible: bool = false
var _netstat_overlay: CanvasLayer = null
var _netstat_label: Label = null
var _netstat_timer: float = 0.0

## Solo fallback
var _solo_mode: bool = false

## Notification banner
var _banner_label: Label = null
var _banner_timer: float = 0.0

## Reference
var _player_spawner: Node = null

func _ready() -> void:
	if not NetworkManager.is_multiplayer_active():
		return
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.player_connected.connect(_on_player_reconnected)
	_create_banner()

func setup(player_spawner: Node) -> void:
	_player_spawner = player_spawner

func _process(delta: float) -> void:
	if not NetworkManager.is_multiplayer_active() and not _solo_mode:
		return

	_update_disconnected_heroes(delta)
	_update_banner(delta)

	if _netstat_visible:
		_netstat_timer += delta
		if _netstat_timer >= NETSTAT_UPDATE_INTERVAL:
			_netstat_timer = 0.0
			_refresh_netstat()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		_toggle_netstat()

# ---------- DISCONNECT HANDLER ----------

func _on_player_disconnected(peer_id: int) -> void:
	if _player_spawner == null:
		return

	var hero: Node3D = _player_spawner.player_heroes.get(peer_id, null)
	if hero == null or not is_instance_valid(hero):
		return

	# Don't despawn immediately — keep the hero in idle AI mode
	_dc_heroes[peer_id] = {
		"hero": hero,
		"idle_center": hero.global_position,
		"timer": RECONNECT_TIMEOUT,
		"idle_angle": randf() * TAU,
	}

	# Show disconnect notification
	var player_name := NetworkManager.get_player_name(peer_id)
	_show_banner("%s disconnected — waiting %.0fs for reconnect..." % [player_name, RECONNECT_TIMEOUT], Color(1.0, 0.6, 0.2))

	# Disable hero input processing but keep it in the scene
	hero.set_meta("mp_disconnected", true)

	# Check if we should go solo
	_check_solo_fallback()

func _on_player_reconnected(peer_id: int) -> void:
	if not _dc_heroes.has(peer_id):
		return

	var entry: Dictionary = _dc_heroes[peer_id]
	var hero: Node3D = entry.get("hero", null)
	if hero and is_instance_valid(hero):
		hero.remove_meta("mp_disconnected")

	_dc_heroes.erase(peer_id)

	var player_name := NetworkManager.get_player_name(peer_id)
	_show_banner("%s reconnected!" % player_name, Color(0.3, 1.0, 0.4))
	player_reconnected.emit(peer_id)

	# Exit solo mode if we were in it
	if _solo_mode and NetworkManager.get_player_count() > 1:
		_solo_mode = false

func _update_disconnected_heroes(delta: float) -> void:
	var expired: Array[int] = []

	for pid in _dc_heroes:
		var entry: Dictionary = _dc_heroes[pid]
		entry["timer"] -= delta
		var hero: Node3D = entry.get("hero", null)

		if hero == null or not is_instance_valid(hero):
			expired.append(pid)
			continue

		# Idle AI: wander slowly near disconnect position (host only)
		if NetworkManager.is_host and not hero.is_dead:
			var center: Vector3 = entry.get("idle_center", hero.global_position)
			var angle: float = entry.get("idle_angle", 0.0) + delta * 0.5
			entry["idle_angle"] = angle
			var target = center + Vector3(cos(angle) * AI_IDLE_MOVE_RANGE, 0, sin(angle) * AI_IDLE_MOVE_RANGE)
			var dir = (target - hero.global_position).normalized()
			dir.y = 0
			hero.velocity = dir * 1.5
			hero.move_and_slide()

		# Check timeout
		if entry["timer"] <= 0:
			expired.append(pid)

	for pid in expired:
		_on_reconnect_timeout(pid)

func _on_reconnect_timeout(peer_id: int) -> void:
	var entry: Dictionary = _dc_heroes.get(peer_id, {})
	var hero: Node3D = entry.get("hero", null)

	if hero and is_instance_valid(hero) and not hero.is_dead:
		# Drop a loot pinata at their position
		if NetworkManager.is_host:
			_drop_disconnect_loot(hero)

		# Despawn the hero
		hero.queue_free()

	_dc_heroes.erase(peer_id)
	if _player_spawner and _player_spawner.player_heroes.has(peer_id):
		_player_spawner.player_heroes.erase(peer_id)

	var player_name := NetworkManager.get_player_name(peer_id)
	_show_banner("%s timed out — hero removed." % player_name, Color(1.0, 0.3, 0.3))

	_check_solo_fallback()

func _drop_disconnect_loot(hero: Node3D) -> void:
	# Drop some gold at disconnect position as consolation
	var gold_amount := 20 + FloorManager.current_floor * 10
	LootManager.gold += gold_amount
	LootManager.gold_changed.emit(LootManager.gold)

# ---------- HOST MIGRATION ----------

## Attempt to become the new host when the original host disconnects.
## Uses lowest connected peer ID as the deterministic pick.
func attempt_host_migration() -> void:
	if NetworkManager.is_host:
		return  # Already host

	# Find the lowest remaining peer ID (deterministic pick)
	var my_id := NetworkManager.get_my_id()
	var lowest_id := my_id
	for pid in NetworkManager.players:
		if pid < lowest_id:
			lowest_id = pid

	if lowest_id == my_id:
		# We become the new host
		NetworkManager.is_host = true
		_show_banner("Host disconnected — you are now the host.", Color(1.0, 0.85, 0.3))
		host_migrated.emit(my_id)

		# Re-enable host-side systems
		_enable_host_systems()
	else:
		_show_banner("Host disconnected — migrating to Player %d..." % lowest_id, Color(1.0, 0.85, 0.3))

func _enable_host_systems() -> void:
	# Re-enable enemy AI processing on this client (now host)
	var units := get_tree().current_scene.get_node_or_null("Units")
	if units:
		for child in units.get_children():
			if child.name.begins_with("Hero"):
				continue
			# Re-enable physics process for enemies
			child.set_physics_process(true)

# ---------- NETSTAT HUD ----------

func _toggle_netstat() -> void:
	_netstat_visible = not _netstat_visible

	if _netstat_visible:
		if _netstat_overlay == null:
			_create_netstat_overlay()
		_netstat_overlay.visible = true
		_refresh_netstat()
	elif _netstat_overlay:
		_netstat_overlay.visible = false

func _create_netstat_overlay() -> void:
	_netstat_overlay = CanvasLayer.new()
	_netstat_overlay.layer = 90
	_netstat_overlay.name = "NetstatOverlay"

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -280
	panel.offset_right = -10
	panel.offset_top = 10
	panel.offset_bottom = 200

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.75)
	style.border_color = Color(0.3, 0.8, 0.3, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)

	_netstat_label = Label.new()
	_netstat_label.name = "NetstatLabel"
	_netstat_label.add_theme_font_size_override("font_size", 12)
	_netstat_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
	panel.add_child(_netstat_label)

	_netstat_overlay.add_child(panel)
	add_child(_netstat_overlay)

func _refresh_netstat() -> void:
	if _netstat_label == null:
		return

	var stats := NetworkManager.get_net_stats()
	var lines: Array[String] = []

	lines.append("=== NETSTAT (F3) ===")
	lines.append("State: %s" % stats.get("state", "?"))
	lines.append("Role: %s" % ("HOST" if stats.get("is_host", false) else "CLIENT"))
	lines.append("Players: %d / %d" % [stats.get("player_count", 0), NetworkManager.MAX_PLAYERS])
	lines.append("Pkts Sent: %d | Recv: %d" % [stats.get("packets_sent", 0), stats.get("packets_received", 0)])
	lines.append("")

	# Per-player ping
	for pid in NetworkManager.players:
		var ping: int = NetworkManager.players[pid].get("ping", -1)
		var name: String = NetworkManager.players[pid].get("name", "?")
		var quality := _ping_quality(ping)
		var dc_tag := ""
		if _dc_heroes.has(pid):
			var remaining: float = _dc_heroes[pid].get("timer", 0.0)
			dc_tag = " [DC %.0fs]" % remaining
		lines.append("%s: %dms %s%s" % [name, ping, quality, dc_tag])

	# Solo mode indicator
	if _solo_mode:
		lines.append("")
		lines.append("!! SOLO FALLBACK ACTIVE !!")

	# Disconnected players waiting
	if not _dc_heroes.is_empty():
		lines.append("")
		lines.append("Disconnected (%d):" % _dc_heroes.size())
		for pid in _dc_heroes:
			var remaining: float = _dc_heroes[pid].get("timer", 0.0)
			lines.append("  PID %d — %.0fs remaining" % [pid, remaining])

	_netstat_label.text = "\n".join(lines)

func _ping_quality(ping: int) -> String:
	if ping < 0:
		return "[?]"
	elif ping < 60:
		return "[OK]"
	elif ping < 120:
		return "[~]"
	else:
		return "[!!]"

# ---------- SOLO FALLBACK ----------

func _check_solo_fallback() -> void:
	if _solo_mode:
		return

	# Count actually connected players (excluding disconnected ones)
	var connected := 0
	for pid in NetworkManager.players:
		if not _dc_heroes.has(pid):
			connected += 1

	# If only the local player remains and all DCs have timed out
	if connected <= 1 and _dc_heroes.is_empty():
		_activate_solo_mode()

func _activate_solo_mode() -> void:
	_solo_mode = true
	_show_banner("All other players left — continuing solo.", Color(0.8, 0.8, 0.3))

	# Ensure the local hero is registered with GameManager for singleplayer systems
	if _player_spawner:
		var my_hero: Node3D = _player_spawner.get_local_hero()
		if my_hero and is_instance_valid(my_hero):
			GameManager.register_hero(my_hero)

	# Re-enable enemy AI locally (was disabled for clients)
	if not NetworkManager.is_host:
		_enable_host_systems()
		NetworkManager.is_host = true

	solo_mode_activated.emit()

func is_solo_mode() -> bool:
	return _solo_mode

# ---------- NOTIFICATION BANNER ----------

func _create_banner() -> void:
	_banner_label = Label.new()
	_banner_label.name = "StabilityBanner"
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_banner_label.offset_top = 50
	_banner_label.offset_bottom = 80
	_banner_label.add_theme_font_size_override("font_size", 18)
	_banner_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_banner_label.add_theme_constant_override("shadow_offset_x", 2)
	_banner_label.add_theme_constant_override("shadow_offset_y", 2)
	_banner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_label.visible = false

	# Wrap in a CanvasLayer so it draws on top
	var canvas := CanvasLayer.new()
	canvas.layer = 85
	canvas.name = "StabilityBannerLayer"
	canvas.add_child(_banner_label)
	add_child(canvas)

func _show_banner(text: String, color: Color) -> void:
	if _banner_label == null:
		return
	_banner_label.text = text
	_banner_label.add_theme_color_override("font_color", color)
	_banner_label.visible = true
	_banner_timer = 5.0

func _update_banner(delta: float) -> void:
	if _banner_label == null or not _banner_label.visible:
		return
	_banner_timer -= delta
	if _banner_timer <= 0:
		_banner_label.visible = false
	elif _banner_timer < 1.0:
		# Fade out
		_banner_label.modulate.a = _banner_timer
	else:
		_banner_label.modulate.a = 1.0
