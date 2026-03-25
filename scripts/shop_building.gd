extends Node3D

## Clickable 3D shop building — placed in the dungeon arena.
## Left-click to open the merchant UI. Uses KayKit market building model.

signal shop_clicked

var _model: Node3D = null
var _area: Area3D = null
var _label: Label3D = null
var _interact_range := 5.0  # Max click distance from hero

func _ready() -> void:
	# Load and instance the market building model
	var building_scene = load("res://assets/models/kaykit/buildings/building_market_blue.fbx")
	if building_scene:
		_model = building_scene.instantiate()
		_model.scale = Vector3(1.5, 1.5, 1.5)
		add_child(_model)

	# Click detection area (StaticBody3D so raycast hits it)
	var body := StaticBody3D.new()
	body.collision_layer = 8  # Interactable layer
	body.collision_mask = 0
	body.set_meta("shop_building", true)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.0, 4.0, 3.0)
	col.shape = shape
	col.position.y = 2.0
	body.add_child(col)
	add_child(body)

	# Floating label
	_label = Label3D.new()
	_label.text = "SHOP"
	_label.font_size = 52
	_label.modulate = Color(1.0, 0.85, 0.3)
	_label.outline_modulate = Color(0, 0, 0, 0.8)
	_label.outline_size = 4
	_label.position = Vector3(0, 5.0, 0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_label)

	# Subtle hint label below
	var hint := Label3D.new()
	hint.text = "Left-click to browse"
	hint.font_size = 28
	hint.modulate = Color(0.7, 0.65, 0.5, 0.8)
	hint.position = Vector3(0, 4.2, 0)
	hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(hint)

func try_interact(hero_pos: Vector3) -> bool:
	## Returns true if hero is close enough to interact
	var dist := global_position.distance_to(hero_pos)
	if dist <= _interact_range:
		shop_clicked.emit()
		return true
	return false
