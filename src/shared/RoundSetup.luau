--!strict
-- Playable-MVP household fixture. Engine-independent so Lune tests and the Roblox
-- server read exactly the same numbers. Everything here is a tuning value under
-- "Remains adjustable" in the mechanics contract, not an accepted balance.
local Setup = {}

Setup.version = "mvp-playable-1"

-- Actor IDs are colors on purpose: the color-only projection then needs no aliasing,
-- and the beans in the apartment carry the same three identities.
Setup.player = "blue"
Setup.actors = {
    { id = "blue", role = "player", cash = 20, income = 15, goal = 40, expense = 5 },
    { id = "green", role = "npc", cash = 12, income = 12, goal = 25, expense = 5 },
    { id = "red", role = "npc", cash = 15, income = 14, goal = 30, expense = 5 },
}

-- Overrides applied on top of `MvpRound.defaults`. Empty means "use the contract defaults".
Setup.rules = {}

-- The bean already standing in the scene that each NPC controls.
Setup.beans = { green = "Green", red = "Red" }
Setup.colors = {
    blue = { 91, 157, 224 },
    green = { 85, 166, 121 },
    red = { 223, 102, 88 },
}

Setup.labels = {
    morning = "Morning plan",
    action_one = "Action window",
    work = "Work shift",
    midday = "Midday stop",
    action_two = "Action window",
    night = "Night stop",
}

-- The live HousePad build advances only on explicit input. Work minigames are
-- deferred; HousepadFlow pays base wages when the player leaves the work screen.
Setup.manualPhases = true
Setup.minigamesEnabled = false

return Setup
