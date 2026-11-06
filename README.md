# RivQoL

Riv's personal quality-of-life addon for WoW Forever (interface 16001).

## Install (dev)

The game loads this folder through a symlink, so edits here are live after `/reload`:

```
ln -s ~/Projects/RivQoL "/mnt/linux-games/Blizzard/World of Warcraft/_forever_/Interface/AddOns/RivQoL"
```

A brand-new addon folder is only picked up after a full game restart; after that, `/reload` is enough.
Changes to the `.toc` (new files) also need a restart.

## Commands

- `/rivqol` or `/rq`: open the options window (also under Esc > Options > AddOns > RivQoL)
- `/rivqol list`: list modules and whether they are on, in chat
- `/rivqol toggle <module>`: turn a module on/off (saved per account)

## Options window

A module list on the left (checkbox = on/off) and the selected module's page on the right.
It uses stock Blizzard templates, so it looks native with no other addons. With EllesmereUI
installed it is themed through EUI's Skinning API and follows the EUI theme live; turn that off
per addon in EUI options under Blizzard Skins+ > Window Skins > Third-Party Addons.

## Modules

| Module | What it does |
|---|---|
| `friendlynames` | Keeps floating friendly player names off (`UnitNameFriendlyPlayerName 0`). EllesmereUI Nameplates forces it on at every load while its friendly player nameplates are enabled. |
| `lootfilter` | Off by default. When auto-looting, leaves junk on the corpse instead of picking it up: items on its skip list, or items matching a rule (type/subtype, max quality, max vendor price). Nothing is deleted and your bags are never touched. |

### Loot filter

- **Turn it on** in the options window (`/rq` > Loot Filter). While it is on it does the auto-looting
  itself: it sets the game's `autoLootDefault` CVar to 0 and uses its own Auto-loot toggle, seeded
  from the game's setting. It hands the CVar back (as the toggle has it) when turned off and at every
  logout, so disabling or removing the addon never leaves auto-loot off. The auto-loot key
  (Interface > Controls) still inverts it, and ticking the game's own Auto Loot box while the module
  is on just turns its toggle on.
- **Filters only apply when auto-looting.** When you loot by hand (auto-loot off, or the key held),
  the loot window is yours as usual.
- **Always skip / Never skip lists**: drag an item from your bags onto the slot, or Alt-click it in
  your bags while the page is open. An item is on at most one list.
- **Rules**: an item is skipped when all set conditions of any rule match. A max sell price of 0
  means any price, and a rule with no conditions does nothing.
- **Always looted**: coins and currencies; anything on the never-skip list; and, unless it is on the
  skip list, quest items, Rare or better items, items whose info isn't cached yet, and (for rules
  with a price limit) items with no vendor price.
- When only skipped items are left, the loot window closes and they stay on the corpse. "Announce"
  prints each one in chat.

## Adding a module

Create `Modules/<Name>.lua`, add it to `RivQoL.toc`, and register it:

```lua
local _, ns = ...
local M = {
    name = "mymodule",           -- slash/saved-variables key
    title = "My Module",         -- shown in the options window
    description = "...",
    defaults = { enabled = true, threshold = 5 },
}
function M:OnEnable(db)  --[[ at PLAYER_LOGIN, and when turned on later: keep it idempotent ]] end
function M:OnDisable(db) --[[ optional: when turned off in-session ]] end

-- Optional: extra settings on the module's page. Title, description and the
-- Enabled toggle are already there; start at `y` and return the final y.
function M:BuildOptions(page, db, y)
    local W = ns.Widgets
    local _
    _, y = W.SectionHeader(page, y, "Rules")
    _, y = W.Slider(page, y, { label = "Threshold", min = 1, max = 20, db = db, key = "threshold" })
    return y
end
ns.RegisterModule(M)
```

A page whose content changes size after it is built (a list you add to) can lay its widgets out
again and call `page:SetPageHeight(-y)` so the page scrolls to fit (see `Modules/LootFilter.lua`).

Turn modules on/off with `ns.SetModuleEnabled(name, on)` (never set `db.enabled` directly), and
listen for changes with `ns.RegisterCallback(function(module, key) ... end)`.

### Widgets (`UI/Widgets.lua`)

Each is `widget, nextY = W.X(parent, y, opts)` and lays out top-down. Value widgets take
`db` + `key` (changes fire the settings callback) or `get` / `set`, and accept `label`, `tooltip`, `x`.

| Widget | Extra opts |
|---|---|
| `SectionHeader(parent, y, text)` | |
| `Text(parent, y, text, opts)` | `font`, `width` |
| `Checkbox` | `onChange(v)` |
| `Button` | `text`, `width`, `onClick` |
| `Slider` | `min`, `max`, `step`, `format(v)`, `width` |
| `MoneyInput` | value is copper |
| `Dropdown` | `choices = {{value=, text=}, ...}` or a function returning them, `width` |
| `ItemDropSlot` | `onItem(itemID, link)`, `size`; `slot:SetItem(itemID)` |

Frames you build yourself can be themed with `ns.Skin(kind, frame, ...)`, where `kind` is an
EllesmereUI skin primitive (`"Button"`, `"Checkbox"`, `"EditBox"`, ...); it does nothing without EUI.

New files must be added to `RivQoL.toc`, which needs a full game restart.
