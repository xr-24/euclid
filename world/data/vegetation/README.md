# Vegetation and rock scatter rules

Each file scatters library models (world/assets/library/catalog.json) over a generated height
field, read by world/scripts/scatter.gd. Copies of one model are drawn together (one multimesh per
model part), so thousands of plants stay cheap. Placement is seeded: the same file always gives
the same landscape.

```json
{
 "schema_version": 1,
 "seed": 11,
 "rules": [
  {"asset": "crystalline_iceplant", "count": 1500, "y": [-77, 20], "slope": [0.45, 0.97],
   "noise": {"scale": 25, "threshold": 0.45}, "spacing": 1.3, "scale": [0.9, 1.8],
   "align": 0.9, "sink": 0.02, "range": 85, "shadows": false}
 ]
}
```

- `asset`: a catalog id; rules for missing models are skipped.
- `count`: how many to place (fewer if the area can't hold them).
- `region` (optional): `[x0, x1, z0, z1]` in metres; default is the whole height field.
- `y`: allowed ground height band. `slope`: allowed range of the ground normal's y (1 = flat,
  0 = vertical).
- `noise` (optional): clumping; a spot is used only where smooth noise of that `scale` (metres)
  exceeds `threshold` (0..1).
- `spacing`: minimum distance between two copies.
- `scale`: random uniform scale range. `align`: 0 stands upright, 1 follows the slope.
  `sink`: metres pushed into the ground (times the scale).
- `range`: distance (m) beyond which the copies fade out; 0 keeps them always.
- `shadows` (default true). `collider` / `collider_height` (optional): a cylinder of that radius
  and height for each copy, for trunks and boulders.
- Keys starting with `_` are comments. The zone code supplies the areas to keep clear (buildings,
  gardens).

Files: `villa_coast.json` (the coast round Villa Aurelia).
