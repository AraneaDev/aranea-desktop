"""The empty preview separator must leave background pixels untouched."""

import json
import pathlib
import subprocess
import sys

stage = pathlib.Path(sys.argv[1])
line = next(
    line
    for line in (stage / "client.log").read_text().splitlines()
    if "NATIVE PICKER " in line
)
data = json.loads(line.split("NATIVE PICKER ", 1)[1])
for name in ("empty", "populated"):
    path = str(stage / (name + ".png"))
    width, height = map(
        int,
        subprocess.check_output(
            ["magick", "identify", "-format", "%w %h", path]
        ).split(),
    )
    pixels = subprocess.check_output(["magick", path, "-depth", "8", "rgba:-"])
    x, y = (
        round(data["x"] * width / data["width"]),
        round(data["y"] * width / data["width"]),
    )
    actual = tuple(pixels[(y * width + x) * 4 : (y * width + x) * 4 + 4])
    if name == "empty":
        assert actual == (16, 16, 16, 255), (
            f"empty picker painted preview separator: {actual}"
        )
    else:
        assert actual[0] > 40 and actual[1] < 16, (
            f"populated preview separator missing: {actual}"
        )
    print(f"PASS: {name} preview separator pixel {actual}")
