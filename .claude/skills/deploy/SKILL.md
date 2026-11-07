---
name: deploy
description: Deploy RivQoL to the local World of Warcraft game folder, install it into AddOns, or make the current worktree available for testing in game. Also installs a release candidate (the packaged build, as CurseForge ships it) when the user is about to release, asks for a "release candidate"/"RC", or wants to test the real release build, and switches back to the dev symlink afterwards.
---

# Deploy RivQoL

The game loads this worktree through an AddOns/RivQoL symlink. Deploying
repoints that link, so subsequent edits in this worktree are immediately available
to the game.

Run `./scripts/deploy.sh` from the current worktree's root. It defaults to
`deploy`; use `./scripts/deploy.sh status` to inspect the current link without
changing it.

## Release candidate

When the user is about to release, or asks for a release candidate, RC, or the
"real"/packaged build, run `./scripts/deploy.sh rc` instead. It packages this
worktree's current commit with the same BigWigs packager the release workflow
uses (`.pkgmeta` exclusions, `@project-version@` replaced, `CHANGELOG.md`
generated), then installs that package as a real `AddOns/RivQoL` folder in place
of the symlink. Edits to the worktree no longer reach the game until it is
switched back.

- It refuses if the worktree has uncommitted changes, so the candidate matches a
  commit that can be tagged. Report the listed changes and ask the user whether
  to commit them; don't commit or stash on your own.
- Before tagging, the version shows as a commit hash, which is expected.
- Report the before/after lines and the packaged file list, and point out any file
  that looks out of place or missing.
- Tell the user to fully restart the game to test it, as a fresh install would.
- Once they're done testing (released, or found a problem to fix), run
  `./scripts/deploy.sh` to put the dev symlink back. It replaces the release
  candidate. Mention this when installing a candidate so it isn't forgotten.

The candidate folder holds a `.rivqol-release-candidate` marker, which is how
the script knows it may replace it. `status` shows the candidate's version,
commit and build time.

Don't install RivQoL through the CurseForge app on this machine. It would
replace the `RivQoL` folder and could write through the symlink into the
repository.

The script reads `rivqol.addonsDir` from local Git config, shared by this
repository's worktrees and never committed. If unset, ask the user for the
absolute game `Interface/AddOns` path rather than guessing. Configure it with:

```bash
git config --local rivqol.addonsDir "/absolute/path/to/Interface/AddOns"
```

Then retry deployment. If the configured directory is missing, have the user
confirm the path or mount the game drive before retrying. In an unattended run,
record the missing information as a blocker instead of guessing.

The script replaces existing symlinks (including broken ones) and release
candidates it installed, but refuses to replace any other real file or directory. If it refuses, report the conflict and stop;
do not delete or move the existing installation without the user's direction.

Report the script's before/after output, including the worktree path and branch.
Deployment selects this worktree for the game; it does not build or copy files.

Tell the user to run `/reload` in game to pick up changes. A newly installed addon
folder or changes to `RivQoL.toc` require a full game restart.
