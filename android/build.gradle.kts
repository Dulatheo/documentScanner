// Top-level build file where you can add configuration options common to all sub-projects/modules.
plugins {
    id("com.android.application") version "8.5.2" apply false
    // Kotlin 1.9.x: Compose is wired up via the classic `composeOptions {
    // kotlinCompilerExtensionVersion }` block in app/build.gradle.kts, not
    // the org.jetbrains.kotlin.plugin.compose Gradle plugin (that plugin
    // ships with the Kotlin 2.0+ toolchain's merged Compose compiler).
    id("org.jetbrains.kotlin.android") version "1.9.24" apply false
    id("com.google.devtools.ksp") version "1.9.24-1.0.20" apply false
}
