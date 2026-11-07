#!/usr/bin/env bash
set -euo pipefail

# deploy: point AddOns/RivQoL at this worktree (symlink, live edits).
# rc:     install a release candidate: the packaged build of this worktree's
#         commit, copied in as a real folder, exactly as CurseForge ships it.
# status: show what AddOns/RivQoL currently is.
command_name=${1:-deploy}
if (( $# > 1 )) || [[ $command_name != deploy && $command_name != rc && $command_name != status ]]; then
    echo "Usage: $0 [deploy|rc|status]" >&2
    exit 1
fi

# Same packager the release workflow uses (BigWigsMods/packager@v2). It tracks
# the moving v2 ref on purpose, so a candidate is built exactly as a release is.
packager_url=https://raw.githubusercontent.com/BigWigsMods/packager/v2/release.sh
# Marks an AddOns/RivQoL folder as a release candidate this script installed,
# so it may be replaced again. Any other real folder is left alone.
rc_marker=.rivqol-release-candidate

repo_root=$(git -C "$(dirname -- "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
addons_dir=$(git -C "$repo_root" config --local --path --get rivqol.addonsDir || true)
if [[ -z $addons_dir || $addons_dir != /* || ! -d $addons_dir ]]; then
    echo "rivqol.addonsDir must name an existing absolute AddOns directory." >&2
    echo 'Configure it with: git config --local rivqol.addonsDir "/absolute/path/to/Interface/AddOns"' >&2
    exit 1
fi
target="$addons_dir/RivQoL"

describe_target() {
    if [[ -L $target ]]; then
        local linked_path resolved branch
        linked_path=$(readlink -- "$target")
        if [[ ! -e $target ]]; then
            printf '%s -> %s (broken symlink)\n' "$target" "$linked_path"
            return
        fi
        resolved=$(realpath -- "$target")
        branch=$(git -C "$resolved" symbolic-ref --quiet --short HEAD 2>/dev/null ||
            git -C "$resolved" rev-parse --short HEAD 2>/dev/null || printf 'unknown')
        printf '%s -> %s (branch: %s)\n' "$target" "$resolved" "$branch"
    elif [[ -f $target/$rc_marker ]]; then
        printf '%s (release candidate: %s)\n' "$target" "$(tr '\n' ' ' <"$target/$rc_marker" | sed 's/ *$//')"
    elif [[ -e $target ]]; then
        printf '%s (not a symlink)\n' "$target"
    else
        printf '%s (not deployed)\n' "$target"
    fi
}

# Only a symlink, nothing, or a release candidate we installed may be replaced.
check_replaceable() {
    if [[ -e $target && ! -L $target && ! -f $target/$rc_marker ]]; then
        echo "Refusing to replace a real file or directory: $target" >&2
        exit 1
    fi
}

remove_target() {
    if [[ -L $target ]]; then
        rm -f -- "$target"
    elif [[ -d $target ]]; then
        rm -rf -- "$target"
    fi
}

if [[ $command_name == deploy ]]; then
    printf 'Before: '
    describe_target
    check_replaceable
    [[ -L $target ]] || remove_target
    ln -sfnT -- "$repo_root" "$target"
    printf 'After:  '
    describe_target
fi

if [[ $command_name == rc ]]; then
    printf 'Before: '
    describe_target
    check_replaceable
    if [[ -n $(git -C "$repo_root" status --porcelain) ]]; then
        echo "Worktree has uncommitted changes; commit or stash them first so the" >&2
        echo "release candidate matches a commit that can be tagged." >&2
        git -C "$repo_root" status --short >&2
        exit 1
    fi

    work=$(mktemp -d)
    staging="$addons_dir/.RivQoL.rc-staging"
    trap 'rm -rf -- "$work" "$staging"' EXIT

    echo "Downloading packager: $packager_url"
    curl -fsSL -o "$work/release.sh" "$packager_url"
    commit=$(git -C "$repo_root" rev-parse HEAD)
    echo "Packaging ${commit:0:7}..."
    # The packager needs a real .git directory (a worktree has a .git file), so
    # package a throwaway clone checked out at this exact commit, tags included.
    git clone -q --shared --no-checkout "$(git -C "$repo_root" rev-parse --path-format=absolute --git-common-dir)" "$work/src"
    git -C "$work/src" checkout -q --detach "$commit"
    # The packager builds CHANGELOG.md links from origin's URL; use the real one.
    if origin_url=$(git -C "$repo_root" remote get-url origin 2>/dev/null); then
        git -C "$work/src" remote set-url origin "$origin_url"
    fi
    # -d: no upload, -z: no zip; the package directory is all we need.
    if ! bash "$work/release.sh" -t "$work/src" -r "$work/out" -d -z >"$work/packager.log" 2>&1; then
        tail -n 40 "$work/packager.log" >&2
        echo "Packaging failed (log above)." >&2
        exit 1
    fi
    package="$work/out/RivQoL"
    if [[ ! -f $package/RivQoL.toc ]]; then
        echo "Packager did not produce $package/RivQoL.toc." >&2
        exit 1
    fi

    version=$(sed -n 's/^## Version: *//p' "$package/RivQoL.toc" | tr -d '\r')
    branch=$(git -C "$repo_root" symbolic-ref --quiet --short HEAD || echo detached)
    {
        printf 'version %s\n' "$version"
        printf 'commit %s\n' "${commit:0:7}"
        printf 'branch %s\n' "$branch"
        printf 'built %s\n' "$(date -Iseconds)"
    } >"$package/$rc_marker"

    rm -rf -- "$staging"
    cp -a -- "$package" "$staging"
    remove_target
    mv -T -- "$staging" "$target"
    printf 'After:  '
    describe_target
    echo "Packaged files:"
    (cd "$target" && find . -type f ! -name "$rc_marker" | sed 's|^\./|  |' | sort)
fi
if [[ $command_name == status ]]; then
    describe_target
fi
