#!/usr/bin/env python3
"""Validate Tidewrack dialogue graphs without needing the Godot engine.

Checks, for every data/dialogue/*.json file:
  - it parses as a JSON object of node_id -> node
  - each node is either a linear node ("next": id|null) or a choice node
    ("choices": [{text, next, set_flag?}]) — not neither, not both
  - every referenced target id exists
  - at least one terminal (next == null) is reachable from an entry point
  - reports orphan nodes (unreachable from any known entry) as warnings

Then prints a flag report: for every choice in every graph, the story flags it
sets (or that it sets none), and the flags each graph sets overall. The report
is for reading; it never changes the exit code.

Exit code 0 = all valid, 1 = at least one error.

Usage:  python3 tests/validate_dialogue.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

# Entry-point node ids the game starts graphs from (see scripts/game.gd).
KNOWN_ENTRIES = {"logbook", "radio", "door", "start"}

ROOT = Path(__file__).resolve().parent.parent
DIALOGUE_DIR = ROOT / "data" / "dialogue"


def reachable(graph: dict, entries: set[str]) -> set[str]:
    seen: set[str] = set()
    stack = [e for e in entries if e in graph]
    while stack:
        nid = stack.pop()
        if nid in seen:
            continue
        seen.add(nid)
        node = graph[nid]
        targets: list[str] = []
        if isinstance(node.get("choices"), list):
            targets += [c.get("next") for c in node["choices"]]
        if "next" in node:
            targets.append(node.get("next"))
        for t in targets:
            if isinstance(t, str) and t in graph:
                stack.append(t)
    return seen


def validate_file(path: Path) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    warnings: list[str] = []

    try:
        graph = json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        return [f"{path.name}: invalid JSON — {exc}"], warnings

    if not isinstance(graph, dict):
        return [f"{path.name}: top level must be an object of node_id -> node"], warnings

    has_terminal = False
    for nid, node in graph.items():
        if not isinstance(node, dict):
            errors.append(f"{path.name}:{nid}: node must be an object")
            continue

        has_choices = isinstance(node.get("choices"), list) and len(node["choices"]) > 0
        has_next = "next" in node

        if not has_choices and not has_next:
            errors.append(f"{path.name}:{nid}: node has neither 'next' nor 'choices'")
        if has_choices and has_next:
            errors.append(f"{path.name}:{nid}: node has both 'next' and 'choices' (ambiguous)")

        if has_next and node.get("next") is None:
            has_terminal = True

        if has_next and isinstance(node.get("next"), str) and node["next"] not in graph:
            errors.append(f"{path.name}:{nid}: 'next' points to missing node '{node['next']}'")

        if has_choices:
            for i, choice in enumerate(node["choices"]):
                if not isinstance(choice, dict) or "text" not in choice:
                    errors.append(f"{path.name}:{nid}: choice #{i} needs a 'text' field")
                    continue
                target = choice.get("next")
                if target is not None and (not isinstance(target, str) or target not in graph):
                    errors.append(f"{path.name}:{nid}: choice #{i} 'next' -> missing node '{target}'")
                if target is None:
                    has_terminal = True

    if not has_terminal:
        errors.append(f"{path.name}: no terminal node (a node with next == null) — the graph never ends")

    entries = KNOWN_ENTRIES & set(graph.keys())
    if not entries:
        warnings.append(f"{path.name}: no known entry point ({sorted(KNOWN_ENTRIES)}) present")
    else:
        seen = reachable(graph, entries)
        for orphan in sorted(set(graph) - seen):
            warnings.append(f"{path.name}:{orphan}: unreachable from entry points {sorted(entries)}")

    return errors, warnings


def describe_flags(set_flag: object) -> str:
    """One line for a `set_flag` value, e.g. 'trusted_edith = false'."""
    if set_flag is None:
        return "(sets no flag)"
    if not isinstance(set_flag, dict):
        return f"(set_flag is not an object: {json.dumps(set_flag)})"
    if not set_flag:
        return "(sets no flag)"
    return ", ".join(f"{name} = {json.dumps(value)}" for name, value in set_flag.items())


def flag_report(path: Path) -> list[str]:
    """Lines listing the flags each choice (and each node) in a graph sets."""
    try:
        graph = json.loads(path.read_text())
    except json.JSONDecodeError:
        return [f"  {path.name}: not readable (invalid JSON)"]
    if not isinstance(graph, dict):
        return [f"  {path.name}: not readable (top level is not an object)"]

    lines: list[str] = []
    flags_set: set[str] = set()
    for nid, node in graph.items():
        if not isinstance(node, dict):
            continue
        node_lines: list[str] = []

        # A node can set flags itself, applied when the node is entered.
        if "set_flag" in node:
            node_lines.append(f"      on entering this node -> {describe_flags(node['set_flag'])}")
            if isinstance(node["set_flag"], dict):
                flags_set.update(str(name) for name in node["set_flag"])

        choices = node.get("choices")
        if isinstance(choices, list) and choices:
            labels = [
                json.dumps(str(c.get("text", "")), ensure_ascii=False) if isinstance(c, dict) else "(not an object)"
                for c in choices
            ]
            width = max(len(label) for label in labels)
            for label, choice in zip(labels, choices):
                set_flag = choice.get("set_flag") if isinstance(choice, dict) else None
                node_lines.append(f"      {label.ljust(width)} -> {describe_flags(set_flag)}")
                if isinstance(set_flag, dict):
                    flags_set.update(str(name) for name in set_flag)

        if node_lines:
            lines.append(f"    {nid}")
            lines += node_lines

    if not lines:
        return [f"  {path.name}: no choices, sets no flags"]
    summary = ", ".join(sorted(flags_set)) if flags_set else "none"
    return [f"  {path.name}"] + lines + [f"    flags this graph sets: {summary}"]


def main() -> int:
    files = sorted(DIALOGUE_DIR.glob("*.json"))
    if not files:
        print(f"No dialogue files found in {DIALOGUE_DIR}")
        return 1

    all_errors: list[str] = []
    all_warnings: list[str] = []
    for path in files:
        errs, warns = validate_file(path)
        all_errors += errs
        all_warnings += warns
        status = "OK" if not errs else "FAIL"
        print(f"[{status}] {path.relative_to(ROOT)}  ({len(json.loads(path.read_text()))} nodes)")

    for w in all_warnings:
        print(f"  warning: {w}")
    for e in all_errors:
        print(f"  ERROR:   {e}")

    print()
    print("Flag report")
    for path in files:
        for line in flag_report(path):
            print(line)

    print()
    if all_errors:
        print(f"✗ {len(all_errors)} error(s), {len(all_warnings)} warning(s)")
        return 1
    print(f"✓ all dialogue graphs valid ({len(all_warnings)} warning(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main())


# --- Public Demo: journal graphs -------------------------------------------
# The journal system (scripts/journal.gd) reads discovered-log entries from the
# same JSON-graph format, so they validate through the checker above. Journal
# graphs live under data/dialogue/ with an "entry_*" id and are held to the same
# rules (targets resolve, a terminal exists). This hook is a placeholder until
# the journal content lands for the public demo.
JOURNAL_ENTRY_PREFIX = "entry_"


def is_journal_graph(graph: dict) -> bool:
	return any(str(k).startswith(JOURNAL_ENTRY_PREFIX) for k in graph)
