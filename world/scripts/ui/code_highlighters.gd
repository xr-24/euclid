extends RefCounted
## Syntax colors for the formats the Workbench can open, plus line colorers for diffs and logs.
## Every call returns a new highlighter because each one binds to a single TextEdit.
const Look = preload("res://scripts/ui/terminal_theme.gd")

const KEYWORD := Color("5fdcff")
const CONTROL := Color("8fb0ff")
const TYPE := Color("72f0d0")
const FUNCTION := Color("b9a7ff")
const MEMBER := Color("9dd3e8")
const STRING := Color("ffd27a")
const NUMBER := Color("ff9f80")
const COMMENT := Color("4a6a7e")
const ANNOTATION := Color("ff88c8")
const SYMBOL := Color("74a3ba")
const LITERAL := Color("ff9fd0")

const GD_KEYWORDS := ["extends", "class_name", "func", "var", "const", "signal", "enum", "class", "static",
	"await", "preload", "load", "self", "super", "as", "is", "in", "not", "and", "or", "assert", "breakpoint"]
const GD_CONTROL := ["if", "elif", "else", "for", "while", "match", "when", "break", "continue", "pass", "return"]
const GD_LITERALS := ["true", "false", "null", "PI", "TAU", "INF", "NAN"]
const GD_BUILTINS := ["print", "push_error", "push_warning", "str", "len", "range", "abs", "absf", "absi",
	"clamp", "clampf", "clampi", "lerp", "lerpf", "min", "max", "mini", "maxi", "minf", "maxf", "floor",
	"ceil", "round", "sqrt", "pow", "sin", "cos", "tan", "atan2", "deg_to_rad", "rad_to_deg", "randf",
	"randi", "randf_range", "randi_range", "is_instance_valid", "typeof", "smoothstep", "move_toward",
	"snapped", "wrapf", "wrapi", "posmod", "fposmod", "exp", "log", "sign", "ease", "inverse_lerp"]
const SHADER_KEYWORDS := ["shader_type", "render_mode", "uniform", "varying", "instance", "global", "const",
	"in", "out", "inout", "flat", "smooth", "lowp", "mediump", "highp", "struct", "group_uniforms"]
const SHADER_CONTROL := ["if", "else", "for", "while", "do", "break", "continue", "return", "discard",
	"switch", "case", "default"]
const SHADER_TYPES := ["void", "bool", "bvec2", "bvec3", "bvec4", "int", "ivec2", "ivec3", "ivec4", "uint",
	"uvec2", "uvec3", "uvec4", "float", "vec2", "vec3", "vec4", "mat2", "mat3", "mat4", "sampler2D",
	"isampler2D", "usampler2D", "sampler2DArray", "sampler3D", "samplerCube", "samplerCubeArray"]
const SHADER_FUNCTIONS := ["vertex", "fragment", "light", "start", "process", "sky", "fog"]

static var _engine_types := {}

static func language_for(path: String) -> String:
	match path.get_extension().to_lower():
		"gd":
			return "gdscript"
		"gdshader", "gdshaderinc":
			return "shader"
		"json":
			return "json"
		"tscn", "tres":
			return "scene"
	return "text"

static func comment_token(language: String) -> String:
	return {"gdscript": "#", "shader": "//", "scene": ";"}.get(language, "")

static func display_name(language: String) -> String:
	return {"gdscript": "GDScript", "shader": "Shader", "json": "JSON", "scene": "Scene", "text": "Text"}.get(language, "Text")

## Words that should appear in completion even before they occur in the file.
static func vocabulary(language: String) -> PackedStringArray:
	var words := PackedStringArray()
	match language:
		"gdscript":
			words.append_array(GD_KEYWORDS + GD_CONTROL + GD_LITERALS + GD_BUILTINS)
			words.append_array(PackedStringArray(_types().keys()))
		"shader":
			words.append_array(SHADER_KEYWORDS + SHADER_CONTROL + SHADER_TYPES)
		"json":
			words.append_array(["true", "false", "null"])
	return words

static func is_type(word: String) -> bool:
	return _types().has(word)

static func for_language(language: String) -> SyntaxHighlighter:
	match language:
		"gdscript":
			return _gdscript()
		"shader":
			return _shader()
		"json", "scene":
			return _data(language)
	return null

static func diff() -> SyntaxHighlighter:
	return DiffColors.new()

static func check_log() -> SyntaxHighlighter:
	return LogColors.new()

static func _types() -> Dictionary:
	if _engine_types.is_empty():
		for name in ClassDB.get_class_list():
			if not name.begins_with("_"):
				_engine_types[name] = true
		for name in ["bool", "int", "float", "void", "String", "StringName", "NodePath", "Vector2", "Vector2i",
				"Vector3", "Vector3i", "Vector4", "Vector4i", "Rect2", "Rect2i", "Transform2D", "Transform3D",
				"Basis", "Quaternion", "Plane", "AABB", "Projection", "Color", "RID", "Callable", "Signal",
				"Dictionary", "Array", "Variant", "PackedByteArray", "PackedInt32Array", "PackedInt64Array",
				"PackedFloat32Array", "PackedFloat64Array", "PackedStringArray", "PackedVector2Array",
				"PackedVector3Array", "PackedVector4Array", "PackedColorArray"]:
			_engine_types[name] = true
	return _engine_types

static func _base() -> CodeHighlighter:
	var colors := CodeHighlighter.new()
	colors.number_color = NUMBER
	colors.symbol_color = SYMBOL
	colors.function_color = FUNCTION
	colors.member_variable_color = MEMBER
	return colors

static func _gdscript() -> CodeHighlighter:
	var colors := _base()
	for word in _types():
		colors.add_keyword_color(word, TYPE)
	for word in GD_BUILTINS:
		colors.add_keyword_color(word, FUNCTION)
	for word in GD_KEYWORDS:
		colors.add_keyword_color(word, KEYWORD)
	for word in GD_CONTROL:
		colors.add_keyword_color(word, CONTROL)
	for word in GD_LITERALS:
		colors.add_keyword_color(word, LITERAL)
	colors.add_color_region("#", "", COMMENT, true)
	colors.add_color_region("\"\"\"", "\"\"\"", STRING)
	colors.add_color_region("\"", "\"", STRING)
	colors.add_color_region("'", "'", STRING)
	colors.add_color_region("&\"", "\"", STRING)
	colors.add_color_region("^\"", "\"", STRING)
	colors.add_color_region("@", " ", ANNOTATION, true)
	colors.add_color_region("$", " ", MEMBER, true)
	return colors

static func _shader() -> CodeHighlighter:
	var colors := _base()
	for word in SHADER_TYPES:
		colors.add_keyword_color(word, TYPE)
	for word in SHADER_KEYWORDS:
		colors.add_keyword_color(word, KEYWORD)
	for word in SHADER_CONTROL:
		colors.add_keyword_color(word, CONTROL)
	for word in SHADER_FUNCTIONS:
		colors.add_keyword_color(word, FUNCTION)
	for word in ["true", "false"]:
		colors.add_keyword_color(word, LITERAL)
	# Upper-case built-ins (TIME, UV, ALBEDO, ...) read as members of the render pipeline.
	for word in ["TIME", "PI", "TAU", "E", "UV", "UV2", "COLOR", "ALBEDO", "ALPHA", "EMISSION", "NORMAL",
			"NORMAL_MAP", "ROUGHNESS", "METALLIC", "SPECULAR", "VERTEX", "FRAGCOORD", "SCREEN_UV", "TEXTURE",
			"TEXTURE_PIXEL_SIZE", "SCREEN_PIXEL_SIZE", "MODEL_MATRIX", "VIEW_MATRIX", "INV_VIEW_MATRIX",
			"PROJECTION_MATRIX", "CAMERA_POSITION_WORLD", "NODE_POSITION_WORLD", "INSTANCE_ID", "POINT_COORD",
			"LIGHT", "LIGHT_COLOR", "ATTENUATION", "DIFFUSE_LIGHT", "SPECULAR_LIGHT", "AO", "RIM", "DEPTH"]:
		colors.add_keyword_color(word, MEMBER)
	colors.add_color_region("//", "", COMMENT, true)
	colors.add_color_region("/*", "*/", COMMENT)
	colors.add_color_region("#", "", ANNOTATION, true)
	colors.add_color_region("\"", "\"", STRING)
	return colors

static func _data(language: String) -> CodeHighlighter:
	var colors := _base()
	colors.function_color = Look.INK
	colors.member_variable_color = Look.INK
	for word in ["true", "false", "null"]:
		colors.add_keyword_color(word, LITERAL)
	colors.add_color_region("\"", "\"", STRING)
	if language == "scene":
		colors.add_color_region("[", "]", KEYWORD)
		colors.add_color_region(";", "", COMMENT, true)
	return colors

## Unified diffs: added and removed lines, hunk headers and file headers.
class DiffColors extends SyntaxHighlighter:
	func _get_line_syntax_highlighting(line: int) -> Dictionary:
		var text := get_text_edit().get_line(line)
		var color := Look.INK
		if text.begins_with("+++") or text.begins_with("---") or text.begins_with("diff ") or text.begins_with("index "):
			color = Look.MUTED
		elif text.begins_with("@@"):
			color = Look.ACCENT
		elif text.begins_with("+"):
			color = Look.GOOD
		elif text.begins_with("-"):
			color = Look.ERROR
		else:
			color = Color(Look.INK, 0.72)
		return {0: {"color": color}}

## Check logs: failures, warnings and successes, with res:// locations picked out so they read as links.
class LogColors extends SyntaxHighlighter:
	var _location := RegEx.create_from_string("res://[\\w./-]+:\\d+")

	func _get_line_syntax_highlighting(line: int) -> Dictionary:
		var text := get_text_edit().get_line(line)
		var upper := text.to_upper()
		var color := Color(Look.INK, 0.8)
		if upper.contains("ERROR") or upper.contains("FAILED") or upper.contains("FAIL:"):
			color = Look.ERROR
		elif upper.contains("WARNING"):
			color = Look.WARN
		elif upper.contains(" OK") or upper.ends_with("_OK") or upper.contains("PASSED") or upper.contains("PASS "):
			color = Look.GOOD
		var spans := {0: {"color": color}}
		var found := _location.search(text)
		if found:
			spans[found.get_start()] = {"color": Look.ACCENT}
			if found.get_end() < text.length():
				spans[found.get_end()] = {"color": color}
		return spans
