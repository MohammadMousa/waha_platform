# Geidea POS terminal SDK (spec §3.3). The comment this rule set used to
# carry ("release buildType doesn't enable isMinifyEnabled, so nothing here
# is active yet") was wrong — confirmed via a 25MB
# build/app/outputs/mapping/release/mapping.txt that R8 runs on every
# release build regardless (Flutter's own Gradle plugin turns minification
# on for release by default; nothing in this file ever needed to set
# isMinifyEnabled explicitly for that to be true). These rules were live
# the whole time.
-keep class geidea.net.terminal_comm_api.** {*;}
-keep class com.jcraft.jsch.jce.*
-keep class * extends com.jcraft.jsch.KeyExchange
-keep class com.jcraft.jsch.**
-keep class org.ietf.jgss.*
-dontwarn org.ietf.jgss.**
-dontwarn com.jcraft.jsch.**

# ML Kit (mobile_scanner's on-device barcode engine) discovers its
# CommonComponentRegistrar/BarcodeRegistrar/VisionCommonRegistrar classes
# via reflection at runtime (Class.getDeclaredConstructor().newInstance()
# inside ComponentDiscovery) — R8 doesn't know about that reflective use and
# was stripping/renaming their no-arg constructors, since R8 being live was
# never accounted for here (see comment above). Confirmed on real hardware:
# every registrar failed with NoSuchMethodException <init> [] right at
# MlKitInitProvider.onCreate/attachInfo (app startup, before any scan is
# even attempted), which cascades into mobile_scanner's own MethodChannel
# handler NPE'ing on a null scanner client — the camera scanner's "!" error
# placeholder. Keeping these classes and their constructors intact fixes it.
-keep class com.google.mlkit.common.internal.** { *; }
-keep class com.google.mlkit.vision.barcode.internal.** { *; }
-keep class com.google.mlkit.vision.common.internal.** { *; }
-keep class com.google.mlkit.vision.barcode.** { *; }
-keep class com.google.mlkit.vision.common.** { *; }
-keep class com.google.mlkit.common.** { *; }
-keep class * implements com.google.mlkit.common.internal.ComponentRegistrar { <init>(); }
-dontwarn com.google.mlkit.**
