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
        targetSdk = flutter.targetSdkVersion
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
}

flutter {
    source = "../.."
}
