--!strict
-- Command entry point for the menu visual study. It only relays which mockup to
-- draw; no gameplay state exists on this path, so either command-bar context is
-- safe to use during a playtest.
local Menus = {}

local function clean(value: any): string?
    return if type(value) == "string"
            and #value > 0
            and #value <= 32
        then string.lower(value)
        else nil
end

function Menus.start()
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local ServerStorage = game:GetService("ServerStorage")

    local remote = Instance.new("RemoteEvent")
    remote.Name = "MenuPreview"
    remote.Parent = ReplicatedStorage

    local function broadcast(command: any, first: any, second: any)
        local name = clean(command) or "next"
        remote:FireAllClients(name, clean(first), clean(second))
        print(string.format("[Menus] %s %s %s", name, clean(first) or "-", clean(second) or "-"))
    end

    remote.OnServerEvent:Connect(function(_player, command, first, second)
        broadcast(command, first, second)
    end)

    local bindable = Instance.new("BindableEvent")
    bindable.Name = "MenuPreview"
    bindable.Parent = ServerStorage
    bindable.Event:Connect(broadcast)

    print(
        '[Menus] Server-context command bar: game.ServerStorage.MenuPreview:Fire("show", "night", "phone")'
    )
    print(
        '[Menus] Client-context command bar: game.ReplicatedStorage.MenuPreview:FireServer("show", "night", "phone")'
    )
end

return Menus
