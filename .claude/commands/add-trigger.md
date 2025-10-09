---
allowed-tools: Bash(python3:*)
argument-hint: "trigger phrase"
description: Add a new trigger phrase for switching to implementation mode
---

!`python3 -c "
import json
import sys
import os
from pathlib import Path

try:
    # Get the trigger phrase from arguments
    phrase = '$ARGUMENTS'.strip()

    if not phrase:
        print('Error: No trigger phrase provided. Usage: /add-trigger \"your phrase\"')
        sys.exit(1)

    # Find the config file
    project_dir = os.environ.get('CLAUDE_PROJECT_DIR', '.')
    config_file = Path(project_dir) / 'sessions' / 'sessions-config.json'

    if not config_file.exists():
        print(f'Error: sessions-config.json not found at {config_file}')
        sys.exit(1)

    # Read existing config
    with open(config_file, 'r') as f:
        data = json.load(f)

    # Add the trigger phrase (avoiding duplicates)
    if 'trigger_phrases' not in data:
        data['trigger_phrases'] = []

    if phrase not in data['trigger_phrases']:
        data['trigger_phrases'].append(phrase)
        data['trigger_phrases'].sort()  # Keep sorted for consistency

        # Write back to file
        with open(config_file, 'w') as f:
            json.dump(data, f, indent=2)

        print(f'Successfully added trigger phrase: \"{phrase}\"')
    else:
        print(f'Trigger phrase already exists: \"{phrase}\"')

except Exception as e:
    print(f'Error: {e}')
    sys.exit(1)
"`

The trigger phrase has been processed. The phrase will now trigger implementation mode when detected in your messages.
