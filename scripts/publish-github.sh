#!/usr/bin/env bash
# Create (or update) the public GitHub repo and push this tree.
#
# Prerequisites:
#   gh auth login
#   # or: export GH_TOKEN=ghp_...
#
# Usage:
#   ./scripts/publish-github.sh [owner/repo]
# Default repo name: grok-build-multi-vendor under the authenticated user.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

REPO_SLUG="${1:-}"
if [[ -z "$REPO_SLUG" ]]; then
  if ! command -v gh >/dev/null; then
    echo "gh not installed" >&2
    exit 1
  fi
  USER="$(gh api user -q .login)"
  REPO_SLUG="${USER}/grok-build-multi-vendor"
fi

echo "Target: https://github.com/${REPO_SLUG}"

if ! gh auth status >/dev/null 2>&1; then
  echo "Not logged in. Run:  gh auth login" >&2
  echo "Or set GH_TOKEN / GITHUB_TOKEN." >&2
  exit 1
fi

# Ensure we don't push secrets (real key files / env dumps — not source named *api_key*)
if git ls-files | grep -qiE 'together_api_key\.txt$|(^|/)\.env(\.|$)|secrets?/|credentials\.json$'; then
  echo "Refusing to publish: secret-like paths are tracked" >&2
  git ls-files | grep -iE 'together_api_key\.txt$|(^|/)\.env(\.|$)|secrets?/|credentials\.json$' >&2
  exit 1
fi

if gh repo view "$REPO_SLUG" >/dev/null 2>&1; then
  echo "Repo exists — setting remote and pushing"
else
  gh repo create "$REPO_SLUG" --public --description "Grok Build multi-vendor fork (Together.ai api_key_file, install.sh)" --source=. --remote=origin 2>/dev/null \
    || gh repo create "$REPO_SLUG" --public --description "Grok Build multi-vendor fork (Together.ai api_key_file, install.sh)"
fi

# Remotes
if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "https://github.com/${REPO_SLUG}.git"
else
  git remote add origin "https://github.com/${REPO_SLUG}.git"
fi
# Keep upstream pointer if missing
if ! git remote get-url upstream >/dev/null 2>&1; then
  git remote add upstream https://github.com/xai-org/grok-build.git || true
fi

git push -u origin HEAD:main
echo "Published: https://github.com/${REPO_SLUG}"
echo "Optional release zip:"
echo "  ./scripts/make-source-zip.sh && gh release create v0.1.0 dist/*.zip -t 'Source install' -n 'Unzip and run ./install.sh'"
