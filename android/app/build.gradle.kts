plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.waha_platform"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.waha_platform"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        // Pinned below Flutter's own default (34+), NOT flutter.targetSdkVersion —
        // Geidea's compiled POS SDK (net.geidea.sdk:pos-comm-sdk-ksa:1.3.0)
        // constructs a mutable PendingIntent from an implicit intent internally
        // (geidea.net.terminal_comm_api.USBService, requesting USB permission),
        // which Android 14 flatly disallows for apps targeting API 34+ — see
        // https://developer.android.com/about/versions/14/behavior-changes-14
        // ("Restrictions to implicit and pending intents"). Confirmed via a
        // real crash log from the client's Android 14 kiosk: an uncaught
        // IllegalArgumentException from inside that exact SDK class, crashing
        // the app on every startup. The restriction is gated by targetSdk, not
        // by the device's own Android version, so targeting 33 here makes
        // Geidea's SDK behave exactly as it did on Android 13 and earlier —
        // this isn't source we can patch (no source, it's a closed binary).
        // Remove once Geidea ships an SDK build that constructs this
        // PendingIntent correctly (FLAG_IMMUTABLE or an explicit intent).
        targetSdk = 33
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // Renames the built APK from Flutter's generic app-release.apk to
    // something that identifies itself on sight — waha-kiosk-release.apk —
    // since this is handed off/installed manually rather than through a
    // store listing that already carries the app's name.
    applicationVariants.all {
        val variant = this
        variant.outputs
            .map { it as com.android.build.gradle.internal.api.BaseVariantOutputImpl }
            .forEach { output ->
                output.outputFileName = "waha-kiosk-${variant.buildType.name}.apk"
            }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Geidea POS terminal SDK (USB Serial). The archive at
    // android/app/libs/Geidea_Android_SDK_v1.3.0.rar turned out to contain
    // only docs + a sample app, no bundled binary — the sample's own
    // build.gradle pulls the SDK from the Cloudsmith repo declared in the
    // root build.gradle.kts, same as here. com.jcraft:jsch (kept in
    // proguard-rules.pro) resolves transitively via this artifact's own
    // POM — no need to declare it separately.
    implementation("net.geidea.sdk:pos-comm-sdk-ksa:1.3.0")

    // JVM unit tests (PaymentCallbackClassifierTest) — pure Kotlin, no device.
    testImplementation("junit:junit:4.13.2")
}

flutter {
    source = "../.."
}
