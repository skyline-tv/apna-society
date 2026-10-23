allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Align FlutterFire plugins with firebase_core 3.15.2 (BoM 33.16.0).
// BoM 35.1.0 pulls Play services compiled with Kotlin 2.4 metadata, which
// this project's Kotlin 2.2.20 plugin cannot read.
extra["FlutterFire"] = hashMapOf("FirebaseSDKVersion" to "33.16.0")

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
