group = "dev.ifiokjr.mpgenai"
version = "1.0-SNAPSHOT"

buildscript {
    val kotlinVersion = "2.3.20"
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:9.0.1")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
    id("org.jlleitschuh.gradle.ktlint") version "14.2.0"
}

android {
    namespace = "dev.ifiokjr.mpgenai"
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
    }

    defaultConfig {
        minSdk = 24
    }

    androidResources {
        noCompress += listOf("bin", "litertlm", "task", "tflite")
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("com.google.ai.edge.localagents:localagents-fc:0.1.0")
    implementation("com.google.ai.edge.localagents:localagents-rag:0.3.0")
    // tasks-genai's published POM omits the MPImage classes used by its public API.
    implementation("com.google.mediapipe:tasks-core:1.0.0")
    implementation("com.google.mediapipe:tasks-genai:0.10.35")
    implementation("com.google.mediapipe:tasks-vision-image-generator:0.10.26.1")
}
