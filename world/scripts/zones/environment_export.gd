extends RefCounted
## Turn an environment's in-world edits (its pieces and its atmosphere) into its package file, so a
## commit makes them part of the project. Lines of pieces that did not change are kept exactly as
## they were, so the draft's diff shows only what changed.

const PieceTypes = preload("res://scripts/pieces/piece_types.gd")
## Atmosphere field names that differ in the package's environment block.
const PACKAGE_KEYS := {"sky": "hdri", "fog_color": "fog_albedo", "fog_direction": "fog_anisotropy"}

## The package text with these pieces and atmosphere edits, and what changed:
## {"text", "pieces": changed piece count, "atmosphere": changed setting count} or {"error"}.
static func package_text(original: String, pieces: Array, atmosphere: Dictionary) -> Dictionary:
	var parsed: Variant = _parse(original)
	if not parsed is Dictionary or not parsed.get("pieces") is Array or not PieceTypes.valid_tree(pieces):
		return {"error": "The environment package could not be read."}
	var opening := original.find('"pieces": [')
	var spans := _objects(original, original.find("[", opening)) if opening >= 0 else {}
	if spans.is_empty() or spans.objects.size() != parsed.pieces.size():
		return {"error": "The environment package's pieces could not be found."}
	var known := {}
	for span: Array in spans.objects:
		var piece: Variant = _parse(original.substr(span[0], span[1] - span[0]))
		if piece is Dictionary and piece.has("id"):
			known[str(piece.id)] = [original.substr(span[0], span[1] - span[0]), piece]
	var separator := ",\n    "
	if spans.objects.size() > 1:
		separator = original.substr(spans.objects[0][1], spans.objects[1][0] - spans.objects[0][1])
	# New and changed pieces follow the package's own style: one per line, or spread over lines.
	var spread: bool = known.values().any(func(entry: Array) -> bool: return str(entry[0]).contains("\n"))
	var rows: Array[String] = []
	var changed := 0
	var kept := {}
	for piece: Dictionary in pieces:
		var id := str(piece.get("id", ""))
		kept[id] = true
		if known.has(id) and known[id][1] == piece:
			rows.append(known[id][0])
		else:
			rows.append(pretty(piece, "    ") if spread else compact(piece))
			changed += 1
	for id in known:
		if not kept.has(id):
			changed += 1
	var text := original
	if not spans.objects.is_empty():
		text = original.substr(0, spans.objects[0][0]) + separator.join(rows) + original.substr(spans.objects[-1][1])
	if changed > 0:
		var revision := int(parsed.get("piece_revision", 0))
		text = text.replace('"piece_revision": %d' % revision, '"piece_revision": %d' % (revision + 1))
	var settings := _environment(parsed.get("environment", {}), atmosphere)
	if settings.changed > 0:
		text = _replace_block(text, "environment", settings.values)
	var check: Variant = _parse(text)
	if not check is Dictionary or not PieceTypes.valid_tree(check.get("pieces")):
		return {"error": "The saved environment would not be a valid package."}
	return {"text": text, "pieces": changed, "atmosphere": settings.changed}

## The text spans of the objects directly inside the array that opens at index.
static func _objects(text: String, index: int) -> Dictionary:
	if index < 0 or index >= text.length() or text[index] != "[":
		return {}
	var objects := []
	var depth := 0
	var start := -1
	var quoted := false
	var escaped := false
	for at in range(index + 1, text.length()):
		var c := text[at]
		if quoted:
			if escaped:
				escaped = false
			elif c == "\\":
				escaped = true
			elif c == '"':
				quoted = false
		elif c == '"':
			quoted = true
		elif c == "{" or c == "[":
			if depth == 0 and c == "{":
				start = at
			depth += 1
		elif c == "}" or c == "]":
			if depth == 0:
				return {"objects": objects, "end": at}
			depth -= 1
			if depth == 0 and c == "}":
				objects.append([start, at + 1])
	return {}

static func _parse(text: String) -> Variant:
	var json := JSON.new()
	return json.data if not text.strip_edges().is_empty() and json.parse(text) == OK else null

## JSON on one line with spaces after separators, keys in their order: how packages list pieces.
static func compact(value: Variant) -> String:
	if value is Dictionary:
		var parts: Array[String] = []
		for key in value:
			parts.append("%s: %s" % [JSON.stringify(str(key)), compact(value[key])])
		return "{" + ", ".join(parts) + "}"
	if value is Array:
		return "[" + ", ".join(value.map(compact)) + "]"
	# Parsed JSON numbers are floats; whole ones are written as integers, like the package does.
	if value is float and value == floorf(value) and absf(value) < 1e15:
		return str(int(value))
	return JSON.stringify(value)

## JSON spread over lines with two-space steps, continuing from indent: how packages print blocks.
static func pretty(value: Variant, indent: String) -> String:
	var inner := indent + "  "
	if value is Dictionary and not value.is_empty():
		var parts: Array[String] = []
		for key in value:
			parts.append(inner + "%s: %s" % [JSON.stringify(str(key)), pretty(value[key], inner)])
		return "{\n" + ",\n".join(parts) + "\n" + indent + "}"
	if value is Array and not value.is_empty():
		return "[\n" + ",\n".join(value.map(func(item: Variant) -> String: return inner + pretty(item, inner))) + "\n" + indent + "]"
	return compact(value)

static func _environment(base: Dictionary, edits: Dictionary) -> Dictionary:
	var values := base.duplicate()
	var changed := 0
	for field in edits:
		var key: String = PACKAGE_KEYS.get(field, field)
		var value: Variant = edits[field]
		if field == "sky" and value == "gradient":
			if values.has("hdri"):
				values.erase("hdri")
				changed += 1
			continue
		if values.get(key) != value:
			values[key] = value
			changed += 1
	return {"values": values, "changed": changed}

## Rewrite one top-level block, keeping two-space indentation.
static func _replace_block(text: String, key: String, values: Dictionary) -> String:
	var lines := text.split("\n")
	var start := lines.find('  "%s": {' % key)
	if start < 0:
		return text
	var finish := -1
	for index in range(start + 1, lines.size()):
		if lines[index] == "  }" or lines[index] == "  },":
			finish = index
			break
	if finish < 0:
		return text
	var rows: Array[String] = []
	for field in values:
		rows.append("    %s: %s" % [JSON.stringify(str(field)), compact(values[field])])
	var out: Array[String] = []
	out.append_array(Array(lines.slice(0, start + 1)))
	out.append(",\n".join(rows))
	out.append_array(Array(lines.slice(finish)))
	return "\n".join(out)
