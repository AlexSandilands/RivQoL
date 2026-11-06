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
