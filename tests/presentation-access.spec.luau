--!strict
local Access = require("../src/server/PresentationAccess")
return function()
    assert(Access.allowed(10, true, nil, {}), "Studio remains usable offline")
    assert(Access.allowed(10, false, 10, {}), "individual owner can present")
    assert(Access.allowed(20, false, 10, { 20 }), "invited judge can play")
    assert(not Access.allowed(30, false, 10, { 20 }), "unknown account must be denied")
    assert(not Access.allowed(10, false, nil, {}), "group games fail closed until configured")
    assert(not Access.allowed(0, false, 0, {}), "unpublished owner ID is not an invitation")
end
