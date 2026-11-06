#!/usr/bin/env bash
# Run the user-level scenario suite.
#
# Every scenario boots a fresh headless Neovim, drives the plugin through the
# real command + keymap layer against test/user/fake_backend.py (a slow
# backend, so requests can be cancelled mid-flight), and prints one PASS/FAIL
# line per assertion group.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
timeout_s="${TIMEOUT:-40}"
failed=0
total=0

for scenario in "$here"/scenarios/*.lua; do
	name="$(basename "$scenario" .lua)"
	out_file="$(mktemp)"
	total=$((total + 1))

	SLOW_DELAY="${SLOW_DELAY:-1}" SLOW_STAGGER="${SLOW_STAGGER:-1.5}" \
		nvim --headless -u NONE -i NONE -c "luafile $scenario" >"$out_file" 2>&1 &
	pid=$!
	(sleep "$timeout_s" && kill -9 "$pid" 2>/dev/null) >/dev/null 2>&1 &
	watchdog=$!

	wait "$pid"
	kill "$watchdog" 2>/dev/null
	wait "$watchdog" 2>/dev/null

	out="$(cat "$out_file")"
	rm -f "$out_file"
	if [[ -z "$out" ]]; then
		echo "FAIL $name | no output (timed out after ${timeout_s}s?)"
		failed=$((failed + 1))
		continue
	fi
	echo "$out"
	grep -q "^FAIL" <<<"$out" && failed=$((failed + 1))
done

if [[ $failed -ne 0 ]]; then
	echo "user tests: $failed/$total scenario(s) FAILED"
	exit 1
fi
echo "user tests: OK ($total scenarios)"
