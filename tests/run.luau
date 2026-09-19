--!strict
local fs = require("@lune/fs")

-- Future *.spec.luau modules return a function and exercise pure rules without Studio.
local count = 0
local function runDirectory(path: string)
    local entries = fs.readDir(path)
    table.sort(entries)
    for _, entry in entries do
        local child = path .. "/" .. entry
        if fs.isDir(child) then
            runDirectory(child)
        elseif string.match(entry, "%.spec%.luau$") then
            local modulePath = string.gsub(child, "%.luau$", "")
            local test = require("../" .. modulePath)
            assert(type(test) == "function", child .. " must return a test function")
            test()
            count += 1
            print("PASS " .. child)
        end
    end
end

runDirectory("tests")
assert(count > 0, "No test modules found")
print(string.format("%d test module(s) passed", count))
