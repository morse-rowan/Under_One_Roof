--!strict
-- Presentation derived exclusively from the viewer's server-filtered observation.
local Data = {}

Data.phases = { "morning", "action_one", "work", "midday", "action_two", "night" }
Data.labels = { "Morning", "Action 1", "Work", "Midday", "Action 2", "Night" }
Data.minigames = {
    {
        title = "Parcel desk",
        detail = "Remember delivery labels and rebuild their order.",
        icon = "parcel",
    },
    { title = "Café tickets", detail = "Recall a drink order from a short ticket.", icon = "cup" },
    {
        title = "Sorting station",
        detail = "Repeat the labels on a four-button sorting pad.",
        icon = "sort",
    },
}

function Data.messages(observation: any, channel: string): { any }
    local messages = {}
    local viewer = observation.actor.id
    for _, event in observation.events do
        if event.kind == "message" then
            local entry = event.data
            local visible = if channel == "group"
                then entry.channel == "group"
                else entry.channel == "private"
                    and (
                        (entry.actor == viewer and entry.target == channel)
                        or (entry.actor == channel and entry.target == viewer)
                    )
            if visible then
                table.insert(messages, {
                    id = event.id,
                    actor = entry.actor,
                    mine = entry.actor == viewer,
                    text = entry.speech,
                    day = event.day,
                    phase = event.phase,
                })
            end
        end
    end
    return messages
end

function Data.metrics(o: any): { any }
    local happiness = math.clamp(1 - o.heat / o.rules.eviction, 0, 1)
    return {
        {
            id = "landlord",
            title = "Landlord",
            icon = "house",
            fraction = happiness,
            value = string.format("%d%% happy", math.floor(happiness * 100 + 0.5)),
            state = if happiness <= 0.3
                then "Eviction risk"
                elseif happiness <= 0.65 then "Concerned"
                else "Happy at home",
            tone = if happiness <= 0.3 then "bad" elseif happiness <= 0.65 then "warn" else "good",
            detail = string.format(
                "Eviction pressure: %d / %d. Rent, inspections and parties affect this. Eviction is checked when a phase ends.",
                o.heat,
                o.rules.eviction
            ),
        },
        {
            id = "rent",
            title = "Rent tonight",
            icon = "coin",
            fraction = if o.rent == 0 then 1 else o.rentPaid / o.rent,
            value = string.format("$%d / $%d", o.rentPaid, o.rent),
            state = if o.rentPaid >= o.rent
                then "All covered!"
                else string.format("$%d left to cover", o.rent - o.rentPaid),
            tone = if o.rentPaid >= o.rent then "good" else "warn",
            detail = "Shared rent is due after the night conversation. Contributions are final; the next morning starts a new bill.",
        },
        {
            id = "cleanliness",
            title = "Cleanliness",
            icon = "sparkle",
            fraction = o.cleanliness / 100,
            value = string.format("%d / 100", o.cleanliness),
            state = if o.cleanliness >= o.rules.inspectionCleanliness
                then "Inspection ready"
                else "Needs a tidy-up",
            tone = if o.cleanliness >= o.rules.inspectionCleanliness then "good" else "bad",
            detail = string.format(
                "Inspections need %d cleanliness. Old messes get worse. Cleaning improves this meter, but past landlord complaints remain.",
                o.rules.inspectionCleanliness
            ),
        },
    }
end

return Data
