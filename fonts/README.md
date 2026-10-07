# Bundled fonts

Inter is Aranea's default interface face, paired with JetBrains Mono for
technical text. IBM Plex Sans offers open counters and an engineered character;
Source Sans 3 is the softer humanist alternative available in Appearance.
Both families ship Regular, Medium, Semibold, Bold and Italic desktop fonts.

Inter provides a neutral interface: all nine weights (Thin through
Black) with italics, in text and display cuts, plus the variable family.
JetBrains Mono and JetBrains Mono NL (without ligatures) each ship all eight
weights (Thin through ExtraBold) with italics. Existing Nerd Font selections
are preserved; the bundled original JetBrains faces do not replace icon fonts.

The unmodified TTF files and their SIL Open Font License texts come from:

- [IBM Plex](https://github.com/IBM/plex), revision
  `763c36ef9117782905ae010056dfbe8fd2653a25`,
  `packages/plex-sans/fonts/complete/ttf/`.
- [Adobe Source Sans](https://github.com/adobe-fonts/source-sans), revision
  `87b37a2daaed80fcb8e8ccb0085c4d72ddade12e`, `TTF/`.
- [Inter 4.1](https://github.com/rsms/inter/releases/tag/v4.1),
  `extras/ttf/` and `InterVariable*.ttf` from the official release archive.
- [JetBrains Mono 2.304](https://github.com/JetBrains/JetBrainsMono/releases/tag/v2.304),
  `fonts/ttf/` from the official release archive, with `AUTHORS.txt`.

All bundled fonts permit redistribution under the SIL Open Font License 1.1;
each family directory includes its original copyright and license text. These
are unmodified desktop fonts; duplicate web/OTF formats are not installed.
JetBrains Sans is not included because no redistribution license was verified.

Run `scripts/install-fonts` to copy them into `$XDG_DATA_HOME/fonts/aranea/`
(default `~/.local/share/fonts/aranea/`) and refresh the font cache when files
change. The installer and Aranea's theme-set/post-boot hooks also do this.
Installation does not alter saved font preferences, desktop font aliases or
terminal fonts. The files remain installed after theme removal, for documents
and applications that selected them.
