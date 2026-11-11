extends RefCounted
## One kind of live extension. A reviewed Workbench draft of this kind can run in the world before it
## is committed, then be kept or dropped. Every kind follows the same lifecycle:
##   accepts -> preview -> status ... -> finish(keep), and reload_committed after a commit or revert.
## Subclasses override what they support. The defaults describe a kind that holds nothing live.

## A stable name for logs and tests.
func id() -> String:
	return ""

## Whether this kind owns the candidate the gateway served for a draft.
func accepts(_candidate: Dictionary) -> bool:
	return false

## Activate the reviewed candidate in the running world. Returns {"ok": bool, "message": String}.
func preview(_candidate: Dictionary) -> Dictionary:
	return {"ok": false, "message": "This extension kind cannot preview a draft."}

## "active" or "failed" while this kind holds the draft, otherwise empty.
func status(_draft: String) -> String:
	return ""

## Keep (after a commit) or drop (after a discard) the draft. "live" is true when this kind held it.
func finish(_draft: String, _keep: bool) -> Dictionary:
	return {"live": false}

## Load the committed definitions again, after a revert or, when reloads_on_commit, a commit.
func reload_committed() -> void:
	pass

func reloads_on_commit() -> bool:
	return false
