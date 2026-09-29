import java.net.URI
import java.security.MessageDigest
import java.util.zip.ZipFile

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// The Immersal token is baked in from a file outside the repo, as on iOS
// (IMMERSAL_DEFAULT_TOKEN). A build without it asks for one on screen.
val immersalToken: String = File(System.getProperty("user.home"), ".config/aiseebin/immersal_pro_token")
    .takeIf { it.isFile }?.readText()?.trim().orEmpty()

// Immersal's native plugin (SDK 2.4.0) is published in its public Unity SDK repo
// but may not be redistributed, so it is fetched at build time and gitignored,
// like Vendor/Immersal/fetch.sh on iOS. Without it the app localizes in the cloud.
val posePluginDir = layout.buildDirectory.dir("poseplugin/jniLibs")
val fetchPosePlugin by tasks.registering {
    val out = posePluginDir.map { it.file("arm64-v8a/libPosePlugin.so") }
    outputs.file(out)
    doLast {
        val url = "https://raw.githubusercontent.com/immersal/imdk-unity/2.4.0/Runtime/Plugins/Android/poseplugin.aar"
        val sha = "ec3b01a85e2d4b71d1fa9973a46a50faa167b437a7bbac1acaac1be0ef926e5c"
        val target = out.get().asFile
        if (target.isFile) return@doLast
        val aar = File(temporaryDir, "poseplugin.aar")
        runCatching { URI(url).toURL().openStream().use { input -> aar.outputStream().use { input.copyTo(it) } } }
            .onFailure { logger.warn("Immersal plugin not fetched ($it); the app will localize in the cloud."); return@doLast }
        val got = MessageDigest.getInstance("SHA-256").digest(aar.readBytes()).joinToString("") { "%02x".format(it) }
        if (got != sha) error("poseplugin.aar sha256 mismatch: $got")
        ZipFile(aar).use { zip ->
            val entry = zip.getEntry("jni/arm64-v8a/libPosePlugin.so") ?: error("libPosePlugin.so not in the aar")
            target.parentFile.mkdirs()
            zip.getInputStream(entry).use { input -> target.outputStream().use { input.copyTo(it) } }
        }
    }
}
tasks.named("preBuild") { dependsOn(fetchPosePlugin) }

android {
    namespace = "com.flowsxr.aiseebin"
    compileSdk = 36
    ndkVersion = "27.3.13750724"

    defaultConfig {
        applicationId = "com.flowsxr.aiseebin"
        // Realtek's SDK floor; the Nova 5T runs Android 10 (29).
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
        buildConfigField("String", "IMMERSAL_TOKEN", "\"$immersalToken\"")

        ndk {
            // Immersal ships arm64 only, and so does every phone worth testing on.
            abiFilters += listOf("arm64-v8a")
        }
        externalNativeBuild {
            cmake {
                cppFlags += listOf("-std=c++17")
                arguments += listOf("-DANDROID_STL=c++_shared", "-DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON")
            }
        }
    }

    sourceSets["main"].jniLibs.srcDir(posePluginDir)

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.31.6"
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
        prefab = true
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    packaging {
        jniLibs {
            // The Realtek AAR and our CMake build both carry libc++_shared.so.
            pickFirsts += listOf("**/libc++_shared.so")
            useLegacyPackaging = true
        }
        resources {
            excludes += listOf("META-INF/atomicfu.kotlin_module", "META-INF/*.version")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }

    testOptions { unitTests.isReturnDefaultValues = true }
}

dependencies {
    // Realtek SDK, vendored as delivered (no Maven coordinates exist for it).
    implementation(files("libs/rtk-audioconnect-smartwear-1.8.48.aar"))
    implementation(files("libs/rtk-audioconnect-common-1.15.28.aar"))
    implementation(files("libs/rtk-audioconnect-core-1.9.10.jar"))
    implementation(files("libs/rtk-core-ktx-1.7.83.jar"))

    implementation("androidx.core:core-ktx:1.17.0")
    implementation("androidx.appcompat:appcompat:1.7.1")
    implementation("androidx.activity:activity-compose:1.12.3")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.10.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.10.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    implementation(platform("androidx.compose:compose-bom:2026.01.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-core")
    implementation("com.google.code.gson:gson:2.13.2")
    implementation("com.squareup.okhttp3:okhttp:5.3.2")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20250517")
}
