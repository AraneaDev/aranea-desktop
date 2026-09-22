# Aranea wallpaper variants

The stable variant IDs are declared in `../manifest.toml`. The current source
collection is intentionally conservative: day/night are the canonical assets,
while sparse, dusk, monochrome, and ultrawide provide stable picker slots and
fallback to the closest readable source until dedicated artwork is supplied.

This keeps the picker and automation API stable without pretending that a
recolored or cropped asset is a new composition.
