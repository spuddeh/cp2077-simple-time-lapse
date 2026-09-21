# Simple Time-lapse

**Simple Time-lapse** is a Cyberpunk 2077 mod for shooting time-lapse footage of Night City. It
handles the setup a cinematic take needs - hiding the HUD, holding your position, silencing the
radio and notifications - and puts all of it back when the run ends.

📥 **Download:** [Simple Time-lapse on Nexus Mods](https://www.nexusmods.com/cyberpunk2077/mods/26107)

## 🚀 Features

* **Two modes:** Simulation speeds up everything to the engine's limit of 10x. Clock speeds up only
  the sky and lighting, up to three game hours per real second.
* **Auto Speed:** Give Clock mode a start time, an end time, how many days to cross and how long the
  run lasts, and it works the speed out for you.
* **Presets:** Defaults, Sunrise, City Rush and Empty City ship with the mod, and you can save your own.
* **HUD control:** Hides the whole HUD for the run, the vehicle HUD included, and leaves other mods'
  on-screen overlays alone.
* **Audio control:** Mute the radio, the score, sound effects and notifications for the length of a
  run. A call that arrives mid-run has its ringtone cut.
* **Scene control:** Disable flying AVs, disable crowds and street traffic, or run Traffic Frenzy to
  speed up nearby vehicles.
* **Cinema (needs XUtils):** A static or free-flying camera, camera shake, depth of field with five
  lens presets, a weather sequence across the run, cinematic bars and fades.
* **Everything is undone:** Each change a run makes records its own undo, and Stop runs them in
  reverse. Panic buttons on the Debug tab cover anything a crash left behind.

## 📋 Requirements

* [Cyber Engine Tweaks](https://www.nexusmods.com/cyberpunk2077/mods/107).
* [Window Utils](https://www.nexusmods.com/cyberpunk2077/mods/26589) - the mod window is drawn with it.
* [Codeware](https://www.nexusmods.com/cyberpunk2077/mods/7780) - hiding the HUD needs it.
* [XUtils](https://www.nexusmods.com/cyberpunk2077/mods/30296) - optional, for the Cinema section.

Each dependency lists its own requirements on its mod page.

## 🎮 Usage

1. Open the CET overlay.
2. Bind a hotkey for **Start/Stop Time-lapse**, and optionally one for **Toggle HUD**.
3. Pick a preset, or set the mode, speed and duration yourself.
4. Close the overlay, frame your shot, and hit the hotkey.

## 🎥 Cinema

With XUtils installed, the Cinema tab shoots the run through an XUtils camera.

* **Static** holds the frame where the run started, and accepts a shake and a held roll.
* **Free fly** moves the camera on WASD, Space and C, and brings V along so the city keeps loading.
  Q and E roll, the wheel sets speed, Ctrl is precision, and holding R, F or X with the wheel sets
  roll, field of view or look sensitivity. These are your own XUtils bindings.

Camera shake reaches a static camera only: XUtils drives a free-flying camera itself every frame.

## 📦 Releasing

See [RELEASING.md](RELEASING.md). Releases are built and uploaded by
[`.github/workflows/release.yml`](.github/workflows/release.yml) from a GitHub Release tagged
`stl-v<version>`.

## 📜 License

Licensed under the [MIT License](LICENSE). Use, change and share this mod and its source,
including in your own mods. Keep the licence notice with any copy.

## 🤖 Disclaimer

This mod was developed with the assistance of an LLM. All in-game testing and code validation was performed by a human. No rogue AIs were permitted through the Blackwall.
