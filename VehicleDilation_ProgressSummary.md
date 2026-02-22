# Simple Time-lapse: Autonomous Traffic Override Progress

## Current Objective

Apply a global speed multiplier to all ambient driven vehicles (street traffic) when the time-lapse is active, allowing them to drive realistically at high speed without using experimental pathing overrides.

## What We Have Done

1. **Redscript AI Hook:** Created `SimpleTimelapseTrafficOverrides.reds`. We wrapped `AIDriveToNodeCommandHandler.UpdateCommand` to intercept traffic speed calculations and apply a multiplier.
2. **Redscript System Bridge:** Created `TimelapseTrafficSystem` to hold the `IsActive` state and `SpeedMultiplier`, allowing Lua to easily toggle the behavior globally.
3. **Lua State Management:** Updated `Core.lua` and `VehicleDilation.lua` to set the Redscript system state on Start/Stop instead of running an `Update` loop every frame.
4. **800m Radar Scan:** Restored a highly accurate `TargetSearchQuery` loop in Lua that successfully bypasses the camera frustum limits and identifies all vehicles within 800m using Object Masks 2 and 8.
5. **The "Poke" Attempt:** Tried to force existing vehicles to re-evaluate their AI commands by calling `crowdComp:ChangeMoveType("stop")` followed by `"normal"`.

## What We Learned

1. **Redscript Logging Gotchas:** Native `Log` declarations cannot be packaged within modules, and if other mods (like Codeware) define them, we must use `LogChannel` to avoid overload collisions.
2. **Scanner Success:** The 800m Lua scanner works perfectly. In our last test, it found 87 vehicles in the area.
3. **The Engine Bottleneck:** `AIDriveToNodeCommandHandler.UpdateCommand` is apparently only evaluated *once* when a vehicle begins its drive action or receives a new command.
4. **Poke Failure:** Even though we successfully sent `ChangeMoveType` to 87 vehicles, none of them triggered our Redscript logging hook. This means `ChangeMoveType` does *not* force them to rebuild or re-evaluate their current `AIDriveToNode` command parameters.
5. **The Spawning Problem (Caught by User):** Poking vehicles from Lua on `Start` only affects cars currently on the map. Vehicles that stream in *during* the time-lapse would not get poked (though theoretically, if they evaluate `UpdateCommand` upon spawning, they might automatically grab the 10x multiplier—we need to test this!)

## Next Steps for Tomorrow

1. **Test Spawns:** We need to confirm if vehicles that spawn *after* the time-lapse has started naturally pick up the 10x multiplier because they are evaluating `UpdateCommand` for the first time.
2. **New Poke Vector:** Since `ChangeMoveType` didn't work, we need a stronger "poke" for existing vehicles. In our old Lua script, we used `aiComp:CancelOrInterruptCommand(CName.new("AIVehicleOnSplineCommand"), true, true)`. We should try flushing their current command naturally to force a pure reset.
3. **Alternative Redscript Hooks:** If `AIDriveToNodeCommandHandler` is too stubborn, we should search the NativeDB / Redmodding Wiki for other crowd or vehicle behavior hooks that run continuously (like checking how the game calculates current safe speeds for traffic).
4. **Resume Command:** Look deeper into how `Traffic Unjammed` forces cars to start moving again after being stuck. There might be a specific `crowdComp` reset function we missed.
