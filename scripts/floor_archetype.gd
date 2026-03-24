extends RefCounted

## FloorArchetype — abstract base class for floor gameplay modes.
## Each archetype defines a unique win condition, enemy spawning rules,
## camera behavior, and UI hints. Subclasses override these methods.
##
## Usage:
##   var archetype = EscapeArchetype.new()
##   archetype.setup(builder, units_node, floor_number)
##   archetype.start()
##   # In _process: archetype.update(delta)
##   # Archetype emits floor_completed when win condition is met.

class_name FloorArchetype

signal floor_completed
signal archetype_ui_message(text: String, color: Color, duration: float)

## Human-readable name shown in loading screen and HUD
var archetype_name: String = "Unknown"
## Short flavor text for the archetype
var flavor_text: String = ""
## Accent color for UI hints
var accent_color: Color = Color.WHITE

## References set by setup()
var builder: Node3D = null
var units_node: Node3D = null
var floor_number: int = 1
var _is_active: bool = false

## Set up the archetype with dungeon references. Called once before start().
func setup(p_builder: Node3D, p_units_node: Node3D, p_floor_number: int) -> void:
	builder = p_builder
	units_node = p_units_node
	floor_number = p_floor_number

## Start the archetype gameplay. Called after dungeon is built and hero is placed.
func start() -> void:
	_is_active = true

## Per-frame update. Called from dungeon_floor1_scene._process().
func update(_delta: float) -> void:
	pass

## Called when the archetype should clean up (floor transition, hero death, etc.)
func stop() -> void:
	_is_active = false

## Should this archetype spawn a boss? Override to return false for non-boss modes.
func has_boss() -> bool:
	return true

## Should the Smusher timer run on this floor?
func has_smusher() -> bool:
	return true

## Should the merchant appear before this floor? Boss Rush skips it.
func has_merchant() -> bool:
	return true

## Should the exit portal be visible from the start? Some archetypes hide it.
func exit_visible_at_start() -> bool:
	return false

## Should enemies be spawned by the default spawner? Some archetypes handle their own.
func uses_default_enemy_spawning() -> bool:
	return true

## Override to return custom enemy spawn data. Ignored if uses_default_enemy_spawning().
func get_custom_enemy_spawns() -> Array[Dictionary]:
	return []

## Override to add archetype-specific HUD elements. Returns a Control (or null).
func create_hud_overlay() -> Control:
	return null

## Override to remove archetype-specific HUD elements.
func destroy_hud_overlay() -> void:
	pass

## Complete the floor — call this when win condition is met.
func complete() -> void:
	_is_active = false
	floor_completed.emit()

## Send a UI message (archetype_ui_message signal → picked up by HUD).
func show_message(text: String, color: Color = Color.WHITE, duration: float = 2.0) -> void:
	archetype_ui_message.emit(text, color, duration)
