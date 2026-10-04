# Halation accuracy review

Reviewed 2026-10-03. The renderer is a useful, normalized RGB approximation of film-layer scattering. It is not a spectrally calibrated simulation of a particular negative, backing, or scan process.

## Physical basis

Kodak describes halation as secondary exposure from light returning through the emulsion after reflection at the film support. Its color-negative layer diagram places the red-sensitive record nearest the support, below green and the yellow filter/blue record. This supports preferential red scattering, a weaker green contribution, and negligible blue in a simplified color-negative model. Layer arrangements differ in other film types; this is not a universal film model.

Sources:

- [Kodak: Essential Reference Guide for Filmmakers, film structure and antihalation](https://www.kodak.com/content/products-brochures/Film/kodak-essential-reference-guide-for-filmmakers.pdf)
- [Kodak: Processing Motion Picture Films, Module 7, Figure 7-1](https://www.kodak.com/content/products-brochures/Film/Processing-KODAK-Motion-Picture-Films-Module-7.pdf)
- [Video Village: Filmbox halation controls](https://videovillage.com/learn/filmbox/full-guide/negative/halation) distinguishes compact emulsion scattering from the larger aura and relates scale to film gauge.
- [Dehancer: Halation](https://www.dehancer.com/learn/article/halation) describes weaker lights as valid contributors and green sensitivity as a hue control. These software references inform behavior, not measured physical constants.

The existing continuous, channel-selective convolution is a good foundation. A highlight threshold or edge detector is unnecessary: bright sources naturally send more exposure into their surroundings. The application's preview and export contexts use extended-linear Rec.2020, which is appropriate for this light mixing. Display-encoded RGB would not be.

## Corrections on this branch

1. **Separate spatial responses.** Previously red and green used exactly the same normalized point-spread function (PSF), so the halo's red/green balance could not evolve with distance on a white edge. Red retains the three-scale tail. Green now uses a compact mixture: 80% at 0.55 times the base radius and 20% at the base radius. This creates a warmer inner fringe and a predominantly red outer tail. These ratios are an explicit approximation; stock-specific measurements are still needed to calibrate them. One additional Gaussian is evaluated per halation pass.
2. **Scale with image dimensions.** Removed the 0.75-pixel base-radius floor. It overrode the image-relative model at small preview sizes and widened all three scales. The hard-edge regression at minimum Spill Radius previously differed by 0.2044 summed linear-red units outside the two-pixel edge band; it now meets a 0.006 absolute tolerance. Subpixel sampling still prevents exact equality around the immediate edge.
3. **Handle alpha as coverage.** Blur premultiplied RGB and alpha together, normalize each channel's PSF by its filtered coverage, then repremultiply with the original alpha. A transparent cutout no longer develops cyan edges or stores halo RGB outside its alpha. Coverage normalization also reduces constant-field drift from Gaussian intermediate precision. This preserves coverage rather than expanding the cutout to contain an external glow.
4. **Bound imported settings.** Spatial and color parameters are clamped to their UI ranges before use. Previously invalid imported values could change the Gaussian radii and extrapolate the color controls.

Preset values, the Amount mapping, the progressive second pass above 0.5, and the established pipeline order remain unchanged. Opaque full-resolution red spread remains essentially the existing model. Green becomes more compact; small previews and transparent assets intentionally change.

## Meaning of energy preservation

For opaque images, each record follows:

```text
O[c] = (1 - s[c]) I[c] + s[c] (K[c] * I[c])
```

This is a positive normalized PSF. Uniform colors remain constant and total channel energy is preserved for isolated sources sufficiently far from the frame boundary. Alpha coverage normalization is not globally energy-conserving on cutouts. Edge clamping assumes the image continues beyond the frame; it is not an assertion of flux conservation across a finite crop.

Real back-reflection adds secondary exposure. A normalized approximation is defensible after compensating for uniform-field gain:

```text
E[c] = I[c] + q[c] (K[c] * I[c])
O[c] = E[c] / (1 + q[c])
s[c] = q[c] / (1 + q[c])
```

Consequently, the current model's energy conservation is a normalization choice, not a literal claim that real film must remove each scattered photon from the recorded highlight. Narrow highlight cores can become cooler as red is redistributed. At extreme Amount settings this is visible in synthetic fixtures; the upper range is a creative exaggeration, not a physically measured reflectance.

## Remaining limits

- **Film response ordering:** the complete Film Tone/color-stock stage precedes halation. Its nonlinear highlight compression and color transforms can change the exposure that drives scattering. A fuller acquisition model would separate exposure/illumination, optics, film-layer exposure, and the subsequent nonlinear negative/print response. That is a coordinated pipeline and preset recalibration, not a local halation fix. Merely running in linear RGB does not reverse an earlier tone curve.
- **Source limitations:** JPEGs and clipped highlights do not retain the original scene radiance. No halation algorithm can reconstruct that missing exposure reliably. The kernel does preserve supplied HDR values and responds linearly to exposure.
- **Spectral approximation:** Rec.2020 primaries stand in for emulsion records. They are not measured dye sensitivities. The film's spectral response, backing reflectance, base thickness, pressure plate, and development are not modeled. Very saturated halos can also clip in a smaller output gamut.
- **Scale calibration:** radius follows the image's short edge. There is no actual gate size or crop metadata, and there are no measured per-stock PSFs. Virtual-format preset names alone do not establish physical dimensions.
- **Black-and-white:** the halation model is intentionally color-negative-like. A monochrome color stock can still acquire colored fringes; a separate neutral scattering mode would be needed for monochrome-film fidelity.
- **Preview sampling:** removing the radius floor fixes the systematic scale mismatch. Already-downsampled previews still cannot preserve all of the spatial information available during a full-resolution render.

## Verification and visual review

`Tests/GranularCoreTests/HalationTests.swift` exercises:

- Uniform black, gray, white, colored HDR, and partial-alpha fields at several strengths.
- Per-channel energy conservation for an isolated HDR source, finite/nonnegative output, and a broader normalized red halo than green.
- Unchanged blue, no manufactured red/green from blue-only sources, and invariance under image translation.
- Continuous exposure response from dim to HDR sources, with no highlight threshold or HDR clipping.
- Alpha preservation and empty transparent RGB, allowing 0.001 absolute error for Gaussian intermediate precision.
- Preview/export spatial scaling, monotonic hard edges, neutral uniform highlight interiors, and agreement with the production half-float working format.
- Imported-setting bounds.

Generate visual fixtures from the real Core Image renderer:

```sh
HALATION_REVIEW_DIRECTORY=/tmp/halation-review swift test --filter halationReviewFixtures
```

This writes synthetic white/HDR/warm practicals on black and gray, a hard edge, and three repository sample photos. Synthetic strengths are Off, Classic (0.15), Strong (0.5), and Maximum (1); photos use Off, Classic, and Strong. Other effects are disabled. The PNGs are display sRGB, so HDR fixture cores are clipped for display, while numeric tests examine linear float pixels.

The pre-change fixtures were captured before modifying the kernel. Regression tests failed on the original identical channel spread, radius floor, alpha handling, and unclamped controls. Keep the test command as a repeatable review tool; visual plausibility on these images does not establish a measured match to film.

Validation result: `swift test` passed all 132 tests on macOS. The optional fixture run also passed. Synthetic before/after renders and the three sample-photo outputs were inspected: Classic remains restrained; Strong exposes the model's red/cyan edge separation, particularly around windows. No matched real-film reference captures were available for physical calibration. iOS device rendering was not exercised in this review.
