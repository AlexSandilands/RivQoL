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

A list on the left and the selected page on the right. **General** holds the small tweaks, each
with its own on/off checkbox and options; bigger modules (Loot Filter) get their own entry, with
an on/off checkbox in the list.
Drag the window by its title bar and resize it from the bottom-right corner; size and position are
saved.
It has its own look (`UI/Theme.lua`): warm dark panels, thin bronze borders that turn gold on
hover, Morpheus headers. It doesn't depend on, or get re-skinned by, other UI addons.

## Modules

| Module | What it does |
|---|---|
| `friendlynames` | On the General page. Keeps floating friendly player names off (`UnitNameFriendlyPlayerName 0`). EllesmereUI Nameplates forces it on at every load while its friendly player nameplates are enabled. |
| `iteminfo` | On the General page. Hold Alt while hovering an item to add its type, subtype, slot, item level and stack size to the tooltip (handy for Loot Filter rules). Options: show always instead of only with Alt, show IDs. |
| `iconsearch` | On the General page. Adds a search box and a category filter to the icon pickers (new/edit macro, equipment set, guild bank tab). See below. |
| `groupzone` | On the General page. Shows where players are in the Group Browser (Looking For Group > Browse): the leader's location on each listing and every player's in its tooltip, with the subzone from /who on a click. See below. |
| `lootfilter` | Off by default. When auto-looting, leaves junk on the corpse instead of picking it up: items on its skip list, or items matching a rule (type/subtype, max quality, max vendor price). Nothing is deleted and your bags are never touched. |

### Loot filter

- **Turn it on** in the options window (`/rq` > Loot Filter). While it is on it does the auto-looting
  itself: it sets the game's `autoLootDefault` CVar to 0 and uses its own Auto-loot toggle, seeded
  from the game's setting. It hands the CVar back (as the toggle has it) when turned off and at every
  logout, so disabling or removing the addon never leaves auto-loot off. Ticking the game's own
  Auto Loot box while the module is on just turns its toggle on.
- **Looks like the game's auto-loot**: it waits for the loot window to open, then takes one slot at a
  time at the game's auto-loot pace (`autoLootRate`, 150 ms if that is 0 or missing), so the window and
  its animations play as usual.
- **The auto-loot key** (Interface > Controls) still inverts auto-loot. With the CVar at 0 the game
  would loot everything itself while that key is held, so the module also sets the key's binding to
  NONE for the session and checks the key itself. That change is never saved: if the key bindings are
  saved meanwhile, the real key is written back, and picking a new key there (Shift, Ctrl or Alt) is
  adopted. Interface > Controls shows the key as None meanwhile; to really set it to None, turn the
  module off first.
- **Filters only apply when auto-looting.** When you loot by hand (auto-loot off, or the key held),
  the loot window is yours as usual.
- **Always skip / Never skip lists**: drag an item from your bags onto the slot, or Alt-click it in
  your bags while the page is open. An item is on at most one list.
- **Rules**: an item is skipped when all set conditions of any rule match. A max sell price of 0
  means any price, and a rule with no conditions does nothing. Click a rule's name to rename it
  (clear it to go back to "Rule N"); the chat line says which rule, or the skip list, left an item.
- **Tooltip text** in a rule: "Tooltip contains" matches items whose tooltip has that text, and
  "...but doesn't contain" leaves out items that have it. Both are case-insensitive, ignore numbers
  ("restores health" matches "Restores 61 Health over 18 sec.") and take comma-separated alternatives.
  Food but not water: type Consumable, contains `restores health`, doesn't contain `mana` (the last
  part also keeps mixed food-and-drink items). "Doesn't contain" alone doesn't make a rule active, and
  an item whose tooltip hasn't loaded yet is looted.
- **Always looted**: coins and currencies; anything on the never-skip list; and, unless it is on the
  skip list, quest items, Rare or better items, items whose info isn't cached yet, and (for rules
  with a price limit) items with no vendor price.
- **Highlight matching items in your bags** (Loot Filter page): with Baganator, items the filter
  would leave behind glow like a proc'd action button, so you can check your lists and rules.
  It's a Baganator icon-corner widget ("RivQoL: Loot Filter match", top left by default) that you can
  move or remove in Baganator's icon settings. The default and other bag UIs aren't supported.
- When only skipped items are left, the loot window closes after a short pause and they stay on the
  corpse. "Announce" prints each one in chat.

### Icon search

- **Search box**: matches every word you type (in any order, case-insensitive) against the icon's file
  name (`Spell_Fire_FlameBolt`), the spells and items that use it, the classes and professions
  whose spells use it, and its item types. "fireball", "two-handed swords", "wolf mount" and
  "frost mage" all work, and so does a file ID. Spells in your spellbook are always searchable by name.
- **Category dropdown**: My spells (your spellbook), My class, any class, profession, or item type
  (Weapon > One-Handed Swords...). It combines with the search and with Blizzard's own All/Spell/Item filter.
- **Hover an icon** to see its file name and what uses it (turn off with "Show icon details on hover").
- The filter is cleared each time the picker closes. While a filter is set, the picker's grid shows
  the module's own list of matching icons; Blizzard's icon list is never changed, and picking and
  saving still go through Blizzard's code.
- The names come from `Data/IconData.lua` (about 1.5 MB, parsed the first time you search or hover an icon). The game
  has no API for icon names, so `scripts/build-icon-data.py` builds it from the client's data tables
  as exported by [wago.tools](https://wago.tools). Run it again after a game patch adds icons:
  `scripts/build-icon-data.py` (latest WoW Forever build) or `scripts/build-icon-data.py 1.60.1.70790`.

### Group Browser zones

- **Where it shows**: on each listing, right-aligned on its bottom line (the leader's location), and
  in the listing's tooltip after each player.
- **The zone** comes with the listing (`areaName` in `C_LFGList.GetSearchResultPlayerInfo`), so it
  shows straight away for everyone.
- **A more specific place** comes from /who. When it names somewhere other than the zone (usually the
  subzone), both show: "Goldshire (Elwynn Forest)". The game only lets addons send a /who from a click,
  so this can't run in the background:
  - Left-clicking a listing looks up its leader, unless that was done in the last 5 minutes.
  - The magnifier at the right of a hovered listing looks up the next player of that listing not
    looked up recently (leader first, then each member, one per click), or the leader again.
  - One lookup at a time, at most one every 5 seconds (the server limits /who). The tooltip says how
    old a result is ("3m ago") or "looking up...", and the magnifier's tooltip says what the last
    lookup found (or that the server didn't answer).
- **Quiet**: its /who answers stay out of chat, and the Who lists don't redraw for them. The game keeps
  only the last /who result, though, so a Who list redrawn later (scrolling, reopening) shows the
  module's last lookup instead of your search. A /who you send yourself always wins: the module's
  pending lookup is dropped and yours shows as usual.
- **Show zone on listings** (option): turn the label on listings off and keep only the tooltip.
  Labels copy the font of the listing's own text, so they match EllesmereUI's skin.

## Adding a module

Create `Modules/<Name>.lua`, add it to `RivQoL.toc`, and register it:

```lua
local _, ns = ...
local M = {
    name = "mymodule",           -- slash/saved-variables key
    title = "My Module",         -- shown in the options window
    group = "general",           -- optional: list it on the General page instead of its own
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
| `Button` | `text`, `width`, `onClick`, `variant` ("danger") |
| `Slider` | `min`, `max`, `step`, `format(v)`, `width` |
| `MoneyInput` | value is copper |
| `TextInput` | `width`, `maxLetters`; saved on Enter / focus loss |
| `Dropdown` | `choices = {{value=, text=}, ...}` or a function returning them, `width` |
| `ItemDropSlot` | `onItem(itemID, link)`, `size`; `slot:SetItem(itemID)` |

Controls you build yourself should come from `ns.Theme` so they match: `T.Button(parent, text, w, h, variant)`
(`"danger"` for destructive actions), `T.Checkbox`, `T.EditBox` (hook, don't set, its focus scripts),
`T.Slot`, `T.FontString(parent, "body" | "small" | "header" ...)`, `T.Backdrop`, `T.Rule`, and the
palette in `T.colors`.

New files must be added to `RivQoL.toc`, which needs a full game restart.
