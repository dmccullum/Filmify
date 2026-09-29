#!/bin/zsh
# Regenerates Sources/GranularCore/FilmStocks with a pinned spectral_film_lut.
# Usage: ./Scripts/bake-film-stocks.sh --all | --name portra_400 | --list-films
set -euo pipefail

ROOT="${0:A:h:h}"
VENV="$ROOT/.build/film-stock-venv"
VERSION="0.18.2"

PYTHON=""
for candidate in python3.14 python3.13 python3.12 python3.11; do
    if command -v "$candidate" >/dev/null; then
        PYTHON="$(command -v "$candidate")"
        break
    fi
done
if [[ -z "$PYTHON" ]]; then
    echo "spectral_film_lut needs Python 3.11 or later (for example: brew install python@3.12)." >&2
    exit 1
fi

if [[ ! -x "$VENV/bin/python" ]]; then
    "$PYTHON" -m venv "$VENV"
fi
if ! "$VENV/bin/python" -m pip show spectral_film_lut 2>/dev/null | grep -q "^Version: $VERSION$"; then
    "$VENV/bin/python" -m pip install --quiet "spectral_film_lut==$VERSION"
fi

exec "$VENV/bin/python" "$ROOT/Scripts/bake-film-stocks.py" "$@"
