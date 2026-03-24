extends Area3D

## SecretRoomTrigger — hidden trigger behind a wall.
## Hero stands on it for 2 seconds to reveal a hidden door and spawn rare+ loot.

class_name SecretRoomTrigger

var _hero_inside: bool = false
var _timer: float = 0.0
var _activated: bool = false
const ACTIVATION_TIME: float = 2.0

func _ready() -> void:
	# Invisible trigger area
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(2.0, 2.0, 2.0)
	col.shape = shape
	add_child(col)

	collision_layer = 0
	collision_mask = 2  # Units layer

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if body == GameManager.hero:
		_hero_inside = true
		_timer = 0.0

func _on_body_exited(body: Node3D) -> void:
	if body == GameManager.hero:
		_hero_inside = false
		_timer = 0.0

func _process(delta: float) -> void:
	if _activated or not _hero_inside:
		return

	_timer += delta
	if _timer >= ACTIVATION_TIME:
		_activate()

func _activate() -> void:
	_activated = true

	# Reveal hidden door — visual effect
	var door_mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(2.0, 3.0, 0.3)
	door_mesh.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.5, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(0.8, 0.6, 0.1)
	mat.emission_energy_multiplier = 2.0
	door_mesh.material_override = mat
	door_mesh.position = Vector3(0, 1.5, -1.0)
	add_child(door_mesh)

	# Label
	var label = Label3D.new()
	label.text = "SECRET ROOM!"
	label.font_size = 48
	label.modulate = Color(1.0, 0.85, 0.2)
	label.position = Vector3(0, 3.5, -1.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)

	# Spawn rare+ loot
	_spawn_secret_loot()

	# Screen shake + audio
	GameManager.request_screen_shake(4.0, 0.3)
	AudioManager.play_sfx("chest_open", 1.0)

	if Narrator:
		Narrator.speak("A hidden chamber... the Collective approves of your curiosity.")

func _spawn_secret_loot() -> void:
	# Roll 2 items from boss loot table (guaranteed rare+)
	for _i in range(2):
		var item = LootManager.roll_from_table("boss")
		if not item.is_empty():
			# Upgrade rarity to at least RARE
			if item.get("rarity", 0) < LootManager.Rarity.RARE:
				item["rarity"] = LootManager.Rarity.RARE
			LootManager._spawn_drop(global_position + Vector3(randf_range(-1.5, 1.5), 0.5, randf_range(-1.5, 1.5)), item)
