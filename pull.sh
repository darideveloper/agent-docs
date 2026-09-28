#!/usr/bin/env bash
set -euo pipefail

# pull.sh — vendored copy via degit + manifest, bash select TUI
# Usage:
#   ./pull.sh                          # TUI
#   ./pull.sh --check                  # report states
#   ./pull.sh --stack astro --layers i18n,react-islands --yes --dest ./docs
#
# Requires: bash 4+, python3, git + npx degit (fallback: curl per-file if no Node)
if [[ "${BASH_VERSINFO[0]:-0}" -lt 4 ]]; then
  echo "pull.sh requires bash 4+ (associative arrays, mapfile). On macOS: brew install bash." >&2
  exit 1
fi

REPO="darideveloper/agent-docs"
BRANCH="main"
MANIFEST_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/manifest.json"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_FILE="${SCRIPT_DIR}/manifest.json"
if [[ ! -f "$MANIFEST_FILE" ]]; then
  # when curl|bash, manifest is remote
  MANIFEST_FILE="/tmp/agent-docs-manifest.json"
  if command -v curl >/dev/null 2>&1; then
    curl -sL "$MANIFEST_URL" -o "$MANIFEST_FILE" 2>/dev/null || true
  fi
fi

DEST="./docs"
STACK=""
LAYERS=""
YES="false"
CHECK="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest) DEST="$2"; shift 2;;
    --stack) STACK="$2"; shift 2;;
    --layers) LAYERS="$2"; shift 2;;
    --yes) YES="true"; shift;;
    --check) CHECK="true"; shift;;
    --help|-h) echo "Usage: $0 [--stack django|astro] [--layers a,b] [--yes] [--dest ./docs] [--check]"; exit 0;;
    *) echo "Unknown arg: $1" >&2; exit 1;;
  esac
done

# NOTE: manifest parsing uses python3 helpers below (py_list_*). No jq needed.

# --check mode: header dump only (no upstream comparison).
# For UP-TO-DATE/DIVERGED/NEW states use promote.sh --check.
if [[ "$CHECK" == "true" ]]; then
  echo "check: scanning ${DEST} headers..."
  if [[ ! -d "$DEST" ]]; then echo "MISSING: $DEST does not exist (re-pull to create)"; exit 0; fi
  # List vendor files (exclude *.local.md)
  found=0
  while IFS= read -r -d '' f; do
    [[ "$f" == *".local.md" ]] && continue
    [[ "$f" == *"/INDEX.md" ]] && continue
    found=1
    ver=$(grep -m1 "^version:" "$f" 2>/dev/null | sed 's/version: *//' || echo "unknown")
    src=$(grep -m1 "^source:" "$f" 2>/dev/null | sed 's/source: *//' || echo "unknown")
    echo "  $f  source=$src  version=$ver"
  done < <((find "$DEST" -maxdepth 2 -type f -name "*.md" -print0 2>/dev/null; find "$DEST" -maxdepth 3 -type f -path "*/gsap-scrolltrigger/*.md" -print0 2>/dev/null) | sort -zu)
  [[ $found -eq 0 ]] && echo "  (no vendored *.md found)"
  echo "check done. States: see promote.sh --check for UP-TO-DATE/DIVERGED/NEW. Pull always overwrites *.md, never *.local.md."
  exit 0
fi

# Determine manifest source: local file preferred
if [[ ! -f "$MANIFEST_FILE" ]]; then
  echo "manifest not found at $MANIFEST_FILE and remote fetch failed." >&2
  echo "Run from agent-docs checkout, or ensure curl can fetch $MANIFEST_URL" >&2
  exit 1
fi

# Python helper to list stacks/layers
py_list_stacks() {
  python3 -c "import json; data=json.load(open('$MANIFEST_FILE')); print('\n'.join(data.keys()))"
}
py_list_base() {
  local stack="$1"
  python3 -c "
import json
data=json.load(open('$MANIFEST_FILE'))
for item in data.get('$stack',{}).get('base',[]):
    print(f\"{item['file']}|{item['description']}\")
"
}
py_list_layers() {
  local stack="$1"
  python3 -c "
import json
data=json.load(open('$MANIFEST_FILE'))
layers=data.get('$stack',{}).get('layers',{})
for k,v in layers.items():
    files=','.join(v.get('files',[]))
    desc=v.get('description','')
    print(f\"{k}|{files}|{desc}\")
"
}

# TUI: pick stack if not given
if [[ -z "$STACK" ]]; then
  echo "Select stack:"
  stacks=$(py_list_stacks)
  # convert to array
  mapfile -t stack_arr <<< "$stacks"
  if [[ ${#stack_arr[@]} -eq 0 ]]; then echo "No stacks in manifest" >&2; exit 1; fi
  PS3="Enter number (stack): "
  select choice in "${stack_arr[@]}"; do
    if [[ -n "$choice" ]]; then STACK="$choice"; break; else echo "Invalid selection"; fi
  done
fi

# Validate stack
if ! python3 -c "import json; data=json.load(open('$MANIFEST_FILE')); assert '$STACK' in data" 2>/dev/null; then
  echo "Unknown stack: $STACK (available: $(py_list_stacks | tr '\n' ',' ))" >&2
  exit 1
fi

echo "Stack: $STACK"

# Build selection lists
mapfile -t base_entries < <(py_list_base "$STACK")
mapfile -t layer_entries < <(py_list_layers "$STACK")

# Show base (mandatory)
echo ""
echo "Base (always included):"
for e in "${base_entries[@]}"; do
  IFS='|' read -r file desc <<< "$e"
  echo "  [x] $file — $desc"
done

# Layer selection via bash select loop
declare -A selected
for e in "${layer_entries[@]}"; do
  IFS='|' read -r name files desc <<< "$e"
  selected["$name"]="false"
done

# If --layers provided non-interactively, parse them
if [[ -n "$LAYERS" ]]; then
  IFS=',' read -ra req <<< "$LAYERS"
  for r in "${req[@]}"; do
    r=$(echo "$r" | xargs)
    [[ -z "$r" ]] && continue
    if [[ -v selected["$r"] ]]; then
      selected["$r"]="true"
    else
      echo "Warning: unknown layer '$r' for stack $STACK" >&2
    fi
  done
  # if --yes, skip TUI
  if [[ "$YES" == "true" ]]; then
    echo ""
    echo "Layers (pre-selected via --layers):"
    for e in "${layer_entries[@]}"; do
      IFS='|' read -r name files desc <<< "$e"
      mark=" "; [[ "${selected[$name]}" == "true" ]] && mark="x"
      echo "  [$mark] $name — $desc"
    done
  else
    LAYERS="" # fall through to TUI
  fi
fi

# Interactive layer toggle: skipped when --yes (non-interactive, base + --layers only).
if [[ "$YES" != "true" ]]; then
  if [[ ${#layer_entries[@]} -gt 0 && ( -z "$LAYERS" || "$YES" != "true" ) ]]; then
    # Build indexed array of layer names
    layer_names=()
    for e in "${layer_entries[@]}"; do
      IFS='|' read -r name files desc <<< "$e"
      layer_names+=("$name")
    done
    echo ""
    echo "Toggle layers (enter number to toggle, 'd' when done):"
    while true; do
      for i in "${!layer_names[@]}"; do
        name="${layer_names[$i]}"
        # find desc
        desc=""
        for e in "${layer_entries[@]}"; do
          IFS='|' read -r n f d <<< "$e"
          [[ "$n" == "$name" ]] && desc="$d" && break
        done
        mark=" "; [[ "${selected[$name]}" == "true" ]] && mark="x"
        printf "  %2d) [%s] %-20s — %s\n" $((i+1)) "$mark" "$name" "$desc"
      done
      echo "   d) done"
      read -rp "Select: " ans
      if [[ "$ans" == "d" || "$ans" == "D" ]]; then break; fi
      if [[ "$ans" =~ ^[0-9]+$ ]] && (( ans >= 1 && ans <= ${#layer_names[@]} )); then
        idx=$((ans-1))
        name="${layer_names[$idx]}"
        if [[ "${selected[$name]}" == "true" ]]; then selected["$name"]="false"; else selected["$name"]="true"; fi
      else
        echo "Invalid input"
      fi
    done
  fi
fi

# Collect selected files
files_to_copy=()
for e in "${base_entries[@]}"; do
  IFS='|' read -r file desc <<< "$e"
  files_to_copy+=("$STACK/$file")
done
for e in "${layer_entries[@]}"; do
  IFS='|' read -r name files desc <<< "$e"
  if [[ "${selected[$name]}" == "true" ]]; then
    IFS=',' read -ra parts <<< "$files"
    for p in "${parts[@]}"; do
      p=$(echo "$p" | xargs)
      [[ -z "$p" ]] && continue
      files_to_copy+=("$STACK/$p")
    done
  fi
done

echo ""
echo "Selected files (${#files_to_copy[@]}):"
for f in "${files_to_copy[@]}"; do echo "  - $f"; done

if [[ "$YES" != "true" ]]; then
  read -rp "Proceed? [Y/n] " confirm
  if [[ "$confirm" =~ ^[nN] ]]; then echo "Aborted."; exit 0; fi
fi

# Fetch via degit or fallback
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

fetched=false
if command -v npx >/dev/null 2>&1; then
  echo "Fetching ${REPO}#${BRANCH} via degit..."
  if npx --yes degit "${REPO}#${BRANCH}" "$TMPDIR/agent-docs" --force 2>&1 | tail -n 20; then
    fetched=true
  else
    echo "degit failed, falling back to curl per-file..." >&2
  fi
else
  echo "npx not found — using curl per-file fallback..."
fi

mkdir -p "$DEST"

# Copy helper — keeps upstream source:/version: untouched (single truth).
copy_with_header() {
  local src="$1"
  local dst="$2"
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
}

if [[ "$fetched" == "true" && -d "$TMPDIR/agent-docs" ]]; then
  for rel in "${files_to_copy[@]}"; do
    src="$TMPDIR/agent-docs/$rel"
    rel_after_stack="${rel#*/}"
    dst="$DEST/$rel_after_stack"
    if [[ -f "$src" ]]; then
      copy_with_header "$src" "$dst"
      echo "  copied $rel -> $dst"
    else
      echo "  missing in source: $rel" >&2
    fi
  done
elif [[ -d "$SCRIPT_DIR/$STACK" ]]; then
  # Local fallback: SCRIPT_DIR is agent-docs checkout (pre-push / offline use)
  echo "Using local source at $SCRIPT_DIR ..."
  for rel in "${files_to_copy[@]}"; do
    src="$SCRIPT_DIR/$rel"
    rel_after_stack="${rel#*/}"
    dst="$DEST/$rel_after_stack"
    if [[ -f "$src" ]]; then
      copy_with_header "$src" "$dst"
      echo "  copied $rel -> $dst (local)"
    else
      echo "  missing in local source: $rel" >&2
    fi
  done
else
  # curl per-file fallback: fetch each file from raw github
  echo "Fetching files via curl..."
  for rel in "${files_to_copy[@]}"; do
    url="https://raw.githubusercontent.com/${REPO}/${BRANCH}/$rel"
    rel_after_stack="${rel#*/}"
    dst="$DEST/$rel_after_stack"
    mkdir -p "$(dirname "$dst")"
    if curl -sL "$url" -o "$dst"; then
      # detect 404 HTML
      if head -n 1 "$dst" | grep -q "404: Not Found"; then
        echo "  failed to fetch $rel (404)" >&2
        rm -f "$dst"
      else
        echo "  fetched $rel -> $dst"
      fi
    else
      echo "  failed to fetch $rel" >&2
    fi
  done
fi

# Create empty .local.md stubs (never overwrite)
for rel in "${files_to_copy[@]}"; do
  rel_after_stack="${rel#*/}"
  base_dst="$DEST/$rel_after_stack"
  local_file="${base_dst%.md}.local.md"
  if [[ ! -f "$local_file" ]]; then
    mkdir -p "$(dirname "$local_file")"
    cat > "$local_file" << EOF
---
source: templates://${STACK}/${rel_after_stack%.md}.local.md
version: $(date +%Y-%m-%d)+local
---

# ${rel_after_stack%.md} — Project Overrides

> Project-specific additions for \`${rel_after_stack}\`. This file is never overwritten by \`pull.sh\`.

EOF
    echo "  stub $local_file"
  fi
done

# Write/refresh INDEX.md from template on every pull (vendored contract).
if [[ -f "$SCRIPT_DIR/INDEX-template.md" ]]; then
  cp "$SCRIPT_DIR/INDEX-template.md" "$DEST/INDEX.md"
elif [[ -f "$TMPDIR/agent-docs/INDEX-template.md" ]]; then
  cp "$TMPDIR/agent-docs/INDEX-template.md" "$DEST/INDEX.md"
else
  echo "# docs/INDEX" > "$DEST/INDEX.md"
fi
echo "  wrote $DEST/INDEX.md"

echo ""
echo "Done. Files in $DEST:"
ls -R "$DEST" 2>/dev/null | head -n 100
