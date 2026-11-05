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

- `/rivqol` or `/rq`: list modules and whether they are on
- `/rivqol toggle <module>`: turn a module on/off (saved per account)

## Modules

| Module | What it does |
|---|---|
| `friendlynames` | Keeps floating friendly player names off (`UnitNameFriendlyPlayerName 0`). EllesmereUI Nameplates forces it on at every load while its friendly player nameplates are enabled. |

## Adding a module

Create `Modules/<Name>.lua`, add it to `RivQoL.toc`, and register it:

```lua
local _, ns = ...
local M = { name = "mymodule", description = "...", defaults = { enabled = true } }
function M:OnEnable(db) --[[ runs at PLAYER_LOGIN ]] end
ns.RegisterModule(M)
```
