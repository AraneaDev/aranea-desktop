# Cinematic Precision artwork

Seven independently generated static wallpapers share an obsidian field,
asymmetric peripheral spider-silk topology, fine mint/violet filaments, and
quiet central and upper regions. The recognizable Aranea spider remains in
the native SVG mark system; the wallpapers evoke it through silk rather than
placing a competing central logo behind working windows.

## Provenance and resolution

All raster artwork was made with the built-in OpenAI imagegen tool. No CLI/API
fallback, stock imagery, or external reference image was used. The unmodified
generator PNGs are retained in `sources/`, including their embedded provenance.
They are development sources and are not referenced by the wallpaper picker.

The tool returned 1672×941 for each 16:9 request and 2172×724 for ultrawide,
despite the requested native dimensions. The shipped wallpapers are Lanczos
exports at 3840×2160 and 3840×1280 respectively. **These are upscaled delivery
files, not native 4K generated detail.** No crop, retouching, artificial
sharpening, or added logo was applied. The tiny 16:9 rounding discrepancy in
the source is normalized to the exact delivery aspect ratio.

| ID | Original source | Shipped file | Composition |
| --- | --- | --- | --- |
| day | `sources/day.png` | `background-day.png` | Mint silk, brighter charcoal, lower-left weight |
| night | `sources/night.png` | `background-night.png` | Mint/violet silk, dark field, lower-right weight |
| sparse | `sources/sparse.png` | `variants/sparse.png` | Small lower-left cluster, almost empty field |
| dense | `sources/dense.png` | `variants/dense.png` | Richer right-edge strands and dimensional junctions |
| dusk | `sources/dusk.png` | `variants/dusk.png` | Soft violet atmosphere and left-edge silk |
| monochrome | `sources/monochrome.png` | `variants/monochrome.png` | Silver silk on black, right-edge weight |
| ultrawide | `sources/ultrawide.png` | `variants/ultrawide.png` | Dedicated 3:1 composition, mint left/violet right |

## Export workflow

Run from the repository root with ImageMagick installed:

```bash
for id in day night sparse dense dusk monochrome; do
  case "$id" in
    day|night) destination="backgrounds/background-$id.png" ;;
    *) destination="backgrounds/variants/$id.png" ;;
  esac
  magick "backgrounds/sources/$id.png" -filter Lanczos \
    -resize '3840x2160!' -define png:compression-level=9 "$destination"
done
magick backgrounds/sources/ultrawide.png -filter Lanczos \
  -resize '3840x1280!' -define png:compression-level=9 \
  backgrounds/variants/ultrawide.png
```

Inspect every export, then run `bash tests/assets.test.sh` and
`bash tests/wallpaper.test.sh`. Keep the existing manifest IDs and paths.

## Generation prompts

### Night

Use case: stylized-concept. Asset type: production desktop wallpaper for the Aranea Linux theme, NIGHT variant. Generate one full-bleed native 3840x2160 16:9 raster image. Premium cinematic abstract spider-silk network in deep obsidian black (#080b10), quiet photographic atmospheric depth. Ultra-fine luminous filaments connect very sparse precise pinhead nodes, mint (#79efc3) with restrained cool violet (#9186d8). An asymmetric delicate silk topology hugs the lower-right edge and a smaller cluster at the left edge, with beautiful fine material detail. The whole central 65% and upper 10% bar region must stay near-black and calm with no bright features. Extremely subtle violet atmospheric depth near the lower edge only. Elegant contemporary art direction, disciplined contrast, crisp fine strands, no broad glowing beams, no star field. Aranea identity is evoked through spider silk topology, do not add a literal spider or any logo. No text, letters, watermark, UI, frame, charts or labels. This is final production artwork, not a mockup. Output exactly 3840x2160 pixels if supported.

### Day

Use case: stylized-concept. Asset type: production desktop wallpaper for Aranea Linux theme, DAY variant. Generate one full-bleed native 3840x2160 16:9 image. Premium cinematic abstract spider-silk network on charcoal obsidian (#10161c), a restrained daytime companion still suitable for a dark desktop. Extremely fine luminous mint (#79efc3) filaments with a few pearl-green pinhead junctions curve through a small asymmetric cluster hugging the lower-left edge and a much smaller cluster at the far right. Dim slate atmospheric depth, subtle mint light from off-canvas left. Center 65% and top 10% must be uniform quiet dark charcoal with no bright features. Beautiful precise microscopic silk details, gently graded depth, sparse topology, elegant sophisticated minimalism, no thick beams, no grainy stars. Spider identity is abstract silk topology, no literal spider, logo, text, watermark, UI, frame or labels. This is final artwork, not a mockup. Output exactly 3840x2160 if supported.

### Sparse

Use case: stylized-concept. Asset type: production Aranea Linux desktop wallpaper, SPARSE variant. One full-bleed 3840x2160 16:9 image, exact 4K requested. Obsidian black (#080b10) with extraordinarily sparse mint (#79efc3) spider-silk topology. Only a few fine filaments and tiny pinprick mint nodes occupy the far lower-left corner, with two or three dim violet threads grazing the extreme right edge. At least 80% of the canvas is quiet near-black, especially all center and top 12%. Delicate precision macro material detail, low-noise refined gradients, elegant contemporary minimalism, barely perceptible atmosphere. A functional quiet working wallpaper with restrained cinematic depth. No text, logo, literal spider, star field, broad glows, UI, border or watermark. No large objects, no bright center.

### Dense

Use case: stylized-concept. Asset type: production Aranea Linux wallpaper, DENSE variant. Generate a full-bleed native 3840x2160 16:9 image. A rich intricate yet disciplined web of hair-fine luminous silk filaments, asymmetrically concentrated at the right and lower-right perimeter with a tiny counterpoint at the lower left. Elegant mint and muted violet precise nodes, deep dark obsidian background. Layers of sharp foreground filament and softly defocused distant silk create cinematic dimensionality without broad glow. Richer peripheral topology than a minimal variant, but central 65% of frame and top 10% must remain very dark, empty and calm for work and a desktop bar. No lines crossing center, no literal spider, no text, logos, UI, watermark, border, stars or broad neon beams. Exceptional production wallpaper polish, tasteful precision, no visual noise in center. Exact 3840x2160 requested.

### Dusk

Use case: stylized-concept. Asset type: production Aranea Linux desktop wallpaper, DUSK variant. One full-bleed 3840x2160 16:9 image. Deep obsidian-purple (#0d0c16), soft dim violet twilight atmospheric depth hugging the lower-left edge only. Beautiful hair-thin spider-silk filaments with quiet lavender junctions and extremely restrained mint flecks, delicate asymmetric topology at far left and lower perimeter, a small faint answering strand at far right. Soft low-contrast filaments create a calming cinematic wallpaper. Center 65% and top 10% remain dark and empty for windows and bar. No bright nebula, no star field, no large rings or discs, no broad neon beams, no literal spider. No text, logos, watermark, UI, border or labels. Premium quiet abstract material study with fine depth and sparse precise nodes. Exact 3840x2160 requested.

### Monochrome

Use case: stylized-concept. Asset type: production Aranea Linux desktop wallpaper, MONOCHROME variant. One full-bleed 3840x2160 16:9 image. Strictly achromatic black, charcoal and silver-white, no colored pixels. A premium cinematic macro study of extremely fine silver spider-silk filaments on deep black. Sparse luminous white pinhead nodes at intersections, asymmetrical narrow silk topology hugging the lower-right perimeter and a much smaller dim cluster at left edge. Intricate material detail at edge with crisp high contrast silver highlights and soft depth, central 65% and top 10% uniformly near-black and quiet for work. Elegant minimalist art direction. No spider, logo, text, watermark, stars, UI, frame, thick beams, broad glow or central subject. Exact 3840x2160 requested.

### Ultrawide

Use case: stylized-concept. Asset type: production Aranea Linux ULTRAWIDE desktop wallpaper. Generate one native 3840x1280 panoramic 3:1 image. Entire image is a cinematic extremely dark obsidian field with precise hair-thin spider-silk topology at the extreme left and extreme right edges. Delicate mint filaments and sparse pearl-mint pinhead nodes occupy the lower-left extreme, while a smaller muted violet cluster occupies far right, asymmetric and beautifully balanced across a very wide panoramic composition. Quiet atmospheric depth, crisp material detail and softly defocused peripheral strands. Central 70% and upper 12% remain almost black, clean and empty for windows and a desktop bar. Fine luminous lines, restrained highlights, premium minimalism. No literal spider, logo, text, star field, watermark, UI, mockup, border, central object, thick beams or broad glow. Strict panoramic 3:1 framing; exact requested output 3840x1280 pixels.

## Native vector assets

The primary and ceremony SVG marks retain the existing traced Aranea spider
silhouette. The reduced mark retains its simplified eight-leg geometry with
slightly lighter rounded strokes and a mint-only gradient; the ceremony halo
uses finer, quieter ticks. Network motifs use restrained neutral hairlines,
smaller nodes, and short mint/violet accents to match the wallpaper language.
Existing semantic state glyphs and cursor geometry, animation frames, and
hotspots are preserved. Cursor source trees must remain byte-identical.
