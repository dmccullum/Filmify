#!/usr/bin/env python3
"""Generates AppIcon.icon, Granular's Icon Composer icon.

The top of a 35mm film canister fills the icon: its left edge and ribbed cap are the
icon's left and top edges, and a sliver of film comes out of the light-trap lip. The
canister's lighting is computed from a cylinder so it reads round, the background is
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

YELLOW, YELLOW_D, RED, INK, CAP, CAP_L = "#F5BE12", "#D99A06", "#E2471B", "#161616", "#232326", "#3A3B3F"
FILM, FILM_D, BASE, BASE_D, STEEL, STEEL_D = "#D06A22", "#9C4613", "#3B281D", "#24180F", "#C9CDD1", "#7D8287"

def rrect(x, y, w, h, r):
    r = min(r, w/2, h/2)
    if r <= 0:
        return "M%.2f,%.2f h%.2f v%.2f h%.2f z" % (x, y, w, h, -w)
    return ("M%.2f,%.2f h%.2f a%.2f,%.2f 0 0 1 %.2f,%.2f v%.2f a%.2f,%.2f 0 0 1 %.2f,%.2f "
            "h%.2f a%.2f,%.2f 0 0 1 %.2f,%.2f v%.2f a%.2f,%.2f 0 0 1 %.2f,%.2f z" %
            (x+r, y, w-2*r, r, r, r, r, h-2*r, r, r, -r, r, -(w-2*r), r, r, -r, -r, -(h-2*r), r, r, r, -r))

OUT = os.environ.get("ICON_OUT") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "AppIcon.icon")
# Proportions measured from a real 35mm canister, scaled so it is 700 wide.
BODY_R = 700            # canister's right edge; its left edge is the icon's
CAP_H = 78              # thin top cap, flush with the icon's top edge
LIP_W = 96              # the velvet light-trap lip runs down the canister's right side
FILM_T = CAP_H + 8      # the film is as tall as the body, its top nearly flush with it
PANEL_R = 300           # "split" label: coloured panel, then a dark face (as in the app)
LABEL = os.environ.get("ICON_LABEL", "split")
RED_W = int(os.environ.get("ICON_RED") or (56 if LABEL == "split" else 22))  # the red accent stripe

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

def overlay(gid, x0=0, x1=BODY_R, steps=40, strength=1.0):
    """The same lighting as black/white alpha, for textured parts like the ribbed cap."""
    stops = ""
    for i in range(steps + 1):
        x = i / steps
        diffuse, spec, bounce = lighting(x)
        v = diffuse - 0.7 + bounce + spec * 0.6
        color, alpha = ("#fff", min(0.3, v * 0.9)) if v > 0 else ("#000", min(0.8, -v * 1.2))
        stops += '<stop offset="%.4f" stop-color="%s" stop-opacity="%.3f"/>' % (x, color, alpha * strength)
    return ('<linearGradient id="%s" gradientUnits="userSpaceOnUse" x1="%s" y1="0" x2="%s" y2="0">%s</linearGradient>'
            % (gid, x0, x1, stops))

def svg(defs, body):
    return ('<?xml version="1.0" encoding="UTF-8"?>\n<svg xmlns="http://www.w3.org/2000/svg" '
            'viewBox="0 0 1024 1024"><defs>%s</defs>%s</svg>\n' % (defs, body))

# Palettes: colour, and a high-contrast monochrome set for Clear and Tinted.
COLOR = {
    "yellow": ("#7A3400", "#FFC20A", "#FFDF7A"), "red": ("#5A0E02", "#EE4A1A", "#FF8C62"),
    "black": ("#000000", "#1D1D20", "#55575E"), "cap": ("#0E0E10", "#4E5057"),
    "film": ("#8A4A1C", "#6A3413", "#4A220B", "#2A1206"), "lip": "#0c0a09", "lipline": "#2d2622",
}
# Four clear values: bright canister, mid film, black face and lip, dark cap.
MONO = {
    "yellow": ("#5C5C5C", "#EDEDED", "#FFFFFF"), "red": ("#2A2A2A", "#5E5E5E", "#8A8A8A"),
    "black": ("#000000", "#0A0A0A", "#3A3A3A"), "cap": ("#030303", "#9A9A9A"),
    "film": ("#A2A2A2", "#929292", "#828282", "#727272"), "lip": "#000000", "lipline": "#141414",
}

def body_svg(P):
    x0, top = -60, CAP_H - 6
    defs = "".join(cylinder(k, *P[k]) for k in ("yellow", "red", "black"))
    if LABEL == "split":
        # Coloured panel, a thin accent, then the dark face, as on the app's canisters.
        parts = [(x0, PANEL_R - x0, "yellow"), (PANEL_R, RED_W, "red"), (PANEL_R + RED_W, BODY_R - PANEL_R - RED_W, "black")]
        b = "".join('<rect x="%s" y="%s" width="%s" height="1200" fill="url(#%s)"/>' % (x, top, w, g) for x, w, g in parts)
    else:
        w = BODY_R - x0
        bands = [(top, 96, "black"), (top + 96, RED_W, "red"), (top + 96 + RED_W, 1100, "yellow")]
        b = "".join('<rect x="%s" y="%s" width="%s" height="%s" fill="url(#%s)"/>' % (x0, y, w, h, g) for y, h, g in bands)
    return svg(defs, b)

def cap_svg(P):
    """A thin, smooth, glossy cap, standing just proud of the body."""
    r = 16
    d = "M-60,-60 H%s V%s a%s,%s 0 0 1 -%s,%s H-60 Z" % (BODY_R, CAP_H - r, r, r, r, r)
    vert = ('<linearGradient id="v" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#000" stop-opacity="0.25"/>'
            '<stop offset="0.7" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity="0.5"/></linearGradient>')
    defs = '<clipPath id="c"><path d="%s"/></clipPath>' % d + overlay("s") + vert
    body = ('<g clip-path="url(#c)"><rect x="-60" y="-60" width="800" height="%s" fill="%s"/>'
            '<rect x="-60" y="-60" width="800" height="%s" fill="url(#s)"/>'
            '<rect x="-60" y="-60" width="800" height="%s" fill="url(#v)"/>'
            '<rect x="-60" y="%s" width="800" height="3" fill="%s" fill-opacity="0.5"/></g>'
            % (CAP_H + 70, P["cap"][0], CAP_H + 70, CAP_H + 70, CAP_H - 9, P["cap"][1]))
    return svg(defs, body)

def lip_svg(P):
    x, y, w = BODY_R - LIP_W, CAP_H - 6, LIP_W + 10
    h = 1100 - y
    lines = "".join('<rect x="%s" y="%s" width="%s" height="3" fill="%s"/>' % (x, yy, w, P["lipline"]) for yy in range(y + 10, 1060, 9))
    defs = ('<clipPath id="l"><path d="%s"/></clipPath>' % rrect(x, y, w, h, 18) +
            '<linearGradient id="ls" gradientUnits="userSpaceOnUse" x1="%s" y1="0" x2="%s" y2="0">'
            '<stop offset="0" stop-color="#fff" stop-opacity="0.1"/><stop offset="1" stop-color="#000" stop-opacity="0.7"/></linearGradient>' % (x, x + w))
    return svg(defs, '<g clip-path="url(#l)"><rect x="%s" y="%s" width="%s" height="%s" fill="%s"/>%s'
                     '<rect x="%s" y="%s" width="%s" height="%s" fill="url(#ls)"/></g>' % (x, y, w, h, P["lip"], lines, x, y, w, h))

def film_svg(P):
    x0 = BODY_R - LIP_W / 2
    d = rrect(x0, FILM_T, 1200 - x0, 1200 - FILM_T, 0)
    # Real 35mm perforations: taller than they are wide, 4.75 mm apart.
    x = BODY_R + 30
    while x < 1100:
        d += rrect(x, FILM_T + 50, 60, 96, 12); x += 146
    f = P["film"]
    defs = ('<linearGradient id="f" gradientUnits="userSpaceOnUse" x1="0" y1="%s" x2="0" y2="1024">'
            '<stop offset="0" stop-color="%s"/><stop offset="0.12" stop-color="%s"/>'
            '<stop offset="0.55" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient>' % ((FILM_T,) + f) +
            '<linearGradient id="g" gradientUnits="userSpaceOnUse" x1="%s" y1="0" x2="1024" y2="0">'
            '<stop offset="0" stop-color="#000" stop-opacity="0.6"/><stop offset="0.25" stop-color="#000" stop-opacity="0"/>'
            '<stop offset="0.55" stop-color="#FFD2A8" stop-opacity="0.16"/><stop offset="0.7" stop-color="#FFD2A8" stop-opacity="0"/></linearGradient>' % (BODY_R - LIP_W / 2))
    return svg(defs, '<path fill="url(#f)" fill-rule="evenodd" d="%s"/><path fill="url(#g)" fill-rule="evenodd" d="%s"/>' % (d, d))

def layer(name):
    # No plain "image-name": when it's present, Icon Composer ignores the specializations.
    return {"name": name,
            "image-name-specializations": [{"value": name + ".svg"}, {"appearance": "tinted", "value": name + "-mono.svg"}]}
def group(name, layers, translucency=0.0, shadow="neutral"):
    return {"name": name, "layers": layers, "shadow": {"kind": shadow, "opacity": 0.5}, "specular": True,
            "translucency": {"enabled": translucency > 0, "value": translucency}}

shutil.rmtree(OUT, ignore_errors=True); os.makedirs(OUT + "/Assets")
for name, build in {"cap": cap_svg, "body": body_svg, "lip": lip_svg, "film": film_svg}.items():
    open("%s/Assets/%s.svg" % (OUT, name), "w").write(build(COLOR))
    open("%s/Assets/%s-mono.svg" % (OUT, name), "w").write(build(MONO))

aluminum = lin("#E2E4E6", "#AEB2B6", 0.2, 0.0, 0.8, 1.0)     # bead-blasted aluminum body
magnesium = lin("#26272A", "#0B0C0D", 0.2, 0.0, 0.8, 1.0)    # dark magnesium body
doc = {
    "fill": aluminum,
    "fill-specializations": [{"value": aluminum}, {"appearance": "dark", "value": magnesium}],
    "groups": [
        group("Cap", [layer("cap")]),
        group("Canister", [layer("lip"), layer("body")]),
        group("Film", [layer("film")], translucency=0.1, shadow="layer-color"),
    ],
    "supported-platforms": {"circles": ["watchOS"], "squares": "shared"},
}
open(OUT + "/icon.json", "w").write(json.dumps(doc, indent=2))
print(os.path.normpath(OUT))
