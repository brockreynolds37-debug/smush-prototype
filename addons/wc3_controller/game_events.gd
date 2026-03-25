# GameEvents — Global Event Bus (Autoload)
extends Node

signal unit_dies(dying_unit: Node3D, killing_unit: Node3D)
signal unit_takes_damage(target: Node3D, source: Node3D, amount: float, damage_type: int)
signal unit_attacked(target: Node3D, attacker: Node3D)
signal unit_spawns(unit: Node3D)
signal hero_levels_up(hero: Node3D, new_level: int)
signal ability_cast_start(caster: Node3D, ability_id: int, target: Variant)
signal ability_cast_finish(caster: Node3D, ability_id: int, target: Variant)
signal order_issued(unit: Node3D, order_type: int, target: Variant)
signal order_completed(unit: Node3D, order_type: int)
signal projectile_launched(source: Node3D, target: Node3D, projectile: Node3D)
signal projectile_hit(projectile: Node3D, target: Node3D)
