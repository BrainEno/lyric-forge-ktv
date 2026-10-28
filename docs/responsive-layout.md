# LyricForge Responsive Layout Standard

LyricForge targets both desktop windows and mobile screens. Responsive behavior must be driven by the **available viewport**, not by device-name checks alone. A desktop window can become phone-sized when resized; a tablet can be wide enough for a desktop-like two-pane layout.

## Width classes

| Class | Width | Intended use |
| --- | ---: | --- |
| Compact | `< 600` | phone portrait, very narrow desktop window |
| Medium | `600–839` | large phone landscape, small tablet, narrow desktop |
| Expanded | `840–1199` | tablet landscape, small desktop window |
| Large | `1200–1599` | standard desktop |
| Extra Large | `>= 1600` | large desktop / ultrawide |

Use `AppResponsive` / `AppLayoutSpec`. Do not add new feature-local width constants unless a component has a documented intrinsic requirement that cannot be expressed by the shared spec.

## Height classes

Height is independent from width:

- Short: `< 600`
- Regular: `600–899`
- Tall: `>= 900`

Short-height layouts must avoid fixed tall heroes, large artwork plus long control stacks, and unbounded `Expanded` children inside scroll views. Two-pane player layouts are disabled in short-height viewports even when the window is wide.

## Navigation

- Compact / Medium: bottom navigation, tabs, or in-page controls.
- Expanded+ (`>= 840`) and non-short height: `NavigationRail` is preferred when the surface has several peer destinations, including tablets and resized desktop windows.
- Short-height landscape screens stay on bottom/in-page navigation even when width barely crosses 840.
- Do not expose more than five primary destinations in a bottom `NavigationBar`. Secondary destinations belong in the page header, overflow menu, or nested surface.
- Resizing across 840 must change navigation composition without resetting the active destination or business state.

## Content width and gutters

Page gutters are centralized in `AppLayoutSpec.pageGutter`:

- Compact: 12
- Medium: 16
- Expanded: 24
- Large: 32
- Extra Large: 40

Large monitors must gain whitespace instead of endlessly stretching text, forms, lyric columns, or player cards. Top-level surfaces should respect `contentMaxWidth` / `playerContentMaxWidth` or use `ResponsiveContentFrame`.

## Player layouts

- `< 1080`: single-column / stacked player and queue.
- `>= 1080` **and** non-short height: two-pane player + queue is allowed.
- On short-height windows, prefer scrollable single-column content even when width is large.
- Artwork has a viewport-dependent maximum and must never force transport controls below the visible viewport.
- The persistent player bar keeps artwork/title + primary transport + queue visible first. Secondary actions collapse before the primary transport does.
- `< 600` desktop windows use a minimal persistent-player density rather than shrinking every control.
- `600–839` uses compact transport; `>= 840` can expose secondary song actions and playback-mode controls inline.

## Interactive targets

- Touch platforms keep at least 48dp interactive targets at every width class.
- Compact / Medium desktop windows also keep 48dp targets because secondary actions should already be collapsed.
- Expanded desktop+: secondary pointer-oriented controls may use 40dp.
- Primary play/pause remains larger (56–64dp on full player surfaces).
- Do not reduce hit targets just to make a row fit; collapse secondary actions into overflow instead.

## Grid/list behavior

Use `AppLayoutSpec.gridColumns()` for media grids. Prefer minimum tile width over hard-coded column counts. Extra-large displays may add columns, but cap the result so covers do not become tiny.

List views should remain the fallback for dense metadata and short-height layouts.

## Typography and density

Do not scale all typography with viewport width. Preserve the theme type scale and change hierarchy through layout, max width, wrapping, and visibility of secondary metadata.

Long Unicode titles (Chinese, Japanese, emoji, combining characters) must use `maxLines` + ellipsis where truncation is necessary; never truncate by code-unit count.

## Safe responsive implementation rules

1. Prefer `LayoutBuilder` for component decisions and `MediaQuery.sizeOf` for screen-level decisions.
2. Never place `Expanded` / `Spacer` inside a scroll axis with unbounded constraints.
3. Avoid fixed page heights except bounded panels such as the queue.
4. Test width **and height** resize paths.
5. Keep business state outside responsive widgets; resizing must not recreate playback queues, metadata repositories, lyric state, or transcription jobs.
6. Responsive changes must not create separate desktop/mobile playback state.
7. Use `AppResponsive` / `AppLayoutSpec` instead of adding page-local breakpoint constants.

## Required manual viewport matrix

When a Flutter runtime is available, validate at least:

- 390×844 — phone portrait
- 844×390 — phone landscape / short height
- 768×1024 — tablet portrait
- 1024×768 — tablet landscape / small desktop
- 1366×768 — common laptop desktop
- 1600×900 — standard desktop
- 1920×1080 — full HD desktop
- 2560×1440 — large desktop

Also drag-resize continuously across 600, 840, 1080, 1200, and 1600 widths to verify there is no overflow, state reset, queue reset, or abrupt unusable composition.
