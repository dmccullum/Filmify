"""Bake Granular's film-stock cubes with spectral_film_lut.

Each stock is a camera film paired with one sensible default print for its
family. The cubes take display-referred sRGB and return display-referred sRGB,
which is what FilmRenderer's color-stock bridge expects. Every bake solves a
small exposure compensation so 18% gray stays at 18% gray; the renderer, not
the cube, decides how much of each stock's density curve reaches the image.

Run through Scripts/bake-film-stocks.sh, which prepares a pinned environment.
"""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

import colour
import numpy as np
import spectral_film_lut
from spectral_film_lut.film_spectral import FilmSpectral
from spectral_film_lut.utils import create_lut, film_conversion

OUTPUT_DIRECTORY = (
    Path(__file__).resolve().parent.parent / "Sources" / "GranularCore" / "FilmStocks"
)
LUT_SIZE = 33
MIDDLE_GRAY = 0.18

CONVERSION = {
    "input_colorspace": "sRGB",
    "output_gamut": "Rec. 709",
    "gamma_func": "sRGB",
}

# One print per family keeps the choice about the film, not the paper. Slide and
# instant film are viewed directly, so they have no print stage.
FAMILY_PRINTS = {
    "kodak": "Kodak Endura Premier Paper",
    "fuji": "Fuji Crystal Archive DPII",
    "cinema": "Kodak Vision 2383",
    "slide": None,
    "instant": None,
    "bw": "Kodak Polymax Fine-Art Paper Grade 3",
}

# resource name, camera film, family, conversion overrides ("print" replaces
# the family's default print).
#
# A faithful spectral print lands every modern stock close to neutral, so the
# overrides lean each one toward its reputation using the library's own
# exposure white balance (exp_kelvin: higher is warmer), tint (positive is
# greener) and OkLab saturation (sat_adjust).
# Stocks with a fitted FilmCharacter (FilmCharacter.swift) need no cube.
STOCKS = [
    ("vision3_250d", "Kodak Vision3 250D 5207", "cinema", {}),
    # Tungsten film under warm-white light: printed to neutral gray, it keeps
    # the cool cast of an uncorrected night exterior.
    ("vision3_500t", "Kodak Vision3 500T 5219", "cinema", {"exp_kelvin": 4700, "sat_adjust": 0.95}),
    ("eterna_500", "Fuji Eterna 500", "cinema", {"tint": 0.03, "sat_adjust": 0.7}),
]


def load_films() -> dict[str, object]:
    films: dict[str, object] = {}
    for data in spectral_film_lut.FILM_STOCKS:
        films.setdefault(data.name, data)
    return films


def convert(values, negative, print_film, **overrides) -> np.ndarray:
    output = film_conversion(values, negative, print_film, **CONVERSION, **overrides)
    if output.shape[-1] == 1:
        output = np.repeat(output, 3, axis=-1)
    return output


def gray_luminance(negative, print_film, overrides: dict) -> float:
    gray = colour.cctf_encoding(np.full((1, 3), MIDDLE_GRAY), function="sRGB")
    encoded = np.clip(convert(gray, negative, print_film, **overrides), 0, 1)
    linear = colour.cctf_decoding(encoded, function="sRGB")[0]
    return float(np.dot(linear, [0.2126, 0.7152, 0.0722]))


def solve_exposure(negative, print_film, overrides: dict) -> float:
    """Find the exposure compensation, in stops, that returns middle gray."""
    target = np.log2(MIDDLE_GRAY)
    compensation = 0.0
    for _ in range(8):
        settings = {**overrides, "exp_comp": compensation}
        error = np.log2(max(gray_luminance(negative, print_film, settings), 1e-6)) - target
        if abs(error) < 0.01:
            break
        # Film carries roughly half a stop of print density per stop of exposure
        # through the mid-tones; damp the step so steep slide film converges.
        compensation -= error * 0.8
    return round(compensation, 3)


def write_cube(path: Path, table: np.ndarray, header: list[str]) -> None:
    size = table.shape[0]
    lines = [f"# {line}" for line in header]
    lines += [f'TITLE "{path.stem}"', f"LUT_3D_SIZE {size}"]
    clipped = np.clip(table, 0, 1)
    # .cube order: red varies fastest, then green, then blue.
    for blue in range(size):
        for green in range(size):
            for red in range(size):
                r, g, b = clipped[red, green, blue]
                lines.append(f"{r:.6f} {g:.6f} {b:.6f}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def bake(name: str, negative_name: str, family: str, overrides: dict, films) -> None:
    started = time.time()
    overrides = dict(overrides)
    print_name = overrides.pop("print", FAMILY_PRINTS[family])
    negative = FilmSpectral(films[negative_name])
    print_film = FilmSpectral(films[print_name]) if print_name else None

    settings = {**overrides}
    settings["exp_comp"] = solve_exposure(negative, print_film, overrides)

    table = create_lut(
        negative,
        print_film,
        lut_size=LUT_SIZE,
        cube=False,
        **CONVERSION,
        **settings,
    )
    table = np.asarray(table).reshape(LUT_SIZE, LUT_SIZE, LUT_SIZE, 3)

    header = [
        f"Granular film stock: {name}",
        f"Camera film: {negative_name}",
        f"Print: {print_name or 'none (viewed directly)'}",
        f"Generated with spectral_film_lut {spectral_film_lut.__version__} (MIT, Jan Lohse)",
        "Settings: " + ", ".join(f"{k}={v}" for k, v in {**CONVERSION, **settings}.items()),
    ]
    write_cube(OUTPUT_DIRECTORY / f"{name}.cube", table, header)
    print(f"{name:<18} exp_comp {settings['exp_comp']:+.2f}  {time.time() - started:.1f}s")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--all", action="store_true", help="bake every stock")
    group.add_argument("--name", help="bake one stock by resource name")
    group.add_argument("--list-films", action="store_true", help="list library film names")
    args = parser.parse_args(argv)

    films = load_films()
    if args.list_films:
        for name in sorted(films):
            print(name)
        return 0

    stocks = STOCKS if args.all else [s for s in STOCKS if s[0] == args.name]
    if not stocks:
        print(f"Unknown stock: {args.name}", file=sys.stderr)
        return 2

    OUTPUT_DIRECTORY.mkdir(parents=True, exist_ok=True)
    for name, negative_name, family, overrides in stocks:
        bake(name, negative_name, family, overrides, films)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
