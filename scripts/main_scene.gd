extends Node3D

## Main scene — wires up the input handler, camera, and hero connections.

func _ready() -> void:
	# Connect input handler to camera
	var input_handler = $InputHandler
	var camera_rig = $CameraRig
	if input_handler and camera_rig:
		input_handler.set_camera(camera_rig)

	# Connect hero health bar to hero signals
	await get_tree().process_frame
	var hero = GameManager.hero
	if hero:
		var health_bar_node = hero.get_node_or_null("HealthBar")
		if health_bar_node:
			hero.health_changed.connect(health_bar_node.update_health)
			hero.mana_changed.connect(health_bar_node.update_mana)

	# Bake the navigation mesh
	var nav_region = $NavigationRegion3D
	if nav_region:
		nav_region.bake_navigation_mesh()
