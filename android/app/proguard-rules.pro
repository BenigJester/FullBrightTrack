# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.embedding.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# Keep model classes
-keep class com.productivity.and.wellbeing.models.** { *; }

# Keep Gson serialization
-keepattributes Signature
-keepattributes *Annotation*

# Prevent stripping enums
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Flutter / Google Play
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**