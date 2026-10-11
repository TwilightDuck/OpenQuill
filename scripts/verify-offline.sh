#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
app="$PWD/dist/Open Quill.app/Contents/MacOS/OpenQuill"
[[ -x "$app" ]] || { print -u2 "Build the app first with ./scripts/build-app.sh"; exit 1; }
mkdir -p .verification
say -v Samantha -r 170 -o .verification/english.aiff "The meeting starts tomorrow at nine. Please send the report to my colleague."
say -v Ellen -r 165 -o .verification/flemish.aiff "Morgen hebben we een vergadering om negen uur. Stuur het verslag naar mijn collega."
say -v Thomas -r 165 -o .verification/french.aiff "La réunion commence demain matin. Envoyez le rapport à mon collègue."
say -v Anna -r 165 -o .verification/german.aiff "Das Treffen beginnt morgen früh. Bitte senden Sie den Bericht an meinen Kollegen."
say -v Mónica -r 165 -o .verification/spanish.aiff "La reunión empieza mañana por la mañana. Por favor envía el informe a mi colega."
policy='(version 1) (allow default) (deny network*)'
sandbox-exec -p "$policy" "$app" --transcribe "$PWD/.verification/english.aiff" --model parakeet-ultra --language en > .verification/english.json 2> .verification/english.log
sandbox-exec -p "$policy" "$app" --transcribe "$PWD/.verification/flemish.aiff" --model parakeet-ultra --language nl > .verification/flemish.json 2> .verification/flemish.log
sandbox-exec -p "$policy" "$app" --transcribe "$PWD/.verification/french.aiff" --model parakeet-ultra --language fr > .verification/french.json 2> .verification/french.log
sandbox-exec -p "$policy" "$app" --transcribe "$PWD/.verification/german.aiff" --model parakeet-ultra --language de > .verification/german.json 2> .verification/german.log
sandbox-exec -p "$policy" "$app" --transcribe "$PWD/.verification/spanish.aiff" --model parakeet-ultra --language es > .verification/spanish.json 2> .verification/spanish.log
python3 - <<'PY'
import json
from pathlib import Path
cases = [('english', 'en', ['meeting', 'tomorrow', 'report', 'colleague']),
         ('flemish', 'nl', ['morgen', 'vergadering', 'verslag', 'collega']),
         ('french', 'fr', ['réunion', 'demain', 'rapport', 'collègue']),
         ('german', 'de', ['treffen', 'morgen', 'bericht', 'kollegen']),
         ('spanish', 'es', ['reunión', 'mañana', 'informe', 'colega'])]
for language, code, words in cases:
    result = json.loads(Path(f'.verification/{language}.json').read_text())
    transcript = result['text'].lower()
    assert all(word in transcript for word in words), result
    if language in ['english', 'flemish']:
        assert ('9' in transcript or ('nine' if language == 'english' else 'negen') in transcript), result
    assert result['language'] == code, result
    assert result['audioSeconds'] > 0 and result['processingSeconds'] > 0, result
    print(f"{language}: {result['text']} ({result['audioSeconds']:.2f}s audio → {result['processingSeconds']:.2f}s inference, network denied)")
PY
