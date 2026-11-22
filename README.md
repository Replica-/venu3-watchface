# Venu 3 Watch Face

A custom Garmin Connect IQ watch face for the **Venu 3** (454×454 AMOLED).

Shows the time, date, steps, heart rate, and a battery ring around the edge.
In always-on mode it switches to a dim, minimal time display that shifts
position every minute to protect the AMOLED screen from burn-in.

## One-time setup

1. **Install the Connect IQ SDK Manager**
   https://developer.garmin.com/connect-iq/sdk/ – run it, sign in with your
   Garmin account, download the latest SDK, and under *Devices* download
   **Venu 3**.
2. **Install a Java runtime** (JDK 17+), required by the Monkey C compiler.
3. **Install the VS Code extension** "Monkey C" by Garmin
   (`garmin.monkey-c`; VS Code will suggest it when you open this folder).
4. **Generate a developer key**: in VS Code press `Ctrl+Shift+P` →
   *Monkey C: Generate a Developer Key*. Keep it outside this repo (or it is
   git-ignored as `developer_key*`).

## Run in the simulator

`Ctrl+Shift+P` → *Monkey C: Run* (or press `F5`) and pick **venu3**.

Useful simulator menu items:
- *Settings → Low Power Mode* – test the always-on display
- *File → Edit Persistent Storage → Edit Application.Properties* – try the gradient start/end colours (StartColor, EndColor)

## Demo build (sample data)

The simulator has no stress, calorie or intensity-minute history, so those
parts of the face show empty. `demo.jungle` builds a version that fills them
with sample data from `source/Demo.mc`:

```
monkeyc -f demo.jungle -d venu3 -o bin/venu3face-demo.prg -y <developer_key>
monkeydo bin/venu3face-demo.prg venu3
```

`monkey.jungle` (the normal build, used by VS Code) always shows real data.

## Install on your watch

1. `Ctrl+Shift+P` → *Monkey C: Build for Device* → **venu3**. This produces a
   `.prg` file in `bin/`.
2. Plug the watch in via USB and copy the `.prg` to `GARMIN/APPS/` on the
   watch.
3. Unplug, then long-press the watch face → pick the new face.

## Project layout

```
manifest.xml              App ID, type (watchface), target devices
monkey.jungle             Build config
source/
  Venu3FaceApp.mc         App entry point
  Venu3FaceView.mc        All drawing code
resources/
  drawables/              Launcher icon
  strings/                Text shown to the user
  settings/               User-configurable settings (gradient start and end colours)
```
