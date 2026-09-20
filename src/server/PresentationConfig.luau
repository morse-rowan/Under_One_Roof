--!strict
-- Server-only deployment settings. Never put credential values in source.
return {
    allowedUserIds = {}, -- Add invited judges' numeric Roblox user IDs here.
    -- The individual experience owner and local Studio sessions are allowed.
    -- Group-owned experiences require explicit user IDs above.
    brainUrl = "http://127.0.0.1:8787/decide",
    brainSecretName = "ROOMMATE_GATEWAY_TOKEN",
}
