# OrderManager — Order types and queue system (Autoload)
extends Node

enum OrderType {
	NONE, MOVE, ATTACK_MOVE, ATTACK_TARGET, STOP, HOLD_POSITION,
	CAST_POINT, CAST_TARGET, CAST_IMMEDIATE, FOLLOW, PATROL,
}

class Order:
	var type: OrderType = OrderType.NONE
	var target_position: Vector3 = Vector3.ZERO
	var target_unit: Node3D = null
	var ability_id: int = -1
	var queued: bool = false

	func _init(p_type: OrderType = OrderType.NONE):
		type = p_type

	static func move_to(pos: Vector3, is_queued: bool = false) -> Order:
		var o = Order.new(OrderType.MOVE)
		o.target_position = pos
		o.queued = is_queued
		return o

	static func attack_move_to(pos: Vector3, is_queued: bool = false) -> Order:
		var o = Order.new(OrderType.ATTACK_MOVE)
		o.target_position = pos
		o.queued = is_queued
		return o

	static func attack_unit(target: Node3D, is_queued: bool = false) -> Order:
		var o = Order.new(OrderType.ATTACK_TARGET)
		o.target_unit = target
		o.queued = is_queued
		return o

	static func stop() -> Order:
		return Order.new(OrderType.STOP)

	static func hold() -> Order:
		return Order.new(OrderType.HOLD_POSITION)

	static func cast_point(ability: int, pos: Vector3, is_queued: bool = false) -> Order:
		var o = Order.new(OrderType.CAST_POINT)
		o.ability_id = ability
		o.target_position = pos
		o.queued = is_queued
		return o

	static func cast_target(ability: int, target: Node3D, is_queued: bool = false) -> Order:
		var o = Order.new(OrderType.CAST_TARGET)
		o.ability_id = ability
		o.target_unit = target
		o.queued = is_queued
		return o

	static func cast_immediate(ability: int, is_queued: bool = false) -> Order:
		var o = Order.new(OrderType.CAST_IMMEDIATE)
		o.ability_id = ability
		o.queued = is_queued
		return o

	static func follow_unit(target: Node3D, is_queued: bool = false) -> Order:
		var o = Order.new(OrderType.FOLLOW)
		o.target_unit = target
		o.queued = is_queued
		return o
