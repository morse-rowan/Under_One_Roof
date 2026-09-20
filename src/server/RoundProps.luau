--!strict
-- Draws the round's unresolved issues as parts in the apartment. Purely a view:
-- it reads issue records and never decides anything, so deleting it would cost
-- the player their eyes but not change a single rule outcome.
local Props = {}

local function rgb(value: { number }): Color3
    return Color3.fromRGB(value[1], value[2], value[3])
end

local function part(
    parent: Instance,
    name: string,
    size: Vector3,
    offset: Vector3,
    color: { number }
)
    local block = Instance.new("Part")
    block.Name = name
    block.Size = size
    block.Color = rgb(color)
    block.Material = Enum.Material.SmoothPlastic
    block.Anchored = true
    block.CanCollide = false
    block.CanQuery = false
    block.CanTouch = false
    block.TopSurface = Enum.SurfaceType.Smooth
    block.BottomSurface = Enum.SurfaceType.Smooth
    block:SetAttribute("PropOffset", offset)
    block.Parent = parent
    return block
end

local function dishes(model: Instance)
    for index = 1, 3 do
        local plate = part(
            model,
            "Plate",
            Vector3.new(0.95, 0.09, 0.95),
            Vector3.new(0, 1.82 + index * 0.1, 0.1 * index - 0.2),
            { 233, 228, 214 }
        )
        plate.Shape = Enum.PartType.Cylinder
        plate.CFrame = CFrame.Angles(0, 0, math.pi / 2)
    end
    part(
        model,
        "Mug",
        Vector3.new(0.34, 0.4, 0.34),
        Vector3.new(0.45, 1.95, -0.3),
        { 176, 126, 104 }
    )
end

local function litter(model: Instance, bagged: boolean)
    if bagged then
        local sack =
            part(model, "Sack", Vector3.new(1, 1.15, 1), Vector3.new(0, 0.7, 0), { 62, 66, 62 })
        sack.Shape = Enum.PartType.Ball
        part(model, "Tie", Vector3.new(0.18, 0.4, 0.18), Vector3.new(0, 1.35, 0), { 46, 49, 46 })
        return
    end
    part(
        model,
        "Wrapper",
        Vector3.new(0.7, 0.16, 0.5),
        Vector3.new(-0.3, 0.1, 0.2),
        { 198, 176, 132 }
    )
    part(
        model,
        "Carton",
        Vector3.new(0.55, 0.5, 0.4),
        Vector3.new(0.35, 0.28, -0.1),
        { 168, 121, 92 }
    )
    part(
        model,
        "Can",
        Vector3.new(0.25, 0.4, 0.25),
        Vector3.new(0.05, 0.22, 0.45),
        { 150, 158, 160 }
    )
end

local function leak(model: Instance)
    local puddle = part(
        model,
        "Puddle",
        Vector3.new(1.9, 0.06, 1.9),
        Vector3.new(0, 0.06, 1.1),
        { 120, 146, 158 }
    )
    puddle.Shape = Enum.PartType.Cylinder
    puddle.CFrame = CFrame.Angles(0, 0, math.pi / 2)
    puddle.Transparency = 0.35
    part(model, "Drip", Vector3.new(0.1, 0.38, 0.1), Vector3.new(0, 1.1, 0.85), { 120, 146, 158 })
end

local function roaches(model: Instance)
    for index = 1, 5 do
        local angle = index * 1.3
        part(
            model,
            "Roach",
            Vector3.new(0.22, 0.09, 0.14),
            Vector3.new(math.cos(angle) * 0.7, 0.07, math.sin(angle) * 0.7),
            { 68, 50, 40 }
        )
    end
end

local builders = { dishes = dishes, leak = leak, roaches = roaches }

function Props.build(parent: Instance, item: any): Model
    local model = Instance.new("Model")
    model.Name = "Issue" .. item.id
    model:SetAttribute("IssueId", item.id)
    model.Parent = parent
    local builder = builders[item.kind]
    if builder then
        builder(model)
    else
        litter(model, item.stage ~= "open")
    end
    return model
end

-- Reposition every child by the offset it was built with, so one model can follow
-- a carried trash bag around the apartment without being rebuilt.
function Props.place(model: Model, origin: Vector3)
    for _, child in model:GetChildren() do
        if child:IsA("BasePart") then
            local offset = child:GetAttribute("PropOffset") :: Vector3
            local rotation = child.CFrame - child.CFrame.Position
            child.CFrame = CFrame.new(origin + offset) * rotation
        end
    end
end

return Props
