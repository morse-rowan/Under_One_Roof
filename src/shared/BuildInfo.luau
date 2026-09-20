--!strict
-- Shared, non-secret setup metadata. Keep game rules in engine-independent modules.
return table.freeze({
    name = "Roommate Game",
    version = "visual-sandbox-1",
    -- Switch to "gameplay" to restore the earlier chore/UI prototype.
    mode = "visual-sandbox",
    -- Menu visual study. Draws candidate menu looks over whichever mode is
    -- running; set false to play the apartment with no overlay.
    menuPreview = true,
})
