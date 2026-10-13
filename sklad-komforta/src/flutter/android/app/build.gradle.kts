plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Закрытый ключ хранится вне репозитория и передаётся только процессу сборки.
val releaseSigningDirectory = System.getenv("SKLAD_ANDROID_SIGNING_DIR")?.let { file(it) }

android {
    namespace = "com.skladkomforta.sklad_komforta_app"
    // flutter_secure_storage 11 требует Android API 37 только для компиляции.
    // minSdk не повышается, поэтому поддержка старых устройств сохраняется.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.skladkomforta.sklad_komforta_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningDirectory != null) {
            create("release") {
                storeFile = releaseSigningDirectory.resolve("release.p12")
                storeType = "PKCS12"
                storePassword = releaseSigningDirectory.resolve("password.txt").readText().trim()
                keyPassword = storePassword
                keyAlias = "skladkomforta"
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
        }
    }
}

gradle.taskGraph.whenReady {
    if (releaseSigningDirectory == null && allTasks.any {
        it.project.path == ":app" && it.name.contains("Release")
    }) {
        throw GradleException("Для release задайте SKLAD_ANDROID_SIGNING_DIR. См. scripts/build_android_apk.py.")
    }
}

flutter {
    source = "../.."
}
