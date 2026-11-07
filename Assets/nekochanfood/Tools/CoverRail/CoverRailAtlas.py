# CoverRail のカバー画像アトラスを作る
# 8 x 8 = 64 枚のジャケット風の絵を、柄（STYLES）と配色（PALETTES）の組み合わせで描く
# 使い方: python Assets/nekochanfood/Tools/CoverRail/CoverRailAtlas.py
# 出力: Assets/nekochanfood/Shaders/CoverRail/CoverRailAtlas.png（シェーダーの _Atlas / _AtlasCells と合わせる）
import colorsys
import os

import numpy as np
from PIL import Image

CELLS = 8
CELL = 256
SEED = 2027
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "Shaders", "CoverRail", "CoverRailAtlas.png")

rng = np.random.default_rng(SEED)
# セル内の座標（0..1、y は上向き）
y, x = np.mgrid[0:CELL, 0:CELL] / (CELL - 1.0)
y = 1.0 - y


def hsv(h, s, v):
    return np.array(colorsys.hsv_to_rgb(h % 1.0, s, v))


# 配色: 基準の色相 h から 3 色を作る
PALETTES = {
    "vivid": lambda h: [hsv(h, 0.85, 0.95), hsv(h + 0.5, 0.8, 0.9), hsv(h + 0.08, 0.3, 1.0)],
    "pastel": lambda h: [hsv(h, 0.3, 0.98), hsv(h + 0.33, 0.35, 0.95), hsv(h + 0.66, 0.25, 1.0)],
    "mono": lambda h: [hsv(h, 0.05, 0.9), hsv(h, 0.05, 0.12), hsv(h, 0.0, 0.5)],
    "dark": lambda h: [hsv(h, 0.6, 0.18), hsv(h + 0.05, 0.7, 0.55), hsv(h, 0.2, 0.9)],
    "neon": lambda h: [hsv(h, 0.4, 0.06), hsv(h, 1.0, 1.0), hsv(h + 0.4, 1.0, 1.0)],
    "earth": lambda h: [hsv(0.08 + 0.05 * np.sin(h * 6), 0.45, 0.75), hsv(0.25, 0.4, 0.4), hsv(0.1, 0.2, 0.95)],
    "duotone": lambda h: [hsv(h, 0.9, 0.35), hsv(h + 0.15, 0.6, 1.0), hsv(h + 0.15, 0.2, 1.0)],
    "warm": lambda h: [hsv(0.0 + 0.1 * (h % 1), 0.85, 0.9), hsv(0.12, 0.9, 1.0), hsv(0.95, 0.5, 0.35)],
}


def mix(a, b, t):
    t = np.clip(t, 0, 1)[..., None]
    return a * (1 - t) + b * t


def aa(d, w=1.5 / CELL):
    # 符号付き距離 d（負が内側）を、縁をぼかした塗りの割合へ
    return np.clip(0.5 - d / w, 0, 1)


def value_noise(scale):
    g = rng.random((scale + 1, scale + 1))
    gx, gy = x * scale, y * scale
    ix, iy = np.minimum(gx.astype(int), scale - 1), np.minimum(gy.astype(int), scale - 1)
    fx, fy = gx - ix, gy - iy
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a, b = g[iy, ix], g[iy, ix + 1]
    c, d = g[iy + 1, ix], g[iy + 1, ix + 1]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def gradient(c):
    ang = rng.random() * np.pi * 2
    t = (x - 0.5) * np.cos(ang) + (y - 0.5) * np.sin(ang) + 0.5
    img = mix(c[0], c[1], t)
    r = np.hypot(x - rng.uniform(0.3, 0.7), y - rng.uniform(0.3, 0.7))
    return mix(img, c[2], aa(r - rng.uniform(0.12, 0.25)) * 0.9)


def stripes(c):
    ang = rng.choice([0, np.pi / 4, np.pi / 2, -np.pi / 4])
    n = rng.integers(4, 12)
    t = ((x * np.cos(ang) + y * np.sin(ang)) * n) % 1.0
    return mix(c[0], c[1], aa(np.abs(t - 0.5) - 0.22, 1.5 * n / CELL))


def rings(c):
    cx, cy = rng.uniform(0.2, 0.8, 2)
    r = np.hypot(x - cx, y - cy)
    n = rng.integers(5, 14)
    t = (r * n) % 1.0
    img = mix(c[0], c[1], aa(np.abs(t - 0.5) - 0.2, 1.5 * n / CELL))
    return mix(img, c[2], aa(r - 0.06))


def shapes(c):
    img = np.broadcast_to(c[0], x.shape + (3,)).copy()
    for _ in range(rng.integers(2, 5)):
        cx, cy, s = rng.uniform(0.15, 0.85), rng.uniform(0.15, 0.85), rng.uniform(0.08, 0.3)
        kind = rng.integers(3)
        if kind == 0:
            d = np.hypot(x - cx, y - cy) - s
        elif kind == 1:
            d = np.maximum(np.abs(x - cx), np.abs(y - cy)) - s
        else:
            # 三角形
            d = np.maximum(np.abs(x - cx) * 0.866 + (y - cy) * 0.5, -(y - cy)) - s * 0.5
        img = mix(img, c[1 + rng.integers(2)], aa(d))
    return img


def halftone(c):
    n = rng.integers(10, 22)
    gx, gy = (x * n) % 1 - 0.5, (y * n) % 1 - 0.5
    size = 0.48 * np.clip(1 - np.hypot(x - 0.5, y - 0.5) * rng.uniform(0.8, 1.6), 0.05, 1)
    return mix(c[0], c[1], aa(np.hypot(gx, gy) - size, 1.5 * n / CELL))


def clouds(c):
    n = value_noise(4) * 0.6 + value_noise(9) * 0.3 + value_noise(23) * 0.1
    n = (n - n.min()) / (n.max() - n.min() + 1e-6)
    img = mix(c[0], c[1], n)
    return mix(img, c[2], np.clip((n - 0.75) * 4, 0, 1))


def blocks(c):
    # 色の矩形で分割（モンドリアン風）
    img = np.broadcast_to(c[2], x.shape + (3,)).copy()
    sx, sy = rng.uniform(0.25, 0.75, 2)
    img = mix(img, c[0], aa(np.maximum(x - sx, y - sy)))
    img = mix(img, c[1], aa(np.maximum(sx - x, sy - y)))
    line = np.minimum(np.abs(x - sx), np.abs(y - sy)) - 0.012
    return mix(img, np.zeros(3) + 0.08, aa(line))


def waves(c):
    n = rng.uniform(3, 8)
    amp = rng.uniform(0.02, 0.08)
    t = ((y + np.sin(x * np.pi * 2 * rng.uniform(1, 3)) * amp) * n) % 1.0
    img = mix(c[0], c[1], aa(np.abs(t - 0.5) - 0.25, 1.5 * n / CELL))
    return mix(img, c[2], aa(y - 0.12) * 0.85)


def minimal(c):
    # 無地に細い線と小さなタイトル帯
    img = mix(c[0], c[0] * 0.8, y * 0.5)
    lx = rng.uniform(0.2, 0.8)
    img = mix(img, c[1], aa(np.abs(x - lx) - 0.006))
    bar = np.maximum(np.abs(x - 0.5) - 0.3, np.abs(y - 0.18) - 0.025)
    return mix(img, c[2], aa(bar))


STYLES = [gradient, stripes, rings, shapes, halftone, clouds, blocks, waves, minimal]


def title_bar(img, c):
    # ジャケットの文字の代わりの短い帯（半分くらいのカバーに付ける）
    if rng.random() < 0.5:
        return img
    top = rng.random() < 0.5
    yy = rng.uniform(0.82, 0.9) if top else rng.uniform(0.08, 0.16)
    w = rng.uniform(0.15, 0.4)
    x0 = rng.uniform(0.08, 0.92 - w)
    d = np.maximum(np.abs(x - x0 - w / 2) - w / 2, np.abs(y - yy) - 0.018)
    col = c[2] if rng.random() < 0.5 else 1 - c[0]
    return mix(img, col, aa(d))


def main():
    atlas = np.zeros((CELLS * CELL, CELLS * CELL, 3))
    names = list(PALETTES)
    for i in range(CELLS * CELLS):
        # 柄と配色を偏りなく回し、色相は乱数で散らす
        style = STYLES[i % len(STYLES)]
        pal = PALETTES[names[(i * 5 + i // len(STYLES)) % len(names)]](rng.random())
        img = title_bar(style(pal), pal)
        # 縁をわずかに暗くして、隣と分ける
        edge = np.minimum(np.minimum(x, 1 - x), np.minimum(y, 1 - y))
        img = img * (0.85 + 0.15 * np.clip(edge * 40, 0, 1))[..., None]
        # セル (cx, cy) は uv の左下から数える（PNG は上から並ぶので行を反転）
        cx, cy = i % CELLS, i // CELLS
        row = CELLS - 1 - cy
        atlas[row * CELL:(row + 1) * CELL, cx * CELL:(cx + 1) * CELL] = img
    Image.fromarray((np.clip(atlas, 0, 1) * 255 + 0.5).astype(np.uint8)).save(os.path.normpath(OUT), optimize=True)
    print("wrote", os.path.normpath(OUT))


if __name__ == "__main__":
    main()
