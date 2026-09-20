-- ======================================================================================
-- Simple Time-lapse - GameTimeCurve Module
-- Mod Version: 2.0.0
-- Author:       Spuddeh
--
-- DESCRIPTION:
-- The game clock gains timeSystem.settings.realTimeMultiplier (8) game seconds per
-- simulation second, scaled by time_of_the_day_to_timescale in game_time.curveset.
-- The multiplier is read from TweakDB; the curve points are the vanilla file's, so a
-- mod that replaces the curve makes every prediction here inaccurate.
-- ======================================================================================

local GameTimeCurve = {}

local VANILLA_RATE = 8.0

-- { hour, scale }: a key, then two Bezier handles, then the next key. Each segment is
-- evaluated with t linear between its two keys.
local POINTS = {
    { -1.0, 1.0 }, { -0.666667, 1.0 }, { -0.333333, 1.0 },
    { 0.0, 1.0 }, { 1.666667, 1.02124596 }, { 2.763781, 1.01018703 },
    { 5.035597, 1.01012802 }, { 5.672537, 0.89902699 }, { 5.709134, 0.813943982 },
    { 7.0, 0.724349976 }, { 7.913084, 0.765752971 }, { 8.30565, 0.839778006 },
    { 9.035597, 0.999068975 }, { 14.10007, 1.01739001 }, { 15.8187, 1.0 },
    { 17.4394, 1.00958 }, { 17.943, 0.98129 }, { 17.944, 0.70486 },
    { 19.8457, 0.73201 }, { 21.071, 0.74363 }, { 21.072, 0.99992 },
    { 22.0328, 1.00261 }, { 22.6653, 0.9992 }, { 22.6663, 0.99227 },
    { 24.0, 1.0 }, { 24.333333, 0.99841 }, { 24.666667, 0.99841 },
    { 25.0, 1.0 },
}

--- The curve's scale at an hour of day (0 to 24).
function GameTimeCurve.Scale(hour)
    for i = 1, #POINTS - 3, 3 do
        local a, b, c, d = POINTS[i], POINTS[i + 1], POINTS[i + 2], POINTS[i + 3]
        if hour >= a[1] and hour <= d[1] then
            local t = (hour - a[1]) / (d[1] - a[1])
            local u = 1 - t
            return u * u * u * a[2] + 3 * u * u * t * b[2] + 3 * u * t * t * c[2] + t * t * t * d[2]
        end
    end
    return 1.0
end

-- simAtMinute[m + 1] = simulation seconds from 00:00 to game minute m. Built on first use,
-- because TweakDB is not readable while the mod's files load.
local simAtMinute = nil
local DAY_SIM = 0

local function BuildTable()
    local ok, rate = pcall(function() return TweakDB:GetFlat("timeSystem.settings.realTimeMultiplier") end)
    if not ok or type(rate) ~= "number" or rate <= 0 then rate = VANILLA_RATE end

    simAtMinute = { 0 }
    for m = 1, 1440 do
        simAtMinute[m + 1] = simAtMinute[m] + 60 / (rate * GameTimeCurve.Scale((m - 0.5) / 60))
    end
    DAY_SIM = simAtMinute[1441]
end

local function SimAt(daySeconds)
    local minute = math.min(math.floor(daySeconds / 60), 1439)
    local f = daySeconds / 60 - minute
    return simAtMinute[minute + 1] + f * (simAtMinute[minute + 2] - simAtMinute[minute + 1])
end

local function DaySecondsAt(sim)
    local lo, hi = 0, 1439
    while lo < hi do
        local mid = math.ceil((lo + hi) / 2)
        if simAtMinute[mid + 1] <= sim then lo = mid else hi = mid - 1 end
    end
    local span = simAtMinute[lo + 2] - simAtMinute[lo + 1]
    return (lo + (sim - simAtMinute[lo + 1]) / span) * 60
end

--- Game seconds the clock gains from `startSeconds` (any total, only the time of day is used)
--- over `simSeconds` of simulation time, which is real seconds times the dilation.
function GameTimeCurve.GameSecondsGained(startSeconds, simSeconds)
    if not simAtMinute then BuildTable() end
    local start = startSeconds % 86400
    local target = SimAt(start) + simSeconds
    local days = math.floor(target / DAY_SIM)
    return days * 86400 + DaySecondsAt(target - days * DAY_SIM) - start
end

return GameTimeCurve
