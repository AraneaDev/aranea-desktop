# Vendored Three.js

Unmodified files from **Three.js 0.184.0**, released under the MIT license.
Source package: <https://registry.npmjs.org/three/-/three-0.184.0.tgz>.
The license is retained in [LICENSE](LICENSE).

- `three.module.js`, `three.core.js`: `package/build/`.
- `addons/loaders/GLTFLoader.js`: `package/examples/jsm/loaders/`.
- `addons/utils/BufferGeometryUtils.js`, `addons/utils/SkeletonUtils.js`:
  `package/examples/jsm/utils/`.
- `addons/environments/RoomEnvironment.js`: `package/examples/jsm/environments/`.

These files are bundled for offline use and excluded from project formatting
and linting so they remain byte-for-byte copies of upstream. The live page's
import map resolves `three` to this local module; no CDN imports are used.

## Kanji font

The adjacent `../kanji.woff2` is a five-glyph subset (`影光糸夢電`) of
Noto Serif CJK JP Regular, from the installed Noto CJK font collection.
Copyright © 2017–2024 Adobe. Source: <https://github.com/notofonts/noto-cjk>.
Its SIL Open Font License is retained in
[kanji-font-LICENSE](../kanji-font-LICENSE).

The subset was generated with FontTools `pyftsubset`, selecting font 0 from
`NotoSerifCJK-Regular.ttc`, the five glyphs above, and WOFF2 output. It is
bundled locally so effects work offline.
