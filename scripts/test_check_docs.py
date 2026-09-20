#!/usr/bin/env python3
"""Tests for check_docs.py.

A check that has never failed proves nothing, so every rule is shown failing on
a fixture tree before the real tree is trusted to pass it.
"""

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import check_docs  # noqa: E402


def write(root: Path, relative: str, text: str = "") -> None:
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


class CheckDocsTests(unittest.TestCase):
    def setUp(self):
        self._dir = tempfile.TemporaryDirectory()
        self.root = Path(self._dir.name)
        # A clean, fully paired tree.
        write(self.root, "README.md", "[guide](docs/en/guide.md) [site](https://example.com)")
        write(self.root, "README.ja.md", "[guide](docs/ja/guide.ja.md) [top](#top)")
        write(self.root, "docs/en/guide.md", "[back](../../README.md)")
        write(self.root, "docs/ja/guide.ja.md", "[back](../../README.ja.md)")
        write(self.root, "Sources/App/Thing.swift", "let meter = 1\n")

    def tearDown(self):
        self._dir.cleanup()

    def test_clean_tree_has_no_problems(self):
        self.assertEqual(check_docs.check(self.root, retired={}), [])

    def test_broken_relative_link_is_reported(self):
        write(self.root, "docs/en/guide.md", "[gone](missing.md)")
        problems = check_docs.check(self.root, retired={})
        self.assertEqual(len(problems), 1)
        self.assertIn("docs/en/guide.md", problems[0])
        self.assertIn("missing.md", problems[0])

    def test_link_with_anchor_checks_only_the_file(self):
        write(self.root, "docs/en/guide.md", "[back](../../README.md#install)")
        self.assertEqual(check_docs.check(self.root, retired={}), [])

    def test_english_doc_without_japanese_mirror_is_reported(self):
        write(self.root, "docs/en/adr/0001-thing.md")
        problems = check_docs.check(self.root, retired={})
        self.assertEqual(len(problems), 1)
        self.assertIn("docs/ja/adr/0001-thing.ja.md", problems[0])

    def test_japanese_doc_without_english_mirror_is_reported(self):
        write(self.root, "docs/ja/adr/0001-thing.ja.md")
        problems = check_docs.check(self.root, retired={})
        self.assertEqual(len(problems), 1)
        self.assertIn("docs/en/adr/0001-thing.md", problems[0])

    def test_readme_without_mirror_is_reported(self):
        (self.root / "README.ja.md").unlink()
        problems = check_docs.check(self.root, retired={})
        # Two separate findings: the Japanese guide's link back to it is now
        # broken, and README.md has lost its mirror.
        self.assertEqual(len(problems), 2)
        self.assertTrue(any("docs/ja/guide.ja.md: broken link" in p for p in problems))
        self.assertTrue(any("README.md: no mirror at README.ja.md" in p for p in problems))

    def test_retired_name_is_reported_with_its_reason_and_line(self):
        write(self.root, "Sources/App/Thing.swift", "let a = 1\nlet oldMeter = 2\n")
        problems = check_docs.check(self.root, retired={"oldMeter": "withdrawn in ADR-0009"})
        self.assertEqual(len(problems), 1)
        self.assertIn("Sources/App/Thing.swift:2", problems[0])
        self.assertIn("withdrawn in ADR-0009", problems[0])

    def test_struck_through_retired_name_is_an_annotation_not_a_use(self):
        write(self.root, "docs/en/guide.md", "- ~~`oldMeter` draws the graph~~ (withdrawn 2026-10-01, see ADR-0009)")
        write(self.root, "docs/ja/guide.ja.md", "- ~~`oldMeter` がグラフを描く~~（2026-10-01 撤回、ADR-0009）")
        self.assertEqual(check_docs.check(self.root, retired={"oldMeter": "withdrawn"}), [])

    def test_retired_name_outside_the_strike_through_is_still_reported(self):
        write(self.root, "docs/en/guide.md", "- ~~old text~~ but `oldMeter` is still described here")
        write(self.root, "docs/ja/guide.ja.md", "")
        problems = check_docs.check(self.root, retired={"oldMeter": "withdrawn"})
        self.assertEqual(len(problems), 1)
        self.assertIn("docs/en/guide.md:1", problems[0])

    def test_retired_name_in_the_makefile_is_reported(self):
        # BREW_DESC becomes the cask description, which a user reads.
        write(self.root, "Makefile", "BREW_DESC := Meter with oldMeter graph\n")
        problems = check_docs.check(self.root, retired={"oldMeter": "withdrawn"})
        self.assertEqual(len(problems), 1)
        self.assertIn("Makefile:1", problems[0])

    def test_identifier_named_in_one_language_only_is_reported(self):
        write(self.root, "README.md", "Run `make build-app`, then set `CODESIGN_IDENTITY`.")
        write(self.root, "README.ja.md", "`make build-app` を実行します。")
        problems = check_docs.check(self.root, retired={})
        self.assertEqual(len(problems), 1)
        self.assertIn("README.ja.md: lacks `CODESIGN_IDENTITY`", problems[0])

    def test_identifier_missing_from_english_is_reported_too(self):
        write(self.root, "docs/en/guide.md", "Nothing here.")
        write(self.root, "docs/ja/guide.ja.md", "`--verbose` を付けます。")
        problems = check_docs.check(self.root, retired={})
        self.assertEqual(len(problems), 1)
        self.assertIn("docs/en/guide.md: lacks `--verbose`", problems[0])

    def test_only_language_invariant_shapes_are_compared(self):
        # File names, placeholders and prose in backticks differ legitimately.
        write(self.root, "README.md", "See `dist/NetMeter.app`, `<your-path>` and `the panel`.")
        write(self.root, "README.ja.md", "`dist/NetMeter.app` と `<あなたのパス>` と `パネル` を参照。")
        self.assertEqual(check_docs.check(self.root, retired={}), [])

    def test_identifiers_inside_code_fences_are_not_compared(self):
        write(self.root, "README.md", "```bash\nmake only_in_english\n```\n")
        write(self.root, "README.ja.md", "```bash\nmake other_thing\n```\n")
        self.assertEqual(check_docs.check(self.root, retired={}), [])

    def test_identifier_shapes(self):
        text = "`--flag` `make build-app` `snake_case` `NET_RT_IFLIST2` `[ui].unit` `CamelCase` `en0` `make`"
        self.assertEqual(
            check_docs.identifiers(text),
            {"--flag", "make build-app", "snake_case", "NET_RT_IFLIST2", "[ui].unit"},
        )

    def test_build_output_is_not_searched(self):
        write(self.root, ".build/checkouts/dep/README.md", "[gone](missing.md)")
        self.assertEqual(check_docs.check(self.root, retired={}), [])


if __name__ == "__main__":
    unittest.main()
