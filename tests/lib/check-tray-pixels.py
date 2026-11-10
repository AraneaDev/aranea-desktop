"""Verify opaque pixels captured from both actual tray renderers, using ImageMagick."""

import json
import pathlib
import subprocess
import sys

stage = pathlib.Path(sys.argv[1])
line = next(
    line
    for line in (stage / "client.log").read_text().splitlines()
    if "NATIVE PIXELS " in line
)
data = json.loads(line.split("NATIVE PIXELS ", 1)[1])
path = str(stage / "tray.png")
width, height = map(
    int,
    subprocess.check_output(["magick", "identify", "-format", "%w %h", path]).split(),
)
pixels = subprocess.check_output(["magick", path, "-depth", "8", "rgba:-"])
scale = width / data["width"]
assert len(data["points"]) == 6, "both production renderers must be captured"
failures = []
for point in data["points"]:
    x, y = round(point["x"] * scale), round(point["y"] * scale)
    assert 0 <= x < width and 0 <= y < height
    actual = tuple(pixels[(y * width + x) * 4 : (y * width + x) * 4 + 4])
    mx, my = round(point["marginX"] * scale), round(point["marginY"] * scale)
    margin = tuple(pixels[(my * width + mx) * 4 : (my * width + mx) * 4 + 4])
    if margin != (16, 16, 16, 255):
        failures.append(f"{point['name']}: source-alpha margin painted {margin}")
    expected = tuple(bytes.fromhex(point["color"].lstrip("#"))) + (255,)
    if not all(abs(a - e) <= 2 for a, e in zip(actual, expected)):
        failures.append(f"{point['name']}: got {actual}, expected {expected}")
    else:
        print(f"PASS: {point['name']} real shader pixel {actual}")
assert not failures, "\n".join(failures)
