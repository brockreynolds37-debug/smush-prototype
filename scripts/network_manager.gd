extends Node

## NetworkManager — autoload singleton for multiplayer networking.
## Uses ENetMultiplayerPeer for host-authoritative co-op (max 4 players).
##
## Connection state machine:
##   Disconnected -> Connecting -> Lobby -> InGame -> Disconnected
##
## Host runs game logic, spawns enemies, manages floor state.
## Clients send inputs, receive state.

signal connection_state_changed(new_state: ConnectionState)
signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal player_info_updated(peer_id: int, info: Dictionary)
signal all_players_ready()
signal chat_message_received(sender_id: int, message: String)
signal ping_received(sender_id: int, position: Vector3)
signal player_picked_up_item(peer_id: int, item_name: String)
signal floor_transition_player_ready(peer_id: int)
signal lobby_room_code_generated(code: String)

enum ConnectionState {
	DISCONNECTED,
	CONNECTING,
	LOBBY,
	IN_GAME,
}

const MAX_PLAYERS := 4
const DEFAULT_PORT := 7777
const ROOM_CODE_LENGTH := 6

## Current connection state
var state: ConnectionState = ConnectionState.DISCONNECTED

## Peer object (ENet)
var peer: ENetMultiplayerPeer = null

## Player data: peer_id -> { name, character_index, spell_set, is_ready, ping }
var players: Dictionary = {}

## Local player info
var local_player_name: String = "Player"
var local_character_index: int = 0
var local_spell_set: int = 0

## Room code for lobby
var room_code: String = ""

## Host tracking
var is_host: bool = false

## Ping tracking
var _ping_send_time: float = 0.0
var _ping_interval: float = 2.0
var _ping_timer: float = 0.0

## Reconnection
var _reconnect_timer: float = 0.0
var _reconnect_timeout: float = 30.0
var _reconnecting_peer_id: int = -1
var _disconnected_players: Dictionary = {}  # peer_id -> { info, disconnect_time }

## Gold mode
var shared_gold: bool = true  # true = shared gold pool, false = per-player

## Friendly fire
var friendly_fire_enabled: bool = false

## Floor transition tracking
var _floor_ready_players: Dictionary = {}  # peer_id -> bool

## Net stats
var _net_stats_visible: bool = false
var _packets_sent: int = 0
var _packets_received: int = 0

func _ready() -> void:
	# These callbacks fire on both host and clients
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _process(delta: float) -> void:
	if state != ConnectionState.IN_GAME and state != ConnectionState.LOBBY:
		return

	# Ping measurement
	if is_host and multiplayer.has_multiplayer_peer():
		_ping_timer += delta
		if _ping_timer >= _ping_interval:
			_ping_timer = 0.0
			_broadcast_ping_request()

	# Reconnection timeout check
	var to_remove: Array[int] = []
	for pid in _disconnected_players:
		var info: Dictionary = _disconnected_players[pid]
		var elapsed: float = Time.get_ticks_msec() / 1000.0 - info.get("disconnect_time", 0.0)
		if elapsed > _reconnect_timeout:
			to_remove.append(pid)
	for pid in to_remove:
		_disconnected_players.erase(pid)
		# AI takeover or loot pinata could be triggered here

# ---------- HOST ----------

func host_game(port: int = DEFAULT_PORT) -> Error:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		push_error("NetworkManager: Failed to create server on port %d: %s" % [port, error_string(err)])
		state = ConnectionState.DISCONNECTED
		connection_state_changed.emit(state)
		return err

	multiplayer.multiplayer_peer = peer
	is_host = true

	# Generate room code
	room_code = _generate_room_code()
	lobby_room_code_generated.emit(room_code)

	# Register host as player 1
	var host_id := multiplayer.get_unique_id()
	players[host_id] = {
		"name": local_player_name,
		"character_index": local_character_index,
		"spell_set": local_spell_set,
		"is_ready": false,
		"ping": 0,
	}

	state = ConnectionState.LOBBY
	connection_state_changed.emit(state)
	player_connected.emit(host_id)

	print("NetworkManager: Hosting on port %d | Room code: %s" % [port, room_code])
	return OK

# ---------- CLIENT ----------

func join_game(address: String, port: int = DEFAULT_PORT) -> Error:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		push_error("NetworkManager: Failed to connect to %s:%d: %s" % [address, port, error_string(err)])
		state = ConnectionState.DISCONNECTED
		connection_state_changed.emit(state)
		return err

	multiplayer.multiplayer_peer = peer
	is_host = false

	state = ConnectionState.CONNECTING
	connection_state_changed.emit(state)

	print("NetworkManager: Connecting to %s:%d..." % [address, port])
	return OK

# ---------- DISCONNECT ----------

func disconnect_from_game() -> void:
	if peer:
		peer.close()
		peer = null
	multiplayer.multiplayer_peer = null
	players.clear()
	_disconnected_players.clear()
	_floor_ready_players.clear()
	is_host = false
	room_code = ""
	state = ConnectionState.DISCONNECTED
	connection_state_changed.emit(state)
	print("NetworkManager: Disconnected.")

# ---------- LOBBY ----------

func set_player_ready(is_ready: bool) -> void:
	var my_id := multiplayer.get_unique_id()
	if players.has(my_id):
		players[my_id]["is_ready"] = is_ready
	rpc("_sync_player_ready", my_id, is_ready)

func set_player_character(char_index: int, spell_set: int) -> void:
	local_character_index = char_index
	local_spell_set = spell_set
	var my_id := multiplayer.get_unique_id()
	if players.has(my_id):
		players[my_id]["character_index"] = char_index
		players[my_id]["spell_set"] = spell_set
	rpc("_sync_player_character", my_id, char_index, spell_set)

func set_player_name(player_name: String) -> void:
	local_player_name = player_name
	var my_id := multiplayer.get_unique_id()
	if players.has(my_id):
		players[my_id]["name"] = player_name
	rpc("_sync_player_name", my_id, player_name)

func start_game() -> void:
	if not is_host:
		return
	# Verify all players are ready
	for pid in players:
		if not players[pid].get("is_ready", false):
			return  # Not everyone is ready
	rpc("_on_game_start")

func are_all_players_ready() -> bool:
	if players.is_empty():
		return false
	for pid in players:
		if not players[pid].get("is_ready", false):
			return false
	return true

func get_player_count() -> int:
	return players.size()

func is_multiplayer_active() -> bool:
	return state == ConnectionState.IN_GAME or state == ConnectionState.LOBBY

func is_server() -> bool:
	return is_host and multiplayer.has_multiplayer_peer()

func get_my_id() -> int:
	if multiplayer.has_multiplayer_peer():
		return multiplayer.get_unique_id()
	return 1  # Default for singleplayer

# ---------- IN-GAME RPCs ----------

## Send chat message to all players
func send_chat_message(message: String) -> void:
	var sender_id := multiplayer.get_unique_id()
	rpc("_receive_chat_message", sender_id, message)

## Send ping at a world position (visible on minimap)
func send_ping(world_position: Vector3) -> void:
	var sender_id := multiplayer.get_unique_id()
	rpc("_receive_ping", sender_id, world_position)

## Send quick callout
func send_callout(callout: String) -> void:
	send_chat_message("[CALLOUT] %s" % callout)

## Notify host that a player is at the exit portal
func notify_floor_ready() -> void:
	var my_id := multiplayer.get_unique_id()
	rpc("_on_floor_ready_player", my_id)

## Request to pick up loot (client -> host)
func request_loot_pickup(loot_node_path: String) -> void:
	rpc_id(1, "_host_validate_loot_pickup", multiplayer.get_unique_id(), loot_node_path)

## Send damage event to host for validation
func request_damage(target_path: String, amount: int, source_id: int) -> void:
	rpc_id(1, "_host_validate_damage", target_path, amount, source_id)

## Transition to in-game state
func enter_game_state() -> void:
	state = ConnectionState.IN_GAME
	connection_state_changed.emit(state)

# ---------- FLOOR TRANSITION SYNC ----------

func reset_floor_ready() -> void:
	_floor_ready_players.clear()

func get_floor_ready_count() -> int:
	return _floor_ready_players.size()

func are_all_players_at_exit() -> bool:
	for pid in players:
		if not _floor_ready_players.has(pid):
			return false
	return true

# ---------- HOST MIGRATION ----------

func _attempt_host_migration() -> void:
	if is_host:
		return  # We are the host, nothing to migrate

	# Find the connected peer with the lowest ping
	var best_pid: int = -1
	var best_ping: float = 9999.0
	for pid in players:
		var ping: float = players[pid].get("ping", 9999.0)
		if ping < best_ping:
			best_ping = ping
			best_pid = pid

	# If we are the best candidate, become host
	var my_id := multiplayer.get_unique_id()
	if best_pid == my_id:
		print("NetworkManager: Becoming new host (migration)")
		is_host = true
		# In practice, full host migration requires restarting the ENet server
		# which is complex. For now, we mark ourselves as authoritative.

# ---------- NET STATS ----------

func get_net_stats() -> Dictionary:
	var stats := {
		"state": ConnectionState.keys()[state],
		"player_count": players.size(),
		"is_host": is_host,
		"packets_sent": _packets_sent,
		"packets_received": _packets_received,
	}
	# Add per-player pings
	for pid in players:
		stats["ping_%d" % pid] = players[pid].get("ping", -1)
	return stats

# ---------- CALLBACKS ----------

func _on_peer_connected(id: int) -> void:
	print("NetworkManager: Peer connected: %d" % id)
	if is_host:
		# Send existing player data to the new peer
		for pid in players:
			rpc_id(id, "_sync_player_info", pid, players[pid])
		# Send room code to new peer
		if room_code != "":
			rpc_id(id, "_sync_room_code", room_code)

	# Add placeholder entry
	if not players.has(id):
		players[id] = {
			"name": "Player %d" % id,
			"character_index": 0,
			"spell_set": 0,
			"is_ready": false,
			"ping": 0,
		}
	player_connected.emit(id)

func _on_peer_disconnected(id: int) -> void:
	print("NetworkManager: Peer disconnected: %d" % id)
	if players.has(id):
		_disconnected_players[id] = {
			"info": players[id].duplicate(),
			"disconnect_time": Time.get_ticks_msec() / 1000.0,
		}
		players.erase(id)
	_floor_ready_players.erase(id)
	player_disconnected.emit(id)

	# If host disconnected, attempt migration
	if id == 1 and not is_host:
		_attempt_host_migration()

func _on_connected_to_server() -> void:
	print("NetworkManager: Connected to server!")
	var my_id := multiplayer.get_unique_id()
	players[my_id] = {
		"name": local_player_name,
		"character_index": local_character_index,
		"spell_set": local_spell_set,
		"is_ready": false,
		"ping": 0,
	}
	state = ConnectionState.LOBBY
	connection_state_changed.emit(state)
	player_connected.emit(my_id)

	# Send our info to the host
	rpc("_sync_player_info", my_id, players[my_id])

func _on_connection_failed() -> void:
	print("NetworkManager: Connection failed!")
	state = ConnectionState.DISCONNECTED
	connection_state_changed.emit(state)

func _on_server_disconnected() -> void:
	print("NetworkManager: Server disconnected!")
	# Delegate to stability system for robust host migration
	var stability = get_tree().current_scene.get_node_or_null("MultiplayerStability")
	if stability and stability.has_method("attempt_host_migration"):
		stability.attempt_host_migration()
	else:
		_attempt_host_migration()
		if not is_host:
			disconnect_from_game()

# ---------- SYNCED RPCs ----------

@rpc("any_peer", "reliable")
func _sync_player_info(pid: int, info: Dictionary) -> void:
	players[pid] = info
	player_info_updated.emit(pid, info)

@rpc("any_peer", "reliable")
func _sync_player_ready(pid: int, is_ready: bool) -> void:
	if players.has(pid):
		players[pid]["is_ready"] = is_ready
		player_info_updated.emit(pid, players[pid])

	# Check if all ready
	if is_host and are_all_players_ready():
		all_players_ready.emit()

@rpc("any_peer", "reliable")
func _sync_player_character(pid: int, char_index: int, spell_set: int) -> void:
	if players.has(pid):
		players[pid]["character_index"] = char_index
		players[pid]["spell_set"] = spell_set
		player_info_updated.emit(pid, players[pid])

@rpc("any_peer", "reliable")
func _sync_player_name(pid: int, player_name: String) -> void:
	if players.has(pid):
		players[pid]["name"] = player_name
		player_info_updated.emit(pid, players[pid])

@rpc("authority", "reliable")
func _sync_room_code(code: String) -> void:
	room_code = code
	lobby_room_code_generated.emit(code)

@rpc("authority", "reliable")
func _on_game_start() -> void:
	state = ConnectionState.IN_GAME
	connection_state_changed.emit(state)

@rpc("any_peer", "reliable")
func _receive_chat_message(sender_id: int, message: String) -> void:
	_packets_received += 1
	chat_message_received.emit(sender_id, message)

@rpc("any_peer", "unreliable")
func _receive_ping(sender_id: int, world_position: Vector3) -> void:
	_packets_received += 1
	ping_received.emit(sender_id, world_position)

@rpc("any_peer", "reliable")
func _on_floor_ready_player(pid: int) -> void:
	_floor_ready_players[pid] = true
	floor_transition_player_ready.emit(pid)

	# Check if all at exit
	if is_host and are_all_players_at_exit():
		rpc("_trigger_floor_transition")

@rpc("authority", "reliable")
func _trigger_floor_transition() -> void:
	# All players at exit — transition to next floor
	FloorManager.go_to_next_floor()
	reset_floor_ready()

@rpc("any_peer", "reliable")
func _host_validate_loot_pickup(requester_id: int, loot_path: String) -> void:
	if not is_host:
		return
	# Host validates and grants the pickup
	var loot_node = get_tree().root.get_node_or_null(loot_path)
	if loot_node and is_instance_valid(loot_node) and loot_node.has_method("_pickup"):
		if not loot_node._picked_up:
			# Grant to requester
			loot_node._pickup()
			var item_name: String = loot_node.item_data.get("name", "item")
			rpc("_notify_loot_picked_up", requester_id, item_name)

@rpc("authority", "reliable")
func _notify_loot_picked_up(picker_id: int, item_name: String) -> void:
	player_picked_up_item.emit(picker_id, item_name)

@rpc("any_peer", "reliable")
func _host_validate_damage(target_path: String, amount: int, source_id: int) -> void:
	if not is_host:
		return
	var target = get_tree().root.get_node_or_null(target_path)
	if target and is_instance_valid(target) and target.has_method("take_damage"):
		target.take_damage(amount)

# ---------- PING SYSTEM ----------

func _broadcast_ping_request() -> void:
	if not is_host:
		return
	_ping_send_time = Time.get_ticks_msec() / 1000.0
	rpc("_ping_request")

@rpc("authority", "unreliable")
func _ping_request() -> void:
	rpc_id(1, "_ping_response", multiplayer.get_unique_id())

@rpc("any_peer", "unreliable")
func _ping_response(pid: int) -> void:
	if not is_host:
		return
	var rtt := (Time.get_ticks_msec() / 1000.0 - _ping_send_time) * 1000.0
	if players.has(pid):
		players[pid]["ping"] = int(rtt)

# ---------- UTILITIES ----------

func _generate_room_code() -> String:
	var chars := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # Exclude confusing chars (I, O, 0, 1)
	var code := ""
	for i in range(ROOM_CODE_LENGTH):
		code += chars[randi() % chars.length()]
	return code

## Get the display name for a peer
func get_player_name(peer_id: int) -> String:
	if players.has(peer_id):
		return players[peer_id].get("name", "Player %d" % peer_id)
	return "Player %d" % peer_id

## Check if a given peer is still connected
func is_peer_connected(peer_id: int) -> bool:
	return players.has(peer_id)

## Get all connected peer IDs
func get_peer_ids() -> Array:
	return players.keys()

## Quick callout presets
const CALLOUTS := {
	"help": "Help!",
	"here": "Over here!",
	"run": "Run!",
	"boss": "Boss incoming!",
	"loot": "Loot here!",
	"wait": "Wait for me!",
}
