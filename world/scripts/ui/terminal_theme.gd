extends RefCounted
## Shared Grid-cyan look for Euclid's text tools: palette, monospace font and control styles.
## The Codex console, Workbench and their editors read colors from here so a palette change
## stays in one place.

const BACKGROUND := Color("03070c")
const SURFACE := Color("07101a")
const RAISED := Color("0c1925")
const LINE := Color("12303f")
const BORDER := Color("1d5a75")
const INK := Color("b8ecff")
const BRIGHT := Color("eafcff")
const MUTED := Color("6994aa")
const DIM := Color("33536a")
const ACCENT := Color("4fdcff")
const GOOD := Color("6effc8")
const WARN := Color("ffc46b")
const ERROR := Color("ff6b8a")
const ADDED_BG := Color("0a3330")
const REMOVED_BG := Color("361224")
const ERROR_BG := Color("45142a")
const FONT_SIZE := 16

static var _font: Font

## A system monospace font. Subpixel positioning stays off so every glyph sits on a whole-pixel
## grid; the text-effects layer relies on that to place characters by column.
static func mono_font() -> Font:
	if _font == null:
		var font := SystemFont.new()
		font.font_names = PackedStringArray(["JetBrains Mono", "Cascadia Mono", "Cascadia Code", "Consolas",
			"DejaVu Sans Mono", "Liberation Mono", "monospace"])
		font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		font.hinting = TextServer.HINTING_LIGHT
		font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		_font = font
	return _font

static func frame_style() -> StyleBoxFlat:
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(BACKGROUND, 0.97)
	frame.border_color = BORDER
	frame.set_border_width_all(1)
	frame.set_corner_radius_all(6)
	# A faint cyan halo, as if the panel were lit from its own text.
	frame.shadow_color = Color(0.12, 0.62, 0.86, 0.16)
	frame.shadow_size = 22
	return frame

static func box(fill: Color, edge: Color, width := 1, radius := 4, margin_x := 8.0, margin_y := 4.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = margin_x
	style.content_margin_right = margin_x
	style.content_margin_top = margin_y
	style.content_margin_bottom = margin_y
	return style

static func make_theme(size := FONT_SIZE) -> Theme:
	var theme := Theme.new()
	theme.default_font = mono_font()
	theme.default_font_size = size
	var pressed := box(Color("0d2635"), ACCENT)
	for type in ["Button", "OptionButton", "MenuButton"]:
		theme.set_stylebox("normal", type, box(SURFACE, LINE))
		theme.set_stylebox("hover", type, box(RAISED, BORDER))
		theme.set_stylebox("pressed", type, pressed)
		theme.set_stylebox("hover_pressed", type, pressed)
		theme.set_stylebox("disabled", type, box(Color(SURFACE, 0.5), Color(LINE, 0.5)))
		theme.set_stylebox("focus", type, box(Color.TRANSPARENT, Color(ACCENT, 0.7)))
		theme.set_color("font_color", type, INK)
		theme.set_color("font_hover_color", type, BRIGHT)
		theme.set_color("font_focus_color", type, BRIGHT)
		theme.set_color("font_pressed_color", type, ACCENT)
		theme.set_color("font_hover_pressed_color", type, ACCENT)
		theme.set_color("font_disabled_color", type, DIM)
	theme.set_stylebox("normal", "LineEdit", box(BACKGROUND, LINE, 1, 3, 10, 5))
	theme.set_stylebox("focus", "LineEdit", box(Color.TRANSPARENT, Color(ACCENT, 0.8), 1, 3, 10, 5))
	theme.set_stylebox("read_only", "LineEdit", box(BACKGROUND, Color(LINE, 0.5), 1, 3, 10, 5))
	theme.set_color("font_color", "LineEdit", INK)
	theme.set_color("font_placeholder_color", "LineEdit", DIM)
	theme.set_color("font_uneditable_color", "LineEdit", MUTED)
	theme.set_color("caret_color", "LineEdit", ACCENT)
	theme.set_color("selection_color", "LineEdit", Color(ACCENT, 0.26))
	theme.set_color("font_selected_color", "LineEdit", BRIGHT)
	for type in ["TextEdit", "CodeEdit"]:
		var field := box(BACKGROUND, Color.TRANSPARENT, 0, 0, 10, 6)
		theme.set_stylebox("normal", type, field)
		theme.set_stylebox("focus", type, box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 10, 6))
		theme.set_stylebox("read_only", type, field)
		theme.set_color("background_color", type, BACKGROUND)
		theme.set_color("font_color", type, INK)
		theme.set_color("font_readonly_color", type, INK)
		theme.set_color("font_placeholder_color", type, DIM)
		theme.set_color("font_selected_color", type, Color(0, 0, 0, 0))
		theme.set_color("selection_color", type, Color(ACCENT, 0.2))
		theme.set_color("current_line_color", type, Color(ACCENT, 0.055))
		theme.set_color("word_highlighted_color", type, Color(ACCENT, 0.12))
		theme.set_color("search_result_color", type, Color(WARN, 0.2))
		theme.set_color("search_result_border_color", type, Color(WARN, 0.55))
		theme.set_color("caret_color", type, ACCENT)
		theme.set_constant("line_spacing", type, 6)
	theme.set_color("line_number_color", "CodeEdit", DIM)
	theme.set_color("code_folding_color", "CodeEdit", MUTED)
	theme.set_color("brace_mismatch_color", "CodeEdit", ERROR)
	theme.set_color("line_length_guideline_color", "CodeEdit", Color(LINE, 0.6))
	theme.set_color("completion_background_color", "CodeEdit", RAISED)
	theme.set_color("completion_selected_color", "CodeEdit", Color(ACCENT, 0.22))
	theme.set_color("completion_existing_color", "CodeEdit", Color(ACCENT, 0.14))
	theme.set_color("completion_scroll_color", "CodeEdit", BORDER)
	theme.set_color("completion_scroll_hovered_color", "CodeEdit", ACCENT)
	theme.set_stylebox("completion", "CodeEdit", box(RAISED, BORDER, 1, 4, 6, 4))
	theme.set_color("font_color", "Label", INK)
	var tab_selected := box(SURFACE, Color.TRANSPARENT, 0, 3, 14, 6)
	tab_selected.border_color = ACCENT
	tab_selected.border_width_bottom = 2
	var tab_idle := box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 3, 14, 6)
	for type in ["TabBar", "TabContainer"]:
		theme.set_stylebox("tab_selected", type, tab_selected)
		theme.set_stylebox("tab_unselected", type, tab_idle)
		theme.set_stylebox("tab_hovered", type, box(RAISED, Color.TRANSPARENT, 0, 3, 14, 6))
		theme.set_stylebox("tab_disabled", type, tab_idle)
		theme.set_stylebox("tab_focus", type, box(Color.TRANSPARENT, Color(ACCENT, 0.5), 1, 3))
		theme.set_color("font_selected_color", type, BRIGHT)
		theme.set_color("font_unselected_color", type, MUTED)
		theme.set_color("font_hovered_color", type, INK)
		theme.set_color("font_disabled_color", type, DIM)
	theme.set_stylebox("panel", "TabContainer", box(BACKGROUND, LINE, 1, 0, 0, 0))
	theme.set_stylebox("tabbar_background", "TabContainer", StyleBoxEmpty.new())
	theme.set_stylebox("panel", "Tree", box(BACKGROUND, LINE, 1, 0, 4, 4))
	theme.set_stylebox("focus", "Tree", StyleBoxEmpty.new())
	theme.set_stylebox("selected", "Tree", box(Color(ACCENT, 0.14), Color.TRANSPARENT, 0, 2))
	theme.set_stylebox("selected_focus", "Tree", box(Color(ACCENT, 0.2), Color.TRANSPARENT, 0, 2))
	theme.set_stylebox("hovered", "Tree", box(Color(ACCENT, 0.07), Color.TRANSPARENT, 0, 2))
	theme.set_stylebox("cursor", "Tree", StyleBoxEmpty.new())
	theme.set_stylebox("cursor_unfocused", "Tree", StyleBoxEmpty.new())
	theme.set_color("font_color", "Tree", MUTED)
	theme.set_color("font_selected_color", "Tree", BRIGHT)
	theme.set_color("font_hovered_color", "Tree", INK)
	theme.set_color("guide_color", "Tree", Color(LINE, 0.6))
	theme.set_color("relationship_line_color", "Tree", Color(LINE, 0.8))
	theme.set_constant("v_separation", "Tree", 3)
	theme.set_stylebox("panel", "ItemList", box(BACKGROUND, LINE, 1, 3, 4, 4))
	theme.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	theme.set_stylebox("selected", "ItemList", box(Color(ACCENT, 0.16), Color.TRANSPARENT, 0, 2))
	theme.set_stylebox("selected_focus", "ItemList", box(Color(ACCENT, 0.22), Color.TRANSPARENT, 0, 2))
	theme.set_stylebox("hovered", "ItemList", box(Color(ACCENT, 0.07), Color.TRANSPARENT, 0, 2))
	theme.set_stylebox("cursor", "ItemList", StyleBoxEmpty.new())
	theme.set_stylebox("cursor_unfocused", "ItemList", StyleBoxEmpty.new())
	theme.set_color("font_color", "ItemList", MUTED)
	theme.set_color("font_selected_color", "ItemList", BRIGHT)
	theme.set_color("font_hovered_color", "ItemList", INK)
	for type in ["PopupPanel", "PopupMenu"]:
		theme.set_stylebox("panel", type, box(SURFACE, BORDER, 1, 6, 8, 8))
	theme.set_stylebox("hover", "PopupMenu", box(Color(ACCENT, 0.16), Color.TRANSPARENT, 0, 2))
	theme.set_color("font_color", "PopupMenu", INK)
	theme.set_color("font_hover_color", "PopupMenu", BRIGHT)
	theme.set_color("font_disabled_color", "PopupMenu", DIM)
	theme.set_stylebox("panel", "TooltipPanel", box(RAISED, BORDER, 1, 3, 8, 5))
	theme.set_color("font_color", "TooltipLabel", INK)
	for type in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", type, box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 3, 3))
		theme.set_stylebox("grabber", type, box(Color(BORDER, 0.55), Color.TRANSPARENT, 0, 3, 3, 3))
		theme.set_stylebox("grabber_highlight", type, box(BORDER, Color.TRANSPARENT, 0, 3, 3, 3))
		theme.set_stylebox("grabber_pressed", type, box(ACCENT, Color.TRANSPARENT, 0, 3, 3, 3))
	theme.set_constant("separation", "HSplitContainer", 8)
	return theme
