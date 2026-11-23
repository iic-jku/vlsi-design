# shellcheck shell=bash
# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Check helpers that every scripts/check_<chapter>.sh sources.
# CHECK_MODE decides which checks can fail a script:
#   book             (default) every check, i.e., every value that the
#                    chapter quotes for the image named in the script header
#   regression-full  only the must checks, i.e., what the exercises need on
#                    any image: the tools run, the course code lints,
#                    synthesizes, and passes its testbenches, and every
#                    seeded bug is caught. A check that differs is printed
#                    as drift, a quoted value that a tool or PDK update
#                    changed.
#   regression       as regression-full, but without the long runs of
#                    variants: four of the seven LibreLane runs of
#                    digital_flow and two of the four ngspice runs of cdc.
#                    The nightly test of IIC-OSIC-TOOLS runs this mode.

CHECK_MODE=${CHECK_MODE:-book}
case $CHECK_MODE in
  book | regression-full | regression) ;;
  *) echo "CHECK_MODE must be book, regression-full or regression, not '$CHECK_MODE'" >&2; exit 2 ;;
esac
n_check=0
n_must=0
fails=0
drifts=0

check() {  # check <what> <got> <expected>: a value that the chapter quotes
  n_check=$((n_check + 1))
  if [ "$2" == "$3" ]; then
    echo "  ok    $1: $2"
  elif [ "$CHECK_MODE" != book ]; then
    echo "  drift $1: got '$2', expected '$3'"
    drifts=$((drifts + 1))
  else
    echo "  FAIL  $1: got '$2', expected '$3'"
    fails=$((fails + 1))
  fi
}

must() {  # must <what> <got> <expected>: a result that the exercises need on any image
  n_must=$((n_must + 1))
  if [ "$2" == "$3" ]; then
    echo "  ok    $1: $2"
  else
    echo "  FAIL  $1: got '$2', expected '$3'"
    fails=$((fails + 1))
  fi
}

full() {  # full: false only under CHECK_MODE=regression, which skips the long runs of variants
  [ "$CHECK_MODE" != regression ]
}

skip() {  # skip <what>: a part that CHECK_MODE=regression leaves out
  echo "  skip  $1 (CHECK_MODE=regression)"
}

lint() {  # lint <files>: count of Verilator -Wall warnings and errors, "failed" if it stops without one
  local out rc n
  out=$(verilator --lint-only -Wall "$@" 2>&1)
  rc=$?
  n=$(printf '%s\n' "$out" | grep -c -E '%Warning|%Error')
  if [ "$rc" -ne 0 ] && [ "$n" -eq 0 ]; then
    echo failed
  else
    echo "$n"
  fi
}

finish() {  # finish: print the summary, exit with 1 if a check failed
  echo
  if [ "$CHECK_MODE" == book ]; then
    local total=$((n_check + n_must))
    if [ "$fails" -eq 0 ]; then
      echo "PASS: all $total results match the chapter"
    else
      echo "FAIL: $fails of $total results differ from the chapter"
      exit 1
    fi
  elif [ "$fails" -eq 0 ]; then
    echo "PASS: all $n_must must checks passed, $drifts of $n_check quoted values drifted"
  else
    echo "FAIL: $fails of $n_must must checks failed, $drifts of $n_check quoted values drifted"
    exit 1
  fi
}
