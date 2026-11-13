extends AcceptDialog
## Shared Poly Haven search and import dialog.

const Look = preload("res://scripts/ui/terminal_theme.gd")
signal chosen(id: String, title: String)

var _search_catalog: Callable
var _import_asset: Callable
var _kind: String
var _catalog: String
var _query := LineEdit.new()
var _results := ItemList.new()
var _status := Label.new()
var _search: Button
var _busy := false

func setup(kind: String, catalog: String, search_catalog: Callable, import_asset: Callable) -> void:
	_kind = kind
	_catalog = catalog
	_search_catalog = search_catalog
	_import_asset = import_asset
	title = "Import " + kind
	exclusive = true
	var style := Look.frame_style()
	add_theme_stylebox_override("embedded_border", style)
	add_theme_stylebox_override("embedded_unfocused_border", style)
	add_theme_stylebox_override("panel", style)
	ok_button_text = "Import"
	dialog_hide_on_ok = false
	var content := VBoxContainer.new()
	add_child(content)
	var row := HBoxContainer.new()
	content.add_child(row)
	_query.placeholder_text = "Search Poly Haven"
	_query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_query.max_length = 120
	_query.text_submitted.connect(func(_text: String) -> void: _find())
	row.add_child(_query)
	_search = Button.new()
	_search.text = "Search"
	_search.pressed.connect(_find)
	row.add_child(_search)
	_results.custom_minimum_size.y = 135
	_results.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_results.item_selected.connect(func(_index: int) -> void: get_ok_button().disabled = _busy)
	_results.item_activated.connect(func(_index: int) -> void: _import())
	content.add_child(_results)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_status)
	_status.text = "Powered by Poly Haven"
	get_ok_button().disabled = true
	confirmed.connect(_import)
	canceled.connect(queue_free)
	close_requested.connect(queue_free)
	about_to_popup.connect(func() -> void: _query.grab_focus.call_deferred())

func _find() -> void:
	var query := _query.text.strip_edges()
	if _busy or query.is_empty():
		return
	_set_busy(true, "Searching…")
	_results.clear()
	var result: Dictionary = await _search_catalog.call(query)
	if not result.ok:
		_set_busy(false, result.message)
		return
	for item: Dictionary in result[_catalog]:
		var index := _results.add_item(item.name)
		_results.set_item_metadata(index, item.id)
		_results.set_item_tooltip(index, item.author)
	if _results.item_count > 0:
		_results.select(0)
	_set_busy(false, "Powered by Poly Haven" if _results.item_count > 0 else "No matching results.")

func _import() -> void:
	var selected := _results.get_selected_items()
	if _busy or selected.is_empty():
		return
	var id: String = _results.get_item_metadata(selected[0])
	_set_busy(true, "Downloading material…")
	var result: Dictionary = await _import_asset.call(id)
	if not result.ok:
		_set_busy(false, result.message)
		return
	var asset: Dictionary = result[_kind]
	chosen.emit(asset.get("key", asset.id), asset.name)
	hide()
	queue_free()

func _set_busy(busy: bool, message: String) -> void:
	_busy = busy
	_query.editable = not busy
	_search.disabled = busy
	get_ok_button().disabled = busy or _results.get_selected_items().is_empty()
	_status.text = message
