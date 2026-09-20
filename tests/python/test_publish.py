"""Offline checks for the Open Cloud publish helper. No network, no key, no upload."""
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
import publish_place  # noqa: E402


class ContentType(unittest.TestCase):
    def test_place_formats(self):
        self.assertEqual(publish_place.content_type("a/b.rbxlx"), "application/xml")
        self.assertEqual(publish_place.content_type("a/b.RBXL"), "application/octet-stream")

    def test_anything_else_is_refused(self):
        # Uploading the wrong file would publish a broken place, not fail loudly.
        for name in ("place.zip", "place.txt", "place"):
            with self.assertRaises(ValueError):
                publish_place.content_type(name)


class VersionUrl(unittest.TestCase):
    def test_published_version_endpoint(self):
        self.assertEqual(
            publish_place.version_url(11, 22),
            "https://apis.roblox.com/universes/v1/11/places/22/versions?versionType=Published")

    def test_ids_must_be_positive_integers(self):
        for universe, place in ((0, 2), (1, 0), (-1, 2), ("1", 2), (1, 2.5), (True, 2)):
            with self.assertRaises(ValueError):
                publish_place.version_url(universe, place)


class Target(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.store = Path(self.directory.name) / "roblox-place.json"
        for name in ("ROBLOX_UNIVERSE_ID", "ROBLOX_PLACE_ID"):
            os.environ.pop(name, None)
        self.addCleanup(self.directory.cleanup)

    def test_nothing_configured_explains_itself(self):
        with self.assertRaises(ValueError) as caught:
            publish_place.load_target(store=self.store)
        self.assertIn("--universe", str(caught.exception))

    def test_saved_target_is_reused(self):
        publish_place.save_target(11, 22, store=self.store)
        self.assertEqual(publish_place.load_target(store=self.store), (11, 22))
        self.assertEqual(json.loads(self.store.read_text())["placeId"], 22)

    def test_arguments_beat_the_saved_target(self):
        publish_place.save_target(11, 22, store=self.store)
        self.assertEqual(publish_place.load_target(33, 44, store=self.store), (33, 44))

    def test_environment_beats_the_saved_target(self):
        publish_place.save_target(11, 22, store=self.store)
        os.environ["ROBLOX_UNIVERSE_ID"] = "55"
        self.addCleanup(os.environ.pop, "ROBLOX_UNIVERSE_ID", None)
        self.assertEqual(publish_place.load_target(store=self.store), (55, 22))

    def test_corrupt_store_is_not_fatal(self):
        self.store.parent.mkdir(parents=True, exist_ok=True)
        self.store.write_text("not json", encoding="utf-8")
        with self.assertRaises(ValueError):
            publish_place.load_target(store=self.store)
        self.assertEqual(publish_place.load_target(11, 22, store=self.store), (11, 22))


class Failures(unittest.TestCase):
    def test_permission_errors_name_the_actual_cause(self):
        self.assertIn("universe-places:write", publish_place.describe_failure(403, ""))
        self.assertIn("expired", publish_place.describe_failure(401, ""))
        self.assertIn("not the universe ID", publish_place.describe_failure(404, ""))

    def test_roblox_own_message_is_kept(self):
        message = publish_place.describe_failure(403, '{"message":"Invalid API key"}')
        self.assertIn("Invalid API key", message)

    def test_unmapped_status_still_reports(self):
        self.assertIn("HTTP 500", publish_place.describe_failure(500, ""))


if __name__ == "__main__":
    unittest.main()
