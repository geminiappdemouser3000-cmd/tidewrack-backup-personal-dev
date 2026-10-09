extends Control
class_name JournalReader
## JournalReader — the in-game journal screen. Built entirely in code.
##
## Lists every entry the `Journal` autoload holds, in discovery order, and
## shows the selected one beside the list. Open it by adding an instance on
## top of the current screen:
##
##     overlay.add_child(JournalReader.new())
##
## It closes itself (Back button or ui_cancel) and hands focus back to whatever
## had it before.
##
## Entry text lives in res://data/dialogue/journal.json, in the same node
## format the dialogue graphs use, keyed by entry id:
##
##     "entry_logbook": { "speaker": "Title shown in the list",
##                        "text": "Body text. BBCode works.",
##                        "next": null }
##
## A `next` chain is followed and joined into one scrolling entry, so a long
## log can be split across nodes. An id with no node still lists (under a
## title made from its id) and says its text is missing.
##
## Controls: the list has focus first. Up/down picks an entry, ui_accept or
## right moves into the text, where up/down scrolls. ui_cancel steps back
## from the text to the list, and from the list closes the reader.

const CONTENT_PATH := "res://data/dialogue/journal.json"

## Scroll speed for the entry text, in pixels per second with the stick fully
## pushed (it scales with how far the stick is pushed). Kept slow on purpose:
## playtesters overshot dense text on gamepad.
const SCROLL_SPEED := 240.0

const LIST_WIDTH := 300.0
const FADE_HEIGHT := 48.0

## Edith had been gone eleven days when the game opens. Once the game counts
## days, set the story flag below to the number of days played and the day
## line follows it. Until then it reads eleven. The same line is shown in the
## journal header and on the pause menu (scripts/game.gd), both through
## days_text().
const DAYS_GONE_AT_START := 11
const DAYS_ELAPSED_FLAG := "days_elapsed"

const COLOR_PANEL := Color("#16232c")
const COLOR_ACCENT := Color("#ffd466")
const COLOR_DIM := Color(1, 1, 1, 0.5)

const HINT_LIST := "Up / Down: choose      Enter: read      Esc: close"
const HINT_TEXT := "Up / Down: scroll      Esc: back to the list"

## Where the player was last time the reader was open: which entry, and how
## far down each entry they had scrolled. Kept for the session, and forgotten
## on New Game or when a save is loaded.
static var _last_id: String = ""
static var _scroll_by_id: Dictionary = {}
static var _memory_wired: bool = false

var _ids: Array[String] = []
var _content: Dictionary = {}
var _selected: int = -1
var _scroll_pos: float = 0.0
var _pending_restore_id: String = ""
var _previous_focus: Control = null

var _entry_buttons: Array[Button] = []
var _entry_title: Label
var _text_scroll: ScrollContainer
var _body: RichTextLabel
var _fade_top: TextureRect
var _fade_bottom: TextureRect
var _hint: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	focus_mode = Control.FOCUS_ALL
	_wire_memory()

	_previous_focus = get_viewport().gui_get_focus_owner()
	_ids = Journal.entries()
	_content = _load_content()
	_build_ui()

	if _ids.is_empty():
		grab_focus()
		return
	var start := _ids.find(_last_id)
	if start == -1:
		start = _ids.size() - 1  # first visit: open on the newest entry
	_entry_buttons[start].grab_focus()


func _exit_tree() -> void:
	_remember_scroll()


# --- Remembering the player's place ---------------------------------------

static func _wire_memory() -> void:
	if _memory_wired:
		return
	_memory_wired = true
	Journal.entries_reset.connect(_forget_place)


static func _forget_place() -> void:
	_last_id = ""
	_scroll_by_id.clear()


func _remember_scroll() -> void:
	if _selected < 0 or _text_scroll == null:
		return
	var id := _ids[_selected]
	if id == _pending_restore_id:
		return  # the saved position has not been applied yet; keep it
	_scroll_by_id[id] = _text_scroll.scroll_vertical


func _restore_scroll(id: String) -> void:
	var target := int(_scroll_by_id.get(id, 0))
	if target <= 0:
		return
	# The text needs a couple of frames to lay out before it can scroll.
	_pending_restore_id = id
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree() or _pending_restore_id != id:
		return
	_pending_restore_id = ""
	_text_scroll.scroll_vertical = target
	_scroll_pos = float(_text_scroll.scroll_vertical)


# --- Content ---------------------------------------------------------------

func _load_content() -> Dictionary:
	if not FileAccess.file_exists(CONTENT_PATH):
		if not _ids.is_empty():
			push_warning("JournalReader: %s not found; entries will show without text." % CONTENT_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTENT_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("JournalReader: %s is not a JSON object." % CONTENT_PATH)
		return {}
	return parsed


func _node_for(id: Variant) -> Dictionary:
	if typeof(id) != TYPE_STRING or not _content.has(id):
		return {}
	var node: Variant = _content[id]
	return node if typeof(node) == TYPE_DICTIONARY else {}


func _title_for(id: String) -> String:
	var title := str(_node_for(id).get("speaker", "")).strip_edges()
	if title != "":
		return title
	return id.trim_prefix("entry_").replace("_", " ").capitalize()


func _body_for(id: String) -> String:
	var parts: PackedStringArray = []
	var seen: Dictionary = {}
	var current: Variant = id
	while typeof(current) == TYPE_STRING and not seen.has(current):
		seen[current] = true
		var node := _node_for(current)
		if node.is_empty():
			break
		var text := str(node.get("text", "")).strip_edges()
		if text != "":
			parts.append(text)
		current = node.get("next", null)
	return "\n\n".join(parts)


## The day-count line, e.g. "Day 11 since Edith rowed out". Static so other
## screens can show the same wording without opening the journal.
static func days_text() -> String:
	var days := DAYS_GONE_AT_START + int(GameState.get_flag(DAYS_ELAPSED_FLAG, 0))
	return "Day %d since Edith rowed out" % days


# --- UI --------------------------------------------------------------------

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 110)
	margin.add_theme_constant_override("margin_right", 110)
	margin.add_theme_constant_override("margin_top", 60)
	margin.add_theme_constant_override("margin_bottom", 60)
	add_child(margin)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL
	style.border_color = Color(COLOR_ACCENT, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", style)
	margin.add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	panel.add_child(root)

	# Header: title on the left, the day count kept small on the right.
	var header := HBoxContainer.new()
	root.add_child(header)

	var title := Label.new()
	title.text = "Journal"
	title.add_theme_font_size_override("font_size", 28)
	title.modulate = COLOR_ACCENT
	header.add_child(title)

	var days := Label.new()
	days.text = days_text()
	days.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	days.size_flags_vertical = Control.SIZE_SHRINK_END
	days.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	days.add_theme_font_size_override("font_size", 16)
	days.modulate = COLOR_DIM
	header.add_child(days)

	root.add_child(HSeparator.new())

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 24)
	root.add_child(columns)

	_build_list(columns)
	columns.add_child(VSeparator.new())
	_build_text(columns)

	# Footer: a mouse-only Back button, and the controls for the focused side.
	var footer := HBoxContainer.new()
	root.add_child(footer)

	var back := Button.new()
	back.text = "Back"
	back.focus_mode = Control.FOCUS_NONE
	back.custom_minimum_size = Vector2(110, 36)
	back.pressed.connect(_close)
	footer.add_child(back)

	_hint = Label.new()
	_hint.text = HINT_LIST
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.modulate = COLOR_DIM
	footer.add_child(_hint)

	_link_focus()


func _build_list(parent: Control) -> void:
	var list_scroll := ScrollContainer.new()
	list_scroll.custom_minimum_size = Vector2(LIST_WIDTH, 0)
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.follow_focus = true
	parent.add_child(list_scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	list_scroll.add_child(list)

	if _ids.is_empty():
		var empty := Label.new()
		empty.text = "Nothing recorded yet."
		empty.modulate = COLOR_DIM
		list.add_child(empty)
		return

	for i in _ids.size():
		var button := Button.new()
		button.text = _title_for(_ids[i])
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 40)
		button.add_theme_font_size_override("font_size", 18)
		button.focus_entered.connect(_show_entry.bind(i))
		button.pressed.connect(_focus_text)
		list.add_child(button)
		_entry_buttons.append(button)


func _build_text(parent: Control) -> void:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	parent.add_child(column)

	_entry_title = Label.new()
	_entry_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_entry_title.add_theme_font_size_override("font_size", 22)
	_entry_title.modulate = COLOR_ACCENT
	column.add_child(_entry_title)

	# The text and the two fades share this area; the fades sit on top.
	var area := Control.new()
	area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	area.clip_contents = true
	column.add_child(area)

	_text_scroll = ScrollContainer.new()
	_text_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_text_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_text_scroll.focus_mode = Control.FOCUS_ALL
	_text_scroll.focus_entered.connect(func() -> void: _hint.text = HINT_TEXT)
	_text_scroll.focus_exited.connect(func() -> void: _hint.text = HINT_LIST)
	area.add_child(_text_scroll)

	var text_margin := MarginContainer.new()
	text_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_margin.mouse_filter = Control.MOUSE_FILTER_PASS
	text_margin.add_theme_constant_override("margin_right", 18)
	_text_scroll.add_child(text_margin)

	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.mouse_filter = Control.MOUSE_FILTER_PASS
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_font_size_override("normal_font_size", 20)
	_body.add_theme_font_size_override("italics_font_size", 20)
	_body.add_theme_font_size_override("bold_font_size", 20)
	_body.add_theme_constant_override("line_separation", 4)
	text_margin.add_child(_body)

	_fade_top = _make_fade(true)
	area.add_child(_fade_top)
	_fade_bottom = _make_fade(false)
	area.add_child(_fade_bottom)

	if _ids.is_empty():
		_entry_title.text = ""
		_body.text = ""


## A strip that fades the text into the panel colour. Shown at an edge only
## while there is more text past it, so nobody mistakes a cut-off entry for
## the end of one.
func _make_fade(at_top: bool) -> TextureRect:
	var clear := Color(COLOR_PANEL, 0.0)
	var gradient := Gradient.new()
	gradient.set_color(0, COLOR_PANEL if at_top else clear)
	gradient.set_color(1, clear if at_top else COLOR_PANEL)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	texture.width = 4
	texture.height = 64

	var fade := TextureRect.new()
	fade.texture = texture
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.anchor_left = 0.0
	fade.anchor_right = 1.0
	fade.anchor_top = 0.0 if at_top else 1.0
	fade.anchor_bottom = fade.anchor_top
	fade.offset_left = 0.0
	fade.offset_right = -18.0  # leave the scrollbar uncovered
	fade.offset_top = 0.0 if at_top else -FADE_HEIGHT
	fade.offset_bottom = FADE_HEIGHT if at_top else 0.0
	fade.visible = false
	return fade


## Keep keyboard/gamepad focus inside the reader, so it cannot wander onto the
## menu underneath.
func _link_focus() -> void:
	var here := NodePath(".")
	for i in _entry_buttons.size():
		var button := _entry_buttons[i]
		var above := _entry_buttons[maxi(i - 1, 0)]
		var below := _entry_buttons[mini(i + 1, _entry_buttons.size() - 1)]
		button.focus_neighbor_left = here
		button.focus_neighbor_top = button.get_path_to(above)
		button.focus_neighbor_bottom = button.get_path_to(below)
		button.focus_neighbor_right = button.get_path_to(_text_scroll)
		button.focus_next = here
		button.focus_previous = here
	for control: Control in [_text_scroll, self]:
		control.focus_neighbor_left = here
		control.focus_neighbor_top = here
		control.focus_neighbor_right = here
		control.focus_neighbor_bottom = here
		control.focus_next = here
		control.focus_previous = here


# --- Behaviour -------------------------------------------------------------

func _show_entry(index: int) -> void:
	if index == _selected:
		return
	_remember_scroll()
	_pending_restore_id = ""
	_selected = index
	var id := _ids[index]
	_last_id = id

	for i in _entry_buttons.size():
		var button := _entry_buttons[i]
		for colour_name in ["font_color", "font_focus_color", "font_hover_color"]:
			if i == index:
				button.add_theme_color_override(colour_name, COLOR_ACCENT)
			else:
				button.remove_theme_color_override(colour_name)

	_entry_title.text = _title_for(id)
	var body := _body_for(id)
	if body == "":
		push_warning("JournalReader: no text for '%s' in %s." % [id, CONTENT_PATH])
		body = "[color=#ffffff80][i]This entry has no text yet.[/i][/color]"
	_body.text = body
	_text_scroll.scroll_vertical = 0
	_scroll_pos = 0.0
	_restore_scroll(id)


func _focus_text() -> void:
	_text_scroll.grab_focus()


func _focus_list() -> void:
	if _selected >= 0:
		_entry_buttons[_selected].grab_focus()


func _close() -> void:
	queue_free()
	if is_instance_valid(_previous_focus) and _previous_focus.is_visible_in_tree():
		_previous_focus.grab_focus()


func _process(delta: float) -> void:
	var bar := _text_scroll.get_v_scroll_bar()
	var max_scroll := maxf(bar.max_value - bar.page, 0.0)

	var axis := Input.get_axis("ui_up", "ui_down") if _text_scroll.has_focus() else 0.0
	if axis != 0.0:
		_scroll_pos = clampf(_scroll_pos + axis * SCROLL_SPEED * delta, 0.0, max_scroll)
		_text_scroll.scroll_vertical = int(round(_scroll_pos))
	else:
		_scroll_pos = float(_text_scroll.scroll_vertical)  # follow the mouse wheel

	_fade_top.visible = _text_scroll.scroll_vertical > 1
	_fade_bottom.visible = float(_text_scroll.scroll_vertical) < max_scroll - 1.0


## Runs before the GUI sees the event, so the reader can keep ui_cancel away
## from the pause menu and stop focus navigation while the text is scrolling.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _text_scroll.has_focus():
			_focus_list()
		else:
			_close()
		get_viewport().set_input_as_handled()
		return

	if event.is_action("ui_focus_next") or event.is_action("ui_focus_prev"):
		get_viewport().set_input_as_handled()
		return

	if _text_scroll.has_focus():
		if event.is_action_pressed("ui_left"):
			_focus_list()
		for action in ["ui_up", "ui_down", "ui_left", "ui_right", "ui_accept"]:
			if event.is_action(action):
				get_viewport().set_input_as_handled()
				return
	elif _ids.is_empty():
		for action in ["ui_up", "ui_down", "ui_left", "ui_right", "ui_accept"]:
			if event.is_action(action):
				get_viewport().set_input_as_handled()
				return
