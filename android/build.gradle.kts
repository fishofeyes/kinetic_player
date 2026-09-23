group = "com.keepwan.kinetic_player"
version = "2.1.1"

buildscript {
    val kotlinVersion = "2.4.10"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.3.2")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
        maven(url = uri("https://maven.aliyun.com/repository/public"))
        maven(url = uri("https://jitpack.io"))
    }
}

plugins {
    id("com.android.library")
}

android {
    namespace = "com.keepwan.kinetic_player"

    compileSdk = 37

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
        getByName("test") {
            java.srcDirs("src/test/kotlin")
        }
    }

    defaultConfig {
        minSdk = 24
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
            all {
                it.useJUnitPlatform()

                it.outputs.upToDateWhen { false }

                it.testLogging {
                    events("passed", "skipped", "failed", "standardOut", "standardError")
                    showStandardStreams = true
                }
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    val gsyVersion = "13.2.1"

    // Android-only: GSYVideoPlayer v13.1.0 (Maven Central, recommended).
    implementation("io.github.carguo:gsyvideoplayer-java:$gsyVersion")
    implementation("io.github.carguo:gsyvideoplayer-exo2:$gsyVersion")
    implementation("io.github.carguo:gsyvideoplayer-arm64:$gsyVersion")
    implementation("com.github.bilibili:DanmakuFlameMaster:0.9.25")

    testImplementation("org.jetbrains.kotlin:kotlin-test")
    testImplementation("org.mockito:mockito-core:5.0.0")
}
