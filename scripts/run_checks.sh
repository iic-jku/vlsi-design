#!/bin/bash
# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Runs the check scripts of all chapters, or of the chapters
# named, inside the IIC-OSIC-TOOLS container and prints one summary. Exits
# with 1 if a chapter fails. Usage, from anywhere in the container:
#   scripts/run_checks.sh [chapter ...]           every value the book quotes
#   CHECK_MODE=regression scripts/run_checks.sh   what the exercises need
# CHECK_MODE is explained in scripts/lib_check.sh. Other settings:
#   JOBS=n           chapters in parallel (default 2). check_digital_flow
#                    runs two LibreLane runs itself, and the run-time
#                    checks of check_verification want an idle machine.
#   RUN_DIR=dir      logs and work folders (default /tmp/vlsi_checks)
#   CHECK_TIMEOUT=s  limit per chapter in seconds (default 10800, the
#                    LibreLane chapter alone takes about 30 minutes)
#   TEMPLATE_DIR     as in the chapter scripts

REPO=$(cd "$(dirname "$0")/.." && pwd)
RUN_DIR=${RUN_DIR:-/tmp/vlsi_checks}
JOBS=${JOBS:-2}
CHECK_TIMEOUT=${CHECK_TIMEOUT:-10800}
export CHECK_MODE=${CHECK_MODE:-book}
# Long chapters first, so that none of them starts last
SLOW="digital_flow cdc dft verification sv_crashcourse"

case $CHECK_MODE in
  book | regression) ;;
  *) echo "CHECK_MODE must be book or regression, not '$CHECK_MODE'" >&2; exit 2 ;;
esac
case $JOBS in '' | *[!0-9]* | 0) JOBS=2 ;; esac

# The course uses SG13CMOS5L, the container starts with SG13G2. The script
# fails under set -u and returns 1 even when it switched, so check PDK.
if [ "${PDK:-}" != ihp-sg13cmos5l ] && command -v sak-pdk-script.sh > /dev/null; then
  # shellcheck source=/dev/null
  source sak-pdk-script.sh ihp-sg13cmos5l sg13cmos5l_stdcell > /dev/null 2>&1
fi
set -u
if [ "${PDK:-}" != ihp-sg13cmos5l ] || [ ! -d "${PDK_ROOT:-}/ihp-sg13cmos5l" ]; then
  echo "Needs the IIC-OSIC-TOOLS container with PDK=ihp-sg13cmos5l (PDK='${PDK:-}')." >&2
  exit 2
fi

all=()
for f in "$REPO"/scripts/check_*.sh; do
  c=$(basename "$f" .sh)
  all+=("${c#check_}")
done
if [ $# -gt 0 ]; then
  chapters=()
  for a in "$@"; do
    c=$(basename "$a" .sh)
    c=${c#check_}
    if [ ! -f "$REPO/scripts/check_$c.sh" ]; then
      echo "No check script for '$a'. Chapters: ${all[*]}" >&2
      exit 2
    fi
    chapters+=("$c")
  done
else
  chapters=()
  for c in $SLOW; do
    [ -f "$REPO/scripts/check_$c.sh" ] && chapters+=("$c")
  done
  for c in "${all[@]}"; do
    case " $SLOW " in *" $c "*) ;; *) chapters+=("$c") ;; esac
  done
fi

mkdir -p "$RUN_DIR/logs"
rm -f "$RUN_DIR"/logs/*.status
echo "Checks of ${#chapters[@]} chapters, CHECK_MODE=$CHECK_MODE, JOBS=$JOBS"
echo "  repository: $REPO ($(git -C "$REPO" rev-parse --short HEAD 2> /dev/null || echo 'no git'))"
echo "  image:      ${IIC_OSIC_TOOLS_VERSION:-unknown}"
echo "  logs:       $RUN_DIR/logs"

run_one() {  # run_one <chapter>: run one check script, write its status file
  local c=$1 start rc
  start=$(date +%s)
  CHECK_DIR=$RUN_DIR/work/$c timeout "$CHECK_TIMEOUT" \
    bash "$REPO/scripts/check_$c.sh" > "$RUN_DIR/logs/$c.log" 2>&1
  rc=$?
  echo "$rc $(( $(date +%s) - start ))" > "$RUN_DIR/logs/$c.status"
  echo "  done $c: exit status $rc"
}

for c in "${chapters[@]}"; do
  while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do
    wait -n
  done
  run_one "$c" &
done
wait

failed=0
echo
printf '%-16s %-6s %6s %6s %6s %7s\n' chapter result ok fail drift seconds
for c in "${chapters[@]}"; do
  L=$RUN_DIR/logs/$c.log
  read -r rc secs < "$RUN_DIR/logs/$c.status"
  res=PASS
  [ "$rc" -eq 0 ] || { res=FAIL; failed=$((failed + 1)); }
  [ "$rc" -eq 124 ] && res=TIME
  printf '%-16s %-6s %6s %6s %6s %7s\n' "$c" "$res" "$(grep -c '^  ok ' "$L")" \
    "$(grep -c '^  FAIL ' "$L")" "$(grep -c '^  drift ' "$L")" "$secs"
done
for c in "${chapters[@]}"; do
  L=$RUN_DIR/logs/$c.log
  if grep -q -E '^  (FAIL|drift) ' "$L"; then
    echo
    echo "== $c"
    grep -E '^  (FAIL|drift) ' "$L"
  fi
  read -r rc secs < "$RUN_DIR/logs/$c.status"
  if [ "$rc" -ne 0 ] && ! grep -q '^  FAIL ' "$L"; then
    echo
    echo "== $c stopped with exit status $rc, the end of its log:"
    tail -n 15 "$L"
  fi
done
echo
if [ "$failed" -eq 0 ]; then
  echo "PASS: ${#chapters[@]} chapters"
else
  echo "FAIL: $failed of ${#chapters[@]} chapters"
  exit 1
fi
