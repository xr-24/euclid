extends RefCounted
## Render layers every zone shares. Cameras pick what they draw by these bits, and so does each
## light (a light whose layer is outside a camera's cull mask neither lights nor casts shadows
## in that camera's view, Godot 4.4 and later).
##
## Reflections are the expensive case: a mirror redraws the scene. Keep fine, alpha-tested or
## shadowless detail (leaf cards, small plants, the first-person arms) on REFLECTION_HIDDEN, and a
## mirror lights its view with its own unshadowed copy of the sun on MIRROR_LIGHT instead of
## rendering the sun's shadow cascades a second time.

const SCENE := 1                    # layer 1: geometry every camera draws
const SUN := 1 << 1                 # layer 2: the shadowed sun, for the main view only
const REFLECTION_HIDDEN := 1 << 2   # layer 3: drawn in the main view, never in reflections
const MIRROR_LIGHT := 1 << 10       # layer 11: lights that exist only for reflections
const ALL := (1 << 20) - 1

## What the player's camera draws: everything except the lights meant only for mirrors.
const MAIN_VIEW := ALL & ~MIRROR_LIGHT
## What a mirror draws: ordinary geometry, lit by mirror lights.
const MIRROR_VIEW := SCENE | MIRROR_LIGHT
