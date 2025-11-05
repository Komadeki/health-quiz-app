import java.util.Properties

val keystoreProps = Properties().apply {
    val f = file("key.properties") // ← app/ 直下を見る
    if (f.exists()) f.inputStream().use { load(it) }
}


plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "jp.mokeke.healthquiz"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true

        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions { jvmTarget = JavaVersion.VERSION_11.toString() }

    defaultConfig {
        // ★ 本番用のベース applicationId（prod は suffix なし）
        applicationId = "jp.mokeke.healthquiz"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // ===== signing =====
    signingConfigs {
        create("release") {
            if (keystoreProps.isNotEmpty()) {
                // key.properties の値をそのまま使う
                storeFile = file(keystoreProps["storeFile"] as String)      // 例: ../upload-keystore.jks
                storePassword = keystoreProps["storePassword"] as String?
                keyAlias = keystoreProps["keyAlias"] as String?
                keyPassword = keystoreProps["keyPassword"] as String?
            }
        }
    }

    buildTypes {
        getByName("release") {
            // keystore が無い環境では debug 署名でビルド可（内部検証用）
            signingConfig = if (keystoreProps.isNotEmpty())
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")

            // まずは無効でOK（必要に応じて有効化）
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    // ===== flavors =====
    flavorDimensions += "env"
    productFlavors {
        create("dev") {
            dimension = "env"
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
            // ランチャー名（AndroidManifest.xml の android:label="@string/app_name"）
        }
        create("qa") {
            dimension = "env"
            applicationIdSuffix = ".qa"
            versionNameSuffix = "-qa"
        }
        create("prod") {
            dimension = "env"
            // prod は suffix なし
        }
    }
}

// prod のリリース系を“実行する時”だけ key.properties を必須化
listOf(
    "bundleProdRelease",
    "assembleProdRelease",
    "publishProdBundle" // Play Publisher使う場合
).forEach { taskName ->
    tasks.matching { it.name.equals(taskName, ignoreCase = true) }
        .configureEach {
            doFirst {
                if (keystoreProps.isEmpty) {
                    throw GradleException("prodRelease には android/app/key.properties が必要です。")
                }
            }
        }
}

println("🧩 CWD(app module): " + project.projectDir)
println("🧩 key.properties exists? " + file("key.properties").exists())
println("🧩 keystore at ../upload-keystore.jks exists? " + file("../upload-keystore.jks").exists())


// ===== Flutter =====
flutter {
    source = "../.."
}

// ===== Dependencies =====
dependencies {
    // flutter_local_notifications 等の Java 8 API に必要
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
