#!/usr/bin/env bash
# Test runner. Runs the fast unit + stubbed-dispatch suites by default; add the
# slow Docker integration suite with --docker (or RUN_DOCKER=1).
#
#   tests/run.sh             # fast suites only
#   tests/run.sh --docker    # also run the real-image integration test
#
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

run_docker=0
[[ "${1:-}" == "--docker" || "${RUN_DOCKER:-0}" == "1" ]] && run_docker=1

suites=("$HERE/unit_detect.sh" "$HERE/dispatch_stubbed.sh")
[[ "$run_docker" == "1" ]] && suites+=("$HERE/integration_docker.sh")

rc=0
for s in "${suites[@]}"; do
  echo "════════════════════════════════════════════════════════════"
  echo "▶ $(basename "$s")"
  echo "════════════════════════════════════════════════════════════"
  bash "$s" || rc=1
  echo
done

if [[ "$run_docker" == "0" ]]; then
  echo "(integration_docker.sh skipped — pass --docker to include it)"
fi
exit $rc
