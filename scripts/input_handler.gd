extends Node

## Handles mouse clicks for movement, targeting, selection, and spell casting.
## Right click: move / attack / spell target
## Left click: select unit or interact with objects

var camera_rig: Node3D = null

signal unit_selected(unit: Node3D)
signal unit_deselected

var selected_unit: Node3D = null

func _ready() -> void:
	pass

func set_camera(cam: Node3D) -> void:
	camera_rig = cam

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_handle_right_click()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_handle_left_click()

	# Spell hotkeys (uses InputMap actions so rebinding works)
	var hero = GameManager.hero
	if hero != null and not hero.is_dead:
		for i in range(4):
			if event.is_action_pressed("spell_%d" % i):
				hero.cast_spell(i)
				TutorialManager.notify_event("spell_cast")
				break

		# (WASD attack removed — click-to-move only)

func _handle_right_click() -> void:
	## Right click: move, attack, spell targeting (action button)
	if camera_rig == null:
		return
	var hero = GameManager.hero
	if hero == null or hero.is_dead:
		return

	var camera = camera_rig.get_node("CameraArm/Camera3D")
	var mouse_pos = get_viewport().get_mouse_position()
	var from = camera.project_ray_origin(mouse_pos)
	var dir = camera.project_ray_normal(mouse_pos)

	# Spell targeting mode — place spell on right click
	if GameManager.is_targeting_spell:
		var ground_pos = _get_ground_position(from, dir)
		match GameManager.targeting_spell_id:
			1:
				hero.cast_fireball_at(ground_pos)
			100:
				hero.cast_alt_targeted_at(ground_pos)
		GameManager.is_targeting_spell = false
		GameManager.targeting_spell_id = -1
		return

	# Raycast for enemy — right click to attack
	var space_state = hero.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, from + dir * 100.0)
	query.collision_mask = 2  # Layer 2 = Units
	var result = space_state.intersect_ray(query)

	if result and result.collider and result.collider.is_in_group("enemies"):
		hero.set_attack_target(result.collider)
		TutorialManager.notify_event("enemy_hit")
		return

	# Right click on interactable — walk to and interact
	var query2 = PhysicsRayQueryParameters3D.create(from, from + dir * 100.0)
	query2.collision_mask = 4  # Layer 3 = Interactables
	var result2 = space_state.intersect_ray(query2)

	if result2 and result2.collider and result2.collider.is_in_group("interactables"):
		_interact_with(hero, result2.collider)
		return

	# Otherwise, right-click-to-move on ground
	var ground_pos = _get_ground_position(from, dir)
	if ground_pos != Vector3.ZERO:
		hero.move_to(ground_pos)
		TutorialManager.notify_event("hero_moved")
		_spawn_click_indicator(ground_pos)

func _handle_left_click() -> void:
	## Left click: select units to inspect, or cancel spell targeting
	if camera_rig == null:
		return

	# Cancel spell targeting with left click
	if GameManager.is_targeting_spell:
		GameManager.is_targeting_spell = false
		GameManager.targeting_spell_id = -1
		return

	var camera = camera_rig.get_node("CameraArm/Camera3D")
	var mouse_pos = get_viewport().get_mouse_position()
	var from = camera.project_ray_origin(mouse_pos)
	var dir = camera.project_ray_normal(mouse_pos)

	var hero = GameManager.hero
	if hero == null:
		return
	var space_state = hero.get_world_3d().direct_space_state

	# Check for unit click (enemies or any selectable)
	var query = PhysicsRayQueryParameters3D.create(from, from + dir * 100.0)
	query.collision_mask = 2  # Layer 2 = Units
	var result = space_state.intersect_ray(query)

	if result and result.collider:
		_select_unit(result.collider)
		return

	# Check for interactable click (chests, barrels — left click also interacts)
	var query2 = PhysicsRayQueryParameters3D.create(from, from + dir * 100.0)
	query2.collision_mask = 4  # Layer 3 = Interactables
	var result2 = space_state.intersect_ray(query2)

	if result2 and result2.collider:
		_select_unit(result2.collider)
		return

	# Clicked empty ground — deselect
	_deselect_unit()

func _select_unit(unit: Node3D) -> void:
	if selected_unit == unit:
		return
	_deselect_unit()
	selected_unit = unit
	unit_selected.emit(unit)

func _deselect_unit() -> void:
	if selected_unit != null:
		selected_unit = null
		unit_deselected.emit()

func _interact_with(hero: Node3D, target: Node3D) -> void:
	var dist := hero.global_position.distance_to(target.global_position)
	if dist < 2.5:
		if target.has_method("interact"):
			target.interact()
		elif target.has_method("take_damage"):
			target.take_damage(hero._get_melee_damage())
	else:
		hero.move_to(target.global_position)
		_pending_interactable = target

var _pending_interactable: Node3D = null

func _process(_delta: float) -> void:
	if _pending_interactable and is_instance_valid(_pending_interactable):
		var hero = GameManager.hero
		if hero == null or hero.is_dead:
			_pending_interactable = null
			return
		var dist: float = hero.global_position.distance_to(_pending_interactable.global_position)
		if dist < 2.5:
			if _pending_interactable.has_method("interact"):
				_pending_interactable.interact()
			elif _pending_interactable.has_method("take_damage"):
				_pending_interactable.take_damage(hero._get_melee_damage())
			_pending_interactable = null
	elif _pending_interactable:
		_pending_interactable = null

func _get_ground_position(from: Vector3, dir: Vector3) -> Vector3:
	if dir.y != 0:
		var t = -from.y / dir.y
		if t > 0:
			return from + dir * t
	return Vector3.ZERO

func _spawn_click_indicator(pos: Vector3) -> void:
	var indicator = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 0.2
	torus.outer_radius = 0.4
	indicator.mesh = torus
	indicator.position = pos + Vector3.UP * 0.05
	indicator.rotation_degrees.x = 90

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 1.0, 0.3, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.3, 1.0, 0.3)
	mat.emission_energy_multiplier = 2.0
	indicator.set_surface_override_material(0, mat)

	get_tree().root.add_child(indicator)

	var tween = indicator.create_tween()
	tween.tween_property(indicator, "scale", Vector3(2.0, 2.0, 2.0), 0.3)
	tween.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.3)
	tween.tween_callback(indicator.queue_free)
