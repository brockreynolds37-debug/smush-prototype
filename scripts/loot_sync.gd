extends Node

## LootSync — multiplayer loot synchronization.
## Host spawns all loot, validates pickup claims, manages shared gold pool.
## Broadcasts 'X picked up [item]' floating text to all players.

## Shared gold pool (host-authoritative)
var _shared_gold: int = 0

func _ready() -> void:
	if not NetworkManager.is_multiplayer_active():
		return
	NetworkManager.player_picked_up_item.connect(_on_pickup_broadcast)

## Initialize shared gold pool from LootManager
func setup() -> void:
	if NetworkManager.is_host:
		_shared_gold = LootManager.gold

# ---------- LOOT PICKUP: CLIENT -> HOST -> BROADCAST ----------

## Client requests to pick up a loot drop. Host validates first-claimer.
func request_pickup(loot_node: Node, requester_id: int) -> void:
	var loot_path := str(loot_node.get_path())
	if NetworkManager.is_host:
		_host_process_pickup(requester_id, loot_path)
	else:
		rpc_id(1, "_host_validate_pickup", requester_id, loot_path)

@rpc("any_peer", "reliable")
func _host_validate_pickup(requester_id: int, loot_path: String) -> void:
	if not NetworkManager.is_host:
		return
	_host_process_pickup(requester_id, loot_path)

func _host_process_pickup(requester_id: int, loot_path: String) -> void:
	var loot_node := get_tree().root.get_node_or_null(loot_path)
	if loot_node == null or not is_instance_valid(loot_node):
		return

	# Check if already picked up
	if loot_node.get_meta("_picked_up", false):
		return

	# Mark as claimed
	loot_node.set_meta("_picked_up", true)

	# Get item data
	var item_data: Dictionary = loot_node.get_meta("item_data", {})
	if item_data.is_empty():
		return

	var item_name: String = item_data.get("name", "item")
	var player_name: String = NetworkManager.get_player_name(requester_id)

	# Handle currency: add to shared gold pool
	if item_data.get("type", "") == "currency":
		var amount := randi_range(item_data.get("gold_min", 5), item_data.get("gold_max", 25))
		_shared_gold += amount
		# Sync gold to all
		rpc("_sync_shared_gold", _shared_gold)
		# Grant locally on host too
		LootManager.gold = _shared_gold
		LootManager.gold_changed.emit(_shared_gold)
		item_name = "%d Gold" % amount
	else:
		# Grant item to the requester only
		rpc_id(requester_id, "_grant_item_to_player", item_data)
		# Also grant locally if requester is host
		if requester_id == 1:
			LootManager.pickup_item(item_data)

	# Broadcast pickup notification to all
	rpc("_broadcast_pickup_notification", player_name, item_name, item_data.get("rarity", 0))

	# Remove the loot drop from the world on all clients
	rpc("_remove_loot_drop", loot_path)

@rpc("authority", "reliable")
func _grant_item_to_player(item_data: Dictionary) -> void:
	# Client receives item from host
	LootManager.pickup_item(item_data)

@rpc("authority", "reliable")
func _sync_shared_gold(amount: int) -> void:
	_shared_gold = amount
	LootManager.gold = amount
	LootManager.gold_changed.emit(amount)

@rpc("authority", "reliable")
func _broadcast_pickup_notification(player_name: String, item_name: String, rarity: int) -> void:
	# Show floating text: "PlayerName picked up [ItemName]"
	var color: Color = LootManager.RARITY_COLORS.get(rarity, Color.WHITE)
	var msg := "%s picked up %s" % [player_name, item_name]
	# Route to HUD loot feed
	var hud := get_tree().current_scene.get_node_or_null("HUD")
	if hud and hud.has_method("_on_item_picked_up"):
		hud._on_item_picked_up({"name": msg, "rarity": rarity})

@rpc("authority", "reliable")
func _remove_loot_drop(loot_path: String) -> void:
	var loot_node := get_tree().root.get_node_or_null(loot_path)
	if loot_node and is_instance_valid(loot_node):
		loot_node.queue_free()

# ---------- LOOT SPAWNING (HOST ONLY) ----------

## Host spawns a loot drop and notifies all clients
func host_spawn_loot(world_pos: Vector3, item_data: Dictionary) -> void:
	if not NetworkManager.is_host:
		return
	# Spawn locally (host)
	LootManager._spawn_drop(world_pos, item_data)
	# Tell clients to spawn same drop
	rpc("_client_spawn_loot", world_pos, item_data)

@rpc("authority", "reliable")
func _client_spawn_loot(world_pos: Vector3, item_data: Dictionary) -> void:
	# Client spawns a visual loot drop
	LootManager._spawn_drop(world_pos, item_data)

# ---------- CALLBACK ----------

func _on_pickup_broadcast(peer_id: int, item_name: String) -> void:
	# NetworkManager's built-in pickup notification
	var player_name := NetworkManager.get_player_name(peer_id)
	print("LootSync: %s picked up %s" % [player_name, item_name])

## Get current shared gold pool
func get_shared_gold() -> int:
	return _shared_gold
