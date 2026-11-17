# Canopy

A side-view terrarium where plants evolve on their own and you play the climate.
Leaves in light earn growth, wood has weight, and everything else follows from
those two rules. Drag the sun, snip, and wait: the forest leans, overreaches and
comes down in slow cascades, then grows back different.

The full design is in [Canopy Design Bible.md](Canopy%20Design%20Bible.md).
Made with Godot 4.7 for Android and desktop (Windows, Linux, macOS).

## Get it

Every commit on `main` is tested, built and published automatically. Grab the
newest build from [Releases](https://github.com/maccam912/canopy/releases/latest):

| Platform | File | Notes |
| --- | --- | --- |
| Android (ARM64) | `canopy-android.apk` | Sideload; development-signed |
| Windows x86_64 | `canopy-windows.zip` | Unzip and run |
| Linux x86_64 | `canopy-linux.zip` | Unzip and run |
| macOS (universal) | `canopy-macos.zip` | Right-click the app, then Open (not notarized) |

## How to play

| | Touch | Desktop |
| --- | --- | --- |
| Move the sun | drag it along its rail; flick to keep it swinging | same, with the mouse |
| Snip | swipe across any stem | drag across any stem |
| Fast-forward | hold a finger still | hold Space, or F to latch |
| Zoom / pan | pinch | mouse wheel / right-drag |

## Develop

```
python3 tools/godot.py --editor        # pinned Godot, downloaded into .tools/
python3 tools/check.py                 # headless simulation tests
python3 tools/export.py macos          # or linux / windows / android
```

The simulation lives in `sim/` and never draws or reads input, so a whole
forest can be grown headless:

```
godot --headless --fixed-fps 60 --script res://tests/soak.gd -- 60 8 1
```

(minutes of forest time, speed, seed). Everything tunable is in `sim/tune.gd`.
To measure how much standing plants and fallen logs shake in a grown forest:

```
godot --headless --fixed-fps 60 --script res://tests/jitter.gd -- 5 12 all
```

All art and sound are generated in code.

## Physics

Plants bend with their own joint solver in `sim/plant.gd`; fallen wood is
simulated by [Godot Rapier 2D](https://github.com/appsinacup/godot-rapier-physics)
v0.36.0 (MIT), which replaces Godot's built-in 2D physics. Piles of logs settle
and sleep under Rapier instead of buzzing, which used to shake the stems they
leant on. Its native libraries live in `addons/godot-rapier2d/bin/` and are
stored with Git LFS.
