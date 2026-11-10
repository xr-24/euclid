extends SceneTree
## Rendered captures of the Workbench editor and Codex console text effects. The Workbench runs
## against an in-process stand-in for the gateway that reads files and never writes. The normal
## world save is not loaded, and kept buffers go to the capture folder rather than the user's.
## Frames go to EUCLID_CAPTURE_DIR.
const WorkbenchPanel = preload("res://scripts/ui/workbench_panel.gd")
const CodexConsole = preload("res://scripts/ui/codex_console.gd")
const Look = preload("res://scripts/ui/terminal_theme.gd")

var _viewport: SubViewport
var _output := ""

class ReadOnlyGateway extends "res://scripts/agents/workbench_client.gd":
	func send(action: String, arguments := {}) -> Dictionary:
		await get_tree().process_frame
		match action:
			"catalog":
				var files := PackedStringArray()
				for folder in ["scripts", "scripts/ui", "scripts/zones", "scripts/workshop", "shaders", "data"]:
					for name in DirAccess.get_files_at("res://" + folder):
						if name.get_extension() in ["gd", "gdshader", "json"]:
							files.append("world/%s/%s" % [folder, name])
				return {"files": files}
			"read":
				var text := FileAccess.get_file_as_string("res://" + str(arguments.name).trim_prefix("world/"))
				return {"text": text, "hash": text.sha256_text()}
		return {}

func _initialize() -> void:
	call_deferred("_run")

func _frames(count: int) -> void:
	for index in count:
		await process_frame

func _capture(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	_viewport.get_texture().get_image().save_png(_output.path_join(label + ".png"))
	print("captured ", label)

func _run() -> void:
	_output = OS.get_environment("EUCLID_CAPTURE_DIR")
	if _output.is_empty():
		_output = ProjectSettings.globalize_path("user://text-tools-capture")
	DirAccess.make_dir_recursive_absolute(_output)
	WorkbenchPanel.saved_buffers_path = _output.path_join("workbench-buffers.json")
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1440, 900)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var backdrop := ColorRect.new()
	backdrop.color = Color("0b1622")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_viewport.add_child(backdrop)
	var frame := PanelContainer.new()
	var style := Look.frame_style()
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	frame.add_theme_stylebox_override("panel", style)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 68
	frame.offset_top = 55
	frame.offset_right = -68
	frame.offset_bottom = -55
	_viewport.add_child(frame)
	var panel := WorkbenchPanel.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(panel)
	panel.setup("http://127.0.0.1:9", "capture", "capture", func(_c: Dictionary) -> Dictionary: return {},
		func(_a: String, _b: String) -> Dictionary: return {}, func(_id: String) -> String: return "",
		func() -> Dictionary: return {})
	await _frames(4)
	var gateway := ReadOnlyGateway.new()
	panel.add_child(gateway)
	panel._client.queue_free()
	panel._client = gateway
	panel._busy = false
	await panel._load_catalog()
	await panel._select_file("world/shaders/ui_glow.gdshader")
	await panel._select_file("world/scripts/scatter.gd")
	await _frames(8)
	await _capture("01_reveal")
	await _frames(30)
	var editor = panel._current_editor()
	editor.set_caret_line(20)
	editor.set_caret_column(editor.get_line(20).length())
	await _frames(20)
	for glyph in "\n\tvar glow_strength := clampf(intensity * 1.6, 0.0, 4.0)":
		editor.insert_text_at_caret(glyph)
		await _frames(1)
	await _capture("02_typing")
	await _frames(40)
	editor.select(14, 0, 17, 0)
	await _frames(2)
	editor.delete_selection()
	await _frames(5)
	await _capture("03_delete")
	await _frames(40)
	editor.set_caret_line(8)
	editor.set_caret_column(0)
	await _frames(1)
	editor.set_caret_line(46)
	editor.set_caret_column(12)
	await _frames(2)
	await _capture("04_caret_motion")
	await _frames(40)
	panel._on_editor_command("find")
	panel._find._query.text = "tile"
	panel._find._refresh()
	panel._find.find_next()
	await _frames(20)
	await _capture("05_find")
	panel._find.close()
	editor.deselect()
	editor.set_caret_line(22)
	editor.set_caret_column(editor.get_line(22).length())
	editor.insert_text_at_caret("\n\tvar t := Vec")
	await _frames(2)
	editor.request_code_completion(true)
	await _frames(20)
	await _capture("06_completion")
	editor.cancel_code_completion()
	var diff := "diff --git a/world/scripts/scatter.gd b/world/scripts/scatter.gd\n@@ -18,6 +18,7 @@\n var tiles := {}\n-var range := 40.0\n+var range := 48.0\n+var glow_strength := 1.6\n func apply() -> void:\n"
	var log := "Godot check started\nSCRIPT ERROR: Parse Error: Identifier \"intensity\" not declared.\n   at: GDScript::reload (res://scripts/scatter.gd:22)\nCONSTRUCT_SMOKE: 12 checks\nCONSTRUCT_CORE_TESTS_OK\n"
	panel._show_state({"draft": {"id": "capture", "name": "Tune scatter glow", "status": "failed", "error": "Godot check failed.",
		"diff": diff, "log": log, "files": ["world/scripts/scatter.gd"], "activation": "restart"}})
	panel.show_review(false)
	await _frames(30)
	await _capture("07_diff")
	panel.show_review(true)
	await _frames(30)
	await _capture("08_checks")
	panel.show_review(false)
	panel._tabs.current_tab = 0
	await _frames(20)
	await _capture("09_error_marker")
	frame.queue_free()
	await _frames(2)
	var shell := PanelContainer.new()
	shell.add_theme_stylebox_override("panel", Look.frame_style())
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shell.offset_left = 835
	shell.offset_top = 96
	shell.offset_right = -46
	shell.offset_bottom = -108
	_viewport.add_child(shell)
	var console := CodexConsole.new()
	console.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(console)
	var lines := PackedStringArray(["Euclid uplink ready.", "> Where can we go?", "The Grid, the Roman villa and the shore are available."])
	console.setup(lines, false, false)
	await _frames(10)
	lines.append("> Take me to the Roman villa")
	lines.append("Shifting to the Roman villa. Hold still while the construct resolves around you.")
	console.update_display(lines, false)
	await _frames(12)
	await _capture("10_console_typing")
	for glyph in "Spawn a piece of pizza":
		console._entry.insert_text_at_caret(glyph)
		await _frames(1)
	await _frames(20)
	await _capture("11_console_prompt")
	print("CONSTRUCT_TEXT_TOOLS_CAPTURE_OK")
	quit()
