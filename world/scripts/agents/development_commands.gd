extends RefCounted
## Trusted command handlers receive the application coordinator as their explicit host.

const WorkbenchDiagnostics = preload("res://scripts/ui/workbench_diagnostics.gd")

var _world: Node3D

func _init(world: Node3D) -> void:
	_world = world

func execute(definition: Dictionary, request: Dictionary) -> void:
	if has_method(definition.handler):
		await call(definition.handler, definition, request)
	else:
		_world._console_notice("The registered development handler is unavailable.")

func _request_development_draft(definition: Dictionary, request: Dictionary) -> void:
	if definition.get("scope") == "scene":
		var available: bool = _world._shoreline.available() if definition.availability == "shoreline_preview" else _world._grid_scenery.available()
		if not available:
			_world._console_notice("This environment can no longer preview that change.")
			return
	var context: Dictionary = _world._workbench_plugin_context() if definition.get("workshop_context", false) else {}
	var result: Dictionary = await _world._development.request(definition, request.prompt, context)
	if result.has("error"):
		_world._console_notice(result.error)
	elif result.draft.status == "authoring":
		_world._console_notice("Codex is working in a separate source workspace. Open Workbench to see progress.")
	else:
		var summary: String = result.draft.get("summary", "")
		if not summary.is_empty():
			_world._console_notice(summary)
		if result.draft.status == "checking":
			_world._console_notice("Review the diff while the checks run.")

func _revise_command(_definition: Dictionary, request: Dictionary) -> void:
	var reviewed: Dictionary = request.reviewed
	var output: String = _world._palette_host.error_log(reviewed.id, reviewed.version)
	var result: Dictionary = await _world._development.revise(request.prompt, reviewed, output)
	if result.has("error"):
		_world._console_notice(result.error)

func _benchmark_command(_definition: Dictionary, request: Dictionary) -> void:
	var result: Dictionary = await _world._run_workbench_benchmark("benchmark", request.benchmark)
	if result.has("error"):
		_world._console_notice(result.error)

func _villa_results_command(_definition: Dictionary, _request: Dictionary) -> void:
	await _world._development.refresh()
	if _world._development.diagnostic_job.is_empty():
		_world._console_notice(WorkbenchDiagnostics.summary(_world._development.diagnostic))
	else:
		_world._console_notice("The villa benchmark is still running.")
