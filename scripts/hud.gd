extends CanvasLayer

## WC3-style HUD with portrait, bars, ability buttons, minimap placeholder.

@onready var health_bar: ProgressBar = %HealthBar
@onready var mana_bar: ProgressBar = %ManaBar
@onready var portrait: ColorRect = %Portrait
@onready var ability_q: Button = %AbilityQ
@onready var ability_w: Button = %AbilityW
@onready var ability_e: Button = %AbilityE
@onready var ability_r: Button = %AbilityR
@onready var cooldown_q: ColorRect = %CooldownQ
@onready var cooldown_w: ColorRect = %CooldownW
@onready var cooldown_e: ColorRect = %CooldownE
@onready var cooldown_r: ColorRect = %CooldownR
@onready var minimap_frame: ColorRect = %MinimapFrame

var cooldown_labels: Array[ColorRect] = []

func _ready() -> void:
	cooldown_labels = [cooldown_q, cooldown_w, cooldown_e, cooldown_r]
	# Connect to hero when available
	await get_tree().process_frame
	_connect_hero()

func _connect_hero() -> void:
	var hero = GameManager.hero
	if hero:
		hero.health_changed.connect(_on_health_changed)
		hero.mana_changed.connect(_on_mana_changed)
		hero.spell_cooldown_updated.connect(_on_cooldown_updated)

func _on_health_changed(current: int, maximum: int) -> void:
	health_bar.max_value = maximum
	health_bar.value = current

func _on_mana_changed(current: int, maximum: int) -> void:
	mana_bar.max_value = maximum
	mana_bar.value = current

func _on_cooldown_updated(spell_index: int, remaining: float, total: float) -> void:
	if spell_index < cooldown_labels.size():
		var cd_rect = cooldown_labels[spell_index]
		if remaining > 0:
			cd_rect.visible = true
			# Shrink the overlay from full to zero as cooldown completes
			var ratio = remaining / total
			cd_rect.custom_minimum_size.y = 60 * ratio
			cd_rect.size.y = 60 * ratio
		else:
			cd_rect.visible = false
