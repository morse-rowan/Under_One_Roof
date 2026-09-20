--!strict
-- Candidate menu looks for the visual study. Plain data only: colors are RGB
-- triples and fonts are keys resolved by `src/client/MenuKit.luau`, so this file
-- stays engine-independent and testable. Nothing here is an accepted design.
local Styles = {}

Styles.order = { "tablet", "laptop", "arcade", "paper", "phone", "board" }

-- Shared roommate identity colors, matching the sandbox beans.
Styles.identity = {
    blue = { 91, 157, 224 },
    green = { 85, 166, 121 },
    red = { 223, 102, 88 },
}

Styles.list = {
    paper = {
        id = "paper",
        name = "Fridge door",
        blurb = "Warm paper cards pinned to the apartment. Handwriting for anything a roommate said.",
        layout = "paper",
        scrim = 0.35,
        corner = 4,
        cardTransparency = 0.02,
        tilt = true,
        stroke = 0,
        colors = {
            bg = { 46, 38, 32 },
            card = { 248, 241, 225 },
            cardAlt = { 236, 226, 203 },
            ink = { 60, 52, 44 },
            muted = { 128, 115, 98 },
            accent = { 219, 149, 70 },
            good = { 96, 147, 122 },
            warn = { 198, 138, 60 },
            bad = { 191, 90, 74 },
            cool = { 108, 129, 158 },
            line = { 206, 193, 169 },
            chipOn = { 96, 147, 122 },
            chipOff = { 236, 226, 203 },
            bubbleMine = { 214, 229, 216 },
            bubbleOther = { 240, 231, 212 },
        },
        fonts = {
            display = "marker",
            heading = "hand",
            body = "hand",
            data = "gothamMedium",
        },
    },
    phone = {
        id = "phone",
        name = "Roommate app",
        blurb = "The household lives in a phone. Chat first, one thumb-sized card at a time.",
        layout = "phone",
        scrim = 0.2,
        corner = 16,
        cardTransparency = 0,
        tilt = false,
        stroke = 0,
        colors = {
            bg = { 22, 24, 28 },
            card = { 252, 251, 248 },
            cardAlt = { 240, 238, 233 },
            ink = { 30, 32, 36 },
            muted = { 130, 134, 142 },
            accent = { 232, 160, 74 },
            good = { 73, 158, 118 },
            warn = { 214, 152, 58 },
            bad = { 212, 88, 76 },
            cool = { 92, 126, 186 },
            line = { 224, 221, 214 },
            chipOn = { 30, 32, 36 },
            chipOff = { 236, 234, 229 },
            bubbleMine = { 202, 226, 210 },
            bubbleOther = { 238, 236, 231 },
        },
        fonts = {
            display = "gothamBold",
            heading = "gothamBold",
            body = "gotham",
            data = "gothamMedium",
        },
    },
    board = {
        id = "board",
        name = "Situation board",
        blurb = "Dark strategy dashboard. Everything that can evict you is on screen at once.",
        layout = "board",
        scrim = 0.55,
        corner = 6,
        cardTransparency = 0.06,
        tilt = false,
        stroke = 1,
        colors = {
            bg = { 20, 23, 27 },
            card = { 33, 38, 44 },
            cardAlt = { 42, 48, 56 },
            ink = { 235, 233, 226 },
            muted = { 146, 154, 163 },
            accent = { 233, 176, 91 },
            good = { 108, 189, 148 },
            warn = { 226, 166, 74 },
            bad = { 226, 104, 90 },
            cool = { 122, 158, 218 },
            line = { 58, 66, 76 },
            chipOn = { 233, 176, 91 },
            chipOff = { 42, 48, 56 },
            bubbleMine = { 48, 66, 58 },
            bubbleOther = { 44, 50, 58 },
        },
        fonts = {
            display = "condensedBold",
            heading = "condensedBold",
            body = "gotham",
            data = "mono",
        },
    },
}

-- Full-screen studies share warm, outlined game UI, with distinct compositions.
for _, entry in
    {
        { "tablet", "HousePad", { 216, 173, 126 }, { 72, 115, 95 }, 22 },
        { "laptop", "Roomie OS", { 91, 119, 113 }, { 64, 102, 140 }, 10 },
        { "arcade", "House meeting", { 223, 170, 93 }, { 161, 73, 58 }, 18 },
    }
do
    local id = entry[1]
    Styles.list[id] = {
        id = id,
        name = entry[2],
        blurb = "Full-screen concept with bean portraits, messaging and a separate shift view.",
        layout = id,
        fullscreen = true,
        scrim = 1,
        corner = entry[5],
        cardTransparency = 0,
        tilt = false,
        stroke = 2,
        colors = {
            bg = entry[3],
            card = { 255, 247, 225 },
            cardAlt = { 239, 224, 194 },
            ink = { 51, 45, 42 },
            muted = { 111, 96, 78 },
            accent = entry[4],
            good = { 53, 108, 78 },
            warn = { 142, 91, 32 },
            bad = { 167, 65, 53 },
            cool = { 57, 94, 140 },
            line = { 67, 56, 48 },
            chipOn = entry[4],
            chipOff = { 239, 224, 194 },
            bubbleMine = { 204, 226, 210 },
            bubbleOther = { 247, 230, 198 },
        },
        fonts = {
            display = "gothamBold",
            heading = "gothamBold",
            body = "gotham",
            data = "gothamMedium",
        },
    }
end

function Styles.get(id: string): any
    local style = Styles.list[id]
    assert(style, "Unknown menu style: " .. tostring(id))
    return style
end

function Styles.step(id: string, delta: number): string
    local index = table.find(Styles.order, id) or 1
    return Styles.order[1 + (index - 1 + delta) % #Styles.order]
end

return Styles
