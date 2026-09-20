"""Persistent bounded/open-ended research campaigns and isolated code experiments."""
import copy
import itertools
import json
import random
import shutil
import subprocess
import time
import uuid
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from . import config as settings
from . import policies
from .analysis import campaign_report, compare, evaluate, summarize
from .runner import drive, new_run
from .storage import atomic, digest, lock, read, source_manifest, snapshot

DEFAULT = {
    "schema": 1, "name": "social-screen", "scenario": "bargaining", "strategy": "sweep",
    "space": {"economy.bill": [30, 45, 60], "memory.strategy": ["none", "recent"]},
    "seeds": [11, 29, 47], "holdout_seeds": [101, 131], "repetitions": 1,
    "rotate": True, "max_runs": 12, "max_seconds": 900, "max_calls": 500,
    "workers": 1, "until_stopped": False, "supervisor": "offline", "evaluator": "offline",
    "allow_code": False, "hypothesis": "Economic pressure and memory change cooperation and goal tradeoffs.",
}


def validate(value):
    if not isinstance(value, dict) or set(value) - set(DEFAULT):
        raise ValueError("Unknown campaign fields")
    result = copy.deepcopy(DEFAULT)
    result.update(value)
    if type(result["schema"]) is not int or result["schema"] != 1 or result["strategy"] not in {"sweep", "random", "adaptive"}:
        raise ValueError("Unsupported campaign schema/strategy")
    for key in ("name", "scenario", "hypothesis"):
        if not isinstance(result[key], str) or not result[key]:
            raise ValueError(f"Campaign {key} must be nonempty text")
    for key in ("rotate", "until_stopped", "allow_code"):
        if type(result[key]) is not bool:
            raise ValueError(f"Campaign {key} must be boolean")
    for key in ("max_runs", "max_seconds", "max_calls", "workers", "repetitions"):
        settings.numeric(result[key], key, 0, 100000)
    if not 1 <= result["workers"] <= 16 or result["repetitions"] < 1:
        raise ValueError("workers must be 1..16; repetitions must be positive")
    for key in ("seeds", "holdout_seeds"):
        if not isinstance(result[key], list) or not result[key]:
            raise ValueError("Supply training and held-out seeds")
        for seed in result[key]:
            settings.numeric(seed, key, 0, 2_147_483_645)
    if set(result["seeds"]) & set(result["holdout_seeds"]):
        raise ValueError("Training and holdout seeds must be disjoint")
    if not isinstance(result["space"], dict) or not result["space"]:
        raise ValueError("Campaign space must map fields to candidate values")
    for key, values in result["space"].items():
        if not isinstance(values, list) or not values:
            raise ValueError("Each search dimension needs values")
        for item in values:
            settings.load(result["scenario"], [f"{key}={json.dumps(item)}"])
    if result["supervisor"] not in {"offline", "codex", "claude", "nvidia"} or result["evaluator"] not in {"offline", "codex", "claude", "nvidia"}:
        raise ValueError("Unsupported research provider")
    return result


PROPOSAL_SCHEMA = {"type": "object", "properties": {
    "hypothesis": {"type": "string"}, "project_goal": {"type": "string"},
    "overrides": {"type": "array", "items": {"type": "string"}},
    "next_test": {"type": "string"}, "code_experiment": {"type": "string"}},
    "required": ["hypothesis", "project_goal", "overrides", "next_test", "code_experiment"], "additionalProperties": False}


def supervisor(directory, campaign, completed, root, live):
    request_dir = directory / "supervisor" / uuid.uuid4().hex
    request_dir.mkdir(parents=True)
    evidence = [summarize(p) for p in completed[-8:]]
    request = {"goal": "Improve consequential, understandable social strategy in a roommate survival game. Preserve scarce actions, automatic income, private observations and explicit commitments.",
               "hypothesis": campaign["hypothesis"], "allowed_space": campaign["space"], "results": evidence,
               "instruction": "Propose a falsifiable next experiment; include failures. Use dotted.path=JSON overrides within the supplied space. New mechanics may fit the project's goals but must be an isolated code_experiment description, never disguised as an unsupported config field. Do not change metrics or adopt changes into the game."}
    atomic(request_dir / "request.json", request)
    atomic(request_dir / "schema.json", PROPOSAL_SCHEMA)
    provider = campaign["supervisor"]
    if not live:
        raise ValueError("Adaptive model supervision requires --live")
    if provider == "nvidia":
        config = settings.load(campaign["scenario"])
        policies.preflight(config["inference"], root, request_dir / "launch.json")
        model = policies.model_payload(request["instruction"], request, config["inference"], PROPOSAL_SCHEMA)
        atomic(request_dir / "model-request.json", model)
        response = policies.nvidia(model, config["inference"], root)
    else:
        response = policies.command_agent(provider, json.dumps(request), request_dir / "schema.json", request_dir / "output.json", settings.ROOT)
    atomic(request_dir / "response.json", response)
    if response.get("error"):
        raise RuntimeError("Supervisor failed; response saved")
    value = response["response"]
    if not isinstance(value, dict) or set(value) != set(PROPOSAL_SCHEMA["required"]):
        raise ValueError("Invalid supervisor proposal")
    if not isinstance(value["overrides"], list) or any(not isinstance(x, str) for x in value["overrides"]):
        raise ValueError("Invalid supervisor overrides")
    for key in set(value) - {"overrides"}:
        if not isinstance(value[key], str):
            raise ValueError("Invalid proposal text")
    for override in value["overrides"]:
        key, _, raw = override.partition("=")
        if key not in campaign["space"] or json.loads(raw) not in campaign["space"][key]:
            raise ValueError("Proposal exceeds declared search space")
    settings.load(campaign["scenario"], value["overrides"])
    atomic(request_dir / "proposal.json", value)
    return value


def candidate(campaign, index, holdout=False):
    keys = sorted(campaign["space"])
    seeds = campaign["holdout_seeds"] if holdout else campaign["seeds"]
    block = len(seeds) * campaign["repetitions"]
    variant = index // block
    seed = seeds[(index // campaign["repetitions"]) % len(seeds)]
    if campaign["strategy"] == "random":
        rng = random.Random(variant)
        values = [rng.choice(campaign["space"][key]) for key in keys]
    else:
        cursor = variant
        values = []
        for key in reversed(keys):
            options = campaign["space"][key]
            values.insert(0, options[cursor % len(options)])
            cursor //= len(options)
    return [f"{key}={json.dumps(value)}" for key, value in zip(keys, values)] + [f"seed={seed}"]


def search(root, campaign_config=None, resume=None, live=False, holdout=False):
    root = Path(root).resolve()
    if resume:
        directory = Path(resume).resolve()
        campaign = validate(read(directory / "config.json"))
    else:
        campaign = validate(campaign_config or {})
        directory = root / "campaigns" / (time.strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:8])
        directory.mkdir(parents=True)
        snapshot(directory / "source")
        atomic(directory / "config.json", campaign)
        atomic(directory / "state.json", {"next": 0, "queue": [], "completed": [], "proposals": [], "code_experiments": [], "role_calls": {"actor": 0, "evaluator": 0, "supervisor": 0}, "holdout": holdout})
    with lock(directory):
        state = read(directory / "state.json")
        start = time.monotonic()
        reason = "run_budget"
        while True:
            # Recompute actor usage from committed evidence, including paused children.
            state["role_calls"]["actor"] = sum(summarize(p)["usage"]["calls"] for p in state["completed"] + state["queue"])
            atomic(directory / "state.json", state)
            if (directory / "STOP").exists():
                reason = "stop_requested"
                break
            if not campaign["until_stopped"]:
                if campaign["max_runs"] and len(state["completed"]) >= campaign["max_runs"]:
                    break
                if campaign["max_seconds"] and time.monotonic() - start >= campaign["max_seconds"]:
                    reason = "time_budget"
                    break
                if campaign["max_calls"] and sum(state["role_calls"].values()) >= campaign["max_calls"]:
                    reason = "call_budget"
                    break
            if not state["queue"]:
                width = campaign["workers"]
                if not campaign["until_stopped"] and campaign["max_runs"]:
                    width = min(width, campaign["max_runs"] - len(state["completed"]))
                for _ in range(width):
                    overrides = candidate(campaign, state["next"], state["holdout"])
                    if campaign["strategy"] == "adaptive" and campaign["supervisor"] != "offline" and state["completed"]:
                        if state["holdout"]:
                            raise ValueError("Adaptive exploration cannot use held-out seeds; freeze candidates first")
                        if not live:
                            raise ValueError("Adaptive model supervision requires --live")
                        reserved = sum(read(Path(p) / "config.json")["limits"]["max_calls"] for p in state["queue"])
                        if not campaign["until_stopped"] and campaign["max_calls"] and sum(state["role_calls"].values()) + reserved >= campaign["max_calls"]:
                            reason = "call_budget"
                            break
                        state["role_calls"]["supervisor"] += 1
                        atomic(directory / "state.json", state)
                        proposal = supervisor(directory, campaign, state["completed"], root, live)
                        state["proposals"].append(proposal)
                        if proposal["code_experiment"]:
                            state["code_experiments"].append({"proposal": proposal, "status": "pending"})
                        overrides = proposal["overrides"] + [o for o in overrides if o.startswith("seed=")]
                    config = settings.load(campaign["scenario"], overrides)
                    if campaign["rotate"]:
                        campaign_seeds = campaign["holdout_seeds"] if state["holdout"] else campaign["seeds"]
                        offset = (state["next"] % (len(campaign_seeds) * campaign["repetitions"])) % len(config["actors"])
                        # Rotate identities through goal/policy roles while preserving unique IDs.
                        ids = [a["id"] for a in config["actors"]]
                        for i, actor in enumerate(config["actors"]):
                            actor["id"] = ids[(i + offset) % len(ids)]
                    if live and not campaign["until_stopped"]:
                        reserved = sum(read(Path(p) / "config.json")["limits"]["max_calls"] for p in state["queue"])
                        slots = width - len(state["queue"])
                        remaining = campaign["max_calls"] - sum(state["role_calls"].values()) - reserved if campaign["max_calls"] else config["limits"]["max_calls"] * slots
                        if remaining < slots:
                            reason = "call_budget"
                            break
                        config["limits"]["max_calls"] = max(1, min(config["limits"]["max_calls"], remaining // slots))
                    if not campaign["until_stopped"] and campaign["max_seconds"]:
                        config["limits"]["max_seconds"] = max(1, min(config["limits"]["max_seconds"], int(campaign["max_seconds"] - (time.monotonic() - start))))
                    run = new_run(root, config, source=directory / "source" if (directory / "source").exists() else settings.ROOT)
                    state["queue"].append(str(run))
                    state["next"] += 1
                    atomic(directory / "state.json", state)
            if not state["queue"]:
                break
            def worker(path):
                source = Path(path) / "source"
                saved = read(Path(path) / "manifest.json")["source_files"]
                current = source_manifest()
                if any(current.get(k) != v for k, v in saved.items() if k.startswith("tools/simlab/") and k.endswith(".py")):
                    # A developer may continue working while a campaign runs. Execute its frozen runner.
                    args = [sys.executable, str(source / "tools/simulate.py"), "--root", str(root), "resume", path, "--campaign-stop", str(directory / "STOP")]
                    if live: args.append("--live")
                    outcome = subprocess.run(args, text=True, encoding="utf-8", capture_output=True)
                    if outcome.returncode:
                        raise RuntimeError(outcome.stderr)
                    return json.loads(outcome.stdout)
                return drive(path, root, live=live, stop_file=directory / "STOP")
            with ThreadPoolExecutor(max_workers=campaign["workers"]) as pool:
                # map order is deterministic even when completion order differs.
                outcomes = list(pool.map(worker, state["queue"]))
            paused = False
            for outcome in outcomes:
                path = outcome["run"]
                if outcome["status"] == "paused":
                    paused = True
                    continue
                if path not in state["completed"]:
                    state["completed"].append(path)
                    state["queue"].remove(path)
                    state["role_calls"]["actor"] = sum(summarize(p)["usage"]["calls"] for p in state["completed"] + state["queue"])
                    if campaign["evaluator"] != "offline":
                        if campaign["until_stopped"] or not campaign["max_calls"] or sum(state["role_calls"].values()) < campaign["max_calls"]:
                            # Reserve before invoking: a crash must not erase a possibly billed job.
                            state["role_calls"]["evaluator"] += 1
                            atomic(directory / "state.json", state)
                            evaluate(path, root, campaign["evaluator"], live)
                atomic(directory / "state.json", state)
            if paused:
                reason = "child_paused"
                break
            comparison = compare(state["completed"])
            atomic(directory / "comparison.json", comparison)
            campaign_report(comparison, directory / "report.md", campaign["hypothesis"])
            if campaign["allow_code"]:
                for entry in state["code_experiments"]:
                    if entry["status"] == "pending":
                        if not campaign["until_stopped"] and campaign["max_calls"] and sum(state["role_calls"].values()) >= campaign["max_calls"]:
                            break
                        state["role_calls"]["supervisor"] += 1
                        entry["status"] = "running"
                        atomic(directory / "state.json", state)
                        entry["result"] = experiment(root, entry["proposal"], campaign["supervisor"] if campaign["supervisor"] in {"codex", "claude"} else "codex", live)
                        entry["status"] = "tested"
                        atomic(directory / "state.json", state)
        atomic(directory / "status.json", {"reason": reason, "completed": len(state["completed"]), "pending": len(state["queue"]), "role_calls": state["role_calls"]})
    return {"campaign": str(directory), "reason": reason, "completed": len(state["completed"]), "pending": len(state["queue"])}


def experiment(root, proposal, provider, live):
    if not live:
        raise ValueError("Code experiments require --live and an explicit campaign allow_code setting or experiment command")
    directory = Path(root).resolve() / "code-experiments" / uuid.uuid4().hex
    worktree = directory / "worktree"
    directory.mkdir(parents=True)
    subprocess.run(["git", "worktree", "add", "--detach", str(worktree), "HEAD"], cwd=settings.ROOT, check=True, capture_output=True)
    # Include the authorized current working sources, including uncommitted lab code.
    for folder in ("src", "tests", "tools", "experiments"):
        shutil.copytree(settings.ROOT / folder, worktree / folder, dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    for name in ("default.project.json", "rokit.toml", "selene.toml", "stylua.toml"):
        shutil.copyfile(settings.ROOT / name, worktree / name)
    baseline = source_manifest(worktree)
    def tracked_tree():
        # Include harness/tests as well as rules: a passing check cannot hide an edited verifier.
        return {p.relative_to(worktree).as_posix(): digest(p.read_bytes().hex())
                for folder in ("src", "tests", "tools", "experiments")
                for p in (worktree / folder).rglob("*") if p.is_file() and "__pycache__" not in p.parts}
    frozen_tree = tracked_tree()
    atomic(directory / "baseline.json", baseline)
    atomic(directory / "proposal.json", proposal)
    schema = {"type": "object", "properties": {"summary": {"type": "string"}}, "required": ["summary"], "additionalProperties": False}
    atomic(directory / "schema.json", schema)
    prompt = ("Implement and test this isolated simulation mechanic experiment. Read the canonical project wiki and original notes; respect accepted decisions while treating brainstorm details as flexible. Do not edit the wiki, parent checkout, credentials, metrics/rubrics, or publish/merge anything. Change only this worktree's shared Lab rules, scenario configurations and focused tests. Preserve observation isolation and explicit-action authority. Run tools/dev.ps1 check -SkipWiki. Explain results and limitations. Proposal:\n" + json.dumps(proposal))
    result = policies.command_agent(provider, prompt, directory / "schema.json", directory / "output.json", worktree, timeout=600, writable=True)
    atomic(directory / "agent.json", result)
    after_tree = tracked_tree()
    changes = sorted(p for p in frozen_tree.keys() | after_tree.keys() if frozen_tree.get(p) != after_tree.get(p))
    allowed = lambda p: (p.startswith("src/shared/Lab") and p.endswith(".luau")) or p.startswith("experiments/scenarios/") or (p.startswith("tests/") and (p.endswith(".spec.luau") or p.endswith(".py")))
    forbidden = [p for p in changes if not allowed(p)]
    atomic(directory / "scope-check.json", {"changes": changes, "forbidden": forbidden})
    if forbidden:
        return {"worktree": str(worktree), "checks_passed": False, "adopted": False,
                "error": "Experiment modified protected harness or evaluation files", "forbidden": forbidden}
    check = subprocess.run(["powershell", "-NoProfile", "-File", str(worktree / "tools/dev.ps1"), "check", "-SkipWiki"], cwd=worktree, text=True, capture_output=True, timeout=300)
    atomic(directory / "checks.json", {"exit_code": check.returncode, "stdout": check.stdout, "stderr": check.stderr})
    return {"worktree": str(worktree), "checks_passed": check.returncode == 0, "adopted": False,
            "source_hash": digest(source_manifest(worktree)), "agent_error": result.get("error")}
