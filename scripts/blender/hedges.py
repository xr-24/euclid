"""Clipped box hedges built from leaf cards (disposable Blender only).

A hedge is a dark core box (collision, and the shadowed interior you glimpse between leaves) clad
in thousands of small alpha-tested cards, each carrying a sprig of small oval leaves from a
generated atlas. Cards lie roughly flat on the clipped faces with random tilt and spin, and share
the face's normal so the hedge shades as one soft volume instead of a field of flat quads.

leaf_atlas() writes the atlas (colour with alpha, and a normal map) generated with numpy, so the
hedges need no external texture. Everything here is original procedural content.
"""
import math
import random
from pathlib import Path

import bpy
import numpy as np

import arch_kit as kit

CELLS = 4          # atlas is CELLS x CELLS sprigs
CARD = (0.12, 0.2)   # card edge length range (m)
DENSITY = 150.0    # cards per square metre of hedge surface


def leaf_atlas(color_path: Path, normal_path: Path, size=1024, seed=7):
    rng = np.random.default_rng(seed)
    rgba = np.zeros((size, size, 4), np.float32)
    nrm = np.zeros((size, size, 3), np.float32)
    nrm[..., 2] = 1.0
    cell = size // CELLS
    yy, xx = np.mgrid[0:cell, 0:cell].astype(np.float32)
    for cy in range(CELLS):
        for cx in range(CELLS):
            col = np.zeros((cell, cell, 4), np.float32)
            nr = np.zeros((cell, cell, 3), np.float32)
            nr[..., 2] = 1.0
            depth = np.full((cell, cell), -1.0, np.float32)
            for _ in range(int(rng.integers(26, 38))):
                # a small oval leaf: centre, half-length, half-width, rotation
                r = rng.uniform(0, cell * 0.36)
                t = rng.uniform(0, math.tau)
                px, py = cell / 2 + r * math.cos(t), cell / 2 + r * math.sin(t)
                a, b = rng.uniform(cell * 0.075, cell * 0.12), rng.uniform(cell * 0.035, cell * 0.055)
                rot = rng.uniform(0, math.pi)
                c, s = math.cos(rot), math.sin(rot)
                u = ((xx - px) * c + (yy - py) * s) / a
                v = (-(xx - px) * s + (yy - py) * c) / b
                d = u * u + v * v
                inside = d < 1.0
                z = rng.uniform(0, 1)  # stacking order
                take = inside & (z > depth)
                if not take.any():
                    continue
                depth[take] = z
                shade = rng.uniform(0.72, 1.18)
                base = np.array([0.085, 0.20, 0.055]) * shade
                tip = np.array([0.16, 0.30, 0.08]) * shade
                g = np.clip((u + 1) / 2, 0, 1)[..., None]
                leaf = base * (1 - g) + tip * g
                rib = np.exp(-(v * 6.0) ** 2)[..., None] * 0.25
                leaf = leaf * (1 - rib) + leaf * 0.55 * rib
                edge = np.clip((1.0 - d) * 6.0, 0, 1)
                col[take, :3] = leaf[take]
                col[take, 3] = np.maximum(col[take, 3], edge[take])
                # domed leaf normal, tilted along the leaf by its local coordinates
                nx = (u * c - v * s) * 0.45
                ny = (u * s + v * c) * 0.45
                n = np.stack([nx, ny, np.ones_like(nx)], -1)
                n /= np.linalg.norm(n, axis=-1, keepdims=True)
                nr[take] = n[take]
            rgba[cy * cell:(cy + 1) * cell, cx * cell:(cx + 1) * cell] = col
            nrm[cy * cell:(cy + 1) * cell, cx * cell:(cx + 1) * cell] = nr
    # Bleed leaf colour into transparent texels so mipmaps don't fringe dark.
    rgba[..., :3] = np.where(rgba[..., 3:4] > 0, rgba[..., :3], np.array([0.08, 0.17, 0.05]))
    _save(rgba, color_path, alpha=True)
    _save(np.concatenate([nrm * 0.5 + 0.5, np.ones((size, size, 1), np.float32)], -1), normal_path, alpha=False)


def _save(pixels, path, alpha):
    path.parent.mkdir(parents=True, exist_ok=True)
    h, w = pixels.shape[:2]
    img = bpy.data.images.new(path.stem, w, h, alpha=alpha)
    img.pixels.foreach_set(np.flipud(pixels).astype(np.float32).ravel())
    img.filepath_raw = str(path)
    img.file_format = 'PNG'
    img.save()


class HedgeBuilder:
    """Collects hedge boxes, then emits one core mesh (COL_) and one leaf-card mesh."""

    def __init__(self, seed=11):
        self.rng = random.Random(seed)
        self.verts, self.faces, self.uvs, self.normals = [], [], [], []

    def add(self, x0, x1, z0, z1, height, base_y=0.0):
        x0, x1 = min(x0, x1), max(x0, x1)
        z0, z1 = min(z0, z1), max(z0, z1)
        inset = 0.05
        kit.box('COL_Hedge core', x0 + inset, x1 - inset, base_y, base_y + height - inset, z0 + inset, z1 - inset, 'Hedge core')
        top = base_y + height
        # (origin, axis u, axis v, normal) for the clipped faces: top and four sides
        faces = [((x0, top, z0), (x1 - x0, 0, 0), (0, 0, z1 - z0), (0, 1, 0)),
                 ((x0, base_y, z0), (x1 - x0, 0, 0), (0, height, 0), (0, 0, -1)),
                 ((x0, base_y, z1), (x1 - x0, 0, 0), (0, height, 0), (0, 0, 1)),
                 ((x0, base_y, z0), (0, 0, z1 - z0), (0, height, 0), (-1, 0, 0)),
                 ((x1, base_y, z0), (0, 0, z1 - z0), (0, height, 0), (1, 0, 0))]
        for origin, du, dv, n in faces:
            area = math.dist((0, 0, 0), du) * math.dist((0, 0, 0), dv)
            for _ in range(int(area * DENSITY)):
                s, t = self.rng.random(), self.rng.random()
                p = [origin[i] + du[i] * s + dv[i] * t for i in range(3)]
                if n[1] == 0:  # sides: fewer cards near the ground, where hedges thin out
                    if (p[1] - base_y) / height < 0.12 and self.rng.random() < 0.6:
                        continue
                self._card(p, n, top)

    def _card(self, p, n, top):
        rng = self.rng
        n = np.array(n, float)
        # a tangent frame around the (tilted) normal
        tilt = np.array([rng.uniform(-0.6, 0.6), rng.uniform(-0.6, 0.6), rng.uniform(-0.6, 0.6)])
        cn = n + tilt * (1 - abs(n @ tilt) * 0.2)
        cn /= np.linalg.norm(cn)
        ref = np.array([0, 1, 0]) if abs(cn[1]) < 0.9 else np.array([1, 0, 0])
        t1 = np.cross(ref, cn); t1 /= np.linalg.norm(t1)
        t2 = np.cross(cn, t1)
        spin = rng.uniform(0, math.tau)
        a = t1 * math.cos(spin) + t2 * math.sin(spin)
        b = np.cross(cn, a)
        size = rng.uniform(*CARD) / 2
        c = np.array(p) + n * rng.uniform(-0.02, 0.06)
        # rounded clipped edges: pull cards near the top edge down and outward a little
        if n[1] == 0 and top - c[1] < 0.08:
            c[1] -= 0.03
        corners = [c - a * size - b * size, c + a * size - b * size, c + a * size + b * size, c - a * size + b * size]
        cell = rng.randrange(CELLS * CELLS)
        u0, v0 = (cell % CELLS) / CELLS, (cell // CELLS) / CELLS
        d = 1 / CELLS
        uv = [(u0, v0), (u0 + d, v0), (u0 + d, v0 + d), (u0, v0 + d)]
        shade_n = n * 0.85 + np.array([0, 0.35, 0])  # soft volume normal, a little skyward
        shade_n /= np.linalg.norm(shade_n)
        i = len(self.verts)
        for k in range(4):
            self.verts.append(tuple(corners[k]))
            self.uvs.append(uv[k])
            self.normals.append(tuple(shade_n))
        self.faces.append((i, i + 1, i + 2, i + 3))

    def finish(self):
        if self.verts:
            kit.mesh_obj('Hedge leaves', self.verts, self.faces, 'Hedge leaves', uvs=self.uvs, normals=self.normals)
        return len(self.faces)
