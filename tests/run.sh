#!/bin/sh
# Runs every test page in tests/ in headless Chrome and prints the results.
# Exits 1 if a check fails or a page does not finish. Usage: tests/run.sh [-v] [page ...]
#   -v      print every check, not only failures
#   page    names without .html, e.g. tests/run.sh scoring watch-sync
# Needs python3 and Chrome; set CHROME=/path/to/chrome if it is not found.
set -u
cd "$(dirname "$0")/.."

verbose=0
if [ "${1:-}" = "-v" ]; then verbose=1; shift; fi

chrome="${CHROME:-}"
if [ -z "$chrome" ]; then
  for c in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" google-chrome google-chrome-stable chromium chromium-browser; do
    if [ -x "$c" ] || command -v "$c" >/dev/null 2>&1; then chrome="$c"; break; fi
  done
fi
if [ -z "$chrome" ]; then echo "Chrome not found; set CHROME=/path/to/chrome"; exit 2; fi

port="${PORT:-8765}"
profiles=$(mktemp -d)
python3 -m http.server "$port" --bind 127.0.0.1 >/dev/null 2>&1 &
server=$!
trap 'kill $server 2>/dev/null; wait $server 2>/dev/null; rm -rf "$profiles"' EXIT
sleep 1

if [ $# -gt 0 ]; then pages="$*"; else pages=$(ls tests/*.html | sed 's#tests/##; s#\.html$##'); fi

status=0
for name in $pages; do
  # A fresh Chrome profile per page, so no page sees another's saved data. Virtual time lets pages that wait
  # (timers, polls) finish quickly; perl's alarm stops a page that hangs.
  dom=$(perl -e 'alarm shift; exec @ARGV' 120 "$chrome" --headless=new --disable-gpu --no-sandbox --no-first-run \
    --user-data-dir="$profiles/$name" --virtual-time-budget=60000 \
    --dump-dom "http://127.0.0.1:$port/tests/$name.html" 2>/dev/null)
  lines=$(printf '%s\n' "$dom" | sed -n '/<pre id="out">/,/<\/pre>/p' \
    | sed 's/.*<pre id="out">//; s/<\/pre>.*//; s/&lt;/</g; s/&gt;/>/g; s/&quot;/"/g; s/&amp;/\&/g')
  title=$(printf '%s\n' "$dom" | sed -n 's/.*<title>\([A-Z]*\)<\/title>.*/\1/p' | head -1)
  summary=$(printf '%s\n' "$lines" | grep -E '^[0-9]+ passed' | tail -1)
  if [ "$title" = "PASSED" ]; then
    echo "ok    $name: $summary"
    [ $verbose -eq 1 ] && printf '%s\n' "$lines" | grep -E '^(PASS|FAIL)' | sed 's/^/      /'
  else
    status=1
    echo "FAIL  $name: ${summary:-did not finish}"
    printf '%s\n' "$lines" | grep -E '^FAIL' | sed 's/^/      /'
  fi
done
exit $status
