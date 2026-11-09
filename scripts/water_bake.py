"""Water data bakes independent of Blender; binary layout matches SimController's RGBA32F grids."""
import json
from pathlib import Path
import numpy as np


def bake_pool(output, pool, floor, water_y, *, ramp_length=3.4):
    output = Path(output)
    x0, x1, z0, z1 = pool
    n, dx = 640, 0.08
    size = n * dx
    # Dry margins keep every wet cell out of the two-cell mirror boundary stencil.
    ox, oz = (x0 + x1 - size) / 2, (z0 + z1 - size) / 2
    jj, ii = np.meshgrid(np.arange(n), np.arange(n), indexing='ij')
    wx, wz = ox + (jj+0.5) * dx, oz + (ii+0.5) * dx
    inside = (wx > x0) & (wx < x1) & (wz > z0) & (wz < z1)
    # Match the south-end entry ramp in the villa collision geometry.
    basin = floor + np.clip((wz - (z1 - ramp_length)) / ramp_length, 0, 1) * -floor
    # Vertical coping is a solid boundary, not a sloping, partially wet terrain cell.
    centre = np.where(inside, basin-water_y, 0.3).astype(np.float32)
    padded = np.pad(centre, 1, mode='edge')
    east_neighbour, north_neighbour = padded[1:n+1,2:n+2], padded[2:n+2,1:n+1]
    def face(other):
        return np.where(centre >= 0.0, other,
            np.where(other >= 0.0, centre, (centre+other)*0.5))
    east, north = face(east_neighbour), face(north_neighbour)
    neighbours = [padded[1+a:1+a+n, 1+b:1+b+n] for a in (-1,0,1) for b in (-1,0,1)]
    nb_max = np.max([np.where(neighbour >= 0.0,centre,neighbour) for neighbour in neighbours], axis=0)
    bottom = np.stack([centre, east, north, nb_max], axis=-1).astype('<f4')
    state = np.zeros_like(bottom)
    state[..., 0] = np.maximum(centre, 0)
    assert np.all(centre[:3] > 0) and np.all(centre[-3:] > 0)
    assert np.all(centre[:, :3] > 0) and np.all(centre[:, -3:] > 0)
    output.mkdir(parents=True, exist_ok=True)
    (output / 'villa_pool_bottom.bin').write_bytes(bottom.tobytes())
    (output / 'villa_pool_state.bin').write_bytes(state.tobytes())
    (output / 'villa_pool.json').write_text(json.dumps(dict(
        n=n, dx=dx, x0=ox, z0=oz, water_y=water_y, pool=pool), indent=1))


if __name__ == '__main__':
    root = Path(__file__).resolve().parents[1]
    output = root / 'world/assets/generated'
    layout = json.loads((output / 'villa_layout.json').read_text())
    bake_pool(output, layout['pool'], layout.get('pool_floor', -0.62), layout['water_y'],
              ramp_length=layout.get('pool_ramp_length', 3.4))
