extends CanvasLayer

## ChatConsole — in-game console toggled with ~ (tilde/backtick).
## Commands prefixed with - (WC3 style): -stats, -gold, -time, -seed, -difficulty.
## Cheat codes only work in debug builds.

var _visible: bool = false
var _panel: PanelContainer = null
var _input: LineEdit = null
var _output: RichTextLabel = null
var _history: Array[String] = []
var _history_idx: int = -1

const MAX_OUTPUT_LINES := 50

func _ready() -> void:
	layer = 100
	_build_ui()
	_panel.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_QUOTELEFT:  # ~ / backtick
			_toggle()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and _visible:
			_toggle()
			get_viewport().set_input_as_handled()

func _toggle() -> void:
	_visible = not _visible
	_panel.visible = _visible
	if _visible:
		_input.grab_focus()
		_input.text = ""
		get_tree().paused = true
	else:
		get_tree().paused = false

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "ConsolePanel"
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.1, 0.92)
	style.border_color = Color(0.3, 0.3, 0.5)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	_panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	_panel.add_child(vbox)

	# Title bar
	var title = Label.new()
	title.text = "Console (~)"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
	vbox.add_child(title)

	# Output area
	_output = RichTextLabel.new()
	_output.name = "Output"
	_output.bbcode_enabled = true
	_output.custom_minimum_size = Vector2(500, 200)
	_output.scroll_following = true
	_output.add_theme_font_size_override("normal_font_size", 13)
	_output.add_theme_color_override("default_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(_output)

	# Input line
	_input = LineEdit.new()
	_input.name = "Input"
	_input.placeholder_text = "Type a command (e.g. -stats, -help)..."
	_input.add_theme_font_size_override("font_size", 14)
	_input.text_submitted.connect(_on_command_submitted)
	vbox.add_child(_input)

	# Position: bottom-left
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_panel.position = Vector2(10, -280)
	_panel.size = Vector2(520, 270)
	_panel.process_mode = Node.PROCESS_MODE_ALWAYS

	add_child(_panel)

	_print_line("[color=cyan]Console ready. Type -help for commands.[/color]")

func _on_command_submitted(text: String) -> void:
	if text.strip_edges().is_empty():
		return

	_input.text = ""
	_history.append(text)
	_history_idx = _history.size()

	_print_line("[color=gray]> %s[/color]" % text)
	_execute(text.strip_edges())

func _execute(cmd: String) -> void:
	# Strip leading dash
	if cmd.begins_with("-"):
		cmd = cmd.substr(1)

	var parts := cmd.split(" ", false)
	if parts.is_empty():
		return

	var command := parts[0].to_lower()
	var args := parts.slice(1)

	match command:
		"help":
			_cmd_help()
		"stats":
			_cmd_stats()
		"gold":
			_cmd_gold(args)
		"time":
			_cmd_time()
		"seed":
			_cmd_seed()
		"difficulty", "diff":
			_cmd_difficulty()
		"floor":
			_cmd_floor()
		"hp":
			_cmd_hp(args)
		"mana":
			_cmd_mana(args)
		"level", "lvl":
			_cmd_level()
		"kill", "kills":
			_cmd_kills()
		"audience", "vp":
			_cmd_audience()
		"archetype":
			_cmd_archetype()
		"path", "paths":
			_cmd_path()
		"faction", "factions", "rep":
			_cmd_factions()
		"consequence", "consequences", "tags":
			_cmd_consequences()
		"replays":
			_cmd_replays()
		"clear", "cls":
			_output.clear()
		# ── CHEAT CODES (debug only) ──
		"greedisgood":
			_cheat_gold(args)
		"whosyourdaddy":
			_cheat_godmode()
		"thereisnospoon":
			_cheat_mana()
		"iseedeadpeople":
			_cheat_reveal()
		"motherload":
			_cheat_loot()
		_:
			_print_line("[color=red]Unknown command: -%s[/color]" % command)
			_print_line("[color=gray]Type -help for available commands.[/color]")

# ── INFO COMMANDS ──

func _cmd_help() -> void:
	_print_line("[color=cyan]── Commands ──[/color]")
	_print_line("-stats    Show run statistics")
	_print_line("-gold     Show gold (or -gold <amount> in debug)")
	_print_line("-time     Show run elapsed time")
	_print_line("-seed     Show current random seed")
	_print_line("-difficulty  Show current difficulty")
	_print_line("-floor    Show current floor info")
	_print_line("-hp       Show hero HP (or -hp <amount> in debug)")
	_print_line("-mana     Show hero mana")
	_print_line("-level    Show hero level and XP")
	_print_line("-kills    Show kill count")
	_print_line("-vp       Show audience VP and mood")
	_print_line("-archetype  Show current floor archetype")
	_print_line("-path       Show current solution path")
	_print_line("-faction    Show faction reputation")
	_print_line("-tags       Show cross-floor consequence tags")
	_print_line("-replays  List saved replays")
	_print_line("-clear    Clear console output")
	if OS.is_debug_build():
		_print_line("[color=yellow]── Cheats (debug only) ──[/color]")
		_print_line("-greedisgood [n]  Add gold")
		_print_line("-whosyourdaddy    God mode (full heal)")
		_print_line("-thereisnospoon   Full mana")
		_print_line("-motherload       Drop random legendary")

func _cmd_stats() -> void:
	var s := RunStats.get_summary()
	_print_line("[color=cyan]── Run Stats ──[/color]")
	_print_line("Floor: %d | Kills: %d" % [FloorManager.current_floor, GameManager.run_kills])
	_print_line("Gold: %d | Damage dealt: %d" % [LootManager.gold, GameManager.run_damage_dealt])
	_print_line("Level: %d | XP: %d" % [XpManager.current_level, XpManager.current_xp])
	_print_line("VP: %d | Difficulty: %s" % [AudienceManager.total_vp, GameManager.get_difficulty_name()])

func _cmd_gold(args: Array) -> void:
	if args.size() > 0 and OS.is_debug_build():
		var amount := int(args[0])
		LootManager.gold += amount
		LootManager.gold_changed.emit(LootManager.gold)
		_print_line("[color=yellow]Added %d gold. Total: %d[/color]" % [amount, LootManager.gold])
	else:
		_print_line("Gold: %d" % LootManager.gold)

func _cmd_time() -> void:
	var t := GameManager.get_run_elapsed()
	_print_line("Run time: %d:%02d" % [int(t) / 60, int(t) % 60])

func _cmd_seed() -> void:
	# Godot doesn't expose the current seed easily, show a hash instead
	var seed_hash := hash(Time.get_ticks_msec())
	_print_line("Seed hash: %d" % seed_hash)

func _cmd_difficulty() -> void:
	_print_line("Difficulty: %s (multiplier: %.1fx)" % [
		GameManager.get_difficulty_name(),
		GameManager.get_difficulty_multiplier()
	])

func _cmd_floor() -> void:
	_print_line("Floor: %d (max reached: %d)" % [FloorManager.current_floor, FloorManager.max_floor_reached])
	if FloorManager.current_archetype:
		_print_line("Archetype: %s" % FloorManager.current_archetype.archetype_name)

func _cmd_hp(args: Array) -> void:
	var hero = GameManager.hero
	if not hero or not is_instance_valid(hero):
		_print_line("[color=red]No hero active.[/color]")
		return

	if args.size() > 0 and OS.is_debug_build():
		var amount := int(args[0])
		hero.current_health = mini(hero.current_health + amount, hero.max_health)
		hero.health_changed.emit(hero.current_health, hero.max_health)
		_print_line("[color=yellow]HP set to %d/%d[/color]" % [hero.current_health, hero.max_health])
	else:
		_print_line("HP: %d/%d" % [hero.current_health, hero.max_health])

func _cmd_mana(args: Array) -> void:
	var hero = GameManager.hero
	if not hero or not is_instance_valid(hero):
		_print_line("[color=red]No hero active.[/color]")
		return
	_print_line("Mana: %d/%d" % [hero.current_mana, hero.max_mana])

func _cmd_level() -> void:
	_print_line("Level: %d | XP: %d / %d" % [XpManager.current_level, XpManager.current_xp, XpManager.get_xp_for_next_level()])

func _cmd_kills() -> void:
	_print_line("Total kills this run: %d" % GameManager.run_kills)

func _cmd_audience() -> void:
	_print_line("VP: %d | Mood: %s" % [AudienceManager.total_vp, AudienceManager.get_mood_name()])

func _cmd_archetype() -> void:
	if FloorManager.current_archetype:
		var a = FloorManager.current_archetype
		_print_line("Archetype: %s" % a.archetype_name)
		_print_line("\"%s\"" % a.flavor_text)
	else:
		_print_line("No archetype active.")

func _cmd_path() -> void:
	var path := SolutionPathTracker.get_dominant_path()
	var label := SolutionPathTracker.get_path_label()
	var scores := SolutionPathTracker.get_scores()
	_print_line("[color=cyan]── Solution Path ──[/color]")
	_print_line("Current: %s (%s)" % [label, path])
	_print_line("Scores: combat=%d speed=%d social=%d clever=%d" % [
		scores.get("combat", 0), scores.get("speed", 0),
		scores.get("social", 0), scores.get("clever", 0),
	])
	if SolutionPathTracker.is_audience_favorite_path():
		_print_line("[color=green]Audience loves this approach![/color]")
	var history := SolutionPathTracker.floor_history
	if not history.is_empty():
		_print_line("History: %s" % ", ".join(SolutionPathTracker.last_three_paths))

func _cmd_factions() -> void:
	_print_line("[color=cyan]── Faction Reputation ──[/color]")
	var summary := FactionManager.get_reputation_summary()
	_print_line(summary)

func _cmd_replays() -> void:
	var replays := ReplayManager.list_replays()
	if replays.is_empty():
		_print_line("No saved replays.")
		return
	_print_line("[color=cyan]── Saved Replays (%d) ──[/color]" % replays.size())
	for r in replays:
		_print_line("%s | %s | Floor %d | %d kills" % [
			r.get("date", "?"),
			r.get("character", "?"),
			r.get("floors_cleared", 0),
			r.get("total_kills", 0),
		])

func _cmd_consequences() -> void:
	_print_line("[color=cyan]── Cross-Floor Consequences ──[/color]")
	if CrossFloorConsequences.tags.is_empty():
		_print_line("No choice tags set yet.")
	else:
		for tag in CrossFloorConsequences.tags:
			var info: Dictionary = CrossFloorConsequences.tags[tag]
			_print_line("  [%s] set on floor %d" % [tag, info.get("floor_set", 0)])
	var effects := CrossFloorConsequences.get_active_effects()
	if not effects.is_empty():
		_print_line("[color=yellow]Active effects:[/color]")
		for e in effects:
			_print_line("  %s: %s" % [e.get("type", "?"), e.get("data", {}).get("reason", "")])
	var discount := CrossFloorConsequences.get_vendor_discount()
	if discount != 1.0:
		_print_line("Vendor price mult: %.2fx" % discount)

# ── CHEAT CODES ──

func _cheat_gold(args: Array) -> void:
	if not OS.is_debug_build():
		_print_line("[color=red]Cheats only work in debug builds.[/color]")
		return
	var amount := 500
	if args.size() > 0:
		amount = int(args[0])
	LootManager.gold += amount
	LootManager.gold_changed.emit(LootManager.gold)
	_print_line("[color=yellow]CHEAT: +%d gold (total: %d)[/color]" % [amount, LootManager.gold])

func _cheat_godmode() -> void:
	if not OS.is_debug_build():
		_print_line("[color=red]Cheats only work in debug builds.[/color]")
		return
	var hero = GameManager.hero
	if hero and is_instance_valid(hero):
		hero.current_health = hero.max_health
		hero.health_changed.emit(hero.current_health, hero.max_health)
		_print_line("[color=yellow]CHEAT: Full health restored.[/color]")
	else:
		_print_line("[color=red]No hero active.[/color]")

func _cheat_mana() -> void:
	if not OS.is_debug_build():
		_print_line("[color=red]Cheats only work in debug builds.[/color]")
		return
	var hero = GameManager.hero
	if hero and is_instance_valid(hero):
		hero.current_mana = hero.max_mana
		hero.mana_changed.emit(hero.current_mana, hero.max_mana)
		_print_line("[color=yellow]CHEAT: Full mana restored.[/color]")
	else:
		_print_line("[color=red]No hero active.[/color]")

func _cheat_reveal() -> void:
	if not OS.is_debug_build():
		_print_line("[color=red]Cheats only work in debug builds.[/color]")
		return
	_print_line("[color=yellow]CHEAT: Map revealed (not yet implemented).[/color]")

func _cheat_loot() -> void:
	if not OS.is_debug_build():
		_print_line("[color=red]Cheats only work in debug builds.[/color]")
		return
	# Give a massive gold bonus as substitute for loot drop
	LootManager.gold += 999
	LootManager.gold_changed.emit(LootManager.gold)
	_print_line("[color=yellow]CHEAT: +999 gold! (Total: %d)[/color]" % LootManager.gold)

# ── UTILITY ──

func _print_line(text: String) -> void:
	_output.append_text(text + "\n")
