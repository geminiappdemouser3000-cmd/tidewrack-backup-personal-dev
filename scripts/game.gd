extends Node2D
## Game — the vertical-slice level: the ground floor of Cape Marrow Light.
## Builds the room, player, interactables, HUD prompt, the "Journal updated"
## line, dialogue box, and a pause overlay in code.

const DIALOGUE := "res://data/dialogue/keeper_intro.json"
const INTERACT_RADIUS := 90.0
const ROOM := Rect2(120, 140, 1040, 460)

## Journal entry recorded when the player examines an interactable, keyed by
## the interactable's dialogue start id. Only the keeper's log makes an entry
## for now; add a line here to have another object record one. Entries for
## the choices made inside a dialogue come from the story flags instead (see
## `when_flag` in res://data/dialogue/journal.json, which also holds every
## entry's title and text).
const JOURNAL_ENTRIES := {
	"logbook": "entry_logbook",
}

## The line shown at the top right whenever an entry is recorded, and how
## long it stays fully visible (it fades in and out on either side of that).
const JOURNAL_NOTE_TEXT := "Journal updated"
const JOURNAL_NOTE_SECONDS := 2.5

var _player: Player
var _interactables: Array[Interactable] = []
var _prompt: Label
var _journal_note: Label
var _journal_note_tween: Tween
var _nearest: Interactable = null
var _paused: bool = false


func _ready() -> void:
	_build_room()
	_build_player()
	_build_interactables()
	_build_hud()

	var dialogue_box := preload("res://scenes/ui/dialogue_box.tscn").instantiate()
	add_child(dialogue_box)

	DialogueManager.dialogue_started.connect(func(): _set_movement(false))
	DialogueManager.dialogue_finished.connect(func(): _set_movement(true))
	Journal.entry_added.connect(_show_journal_note)


func _build_room() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#0f1a22")
	bg.size = Vector2(1280, 720)
	add_child(bg)

	var floor_rect := ColorRect.new()
	floor_rect.color = Color("#1c2b34")
	floor_rect.position = ROOM.position
	floor_rect.size = ROOM.size
	add_child(floor_rect)

	var title := Label.new()
	title.text = "Cape Marrow Light — ground floor"
	title.position = Vector2(ROOM.position.x, ROOM.position.y - 34)
	title.modulate = Color(1, 1, 1, 0.5)
	add_child(title)


func _build_player() -> void:
	_player = Player.new()
	_player.bounds = ROOM.grow(-30)
	_player.position = Vector2(ROOM.position.x + ROOM.size.x * 0.5, ROOM.position.y + ROOM.size.y - 60)
	add_child(_player)

	var camera := Camera2D.new()
	camera.position_smoothing_enabled = true
	_player.add_child(camera)
	camera.make_current()


func _build_interactables() -> void:
	_add_interactable("Logbook", "Read the keeper's log", "logbook",
		Vector2(ROOM.position.x + 160, ROOM.position.y + 120), Color("#8a6f4b"))
	_add_interactable("Radio set", "Call the mainland", "radio",
		Vector2(ROOM.position.x + ROOM.size.x - 180, ROOM.position.y + 130), Color("#4b6f8a"))
	_add_interactable("Lamp-room stair", "Climb toward the light", "door",
		Vector2(ROOM.position.x + ROOM.size.x * 0.5, ROOM.position.y + 60), Color("#3a4a54"))


func _add_interactable(label: String, prompt: String, start_id: String, pos: Vector2, color: Color) -> void:
	var item := Interactable.new()
	item.label = label
	item.prompt_text = prompt
	item.dialogue_path = DIALOGUE
	item.dialogue_start = start_id
	item.color = color
	item.position = pos
	add_child(item)
	item.setup()
	_interactables.append(item)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	_prompt = Label.new()
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_top = -70
	_prompt.offset_left = -200
	_prompt.offset_right = 200
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 20)
	_prompt.modulate = Color("#ffd466")
	_prompt.hide()
	layer.add_child(_prompt)

	# Top right, clear of the dialogue box, which sits along the bottom.
	_journal_note = Label.new()
	_journal_note.text = JOURNAL_NOTE_TEXT
	_journal_note.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_journal_note.offset_left = -332
	_journal_note.offset_right = -32
	_journal_note.offset_top = 24
	_journal_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_journal_note.add_theme_font_size_override("font_size", 20)
	_journal_note.modulate = Color("#ffd466", 0.0)
	_journal_note.hide()
	layer.add_child(_journal_note)


## Show the "Journal updated" line. Entries recorded while it is already up
## (several choices in one conversation) restart its time on screen instead of
## stacking. Starting entries and loaded saves do not come through here.
func _show_journal_note(_id: String) -> void:
	if _journal_note_tween != null:
		_journal_note_tween.kill()
	_journal_note.show()
	_journal_note_tween = create_tween()
	_journal_note_tween.tween_property(_journal_note, "modulate:a", 1.0, 0.25)
	_journal_note_tween.tween_interval(JOURNAL_NOTE_SECONDS)
	_journal_note_tween.tween_property(_journal_note, "modulate:a", 0.0, 0.6)
	_journal_note_tween.tween_callback(_journal_note.hide)


func _process(_delta: float) -> void:
	if _paused or DialogueManager.is_active:
		_prompt.hide()
		return
	_nearest = _find_nearest()
	if _nearest != null:
		_prompt.text = "[ Enter ] %s" % _nearest.prompt_text
		_prompt.show()
	else:
		_prompt.hide()


func _find_nearest() -> Interactable:
	var best: Interactable = null
	var best_dist := INTERACT_RADIUS
	for item in _interactables:
		if not item.can_interact():
			continue
		var dist := _player.position.distance_to(item.position)
		if dist <= best_dist:
			best_dist = dist
			best = item
	return best


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if _paused or DialogueManager.is_active:
		return
	if event.is_action_pressed("ui_accept") and _nearest != null:
		# Record the object's own entry as its dialogue opens, so it lists
		# ahead of the entries the player's choices in that dialogue record.
		var start_id := _nearest.dialogue_start
		if _nearest.can_interact() and JOURNAL_ENTRIES.has(start_id):
			Journal.discover(str(JOURNAL_ENTRIES[start_id]))
		_nearest.interact()
		get_viewport().set_input_as_handled()


func _set_movement(enabled: bool) -> void:
	if _player != null:
		_player.can_move = enabled and not _paused


func _toggle_pause() -> void:
	if DialogueManager.is_active:
		return
	_paused = not _paused
	_set_movement(not _paused)
	if _paused:
		_show_pause_menu()


func _show_pause_menu() -> void:
	var overlay := Control.new()
	overlay.name = "PauseOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var layer := CanvasLayer.new()
	layer.layer = 20
	layer.name = "PauseLayer"
	layer.add_child(overlay)
	add_child(layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	center.add_child(vbox)

	var resume := _menu_button("Resume")
	resume.pressed.connect(func():
		layer.queue_free()
		_paused = false
		_set_movement(true))
	vbox.add_child(resume)

	# The journal only appears once there is something in it.
	if not Journal.entries().is_empty():
		var journal := _menu_button("Journal")
		journal.pressed.connect(func():
			overlay.add_child(JournalReader.new()))
		vbox.add_child(journal)

	var save := _menu_button("Save")
	save.pressed.connect(func():
		GameState.current_scene = scene_file_path
		var ok := GameState.save_game()
		save.text = "Saved ✓" if ok else "Save failed")
	vbox.add_child(save)

	var settings := _menu_button("Settings")
	settings.pressed.connect(func():
		overlay.add_child(preload("res://scenes/ui/settings.tscn").instantiate()))
	vbox.add_child(settings)

	var menu := _menu_button("Main Menu")
	menu.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	vbox.add_child(menu)

	resume.grab_focus()


func _menu_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(200, 40)
	button.add_theme_font_size_override("font_size", 20)
	return button
