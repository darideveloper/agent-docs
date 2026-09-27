#!/usr/bin/env bash
set -euo pipefail

# promote.sh — promote generic fixes / new docs back upstream
# Never reads *.local.md or INDEX.md. Upstream stamps version on merge.
# Usage:
#   ./promote.sh                              # TUI grouped by state
#   ./promote.sh --check                      # read-only table
#   ./promote.sh --all [--yes] [--out DIR]    # batch: all DIVERGED+NEW
#   ./promote.sh --dest ./docs [--out DIR] [--stack astro]

DEST="./docs"
OUT=""
REPO="darideveloper/agent-docs"
BRANCH="main"
CHECK="false"
ALL="false"
YES="false"
STACK_HINT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest) DEST="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    --check) CHECK="true"; shift;;
    --all) ALL="true"; shift;;
    --yes) YES="true"; shift;;
    --stack) STACK_HINT="$2"; shift 2;;
    --help|-h)
      echo "Usage: $0 [--dest ./docs] [--check] [--all [--yes] [--out DIR]] [--stack astro|django]"
      echo "  TUI (default): pick file grouped by state, writes <file>.patch or <file>.add.md+snippet"
      echo "  --check: read-only STATE table. --all: batch all DIVERGED+NEW."
      exit 0;;
    *) echo "Unknown arg: $1" >&2; exit 1;;
  esac
done

if [[ ! -d "$DEST" ]]; then
  echo "No $DEST directory found." >&2
  exit 1
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

MANIFEST_TMP="$TMPDIR/manifest.json"
OFFLINE="false"
curl -sL "https://raw.githubusercontent.com/${REPO}/${BRANCH}/manifest.json" -o "$MANIFEST_TMP" 2>/dev/null || true
[[ -s "$MANIFEST_TMP" ]] || OFFLINE="true"

# Collect vendor files (exclude *.local.md and INDEX.md; depth mirrors pull.sh).
# sort -zu dedups: the gsap subtree matches both finds.
vendor_files=()
while IFS= read -r -d '' f; do
  [[ "$f" == *".local.md" ]] && continue
  [[ "$f" == *"/INDEX.md" ]] && continue
  vendor_files+=("$f")
done < <( (find "$DEST" -maxdepth 2 -type f -name "*.md" -print0 2>/dev/null; find "$DEST" -maxdepth 3 -type f -path "*/gsap-scrolltrigger/*.md" -print0 2>/dev/null) | sort -zu)

if [[ ${#vendor_files[@]} -eq 0 ]]; then
  echo "No vendored *.md found in $DEST (excluding *.local.md)." >&2
  exit 0
fi

derive_rel() {
  local f="$1"
  local src
  src=$(grep -m1 "^source:" "$f" 2>/dev/null | sed 's/source:\s*templates:\/\///' || echo "")
  if [[ -n "$src" && "$src" != "unknown" ]]; then
    echo "$src"
  else
    local base
    base=$(basename "$f")
    if [[ "$f" == *"gsap-scrolltrigger"* ]]; then
      echo "astro/gsap-scrolltrigger/$base"
    elif grep -q "django" "$f" 2>/dev/null; then
      echo "django/$base"
    elif [[ -n "$STACK_HINT" ]]; then
      echo "${STACK_HINT}/$base"
    else
      echo "astro/$base"
    fi
  fi
}

fetch_upstream() {
  local rel_path="$1"
  local safe
  safe=$(echo "$rel_path" | tr '/' '_')
  local out="$TMPDIR/upstream-$safe"
  if [[ -f "$out" ]]; then echo "$out"; return; fi
  if curl -sL "https://raw.githubusercontent.com/${REPO}/${BRANCH}/$rel_path" -o "$out" 2>/dev/null; then
    if head -n 1 "$out" 2>/dev/null | grep -q "404: Not Found"; then
      rm -f "$out"; echo ""; return
    fi
    echo "$out"
  else
    echo ""
  fi
}

# ponytail: pull.sh re-stamps source/version on copy, so headers are noise.
# State compares content only (diff -I); upstream stamps real version on merge.
classify() {
  local f="$1" rel upstream
  rel=$(derive_rel "$f")
  upstream=$(fetch_upstream "$rel")
  if [[ -z "$upstream" || ! -s "$upstream" ]]; then
    if [[ "$OFFLINE" == "true" ]]; then echo "UNKNOWN|$rel|"; else echo "NEW|$rel|"; fi
  elif diff -q -I '^source:' -I '^version:' "$upstream" "$f" >/dev/null 2>&1; then
    echo "UP-TO-DATE|$rel|$upstream"
  else
    echo "DIVERGED|$rel|$upstream"
  fi
}

# Fail-closed secrets gate; placeholders pass. Warnings (project signals) print only.
sanitize_gate() {
  local f="$1"
  if grep -q "sk_live" "$f" 2>/dev/null; then echo "BLOCKED: $f contains sk_live" >&2; return 1; fi
  if grep -q "BEGIN .*PRIVATE KEY" "$f" 2>/dev/null; then echo "BLOCKED: $f contains a private key" >&2; return 1; fi
  # sk_test / SECRET_KEY= / PASSWORD only blocked when NOT a placeholder line
  if grep -E "sk_test|SECRET_KEY=|PASSWORD" "$f" 2>/dev/null | grep -v -E "sk_test_placeholder|SECRET_KEY=change-me|<[^>]+>|example|placeholder|paste-token-here" | grep -q .; then
    echo "BLOCKED: $f contains a possible real secret (sk_test/SECRET_KEY/PASSWORD). Use placeholders." >&2
    return 1
  fi
  grep -E "https?://[a-z0-9-]+\.localhost|/mnt/hd/" "$f" 2>/dev/null | head -n 3 | sed 's/^/WARN project-signal: /' >&2 || true
  return 0
}

emit_modify() {
  local f="$1" rel="$2" upstream="$3" patch_file
  if [[ -n "$OUT" ]]; then mkdir -p "$OUT"; patch_file="$OUT/$(basename "${f%.md}").patch"
  else patch_file="${f%.md}.patch"; fi
  {
    echo "# Source: templates://$rel"
    echo "# Suggested-PR: ${REPO}: $rel"
    echo "# Note: source/version stamp lines are noise (pull.sh re-stamps, upstream re-stamps on merge); review content hunks."
    diff -u "$upstream" "$f" || true
  } > "$patch_file"
  echo "Patch written to: $patch_file"
  head -n 40 "$patch_file" | tail -n 30
}

emit_new() {
  local f="$1" rel="$2" base dest snippet stack
  base=$(basename "$f" .md)
  if [[ -n "$OUT" ]]; then mkdir -p "$OUT"; dest="$OUT/$base.md"
  else dest="${f%.md}.add.md"; fi
  cp "$f" "$dest"
  stack=$(echo "$rel" | cut -d/ -f1)
  snippet="${dest%.md}.manifest.json.snippet"
  cat > "$snippet" <<EOF
{ "file": "$(echo "$rel" | cut -d/ -f2-)", "description": "TODO one-line Use-when" }
EOF
  echo "New file copied to: $dest"
  echo "Manifest snippet: $snippet (paste under $stack.layers.<new-key> or $stack.base)"
  echo "Hub hint: add row to $stack/$stack.md opt-in table + keep source: templates://$rel header"
}

if [[ "$CHECK" == "true" ]]; then
  printf "%-10s  %s\n" "STATE" "FILE"
  for f in "${vendor_files[@]}"; do
    IFS='|' read -r state rel _ < <(classify "$f")
    printf "%-10s  %s  [%s]\n" "$state" "$f" "$rel"
  done
  echo "States: UP-TO-DATE (content same, stamp ignored) / DIVERGED (content differs — local fix or upstream moved, inspect diff) / NEW (not upstream yet) / UNKNOWN (offline, retry online)."
  exit 0
fi

if [[ "$ALL" == "true" ]]; then
  [[ -n "$OUT" ]] && mkdir -p "$OUT"
  wrote=0; skipped=0; blocked=0
  for f in "${vendor_files[@]}"; do
    IFS='|' read -r state rel upstream < <(classify "$f")
    case "$state" in
      DIVERGED)
        if sanitize_gate "$f"; then
          [[ "$YES" != "true" ]] && { read -rp "Promote $f? [Y/n] " c; [[ "$c" =~ ^[nN] ]] && { skipped=$((skipped+1)); continue; }; }
          emit_modify "$f" "$rel" "$upstream"; wrote=$((wrote+1))
        else blocked=$((blocked+1)); fi;;
      NEW)
        if sanitize_gate "$f"; then
          [[ "$YES" != "true" ]] && { read -rp "Promote NEW $f? [Y/n] " c; [[ "$c" =~ ^[nN] ]] && { skipped=$((skipped+1)); continue; }; }
          emit_new "$f" "$rel"; wrote=$((wrote+1))
        else blocked=$((blocked+1)); fi;;
      *) skipped=$((skipped+1));;
    esac
  done
  echo "Done: wrote=$wrote skipped=$skipped blocked=$blocked"
  echo "Next: open a PR at https://github.com/${REPO}/compare/${BRANCH}... (only generic content; upstream stamps version)."
  exit 0
fi

# TUI grouped by state
echo "Classifying ${#vendor_files[@]} files..."
declare -a labels states rels ups
for f in "${vendor_files[@]}"; do
  IFS='|' read -r state rel upstream < <(classify "$f")
  labels+=("$f [$state]")
  states+=("$state"); rels+=("$rel"); ups+=("$upstream")
done
for i in "${!labels[@]}"; do printf "  %2d) %s\n" $((i+1)) "${labels[$i]}"; done
echo "   q) quit"
PS3="Select file to promote (or q): "
select _ in "${vendor_files[@]}"; do
  if [[ "$REPLY" == "q" || "$REPLY" == "Q" ]]; then exit 0; fi
  if [[ -n "$REPLY" && "$REPLY" =~ ^[0-9]+$ ]] && (( REPLY >= 1 && REPLY <= ${#vendor_files[@]} )); then
    idx=$((REPLY-1)); FILE="${vendor_files[$idx]}"
    STATE="${states[$idx]}"; REL="${rels[$idx]}"; UP="${ups[$idx]}"
    break
  else echo "Invalid selection"; fi
done

echo ""
echo "Selected: $FILE [$STATE] upstream: $REL"
case "$STATE" in
  UP-TO-DATE) echo "No content differences (stamp ignored). Nothing to promote."; exit 0;;
  DIVERGED)
    sanitize_gate "$FILE" || exit 1
    emit_modify "$FILE" "$REL" "$UP";;
  NEW)
    sanitize_gate "$FILE" || exit 1
    emit_new "$FILE" "$REL";;
esac
echo ""
echo "Next: open a PR at https://github.com/${REPO}/compare/${BRANCH}... with this artifact."
echo "Only generic improvements — project-specific content stays in *.local.md (upstream stamps version on merge)."
