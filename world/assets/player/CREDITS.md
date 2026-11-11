# Player mannequin

The mannequin, skin weights, materials, and locomotion clips come from Quaternius's
Universal Animation Library Standard, released under CC0 1.0 Universal. Euclid uses the
in-place GLB and adds a cropped first-person mesh and its own hand poses.

Run background Blender with `--factory-startup --python scripts/blender/build_player_model.py`
followed by `-- <path to Unreal-Godot/UAL1_Standard.glb> world/assets/player` to regenerate the GLBs.

[Quaternius](https://quaternius.com/) · [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/)
