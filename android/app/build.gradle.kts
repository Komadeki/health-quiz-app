plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.health_quiz_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions { jvmTarget = JavaVersion.VERSION_11.toString() }

    defaultConfig {
        // ← 実アプリでは本番IDに変える
        applicationId = "com.example.health_quiz_app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // ★ 追加：flavor 定義
    flavorDimensions += "env"
    productFlavors {
        create("dev") {
            dimension = "env"
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
            // アプリアイコン名などを分けたい場合は resValue で
            resValue("string", "app_name", "健康クイズ（DEV）")
        }
        create("qa") {
            dimension = "env"
            applicationIdSuffix = ".qa"
            versionNameSuffix = "-qa"
            resValue("string", "app_name", "健康クイズ（QA）")
        }
        create("prod") {
            dimension = "env"
            // suffix なし＝本番
            resValue("string", "app_name", "高校保健 一問一答")
        }
    }

    buildTypes {
        release {
            // 署名は後で本番キーに差し替え
            signingConfig = signingConfigs.getByName("debug")
            // minify/obfuscate を使う場合:
            // isMinifyEnabled = true
            // proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
        debug {
            // 必要に応じて
        }
    }
}

flutter { source = "../.." }
