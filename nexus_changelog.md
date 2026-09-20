# Simple Time-lapse (Timelapse Time Lapse) - Time Dilation and HUD Toggle — Nexus Changelogs

### [Unreleased - v2.0.0]
- New: Depth of Field runs get a camera mode. Locked off holds the frame where the run started; Free fly moves the camera on WASD, Space and C at a speed you set, and V rides along so the city keeps loading around the shot
- New: Stay Level keeps a free fly camera moving flat along the ground, so looking down does not fly you into it
- New: The weather sequence is reordered by dragging a state by its grip, instead of nudging it with arrows
- Fix: V is hidden for the length of a Depth of Field run. Walking out from under the camera showed a headless body
- New: The window is rebuilt on Window Utils - tabs for Shot, Scene, Audio, Player and Debug, sections in a column beside the panel, a preset row and status line pinned at the top, and the clock and START pinned at the bottom
- New: Presets. Defaults, Sunrise, City Rush and Empty City ship with the mod, and you can save your own; a preset carries every setting except the log level and Traffic Frenzy
- New: A run summary above the panel stating mode, speed, length and start time, with an icon for every option the run will apply
- New: Cinema section, needing XUtils by CyanideX - depth of field with five lens presets, a weather sequence across the run, cinematic bars and fades in and out
- New: The weather sequence splits the run evenly, by percent per state, or by game hours per state, and puts the natural weather back on Stop
- New: Auto Speed for Clock mode works the speed out from a start time, an end time, how many days later and how long the run lasts, so 5 AM to 5 AM three days later over one minute runs itself
- New: Clock mode speed goes up to three game hours per real second
- New: Duration and Clock speed read as plain sentences - "10 minutes", "1 minute per real second" - and Ctrl+click types an exact number into any slider
- Fix: Hiding the HUD now hides all of it, the vehicle HUD included, in a car, on foot, with the scanner open and with a notification on screen. Hiding the HUD needs Codeware
- Fix: Cinematic bars, fades and other mods' overlays stay on screen while the HUD is hidden
- Fix: STOP and every control below the mode buttons no longer grey out for the length of a run
- Fix: Dragging the Clock speed slider to its end no longer jumps to the next unit
- Fix: Clicks on the duration unit buttons no longer land on the speed unit buttons
- New: Mute Radio, on by default, silences the Radioport and the car radio for the length of a run
- New: Mute Music and Mute Sound Effects, both off by default, for keeping the score or a message alert off a recording
- New: Mute Notifications, on by default, silences message, quest and side popups for the run, and cuts the ringtone of a call that arrives mid-run
- New: Lock Weapons is now its own setting. Lock Movement no longer empties V's hands, so the radio can keep playing during a locked shot
- New: Restore Audio button on the Debug tab, for a volume left muted by a crash mid-run
- New: Mode and speed are locked while a time-lapse runs
- Fix: Changing mode or speed during a run no longer moves the game clock to the wrong time or miscounts the run
- Fix: A time-lapse that fails to start puts back everything it changed instead of leaving V locked in place
- Fix: Starting a fight during the countdown now refuses the run, as it does at the button press
- Fix: Run statistics read n/a instead of a meaningless percentage after a 0x run

### 1.3.0
- Added Disable Air Traffic option to remove flying AVs during time-lapse
- Added Disable Crowds & Traffic option to clear pedestrians and street vehicles
- Added Traffic Frenzy mode (experimental) - speeds up nearby traffic using AI command injection

### 1.2.0
- New "Clock Only" Mode: Separate time-lapse mode that advances the sky/sun without speeding up physics or NPCs. Perfect for sunsets/sunrises.
- Clock Mode: Speed slider now scales up to 10000x for Clock Mode.
- Clock Mode: Added a manual text box to type exact speed values.
- Automatically limits speed when switching back to Simulation Mode to prevent physics explosions.

### 1.1.0
- Renamed mod to "Simple Time-lapse" (Clean install required! Delete old cinematic_timelapse folder).
- Added Combat Safety Check: Prevents starting time-lapse while in combat.
- Added new settings to lock Player Movement and Camera Rotation during recording.
- Added buttons to the debug tab to restore the head-bob and unlock player movement/camera if they get stuck.

### 1.0.0
- Initial upload

---
## Notes

No issues flagged.

---
## Stickied Comment BBCode

```
[color=#ffff00][size=5][b]- Changes -[/b][/size][/color]

[b][size=3]Version 1.3.0[/size][/b]
[list][*]Added Disable Air Traffic option to remove flying AVs during time-lapse
[*]Added Disable Crowds &amp; Traffic option to clear pedestrians and street vehicles
[*]Added Traffic Frenzy mode (experimental) - speeds up nearby traffic using AI command injection
[/list]
[b][size=3]Version 1.2.0[/size][/b]
[spoiler][list][*]New "Clock Only" Mode: Separate time-lapse mode that advances the sky/sun without speeding up physics or NPCs. Perfect for sunsets/sunrises.
[*]Clock Mode: Speed slider now scales up to 10000x for Clock Mode.
[*]Clock Mode: Added a manual text box to type exact speed values.
[*]Automatically limits speed when switching back to Simulation Mode to prevent physics explosions.
[/list][/spoiler]
[b][size=3]Version 1.1.0[/size][/b]
[spoiler][list][*]Renamed mod to "Simple Time-lapse" (Clean install required! Delete old cinematic_timelapse folder).
[*]Added Combat Safety Check: Prevents starting time-lapse while in combat.
[*]Added new settings to lock Player Movement and Camera Rotation during recording.
[*]Added buttons to the debug tab to restore the head-bob and unlock player movement/camera if they get stuck.
[/list][/spoiler]
[b][size=3]Version 1.0.0[/size][/b]
[spoiler][list][*]Initial upload
[/list][/spoiler]
```

> Character count: 1344 / 5000