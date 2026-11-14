extends RefCounted
## Local presentation state. Git draft versions and check results live in the gateway.

const Store = preload("res://scripts/persistence/world_state_store.gd")
const TABS := ["Source", "Diff", "Checks", "Revision", "Diagnostics"]
const MAX_LINES := 300
const MAX_PROMPTS := 100
const MAX_LINE_LENGTH := 2048
const MAX_PROMPT_LENGTH := 4096
const MAX_BYTES := 4 * 1024 * 1024

var lines := PackedStringArray()
var prompts := PackedStringArray()
var file := ""
var tab := ""
var chat_tabs: Array[String] = []
var chat_peer := ""
var voice_id := ""
## Whether voice was on when Euclid last closed.
var voice_enabled := false
var legacy_chat_tabs: Array[String] = []
var legacy_chat_peer := ""
var _path: String

func _init(path: String) -> void:
	_path = path
	var stream := FileAccess.open(path, FileAccess.READ)
	if stream == null or stream.get_length() > MAX_BYTES:
		return
	var state: Variant = JSON.parse_string(stream.get_as_text())
	if not state is Dictionary:
		return
	var version: Variant = state.get("schema_version")
	if version != 1 and version != 2:
		return
	lines = _strings(state.get("lines"), MAX_LINES, MAX_LINE_LENGTH)
	prompts = _strings(state.get("prompts"), MAX_PROMPTS, MAX_PROMPT_LENGTH)
	if version == 2:
		if state.get("voice_id") is String and RegEx.create_from_string("^[a-zA-Z0-9_-]{1,80}$").search(state.voice_id):
			voice_id = state.voice_id
		voice_enabled = state.get("voice_enabled") == true
		chat_tabs = _peers(state.get("chat_tabs"))
		if state.get("chat_peer") in chat_tabs:
			chat_peer = state.chat_peer
	legacy_chat_tabs = _peers(state.get("chat_tabs" if version == 1 else "legacy_chat_tabs"))
	var legacy_selected: Variant = state.get("chat_peer" if version == 1 else "legacy_chat_peer")
	if legacy_selected in legacy_chat_tabs:
		legacy_chat_peer = legacy_selected
	var view: Variant = state.get("view")
	if view is Dictionary:
		if view.get("file") is String:
			file = view.file.left(256)
		if view.get("tab") in TABS:
			tab = view.tab

func save_console(entries: PackedStringArray, submitted: PackedStringArray) -> void:
	lines = _strings(Array(entries), MAX_LINES, MAX_LINE_LENGTH)
	prompts = _strings(Array(submitted), MAX_PROMPTS, MAX_PROMPT_LENGTH)
	_save()

func save_view(selected_file: String, selected_tab: String) -> void:
	if selected_file == file and selected_tab == tab:
		return
	file = selected_file
	tab = selected_tab
	_save()

func save_chat_tabs(tabs: Array[String], selected: String, migrated := false) -> void:
	if not migrated and tabs == chat_tabs and selected == chat_peer:
		return
	chat_tabs = tabs.duplicate()
	chat_peer = selected
	if migrated:
		legacy_chat_tabs.clear()
		legacy_chat_peer = ""
	_save()

func save_voice_enabled(on: bool) -> void:
	if on != voice_enabled:
		voice_enabled = on
		_save()

func save_voice(id: String) -> void:
	if id != voice_id:
		voice_id = id
		_save()

func _save() -> void:
	Store.write_json(_path, {"schema_version": 2, "lines": Array(lines), "prompts": Array(prompts),
		"view": {"file": file, "tab": tab}, "chat_tabs": chat_tabs, "chat_peer": chat_peer,
		"legacy_chat_tabs": legacy_chat_tabs, "legacy_chat_peer": legacy_chat_peer, "voice_id": voice_id,
		"voice_enabled": voice_enabled})

static func _peers(values: Variant) -> Array[String]:
	var peers: Array[String] = []
	if values is Array:
		var valid := RegEx.create_from_string("^[a-z0-9_-]{1,32}$")
		for peer in values.slice(0, 100):
			if peer is String and valid.search(peer) and peer not in peers:
				peers.append(peer)
	return peers

static func _strings(values: Variant, count: int, length: int) -> PackedStringArray:
	var result := PackedStringArray()
	if values is Array:
		for index in range(maxi(0, values.size() - count), values.size()):
			if values[index] is String:
				result.append(values[index].left(length))
	return result
