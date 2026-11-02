# 乐天助手 · Letian Assistant

使用 Minis 或其他代码助手修改时，请先阅读 [AGENTS.md](AGENTS.md)，遵守双端同步、隐私和验证要求。

A Flutter client for personal services, device management, conversations, quota history and read-only server monitoring. Android and iOS share the same business UI. Native capabilities use platform-specific implementations.

This repository contains generic source only. It contains no production server configuration, account data, signing materials, database, or private history. Generic builds start at a configuration-required screen and do not connect to a deployment.

## Build

Flutter 3.44.0 and Java 17. Run `flutter pub get`, `flutter test`, then `LETIAN_BUILD_UNSIGNED=1 flutter build apk --release` or `flutter build ios --release --no-codesign` on macOS with Xcode. GitHub Actions produces unsigned generic artifacts. Those artifacts are not a configured personal release.

Supply a reviewed `assets/runtime-config.json` in a private environment before signing. The schema permits deployment URLs only, never credentials. A minimal example is `{ "schema_version":1, "api_base_url":"https://api.example.org", "update_manifest_url":"https://updates.example.org/latest.json" }`. Do not commit a configured file or upload configured artifacts to public CI. User authentication is obtained through the application's normal login flow.

SQLite history records quota observations and distinguishes unknown values, source timestamps, inferred consumption, and possible resets. Subscription usage is not an official pay-as-you-go bill. The database and online backups belong in a private persistent directory outside this repository. Server monitor targets are configured privately and are never accepted from client parameters.

Android APK installation and Android companion-app discovery have no direct iOS equivalent. iOS uses TestFlight updates, system authentication, document selection, previews and explicit backup uploads. Compilation is not proof of real-device functional acceptance.

Tibo's 28-day challenge card opens an independently maintained announcement tracker; announcements are separate from observed account resets.

## Privacy and licenses

Source export uses a fresh allowlisted tree and a pattern scan. Independent review is still necessary; passing a pattern scan is not proof that arbitrary content is safe. See [public build boundary](docs/PUBLIC-BUILD.md). Original third-party licenses are retained. Generated decorative avatar and vehicle art are generic assets, not user photos.
