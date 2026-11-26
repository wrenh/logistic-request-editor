# Logistic Request Editor

Logistic Request Editor adds a compact panel for editing
**item selections within one or more logistics requests**. Set amounts,
sort items, adjust quality, and manage platform imports at scale with fewer clicks.

> **Requires Factorio 2.1 and Space Age.**

> This mod only provides quality of life UX additions. There are no changes to
> gameplay.

---

## What can it do?

- **Edit whole sections together.** Switch between Single and Multiple
  selection of logistic requests.
- **Set amounts in items or stacks.** Adjust item counts on a per-item or
  per-stack basis.
- **Balance requests to fit an inventory.** Distribute container capacity evenly
  between item selectiosn while allowing for reserved slots and
  unselected requests. Balance to the closest whole stack or whole item. Stacks mode gives
  each type an equal whole-stack allocation; Items mode gives each an equal whole-item target
  that fits, allowing partial stacks.
- **Sort requests** Apply Factorio's default item ordering, or sort by
  item names, requested amounts, quality, or other properties. Choose a primary
  priority and an optional secondary tie-breaker, each with an up/down direction
  toggle. Default as the primary priority hides the secondary controls.
  Optionally clear empty gaps between items.
- **Filter by quality.** Apply quality filters across items and requests.
- **Manage platform logistics.** Change the import planet, choose Planet /
  Platforms / All, and set a custom minimum delivery payload in items or stacks.
- **Undo** Made a mistake? Undo the prior change.
- **Adjust defaults** Most constants are adjustable in settings > mod seetings > per player.
- **Adjustable panel location** supports minimizing, various docked locations, and
  floating (with optional lock). Hide or show the pane with the shortcut-bar launcher.

## Where does it work?

- **Space-platform hubs**
- **Personal logistics**, once requester logistics is unlocked
- **Requester and buffer chests**
- **Spidertrons**
- **Tanks and other vehicles with an existing requester point**
- **Cargo landing pads**

Import filters and minimum payload editing are platform-only. The mod does not
add logistics to unsupported inventories.

## Getting started

1. **Open a supported inventory.** The editor opens beside it by default.
2. **Choose your sections.** Use Single or select the sections you want in Multiple.
3. **Choose what to change.** Enable only the categories you need and review their
   proposed values.
4. **Click Apply.** If needed, use Undo to restore the previous batch.

The request list will update automatically as you edit requests in the game UI.

## Notes

- **Named groups remain shared.** Editing a named group updates its other linked
  uses too, just like the normal game UI.
- **Undo keeps one batch, not a history.** A successful Apply replaces the previous
  snapshot. Closing the editor or its inventory discards Undo.
- **Quality ranges require Requested = 0.** The default "Set to 0 policy" handles
  this automatically when relevant amount or quality edits affect a range.
  Choose "Prevent" in player options if you prefer the entire batch to be refused.

## Feedback

I hope you find this useful. If you find a bug, report it here, and I will try to address it.
I would like to avoid new dependencies, but I an open to feature requests which avoid gameplay
changes, I just want to save some unnecessary clicking.

I did not do any specific mod compatibility testing, but this seems to work fine with
the ~50 mods I have installed.
