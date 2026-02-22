-- ======================================================================================
-- Simple Time-lapse - CameraUtils Module
-- Mod Version: 1.3.0
-- Author:       Spuddeh
--
-- DESCRIPTION:
-- Handles Head Bobbing (Additive Camera Motions) via GameSettings.
-- Handles Player Movement/Look Locking via Status Effects.
-- ======================================================================================

local GameSettings = require("Modules/GameSettings")
local CameraUtils = {}

-- Hardcoded path as requested
local CAMERA_PATH = "/accessibility/difficulty/AdditiveCameraMovements"

-- Helper to get IDs safely at runtime
local function GetRestrictionIDs()
    return {
        MOVE = TweakDBID.new("GameplayRestriction.NoMovement"),
        LOOK = TweakDBID.new("GameplayRestriction.NoCameraControl"),
        COMBAT = TweakDBID.new("GameplayRestriction.NoCombat")
    }
end

-- =================================================================
-- ### HEAD BOBBING ###
-- =================================================================

function CameraUtils.Disable(mod)
    if not GameSettings then return end

    -- Safely attempt to get the current setting
    local success, val = pcall(function() return GameSettings.Get(CAMERA_PATH) end)

    if success and val ~= nil then
        mod.cameraSnapshot = val
        GameSettings.Set(CAMERA_PATH, 0.0)
        print("[Simple Time-lapse] Head Bobbing Disabled")
    else
        print("[Simple Time-lapse] Warning: Could not access AdditiveCameraMovements at " .. CAMERA_PATH)
    end
end

function CameraUtils.Restore(mod)
    if not GameSettings or mod.cameraSnapshot == nil then return end

    pcall(function() GameSettings.Set(CAMERA_PATH, mod.cameraSnapshot) end)
    mod.cameraSnapshot = nil
    print("[Simple Time-lapse] Head Bobbing Restored")
end

function CameraUtils.ForceRestore(mod)
    if not GameSettings then return end
    pcall(function() GameSettings.Set(CAMERA_PATH, 1.0) end)
    print("[Time-lapse] Head Bob Force Restored (1.0)")
end

-- =================================================================
-- ### PLAYER LOCKING ###
-- =================================================================

function CameraUtils.LockPlayer(mod)
    local player = Game.GetPlayer()
    if not player then return end
    local ses = Game.GetStatusEffectSystem()
    if not ses then return end
    local entityID = player:GetEntityID()

    local ids = GetRestrictionIDs()

    if mod.settings.lockMovement then
        ses:ApplyStatusEffect(entityID, ids.MOVE)
        ses:ApplyStatusEffect(entityID, ids.COMBAT)
    end

    if mod.settings.lockCamera then
        ses:ApplyStatusEffect(entityID, ids.LOOK)
    end
end

function CameraUtils.UnlockMovement(mod)
    local player = Game.GetPlayer(); if not player then return end
    local ses = Game.GetStatusEffectSystem(); if not ses then return end
    local entityID = player:GetEntityID()

    local ids = GetRestrictionIDs()
    ses:RemoveStatusEffect(entityID, ids.MOVE)
    ses:RemoveStatusEffect(entityID, ids.COMBAT)
    print("[Time-lapse] Movement Unlocked")
end

function CameraUtils.UnlockCamera(mod)
    local player = Game.GetPlayer(); if not player then return end
    local ses = Game.GetStatusEffectSystem(); if not ses then return end

    local ids = GetRestrictionIDs()
    ses:RemoveStatusEffect(player:GetEntityID(), ids.LOOK)
    print("[Time-lapse] Camera Unlocked")
end

function CameraUtils.UnlockPlayer(mod)
    local player = Game.GetPlayer(); if not player then return end
    local ses = Game.GetStatusEffectSystem(); if not ses then return end
    local entityID = player:GetEntityID()

    local ids = GetRestrictionIDs()
    ses:RemoveStatusEffect(entityID, ids.MOVE)
    ses:RemoveStatusEffect(entityID, ids.COMBAT)
    ses:RemoveStatusEffect(entityID, ids.LOOK)
end

return CameraUtils
