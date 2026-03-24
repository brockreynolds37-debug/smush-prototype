extends FloorArchetype

## EconomyArchetype — trade floor. NPCs buy/sell at fluctuating prices.
## Goal: earn enough gold to buy the exit key from the Merchant King.
## Prices inflate every 60 seconds. Can steal (guards react). Can gamble.
## Life of a Peasant energy — you're just a broke adventurer trying to survive.

class_name EconomyArchetype

const EXIT_KEY_BASE_PRICE := 120
const PRICE_INFLATE_INTERVAL := 60.0
const PRICE_INFLATE_RATE := 0.15  # 15% inflation per cycle
const STEAL_DETECTION_RADIUS := 5.0
const GUARD_COUNT := 3
const GAMBLE_COST := 10
const GAMBLE_MIN_WIN := 5
const GAMBLE_MAX_WIN := 50

var _hero_gold: int = 30  # Starting gold for the floor
var _exit_key_price: int = EXIT_KEY_BASE_PRICE
var _price_timer: float = 0.0
var _price_cycle: int = 0
var _has_exit_key: bool = false
var _npcs: Array[Node3D] = []
var _guards: Array[Node3D] = []
var _exit_portal: Node3D = null
var _hud_overlay: Control = null
var _merchant_king: Node3D = null

# NPC shop definitions
var _shops: Array[Dictionary] = []

func _init() -> void:
	archetype_name = "Economy"
	flavor_text = "Buy low. Sell high. Or just steal everything."
	accent_color = Color(1.0, 0.85, 0.2)
	solution_paths = {"combat": true, "speed": true, "social": true, "clever": true}
	audience_favorite_path = "social"

func setup(p_builder: Node3D, p_units_node: Node3D, p_floor_number: int) -> void:
	super.setup(p_builder, p_units_node, p_floor_number)

func _register_solution_paths() -> void:
	SolutionPathTracker.register_floor_paths(
		SolutionPathTracker.paths_economy(), "social"
	)

func start() -> void:
	super.start()
	# Scale starting gold and key price with floor
	_hero_gold = 30 + floor_number * 10
	_exit_key_price = EXIT_KEY_BASE_PRICE + floor_number * 40
	_price_timer = 0.0
	_price_cycle = 0
	_has_exit_key = false

	_build_shops()
	_spawn_npcs()
	_spawn_guards()
	_spawn_merchant_king()
	_spawn_exit_portal()

	show_message("ECONOMY FLOOR — BUY THE EXIT KEY", accent_color, 4.0)
	show_message("Starting gold: %d | Key costs: %d" % [_hero_gold, _exit_key_price], Color(0.8, 0.8, 0.3), 3.0)

func _build_shops() -> void:
	_shops = [
		{
			"name": "The Rusty Flagon",
			"type": "tavern",
			"items": [
				{"name": "Health Potion", "buy": 15, "sell": 6, "value": "restore_hp"},
				{"name": "Fortified Ale", "buy": 8, "sell": 3, "value": "buff_speed"},
				{"name": "Mystery Flask", "buy": 5, "sell": 1, "value": "random"},
			],
			"position": Vector3(-10, 0, 12),
			"color": Color(0.6, 0.3, 0.1),
		},
		{
			"name": "Krak's Armory",
			"type": "weapon",
			"items": [
				{"name": "Iron Blade", "buy": 25, "sell": 10, "value": "weapon_dmg"},
				{"name": "Chainmail Scrap", "buy": 20, "sell": 8, "value": "armor"},
				{"name": "Throwing Knife", "buy": 12, "sell": 5, "value": "ranged"},
			],
			"position": Vector3(10, 0, 12),
			"color": Color(0.4, 0.4, 0.5),
		},
		{
			"name": "Madame Zulra",
			"type": "gamble",
			"items": [
				{"name": "Gamble (10g)", "buy": GAMBLE_COST, "sell": 0, "value": "gamble"},
			],
			"position": Vector3(0, 0, 18),
			"color": Color(0.6, 0.2, 0.7),
		},
		{
			"name": "The Fence",
			"type": "fence",
			"items": [
				{"name": "Sell Stolen Goods", "buy": 0, "sell": 15, "value": "fence"},
			],
			"position": Vector3(-14, 0, 18),
			"color": Color(0.2, 0.4, 0.2),
		},
	]

func _spawn_npcs() -> void:
	if not builder:
		return

	for shop_data in _shops:
		var npc = CharacterBody3D.new()
		npc.name = shop_data["name"].replace(" ", "_")

		# Collision
		var col = CollisionShape3D.new()
		var capsule = CapsuleShape3D.new()
		capsule.radius = 0.4
		capsule.height = 1.8
		col.shape = capsule
		npc.add_child(col)

		# Visual mesh
		var mesh = MeshInstance3D.new()
		var capsule_mesh = CapsuleMesh.new()
		capsule_mesh.radius = 0.4
		capsule_mesh.height = 1.8
		mesh.mesh = capsule_mesh
		var mat = StandardMaterial3D.new()
		mat.albedo_color = shop_data["color"]
		mat.emission_enabled = true
		mat.emission = shop_data["color"] * 0.4
		mat.emission_energy_multiplier = 0.6
		mesh.material_override = mat
		npc.add_child(mesh)

		# Name label floating above
		var label_3d = Label3D.new()
		label_3d.text = shop_data["name"]
		label_3d.font_size = 48
		label_3d.position = Vector3(0, 1.8, 0)
		label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label_3d.modulate = Color(1.0, 1.0, 0.6)
		npc.add_child(label_3d)

		# Interact area
		var interact_area = Area3D.new()
		interact_area.name = "InteractArea"
		var interact_shape = CollisionShape3D.new()
		var interact_sphere = SphereShape3D.new()
		interact_sphere.radius = 3.0
		interact_shape.shape = interact_sphere
		interact_area.add_child(interact_shape)
		npc.add_child(interact_area)

		# Store shop data
		npc.set_meta("shop", shop_data)
		npc.set_meta("interact_cooldown", 0.0)

		npc.position = shop_data["position"]
		npc.position.y = 0.0
		builder.add_child(npc)
		_npcs.append(npc)

func _spawn_merchant_king() -> void:
	if not builder:
		return

	_merchant_king = CharacterBody3D.new()
	_merchant_king.name = "MerchantKing"

	var col = CollisionShape3D.new()
	var capsule = CapsuleShape3D.new()
	capsule.radius = 0.55
	capsule.height = 2.2
	col.shape = capsule
	_merchant_king.add_child(col)

	# Regal gold mesh
	var mesh = MeshInstance3D.new()
	var capsule_mesh = CapsuleMesh.new()
	capsule_mesh.radius = 0.55
	capsule_mesh.height = 2.2
	mesh.mesh = capsule_mesh
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.75, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.0)
	mat.emission_energy_multiplier = 1.2
	mat.metallic = 0.8
	mat.roughness = 0.2
	mesh.material_override = mat
	_merchant_king.add_child(mesh)

	var label_3d = Label3D.new()
	label_3d.text = "👑 Merchant King\nExit Key: %dg" % _exit_key_price
	label_3d.font_size = 52
	label_3d.position = Vector3(0, 2.0, 0)
	label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label_3d.modulate = accent_color
	label_3d.name = "MKLabel"
	_merchant_king.add_child(label_3d)

	# Interact area
	var interact_area = Area3D.new()
	interact_area.name = "InteractArea"
	var interact_shape = CollisionShape3D.new()
	var interact_sphere = SphereShape3D.new()
	interact_sphere.radius = 3.5
	interact_shape.shape = interact_sphere
	interact_area.add_child(interact_shape)
	_merchant_king.add_child(interact_area)

	_merchant_king.set_meta("interact_cooldown", 0.0)
	_merchant_king.position = Vector3(0, 0, 25)
	builder.add_child(_merchant_king)

func _spawn_guards() -> void:
	if not builder:
		return

	var guard_positions := [
		Vector3(-5, 0, 14), Vector3(5, 0, 14), Vector3(0, 0, 22)
	]

	for i in range(GUARD_COUNT):
		var guard = CharacterBody3D.new()
		guard.name = "Guard_%d" % i

		var col = CollisionShape3D.new()
		var capsule = CapsuleShape3D.new()
		capsule.radius = 0.4
		capsule.height = 1.8
		col.shape = capsule
		guard.add_child(col)

		var mesh = MeshInstance3D.new()
		var capsule_mesh = CapsuleMesh.new()
		capsule_mesh.radius = 0.4
		capsule_mesh.height = 1.8
		mesh.mesh = capsule_mesh
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.3, 0.6)
		mat.emission_enabled = true
		mat.emission = Color(0.2, 0.2, 0.5)
		mat.emission_energy_multiplier = 0.5
		mesh.material_override = mat
		guard.add_child(mesh)

		var label = Label3D.new()
		label.text = "Guard"
		label.font_size = 40
		label.position = Vector3(0, 1.6, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color(0.6, 0.7, 1.0)
		guard.add_child(label)

		var pos = guard_positions[i] if i < guard_positions.size() else Vector3(randf_range(-8, 8), 0, randf_range(10, 22))
		guard.position = pos
		guard.set_meta("home_pos", pos)
		guard.set_meta("alert_timer", 0.0)
		guard.set_meta("is_chasing", false)
		guard.set_meta("patrol_angle", (TAU / GUARD_COUNT) * i)
		guard.set_meta("attack_cd", 0.0)
		builder.add_child(guard)
		_guards.append(guard)

func _spawn_exit_portal() -> void:
	if not builder:
		return

	_exit_portal = Node3D.new()
	_exit_portal.name = "ExitPortal"

	var mesh = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 0.8
	torus.outer_radius = 1.4
	mesh.mesh = torus
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.2, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.3, 0.3)
	mat.emission_energy_multiplier = 0.5
	mesh.material_override = mat
	mesh.name = "PortalMesh"
	_exit_portal.add_child(mesh)

	var label = Label3D.new()
	label.text = "🔒 LOCKED"
	label.font_size = 52
	label.position = Vector3(0, 2.2, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(0.5, 0.5, 0.5)
	label.name = "PortalLabel"
	_exit_portal.add_child(label)

	# Trigger area
	var area = Area3D.new()
	area.name = "ExitArea"
	var shape = CollisionShape3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = 2.0
	shape.shape = sphere
	area.add_child(shape)
	_exit_portal.add_child(area)

	_exit_portal.position = Vector3(0, 0, 30)
	builder.add_child(_exit_portal)

func update(delta: float) -> void:
	if not _is_active:
		return

	# Price inflation timer
	_price_timer += delta
	if _price_timer >= PRICE_INFLATE_INTERVAL:
		_price_timer = 0.0
		_price_cycle += 1
		_exit_key_price = int(_exit_key_price * (1.0 + PRICE_INFLATE_RATE))
		_inflate_shop_prices()
		show_message("INFLATION! Exit Key now %dg!" % _exit_key_price, Color(1.0, 0.3, 0.1), 3.0)
		_update_merchant_king_label()

	var hero = GameManager.hero
	if not hero or hero.is_dead:
		return

	# Update guard behavior
	_update_guards(hero, delta)

	# Check for hero interacting with NPCs (E key)
	if Input.is_action_just_pressed("interact"):
		_try_interact(hero)

	# Check if hero steps into exit portal
	if _has_exit_key and is_instance_valid(_exit_portal):
		var portal_area = _exit_portal.get_node_or_null("ExitArea")
		if portal_area:
			var dist = hero.global_position.distance_to(_exit_portal.global_position)
			if dist < 2.5:
				_win_floor()

	_update_hud()

func _update_guards(hero: Node3D, delta: float) -> void:
	for guard in _guards:
		if not is_instance_valid(guard):
			continue

		var is_chasing: bool = guard.get_meta("is_chasing", false)
		var alert_timer: float = guard.get_meta("alert_timer", 0.0)

		if is_chasing:
			# Chase hero
			var dir = (hero.global_position - guard.global_position).normalized()
			dir.y = 0
			guard.velocity = dir * 5.0
			guard.move_and_slide()

			# Attack if close
			var dist = guard.global_position.distance_to(hero.global_position)
			if dist < 2.0:
				var atk_cd: float = guard.get_meta("attack_cd", 0.0) - delta
				guard.set_meta("attack_cd", atk_cd)
				if atk_cd <= 0:
					if hero.has_method("take_damage"):
						hero.take_damage(20 + floor_number * 5)
					guard.set_meta("attack_cd", 1.5)

			# Give up after 12 seconds
			alert_timer -= delta
			guard.set_meta("alert_timer", alert_timer)
			if alert_timer <= 0:
				guard.set_meta("is_chasing", false)
				show_message("Guard lost you.", Color(0.6, 0.8, 0.4), 1.5)
		else:
			# Patrol around home position
			var home: Vector3 = guard.get_meta("home_pos", guard.global_position)
			var angle: float = guard.get_meta("patrol_angle", 0.0) + delta * 0.5
			guard.set_meta("patrol_angle", angle)
			var patrol_target = home + Vector3(cos(angle) * 3.0, 0, sin(angle) * 3.0)
			var dir = (patrol_target - guard.global_position).normalized()
			dir.y = 0
			guard.velocity = dir * 2.0
			guard.move_and_slide()

func _try_interact(hero: Node3D) -> void:
	# Check merchant king first
	if is_instance_valid(_merchant_king):
		var dist = hero.global_position.distance_to(_merchant_king.global_position)
		if dist < 3.5:
			_interact_merchant_king()
			return

	# Check shopkeepers
	for npc in _npcs:
		if not is_instance_valid(npc):
			continue
		var dist = hero.global_position.distance_to(npc.global_position)
		if dist < 3.0:
			var cd: float = npc.get_meta("interact_cooldown", 0.0)
			if cd > 0:
				continue
			npc.set_meta("interact_cooldown", 1.5)
			_interact_shop(npc, hero)
			return

func _interact_merchant_king() -> void:
	if _has_exit_key:
		show_message("You already have the Exit Key!", accent_color, 2.0)
		return

	if _hero_gold >= _exit_key_price:
		_hero_gold -= _exit_key_price
		_has_exit_key = true
		show_message("You bought the Exit Key! REACH THE PORTAL!", accent_color, 4.0)
		GameManager.request_screen_shake(3.0, 0.2)
		_unlock_exit_portal()
	else:
		var needed = _exit_key_price - _hero_gold
		show_message("Not enough gold! Need %dg more." % needed, Color(1.0, 0.4, 0.2), 2.5)

func _interact_shop(npc: Node3D, hero: Node3D) -> void:
	var shop: Dictionary = npc.get_meta("shop", {})
	if shop.is_empty():
		return

	var items: Array = shop.get("items", [])
	if items.is_empty():
		return

	var shop_type: String = shop.get("type", "general")

	# Pick a random item to offer (simplified: cycles through)
	var tick = int(Time.get_ticks_msec() / 2000) % items.size()
	var item: Dictionary = items[tick]

	if shop_type == "gamble":
		_do_gamble(hero)
	elif shop_type == "fence":
		_do_fence()
	elif item.get("buy", 0) > 0 and shop_type in ["tavern", "weapon"]:
		# Buy item
		var price: int = item.get("buy", 99)
		if _hero_gold >= price:
			_hero_gold -= price
			_apply_item_effect(item, hero)
			show_message("Bought %s for %dg" % [item["name"], price], Color(0.8, 1.0, 0.5), 2.0)
		else:
			# Try to steal (risky)
			_attempt_steal(npc, hero, item)
	elif item.get("sell", 0) > 0:
		# Sell items
		var sell_price: int = item.get("sell", 0)
		_hero_gold += sell_price
		show_message("Sold for %dg (Total: %dg)" % [sell_price, _hero_gold], Color(0.8, 0.9, 0.4), 1.5)

func _do_gamble(hero: Node3D) -> void:
	if _hero_gold < GAMBLE_COST:
		show_message("Not enough gold to gamble!", Color(1.0, 0.4, 0.2), 1.5)
		return

	_hero_gold -= GAMBLE_COST

	var roll = randf()
	if roll < 0.45:
		# Win
		var winnings = randi_range(GAMBLE_MIN_WIN, GAMBLE_MAX_WIN)
		_hero_gold += winnings
		show_message("🎲 YOU WIN! +%dg" % winnings, Color(1.0, 0.9, 0.1), 2.5)
	elif roll < 0.75:
		# Small loss (already paid cost)
		show_message("🎲 No luck. Lost your %dg." % GAMBLE_COST, Color(0.7, 0.5, 0.3), 2.0)
	else:
		# Jackpot or bust
		if roll > 0.92:
			var jackpot = randi_range(60, 120)
			_hero_gold += jackpot
			show_message("🎲 JACKPOT! +%dg!" % jackpot, accent_color, 3.0)
			GameManager.request_screen_shake(2.0, 0.15)
		else:
			# Bad luck — take HP damage
			if hero.has_method("take_damage"):
				hero.take_damage(15)
			show_message("🎲 Cheated! Lost gold AND got punched!", Color(1.0, 0.2, 0.1), 2.0)

func _do_fence() -> void:
	# Sell "stolen goods" — fake items the hero "lifted" for gold
	var loot_val = randi_range(8, 25)
	_hero_gold += loot_val
	show_message("Fenced goods for %dg. No questions asked." % loot_val, Color(0.5, 0.8, 0.5), 2.0)

func _attempt_steal(npc: Node3D, hero: Node3D, item: Dictionary) -> void:
	# Chance of success depends on distance to nearest guard
	var min_guard_dist := 9999.0
	for guard in _guards:
		if is_instance_valid(guard):
			var d = guard.global_position.distance_to(npc.global_position)
			min_guard_dist = minf(min_guard_dist, d)

	var steal_chance := 0.7
	if min_guard_dist < STEAL_DETECTION_RADIUS:
		steal_chance = 0.2

	if randf() < steal_chance:
		_apply_item_effect(item, hero)
		show_message("Stole %s! Don't get caught." % item["name"], Color(0.5, 1.0, 0.5), 2.0)
	else:
		show_message("CAUGHT STEALING! Guards inbound!", Color(1.0, 0.1, 0.1), 2.5)
		GameManager.request_screen_shake(4.0, 0.2)
		_alert_all_guards()

func _alert_all_guards() -> void:
	for guard in _guards:
		if is_instance_valid(guard):
			guard.set_meta("is_chasing", true)
			guard.set_meta("alert_timer", 12.0)
	if AudioManager.has_method("play_sfx"):
		AudioManager.play_sfx("alert")

func _apply_item_effect(item: Dictionary, hero: Node3D) -> void:
	var val: String = item.get("value", "")
	match val:
		"restore_hp":
			if hero.has_method("heal"):
				hero.heal(40)
		"buff_speed":
			# Temporary speed buff stored as meta
			hero.set_meta("speed_boost_timer", 8.0)
		"random":
			var effects = ["restore_hp", "buff_speed", "armor"]
			_apply_item_effect({"value": effects.pick_random()}, hero)
		"weapon_dmg":
			if hero.has_method("add_damage_bonus"):
				hero.add_damage_bonus(8)
		"armor":
			if hero.has_method("add_armor"):
				hero.add_armor(10)
		"ranged":
			# Grant a throwing knife charge
			if hero.has_method("add_ranged_charge"):
				hero.add_ranged_charge(3)
		"gamble":
			_do_gamble(hero)

func _inflate_shop_prices() -> void:
	for shop_data in _shops:
		for item in shop_data["items"]:
			if item.get("buy", 0) > 0:
				item["buy"] = int(item["buy"] * (1.0 + PRICE_INFLATE_RATE))

func _unlock_exit_portal() -> void:
	if not is_instance_valid(_exit_portal):
		return

	var mesh = _exit_portal.get_node_or_null("PortalMesh")
	if mesh and mesh.material_override:
		mesh.material_override.albedo_color = Color(0.2, 0.8, 1.0)
		mesh.material_override.emission = Color(0.2, 0.8, 1.0)
		mesh.material_override.emission_energy_multiplier = 2.5

	var label = _exit_portal.get_node_or_null("PortalLabel")
	if label:
		label.text = "✅ EXIT"
		label.modulate = Color(0.3, 1.0, 0.5)

func _update_merchant_king_label() -> void:
	if not is_instance_valid(_merchant_king):
		return
	var lbl = _merchant_king.get_node_or_null("MKLabel")
	if lbl:
		lbl.text = "👑 Merchant King\nExit Key: %dg" % _exit_key_price

func _win_floor() -> void:
	show_message("ESCAPED! The Merchant King weeps.", accent_color, 3.0)
	complete()

func _update_hud() -> void:
	if not _hud_overlay:
		return

	var gold_label = _hud_overlay.get_node_or_null("GoldLabel")
	if gold_label:
		gold_label.text = "💰 Gold: %dg" % _hero_gold

	var key_label = _hud_overlay.get_node_or_null("KeyLabel")
	if key_label:
		if _has_exit_key:
			key_label.text = "🔑 Exit Key: OWNED — reach the portal!"
			key_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
		else:
			key_label.text = "🔑 Exit Key: %dg (E near Merchant King)" % _exit_key_price
			key_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))

	var inflate_label = _hud_overlay.get_node_or_null("InflateLabel")
	if inflate_label:
		var next_inflate = PRICE_INFLATE_INTERVAL - _price_timer
		inflate_label.text = "📈 Inflation in %.0fs" % next_inflate

func stop() -> void:
	super.stop()
	for npc in _npcs:
		if is_instance_valid(npc):
			npc.queue_free()
	_npcs.clear()
	for guard in _guards:
		if is_instance_valid(guard):
			guard.queue_free()
	_guards.clear()
	if is_instance_valid(_merchant_king):
		_merchant_king.queue_free()
	_merchant_king = null
	if is_instance_valid(_exit_portal):
		_exit_portal.queue_free()
	_exit_portal = null

func has_boss() -> bool:
	return false

func has_smusher() -> bool:
	return false  # No timer pressure — economic pressure instead

func exit_visible_at_start() -> bool:
	return true  # Portal visible but locked

func uses_default_enemy_spawning() -> bool:
	return false  # We handle guards + NPCs ourselves

func create_hud_overlay() -> Control:
	_hud_overlay = Control.new()
	_hud_overlay.name = "EconomyHUD"
	_hud_overlay.set_anchors_preset(Control.PRESET_TOP_CENTER)

	var title = Label.new()
	title.name = "ArchetypeLabel"
	title.text = "ECONOMY FLOOR"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", accent_color)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(-120, 8)
	_hud_overlay.add_child(title)

	var gold = Label.new()
	gold.name = "GoldLabel"
	gold.text = "💰 Gold: %dg" % _hero_gold
	gold.add_theme_font_size_override("font_size", 18)
	gold.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	gold.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gold.position = Vector2(-120, 32)
	_hud_overlay.add_child(gold)

	var key = Label.new()
	key.name = "KeyLabel"
	key.text = "🔑 Exit Key: %dg (E near Merchant King)" % _exit_key_price
	key.add_theme_font_size_override("font_size", 15)
	key.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key.position = Vector2(-200, 54)
	_hud_overlay.add_child(key)

	var inflate = Label.new()
	inflate.name = "InflateLabel"
	inflate.text = "📈 Inflation in 60s"
	inflate.add_theme_font_size_override("font_size", 13)
	inflate.add_theme_color_override("font_color", Color(0.8, 0.5, 0.3))
	inflate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inflate.position = Vector2(-100, 74)
	_hud_overlay.add_child(inflate)

	var hint = Label.new()
	hint.name = "HintLabel"
	hint.text = "[E] Interact  |  [D] Steal (risky)"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.position = Vector2(-140, 92)
	_hud_overlay.add_child(hint)

	return _hud_overlay

func destroy_hud_overlay() -> void:
	if _hud_overlay and is_instance_valid(_hud_overlay):
		_hud_overlay.queue_free()
		_hud_overlay = null
