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
