extends RefCounted
## The single lifecycle for live extensions. The Workbench and F2 hand every reviewed candidate here;
## the first registered kind that accepts it previews it. Register a catch-all kind last.
const LiveKind = preload("res://scripts/extensions/live_kind.gd")

var _kinds: Array[LiveKind] = []

func register(kind: LiveKind) -> void:
	_kinds.append(kind)

func kind_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for kind in _kinds:
		ids.append(kind.id())
	return ids

## Some kinds take a moment (a hot load may rebuild the environment), so callers await this.
func preview(candidate: Dictionary) -> Dictionary:
	for kind in _kinds:
		if kind.accepts(candidate):
			return await kind.preview(candidate)
	return {"ok": false, "message": "No live extension kind accepts this draft."}

func status(draft: String) -> String:
	for kind in _kinds:
		var current := kind.status(draft)
		if not current.is_empty():
			return current
	return ""

## Each kind is asked in order until one held the draft. The last answer carries any warning.
func finish(draft: String, keep: bool) -> Dictionary:
	var answer := {"live": false}
	for kind in _kinds:
		answer = kind.finish(draft, keep)
		if answer.get("live", false):
			return answer
	return answer

## After a revert every kind reloads. After a commit only the kinds that ask to.
func reload_committed(after_commit := false) -> void:
	for kind in _kinds:
		if not after_commit or kind.reloads_on_commit():
			kind.reload_committed()
