extends CanvasLayer

## Sponsor System — Faustian bargains offered between floors.
## At medium+ audience popularity (INTERESTED or higher), sponsors appear
## offering deals with significant trade-offs. Decision-making tension.

signal sponsor_closed

var _panel: Panel = null
var _visible: bool = false

# Sponsor deal definitions: each has a benefit and a cost
const DEALS := [
	{
		"name": "Bloodforge Industries",
		"offer": "+50% Attack Damage",
		"cost": "Smusher Timer runs 20% faster",
		"benefit_key": "damage_boost",
		"benefit_value": 0.5,
		"penalty_key": "timer_speed",
		"penalty_value": 0.2,
	},
	{
		"name": "Arcane Surplus Co.",
		"offer": "Free Legendary Weapon",
		"cost": "+3 extra enemies per floor",
		"benefit_key": "free_legendary",
		"benefit_value": 1,
		"penalty_key": "extra_enemies",
		"penalty_value": 3,
	},
	{
		"name": "Vitality Unlimited",
		"offer": "+100 Max HP and full heal",
		"cost": "-30% move speed",
		"benefit_key": "hp_boost",
		"benefit_value": 100,
		"penalty_key": "speed_penalty",
		"penalty_value": 0.3,
	},
	{
		"name": "The Mana Cartel",
		"offer": "-50% spell cooldowns",
		"cost": "-25% spell damage",
		"benefit_key": "cooldown_reduction",
		"benefit_value": 0.5,
		"penalty_key": "spell_damage_penalty",
		"penalty_value": 0.25,
	},
	{
		"name": "Gold Rush Holdings",
		"offer": "+200 Gold immediately",
		"cost": "Audience boredom threshold halved",
		"benefit_key": "gold_grant",
		"benefit_value": 200,
		"penalty_key": "boredom_penalty",
		"penalty_value": 0.5,
	},
	{
		"name": "Berserker Brew LLC",
		"offer": "+75% Attack Speed",
		"cost": "Take 25% more damage",
		"benefit_key": "attack_speed_boost",
		"benefit_value": 0.75,
		"penalty_key": "damage_taken_increase",
		"penalty_value": 0.25,
	},
]

# Active sponsor effects (accumulated across floors)
var active_effects: Dictionary = {}  # effect_key -> total value

func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS

func show_sponsor_offer(floor_number: int) -> void:
	# Only show if audience is at INTERESTED or higher
	if AudienceManager.current_mood < AudienceManager.Mood.INTERESTED:
		sponsor_closed.emit()
		return

	# Pick 2 random deals
	var available := DEALS.duplicate()
	available.shuffle()
	var deal_a: Dictionary = available[0]
	var deal_b: Dictionary = available[1]

	_build_ui(deal_a, deal_b, floor_number)
	_visible = true

func _build_ui(deal_a: Dictionary, deal_b: Dictionary, _floor_number: int) -> void:
	# Dark overlay
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.8)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -400
	_panel.offset_right = 400
	_panel.offset_top = -250
	_panel.offset_bottom = 250
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.06, 0.1, 0.95)
	panel_style.border_color = Color(0.6, 0.4, 0.1)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(8)
	_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_panel)

	# Title
	var title := Label.new()
	title.text = "SPONSOR OFFERS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.95, 0.8, 0.3))
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 15
	title.offset_bottom = 55
	_panel.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "The audience has attracted sponsors. Choose wisely... or decline."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.55, 0.5))
	subtitle.set_anchors_preset(Control.PRESET_TOP_WIDE)
	subtitle.offset_top = 55
	subtitle.offset_bottom = 75
	_panel.add_child(subtitle)

	# Deal A (left side)
	_create_deal_card(deal_a, -370, _panel)
	# Deal B (right side)
	_create_deal_card(deal_b, 30, _panel)

	# Decline button
	var decline_btn := Button.new()
	decline_btn.text = "DECLINE ALL"
	decline_btn.add_theme_font_size_override("font_size", 18)
	decline_btn.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	decline_btn.offset_top = -55
	decline_btn.offset_bottom = -15
	decline_btn.offset_left = 250
	decline_btn.offset_right = -250
	var decline_style := StyleBoxFlat.new()
	decline_style.bg_color = Color(0.15, 0.1, 0.1, 0.9)
	decline_style.border_color = Color(0.4, 0.3, 0.3)
	decline_style.set_border_width_all(1)
	decline_style.set_corner_radius_all(4)
	decline_btn.add_theme_stylebox_override("normal", decline_style)
	decline_btn.add_theme_color_override("font_color", Color(0.6, 0.5, 0.5))
	decline_btn.pressed.connect(_on_decline)
	_panel.add_child(decline_btn)

func _create_deal_card(deal: Dictionary, x_offset: float, parent: Control) -> void:
	var card := Panel.new()
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.offset_left = x_offset
	card.offset_right = x_offset + 340
	card.offset_top = -90
	card.offset_bottom = 100

	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.12, 0.10, 0.14, 0.9)
	card_style.border_color = Color(0.5, 0.35, 0.15)
	card_style.set_border_width_all(1)
	card_style.set_corner_radius_all(6)
	card.add_theme_stylebox_override("panel", card_style)
	parent.add_child(card)

	# Sponsor name
	var name_label := Label.new()
	name_label.text = deal["name"]
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", Color(0.9, 0.75, 0.4))
	name_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	name_label.offset_top = 10
	name_label.offset_bottom = 35
	card.add_child(name_label)

	# Benefit (green)
	var benefit_label := Label.new()
	benefit_label.text = deal["offer"]
	benefit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	benefit_label.add_theme_font_size_override("font_size", 16)
	benefit_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
	benefit_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	benefit_label.offset_top = 45
	benefit_label.offset_bottom = 70
	card.add_child(benefit_label)

	# Cost (red)
	var cost_label := Label.new()
	cost_label.text = deal["cost"]
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_label.add_theme_font_size_override("font_size", 14)
	cost_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	cost_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	cost_label.offset_top = 75
	cost_label.offset_bottom = 95
	card.add_child(cost_label)

	# Accept button
	var accept_btn := Button.new()
	accept_btn.text = "ACCEPT"
	accept_btn.add_theme_font_size_override("font_size", 16)
	accept_btn.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	accept_btn.offset_top = -45
	accept_btn.offset_bottom = -10
	accept_btn.offset_left = 60
	accept_btn.offset_right = -60
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.35, 0.25, 0.08, 0.9)
	btn_style.border_color = Color(0.7, 0.5, 0.15)
	btn_style.set_border_width_all(1)
	btn_style.set_corner_radius_all(4)
	accept_btn.add_theme_stylebox_override("normal", btn_style)
	accept_btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	accept_btn.pressed.connect(_on_accept.bind(deal))
	card.add_child(accept_btn)

func _on_accept(deal: Dictionary) -> void:
	_apply_deal(deal)
	_close()

func _on_decline() -> void:
	_close()

func _close() -> void:
	_visible = false
	for child in get_children():
		child.queue_free()
	sponsor_closed.emit()

func _apply_deal(deal: Dictionary) -> void:
	var benefit_key: String = deal["benefit_key"]
	var benefit_value = deal["benefit_value"]
	var penalty_key: String = deal["penalty_key"]
	var penalty_value = deal["penalty_value"]

	# Accumulate effects
	active_effects[benefit_key] = active_effects.get(benefit_key, 0) + benefit_value
	active_effects[penalty_key] = active_effects.get(penalty_key, 0) + penalty_value

	var hero = GameManager.hero
	if hero == null:
		return

	# Apply benefit
	match benefit_key:
		"damage_boost":
			# Increase attack damage
			if hero.get("base_attack_damage") != null:
				hero.base_attack_damage = int(hero.base_attack_damage * (1.0 + benefit_value))
		"free_legendary":
			# Drop a legendary item
			LootManager._spawn_random_legendary(hero.global_position)
		"hp_boost":
			hero.max_health += int(benefit_value)
			hero.current_health = hero.max_health
			hero.health_changed.emit(hero.current_health, hero.max_health)
		"cooldown_reduction":
			if hero.get("_cooldown_mult") != null:
				hero._cooldown_mult *= (1.0 - benefit_value)
		"gold_grant":
			LootManager.gold += int(benefit_value)
			LootManager.gold_changed.emit(LootManager.gold)
		"attack_speed_boost":
			if hero.get("attack_cooldown") != null:
				hero.attack_cooldown *= (1.0 / (1.0 + benefit_value))

	# Apply penalty
	match penalty_key:
		"timer_speed":
			SmusherTimer.speed_multiplier = SmusherTimer.get("speed_multiplier") if SmusherTimer.get("speed_multiplier") != null else 1.0
			SmusherTimer.speed_multiplier *= (1.0 + penalty_value)
		"extra_enemies":
			# Store for spawn system to read
			GameManager.set_meta("sponsor_extra_enemies", active_effects.get("extra_enemies", 0))
		"speed_penalty":
			if hero.get("_base_move_speed") != null:
				hero._base_move_speed *= (1.0 - penalty_value)
				hero.move_speed = hero._base_move_speed
		"spell_damage_penalty":
			if hero.get("_spell_damage_mult") != null:
				hero._spell_damage_mult *= (1.0 - penalty_value)
		"boredom_penalty":
			# Reduce boredom threshold
			AudienceManager.set("BOREDOM_THRESHOLD", AudienceManager.BOREDOM_THRESHOLD * penalty_value)
		"damage_taken_increase":
			if hero.get("_damage_taken_mult") != null:
				hero._damage_taken_mult *= (1.0 + penalty_value)
			else:
				hero.set_meta("damage_taken_mult", 1.0 + penalty_value)

	# Announce to narrator
	Narrator.narrator_says.emit(
		"A sponsor deal has been struck with %s!" % deal["name"],
		Color(0.95, 0.8, 0.3), 26
	)

func reset() -> void:
	active_effects.clear()
	_visible = false
	for child in get_children():
		child.queue_free()
