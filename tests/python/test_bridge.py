"""The loopback bridge's /decide endpoint: routing, limits and JSON repair.

The bridge is transport. Nothing here asserts anything about a model's judgement,
and no request leaves the machine: the server runs in offline mode.
"""
import json
import sys
import threading
import unittest
from unittest.mock import patch
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


class RepairDecisionTests(unittest.TestCase):
    def test_keeps_a_correct_object(self):
        self.assertEqual(
            bridge.repair_decision({"assessment": "short", "choice": 2, "message": None}),
            {"assessment": "short", "choice": 2, "message": None},
        )

    def test_drops_unknown_keys(self):
        repaired = bridge.repair_decision({"choice": 0, "confidence": 0.9, "notes": "hi"})
        self.assertEqual(set(repaired), {"assessment", "choice", "message"})

    def test_accepts_common_aliases(self):
        self.assertEqual(bridge.repair_decision({"index": 3})["choice"], 3)
        self.assertEqual(bridge.repair_decision({"Choice": "1"})["choice"], 1)
        self.assertEqual(bridge.repair_decision({"rationale": "why"})["assessment"], "why")

    def test_refuses_a_choice_that_is_not_an_index(self):
        for bad in ({"choice": True}, {"choice": "wait"}, {"choice": 1.5}, {"choice": [1]}):
            self.assertIsNone(bridge.repair_decision(bad)["choice"], bad)

    def test_wraps_a_bare_string_message(self):
        message = bridge.repair_decision({"message": "Rent is short."})["message"]
        self.assertEqual(message, {"channel": "group", "target": None, "speech": "Rent is short."})
        self.assertIsNone(bridge.repair_decision({"message": "   "})["message"])

    def test_normalises_message_fields(self):
        message = bridge.repair_decision(
            {"message": {"Channel": "private", "target": "blue", "text": "hi"}}
        )["message"]
        self.assertEqual(message, {"channel": "private", "target": "blue", "speech": "hi"})

    def test_truncates_an_over_long_assessment(self):
        repaired = bridge.repair_decision({"assessment": "x" * 2000, "choice": 0})
        self.assertEqual(len(repaired["assessment"].encode()), bridge.MAX_ASSESSMENT)

    def test_refuses_non_objects(self):
        for bad in (None, [], "text", 7):
            self.assertIsNone(bridge.repair_decision(bad), bad)


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

    def test_authentication_precedes_inference_for_all_routes(self):
        self.httpd.gateway_token = "test-only-token-32-characters-long"
        before = bridge.state["calls"]
        try:
            for path in ("/ask", "/decide", "/health"):
                for token in (None, "wrong"):
                    headers = {} if token is None else {"Authorization": "Bearer " + token}
                    request = urllib.request.Request(self.base + path,
                        data=None if path == "/health" else b"{}", headers=headers)
                    with self.assertRaises(urllib.error.HTTPError) as caught:
                        urllib.request.urlopen(request, timeout=5)
                    self.assertEqual(caught.exception.code, 401)
            self.assertEqual(bridge.state["calls"], before)
            request = urllib.request.Request(self.base + "/decide",
                data=json.dumps({"system": "rules", "observation": self.observation()}).encode(),
                headers={"Authorization": "Bearer " + self.httpd.gateway_token})
            with urllib.request.urlopen(request, timeout=5) as response:
                self.assertTrue(json.loads(response.read())["ok"])
            with bridge.lock:
                bridge.admissions.extend([bridge.time.monotonic()] * 30)
            with self.assertRaises(urllib.error.HTTPError) as caught:
                urllib.request.urlopen(request, timeout=5)
            self.assertEqual(caught.exception.code, 429)
        finally:
            self.httpd.gateway_token = ""
            bridge.admissions.clear()

    def test_network_host_fails_closed_without_token_or_budget(self):
        args = ArgsStub()
        args.host = "0.0.0.0"
        with patch.dict(bridge.os.environ, {"ROOMMATE_GATEWAY_TOKEN": ""}):
            with self.assertRaises(SystemExit):
                bridge.serve(args)
        with patch.dict(bridge.os.environ, {"ROOMMATE_GATEWAY_TOKEN": "x" * 32}):
            with self.assertRaises(SystemExit):
                bridge.serve(args)


if __name__ == "__main__":
    unittest.main()
