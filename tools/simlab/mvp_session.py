"""Offline orchestration with injectable policies; Luau is the rules authority.

Policies receive color-only prompt packets, never administrative state. This
synchronous adapter is not an HTTP server or a hosted model provider.
"""
import copy
import json

from .mvp_policy import packet, scripted, validate

STOPS = {"morning", "midday", "night"}


def baseline(strategy):
    if strategy not in {"protect_cash", "household_first"}:
        raise ValueError("Unknown baseline")
    def choose(prompt):
        return scripted(json.loads(prompt["messages"][-1]["content"]), strategy)
    return choose


class MvpSession:
    def __init__(self, engine, actors, seed=13, config=None, *, communication_waves=2,
                 prompt_options=None):
        if type(communication_waves) is not int or not 1 <= communication_waves <= 10:
            raise ValueError("Expected 1..10 communication waves")
        self.engine = engine
        self.initial = {"actors": copy.deepcopy(actors), "seed": seed, "config": copy.deepcopy(config or {})}
        self.state = engine.call("new", **self.initial)["state"]
        self.communication_waves = communication_waves
        self.prompt_options = copy.deepcopy(prompt_options or {})
        self.journal = []
        self.decisions = []

    def observe(self, actor):
        return self.engine.call("observe", state=self.state, actor=actor)["observation"]

    def execute(self, op, **arguments):
        """Trusted driver mutations; caller does not supply state or revision."""
        arguments = dict(arguments, revision=self.state["revision"])
        result = self.engine.call(op, state=self.state, **arguments)
        if not result["accepted"]:
            raise ValueError(result["reason"])
        self.journal.append({"op": op, "arguments": copy.deepcopy(arguments)})
        self.state = result["state"]
        return result

    def turn(self, actor, mode, policy):
        obs = self.observe(actor)
        obs["decisionMode"] = mode
        if mode == "communication":
            if not obs["messagesRemaining"]:
                return False
            obs["candidates"] = []
        elif not obs["candidates"]:
            return False
        prompt = packet(obs, **self.prompt_options)
        failure = None
        try:
            response = policy(copy.deepcopy(prompt))
            command, diagnostic = validate(response, obs)
        except Exception as error:  # A failed adapter is not an intentional strategy.
            failure = type(error).__name__
            response = {"assessment": "", "choice": None if mode == "communication" else 0, "message": None}
            command, diagnostic = validate(response, obs)
        first_event = len(self.state["events"]) + 1
        revision = self.state["revision"]
        if command["action"] is not None or command["message"] is not None:
            self.execute("decide", actor=actor, **command)
        self.decisions.append({
            "day": obs["day"], "phase": obs["phase"], "actor": actor, "mode": mode,
            "revision": revision, "prompt": prompt, "response": response,
            "action": command["action"], "message": command["message"],
            "private_diagnostic": diagnostic, "adapter_failure": failure,
            "fallback": failure is not None,
            "eventIds": list(range(first_event, len(self.state["events"]) + 1)),
        })
        return command["message"] is not None

    def step(self, policies, work_accuracy=0.5):
        if self.state["status"] != "running":
            raise ValueError("Session already finished")
        if type(work_accuracy) not in (int, float) or not 0 <= work_accuracy <= 1:
            raise ValueError("Invalid simulated work accuracy")
        selected = {actor: policies[actor] for actor in self.state["order"]}
        if any(not callable(policy) for policy in selected.values()):
            raise ValueError("Every actor requires a callable policy")
        order = self.state["order"]
        if self.state["phase"] in STOPS:
            # Immediate delivery, then reversed order gives late speakers an early
            # reply opportunity on the next wave. All spending follows these waves.
            for wave in range(self.communication_waves):
                spoke = False
                for actor in order if wave % 2 == 0 else list(reversed(order)):
                    spoke = self.turn(actor, "communication", selected[actor]) or spoke
                if not spoke:
                    break
        if self.state["phase"] == "work":
            worker = next((a for a in order if self.state["actors"][a]["role"] == "player"), None)
            if worker is None:
                self.execute("work", score=0)
            else:
                challenge = self.engine.call("work_view", state=self.state, actor=worker)["challenge"]
                # Offline fixture with known answers. A playable adapter must send
                # actual recalled answers after its server-controlled preview.
                count = int(len(challenge["sequence"]) * work_accuracy)
                answers = challenge["sequence"][:count]
                self.execute("begin_recall", actor=worker, challengeId=challenge["id"])
                self.execute("submit_work", actor=worker, challengeId=challenge["id"], answers=answers)
        else:
            action_order = sorted(order, key=lambda a: self.state["actors"][a]["role"] != "player")
            for actor in action_order:
                while self.observe(actor)["candidates"]:
                    self.turn(actor, "action", selected[actor])
        self.execute("advance")

    def replay(self):
        """Replay receipts on current code without rerunning policies or paid calls."""
        state = self.engine.call("new", **self.initial)["state"]
        for entry in self.journal:
            result = self.engine.call(entry["op"], state=state, **entry["arguments"])
            if not result["accepted"]:
                raise ValueError("Replay rejected: " + result["reason"])
            state = result["state"]
        return state
