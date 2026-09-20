import copy
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from simlab.engine import Engine
from simlab.mvp_policy import packet, validate
from simlab.mvp_context import roommate_context
from mvp_simulate import ACTORS, run


class MvpTests(unittest.TestCase):
    def test_color_context_hides_controller_and_cleanup_method(self):
        result = run(13, "household_first", 1)
        obs = result["actor_views"]["blue"]
        obs["actor"]["controller"] = "LLM"
        obs["debug"] = "human player"
        obs["events"] = [
            {"id": 101, "day": 1, "phase": "action_one", "kind": "action",
             "data": {"actor": "player", "action": {"kind": "finish_chore", "reference": 1}}},
            {"id": 102, "day": 1, "phase": "action_one", "kind": "action",
             "data": {"actor": "red", "action": {"kind": "pay_cleanup", "reference": 2, "amount": 5}}},
            {"id": 103, "day": 1, "phase": "action_one", "kind": "phase_closed",
             "data": {"actionsUsed": {"player": 2, "blue": 1}}},
        ]
        original = copy.deepcopy(obs)
        view = roommate_context(obs)
        self.assertEqual(obs, original)
        encoded = json.dumps(view)
        for forbidden in ("player", "npc", "human", "LLM", "controller", "role", "pay_cleanup", "finish_chore", "actionsUsed"):
            self.assertNotIn(forbidden, encoded)
        self.assertEqual([e["kind"] for e in view["events"]], ["requirement_handled"] * 2)
        self.assertEqual(view["events"][0]["data"]["text"], "Green handled outstanding requirement #1.")
        self.assertNotIn("amount", view["events"][1]["data"])
        for forbidden in ("player", "npc", "human", "LLM"):
            self.assertNotIn(forbidden, json.dumps(packet(obs)))
        response = {"assessment": "Ask Green.", "choice": 0,
                    "message": {"channel": "private", "target": "green", "speech": "Can you cover rent?"}}
        # Stop context with fresh candidates, for alias-to-authority routing.
        with Engine(ROOT, "tools/simlab/mvp_bridge.luau") as engine:
            state = engine.call("new", actors=ACTORS, seed=13)["state"]
            fresh = engine.call("observe", state=state, actor="blue")["observation"]
        command, _ = validate(response, fresh)
        self.assertEqual(command["message"]["target"], "player")
        self.assertEqual(response["message"]["target"], "green")

    def test_transport_privacy_and_candidate_contract(self):
        with Engine(ROOT, "tools/simlab/mvp_bridge.luau") as engine:
            state = engine.call("new", actors=ACTORS, seed=13)["state"]
            result = engine.call("message", state=state, actor="blue", revision=state["revision"],
                                 channel="private", target="red", speech="PRIVATE_TEST_SENTINEL")
            self.assertTrue(result["accepted"])
            obs = engine.call("observe", state=result["state"], actor="player")["observation"]
            prompt = packet(obs)
            self.assertNotIn("PRIVATE_TEST_SENTINEL", str(prompt))
            response = {"assessment": "Reserve food money.", "choice": 0,
                        "message": {"channel": "private", "target": "blue", "speech": "Can you cover rent?"}}
            authority, diagnostic = validate(response, obs)
            self.assertNotIn("assessment", authority)
            self.assertEqual(diagnostic["label"], "self_report_not_ground_truth")
            self.assertEqual(authority["action"], {"kind": "wait"})
            for invalid in [dict(response, choice=True), dict(response, choice=-1), dict(response, assessment="x" * 801)]:
                with self.assertRaises(ValueError):
                    validate(invalid, obs)
            action_obs = copy.deepcopy(obs)
            action_obs["phase"] = "action_one"
            with self.assertRaises(ValueError):
                validate(response, action_obs)
            self.assertEqual(packet(obs, "direct")["assessment_token_target"], 0)

    def test_full_day_loop_reproduces_and_has_every_stop(self):
        result = run(13, "protect_cash", 2)
        self.assertEqual(result, run(13, "protect_cash", 2))
        state = result["state"]
        self.assertEqual(state["status"], "horizon")
        stops = {(s["day"], s["phase"]) for s in state["checkpoints"]}
        self.assertTrue({(day, phase) for day in (1, 2) for phase in ("morning", "midday", "night")} <= stops)
        income = [e for e in state["events"] if e["kind"] == "income"]
        self.assertEqual(len(income), 6)
        self.assertEqual(len({(e["day"], e["data"]["actor"]) for e in income}), 6)
        for actor in state["actors"].values():
            self.assertGreaterEqual(actor["cash"], 0)


if __name__ == "__main__":
    unittest.main()
