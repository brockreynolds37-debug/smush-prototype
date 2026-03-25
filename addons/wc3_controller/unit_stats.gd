# UnitStats — Data-driven unit statistics (like WC3 Object Editor)
class_name UnitStats
extends Resource

@export_group("Identity")
@export var unit_name: String = "Unnamed Unit"
@export var unit_id: int = 0
@export var is_hero: bool = false

@export_group("Movement")
@export_range(50, 522) var move_speed: float = 300.0
@export_range(0.01, 3.0) var turn_rate: float = 0.5
@export_range(8, 96) var collision_radius: float = 48.0
@export var blocks_pathing: bool = true

@export_group("Combat")
@export var attack_damage_min: int = 20
@export var attack_damage_max: int = 28
@export var attack_dice: int = 1
@export var attack_sides: int = 4
@export var base_attack_time: float = 1.7
@export_range(0.0, 1.0) var damage_point: float = 0.433
@export_range(0.0, 1.0) var attack_backswing: float = 0.567
@export var attack_range: float = 128.0
@export var is_ranged: bool = false
@export var projectile_speed: float = 900.0
@export var acquisition_range: float = 500.0

@export_group("Defense")
@export var max_health: float = 700.0
@export var max_mana: float = 300.0
@export var health_regen: float = 1.0
@export var mana_regen: float = 0.75
@export var base_armor: float = 3.0

@export_group("Abilities")
@export_range(0.0, 2.0) var cast_point: float = 0.3
@export_range(0.0, 2.0) var cast_backswing: float = 0.5

@export_group("Visuals")
@export var model_scale: float = 1.0
@export var selection_radius: float = 64.0

func get_random_damage() -> int:
	var roll: int = 0
	for i in attack_dice:
		roll += randi_range(1, attack_sides)
	return attack_damage_min + roll

func get_turn_speed_deg_per_sec() -> float:
	var theoretical: float = (turn_rate / 0.03) * rad_to_deg(1.0)
	return minf(theoretical, 382.0)

func get_turn_speed_rad_per_sec() -> float:
	return deg_to_rad(get_turn_speed_deg_per_sec())
