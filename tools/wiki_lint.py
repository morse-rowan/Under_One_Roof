"""Read-only checks for the shared project wiki. Python 3 standard library only."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from datetime import date
from pathlib import Path
from urllib.parse import unquote, urlsplit

DEFAULT_ROOT = Path.home() / "Documents/Obsidian Vault/school/Steelhacks"
TYPES = {"hub", "project", "source-summary", "research", "plan", "decision", "log"}
STATUSES = {"current", "exploratory", "open", "proposed", "accepted", "superseded"}


def local_links(text: str, parent: Path) -> list[Path]:
    """Project convention: inline Markdown file links, optionally angle-wrapped."""
    text = re.sub(r"(?ms)^```.*?^```[^\n]*", "", text)
    text = re.sub(r"`[^`\n]+`", "", text)
    links = []
    for match in re.finditer(r"\[[^\]\n]*\]\(\s*(?:<([^>]+)>|([^\s)]+))\s*\)", text):
        target = match.group(1) or match.group(2)
        parsed = urlsplit(target)
        if parsed.scheme or target.startswith(("#", "//")):
            continue
        if parsed.path:
            links.append((parent / unquote(parsed.path)).resolve())
    return links


def check(root: Path, repo: Path | None = None) -> tuple[list[str], list[str], int]:
    errors: list[str] = []
    warnings: list[str] = []
    root = root.resolve()
    required = ["AGENTS.md", "CLAUDE.md", "SCHEMA.md", "Start Here.md",
                "wiki/index.md", "wiki/log.md", "wiki/project/current-state.md",
                "maintenance/ingested-notes.json"]
    for name in required:
        if not (root / name).is_file():
            errors.append(f"Missing required file: {name}")
    if not root.is_dir():
        return errors, warnings, 0

    # Never parse or enforce formatting on human-owned note contents.
    pages = sorted((root / "wiki").rglob("*.md"))
    owned = list(root.glob("*.md"))
    for folder in ("wiki", "raw", "templates"):
        owned.extend((root / folder).rglob("*.md"))
    if repo:
        owned.extend(repo / name for name in ("README.md", "AGENTS.md", "CLAUDE.md"))
    texts: dict[Path, str] = {}
    for path in owned:
        try:
            text = path.read_text(encoding="utf-8-sig")
        except (OSError, UnicodeError) as exc:
            errors.append(f"Cannot read {path}: {exc}")
            continue
        texts[path.resolve()] = text
        for target in local_links(text, path.parent):
            if not target.is_file():
                errors.append(f"Broken local file link in {path}: {target}")

    index_path = (root / "wiki/index.md").resolve()
    indexed = set(local_links(texts.get(index_path, ""), index_path.parent))
    for path in pages:
        text = texts.get(path.resolve(), "")
        label = path.relative_to(root).as_posix()
        front = re.match(r"\A---\r?\n(.*?)\r?\n---(?:\r?\n|$)", text, re.S)
        meta = dict(re.findall(r"(?m)^(title|type|status|updated):\s*([^\r\n]+)$",
                               front.group(1) if front else ""))
        meta = {key: value.strip().strip('\"\'') for key, value in meta.items()}
        for key in ("title", "type", "status", "updated"):
            if not meta.get(key):
                errors.append(f"{label}: missing frontmatter {key}")
        if meta.get("type") not in TYPES:
            errors.append(f"{label}: invalid type")
        if meta.get("status") not in STATUSES:
            errors.append(f"{label}: invalid status")
        try:
            value = meta.get("updated", "")
            if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
                raise ValueError("date format")
            date.fromisoformat(value)
        except ValueError:
            errors.append(f"{label}: invalid updated date")
        if path.resolve() != index_path and path.resolve() not in indexed:
            errors.append(f"{label}: not linked from wiki/index.md")
        if meta.get("type") not in {"hub", "log"}:
            source = re.search(r"(?ms)^## Sources\s*\n(.*?)(?=^## |\Z)", text)
            if not source or not re.search(r"\[[^\]]+\]\(", source.group(1)):
                errors.append(f"{label}: missing linked Sources section")

    try:
        register = json.loads((root / "maintenance/ingested-notes.json").read_text(encoding="utf-8-sig"))
        if register.get("version") != 1 or not isinstance(register.get("notes"), list):
            raise ValueError("expected version 1 and notes list")
        notes_root = (root / "My Notes").resolve()
        if not notes_root.is_dir():
            errors.append("Missing human-owned My Notes directory")
        tracked = set()
        for note in register["notes"]:
            path = (root / note["path"]).resolve()
            if not path.is_relative_to(notes_root):
                raise ValueError("ingested note path must be inside My Notes")
            if path in tracked:
                raise ValueError(f"duplicate note entry: {note['path']}")
            tracked.add(path)
            if not re.fullmatch(r"[0-9a-fA-F]{64}", note["sha256"]):
                raise ValueError(f"invalid SHA-256 for {note['path']}")
            date.fromisoformat(note["ingested"])
            if not note.get("pages"):
                raise ValueError(f"no affected pages for {note['path']}")
            for name in note["pages"]:
                target = (root / name).resolve()
                if not target.is_relative_to((root / "wiki").resolve()) or not target.is_file():
                    errors.append(f"Invalid ingestion page: {name}")
            if not path.is_file():
                warnings.append(f"Previously ingested note missing: {note['path']}")
            elif hashlib.sha256(path.read_bytes()).hexdigest() != note["sha256"].lower():
                warnings.append(f"Changed note needs reconciliation: {note['path']}")
        for path in sorted(notes_root.rglob("*")):
            if path.is_file() and path.resolve() not in tracked:
                warnings.append(f"New note/source needs ingestion: {path.relative_to(root)}")
    except (OSError, ValueError, TypeError, KeyError, AttributeError) as exc:
        errors.append(f"Invalid ingestion register: {exc}")
    return errors, warnings, len(pages)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=DEFAULT_ROOT)
    args = parser.parse_args()
    errors, warnings, count = check(args.root, Path(__file__).resolve().parents[1])
    for message in errors:
        print(f"ERROR: {message}")
    for message in warnings:
        print(f"WARN: {message}")
    print(f"Checked {count} wiki pages: {len(errors)} errors, {len(warnings)} freshness warnings.")
    print("Read-only check; source accuracy and contradictions require agent review.")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
