# Simple Time-lapse

**Simple Time-lapse** speeds up the flow of time in Night City so you can shoot time-lapse footage of it. It handles the setup a cinematic take needs - hiding the HUD, holding your position, silencing the radio and notifications - and puts every one of them back when the run ends.

**Download:** [Simple Time-lapse on Nexus Mods](https://www.nexusmods.com/cyberpunk2077/mods/26107)

- Showcase of some of the 2.0 features: <https://www.youtube.com/watch?v=H7sFqRFak9w>
- How to use it: <https://www.youtube.com/watch?v=DklQ6SAhm10>

## Features

- **Two modes:** Simulation speeds up everything, to the engine's limit of 10x. Clock speeds up only the sky and lighting, up to three game hours per real second.
- **Auto Speed:** Give Clock mode a start time, an end time, how many days to cross and how long the run lasts, and it works the speed out for you.
- **Presets:** Defaults, Sunrise, City Rush and Empty City ship with the mod, and you can save your own.
- **Run summary:** Mode, speed, length and start time in one line, with an icon for every option the run will apply.
- **HUD control:** Hides the whole HUD for the run, the vehicle HUD included, and leaves other mods' on-screen overlays alone.
- **Audio control:** Mute the radio, the score, sound effects and notifications for the length of a run. A call that arrives mid-run has its ringtone cut.
- **Scene control:** Disable flying AVs, disable crowds and street traffic, or run Traffic Frenzy to speed up nearby vehicles.
- **Everything is undone:** Each change a run makes records its own undo, and Stop runs them in reverse. Panic buttons on the Debug tab cover anything a crash left behind.

## Requirements

- [Cyber Engine Tweaks](https://www.nexusmods.com/cyberpunk2077/mods/107).
- [Window Utils](https://www.nexusmods.com/cyberpunk2077/mods/26589) - draws the mod window. Without
  it the window shows a notice and the hotkeys still work.
- [Codeware](https://www.nexusmods.com/cyberpunk2077/mods/7780) - required to hide the HUD.

### Optional

- [XUtils](https://www.nexusmods.com/cyberpunk2077/mods/30296) - the Cinema section: a moving camera,
  camera shake, depth of field, a weather sequence, cinematic bars and fades.

## Usage

1. Open the CET overlay.
2. Bind a hotkey for **Start/Stop Time-lapse**, and optionally one for **Toggle HUD**.
3. Pick a preset, or set the mode, speed and duration yourself.
4. Close the overlay, frame your shot, and hit the hotkey.

## Cinema

With XUtils installed, the run is shot through an XUtils camera rather than V's own view. V is hidden
for the length of it either way.

- **Static** holds the frame where the run started, and takes a camera shake and a held roll.
- **Free fly** moves the camera on WASD, Space and C, and brings V along so the city keeps loading
  around the shot. Q and E roll, the wheel sets speed, Ctrl is precision, and holding R, F or X with
  the wheel sets roll, field of view or look sensitivity. Those are your own XUtils bindings, so
  rebinding them under XUtils in Mod Settings works here too.

Camera shake reaches a static camera only. XUtils drives a free-flying camera itself every frame, so
a shake laid over it would not survive the frame.

## Known limits

- Vehicles are hard-coded to ignore time dilation in the physics engine. In Simulation mode nearby
  vehicles run at normal speed unless Traffic Frenzy is on.
- Traffic Frenzy is experimental. Cars may corner aggressively, briefly stop, or behave unusually at
  higher multipliers.
- Simulation mode cannot exceed 10x. The engine caps it there whatever it is asked for.

## Releasing

See [RELEASING.md](RELEASING.md). A GitHub Release tagged `stl-v<version>` builds the zip, attaches
it, and uploads it to Nexus.

## License

Licensed under the [MIT License](LICENSE). Use, change and share this mod and its source,
including in your own mods. Keep the licence notice with any copy.

## Disclaimer

This mod was developed with the assistance of an LLM. All in-game testing and code validation was performed by a human. No rogue AIs were permitted through the Blackwall.
