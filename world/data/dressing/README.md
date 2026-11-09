# Zone dressing files

Each file places models from the asset library (world/assets/library/catalog.json) into a zone.
They are plain data, read by world/scripts/scene_dressing.gd, so statues and props can be moved,
added or swapped without touching code, and a new zone can be furnished the same way.

```json
{
 "schema_version": 1,
 "plinths": {"statue": {"size": [0.95, 0.42, 0.95], "material": "marble"}},
 "items": [
  {"asset": "apollo_belvedere", "position": [-18.5, 0.15, -17], "yaw": 90, "plinth": "statue"}
 ]
}
```

- `asset`: a catalog id. Items whose model is missing (for example after removing a licence
  folder) are skipped.
- `position`: the floor point, in metres, that the item (or its plinth) stands on.
- `yaw`: degrees about the vertical axis. Every library model faces +Z at yaw 0; 90 turns it to
  face +X.
- `plinth` (optional): a named box from `plinths`, placed under the model and turned with it.
  Its `material` is a name the zone code supplies (the villa provides `marble`).
- `height` (optional): rescale the model to this many metres tall. `scale` multiplies on top.
- `finish` (optional): replace every surface of the model with a named material the zone code
  supplies (the villa provides `bronze`), e.g. to cast a marble scan in bronze.
- `collision` (optional): `"box"` (default) or `"none"`.
- Keys starting with `_` are comments and are ignored.

Files: `villa.json` (Villa Aurelia's statuary).
