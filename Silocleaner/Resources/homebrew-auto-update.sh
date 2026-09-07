#!/bin/sh
# This is deliberately static shell source. The LaunchAgent supplies only the
# three fixed action flags below; it never contains a constructed command.
set -eu

log_file="/tmp/homebrew-autoupdate.log"
run_update=false
run_upgrade=false
run_cleanup=false

for action in "$@"; do
    case "$action" in
        --update) run_update=true ;;
        --upgrade) run_upgrade=true ;;
        --cleanup) run_cleanup=true ;;
        *) exit 64 ;;
    esac
done

{
    echo ""
    echo "================================"
    echo "Homebrew Auto-Update - $(date)"
    echo "================================"
    echo ""

    if "$run_update"; then
        echo "[ Updating Homebrew ]"
        brew update
        echo ""
    fi
    if "$run_upgrade"; then
        echo "[ Upgrading Packages ]"
        brew upgrade --greedy
        echo ""
    fi
    if "$run_cleanup"; then
        echo "[ Cleaning Up ]"
        brew autoremove
        brew cleanup --scrub --prune=all
        echo ""
    fi

    echo "================================"
    echo "Completed at $(date)"
    echo "================================"
} > "$log_file" 2>&1
