allprojects {
    repositories {
        google()
        mavenCentral()
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

// Older Flutter plugins (e.g. tdlib) omit `namespace`, which AGP 8+ requires.
subprojects {
    pluginManager.withPlugin("com.android.library") {
        val android = extensions.findByName("android") ?: return@withPlugin
        try {
            val getNs = android.javaClass.methods.firstOrNull {
                it.name == "getNamespace" && it.parameterCount == 0
            }
            val current = getNs?.invoke(android) as? String
            if (!current.isNullOrBlank()) return@withPlugin

            val manifest = file("src/main/AndroidManifest.xml")
            var pkg = "com.flutter.${project.name.replace('-', '_')}"
            if (manifest.exists()) {
                val match = Regex("""package\s*=\s*"([^"]+)"""")
                    .find(manifest.readText())
                if (match != null) pkg = match.groupValues[1]
            }
            val setNs = android.javaClass.methods.firstOrNull {
                it.name == "setNamespace" && it.parameterCount == 1
            }
            setNs?.invoke(android, pkg)
        } catch (_: Exception) {
            // Plugin may already configure namespace correctly.
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
