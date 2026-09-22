# Granular

Granular is a native macOS app for giving still images a more photographic, film-like finish—quickly. It combines film tone, light shaping, lens diffusion, halation, and light-responsive grain in a focused workflow built for macOS.

## What it does

- **Instant processing** — drop images onto Granular and process them immediately with the selected recipe.
- **Live editing** — open an image, fine-tune the look with a live preview, inspect details at any zoom level, compare original and processed output, then export.
- **Watched folders** — automatically process new images placed in a selected folder.
- **Recipes** — start with a small set of built-in looks, then save, rename, update, and delete your own.
- **Film tone** — choose from curated color stocks and adjust exposure, contrast, saturation, vibrance, and warmth with a photographic response.
- **Optical and finishing effects** — shape the frame with vignette, imperfect edge-focused lens blur and prismatic RGB separation, Black Pro-Mist-style diffusion, restrained halation, detail-preserving landscape glow, and signal-dependent grain.

Granular processes JPEG, HEIC, PNG, and TIFF images. The rendering order is fixed:

`film tone → spotlight/vignette → lens blur → diffusion → halation → landscape glow → grain`

## Requirements

- macOS 26 or later
- Apple Silicon or an Intel Mac capable of running macOS 26

## Build from source

Granular currently ships as source. Building requires the full Xcode 26 application, including Icon Composer.

The easiest route is to double-click **Build Granular.command** in Finder. It creates the app at `dist/Granular.app` and reveals it when finished.

Or build from Terminal:

```sh
swift test
./Scripts/build-app.sh
open -R dist/Granular.app
```

Detailed setup and troubleshooting instructions are in [BUILDING.md](BUILDING.md).

## Notes on distribution

Local builds are ad-hoc signed for use on the Mac that builds them. A broadly distributable macOS release will require Developer ID signing and Apple notarization.

## Credits and attribution

The bundled color-stock cubes are selected from [ComfyUI-Darkroom](https://github.com/jeremieLouvaert/ComfyUI-Darkroom) and its MIT-licensed spectral film model. See [THIRD_PARTY_NOTICES.txt](Resources/THIRD_PARTY_NOTICES.txt) for details.

Film-stock and manufacturer names are descriptive only. Granular is not endorsed by or affiliated with their trademark owners.

## Further reading

The product, interaction, imaging, validation, and delivery rationale lives in [docs/PRODUCT_PLAN.md](docs/PRODUCT_PLAN.md).
