extends Node

## Accessibility Settings — colorblind mode, large text, reduced screen shake.
## Autoload singleton. Persists to user://settings.cfg alongside audio settings.

signal settings_changed()

## Colorblind mode: "off", "deuteranopia", "protanopia", "tritanopia"
var colorblind_mode: String = "off"

## UI text scale multiplier (1.0 = default, 1.3 = large, 1.6 = extra large)
var ui_text_scale: float = 1.0

## Screen shake multiplier (1.0 = full, 0.3 = reduced, 0.0 = off)
var screen_shake_scale: float = 1.0

## Screen flash intensity (1.0 = full, 0.0 = off)
var screen_flash_scale: float = 1.0

## Show tutorial hints (true = show on first encounter)
var hints_enabled: bool = true

const SETTINGS_PATH := "user://settings.cfg"

# ---------- COLORBLIND PALETTES ----------

# Deuteranopia/Protanopia: red-green blind — swap green→cyan, red→orange/yellow
# Tritanopia: blue-yellow blind — swap blue→magenta, yellow→white
const CB_PALETTES := {
	"off": {},
	"deuteranopia": {
		# Minimap
		"hero":   Color(0.0, 0.85, 0.9, 1.0),     # cyan instead of green
		"enemy":  Color(1.0, 0.55, 0.0, 1.0),      # orange instead of red
		"elite":  Color(0.9, 0.2, 0.9, 1.0),        # stays purple
		# Status effects
		"poison": Color(0.0, 0.75, 0.9),             # cyan instead of green
		# Loot rarity (uncommon was green)
		"uncommon": Color(0.0, 0.85, 0.85),          # cyan
	},
	"protanopia": {
		"hero":   Color(0.0, 0.85, 0.9, 1.0),
		"enemy":  Color(1.0, 0.7, 0.0, 1.0),        # warm yellow-orange
		"elite":  Color(0.9, 0.2, 0.9, 1.0),
		"poison": Color(0.0, 0.75, 0.9),
		"uncommon": Color(0.0, 0.85, 0.85),
	},
	"tritanopia": {
		"hero":   Color(0.2, 0.9, 0.3, 1.0),        # green stays fine
		"enemy":  Color(0.9, 0.15, 0.15, 1.0),       # red stays fine
		"elite":  Color(0.9, 0.3, 0.5, 1.0),         # pinkish
		"poison": Color(0.2, 0.85, 0.15),             # stays green
		"uncommon": Color(0.2, 0.9, 0.2),             # stays green
	},
}

func _ready() -> void:
	load_settings()

# ---------- COLOR HELPERS ----------

## Get colorblind-adjusted minimap hero color
func get_hero_color() -> Color:
	var pal = CB_PALETTES.get(colorblind_mode, {})
	return pal.get("hero", Color(0.2, 0.9, 0.3, 1.0))

## Get colorblind-adjusted minimap enemy color
func get_enemy_color() -> Color:
	var pal = CB_PALETTES.get(colorblind_mode, {})
	return pal.get("enemy", Color(0.9, 0.15, 0.15, 1.0))

## Get colorblind-adjusted minimap elite color
func get_elite_color() -> Color:
	var pal = CB_PALETTES.get(colorblind_mode, {})
	return pal.get("elite", Color(0.8, 0.2, 0.8, 1.0))

## Get colorblind-adjusted poison effect color
func get_poison_color() -> Color:
	var pal = CB_PALETTES.get(colorblind_mode, {})
	return pal.get("poison", Color(0.2, 0.85, 0.15))

## Get colorblind-adjusted uncommon rarity color
func get_uncommon_color() -> Color:
	var pal = CB_PALETTES.get(colorblind_mode, {})
	return pal.get("uncommon", Color(0.2, 0.9, 0.2))

## Scale a font size by the accessibility text scale
func scale_font_size(base_size: int) -> int:
	return int(base_size * ui_text_scale)

## Get the effective screen shake multiplier
func get_shake_multiplier() -> float:
	return screen_shake_scale

# ---------- PERSISTENCE ----------

func save_settings() -> void:
	var config = ConfigFile.new()
	# Load existing to preserve audio settings
	config.load(SETTINGS_PATH)
	config.set_value("accessibility", "colorblind_mode", colorblind_mode)
	config.set_value("accessibility", "ui_text_scale", ui_text_scale)
	config.set_value("accessibility", "screen_shake_scale", screen_shake_scale)
	config.set_value("accessibility", "screen_flash_scale", screen_flash_scale)
	config.set_value("accessibility", "hints_enabled", hints_enabled)
	config.save(SETTINGS_PATH)

func load_settings() -> void:
	var config = ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	colorblind_mode = config.get_value("accessibility", "colorblind_mode", "off")
	ui_text_scale = config.get_value("accessibility", "ui_text_scale", 1.0)
	screen_shake_scale = config.get_value("accessibility", "screen_shake_scale", 1.0)
	screen_flash_scale = config.get_value("accessibility", "screen_flash_scale", 1.0)
	hints_enabled = config.get_value("accessibility", "hints_enabled", true)
