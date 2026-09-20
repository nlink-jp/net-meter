#!/usr/bin/env python3
"""Checks the documents can be trusted.

Prose does not compile, so nothing else notices when it goes wrong. Four things
are checked:

- every relative link in a Markdown file resolves;
- every English document has its Japanese mirror and the reverse
  (`README.md` <-> `README.ja.md`, `docs/en/x.md` <-> `docs/ja/x.ja.md`);
- each mirrored pair names the same identifiers. Prose cannot be compared across
  a translation, but the things a translation must not change can: flags, make
  targets, snake_case and SCREAMING_SNAKE names. A feature documented in one
  language only shows up here as an identifier the other side lacks;
- no retired name is still in use. Add an entry to RETIRED in the same commit
  that withdraws a mechanism, so the code and the documents are swept together.

What this does not check: that two mirrored documents say the same thing in
prose. A pair can pass and still disagree in a sentence that names no identifier.
"""

import re
import sys
from pathlib import Path

# name -> why it is retired, printed when it reappears
RETIRED: dict[str, str] = {
    "statusPlaceholder": "the scaffold's placeholder symbol went when the item started drawing rates",
    "automaticChoice": "a string of the interim settings menu, which the panel replaced",
    "menuNeedsUpdate": "the interim settings menu was replaced by the panel",
    "secondsPerColumn": "graph bars are samples, not time buckets (RFP Amendment A12)",
    "sameClickWindow": "clicks and actions are matched by order, never by time (PanelToggle)",
    "monitorClosedAt": "clicks and actions are matched by order, never by time (PanelToggle)",
    "PopoverClick": "renamed PanelClick when the popover went (ADR-0003)",
    "popoverDidClose": "the panel is a non-activating NSPanel with one close path, hidePanel (ADR-0003)",
}

SEARCHED_DIRS = ("Sources", "Tests", "docs", "spikes")
# The Makefile is here for BREW_DESC: the cask description is text a user reads.
SEARCHED_FILES = ("README.md", "README.ja.md", "AGENTS.md", "CLAUDE.md", "Makefile")
SEARCHED_SUFFIXES = {".swift", ".md", ".py"}
IGNORED_PARTS = {".build", ".git", "dist", ".swiftpm"}

LINK = re.compile(r"!?\[([^\]]*)\]\(([^)]+)\)")
FENCE = re.compile(r"^\s*(```|~~~)")
CODE_SPAN = re.compile(r"`([^`\n]+)`")
STRUCK = re.compile(r"~~.*?~~")

# Shapes that are the same in every language. Anything else in backticks —
# file names, placeholders, prose — is left alone: if this check ever reacts to
# prose, take the backticks off the prose rather than loosening the rule.
IDENTIFIER_SHAPES = (
    re.compile(r"--[a-z][a-z0-9-]*"),             # --flag
    re.compile(r"make [a-z][a-z0-9-]*"),          # make target
    re.compile(r"[a-z][a-z0-9]*(_[a-z0-9]+)+"),   # snake_case
    re.compile(r"[A-Z][A-Z0-9]*(_[A-Z0-9]+)+"),   # SCREAMING_SNAKE
    re.compile(r"\[[a-z_.]+\]\.[a-z_]+"),         # [section].key
)


def markdown_files(root: Path):
    for path in sorted(root.rglob("*.md")):
        if not IGNORED_PARTS.intersection(path.relative_to(root).parts):
            yield path


def searched_files(root: Path):
    for name in SEARCHED_FILES:
        if (root / name).is_file():
            yield root / name
    for name in SEARCHED_DIRS:
        for path in sorted((root / name).rglob("*")):
            if path.is_file() and path.suffix in SEARCHED_SUFFIXES:
                yield path


def mirror_pairs(root: Path):
    """(english, japanese) for every document that has a counterpart slot."""
    yield root / "README.md", root / "README.ja.md"
    en, ja = root / "docs" / "en", root / "docs" / "ja"
    seen = set()
    for path in sorted(en.rglob("*.md")):
        relative = path.relative_to(en)
        mirror = ja / relative.with_name(relative.stem + ".ja.md")
        seen.add(mirror)
        yield path, mirror
    for path in sorted(ja.rglob("*.ja.md")):
        if path not in seen:
            relative = path.relative_to(ja)
            yield en / relative.with_name(relative.name[: -len(".ja.md")] + ".md"), path


def broken_links(root: Path) -> list[str]:
    problems = []
    for path in markdown_files(root):
        for label, target in LINK.findall(path.read_text(encoding="utf-8")):
            if target.startswith(("http://", "https://", "#", "mailto:")):
                continue
            if not (path.parent / target.split("#")[0]).resolve().exists():
                problems.append(f"{path.relative_to(root)}: broken link [{label}]({target})")
    return problems


def missing_mirrors(root: Path) -> list[str]:
    problems = []
    for english, japanese in mirror_pairs(root):
        for source, mirror in ((english, japanese), (japanese, english)):
            if source.is_file() and not mirror.is_file():
                problems.append(
                    f"{source.relative_to(root)}: no mirror at {mirror.relative_to(root)}"
                )
    return problems


def identifiers(text: str) -> set[str]:
    """Language-invariant identifiers in code spans, outside code fences."""
    found = set()
    fenced = False
    for line in text.splitlines():
        if FENCE.match(line):
            fenced = not fenced
            continue
        if fenced:
            continue
        for span in CODE_SPAN.findall(line):
            if any(shape.fullmatch(span) for shape in IDENTIFIER_SHAPES):
                found.add(span)
    return found


def identifier_mismatches(root: Path) -> list[str]:
    problems = []
    for english, japanese in mirror_pairs(root):
        if not (english.is_file() and japanese.is_file()):
            continue  # reported by missing_mirrors
        en_ids = identifiers(english.read_text(encoding="utf-8"))
        ja_ids = identifiers(japanese.read_text(encoding="utf-8"))
        for name in sorted(en_ids - ja_ids):
            problems.append(
                f"{japanese.relative_to(root)}: lacks `{name}`, which {english.relative_to(root)} names"
            )
        for name in sorted(ja_ids - en_ids):
            problems.append(
                f"{english.relative_to(root)}: lacks `{name}`, which {japanese.relative_to(root)} names"
            )
    return problems


def retired_names(root: Path, retired: dict[str, str]) -> list[str]:
    problems = []
    for path in searched_files(root):
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            # A design document is not rewritten when something is withdrawn; the
            # withdrawal is annotated with a strike-through. That annotation has
            # to be able to name what it withdraws.
            visible = STRUCK.sub("", line)
            for name, reason in retired.items():
                if name in visible:
                    problems.append(
                        f"{path.relative_to(root)}:{number}: retired name {name!r} — {reason}"
                    )
    return problems


def check(root: Path, retired: dict[str, str] | None = None) -> list[str]:
    retired = RETIRED if retired is None else retired
    return (
        broken_links(root)
        + missing_mirrors(root)
        + identifier_mismatches(root)
        + retired_names(root, retired)
    )


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    problems = check(root)
    for problem in problems:
        print(problem)
    if problems:
        print(f"\ncheck-docs: {len(problems)} problem(s)")
        return 1
    print(
        "check-docs: links resolve, mirrors are paired and name the same identifiers, "
        "no retired name in use"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
