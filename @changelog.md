### [2026-09-20] Session - the Camera section, fixed against a run
- **[Simple Time-lapse] XUtilsFx.lua v2.0.0**:
    - [Fix] The camera transform is reached through the scriptable system's `GetCamera()`, not `XUtils.Camera`. XUtils exports only `CameraController`, `CameraShake` and `CameraLens`; its `Camera` module is internal, so the guard on it returned before anything ran. The shake pushed no undo and logged nothing, which is how a missing export looks.
    - [Fix] `StartShake` is `StartStaticCamera`, and it takes the transform over for a roll as well as a shake. Nothing else writes a static camera, so a roll set through `FreeFlyController` had nobody to apply it.
    - [Fix] The base transform is read on the first frame that answers rather than at start. The camera entity spawns after the session does, so a start-time read returns an empty string.
    - [New] `ApplyFlyFeel` logs the sensitivity asked for beside the one `GetSensitivity` reports back, because the setter is relative and a silent clamp is otherwise invisible.
- **[Simple Time-lapse] UI.lua v2.0.0**:
    - [Fix] Depth of Field sets `xuCamera` through an `onChange`, and the Camera checkbox draws disabled while the lens is on. It read as ticked-off with its settings showing.
    - [Fix] The roll tooltip no longer promises Q and E. Those keys reach a free-fly camera through XUtils' own consumer input modes, which this mod does not register.

### [2026-09-20] Session - the Camera section
- **[Simple Time-lapse] XUtilsFx.lua v2.0.0**:
    - [Refactor] `StartLens` is `StartCamera`, and the lens config is attached only when `xuLens` is set. The camera session no longer implies depth of field, so a moving shot can leave the picture alone. `XUtilsFx.UsesCamera(s)` is true for either, because the lens needs the session.
    - [New] `ApplyFlyFeel` sets look sensitivity, roll and pitch lock on the session that has just started. Sensitivity has no absolute setter: `AdjustSensitivity` takes a number of 0.1 steps, so it resets first and adjusts by the difference.
    - [New] `StartShake` builds a `CameraShake` from an XUtils preset name and an intensity, records the parked transform, and `XUtilsFx.Update` writes `Apply`'s result through `XUtils.Camera.setTransform` each frame. Its undo puts the camera back before the session's undo stops it.
    - [New] `XUtilsFx.ShakeReachesCamera(s)` gates the shake to a static camera. XUtils applies a shake on its playback, timeline and point cloud paths only; the free-fly path calls `m_freeFly.Update(delta, m_camera)` every frame and overwrites anything written from Lua. `m_freeFly.Update` is itself gated on `!IsInputSuppressed()`, which is what makes the static path free.
    - [New] `XUtilsFx.ShakePresets()` reads `CameraShake.GetPresetNames()` at call time rather than listing them, so a user preset appears without a change here.
- **[Simple Time-lapse] UI.lua v2.0.0**:
    - [New] A Camera section above Lens in Cinema: the camera toggle, mode, fly speed, stay level, look sensitivity, unlock pitch, roll, and the shake preset and strength. The shake controls sit in `ImGui.BeginDisabled` with a line saying it reaches a static camera only.
    - [Refactor] The shake preset is a `Controls.StringCombo`, so the saved value survives XUtils reordering or adding a preset.
- **[Simple Time-lapse] Core.lua v2.0.0**:
    - [Refactor] `XUtilsFx.Update` takes the frame delta, which the shake needs.

### [2026-09-20] Session
- **[Simple Time-lapse] XUtilsFx.lua v2.0.0**:
    - [New] `xuCameraMode` picks how the lens camera behaves. Static pauses the free-fly input. Free fly leaves the input live, sets `proximityTeleport` so V is brought along once the camera is 30 m clear and the world keeps streaming, and passes `freeFly = { baseSpeed = xuFlySpeed, movementMode = xuFlyLevel and "global" or "relative" }`.
    - [Fix] The camera session's `playerMode` carries `invisible = true` in both modes. The session renders from outside the body and the first-person mesh has no head, so V walking out from under a static camera showed a headless body. `invisible` toggles visual components only, so anything that moves V is still heard. Free fly uses proximity teleport for that reason, not a per-frame one.
    - [New] Free fly resolves `playerMode.restrictions`, XUtils' own block of GameplayRestriction effects, instead of this mod's three locks. `XUtilsFx.IsFreeFly(settings)` is the single test.
- **[Simple Time-lapse] Core.lua v2.0.0**:
    - [Fix] `CameraUtils.LockPlayer` is skipped on a free-fly lens run, so NoMovement and NoCombat are not applied from two places.
- **[Simple Time-lapse] UI.lua v2.0.0**:
    - [New] Camera mode combo, Fly Speed slider (0.5 to 50 m/s) and Stay Level checkbox in the lens panel.
    - [New] Lock Movement, Lock Weapons and Lock Camera render inside `ImGui.BeginDisabled` on a free-fly lens run, under a line saying XUtils holds them. The run summary drops their chips and shows the camera mode instead.
    - [Refactor] The weather sequence list is `wu.DragDrop.list` with `showHandle = true` and `handleIcon = "DragHorizontalVariant"`, the grip a reorderable `Lists.render` draws, replacing the per-row up and down buttons. The grip is the only drag source, so the row's combo, slider and remove button keep their clicks.

### [2026-09-19] Session
- **[Simple Time-lapse] HudUtils.lua v2.0.0**:
    - [Fix] The HUD is hidden by hiding the HUD layer's virtual window through Codeware's `inkSystem`, which makes Codeware a hard dependency for HUD hiding. The UI context stack cannot do it: an `Empty` context only holds while it is on top, mounting a vehicle pushes `VehicleMounted` above it natively, a duplicate push and a pop below the top are both ignored, and a context left above `VehicleMounted` at exit stranded the car context on foot.
    - [Fix] Only the layer's `Root` canvas is hidden, not the whole layer window. Other mods parent overlays onto the window beside `Root` - XUtils' cinematic bars, fade, guides and crosshair among them - and hiding the window took those with it.
    - [Removed] The `/interface/hud/vehicle_hud` write, its launch repair, its saved keys and the HUD probe. The layer window covers the vehicle HUD, so none of them has anything left to do.
- **[Simple Time-lapse] XUtilsFx.lua (new) v2.0.0**:
    - [New] A Cinema section, drawn only when XUtils is installed: depth of field through an XUtils camera with five lens presets over the full lens settings, a weather sequence, cinematic bars and fades in and out.
    - [New] The weather sequence splits the run evenly, by percent per state, or by game hours per state, and resets to natural weather on Stop.
    - [New] Bars and fades draw on the HUD layer beside `Root`, so the HUD hide leaves them up. The closing fade's undo is pushed before every other change of the run, so the view returns after everything else is restored.
- **[Simple Time-lapse] Settings.lua / Presets.lua v2.0.0**:
    - [Fix] Settings and presets copy tables deeply. The weather list is the first table setting, and a shared reference let an edit change the defaults and the saved presets with it.
- **[Simple Time-lapse] Core.lua / UI.lua v2.0.0**:
    - [New] Auto Speed for Clock mode works the speed out from a start time, an end time, an optional number of days later and the run's length. The run always sets its start time, and the clock stops on the end time rather than a frame past it. Start is refused with no set duration, or when the speed needed is over the ceiling.
    - [New] The Clock ceiling is three game hours per real second and the unit row goes to 3 hours. Auto Speed itself has no ceiling; the run's length decides it.
    - [New] Start and end times share one hour / minute / AM-PM input, both labelled, and the quick times apply to whichever is being set.

### [2026-09-16] Session
- **[Simple Time-lapse] Core.lua / UI.lua v1.3.0**:
    - [Fix] A run reads mode, speed, dilation and Traffic Frenzy speed from `mod.run`, saved in `ApplyStart`. Switching to Clock mid-run wrote a stale `startTotalSeconds` to the clock; a speed change miscounted `elapsedTime` and the run stats.
    - [New] Mode, speed slider, speed input, speed presets and the Vehicle Speed Multiplier are wrapped in `ImGui.BeginDisabled` while `mod.isActive`.
    - [Fix] `ExecuteStart` runs `ApplyStart` in `pcall`; a throw runs `Undo.RunAll` instead of leaving the player locked with no Stop button. `Core.DisableAirTraffic` and the air-traffic re-apply nil-check `Game.GetQuestsSystem()`.
    - [Fix] `RefusedInCombat` is checked again in `ExecuteStart`, so combat entered during the countdown refuses the run.
    - [Fix] `lastRunStats.factor` is nil under one expected game second; the Debug tab and the Stop log line read "n/a" instead of a ratio of rounding noise.
- **[Simple Time-lapse] AudioUtils.lua (new) v1.3.0**:
    - [New] `Mute` turns `RadioportVolume`, `CarRadioVolume`, `MusicVolume` and `SfxVolume` to 0 per the `muteRadio` / `muteMusic` / `muteSfx` settings, each with its own undo that restores only a level still at 0.
    - [New] `ForceRestore` panic button on the Debug tab puts any of those sliders sitting at 0 back to 100.
- **[Simple Time-lapse] Notifications.lua (new) v1.3.0**:
    - [New] `Silence` sends `MakeNotificationQueueSilentEvent` through `UISystem.QueueEvent` for the Generic, JournalNotification and PhoneNotification queues, with one undo that gives all three back.
    - [New] `Init` observes `PhoneSystem.OnTriggerCall` and plays `ui_phone_incoming_call_stop` / `ui_phone_initiation_call_stop` while a run is active, which is how `OnTalkingTriggerRequest` ends a ring. The call itself is untouched.
    - [New] `ForceRestore` is wired into the Restore Audio panic button.
- **[Simple Time-lapse] CameraUtils.lua v1.3.0**:
    - [New] `lockWeapons` applies `GameplayRestriction.NoCombat` on its own; `lockMovement` applies only `NoMovement`. `NoCombat` forces empty hands, which is what the game uses to silence the Radioport.
- **[Simple Time-lapse] VehicleDilation.lua v1.3.0**:
    - [Refactor] Drive-command comments state the speed limits rather than the values they replaced.

- **[Simple Time-lapse] UI.lua v2.0.0 - the window redesign**:
    - [Refactor] The window is a Window Utils tab bar - Shot / Scene / Audio / Player / Debug - with the sections in a button column beside their pane, so the tab strip no longer eats width. Controls, section headers, status bars, text colours and button styles all come from the library.
    - [New] A status line and preset row pinned at the top, a run summary under it stating mode, speed, length and start time with an icon per option the run applies, and the clock readout and START pinned at the bottom.
    - [New] Presets carry every setting but the log level and Traffic Frenzy, saved to `presets.json`. Defaults, Sunrise, City Rush and Empty City ship with the mod; a saved preset may shadow one, and deleting it brings the shipped one back.
    - [Fix] Controls size by the library's 12-column grid. Setting their own item width lost the preset row its buttons.
    - [Fix] Each unit row pushes its own ImGui id. Two rows of the same labels shared one id, so the duration row's clicks landed on the speed row's buttons.
    - [Fix] The Clock-mode unit is stored in `mod.ui` like the duration's, so running the slider to its end no longer re-reads the speed and jumps a unit.
    - [Fix] The `BeginDisabled` for the mode buttons had no matching `EndDisabled`, which disabled every control after it, STOP included, for the length of a run.
    - [Refactor] Duration and Clock-mode speed are a unit row plus a slider reading "10 minutes" and "1 minute per real second". Start time is an hour box, a minute box and an AM/PM toggle beside them, on a `startSeconds` setting migrated from the three combo keys. The Clock-mode type box is gone, because Ctrl+click types into any slider and the tooltips now say so.
    - [Fix] The window opens at 720x960, the size that fits the sections without scrolling, and the panes leave room for the footer.

### [2026-02-22] Initial
- Repository created from workspace restructure.

---

## Historical Changelog (Pre-Restructure)

### v1.0.0
- Initial upload

### v1.1.0
- Renamed mod to "Simple Time-lapse" (Clean install required! Delete old cinematic_timelapse folder).
- Added Combat Safety Check: Prevents starting time-lapse while in combat.
- Added new settings to lock Player Movement and Camera Rotation during recording.
- Added buttons to the debug tab to restore the head-bob and unlock player movement/camera if they get stuck.

### v1.2.0
- New "Clock Only" Mode: Separate time-lapse mode that advances the sky/sun without speeding up physics or NPCs. Perfect for sunsets/sunrises.
- Clock Mode: Speed slider now scales up to 10000x for Clock Mode.
- Clock Mode: Added a manual text box to type exact speed values.
- Automatically limits speed when switching back to Simulation Mode to prevent physics explosions.

### v1.3.0
- Added Disable Air Traffic option to remove flying AVs during time-lapse
- Added Disable Crowds &amp; Traffic option to clear pedestrians and street vehicles
- Added Traffic Frenzy mode (experimental) - speeds up nearby traffic using AI command injection
