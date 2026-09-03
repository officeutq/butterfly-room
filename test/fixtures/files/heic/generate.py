"""Synthetic fixtures only. Rebuild with Pillow 12.3.0 / pillow-heif 1.6.0.

No photographs, personal data, or production objects are used.
"""
from pathlib import Path

from PIL import Image, ImageDraw
from pillow_heif import register_heif_opener

register_heif_opener()
destination = Path(__file__).resolve().parent


def quadrants(width, height):
    image = Image.new("RGB", (width, height))
    draw = ImageDraw.Draw(image)
    for x, y, color in [(0, 0, "red"), (1, 0, "lime"), (0, 1, "blue"), (1, 1, "yellow")]:
        draw.rectangle((x * width // 2, y * height // 2, (x + 1) * width // 2 - 1, (y + 1) * height // 2 - 1), fill=color)
    return image


def save(image, name, **kwargs):
    image.save(destination / name, format="HEIF", quality=70, **kwargs)
    print(name, (destination / name).stat().st_size)


save(quadrants(1200, 800), "medium.heic")
save(quadrants(4000, 3000), "large.heic")
oriented = quadrants(160, 96)
oriented.getexif()[274] = 6  # Stored as container rotation + EXIF by pillow-heif.
save(oriented, "rotated.heif")
alpha = Image.new("RGBA", (96, 64), (0, 0, 0, 0))
ImageDraw.Draw(alpha).rectangle((48, 0, 95, 63), fill=(255, 0, 0, 255))
save(alpha, "alpha.heic")
# The second image is primary; the agreed policy still selects index zero.
save(Image.new("RGB", (96, 64), "red"), "multiple.heic", save_all=True,
     append_images=[Image.new("RGB", (96, 64), "blue")], primary_index=1)
