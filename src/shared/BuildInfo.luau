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
})
