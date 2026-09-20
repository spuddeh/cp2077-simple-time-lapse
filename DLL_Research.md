# Cyberpunk 2077 Time Dilation DLL Research

If you decide to revisit the idea of writing a custom C++ DLL (RED4ext plugin) to uncap or manipulate vehicle time dilation natively, here is a primer on what is involved and how to start.

## The Core Problem

Cyberpunk 2077's vehicle physics are handled by the proprietary Havok Physics engine. While Redscript and CET can interact with the *gameplay* layers of the engine (like Quest Facts or UI), the core physics tick rate and hardcoded speed limits are compiled deeply inside C++.

When we use `TimeDilationHelper.SetIndividualTimeDilation()`, the game sends a multiplier to that entity. However, if the entity is a `VehicleObject`, its internal Havok `RigidBody` often ignores or overrides the visual time dilation because the physics simulation is running synchronously with the global game tick to prevent cars from vibrating through the ground or clipping through walls.

## How a RED4ext Plugin Solves This

RED4ext allows us to inject raw C++ code directly into the game's memory while it is running. By finding the exact memory address (offset) of the `RigidBody::Recalculate` function, we can literally replace CDPR's code with our own.

### Example: Vehicle Speed Unlimiter

The `vehicle_speed_unlimiter` mod does exactly this. It hooks into `RED4ext::vehicle::PhysicsData` and overrides the resulting velocity just before the game clamps it.

```cpp
// Intercept the Havok physics recalculation
REGISTER_FLIGHT_HOOK_HASH(short, 593628708, Recalculate, RED4ext::vehicle::PhysicsData *ps) {
  RED4ext::Vector3 unlimitedVelocity;
  unlimitedVelocity.X = ps->velocity.X + ps->force.X * ps->inverseMass;
  unlimitedVelocity.Y = ps->velocity.Y + ps->force.Y * ps->inverseMass;
  unlimitedVelocity.Z = ps->velocity.Z + ps->force.Z * ps->inverseMass;

  auto result = Recalculate_Original(ps);
  // Bypass CDPR's speed limit clamp
  if (result != FP_INFINITE) {
    ps->velocity = unlimitedVelocity;
  }
  return result;
}
```

## Steps to Get Started

1. **Prerequisites & Toolchain:**
   - Visual Studio 2022 (C++ Desktop Development workload)
   - CMake
   - Basic understanding of C++ pointers and memory structures.

2. **Clone the RED4ext SDK:**
   - [RED4ext GitHub](https://github.com/WopsS/RED4ext.SDK)
   - You will use this SDK to compile your `.dll` and place it in `Cyberpunk 2077\red4ext\plugins\`.

3. **Reverse Engineering (The Hard Part):**
   - You need a tool like **Ghidra** or **IDA Pro** (with the Cyberpunk 2077 PDB debug symbols loaded).
   - You must search the compiled executable for the functions related to `TimeSystem` or `vehicle::PhysicsData`, reverse engineer their assembly instructions, and find their memory offsets.
   - *Note:* These offsets change every time the game updates (e.g., from Patch 2.1 to 2.12), so a DLL mod built on them breaks on every patch.

4. **Writing the Hook:**
   - Once you have the offset, you write a RED4ext hook (like the example above) to intercept the time-dilation application for vehicles.
   - You would read the current `TimeSystem` multiplier and manually multiply the `ps->velocity` by that exact amount.

## Should You Do It?

If you are comfortable with C++ and assembly, it is the *only* way to achieve perfect 10x physics speed-ups without visual stuttering. However, it requires constant maintenance whenever the game updates, unlike CET or Redscript which are usually version-agnostic.
