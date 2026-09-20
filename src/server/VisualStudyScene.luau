--!strict
local Scene = {}
local scale = 2 -- Browser-study proportions translated to the 4-stud grid.

local function rgb(value: { number }): Color3
    return Color3.fromRGB(value[1], value[2], value[3])
end

local function primitives(parent: Instance, origin: Vector3, palette: any)
    local function box(
        name: string,
        w: number,
        h: number,
        d: number,
        x: number,
        y: number,
        z: number,
        tone: any
    ): Part
        local part = Instance.new("Part")
        part.Name = name
        part.Anchored = true
        part.CanCollide = false
        part.CanTouch = false
        part.Size = Vector3.new(w, h, d) * scale
        part.Position = origin + Vector3.new(x, y, z) * scale
        part.Material = Enum.Material.SmoothPlastic
        part.TopSurface = Enum.SurfaceType.Smooth
        part.BottomSurface = Enum.SurfaceType.Smooth
        if type(tone) == "string" then
            part.Color = rgb(palette[tone])
            part:SetAttribute("VisualTone", tone)
        else
            part.Color = rgb(tone)
        end
        part.Parent = parent
        return part
    end
    local function ell(
        name: string,
        rx: number,
        ry: number,
        rz: number,
        x: number,
        y: number,
        z: number,
        tone: any
    ): Part
        local part = box(name, rx * 2, ry * 2, rz * 2, x, y, z, tone)
        -- Built-in sphere mesh keeps nonuniform proportions for stationary NPCs too.
        local mesh = Instance.new("SpecialMesh")
        mesh.MeshType = Enum.MeshType.Sphere
        mesh.Parent = part
        return part
    end
    local function cyl(
        name: string,
        radius: number,
        height: number,
        x: number,
        y: number,
        z: number,
        tone: any
    ): Part
        local part = box(name, height, radius * 2, radius * 2, x, y, z, tone)
        part.Shape = Enum.PartType.Cylinder
        part.CFrame *= CFrame.Angles(0, 0, math.pi / 2)
        return part
    end
    return box, ell, cyl
end

function Scene.bean(
    parent: Instance,
    name: string,
    color: { number },
    position: Vector3,
    palette: any
): Model
    local model = Instance.new("Model")
    model.Name = name
    local box, ell = primitives(model, Vector3.zero, palette)
    local root = box("HumanoidRootPart", 0.5, 0.5, 0.5, 0, 0, 0, color)
    root.Transparency = 1
    root.CastShadow = false
    model.PrimaryPart = root
    -- One continuous silhouette avoids a seam between stacked body/head spheres.
    ell("Head", 0.42, 0.76, 0.37, 0, 0.95, 0, color)
    for _, side in { -1, 1 } do
        ell("Foot", 0.15, 0.16, 0.22, side * 0.23, 0.2, 0.05, color)
        ell("Hand", 0.13, 0.2, 0.14, side * 0.48, 0.72, 0, color)
        ell("Eye", 0.04, 0.067, 0.038, side * 0.12, 1.3, 0.343, { 39, 54, 64 })
    end
    model:PivotTo(CFrame.new(position))
    model.Parent = parent
    return model
end

local function fixture(parent: Instance, data: any, position: Vector3, palette: any)
    local model = Instance.new("Model")
    model.Name = data.name
    model:SetAttribute("Column", data.c)
    model:SetAttribute("Row", data.r)
    model:SetAttribute("FootprintColumns", data.w)
    model:SetAttribute("FootprintRows", data.h)
    model.Parent = parent
    local box, ell, cyl = primitives(model, position, palette)
    local kind = data.kind
    if kind == "counter" or kind == "sink" or kind == "stove" then
        box("Cabinet", 1.94, 1.55, 1.62, 0, 0.82, 0, "cabinet")
        box("Worktop", 1.96, 0.15, 1.74, 0, 1.64, 0, "trim")
        box("Handle", 0.42, 0.065, 0.06, 0, 1.31, 0.83, "dark")
        if kind == "sink" then
            box("Rim", 1, 0.025, 0.88, 0, 1.73, 0, "dark")
            box("Basin", 0.8, 0.027, 0.66, 0, 1.75, 0, { 169, 185, 182 })
            box("TapStem", 0.07, 0.39, 0.07, 0, 1.92, -0.55, "wood")
            box("Tap", 0.07, 0.07, 0.36, 0, 2.1, -0.38, "wood")
        elseif kind == "stove" then
            box("Hob", 1.35, 0.03, 1.31, 0, 1.74, 0, "dark")
            for _, x in { -0.34, 0.34 } do
                for _, z in { -0.31, 0.31 } do
                    cyl("Burner", 0.22, 0.015, x, 1.767, z, { 112, 123, 123 })
                end
            end
            box("Oven", 1.06, 0.82, 0.04, 0, 0.79, 0.83, "dark")
            box("OvenGlass", 0.8, 0.55, 0.045, 0, 0.79, 0.86, { 119, 130, 134 })
        end
    elseif kind == "fridge" then
        box("Fridge", 1.4, 2.65, 1.5, 0, 1.37, 0, "trim")
        box("Seam", 1.24, 0.028, 0.045, 0, 1.78, 0.76, "wood")
        box("Handle", 0.055, 0.44, 0.07, 0.48, 1.18, 0.77, "dark")
    elseif kind == "table" then
        box("Top", 1.7, 0.22, 1.3, 0, 0.94, 0, "wood")
        for _, x in { -0.65, 0.65 } do
            for _, z in { -0.4, 0.4 } do
                box("Leg", 0.13, 0.78, 0.13, x, 0.45, z, "wood")
            end
        end
    elseif kind == "chair" then
        box("Seat", 0.86, 0.14, 0.8, 0, 0.65, 0, "sofa")
        box("Back", 0.86, 0.82, 0.12, 0, 1.01, 0.35 * data.facing, "sofa")
        for _, x in { -0.3, 0.3 } do
            for _, z in { -0.28, 0.28 } do
                box("Leg", 0.1, 0.58, 0.1, x, 0.33, z, "wood")
            end
        end
    elseif kind == "trash" then
        cyl("Bin", 0.4, 0.92, 0, 0.48, 0, "cabinet")
        cyl("Lid", 0.44, 0.1, 0, 0.99, 0, "dark")
    elseif kind == "sofa" then
        box("Seat", 5.65, 0.65, 1.48, 0, 0.73, 0, "sofa")
        box("Back", 5.65, 1.13, 0.32, 0, 1.23, -0.68, "sofa")
        for _, x in { -2.64, 2.64 } do
            box("Arm", 0.35, 0.72, 1.78, x, 1.03, 0, "sofa")
        end
        for _, x in { -1.78, 0, 1.78 } do
            box("Cushion", 1.65, 0.15, 1.3, x, 1.1, 0.07, "sofa")
        end
        for _, x in { -2.5, 2.5 } do
            for _, z in { -0.6, 0.6 } do
                box("Foot", 0.13, 0.42, 0.13, x, 0.22, z, "wood")
            end
        end
    elseif kind == "sideboard" then
        box("Cabinet", 1.32, 1.12, 3.55, 0, 0.59, 0, "wood")
        box("Top", 1.45, 0.13, 3.7, 0, 1.2, 0, "trim")
        for _, z in { -0.95, 0.95 } do
            box("Door", 0.08, 0.75, 1.25, 0.69, 0.7, z, "dark")
        end
    elseif kind == "plant" then
        cyl("Pot", 0.32, 0.55, 0, 0.35, 0, "wood")
        box("Stem", 0.075, 1.1, 0.075, 0, 1, 0, { 105, 126, 98 })
        for i = 0, 4 do
            local angle = i * 2.4
            local leaf = ell(
                "Leaf",
                0.22,
                0.46,
                0.17,
                math.cos(angle) * 0.23,
                1.05 + i * 0.12,
                math.sin(angle) * 0.23,
                { 129, 146, 118 }
            )
            leaf.CFrame *= CFrame.Angles(0, 0, math.sin(angle) * 0.7)
        end
    end
    if kind == "sink" or kind == "trash" then
        -- Future dish/fullness pieces belong here without changing the fixture footprint.
        local contents = Instance.new("Folder")
        contents.Name = "Contents"
        contents.Parent = model
    end
end

function Scene.build(stage: Model, config: any, grid: any): Model
    for _, name in { "Apartment", "VisualStudy" } do
        local old = stage:FindFirstChild(name)
        if old then
            old:Destroy()
        end
    end
    for _, name in { "Floor", "Spawn" } do
        local part = stage:FindFirstChild(name) :: BasePart
        part.Transparency = 1
        part.CanCollide = false
    end
    local scene = Instance.new("Model")
    scene.Name = "VisualStudy"
    scene.Parent = stage
    local palette = config.palettes.Warm
    local backdrop = primitives(scene, Vector3.zero, palette)
    local ground = backdrop("Backdrop", 500, 0.1, 500, 0, -0.65, 0, { 218, 211, 198 })
    ground.CastShadow = false
    local doorway = primitives(scene, Vector3.new(0, 0, 8), palette)
    for _, side in { -1, 1 } do
        doorway("DoorPost", 0.14, 2.75, 0.14, 0, 1.375, side * 0.98, "wood")
    end
    doorway("DoorLintel", 0.14, 0.16, 2.1, 0, 2.75, 0, "wood")
    local rooms = {}
    for index, name in { "Kitchen", "Lounge" } do
        local room = Instance.new("Model")
        room.Name = name
        room:SetAttribute("Room", name)
        room.Parent = scene
        rooms[name] = room
        local centerX = if index == 1 then -12 else 12
        local box = primitives(room, Vector3.new(centerX, 0, 0), palette)
        box("Foundation", 12, 0.28, 10, 0, -0.14, 0, "grout")
        for c = (index - 1) * 6, index * 6 - 1 do
            for r = 0, config.rows - 1 do
                local x, z = grid.point(config, { c = c, r = r })
                local tile = box(
                    "Tile_" .. c .. "_" .. r,
                    1.952,
                    0.04,
                    1.952,
                    (x - centerX) / scale,
                    0.02,
                    z / scale,
                    if (c + r) % 2 == 0 then "floorA" else "floorB"
                )
                tile:SetAttribute("Column", c)
                tile:SetAttribute("Row", r)
            end
        end
        box("BackWall", 12.3, 3.25, 0.22, 0, 1.5, -5.1, "wall")
        -- Lounge wall has a one-cell opening matching the shared doorway rule.
        box(
            "LeftWall",
            0.22,
            3.25,
            if index == 1 then 10.2 else 8,
            -6.1,
            1.5,
            if index == 1 then 0 else -1.1,
            "wall"
        )
        box("BackSkirting", 12.05, 0.16, 0.11, 0, 0.08, -4.94, "trim")
        box(
            "LeftSkirting",
            0.11,
            0.16,
            if index == 1 then 10 else 8,
            -5.95,
            0.08,
            if index == 1 then 0 else -1,
            "trim"
        )
        box("WindowFrame", 0.09, 1.65, 2.9, -5.95, 2, -1.1, "trim")
        box("Window", 0.10, 1.38, 2.61, -5.88, 2, -1.1, { 193, 212, 210 })
        box("WindowRail", 0.12, 0.08, 2.62, -5.81, 2, -1.1, "trim")
        box("WindowMullion", 0.12, 1.43, 0.08, -5.81, 2, -1.1, "trim")
        box("Sill", 0.35, 0.12, 3.08, -5.72, 1.2, -1.1, "trim")
    end
    for _, data in config.fixtures do
        local x, z =
            grid.point(config, { c = data.c + (data.w - 1) / 2, r = data.r + (data.h - 1) / 2 })
        fixture(rooms[grid.room(config, data)], data, Vector3.new(x, config.floorY, z), palette)
    end
    for _, data in config.roommates do
        local x, z = grid.point(config, data)
        Scene.bean(
            rooms[grid.room(config, data)],
            data.name,
            data.color,
            Vector3.new(x, config.floorY, z),
            palette
        )
    end
    return scene
end

return Scene
