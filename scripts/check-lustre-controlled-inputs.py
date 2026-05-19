#!/usr/bin/env python3
"""Flag Lustre textareas with input/change handlers but no controlled value."""

from __future__ import annotations

import argparse
from pathlib import Path
import sys


def gleam_files(paths: list[Path]) -> list[Path]:
    files: list[Path] = []
    for path in paths:
        if path.is_file() and path.suffix == ".gleam":
            files.append(path)
        elif path.is_dir():
            files.extend(sorted(path.rglob("*.gleam")))
    return files


def call_body(source: str, open_paren: int) -> tuple[str, int] | None:
    depth = 0
    index = open_paren
    in_string = False
    in_line_comment = False
    while index < len(source):
        char = source[index]
        next_char = source[index + 1] if index + 1 < len(source) else ""

        if in_line_comment:
            if char == "\n":
                in_line_comment = False
            index += 1
            continue

        if in_string:
            if char == "\\":
                index += 2
                continue
            if char == '"':
                in_string = False
            index += 1
            continue

        if char == "/" and next_char == "/":
            in_line_comment = True
            index += 2
            continue

        if char == '"':
            in_string = True
            index += 1
            continue

        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0:
                return source[open_paren : index + 1], index + 1
        index += 1
    return None


def line_number(source: str, index: int) -> int:
    return source.count("\n", 0, index) + 1


def scan_file(path: Path) -> list[str]:
    source = path.read_text()
    findings: list[str] = []
    needle = "textarea("

    offset = 0
    while True:
        start = source.find(needle, offset)
        if start == -1:
            break
        body = call_body(source, start + len(needle) - 1)
        if body is None:
            break
        text, end = body
        has_handler = "event.on_input" in text or "event.on_change" in text
        has_controlled_value = "value(" in text
        if has_handler and not has_controlled_value:
            findings.append(
                f"{path}:{line_number(source, start)} textarea has an input/change handler but no value(...) attribute"
            )
        offset = end

    return findings


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="+", type=Path)
    args = parser.parse_args()

    findings: list[str] = []
    for path in gleam_files(args.paths):
        findings.extend(scan_file(path))

    if findings:
        print("\n".join(findings))
        return 1

    print("No uncontrolled Lustre textareas with input/change handlers found.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
