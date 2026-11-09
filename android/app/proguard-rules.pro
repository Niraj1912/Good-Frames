# R8 rules for release builds. Flutter's own rules come with the Flutter
# Gradle plugin; these cover this app's Kotlin side.

# The method-channel handlers are reached by Flutter at run time, by name.
-keep class com.goodframes.app.** { *; }

# Play Core is referenced by Flutter's deferred-components code but not used.
-dontwarn com.google.android.play.core.**
