"""Color-only roommate context. Administrative state is never model input."""
import copy

COLORS = ("blue", "red", "green", "yellow", "purple", "orange", "pink", "cyan")
EVENT_FIELDS = {
    "expense": ("actor", "due", "paid", "debt"),
    "work_forecast": ("actor", "income", "modifier", "tired", "nextExpense", "reason"),
    "party_effects": ("host", "hostBonus", "othersPenalty"),
    "day_started": ("rent", "inspectionDay"),
    "issue_created": ("id", "kind", "creator", "day", "stage", "age", "resolved"),
    "plan_created": ("id", "kind", "actor", "due", "day", "status"),
    "clue": ("plan", "actor", "kind", "due"),
    "cancel_requested": ("actor", "target", "reference"),
    "message": ("actor", "channel", "target", "speech"),
    "issue_aged": ("reference", "age", "heat"),
    "inspection": ("scheduled", "cleanliness", "failed", "heat"),
    "income": ("actor", "amount", "modifier", "expenseDebtPaid"),
    "rent_settled": ("due", "paid", "heat"),
    "party": ("host", "heat"),
}


def aliases(observation):
    ids = observation["actorIds"]
    if len(ids) > len(COLORS):
        raise ValueError("MVP color roster exhausted")
    result = {actor: actor for actor in ids if actor in COLORS}
    available = iter(color for color in COLORS if color not in result.values())
    for actor in ids:
        if actor not in result:
            result[actor] = next(available)
    return result


def roommate_context(observation):
    """Project trusted, audience-filtered Round.observe output using explicit field lists.

    Dialogue remains verbatim: user-authored claims are not rewritten or treated as metadata.
    This removes explicit controller disclosures, not every possible behavioral inference.
    """
    names = aliases(observation)

    def fields(data, allowed):
        result = {key: copy.deepcopy(data[key]) for key in allowed if key in data}
        for key in ("actor", "target", "host", "creator", "id"):
            if key in result and isinstance(result[key], str):
                result[key] = names.get(result[key], result[key])
        return result

    events = []
    for event in observation["events"] if isinstance(observation["events"], list) else []:
        kind, data = event["kind"], event["data"]
        if kind == "action":
            action = data["action"]
            details = fields(data, ("actor",))
            details.update(fields(action, ("reference",)))
            if action["kind"] in {"pay_cleanup", "finish_chore"}:
                kind = "requirement_handled"
                details["text"] = f"{details['actor'].title()} handled outstanding requirement #{action['reference']}."
            elif action["kind"] == "pickup_trash":
                kind = "requirement_progress"
                details["text"] = f"{details['actor'].title()} made progress on outstanding requirement #{action['reference']}."
            else:
                kind = action["kind"]
                details.update(fields(action, ("amount",)))
        elif kind in EVENT_FIELDS:
            details = fields(data, EVENT_FIELDS[kind])
        else:
            # E.g. phase_closed contains controller-specific effort counts.
            continue
        events.append({"id": event["id"], "day": event["day"], "phase": event["phase"],
                       "kind": kind, "data": details})

    result = fields(observation, ("day", "phase", "status", "cleanliness", "heat", "rent", "rentPaid", "goalMet", "messagesRemaining"))
    result["actor"] = fields(observation["actor"], ("id", "cash", "income", "goal", "expense", "debt", "modifier", "tired"))
    result["actorIds"] = [names[actor] for actor in observation["actorIds"]]
    if "outcome" in observation:
        result["outcome"] = fields(observation["outcome"], ("final", "survived", "goalMet", "success"))
    if "decisionMode" in observation:
        result["decisionMode"] = observation["decisionMode"]
    result["events"] = events
    result["items"] = [fields(item, ("id", "kind", "creator", "day", "stage", "age", "resolved"))
                       for item in observation["items"] if isinstance(item, dict)]
    result["plans"] = [fields(plan, ("id", "kind", "actor", "due", "day", "status"))
                       for plan in observation["plans"] if isinstance(plan, dict)]
    # Own legal options remain useful; no other roommate's action budget or controller is exposed.
    result["candidates"] = [fields(action, ("kind", "target", "reference", "amount")) for action in observation["candidates"]]
    result["rules"] = fields(observation["rules"], (
        "days", "rent", "payment", "cleanup", "repair", "eviction", "unpaidHeat", "paidCooling",
        "inspectionHeat", "inspectionCleanliness", "inspectionDay", "randomInspectionPercent",
        "messPercent", "partyPercent", "leakPercent", "roachPercent", "pressurePerDay", "messDirt",
        "ageDirt", "leakHeat", "partyHeat", "tiredPenalty", "hostBonus", "messages", "speechBytes"))
    visible = {event["id"] for event in events}
    result["recaps"] = []
    for recap in observation["recaps"]:
        entry = fields(recap, ("day", "phase", "cleanliness", "heat", "rentPaid"))
        entry["eventIds"] = [event_id for event_id in recap["eventIds"] if event_id in visible]
        entry["outstanding"] = [fields(item, ("id", "kind", "creator", "day", "stage", "age", "resolved"))
                                for item in recap.get("outstanding", [])]
        result["recaps"].append(entry)
    return result
