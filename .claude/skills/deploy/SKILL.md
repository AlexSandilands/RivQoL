---
name: deploy
description: Deploy RivQoL to the local World of Warcraft game folder, install it into AddOns, or make the current worktree available for testing in game.
---

# Deploy RivQoL

The game loads this worktree through an AddOns/RivQoL symlink. Deploying
repoints that link, so subsequent edits in this worktree are immediately available
to the game.

Run `./scripts/deploy.sh` from the current worktree's root. It defaults to
`deploy`; use `./scripts/deploy.sh status` to inspect the current link without
changing it.

The script reads `rivqol.addonsDir` from local Git config, shared by this
repository's worktrees and never committed. If unset, ask the user for the
absolute game `Interface/AddOns` path rather than guessing. Configure it with:

```bash
git config --local rivqol.addonsDir "/absolute/path/to/Interface/AddOns"
```

Then retry deployment. If the configured directory is missing, have the user
confirm the path or mount the game drive before retrying. In an unattended run,
record the missing information as a blocker instead of guessing.

The script replaces existing symlinks (including broken ones), but refuses to
replace a real file or directory. If it refuses, report the conflict and stop;
do not delete or move the existing installation without the user's direction.

Report the script's before/after output, including the worktree path and branch.
Deployment selects this worktree for the game; it does not build or copy files.

Tell the user to run `/reload` in game to pick up changes. A newly installed addon
folder or changes to `RivQoL.toc` require a full game restart.
