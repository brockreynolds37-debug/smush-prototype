extends Node

## Credits screen — scrolling credits with Collective flavor text commentary.
## Accessible from main menu. ESC or click backdrop to exit.

signal credits_closed

var _canvas: CanvasLayer = null
var _scroll_container: ScrollContainer = null
var _content_vbox: VBoxContainer = null
var _scroll_tween: Tween = null
var _is_open: bool = false

# Collective commentary that appears as flavor dividers between sections
const COLLECTIVE_LINES := [
	"\"We observed. We judged. We are the reason they kept going.\"",
	"\"Every death was a performance. Thank you for the entertainment.\"",
	"\"The dungeon did not build itself. Nor did it kill you. We did that.\"",
	"\"Do you believe in fate? We do. We wrote yours.\"",
	"\"Some who made this game have never met. The Collective approves.\"",
	"\"Credit where credit is due. Then back into the arena.\"",
	"\"These names made the machine. The machine made you suffer. You're welcome.\"",
]

func show_credits() -> void:
	if _is_open:
		return
	_is_open = true
	_build_credits_ui()

func close_credits() -> void:
	if not _is_open:
		return
	_is_open = false
	if _scroll_tween:
		_scroll_tween.kill()
		_scroll_tween = null
	if _canvas and is_instance_valid(_canvas):
		_canvas.queue_free()
		_canvas = null
	emit_signal("credits_closed")

func _build_credits_ui() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 60
	add_child(_canvas)

	# Full-screen dark backdrop — click to close
	var backdrop = ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.92)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			close_credits()
	)
	_canvas.add_child(backdrop)

	# Title header (fixed, above scroll area)
	var header_label = Label.new()
	header_label.text = "CREDITS"
	header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header_label.add_theme_font_size_override("font_size", 52)
	header_label.add_theme_color_override("font_color", Color(0.95, 0.8, 0.4))
	header_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	header_label.offset_top = 28
	header_label.offset_bottom = 90
	header_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(header_label)

	# Scroll container
	_scroll_container = ScrollContainer.new()
	_scroll_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll_container.offset_top = 100
	_scroll_container.offset_bottom = -50
	_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_scroll_container)

	# Inner vbox with centered credits content
	_content_vbox = VBoxContainer.new()
	_content_vbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	_content_vbox.add_theme_constant_override("separation", 0)
	_content_vbox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER | Control.SIZE_EXPAND
	_content_vbox.custom_minimum_size = Vector2(700, 0)
	_scroll_container.add_child(_content_vbox)

	# Build the content
	_add_spacer(120)
	_add_flavor_collective(COLLECTIVE_LINES[0])
	_add_spacer(60)

	# Core team
	_add_section_header("DEVELOPED BY")
	_add_spacer(14)
	_add_credit("Brock Reynolds", "Game Designer / Founder")
	_add_credit("Minerva (AI)", "Systems Architect / Lead Developer")
	_add_spacer(10)
	_add_body_text("\"Developed in the dark by a single human and an AI familiar.\"")
	_add_spacer(60)

	_add_flavor_collective(COLLECTIVE_LINES[1])
	_add_spacer(60)

	# Engine & tools
	_add_section_header("BUILT WITH")
	_add_spacer(14)
	_add_tool_credit("Godot Engine 4.4", "The game engine. Free and open source.", "https://godotengine.org")
	_add_tool_credit("KayKit Dungeon Remastered", "Dungeon tileset and 3D models.", "https://kaylousberg.com")
	_add_tool_credit("KayKit Adventurers", "Character models and animations.", "https://kaylousberg.com")
	_add_tool_credit("Kenney.nl Assets", "Environment props, dungeon elements.", "https://kenney.nl")
	_add_tool_credit("Blender 5.1", "3D rendering and store page assets.", "https://blender.org")
	_add_tool_credit("Claude (Anthropic)", "AI development assistant.", "https://anthropic.com")
	_add_spacer(60)

	_add_flavor_collective(COLLECTIVE_LINES[2])
	_add_spacer(60)

	# Music & audio
	_add_section_header("AUDIO")
	_add_spacer(14)
	_add_credit("Procedural Audio System", "Generated via AudioManager")
	_add_body_text("All audio generated programmatically.\nNo sound designers were harmed in the making of this dungeon.")
	_add_spacer(60)

	_add_flavor_collective(COLLECTIVE_LINES[3])
	_add_spacer(60)

	# Special thanks
	_add_section_header("SPECIAL THANKS")
	_add_spacer(14)
	_add_body_text("The Reynolds Family —\nFor tolerating late nights and the sound of GDScript error logs.")
	_add_spacer(20)
	_add_body_text("The Godot Community —\nFor building a game engine that doesn't hate you.")
	_add_spacer(20)
	_add_body_text("Kay Lousberg —\nFor making 3D accessible to solo developers everywhere.")
	_add_spacer(20)
	_add_body_text("Kenney —\nThe patron saint of game jams.")
	_add_spacer(60)

	_add_flavor_collective(COLLECTIVE_LINES[4])
	_add_spacer(60)

	# The Collective
	_add_section_header("THE COLLECTIVE")
	_add_spacer(14)
	_add_body_text("A mysterious audience of unknown origin.\nThey came to watch. They stayed to judge.\nThey are always watching.")
	_add_spacer(20)
	_add_body_text("\"We do not forgive. We do not forget. We do review-bomb.\"")
	_add_spacer(60)

	_add_flavor_collective(COLLECTIVE_LINES[5])
	_add_spacer(60)

	# Version
	_add_section_header("VERSION")
	_add_spacer(14)
	_add_credit("Smush v0.1.0", "Prototype Build")
	_add_body_text("Steam release target: Q4 2026")
	_add_spacer(60)

	_add_flavor_collective(COLLECTIVE_LINES[6])
	_add_spacer(60)

	# Closing
	_add_section_header("DEDICATED TO")
	_add_spacer(14)
	_add_body_text("Everyone who ever wondered what would happen\nif you put too many goblins in a room with a timer.")
	_add_spacer(20)
	_add_body_text("Now you know.")
	_add_spacer(160)

	# Close hint
	var hint = Label.new()
	hint.text = "Press ESC or click to return"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.35, 0.35, 0.4))
	_content_vbox.add_child(hint)
	_add_spacer(80)

	# Start auto-scroll after a short delay
	await get_tree().create_timer(1.2).timeout
	if not _is_open:
		return
	_start_auto_scroll()

func _start_auto_scroll() -> void:
	if not _scroll_container or not is_instance_valid(_scroll_container):
		return
	# Total scrollable height = content height - visible height
	var total_scroll := _content_vbox.size.y - _scroll_container.size.y
	if total_scroll <= 0:
		total_scroll = 3000.0  # fallback if layout not ready
	var scroll_duration := total_scroll / 60.0  # ~60 px per second
	_scroll_tween = create_tween()
	_scroll_tween.tween_property(_scroll_container, "scroll_vertical", int(total_scroll), scroll_duration)
	_scroll_tween.tween_callback(func():
		# Hold at bottom for 4s then auto-close
		await get_tree().create_timer(4.0).timeout
		close_credits()
	)

func _add_spacer(height: int) -> void:
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_vbox.add_child(spacer)

func _add_section_header(text: String) -> void:
	var lbl = Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 26)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.7, 0.35))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_vbox.add_child(lbl)

	# Underline separator
	var sep = ColorRect.new()
	sep.color = Color(0.6, 0.4, 0.15, 0.5)
	sep.custom_minimum_size = Vector2(320, 1)
	sep.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_vbox.add_child(sep)
	_add_spacer(6)

func _add_credit(name: String, role: String) -> void:
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 32)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_vbox.add_child(hbox)

	var name_lbl = Label.new()
	name_lbl.text = name
	name_lbl.custom_minimum_size = Vector2(220, 0)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	name_lbl.add_theme_font_size_override("font_size", 20)
	name_lbl.add_theme_color_override("font_color", Color(0.92, 0.88, 0.8))
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(name_lbl)

	var role_lbl = Label.new()
	role_lbl.text = role
	role_lbl.custom_minimum_size = Vector2(280, 0)
	role_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	role_lbl.add_theme_font_size_override("font_size", 18)
	role_lbl.add_theme_color_override("font_color", Color(0.55, 0.52, 0.6))
	role_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(role_lbl)
	_add_spacer(4)

func _add_tool_credit(tool_name: String, description: String, _url: String) -> void:
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.custom_minimum_size = Vector2(560, 0)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_vbox.add_child(vbox)

	var name_lbl = Label.new()
	name_lbl.text = tool_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 20)
	name_lbl.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_lbl)

	var desc_lbl = Label.new()
	desc_lbl.text = description
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.add_theme_font_size_override("font_size", 15)
	desc_lbl.add_theme_color_override("font_color", Color(0.48, 0.48, 0.55))
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(desc_lbl)
	_add_spacer(10)

func _add_body_text(text: String) -> void:
	var lbl = Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(560, 0)
	lbl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	lbl.add_theme_font_size_override("font_size", 17)
	lbl.add_theme_color_override("font_color", Color(0.65, 0.62, 0.72))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_vbox.add_child(lbl)
	_add_spacer(8)

func _add_flavor_collective(line: String) -> void:
	# Decorative separator
	var sep_box = HBoxContainer.new()
	sep_box.alignment = BoxContainer.ALIGNMENT_CENTER
	sep_box.add_theme_constant_override("separation", 12)
	sep_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_vbox.add_child(sep_box)

	for _i in 3:
		var dot = Label.new()
		dot.text = "◆"
		dot.add_theme_font_size_override("font_size", 12)
		dot.add_theme_color_override("font_color", Color(0.5, 0.35, 0.15, 0.6))
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sep_box.add_child(dot)

	_add_spacer(16)

	var lbl = Label.new()
	lbl.text = line
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(580, 0)
	lbl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(0.45, 0.38, 0.55))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_vbox.add_child(lbl)
	_add_spacer(16)

	# Bottom decorative separator
	var sep_box2 = HBoxContainer.new()
	sep_box2.alignment = BoxContainer.ALIGNMENT_CENTER
	sep_box2.add_theme_constant_override("separation", 12)
	sep_box2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_vbox.add_child(sep_box2)

	for _i in 3:
		var dot = Label.new()
		dot.text = "◆"
		dot.add_theme_font_size_override("font_size", 12)
		dot.add_theme_color_override("font_color", Color(0.5, 0.35, 0.15, 0.6))
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sep_box2.add_child(dot)

func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
			close_credits()
			get_viewport().set_input_as_handled()
