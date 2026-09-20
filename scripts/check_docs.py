#!/usr/bin/env python3
"""Checks the documents can be trusted.

Prose does not compile, so nothing else notices when it goes wrong. Three things
are checked:

- every relative link in a Markdown file resolves;
- every English document has its Japanese mirror and the reverse
  (`README.md` <-> `README.ja.md`, `docs/en/x.md` <-> `docs/ja/x.ja.md`);
- no retired name is still in use. Add an entry to RETIRED in the same commit
  that withdraws a mechanism, so the code and the documents are swept together.
"""

import re
import sys
from pathlib import Path

# name -> why it is retired, printed when it reappears
RETIRED: dict[str, str] = {}

SEARCHED_DIRS = ("Sources", "Tests", "docs", "spikes")
SEARCHED_FILES = ("README.md", "README.ja.md", "AGENTS.md", "CLAUDE.md")
SEARCHED_SUFFIXES = {".swift", ".md", ".py"}
IGNORED_PARTS = {".build", ".git", "dist", ".swiftpm"}

LINK = re.compile(r"!?\[([^\]]*)\]\(([^)]+)\)")


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

    def expect(source: Path, mirror: Path):
        if source.is_file() and not mirror.is_file():
            problems.append(
                f"{source.relative_to(root)}: no mirror at {mirror.relative_to(root)}"
            )

    expect(root / "README.md", root / "README.ja.md")
    expect(root / "README.ja.md", root / "README.md")

    en, ja = root / "docs" / "en", root / "docs" / "ja"
    for path in sorted(en.rglob("*.md")):
        relative = path.relative_to(en)
        expect(path, ja / relative.with_name(relative.stem + ".ja.md"))
    for path in sorted(ja.rglob("*.ja.md")):
        relative = path.relative_to(ja)
        expect(path, en / relative.with_name(relative.name[: -len(".ja.md")] + ".md"))
    return problems


def retired_names(root: Path, retired: dict[str, str]) -> list[str]:
    problems = []
    for path in searched_files(root):
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            for name, reason in retired.items():
                if name in line:
                    problems.append(
                        f"{path.relative_to(root)}:{number}: retired name {name!r} — {reason}"
                    )
    return problems


def check(root: Path, retired: dict[str, str] | None = None) -> list[str]:
    retired = RETIRED if retired is None else retired
    return broken_links(root) + missing_mirrors(root) + retired_names(root, retired)


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    problems = check(root)
    for problem in problems:
        print(problem)
    if problems:
        print(f"\ncheck-docs: {len(problems)} problem(s)")
        return 1
    print("check-docs: links resolve, mirrors are paired, no retired name in use")
    return 0


if __name__ == "__main__":
    sys.exit(main())
