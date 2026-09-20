--!strict
-- Shared, non-secret setup metadata. Keep game rules in engine-independent modules.
return table.freeze({
    name = "Under One Roof",
    version = "housepad-manual-1",
    -- "mvp"            the locked six-phase round, played in the apartment
    -- "visual-sandbox" movement and palette comparison only
    -- "gameplay"       the earlier chore/UI prototype
    mode = "mvp",
    -- The Nemotron sanity bubble that floats over Green in Studio. It is a
    -- connectivity probe, not part of the round, and it reads as a stray debug
    -- label during a demo. Set true to get the typed-prompt check back.
    sanityBubble = false,
    -- Menu visual study. Draws candidate menu looks over whichever mode is
    -- running. It covers the playable HUD, so it is off while the round is the
    -- default mode; set true to go back to judging the looks.
    menuPreview = false,
    -- Roommates walk the apartment during the action windows and carry out their
    -- choice where it happens, instead of standing still until Continue is pressed.
    -- Deterministic and independent of `brain`. Set false to put the four beans back
    -- on their fixed tiles if a playtest finds the movement wrong.
    movingRoommates = true,
    -- Live roommate decisions through the local Nemotron bridge.
    -- On from the first morning, so a session is live without anyone remembering a
    -- command. Start `./tools/nemotron_proxy.ps1` first; with no bridge reachable
    -- each turn fails fast and the deterministic policy takes it instead, so play
    -- still works with no key, no network and no inference. `/brain off` in the
    -- HousePad command box forces the deterministic household for a whole run.
    -- Automated checks are unaffected: they pass their own adapter, never this.
    brain = table.freeze({
        enabled = true,
        maxCalls = 120,
        deadline = 8,
    }),
})
