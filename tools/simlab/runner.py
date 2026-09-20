"""Durable run state machine. The journal commit is the transaction boundary."""
import copy
import json
import os
import time
import uuid
from pathlib import Path

from . import config as settings
from .engine import Engine
from . import policies
from .storage import (atomic, checkpoint, create, digest, free_space, journal, load_checkpoint,
                      lock, read, record, source_manifest, verify_source)


def initial_payload(state, config):
    return {"state": state, "policy_state": {a["id"]: {"rng": config["seed"] + i + 1, "decisions": 0} for i, a in enumerate(config["actors"])},
            "usage": {"calls": 0, "tokens": 0, "known_cost_usd": 0, "unpriced_calls": 0, "fallbacks": 0},
            "context_state": {}}


def new_run(root, config, parent=None, initial=None, source=settings.ROOT, run_id=None):
    config = settings.validate(config)
    directory = create(root, config, parent, source, run_id)
    if config["recorded_decisions"]:
        atomic(directory / "recorded.json", read(config["recorded_decisions"]))
    if initial is None:
        with Engine(directory / "source") as engine:
            initial = initial_payload(engine.call("new", config=config, seed=config["seed"])["state"], config)
    checkpoint(directory, 0, initial, {"kind": "initial"})
    atomic(directory / "status.json", {"status": "ready", "reason": "created"})
    return directory


def verify_config(directory):
    saved = read(directory / "config.json")
    if digest(saved) != read(directory / "manifest.json")["config_hash"]:
        raise ValueError("Saved configuration changed; use branch instead")
    return settings.validate(saved)


def budget_reason(payload, config, elapsed, live_next):
    limits = config["limits"]
    if limits["max_seconds"] and elapsed >= limits["max_seconds"]:
        return "time_budget"
    if live_next and limits["max_calls"] and payload["usage"]["calls"] >= limits["max_calls"]:
        return "call_budget"
    if live_next and config["inference"]["pricing_known"] and limits["max_cost_usd"]:
        # Conservative reserve: at most context bytes input tokens plus maximum output tokens.
        inf = config["inference"]
        reserve = ((config["memory"]["context_bytes"] + len(config["prompt"].encode()) + 4096) * inf["input_usd_per_million"] + inf["max_tokens"] * inf["output_usd_per_million"]) / 1_000_000
        if payload["usage"]["known_cost_usd"] + reserve > limits["max_cost_usd"]:
            return "cost_budget"
    return None


def drive(directory, root, live=False, max_steps=None, crash_hook=None, stop_file=None):
    directory = Path(directory).resolve()
    config = verify_config(directory)
    specs = {a["id"]: a for a in config["actors"]}
    if any(a["policy"] == "nemotron" for a in config["actors"]):
        if not live:
            raise ValueError("Nemotron policies require --live")
        if not os.environ.get(config["inference"]["key_env"]):
            raise ValueError("NVIDIA credential is unavailable")
    source = verify_source(directory)
    # Replays use archived rules; continuation also requires the original policy implementation.
    current = source_manifest()
    original = read(directory / "manifest.json")["source_files"]
    code_names = [n for n in original if n.startswith("tools/simlab/") and n.endswith(".py")]
    if any(current.get(n) != original[n] for n in code_names):
        raise ValueError(f"Runner changed. Resume with archived entrypoint: {source / 'tools/simulate.py'}")
    start, count = time.monotonic(), 0
    with lock(directory), Engine(source) as engine:
        journal(directory, repair=True)
        number, payload = load_checkpoint(directory)
        if payload["state"]["status"] == "active" and any(a["policy"] == "nemotron" for a in config["actors"]):
            policies.preflight(config["inference"], root, directory / f"launch-{uuid.uuid4().hex}.json")
        reason = "complete"
        while payload["state"]["status"] == "active":
            if (directory / "STOP").exists() or (stop_file and Path(stop_file).exists()):
                reason = "stop_requested"
                break
            if max_steps is not None and count >= max_steps:
                reason = "step_budget"
                break
            try:
                free_space(directory, config)
            except RuntimeError:
                reason = "disk_pressure"
                break
            state = payload["state"]
            actor_id = state["order"][state["turn"] - 1] if state["phase"] != "settlement" else None
            policy = specs[actor_id]["policy"] if actor_id else None
            reason = budget_reason(payload, config, time.monotonic() - start, policy == "nemotron") or "complete"
            if reason != "complete":
                break
            next_payload = copy.deepcopy(payload)
            operation = {"kind": "advance"}
            if actor_id:
                obs = policies.context(engine.call("observe", state=state, config=config, actor=actor_id)["observation"], config)
                request_id = f"{number + 1:06d}"
                request_path = directory / "decisions" / f"{request_id}.request.json"
                response_path = directory / "decisions" / f"{request_id}.response.json"
                request = {"actor": actor_id, "policy": policy, "observation": obs, "before_hash": digest(payload)}
                if policy == "nemotron":
                    schema = copy.deepcopy(policies.ACTION_SCHEMA)
                    schema["properties"]["choice"]["maximum"] = len(obs["candidates"]) - 1
                    request["payload"] = policies.model_payload(config["prompt"] + " Return a zero-based candidate choice, bounded speech and channel.", obs, config["inference"], schema)
                if request_path.exists() and read(request_path) != request:
                    raise ValueError("Pending request differs from restored state")
                was_pending = request_path.exists()
                atomic(request_path, request)
                if crash_hook:
                    crash_hook("request")
                if response_path.exists():
                    response = read(response_path)
                    if response["request_hash"] != digest(request):
                        raise ValueError("Response/request checksum mismatch")
                    result = response["result"]
                else:
                    if was_pending:
                        record(directory, {"kind": "uncertain_request", "request": request_id, "provider": policy,
                                           "note": "No persisted response; prior remote execution may have happened."})
                    if policy == "nemotron" and was_pending:
                        # A lost response may already have been billed. Do not silently retry.
                        result = {"provider": "nvidia", "error": "uncertain_interrupted_request", "usage": {},
                                  "policy_state": payload["policy_state"][actor_id], "cost_usd": None}
                    elif policy == "nemotron":
                        # Retries and fallbacks are spent from the call budget, never added to it.
                        limit = config["limits"]["max_calls"]
                        remaining = limit - payload["usage"]["calls"] if limit else None
                        result = policies.attempt_chain(request["payload"], config["inference"], root, remaining)
                        result["policy_state"] = payload["policy_state"][actor_id]
                    elif policy == "recorded":
                        recorded = read(directory / "recorded.json")
                        key = f"{actor_id}:{payload['policy_state'][actor_id]['decisions']}"
                        result = {"provider": "recorded", "response": recorded.get(key), "policy_state": copy.deepcopy(payload["policy_state"][actor_id])}
                        result["policy_state"]["decisions"] += 1
                    else:
                        decision, policy_state = policies.scripted(obs, policy, payload["policy_state"][actor_id])
                        result = {"provider": "scripted", "response": decision, "policy_state": policy_state}
                    # This is deliberately before any world-state application.
                    atomic(response_path, {"request_hash": digest(request), "result": result})
                if crash_hook:
                    crash_hook("response")
                fallback_reason = result.get("error")
                try:
                    if fallback_reason:
                        raise ValueError(fallback_reason)
                    proposal = policies.proposal(result.get("response"), obs, config)
                except (ValueError, TypeError, KeyError) as exc:
                    fallback_reason = str(exc)
                    proposal = policies.proposal(policies.fallback(obs), obs, config)
                stepped = engine.call("step", state=state, config=config, proposal=proposal)
                if not stepped["accepted"]:
                    fallback_reason = stepped["reason"]
                    proposal = policies.proposal(policies.fallback(obs), obs, config)
                    stepped = engine.call("step", state=state, config=config, proposal=proposal)
                if not stepped["accepted"]:
                    raise RuntimeError("Even fallback rejected by authority")
                next_payload["state"] = stepped["state"]
                next_payload["policy_state"][actor_id] = result["policy_state"]
                next_payload["context_state"][actor_id] = {"event_ids": [e["id"] for e in obs["events"]], "summary": obs["memory_summary"]}
                usage = next_payload["usage"]
                if policy == "nemotron" and result["provider"] != "intervention":
                    attempts = result.get("attempt_count", 1)
                    usage["calls"] += attempts
                    usage["tokens"] += result.get("usage", {}).get("total_tokens", 0)
                    if result.get("cost_usd") is None:
                        usage["unpriced_calls"] += attempts
                    else:
                        usage["known_cost_usd"] += result["cost_usd"]
                if fallback_reason:
                    usage["fallbacks"] += 1
                operation = {"kind": "decision", "request": request_id, "proposal": proposal,
                             "fallback": fallback_reason, "request_hash": digest(request),
                             "response_hash": digest(read(response_path))}
                if policy == "nemotron":
                    # Which model served this decision; mixed trajectories are availability evidence.
                    operation["model"] = result.get("model") if not fallback_reason else None
                    operation["models_tried"] = result.get("models_tried", [])
            else:
                stepped = engine.call("step", state=state, config=config)
                if not stepped["accepted"]:
                    raise RuntimeError(stepped["reason"])
                next_payload["state"] = stepped["state"]
            if crash_hook:
                crash_hook("applied")
            checkpoint(directory, number + 1, next_payload, operation)
            if crash_hook:
                crash_hook("committed")
            number, payload = number + 1, next_payload
            count += 1
        status = payload["state"]["status"] if payload["state"]["status"] != "active" else "paused"
        atomic(directory / "status.json", {"status": status, "reason": reason, "checkpoint": number})
        from .analysis import summarize
        summary = summarize(directory)
        atomic(directory / "summary.json", summary)
        return {"run": str(directory), "status": status, "reason": reason, "checkpoint": number, "metrics": summary}


def replay(directory):
    directory = Path(directory).resolve()
    config = verify_config(directory)
    source = verify_source(directory)
    rows = [r for r in journal(directory) if r["kind"] == "commit"]
    _, payload = load_checkpoint(directory, 0)
    state = payload["state"]
    with Engine(source) as engine:
        for row in rows[1:]:
            operation = row["operation"]
            if operation["kind"] == "decision":
                decision_dir = directory / "decisions"
                request = read(decision_dir / f"{operation['request']}.request.json")
                response = read(decision_dir / f"{operation['request']}.response.json")
                if digest(request) != operation["request_hash"] or digest(response) != operation["response_hash"]:
                    raise ValueError("Decision artifact checksum mismatch")
            result = engine.call("step", state=state, config=config,
                                 **({"proposal": operation["proposal"]} if operation["kind"] == "decision" else {}))
            _, expected = load_checkpoint(directory, row["number"])
            if not result["accepted"] or digest(result["state"]) != digest(expected["state"]):
                raise ValueError(f"Replay diverged at checkpoint {row['number']}")
            state = result["state"]
    return {"verified": True, "checkpoints": len(rows), "state_hash": digest(state)}


def branch(directory, root, number=None, overrides=None, choice=None):
    directory = Path(directory).resolve()
    original = verify_config(directory)
    config = settings.load(directory / "config.json", overrides)
    # World construction fields cannot be retroactively changed in an existing household.
    if config["seed"] != original["seed"]:
        raise ValueError("Branch seed is inherited; create a new run for a new world seed")
    for a, b in zip(config["actors"], original["actors"]):
        if {k: v for k, v in a.items() if k != "policy"} != {k: v for k, v in b.items() if k != "policy"}:
            raise ValueError("Actor world fields are immutable in branches; policies may change")
    if len(config["actors"]) != len(original["actors"]):
        raise ValueError("Branch actor cast is immutable")
    number, payload = load_checkpoint(directory, number)
    if config["mechanics"] != original["mechanics"]:
        if payload["state"]["phase"] != "social" or payload["state"]["slot"] != 1 or payload["state"]["turn"] != 1:
            raise ValueError("Mechanic switches require a day-start checkpoint")
        if any(d["status"] in {"accepted", "delivered"} for d in policies.sequence(payload["state"]["commitments"])):
            raise ValueError("Cannot disable mechanics with pending commitments")
    ancestry = {"run": str(directory), "run_id": read(directory / "manifest.json")["run_id"],
                "checkpoint": number, "state_hash": digest(payload["state"]),
                "overrides": overrides or [], "choice": choice}
    from .analysis import root_group
    ancestry["root_run_id"] = root_group(directory)
    if payload["state"]["status"] == "horizon" and config["time"]["days"] > payload["state"]["day"]:
        raise ValueError("Extend the horizon by branching before final settlement")
    child = new_run(root, config, ancestry, payload, verify_source(directory))
    if choice is not None:
        state = payload["state"]
        with Engine(child / "source") as engine:
            obs = policies.context(engine.call("observe", state=state, config=config)["observation"], config)
        actor_id = obs["actor"]["id"]
        request = {"actor": actor_id, "policy": next(a["policy"] for a in config["actors"] if a["id"] == actor_id), "observation": obs, "before_hash": digest(payload)}
        if request["policy"] == "nemotron":
            schema = copy.deepcopy(policies.ACTION_SCHEMA)
            schema["properties"]["choice"]["maximum"] = len(obs["candidates"]) - 1
            request["payload"] = policies.model_payload(config["prompt"] + " Return a zero-based candidate choice, bounded speech and channel.", obs, config["inference"], schema)
        decision = {"choice": choice, "speech": "", "channel": "public"}
        policies.proposal(decision, obs, config)
        atomic(child / "decisions/000001.request.json", request)
        atomic(child / "decisions/000001.response.json", {"request_hash": digest(request), "result": {"provider": "intervention", "response": decision, "policy_state": payload["policy_state"][actor_id]}})
    return child
