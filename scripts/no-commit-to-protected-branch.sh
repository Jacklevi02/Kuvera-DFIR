#!/usr/bin/env bash
#
# pre-commit guard (T1.10): refuses commits made directly on main or dev. Every
# change goes through a feature branch and a pull request — see CONTRIBUTING.md.
#
# A detached HEAD has no branch to protect (rebases run in this state), so it
# passes.
#
set -euo pipefail

branch="$(git symbolic-ref --quiet --short HEAD || true)"

case "$branch" in
    main | dev)
        echo "Direct commits to '$branch' are not allowed. Create a feature branch:" >&2
        echo "  git switch -c <issue-number>-<ticket-id>-<component>-<slug>" >&2
        exit 1
        ;;
esac
