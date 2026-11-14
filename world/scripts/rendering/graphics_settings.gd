extends RefCounted
const Packages = preload("res://scripts/zones/zone_packages.gd")
## Cost budgets belong here, not in the art builders. Both profiles retain the authored effects.
const PATH := "user://graphics.cfg"
const PROFILES := {
	"balanced": {"label":"Balanced", "msaa":Viewport.MSAA_DISABLED, "shadow_size":4096},
	"cinematic": {"label":"Cinematic", "msaa":Viewport.MSAA_4X, "shadow_size":8192},
}
static var current := "balanced"
## What agents show above their heads (agents/activity_card.gd): full, icons or off.
const AGENT_ACTIVITY := ["full", "icons", "off"]
static var agent_activity := "full"
## Whether those panels show the code itself; off draws bars in its place, for recording or streaming.
static var show_code := true
## Whether agents' chat replies are spoken aloud while the chat window is closed (voice must be on).
static var speak_replies := true

static func configure(viewport: Viewport, automated: bool) -> void:
	current = "balanced"
	if not automated:
		var config := ConfigFile.new()
		if config.load(PATH) == OK:
			current = str(config.get_value("graphics", "profile", "balanced"))
			agent_activity = str(config.get_value("agents", "activity", "full"))
			show_code = bool(config.get_value("agents", "show_code", true))
			speak_replies = bool(config.get_value("agents", "speak_replies", true))
	if agent_activity not in AGENT_ACTIVITY:
		agent_activity = "full"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--quality="):
			current = arg.trim_prefix("--quality=")
	if not PROFILES.has(current):
		push_warning("Unknown graphics profile; using Balanced")
		current = "balanced"
	apply(viewport)

static func apply(viewport: Viewport) -> void:
	if RenderingServer.get_current_rendering_method() == "forward_plus":
		viewport.msaa_3d = PROFILES[current].msaa
		RenderingServer.directional_shadow_atlas_set_size(PROFILES[current].shadow_size, true)

static func apply_zone(world: Node3D, zone: String) -> void:
	if RenderingServer.get_current_rendering_method() != "forward_plus":
		return
	var viewport := world.get_viewport()
	var balanced_villa: bool = Packages.definition(zone).graphics.get("balanced_reconstruction", false) and current == "balanced"
	viewport.mesh_lod_threshold = 6.0 if balanced_villa else 1.0
	if balanced_villa:
		# Reconstruct the 3D image at window size; UI remains at native resolution.
		viewport.use_taa = false
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
		viewport.scaling_3d_scale = 0.75
		world.sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		world.sun.directional_shadow_max_distance = 38.0
		world.environment.ssr_max_steps = 40
	else:
		viewport.scaling_3d_scale = 1.0
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		viewport.use_taa = true
	var default_filter: int = ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality")
	RenderingServer.directional_soft_shadow_filter_set_quality(
		RenderingServer.SHADOW_QUALITY_SOFT_LOW if balanced_villa else default_filter)

static func select(profile: String, viewport: Viewport) -> void:
	assert(PROFILES.has(profile))
	current = profile
	apply(viewport)
	_save()

## Speak agents' chat replies while the chat window is closed, or only inside chat.
static func set_speak_replies(on: bool) -> void:
	speak_replies = on
	_save()

## Set what agents show above their heads, and whether their panels show code.
static func set_agent_activity(mode: String, code: bool) -> void:
	assert(mode in AGENT_ACTIVITY)
	agent_activity = mode
	show_code = code
	_save()

static func _save() -> void:
	var config := ConfigFile.new()
	config.load(PATH)
	config.set_value("graphics", "profile", current)
	config.set_value("agents", "activity", agent_activity)
	config.set_value("agents", "show_code", show_code)
	config.set_value("agents", "speak_replies", speak_replies)
	config.save(PATH)

static func label() -> String:
	return PROFILES[current].label
