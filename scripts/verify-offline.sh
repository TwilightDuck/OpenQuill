#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
app="$PWD/dist/Open Whisper.app/Contents/MacOS/OpenWhisper"
[[ -x "$app" ]] || { print -u2 "Build the app first with ./scripts/build-app.sh"; exit 1; }
mkdir -p .verification
say -v Samantha -r 170 -o .verification/english.aiff "The meeting starts tomorrow at nine. Please send the report to my colleague."
say -v Ellen -r 165 -o .verification/flemish.aiff "Morgen hebben we een vergadering om negen uur. Stuur het verslag naar mijn collega."
policy='(version 1) (allow default) (deny network*)'
sandbox-exec -p "$policy" "$app" --transcribe "$PWD/.verification/english.aiff" --model parakeet-ultra --language en > .verification/english.json 2> .verification/english.log
sandbox-exec -p "$policy" "$app" --transcribe "$PWD/.verification/flemish.aiff" --model parakeet-ultra --language nl > .verification/flemish.json 2> .verification/flemish.log
python3 - <<'PY'
import json
from pathlib import Path
for language, words in [('english', ['meeting', 'tomorrow', 'report', 'colleague']), ('flemish', ['morgen', 'vergadering', 'verslag', 'collega'])]:
    result = json.loads(Path(f'.verification/{language}.json').read_text())
    transcript = result['text'].lower()
    assert all(word in transcript for word in words), result
    assert ('9' in transcript or ('nine' if language == 'english' else 'negen') in transcript), result
    assert result['audioSeconds'] > 0 and result['processingSeconds'] > 0, result
    print(f"{language}: {result['text']} ({result['audioSeconds']:.2f}s audio → {result['processingSeconds']:.2f}s inference, network denied)")
PY
