#!/usr/bin/env bash
# skill-search.sh — find an existing agent skill: local scan first, GitHub fallback.
# Usage: skill-search.sh [--web|--local] [--top N] <query keywords>
set -euo pipefail

TOP=5
WEB=auto
QUERY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --web) WEB=force; shift ;;
    --local) WEB=off; shift ;;
    --top) TOP="$2"; shift 2 ;;
    -h|--help) sed -n '2,4p' "$0"; exit 0 ;;
    *) QUERY="${QUERY:+$QUERY }$1"; shift ;;
  esac
done
[ -n "$QUERY" ] || { echo "usage: skill-search.sh [--web|--local] [--top N] <query keywords>" >&2; exit 2; }

command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }
PY="$(command -v python3 || command -v python || true)"
[ -n "$PY" ] || { echo "python3 is required" >&2; exit 1; }
if command -v jq >/dev/null; then HAS_JQ=1; else HAS_JQ=0; fi

GH="https://api.github.com"
AUTH=()
[ -n "${GITHUB_TOKEN:-}" ] && AUTH=(-H "Authorization: Bearer $GITHUB_TOKEN")
gh_get() { curl -sS -m 15 -H "Accept: application/vnd.github+json" "${AUTH[@]}" "$1"; }

# --- keyword scoring: AND-match, substring (works for CJK), case-insensitive ---
SCORE="$(cat <<'PYEOF'
import sys
q = sys.argv[1].lower().split()
for line in sys.stdin:
    line = line.rstrip("\n")
    if not line:
        continue
    parts = line.split(chr(9))
    kw = parts[0]
    desc = parts[1] if len(parts) > 1 else ""
    text = (kw + " " + desc).lower()
    if all(w in text for w in q):
        print(kw, desc, sep=chr(9))
PYEOF
)"

# ---------------- 1) local scan ----------------
echo "== LOCAL skills (query: $QUERY) =="
LOCAL_HITS=0
scan_local() {
  local root="$1" scope="$2" n=0
  [ -d "$root" ] || return 0
  local f
  for f in "$root"/*/SKILL.md; do
    [ -f "$f" ] || continue
    local name desc
    name="$(awk 'NR==1 && $0=="---"{f=1;next} f&&/^---/{exit} f&&index($0,"name:")==1{print substr($0,6);exit}' "$f")"
    desc="$(awk 'NR==1 && $0=="---"{f=1;next} f&&/^---/{exit}
      f&&index($0,"description:")==1{d=1;v=substr($0,13);gsub(/^[[:space:]]+/,"",v);if(v!=""&&v!=">-"&&v!=">"&&v!="|-"){print;exit};next}
      f&&d{if($0~/^[^[:space:]]/)exit;v=$0;gsub(/^[[:space:]]+/,"",v);if(v!="")print}' "$f" | tr '\n' ' ')"
    printf '%s\t%s\n' "${name:-$(basename "$(dirname "$f")")}" "$desc"
    n=$((n+1))
  done
  [ "$n" -gt 0 ] && echo "  ($scope: $n skill(s) indexed under $root)" >&2
}
LOCAL_ROWS="$(
  scan_local "$HOME/.config/opencode/skills" global
  scan_local "$HOME/.claude/skills" global
  scan_local "$HOME/.agents/skills" global
  d="$PWD"
  while [ "$d" != "/" ]; do
    for sub in .opencode/skills .opencode/skill .claude/skills .agents/skills; do
      scan_local "$d/$sub" "project"
    done
    [ -d "$d/.git" ] && break
    d="$(dirname "$d")"
  done
)"
if [ -n "$LOCAL_ROWS" ]; then
  while IFS=$'\t' read -r n d; do
    [ -n "$n" ] || continue
    s="$(printf '%s\t%s\n' "$n" "$d" | "$PY" -c "$SCORE" "$QUERY")" || true
    [ -n "$s" ] || continue
    LOCAL_HITS=$((LOCAL_HITS+1))
    echo "  HIT | $n | ${d:0:160}"
  done <<< "$LOCAL_ROWS"
fi
[ "$LOCAL_HITS" -eq 0 ] && echo "  (no local match)"

if [ "$WEB" = off ]; then exit 0; fi
if [ "$LOCAL_HITS" -gt 0 ] && [ "$WEB" != force ]; then
  echo; echo "(local match found — network skipped; use --web to force)"
  exit 0
fi

# ---------------- 2) GitHub topic search ----------------
echo; echo "== GITHUB topic search =="
KW_URL="$( "$PY" -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$QUERY" )"
for topic in agent-skills claude-skills opencode-skills; do
  echo "-- topic:$topic --"
  RESP="$(gh_get "$GH/search/repositories?q=topic%3A$topic+$KW_URL&per_page=$TOP")"
  if [ "$HAS_JQ" = 1 ]; then
    REPOS="$(printf '%s' "$RESP" | jq -r '.items[]? | "\(.full_name)|\(.html_url)|\(.description // "")"' 2>/dev/null || true)"
  else
    REPOS="$(printf '%s' "$RESP" | "$PY" -c 'import sys,json
d=json.load(sys.stdin)
for i in d.get("items",[]): print("|".join([i["full_name"], i["html_url"], (i.get("description") or "").replace("|"," ")]))' 2>/dev/null || true)"
  fi
  if [ -z "$REPOS" ]; then
    printf '%s' "$RESP" | grep -qi 'rate limit' && echo "  (GitHub rate limit — wait or set GITHUB_TOKEN)" || echo "  (no results)"
    continue
  fi
  while IFS='|' read -r full url desc; do
    [ -n "$full" ] || continue
    echo "  REPO $full — $desc"
    echo "       url: $url"
    skills="$(gh_get "$GH/repos/$full/contents/skills" | "$PY" -c 'import sys,json
try:
  d=json.load(sys.stdin)
  if isinstance(d,list): print(" ".join(x["name"] for x in d if x.get("type")=="dir"))
except Exception: pass' 2>/dev/null || true)"
    [ -n "$skills" ] && echo "       skills: $skills"
  done <<< "$REPOS"
done

# ---------------- 3) known indexes (README grep) ----------------
echo; echo "== KNOWN INDEXES (keyword grep in README) =="
for repo in anthropics/skills addyosmani/agent-skills; do
  for br in main master; do
    README="$(curl -sS -m 15 "https://raw.githubusercontent.com/$repo/$br/README.md" 2>/dev/null || true)"
    [ -n "$README" ] || continue
    M="$(printf '%s\n' "$README" | grep -iE "$QUERY" | grep -iE '\[|http' | head -3 || true)"
    [ -n "$M" ] && { echo "-- $repo ($br) --"; printf '%s\n' "$M" | sed 's/^/  /'; }
    break
  done
done

echo; echo "Install hint: default destination ~/.claude/skills/<name>/ (auto-loaded by opencode after restart)."
