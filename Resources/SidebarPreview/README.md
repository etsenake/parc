# Sidebar preview artwork

`open-in-peek` is the tab picture card's Open in Peek template image: a dimmed
window with a title bar and a smaller window stepping out in front of its lower
edge, with a clear gap around it. It uses the blocked pop-up glyph's language
([Site Control Center artwork](../SiteControlCenter/README.md)): round strokes,
the same corner radii and title bars, drawn at 16 × 16 points so its 1.24-point
strokes match the 12-point Split View symbol beside it. The dimmed window is
stroked once at 42% opacity, so the button's tint dims it the same way in light
and dark.

It has a vector `.pdf` plus `.png` and `@2x.png` renditions at 16 × 16 and
32 × 32 pixels, rendered from the same geometry with 8× supersampling.
`SidebarPreviewArtwork` combines them at the 1× point size as a template.

See [sidebar previews](../../docs/sidebar-previews.md#tab-picture-card) for the
button's behavior.
