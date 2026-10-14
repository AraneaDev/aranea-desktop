# Aranea artwork

## Cyberpunk collection

Fifteen wallpapers have distinct subjects,
compositions and moods, united by obsidian, mint #3bff9e and violet #7a5cff.
Aranea Core and Signal Shrine use the canonical Aranea spider mark as an image
reference. The other scenes were generated without image references.
The Aranea spider marks remain unchanged.

## Provenance and resolution

Generated with the built-in OpenAI imagegen tool. Unmodified outputs and
embedded provenance are retained in `sources/`; the picker uses delivery files.
The fourteen 16:9 sources are 1672×941; ultrawide is 2172×724. Delivery sizes are
3840×2160 and 3840×1280, resampled with Lanczos rather than native 4K detail.
No crop, retouching or sharpening was applied after generation. Stable IDs and paths
preserve existing wallpaper selections and schedules. Human-facing titles come
from each manifest entry’s `label`, independently of its stable ID.

| ID             | Scene                                                                    | Delivery file                 |
| -------------- | ------------------------------------------------------------------------ | ----------------------------- |
| cockpit        | Neural Deck: cinematic hacker command room                               | `variants/cockpit.png`        |
| day            | Rain City: wet megacity and elevated transit                             | `background-day.png`          |
| night          | Silent Vault: subterranean server archive                                | `background-night.png`        |
| dawn           | First Departure: sweeping maglev station                                 | `variants/dawn.png`           |
| dusk           | Dead Frequency: rooftop satellite dish                                   | `variants/dusk.png`           |
| sparse         | Black Signal: isolated desert monolith                                   | `variants/sparse.png`         |
| dense          | Undercity: crowded electronics market                                    | `variants/dense.png`          |
| monochrome     | Ghost in the Wire: silver cybernetic portrait, small mint/violet accents | `variants/monochrome.png`     |
| ultrawide      | Orbital Relay: panoramic station above a dark planet                     | `variants/ultrawide.png`      |
| aranea-core    | Aranea Core: holographic spider reactor                                  | `variants/aranea-core.png`    |
| signal-shrine  | Signal Shrine: rain-soaked illuminated spider shrine                     | `variants/signal-shrine.png`  |
| violet-pursuit | Violet Pursuit: motorcycle on a neon expressway                          | `variants/violet-pursuit.png` |
| deep-current   | Deep Current: submerged data facility                                    | `variants/deep-current.png`   |
| canopy-circuit | Canopy Circuit: suspended botanical habitat                              | `variants/canopy-circuit.png` |
| polar-freight  | Polar Freight: autonomous vessel crossing fractured polar sea ice        | `variants/polar-freight.png`  |

Preview: [collection contact sheet](../screenshots/cockpit-wallpapers.jpg).

## Export workflow

Run from the repository root with ImageMagick:

```bash
for id in cockpit day night dawn dusk sparse dense monochrome ultrawide aranea-core signal-shrine violet-pursuit deep-current canopy-circuit polar-freight; do
  case "$id" in
    day|night) destination="backgrounds/background-$id.png" ;;
    *) destination="backgrounds/variants/$id.png" ;;
  esac
  size=3840x2160
  if [ "$id" = ultrawide ]; then size=3840x1280; fi
  magick "backgrounds/sources/$id.png" -filter Lanczos \
    -resize "$size!" -define png:compression-level=9 "$destination"
done
```

Run `bash tests/assets.test.sh` and `bash tests/wallpaper.test.sh` after export.

## Generation prompts

### Neural Deck (`cockpit`)

Use case: stylized-concept. Asset: final production Aranea Linux desktop wallpaper, full bleed wide 16:9 landscape at highest available resolution. NEURAL DECK: an actual immersive cyberpunk hacker command room, cinematic architectural environment, photographed from its entrance at waist height. A low sculptural curved black workstation sweeps across the lower third around a single empty ergonomic chair; several slim smoked-glass displays cast faint abstract mint light with no readable text or recognizable application interface. An immense rounded concrete ceiling and ribbed asymmetrical architecture create an expansive dark interior with sophisticated depth. Left wall contains tall recessed equipment cabinets and braided optical cabling, violet channels illuminate the right ceiling, a narrow side window reveals distant blurred city rain. The room feels luxurious, secret, technically credible and lived-in, finely textured charcoal concrete, graphite brushed metal, satin black surfaces and damp glass; no generic symmetric science fiction bridge, no mech armor border, no flat empty central black rectangle, no mockup. Palette restricted to deep obsidian #08090b, graphite and cool neutral steel, rich luminous mint #3bff9e and violet #7a5cff. Confident mint-violet interplay with restrained atmospheric bloom, large natural dark areas through the upper center and shadowed floor for desktop readability. Strong oblique perspective, offset viewpoint, circular sweeping architecture and asymmetrical light, carefully composed and exceptionally detailed. The result must feel entirely different from an abstract armored picture frame. No people, human silhouettes, logos, spider symbols, readable letters or numbers, watermark, orange, yellow, red or pink lights. One final artwork.

### Rain City (`day`)

Use case: stylized-concept. Asset: final full-bleed Linux desktop wallpaper, wide 16:9 landscape, highest available resolution. Scene: rain-soaked cyberpunk megacity viewed from a high empty pedestrian bridge, dramatic oblique architecture, immense black skyscrapers receding into low clouds. A thin elevated train curves through the city; rain reflections make pools of mint light far below, violet light catches the fog and distant tower edges. Premium cinematic environment concept art with convincing scale, sophisticated materials and atmosphere. This is an actual outdoor city environment, with no cockpit, no mechanical framing around the image. Palette: near-black obsidian #08090b, charcoal and cool neutral concrete, neon mint #3bff9e and violet #7a5cff only for chromatic illumination. Mint is dominant, violet secondary. Upper third misty and subdued; brightest detail in the lower third; readable dark negative space amid architecture rather than an artificial blank black rectangle. No readable text, lettering, numbers, logos, spiders, watermark, fake UI, collage, orange, red, pink or yellow. One unique artwork, no mockup or border.

### Silent Vault (`night`)

Use case: stylized-concept. Asset: production Aranea Linux desktop wallpaper, full bleed, highest available resolution. Premium cinematic cyberpunk concept art, exceptional composition, convincing material detail and lighting. Restrict chromatic lighting to neon mint #3bff9e and violet #7a5cff against obsidian #08090b, charcoal and cool silver neutrals. No warm orange/red/yellow/pink light. No readable text, letters, numbers, logos, spider emblems, watermark, fake UI, collage or surrounding frame. Do not make a cockpit, mechanical border, or abstract armor wallpaper. Design useful subdued areas behind desktop windows, naturally integrated into this scene. 16:9 wide landscape. THE SILENT VAULT: cavernous abandoned subterranean data archive, shot from floor level with extreme perspective. Towering irregular rows of black glass server monoliths disappearing into darkness, thin violet status lights, a single mint-lit fiber-optic cable spilling across the foreground floor like a luminous river. Immense vaulted concrete ceiling lost in shadow, drifting cold vapor. Sparse and silent brutalist architecture, violet dominant, reflective black stone floor. Strong asymmetry and deep shadow, no central glowing portal, no city, no people.

### First Departure (`dawn`)

Use case: stylized-concept. Asset: production Aranea Linux desktop wallpaper, full bleed, highest available resolution. Premium cinematic cyberpunk concept art, exceptional composition, convincing material detail and lighting. Restrict chromatic lighting to neon mint #3bff9e and violet #7a5cff against obsidian #08090b, charcoal and cool silver neutrals. No warm orange/red/yellow/pink light. No readable text, letters, numbers, logos, spider emblems, watermark, fake UI, collage or surrounding frame. Do not make a cockpit, mechanical border, or abstract armor wallpaper. Design useful subdued areas behind desktop windows, naturally integrated into this scene. 16:9 wide landscape. FIRST DEPARTURE: deserted futuristic maglev station at cool mint dawn, a sleek dark graphite train parked along a sweeping platform that arcs across the lower half. Massive suspended curved concrete roof, delicate mint light tracing the tracks, pale cool fog through open station sides and subtle violet reflections on train metal. Elegant bright charcoal architectural minimalism, spacious and cinematic, more luminous than a night scene while retaining dark shadow. Strong curved horizontal composition, no skyline of skyscrapers, no cockpit or server racks.

### Dead Frequency (`dusk`)

Use case: stylized-concept. Asset: production Aranea Linux desktop wallpaper, full bleed, highest available resolution. Premium cinematic cyberpunk concept art, exceptional composition, convincing material detail and lighting. Restrict chromatic lighting to neon mint #3bff9e and violet #7a5cff against obsidian #08090b, charcoal and cool silver neutrals. No warm orange/red/yellow/pink light. No readable text, letters, numbers, logos, spider emblems, watermark, fake UI, collage or surrounding frame. Do not make a cockpit, mechanical border, or abstract armor wallpaper. Design useful subdued areas behind desktop windows, naturally integrated into this scene. 16:9 wide landscape. DEAD FREQUENCY: rooftop communications array above a low sea of violet fog, an immense off-center satellite dish in silhouette, slender antenna masts, tension cables and small mint navigation lights. Camera looks slightly upward into an expansive dark violet storm sky. Rooftop ledge across the lower quarter, hard violet rim light on wet metal, faint distant city lights below cloud layer. Bold graphic silhouette and vast atmospheric negative space; no crowded city canyon, no cockpit, no sunset orange.

### Black Signal (`sparse`)

Use case: stylized-concept. Asset: production Aranea Linux desktop wallpaper, full bleed, highest available resolution. Premium cinematic cyberpunk concept art, exceptional composition, convincing material detail and lighting. Restrict chromatic lighting to neon mint #3bff9e and violet #7a5cff against obsidian #08090b, charcoal and cool silver neutrals. No warm orange/red/yellow/pink light. No readable text, letters, numbers, logos, spider emblems, watermark, fake UI, collage or surrounding frame. Do not make a cockpit, mechanical border, or abstract armor wallpaper. Design useful subdued areas behind desktop windows, naturally integrated into this scene. 16:9 wide landscape. THE BLACK SIGNAL: radically minimal cyberpunk desert at night. A single impossibly tall, very slender fractured obsidian monolith on the far right third, one narrow mint seam climbing its face and a tiny violet halo spilling into dark dust. Huge empty charcoal sky and almost black smooth dunes, tiny horizon, soft film grain. Restrained fine-art science-fiction photography, clean silhouettes, 80 percent negative space. No mechanical frame, no city, no other buildings, no circular portals or interface.

### Undercity (`dense`)

Use case: stylized-concept. Asset: production Aranea Linux desktop wallpaper, full bleed, highest available resolution. Premium cinematic cyberpunk concept art, exceptional composition, convincing material detail and lighting. Restrict chromatic lighting to neon mint #3bff9e and violet #7a5cff against obsidian #08090b, charcoal and cool silver neutrals. No warm orange/red/yellow/pink light. No readable text, letters, numbers, logos, spider emblems, watermark, fake UI, collage or surrounding frame. Do not make a cockpit, mechanical border, or abstract armor wallpaper. Design useful subdued areas behind desktop windows, naturally integrated into this scene. 16:9 wide landscape. UNDERCITY: intimate dense cyberpunk street market beneath elevated infrastructure, wide-angle view at human eye level from a narrow wet side lane. Layered vendor kiosks, bundled overhead utility cables, hanging abstract luminous mint and violet light panels without lettering, dark fabric awnings, chrome repairs and microelectronics stalls. A few tiny anonymous hooded silhouettes deep in the distance, foreground empty. Saturated mint and violet pools reflected on puddles, dense lived-in gritty detail, diagonals and irregular shapes, deep dark passage. No legible signage, no repeating megacity tower panorama, no cockpit.

### Ghost in the Wire (`monochrome`)

Use case: stylized-concept. Asset: production Aranea Linux desktop wallpaper, full bleed, highest available resolution. Premium cinematic cyberpunk concept art, exceptional composition, convincing material detail and lighting. Restrict chromatic lighting to neon mint #3bff9e and violet #7a5cff against obsidian #08090b, charcoal and cool silver neutrals. No warm orange/red/yellow/pink light. No readable text, letters, numbers, logos, spider emblems, watermark, fake UI, collage or surrounding frame. Do not make a cockpit, mechanical border, or abstract armor wallpaper. Design useful subdued areas behind desktop windows, naturally integrated into this scene. 16:9 wide landscape. GHOST IN THE WIRE: striking close-up portrait of a mysterious adult androgynous cybernetic hacker, head and shoulders occupying the left third in profile looking toward the open dark right side. Obsidian hood, pale cool silver synthetic skin with extremely fine etched seams, delicate black braided neural cables behind the head. One narrow mint eye sensor, faint violet rim light on the cheek and hood. Mostly black and silver with only these small theme-color lights. Fashion-editorial cyberpunk photography, impeccable face anatomy, dramatic chiaroscuro, 60 percent empty black background. No city, no room, no large machinery, no text, no weapons.

### Orbital Relay (`ultrawide`)

Use case: stylized-concept. Asset: production Aranea Linux desktop wallpaper, full bleed, highest available resolution. Premium cinematic cyberpunk concept art, exceptional composition, convincing material detail and lighting. Restrict chromatic lighting to neon mint #3bff9e and violet #7a5cff against obsidian #08090b, charcoal and cool silver neutrals. No warm orange/red/yellow/pink light. No readable text, letters, numbers, logos, spider emblems, watermark, fake UI, collage or surrounding frame. Do not make a cockpit, mechanical border, or abstract armor wallpaper. Design useful subdued areas behind desktop windows, naturally integrated into this scene. Dedicated extreme 3:1 panoramic landscape aspect ratio, 3840x1280 if possible. ORBITAL RELAY: immense thin orbital antenna station sweeping diagonally through deep black space, seen from outside at a great distance. A dark planet's curved limb runs along the bottom, thin luminous mint atmospheric rim, enormous station trusses catch violet edge light, fine mint power nodes and delicate communication sails at opposite ends. Off-center station forms a precise sweeping silhouette rather than filling the panorama, huge serene areas of starless black space, very sparse stars, majestic science-fiction scale. No inside cockpit, no room, no rectangular mechanical border, no bright central sun, no bright white moon.

### Aranea Core (`aranea-core`)

Input reference: `branding/marks/aranea-glyph.svg`, rasterized for generation;
the source vector remains unchanged.

Use case: stylized-concept. Final Aranea desktop wallpaper, full-bleed wide 16:9 landscape, highest available resolution. Premium cinematic cyberpunk concept art, rich physical materials, atmospheric depth, sophisticated bloom and composition. Palette: obsidian #08090b, graphite and cool silver neutrals, luminous mint #3bff9e and violet #7a5cff. No orange, yellow, red or pink lighting. Keep naturally integrated darker areas for desktop windows and a subdued top-bar region. No readable text, letters, numbers, watermark, fake UI, collage or surrounding frame. Transform the provided Aranea spider mark into this scene, using the image only as the exact emblem design reference. Preserve the recognizable silhouette, leg arrangement, angular central A-shaped structure and faceted abdomen; do not invent a different logo or an organic spider. A colossal holographic mint Aranea emblem hovers inside an asymmetrical industrial fusion chamber, encircled by thin incomplete violet magnetic rings suspended at different depths. Camera low and off-axis, looking across a vast dark brushed-metal floor into the cavern; emblem placed right of center, not filling the image. Hologram feels volumetric with fine luminous particles while the silhouette remains crisply recognizable. Heavy matte-black reactor machinery, small mint conduits, vapor and graphite concrete architecture. Dark left half, strong cinematic depth, not an abstract armored border or a cockpit, no screens or people. The emblem is one meaningful physical hologram in the environment, not a flat watermark.

### Signal Shrine (`signal-shrine`)

Input reference: `branding/marks/aranea-glyph.svg`, rasterized for generation;
the source vector remains unchanged.

Use case: stylized-concept. Final Aranea desktop wallpaper, full-bleed wide 16:9 landscape, highest available resolution. Premium cinematic cyberpunk concept art, rich physical materials, atmospheric depth, sophisticated bloom and composition. Palette: obsidian #08090b, graphite and cool silver neutrals, luminous mint #3bff9e and violet #7a5cff. No orange, yellow, red or pink lighting. Keep naturally integrated darker areas for desktop windows and a subdued top-bar region. No readable text, letters, numbers, watermark, fake UI, collage or surrounding frame. Transform the provided Aranea spider mark into this scene, using the image only as the exact emblem design reference. Preserve its recognizable silhouette, leg arrangement, angular central A-shaped structure and faceted abdomen; no invented organic spider or alternate logo. Rain-soaked cyberpunk backstreet shrine: a large sculptural mint-lit Aranea emblem embedded into a weathered obsidian concrete wall on the far left foreground, viewed obliquely so the wall recedes into a narrow alley. Violet mist drifts through the otherwise dark right half, wet pavement mirrors fragments of green, bundled cables and metal ventilation grilles provide tactile scale. Emblem constructed of precisely machined recessed glass with thin luminous edges, not a floating watermark. Intimate street-level architectural photography, quiet and mysterious, strong asymmetry, no human figures, no towers panorama, no desert monolith, no cockpit, no legible signs.

### Violet Pursuit (`violet-pursuit`)

Use case: stylized-concept. Final Aranea desktop wallpaper, full-bleed wide 16:9 landscape, highest available resolution. Premium cinematic cyberpunk concept art, rich physical materials, atmospheric depth, sophisticated bloom and composition. Palette: obsidian #08090b, graphite and cool silver neutrals, luminous mint #3bff9e and violet #7a5cff. No orange, yellow, red or pink lighting. Keep naturally integrated darker areas for desktop windows and a subdued top-bar region. No readable text, letters, numbers, watermark, fake UI, collage or surrounding frame. One black futuristic motorcycle with an adult rider in a fully enclosed dark helmet races across a suspended industrial expressway at night, dramatic low tracking side view. Bike and rider occupy the lower right third with ample darker space above and left. Wet graphite asphalt reflects a slender mint energy trail from the bike; violet-lit support girders streak softly in the distance. Sharp vehicle sculptural engineering, quiet silver reflections, atmospheric speed without messy blur over the subject, elegant neon rim light. Subject is the vehicle and physical motion, not a city skyline or portrait. No weapons, no logos, no readable signage, no extra motorcycles. Distinct confident dynamic diagonal composition, cinematic near-photoreal science-fiction photography.

### Deep Current (`deep-current`)

Use case: stylized-concept. Final Aranea desktop wallpaper, full-bleed wide 16:9 landscape, highest available resolution. Premium cinematic cyberpunk concept art, rich physical materials, atmospheric depth, sophisticated bloom and composition. Palette: obsidian #08090b, graphite and cool silver neutrals, luminous mint #3bff9e and violet #7a5cff. No orange, yellow, red or pink lighting. Keep naturally integrated darker areas for desktop windows and a subdued top-bar region. No readable text, letters, numbers, watermark, fake UI, collage or surrounding frame. A submerged cyberpunk data facility beneath a dark ocean, viewed from outside through shadowed water. Huge low glass capsules and vertical graphite server pylons rest on the seafloor, connected by flowing bundles of luminous mint fiber-optic cables. Dim violet security lights reveal geometric silhouettes through silt and drifting bubbles; mint reflections ripple in the glass. A small uncrewed maintenance drone provides scale deep in the scene. Immense dark water occupies the upper two thirds; detailed foreground rock and precise industrial architecture concentrate along the bottom. No bright blue ocean, no tropical water, no sunlight, no people, no biological creatures, no logos, no readable labels, no central giant portal. Serene ominous underwater environment with slow flowing curves, entirely different from above-ground city and corridor scenes.

### Canopy Circuit (`canopy-circuit`)

Use case: stylized-concept. Asset type: dark 16:9 Linux desktop wallpaper titled Canopy Circuit. Create cinematic high detail concept art of a suspended botanical habitat inside a vast obsidian megastructure: sculptural hanging gardens, cascading delicate ferns and glass cultivation pods suspended by fine structural cables, mist drifting through immense dark architectural space. Organic silhouettes and physical brushed metal, believable restrained engineering. Asymmetric wide composition with the garden clustered in the lower right and distant small suspended platforms giving scale; upper quarter and central left remain naturally dark spacious atmosphere for desktop panels. Palette overwhelmingly near black obsidian #08090b with restrained mint green #3bff9e grow-light accents and subtle violet #7a5cff reflected haze. Beautiful understated luminous foliage, deep shadow, no bright white expanses. Wide landscape 16:9, highest available resolution. No people, no city skyline, no server room, no corridor, no lettering, logos, UI, watermark or spider symbol.

### Polar Freight (`polar-freight`)

Use case: stylized-concept. Asset type: dark 16:9 Linux desktop wallpaper titled Polar Freight. Cinematic exceptionally detailed physical science-fiction environment: one vast uncrewed graphite-black industrial cargo vessel crossing fractured polar sea ice at night, seen from a high distant three-quarter aerial viewpoint. Sculptural low angular hull, containers and precise deck cranes, sparse thin mint navigation lights and subtle violet deck illumination. The vessel sits across lower right third, a narrow dark open-water wake recedes through irregular fractured charcoal ice floes. An expansive almost-black sky and distant low fog over the frozen sea provide readable negative space in upper half and left. Ice is dark steel grey under nocturnal illumination, with restrained mint edge reflections and violet haze, not bright white snow. Palette obsidian #08090b, cool graphite metal, tiny mint #3bff9e accents and violet #7a5cff. Majestic solitude, tangible ice texture, restrained cinematic light, realistic scale, wide landscape 16:9 highest available resolution. No people, buildings, city, underwater facility, motorcycles, logos, text, numbers, screens, UI, borders or watermark. No daylight or warm orange/pink light.

## Native vector assets

The existing Aranea spider silhouette, semantic state glyphs, and cursor
geometry are preserved. Cursor source trees remain byte-identical.
