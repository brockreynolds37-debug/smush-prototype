extends StaticBody3D

## EasterEggPillar — attack the spawn pillar 5 times for a reward.
## Plays level_up jingle and drops 500 gold.

class_name EasterEggPillar

var _hit_count: int = 0
var _activated: bool = false
const REQUIRED_HITS: int = 5
const GOLD_REWARD: int = 500

func take_damage(_amount: int) -> void:
	if _activated:
		return

	_hit_count += 1
	GameManager.request_screen_shake(1.0, 0.05)

	# Visual feedback — flash the pillar
	var mesh = get_node_or_null("PillarMesh")
	if mesh and mesh is MeshInstance3D:
		var tween = create_tween()
		tween.tween_property(mesh, "scale", Vector3(1.1, 1.1, 1.1), 0.05)
		tween.tween_property(mesh, "scale", Vector3.ONE, 0.1)

	if _hit_count >= REQUIRED_HITS:
		_activate()

func _activate() -> void:
	_activated = true

	# Level up jingle
	AudioManager.play_sfx("level_up", 1.0)
	GameManager.request_screen_shake(6.0, 0.3)

	# Drop 500 gold
	var gold_item = LootManager.ITEMS["gold_pile"].duplicate()
	gold_item["gold_min"] = GOLD_REWARD
	gold_item["gold_max"] = GOLD_REWARD
	LootManager._spawn_drop(global_position + Vector3.UP * 1.5, gold_item)

	# Label
	var label = Label3D.new()
	label.text = "EASTER EGG!"
	label.font_size = 56
	label.modulate = Color(1.0, 0.85, 0.0)
	label.position = Vector3(0, 3.0, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)

	if Narrator:
		Narrator.speak("The ancient pillar rewards the persistent. 500 gold!")
