import groovy.json.JsonSlurper
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
// A connected-test run without local.properties may pass a throwaway digest with -P.
val reviewCodeDigest = localProperties.getProperty("PLAY_REVIEW_CODE_SHA256")
    ?: providers.gradleProperty("PLAY_REVIEW_CODE_SHA256").getOrElse("")
val testKey = localProperties.getProperty("REVENUECAT_TEST_KEY", "")
val uploadKeyStore = localProperties.getProperty("PLAY_UPLOAD_KEYSTORE", "")
val uploadKeyAlias = localProperties.getProperty("PLAY_UPLOAD_KEY_ALIAS", "")
val uploadStorePassword = localProperties.getProperty("PLAY_UPLOAD_STORE_PASSWORD", "")
val uploadKeyPassword = localProperties.getProperty("PLAY_UPLOAD_KEY_PASSWORD", uploadStorePassword)

/**
 * Log together (Firebase) reads the Console's google-services.json without the
 * Google Services plugin, so the app still builds without it: sharing is then
 * hidden. The file is ignored by git (android/app/google-services.json).
 */
data class FirebaseValues(val apiKey: String, val appId: String, val projectId: String, val senderId: String, val webClientId: String)

@Suppress("UNCHECKED_CAST")
fun readFirebase(file: File, packageName: String): FirebaseValues? {
    if (!file.isFile) return null
    val root = JsonSlurper().parse(file) as Map<String, Any?>
    val project = root["project_info"] as? Map<String, Any?> ?: return null
    val clients = root["client"] as? List<Map<String, Any?>> ?: return null
    val client = clients.firstOrNull {
        ((it["client_info"] as? Map<String, Any?>)?.get("android_client_info") as? Map<String, Any?>)?.get("package_name") == packageName
    } ?: return null
    val appId = (client["client_info"] as Map<String, Any?>)["mobilesdk_app_id"] as? String ?: return null
    val apiKey = (client["api_key"] as? List<Map<String, Any?>>)?.firstOrNull()?.get("current_key") as? String ?: return null
    // The web client (type 3) is the audience Google sign-in tokens are issued for.
    val oauth = (client["oauth_client"] as? List<Map<String, Any?>>).orEmpty() +
        (((client["services"] as? Map<String, Any?>)?.get("appinvite_service") as? Map<String, Any?>)?.get("other_platform_oauth_client") as? List<Map<String, Any?>>).orEmpty()
    val webClientId = oauth.firstOrNull { it["client_type"].toString() == "3" }?.get("client_id") as? String ?: ""
    return FirebaseValues(apiKey, appId, project["project_id"] as? String ?: return null, project["project_number"]?.toString() ?: "", webClientId)
}

val googleServicesFile = file("google-services.json")
val firebase = readFirebase(googleServicesFile, "com.jackwallner.baby")

val validateReleaseConfiguration = tasks.register("validateReleaseConfiguration") {
    doLast {
        check(firebase != null) {
            "Put the Firebase Console's google-services.json (Android app com.jackwallner.baby) at android/app/google-services.json before a release build; Log together needs it."
        }
        check(firebase!!.webClientId.isNotBlank()) {
            "google-services.json has no web OAuth client: enable Google sign-in in Firebase Authentication and add the upload and Play signing SHA-1s, then download it again."
        }
        check(playKey.startsWith("goog_")) { "Set REVENUECAT_PLAY_KEY in android/local.properties before a release build." }
        check(reviewCodeDigest.matches(Regex("[a-f0-9]{64}"))) { "Set PLAY_REVIEW_CODE_SHA256 (lowercase SHA-256 hex of the reviewer code) in android/local.properties before a release build." }
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
        versionCode = 2
        versionName = "1.0.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        // Every connected test starts from a clean install: no setup, no log.
        testInstrumentationRunnerArguments["clearPackageData"] = "true"
        buildConfigField("String", "REVENUECAT_API_KEY", "\"$testKey\"")
        buildConfigField("String", "PLAY_REVIEW_CODE_SHA256", "\"$reviewCodeDigest\"")
        buildConfigField("String", "FIREBASE_API_KEY", "\"${firebase?.apiKey.orEmpty()}\"")
        buildConfigField("String", "FIREBASE_APP_ID", "\"${firebase?.appId.orEmpty()}\"")
        buildConfigField("String", "FIREBASE_PROJECT_ID", "\"${firebase?.projectId.orEmpty()}\"")
        buildConfigField("String", "FIREBASE_SENDER_ID", "\"${firebase?.senderId.orEmpty()}\"")
        buildConfigField("String", "FIREBASE_WEB_CLIENT_ID", "\"${firebase?.webClientId.orEmpty()}\"")
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
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.10.2")
    // Log together: Firebase Auth (Google sign-in through Credential Manager) and Firestore.
    implementation(platform("com.google.firebase:firebase-bom:35.0.2"))
    implementation("com.google.firebase:firebase-auth")
    implementation("com.google.firebase:firebase-firestore")
    implementation("androidx.credentials:credentials:1.6.0")
    implementation("androidx.credentials:credentials-play-services-auth:1.6.0")
    implementation("com.google.android.libraries.identity.googleid:googleid:1.2.1")

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
