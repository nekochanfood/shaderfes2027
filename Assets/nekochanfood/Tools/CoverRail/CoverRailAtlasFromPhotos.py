# 写真フォルダの画像でカバーアトラスを作る（8x8 = 64 セルを画像の繰り返しで埋める）
# 使い方: python Assets/nekochanfood/Tools/CoverRail/CoverRailAtlasFromPhotos.py <画像フォルダ>
# 各画像は中央を正方形に切り抜く。出力と配置は CoverRailAtlas.py と同じ。
import os
import sys

from PIL import Image, ImageOps

Image.MAX_IMAGE_PIXELS = None
CELLS, CELL = 8, 256
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "Shaders", "CoverRail", "CoverRailAtlas.png")

src = sys.argv[1]
files = sorted(f for f in os.listdir(src) if f.lower().endswith((".jpg", ".jpeg", ".png")))
tiles = [ImageOps.fit(ImageOps.exif_transpose(Image.open(os.path.join(src, f))).convert("RGB"), (CELL, CELL), Image.LANCZOS) for f in files]
atlas = Image.new("RGB", (CELLS * CELL, CELLS * CELL))
for i in range(CELLS * CELLS):
    # セル i は uv 左下から数える（PNG は上から並ぶので行を反転）
    atlas.paste(tiles[i % len(tiles)], ((i % CELLS) * CELL, (CELLS - 1 - i // CELLS) * CELL))
atlas.save(os.path.normpath(OUT), optimize=True)
print("wrote", os.path.normpath(OUT), len(tiles), "images")
