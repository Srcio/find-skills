---
description: Search for an existing agent skill (local installs + GitHub) matching a query.
---

Run the skill-search script with the user's query:

```bash
bash "$HOME/.config/opencode/skills/skill-search/scripts/skill-search.sh" "$ARGUMENTS"
```

Summarize the candidates found (source, description, install path). Propose an
install destination — default `~/.claude/skills/<name>/` — and wait for user
confirmation before downloading anything. After any install, remind the user to
restart opencode so the new skill is loaded.
