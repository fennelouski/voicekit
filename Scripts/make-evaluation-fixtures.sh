#!/bin/bash
# Synthetic smoke fixtures only. Use real recordings for speech-quality decisions.
set -euo pipefail
cd "$(dirname "$0")/.."
DEST=build/evaluation-fixtures
mkdir -p "$DEST"
python3 - "$DEST" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
sentences = [
    ('brief', 'Yes.', 'brief-speech'),
    ('question', 'What time does the meeting start tomorrow?', 'literal-question'),
    ('terminology', 'OpenWhispr and VoiceKit use Kubernetes and Redis.', 'terminology'),
    ('self-correction', 'Send it on Monday, no, Tuesday morning.', 'self-correction'),
]
fixtures=[]
for name, text, category in sentences:
    (root / f'{name}.txt').write_text(text)
    fixtures.append(dict(id=name, audio=f'{name}.aiff', expected=text, locale='en-US', category=category))
(root / 'manifest.json').write_text(json.dumps(fixtures, indent=2)+'\n')
PY
for TEXT in "$DEST"/*.txt; do
  # Voice selection is explicit and uses voices already installed on this Mac.
  say -v "${EVALUATION_VOICE:-Samantha}" -f "$TEXT" -o "${TEXT%.txt}.aiff"
done
echo "Synthetic fixtures: $DEST/manifest.json"
