-- ======================================================================================
-- Simple Time-lapse - TimingProbe Module
-- Mod Version: 2.0.0
-- Author:       Spuddeh
--
-- DESCRIPTION:
-- At the Debug log level, logs one line per real second of a Simulation run comparing
-- three clocks: real time (the CET frame delta), the engine's simulation time
-- (TimeSystem.GetSimTime) and the game clock (TimeSystem.GetGameTimeStamp).
-- GetGameTimeStamp is a single-precision float, so only whole-window totals are reliable.
-- ======================================================================================

local Log = require("Modules/Log")

local TimingProbe = {}

local WINDOW_SECONDS = 1.0
local GAP_SECONDS = 0.25 -- a frame this long means onUpdate stopped, or the game hitched

local lastSim = nil
local lastGame = nil
local window = nil

local function ResetWindow()
    window = { frames = 0, real = 0, sim = 0, game = 0, maxReal = 0, maxSim = 0, short = 0 }
end

function TimingProbe.Start()
    lastSim = nil
    lastGame = nil
    ResetWindow()
end

--- @param delta number Real seconds since the previous frame
--- @param dilation number The dilation the run asked for
function TimingProbe.Update(delta, dilation)
    if not Log.IsDebug() then return end
    local ts = Game.GetTimeSystem()
    if not ts then return end

    local sim = EngineTime.ToDouble(ts:GetSimTime())
    local game = ts:GetGameTimeStamp()

    if lastSim then
        local simStep = sim - lastSim
        if delta > GAP_SECONDS then
            Log.Debug("Timing gap: one frame covered %.2f s real, %.2f s sim, %.1f s game",
                delta, simStep, game - lastGame)
        end
        window.frames = window.frames + 1
        window.real = window.real + delta
        window.sim = window.sim + simStep
        window.game = window.game + (game - lastGame)
        if delta > window.maxReal then window.maxReal = delta end
        if simStep > window.maxSim then window.maxSim = simStep end
        -- A frame is short when the simulation gained less than 95% of real time times the dilation.
        if simStep < 0.95 * dilation * delta then window.short = window.short + 1 end

        if window.real >= WINDOW_SECONDS then
            local t = ts:GetGameTime()
            local gamePerSim = window.sim > 0 and window.game / window.sim or 0
            Log.Debug("Timing %02d:%02d | %.0f fps, longest frame %.1f ms | sim %.2fx real (asked %.1fx), longest step %.1f ms, %d of %d frames short | game %.3fx sim, %.2fx real",
                t:Hours(), t:Minutes(),
                window.frames / window.real, window.maxReal * 1000,
                window.sim / window.real, dilation, window.maxSim * 1000, window.short, window.frames,
                gamePerSim, window.game / window.real)
            ResetWindow()
        end
    end

    lastSim = sim
    lastGame = game
end

return TimingProbe
