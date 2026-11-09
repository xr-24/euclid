# Asset library

Placeable models (statues, busts, sarcophagi, and every Poly Haven prop, tree and rock) that any
zone can use by id. A future "build your own environment" mode can list and place anything here
without new code.

## Layout

```
world/assets/library/
  catalog.json          generated index of every placeable model (Poly Haven ones included)
  CREDITS.md            generated attribution for every library model
  cc-by/<id>/           <id>.glb + asset.json; free for any use with credit
  cc-by-nc/<id>/        non-commercial only
  cc-by-nc-sa/<id>/     non-commercial only, and share-alike for modified versions
```

Each licence folder has a generated README.md saying what that licence allows. Models are kept
apart by licence so a whole class can be removed in one step: delete `cc-by-nc/` and
`cc-by-nc-sa/` before selling Construct, monetising it, or publishing it under an open-source
licence, then rebuild the catalog. Zones skip models that are no longer in the catalog.

Every model follows the same conventions: metres, the base at y = 0, the footprint centred on
the origin, and the front facing +Z.

## Adding a model

1. Add an entry to `scripts/assets/sketchfab.json`: `id`, Sketchfab `uid`, `title`, `category`,
   `tags`, `fit` (`{"height": m}` or `{"length": m}` for real-world size), triangle `budget` and
   maximum `texture` edge. Licence and author are not typed in; they are read from Sketchfab.
2. `python scripts/assets/fetch_sketchfab.py <id>` (needs `SKETCHFAB_API_TOKEN` or
   `.local/sketchfab-key.txt`). Only CC0 and CC BY family licences are accepted.
3. `blender --background --factory-startup --python scripts/blender/build_library.py -- <id> --preview`
   and check `.local/library-previews/<id>_front.png`. If the figure does not face the camera,
   add `"rotate": [0, 0, 90]` (or -90, 180) to its entry and build again.
4. `python scripts/assets/build_catalog.py`, then let Godot import.
5. Place it: add an item to a dressing file in `world/data/dressing/` (see the README there), or
   in code with `AssetLibrary.instance(id)` (`world/scripts/asset_library.gd`).

`scripts/build-assets.ps1` runs steps 2-4 for the whole library.
