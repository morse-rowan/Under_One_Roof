"""Survey hosted NVIDIA models for this project's two jobs, using the account's own key.

    py -3 tools/survey_models.py              # dialogue pass, then JSON-action pass
    py -3 tools/survey_models.py --list       # just what the account can see
    py -3 tools/survey_models.py --only nvidia/nemotron-3-super-120b-a12b

Sequential and capped so it stays well under the account's displayed 40 RPM. Prints no
credential. Latency here is one sample per model from one machine, not a benchmark.
"""

import argparse
import getpass
import json
import os
import time
import urllib.error
import urllib.request

ENDPOINT = "https://integrate.api.nvidia.com/v1"

# Chat-capable general models; embedding, vision, parsing, safety and code models omitted.
CANDIDATES = [
    "nvidia/nemotron-3-super-120b-a12b",
    "nvidia/nemotron-3-ultra-550b-a55b",
    "nvidia/nemotron-3.5-lightning-30b-a3b",
    "nvidia/nemotron-nano-3-30b-a3b",
    "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning",
    "nvidia/llama-3.1-nemotron-ultra-253b-v1",
    "nvidia/llama-3.1-nemotron-51b-instruct",
    "nvidia/nemotron-4-340b-instruct",
    "mistralai/mistral-nemotron",
    "nv-mistralai/mistral-nemo-12b-instruct",
    "writer/palmyra-creative-122b",
    "google/gemma-4-31b-it",
    "moonshotai/kimi-k3",
    "z-ai/glm-5.3-flash",
    "z-ai/glm-5.3",
    "deepseek-ai/deepseek-v4-flash-0731",
    "openai/gpt-oss-20b",
    "mistralai/mistral-large-2-instruct",
    "microsoft/phi-3.5-moe-instruct",
    "meta/muse-glimmer-30b",
]

DIALOGUE_SYSTEM = (
    "You are Green, a roommate sharing a small apartment in a game. Reply in character "
    "with one or two short sentences, at most 160 characters, as plain text with no "
    "quotes, JSON, or narration."
)
DIALOGUE_USER = "Green, you left dishes in the sink for three days. What do you have to say?"

ACTION_SYSTEM = (
    "Choose one action for a roommate simulation. Return only JSON with actor_id, "
    "action_id and speech. Copy actor_id from the observation and choose action_id from "
    "legal_actions. Speech is at most 160 characters."
)
ACTION_OBS = {
    "actor_id": "green",
    "goal": "Keep the peace without doing extra chores",
    "legal_actions": ["offer_dishes", "propose_trade", "refuse", "wait"],
    "visible_events": ["Blue accused Green of leaving dishes for three days."],
}
ACTION_SCHEMA = {
    "type": "object",
    "properties": {
        "actor_id": {"type": "string", "enum": ["green"]},
        "action_id": {"type": "string", "enum": ACTION_OBS["legal_actions"]},
        "speech": {"type": "string", "maxLength": 160},
    },
    "required": ["actor_id", "action_id", "speech"],
    "additionalProperties": False,
}


def post(key, body, timeout):
    request = urllib.request.Request(
        ENDPOINT + "/chat/completions",
        data=json.dumps(body).encode(),
        headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"},
    )
    start = time.monotonic()
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            payload = json.loads(response.read(200000))
        secs = time.monotonic() - start
        choice = payload["choices"][0]
        text = (choice["message"].get("content") or "").strip()
        usage = payload.get("usage") or {}
        return {
            "ok": bool(text),
            "secs": secs,
            "text": text,
            "tokens": usage.get("total_tokens"),
            "finish": choice.get("finish_reason"),
            "note": "" if text else "empty content",
        }
    except urllib.error.HTTPError as error:
        raw = error.read(400).decode("utf-8", "replace").replace(key, "[REDACTED]")
        try:
            decoded = json.loads(raw)
            raw = decoded.get("detail") or decoded.get("title") or raw
        except ValueError:
            pass
        return {
            "ok": False,
            "secs": time.monotonic() - start,
            "text": "",
            "note": "HTTP %d %s" % (error.code, str(raw)[:80]),
        }
    except Exception as error:  # timeouts, malformed payloads, unexpected shapes
        return {
            "ok": False,
            "secs": time.monotonic() - start,
            "text": "",
            "note": type(error).__name__,
        }


def dialogue(key, model, timeout):
    return post(
        key,
        {
            "model": model,
            "messages": [
                {"role": "system", "content": DIALOGUE_SYSTEM},
                {"role": "user", "content": DIALOGUE_USER},
            ],
            "temperature": 1,
            "top_p": 0.95,
            "max_tokens": 160,
            "stream": False,
            "chat_template_kwargs": {"enable_thinking": False},
        },
        timeout,
    )


def action(key, model, timeout):
    result = post(
        key,
        {
            "model": model,
            "messages": [
                {"role": "system", "content": ACTION_SYSTEM},
                {"role": "user", "content": json.dumps(ACTION_OBS)},
            ],
            "temperature": 1,
            "top_p": 0.95,
            "max_tokens": 200,
            "stream": False,
            "chat_template_kwargs": {"enable_thinking": False},
            "response_format": {
                "type": "json_schema",
                "json_schema": {
                    "name": "roommate_action",
                    "strict": True,
                    "schema": ACTION_SCHEMA,
                },
            },
        },
        timeout,
    )
    if result["ok"]:
        try:
            parsed = json.loads(result["text"])
            legal = (
                parsed.get("actor_id") == "green"
                and parsed.get("action_id") in ACTION_OBS["legal_actions"]
                and isinstance(parsed.get("speech"), str)
            )
            result["note"] = "valid" if legal else "parsed but illegal"
            result["ok"] = legal
        except ValueError:
            result["ok"], result["note"] = False, "not JSON"
    return result


def show(label, model, result):
    status = "ok  " if result["ok"] else "FAIL"
    detail = result["text"][:88].replace("\n", " ") if result["ok"] else result["note"]
    print(
        "%-5s %-46s %s %6.2fs %-6s %s"
        % (label, model, status, result["secs"], result.get("tokens") or "-", detail),
        flush=True,
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--only", nargs="*", help="restrict to these model ids")
    parser.add_argument("--timeout", type=float, default=20)
    parser.add_argument("--gap", type=float, default=1.0, help="seconds between calls")
    parser.add_argument("--repeat", type=int, default=1, help="reliability passes per model")
    args = parser.parse_args()

    key = (
        os.environ.get("NVIDIA_API_KEY")
        or getpass.getpass("NVIDIA API key (hidden, not saved): ")
    ).strip()
    if not key:
        raise SystemExit("No key provided; no requests sent.")

    if args.list:
        request = urllib.request.Request(
            ENDPOINT + "/models", headers={"Authorization": "Bearer " + key}
        )
        with urllib.request.urlopen(request, timeout=30) as response:
            for model in sorted(m["id"] for m in json.loads(response.read())["data"]):
                print(model)
        return

    models = args.only or CANDIDATES
    if args.repeat > 1:
        # Reliability matters more than peak latency: Lightning failed every call in one
        # window on 2026-09-19 and answered in 0.78 s in the next.
        print("=== reliability: %d passes per model, both tasks ===" % args.repeat, flush=True)
        for model in models:
            for task, run in (("chat", dialogue), ("json", action)):
                times, wins = [], 0
                for _ in range(args.repeat):
                    result = run(key, model, args.timeout)
                    wins += 1 if result["ok"] else 0
                    times.append(result["secs"])
                    time.sleep(args.gap)
                times.sort()
                print(
                    "%-5s %-46s %d/%d  min %5.2fs  med %5.2fs  max %5.2fs"
                    % (task, model, wins, args.repeat, times[0],
                       times[len(times) // 2], times[-1]),
                    flush=True,
                )
        return

    print("=== dialogue: one in-character line ===", flush=True)
    passed = []
    for model in models:
        result = dialogue(key, model, args.timeout)
        show("chat", model, result)
        if result["ok"]:
            passed.append((model, result))
        time.sleep(args.gap)

    print("\n=== structured action: strict json_schema ===", flush=True)
    for model, _ in passed:
        show("json", model, action(key, model, args.timeout))
        time.sleep(args.gap)

    print("\n%d of %d models answered the dialogue prompt." % (len(passed), len(models)))
    if passed:
        fastest = sorted(passed, key=lambda item: item[1]["secs"])[:5]
        print("fastest:", ", ".join("%s %.2fs" % (m, r["secs"]) for m, r in fastest))


if __name__ == "__main__":
    main()
