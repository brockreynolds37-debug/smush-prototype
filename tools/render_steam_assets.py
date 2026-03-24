"""
Blender script: Render all Steam store page assets for Smush.
Run headless: blender --background --python tools/render_steam_assets.py

Outputs to game-rpg/steam-assets/:
  1. capsule_small.png      (460x215)   — Small capsule
  2. capsule_main.png       (920x430)   — Main capsule
  3. library_hero.png       (3840x1240) — Library hero banner
  4. screenshot_arena.png   (1920x1080) — Arena combat scene
  5. screenshot_boss.png    (1920x1080) — Boss encounter
  6. screenshot_dungeon.png (1920x1080) — Dungeon exploration
  7. screenshot_loot.png    (1920x1080) — Loot and chest scene
  8. screenshot_horde.png   (1920x1080) — Horde of enemies
"""
import bpy
import math
import os

# --- Paths ---
BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS = os.path.join(BASE, "assets", "models")
OUT_DIR = os.path.join(os.path.dirname(BASE), "steam-assets")
os.makedirs(OUT_DIR, exist_ok=True)

# --- Helpers ---

def clean_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)

def import_glb(filepath, name=None):
    if not os.path.exists(filepath):
        print(f"SKIP (not found): {filepath}")
        return None
    bpy.ops.import_scene.gltf(filepath=filepath)
    obj = bpy.context.selected_objects[0] if bpy.context.selected_objects else None
    if obj and name:
        obj.name = name
    return obj

def loc(obj, x, y, z):
    if obj:
        obj.location = (x, y, z)

def rot(obj, rx=0, ry=0, rz=0):
    if obj:
        obj.rotation_euler = (math.radians(rx), math.radians(ry), math.radians(rz))

def scl(obj, s):
    if obj:
        obj.scale = (s, s, s)

def add_point_light(x, y, z, energy, color, name="Light", shadow_size=1.5):
    bpy.ops.object.light_add(type='POINT', location=(x, y, z))
    light = bpy.context.object
    light.name = name
    light.data.energy = energy
    light.data.color = color
    light.data.shadow_soft_size = shadow_size
    return light

def add_spot_light(x, y, z, energy, color, angle=45, blend=0.3, name="Spot"):
    bpy.ops.object.light_add(type='SPOT', location=(x, y, z))
    light = bpy.context.object
    light.name = name
    light.data.energy = energy
    light.data.color = color
    light.data.spot_size = math.radians(angle)
    light.data.spot_blend = blend
    return light

def setup_world(bg_color=(0.02, 0.015, 0.03, 1.0), strength=0.3):
    scene = bpy.context.scene
    world = bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = bg_color
        bg.inputs[1].default_value = strength

def setup_render(res_x, res_y, out_path, samples=64):
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x = res_x
    scene.render.resolution_y = res_y
    scene.render.resolution_percentage = 100
    scene.render.filepath = out_path
    scene.render.image_settings.file_format = 'PNG'
    scene.view_settings.view_transform = 'AgX'
    scene.view_settings.look = 'AgX - Medium High Contrast'

def add_camera(x, y, z, rx, ry, rz, lens=28):
    bpy.ops.object.camera_add(location=(x, y, z))
    cam = bpy.context.object
    cam.data.lens = lens
    rot(cam, rx, ry, rz)
    bpy.context.scene.camera = cam
    return cam

def build_floor(cols, rows, offset_x=0, offset_y=0):
    floor_glb = os.path.join(MODELS, "dungeon", "kenney_floor.glb")
    for gx in range(-cols // 2, cols // 2 + 1):
        for gy in range(-rows // 2, rows // 2 + 1):
            tile = import_glb(floor_glb, f"floor_{gx}_{gy}")
            if tile:
                loc(tile, gx * 2.0 + offset_x, gy * 2.0 + offset_y, 0)

def build_walls_back(count, y_pos=4.0):
    wall_glb = os.path.join(MODELS, "dungeon", "kenney_wall.glb")
    for i in range(-count // 2, count // 2 + 1):
        w = import_glb(wall_glb, f"wall_back_{i}")
        if w:
            loc(w, i * 2.0, y_pos, 0)

def build_walls_sides(count, x_left=-4.0, x_right=4.0):
    wall_glb = os.path.join(MODELS, "dungeon", "kenney_wall.glb")
    for i in range(-count // 2, count // 2 + 1):
        wl = import_glb(wall_glb, f"wall_left_{i}")
        if wl:
            loc(wl, x_left, i * 2.0, 0)
            rot(wl, rz=90)
        wr = import_glb(wall_glb, f"wall_right_{i}")
        if wr:
            loc(wr, x_right, i * 2.0, 0)
            rot(wr, rz=-90)

def build_columns(positions):
    col_glb = os.path.join(MODELS, "dungeon", "kenney_column.glb")
    for i, (cx, cy) in enumerate(positions):
        c = import_glb(col_glb, f"col_{i}")
        if c:
            loc(c, cx, cy, 0)

def add_hero(x, y, rz=30, scale=1.3):
    hero = import_glb(os.path.join(MODELS, "fat_nate.glb"), "Hero")
    if hero:
        loc(hero, x, y, 0)
        rot(hero, rz=rz)
        scl(hero, scale)
    sword = import_glb(os.path.join(MODELS, "weapons", "iron_sword.glb"), "HeroSword")
    if sword:
        loc(sword, x + 0.5, y + 0.3, 0.8)
        rot(sword, rx=20, rz=rz)
        scl(sword, 1.2)
    return hero

def add_standard_lighting():
    add_point_light(3, -2, 4, 800, (1.0, 0.75, 0.4), "KeyLight")
    add_point_light(-3, 1, 3, 300, (0.4, 0.5, 0.9), "FillLight")
    add_point_light(-1, -3, 3.5, 500, (0.9, 0.6, 0.3), "RimLight")
    bpy.ops.object.light_add(type='AREA', location=(0, 0, 6))
    amb = bpy.context.object
    amb.name = "AmbientTop"
    amb.data.energy = 150
    amb.data.size = 10
    amb.data.color = (0.3, 0.25, 0.35)

def render():
    print(f"Rendering to {bpy.context.scene.render.filepath} ...")
    bpy.ops.render.render(write_still=True)
    print(f"Done: {bpy.context.scene.render.filepath}")


# ============================================================
# SCENE 1: CAPSULE IMAGES (shared scene — arena combat)
# Hero front-center, enemies lunging, dramatic lighting
# Rendered at high res then used for both capsule sizes
# ============================================================

def build_capsule_scene():
    clean_scene()
    build_floor(5, 3)
    build_walls_back(5, 4.0)
    build_columns([(-3, 3), (3, 3), (-3, -1), (3, -1)])

    # Hero in heroic pose, center-left
    add_hero(-0.5, -0.5, rz=20, scale=1.4)

    # Enemies charging in
    enemies = [
        ("enemies/goblin_warrior.glb", "Gob1", 2.0, 1.5, 0.9, -160),
        ("enemies/skeleton.glb", "Skel1", 1.5, 2.5, 0.95, -140),
        ("enemies/spider.glb", "Spider1", 2.5, -0.5, 1.0, -180),
        ("enemies/goblin_archer.glb", "Archer1", 3.0, 0.5, 0.85, -170),
    ]
    for fname, ename, ex, ey, escale, erot in enemies:
        e = import_glb(os.path.join(MODELS, fname), ename)
        if e:
            loc(e, ex, ey, 0)
            scl(e, escale)
            rot(e, rz=erot)

    # Dramatic lighting
    add_point_light(2, -3, 5, 1000, (1.0, 0.7, 0.3), "KeyWarm")
    add_point_light(-3, 0, 3, 400, (0.3, 0.4, 0.9), "FillCool")
    add_point_light(0, -4, 3, 600, (1.0, 0.5, 0.2), "Rim")
    add_spot_light(0, 2, 6, 500, (0.8, 0.2, 0.15), angle=50, name="DangerSpot")
    rot(bpy.context.object, rx=50)

    bpy.ops.object.light_add(type='AREA', location=(0, 0, 7))
    amb = bpy.context.object
    amb.data.energy = 120
    amb.data.size = 12
    amb.data.color = (0.25, 0.2, 0.3)

    setup_world()

    # Camera — tight, slightly low, heroic framing
    add_camera(-1.5, -5.0, 2.5, 72, 0, -8, lens=32)


def render_capsule_small():
    build_capsule_scene()
    setup_render(460, 215, os.path.join(OUT_DIR, "capsule_small.png"), samples=48)
    render()

def render_capsule_main():
    build_capsule_scene()
    setup_render(920, 430, os.path.join(OUT_DIR, "capsule_main.png"), samples=64)
    render()


# ============================================================
# SCENE 2: LIBRARY HERO (ultrawide banner — 3840x1240)
# Panoramic dungeon with hero silhouette, enemies on both sides
# ============================================================

def render_library_hero():
    clean_scene()

    # Wide floor
    build_floor(9, 3)
    build_walls_back(9, 4.0)
    build_walls_sides(3, -8.0, 8.0)

    # Columns lining the hall
    build_columns([
        (-6, 3), (-3, 3), (3, 3), (6, 3),
        (-6, -1), (-3, -1), (3, -1), (6, -1),
    ])

    # Hero center
    add_hero(0, -0.3, rz=0, scale=1.5)

    # Enemies on both sides
    left_enemies = [
        ("enemies/goblin_warrior.glb", "LGob", -3.5, 0.5, 0.9, 30),
        ("enemies/spider.glb", "LSpider", -5.0, 1.0, 1.0, 45),
        ("enemies/wolf.glb", "LWolf", -2.5, 2.0, 0.9, 20),
    ]
    right_enemies = [
        ("enemies/skeleton.glb", "RSkel", 3.5, 0.5, 0.95, -30),
        ("enemies/slime.glb", "RSlime", 5.0, 1.0, 1.1, -45),
        ("enemies/animated_armor.glb", "RArmor", 2.5, 2.0, 1.0, -20),
    ]
    for fname, ename, ex, ey, escale, erot in left_enemies + right_enemies:
        e = import_glb(os.path.join(MODELS, fname), ename)
        if e:
            loc(e, ex, ey, 0)
            scl(e, escale)
            rot(e, rz=erot)

    # Boss looming in the back
    boss = import_glb(os.path.join(MODELS, "bosses", "kraken_spawn.glb"), "Kraken")
    if boss:
        loc(boss, 0, 4.0, 0)
        scl(boss, 2.0)
        rot(boss, rz=180)

    # Lighting — wide dramatic spread
    add_point_light(0, -3, 5, 1200, (1.0, 0.7, 0.3), "CenterKey")
    add_point_light(-6, -1, 4, 500, (0.6, 0.4, 0.2), "LeftTorch")
    add_point_light(6, -1, 4, 500, (0.6, 0.4, 0.2), "RightTorch")
    add_point_light(0, 4, 4, 400, (0.8, 0.2, 0.3), "BossGlow")
    add_spot_light(0, -2, 7, 600, (1.0, 0.85, 0.5), angle=60, name="HeroSpot")
    rot(bpy.context.object, rx=60)

    bpy.ops.object.light_add(type='AREA', location=(0, 0, 8))
    amb = bpy.context.object
    amb.data.energy = 100
    amb.data.size = 18
    amb.data.color = (0.2, 0.15, 0.25)

    setup_world(bg_color=(0.015, 0.01, 0.025, 1.0))

    # Ultrawide camera — low and wide
    add_camera(0, -7.0, 2.8, 72, 0, 0, lens=22)

    setup_render(3840, 1240, os.path.join(OUT_DIR, "library_hero.png"), samples=48)
    render()


# ============================================================
# SCREENSHOT 1: Arena combat — hero fighting group of enemies
# ============================================================

def render_screenshot_arena():
    clean_scene()
    build_floor(5, 5)
    build_walls_back(5, 6.0)
    build_walls_sides(5)
    build_columns([(-3, 5), (3, 5), (-3, -3), (3, -3)])

    add_hero(-0.8, 0, rz=35, scale=1.3)

    # Enemies scattered in combat
    combat_enemies = [
        ("enemies/goblin_warrior.glb", "Gob", 1.5, 1.5, 0.9, -150),
        ("enemies/goblin_archer.glb", "Archer", 3.0, 0.0, 0.85, -170),
        ("enemies/skeleton.glb", "Skel", 1.0, 3.0, 0.95, -130),
        ("enemies/rat.glb", "Rat", 2.5, -1.5, 0.7, -180),
        ("enemies/spider.glb", "Spider", -2.0, 2.5, 1.0, -60),
        ("enemies/wolf.glb", "Wolf", 0.5, -2.0, 0.9, -120),
    ]
    for fname, ename, ex, ey, escale, erot in combat_enemies:
        e = import_glb(os.path.join(MODELS, fname), ename)
        if e:
            loc(e, ex, ey, 0)
            scl(e, escale)
            rot(e, rz=erot)

    # Props
    for i, (bx, by) in enumerate([(-3, 4), (3, -2), (-3, -2)]):
        b = import_glb(os.path.join(MODELS, "dungeon", "kenney_barrel.glb"), f"barrel_{i}")
        if b:
            loc(b, bx, by, 0)

    add_standard_lighting()
    setup_world()
    add_camera(-2.5, -5.5, 3.5, 68, 0, -10, lens=28)
    setup_render(1920, 1080, os.path.join(OUT_DIR, "screenshot_arena.png"), samples=64)
    render()


# ============================================================
# SCREENSHOT 2: Boss encounter — Spider Queen in lair
# ============================================================

def render_screenshot_boss():
    clean_scene()
    build_floor(7, 7)
    build_walls_back(7, 8.0)
    build_walls_sides(7, -6.0, 6.0)

    # Boss in center-back, massive
    boss = import_glb(os.path.join(MODELS, "bosses", "spider_queen.glb"), "SpiderQueen")
    if boss:
        loc(boss, 0, 4.0, 0)
        scl(boss, 2.2)
        rot(boss, rz=180)

    # Hero approaching
    add_hero(-1.0, -2.0, rz=10, scale=1.2)

    # Columns framing the scene
    build_columns([(-5, 6), (5, 6), (-5, 0), (5, 0), (-3, 3), (3, 3)])

    # Dramatic boss lighting
    add_point_light(0, 4, 5, 600, (1.0, 0.15, 0.1), "BossRed")
    add_spot_light(0, 4, 8, 800, (0.9, 0.2, 0.15), angle=40, name="BossSpot")
    rot(bpy.context.object, rx=45)
    add_point_light(-2, -3, 4, 600, (1.0, 0.7, 0.3), "HeroKey")
    add_point_light(3, -1, 3, 300, (0.4, 0.5, 0.9), "Fill")
    add_point_light(-1, -4, 3, 400, (0.8, 0.55, 0.25), "Rim")

    bpy.ops.object.light_add(type='AREA', location=(0, 2, 7))
    amb = bpy.context.object
    amb.data.energy = 80
    amb.data.size = 14
    amb.data.color = (0.35, 0.15, 0.2)

    setup_world(bg_color=(0.03, 0.01, 0.02, 1.0), strength=0.2)
    add_camera(-3.0, -6.0, 3.0, 70, 0, -12, lens=30)
    setup_render(1920, 1080, os.path.join(OUT_DIR, "screenshot_boss.png"), samples=64)
    render()


# ============================================================
# SCREENSHOT 3: Dungeon exploration — corridor with atmosphere
# ============================================================

def render_screenshot_dungeon():
    clean_scene()

    # Long corridor layout
    floor_glb = os.path.join(MODELS, "dungeon", "kenney_floor.glb")
    for gx in range(-1, 2):
        for gy in range(-4, 5):
            tile = import_glb(floor_glb, f"floor_{gx}_{gy}")
            if tile:
                loc(tile, gx * 2.0, gy * 2.0, 0)

    wall_glb = os.path.join(MODELS, "dungeon", "kenney_wall.glb")
    for gy in range(-4, 5):
        wl = import_glb(wall_glb, f"wl_{gy}")
        if wl:
            loc(wl, -2.0, gy * 2.0, 0)
            rot(wl, rz=90)
        wr = import_glb(wall_glb, f"wr_{gy}")
        if wr:
            loc(wr, 2.0, gy * 2.0, 0)
            rot(wr, rz=-90)

    # Back wall
    for i in range(-1, 2):
        w = import_glb(wall_glb, f"wb_{i}")
        if w:
            loc(w, i * 2.0, 8.0, 0)

    # Hero walking deeper into corridor
    add_hero(0, -2.0, rz=0, scale=1.2)

    # Torches along walls
    candle_glb = os.path.join(MODELS, "dungeon", "candle_lit.gltf")
    for gy in range(-2, 4, 2):
        for side_x in [-1.5, 1.5]:
            c = import_glb(candle_glb, f"candle_{side_x}_{gy}")
            if c:
                loc(c, side_x, gy * 2.0, 0)

    # Columns at doorway
    build_columns([(-1, 4), (1, 4)])

    # Stairs at end
    stairs = import_glb(os.path.join(MODELS, "dungeon", "kenney_stairs.glb"), "Stairs")
    if stairs:
        loc(stairs, 0, 7.0, 0)

    # Moody corridor lighting
    for gy in range(-2, 4, 2):
        add_point_light(0, gy * 2.0, 2.5, 200, (1.0, 0.65, 0.3), f"Torch_{gy}")

    add_point_light(0, -3, 3, 400, (0.9, 0.6, 0.3), "HeroLight")
    add_point_light(0, 7, 3, 300, (0.5, 0.7, 1.0), "StairsGlow")

    bpy.ops.object.light_add(type='AREA', location=(0, 2, 5))
    amb = bpy.context.object
    amb.data.energy = 60
    amb.data.size = 8
    amb.data.color = (0.2, 0.15, 0.25)

    setup_world(bg_color=(0.01, 0.008, 0.02, 1.0), strength=0.15)
    add_camera(0, -7.5, 3.0, 72, 0, 0, lens=26)
    setup_render(1920, 1080, os.path.join(OUT_DIR, "screenshot_dungeon.png"), samples=64)
    render()


# ============================================================
# SCREENSHOT 4: Loot and treasure — open chest, glowing items
# ============================================================

def render_screenshot_loot():
    clean_scene()
    build_floor(3, 3)
    build_walls_back(3, 4.0)
    build_walls_sides(3)

    # Open gold chest center
    chest = import_glb(os.path.join(MODELS, "dungeon", "chest_gold.gltf"), "GoldChest")
    if chest:
        loc(chest, 0, 0.5, 0)
        scl(chest, 1.5)

    # Weapons scattered around chest
    weapons = [
        ("weapons/steel_sword.glb", "Sword", -0.8, 0.2, 0.6, 90, 0, -30),
        ("weapons/iron_axe.glb", "Axe", 0.8, 0.3, 0.4, 80, 0, 40),
        ("weapons/longbow.glb", "Bow", -0.3, 1.2, 0.3, 70, 20, 0),
    ]
    for fname, wname, wx, wy, wz, wrx, wry, wrz in weapons:
        w = import_glb(os.path.join(MODELS, fname), wname)
        if w:
            loc(w, wx, wy, wz)
            rot(w, wrx, wry, wrz)
            scl(w, 1.0)

    # Coins near chest
    coin_glb = os.path.join(MODELS, "dungeon", "kenney_coin.glb")
    for i, (cx, cy) in enumerate([(0.3, -0.3), (-0.5, -0.2), (0.1, 0.8), (-0.2, 1.0)]):
        coin = import_glb(coin_glb, f"coin_{i}")
        if coin:
            loc(coin, cx, cy, 0)
            scl(coin, 0.8)

    # Hero admiring loot
    add_hero(-1.5, -1.5, rz=30, scale=1.2)

    # Barrels in corners
    for i, (bx, by) in enumerate([(-2, 3), (2, 3)]):
        b = import_glb(os.path.join(MODELS, "dungeon", "kenney_barrel.glb"), f"barrel_{i}")
        if b:
            loc(b, bx, by, 0)

    # Golden warm lighting — treasure glow
    add_point_light(0, 0.5, 2.0, 600, (1.0, 0.85, 0.4), "ChestGlow")
    add_point_light(0, 0.5, 0.5, 300, (1.0, 0.9, 0.5), "ChestInner")
    add_point_light(-2, -2, 3, 400, (0.9, 0.6, 0.3), "HeroKey")
    add_point_light(2, 0, 3, 200, (0.4, 0.45, 0.8), "Fill")

    bpy.ops.object.light_add(type='AREA', location=(0, 0, 5))
    amb = bpy.context.object
    amb.data.energy = 100
    amb.data.size = 8
    amb.data.color = (0.35, 0.28, 0.2)

    setup_world(bg_color=(0.02, 0.015, 0.01, 1.0), strength=0.25)
    add_camera(-2.0, -4.0, 2.5, 70, 0, -10, lens=32)
    setup_render(1920, 1080, os.path.join(OUT_DIR, "screenshot_loot.png"), samples=64)
    render()


# ============================================================
# SCREENSHOT 5: Enemy horde — tons of enemies, overwhelming
# ============================================================

def render_screenshot_horde():
    clean_scene()
    build_floor(7, 5)
    build_walls_back(7, 6.0)
    build_walls_sides(5, -6.0, 6.0)

    # Hero in defensive stance, slightly retreating
    add_hero(-1.0, -3.0, rz=15, scale=1.3)

    # Massive wave of enemies
    horde = [
        ("enemies/goblin_warrior.glb", 0, 0, 0.9),
        ("enemies/goblin_warrior.glb", 1.5, 0.5, 0.85),
        ("enemies/goblin_warrior.glb", -1.5, 1.0, 0.9),
        ("enemies/skeleton.glb", 2.5, 1.5, 0.95),
        ("enemies/skeleton.glb", -0.5, 2.0, 0.95),
        ("enemies/spider.glb", 3.0, 0.0, 1.0),
        ("enemies/spider.glb", -2.5, 0.5, 1.0),
        ("enemies/wolf.glb", 1.0, 2.5, 0.9),
        ("enemies/wolf.glb", -2.0, 2.0, 0.9),
        ("enemies/rat.glb", 0.5, 1.0, 0.7),
        ("enemies/rat.glb", -1.0, 0.5, 0.7),
        ("enemies/goblin_archer.glb", 3.5, 2.0, 0.85),
        ("enemies/goblin_shaman.glb", -3.0, 2.5, 0.9),
        ("enemies/slime.glb", 2.0, 3.0, 1.1),
        ("enemies/animated_armor.glb", 0, 3.5, 1.0),
    ]
    for i, (fname, ex, ey, escale) in enumerate(horde):
        e = import_glb(os.path.join(MODELS, fname), f"Enemy_{i}")
        if e:
            loc(e, ex, ey, 0)
            scl(e, escale)
            rot(e, rz=-180 + (i * 7 - 50))

    # Boss behind the horde
    boss = import_glb(os.path.join(MODELS, "bosses", "slime_lord.glb"), "SlimeLord")
    if boss:
        loc(boss, 0, 5.0, 0)
        scl(boss, 2.0)
        rot(boss, rz=180)

    # Intense combat lighting
    add_point_light(0, -4, 5, 800, (1.0, 0.65, 0.3), "HeroKey")
    add_point_light(0, 3, 4, 500, (0.9, 0.2, 0.15), "HordeRed")
    add_point_light(-4, 0, 3, 300, (0.4, 0.4, 0.8), "LeftFill")
    add_point_light(4, 0, 3, 300, (0.4, 0.4, 0.8), "RightFill")
    add_spot_light(0, 5, 6, 700, (0.8, 0.15, 0.1), angle=50, name="BossRed")
    rot(bpy.context.object, rx=45)

    bpy.ops.object.light_add(type='AREA', location=(0, 0, 7))
    amb = bpy.context.object
    amb.data.energy = 80
    amb.data.size = 14
    amb.data.color = (0.25, 0.15, 0.2)

    setup_world(bg_color=(0.025, 0.01, 0.02, 1.0), strength=0.2)
    add_camera(-2.5, -7.0, 4.0, 65, 0, -8, lens=24)
    setup_render(1920, 1080, os.path.join(OUT_DIR, "screenshot_horde.png"), samples=64)
    render()


# ============================================================
# RUN ALL RENDERS
# ============================================================

if __name__ == "__main__":
    print("=" * 60)
    print("SMUSH — Steam Store Asset Renderer")
    print("=" * 60)

    renders = [
        ("Small Capsule (460x215)", render_capsule_small),
        ("Main Capsule (920x430)", render_capsule_main),
        ("Library Hero (3840x1240)", render_library_hero),
        ("Screenshot: Arena Combat", render_screenshot_arena),
        ("Screenshot: Boss Encounter", render_screenshot_boss),
        ("Screenshot: Dungeon Exploration", render_screenshot_dungeon),
        ("Screenshot: Loot & Treasure", render_screenshot_loot),
        ("Screenshot: Enemy Horde", render_screenshot_horde),
    ]

    for i, (name, func) in enumerate(renders):
        print(f"\n[{i+1}/{len(renders)}] Rendering: {name}")
        func()

    print("\n" + "=" * 60)
    print(f"All {len(renders)} assets rendered to {OUT_DIR}/")
    print("=" * 60)
