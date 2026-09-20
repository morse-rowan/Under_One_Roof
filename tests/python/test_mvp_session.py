import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from simlab.engine import Engine
from simlab.mvp_session import MvpSession, baseline
from simlab.mvp_policy import packet
from mvp_simulate import ACTORS, run


class MvpSessionTests(unittest.TestCase):
    def test_private_replies_arrive_before_spending_and_stay_private(self):
        seen = {actor["id"]: [] for actor in ACTORS}
        def policy(actor):
            def choose(prompt):
                obs = json.loads(prompt["messages"][-1]["content"])
                seen[actor].append(obs)
                if obs["decisionMode"] == "communication":
                    if actor == "blue":
                        speech, target = "PRIVATE_REQUEST", "red"
                    elif actor == "red":
                        speech, target = "PRIVATE_REPLY", "blue"
                    else:
                        return {"assessment": "", "choice": None, "message": None}
                    return {"assessment": "PRIVATE_DIAGNOSTIC", "choice": None,
                            "message": {"channel": "private", "target": target, "speech": speech}}
                return {"assessment": "", "choice": 0, "message": None}
            return choose
        with Engine(ROOT, "tools/simlab/mvp_bridge.luau") as engine:
            session = MvpSession(engine, ACTORS, config={"messages": 2})
            session.step({a["id"]: policy(a["id"]) for a in ACTORS})
            blue_action = next(o for o in seen["blue"] if o["decisionMode"] == "action")
            self.assertIn("PRIVATE_REPLY", json.dumps(blue_action))
            self.assertNotIn("PRIVATE_REQUEST", json.dumps(seen["player"]))
            self.assertNotIn("PRIVATE_REPLY", json.dumps(seen["player"]))
            self.assertNotIn("PRIVATE_DIAGNOSTIC", json.dumps(seen))
            self.assertEqual(session.state, session.replay())
            events = session.state["events"]
            messages = [e["id"] for e in events if e["kind"] == "message"]
            actions = [e["id"] for e in events if e["kind"] == "action"]
            self.assertLess(max(messages), min(actions))
            self.assertFalse(any(d["fallback"] for d in session.decisions))

    def test_failure_becomes_labeled_wait_and_does_not_stop_day(self):
        def broken(_prompt):
            return {"choice": 999}
        result = run(days=1, policies={a["id"]: broken for a in ACTORS})
        self.assertEqual(result["state"]["status"], "horizon")
        self.assertTrue(result["replay_verified"])
        self.assertTrue(all(d["fallback"] for d in result["decisions"]))
        self.assertTrue(all(d["action"] == {"kind": "wait"} for d in result["decisions"] if d["mode"] == "action"))

    def test_configurable_setup_and_prompt_memory_limits(self):
        setup = json.loads((ROOT / "experiments/mvp-demo.json").read_text())
        setup["prompt_options"].update(strategy="direct", history_events=2, history_recaps=1)
        result = run(seed=4, days=1, setup=setup)
        self.assertEqual(result["mechanicsVersion"], "mvp-1")
        self.assertEqual(result["state"]["config"]["days"], 1)
        self.assertEqual(set(result["outcomes"]), {"green", "blue", "red"})
        for decision in result["decisions"]:
            obs = json.loads(decision["prompt"]["messages"][-1]["content"])
            self.assertLessEqual(len(obs["events"]), 2)
            self.assertLessEqual(len(obs["recaps"]), 1)
            retained = {e["id"] for e in obs["events"]}
            self.assertTrue(all(set(r["eventIds"]) <= retained for r in obs["recaps"]))
            self.assertEqual(decision["prompt"]["assessment_token_target"], 0)
        obs = result["actor_views"]["blue"]
        empty = json.loads(packet(obs, history_events=0, history_recaps=0)["messages"][-1]["content"])
        self.assertEqual(empty["events"], [])
        self.assertEqual(empty["recaps"], [])
        self.assertIn("outcome", empty)

    def test_group_board_and_clue_prevention_across_stages(self):
        def investigate(prompt):
            obs = json.loads(prompt["messages"][-1]["content"])
            if obs["decisionMode"] == "communication":
                return {"assessment": "", "choice": None,
                        "message": {"channel": "group", "target": None, "speech": "Keep the house clean."}}
            options = obs["candidates"]
            choice = next((i for i, c in enumerate(options) if c["kind"] == "request_cancel"),
                          next((i for i, c in enumerate(options) if c["kind"] == "inspect"), 0))
            return {"assessment": "", "choice": choice, "message": None}
        def persuaded(prompt):
            obs = json.loads(prompt["messages"][-1]["content"])
            if obs["decisionMode"] == "communication":
                return {"assessment": "", "choice": None, "message": None}
            requests = {e["data"]["reference"] for e in obs["events"] if e["kind"] == "cancel_requested"}
            choice = next((i for i, c in enumerate(obs["candidates"])
                           if c["kind"] == "cancel_plan" and c["reference"] in requests), 0)
            return {"assessment": "", "choice": choice, "message": None}
        with Engine(ROOT, "tools/simlab/mvp_bridge.luau") as engine:
            session = MvpSession(engine, list(reversed(ACTORS)), config={
                "messPercent": 100, "leakPercent": 0, "roachPercent": 0,
                "randomInspectionPercent": 0, "pressurePerDay": 0,
            })
            policies = {"player": investigate, "blue": persuaded, "red": persuaded}
            session.step(policies)
            self.assertIn("Keep the house clean.", json.dumps(session.observe("blue")))
            session.step(policies)
            self.assertEqual(session.state["plans"][0]["status"], "cancelled")
            self.assertFalse(session.state["items"])
            self.assertEqual(session.state, session.replay())


if __name__ == "__main__":
    unittest.main()
