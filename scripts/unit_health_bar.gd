extends Node3D

## 3D health bar that billboards toward camera.

@onready var bar_bg: MeshInstance3D = $BarBG
@onready var bar_fill: MeshInstance3D = $BarFill
@onready var mana_fill: MeshInstance3D = $ManaFill if has_node("ManaFill") else null

var health_percent: float = 1.0
var mana_percent: float = 1.0

func _process(_delta: float) -> void:
	# Billboard toward camera
	var cam = get_viewport().get_camera_3d()
	if cam:
		look_at(cam.global_position, Vector3.UP)

func update_health(current: int, maximum: int) -> void:
	health_percent = clampf(float(current) / float(maximum), 0.0, 1.0)
	if bar_fill:
		bar_fill.scale.x = health_percent
		bar_fill.position.x = -(1.0 - health_percent) * 0.5

		# Color goes from green to yellow to red
		var mat = bar_fill.get_surface_override_material(0)
		if mat:
			if health_percent > 0.5:
				mat.albedo_color = Color(0.1, 0.9, 0.1)
			elif health_percent > 0.25:
				mat.albedo_color = Color(0.9, 0.9, 0.1)
			else:
				mat.albedo_color = Color(0.9, 0.1, 0.1)

func update_mana(current: int, maximum: int) -> void:
	mana_percent = clampf(float(current) / float(maximum), 0.0, 1.0)
	if mana_fill:
		mana_fill.scale.x = mana_percent
		mana_fill.position.x = -(1.0 - mana_percent) * 0.5
