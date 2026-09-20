--!strict
-- Headless render check for the menu visual study.
--
-- Roblox UI code fails at runtime, not at lint time: a misspelled property or a
-- nil layout value only shows up once something draws. This builds every screen
-- in every candidate look against Lune's Roblox reflection database, so those
-- mistakes surface from the CLI instead of during a Studio playtest. It is not
-- a visual check: it proves the instances can be created, not that they look
-- right or lay out correctly on screen.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Instance = roblox.Instance
local rbx = roblox :: any

local function expect(condition: any, message: string)
    assert(condition, "Menu render: " .. message)
end

-- Minimal stand-ins for the instances the client modules reach through.
local function moduleRef(path: string): any
    return { __module = path }
end

local function folder(prefix: string): any
    local self = {}
    function self.WaitForChild(_self: any, name: string): any
        return moduleRef(prefix .. name .. ".luau")
    end
    self.FindFirstChild = self.WaitForChild
    return self
end

local replicatedStorage = {}
function replicatedStorage.WaitForChild(_self: any, name: string): any
    expect(name == "Shared", "the client should only reach for Shared, not " .. name)
    return folder("src/shared/")
end

local fakeGame = {}
function fakeGame.GetService(_self: any, name: string): any
    expect(name == "ReplicatedStorage", "unexpected service at module scope: " .. name)
    return replicatedStorage
end

local loaded: { [string]: any } = {}
local loading: { [string]: boolean } = {}
local load

local function requireModule(target: any): any
    local path = if type(target) == "table" then target.__module else target
    expect(type(path) == "string", "require target is not a module reference")
    if loaded[path] == nil then
        expect(not loading[path], "circular require: " .. path)
        loading[path] = true
        loaded[path] = load(path)
        loading[path] = nil
    end
    return loaded[path]
end

function load(path: string): any
    local directory = string.match(path, "^(.*/)[^/]+$")
    local scriptRef = {
        Parent = setmetatable({}, {
            __index = function(_self, name: string)
                return moduleRef(directory .. name .. ".luau")
            end,
        }),
    }
    local environment = {
        game = fakeGame,
        script = scriptRef,
        require = requireModule,
        Instance = Instance,
        Enum = rbx.Enum,
        Color3 = rbx.Color3,
        UDim = rbx.UDim,
        UDim2 = rbx.UDim2,
        Vector2 = rbx.Vector2,
        Font = rbx.Font,
    }
    local chunk = luau.load(fs.readFile(path), {
        debugName = path,
        environment = environment,
        injectGlobals = true,
    })
    return chunk()
end

return function()
    local Preview = requireModule("src/client/MenuPreview.luau")
    local Styles = requireModule("src/shared/MenuStyles.luau")
    local Data = requireModule("src/shared/MenuPreviewData.luau")

    local root = Instance.new("ScreenGui")
    local stage = Instance.new("Frame")
    stage.Parent = root

    local drawn = 0
    for _, styleId in Styles.order do
        for _, screenId in Data.screens do
            local style, screen = Preview.render(stage, screenId, styleId)
            expect(style.id == styleId, screenId .. " rendered the wrong look")
            expect(screen.id == screenId, styleId .. " rendered the wrong screen")
            local children = stage:GetChildren()
            expect(#children > 0, string.format("%s in %s produced nothing", screenId, styleId))
            local texts = 0
            for _, child in children do
                for _, item in child:GetDescendants() do
                    if item:IsA("TextLabel") or item:IsA("TextButton") then
                        expect(
                            #item.Text > 0,
                            string.format("%s in %s has an empty label", screenId, styleId)
                        )
                        texts += 1
                    end
                end
            end
            expect(
                texts >= 8,
                string.format("%s in %s drew only %d labels", screenId, styleId, texts)
            )
            drawn += 1
        end
    end
    expect(drawn == #Styles.order * #Data.screens, "every look and screen must draw")
    print(string.format("Menus: %d screen/look combinations built without error", drawn))
end
