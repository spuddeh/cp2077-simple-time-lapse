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

local Log = require("Modules/Log")
local Undo = require("Modules/Undo")

local VehicleDilation = {}
local running = false      -- True from Start until the run's undo releases the vehicles
local appliedVehicles = {} -- EntityID of each vehicle given an autonomous command, keyed by hash
local scanTimer = 0        -- Accumulates delta time until the next scan interval
local logTimer = 0         -- Throttles scan summary logs to once per second

-- =========================================================================
-- ### INI OVERRIDES ###
-- Each entry is snapshotted on Start and written back on Stop. An entry with `scale`
-- is multiplied by the speed multiplier; an entry with `timelapse` is set to that value.
-- An option the game does not expose is neither written nor restored.
-- =========================================================================

-- Spawning:
--   DespawnLastSeenMinTime: Seconds an entity persists after leaving view. Lower = faster cleanup.
--   SpawnLimit: Per-tick spawn batch size (default 1).
-- Collision recovery:
--   DisableCollisionDamage: Prevents crumpling so vehicles keep moving after bumps.
--   DisposeOnOverlap: Auto-despawns wedged/overlapping vehicles.
--   SafetyMeasure: Extra collision avoidance precautions.
--   SafetyMeasureDistance: Buffer distance (metres) for safety checks.
local iniOverrides = {
    -- Vehicle force-move caps
    { group = "Vehicle", key = "ForceMoveToMaxLinearSpeed",  type = "float", scale = 1.0 },
    { group = "Vehicle", key = "ForceMoveToMaxAngularSpeed", type = "float", scale = 0.5 },
    -- Spawning
    { group = "Crowd",   key = "DespawnLastSeenMinTime",     type = "float", timelapse = 5.0 },
    { group = "Crowd",   key = "SpawnLimit",                 type = "int",   timelapse = 1 },
    -- Collision recovery
    { group = "Vehicle", key = "DisableCollisionDamage",     type = "bool",  timelapse = true },
    { group = "Traffic", key = "DisposeOnOverlap",           type = "bool",  timelapse = true },
    { group = "Traffic", key = "SafetyMeasure",              type = "bool",  timelapse = true },
    { group = "Traffic", key = "SafetyMeasureDistance",      type = "float", timelapse = 2.0 },
}

-- GameOptions getter/setter suffix for each entry type.
local TYPE_SUFFIX = { float = "Float", int = "Int", bool = "Bool" }

local function PathOf(entry)
    return entry.group .. "/" .. entry.key
end

--- Reads an option, or nil if the game does not expose it.
local function ReadOption(entry)
    local ok, val = pcall(GameOptions["Get" .. TYPE_SUFFIX[entry.type]], entry.group, entry.key)
    if ok and val ~= nil then return val end
    return nil
end

local function SameValue(entry, a, b)
    if a == nil or b == nil then return false end
    if entry.type == "float" then return math.abs(a - b) < 0.01 end
    return a == b
end

--- Writes an option and reads it back. Returns true if the game kept the value.
local function WriteOption(entry, value)
    local ok, err = pcall(GameOptions["Set" .. TYPE_SUFFIX[entry.type]], entry.group, entry.key, value)
    if not ok then
        Log.Error("Traffic Frenzy could not write %s = %s: %s", PathOf(entry), tostring(value), tostring(err))
        return false
    end

    local readback = ReadOption(entry)
    if SameValue(entry, readback, value) then
        Log.Debug("Traffic Frenzy: %s = %s", PathOf(entry), tostring(value))
        return true
    end
    Log.Warn("Traffic Frenzy: %s did not keep its value (wrote %s, read back %s)",
        PathOf(entry), tostring(value), tostring(readback))
    return false
end

-- =========================================================================
-- ### APPLY / RESTORE ###
-- =========================================================================

--- Applies every override the game exposes and records an undo for each one it kept.
--- Scaled entries are capped at 20x their current value.
local function ApplyINI(speedMult)
    Log.Debug("Traffic Frenzy: applying INI overrides for %.1fx", speedMult)
    for _, entry in ipairs(iniOverrides) do
        local before = ReadOption(entry)
        if before == nil then
            Log.Warn("Traffic Frenzy: %s is not readable, left unchanged", PathOf(entry))
        else
            local value = entry.timelapse
            if entry.scale then
                value = math.min(before * speedMult * entry.scale, math.abs(before) * 20.0)
            end
            if not SameValue(entry, before, value) and WriteOption(entry, value) then
                -- A value changed mid-run belongs to whoever changed it.
                Undo.Push("ini:" .. PathOf(entry), function()
                    if SameValue(entry, ReadOption(entry), value) then WriteOption(entry, before) end
                end)
            end
        end
    end
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
--- The caller has already checked that the vehicle is untracked and has an AI component.
--- @param vehicle VehicleObject The vehicle entity to command
--- @param aiComp AIComponent The vehicle's AI component
--- @param entId string The tracking key for this vehicle
--- @param speedMult number The speed multiplier (frenzySpeedMult, e.g. 1.5 to 20.0)
local function ApplyAutonomousDrive(vehicle, aiComp, entId, speedMult)
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

    -- Send the command via the AI component
    -- Clear existing spline-following commands so the autonomous command takes priority
    aiComp:CancelOrInterruptCommand(CName.new("AIVehicleOnSplineCommand"), true, true)
    aiComp:CancelOrInterruptCommand(CName.new("AIVehicleJoinTrafficCommand"), true, true)
    aiComp:SetInitCmd(cmd)

    -- Also queue the command as an event for redundancy
    local evt = AICommandEvent.new()
    evt.command = cmd
    vehicle:QueueEvent(evt)

    appliedVehicles[entId] = vehicle:GetEntityID()
    Log.Debug("Traffic Frenzy: drive command on %s (%.0f -> %.0f m/s)", entId, currentSpeed, targetMaxSpeed)
end

-- =========================================================================
-- ### VEHICLE SCANNER ###
-- =========================================================================

--- Scans for nearby vehicles using the TargetingSystem and applies autonomous
--- drive commands to any that have an active AI component.
--- Uses TargetingSet.Complete for a full 360-degree search (not frustum-only).
---
--- TargetSearchQuery returns at most 128 parts. Mask 8 (Obj_Device) covers vehicles.
--- @param speedMult number The speed multiplier
local function ScanAndApply(speedMult)
    local player = Game.GetPlayer()
    if not player then return end

    local searchQuery = TargetSearchQuery.new()
    searchQuery.maxDistance = 800
    searchQuery.testedSet = "Complete" -- 360-degree scan, not frustum-only
    searchQuery.filterObjectByDistance = true
    searchQuery.ignoreInstigator = true
    searchQuery.searchFilter = Game.TSF_Any(8)

    local success, parts = Game.GetTargetingSystem():GetTargetParts(player, searchQuery)
    if not success or not parts then return end

    -- Diagnostic counters for this tick
    local vehiclesFound = 0
    local alreadyApplied = 0
    local skippedParked = 0
    local newlyApplied = 0

    for _, part in ipairs(parts) do
        local entity = part:GetComponent():GetEntity()
        if entity and entity:IsVehicle() then
            vehiclesFound = vehiclesFound + 1
            local entId = tostring(entity:GetEntityID().hash)

            if appliedVehicles[entId] then
                alreadyApplied = alreadyApplied + 1
            else
                -- Active traffic has an AI component; parked and decoration cars do not.
                -- GetCurrentSpeed() cannot tell them apart, because crowd vehicles report ~0.
                local aiComp = entity:GetAIComponent()
                if aiComp then
                    ApplyAutonomousDrive(entity, aiComp, entId, speedMult)
                    newlyApplied = newlyApplied + 1
                else
                    skippedParked = skippedParked + 1
                end
            end
        end
    end

    -- Log scan summary once per second (not every tick)
    if newlyApplied > 0 or logTimer >= 1.0 then
        Log.Debug("Traffic Frenzy scan: %d parts, %d vehicles (new %d, tracked %d, no AI %d)",
            #parts, vehiclesFound, newlyApplied, alreadyApplied, skippedParked)
        logTimer = 0
    end
end

-- =========================================================================
-- ### PUBLIC API ###
-- =========================================================================

--- Hands every commanded vehicle that still exists back to the traffic system.
local function ReleaseVehicles()
    local released = 0
    for _, entityID in pairs(appliedVehicles) do
        local vehicle = Game.FindEntityByID(entityID)
        local aiComp = vehicle and vehicle:GetAIComponent()
        if aiComp then
            aiComp:CancelOrInterruptCommand(CName.new("AIVehicleDriveToPointAutonomousCommand"), false, true)
            aiComp:SendCommand(AIVehicleJoinTrafficCommand.new())
            released = released + 1
        end
    end
    Log.Debug("Traffic Frenzy: released %d vehicles", released)
    appliedVehicles = {}
    running = false
end

--- Called when the time-lapse starts with Traffic Frenzy enabled.
--- Applies the INI overrides and records the undo that ends Traffic Frenzy.
--- @param speedMult number The frenzySpeedMult from the UI slider
function VehicleDilation.Start(speedMult)
    Log.Debug("Traffic Frenzy starting at %.1fx", speedMult)
    appliedVehicles = {}
    scanTimer = 0
    logTimer = 0
    running = true
    -- Pushed before the INI entries, so it runs after them.
    Undo.Push("trafficFrenzy", ReleaseVehicles)
    ApplyINI(speedMult)
end

function VehicleDilation.IsRunning()
    return running
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
        ScanAndApply(speedMult)
    end
end

return VehicleDilation
