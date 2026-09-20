--!strict
-- Shared, non-secret setup metadata. Keep game rules in engine-independent modules.
return table.freeze({
    name = "Roommate Game",
    version = "housepad-manual-1",
    -- "mvp"            the locked six-phase round, played in the apartment
    -- "visual-sandbox" movement and palette comparison only
    -- "gameplay"       the earlier chore/UI prototype
    mode = "mvp",
    -- Menu visual study. Draws candidate menu looks over whichever mode is
    -- running. It covers the playable HUD, so it is off while the round is the
    -- default mode; set true to go back to judging the looks.
    menuPreview = false,
    -- Live roommate decisions through the local Nemotron bridge.
    -- Off by default so normal play, Studio sessions and every automated check stay
    -- inference-free: the deterministic policy plays the whole household on its own.
    -- Start `./tools/nemotron_proxy.ps1`, then `/brain on` in the HousePad command
    -- box, or flip `enabled` here to have it on from the first morning.
    brain = table.freeze({
        enabled = false,
        url = "http://127.0.0.1:8787/decide",
        maxCalls = 120,
        deadline = 8,
    }),
})
