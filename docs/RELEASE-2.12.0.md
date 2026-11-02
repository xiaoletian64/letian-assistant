# 2.12.0 (45)

Shared Flutter Android/iOS release. Adds a notification inbox and settings for low quota, low balance, confirmed quota resets/recovery and server incidents/recovery. Thresholds: CNY below 5, USD below 1, subscription remaining below 10%.

Android uses user-started foreground monitoring with a visible running notification and stop action. No vendor push account is required. Battery restrictions, force-stop and network loss can delay detection. Logout stops monitoring and erases its encrypted credentials. iOS uses APNs with private server credentials and a push-enabled signing profile. Permission, valid registration, backend acceptance and actual delivery are separate states.

The home page exposes the existing authorized server dashboard. MiMo uses readable Chinese plan/window labels; Cursor prioritizes the direct source while keeping distinct pushed accounts available. Historical usage and reset data remain intact in SQLite. Notification rules and events use a separate private SQLite database with online backups.

Validation: source commit `8b700ed29ada682aa2526e1ae2610b4693f78c80`, GitHub Actions run `41411512940` passed verification and both platform builds. Android QA verified upgrade from44, background ordinary notification, notification navigation, stop and logout cleanup. iOS signed entitlement and Apple internal availability were checked; physical-device push receipt requires installation and user notification permission.

Generic public CI artifacts contain placeholder endpoints and no private signing assets, server deployment credentials or APNs keys. Production signing and endpoint injection happen outside this repository.
