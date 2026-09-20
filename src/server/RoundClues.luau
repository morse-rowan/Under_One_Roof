--!strict
-- Opaque clue markers. Only the filtered legal candidate list creates these.
local Clues = {}

function Clues.sync(parent: Instance, markers: any, point: any, room: any)
    parent:ClearAllChildren()
    for _, marker in markers do
        local model = Instance.new("Model")
        model.Name = "Clue_" .. marker.reference
        model:SetAttribute("Room", room(marker.cell))
        model.Parent = parent
        local origin = point(marker.cell)
        for index, shape in
            {
                { offset = Vector3.new(0, 0.06, 0), size = Vector3.new(1.5, 0.06, 1.5) },
                { offset = Vector3.new(0, 1.65, 0), size = Vector3.new(0.3, 0.95, 0.3) },
                { offset = Vector3.new(0, 0.95, 0), size = Vector3.new(0.3, 0.3, 0.3) },
            }
        do
            local part = Instance.new("Part")
            part.Name = if index == 1 then "ClueTile" else "Attention"
            part.Size = shape.size
            part.Position = origin + shape.offset
            part.Color = if index == 1
                then Color3.fromRGB(239, 211, 161)
                else Color3.fromRGB(171, 112, 31)
            part.Material = Enum.Material.SmoothPlastic
            part.Anchored = true
            part.CanCollide = false
            part.CanTouch = false
            part.CanQuery = false
            part.Parent = model
        end
    end
end

return Clues
