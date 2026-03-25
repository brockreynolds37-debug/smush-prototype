extends Node3D

## ForgeStation — interactable world object that opens the crafting UI.
## Spawned by DungeonBuilder on merchant/rest floors (~1 per run).
## Player walks into the interaction zone to activate.

class_name ForgeStation

signal forge_opened

var _crafting_ui: CanvasLayer = null
var _interact_zone: Area3D = null
var _prompt_label: Label3D = null
var _mesh: MeshInstance3D = null
var _player_nearby: bool = false
var _can_use: bool = true  # one-use per floor placement

func _ready() -> void:
	_build_forge_mesh()
	_build_interact_zone()
	_build_prompt()
	_build_crafting_ui()

func _build_forge_mesh() -> void:
	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.2, 1.4, 1.0)
	_mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.2, 0.1)
	mat.metallic = 0.7
	mat.roughness = 0.4
	_mesh.material_override = mat
	_mesh.position = Vector3(0, 0.7, 0)
	add_child(_mesh)

	# Glow on top — the forge fire
	var fire := MeshInstance3D.new()
	var fire_box := BoxMesh.new()
	fire_box.size = Vector3(0.6, 0.2, 0.4)
	fire.mesh = fire_box
	var fire_mat := StandardMaterial3D.new()
	fire_mat.albedo_color = Color(1.0, 0.4, 0.05)
	fire_mat.emission_enabled = true
	fire_mat.emission = Color(1.0, 0.35, 0.0)
	fire_mat.emission_energy_multiplier = 3.0
	fire.material_override = fire_mat
	fire.position = Vector3(0, 1.5, 0)
	add_child(fire)

	# Steady fire — no pulsing

func _build_interact_zone() -> void:
	_interact_zone = Area3D.new()
	_interact_zone.collision_layer = 0
	_interact_zone.collision_mask = 2  # Player layer

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 2.5
	shape.shape = sphere
	_interact_zone.add_child(shape)
	add_child(_interact_zone)

	_interact_zone.body_entered.connect(_on_body_entered)
	_interact_zone.body_exited.connect(_on_body_exited)

func _build_prompt() -> void:
	_prompt_label = Label3D.new()
	_prompt_label.text = "[E] Forge"
	_prompt_label.font_size = 32
	_prompt_label.modulate = Color(1.0, 0.85, 0.3)
	_prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt_label.position = Vector3(0, 2.4, 0)
	_prompt_label.visible = false
	add_child(_prompt_label)

func _build_crafting_ui() -> void:
	var ui_script = load("res://scripts/crafting_ui.gd")
	_crafting_ui = CanvasLayer.new()
	_crafting_ui.set_script(ui_script)
	_crafting_ui.name = "CraftingUI"
	add_child(_crafting_ui)
	_crafting_ui.crafting_closed.connect(_on_crafting_closed)
	_crafting_ui.item_crafted.connect(_on_item_crafted)

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") or body.name == "Hero":
		_player_nearby = true
		if _can_use:
			_prompt_label.visible = true

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player") or body.name == "Hero":
		_player_nearby = false
		_prompt_label.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not _player_nearby or not _can_use:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E or event.keycode == KEY_F:
			_open_forge()
			get_viewport().set_input_as_handled()

func _open_forge() -> void:
	_prompt_label.visible = false
	forge_opened.emit()
	if _crafting_ui:
		_crafting_ui.open_forge()

func _on_crafting_closed() -> void:
	if _player_nearby and _can_use:
		_prompt_label.visible = true

func _on_item_crafted(result_item: Dictionary) -> void:
	# After crafting, mark as used — forge cools down (one craft per station)
	_can_use = false
	_prompt_label.visible = false
	_prompt_label.text = "(used)"

	# Change forge color to cooled-down grey
	if _mesh and _mesh.material_override:
		var mat := _mesh.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color = Color(0.25, 0.25, 0.25)

	if Narrator:
		Narrator.speak("The forge goes dark... but something useful came out of it.")
