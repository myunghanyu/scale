# Scale

Menu bar app that holds your MacBook battery at a set charge — even in clamshell mode. Apple Silicon only.

Set a goal (e.g. 80%):
- below goal → charges
- at goal → stops charging, runs on adapter
- above goal → drains the battery to the goal **while plugged in** (sleep is blocked only during this, so clamshell keeps working)

## Install

1. Download `Scale.zip` from the **Assets** of the [latest release](../../releases/latest) — not the green `Code → Download ZIP` (that's source only, no app inside).
2. Unzip, then move `Scale.app` to `/Applications` and clear the quarantine flag (the app is not notarized):
   ```sh
   mv ~/Downloads/Scale.app /Applications/
   xattr -dr com.apple.quarantine /Applications/Scale.app
   ```
3. Open it → click the scale icon in the menu bar → `[INSTALL]` (admin password).

`[UNINSTALL]` restores charging, adapter and sleep settings.

## CLI

```sh
scale        # status
scale 80     # set goal (100 = no limit)
```

## Build

```sh
./build.sh   # → build/Scale.app
```

## Notes

- Uses SMC keys `CHTE`/`CHIE` (macOS 15+ firmware) or `CH0B`/`CH0C`/`CH0I` (older).
- The macOS battery icon keeps showing the plug/charging icon while the adapter is connected; check real current with
  `ioreg -rn AppleSmartBattery | grep InstantAmperage` (huge number = negative = draining).
