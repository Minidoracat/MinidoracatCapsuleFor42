# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy", "pillow", "scipy"]
# ///
"""Procedural, non-cartoon smoke / burst styles for the Universal Capsule pack/unpack effect (the sandbox EffectStyle
choices, client/Effects.lua STYLES).

Usage (repo root):
    uv run scripts/assets/design_smoke.py [ID ...]           # review images only (every style, or just these: S6)
    uv run scripts/assets/design_smoke.py --write [ID ...]   # also those styles' frames into the MOD (smoke_<ID>_<n>.png)
Output: temp/assets-review/fx-v1/smoke/
    styles.json                      metadata (C0 first, then S1..S6)
    <ID>/<ID>_01.png .. <ID>_NN.png  RGBA straight alpha, transparent background, 4-px zero-alpha border
    <ID>/<ID>_sheet.png              frames on a checkerboard + on the in-game background crop
    <ID>/<ID>_preview.webp           animation at true frame timing on the background crop
C0 is the current cartoon smoke copied unchanged from the MOD textures.

Everything is deterministic (fixed seeds). Styles are authored in screen pixels at zoom 1 relative to the
anchor (ground point): x right, y down; the game draws the square texture at w = px with its anchor point at
(w/2, w*anchor). Frames are rendered at 2x and box-downsampled to 384.
"""
import json
import os
import shutil
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(REPO, "temp", "assets-review", "fx-v1", "smoke")
C0_SRC = os.path.join(REPO, "MOD", "MinidoracatCapsuleFor42", "Contents", "mods", "MinidoracatCapsuleFor42",
                      "42", "media", "textures", "MinidoracatCapsule")
BG = os.path.join(REPO, "temp", "e2e-vcap-press-1010r", "client1", "Screenshots", "vcap-press-done.png")
SX, SY = 1148, 430                    # anchor (landing tile) in the background screenshot
CROP = (770, 100, 1530, 660)          # 760x560 around it
SIZE, SS = 384, 2
N = SIZE * SS
LIGHT = np.array([-0.6, -0.8])        # direction towards the light (upper left)
L3 = np.array([-0.6, -0.8, 0.9]) / np.linalg.norm([-0.6, -0.8, 0.9])   # same light in 3D (z towards viewer)


# ---------------------------------------------------------------- helpers

def smoothstep(a, b, x):
    t = np.clip((np.asarray(x, dtype=np.float64) - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def _grid(seed, n=128):
    g = ndimage.gaussian_filter(np.random.default_rng(seed).random((n, n)), 1.3, mode="wrap")
    return (g - g.mean()) / g.std()


GRIDS = [_grid(9000 + i) for i in range(8)]


def fbm(u, v, octaves=4, seed=0):
    """Tileable fBm value noise, roughly zero-mean unit-variance, sampled at lattice coords (u, v)."""
    s, a, tot = 0.0, 1.0, 0.0
    for o in range(octaves):
        f = 2.0 ** o
        s = s + a * ndimage.map_coordinates(GRIDS[(seed + o) % 8], [v * f + 31.7 * o, u * f + 13.1 * o],
                                            order=3, mode="grid-wrap")
        tot += a * a
        a *= 0.55
    return s / np.sqrt(tot)


class Canvas:
    """Internal 2x render target; coordinates are screen px at zoom 1 relative to the anchor."""

    def __init__(self, px, anchor):
        self.k = N / px
        self.ax, self.ay = N / 2, N * anchor
        i = np.arange(N) + 0.5
        self.x = (i - self.ax) / self.k
        self.y = (i - self.ay) / self.k
        self.X, self.Y = np.meshgrid(self.x, self.y)
        # half-res grid for noise (upsampled afterwards; noise is low frequency)
        self.Xh, self.Yh = self.X[::2, ::2], self.Y[::2, ::2]
        # superellipse (p=2.5) distance to the usable frame area (inside the finish() border fade)
        half = (N / 2 - 28 * SS) / self.k
        cy = (N / 2 - self.ay) / self.k
        self.edge = (np.abs(self.X / half) ** 2.5 + np.abs((self.Y - cy) / half) ** 2.5) ** 0.4

    def zeros(self):
        return np.zeros((N, N))

    def fit(self, D, n=0.0, inner=0.62):
        """Fade a density field out before the frame edge (noise-wobbled) so nothing gets a straight cut."""
        return D * (1 - smoothstep(inner, 1.0, self.edge * (1 + 0.18 * n)))

    def splat(self, D, x, y, sx, sy, w):
        """Add an axis-aligned gaussian (sigmas sx, sy, peak w) at (x, y)."""
        c0 = max(int((x - 3.2 * sx) * self.k + self.ax), 0)
        c1 = min(int((x + 3.2 * sx) * self.k + self.ax) + 2, N)
        r0 = max(int((y - 3.2 * sy) * self.k + self.ay), 0)
        r1 = min(int((y + 3.2 * sy) * self.k + self.ay) + 2, N)
        if c0 >= c1 or r0 >= r1 or w <= 0:
            return
        gx = np.exp(-0.5 * ((self.x[c0:c1] - x) / sx) ** 2)
        gy = np.exp(-0.5 * ((self.y[r0:r1] - y) / sy) ** 2)
        D[r0:r1, c0:c1] += w * gy[:, None] * gx[None, :]

    def noise(self, scale, t, drift=(0.0, 0.0), warp=0.0, octaves=4, seed=0, evolve=0.3):
        """Domain-warped fBm in screen space (feature size ~scale px), advected by drift px/s."""
        u = (self.Xh - drift[0] * t) / scale
        v = (self.Yh - drift[1] * t) / scale
        if warp:
            wu = fbm(u * 0.5 + evolve * t, v * 0.5, 3, seed + 3)
            wv = fbm(u * 0.5, v * 0.5 - evolve * t, 3, seed + 5)
            u, v = u + warp * wu, v + warp * wv
        n = fbm(u, v, octaves, seed)
        return ndimage.zoom(n, 2, order=3, mode="nearest")

    def light_occlusion(self, D, steps=(4, 10, 22), blur=2.0):
        """Mean (saturating) density between each pixel and the light (upper left); 0 on lit edges."""
        Db = ndimage.gaussian_filter(1 - np.exp(-D), blur * self.k)
        occ = np.zeros_like(D)
        for s in steps:
            dx, dy = int(round(LIGHT[0] * s * self.k)), int(round(LIGHT[1] * s * self.k))
            occ += np.roll(Db, (-dy, -dx), axis=(0, 1))
        return occ / len(steps)


def over(dst, src):
    """Straight-alpha 'over': src on top of dst; both (rgb HxWx3, a HxW)."""
    (cd, ad), (cs, as_) = dst, src
    a = as_ + ad * (1 - as_)
    w = np.where(a > 1e-6, as_ / np.maximum(a, 1e-6), 1.0)[..., None]
    return cd * (1 - w) + cs * w, a


def smoke_layer(cv, D, lit, shadow, k_alpha, k_shade, tint=None, bump=40.0, soft=1.5):
    """Density -> lit straight-alpha smoke. Treats the (compressed, blurred) density as a height field so each
    billow gets its own lambert shading from the upper left, times large-scale self-occlusion.
    bump: lobe height in px (shading contrast); tint: optional per-pixel rgb multiplier."""
    H = ndimage.gaussian_filter(1 - np.exp(-0.35 * D), soft * cv.k)
    gy, gx = np.gradient(H)
    nx, ny = -gx * cv.k * bump, -gy * cv.k * bump
    lam = np.clip((nx * L3[0] + ny * L3[1] + L3[2]) / np.sqrt(nx * nx + ny * ny + 1), 0, 1)
    shade = (0.25 + 0.75 * lam) * np.exp(-k_shade * cv.light_occlusion(D))
    rgb = lerp(np.asarray(shadow), np.asarray(lit), shade[..., None])
    if tint is not None:
        rgb = rgb * tint
    return np.clip(rgb, 0, 1), 1 - np.exp(-k_alpha * D)


def glow_layer(I, outer, core, k=1.6, core_from=0.5, core_to=1.6):
    """Emission intensity -> straight-alpha 'glow' (normal blending: white core, coloured falloff)."""
    t = smoothstep(core_from, core_to, I)[..., None]
    return lerp(np.asarray(outer), np.asarray(core), t), 1 - np.exp(-k * I)


def star(cv, I, x, y, size, width=0.7, halo=0.25):
    """Add a 4-point glint (cross of exponential arms + core + soft halo) of arm length ~size px."""
    r = size * 3.5
    c0 = max(int((x - r) * cv.k + cv.ax), 0)
    c1 = min(int((x + r) * cv.k + cv.ax) + 2, N)
    r0 = max(int((y - r) * cv.k + cv.ay), 0)
    r1 = min(int((y + r) * cv.k + cv.ay) + 2, N)
    if c0 >= c1 or r0 >= r1:
        return
    dx = cv.x[c0:c1][None, :] - x
    dy = cv.y[r0:r1][:, None] - y
    arms = (np.exp(-np.abs(dx) / size) * np.exp(-0.5 * (dy / width) ** 2)
            + np.exp(-np.abs(dy) / size) * np.exp(-0.5 * (dx / width) ** 2))
    rr = dx * dx + dy * dy
    I[r0:r1, c0:c1] += 1.4 * arms + 1.6 * np.exp(-rr / (2 * (0.5 * size) ** 2)) + halo * np.exp(-rr / (2 * (1.6 * size) ** 2))


def finish(rgb, a, seed):
    """2x box downsample (premultiplied), border mask, dither, quantise -> uint8 RGBA 384x384."""
    a = np.clip(a, 0, 1)
    pm = rgb * a[..., None]
    box = lambda z: z.reshape(SIZE, SS, SIZE, SS, *z.shape[2:]).mean(axis=(1, 3))
    A, PM, RAW = box(a), box(pm), box(rgb)
    out = np.where(A[..., None] > 1e-4, PM / np.maximum(A, 1e-4)[..., None], RAW)
    i = np.arange(SIZE)
    e = np.minimum.outer(np.minimum(i, SIZE - 1 - i), np.minimum(i, SIZE - 1 - i))
    rr = np.hypot(*np.meshgrid(i - (SIZE - 1) / 2, i - (SIZE - 1) / 2)) / (SIZE / 2)
    A = A * smoothstep(4, 28, e) * (1 - smoothstep(1.0, 1.35, rr))
    rng = np.random.default_rng(seed)
    dith = rng.random(A.shape) - rng.random(A.shape)       # triangular, +-1 LSB
    a8 = np.clip(np.round(A * 255 + dith * 0.5), 0, 255)
    a8[e < 4] = 0
    rgb8 = np.clip(np.round(np.clip(out, 0, 1) * 255 + dith[..., None] * 0.5), 0, 255)
    return np.dstack([rgb8, a8]).astype(np.uint8)


def puff(cv, t, P, env):
    """Sum the gaussian blobs of particle set P (dict of equal-length arrays) at time t."""
    D = cv.zeros()
    e = 1 - np.exp(-t / P["tau"])
    x = P["x0"] + P["vx"] * P["tau"] * e + P["wind"] * t
    y = P["y0"] + P["vy"] * P["tau"] * e - P["rise"] * t
    r = P["r0"] + P["rg"] * (1 - np.exp(-t / P["taur"])) + P["rs"] * t
    w = P["w"] * (P["r0"] / r) ** P["thin"] * smoothstep(-0.02, P["tin"], t - P["delay"]) * env
    for j in range(len(x)):
        cv.splat(D, x[j], y[j], r[j] * P["ax"][j], r[j] * P["ay"][j], w[j])
    return D


def burst_particles(rng, n, rx, ry, hmax, speed, tau, rise, r0, rg, taur, rs, w, cy=-40.0, flat=1.0,
                    wind=10.0, thin=1.0, tin=0.06, delay=0.0):
    """Particles spawned in the vehicle volume (ground ellipse rx/ry, height 0..hmax), pushed outward from
    (0, cy) on the iso ground plane plus upward. Range args are (lo, hi) tuples."""
    U = lambda lohi: rng.uniform(*lohi, n) if isinstance(lohi, tuple) else np.full(n, float(lohi))
    ang = rng.uniform(0, 2 * np.pi, n)
    rad = np.sqrt(rng.uniform(0, 1, n))
    gx, gy = rx * rad * np.cos(ang), ry * rad * np.sin(ang)
    h = U((0, hmax))
    x0, y0 = gx, gy - h
    dx, dy = x0, (y0 - cy) * 1.4
    norm = np.maximum(np.hypot(dx, dy), 1e-3)
    sp = U(speed)
    return dict(x0=x0, y0=y0, vx=sp * dx / norm, vy=sp * dy / norm * 0.75, tau=U(tau), rise=U(rise),
                r0=U(r0), rg=U(rg), taur=U(taur), rs=U(rs), w=U(w), wind=U((-wind, wind)) + wind * 0.5,
                thin=np.full(n, thin), tin=np.full(n, tin), delay=U(delay),
                ax=np.full(n, 1.0), ay=np.full(n, flat))


def merge(*ps):
    return {k: np.concatenate([p[k] for p in ps]) for k in ps[0]}


def billows(rng, n, rx, ry, hmax, speed, drift, up, rise, R0, grow, kids=(3, 5), flat=1.0, life=(0.6, 0.95),
            even=False, tau=(0.1, 0.17)):
    """Billow clusters: each parent lobe plus 'kids' smaller lobes on its upper rim (cauliflower outline).
    Parents spawn in the vehicle footprint (ground ellipse rx/ry, height 0..hmax) and are shoved outward on the
    2:1 ground plane. Range args are (lo, hi); life is the fade-out end as a fraction of the effect length.
    Returns a dict of per-lobe arrays; positions are evaluated by billow_state()."""
    U = lambda lohi: float(rng.uniform(*lohi))
    rows = []
    for i in range(n):
        ang = 2 * np.pi * (i + rng.uniform(0.2, 0.8)) / n if even else rng.uniform(0, 2 * np.pi)
        rad = np.sqrt(rng.uniform(0.05, 1))
        p = dict(gx=rx * rad * np.cos(ang), gy=ry * rad * np.sin(ang), h0=U(hmax), dx=np.cos(ang),
                 dy=np.sin(ang), speed=U(speed), tau=U(tau), drift=U(drift), up=U(up), rise=U(rise),
                 R0=U(R0), grow=U(grow), flat=flat, life=U(life), hue=rng.uniform(-1, 1))
        rows.append(dict(p, ox=0.0, oy=0.0, rr=1.0, dz=0.0))
        for _ in range(int(rng.integers(kids[0], kids[1] + 1))):
            phi = rng.uniform(-0.95 * np.pi, -0.05 * np.pi) if rng.random() < 0.75 else rng.uniform(0, np.pi)
            dist = rng.uniform(0.5, 0.85)
            rows.append(dict(p, ox=dist * np.cos(phi), oy=dist * np.sin(phi) * flat, rr=rng.uniform(0.35, 0.65),
                             dz=rng.uniform(-0.4, 0.4)))
    return {k: np.array([r[k] for r in rows]) for k in rows[0]}


def billow_state(B, t, T):
    """Lobe centres (x, y), radii (rx, ry), depth (ground y, larger = nearer) and opacity at time t."""
    d = B["speed"] * B["tau"] * (1 - np.exp(-t / B["tau"])) + B["drift"] * t
    gx, gy = B["gx"] + B["dx"] * d, B["gy"] + B["dy"] * 0.5 * d
    h = B["h0"] + B["up"] * 0.15 * (1 - np.exp(-t / 0.15)) + B["rise"] * t
    R = B["R0"] * (0.55 + 0.45 * (1 - np.exp(-t / 0.12))) + B["grow"] * t
    x = gx + B["ox"] * R * (1 + 0.3 * t)          # kids drift slightly apart from their parent
    y = gy - h + B["oy"] * R * (1 + 0.3 * t)
    end = B["life"] * T
    a = smoothstep(-0.06, 0.04, t) * (1 - smoothstep(end - 0.5 * T, end, t))
    return x, y, R * B["rr"], R * B["rr"] * B["flat"], gy + B["dz"] * R * 0.5, a


def render_billows(cv, t, T, B, colors, k_alpha, erode, seed, rise=60.0, occ_k=1.4, edge=(0.9, 1.0), detail=6.0):
    """billows() clusters at time t, through render_lobes()."""
    return render_lobes(cv, t, billow_state(B, t, T), colors, k_alpha, erode, seed, rise, occ_k, edge, detail)


def render_lobes(cv, t, state, colors, k_alpha, erode, seed, rise=60.0, occ_k=1.4, edge=(0.9, 1.0), detail=6.0):
    """Composite the lobes back to front. state: per-lobe centres (x, y), radii (rx, ry), depth (ground y, larger =
    nearer) and opacity. Each lobe is a noise-roughened sphere: thickness-based density (thick
    centre, thin eroded rim), per-lobe lambert from the upper left (+25% lit cap / -30% underside) and a shared
    occlusion term so overlapping lobes darken each other. colors: per-lobe base rgb (n, 3).
    detail: strength of the small-scale surface bumps in the lambert normal.
    edge: soft safety fade in Canvas.edge units (1 = start of the finish() border fade)."""
    x, y, rx, ry, depth, a = state
    n = cv.noise(34, t, drift=(10, -rise), warp=0.7, octaves=3, seed=seed)
    nf = cv.noise(11, t, drift=(10, -1.3 * rise), warp=0.5, octaves=2, seed=seed + 1)
    gny, gnx = np.gradient(nf)
    lobes, D = [], cv.zeros()
    for j in range(len(x)):
        if a[j] <= 0.002:
            continue
        c0 = max(int((x[j] - 1.45 * rx[j]) * cv.k + cv.ax), 0)
        c1 = min(int((x[j] + 1.45 * rx[j]) * cv.k + cv.ax) + 2, N)
        r0 = max(int((y[j] - 1.45 * ry[j]) * cv.k + cv.ay), 0)
        r1 = min(int((y[j] + 1.45 * ry[j]) * cv.k + cv.ay) + 2, N)
        if c0 >= c1 or r0 >= r1:
            continue
        w = (slice(r0, r1), slice(c0, c1))
        dx = ((cv.x[c0:c1] - x[j]) / rx[j])[None, :]
        dy = ((cv.y[r0:r1] - y[j]) / ry[j])[:, None]
        rn = np.hypot(dx, dy) * (1 + 0.22 * np.clip(n[w], -1.2, 2.5))   # reach <= 1.36 r, inside the window
        th = np.sqrt(np.clip(1 - rn * rn, 0, 1))
        dens = a[j] * (th * th) ** 1.2 * np.exp(0.45 * nf[w])      # zero-slope rim: soft, not a cut-out disc
        D[w] += dens
        lobes.append((depth[j], j, w, dx, dy, th, dens))
    occ = np.exp(-occ_k * cv.light_occlusion(D, steps=(10, 24, 44), blur=4.0))
    P, A = np.zeros((N, N, 3)), cv.zeros()
    for _, j, w, dx, dy, th, dens in sorted(lobes, key=lambda l: l[0]):
        al = 1 - np.exp(-k_alpha * np.maximum(dens - erode * np.sqrt(a[j]), 0))
        nx, ny, nz = dx + detail * gnx[w], dy + detail * gny[w], th + 0.1
        lam = np.clip((nx * L3[0] + ny * L3[1] + nz * L3[2]) / np.sqrt(nx * nx + ny * ny + nz * nz), 0, 1)
        col = colors[j] * (0.70 + 0.55 * lam)[..., None] * (0.5 + 0.5 * occ[w])[..., None]
        col = lerp(col, colors[j] * 1.05, 0.6 * (1 - a[j]))           # thinning smoke scatters, reads lighter
        P[w] = P[w] * (1 - al[..., None]) + col * al[..., None]
        A[w] = A[w] * (1 - al) + al
    rgb = np.where(A[..., None] > 1e-4, P / np.maximum(A, 1e-4)[..., None], np.mean(colors, axis=0))
    A *= 1 - smoothstep(edge[0], edge[1], cv.edge)  # safety only; lobes are sized to stay inside the frame
    return np.clip(rgb, 0, 1), A


# ---------------------------------------------------------------- styles

S1_B = merge(
    billows(np.random.default_rng(101), 11, 95, 48, (10, 70), (200, 400), (12, 30), (30, 150), (20, 50),
            (45, 75), (10, 20), life=(0.9, 1.05), even=True),
    billows(np.random.default_rng(103), 6, 80, 40, (0, 10), (350, 550), (20, 40), (0, 20), (5, 15), (34, 50),
            (8, 16), kids=(2, 4), life=(0.8, 1.0), even=True),
)


def s1_grey(cv, t, T):
    base = np.array([0.66, 0.66, 0.67]) * (1 + 0.05 * S1_B["hue"])[:, None]
    erode = 0.05 + 0.3 * smoothstep(0.3 * T, T, t)
    return render_billows(cv, t, T, S1_B, base, k_alpha=2.2, erode=erode, seed=1, rise=40)


# ground skirt: flattened lobes filling a 2:1 disc that is ~520 px wide at peak (outer lobes on a fixed tau)
S2_SKIRT = merge(
    billows(np.random.default_rng(201), 14, 30, 15, (0, 6), (1600, 1750), (8, 15), (0, 0), (0, 5), (45, 52),
            (6, 12), kids=(2, 3), flat=0.5, life=(0.75, 1.02), even=True, tau=(0.12, 0.13)),
    billows(np.random.default_rng(204), 10, 60, 30, (0, 8), (300, 900), (5, 12), (0, 0), (0, 5), (48, 60),
            (6, 12), kids=(2, 3), flat=0.5, life=(0.7, 1.0), even=True, tau=(0.12, 0.13)),
)
# lumpy plumes kicked up over the car body, settling back down
S2_PLUME = billows(np.random.default_rng(202), 10, 115, 55, (20, 70), (100, 250), (3, 10), (300, 550), (-25, 0),
                   (52, 72), (8, 14), life=(0.6, 0.92), even=True)
S2_B = merge(S2_SKIRT, S2_PLUME)


def s2_dust(cv, t, T):
    base = np.array([0.70, 0.61, 0.48]) * (1 + np.outer(0.06 * S2_B["hue"], [1.0, 0.9, 0.7]))
    erode = 0.05 + 0.3 * smoothstep(0.3 * T, T, t)
    # the skirt tips may reach into the finish() border fade (~520 px wide on a 576 px frame)
    layer = render_billows(cv, t, T, S2_B, base, k_alpha=2.6, erode=erode, seed=2, rise=15, edge=(1.0, 1.12))
    # debris: dirt/gravel specks thrown up from the car footprint, ballistic, gone shortly after landing
    rng = np.random.default_rng(203)
    k = 16
    ang = rng.uniform(0, 2 * np.pi, k)
    r0 = rng.uniform(10, 70, k)
    sp = rng.uniform(160, 380, k)
    vz = rng.uniform(320, 620, k)
    h0 = rng.uniform(10, 50, k)
    g = 2200.0
    land = (vz + np.sqrt(vz * vz + 2 * g * h0)) / g
    tt = np.minimum(t, land)
    gx = (r0 + sp * tt) * np.cos(ang)
    gy = (r0 + sp * tt) * 0.5 * np.sin(ang)
    h = h0 + vz * tt - 0.5 * g * tt * tt
    a = 1 - smoothstep(land, land + 0.12, t)
    size = rng.uniform(0.9, 1.5, k)
    Dd = cv.zeros()
    for j in range(k):
        cv.splat(Dd, gx[j], gy[j] - h[j], size[j], size[j] * 1.3, 2.5 * a[j])
    deb = (np.broadcast_to(np.array([0.24, 0.20, 0.16]), Dd.shape + (3,)), 1 - np.exp(-Dd))
    return over(layer, deb)


def s3_steam(cv, t, T):
    rng = np.random.default_rng(303)
    P = merge(
        burst_particles(rng, 70, 100, 45, 110, (700, 1150), (0.05, 0.08), (60, 130), (10, 16), (16, 26), 0.1,
                        (18, 30), (0.6, 0.9), thin=1.3, tin=0.03),
        burst_particles(rng, 24, 50, 25, 120, (500, 900), (0.05, 0.08), (160, 260), (9, 14), (12, 20), 0.1,
                        (15, 25), (0.4, 0.6), cy=-80, thin=1.3, tin=0.03),
    )
    env = 1 - smoothstep(0.2 * T, 0.98 * T, t)
    D = puff(cv, t, P, env)
    n = cv.noise(30, t, drift=(0, -160), warp=0.8, octaves=4, seed=3, evolve=1.0)
    # radial streak noise (wisps shooting outward from the burst centre); sampled on a circle in noise space
    a = np.arctan2(cv.Yh + 50, cv.Xh)
    rr = np.hypot(cv.Xh, (cv.Yh + 50) * 1.6)
    nr = ndimage.zoom(fbm(np.cos(a) * 7 + rr / 110 - 1.5 * t, np.sin(a) * 7 + 0.8 * t, 3, 6), 2, order=3)
    nr *= ndimage.zoom(smoothstep(30, 110, rr), 2, order=1)      # no streak pinch at the centre
    D = cv.fit(D * np.exp(0.45 * n + 0.55 * nr), n)
    D = np.maximum(D - (0.12 + 0.35 * smoothstep(0.15 * T, T, t)) * (0.75 - 0.35 * n), 0)
    return smoke_layer(cv, D, lit=(1.0, 1.0, 1.0), shadow=(0.78, 0.83, 0.88), k_alpha=2.1, k_shade=0.5, soft=2,
                       bump=14)


def s4_scifi(cv, t, T):
    X, Y = cv.X, cv.Y
    cyan, core = (0.30, 0.86, 1.0), (0.93, 1.0, 1.0)
    # vertical light column: rises fast, holds, narrows and fades
    on = smoothstep(0.0, 0.06, t) * (1 - smoothstep(0.25, 0.75, t))
    wid = 1 - 0.6 * smoothstep(0.2, 0.75, t)
    top = -60 - 270 * smoothstep(0.0, 0.12, t)
    vert = smoothstep(top, top + 170, Y) * np.exp(-(np.maximum(Y, 0) / 14) ** 2)
    streak = 1 + 0.35 * ndimage.zoom(fbm(cv.Xh / 7, cv.Yh / 60 + 6 * t, 2, 4), 2, order=1)
    col = (2.2 * np.exp(-0.5 * (X / (10 * wid)) ** 2) + 0.7 * np.exp(-0.5 * (X / (34 * wid)) ** 2)) * vert * streak * on
    # ground glow and expanding 2:1 rings
    rho = np.hypot(X, 2 * Y)
    I = col + 1.0 * np.exp(-0.5 * (rho / 60) ** 2) * on
    for delay, amp in ((0.0, 1.6), (0.14, 0.9)):
        tr = max(t - delay, 0)
        R = 25 + 150 * (1 - np.exp(-tr / 0.22))
        th = 5 + 18 * tr
        I += amp * np.exp(-0.5 * ((rho - R) / th) ** 2) * smoothstep(0, 0.04, tr) * (1 - smoothstep(0.2, 0.8, tr))
    # rising motes
    rng = np.random.default_rng(404)
    m = 46
    ang, rad = rng.uniform(0, 2 * np.pi, m), np.sqrt(rng.uniform(0.05, 1, m)) * 130
    t0 = rng.uniform(0, 0.45, m)
    life = rng.uniform(0.35, 0.6, m)
    vy = rng.uniform(140, 330, m)
    ph = rng.uniform(0, 2 * np.pi, m)
    for j in range(m):
        age = t - t0[j]
        if age < 0 or age > life[j]:
            continue
        f = np.sin(np.pi * age / life[j]) * (0.65 + 0.35 * np.sin(ph[j] + 40 * t))
        x = rad[j] * np.cos(ang[j]) * (1 - 0.3 * age)
        y = rad[j] * 0.5 * np.sin(ang[j]) - vy[j] * age
        cv.splat(I, x, y, 1.6, 1.6, 2.2 * f)
        cv.splat(I, x, y, 5.0, 5.0, 0.35 * f)
    return glow_layer(I * (1 - smoothstep(0.7 * T, T, t)), cyan, core, k=1.5)


S5_B = merge(
    billows(np.random.default_rng(501), 11, 95, 48, (10, 70), (200, 400), (12, 30), (30, 150), (25, 55),
            (45, 75), (10, 20), life=(0.88, 1.08), even=True),
    billows(np.random.default_rng(503), 6, 80, 40, (0, 10), (350, 550), (20, 40), (0, 20), (5, 15), (34, 50),
            (8, 16), kids=(2, 4), life=(0.8, 1.0), even=True),
)


def s5_magic(cv, t, T):
    pink, lavender = np.array([0.93, 0.80, 0.89]), np.array([0.84, 0.80, 0.95])
    base = lerp(pink, lavender, (0.5 + 0.5 * S5_B["hue"])[:, None])
    erode = 0.05 + 0.3 * smoothstep(0.3 * T, T, t)
    k_alpha = 2.7 * (1 - 0.5 * smoothstep(0.4 * T, 0.7 * T, t))       # more translucent in the second half
    layer = render_billows(cv, t, T, S5_B, base, k_alpha=k_alpha, erode=erode, seed=5, rise=45, occ_k=1.1,
                           detail=4.0)
    # twinkling 4-point glints drifting up
    rng = np.random.default_rng(506)
    m = 44
    x0 = rng.normal(0, 85, m)
    y0 = rng.uniform(-200, 20, m)
    t0 = rng.uniform(0.02, 0.7 * T, m)
    life = rng.uniform(0.35, 0.65, m)
    vy = rng.uniform(30, 90, m)
    sz = rng.uniform(7.0, 13.0, m)
    ph = rng.uniform(0, 2 * np.pi, m)
    I = cv.zeros()
    for j in range(m):
        age = t - t0[j]
        if age < 0 or age > life[j]:
            continue
        f = np.sin(np.pi * age / life[j]) ** 0.7 * (0.55 + 0.45 * np.cos(ph[j] + 26 * age))
        star(cv, I, x0[j] + 12 * np.sin(ph[j] + 3 * age), y0[j] - vy[j] * age, sz[j] * f, width=0.7)
    I *= 1 - smoothstep(0.75 * T, 0.97 * T, t)
    return over(layer, glow_layer(I, (1.0, 0.82, 0.42), (1.0, 0.99, 0.92), k=1.4, core_from=0.6, core_to=1.8))


def mushroom_lobes(rng):
    """Static lobes of the mushroom cloud; mushroom_state() places them. part 0 = cap ring (a torus seen from above,
    a = angle: 0 right, pi/2 front; b = radius in cap radii), 1 = cap dome (offsets a, b in cap radii), 2 = stem
    (a = height 0..1, b = sway). Every parent gets 1-3 kids on its upper rim that churn slowly around it."""
    rows = []

    def add(**p):
        p.update(kid=0.0, phi=0.0, dist=0.0, spin=0.0, prr=p["rr"])
        rows.append(p)
        for _ in range(int(rng.integers(1, 4))):
            rows.append(dict(p, kid=1.0, phi=rng.uniform(-0.95 * np.pi, -0.05 * np.pi), dist=rng.uniform(0.55, 0.85),
                             rr=p["rr"] * rng.uniform(0.35, 0.6), spin=rng.uniform(-0.9, 0.9),
                             dz=p["dz"] + rng.uniform(-0.1, 0.1)))

    for i in range(14):
        add(part=0, a=2 * np.pi * (i + rng.uniform(-0.25, 0.25)) / 14, b=rng.uniform(0.92, 1.08),
            rr=rng.uniform(0.40, 0.52), dz=0.0, life=rng.uniform(0.92, 1.04), heat=rng.uniform(0.8, 1.0),
            hue=rng.uniform(-1, 1))
    for _ in range(7):
        add(part=1, a=rng.uniform(-0.55, 0.55), b=rng.uniform(0.12, 0.35), rr=rng.uniform(0.42, 0.56),
            dz=rng.uniform(-0.1, 0.1), life=rng.uniform(0.92, 1.04), heat=rng.uniform(0.6, 0.9), hue=rng.uniform(-1, 1))
    for i in range(9):
        add(part=2, a=(i + rng.uniform(0.1, 0.9)) / 9, b=rng.uniform(-1, 1), rr=rng.uniform(0.85, 1.15), dz=0.0,
            life=rng.uniform(0.7, 0.85), heat=rng.uniform(0.2, 0.5), hue=rng.uniform(-1, 1))
    return {k: np.array([r[k] for r in rows]) for k in rows[0]}


def mushroom_cap(t):
    """Cap centre height and radius (px) at time t: shoots up as a ball, then hangs, drifts up and spreads wide."""
    return -40 - 245 * (1 - np.exp(-t / 0.30)) - 10 * t, 30 + 82 * (1 - np.exp(-t / 0.32)) + 8 * t


def mushroom_state(M, t, T):
    """Lobe centres (x, y), radii (rx, ry), depth (ground y, larger = nearer), opacity and heat at time t."""
    cy, Rc = mushroom_cap(t)
    part, a, b = M["part"], M["a"], M["b"]
    ring, dome, stem = part == 0, part == 1, part == 2
    base = np.where(stem, (32 - 9 * a) * (1 + 0.5 * t), Rc)          # stem: thick at the foot, widening over time
    x = np.select([ring, dome], [b * Rc * np.cos(a), a * Rc], 7 * b + 5 * np.sin(9 * a + 2.5 * t))
    y = np.select([ring, dome], [cy + 0.10 * Rc + 0.36 * b * Rc * np.sin(a), cy - b * Rc],
                  lerp(-12, cy + 0.30 * Rc, a))                       # the stem reaches the cap's underside
    depth = np.where(ring, 0.5 * b * Rc * np.sin(a), 0.0) + M["dz"] * base
    ph = M["phi"] + M["spin"] * t
    x = x + M["kid"] * M["dist"] * M["prr"] * base * np.cos(ph)
    y = y + M["kid"] * M["dist"] * M["prr"] * base * np.sin(ph)
    r = M["rr"] * base
    end = M["life"] * T
    alpha = smoothstep(-0.06, 0.04, t) * (1 - smoothstep(end - 0.5 * T, end, t))
    alpha = alpha * np.where(stem, smoothstep(0.03 + 0.10 * a, 0.12 + 0.12 * a, t), 1.0)   # the stem grows upward
    heat = M["heat"] * (0.9 * np.exp(-t / 0.16) + 0.1 * np.exp(-t / 0.5))   # fire for ~0.4 s, then embers
    return x, y, r, r * np.where(stem, 1.0, 0.9), depth, alpha, heat


S6_M = mushroom_lobes(np.random.default_rng(602))
# dust thrown out along the ground under the cloud (flattened lobes, like S2's skirt but smaller)
S6_SKIRT = billows(np.random.default_rng(601), 12, 40, 20, (0, 6), (800, 1150), (6, 12), (0, 0), (0, 4), (34, 44),
                   (5, 10), kids=(2, 3), flat=0.5, life=(0.6, 0.85), even=True, tau=(0.11, 0.13))
S6_COL = np.concatenate([
    np.where((S6_M["part"] == 2)[:, None], [0.58, 0.53, 0.48], [0.50, 0.46, 0.43]) * (1 + 0.05 * S6_M["hue"])[:, None],
    np.array([0.72, 0.66, 0.58]) * (1 + np.outer(0.05 * S6_SKIRT["hue"], [1.0, 0.9, 0.7]))])
EMBER = np.array([0.55, 0.27, 0.10])  # hot smoke in the young cloud reads orange-brown


def s6_shock(cv, t, T):
    X, Y = cv.X, cv.Y
    # flash disc (frames 1-2), centred on the car body
    fl = np.exp(-max(t - 0.06, 0) / 0.07)
    Rf = 90 + 320 * min(t, 0.25)
    rf = np.hypot(X, (Y + 40) * 1.25)
    If = (2.4 * np.exp(-(rf / Rf) ** 4) + 0.6 * np.exp(-0.5 * (rf / (1.4 * Rf)) ** 2)) * fl
    # shockwave ring on the ground
    rho = np.hypot(X, 2 * Y)
    R = 20 + 190 * (1 - np.exp(-t / 0.18))
    Ir = 1.5 * np.exp(-0.5 * ((rho - R) / (3.5 + 6 * t)) ** 2) * (1 - smoothstep(0.12, 0.8, t))
    # mushroom cloud: cap and stem plus the dust skirt, depth-sorted as one set
    mx, my, mrx, mry, md, ma, heat = mushroom_state(S6_M, t, T)
    sk = billow_state(S6_SKIRT, t, T)
    sk = (*sk[:5], 0.75 * sk[5])                                     # thinner dust than the cloud
    state = tuple(np.concatenate(p) for p in zip((mx, my, mrx, mry, md, ma), sk))
    col = S6_COL.copy()
    col[:len(mx)] = lerp(col[:len(mx)], EMBER, np.minimum(1.0, 1.5 * heat)[:, None])
    erode = 0.05 + 0.35 * smoothstep(0.3 * T, T, t)
    layer = render_lobes(cv, t, state, col, k_alpha=2.4, erode=erode, seed=6, rise=70)
    # fire glowing in the young cap and stem, and the fireball core
    cy, Rc = mushroom_cap(t)
    I = cv.zeros()
    hot = heat * ma
    for j in np.flatnonzero(hot > 0.01):
        cv.splat(I, mx[j], my[j], 0.5 * mrx[j], 0.5 * mry[j], 1.1 * hot[j])
    cv.splat(I, 0, cy, 0.6 * Rc, 0.55 * Rc, 2.4 * np.exp(-t / 0.10))
    fire = glow_layer(I, (0.98, 0.42, 0.10), (1.0, 0.95, 0.70), k=1.2, core_from=0.7, core_to=2.2)
    ring = glow_layer(Ir, (0.86, 0.86, 0.84), (1.0, 1.0, 0.98), k=1.3, core_from=0.6, core_to=1.4)
    flash = glow_layer(If, (1.0, 0.86, 0.6), (1.0, 0.99, 0.94), k=1.6)
    return over(over(over(layer, fire), ring), flash)


# id, name, desc, frames, frame_ms, px, anchor, flash, renderer
STYLES = [
    ("S1", "寫實灰煙", "灰色煙團從車底翻滾湧出，再分散成縷縷薄煙。", 16, 90, 576, 0.66, [0.85, 0.85, 0.82], s1_grey),
    ("S2", "塵土爆散", "黃褐塵土貼地向外炸開成大圈，碎石飛落後沉降。", 16, 90, 576, 0.62, [1.0, 0.85, 0.6], s2_dust),
    ("S3", "白色蒸氣", "白色蒸氣瞬間噴開，邊緣絲狀並快速消散。", 12, 85, 480, 0.70, [0.9, 0.95, 1.0], s3_steam),
    ("S4", "科幻光環", "青白光柱升起，地面光環擴散並有光點上飄。", 12, 85, 416, 0.78, [0.5, 0.9, 1.0], s4_scifi),
    ("S5", "魔法星塵", "淡紫粉色煙團中金白星芒閃爍上飄。", 15, 90, 576, 0.66, [0.95, 0.8, 1.0], s5_magic),
    ("S6", "蘑菇雲", "白光一閃，火球衝上天化成蘑菇雲，地面衝擊波環與塵土向外擴散。", 18, 90, 672, 0.75, [1.0, 0.85, 0.6],
     s6_shock),
]


def render_style(sid, frames, frame_ms, px, anchor, fn):
    cv = Canvas(px, anchor)
    T = frames * frame_ms / 1000
    out = []
    for i in range(frames):
        t = (i + 0.6) * frame_ms / 1000
        rgb, a = fn(cv, t, T)
        out.append(finish(rgb, a, seed=7000 + 31 * i + ord(sid[1])))
    return out


# ---------------------------------------------------------------- QA images

def qa_box(px, anchor):
    """The 760-wide QA crop around the anchor, taller than CROP when the style reaches higher (S6's cap)."""
    return CROP[0], max(0, min(CROP[1], SY - round(px * anchor))), CROP[2], CROP[3]


def composite(bg, frame, px, anchor):
    """Draw like the game at zoom 1: w = px, top-left = (sx - w/2, sy - w*anchor); returns the qa_box() crop."""
    im = bg.copy()
    spr = Image.fromarray(frame, "RGBA").convert("RGBa").resize((px, px), Image.BICUBIC).convert("RGBA")
    x0, y0 = round(SX - px / 2), round(SY - px * anchor)
    im.alpha_composite(spr, (max(x0, 0), max(y0, 0)), (max(-x0, 0), max(-y0, 0)))
    return im.crop(qa_box(px, anchor))


def checker(w, h, cell=16):
    yy, xx = np.mgrid[0:h, 0:w]
    v = np.where(((xx // cell) + (yy // cell)) % 2, 150, 105).astype(np.uint8)
    return Image.fromarray(np.dstack([v, v, v, np.full_like(v, 255)]), "RGBA")


def qa(sid, frames, frame_ms, px, anchor, bg, d):
    tile = 256
    sheet = Image.new("RGBA", (tile * len(frames), tile * 2), (40, 40, 40, 255))
    box = qa_box(px, anchor)
    side = box[3] - box[1]
    sq = (box[2] - box[0] - side) // 2
    comp = []
    for i, f in enumerate(frames):
        cb = checker(f.shape[1], f.shape[0])
        cb.alpha_composite(Image.fromarray(f, "RGBA"))
        sheet.paste(cb.resize((tile, tile), Image.LANCZOS), (i * tile, 0))
        c = composite(bg, f, px, anchor)
        comp.append(c)
        sheet.paste(c.crop((sq, 0, sq + side, side)).resize((tile, tile), Image.LANCZOS), (i * tile, tile))
    sheet.convert("RGB").save(os.path.join(d, f"{sid}_sheet.png"), optimize=True)
    base = bg.crop(box)
    seq = [base] + comp + [base]
    dur = [500] + [frame_ms] * len(comp) + [600]
    seq[0].save(os.path.join(d, f"{sid}_preview.webp"), save_all=True, append_images=seq[1:], duration=dur,
                loop=0, quality=88, method=4)


# ---------------------------------------------------------------- main

def install(sids):
    """--write: those styles' frames into the MOD as smoke_<ID>_<n>.png (Core.lua M.TYPES; C0 stays smoke_<n>.png from
    build_smoke.py). Their old smoke_<ID>_*.png go first, so a style that lost frames leaves none behind."""
    dst = os.path.join(REPO, "MOD", "MinidoracatCapsuleFor42", "Contents", "mods", "MinidoracatCapsuleFor42",
                       "42", "media", "textures", "MinidoracatCapsule")
    for f in os.listdir(dst):
        if f.endswith(".png") and any(f.startswith(f"smoke_{sid}_") for sid in sids):
            os.remove(os.path.join(dst, f))
    n = 0
    for sid in sids:
        d = os.path.join(OUT, sid)
        for f in sorted(os.listdir(d)):
            if f.startswith(sid + "_") and f[len(sid) + 1:-4].isdigit():
                shutil.copyfile(os.path.join(d, f), os.path.join(dst, f"smoke_{sid}_{int(f[len(sid) + 1:-4])}.png"))
                n += 1
    print(f"-> {n} frames into {os.path.relpath(dst, REPO)}")


def main():
    args = sys.argv[1:]
    write = "--write" in args
    only = [a for a in args if a != "--write"] or [s[0] for s in STYLES]
    unknown = sorted(set(only) - {s[0] for s in STYLES})
    if unknown:
        sys.exit(f"no style {unknown}")
    for sid in ["C0", *only]:
        shutil.rmtree(os.path.join(OUT, sid), ignore_errors=True)
    bg = Image.open(BG).convert("RGBA")
    meta = []

    d = os.path.join(OUT, "C0")
    os.makedirs(d)
    c0 = []
    for i in range(1, 9):
        dst = os.path.join(d, f"C0_{i:02d}.png")
        shutil.copyfile(os.path.join(C0_SRC, f"smoke_{i}.png"), dst)
        c0.append(np.asarray(Image.open(dst).convert("RGBA")))
    meta.append(dict(id="C0", name="卡通白煙", desc="目前使用的卡通描邊白色煙團。", frames=8, frame_ms=150, px=384,
                     anchor=0.7, flash=[1, 0.95, 0.8]))
    styles = [("C0", c0, 150, 384, 0.7)]

    for sid, name, desc, frames, frame_ms, px, anchor, flash, fn in STYLES:
        meta.append(dict(id=sid, name=name, desc=desc, frames=frames, frame_ms=frame_ms, px=px, anchor=anchor,
                         flash=flash))  # styles.json lists every style, rendered this run or not
        if sid not in only:
            continue
        d = os.path.join(OUT, sid)
        os.makedirs(d)
        imgs = render_style(sid, frames, frame_ms, px, anchor, fn)
        for i, f in enumerate(imgs, 1):
            m = np.ones(f.shape[:2], bool)
            m[4:-4, 4:-4] = False
            assert not f[..., 3][m].any(), f"{sid} frame {i}: alpha on the 4-px border"
            Image.fromarray(f, "RGBA").save(os.path.join(d, f"{sid}_{i:02d}.png"), optimize=True)
        styles.append((sid, imgs, frame_ms, px, anchor))
        print(f"{sid}: {frames} frames x {frame_ms} ms, px {px}, anchor {anchor}")

    # C0 is copied unchanged (its frame 5 has a few alpha<=4 pixels on the border); only S* are checked above
    for sid, imgs, frame_ms, px, anchor in styles:
        qa(sid, imgs, frame_ms, px, anchor, bg, os.path.join(OUT, sid))

    with open(os.path.join(OUT, "styles.json"), "w", encoding="utf-8") as fh:
        json.dump(meta, fh, ensure_ascii=False, indent=2)
    print(f"-> {os.path.relpath(OUT, REPO)}")
    if write:
        install(only)


if __name__ == "__main__":
    main()
