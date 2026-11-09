extends RefCounted
## A generated landscape's height field (written by the Blender build next to the terrain mesh), so
## the game can stand rocks and plants on the ground without raycasting the mesh: bilinear height,
## surface normal and bounds. Format: <name>.json {x0, z0, step, nx, nz} and <name>.bin, nz rows of
## nx little-endian float32 heights.

var x0 := 0.0
var z0 := 0.0
var step := 1.0
var nx := 0
var nz := 0
var heights := PackedFloat32Array()
var info := {}

## Load from the .json path (the .bin sits beside it). Returns false when either file is missing.
func load_from(json_path: String) -> bool:
	var bin_path := json_path.get_basename() + ".bin"
	if not FileAccess.file_exists(json_path) or not FileAccess.file_exists(bin_path):
		return false
	info = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	x0 = info.x0
	z0 = info.z0
	step = info.step
	nx = int(info.nx)
	nz = int(info.nz)
	heights = FileAccess.get_file_as_bytes(bin_path).to_float32_array()
	return heights.size() == nx * nz

func contains(x: float, z: float) -> bool:
	return x >= x0 and z >= z0 and x <= x0 + (nx - 1) * step and z <= z0 + (nz - 1) * step

func height(x: float, z: float) -> float:
	var fx := clampf((x - x0) / step, 0.0, nx - 1.001)
	var fz := clampf((z - z0) / step, 0.0, nz - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * nx + ix
	var a := lerpf(heights[i], heights[i + 1], tx)
	var b := lerpf(heights[i + nx], heights[i + nx + 1], tx)
	return lerpf(a, b, tz)

func normal(x: float, z: float) -> Vector3:
	var d := step
	var hx := height(x + d, z) - height(x - d, z)
	var hz := height(x, z + d) - height(x, z - d)
	return Vector3(-hx, 2.0 * d, -hz).normalized()
