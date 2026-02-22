# Simple Time-lapse: Complete Research Summary (Feb 16–22, 2026)

Compiled from 5 conversations to prevent knowledge loss.

---

## 🔴 Approaches CONFIRMED DEAD

### 1. Native `TimeDilationHelper.SetIndividualTimeDilation()` on Vehicles

**Conversations:** `4a6d12d7`, `cafdb708`

- `VehicleObject` does **not** inherit `gameTimeDilatable`.
- The Havok physics RigidBody ignores the dilation multiplier and runs synchronously with the global game tick.
- **Only solvable via:** A custom C++ RED4ext DLL that hooks `vehicle::PhysicsData::Recalculate` (see `DLL_Research.md`). Requires reverse-engineering offsets that break every game update.

### 2. `SetLinearVelocity` / Physics Force Override

**Conversation:** `cafdb708`

- Attempted forcing velocity directly on vehicle physics bodies.
- **Result:** Failed/Skipped — engine immediately re-clamps.

### 3. `Teleport` Translation Delta Manipulation

**Conversation:** `cafdb708`

- Attempted to move vehicles forward by delta-teleporting them each frame.
- **Result:** Visually unacceptable — cars stutter/snap rather than smoothly moving.

### 4. `AIVehicleDriveToPointAutonomousCommand` Injection ("Traffic Frenzy")

**Conversations:** `4a6d12d7`, `7b2387be`

- Injected a new "drive indefinitely" command with `driveDownTheRoadIndefinitely = true` and scaled `maxSpeed`/`minSpeed`.
- **Result:** Cars DID speed up, but:
  - ❌ Parked cars wake up and start driving
  - ❌ Cars ignore lane assignments and traffic lights
  - ❌ Requires cancelling existing spline commands (`AIVehicleOnSplineCommand`, `AIVehicleJoinTrafficCommand`)
  - **Verdict:** Too chaotic. Abandoned in favor of hooking existing commands.

### 5. `AIDriveToNodeCommandHandler` Redscript Hook (speedInTraffic Multiply)

**Conversations:** `7b2387be`, `1adb3643` (current)

- Wrapped `AIDriveToNodeCommandHandler.UpdateCommand` in Redscript to multiply `speedInTraffic` by our multiplier.
- The hook fires, values are modified, logs confirm the override.
- **Result:** Ambient traffic ignores the modified `speedInTraffic`. The value is read by the behavior tree but the actual movement speed is dictated by the underlying spline/marble system, not by this parameter.

### 6. `CrowdMemberComponent.ChangeMoveType()` "Poke"

**Conversation:** `1adb3643`

- Bounced vehicle state between `"stop"` and `"normal"` to force AI command re-evaluation.
- **Result:** No effect on speed. Same as what Traffic Unjammed uses for unjamming, not speed control.

### 7. `GameOptions` INI Overrides (MinDriveSpeed, ForceMoveToMaxLinearSpeed, etc.)

**Conversation:** `1adb3643` (current)

- Dynamically set `Traffic/MinDriveSpeed` to 80, `Vehicle/ForceMoveToMaxLinearSpeed` to 300, etc.
- All writes verified via read-back. Engine accepts the values.
- **Result:** No visible effect. These are boundary constraints (floors/ceilings), not target speeds. The actual driving speed is determined by road spline data.

### 8. `Traffic/SkippingTimeTimeDilation`

**Conversation:** `1adb3643` (current)

- Set to 500.0 via CET console.
- **Result:** Zero effect. Only applies during the game's built-in time skip (sleeping/waiting), not during dilation.

---

## 🟡 Partially Working / Promising Leads

### `CrowdMovement/NoSpeedUpTime` = `false`

**Conversation:** `7b2387be`

- Setting `GameOptions.SetBool("CrowdMovement", "NoSpeedUpTime", false)` during dilation mode **does** make pedestrians and some vehicle animations respect global time dilation.
- **Current status:** Already implemented in `Core.lua` via `pcall`. Some game versions don't expose this setting, hence the safe wrapper.
- ⚠️ **Caveat:** May not apply to all vehicle types. Needs more testing to determine exactly what it affects. This was noted as successful in the walkthrough but the user's perception was "small impact."

### `DilationClamp` / `DilationLimit` (CrowdMovement)

**Conversation:** `1adb3643` (current)

- Default is `-1.0` (unlimited/disabled). Found in CorpoRatCrowdTweaker's commented-out defaults.
- Writes verified, but no visible testing done in isolation yet.
- **Status:** Untested in isolation.

---

## 🟢 Working Features (Non-Vehicle)

- **Time Dilation (Mode 0):** Global `SetTimeDilation` works perfectly for environment, sky, lighting.
- **Clock Advancement (Mode 1):** `SetGameTimeBySeconds` integration for time-skip without dilation.
- **Air Traffic Toggle:** `Game.GetQuestsSystem():SetFactStr("air_traffic_off", 1)` — works.
- **Crowd Toggle:** `GameOptions.SetBool("Crowd", "Enabled", false)` — works.
- **HUD hide/restore, head bobbing, camera lock:** All working.

---

## 📋 Unexplored Avenues

1. **`ApplyImpulse` or direct physics forces** (listed in `4a6d12d7` task but never attempted)
2. **`TrafficSystem` global lane speed** (searched for but never found an accessible API)
3. **`AIVehicleFollowCommand` catch-up mechanics** (noted but never researched)
4. **`AIVehicleRacingCommand` aggressive driving** (noted but never researched)
5. **`VehicleAI/PerceptionNumSweeps`** — increase AI scan rate so fast cars don't miss obstacles (noted in traffic_ai_report but never tested)
6. **Modifying spline/road speed limit data** via TweakDB or Archive edits

---

## 🎨 Tilt-Shift / Gaussian Blur (Separate Feature)

**Conversation:** `d1e7eefc`

- Native Lua/Redscript **cannot** create a custom Gaussian blur on the game world.
- `inkBoxBlurEffect` only blurs UI widgets, not the scene.
- Status effects (Drunk, Stunned) apply pre-baked visual packages — not a clean blur.
- **Verdict:** Use ReShade for tilt-shift. Not implementable natively.

---

## 📐 Technical Notes

- **TargetingSystem vs SpatialQueriesSystem:** For finding vehicles in a radius, `TargetingSystem` with `TargetingSet.Complete` is the correct tool. `SpatialQueriesSystem` returns too much noise (terrain, walls).
- **`GameOptions.GetFloat` read-back:** Confirmed working. Engine accepts and stores the values. The issue is semantic — the settings don't control what we thought.
- **Git snapshot taken** before the Traffic Simulation refactor (`7b2387be` walkthrough confirms this).
