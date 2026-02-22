# Vehicle Time Dilation Alignment Strategy

## 1. The Core Engine Limitation

As established in `DLL_Research.md`, Cyberpunk 2077's native time dilation system (`TimeDilationHelper.SetIndividualTimeDilation()`) does **not** accelerate vehicle movement. The game's proprietary Havok physics engine forces vehicles to run synchronously with the global game tick to prevent cars from vibrating through the ground or clipping through walls.
Any true "engine-level" time dilation for vehicles requires injecting raw C++ via a RED4ext plugin to bypass the CDPR speed limit clamps. We are purposely avoiding this route to maintain mod stability and accessibility without requiring manual C++ updates every game patch.

## 2. The Objective

Since native Time Dilation on vehicles is impossible, our goal is to **"simulate"** time dilation for vehicles during a time-lapse.
When the time-lapse begins, traffic should look like it functions normally (obeying road rules, stopping at lights, not crashing indiscriminately), just at a progressively faster pace equivalent to the time-lapse multiplier.

## 3. Our Toolset (The Strategy)

Based on our research into reference mods (`Traffic Unjammed`, `CorpoRatCrowdTweaker`, and `Psycho Crowds and Traffic Improvements`), we have access to a suite of `.ini` parameters that govern traffic physics and AI behavior logic.
We can use CET (Lua) to dynamically override these internal INI settings **while the time-lapse is running**, and restore them back to normal when it stops.

### Key Traffic Variables Identified for Manipulation

From `Psycho Crowds` and `CorpoRatCrowdTweaker`:

- **`[Traffic] MinDriveSpeed`**: Forces traffic to maintain a higher minimum driving speed.
- **`[Traffic] GreenWaveAveragePredictedCarSpeed`**: Makes traffic assume it can drive faster between traffic lights.
- **`[Traffic] leftLaneSpeedIncrease`**: Multiplier for passing lanes.
- **`[CrowdMovement] AngularSpeedFactor` / `RotationSpeedFactor`**: Can we make cars turn corners faster so they don't slow down the simulation?
- **`[Vehicle] ForceMoveToMaxLinearSpeed` / `ForceMoveToMaxAngularSpeed`**: Hard caps on vehicle speed. (CorpoRats uses `fForceMoveToMaxLinearSpeed = 30.000000`).
- **`[Crowds] MaxSpeedDrivingOnPavement` / `MinimumSpeedForKnockdownByCar`**: Potential crash/safety variables to tweak so fast cars don't instantly kill pedestrians at intersections.

## 4. The Implementation Execution Plan

1. **Dynamic INI Sweeping**: When `VehicleDilation.Start(multiplier)` is called, we will calculate temporarily inflated values for the variables listed above based on the `multiplier`.
2. **Apply via GameOptions**: We will use Lua's `GameOptions.SetFloat(group, setting, value)` (or similar CET API) to push these overrides into the live game engine.
3. **Restoration**: When `VehicleDilation.Stop()` is called, we will restore the original unmodified `.ini` values so normal gameplay is completely unaffected.
4. **Traffic Unjammed Synergy**: (Optional) If cars start piling up because they are moving too fast for the engine to process their stopping logic, we can borrow the `ChangeMoveType("normal")` poke from Traffic Unjammed to force broken traffic nodes to clear out.

## Clarifying Questions for You

1. Does this strategy align with your vision of simulating the effect using INI overrides?
2. `GameOptions.SetFloat` is the typical CET method for manipulating these variables at runtime, but some physics settings require a game reload to take effect. If we find that `MinDriveSpeed` doesn't apply instantly to currently spawned cars, we may still need the Redscript hook to force a refresh on the existing cars. Does that sound acceptable?
3. Since we are simulating high speeds, vehicles will travel much further distances in the same amount of real-time. Do we want to lower the `DespawnLastSeenMinTime` so that cars despawn faster when they exit the player's view to save engine memory during the time-lapse?
