#!/usr/bin/env bash
set -euo pipefail

# promote.sh — TUI to produce patches for DIVERGED vendor files
# Excludes *.local.md (never promoted wholesale)
# Usage:
#   ./promote.sh                # TUI
#   ./promote.sh --dest ./docs  # custom docs path

DEST="./docs"
REPO="darideveloper/agent-docs"
BRANCH="main"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest) DEST="$2"; shift 2;;
    --help|-h) echo "Usage: $0 [--dest ./docs]"; exit 0;;
    *) echo "Unknown arg: $1" >&2; exit 1;;
  esac
done

if [[ ! -d "$DEST" ]]; then
  echo "No $DEST directory found." >&2
  exit 1
fi

# Collect vendor files (exclude *.local.md and INDEX.md)
vendor_files=()
while IFS= read -r -d '' f; do
  [[ "$f" == *".local.md" ]] && continue
  [[ "$f" == *"/INDEX.md" ]] && continue
  vendor_files+=("$f")
done < <(find "$DEST" -maxdepth 3 -type f -name "*.md" -print0 2>/dev/null | sort -z)

if [[ ${#vendor_files[@]} -eq 0 ]]; then
  echo "No vendored *.md found in $DEST (excluding *.local.md)." >&2
  exit 0
fi

# For each file, check if it has local edits vs header version
# Best-effort: list all and let user pick; show diff against tmp fetch of upstream
echo "Vendored files (excluding *.local.md):"
for i in "${!vendor_files[@]}"; do
  f="${vendor_files[$i]}"
  src=$(grep -m1 "^source:" "$f" 2>/dev/null | sed 's/source:\s*//' || echo "unknown")
  ver=$(grep -m1 "^version:" "$f" 2>/dev/null | sed 's/version:\s*//' || echo "unknown")
  printf "  %2d) %s  [version %s]\n" $((i+1)) "$f" "$ver"
done
echo "   q) quit"

# Try to fetch upstream version for diff (best-effort via curl)
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

fetch_upstream() {
  local rel_path="$1" # e.g. django/django-project-setup.md or astro/gsap-scrolltrigger/README.md
  local url="https://raw.githubusercontent.com/${REPO}/${BRANCH}/$rel_path"
  local out="$TMPDIR/upstream-$(basename "$rel_path")"
  if curl -sL "$url" -o "$out" 2>/dev/null; then
    echo "$out"
  else
    echo ""
  fi
}

# Derive repo-relative path from source header or file layout
derive_rel() {
  local f="$1"
  local src
  src=$(grep -m1 "^source:" "$f" 2>/dev/null | sed 's/source:\s*templates:\/\///' || echo "")
  if [[ -n "$src" && "$src" != "unknown" ]]; then
    echo "$src"
  else
    # fallback: guess from location
    local base
    base=$(basename "$f")
    # try django first, then astro
    if [[ "$f" == *"gsap-scrolltrigger"* ]]; then
      echo "astro/gsap-scrolltrigger/$base"
    elif grep -q "django" "$f" 2>/dev/null; then
      echo "django/$base"
    else
      echo "astro/$base"
    fi
  fi
}

PS3="Select file to diff (or q): "
select choice in "${vendor_files[@]}"; do
  if [[ "$REPLY" == "q" || "$REPLY" == "Q" ]]; then exit 0; fi
  if [[ -n "$choice" && -f "$choice" ]]; then
    FILE="$choice"
    break
  else
    echo "Invalid selection"
  fi
done

echo ""
echo "Selected: $FILE"
rel=$(derive_rel "$FILE")
echo "Upstream: $rel (branch $BRANCH)"
upstream=$(fetch_upstream "$rel")

if [[ -z "$upstream" || ! -s "$upstream" ]]; then
  echo "Could not fetch upstream for $rel — showing local file only." >&2
  echo "Local file: $FILE"
  echo "---"
  cat "$FILE"
  exit 0
fi

patch_file="${FILE%.md}.patch"
echo ""
echo "Diff (local vs upstream):"
echo "  local:    $FILE"
echo "  upstream: $upstream"
echo "---"
if diff -u "$upstream" "$FILE" > "$patch_file" 2>&1; then
  echo "No differences (files identical). No patch written."
  rm -f "$patch_file"
else
  echo "Patch written to: $patch_file"
  echo ""
  echo "Suggested PR: ${REPO}: $rel"
  echo "Paste the patch into a PR body, or attach $patch_file"
  echo ""
  cat "$patch_file" | head -n 200
  if [[ $(wc -l < "$patch_file") -gt 200 ]]; then
    echo "... (patch truncated, full file at $patch_file)"
  fi
fi

echo ""
echo "Next: open a PR at https://github.com/${REPO}/compare/${BRANCH}... with this patch."
echo "Only generic improvements should be promoted — project-specific content stays in *.local.md"
