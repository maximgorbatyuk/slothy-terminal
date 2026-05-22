#!/bin/bash

# Shared colorized-output helpers for the SlothyTerminal release scripts.
#
# Source from another script like:
#   source "$(dirname "$0")/lib/colors.sh"
#
# Colors auto-disable when stdout is not a TTY (e.g. piped to tee/log file)
# so the captured log stays clean. Set FORCE_COLOR=1 to keep colors even
# when piped — useful for ./script.sh 2>&1 | tee log.txt where you want
# to scroll back with `less -R log.txt`.

if [ -t 1 ] || [ "${FORCE_COLOR:-0}" = "1" ]; then
  C_RESET='\033[0m'
  C_HEAD='\033[1;36m'    ## bold cyan  — banners
  C_STEP='\033[1;34m'    ## bold blue  — step / milestone titles
  C_OK='\033[0;32m'      ## green      — successes
  C_WARN='\033[0;33m'    ## yellow     — warnings
  C_ERR='\033[1;31m'     ## bold red   — errors
  C_DIM='\033[2m'        ## dim        — verbose output
else
  C_RESET=''
  C_HEAD=''
  C_STEP=''
  C_OK=''
  C_WARN=''
  C_ERR=''
  C_DIM=''
fi

## header "Step N: Title" — banner block, separates major phases.
header() {
  printf '\n'
  printf '%b===========================================%b\n' "$C_HEAD" "$C_RESET"
  printf '%b  %s%b\n' "$C_HEAD" "$1" "$C_RESET"
  printf '%b===========================================%b\n' "$C_HEAD" "$C_RESET"
  printf '\n'
}

## step "title" — within-phase milestone (e.g. "[2/8] Creating archive").
step() {
  printf '%b▸ %s%b\n' "$C_STEP" "$1" "$C_RESET"
}

## ok "title" — success / completion marker.
ok() {
  printf '%b✓ %s%b\n' "$C_OK" "$1" "$C_RESET"
}

## info "text" — neutral status (default color so it doesn't compete).
info() {
  printf '%s\n' "$1"
}

## warn "text" — surface but don't halt.
warn() {
  printf '%b⚠ %s%b\n' "$C_WARN" "$1" "$C_RESET"
}

## err "text" — error message, goes to stderr.
err() {
  printf '%b✗ %s%b\n' "$C_ERR" "$1" "$C_RESET" >&2
}

## Pipe verbose output through this to dim each line.
## Usage: noisy_command 2>&1 | dim_lines
## Skips wrapping when colors are disabled so logs stay clean.
dim_lines() {
  if [ -n "$C_DIM" ]; then
    ## Wrap each line in dim..reset. The trailing reset prevents the dim
    ## escape from bleeding into anything that follows the piped block.
    sed -u "s/^/$(printf '%b' "$C_DIM")/;s/\$/$(printf '%b' "$C_RESET")/"
  else
    cat
  fi
}
