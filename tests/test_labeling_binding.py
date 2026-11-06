"""Smoke tests for the Python binding the UI uses. Run: .venv/bin/python -m unittest tests.test_labeling_binding"""
import json
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO))

import mojo.importer  # noqa: E402,F401  (installs the .mojo import hook)
import labeling  # noqa: E402

TASK = str(REPO / "tests/fixtures/12345678.json")


class LabelingBindingTest(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()

    def open(self, split="train", pair=0, side="input"):
        return labeling.Labeling(self.root, TASK, "training", split, pair, side)

    def test_grid_addresses_cover_every_grid_in_order(self):
        self.assertEqual(
            labeling.grid_addresses(TASK),
            [("train", 0, "input"), ("train", 0, "output"),
             ("train", 1, "input"), ("train", 1, "output"),
             ("test", 0, "input"), ("test", 0, "output")],
        )

    def test_label_save_and_reopen(self):
        # train 0 input is [[0, 1], [2, 3]]; every color appears once, so 0 wins the tie.
        g = self.open()
        self.assertEqual((g.rows(), g.cols(), g.cells()), (2, 2, [0, 1, 2, 3]))
        self.assertEqual(g.background(), 0)
        self.assertEqual(g.state(), "unlabeled")

        self.assertEqual(g.propose(0, 1), [1, 2, 3])
        g.add_object([2, 3])
        g.add_object([1])
        self.assertEqual(g.objects(), [[1], [2, 3]])
        self.assertEqual(g.unclaimed(), [])
        self.assertEqual(g.reconstruct(), [0, 1, 2, 3])
        self.assertEqual(g.state(), "complete")
        g.save()

        doc = json.loads((Path(self.root) / "training/12345678/12345678_train0_in.json").read_text())
        self.assertEqual(doc["state"], "complete")
        self.assertEqual(self.open().objects(), [[1], [2, 3]])

    def test_core_errors_become_python_exceptions(self):
        g = self.open()
        g.add_object([1])
        with self.assertRaises(Exception):
            g.add_object([1])
        with self.assertRaises(Exception):
            g.remove_object(5)
        with self.assertRaises(Exception):
            g.set_background(3)

    def test_flag_survives_reopen(self):
        g = self.open("test", 0, "output")
        g.flag("unclear")
        g.save()
        reopened = self.open("test", 0, "output")
        self.assertEqual((reopened.state(), reopened.note()), ("flagged", "unclear"))


if __name__ == "__main__":
    unittest.main()
