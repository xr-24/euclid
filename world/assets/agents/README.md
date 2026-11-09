# Agent projection body

`projection_body.glb` is a posed adult feminine MakeHuman body generated with
MPFB 2.0.18. Its base mesh and morph targets are MakeHuman Community core assets
under CC0. No skin textures or third-party clothing are included.

- Asset license https://static.makehumancommunity.org/about/license.html
- Generator https://github.com/makehumancommunity/mpfb2
- Source revision `d0a32e57a7f915cb2f2b95410e2117648c7bbb7e` (tag `v2.0.18`)
- Editable rig and morphs `assets/source/agent_projection.blend`
- Build script `scripts/blender/build_agent_avatar.py`

From the project root, clone the pinned generator into the ignored build cache
and build in disposable Blender. The generator's GPL code is a build dependency.
Only the generated CC0 mesh is included in the runtime.

```powershell
git clone --depth 1 --branch v2.0.18 https://github.com/makehumancommunity/mpfb2.git .local/euclid-mpfb/mpfb2
$env:BLENDER_USER_RESOURCES = "$PWD/.local/euclid-mpfb/blender-user"
& $env:BLENDER_BIN --background --factory-startup --python-exit-code 1 --python scripts/blender/build_agent_avatar.py -- --mpfb-root .local/euclid-mpfb/mpfb2
```

Set `BLENDER_BIN` to the Blender executable before running this command. The
build creates the editable source and exports an anatomical `ProjectionBody`
and 22,000 independently sampled `ProjectionPoints` splats. Both have identity
transforms, approximately two metres tall, facing Godot +Z. Only the splats are
returned by `AvatarMesh.build()`. The anatomical surface is a build reference.
The shared GLB mesh remains immutable, while each agent has its own shader
material. The point colors encode the source normal in RGB and a stable random
seed in alpha. UVs define the camera-facing splat. Keep automatic mesh LOD and
shadow-mesh generation disabled for this asset so the tiny carrier quads survive.

The Blender source contains the 6.4-second `Hover` action on the editable rig.
The build samples the lift and drift poses and exports two signed blend shapes.
Godot loops their weights and applies the same motion to the filament roots.
The exported splats also carry four bone influences sampled from the source
body. Godot binds the splats and filament roots to one skeleton so agent-authored
joint clips can play live. The default loop still uses the original pose weights.
The body and filament shaders share `avatar_signal.gdshaderinc` for object-space
signal corruption. The shader's face and shoulder masks and separate hair mesh
are calibrated to this body's local coordinates. Recheck these together after
editing the proportions or pose. Set both materials' `signal_time` to the same
nonnegative value for a reproducible still, or leave it at -1 for normal motion.
