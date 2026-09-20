--!strict
-- Playable household fixture. Engine-independent so Lune tests and the Roblox
-- server read exactly the same numbers. Everything here is a tuning value under
-- "Remains adjustable" in the mechanics contract, not an accepted balance.
local Setup = {}

Setup.version = "mvp-endless-1"

-- Actor IDs are colors on purpose: the color-only projection then needs no aliasing,
-- and the beans in the apartment carry the same identities. The player picks one of
-- the colors below; the roommate colors are fixed so no ID ever collides.
Setup.playerColors = {
    { id = "blue", rgb = { 91, 157, 224 } },
    { id = "teal", rgb = { 76, 173, 168 } },
    { id = "coral", rgb = { 232, 124, 106 } },
    { id = "plum", rgb = { 158, 116, 190 } },
    { id = "mint", rgb = { 124, 194, 140 } },
    { id = "sand", rgb = { 219, 178, 96 } },
}
Setup.defaultColor = "blue"

-- Four roommates, deliberately without written personalities: they differ in money
-- and in which of RoundPolicy's two attitudes they use, and nothing else.
Setup.npcs = {
    { id = "green", rgb = { 85, 166, 121 }, cash = 12, income = 12, goal = 25, expense = 5 },
    { id = "red", rgb = { 223, 102, 88 }, cash = 15, income = 14, goal = 30, expense = 5 },
    { id = "amber", rgb = { 226, 165, 74 }, cash = 10, income = 13, goal = 20, expense = 5 },
    { id = "violet", rgb = { 163, 126, 208 }, cash = 18, income = 11, goal = 35, expense = 5 },
}

Setup.player = Setup.defaultColor
Setup.playerStats = { cash = 20, income = 15, goal = 40, expense = 5 }

-- The bean already standing in the scene that each roommate controls.
Setup.beans = { green = "Green", red = "Red", amber = "Amber", violet = "Violet" }

function Setup.isPlayerColor(color: any): boolean
    for _, choice in Setup.playerColors do
        if choice.id == color then
            return true
        end
    end
    return false
end

function Setup.rgb(id: string): { number }
    for _, choice in Setup.playerColors do
        if choice.id == id then
            return choice.rgb
        end
    end
    for _, npc in Setup.npcs do
        if npc.id == id then
            return npc.rgb
        end
    end
    return { 130, 126, 118 }
end

Setup.colors = {}
for _, choice in Setup.playerColors do
    Setup.colors[choice.id] = choice.rgb
end
for _, npc in Setup.npcs do
    Setup.colors[npc.id] = npc.rgb
end

-- The household for one run. The player's color only changes their own identity;
-- the roommates and their numbers stay the same, so runs stay comparable.
function Setup.household(color: string?): { any }
    local chosen = if color and Setup.isPlayerColor(color) then color else Setup.defaultColor
    local actors = {
        {
            id = chosen,
            role = "player",
            cash = Setup.playerStats.cash,
            income = Setup.playerStats.income,
            goal = Setup.playerStats.goal,
            expense = Setup.playerStats.expense,
        },
    }
    for _, npc in Setup.npcs do
        table.insert(actors, {
            id = npc.id,
            role = "npc",
            cash = npc.cash,
            income = npc.income,
            goal = npc.goal,
            expense = npc.expense,
        })
    end
    return actors
end

Setup.actors = Setup.household(Setup.defaultColor)

-- Overrides applied on top of `MvpRound.defaults`.
-- The playable game has no horizon: it runs until eviction and scores the days
-- survived. Rent is a three-day bill, settled on the night the cycle closes, with
-- the scheduled inspection landing on that same afternoon.
Setup.rules = {
    days = 0,
    rentEvery = 3,
    rent = 60,
    inspectionEvery = 3,
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
