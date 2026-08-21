# App Freezer (personal)

Freeze selected apps for a chosen time on **your own phone**.  
No Shizuku. No root. Uses Android **Device Owner** package suspension.

## Warning

Device Owner can make some banking apps (e.g. CBE, BOA) refuse to run, even if you never freeze them. Files are not wiped. Use only if you accept that risk.

## Setup (one time)

1. Install the app on the phone.
2. Prefer a user with **no Google accounts** (or remove accounts temporarily).
3. From your computer:

```bash
adb shell dpm set-device-owner com.example.app_freezer/.DeviceAdminReceiver
```

4. Open App Freezer — the setup banner should disappear.
5. Pick apps → choose duration → freeze. Unfreeze from the home list or wait for the timer.

## Run / build

```bash
cd app_freezer
flutter pub get
flutter run -d <deviceId>
# or
flutter build apk --release
```

## Remove Device Owner later

```bash
adb shell dpm remove-active-admin com.example.app_freezer/.DeviceAdminReceiver
```

If that fails, clear app data / uninstall after disabling device owner, or factory reset.

## How it works

- `DevicePolicyManager.setPackagesSuspended` hides/disables selected packages.
- Exact alarms + boot receiver restore apps when the timer ends.
- Opening the app also clears any expired freezes.
