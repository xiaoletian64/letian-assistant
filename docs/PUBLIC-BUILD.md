# Public build boundary

Only generic source, public dependencies, synthetic tests and reviewed decorative assets belong here. Never include old Git history, backups, diagnostic logs, screenshots of private pages, databases, credentials, API keys, cookies, private hostnames, signing profiles, certificates or private keys.

Public CI uses a configuration-required placeholder. Production URLs and signing stay in the private release environment. Replacing a Flutter JSON asset is a deployment step; inspect and sign the resulting artifact privately. Do not treat publicly visible client configuration as a secret. Keep actual upstream credentials on the authenticated backend.

Private authenticated file transfers enforce the configured HTTPS origin and reject redirects. External public links receive no application Bearer token. An unauthenticated generic build does not issue deployment requests.

Before publication review the complete exported tree, new Git index/history, resource metadata, workflows and artifacts. Keep source revision, package version, artifact hash and signing validation together in private release records. iOS TestFlight availability requires the intended App record, a matching profile and certificate, successful Apple processing and internal-group association.


# 2.12.0 (45)

Shared Flutter Android/iOS release. Adds a notification inbox and settings for low quota, low balance, confirmed quota resets/recovery and server incidents/recovery. Thresholds: CNY below 5, USD below 1, subscription remaining below 10%.

Android uses user-started foreground monitoring with a visible running notification and stop action. No vendor push account is required. Battery restrictions, force-stop and network loss can delay detection. Logout stops monitoring and erases its encrypted credentials. iOS uses APNs with private server credentials and a push-enabled signing profile. Permission, valid registration, backend acceptance and actual delivery are separate states.

The home page exposes the existing authorized server dashboard. MiMo uses readable Chinese plan/window labels; Cursor prioritizes the direct source while keeping distinct pushed accounts available. Historical usage and reset data remain intact in SQLite. Notification rules and events use a separate private SQLite database with online backups.

Validation: source commit `8b700ed29ada682aa2526e1ae2610b4693f78c80`, GitHub Actions run `41411512940` passed verification and both platform builds. Android QA verified upgrade from44, background ordinary notification, notification navigation, stop and logout cleanup. iOS signed entitlement and Apple internal availability were checked; physical-device push receipt requires installation and user notification permission.

Generic public CI artifacts contain placeholder endpoints and no private signing assets, server deployment credentials or APNs keys. Production signing and endpoint injection happen outside this repository.


# 2.13.0 (47) integrated candidate

Combines the daily digest inbox and switch, Android daily notification filtering, order product images with safe placeholders, and default collapsed quota platform/content cards. Reports expand without marking read; the read action remains explicit. Missing payment, refund, logistics and bill data remain unknown. Preserves the existing owner isolation, cached source freshness, notification permission and foreground monitoring behavior.

Local validation: 153 shared Flutter tests plus the integrated preview test, 14 Android release JVM tests, Dart analysis, Python tests and source export scan passed. Both Android release and unsigned iOS device builds succeeded locally with Xcode 27.2. Production configuration and signing were performed privately on the existing server. Signed candidates are distinct from public placeholder artifacts. No claim of TestFlight upload, update-feed publication, real-device installation or notification receipt is made by these build checks.
