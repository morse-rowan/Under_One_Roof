"""Event-based metrics and evidence-linked reports; no synthetic fun score."""
import json
import statistics
import copy
import random
import time
import uuid
from collections import Counter
from pathlib import Path

from . import policies
from .storage import atomic, digest, journal, load_checkpoint, read, verify_source

METRIC_VERSION = "metrics-2"


def summarize(directory):
    directory = Path(directory)
    number, payload = load_checkpoint(directory)
    state, usage = payload["state"], payload["usage"]
    actors = list(state["actors"].values())
    contributions = [a["contributed"] for a in actors]
    total = sum(contributions)
    gini = sum(abs(a - b) for a in contributions for b in contributions) / (2 * len(actors) * total) if total else None
    rows = [r for r in journal(directory) if r["kind"] == "commit" and r["operation"]["kind"] == "decision"]
    segment_fallbacks = sum(bool(r["operation"].get("fallback")) for r in rows)
    # Mixed-model trajectories are availability evidence, not a single-model quality comparison.
    served = Counter(r["operation"]["model"] for r in rows if r["operation"].get("model"))
    attempted = Counter(model for r in rows for model in r["operation"].get("models_tried", []))
    counts = Counter(r["operation"]["proposal"]["action"]["kind"] for r in rows)
    totals = state["totals"]
    events = policies.sequence(state["events"])
    breach_events = [e for e in events if e["kind"] == "commitment_breached"]
    observed_refusals = 0
    for event in events:
        if event["kind"] == "reject" and any(b["day"] <= event["day"] and event["actor"] in b["audience"] for b in breach_events):
            observed_refusals += 1
    alliances = sum(len(a["allies"]) for a in actors) / 2
    alliance_age = sum(state["day"] - since for a in actors for since in a["allies"].values()) / (2 * alliances) if alliances else None
    recovered = sum(1 for i, e in enumerate(events) if e["kind"] == "bill_unpaid" and any(n["kind"] == "bill_paid" and n["day"] > e["day"] for n in events[i + 1:]))
    response_files = sorted((directory / "decisions").glob("*.response.json"))
    latencies = [read(p)["result"].get("seconds", 0) for p in response_files if read(p)["result"].get("provider") == "nvidia"]
    result = {"metric_version": METRIC_VERSION, "run_id": read(directory / "manifest.json")["run_id"],
              "config_hash": read(directory / "manifest.json")["config_hash"], "checkpoint": number,
              "status": state["status"], "days_observed": state["day"], "survival_censored": state["status"] != "evicted",
              "household_cash": sum(a["cash"] for a in actors), "heat": state["heat"], "property": state["property"],
              "obligations_paid": totals["paid"], "obligations_unpaid": totals["unpaid"],
              "payment_rate": totals["paid"] / (totals["paid"] + totals["unpaid"]) if totals["paid"] + totals["unpaid"] else None,
              "commitments_due": totals["commitments_due"],
              "commitment_fulfillment": totals["fulfilled"] / totals["commitments_due"] if totals["commitments_due"] else None,
              "breaches": totals["breached"], "contribution_gini": gini,
              "goals_met": sum(a["cash"] >= a["goal"] for a in actors),
              "actor_outcomes": {a["id"]: {"cash": a["cash"], "goal": a["goal"], "contributed": a["contributed"], "activity_progress": a["progress"], "stress": a["stress"]} for a in actors},
              "alliances_active": alliances, "mean_alliance_age_days": alliance_age,
              "alliances_formed": totals["alliances_formed"], "disclosures": totals["disclosures"],
              "conflicts": totals["conflicts"], "mediation_requests": totals["mediation"],
              "refusals_after_observed_breach": observed_refusals,
              "unpaid_bills_followed_by_recovery": recovered,
              "action_counts": dict(counts), "distinct_action_kinds": len(counts),
              "dominant_action_share": max(counts.values()) / len(rows) if rows else None,
              "fallback_rate": segment_fallbacks / len(rows) if rows else None,
              "decisions_by_model": dict(served), "attempts_by_model": dict(attempted),
              "segment_live_attempts": sum(attempted.values()),
              "segment_decisions": len(rows), "segment_fallbacks": segment_fallbacks,
              "inherited_fallbacks": usage["fallbacks"] - segment_fallbacks,
              "latency_mean_seconds": statistics.mean(latencies) if latencies else None,
              "usage": usage, "accounting_balanced": totals["initial"] + totals["income"] - totals["expenses"] == sum(a["cash"] for a in actors)}
    actor_segments = {a["id"]: [] for a in actors}
    for row in rows:
        proposal = row["operation"]["proposal"]
        actor_segments[proposal["actor"]].append(proposal["action"]["kind"])
    result["actor_action_counts"] = {actor: dict(Counter(actions)) for actor, actions in actor_segments.items()}
    settled_days = totals["paid"] + totals["unpaid"]
    result["conflicts_per_actor_day"] = totals["conflicts"] / (settled_days * len(actors)) if settled_days else None
    result["free_rider_candidates"] = [a["id"] for a in actors if a["contributed"] == 0 and totals["paid"] > 0]
    result["interpretation_limits"] = "Free-rider candidates are descriptive; reciprocity, information value and exploitation require paired interventions."
    return result


def campaign_report(comparison, destination, hypothesis):
    lines = ["# Simulation comparison", "", hypothesis, "", "Offline scripted evidence unless individual run manifests identify live models. These results do not measure human enjoyment.", "", "| Bill | Memory | Runs | Mean bills paid | Mean goals met | Mean heat |", "|---|---|---:|---:|---:|---:|"]
    for cohort in comparison["cohorts"]:
        rows = [row for group in cohort["seeds"].values() for row in group]
        def mean(key):
            numbers = [row[key] for row in rows if row[key] is not None]
            return f"{statistics.mean(numbers):.3f}" if numbers else "undefined"
        cfg = cohort["configuration"]
        lines.append(f"| {cfg['economy']['bill']} | {cfg['memory']['strategy']} | {len(rows)} | {mean('payment_rate')} | {mean('goals_met')} | {mean('heat')} |")
    lines.extend(["", "## Interpretation limits", "", "Compare matched seeds and inspect uncertainty in comparison.json. Saved branches are related samples. Raw conflict counts depend on how long a household survives; use per-actor-day rates as well. Policies may exploit their authored heuristics, so promising settings need live-model confirmation and human trials.", "", "## Inspectable runs", ""])
    for run in comparison["runs"]:
        metrics = run["metrics"]
        lines.append(f"- {metrics['run_id']}: {metrics['status']}, bills paid={metrics['payment_rate']}, goals={metrics['goals_met']}, fallbacks={metrics['fallback_rate']}; {run['path']}")
    Path(destination).write_text("\n".join(lines) + "\n", encoding="utf-8")


def root_group(directory):
    manifest = read(Path(directory) / "manifest.json")
    parent = manifest.get("parent")
    return parent.get("root_run_id", parent["run_id"]) if parent else manifest["run_id"]


def compare(directories):
    runs = [{"path": str(p), "metrics": summarize(p), "config": read(Path(p) / "config.json"),
             "evidence_versions": {k: v for k, v in read(Path(p) / "manifest.json")["source_files"].items()
                                   if k.startswith("src/shared/Lab") or k.startswith("experiments/rubrics/")},
             "independence_group": root_group(p)} for p in directories]
    keys = ["payment_rate", "commitment_fulfillment", "contribution_gini", "goals_met", "conflicts", "conflicts_per_actor_day", "heat", "distinct_action_kinds", "fallback_rate"]
    paired = []
    if runs:
        baseline = runs[0]
        for candidate in runs[1:]:
            a, b = baseline["config"], candidate["config"]
            paired.append({"baseline": baseline["metrics"]["run_id"], "candidate": candidate["metrics"]["run_id"],
                           "same_seed": a["seed"] == b["seed"],
                           "same_rubric": a["evaluation"] == b["evaluation"] and all(candidate["evidence_versions"].get(k) == v for k, v in baseline["evidence_versions"].items() if k.startswith("experiments/rubrics/")),
                           "same_evidence_versions": baseline["evidence_versions"] == candidate["evidence_versions"],
                           "related_samples": baseline["independence_group"] == candidate["independence_group"],
                           "differences": {k: candidate["metrics"][k] - baseline["metrics"][k] for k in keys if candidate["metrics"][k] is not None and baseline["metrics"][k] is not None}})
    cohorts = {}
    for run in runs:
        treatment = copy.deepcopy(run["config"])
        for key in ("seed", "name", "limits"):
            treatment.pop(key, None)
        for actor in treatment["actors"]:
            actor.pop("id", None)
        treatment["actors"].sort(key=lambda a: json.dumps(a, sort_keys=True))
        key = digest({"configuration": treatment, "evidence_versions": run["evidence_versions"]})
        cohort = cohorts.setdefault(key, {"id": key, "configuration": treatment, "evidence_versions": run["evidence_versions"], "runs": [], "seeds": {}})
        cohort["runs"].append(run["metrics"]["run_id"])
        cohort["seeds"].setdefault(run["config"]["seed"], []).append(run["metrics"])
    groups = list(cohorts.values())
    cohort_pairs = []
    if groups:
        baseline = groups[0]
        for group in groups[1:]:
            frozen_rubric = lambda g: {k: v for k, v in g["evidence_versions"].items() if k.startswith("experiments/rubrics/")}
            if frozen_rubric(baseline) != frozen_rubric(group) or baseline["configuration"]["evaluation"] != group["configuration"]["evaluation"]:
                cohort_pairs.append({"baseline": baseline["id"], "candidate": group["id"], "paired_seeds": [], "estimates": {}, "reason": "Evaluation rubric/configuration differs; freeze it before comparison"})
                continue
            shared = sorted(set(baseline["seeds"]) & set(group["seeds"]))
            estimates = {}
            for metric in keys:
                deltas = []
                for seed in shared:
                    left = [r[metric] for r in baseline["seeds"][seed] if r[metric] is not None]
                    right = [r[metric] for r in group["seeds"][seed] if r[metric] is not None]
                    if left and right:
                        deltas.append(statistics.mean(right) - statistics.mean(left))
                if deltas:
                    rng = random.Random(0)
                    boot = sorted(statistics.mean(rng.choices(deltas, k=len(deltas))) for _ in range(1000)) if len(deltas) > 1 else []
                    estimates[metric] = {"mean_difference": statistics.mean(deltas), "seed_groups": len(deltas), "range": [min(deltas), max(deltas)], "bootstrap_95_percent": [boot[24], boot[974]] if boot else None}
            cohort_pairs.append({"baseline": baseline["id"], "candidate": group["id"], "paired_seeds": shared, "estimates": estimates})
    return {"metric_version": METRIC_VERSION, "run_count": len(runs),
            "independent_lineages": len({r["independence_group"] for r in runs}), "runs": runs, "comparisons": paired,
            "cohorts": groups, "paired_cohort_differences": cohort_pairs,
            "interpretation": "Differences are descriptive. Match scenarios and repeat across held-out seeds before claiming a mechanic caused an improvement. No human enjoyment is measured."}


DIMENSIONS = ["consequential choices", "conflicting interests", "reciprocity and memory", "information value", "recoverable conflict", "player agency", "clarity"]
FINDING_SCHEMA = {"type": "object", "properties": {"findings": {"type": "array", "items": {
    "type": "object", "properties": {**{k: {"type": "string"} for k in ("dimension", "observation", "interpretation", "counterevidence", "next_test")},
    "event_ids": {"type": "array", "items": {"type": "string"}}, "confidence": {"type": "string", "enum": ["low", "medium", "high"]}},
    "required": ["dimension", "observation", "interpretation", "counterevidence", "next_test", "event_ids", "confidence"], "additionalProperties": False}}},
    "required": ["findings"], "additionalProperties": False}
FINDING_SCHEMA["properties"]["findings"]["items"]["properties"]["dimension"] = {"type": "string", "enum": DIMENSIONS}


def validate_findings(value, events):
    if not isinstance(value, dict) or set(value) != {"findings"} or not isinstance(value["findings"], list):
        raise ValueError("Evaluator returned an invalid report")
    known = {e["id"] for e in events}
    fields = set(FINDING_SCHEMA["properties"]["findings"]["items"]["required"])
    for finding in value["findings"]:
        if not isinstance(finding, dict) or set(finding) != fields:
            raise ValueError("Invalid finding fields")
        if not isinstance(finding["event_ids"], list) or not finding["event_ids"] or not set(finding["event_ids"]) <= known:
            raise ValueError("Evaluator cited missing evidence")
        if finding["confidence"] not in {"low", "medium", "high"}:
            raise ValueError("Invalid confidence")
        if any(not isinstance(finding[k], str) for k in fields - {"event_ids"}):
            raise ValueError("Finding text must be strings")
        if finding["dimension"] not in DIMENSIONS or any(not finding[k].strip() for k in fields - {"event_ids"}):
            raise ValueError("Finding has an unknown dimension or empty supporting text")
    return value


def evaluate(directory, root, provider="offline", live=False):
    directory = Path(directory).resolve()
    source = verify_source(directory)
    from .runner import verify_config
    config = verify_config(directory)
    _, payload = load_checkpoint(directory)
    all_events = policies.sequence(payload["state"]["events"])
    # Stratified timeline sample: beginning, evenly spaced middle, end; not just highlights.
    cap = config["evaluation"]["sample_events"]
    events = all_events if len(all_events) <= cap else [all_events[round(i * (len(all_events) - 1) / max(1, cap - 1))] for i in range(cap)]
    rubric = read(source / "experiments/rubrics/strategic-social-v1.json")
    report_dir = directory / "evaluations" / uuid.uuid4().hex
    report_dir.mkdir(parents=True)
    metric_definitions = read(Path(__file__).resolve().parents[2] / "experiments/rubrics/metrics-v2.json")
    metric_source = Path(__file__).read_bytes()
    (report_dir / "metric-source.py").write_bytes(metric_source)
    request = {"rubric": rubric, "metrics": summarize(directory), "events": events,
               "metric_definitions": metric_definitions,
               "metric_source_hash": digest(metric_source.decode("utf-8")),
               "semantics": "Actor goal and disclosed actor:savings values are savings targets, not balances. Cash is reported separately. Branch action/fallback/latency metrics describe only the child segment; world totals and usage include inherited history. Absence of a relationship-change event does not establish that the rules have no trust penalty. Check the archived rules before recommending a missing mechanic. Provider fallback waits are not strategic choices.",
               "perspective": "omniscient analyst; not an actor observation", "sampled": len(events) < len(all_events)}
    atomic(report_dir / "request.json", request)
    atomic(report_dir / "schema.json", FINDING_SCHEMA)
    if provider == "offline":
        result = {"provider": "offline", "response": {"findings": []}, "note": "Deterministic metrics only; no LLM evaluation performed."}
    elif not live:
        raise ValueError("Model evaluation requires --live")
    elif provider == "nvidia":
        inference = dict(config["inference"], max_tokens=config["evaluation"]["max_tokens"])
        if config["evaluation"]["model"]:
            inference["model"] = config["evaluation"]["model"]
        policies.preflight(inference, root, report_dir / "launch.json")
        model = policies.model_payload(rubric["instructions"] + " Return at most three concise findings.", request, inference, FINDING_SCHEMA)
        atomic(report_dir / "model-request.json", model)
        result = policies.nvidia(model, inference, root)
    else:
        result = policies.command_agent(provider, json.dumps(request), report_dir / "schema.json", report_dir / "agent-output.json", source)
    atomic(report_dir / "response.json", result)
    if result.get("error"):
        raise RuntimeError(f"Evaluation failed; preserved at {report_dir}")
    try:
        findings = validate_findings(result["response"], events)
    except ValueError as exc:
        atomic(report_dir / "validation.json", {"valid": False, "reason": str(exc)})
        raise
    atomic(report_dir / "validation.json", {"valid": True, "meaning": "Schema and evidence references checked; interpretation still requires review."})
    report = {"schema": 1, "rubric_hash": digest(rubric), "provider": provider, "metrics": request["metrics"], **findings}
    atomic(report_dir / "report.json", report)
    lines = ["# Simulation evidence report", "", f"Run: {directory.name}", "", "These are simulation observations; player enjoyment requires a human trial.", "", "| Metric | Value |", "|---|---|"]
    for key in ("status", "payment_rate", "commitment_fulfillment", "goals_met", "contribution_gini", "conflicts", "fallback_rate"):
        lines.append(f"| {key} | {report['metrics'][key]} |")
    for finding in findings["findings"]:
        lines.extend(["", f"## {finding['dimension']}", "", f"Observed: {finding['observation']}", "", f"Interpretation ({finding['confidence']} confidence): {finding['interpretation']}", "", f"Evidence: {', '.join(finding['event_ids'])}", "", f"Counterevidence: {finding['counterevidence']}", "", f"Next test: {finding['next_test']}"])
    (report_dir / "report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return {"report": str(report_dir / "report.md"), "data": report}
