--!strict
local Scene = {}

function Scene.build(stage: Model, config: any): { [string]: BasePart }
    local old = stage:FindFirstChild("Apartment")
    if old then
        old:Destroy()
    end
    local model = Instance.new("Model")
    model.Name = "Apartment"
    model.Parent = stage
    local function part(name: string, size: Vector3, position: Vector3, color: Color3): Part
        local item = Instance.new("Part")
        item.Name = name
        item.Anchored = true
        item.Size = size
        item.Position = position
        item.Color = color
        item.Material = Enum.Material.SmoothPlastic
        item.TopSurface = Enum.SurfaceType.Smooth
        item.BottomSurface = Enum.SurfaceType.Smooth
        item.Parent = model
        return item
    end
    local function label(target: BasePart, text: string, height: number)
        local gui = Instance.new("BillboardGui")
        gui.Name = "Label"
        gui.Size = UDim2.fromOffset(180, 34)
        gui.StudsOffset = Vector3.new(0, height, 0)
        gui.AlwaysOnTop = false
        gui.MaxDistance = 100
        gui.Parent = target
        local caption = Instance.new("TextLabel")
        caption.Size = UDim2.fromScale(1, 1)
        caption.BackgroundColor3 = Color3.fromRGB(31, 42, 48)
        caption.BackgroundTransparency = 0.15
        caption.TextColor3 = Color3.fromRGB(255, 245, 220)
        caption.TextSize = 15
        caption.Font = Enum.Font.GothamMedium
        caption.Text = text
        caption.Parent = gui
    end
    local floor = stage:FindFirstChild("Floor") :: BasePart
    floor.Size = Vector3.new(60, 1, 32)
    floor.Color = Color3.fromRGB(102, 83, 68)
    local spawn = stage:FindFirstChild("Spawn") :: SpawnLocation
    spawn.Position = Vector3.new(-15, 0.1, 10)
    spawn.Size = Vector3.new(4, 0.2, 4)
    spawn.Transparency = 1
    spawn.CanCollide = false
    part(
        "KitchenTiles",
        Vector3.new(29, 0.1, 31),
        Vector3.new(-15, 0.05, 0),
        Color3.fromRGB(185, 198, 175)
    )
    part(
        "LoungeFloor",
        Vector3.new(29, 0.1, 31),
        Vector3.new(15, 0.05, 0),
        Color3.fromRGB(211, 176, 130)
    )
    local wallColor = Color3.fromRGB(233, 220, 193)
    part("BackWall", Vector3.new(61, 8, 1), Vector3.new(0, 4, -16), wallColor)
    part("LeftWall", Vector3.new(1, 8, 32), Vector3.new(-30, 4, 0), wallColor)
    part("RightWall", Vector3.new(1, 8, 32), Vector3.new(30, 4, 0), wallColor)
    local front = part("FrontBoundary", Vector3.new(60, 8, 1), Vector3.new(0, 4, 16), wallColor)
    front.Transparency = 1
    part("DividerBack", Vector3.new(1, 5, 14), Vector3.new(0, 2.5, -9), wallColor)
    part("DividerFront", Vector3.new(1, 2, 5), Vector3.new(0, 1, 13), wallColor)
    part("Rug", Vector3.new(18, 0.12, 12), Vector3.new(15, 0.15, 2), Color3.fromRGB(135, 162, 160))
    part("SofaSeat", Vector3.new(8, 1.8, 3), Vector3.new(12, 1.3, 7), Color3.fromRGB(208, 139, 95))
    part("SofaBack", Vector3.new(8, 3.5, 1), Vector3.new(12, 2, 8.5), Color3.fromRGB(186, 116, 80))
    part(
        "CoffeeTable",
        Vector3.new(5, 1.6, 3),
        Vector3.new(12, 0.9, 1),
        Color3.fromRGB(102, 83, 68)
    )
    part("Fridge", Vector3.new(4, 6, 3), Vector3.new(-17, 3, -13), Color3.fromRGB(222, 233, 223))
    local puddle = part(
        "Puddle",
        Vector3.new(6, 0.12, 4),
        Vector3.new(-24, 0.2, -6.5),
        Color3.fromRGB(105, 188, 218)
    )
    puddle.CanCollide = false
    puddle.Transparency = 0.25
    local stations: { [string]: BasePart } = {}
    for _, id in config.taskOrder do
        local data = config.tasks[id]
        local station = part(
            id,
            Vector3.new(4, 2.5, 3),
            Vector3.new(data.x, 1.3, data.z),
            if id == "party" then Color3.fromRGB(86, 81, 96) else Color3.fromRGB(113, 137, 136)
        )
        station:SetAttribute("TaskId", id)
        label(station, data.name, 2.8)
        stations[id] = station
    end
    for _, name in config.roommateOrder do
        local data = config.roommates[name]
        local color = Color3.fromRGB(data.color[1], data.color[2], data.color[3])
        local body = part(name, Vector3.new(2, 2.4, 1.5), Vector3.new(data.x, 1.7, data.z), color)
        local head = part(
            name .. "Head",
            Vector3.new(1.7, 1.7, 1.7),
            Vector3.new(data.x, 3.6, data.z),
            color
        )
        head.Shape = Enum.PartType.Ball
        label(head, name, 1.7)
        for _, side in { -1, 1 } do
            local eye = part(
                name .. "Eye",
                Vector3.new(0.16, 0.23, 0.15),
                Vector3.new(data.x + side * 0.3, 3.7, data.z + 0.8),
                Color3.fromRGB(31, 42, 48)
            )
            eye.CanCollide = false
        end
        body:SetAttribute("Roommate", name)
    end
    return stations
end

return Scene
