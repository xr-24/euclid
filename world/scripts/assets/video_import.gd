extends Node
## Owns the conversion independently of the piece editor that initiated it.

signal finished(result: Dictionary)
const Videos = preload("res://scripts/assets/video_library.gd")

var _job := {}
var _copy: Thread
var _pid := -1
var _poll := 0.0
const GROUP := "local_video_import"

func start(source: String) -> void:
	if get_tree().get_nodes_in_group(GROUP).any(func(job: Node) -> bool: return job != self):
		_complete({"ok": false, "message": "Another local video is importing."})
		return
	add_to_group(GROUP)
	_job = Videos.prepare(source)
	if not _job.ok:
		_complete(_job)
		return
	if _job.extension == "ogv":
		_copy = Thread.new()
		if _copy.start(DirAccess.copy_absolute.bind(_job.source, _job.stage), Thread.PRIORITY_LOW) != OK:
			_copy = null
			_complete(Videos.finish(_job, false))
	else:
		_pid = Videos.convert(_job)
		if _pid <= 0:
			_complete(Videos.finish(_job, false))

func _process(delta: float) -> void:
	_poll += delta
	if _poll < 0.1:
		return
	_poll = 0.0
	if _copy and not _copy.is_alive():
		var copied: bool = _copy.wait_to_finish() == OK
		_copy = null
		_complete(Videos.finish(_job, copied))
	elif _pid > 0 and not OS.is_process_running(_pid):
		var converted := OS.get_process_exit_code(_pid) == 0
		_pid = -1
		_complete(Videos.finish(_job, converted))

func _complete(result: Dictionary) -> void:
	if is_in_group(GROUP):
		remove_from_group(GROUP)
	finished.emit(result)
	queue_free()

func _exit_tree() -> void:
	if _pid > 0:
		OS.kill(_pid)
	if _copy and _copy.is_started():
		_copy.wait_to_finish()
	if _job.has("stage") and FileAccess.file_exists(_job.stage):
		DirAccess.remove_absolute(_job.stage)
