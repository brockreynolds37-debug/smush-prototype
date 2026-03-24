extends Node3D

## Audience Gift — falls from the sky with a parachute when the crowd gets excited.
## Gift types: heal, mana, weapon, cruel_trick (bomb).

enum GiftType { HEAL, MANA, WEAPON, CRUEL_TRICK }

var gift_type: GiftType = GiftType.HEAL
var _fall_speed: float = 6.0
var _target_y: float = 0.5
var _landed: bool = false
var _picked_up: bool = false
var _time: float = 0.0
var _parachute: MeshInstance3D = null
var _box: MeshInstance3D = null
var _glow: OmniLight3D = null

const GIFT_COLORS := {
	GiftType.HEAL: Color(0.2, 1.0, 0.3),
	GiftType.MANA: Color(0.3, 0.5, 1.0),
	GiftType.WEAPON: Color(1.0, 0.85, 0.1),
	GiftType.CRUEL_TRICK: Color(1.0, 0.15, 0.15),
}

const GIFT_LABELS := {
	GiftType.HEAL: "HEAL GIFT",
	GiftType.MANA: "MANA GIFT",
	GiftType.WEAPON: "WEAPON DROP",
	GiftType.CRUEL_TRICK: "MYSTERY GIFT",
}

func _ready() -> void:
	_build_visual()

func _build_visual() -> void:
	var color: Color = GIFT_COLORS.get(gift_type, Color.WHITE)

	# Parachute — inverted cone above the gift
	_parachute = MeshInstance3D.new()
	var chute_mesh := ConeMesh.new()
	chute_mesh.radius = 1.2
	chute_mesh.height = 0.8
	_parachute.mesh = chute_mesh
	_parachute.position = Vector3(0, 2.0, 0)
	# Flip upside down so the wide end is on top
	_parachute.rotation_degrees.x = 180.0

	var chute_mat := StandardMaterial3D.new()
	chute_mat.albedo_color = color.lerp(Color.WHITE, 0.4)
	chute_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	chute_mat.albedo_color.a = 0.7
	chute_mat.emission_enabled = true
	chute_mat.emission = color * 0.3
	chute_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_parachute.set_surface_override_material(0, chute_mat)
	add_child(_parachute)

	# Gift box
	_box = MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(0.6, 0.6, 0.6)
	_box.mesh = box_mesh

	var box_mat := StandardMaterial3D.new()
	box_mat.albedo_color = color
	box_mat.emission_enabled = true
	box_mat.emission = color
	box_mat.emission_energy_multiplier = 0.6
	box_mat.roughness = 0.3
	box_mat.metallic = 0.2
	_box.set_surface_override_material(0, box_mat)
	add_child(_box)

	# Glow light
	_glow = OmniLight3D.new()
	_glow.light_color = color
	_glow.light_energy = 1.5
	_glow.omni_range = 4.0
	_glow.omni_attenuation = 2.0
	_glow.shadow_enabled = false
	_glow.position = Vector3.UP * 0.5
	add_child(_glow)

func _process(delta: float) -> void:
	if _picked_up:
		return

	_time += delta

	if not _landed:
		# Fall from sky
		position.y -= _fall_speed * delta

		# Sway the parachute
		if _parachute:
			_parachute.rotation_degrees.y += delta * 120.0
			_parachute.position.x = sin(_time * 3.0) * 0.3

		if position.y <= _target_y:
			position.y = _target_y
			_land()
	else:
		# Landed — bob and rotate the box, pulse glow
		if _box:
			_box.rotation.y += delta * 2.5
			_box.position.y = sin(_time * 3.0) * 0.08 + 0.3

		if _glow:
			_glow.light_energy = 1.0 + sin(_time * 4.0) * 0.5

		# Auto-pickup when hero gets close
		if GameManager.hero and not GameManager.hero.is_dead:
			var dist := global_position.distance_to(GameManager.hero.global_position)
			if dist < 2.0:
				_apply_gift()

func _land() -> void:
	_landed = true

	# Remove parachute with a shrink animation
	if _parachute:
		var tween := create_tween()
		tween.tween_property(_parachute, "scale", Vector3.ZERO, 0.3).set_ease(Tween.EASE_IN)
		tween.tween_callback(func():
			if is_instance_valid(_parachute):
				_parachute.queue_free()
				_parachute = null
		)

	# Bounce the box on landing
	if _box:
		_box.scale = Vector3.ONE * 0.01
		var tween := create_tween()
		tween.tween_property(_box, "scale", Vector3.ONE * 1.3, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tween.tween_property(_box, "scale", Vector3.ONE, 0.1)

	# Play a landing sound
	AudioManager.play_sfx("loot_pickup")

	# Emit audience comment about the gift
	var label: String = GIFT_LABELS.get(gift_type, "GIFT")
	var color: Color = GIFT_COLORS.get(gift_type, Color.WHITE)
	AudienceManager.audience_comment.emit(label + " INCOMING!", color)

func _apply_gift() -> void:
	if _picked_up:
		return
	_picked_up = true

	var hero = GameManager.hero
	if hero == null or hero.is_dead:
		_cleanup()
		return

	match gift_type:
		GiftType.HEAL:
			var heal := 200
			hero.current_health = mini(hero.current_health + heal, hero.max_health)
			hero.health_changed.emit(hero.current_health, hero.max_health)
			GameManager.request_damage_number(hero.global_position + Vector3.UP * 2.5, heal, false)
			AudioManager.play_sfx("heal", 0.8)
			AudienceManager.audience_comment.emit("THE CROWD HEALS YOU!", Color(0.2, 1.0, 0.3))

		GiftType.MANA:
			var mana := 120
			hero.current_mana = mini(hero.current_mana + mana, hero.max_mana)
			hero.mana_changed.emit(hero.current_mana, hero.max_mana)
			GameManager.request_damage_number(hero.global_position + Vector3.UP * 2.5, mana, false)
			AudioManager.play_sfx("heal", 0.8)
			AudienceManager.audience_comment.emit("MANA FROM THE FANS!", Color(0.3, 0.5, 1.0))

		GiftType.WEAPON:
			# Give a random weapon from the loot table
			var weapon_ids := ["iron_sword", "steel_sword", "iron_axe", "longbow"]
			var picked_id: String = weapon_ids[randi() % weapon_ids.size()]
			var item_def: Dictionary = LootManager.ITEMS.get(picked_id, {})
			if not item_def.is_empty():
				LootManager.pickup_item(item_def)
			AudioManager.play_sfx("loot_rare")
			AudienceManager.audience_comment.emit("A GIFT FROM THE CROWD!", Color(1.0, 0.85, 0.1))

		GiftType.CRUEL_TRICK:
			# Bomb! Damages the hero
			var damage := 75
			hero.take_damage(damage)
			GameManager.request_screen_shake(6.0, 0.3)
			AudioManager.play_sfx("fireball_explode")
			AudienceManager.audience_comment.emit("HAHA GOTTEM! CRUEL GIFT!", Color(1.0, 0.15, 0.15))

	_cleanup()

func _cleanup() -> void:
	# Fly up and shrink out
	var tween := create_tween()
	if _box:
		tween.tween_property(_box, "scale", Vector3.ZERO, 0.2).set_ease(Tween.EASE_IN)
	if _glow:
		tween.parallel().tween_property(_glow, "light_energy", 4.0, 0.1)
		tween.tween_property(_glow, "light_energy", 0.0, 0.1)
	tween.tween_callback(queue_free)
