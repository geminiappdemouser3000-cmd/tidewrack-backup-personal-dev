extends Node
## Journal — discovered-logs system (Public Demo).
##
## Autoloaded as `Journal`. Holds the ids of the entries the player has
## discovered, in discovery order. GameState writes them into user://save.json
## and hands them back on load, so this script never touches the save file
## itself and has no dependency on GameState.
##
## Entries come from the story flags. Each entry in
## res://data/dialogue/journal.json can name the flags that unlock it:
##
##     "entry_skeptic": { "speaker": "", "text": "", "next": null,
##                        "when_flag": { "skeptic": true } }
##
## `when_flag` has the same shape as a dialogue choice's `set_flag`. Whenever a
## flag is set, GameState calls sync_with_flags() and every entry whose flags
## all match is recorded. An entry with no `when_flag` is never recorded this
## way; something has to call discover() for it (scripts/game.gd does that for
## the keeper's log).

const CONTENT_PATH := "res://data/dialogue/journal.json"

## A new entry was discovered during play. Not emitted when a save is loaded.
signal entry_added(id: String)
## The whole list was replaced (new game or a loaded save).
signal entries_reset

var _entries: Array[String] = []
## entry id -> { flag name: required value }, in journal.json order.
var _flag_rules: Dictionary = {}


func _ready() -> void:
	_flag_rules = _load_flag_rules()


func discover(id: String) -> void:
	if id == "" or id in _entries:
		return
	_entries.append(id)
	entry_added.emit(id)


func entries() -> Array[String]:
	return _entries.duplicate()


func has(id: String) -> bool:
	return id in _entries


## Record every entry whose `when_flag` conditions all hold in `flags`.
## Called by GameState.set_flag(). Entries already recorded stay recorded even
## if a flag later changes: the journal is a record of what happened.
func sync_with_flags(flags: Dictionary) -> void:
	for id: String in _flag_rules:
		if id in _entries:
			continue
		if _rule_holds(_flag_rules[id], flags):
			discover(id)


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


func _load_flag_rules() -> Dictionary:
	var rules: Dictionary = {}
	if not FileAccess.file_exists(CONTENT_PATH):
		push_warning("Journal: %s not found; no entries will come from story flags." % CONTENT_PATH)
		return rules
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTENT_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Journal: %s is not a JSON object." % CONTENT_PATH)
		return rules
	var content: Dictionary = parsed
	for id in content:
		var node: Variant = content[id]
		if typeof(node) != TYPE_DICTIONARY:
			continue
		var rule: Variant = (node as Dictionary).get("when_flag", null)
		if typeof(rule) == TYPE_DICTIONARY and not (rule as Dictionary).is_empty():
			rules[str(id)] = rule
	return rules


func _rule_holds(rule: Dictionary, flags: Dictionary) -> bool:
	for flag_name in rule:
		if not flags.has(flag_name):
			return false
		if not _same_value(rule[flag_name], flags[flag_name]):
			return false
	return true


## Strict comparison, except that whole and fractional numbers compare by
## value (JSON reads every number as a float; code may set an int).
func _same_value(a: Variant, b: Variant) -> bool:
	var numbers := [TYPE_INT, TYPE_FLOAT]
	if typeof(a) in numbers and typeof(b) in numbers:
		return is_equal_approx(float(a), float(b))
	return typeof(a) == typeof(b) and a == b
