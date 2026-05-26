# Repository Guidelines

## Project Structure & Module Organization

Bettbox is a Flutter app with native support code. Main Dart code lives in `lib/`: app startup in `main.dart` and `application.dart`, screens under `pages/` and `views/`, reusable UI under `widgets/`, state and services under `providers/`, `manager/`, `clash/`, and `common/`. Model sources are in `lib/models/`; generated outputs are in `lib/models/generated/`, `lib/providers/generated/`, `lib/clash/generated/`, and `lib/l10n/`. Static files are in `assets/`, translations in `arb/`, platform projects in `android/`, `linux/`, `macos/`, and `windows/`. Native core code is in `core/` (Go) and helper service code in `services/helper/` (Rust). Local plugin packages are in `plugins/`.

## Build, Test, and Development Commands

- `flutter pub get`: install Dart and Flutter dependencies.
- `dart run build_runner build -d`: regenerate Freezed, JSON, Riverpod, and other generated Dart files.
- `flutter analyze`: run the configured Flutter lint rules.
- `flutter test`: run unit/widget tests when test files are present.
- `dart setup.dart windows --arch amd64 --compatible`: build a Windows package; omit `--compatible` for the normal target.
- `make android_arm64` / `make macos_arm64`: shortcut builds for common Android and macOS targets.

## Coding Style & Naming Conventions

Use Dart defaults from `package:flutter_lints/flutter.yaml`; this repository additionally prefers single quotes. Format Dart changes with `dart format <paths>`. Keep generated files out of manual edits; change the source annotations and rerun `build_runner`. Use `snake_case.dart` filenames, `PascalCase` classes/widgets, `camelCase` members, and descriptive provider/manager names that match existing `lib/` patterns.

## Testing Guidelines

There is currently no committed `test/` tree or coverage gate. Add focused tests for new business logic, model serialization, and nontrivial widgets under `test/`, mirroring the `lib/` path. Name files `*_test.dart`. Run `flutter test` and `flutter analyze` before submitting changes. For platform packaging changes, run the smallest relevant `setup.dart` or `make` target.

## Commit & Pull Request Guidelines

Recent commits use concise prefixes such as `修复:`, `优化:`, `新增:`, `变更:`, plus occasional English `fix:`. Follow that style and keep the subject imperative and scoped. Pull requests should describe the change, list validation commands, link related issues, and include screenshots or recordings for UI changes. Mention affected platforms explicitly, especially Android, Windows, macOS, or Linux packaging.

## Security & Configuration Tips

Do not commit secrets, signing material, local build outputs, or generated `dist/` packages. CI may pass `SENTRY_DSN`; keep such values in environment variables or repository secrets. Treat bundled data in `assets/data/` and platform-specific binaries as release artifacts and verify provenance before updating them.
