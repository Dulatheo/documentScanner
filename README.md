# Document Scanner

A local-first document scanner app: capture paper documents, clean them up
(crop, highlight, OCR, sign), keep them in a library with comments, and
export/share as PDF or JPG. No backend — everything lives on-device.

Implemented natively on both platforms from a single design spec:

- **iOS** — SwiftUI ([`/ios`](./ios))
- **Android** — Kotlin + Jetpack Compose ([`/android`](./android))

## Repo structure

This is a single monorepo covering both platforms, rather than two separate
repos. Both apps implement the same feature set and design language, so
keeping them together makes it straightforward to keep behavior in sync,
review changes side-by-side, and track one issue list — with less
cross-repo coordination overhead than two independent repos would need for
a project this size.

```
/docs/     shared design reference (docs/design) and the implementation spec
           (docs/DESIGN_SPEC.md) both apps are built from
/ios/      SwiftUI app (Xcode project)
/android/  Kotlin + Jetpack Compose app (Gradle project)
```

See [`docs/DESIGN_SPEC.md`](./docs/DESIGN_SPEC.md) for the full screen-by-
screen spec (colors, typography, flows, data model) both apps follow.

## Building

- **iOS**: open `ios/DocumentScanner.xcodeproj` (or `.xcworkspace`, if
  present) in Xcode 16+, and run on iOS 17+.
- **Android**: open `android/` in Android Studio (or `./gradlew assembleDebug`
  from the `android/` directory), min SDK per `android/app/build.gradle.kts`.
