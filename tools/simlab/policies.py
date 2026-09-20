"""Actor-local policies and inference. No policy receives the world state."""
import copy
import json
import os
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path

from .storage import atomic, canonical, lock, read


def sequence(value):
    return value if isinstance(value, list) else []


def context(observation, config):
    obs = copy.deepcopy(observation)
    obs["communication_rules"] = config["communication"]
    memory = config["memory"]
    events = sequence(obs["events"])
    if memory["strategy"] == "none":
        kept = []
        obs["actor"]["beliefs"] = {}
        obs["actor"]["relationships"] = {}
        obs["actor"]["knowledge"] = {k: v for k, v in obs["actor"]["knowledge"].items() if k.startswith(obs["actor"]["id"] + ":")}
    else:
        if memory["strategy"] == "important":
            important = {"commitment_breached", "commitment_fulfilled", "disclosed", "mediation_requested"}
            events = sorted(events, key=lambda e: (e["kind"] in important, int(e["id"][1:])))
        kept = events[-memory["events"]:] if memory["events"] else []
        kept.sort(key=lambda e: int(e["id"][1:]))
    obs["events"] = kept
    obs["memory_summary"] = [f"{e['id']}: {e['kind']} by {e['actor']}" for e in kept if e["kind"] != "speech"] if memory["summary"] else []
    while len(canonical(obs)) > memory["context_bytes"] and obs["events"]:
        obs["events"].pop(0)
        visible = {e["id"] for e in obs["events"]}
        obs["memory_summary"] = [s for s in obs["memory_summary"] if s.split(":")[0] in visible]
    if len(canonical(obs)) > memory["context_bytes"]:
        raise ValueError("context_budget_too_small_for_required_state")
    return obs


def next_random(state):
    state["rng"] = state.get("rng", 1) * 16807 % 2147483647
    return state["rng"] / 2147483647


def scripted(obs, name, state):
    state = copy.deepcopy(state)
    actor = obs["actor"]
    actions = obs["candidates"]
    actions = sequence(actions)
    choice = next(i for i, a in enumerate(actions) if a["kind"] == "wait")
    deals = {d["id"]: d for d in sequence(obs["commitments"])}
    if name == "novice":
        choice = min(len(actions) - 1, int(next_random(state) * len(actions)))
    else:
        def score(action):
            kind = action["kind"]
            relation = actor["relationships"].get(action.get("target", ""), 0)
            ally = action.get("target") in actor["allies"]
            generous = name == "cooperative"
            reciprocal = name == "reciprocal"
            selfish = name in {"selfish", "manipulative"}
            reserve = actor["goal"] if selfish else actor["goal"] * (1 - actor["stats"]["generosity"])
            if kind == "wait": return 1
            if kind == "accept":
                deal = deals[action["reference"]]
                trust = actor["relationships"].get(deal["actor"], 0)
                if deal["purpose"] == "quiet" and actor["preference"] == "party" and deal["amount"] < 10: return -1
                return 10 if generous or trust >= 0 else -2
            if kind == "reject": return 2 if actor["relationships"].get(deals[action["reference"]]["actor"], 0) < 0 else -1
            if kind == "fulfill": return 15 if generous or reciprocal else (-1 if actor["cash"] < reserve else 5)
            if kind == "breach": return 3 if selfish else -5
            if kind == "contribute":
                return 9 if generous or (reciprocal and actor["cash"] > reserve) or obs["heat"] >= 60 else -1
            if kind == "offer":
                existing = any(d["actor"] == actor["id"] and d["target"] == action["target"] and d["due"] == obs["day"] for d in deals.values())
                if existing: return -2
                if action["purpose"] == "quiet": return 6 if actor["preference"] == "quiet" else -2
                return 5 if generous or name == "manipulative" or (reciprocal and relation >= 0) else -1
            if kind == "ally": return 4 + (1 if relation > 0 else 0) if generous or reciprocal else 2
            if kind == "leave": return 8 if relation < -20 else -3
            if kind == "disclose":
                already = any(e["kind"] == "disclosed" and e["actor"] == actor["id"] and e["data"].get("fact") == action["fact"] for e in sequence(obs["events"]))
                return -1 if already else (3 if generous or ally else 0)
            if kind == "claim": return 4 if name == "manipulative" else -2
            if kind == "plan":
                mediated = bool(actor.get("mediation")) and actor["mediation"].get("day") == obs["day"]
                accepted_quiet = any(d["purpose"] == "quiet" and d["target"] == actor["id"] and d["status"] in {"accepted", "delivered"} for d in deals.values())
                desired = "quiet" if (generous or reciprocal) and (mediated or accepted_quiet or actor["allies"]) else actor["preference"]
                return 4 if action["value"] == desired and actor["plan"] != desired else -2
            if kind == "mediate": return 2 if actor["preference"] == "quiet" else -2
            if kind == "repair": return 12 if obs["property"] < 60 and not selfish else -2
            if kind == "repay": return 11 if generous or reciprocal else -2
            if kind in {"transfer", "lend"}: return 2 if generous and ally and actor["cash"] > reserve else -2
            return -3
        scores = [(score(a), -i, i) for i, a in enumerate(actions)]
        choice = max(scores)[2]
    state["decisions"] = state.get("decisions", 0) + 1
    return {"choice": choice, "speech": "", "channel": "public"}, state


ACTION_SCHEMA = {"type": "object", "properties": {
    "choice": {"type": "integer", "minimum": 0}, "speech": {"type": "string"},
    "channel": {"type": "string", "enum": ["public", "private"]}},
    "required": ["choice", "speech", "channel"], "additionalProperties": False}


def proposal(response, obs, config):
    if not isinstance(response, dict) or set(response) != {"choice", "speech", "channel"}:
        raise ValueError("Malformed decision")
    index = response["choice"]
    if type(index) is not int or not 0 <= index < len(obs["candidates"]):
        raise ValueError("Invalid candidate index")
    if not isinstance(response["speech"], str) or len(response["speech"].encode()) > config["communication"]["speech_bytes"]:
        raise ValueError("Speech exceeds budget")
    action = obs["candidates"][index]
    if response["channel"] not in {"public", "private"} or (response["channel"] == "private" and (not config["communication"]["private"] or "target" not in action)):
        raise ValueError("Invalid speech channel")
    return {"actor": obs["actor"]["id"], "revision": obs["revision"], "action": action,
            "speech": response["speech"], "channel": response["channel"]}


def fallback(obs):
    return {"choice": next(i for i, a in enumerate(obs["candidates"]) if a["kind"] == "wait"), "speech": "", "channel": "public"}


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def http_failure(exc):
    """Keep bounded provider diagnostics without retaining request credentials."""
    result = {"error": "http_error", "http_status": exc.code}
    try:
        body = exc.read(65537)
        result["raw_response"] = body[:65536].decode("utf-8", errors="replace")
        result["response_truncated"] = len(body) > 65536
    except OSError:
        result["response_read_error"] = True
    result["response_headers"] = {k: v for k, v in (exc.headers or {}).items()
                                  if k.lower() in {"retry-after", "content-type", "x-request-id"}}
    return result


def rate_limit(root, inference):
    from .storage import digest
    directory = Path(root) / "providers" / digest(inference["endpoint"])
    with lock(directory, blocking=True):
        file = directory / "rate.json"
        last = read(file).get("last", 0) if file.exists() else 0
        scheduled = max(time.time(), last + 60 / inference["requests_per_minute"])
        atomic(file, {"last": scheduled})
    delay = max(0, scheduled - time.time())
    if delay:
        time.sleep(delay)


def model_payload(system, data, inference, schema):
    return {"model": inference["model"], "messages": [{"role": "system", "content": system},
            {"role": "user", "content": canonical(data).decode()}],
            "temperature": inference["temperature"], "max_tokens": inference["max_tokens"],
            "stream": False, "chat_template_kwargs": {"enable_thinking": False},
            "response_format": {"type": "json_schema", "json_schema": {"name": "lab_response", "strict": True, "schema": schema}}}


def model_chain(inference):
    """Ordered attempt models: the primary first, then configured fallbacks."""
    return [inference["model"]] + list(inference["fallback_models"])


def preflight(inference, root, destination):
    """Read the compatible model catalog; preserve launch evidence without inference."""
    key = os.environ.get(inference["key_env"], "")
    if not key:
        raise ValueError("NVIDIA credential is unavailable")
    endpoint = inference["endpoint"].removesuffix("/chat/completions") + "/models"
    result = {"checked_at": time.time(), "endpoint": endpoint, "model": inference["model"],
              "chain": model_chain(inference), "configured_requests_per_minute": inference["requests_per_minute"],
              "quota_note": "Local rate cap; account credits and unadvertised provider limits cannot be inferred from the model catalog."}
    rate_limit(root, inference)
    request = urllib.request.Request(endpoint, headers={"Authorization": "Bearer " + key})
    try:
        with urllib.request.build_opener(NoRedirect).open(request, timeout=inference["timeout_seconds"]) as response:
            result["http_status"] = response.status
            raw = response.read(2_000_001)
            if len(raw) > 2_000_000:
                raise ValueError("catalog_too_large")
            result["raw_response"] = raw.decode("utf-8")
            result["advertised_limits"] = {k: v for k, v in response.headers.items() if k.lower().startswith("x-ratelimit-")}
        catalog = {model.get("id") for model in json.loads(raw)["data"]}
        # A catalog entry is availability evidence only; the chain still starts at the primary model.
        result["available_models"] = [model for model in result["chain"] if model in catalog]
        result["missing_models"] = [model for model in result["chain"] if model not in catalog]
        result["available"] = bool(result["available_models"])
        if not result["available"]:
            result["error"] = "model_not_in_catalog"
    except urllib.error.HTTPError as exc:
        result.update(http_failure(exc))
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as exc:
        result["error"] = type(exc).__name__
    result = json.loads(json.dumps(result).replace(key, "[REDACTED]"))
    atomic(destination, result)
    if result.get("error"):
        raise RuntimeError(f"Provider launch check failed; evidence: {destination}")
    return result


def nvidia(payload, inference, root):
    key = os.environ.get(inference["key_env"], "")
    if not key:
        raise RuntimeError(f"Missing credential environment variable {inference['key_env']}")
    rate_limit(root, inference)
    start = time.monotonic()
    result = {"provider": "nvidia", "model": inference["model"], "usage": {}, "error": None}
    request = urllib.request.Request(inference["endpoint"], data=canonical(payload), headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"})
    try:
        with urllib.request.build_opener(NoRedirect).open(request, timeout=inference["timeout_seconds"]) as response:
            raw = response.read(2_000_001)
            result["http_status"] = response.status
        if len(raw) > 2_000_000:
            raise ValueError("response_too_large")
        result["raw_response"] = raw.decode("utf-8")
        body = json.loads(raw)
        result["usage"] = body.get("usage", {})
        result["returned_model"] = body.get("model")
        choice = body["choices"][0]
        if choice.get("finish_reason") != "stop":
            raise ValueError("incomplete_response")
        result["response"] = json.loads(choice["message"]["content"])
    except urllib.error.HTTPError as exc:
        result.update(http_failure(exc))
    except (OSError, ValueError, KeyError, IndexError, TypeError) as exc:
        result["error"] = type(exc).__name__
    result["seconds"] = time.monotonic() - start
    usage = result["usage"]
    result["cost_usd"] = ((usage.get("prompt_tokens", 0) * inference["input_usd_per_million"] + usage.get("completion_tokens", 0) * inference["output_usd_per_million"]) / 1_000_000) if inference["pricing_known"] else None
    return json.loads(json.dumps(result).replace(key, "[REDACTED]"))


# A shared credential cannot be fixed by switching models; further attempts would only waste calls.
FATAL_STATUS = {401, 402, 403}


def attempt_chain(payload, inference, root, max_attempts=None):
    """Bounded Super-to-fallback chain. Every physical attempt is preserved and counted."""
    chain = model_chain(inference)
    budget = inference["max_attempts"] if max_attempts is None else max(1, min(inference["max_attempts"], max_attempts))
    attempts, unavailable = [], set()
    for slot in range(budget):
        model = chain[slot % len(chain)]
        if model in unavailable:
            continue
        attempt = nvidia(dict(payload, model=model), dict(inference, model=model), root)
        attempts.append(attempt)
        if not attempt.get("error"):
            break
        if attempt.get("http_status") == 404:
            unavailable.add(model)
        if attempt.get("http_status") in FATAL_STATUS:
            break
    result = copy.deepcopy(attempts[-1])
    # Failed attempts may still have been billed, so usage and cost are chain totals.
    result["usage"] = {key: sum(a.get("usage", {}).get(key, 0) for a in attempts)
                       for key in {k for a in attempts for k in a.get("usage", {})}}
    result["seconds"] = sum(a.get("seconds", 0) for a in attempts)
    result["cost_usd"] = sum(a["cost_usd"] or 0 for a in attempts) if inference["pricing_known"] else None
    result["attempt_count"] = len(attempts)
    result["attempt_budget"] = budget
    result["models_tried"] = [a["model"] for a in attempts]
    result["attempts"] = [{k: v for k, v in a.items() if k != "raw_response"} for a in attempts]
    if len(set(result["models_tried"])) > 1:
        result["used_fallback_model"] = not result.get("error")
        # One configured price pair is applied to every model in the chain.
        result["cost_assumes_primary_pricing"] = inference["pricing_known"]
    return result


def command_agent(provider, prompt, schema_path, output, cwd, timeout=180, writable=False):
    """Non-mutating evaluator/supervisor calls; experiment execution stays in the coordinator."""
    import shutil
    executable = shutil.which("codex.cmd" if os.name == "nt" else "codex") if provider == "codex" else shutil.which("claude")
    if not executable:
        raise RuntimeError(f"{provider} CLI not installed")
    if provider == "codex":
        args = [executable, "exec", "--sandbox", "workspace-write" if writable else "read-only", "--json", "--output-schema", str(schema_path), "-o", str(output), "-"]
    elif provider == "claude":
        args = [executable, "-p", "--output-format", "json", "--tools", "Read,Edit,Write,Bash" if writable else "", "--strict-mcp-config", "--mcp-config", '{"mcpServers":{}}', "--json-schema", Path(schema_path).read_text(encoding="utf-8")]
    else:
        raise ValueError("Unknown command agent")
    start = time.monotonic()
    # Actor credentials have no role in external command evaluators/supervisors.
    environment = dict(os.environ)
    environment.pop("NVIDIA_API_KEY", None)
    try:
        proc = subprocess.run(args, input=prompt, text=True, encoding="utf-8", capture_output=True, cwd=cwd, timeout=timeout, env=environment)
    except subprocess.TimeoutExpired as exc:
        def decoded(value):
            return value.decode("utf-8", errors="replace") if isinstance(value, bytes) else value or ""
        return {"provider": provider, "error": "timeout", "seconds": time.monotonic() - start,
                "stdout": decoded(exc.stdout), "stderr": decoded(exc.stderr)}
    result = {"provider": provider, "seconds": time.monotonic() - start, "exit_code": proc.returncode, "stdout": proc.stdout, "stderr": proc.stderr}
    if proc.returncode:
        result["error"] = "agent_failed"
    else:
        try:
            if provider == "codex":
                result["response"] = read(output)
                for line in proc.stdout.splitlines():
                    event = json.loads(line)
                    if event.get("type") == "turn.completed":
                        result["usage"] = event.get("usage", {})
            else:
                body = json.loads(proc.stdout)
                result["response"] = body.get("structured_output") or json.loads(body["result"])
                result["usage"] = body.get("usage", {})
        except (OSError, ValueError, KeyError, TypeError, AttributeError):
            result["error"] = "malformed_agent_output"
    return result
