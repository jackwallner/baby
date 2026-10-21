import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

val localProperties = Properties().apply {
    val localFile = rootProject.file("local.properties")
    if (localFile.exists()) localFile.inputStream().use(::load)
}

val playKey = localProperties.getProperty("REVENUECAT_PLAY_KEY", "")
val testKey = localProperties.getProperty("REVENUECAT_TEST_KEY", "")
val uploadKeyStore = localProperties.getProperty("PLAY_UPLOAD_KEYSTORE", "")
val uploadKeyAlias = localProperties.getProperty("PLAY_UPLOAD_KEY_ALIAS", "")
val uploadStorePassword = localProperties.getProperty("PLAY_UPLOAD_STORE_PASSWORD", "")
val uploadKeyPassword = localProperties.getProperty("PLAY_UPLOAD_KEY_PASSWORD", uploadStorePassword)

val validateReleaseConfiguration = tasks.register("validateReleaseConfiguration") {
    doLast {
        check(playKey.startsWith("goog_")) { "Set REVENUECAT_PLAY_KEY in android/local.properties before a release build." }
        check(uploadKeyStore.isNotBlank() && rootProject.file(uploadKeyStore).isFile) {
            "Set PLAY_UPLOAD_KEYSTORE to the external upload keystore before a release build."
        }
        check(uploadKeyAlias.isNotBlank() && uploadStorePassword.isNotBlank() && uploadKeyPassword.isNotBlank()) {
            "Set the upload key alias and passwords in ignored android/local.properties."
        }
    }
}

android {
    namespace = "com.jackwallner.baby"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.jackwallner.baby"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "1.0.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        // Every connected test starts from a clean install: no setup, no log.
        testInstrumentationRunnerArguments["clearPackageData"] = "true"
        buildConfigField("String", "REVENUECAT_API_KEY", "\"$testKey\"")
    }

    buildFeatures {
        buildConfig = true
        compose = true
    }

    if (uploadKeyStore.isNotBlank()) {
        signingConfigs {
            create("playUpload") {
                storeFile = rootProject.file(uploadKeyStore)
                storePassword = uploadStorePassword
                keyAlias = uploadKeyAlias
                keyPassword = uploadKeyPassword
            }
        }
    }

    buildTypes {
        debug {
            isDebuggable = true
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            if (uploadKeyStore.isNotBlank()) signingConfig = signingConfigs.getByName("playUpload")
            buildConfigField("String", "REVENUECAT_API_KEY", "\"$playKey\"")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
        // The release build as shipped (R8, no debug hooks), signed with the debug
        // key and with no RevenueCat key, so it can run on an emulator without
        // ever touching the production project.
        create("qa") {
            initWith(getByName("release"))
            signingConfig = signingConfigs.getByName("debug")
            buildConfigField("String", "REVENUECAT_API_KEY", "\"\"")
            matchingFallbacks += "release"
        }
    }

    sourceSets {
        getByName("qa").kotlin.directories.add("src/release/java")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    testOptions {
        animationsDisabled = true
        execution = "ANDROIDX_TEST_ORCHESTRATOR"
        unitTests.isReturnDefaultValues = true
    }
}

tasks.configureEach {
    if (name.contains("Release") && name != "validateReleaseConfiguration") {
        dependsOn(validateReleaseConfiguration)
    }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2026.06.01"))
    implementation("androidx.activity:activity-compose:1.12.0")
    implementation("androidx.core:core-ktx:1.18.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.10.0")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("com.revenuecat.purchases:purchases:10.23.2")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")

    debugImplementation("androidx.compose.ui:ui-tooling")
    androidTestImplementation(platform("androidx.compose:compose-bom:2026.06.01"))
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation("androidx.test:runner:1.7.0")
    androidTestImplementation("androidx.test:core-ktx:1.7.0")
    // Compose test pulls an older Espresso that calls InputManager.getInstance, gone on API 36.
    androidTestImplementation("androidx.test.espresso:espresso-core:3.7.0")
    androidTestUtil("androidx.test:orchestrator:1.6.1")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}
