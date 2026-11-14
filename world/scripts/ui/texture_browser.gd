extends AcceptDialog
## Shared sky and surface texture browser.

const Look = preload("res://scripts/ui/terminal_theme.gd")
const SAMPLES := "res://data/texture_samples.json"
signal chosen(id: String, title: String)

var _search_catalog: Callable
var _import_asset: Callable
var _kind: String
var _catalog: String
var _provider := OptionButton.new()
var _query := LineEdit.new()
var _results := ItemList.new()
var _status := Label.new()
var _search: Button
var _source: LinkButton
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
	for provider in [["Poly Haven", "polyhaven"], ["Sketchfab", "sketchfab"]]:
		_provider.add_item(provider[0])
		_provider.set_item_metadata(_provider.item_count - 1, provider[1])
	_provider.item_selected.connect(_change_provider)
	_provider.select(0)
	row.add_child(_provider)
	_query.placeholder_text = "Search Poly Haven"
	_query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_query.max_length = 120
	_query.text_submitted.connect(func(_text: String) -> void: _find())
	row.add_child(_query)
	_search = Button.new()
	_search.text = "Search"
	_search.pressed.connect(_find)
	_query.text_changed.connect(func(text: String) -> void:
		if not _busy and text.strip_edges().is_empty():
			_show_samples())
	row.add_child(_search)
	_results.custom_minimum_size.y = 135
	_results.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_results.item_selected.connect(func(_index: int) -> void: _show_source())
	_results.item_activated.connect(func(_index: int) -> void: _import())
	content.add_child(_results)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_status)
	_source = LinkButton.new()
	_source.hide()
	content.add_child(_source)
	_show_samples()
	confirmed.connect(_import)
	canceled.connect(queue_free)
	close_requested.connect(queue_free)
	about_to_popup.connect(func() -> void: _query.grab_focus.call_deferred())

func _change_provider(index: int) -> void:
	var sketchfab: bool = _provider.get_item_metadata(index) == "sketchfab"
	_query.max_length = 240 if sketchfab else 120
	_query.placeholder_text = "Search or paste a Sketchfab link" if sketchfab else "Search Poly Haven"
	_query.clear()
	_show_samples()

func _show_samples() -> void:
	_results.clear()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAMPLES))
	var provider: String = _provider.get_selected_metadata()
	if data is Dictionary:
		for entry: Dictionary in data.get(_kind, {}).get(provider, []):
			var item := entry.duplicate()
			item["license"] = "CC BY" if provider == "sketchfab" else "CC0"
			item["page"] = item.get("page", "https://polyhaven.com/a/" + item.id)
			_add_result(item)
	_set_busy(false, _provider_note())

func _provider_note() -> String:
	if _provider.get_selected_metadata() == "polyhaven":
		return "Powered by Poly Haven"
	return "Sketchfab skyboxes use a 2:1 panorama." if _kind == "sky" else "Sketchfab materials use textures from a downloadable model."

func _find() -> void:
	var query := _query.text.strip_edges()
	if _busy or query.is_empty():
		return
	_set_busy(true, "Searching…")
	_results.clear()
	var result: Dictionary = await _search_catalog.call(query, _provider.get_selected_metadata())
	if not result.ok:
		_set_busy(false, result.message)
		return
	for item: Dictionary in result[_catalog]:
		_add_result(item)
	if _results.item_count > 0:
		_results.select(0)
	_set_busy(false, _provider_note() if _results.item_count > 0 else "No matching results.")

func _add_result(item: Dictionary) -> void:
	var index := _results.add_item(item.name)
	_results.set_item_metadata(index, item)
	_results.set_item_tooltip(index, "%s · %s\n%s" % [item.author, item.license, item.page])

func _import() -> void:
	var selected := _results.get_selected_items()
	if _busy or selected.is_empty():
		return
	var item: Dictionary = _results.get_item_metadata(selected[0])
	_set_busy(true, "Importing %s…" % _kind)
	var result: Dictionary = await _import_asset.call(item.id)
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
	_provider.disabled = busy
	_search.disabled = busy
	_status.text = message
	_show_source()

func _show_source() -> void:
	var selected := _results.get_selected_items()
	get_ok_button().disabled = _busy or selected.is_empty()
	_source.hide()
	if selected.is_empty():
		return
	var item: Dictionary = _results.get_item_metadata(selected[0])
	var page: String = item.page
	if page.begins_with("https://polyhaven.com/a/") or page.begins_with("https://sketchfab.com/3d-models/"):
		_source.text = "%s · %s" % [item.author, item.license]
		_source.uri = page
		_source.show()
