extends Node
## Journal — discovered-logs system (Public Demo).
##
## Autoloaded as `Journal`. Holds the ids of the entries the player has
## discovered, in discovery order. GameState writes them into user://save.json
## and hands them back on load, so this script never touches the save file
## itself and has no dependency on GameState.

## A new entry was discovered during play. Not emitted when a save is loaded.
signal entry_added(id: String)
## The whole list was replaced (new game or a loaded save).
signal entries_reset

var _entries: Array[String] = []


func discover(id: String) -> void:
	if id == "" or id in _entries:
		return
	_entries.append(id)
	entry_added.emit(id)


func entries() -> Array[String]:
	return _entries.duplicate()


func has(id: String) -> bool:
	return id in _entries


## Forget every entry. Called by GameState.new_game().
func clear() -> void:
	_entries.clear()
	entries_reset.emit()


## Replace the list with ids read from a save file. Called by
## GameState.load_game(). Anything that isn't a non-empty string is skipped,
## and duplicates are dropped, so a hand-edited save can't break the journal.
func restore(ids: Array) -> void:
	_entries.clear()
	for raw in ids:
		if typeof(raw) != TYPE_STRING:
			continue
		var id: String = raw
		if id == "" or id in _entries:
			continue
		_entries.append(id)
	entries_reset.emit()

# TODO(demo): reader UI, and the dialogue hook that calls discover().
