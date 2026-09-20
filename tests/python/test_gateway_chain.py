"""The bridge's model fallback chain. No network and no inference."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
import nemotron_proxy  # noqa: E402


class BuildChain(unittest.TestCase):
    def test_primary_first_then_fallbacks(self):
        self.assertEqual(nemotron_proxy.build_chain("a", ["b", "c"]), ["a", "b", "c"])

    def test_duplicates_and_blanks_are_dropped(self):
        # A repeated model would spend the budget twice for the same answer.
        self.assertEqual(nemotron_proxy.build_chain("a", ["", "a", "b", "b"]), ["a", "b"])

    def test_no_fallbacks_is_a_single_model(self):
        self.assertEqual(nemotron_proxy.build_chain("a", None), ["a"])
        self.assertEqual(nemotron_proxy.build_chain("a", []), ["a"])


class Chain(unittest.TestCase):
    def setUp(self):
        self.attempts = []
        self.real = nemotron_proxy.decide_once
        self.models = nemotron_proxy.state["models"]
        self.addCleanup(setattr, nemotron_proxy, "decide_once", self.real)
        self.addCleanup(nemotron_proxy.state.__setitem__, "models", self.models)
        nemotron_proxy.state["models"] = ["primary", "backup"]

    def fake(self, results):
        def decide_once(model, system, observation, max_tokens):
            self.attempts.append(model)
            return results[model]
        nemotron_proxy.decide_once = decide_once

    def test_primary_answers_and_nothing_else_is_tried(self):
        self.fake({"primary": (True, {"choice": 0}, {"usage": {}})})
        ok, decision, detail = nemotron_proxy.decide_nemotron("s", {}, 16)
        self.assertTrue(ok)
        self.assertEqual(decision, {"choice": 0})
        self.assertEqual(self.attempts, ["primary"])
        self.assertEqual(detail["served"], "primary")
        self.assertNotIn("fallback", detail)

    def test_unavailable_primary_falls_back(self):
        self.fake({
            "primary": (False, None, {"error": "http 503", "retryable": True}),
            "backup": (True, {"choice": 1}, {}),
        })
        ok, decision, detail = nemotron_proxy.decide_nemotron("s", {}, 16)
        self.assertTrue(ok)
        self.assertEqual(self.attempts, ["primary", "backup"])
        self.assertEqual(detail["served"], "backup")
        self.assertEqual(detail["fallback"], 1)

    def test_a_refusal_is_not_retried_on_another_model(self):
        # 401/403 repeat on every model; retrying only doubles the spend.
        self.fake({"primary": (False, None, {"error": "http 401", "retryable": False})})
        ok, _, detail = nemotron_proxy.decide_nemotron("s", {}, 16)
        self.assertFalse(ok)
        self.assertEqual(self.attempts, ["primary"])
        self.assertEqual(detail["error"], "http 401")

    def test_every_model_failing_reports_the_last_one(self):
        self.fake({
            "primary": (False, None, {"error": "http 503", "retryable": True}),
            "backup": (False, None, {"error": "http 500", "retryable": True}),
        })
        ok, decision, detail = nemotron_proxy.decide_nemotron("s", {}, 16)
        self.assertFalse(ok)
        self.assertIsNone(decision)
        self.assertEqual(self.attempts, ["primary", "backup"])
        self.assertEqual(detail["error"], "http 500")
        self.assertNotIn("retryable", detail)

    def test_retryable_is_never_leaked_to_the_caller(self):
        self.fake({"primary": (True, {"choice": 0}, {"retryable": True})})
        _, _, detail = nemotron_proxy.decide_nemotron("s", {}, 16)
        self.assertNotIn("retryable", detail)


class Retryable(unittest.TestCase):
    def test_availability_codes_are_retryable(self):
        for code in (429, 500, 502, 503, 504):
            self.assertIn(code, nemotron_proxy.RETRYABLE)

    def test_client_errors_are_not(self):
        for code in (400, 401, 403, 404):
            self.assertNotIn(code, nemotron_proxy.RETRYABLE)


if __name__ == "__main__":
    unittest.main()
