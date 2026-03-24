"""
Blender script: Render a Smush dungeon arena scene for the Steam store page.
Run headless: blender --background --python tools/render_store_page.py
Outputs: renders/steam_store_concept.png (1920x1080)
"""
import bpy
import math
import os
import random

# --- Config ---
BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS = os.path.join(BASE, "assets", "models")
OUT_DIR = os.path.join(BASE, "renders")
os.makedirs(OUT_DIR, exist_ok=True)
OUT_FILE = os.path.join(OUT_DIR, "steam_store_concept.png")

RESOLUTION_X = 1920
RESOLUTION_Y = 1080

# --- Clean scene ---
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


def import_glb(filepath, name=None):
    """Import a GLB and return the root object."""
    if not os.path.exists(filepath):
        print(f"SKIP (not found): {filepath}")
        return None
    bpy.ops.import_scene.gltf(filepath=filepath)
    obj = bpy.context.selected_objects[0] if bpy.context.selected_objects else None
    if obj and name:
        obj.name = name
    return obj


def set_location(obj, x, y, z):
    if obj:
        obj.location = (x, y, z)


def set_rotation(obj, rx=0, ry=0, rz=0):
    if obj:
        obj.rotation_euler = (math.radians(rx), math.radians(ry), math.radians(rz))


def set_scale(obj, s):
    if obj:
        obj.scale = (s, s, s)


# ============================================================
# BUILD THE SCENE
# ============================================================

# --- Floor tiles (5x5 grid) ---
floor_glb = os.path.join(MODELS, "dungeon", "kenney_floor.glb")
for gx in range(-2, 3):
    for gy in range(-2, 3):
        tile = import_glb(floor_glb, f"floor_{gx}_{gy}")
        if tile:
            set_location(tile, gx * 2.0, gy * 2.0, 0)

# --- Back wall (5 segments) ---
wall_glb = os.path.join(MODELS, "dungeon", "kenney_wall.glb")
for i in range(-2, 3):
    w = import_glb(wall_glb, f"wall_back_{i}")
    if w:
        set_location(w, i * 2.0, 4.0, 0)

# --- Side walls ---
for i in range(-2, 3):
    wl = import_glb(wall_glb, f"wall_left_{i}")
    if wl:
        set_location(wl, -4.0, i * 2.0, 0)
        set_rotation(wl, rz=90)
    wr = import_glb(wall_glb, f"wall_right_{i}")
    if wr:
        set_location(wr, 4.0, i * 2.0, 0)
        set_rotation(wr, rz=-90)

# --- Columns at corners ---
col_glb = os.path.join(MODELS, "dungeon", "kenney_column.glb")
for cx, cy in [(-3, 3), (3, 3), (-3, -3), (3, -3)]:
    c = import_glb(col_glb, f"col_{cx}_{cy}")
    if c:
        set_location(c, cx, cy, 0)

# --- Gate in the back ---
gate_glb = os.path.join(MODELS, "dungeon", "kenney_gate.glb")
gate = import_glb(gate_glb, "gate")
if gate:
    set_location(gate, 0, 4.0, 0)

# --- Barrels and props ---
barrel_glb = os.path.join(MODELS, "dungeon", "kenney_barrel.glb")
for i, (bx, by) in enumerate([(-3, -1), (3, 2), (-2.5, 3.5), (2.8, -2.5)]):
    b = import_glb(barrel_glb, f"barrel_{i}")
    if b:
        set_location(b, bx, by, 0)

# --- Gold chest ---
chest_glb = os.path.join(MODELS, "dungeon", "chest_gold.gltf")
chest = import_glb(chest_glb, "gold_chest")
if chest:
    set_location(chest, 0, 3.2, 0)
    set_scale(chest, 1.2)

# --- HERO (Fat Nate, center-left, facing enemies) ---
hero_glb = os.path.join(MODELS, "fat_nate.glb")
hero = import_glb(hero_glb, "FatNate_Hero")
if hero:
    set_location(hero, -0.8, -0.5, 0)
    set_rotation(hero, rz=30)
    set_scale(hero, 1.3)

# --- Hero weapon (iron sword in hand area) ---
sword_glb = os.path.join(MODELS, "weapons", "iron_sword.glb")
sword = import_glb(sword_glb, "hero_sword")
if sword:
    set_location(sword, -0.3, -0.2, 0.8)
    set_rotation(sword, rx=20, rz=30)
    set_scale(sword, 1.2)

# --- ENEMIES (surrounding the hero in a semicircle) ---
enemy_configs = [
    ("goblin_warrior.glb", "Goblin1", 1.5, 1.2, 0, 0.9, -150),
    ("goblin_archer.glb", "GoblinArcher", 2.5, 0.2, 0, 0.85, -170),
    ("skeleton.glb", "Skeleton", 1.0, 2.0, 0, 0.95, -130),
    ("spider.glb", "Spider", 2.0, -1.5, 0, 1.0, -200),
    ("slime.glb", "Slime", 0.5, 2.8, 0, 1.1, -120),
    ("rat.glb", "Rat", 3.0, 1.0, 0, 0.7, -180),
]
for fname, ename, ex, ey, ez, escale, erot in enemy_configs:
    e = import_glb(os.path.join(MODELS, "enemies", fname), ename)
    if e:
        set_location(e, ex, ey, ez)
        set_scale(e, escale)
        set_rotation(e, rz=erot)

# --- BOSS (Spider Queen lurking in the back) ---
boss_glb = os.path.join(MODELS, "bosses", "spider_queen.glb")
boss = import_glb(boss_glb, "SpiderQueen_Boss")
if boss:
    set_location(boss, 0, 3.0, 0)
    set_scale(boss, 1.8)
    set_rotation(boss, rz=-180)

# ============================================================
# LIGHTING — Dramatic dungeon mood
# ============================================================

# Key light (warm torch-like, slightly above and to the right)
bpy.ops.object.light_add(type='POINT', location=(3, -2, 4))
key = bpy.context.object
key.name = "KeyLight"
key.data.energy = 800
key.data.color = (1.0, 0.75, 0.4)  # warm orange
key.data.shadow_soft_size = 1.5

# Fill light (cool blue, opposite side)
bpy.ops.object.light_add(type='POINT', location=(-3, 1, 3))
fill = bpy.context.object
fill.name = "FillLight"
fill.data.energy = 300
fill.data.color = (0.4, 0.5, 0.9)  # cool blue
fill.data.shadow_soft_size = 2.0

# Rim/back light (hero highlight)
bpy.ops.object.light_add(type='POINT', location=(-1, -3, 3.5))
rim = bpy.context.object
rim.name = "RimLight"
rim.data.energy = 500
rim.data.color = (0.9, 0.6, 0.3)

# Overhead ambient (very dim)
bpy.ops.object.light_add(type='AREA', location=(0, 0, 6))
amb = bpy.context.object
amb.name = "AmbientTop"
amb.data.energy = 150
amb.data.size = 10
amb.data.color = (0.3, 0.25, 0.35)  # dim purple

# Boss spotlight (red, dramatic)
bpy.ops.object.light_add(type='SPOT', location=(0, 2, 5))
boss_light = bpy.context.object
boss_light.name = "BossSpotlight"
boss_light.data.energy = 600
boss_light.data.color = (1.0, 0.2, 0.15)  # red
boss_light.data.spot_size = math.radians(45)
boss_light.data.spot_blend = 0.3
set_rotation(boss_light, rx=30)

# ============================================================
# CAMERA — Low dramatic angle
# ============================================================

bpy.ops.object.camera_add(location=(-2.5, -5.5, 2.8))
cam = bpy.context.object
cam.name = "StorePageCam"
cam.data.lens = 28  # wide angle for drama
cam.rotation_euler = (math.radians(70), 0, math.radians(-15))
scene.camera = cam

# ============================================================
# WORLD — Dark dungeon background
# ============================================================

world = bpy.data.worlds.new("DungeonWorld")
scene.world = world
if hasattr(world, 'use_nodes'):
    world.use_nodes = True
nodes = world.node_tree.nodes
bg = nodes.get("Background")
if bg:
    bg.inputs[0].default_value = (0.02, 0.015, 0.03, 1.0)  # near-black purple
    bg.inputs[1].default_value = 0.3

# ============================================================
# RENDER SETTINGS
# ============================================================

scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 64  # good enough for a concept render
scene.cycles.use_denoising = True
scene.render.resolution_x = RESOLUTION_X
scene.render.resolution_y = RESOLUTION_Y
scene.render.resolution_percentage = 100
scene.render.filepath = OUT_FILE
scene.render.image_settings.file_format = 'PNG'

# Color management
scene.view_settings.view_transform = 'AgX'
scene.view_settings.look = 'AgX - Medium High Contrast'

# ============================================================
# RENDER
# ============================================================

print(f"Rendering to {OUT_FILE} ...")
bpy.ops.render.render(write_still=True)
print(f"Done! Saved to {OUT_FILE}")
