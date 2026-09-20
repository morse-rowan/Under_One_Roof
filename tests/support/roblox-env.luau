--!strict
-- Loads a Roblox client module against Lune's reflection database, with the few
-- instances it reaches through at module scope replaced by stubs.
--
-- Roblox UI code fails at runtime rather than at lint time: a misspelled property
-- or a nil layout value only shows up once something draws. Loading a module here
-- turns that into a CLI failure. It proves instances can be created, not that the
-- result looks right on screen.
--
-- `tests/menu-render.spec.luau` grew its own copy of this first; it was left
-- alone rather than edited from a session that did not own that file.
local fs = require("@lune/fs")
local task = require("@lune/task")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local rbx = roblox :: any

local Env = {}

Env.Instance = roblox.Instance

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

-- Creates an isolated loader. Each call gets its own module cache, so one spec
-- cannot leave state behind for the next.
function Env.new(services: { [string]: any }?): (path: string) -> any
    local replicatedStorage = {}
    function replicatedStorage.WaitForChild(_self: any, name: string): any
        assert(name == "Shared", "unexpected ReplicatedStorage child at module scope: " .. name)
        return folder("src/shared/")
    end

    local available: { [string]: any } = services or {}
    available.ReplicatedStorage = replicatedStorage

    local fakeGame = {}
    function fakeGame.GetService(_self: any, name: string): any
        local service = available[name]
        assert(service, "unexpected service at module scope: " .. name)
        return service
    end

    local loaded: { [string]: any } = {}
    local loading: { [string]: boolean } = {}
    local load

    local function requireModule(target: any): any
        local path = if type(target) == "table" then target.__module else target
        assert(type(path) == "string", "require target is not a module reference")
        if loaded[path] == nil then
            assert(not loading[path], "circular require: " .. path)
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
        local chunk = luau.load(fs.readFile(path), {
            debugName = path,
            environment = {
                game = fakeGame,
                script = scriptRef,
                require = requireModule,
                task = task,
                Instance = roblox.Instance,
                Enum = rbx.Enum,
                Color3 = rbx.Color3,
                UDim = rbx.UDim,
                UDim2 = rbx.UDim2,
                Vector2 = rbx.Vector2,
                Vector3 = rbx.Vector3,
                CFrame = rbx.CFrame,
                Font = rbx.Font,
            },
            injectGlobals = true,
        })
        return chunk()
    end

    return requireModule
end

return Env
