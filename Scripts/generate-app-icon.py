#!/usr/bin/env python3
"""Generates AppIcon.icon, Granular's Icon Composer icon.

A 35mm film canister stands in the left of the icon, seen straight on, with its film
leader coming out of the light-trap lip. The canister runs off the icon's left, top and
bottom edges, so the icon's own shape trims it, and its caps are as thin as a real
tin's. Its lighting is computed from a cylinder so it reads round, the background is
aluminum in light mode and magnesium in dark, and Clear/Tinted use their own
high-contrast monochrome artwork.

Run it after changing anything below, then build with Scripts/build-app.sh.
"""

import json, math, os, shutil


# ---------- colour: sRGB hex -> Display P3 string ----------
def _lin(c): return c/12.92 if c <= 0.04045 else ((c+0.055)/1.055)**2.4
def _gam(c):
    c = max(0.0, min(1.0, c))
    return 12.92*c if c <= 0.0031308 else 1.055*c**(1/2.4)-0.055
M = [[0.8224621, 0.1775380, 0.0000000],
     [0.0331941, 0.9668058, 0.0000000],
     [0.0170827, 0.0723974, 0.9105199]]   # linear sRGB -> linear Display P3
def p3(hexs, a=1.0):
    h = hexs.lstrip('#'); r, g, b = [_lin(int(h[i:i+2], 16)/255) for i in (0, 2, 4)]
    v = [_gam(M[i][0]*r + M[i][1]*g + M[i][2]*b) for i in range(3)]
    return "display-p3:%.5f,%.5f,%.5f,%.5f" % (v[0], v[1], v[2], a)

def lin(c0, c1, x0, y0, x1, y1):
    return {"linear-gradient": [p3(c0), p3(c1)],
            "orientation": {"start": {"x": x0, "y": y0}, "stop": {"x": x1, "y": y1}}}


def rrect(x, y, w, h, r):
    r = min(r, w/2, h/2)
    if r <= 0:
        return "M%.2f,%.2f h%.2f v%.2f h%.2f z" % (x, y, w, h, -w)
    return ("M%.2f,%.2f h%.2f a%.2f,%.2f 0 0 1 %.2f,%.2f v%.2f a%.2f,%.2f 0 0 1 %.2f,%.2f "
            "h%.2f a%.2f,%.2f 0 0 1 %.2f,%.2f v%.2f a%.2f,%.2f 0 0 1 %.2f,%.2f z" %
            (x+r, y, w-2*r, r, r, r, r, h-2*r, r, r, -r, r, -(w-2*r), r, r, -r, -r, -(h-2*r), r, r, r, -r))

OUT = os.environ.get("ICON_OUT") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "AppIcon.icon")
# Proportions follow a real 35mm canister, which stands 600 wide in the icon's left side.
BODY_R = 600            # canister's right edge; its left, top and bottom run off the icon
CAP_H = 58              # the thin top and bottom caps
CAP_CORNER = 24         # the caps' outer corners down the right side
INSET = 12              # the label sits just inside the caps
LIP_W = 58              # the velvet light-trap lip runs down the canister's right side
PANEL_R, RED_W = 330, 80    # label: a yellow panel, a red stripe, then the black face (as in the app)
FILM_T, FILM_R = 150, 952   # the film leader's top edge (mirrored at the bottom) and its right end

def rgb(h): h = h.lstrip("#"); return [int(h[i:i+2], 16) / 255 for i in (0, 2, 4)]
def hexs(c): return "#%02x%02x%02x" % tuple(round(max(0, min(1, v)) * 255) for v in c)
def mix(a, b, t): return [a[i] + (b[i] - a[i]) * t for i in range(3)]
def smooth(t): t = max(0.0, min(1.0, t)); return t * t * (3 - 2 * t)

def lighting(x):
    """Light falling on a cylinder at x (0 = left silhouette, 1 = right): a wrapped key
    light from the upper left, a narrow specular, and a little reflected light on the right."""
    nx = 2 * x - 1
    nz = math.sqrt(max(0.0, 1 - nx * nx))
    lx, lz = -0.5, 0.866
    diffuse = max(0.0, (nx * lx + nz * lz + 0.25) / 1.25)          # wrap lighting: soft terminator
    hx, hz = lx, lz + 1; hl = math.hypot(hx, hz); hx, hz = hx / hl, hz / hl
    spec = max(0.0, nx * hx + nz * hz) ** 90
    bounce = max(0.0, nx) ** 5 * 0.18
    return diffuse, spec, bounce

def cylinder(gid, dark, base, light, x0=0, x1=BODY_R, steps=48, spec_scale=1.0):
    d, b, l = rgb(dark), rgb(base), rgb(light)
    stops = ""
    for i in range(steps + 1):
        x = i / steps
        diffuse, spec, bounce = lighting(x)
        c = mix(d, b, smooth(diffuse / 0.82)) if diffuse < 0.82 else mix(b, l, smooth((diffuse - 0.82) / 0.18))
        c = mix(c, b, bounce)
        c = mix(c, [1, 1, 1], spec * 0.22 * spec_scale)
        stops += '<stop offset="%.4f" stop-color="%s"/>' % (x, hexs(c))
    return ('<linearGradient id="%s" gradientUnits="userSpaceOnUse" x1="%s" y1="0" x2="%s" y2="0">%s</linearGradient>'
            % (gid, x0, x1, stops))

def svg(defs, body):
    return ('<?xml version="1.0" encoding="UTF-8"?>\n<svg xmlns="http://www.w3.org/2000/svg" '
            'viewBox="0 0 1024 1024"><defs>%s</defs>%s</svg>\n' % (defs, body))

# Palettes: colour, and a high-contrast monochrome set for Clear and Tinted.
COLOR = {
    "yellow": ("#7A3400", "#F3B80C", "#F7CB2C"), "red": ("#5A0E02", "#EE4A1A", "#FF8C62"),
    "black": ("#000000", "#1D1D20", "#55575E"), "cap": ("#0E0E10", "#5A5C63"),
    "film": ("#E8893A", "#C9631F", "#A04A14", "#6E300B"), "lip": "#0c0a09", "lipline": "#2d2622",
}
# Dark mode draws its own near-black backdrop (the fill below is ignored there), so the
# black face, lip and caps are lifted to charcoal and steel to stand clear of it.
DARK = dict(COLOR, black=("#141417", "#3A3C42", "#80838B"), cap=("#2A2B30", "#B4B7BE"),
            lip="#2B2725", lipline="#4D4540")
# Four clear values: bright canister, mid film, black face and lip, dark cap.
MONO = {
    "yellow": ("#5C5C5C", "#EDEDED", "#FFFFFF"), "red": ("#2A2A2A", "#5E5E5E", "#8A8A8A"),
    "black": ("#000000", "#0A0A0A", "#3A3A3A"), "cap": ("#030303", "#9A9A9A"),
    "film": ("#A2A2A2", "#929292", "#828282", "#727272"), "lip": "#000000", "lipline": "#141414",
}

def outline(right):
    """The canister's silhouette: square on the left (the icon trims it), rounded caps on the right."""
    return rrect(-80, 0, right + 80, 1024, CAP_CORNER)

def body_svg(P):
    defs = ('<clipPath id="b"><path d="%s"/></clipPath>' % outline(BODY_R - INSET)
            + "".join(cylinder(k, *P[k]) for k in ("yellow", "red", "black")))
    parts = [(-80, PANEL_R + 80, "yellow"), (PANEL_R, RED_W, "red"), (PANEL_R + RED_W, BODY_R, "black")]
    label = "".join('<rect x="%s" y="-80" width="%s" height="1200" fill="url(#%s)"/>' % (x, w, g) for x, w, g in parts)
    x, w = BODY_R - INSET - LIP_W, LIP_W + INSET
    lines = "".join('<rect x="%s" y="%s" width="%s" height="3" fill="%s"/>' % (x, y, w, P["lipline"]) for y in range(0, 1024, 9))
    lip = ('<rect x="%s" y="-80" width="%s" height="1200" fill="%s"/>%s'
           '<rect x="%s" y="-80" width="%s" height="1200" fill="url(#ls)"/>' % (x, w, P["lip"], lines, x, w))
    # The top cap stands proud of the label and shades it.
    shade = '<rect x="-80" y="%s" width="%s" height="42" fill="url(#sh)"/>' % (CAP_H - 2, BODY_R + 80)
    defs += ('<linearGradient id="ls" gradientUnits="userSpaceOnUse" x1="%s" y1="0" x2="%s" y2="0">'
             '<stop offset="0" stop-color="#fff" stop-opacity="0.12"/><stop offset="1" stop-color="#000" stop-opacity="0.6"/></linearGradient>'
             '<linearGradient id="sh" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#000" stop-opacity="0.45"/>'
             '<stop offset="1" stop-color="#000" stop-opacity="0"/></linearGradient>' % (x, x + LIP_W))
    return svg(defs, '<g clip-path="url(#b)">%s%s%s</g>' % (label, lip, shade))

def cap_svg(P):
    """Thin, smooth, glossy caps, standing just proud of the body, with a lit rim on each."""
    c = P["cap"]
    defs = ('<clipPath id="o"><path d="%s"/></clipPath>' % outline(BODY_R)
            + cylinder("m", c[0], hexs(mix(rgb(c[0]), rgb(c[1]), 0.45)), c[1]) +
            '<linearGradient id="v" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity="0.10"/>'
            '<stop offset="1" stop-color="#000" stop-opacity="0.35"/></linearGradient>')
    top, bottom = 1024 - CAP_H, 1104
    body = ('<g clip-path="url(#o)">'
            '<rect x="-80" y="-80" width="%s" height="%s" fill="url(#m)"/>'
            '<rect x="-80" y="-80" width="%s" height="%s" fill="url(#v)"/>'
            '<rect x="-80" y="%s" width="%s" height="%s" fill="url(#m)"/>'
            '<rect x="-80" y="%s" width="%s" height="4" fill="#fff" fill-opacity="0.22"/>'
            '<rect x="-80" y="%s" width="%s" height="4" fill="#fff" fill-opacity="0.14"/></g>'
            % (BODY_R + 80, CAP_H + 80, BODY_R + 80, CAP_H + 80, top, BODY_R + 80, bottom - top,
               CAP_H - 5, BODY_R + 80, top + 1, BODY_R + 80))
    return svg(defs, body)

def film_svg(P):
    """The leader, as tall as the label, cut to half height at its end."""
    x0 = BODY_R - INSET - LIP_W - 10
    t, b = FILM_T, 1024 - FILM_T
    tongue_b = t + (b - t) * 0.5
    xs, xe, rr = FILM_R - 182, FILM_R, 70
    d = ("M%s,%s H%s A%s,%s 0 0 1 %s,%s V%s A%s,%s 0 0 1 %s,%s H%s C%s,%s %s,%s %s,%s V%s H%s Z"
         % (x0, t, xe - rr, rr, rr, xe, t + rr, tongue_b - rr * 0.6, rr * 0.6, rr * 0.6, xe - rr * 0.6, tongue_b,
            xs + 150, xs + 60, tongue_b, xs + 40, b, xs - 40, b, b, x0))
    # Real 35mm perforations: taller than they are wide.
    ph, pw, pitch = 64, 42, 96
    x = BODY_R + 26
    while x + pw < xe - 30:
        d += rrect(x, t + 26, pw, ph, 10)
        if x + pw < xs - 20:
            d += rrect(x, b - 26 - ph, pw, ph, 10)
        x += pitch
    f = P["film"]
    defs = ('<linearGradient id="f" gradientUnits="userSpaceOnUse" x1="0" y1="%s" x2="0" y2="%s">'
            '<stop offset="0" stop-color="%s"/><stop offset="0.15" stop-color="%s"/>'
            '<stop offset="0.6" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient>' % ((t, b) + f) +
            '<linearGradient id="g" gradientUnits="userSpaceOnUse" x1="%s" y1="0" x2="1000" y2="0">'
            '<stop offset="0" stop-color="#000" stop-opacity="0.6"/><stop offset="0.2" stop-color="#000" stop-opacity="0"/>'
            '<stop offset="0.6" stop-color="#FFD2A8" stop-opacity="0.18"/><stop offset="0.8" stop-color="#FFD2A8" stop-opacity="0"/></linearGradient>' % x0)
    return svg(defs, '<path fill="url(#f)" fill-rule="evenodd" d="%s"/><path fill="url(#g)" fill-rule="evenodd" d="%s"/>' % (d, d))

def layer(name, dark=False):
    # No plain "image-name": when it's present, Icon Composer ignores the specializations.
    specs = [{"value": name + ".svg"}]
    if dark:
        specs.append({"appearance": "dark", "value": name + "-dark.svg"})
    specs.append({"appearance": "tinted", "value": name + "-mono.svg"})
    return {"name": name, "image-name-specializations": specs}
def group(name, layers, translucency=0.0, shadow="neutral"):
    return {"name": name, "layers": layers, "shadow": {"kind": shadow, "opacity": 0.5}, "specular": True,
            "translucency": {"enabled": translucency > 0, "value": translucency}}

shutil.rmtree(OUT, ignore_errors=True); os.makedirs(OUT + "/Assets")
for name, build in {"cap": cap_svg, "body": body_svg, "film": film_svg}.items():
    open("%s/Assets/%s.svg" % (OUT, name), "w").write(build(COLOR))
    open("%s/Assets/%s-mono.svg" % (OUT, name), "w").write(build(MONO))
    if name != "film":
        open("%s/Assets/%s-dark.svg" % (OUT, name), "w").write(build(DARK))

aluminum = lin("#E2E4E6", "#AEB2B6", 0.2, 0.0, 0.8, 1.0)     # bead-blasted aluminum body
magnesium = lin("#26272A", "#0B0C0D", 0.2, 0.0, 0.8, 1.0)    # dark magnesium body
doc = {
    "fill": aluminum,
    "fill-specializations": [{"value": aluminum}, {"appearance": "dark", "value": magnesium}],
    "groups": [
        group("Canister", [layer("cap", dark=True), layer("body", dark=True)]),
        group("Film", [layer("film")], translucency=0.1, shadow="layer-color"),
    ],
    "supported-platforms": {"circles": ["watchOS"], "squares": "shared"},
}
open(OUT + "/icon.json", "w").write(json.dumps(doc, indent=2))
print(os.path.normpath(OUT))
