#!/usr/bin/env bash
# Run the Tidepool unit tests headless. Exits non-zero if anything fails.
#
#   ./run_tests.sh
#
# Set GODOT to point at a different binary if `godot` is not on your PATH.
set -uo pipefail

cd "$(dirname "$0")"

GODOT="${GODOT:-$(command -v godot || echo /Applications/Godot_mono.app/Contents/MacOS/Godot)}"
if [[ ! -x "$GODOT" ]]; then
  echo "godot not found; set GODOT=/path/to/godot" >&2
  exit 127
fi

# Adding a new class_name invalidates the global class cache, so always run the import
# pass first. It is a few seconds warm and it is the difference between a real failure and
# "Identifier not declared".
"$GODOT" --headless --path . --import >/dev/null 2>&1

"$GODOT" --headless --path . --script res://tests/run_tests.gd
status=$?
echo "exit status: $status"
exit $status
