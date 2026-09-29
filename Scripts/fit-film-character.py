"""Fit a Granular film character to reference renderings.

Usage (from Scripts/bake-film-stocks.sh's environment):
    python Scripts/fit-film-character.py REFERENCES_DIR "Portra 400"

REFERENCES_DIR holds an Originals/ folder and one folder per stock with the
same images rendered in that look (sRGB). The script fits the small parametric
model FilmRenderer's film-character kernel implements (tone curves plus color
edits by hue) and prints Swift for FilmCharacter.swift. Reference images stay
outside the repository; only the fitted parameters are kept.
"""

import glob
import sys

import cv2
import numpy as np
from scipy.optimize import least_squares

KNOTS = np.array([0, 0.125, 0.25, 0.5, 0.75, 1.0])
HUES = np.radians([30, 90, 150, 210, 270, 330])  # OKLab hue sector centres: red, yellow, green, cyan, blue, magenta

M1 = np.array([[0.4122214708,0.5363325363,0.0514459929],[0.2119034982,0.6806995451,0.1073969566],[0.0883024619,0.2817188376,0.6299787005]])
M2 = np.array([[0.2104542553,0.7936177850,-0.0040720468],[1.9779984951,-2.4285922050,0.4505937099],[0.0259040371,0.7827717662,-0.8086757660]])
def to_lin(x): return np.where(x<=0.04045,x/12.92,((x+0.055)/1.055)**2.4)
def to_srgb(x): x=np.clip(x,0,None); return np.where(x<=0.0031308,x*12.92,1.055*x**(1/2.4)-0.055)
def oklab(rgb):
    lms=np.cbrt(to_lin(rgb)@M1.T); return lms@M2.T
def from_oklab(lab):
    lms=(lab@np.linalg.inv(M2).T)**3; return to_srgb(lms@np.linalg.inv(M1).T)

def sector_weights(h):
    d=np.angle(np.exp(1j*(h[...,None]-HUES)))
    w=np.clip(1-np.abs(d)/np.radians(60),0,None)
    return w  # partition of unity for 60° spacing

def unpack(p):
    curves=p[:18].reshape(3,6)          # per channel curve values at KNOTS (offset from identity)
    dl,dc,dh=p[18:24],p[24:30],p[30:36] # per hue: lightness offset, chroma log-scale, hue rotation
    hi_desat, sh_sat = p[36], p[37]
    return curves,dl,dc,dh,hi_desat,sh_sat

def apply(rgb,p):
    curves,dl,dc,dh,hi_desat,sh_sat=unpack(p)
    lab=oklab(np.clip(rgb,0,1)); L=lab[...,0]; a,b=lab[...,1],lab[...,2]
    C=np.hypot(a,b); h=np.arctan2(b,a)
    w=sector_weights(h); cw=np.clip(C/0.08,0,1)   # hue edits fade toward neutral
    L=L+ (w@dl)*cw
    C=C*np.exp((w@dc)*cw)
    C=C*(1-hi_desat*np.clip((L-0.6)/0.4,0,1))*(1+sh_sat*np.clip((0.6-L)/0.6,0,1))
    h=h+(w@dh)*cw
    out=from_oklab(np.stack([L,C*np.cos(h),C*np.sin(h)],-1))
    out=np.clip(out,0,1)
    res=np.empty_like(out)
    for c in range(3):
        res[...,c]=np.interp(out[...,c],KNOTS,KNOTS+curves[c])
    return res
NPARAM=38


def load(path):
    image = cv2.cvtColor(cv2.imread(path, cv2.IMREAD_UNCHANGED), cv2.COLOR_BGR2RGB)
    return image.astype(float) / (65535 if image.dtype == np.uint16 else 255)


def samples(root, stock, size=240, count=40000):
    sources, targets = [], []
    for target_path in sorted(glob.glob(f"{root}/{stock}/*")):
        stem = target_path.rsplit("/", 1)[-1].rsplit(".", 1)[0]
        matches = [p for p in glob.glob(f"{root}/Originals/*") if stem in p.rsplit("/", 1)[-1]]
        if not matches:
            continue
        source, target = load(matches[0]), load(target_path)
        target = cv2.resize(target, (source.shape[1], source.shape[0]), interpolation=cv2.INTER_AREA)
        scale = size / max(source.shape[:2])
        sources.append(cv2.resize(source, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA).reshape(-1, 3))
        targets.append(cv2.resize(target, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA).reshape(-1, 3))
    x, y = np.concatenate(sources), np.concatenate(targets)
    index = np.random.default_rng(0).choice(len(x), min(count, len(x)), replace=False)
    return x[index], y[index]


def main(root, stock):
    x, y = samples(root, stock)
    target = oklab(y)
    # Black-and-white references share one tone curve so the result stays neutral.
    monochrome = np.hypot(target[:, 1], target[:, 2]).mean() < 0.004

    def expand(p):
        if monochrome:
            p = p.copy()
            p[6:12] = p[12:18] = p[0:6]
        return p

    # Exposure shifts are part of a stock's response, so brightness is fitted too.
    fit = least_squares(
        lambda p: np.concatenate([
            (oklab(apply(x, expand(p))) - target).ravel(),
            0.02 * p,
        ]),
        np.zeros(NPARAM),
        max_nfev=400,
    )
    fit.x = expand(fit.x)
    error = lambda p: np.linalg.norm(oklab(apply(x, p)) - target, axis=-1).mean()
    print(f"// {stock}: mean OKLab difference {error(np.zeros(NPARAM)):.4f} -> {error(fit.x):.4f}")
    values = lambda v: ", ".join(f"{n:.4f}" for n in v)
    p = fit.x
    print(f"red: [{values(p[0:6])}],\ngreen: [{values(p[6:12])}],\nblue: [{values(p[12:18])}],")
    print(f"lightness: [{values(p[18:24])}],\nchroma: [{values(p[24:30])}],\nhue: [{values(p[30:36])}],")
    print(f"highlightDesaturation: {p[36]:.4f},\nshadowSaturation: {p[37]:.4f}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
