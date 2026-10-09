#!/usr/bin/env python3
"""Generates AppIcon.icon, Granular's Icon Composer icon.

A 35mm film canister stands in the left of the icon, seen straight on, with its film
leader coming out of the light-trap lip. The whole canister shows, set within Apple's
icon grid, and its caps are as thin as a real tin's. Its lighting is computed from a cylinder so it reads round, the background is
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
BODY_R = 600            # canister's right edge; its left edge is at 0
CAP_H = 58              # the thin top and bottom caps
CAP_CORNER = 24         # the caps' outer corners down the right side
INSET = 12              # the label sits just inside the caps
LIP_W = 58              # the velvet light-trap lip runs down the canister's right side
PANEL_R, RED_W = 330, 80    # label: a yellow panel, a red stripe, then the black face (as in the app)
CAN_H = 860             # the canister's height, caps included: shorter than the board, for room in the corners
HUB_W, HUB_H = 200, 34  # the spool's hub, standing out of the bottom cap
FILM_T, FILM_R = 136, 952   # the film leader's top edge (mirrored at the bottom) and its right end
# The whole canister and leader are drawn on a board as wide as the leader and as tall as the canister, then scaled into the
# middle of Apple's icon grid so they keep its margins on every side.
ART_W, ART_H = FILM_R, CAN_H     # centred on the canister alone; the hub hangs below
SCALE = 0.773
NUDGE = 16              # the canister outweighs the leader, so the art sits a little right of centre
OFFSET = ((1024 - ART_W * SCALE) / 2 + NUDGE, (1024 - ART_H * SCALE) / 2)

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

def cylinder(gid, dark, base, light, x0=0, x1=BODY_R, steps=48, spec_scale=1.0, spec_shift=0.0):
    d, b, l = rgb(dark), rgb(base), rgb(light)
    stops = ""
    for i in range(steps + 1):
        x = i / steps
        diffuse, _, bounce = lighting(x)
        spec = lighting(x + spec_shift)[1]      # spec_shift slides the highlight left
        c = mix(d, b, smooth(diffuse / 0.82)) if diffuse < 0.82 else mix(b, l, smooth((diffuse - 0.82) / 0.18))
        c = mix(c, b, bounce)
        c = mix(c, [1, 1, 1], spec * 0.22 * spec_scale)
        stops += '<stop offset="%.4f" stop-color="%s"/>' % (x, hexs(c))
    return ('<linearGradient id="%s" gradientUnits="userSpaceOnUse" x1="%s" y1="0" x2="%s" y2="0">%s</linearGradient>'
            % (gid, x0, x1, stops))

def svg(defs, body):
    return ('<?xml version="1.0" encoding="UTF-8"?>\n<svg xmlns="http://www.w3.org/2000/svg" '
            'viewBox="0 0 1024 1024"><defs>%s</defs><g transform="translate(%.2f,%.2f) scale(%s)">%s</g></svg>\n'
            % (defs, OFFSET[0], OFFSET[1], SCALE, body))

# Palettes: colour, and a high-contrast monochrome set for Clear and Tinted.
COLOR = {
    "yellow": ("#7A3400", "#F3B80C", "#F7CB2C"), "red": ("#5A0E02", "#EE4A1A", "#FF8C62"),
    "black": ("#000000", "#1D1D20", "#55575E"), "cap": ("#0E0E10", "#5A5C63"),
    "film": ("#E8893A", "#C9631F", "#A04A14", "#6E300B"), "lip": "#0c0a09", "edge": 0.0, "rim": 0.10,
    "spec_shift": 0.12,     # the wide panel's highlight sits mid-panel, not beside the red stripe
}
# Dark mode draws its own near-black backdrop (the fill below is ignored there). The label
# stays as in light mode, so the black panel and lip meet the backdrop: a brighter rim
# light and a lit rolled edge on the lip keep the canister's right side clear of it. The
# caps turn to chrome, like an old Kodak tin: banded reflections of a bright sky and a
# dark horizon rather than a soft cylinder. The sky's peak is drawn at 0.28 and slid to
# sit exactly over the label's highlight.
DARK = dict(COLOR, lip="#3A3532", edge=0.38, rim=0.22,
            chrome=((0, "#2A2C31"), (0.17, "#4A4E56"), (0.23, "#C9CDD3"), (0.28, "#FFFFFF"),
                    (0.34, "#C3C8CF"), (0.43, "#5E636C"), (0.50, "#2A2C31"), (0.60, "#4E525A"),
                    (0.72, "#80858D"), (0.82, "#8F949B"), (0.93, "#62666E"), (1, "#3E4148")))
# Clear and Tinted read only brightness against a dark backdrop, so the canister is one
# bright shape (its black panel lifted to match), the red stripe its single dark band, the
# lip a black gap, and the leader a second bright shape. Tinted Dark compresses everything
# below white toward the backdrop, so both shapes stay close to white.
MONO = {
    "yellow": ("#8A8A8A", "#F4F4F4", "#FFFFFF"), "red": ("#141414", "#2E2E2E", "#484848"),
    "black": ("#9A9A9A", "#EAEAEA", "#F4F4F4"), "cap": ("#3A3A3A", "#C4C4C4"),
    "film": ("#FFFFFF", "#F6F6F6", "#ECECEC", "#E0E0E0"), "lip": "#000000", "edge": 0.0, "rim": 0.10,
}

def outline(left, right):
    """The canister's silhouette: with rounded caps at each corner."""
    return rrect(left, 0, right - left, CAN_H, CAP_CORNER)

def body_svg(P):
    defs = ('<clipPath id="b"><path d="%s"/></clipPath>' % outline(INSET, BODY_R - INSET)
            + "".join(cylinder(k, *P[k], spec_shift=P.get("spec_shift", 0.0)) for k in ("yellow", "red", "black")))
    parts = [(-80, PANEL_R + 80, "yellow"), (PANEL_R, RED_W, "red"), (PANEL_R + RED_W, BODY_R, "black")]
    label = "".join('<rect x="%s" y="-80" width="%s" height="1200" fill="url(#%s)"/>' % (x, w, g) for x, w, g in parts)
    x, w = BODY_R - INSET - LIP_W, LIP_W + INSET
    # The velvet light trap is matte, sunk in shadow at both sides, with the tin folded
    # over it catching the light on its left and its rolled edge on its right.
    lip = ('<rect x="%s" y="-80" width="%s" height="1200" fill="%s"/>'
           '<rect x="%s" y="-80" width="%s" height="1200" fill="url(#ls)"/>'
           '<rect x="%s" y="-80" width="3" height="1200" fill="#fff" fill-opacity="0.18"/>'
           '<rect x="%s" y="-80" width="5" height="1200" fill="#fff" fill-opacity="%s"/>'
           % (x, w, P["lip"], x, w, x, x + w - 5, P["edge"]))
    # A rim light down the canister's shaded side, so it reads round rather than flat.
    rim = '<rect x="%s" y="-80" width="44" height="1200" fill="url(#rim)"/>' % (x - 44)
    # The top cap stands proud of the label and shades it.
    shade = '<rect x="-80" y="%s" width="%s" height="42" fill="url(#sh)"/>' % (CAP_H - 2, BODY_R + 80)
    defs += ('<linearGradient id="ls" gradientUnits="userSpaceOnUse" x1="%s" y1="0" x2="%s" y2="0">'
             '<stop offset="0" stop-color="#000" stop-opacity="0.35"/><stop offset="0.25" stop-color="#fff" stop-opacity="0.06"/>'
             '<stop offset="1" stop-color="#000" stop-opacity="0.7"/></linearGradient>'
             '<linearGradient id="rim" gradientUnits="userSpaceOnUse" x1="%s" y1="0" x2="%s" y2="0">'
             '<stop offset="0" stop-color="#fff" stop-opacity="0"/><stop offset="0.8" stop-color="#fff" stop-opacity="%s"/>'
             '<stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>'
             '<linearGradient id="sh" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#000" stop-opacity="0.45"/>'
             '<stop offset="1" stop-color="#000" stop-opacity="0"/></linearGradient>' % (x, x + LIP_W, x - 44, x, P["rim"]))
    return svg(defs, '<g clip-path="url(#b)">%s%s%s%s</g>' % (label, rim, lip, shade))

def highlight_x(shift):
    """Where the label's specular peaks, from 0 to 1 across the canister."""
    return max((i / 1000 for i in range(1001)), key=lambda x: lighting(x + shift)[1])

def cap_svg(P):
    """Thin, smooth, glossy caps, standing just proud of the body, with a lit rim on each.
    Painted caps darken toward the top cap's lower edge; chrome caps mirror the same
    sky top and bottom, so they don't."""
    c = P["cap"]
    if "chrome" in P:
        dx = highlight_x(P.get("spec_shift", 0.0)) - 0.28
        stops = "".join('<stop offset="%.4f" stop-color="%s"/>' % (o if o in (0, 1) else o + dx, s) for o, s in P["chrome"])
        metal = ('<linearGradient id="m" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="%s" y2="0">%s</linearGradient>'
                 % (BODY_R, stops))
    else:
        metal = cylinder("m", c[0], hexs(mix(rgb(c[0]), rgb(c[1]), 0.45)), c[1], spec_shift=P.get("spec_shift", 0.0))
    defs = ('<clipPath id="o"><path d="%s"/></clipPath>' % outline(0, BODY_R) + metal +
            '<linearGradient id="v" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity="0.10"/>'
            '<stop offset="1" stop-color="#000" stop-opacity="0.35"/></linearGradient>')
    top, bottom = CAN_H - CAP_H, CAN_H + 80
    # The spool's hub stands out of the bottom cap, centred on the canister, lit as its own small cylinder.
    hx = (BODY_R - HUB_W) / 2
    # The hub is dark plastic even where the caps are chrome.
    defs += cylinder("hub", c[0], hexs(mix(rgb(c[0]), rgb(c[1]), 0.45)), c[1], x0=hx, x1=hx + HUB_W)
    # It sits behind the cap's rim, so it's darker than the cap and shaded deeply where it meets it.
    shape = ('M%s,%s h%s v%s a12,12 0 0 1 -12,12 h%s a12,12 0 0 1 -12,-12 z'
             % (hx, CAN_H - 2, HUB_W, HUB_H - 10, -(HUB_W - 24)))
    hub = ('<path d="%s" fill="url(#hub)"/><path d="%s" fill="#000" fill-opacity="0.38"/>'
           '<rect x="%s" y="%s" width="%s" height="18" fill="url(#hsh)"/>'
           % (shape, shape, hx, CAN_H - 2, HUB_W))
    defs += ('<linearGradient id="hsh" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#000" stop-opacity="0.7"/>'
             '<stop offset="1" stop-color="#000" stop-opacity="0"/></linearGradient>')
    body = hub + ('<g clip-path="url(#o)">'
            '<rect x="-80" y="-80" width="%s" height="%s" fill="url(#m)"/>'
            '%s'
            '<rect x="-80" y="%s" width="%s" height="%s" fill="url(#m)"/>'
            '<rect x="-80" y="%s" width="%s" height="4" fill="#fff" fill-opacity="0.22"/>'
            '<rect x="-80" y="%s" width="%s" height="4" fill="#fff" fill-opacity="0.14"/></g>'
            % (BODY_R + 80, CAP_H + 80,
               "" if "chrome" in P else '<rect x="-80" y="0" width="%s" height="%s" fill="url(#v)"/>' % (BODY_R + 80, CAP_H),
               top, BODY_R + 80, bottom - top,
               CAP_H - 5, BODY_R + 80, top + 1, BODY_R + 80))
    return svg(defs, body)

def film_svg(P):
    """The leader, as tall as the label, cut to half height at its end. It's thin, so it
    draws its own crisp lit edge rather than taking Liquid Glass's bevel."""
    x0 = BODY_R - INSET - LIP_W - 10
    t, b = FILM_T, CAN_H - FILM_T
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
            # The slot's shadow on the film just where it leaves the canister, and a warm sheen further out.
            '<linearGradient id="g" gradientUnits="userSpaceOnUse" x1="%s" y1="0" x2="1000" y2="0">'
            '<stop offset="0" stop-color="#000" stop-opacity="0.65"/><stop offset="0.07" stop-color="#000" stop-opacity="0"/>'
            '<stop offset="0.53" stop-color="#FFD2A8" stop-opacity="0.18"/><stop offset="0.76" stop-color="#FFD2A8" stop-opacity="0"/></linearGradient>'
            '<clipPath id="c"><path fill-rule="evenodd" d="%s"/></clipPath>' % (BODY_R - 6, d))
    edge = '<rect clip-path="url(#c)" x="%s" y="%s" width="%s" height="2.5" fill="#FFE2C4" fill-opacity="0.55"/>' % (x0, t, xe - x0)
    return svg(defs, '<path fill="url(#f)" fill-rule="evenodd" d="%s"/><path fill="url(#g)" fill-rule="evenodd" d="%s"/>%s' % (d, d, edge))

def layer(name, dark=False):
    # No plain "image-name": when it's present, Icon Composer ignores the specializations.
    specs = [{"value": name + ".svg"}]
    if dark:
        specs.append({"appearance": "dark", "value": name + "-dark.svg"})
    specs.append({"appearance": "tinted", "value": name + "-mono.svg"})
    return {"name": name, "image-name-specializations": specs}
def group(name, layers, translucency=0.0, shadow="neutral", specular=True):
    return {"name": name, "layers": layers, "shadow": {"kind": shadow, "opacity": 0.5}, "specular": specular,
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
        group("Film", [layer("film")], translucency=0.1, shadow="layer-color", specular=False),
    ],
    "supported-platforms": {"circles": ["watchOS"], "squares": "shared"},
}
open(OUT + "/icon.json", "w").write(json.dumps(doc, indent=2))
print(os.path.normpath(OUT))
