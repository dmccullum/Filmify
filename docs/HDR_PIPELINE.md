# Adaptive HDR processing

HEIC and JPEG exports preserve HDR sources by default. The file contains an
edited SDR base and a newly calculated RGB ISO gain map. `OutputOptions.preserveHDR`
can disable this; the Mac exposes it as “Preserve HDR.” PNG and TIFF exports
use the edited SDR rendition. SDR inputs do not acquire artificial HDR.

## Import and rendering

- A file is HDR when its metadata says so: an ISO or Apple gain map, a PQ/HLG
  color space, or extended-range pixels. Other files are never decoded twice.
- Decode the SDR rendition with Core Image. For PQ/HLG inputs without an SDR
  base, request Apple's HDR-to-SDR tone mapping at import.
- Decode the HDR rendition with ImageIO's explicit HDR decode request. Core
  Image's own decoding sometimes returned the tone-mapped SDR pixels of a PQ
  file when asked for HDR, depending on what had decoded the file before.
- Keep a headroom the decoder reports above 1. Otherwise resolve it with a GPU
  maximum reduction rather than guessing from the file extension.
- Work in extended linear Rec. 2020, with half-float intermediate storage.
- Film Tone grades the SDR rendition, exactly as for an SDR export. The HDR
  rendition is that graded image multiplied by the photo's own HDR-to-SDR
  luminance ratio, so both renditions agree wherever the photo's do, and the
  stock's hue carries into the highlights.
- The ratio's extra light is extended as `1 + (ratio^shoulder - 1) * 2^exposure`,
  with a gentle shoulder of `1 / (1 + 0.15 * stockAmount)`. It is a creative
  film highlight extension, not a simulation of Apple's camera exposure
  algorithm. Negative exposure pulls highlights back toward reference white.
- The SDR exposure curve keeps white fixed, so it can't be extended past 1 by
  itself. An earlier design graded HDR pixels after scaling each down to white;
  its slope jumped about 40× at white at +2 EV, which showed as a hard edge where
  highlights crossed reference white. Grading the smooth SDR rendition avoids
  the boundary. `hdrToneStaysSmoothThroughReferenceWhite` guards this.
- Spatial effects run on each rendition. Halation remains linear in light;
  landscape glow avoids forcing extended colored highlights toward SDR white.
  Grain uses the same seed and image geometry for both renditions.

## Preview and export

Previews are HDR only when the export keeps HDR (HEIC or JPEG with Preserve HDR
on) and the screen reports HDR headroom. Otherwise the preview, the original
shown for comparison and the stock thumbnails all render from the SDR
rendition, which is the image an SDR export or SDR screen shows. Thumbnails of
files decode as half floats only on HDR screens.

Live HDR previews render both renditions' sources at preview size, then make
extended linear Display P3 half-float CGImages. Recalculate their headroom after
all effects and let SwiftUI/UIKit adapt to display headroom. An explicit
`CIAreaMaximum` reduction measures peak linear Rec. 2020 components. The OS
statistics API reported headroom 1 for rendered iPhone photographs despite
pixel values above 3, which caused gain-map encoding to be omitted; the explicit
reduction preserves those highlights and is regression-tested.

On an HDR screen at reduced headroom, the live preview uses the system's tone
mapping of the edited HDR bitmap, while the saved file adapts between its SDR
base and gain map. A paired preview compositor could close this remaining gap
without introducing encoding latency into every slider update.

For export, resize both finished renditions identically and render the HDR one
once into a half-float bitmap. Measuring its peak and encoding it each read that
bitmap, rather than rendering every effect again. Then write with
`CIContext.writeHEIFRepresentation` or `writeJPEGRepresentation`, using `.hdrImage`
and `.hdrGainMapAsRGB`. The source gain map is never copied into the edited
file. The base uses an SDR color space; PQ/HLG source profiles are not reused on
its 8-bit pixels. Preserve ordinary photo metadata, normalize
orientation/dimensions, honor GPS removal, and discard stale Apple maker
metadata. Files are written to a temporary sibling and then moved/replaced using
the existing export behavior.

## Verification

`HDRTests.swift` covers bounded SDR appearance, every stock's HDR highlight
separation at negative and positive exposure, smoothness through reference
white, monochrome neutrality, floating point preview headroom, SDR previews
matching SDR exports, optical effects, ISO gain-map round trips for HEIC and
JPEG, SDR/HDR pixel agreement, resized dimensions, EXIF/GPS behavior, PQ input,
metadata-only HDR detection, headroom resolution and SDR opt-out.

The optional `hdrUserPhotoReview` test reads images from
`GRANULAR_HDR_REVIEW_INPUT`, renders review HEICs and SDR PNGs into
`GRANULAR_HDR_REVIEW_OUTPUT`, and reports source/output headroom and gain maps.
Personal photographs and generated review files stay outside the repository.

The supplied original iPhone HEICs exercise ISO gain maps and files carrying
both ISO and Apple gain maps. On-device acceptance still requires an HDR
screen: compare Photos and Granular, check skin and colored highlights, vary
screen brightness/headroom, and inspect the SDR fallback. Synthetic round trips
verify encoding and processing but cannot establish a visual match on an iPhone.

Reference: [Apple — Use HDR for dynamic image experiences in your app](https://developer.apple.com/videos/play/wwdc2024/10177/).
