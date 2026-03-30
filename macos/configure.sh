#!/bin/bash
# Claude Tap - Configure wrapper
# Resolves symlinks and runs install.sh --reconfigure

SELF="$0"
while [ -L "$SELF" ]; do
    DIR="$(cd "$(dirname "$SELF")" && pwd)"
    SELF="$(readlink "$SELF")"
    [[ "$SELF" != /* ]] && SELF="$DIR/$SELF"
done
SCRIPT_DIR="$(cd "$(dirname "$SELF")" && pwd)"

exec "$SCRIPT_DIR/install.sh" --reconfigure
