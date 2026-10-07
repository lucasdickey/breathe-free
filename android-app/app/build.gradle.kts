import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.breathefree.app"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.breathefree.app"
        minSdk = 26
        targetSdk = 36
        versionCode = 2
        versionName = "2.0"
    }

    // Release builds are signed with the key described in keystore.properties when that file
    // exists (storeFile, storePassword, keyAlias, keyPassword), else with the debug key so a
    // fresh checkout still produces an installable APK.
    val keystoreFile = rootProject.file("keystore.properties")
    signingConfigs {
        if (keystoreFile.exists()) {
            val props = Properties().apply { keystoreFile.inputStream().use { load(it) } }
            create("release") {
                storeFile = rootProject.file(props.getProperty("storeFile"))
                storePassword = props.getProperty("storePassword")
                keyAlias = props.getProperty("keyAlias")
                keyPassword = props.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
    }

    testOptions {
        unitTests.isIncludeAndroidResources = true
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2026.09.00")
    implementation(composeBom)
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")

    testImplementation("junit:junit:4.13.2")
    // Screenshot tests: the real UI rendered on the JVM (run with -Pscreenshots).
    testImplementation("org.robolectric:robolectric:4.17")
    testImplementation("androidx.test:core:1.7.0")
    testImplementation("androidx.compose.ui:ui-test-junit4")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}

tasks.withType<Test>().configureEach {
    systemProperty("screenshots", providers.gradleProperty("screenshots").isPresent.toString())
    providers.gradleProperty("robolectricRepo").orNull?.let { systemProperty("robolectric.dependency.repo.url", it) }
    // Robolectric's Android 16 runtime reaches into this JDK package.
    jvmArgs("--add-opens=java.base/jdk.internal.access=ALL-UNNAMED")
    testLogging {
        showStandardStreams = true
        events("passed", "failed")
        exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL
    }
}
