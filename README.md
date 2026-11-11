# Scale

Menu bar app that holds your MacBook battery at a set charge — even in clamshell mode. Apple Silicon only.

Set a goal (e.g. 80%):
- below goal → charges
- at goal → stops charging, runs on adapter
- above goal → drains the battery to the goal **while plugged in** (sleep is blocked only during this, so clamshell keeps working)

## Install

1. Download `Scale.zip` from [Releases](../../releases), unzip, move `Scale.app` to `/Applications`.
2. The app is not notarized, so clear the quarantine flag once:
   ```sh
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
