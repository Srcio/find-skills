---
name: skill-search
description: >-
  Search for an existing agent skill when the user asks to find, search, or
  discover one (e.g. "找一個能做 X 的 skill", "有沒有的 skill 可以…, "is there a skill
  for…", "install a skill that does Y"). Scans locally installed skills first,
  then falls back to GitHub (topic:agent-skills / claude-skills /
  opencode-skills) and known skill indexes via curl. Use ONLY when the needed
  capability is not already covered by an installed skill.
metadata:
  opencode/slash: "true"
---

# Skill Search

Find an existing skill before writing a new one from scratch.

## Workflow

1. Run the search script with the user's query (keep keywords verbatim; Chinese OK):

   ```bash
   bash "$HOME/.config/opencode/skills/skill-search/scripts/skill-search.sh" "<query keywords>"
   ```

   - Local scan always runs first (all opencode + Claude/agents skill dirs, local + global).
   - If nothing matches locally, the script queries GitHub (unauth; ~60 req/h — slow down on 403).
   - Flags: `--web` force network even on local hit, `--local` skip network, `--top N` results per source (default 5).

2. Report candidates to the user: source URL, one-line description, install path.

3. Propose an install destination and wait for confirmation before downloading:
   - Default: `~/.claude/skills/<name>/` (auto-loaded by opencode, no config edit).
   - Alternative: clone the source repo somewhere and register it via `skills.paths` in `~/.config/opencode/opencode.json`.

4. After installing, remind the user to **quit and restart opencode** — skills are loaded at startup and are not hot-reloaded.

## Rules

- Never install without explicit user confirmation.
- Prefer skills whose SKILL.md follows the spec (folder name == frontmatter `name`, description present).
- If both local and remote match, prefer local (already installed and working).
- Rate limit: GitHub unauth API is ~60 req/h. If `skill-search.sh` prints `rate limit`, wait an hour or set `GITHUB_TOKEN` (script uses it automatically for 5000 req/h).
