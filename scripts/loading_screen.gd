extends CanvasLayer

## Loading screen shown during floor transitions.
## Displays floor name and a random gameplay tip to mask rebuild stutter.

signal loading_dismissed

const FLOOR_NAMES := {
	0: "Training Grounds",
	1: "The Sift",
	2: "The Crucible",
	3: "The Crush",
	4: "The Deep",
}

const TIPS := [
	"Enemies drop better loot on higher floors.",
	"The Smush Timer waits for no one — keep moving!",
	"Ground Slam damages barrels and nearby breakables.",
	"Elite enemies glow and give 2.5x XP. Worth the risk.",
	"Equipping weapons with +STR boosts your melee damage.",
	"Staves boost spell power — great for casters like Elara.",
	"The audience rewards variety. Mix up your attacks!",
	"Dodge spike traps by watching for the warning glow.",
	"Poison pools apply DOT — don't stand in the green.",
	"Fire vents burst every 4 seconds. Time your crossing.",
	"Open chests for guaranteed multi-item drops.",
	"The merchant appears between floors. Save some gold!",
	"Sponsors offer powerful bargains — read the fine print.",
	"Healing spells are more valuable at low HP. Don't panic-cast.",
	"Each civilization has a unique innate trait. Choose wisely.",
	"Level 5 unlocks your third spell. Level 10 unlocks the fourth.",
	"Skill points from leveling up can be spent in the skill tree.",
	"Press I or Tab to open your inventory.",
	"Hover inventory items to compare stats with equipped gear.",
	"Armor reduces incoming damage by a flat amount.",
	"The Narrator speaks less in The Deep. You're on your own.",
	"Combo kills raise the audience mood faster.",
	"When overtime hits, rooms collapse from spawn toward the exit.",
	"Berserker Rage activates below 30% HP — risk vs reward.",
	"Phase Walk charges refresh each floor. Use them or lose them.",
]

var _panel: PanelContainer
var _floor_label: Label
var _tip_label: Label
var _dots_label: Label
var _min_display_time: float = 1.2
var _is_showing: bool = false
var _dot_timer: float = 0.0
var _dot_count: int = 0

func _ready() -> void:
	layer = 99  # Below transition overlay (100) but above everything else
	process_mode = Node.PROCESS_MODE_ALWAYS

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.02, 0.04, 1.0)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.visible = false
	add_child(_panel)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 24)
	_panel.add_child(vbox)

	# Center container to hold the vbox properly
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(center)

	var inner_vbox = VBoxContainer.new()
	inner_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	inner_vbox.add_theme_constant_override("separation", 20)
	center.add_child(inner_vbox)

	# Floor name label
	_floor_label = Label.new()
	_floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_floor_label.add_theme_font_size_override("font_size", 42)
	_floor_label.add_theme_color_override("font_color", Color(0.85, 0.72, 0.38))
	_floor_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_floor_label.add_theme_constant_override("shadow_offset_x", 2)
	_floor_label.add_theme_constant_override("shadow_offset_y", 2)
	inner_vbox.add_child(_floor_label)

	# Animated dots
	_dots_label = Label.new()
	_dots_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dots_label.add_theme_font_size_override("font_size", 28)
	_dots_label.add_theme_color_override("font_color", Color(0.5, 0.45, 0.3, 0.7))
	inner_vbox.add_child(_dots_label)

	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	inner_vbox.add_child(spacer)

	# Tip label
	_tip_label = Label.new()
	_tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip_label.add_theme_font_size_override("font_size", 18)
	_tip_label.add_theme_color_override("font_color", Color(0.6, 0.58, 0.52, 0.85))
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.custom_minimum_size = Vector2(500, 0)
	inner_vbox.add_child(_tip_label)

func _process(delta: float) -> void:
	if not _is_showing:
		return
	# Animate loading dots
	_dot_timer += delta
	if _dot_timer >= 0.4:
		_dot_timer = 0.0
		_dot_count = (_dot_count + 1) % 4
		_dots_label.text = ".".repeat(_dot_count)

func show_loading(floor_number: int) -> void:
	_is_showing = true
	_dot_count = 0
	_dot_timer = 0.0

	# Floor name
	var floor_name: String
	if FLOOR_NAMES.has(floor_number):
		floor_name = FLOOR_NAMES[floor_number]
	elif floor_number >= 4:
		floor_name = "The Deep — Floor %d" % floor_number
	else:
		floor_name = "Floor %d" % floor_number

	# Show archetype name if non-standard
	var archetype_suffix := ""
	if FloorManager.current_archetype and FloorManager.current_archetype.archetype_name != "Dungeon Crawl":
		archetype_suffix = " — %s" % FloorManager.current_archetype.archetype_name

	_floor_label.text = "Entering %s%s" % [floor_name, archetype_suffix]
	_dots_label.text = ""

	# Random tip
	_tip_label.text = TIPS[randi() % TIPS.size()]

	# Theme color per tier
	var title_color: Color
	match floor_number:
		0: title_color = Color(0.5, 0.7, 0.5)  # Green for tutorial
		1: title_color = Color(0.75, 0.68, 0.55)  # Warm stone
		2: title_color = Color(0.85, 0.72, 0.38)  # Gold
		3: title_color = Color(0.7, 0.3, 0.6)  # Purple
		_: title_color = Color(0.4, 0.8, 0.7)  # Eerie teal for The Deep
	_floor_label.add_theme_color_override("font_color", title_color)

	# Fade in
	_panel.visible = true
	_panel.modulate = Color(1, 1, 1, 0)
	var fade_in = create_tween()
	fade_in.tween_property(_panel, "modulate", Color(1, 1, 1, 1), 0.3)

func hide_loading() -> void:
	if not _is_showing:
		return
	_is_showing = false
	var fade_out = create_tween()
	fade_out.tween_property(_panel, "modulate", Color(1, 1, 1, 0), 0.4)
	await fade_out.finished
	_panel.visible = false
	loading_dismissed.emit()
