"""The loopback bridge's /decide endpoint: routing, limits and JSON repair.

The bridge is transport. Nothing here asserts anything about a model's judgement,
and no request leaves the machine: the server runs in offline mode.
"""
import json
import sys
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import nemotron_proxy as bridge


class ArgsStub:
    offline = True
    port = 8791
    max_calls = 0
    model = bridge.MODEL


class ExtractJsonTests(unittest.TestCase):
    def test_accepts_bare_object(self):
        self.assertEqual(bridge.extract_json('{"choice": 0}'), {"choice": 0})

    def test_strips_fences_and_prose(self):
        self.assertEqual(bridge.extract_json('```json\n{"choice": 1}\n```'), {"choice": 1})
        self.assertEqual(bridge.extract_json('Here you go: {"choice": 2}.'), {"choice": 2})

    def test_refuses_non_objects(self):
        for bad in ("", "no object", "[1, 2]", "{not json}", '"a string"'):
            self.assertIsNone(bridge.extract_json(bad), bad)


class OfflineDecisionTests(unittest.TestCase):
    def test_action_takes_the_first_candidate(self):
        # `MvpRound` always offers `wait` first, so index 0 is the inert choice.
        self.assertEqual(bridge.offline_decision({"decisionMode": "action"})["choice"], 0)

    def test_communication_stays_silent(self):
        decision = bridge.offline_decision({"decisionMode": "communication"})
        self.assertIsNone(decision["choice"])
        self.assertIsNone(decision["message"])

    def test_labels_itself_as_a_stub(self):
        self.assertIn("offline", bridge.offline_decision({})["assessment"])


class DecideEndpointTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.httpd = bridge.serve(ArgsStub())
        cls.thread = threading.Thread(target=cls.httpd.serve_forever, daemon=True)
        cls.thread.start()
        cls.base = "http://%s:%d" % (bridge.HOST, ArgsStub.port)

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()

    def post(self, path, payload):
        request = urllib.request.Request(
            self.base + path, data=payload, headers={"Content-Type": "application/json"}
        )
        with urllib.request.urlopen(request, timeout=5) as response:
            return json.loads(response.read())

    def observation(self, mode="action"):
        return {
            "decisionMode": mode,
            "actor": {"id": "green", "cash": 10},
            "candidates": [{"kind": "wait"}],
        }

    def test_returns_a_decision_object(self):
        answer = self.post(
            "/decide",
            json.dumps({"system": "rules", "observation": self.observation()}).encode(),
        )
        self.assertTrue(answer["ok"])
        self.assertEqual(answer["decision"]["choice"], 0)
        self.assertIn("seconds", answer)

    def test_rejects_malformed_requests(self):
        for bad in (
            b'{"observation": {"a": 1}}',
            b'{"system": "", "observation": {}}',
            b'{"system": "s", "observation": 7}',
            b'{"system": "s", "observation": {}, "maxTokens": -5}',
            b"not json",
        ):
            with self.assertRaises(urllib.error.HTTPError) as caught:
                self.post("/decide", bad)
            self.assertEqual(caught.exception.code, 400, bad)

    def test_rejects_oversized_bodies(self):
        payload = json.dumps(
            {"system": "s", "observation": {"pad": "x" * (bridge.MAX_DECIDE_BODY + 1)}}
        ).encode()
        with self.assertRaises(urllib.error.HTTPError) as caught:
            self.post("/decide", payload)
        self.assertEqual(caught.exception.code, 413)

    def test_unknown_paths_are_refused(self):
        with self.assertRaises(urllib.error.HTTPError) as caught:
            self.post("/anything", b"{}")
        self.assertEqual(caught.exception.code, 404)

    def test_ask_still_works_alongside_decide(self):
        answer = self.post(
            "/ask", json.dumps({"prompt": "Whose turn is the sink?", "speaker": "Green"}).encode()
        )
        self.assertTrue(answer["ok"])
        self.assertIn("Green hears", answer["text"])


if __name__ == "__main__":
    unittest.main()
