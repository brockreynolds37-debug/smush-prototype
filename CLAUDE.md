# Smush — Claude Code Context

## Project
Godot 4.4 isometric dungeon crawler. WC3 custom map DNA. 90 sprint tasks complete.
Repo: github.com/brockreynolds37-debug/smush-prototype

## Current Build Status
- **Sprint 1-10 (tasks 1-90): ALL COMPLETE**
- Build exported: `smush_v0.1_prototype` (Windows/macOS/Linux)
- Last major session: Bug fixes + UI/gameplay overhaul (see below)

## Architecture
- **Main scene flow:** main_menu.tscn → character_select.tscn → dungeon floor scenes → victory_screen.tscn
- **Autoloads:** GameManager, FloorManager, AudioManager, AudienceManager, AchievementManager, KeybindingManager, PerformanceMonitor, NetworkManager, NarratorManager (and many more — see project.godot)
- **Key scripts:** hero.gd, input_handler.gd, hud.gd, dungeon_builder.gd, floor_manager.gd
- **193 scripts** in scripts/, **32 scenes** in scenes/

## Controls (Current)
- **Right click** — move to location / attack enemy / interact / place targeted spell
- **Left click** — select unit (inspect stats) / deselect
- **Spells** — Q, E, R, T (hotkeys rebindable in settings)
- **ESC** — pause menu / cancel spell targeting
- **I** — inventory
- **~** — debug console

## HUD Layout (WC3-style, bottom bar)
Rebuilt programmatically in hud.gd:
```
[MINIMAP 180x180] [Portrait+HP/MP] [Hero Name/Stats] [2x2 Spell Grid] [Selection Panel]
```
- Top bar: Gold, Level, XP, Timer, Floor name, VP, Audience mood
- Bottom bar: minimap, portrait, stats, abilities (Q/E/R/T), unit inspector
- All node refs built in _ready() — hud.tscn is a minimal stub

## Known Issues / Recent Fixes
- **NaN transform crash** — fixed: all .normalized() calls guard against zero-length vectors
- **Black screen on floor transition** — fixed: missing `await` before hide_loading()
- **4224 script errors** — fixed: Variant type inference, corrupted function signatures
- **Keybinding manager** — new: scripts/keybinding_manager.gd, persists to user://settings.cfg

## GDScript Rules (STRICT — Godot 4.6 warnings-as-errors)
- **NEVER use `:=` when RHS returns Variant** (dictionary .get(), ternary with mixed types, array[index])
- Use explicit: `var x: int = dict.get("key", 0)` not `var x := dict.get("key", 0)`
- **NEVER normalize without length check:** `dir.normalized() if dir.length_squared() > 0.001 else Vector3.ZERO`
- **Object.get() takes 1 arg** — not 2. For defaults: `var v = node.get("prop"); if v == null: v = default`
- All these will cause parse errors that cascade to 1000+ downstream errors

## Game Design Quick Reference
- **The Smusher** — 30-min countdown per run, room walls close in when timer hits 0
- **The Collective** — alien audience watching the run, mood: Bored → Watching → Excited → Erupting
- **6 civilizations** — Northborn, Centurion, Epoch, Ironclad, Verdant, Shadowkin
- **Floor archetypes** — Dungeon Crawl, Escape, Survival Arena, Stealth, Economy, Boss Rush, Political, Inversion, Race
- **Audience VP** — earned through style, combos, variety, Smush kills, environmental kills

## What's Next (after task 90)
No formal sprint assigned. Priorities based on Brock's feedback:
1. **HUD visual polish** — WC3 art style, textures, medieval border art
2. **Gameplay feel** — movement still slide-y despite animation state machine
3. **DCC Book 1 integration** — transcript ready at game-rpg/DCC_Book1.txt; mine for creature/lore ideas to add to Smush
4. **Playtesting loop** — full run from menu → floor 1-3 → victory without crashes

## Dev Notes
- Minerva (AI) coordinates with Claude Code — keep this file updated after major sessions
- When running Godot headless for error checks: `/Applications/Godot.app/Contents/MacOS/Godot --headless --quit 2>&1`
- smush-dev-sprint cron: runs Claude Code every 20min autonomously (currently paused after sprint 10 complete)
- Game bible: game-rpg/SMUSH_COMPLETE_GAME_BIBLE.md (13,770 lines)
