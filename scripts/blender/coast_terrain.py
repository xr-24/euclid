"""Height field of the Laguna-style coast around Villa Aurelia (pure Python, no Blender needed
except for the noise in arch_kit).

The villa stands on a broad bluff top at y = 0. South of it the bluff edge breaks into a steep,
gullied sandstone cliff falling about 80 m to a sandy cove; rocky headlands on either side push
out into the sea and meet the water without a beach. Inland (north) the land rises into rolling
coastal hills cut by small canyons. Levels are in metres; SEA_Y is the ocean surface.
"""
import math

from arch_kit import fbm, smoothstep

SEA_Y = -80.0
BEACH_BACK_Y = -78.4
PLATEAU_Y = -1.1
HERB_Y = -4.8      # ground under the stepped herb-garden terraces (the terraces sit on top)


def headland(x):
    """0 in the cove below the villa, 1 out on the headlands either side."""
    ax = abs(x)
    return smoothstep(80.0, 175.0, ax) * (1.0 - smoothstep(240.0, 330.0, ax))


def cliff_edge(x):
    """z of the bluff edge (where the cliff starts) along the coast."""
    ridged = 1.0 - abs(fbm(x, 0.0, 14.0, 3, seed=3.3))  # spurs and gullies along the face
    z = 55.0 + 105.0 * headland(x) + 26.0 * smoothstep(300.0, 420.0, abs(x)) + 7.0 * fbm(x, 0.0, 60.0) \
        + 18.0 * fbm(x, 0.0, 150.0, 3, seed=5.1) * smoothstep(90.0, 160.0, abs(x)) + 8.0 * ridged - 4.0
    # Below the villa the bluff breaks off just past the south terrace, so the belvedere looks
    # straight down onto the beach.
    near = 1.0 - smoothstep(60.0, 95.0, abs(x))
    return z * (1.0 - near) + 50.0 * near


def cliff_width(x):
    return 38.0 + 8.0 * fbm(x, 40.0, 50.0) - 8.0 * headland(x)


def beach_width(x):
    return max(0.0, 46.0 * (1.0 - smoothstep(0.25, 0.75, headland(x))) + 10.0 * fbm(x, 90.0, 70.0))


def site_mask(x, z):
    """1 on the levelled villa site, 0 outside, with a soft edge."""
    mx = 1.0 - smoothstep(0.0, 18.0, max(-82.0 - x, x - 72.0, 0.0))
    mz = 1.0 - smoothstep(0.0, 14.0, max(-104.0 - z, 0.0)) - smoothstep(0.0, 2.0, max(z - 48.0, 0.0))
    return mx * max(mz, 0.0)


def herb_mask(x, z):
    mx = 1.0 - smoothstep(0.0, 6.0, max(21.0 - x, x - 64.0, 0.0))
    mz = 1.0 - smoothstep(0.0, 6.0, max(-34.0 - z, z - 47.0, 0.0))
    return mx * max(mz, 0.0)


def bluff_top(x, z):
    """Natural ground on top of the bluffs and the hills behind."""
    inland = smoothstep(-95.0, -330.0, z)
    hills = 46.0 * inland + 26.0 * fbm(x, z, 140.0) * inland
    canyon = -14.0 * max(0.0, 1.0 - abs(fbm(x + 400.0, z, 95.0, 3)) * 3.0) * inland
    rolling = 2.6 * fbm(x, z, 45.0) + 0.7 * fbm(x, z, 11.0, 5)
    headland_drop = -16.0 * headland(x) * smoothstep(40.0, 150.0, z)
    return PLATEAU_Y + 1.0 + hills + canyon + rolling + headland_drop


def height(x, z):
    top = bluff_top(x, z)
    top += (HERB_Y - top) * herb_mask(x, min(z, 46.0))  # the bluff below the herb terraces is lower
    ze = cliff_edge(x)
    w = cliff_width(x)
    bw = beach_width(x)
    if z <= ze:
        h = top - 4.0 * smoothstep(ze - 20.0, ze, z) * (1.0 - site_mask(x, ze - 10.0))  # rounded lip, except at the villa
    else:
        t = min((z - ze) / w, 1.0)
        # convex lip, steep face, then a short talus apron
        g = 1.0 - (1.0 - t) ** 1.7
        g = 0.82 * smoothstep(0.0, 0.78, t) ** 0.85 + 0.18 * g
        ledge = 0.05 * math.sin(t * math.pi * 3.0) * (1 - t)
        foot = BEACH_BACK_Y if bw > 1.0 else SEA_Y - 4.0
        top -= 4.0 * (1.0 - site_mask(x, ze - 10.0))
        # vertical gullies and buttresses down the face, strongest mid-height
        gully = 6.0 * fbm(x * 3.0, z * 0.4, 12.0) + 2.5 * fbm(x * 2.0, z, 5.0)
        h = top + (foot - top) * min(1.0, g + ledge) + gully * (1 - abs(2 * t - 1))
        if z > ze + w:  # beach, then the sea floor
            d = z - (ze + w)
            if d < bw:
                h = BEACH_BACK_Y + (SEA_Y - 0.4 - BEACH_BACK_Y) * (d / max(bw, 1.0)) ** 1.3 + 0.15 * fbm(x, z, 6.0)
            else:
                h = SEA_Y - 0.4 - 0.09 * (d - bw) - 6.0 * smoothstep(0.0, 160.0, d - bw)
    site = site_mask(x, z)
    level = PLATEAU_Y + (HERB_Y - PLATEAU_Y) * herb_mask(x, z)
    return h * (1.0 - site) + level * site
