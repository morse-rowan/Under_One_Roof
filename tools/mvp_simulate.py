"""Run configurable MVP setups offline using the reusable Luau authority."""
import argparse
import copy
import json
from pathlib import Path

from simlab.engine import Engine
from simlab.mvp_context import roommate_context
from simlab.mvp_session import MvpSession, baseline

ROOT = Path(__file__).resolve().parents[1]
ACTORS = [
    {"id": "player", "role": "player", "cash": 20, "income": 15, "goal": 40, "expense": 5},
    {"id": "blue", "role": "npc", "cash": 10, "income": 10, "goal": 25, "expense": 5},
    {"id": "red", "role": "npc", "cash": 15, "income": 15, "goal": 30, "expense": 5},
]


def run(seed=13, strategy="protect_cash", days=None, *, setup=None, policies=None):
    setup = copy.deepcopy(setup or {})
    unknown = set(setup) - {"actors", "config", "policies", "work_accuracy", "communication_waves", "prompt_options"}
    if unknown:
        raise ValueError("Unknown setup fields: " + ", ".join(sorted(unknown)))
    config = setup.get("config", {})
    if days is not None:
        config["days"] = days
    actors = setup.get("actors", ACTORS)
    configured = setup.get("policies", {})
    if set(configured) - {actor["id"] for actor in actors}:
        raise ValueError("Policy references an unknown actor")
    adapters = policies if policies is not None else {
        actor["id"]: baseline(configured.get(actor["id"], strategy)) for actor in actors
    }
    with Engine(ROOT, "tools/simlab/mvp_bridge.luau") as engine:
        session = MvpSession(engine, actors, seed, config,
                             communication_waves=setup.get("communication_waves", 2),
                             prompt_options=setup.get("prompt_options"))
        while session.state["status"] == "running":
            session.step(adapters, setup.get("work_accuracy", 0.5))
        views = {actor: session.observe(actor) for actor in session.state["order"]}
        safe_views = {roommate_context(view)["actor"]["id"]: roommate_context(view) for view in views.values()}
        if session.replay() != session.state:
            raise RuntimeError("MVP replay diverged")
    return {"schema": "mvp-offline-3", "mechanicsVersion": session.state["mechanicsVersion"],
            "seed": seed, "strategy": strategy, "setup": setup, "initial": session.initial,
            "state": session.state, "decisions": session.decisions, "journal": session.journal,
            "actor_views": views, "roommate_views": safe_views,
            "outcomes": {actor: view["outcome"] for actor, view in views.items()},
            "replay_verified": True,
            "sample_prompt": session.decisions[0]["prompt"] if session.decisions else None}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed", type=int, default=13)
    parser.add_argument("--days", type=int)
    parser.add_argument("--setup", type=Path, help="JSON actor/economy/rules/policy/prompt overrides")
    parser.add_argument("--strategy", choices=["protect_cash", "household_first"], default="protect_cash")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Output already exists; choose a new artifact path")
    setup = json.loads(args.setup.read_text(encoding="utf-8")) if args.setup else None
    result = run(args.seed, args.strategy, args.days, setup=setup)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x", encoding="utf-8") as stream:
        json.dump(result, stream, indent=2, ensure_ascii=False, allow_nan=False)
    state = result["state"]
    print(json.dumps({"output": str(args.output), "status": state["status"], "day": state["day"],
                      "heat": state["heat"], "decisions": len(result["decisions"]),
                      "outcomes": result["outcomes"], "replay_verified": result["replay_verified"]}))


if __name__ == "__main__":
    main()
