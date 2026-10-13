import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}
val signingProperties = Properties()
val signingFile = rootProject.file("key.properties")
if (signingFile.exists()) signingFile.inputStream().use { signingProperties.load(it) }

android {
    packaging { resources.excludes += "bundle.properties" }
    buildFeatures { aidl = true }
    testOptions { unitTests.isIncludeAndroidResources = true }
    namespace = "app.skyinfo.vehicle"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    defaultConfig {
        applicationId = "app.skyinfo.vehicle"
        minSdk = 29
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
    signingConfigs {
        if (signingFile.exists()) create("skyinfoRelease") {
            storeFile = file(signingProperties.getProperty("storeFile"))
            storePassword = signingProperties.getProperty("storePassword")
            keyPassword = signingProperties.getProperty("keyPassword")
            keyAlias = signingProperties.getProperty("keyAlias")
        }
    }
    buildTypes {
        release {
            signingConfig = if (signingFile.exists()) signingConfigs.getByName("skyinfoRelease") else signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}
kotlin { compilerOptions { jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17 } }
flutter { source = "../.." }
dependencies {
    implementation(project(":libadb"))
    implementation("org.conscrypt:conscrypt-android:2.5.3")
    implementation("org.bouncycastle:bcpkix-jdk15to18:1.81")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.eclipse.paho:org.eclipse.paho.client.mqttv3:1.2.5")
    implementation("org.eclipse.paho:org.eclipse.paho.mqttv5.client:1.2.5")
    implementation("com.caverock:androidsvg-aar:1.4")
    testImplementation("org.conscrypt:conscrypt-openjdk-uber:2.5.2")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.14.1")
    testImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")
    testImplementation("com.squareup.okhttp3:okhttp-tls:4.12.0")
}

tasks.configureEach {
    if (name == "packageDebugUnitTestForUnitTest") dependsOn("copyFlutterAssetsDebug")
}

configurations.matching { it.name.contains("UnitTest", ignoreCase = true) }.configureEach {
    exclude(group = "org.conscrypt", module = "conscrypt-android")
    for (module in listOf("bcprov-jdk18on", "bcutil-jdk18on", "bcpkix-jdk18on")) exclude(group = "org.bouncycastle", module = module)
}
