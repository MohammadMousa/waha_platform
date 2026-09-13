allprojects {
    repositories {
        google()
        mavenCentral()
        // Geidea POS terminal SDK (public, no credentials needed — see
        // waha-geidea-integration-specs.md §3.1). Confirmed against the
        // vendor's own sample app's build.gradle, extracted from
        // android/app/libs/Geidea_Android_SDK_v1.3.0.rar.
        maven { url = uri("https://dl.cloudsmith.io/public/geidea/pos-comm-sdk-ksa/maven/") }
    }
}

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
