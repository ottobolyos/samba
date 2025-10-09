---
allowed-tools: Bash(python3:*)
description: Toggle API mode (enables/disables automatic ultrathink)
---

!`python3 -c "import json; from pathlib import Path; p = Path('$CLAUDE_PROJECT_DIR') / 'sessions' / 'sessions-config.json'; d = json.loads(p.read_text()); c = d.get('api_mode', False); n = not c; d['api_mode'] = n; p.write_text(json.dumps(d, indent=2)); print(f'API mode toggled: {c} → {n}')"`

API mode configuration updated. The change will take effect in your next message.

- **API mode enabled**: Ultrathink disabled to save tokens (manual control with `[[ ultrathink ]]`)
- **API mode disabled**: Ultrathink automatically enabled for best performance (Max mode)
