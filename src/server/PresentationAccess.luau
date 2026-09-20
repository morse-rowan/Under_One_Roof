--!strict
local Access = {}

function Access.allowed(
    userId: number,
    studio: boolean,
    ownerId: number?,
    invited: { number }
): boolean
    if studio or (ownerId ~= nil and ownerId > 0 and userId == ownerId) then
        return true
    end
    return table.find(invited, userId) ~= nil
end

return Access
