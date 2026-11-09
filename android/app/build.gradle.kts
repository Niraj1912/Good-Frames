import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The release signing key's location and passwords. Each comes from an
// environment variable if set (so the passwords can stay out of any file), else
// from android/key.properties. That file is never committed (see .gitignore);
// key.properties.example shows what goes in it, and the README how to make the
// key.
val fileKey = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
fun keySetting(property: String, env: String): String? =
    System.getenv(env)?.takeIf { it.isNotBlank() } ?: fileKey.getProperty(property)

val keyStorePath = keySetting("storeFile", "GOODFRAMES_STORE_FILE")
val keyStorePassword = keySetting("storePassword", "GOODFRAMES_STORE_PASSWORD")
val keyAliasName = keySetting("keyAlias", "GOODFRAMES_KEY_ALIAS")
val keyPasswordValue = keySetting("keyPassword", "GOODFRAMES_KEY_PASSWORD")
val hasReleaseKey = listOf(keyStorePath, keyStorePassword, keyAliasName, keyPasswordValue)
    .all { it != null }

// A release build without the real key would be signed with the debug key,
// which anyone can forge. Stop the build instead of producing it.
gradle.taskGraph.whenReady {
    val buildingRelease = allTasks.any {
        it.name.matches(Regex("(assemble|bundle|package)Release"))
    }
    if (buildingRelease && !hasReleaseKey) {
        throw GradleException(
            "No release signing key. Create android/key.properties (see " +
                "key.properties.example) or set the GOODFRAMES_STORE_FILE, " +
                "GOODFRAMES_STORE_PASSWORD, GOODFRAMES_KEY_ALIAS and " +
                "GOODFRAMES_KEY_PASSWORD environment variables."
        )
    }
}

android {
    namespace = "com.goodframes.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.goodframes.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 30 // Android 11: first version with the MediaStore trash. See README.
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keyStorePath!!)
                storePassword = keyStorePassword
                keyAlias = keyAliasName
                keyPassword = keyPasswordValue
            }
        }
    }

    buildTypes {
        release {
            // Only ever the real key; the check above stops the build if it
            // is missing.
            if (hasReleaseKey) signingConfig = signingConfigs.getByName("release")
            // R8 removes unused code and shortens names, making the app
            // smaller and harder to read. Rules for what it must keep are in
            // proguard-rules.pro.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
