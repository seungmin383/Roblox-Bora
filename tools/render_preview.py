"""Render an approximate GIF from the saved Roblox geometry, without Studio UI access."""
from pathlib import Path
import math
import xml.etree.ElementTree as ET
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "dist" / "preview"
OUT.mkdir(parents=True, exist_ok=True)
WIDTH, HEIGHT, SCALE = 960, 640, 1.5
FONT = Path("C:/Windows/Fonts/malgun.ttf")
FONTS = {size: ImageFont.truetype(str(FONT), round(size * SCALE)) for size in (14, 18, 20, 28)}


def name(node):
    return node.find("Properties/string[@name='Name']").text


def read_part(node, offset=None):
    props = node.find("Properties")
    cf = props.find("CoordinateFrame[@name='CFrame']")
    vec = props.find("Vector3[@name='size']")
    value = int(props.find("Color3uint8").text)
    transparency = props.find("float[@name='Transparency']")
    shape = props.find("token[@name='shape']")
    return dict(
        size=np.array([float(vec.find(axis).text) for axis in "XYZ"]),
        pos=np.array([float(cf.find(axis).text) for axis in "XYZ"]) + (np.zeros(3) if offset is None else offset),
        rotation=np.array([[float(cf.find(f"R{i}{j}").text) for j in range(3)] for i in range(3)]),
        color=np.array([(value >> 16) & 255, (value >> 8) & 255, value & 255]),
        shape=int(shape.text) if shape is not None else 1,
        hidden=transparency is not None and float(transparency.text) >= 1,
    )


def model_parts(node, offset=None):
    return [read_part(part, offset) for part in node.findall(".//Item[@class='Part']")]


def block(size, pos, color):
    return dict(size=np.array(size), pos=np.array(pos), rotation=np.eye(3), color=np.array(color), shape=1, hidden=False, layer=0)


def primitives(shape):
    if shape == 0:  # Roblox Ball: scaled sphere.
        faces = []
        for row in range(10):
            p, q = -math.pi / 2 + row * math.pi / 10, -math.pi / 2 + (row + 1) * math.pi / 10
            for column in range(20):
                a, b = column * math.tau / 20, (column + 1) * math.tau / 20
                faces.append([[math.cos(y) * math.cos(x), math.sin(y), math.cos(y) * math.sin(x)]
                              for y, x in ((p, a), (p, b), (q, b), (q, a))])
        return np.array(faces)
    if shape == 2:  # Roblox Cylinder runs along its local X axis.
        faces = []
        for index in range(20):
            a, b = index * math.tau / 20, (index + 1) * math.tau / 20
            faces.append([[-1, math.cos(a), math.sin(a)], [1, math.cos(a), math.sin(a)],
                          [1, math.cos(b), math.sin(b)], [-1, math.cos(b), math.sin(b)]])
        return np.array(faces)
    return np.array([
        [[1, -1, -1], [1, 1, -1], [1, 1, 1], [1, -1, 1]],
        [[-1, -1, 1], [-1, 1, 1], [-1, 1, -1], [-1, -1, -1]],
        [[-1, 1, -1], [-1, 1, 1], [1, 1, 1], [1, 1, -1]],
        [[-1, -1, 1], [-1, -1, -1], [1, -1, -1], [1, -1, 1]],
        [[-1, -1, 1], [1, -1, 1], [1, 1, 1], [-1, 1, 1]],
        [[1, -1, -1], [-1, -1, -1], [-1, 1, -1], [1, 1, -1]],
    ], dtype=float)


PRIMITIVES = {shape: primitives(shape) for shape in (0, 1, 2)}


def geometry(parts):
    polygons, normals, colors, layers = [], [], [], []
    for part in parts:
        if part["hidden"]:
            continue
        mesh = PRIMITIVES[part["shape"]]
        half = part["size"] / 2
        world = (mesh * half) @ part["rotation"].T + part["pos"]
        centers = mesh.mean(axis=1)
        if part["shape"] == 2:
            centers[:, 0] = 0
        if part["shape"] == 1:
            local_normals = centers
        else:
            local_normals = centers / half
        world_normals = local_normals @ part["rotation"].T
        world_normals /= np.maximum(np.linalg.norm(world_normals, axis=1, keepdims=True), 1e-8)
        polygons.append(world)
        normals.append(world_normals)
        colors.append(np.tile(part["color"], (len(mesh), 1)))
        layers.extend([part.get("layer", 2)] * len(mesh))
    return np.concatenate(polygons), np.concatenate(normals), np.concatenate(colors), np.array(layers)


def unit(vector):
    return vector / np.linalg.norm(vector)


def render(mesh, camera, target, zoom, title, subtitle, labels, progress):
    pixels = Image.new("RGB", (round(WIDTH * SCALE), round(HEIGHT * SCALE)), (225, 237, 244))
    draw = ImageDraw.Draw(pixels)
    forward = unit(np.array(target) - np.array(camera))
    right = unit(np.cross(forward, np.array([0., 1., 0.])))
    up = np.cross(right, forward)
    basis = np.array([right, up, forward]).T
    polygons, normals, colors, layers = mesh
    projected = (polygons - target) @ basis
    screen = np.empty(projected.shape[:-1] + (2,))
    screen[..., 0] = (WIDTH / 2 + projected[..., 0] * zoom) * SCALE
    screen[..., 1] = (HEIGHT * 0.59 - projected[..., 1] * zoom) * SCALE
    light = unit(np.array([-0.5, 1., 0.8]))
    shade = 0.64 + 0.36 * np.maximum(normals @ light, 0)
    tints = np.clip(colors * shade[:, None], 0, 255).astype(np.uint8)
    visible = normals @ forward < 0.015
    # Large ground faces cannot use a center-depth painter sort without hiding nearby roads.
    for index in np.lexsort((-projected[..., 2].mean(axis=1), layers)):
        if visible[index]:
            draw.polygon([tuple(point) for point in screen[index]], fill=tuple(tints[index]))
    for text, point in labels:
        q = (np.array(point) - target) @ basis
        x, y = (WIDTH / 2 + q[0] * zoom) * SCALE, (HEIGHT * 0.59 - q[1] * zoom) * SCALE
        font = FONTS[18]
        bounds = draw.textbbox((0, 0), text, font=font)
        text_width = bounds[2] - bounds[0]
        draw.rounded_rectangle((x - text_width / 2 - 12 * SCALE, y - 5 * SCALE,
                                x + text_width / 2 + 12 * SCALE, y + 28 * SCALE), radius=7 * SCALE, fill=(35, 47, 57))
        draw.text((x, y), text, font=font, anchor="mt", fill=(255, 255, 255))
    draw.rectangle((0, 0, WIDTH * SCALE, 102 * SCALE), fill=(249, 250, 251))
    draw.text((30 * SCALE, 17 * SCALE), title, font=FONTS[28], fill=(29, 43, 54))
    draw.text((32 * SCALE, 62 * SCALE), subtitle, font=FONTS[18], fill=(79, 97, 108))
    draw.rectangle((0, 590 * SCALE, WIDTH * SCALE, HEIGHT * SCALE), fill=(249, 250, 251))
    draw.text((30 * SCALE, 607 * SCALE), "v0.1 · 실제 모델 데이터로 만든 간이 렌더 · Studio 화면 녹화 아님",
              font=FONTS[14], fill=(84, 102, 114))
    draw.rectangle((0, 587 * SCALE, progress * WIDTH * SCALE, 590 * SCALE), fill=(37, 149, 126))
    return pixels.resize((WIDTH, HEIGHT), Image.Resampling.LANCZOS)


root = ET.parse(ROOT / "dist/BoraAssetDemo.rbxlx").getroot()
workspace = root.find("Item[@class='Workspace']")
sample = next(child for child in workspace.findall("Item") if name(child) == "BoraSample")
tree_models = [child for child in sample.findall("Item[@class='Model']") if name(child).endswith("Tree")]
assert len(tree_models) == 15, "Preview expects the generated 12 season samples and 3 street trees."
seasons = ["봄", "여름", "가을", "겨울"]
species = ["은행나무", "단풍나무", "소나무"]
meshes = []
for season_index in range(4):
    parts = [block((66, 0.3, 30), (0, -0.16, 0), (142, 167, 117))]
    for species_index in range(3):
        model = tree_models[species_index * 4 + season_index]
        trunk = next(p for p in model.findall("Item[@class='Part']") if name(p) == "Trunk")
        trunk_pos = read_part(trunk)["pos"]
        offset = np.array([-16 + species_index * 16 - trunk_pos[0], 0, -trunk_pos[2]])
        parts.extend(model_parts(model, offset))
    meshes.append(geometry(parts))

road_parts = [block((250, 0.3, 85), (15, -0.16, 12), (142, 167, 117))]
for model in sample.findall("Item[@class='Model']"):
    if name(model) in ("StraightRoad", "SlopeRoad"):
        road_parts.extend(model_parts(model))
for model in tree_models[12:]:
    road_parts.extend(model_parts(model))
upper = next(p for p in sample.findall("Item[@class='Part']") if name(p) == "UpperGround")
upper_part = read_part(upper)
upper_part["layer"] = 1
road_parts.append(upper_part)
road_mesh = geometry(road_parts)

frames = []
total = 80
for season_index, season in enumerate(seasons):
    for step in range(12):
        angle = math.radians(-6 + step * 1.0)
        camera = [math.sin(angle) * 65, 28, math.cos(angle) * 65]
        frame = render(meshes[season_index], camera, [0, 6, 0], 14,
                       f"나무 에셋 · {season}", "은행·단풍은 계절에 따라 잎 색과 보이는 상태가 바뀝니다.",
                       [(text, [-16 + i * 16, 0, 6]) for i, text in enumerate(species)], len(frames) / total)
        frames.append(frame)
        if step == 5:
            frame.save(OUT / f"trees_{season_index + 1}.png")
for step in range(32):
    angle = math.radians(12 + step * 0.6)
    camera = [15 + math.sin(angle) * 210, 90, 12 + math.cos(angle) * 210]
    frame = render(road_mesh, camera, [15, 3, 12], 3.6,
                   "도로 에셋 · 평지 → 오르막 → 평지", "두 끝점의 높이 차이로 경사를 계산합니다. 샘플: 80 studs에 +12, 경사 15%.",
                   [("평지", [-45, 1, 4]), ("경사 15%", [40, 8, 4]), ("높이 +12", [98, 13, 4])],
                   len(frames) / total)
    frames.append(frame)
    if step == 12:
        frame.save(OUT / "road.png")
durations = [120] * 48 + [90] * 32
for index in (11, 23, 35, 47):
    durations[index] = 400
durations[-1] = 700
frames[0].save(OUT / "BoraAssetsPreview.gif", save_all=True, append_images=frames[1:],
               duration=durations, loop=0, optimize=True, disposal=2)
with Image.open(OUT / "BoraAssetsPreview.gif") as gif:
    assert gif.n_frames == total and gif.size == (WIDTH, HEIGHT)
print(f"Created {OUT / 'BoraAssetsPreview.gif'} ({total} frames, {(OUT / 'BoraAssetsPreview.gif').stat().st_size:,} bytes)")
