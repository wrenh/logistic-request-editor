# Mod Portal assets and publishing

Working copy for preparing the public listing. Nothing here publishes or uploads
the mod automatically.

## Listing copy

### Suggested short summary

> Bulk-edit, sort and balance logistic requests across personal logistics,
> requester inventories and space platforms. Adjust amounts, quality and imports
> in a compact editor with Undo.

The portal's short summary allows up to **500 characters**. Keep the
[description in the manifest](../info.json) consistent with the final summary
once the wording is approved.

### Full description

[MOD_PORTAL.md](../MOD_PORTAL.md) is the player-facing long-description draft.
Copy its Markdown into the portal's description field and check the preview
before saving.

The [README](../README.md) contains the detailed usage guide. It also uses an
HTML `<details>` section for the developer reference; that treatment is intended
for GitHub and Markdown preview, not copied into the portal draft.

### Suggested classification

| Field | Suggestion |
| --- | --- |
| Display name | Logistic Request Editor |
| Category | Utilities |
| Tags | Logistics, Logistic network, Storage |
| Requirement | Factorio 2.1 with Space Age |

Keep the existing internal mod identifier unless planning a separate rename.
Choose an explicit license before publishing; these drafts do not choose one.

## Formatting approach

- The portal documents support for a **Markdown** long description.
- The portal draft uses headings, bold text, bullet lists, numbered steps,
  blockquotes, and horizontal rules.
- Raw HTML support is not established by the linked portal documentation, so
  the draft does not depend on HTML, custom CSS, collapsible panels, or badges.
- The [README gallery](../README.md#screenshots) links to clearly marked
  placeholder PNGs in the [screenshots folder](screenshots/). Overwrite those
  files with real in-game captures using the same names; the gallery updates
  without changing its Markdown.
- The portal draft still omits inline screenshots until final hosted URLs are
  available. Do not publish the placeholder images.
- Gallery images are managed separately from the description. If adding inline
  screenshots, use their final hosted image URLs and confirm them in the preview.
  Local disk paths will not work for other players.

## Screenshot checklist

The first three subjects are the most useful for showing what makes the mod
worth installing. Others can be added if they remain clear at gallery size.

| Priority | Subject | Capture | Suggested caption |
| --- | --- | --- | --- |
| 1 | [Main overview](screenshots/platform-overview.png) | A platform's request sections beside the editor, with Multiple selection and several checked sections. | Edit multiple request sections from one compact panel. |
| 2 | [Balance requests](screenshots/chest-balance.png) | Select Stacks in a normal unrestricted 48-slot requester chest with four unique item types, no reserved slots or outside requests, and active sections with multiplier 1. Capture the allocation and the result after Apply. An optional Items-mode comparison can show equal item counts with mixed stack sizes. | Balance by equal stacks or equal item counts. |
| 3 | Sorting [before](screenshots/sorting-before.png) and [after](screenshots/sorting-after.png) | The same request section with mixed item order and gaps, then sorted with Clear empty slots enabled. An additional example can use Quality descending, then Name ascending, showing the two direction arrows. Uncheck other edit categories to keep the comparison focused on sorting. | Sort by two priorities and remove empty gaps. |
| 4 | [Platform controls](screenshots/platform-controls.png) | Import planet/source controls and minimum payload editing, with readable values and no error message. | Set import rules and minimum payloads across selected platform requests. |
| 5 | [Quality controls](screenshots/quality-controls.png) | An unlocked exact quality selected in Edit quality. Keep other categories off if demonstrating a quality-only edit. | Apply quality conditions to a whole selection. |
| 6 | [Floating panel](screenshots/floating-panel.png) and [minimized panel](screenshots/minimized-panel.png) | An unlocked floating panel and a separate capture of the minimized icon. | Dock, float, minimize, or hide the editor to suit your layout. |
| 7 | [Player options](screenshots/player-options.png) | The current per-player settings, including Enabled / Disabled / Hidden choices. | Choose your own default edit categories and quantities. |

### Capture tips

- Use the current mod version so screenshots match the described controls and defaults.
- Keep the inventory and editor visible together for the overview.
- Use a consistent GUI scale with comfortably readable labels.
- Move the pointer off controls and wait for tooltips to disappear.
- Clear unrelated chat, alerts, and error messages where practical.
- Keep original PNG captures; crop copies later rather than discarding the originals.
- Avoid exposing personal information or private server details.
- Show real requests and results, without implying that changes happen before Apply.

The portal's official image API documentation does not specify screenshot size,
format, or count limits. Check the upload form for its current requirements
rather than treating the suggestions above as hard limits.

## Thumbnail

The mod browser and portal use a `thumbnail.png` in the mod package.
Factorio recommends **144 x 144 pixels**. This is separate from the screenshot
gallery and should remain recognizable at a small size.

[thumbnail.png](../thumbnail.png) now contains the requester-chest icon with a
green check mark overlapping in the foreground on a grey background. It uses
the game's original icon artwork, with the combined icons filling about 80%
of the square's width.

The in-game launcher uses [32px](../graphics/editor-icon.png) and
[24px](../graphics/editor-icon-small.png) copies of this thumbnail. The 24px
variant is also used by the minimize and restore buttons, without increasing
their existing sizes. Regenerate these variants if the main thumbnail is changed.

## Before publication

- [ ] Approve the short summary and long description.
- [ ] Replace the placeholder images with real captures.
- [ ] Add the selected screenshots to the gallery and review their order.
- [x] Add a thumbnail.
- [ ] Review the thumbnail at catalog size.
- [ ] Verify image links and formatting in the actual portal preview.
- [ ] Choose the license and any public support/source links.
- [ ] Confirm the displayed requirements, defaults, and version.
- [ ] Review the release package and add a correctly formatted changelog.

## Official references

- [Mod details API: summary, Markdown description, categories, tags and license](https://wiki.factorio.com/Mod_details_API)
- [Mod images API: gallery image management](https://wiki.factorio.com/Mod_images_API)
- [Mod structure: manifest, thumbnail and changelog](https://lua-api.factorio.com/latest/auxiliary/mod-structure.html)
