#!/usr/bin/env bash
set -euo pipefail

command_name=${1:-deploy}
if (( $# > 1 )) || [[ $command_name != deploy && $command_name != status ]]; then
    echo "Usage: $0 [deploy|status]" >&2
    exit 1
fi

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
    elif [[ -e $target ]]; then
        printf '%s (not a symlink)\n' "$target"
    else
        printf '%s (not deployed)\n' "$target"
    fi
}

if [[ $command_name == deploy ]]; then
    printf 'Before: '
    describe_target
    if [[ -e $target && ! -L $target ]]; then
        echo "Refusing to replace a real file or directory: $target" >&2
        exit 1
    fi
    ln -sfnT -- "$repo_root" "$target"
    printf 'After:  '
    describe_target
fi
if [[ $command_name == status ]]; then
    describe_target
fi
