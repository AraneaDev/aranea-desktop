# Aranea cursor integration

The repository ships the cursor metadata and palette contract, while the host
cursor theme remains the fallback for pointer shapes that cannot be distributed
as portable text assets. Install this directory only when the desktop supports
Xcursor theme directories; otherwise keep the host cursor and use the Aranea
Qt/GTK focus colors.

The intended visual roles are mint for the default/active pointer, violet for
busy or focus transitions, and red for error feedback. No cursor integration
may replace the user's existing theme without an ownership backup.
