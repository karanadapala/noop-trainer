#!/usr/bin/env bash
#
# NOOP Trainer: merge the latest upstream NOOP (ryanbr/noop main) into a review branch and open a
# pull request against this fork's main, so incoming upstream changes are read before they ship.
#
# Usage: Tools/trainer-sync-upstream.sh
# Expected conflict: project.yml MARKETING_VERSION / CURRENT_PROJECT_VERSION. Keep the Trainer's
# version, and take a build number above both sides.

set -euo pipefail

git remote get-url upstream >/dev/null 2>&1 || git remote add upstream https://github.com/ryanbr/noop.git
git fetch upstream main
git fetch origin main

BRANCH="sync/upstream-$(date +%Y-%m-%d)"
git switch -c "$BRANCH" origin/main
if ! git merge --no-edit upstream/main; then
  echo
  echo "Merge conflicts. Resolve them, then: git commit && git push -u origin $BRANCH && gh pr create --fill"
  exit 1
fi
git push -u origin "$BRANCH"
gh pr create --repo "$(gh repo view --json nameWithOwner -q .nameWithOwner)" --base main --head "$BRANCH" \
  --title "Merge upstream NOOP ($(date +%Y-%m-%d))" \
  --body "Merges ryanbr/noop main into NOOP Trainer. Review the upstream changes, build NOOPiOS, then merge."
