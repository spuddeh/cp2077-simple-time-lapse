-- ======================================================================================
-- Mod Name: Simple Time-lapse - Vehicle Dilation Module
-- Author: Spuddeh
-- Description: Simulates time dilation on ambient traffic using autonomous drive
--              commands. Native TimeDilation on vehicles is impossible (Havok physics
--              limitation). This module scans for nearby vehicles and injects
--              AIVehicleDriveToPointAutonomousCommand with scaled speeds, plus
--              crowd spawning overrides to counteract traffic thinning.
-- Mod Version: 1.3.0
-- ======================================================================================

local VehicleDilation = {}
local appliedVehicles = {} -- Tracks which vehicles have been given autonomous commands
local scanTimer = 0        -- Accumulates delta time until the next scan interval
local logTimer = 0         -- Throttles scan summary logs to once per second

-- =========================================================================
-- ### INI OVERRIDES ###
-- Two categories:
--   1. Vehicle force-move caps (float, scaled by speedMult)
--   2. Crowd spawning overrides (fixed values during time-lapse)
-- =========================================================================
local savedOriginals = {}

-- Vehicle physics caps — scaled by speedMult
local vehicleOverrides = {
    { group = "Vehicle", key = "ForceMoveToMaxLinearSpeed",  baseline = 30.0, scale = 1.0 },
    { group = "Vehicle", key = "ForceMoveToMaxAngularSpeed", baseline = 5.0,  scale = 0.5 },
}

-- Crowd & traffic overrides — fixed values during time-lapse.
-- Spawning:
--   DespawnLastSeenMinTime: Seconds an entity persists after leaving view. Lower = faster cleanup.
--   SpawnLimit: Per-tick spawn batch size (default 1).
-- Collision recovery:
--   DisableCollisionDamage: Prevents crumpling so vehicles keep moving after bumps.
--   DisposeOnOverlap: Auto-despawns wedged/overlapping vehicles.
--   SafetyMeasure: Extra collision avoidance precautions.
--   SafetyMeasureDistance: Buffer distance (metres) for safety checks.
local crowdOverrides = {
    -- Spawning
    { group = "Crowd",   key = "DespawnLastSeenMinTime", type = "float", baseline = 20.0,  timelapse = 5.0 },
    { group = "Crowd",   key = "SpawnLimit",             type = "int",   baseline = 1,     timelapse = 1 },
    -- Collision recovery
    { group = "Vehicle", key = "DisableCollisionDamage", type = "bool",  baseline = false, timelapse = true },
    { group = "Traffic", key = "DisposeOnOverlap",       type = "bool",  baseline = false, timelapse = true },
    { group = "Traffic", key = "SafetyMeasure",          type = "bool",  baseline = false, timelapse = true },
    { group = "Traffic", key = "SafetyMeasureDistance",  type = "float", baseline = 0.5,   timelapse = 2.0 },
}

-- =========================================================================
-- ### INTERNAL HELPERS ###
-- =========================================================================

--- Safely reads a float GameOption value.
local function ReadFloat(group, key)
    local ok, val = pcall(GameOptions.GetFloat, group, key)
    if ok and val then return val end
    return nil
end

--- Safely reads an int GameOption value.
local function ReadInt(group, key)
    local ok, val = pcall(GameOptions.GetInt, group, key)
    if ok and val then return val end
    return nil
end

--- Safely reads a bool GameOption value.
local function ReadBool(group, key)
    local ok, val = pcall(GameOptions.GetBool, group, key)
    if ok and val ~= nil then return val end
    return nil
end

--- Writes a float value to a GameOption with verification logging.
local function WriteFloat(group, key, value)
    local ok, err = pcall(GameOptions.SetFloat, group, key, value)
    if not ok then
        print(string.format("[Time-lapse][VD] ERROR writing %s/%s = %.2f: %s", group, key, value, tostring(err)))
        return false
    end
    local readback = ReadFloat(group, key)
    if readback and math.abs(readback - value) < 0.01 then
        print(string.format("[Time-lapse][VD] INI OK: %s/%s = %.2f", group, key, value))
    else
        print(string.format("[Time-lapse][VD] INI UNVERIFIED: %s/%s target=%.2f readback=%s",
            group, key, value, tostring(readback)))
    end
    return true
end

--- Writes an int value to a GameOption with verification logging.
local function WriteInt(group, key, value)
    local ok, err = pcall(GameOptions.SetInt, group, key, value)
    if not ok then
        print(string.format("[Time-lapse][VD] ERROR writing %s/%s = %d: %s", group, key, value, tostring(err)))
        return false
    end
    local readback = ReadInt(group, key)
    if readback and readback == value then
        print(string.format("[Time-lapse][VD] INI OK: %s/%s = %d", group, key, value))
    else
        print(string.format("[Time-lapse][VD] INI UNVERIFIED: %s/%s target=%d readback=%s",
            group, key, value, tostring(readback)))
    end
    return true
end

--- Writes a bool value to a GameOption with verification logging.
local function WriteBool(group, key, value)
    local ok, err = pcall(GameOptions.SetBool, group, key, value)
    if not ok then
        print(string.format("[Time-lapse][VD] ERROR writing %s/%s = %s: %s", group, key, tostring(value), tostring(err)))
        return false
    end
    local readback = ReadBool(group, key)
    if readback ~= nil and readback == value then
        print(string.format("[Time-lapse][VD] INI OK: %s/%s = %s", group, key, tostring(value)))
    else
        print(string.format("[Time-lapse][VD] INI UNVERIFIED: %s/%s target=%s readback=%s",
            group, key, tostring(value), tostring(readback)))
    end
    return true
end

-- =========================================================================
-- ### SNAPSHOT / APPLY / RESTORE ###
-- =========================================================================

--- Snapshots current values for both vehicle and crowd overrides.
local function SnapshotINI()
    savedOriginals = {}

    -- Vehicle force-move caps (floats)
    for _, entry in ipairs(vehicleOverrides) do
        local lookupKey = entry.group .. "/" .. entry.key
        local current = ReadFloat(entry.group, entry.key)
        savedOriginals[lookupKey] = current or entry.baseline
        print(string.format("[Time-lapse][VD] Snapshot: %s = %.4f", lookupKey, savedOriginals[lookupKey]))
    end

    -- Crowd/traffic overrides (mixed types)
    for _, entry in ipairs(crowdOverrides) do
        local lookupKey = entry.group .. "/" .. entry.key
        if entry.type == "int" then
            local current = ReadInt(entry.group, entry.key)
            savedOriginals[lookupKey] = current or entry.baseline
            print(string.format("[Time-lapse][VD] Snapshot: %s = %d", lookupKey, savedOriginals[lookupKey]))
        elseif entry.type == "bool" then
            local current = ReadBool(entry.group, entry.key)
            if current == nil then current = entry.baseline end
            savedOriginals[lookupKey] = current
            print(string.format("[Time-lapse][VD] Snapshot: %s = %s", lookupKey, tostring(current)))
        else
            local current = ReadFloat(entry.group, entry.key)
            savedOriginals[lookupKey] = current or entry.baseline
            print(string.format("[Time-lapse][VD] Snapshot: %s = %.4f", lookupKey, savedOriginals[lookupKey]))
        end
    end
end

--- Applies all overrides. Vehicle caps are scaled by speedMult; crowd overrides use fixed timelapse values.
local function ApplyINI(speedMult)
    -- Vehicle force-move caps (scaled by multiplier)
    print(string.format("[Time-lapse][VD] Applying Vehicle force-move caps for %.1fx", speedMult))
    for _, entry in ipairs(vehicleOverrides) do
        local lookupKey = entry.group .. "/" .. entry.key
        local baseVal = savedOriginals[lookupKey] or entry.baseline
        local newVal = baseVal * speedMult * entry.scale
        local maxCap = math.abs(baseVal) * 20.0
        if newVal > maxCap then newVal = maxCap end
        WriteFloat(entry.group, entry.key, newVal)
    end

    -- Crowd/traffic overrides (fixed timelapse values, not scaled)
    print("[Time-lapse][VD] Applying crowd/traffic overrides")
    for _, entry in ipairs(crowdOverrides) do
        if entry.type == "int" then
            WriteInt(entry.group, entry.key, entry.timelapse)
        elseif entry.type == "bool" then
            WriteBool(entry.group, entry.key, entry.timelapse)
        else
            WriteFloat(entry.group, entry.key, entry.timelapse)
        end
    end
end

--- Restores all overrides to their pre-timelapse snapshotted values.
local function RestoreINI()
    print("[Time-lapse][VD] Restoring original INI values.")

    -- Vehicle force-move caps
    for _, entry in ipairs(vehicleOverrides) do
        local lookupKey = entry.group .. "/" .. entry.key
        local originalVal = savedOriginals[lookupKey] or entry.baseline
        WriteFloat(entry.group, entry.key, originalVal)
    end

    -- Crowd/traffic overrides
    for _, entry in ipairs(crowdOverrides) do
        local lookupKey = entry.group .. "/" .. entry.key
        if entry.type == "int" then
            local originalVal = savedOriginals[lookupKey] or entry.baseline
            WriteInt(entry.group, entry.key, originalVal)
        elseif entry.type == "bool" then
            local originalVal = savedOriginals[lookupKey]
            if originalVal == nil then originalVal = entry.baseline end
            WriteBool(entry.group, entry.key, originalVal)
        else
            local originalVal = savedOriginals[lookupKey] or entry.baseline
            WriteFloat(entry.group, entry.key, originalVal)
        end
    end

    savedOriginals = {}
end

-- =========================================================================
-- ### AUTONOMOUS DRIVE COMMAND ###
-- =========================================================================

--- Injects an AIVehicleDriveToPointAutonomousCommand on a single vehicle.
--- Projects 1000m ahead along their current heading, with speed scaled by `speedMult`.
---
--- Speed tuning rationale (to reduce rear-end collisions):
---   maxSpeed  = base * mult, capped at 40 m/s (144 km/h) — lower cap means less
---              closing speed when they catch up to traffic ahead.
---   minSpeed  = 3.0 — low enough to allow real braking/stopping behind other cars.
---   forcedStartSpeed = 5.0 * mult — gentler launch from stops, less likely to ram
---              the car in front when a light turns green.
---
--- @param vehicle VehicleObject The vehicle entity to command
--- @param speedMult number The speed multiplier (frenzySpeedMult, e.g. 1.5 to 20.0)
function VehicleDilation.ApplyAutonomousDrive(vehicle, speedMult)
    local entId = tostring(vehicle:GetEntityID().hash)
    if appliedVehicles[entId] then return end -- Already commanding this one

    -- PARKED CAR FILTER: Check for AI component. Active traffic vehicles
    -- have an AIComponent; static decoration/parked cars do not.
    -- We can't use GetCurrentSpeed() because marble/crowd vehicles report ~0.
    local aiComp = vehicle:GetAIComponent()
    if not aiComp then return end -- No AI = decoration/parked prop

    local currentSpeed = vehicle:GetCurrentSpeed()

    local pos = vehicle:GetWorldPosition()
    local fwd = vehicle:GetWorldForward()
    local distance = 1000.0

    -- Project 1000m ahead along their current heading
    local targetVec = Vector3.new(
        pos.x + (fwd.x * distance),
        pos.y + (fwd.y * distance),
        pos.z + (fwd.z * distance)
    )

    -- Scale speed with a more conservative cap to reduce collisions
    local baseSpeed = math.max(currentSpeed, 15.0)               -- Floor at 15m/s (54km/h)
    local targetMaxSpeed = math.min(baseSpeed * speedMult, 40.0) -- Cap 40m/s (144km/h) — reduced from 80

    -- Build the autonomous drive command with collision-aware tuning
    local cmd = AIVehicleDriveToPointAutonomousCommand.new()
    cmd.targetPosition = targetVec
    cmd.maxSpeed = targetMaxSpeed
    cmd.minSpeed = 3.0                      -- Allow real braking (was 5.0 * speedMult = 7.5)
    cmd.clearTrafficOnPath = false          -- Don't ram other cars off the road
    cmd.forcedStartSpeed = 5.0 * speedMult  -- Gentler launch (was 10.0 * speedMult)
    cmd.driveDownTheRoadIndefinitely = true -- Follow the road system (lanes, lights)

    -- Send the command via the AI component (already validated above)
    -- Clear existing spline-following commands so the autonomous command takes priority
    aiComp:CancelOrInterruptCommand(CName.new("AIVehicleOnSplineCommand"), true, true)
    aiComp:CancelOrInterruptCommand(CName.new("AIVehicleJoinTrafficCommand"), true, true)
    aiComp:SetInitCmd(cmd)

    -- Also queue the command as an event for redundancy
    local evt = AICommandEvent.new()
    evt.command = cmd
    vehicle:QueueEvent(evt)

    appliedVehicles[entId] = true
    print(string.format("[Time-lapse][VD] Applied drive cmd to %s (speed %.0f -> %.0f m/s)",
        entId, currentSpeed, targetMaxSpeed))
end

-- =========================================================================
-- ### VEHICLE SCANNER ###
-- =========================================================================

--- Scans for nearby vehicles using the TargetingSystem and applies autonomous
--- drive commands to any that have an active AI component.
--- Uses TargetingSet.Complete for a full 360-degree search (not frustum-only).
---
--- @param speedMult number The speed multiplier
function VehicleDilation.ScanAndApply(speedMult)
    local player = Game.GetPlayer()
    if not player then return end

    -- Diagnostic counters for this tick
    local totalEntities = 0
    local vehiclesFound = 0
    local alreadyApplied = 0
    local skippedParked = 0
    local newlyApplied = 0

    -- TargetSearchQuery has a hard limit of 128 items. We scan with two different
    -- TSF masks to cover both puppet and device/vehicle collision types.
    local function QueryMask(maskValue)
        local searchQuery = TargetSearchQuery.new()
        searchQuery.maxDistance = 800
        searchQuery.testedSet = "Complete" -- 360-degree scan, not frustum-only
        searchQuery.filterObjectByDistance = true
        searchQuery.ignoreInstigator = true
        searchQuery.searchFilter = Game.TSF_Any(maskValue)

        local success, parts = Game.GetTargetingSystem():GetTargetParts(player, searchQuery)
        if success and parts then
            for _, part in ipairs(parts) do
                totalEntities = totalEntities + 1
                local entity = part:GetComponent():GetEntity()
                if entity and entity:IsVehicle() then
                    vehiclesFound = vehiclesFound + 1
                    local entId = tostring(entity:GetEntityID().hash)

                    if appliedVehicles[entId] then
                        alreadyApplied = alreadyApplied + 1
                    elseif not entity:GetAIComponent() then
                        skippedParked = skippedParked + 1
                    else
                        VehicleDilation.ApplyAutonomousDrive(entity, speedMult)
                        newlyApplied = newlyApplied + 1
                    end
                end
            end
        end
    end

    QueryMask(8) -- Obj_Device (vehicles). Obj_Puppet (2) removed — it only found pedestrians.

    -- Log scan summary once per second (not every tick)
    if newlyApplied > 0 or logTimer >= 1.0 then
        print(string.format(
            "[Time-lapse][VD] Scan: %d entities | %d vehicles (new:%d tracked:%d noAI:%d)",
            totalEntities, vehiclesFound, newlyApplied, alreadyApplied, skippedParked))
        logTimer = 0
    end
end

-- =========================================================================
-- ### PUBLIC API ###
-- =========================================================================

--- Called when the time-lapse starts with Traffic Frenzy enabled.
--- Snapshots Vehicle INI caps and applies overrides.
--- @param speedMult number The frenzySpeedMult from the UI slider
function VehicleDilation.Start(speedMult)
    print(string.format("[Time-lapse][VD] Starting (Autonomous Drive) at %.1fx", speedMult))
    SnapshotINI()
    ApplyINI(speedMult)
    appliedVehicles = {}
    scanTimer = 0
    logTimer = 0
end

--- Called every frame while the time-lapse is active.
--- Periodically scans for new vehicles and applies autonomous drive commands.
--- @param deltaTime number Frame delta in seconds
--- @param speedMult number The frenzySpeedMult from the UI slider
function VehicleDilation.Update(deltaTime, speedMult)
    if speedMult <= 1.0 then return end

    scanTimer = scanTimer + deltaTime
    logTimer = logTimer + deltaTime
    if scanTimer >= 0.1 then -- Scan every 100ms
        scanTimer = 0
        VehicleDilation.ScanAndApply(speedMult)
    end
end

--- Called when the time-lapse stops. Restores INI and clears tracking.
function VehicleDilation.Stop()
    print("[Time-lapse][VD] Stopping. Restoring vehicle caps and clearing tracking.")
    RestoreINI()
    appliedVehicles = {}
    scanTimer = 0
end

--- Alias for Stop(); also used as a safety reset.
function VehicleDilation.Reset()
    VehicleDilation.Stop()
end

return VehicleDilation
