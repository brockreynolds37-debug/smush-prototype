extends Node

## FloorTransitionSync — multiplayer floor transition coordination.
## Exit portal shows '[X]/[N] ready' HUD. Host triggers floor load when all
## alive players are ready. Dead players become spectators following a living player.

signal all_players_ready_for_exit
signal spectate_target_changed(target: Node3D)

## Players at exit portal: peer_id -> true
var _ready_at_exit: Dictionary = {}

## Spectator state
var _is_spectating: bool = false
var _spectate_target: Node3D = null
var _spectate_index: int = 0

## HUD label for exit portal readiness
var _exit_hud_label: Label = null

func _ready() -> void:
	if not NetworkManager.is_multiplayer_active():
		return
	NetworkManager.floor_transition_player_ready.connect(_on_floor_ready)
	FloorManager.floor_changed.connect(_on_floor_changed)

func _process(_delta: float) -> void:
	if not NetworkManager.is_multiplayer_active():
		return
	_update_exit_hud()
	_update_spectator_camera()

# ---------- EXIT PORTAL READINESS ----------

## Called when local player reaches the exit portal
func notify_local_at_exit() -> void:
	NetworkManager.notify_floor_ready()
	_update_exit_hud()

func _on_floor_ready(pid: int) -> void:
	_ready_at_exit[pid] = true
	_update_exit_hud()

	# Host checks if all alive players are ready
	if NetworkManager.is_host:
		if _are_all_alive_at_exit():
			all_players_ready_for_exit.emit()

func _are_all_alive_at_exit() -> bool:
	var spawner := get_tree().current_scene.get_node_or_null("PlayerSpawner")
	if spawner == null:
		return NetworkManager.are_all_players_at_exit()

	for pid in NetworkManager.players:
		var hero: Node3D = spawner.get_player_hero(pid)
		if hero and is_instance_valid(hero) and not hero.is_dead:
			# Alive player must be at exit
			if not _ready_at_exit.has(pid):
				return false
	return true

func get_ready_count() -> int:
	return _ready_at_exit.size()

func get_alive_count() -> int:
	var spawner := get_tree().current_scene.get_node_or_null("PlayerSpawner")
	if spawner and spawner.has_method("get_alive_count"):
		return spawner.get_alive_count()
	return NetworkManager.get_player_count()

func _on_floor_changed(_floor_num: int) -> void:
	_ready_at_exit.clear()
	_is_spectating = false
	_spectate_target = null
	NetworkManager.reset_floor_ready()
	_update_exit_hud()

# ---------- EXIT HUD ----------

func setup_exit_hud(parent: CanvasLayer) -> void:
	_exit_hud_label = Label.new()
	_exit_hud_label.text = ""
	_exit_hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_exit_hud_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_exit_hud_label.offset_top = 200
	_exit_hud_label.offset_bottom = 240
	_exit_hud_label.add_theme_font_size_override("font_size", 24)
	_exit_hud_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.6))
	_exit_hud_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_exit_hud_label.add_theme_constant_override("shadow_offset_x", 2)
	_exit_hud_label.add_theme_constant_override("shadow_offset_y", 2)
	_exit_hud_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_exit_hud_label.visible = false
	parent.add_child(_exit_hud_label)

func _update_exit_hud() -> void:
	if _exit_hud_label == null:
		return
	var ready := get_ready_count()
	var alive := get_alive_count()
	if ready > 0:
		_exit_hud_label.visible = true
		_exit_hud_label.text = "Exit: %d/%d ready" % [ready, alive]
		if ready >= alive:
			_exit_hud_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
		else:
			_exit_hud_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.6))
	else:
		_exit_hud_label.visible = false

# ---------- SPECTATOR MODE ----------

## Enter spectator mode (called when local player dies)
func enter_spectator_mode() -> void:
	_is_spectating = true
	_cycle_spectate_target(1)

## Cycle to next/previous living player to spectate
func _cycle_spectate_target(direction: int) -> void:
	var spawner := get_tree().current_scene.get_node_or_null("PlayerSpawner")
	if spawner == null:
		return

	var alive_heroes: Array = spawner.get_alive_heroes()
	if alive_heroes.is_empty():
		_spectate_target = null
		return

	_spectate_index = (_spectate_index + direction + alive_heroes.size()) % alive_heroes.size()
	_spectate_target = alive_heroes[_spectate_index]
	spectate_target_changed.emit(_spectate_target)

func _update_spectator_camera() -> void:
	if not _is_spectating:
		return
	if _spectate_target == null or not is_instance_valid(_spectate_target):
		_cycle_spectate_target(1)
		return

	# Move camera to follow spectate target
	var camera_rig := get_tree().current_scene.get_node_or_null("CameraRig")
	if camera_rig and camera_rig.has_method("set_follow_target"):
		camera_rig.set_follow_target(_spectate_target)
	elif camera_rig:
		# Fallback: directly set the target the camera follows
		if "target" in camera_rig:
			camera_rig.target = _spectate_target

func is_spectating() -> bool:
	return _is_spectating

func _unhandled_input(event: InputEvent) -> void:
	if not _is_spectating:
		return
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_LEFT, KEY_A:
				_cycle_spectate_target(-1)
			KEY_RIGHT, KEY_D:
				_cycle_spectate_target(1)
