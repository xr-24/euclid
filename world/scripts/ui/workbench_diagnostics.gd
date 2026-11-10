extends VBoxContainer
## Renders the Workbench's saved benchmark evidence.

const VIEWS := ["Arrival", "Pool", "Portico"]

var _run := Button.new()
var _cancel := Button.new()
var _artifacts := Button.new()
var _output := TextEdit.new()
var _directory := ""

func setup(run: Callable, cancel: Callable) -> void:
	name = "Diagnostics"
	var row := HBoxContainer.new()
	add_child(row)
	_run.text = "Benchmark villa"
	_run.pressed.connect(run)
	row.add_child(_run)
	_cancel.text = "Cancel"
	_cancel.pressed.connect(cancel)
	row.add_child(_cancel)
	_artifacts.text = "Open captures and logs"
	_artifacts.pressed.connect(func() -> void: OS.shell_open(_directory))
	row.add_child(_artifacts)
	_output.editable = false
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_output)
	update({}, false)

func update(state: Dictionary, busy: bool) -> void:
	var draft: Variant = state.get("draft")
	var job: Variant = state.get("diagnostic_job")
	var report: Variant = state.get("diagnostic")
	var is_running := job is Dictionary
	_run.disabled = busy or state.get("playing", false) or (draft is Dictionary and draft.status != "passed")
	_run.tooltip_text = "Measures arrival, pool and portico at 1920×1080 Balanced. A checked draft runs both builds."
	_cancel.visible = is_running
	_cancel.disabled = not is_running
	_directory = report.get("directory", "") if report is Dictionary else ""
	_artifacts.disabled = _directory.is_empty()
	var text := "1920×1080  ·  Balanced  ·  Arrival, pool, portico"
	if draft is Dictionary and draft.status != "passed":
		text += "\nRun the draft checks before measuring both builds."
	if is_running:
		text += "\n\n" + job.log
	else:
		if not str(state.get("diagnostic_notice", "")).is_empty():
			text += "\n\n" + state.diagnostic_notice
		if report is Dictionary:
			text += "\n\n" + _format_report(report)
	var preview_log: String = state.get("preview_log", "")
	if not preview_log.is_empty():
		text += "\n\nPreview output\n" + preview_log
	var live_output: String = state.get("live_preview_log", "")
	if not live_output.is_empty():
		text += "\n\nGrid palette preview\n" + live_output
	if text != _output.text:
		_output.text = text

static func summary(report: Dictionary) -> String:
	if report.is_empty():
		return "There is no saved villa benchmark for this patch."
	if report.status != "complete":
		return report.error
	var result: Dictionary = report.after if report.after is Dictionary else report.before
	if result.mode == "embedded":
		return "The embedded villa run completed. Its timings are for comparison in the test host."
	var samples := PackedStringArray()
	var compared: bool = report.after is Dictionary
	for index in result.samples.size():
		var sample: Dictionary = result.samples[index]
		var line := "%s %.1f FPS / %.2f ms p95" % [str(sample.view).capitalize(), sample.fps, sample.p95_ms]
		if compared:
			line += " (%+.2f ms)" % (sample.p95_ms - report.before.samples[index].p95_ms)
		samples.append(line)
	var label := "Draft" if compared else "Baseline"
	return ("%s at %d×%d Balanced (base %s). %s. See F4 → Diagnostics." %
		[label, report.width, report.height, str(report.base).left(7), ", ".join(samples)])

static func _format_report(report: Dictionary) -> String:
	if report.status != "complete":
		return report.error + "\n\n" + report.log
	var base: Dictionary = report.before
	var compared: bool = report.after is Dictionary
	var result: Dictionary = report.after if compared else base
	var lines := PackedStringArray(["Git %s  ·  %s  ·  %s" % [str(report.base).left(7), result.device, result.renderer],
		report.completed_at])
	if compared:
		lines.insert(1, "Draft " + str(report.version).left(7))
	if result.mode == "embedded":
		lines.append("Embedded test host timings. Desktop performance budget unavailable.")
	elif result.samples.all(func(sample: Dictionary) -> bool: return sample.fps >= 60 and sample.p95_ms <= 16.67):
		lines.append("All views meet 60 FPS and 16.67 ms p95.")
	else:
		lines.append("At least one view misses 60 FPS or 16.67 ms p95.")
	lines.append("")
	if compared:
		lines.append("View        Baseline FPS / p95      Draft FPS / p95      Δ p95")
		for index in VIEWS.size():
			var before: Dictionary = base.samples[index]
			var after: Dictionary = result.samples[index]
			lines.append("%-9s %7.1f / %6.2f ms  %9.1f / %6.2f ms  %+7.2f ms" %
				[VIEWS[index], before.fps, before.p95_ms, after.fps, after.p95_ms, after.p95_ms - before.p95_ms])
		lines.append("")
	lines.append("View          FPS     p95 ms     p99 ms     GPU ms     Draws")
	for sample in result.samples:
		lines.append("%-9s %7.1f %10.2f %10.2f %10.2f %9.0f" %
			[str(sample.view).capitalize(), sample.fps, sample.p95_ms, sample.p99_ms, sample.gpu_ms, sample.draw_calls])
	return "\n".join(lines)
