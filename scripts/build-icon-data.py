#!/usr/bin/env python3
"""Build Data/IconData.lua: a search index for the icon picker (Modules/IconSearch.lua).

For every icon file in the game (Interface\\Icons) it records the file name, the
names of the spells and items that use it, and tags: the classes whose
spells use it, the professions, and the item types. The game's Lua API has
none of this (icons are bare file IDs), so it comes from the client's own
data tables, as exported by wago.tools.

Usage: scripts/build-icon-data.py [build]   (default: the latest WoW Forever build)
Needs only the Python standard library and network access to wago.tools.
"""
import csv
import io
import json
import sys
import urllib.request
from collections import defaultdict
from pathlib import Path

PRODUCT = "wowf"
WAGO = "https://wago.tools"
OUT = Path(__file__).resolve().parent.parent / "Data" / "IconData.lua"

MAX_SPELL_NAMES = 8  # per icon: player spells first, then any other spell
MAX_ITEM_NAMES = 8
CATEGORY_CLASS = "7"
CATEGORY_SECONDARY = "9"
CATEGORY_PROFESSION = "11"
SECONDARY_PROFESSIONS = {"129", "185", "356"}  # First Aid, Cooking, Fishing


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "RivQoL-icon-data-builder"})
    with urllib.request.urlopen(req, timeout=120) as resp:
        return resp.read().decode("utf-8")


def table(name, build):
    text = fetch(f"{WAGO}/db2/{name}/csv?build={build}")
    return list(csv.DictReader(io.StringIO(text)))


def latest_build():
    builds = json.loads(fetch(f"{WAGO}/api/builds"))
    return builds[PRODUCT][0]["version"]


def junk_name(name):
    low = name.lower()
    return (not name or "[dnt]" in low or "(test)" in low or "(dnd)" in low or "[dnd]" in low
            or "(old)" in low or "deprecated" in low or low.startswith(("test ", "zz", "qa ")))


def lua_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    build = sys.argv[1] if len(sys.argv) > 1 else latest_build()
    print(f"build {build}")

    # Icon files: fileID -> file name without extension.
    icons = {}
    for r in table("ManifestInterfaceData", build):
        if r["FilePath"].lower() == "interface\\icons\\":
            icons[int(r["ID"])] = r["FileName"].rsplit(".", 1)[0]

    # Skill lines -> class / profession tags.
    classes = {int(r["ID"]): r["Name_lang"] for r in table("ChrClasses", build)}
    skill_lines = {r["ID"]: r for r in table("SkillLine", build)}
    skill_classes = defaultdict(set)
    for r in table("SkillRaceClassInfo", build):
        mask = int(r["ClassMask"])
        for cid in classes:
            if mask & (1 << (cid - 1)):
                skill_classes[r["SkillID"]].add(cid)

    def profession_of(skill_id):
        line = skill_lines.get(skill_id)
        if not line:
            return None
        parent = line["ParentSkillLineID"]
        if parent and parent != "0":
            return profession_of(parent) or None
        if "dnt" in line["DisplayName_lang"].lower():
            return None
        if line["CategoryID"] == CATEGORY_PROFESSION or skill_id in SECONDARY_PROFESSIONS:
            return int(skill_id)
        return None

    professions = {}
    spell_tags = defaultdict(set)
    player_spells = set()
    for r in table("SkillLineAbility", build):
        spell, skill = r["Spell"], r["SkillLine"]
        line = skill_lines.get(skill)
        if not line:
            continue
        if line["CategoryID"] == CATEGORY_CLASS:
            mask = int(r["ClassMask"] or 0)
            owners = {cid for cid in classes if mask & (1 << (cid - 1))} or skill_classes.get(skill, set())
            if len(owners) == len(classes):
                owners = set()   # shared by every class (mounts, companions): not a class spell
            for cid in owners:
                spell_tags[spell].add(f"c{cid}")
            if owners:
                player_spells.add(spell)
        prof = profession_of(skill)
        if prof:
            professions[prof] = skill_lines[str(prof)]["DisplayName_lang"]
            spell_tags[spell].add(f"p{prof}")
            player_spells.add(spell)

    # Spells: icon -> names (player spells first) and tags.
    spell_names = {r["ID"]: r["Name_lang"] for r in table("SpellName", build)}
    icon_spells = defaultdict(list)   # fileID -> [(priority, name)]
    icon_tags = defaultdict(set)
    for r in table("SpellMisc", build):
        icon = int(r["SpellIconFileDataID"] or 0)
        spell = r["SpellID"]
        if icon not in icons:
            continue
        icon_tags[icon] |= spell_tags.get(spell, set())
        name = spell_names.get(spell, "")
        if not junk_name(name):
            icon_spells[icon].append((0 if spell in player_spells else 1, name))

    # Items: icon -> names and item type tags.
    item_names = {r["ID"]: r["Display_lang"] for r in table("ItemSparse", build)}
    item_classes = {r["ClassID"]: r["ClassName_lang"] for r in table("ItemClass", build)}
    item_subclasses = {}
    for r in table("ItemSubClass", build):
        if "obsolete" not in r["DisplayName_lang"].lower():
            item_subclasses[(r["ClassID"], r["SubClassID"])] = r["VerboseName_lang"] or r["DisplayName_lang"]
    icon_items = defaultdict(list)
    used_types = set()
    for r in table("Item", build):
        icon = int(r["IconFileDataID"] or 0)
        if icon not in icons:
            continue
        name = item_names.get(r["ID"], "")
        if not name or junk_name(name):
            continue   # items without client data are mostly unused placeholders
        key = (r["ClassID"], r["SubclassID"])
        if r["ClassID"] in item_classes and key in item_subclasses:
            icon_tags[icon].add(f"i{key[0]}_{key[1]}")
            used_types.add(key)
        icon_items[icon].append(name)

    def top_names(entries, limit):
        seen, out = set(), []
        for name in entries:
            if name.lower() not in seen:
                seen.add(name.lower())
                out.append(name)
                if len(out) == limit:
                    break
        return out

    lines = []
    for icon in sorted(icons):
        spells = top_names([n for _, n in sorted(icon_spells.get(icon, []), key=lambda e: e[0])], MAX_SPELL_NAMES)
        items = top_names(icon_items.get(icon, []), MAX_ITEM_NAMES)
        tags = ",".join(sorted(icon_tags.get(icon, set())))
        for part in (icons[icon], tags, *spells, *items):
            assert "|" not in part and "\n" not in part and "]]" not in part, part
        lines.append("|".join([str(icon), icons[icon], tags, ";".join(spells), ";".join(items)]))

    out = []
    out.append("-- Generated by scripts/build-icon-data.py from the client's data tables (via wago.tools).")
    out.append("-- Do not edit by hand: run the script again after a game patch.")
    out.append("local _, ns = ...")
    out.append("ns.IconData = {")
    out.append(f"    build = {lua_string(build)},")
    out.append("    classes = {")
    for cid in sorted(classes):
        out.append(f"        [{cid}] = {lua_string(classes[cid])},")
    out.append("    },")
    out.append("    professions = {")
    for pid in sorted(professions, key=lambda p: professions[p]):
        out.append(f"        {{ {pid}, {lua_string(professions[pid])} }},")
    out.append("    },")
    out.append("    itemClasses = {")
    for cid in sorted(item_classes, key=int):
        subs = sorted((s for c, s in used_types if c == cid), key=int)
        if not subs:
            continue
        sub_text = ", ".join(f"{{ {s}, {lua_string(item_subclasses[(cid, s)])} }}" for s in subs)
        out.append(f"        {{ {cid}, {lua_string(item_classes[cid])}, {{ {sub_text} }} }},")
    out.append("    },")
    out.append("    -- fileID|file name|tags|spell names;...|item names;...")
    out.append("    icons = [[")
    out.extend(lines)
    out.append("]],")
    out.append("}")
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text("\n".join(out) + "\n", encoding="utf-8")
    print(f"wrote {OUT} ({len(lines)} icons, {OUT.stat().st_size // 1024} KiB)")


if __name__ == "__main__":
    main()
