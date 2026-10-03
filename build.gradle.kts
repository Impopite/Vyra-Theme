plugins {
    id("java")
    id("org.jetbrains.intellij.platform") version "2.6.0"
}

group = providers.gradleProperty("pluginGroup").get()
version = providers.gradleProperty("pluginVersion").get()

repositories {
    mavenCentral()
    intellijPlatform {
        defaultRepositories()
    }
}

dependencies {
    intellijPlatform {
        create("IC", "2025.2")
    }
}

intellijPlatform {
    pluginConfiguration {
        id = "impog.vyra-theme"
        name = "Vyra Theme"
        version = project.version.toString()

        ideaVersion {
            sinceBuild = providers.gradleProperty("pluginSinceBuild").get()
            untilBuild = provider { null }
        }
    }

    publishing {
        token = providers.gradleProperty("publishToken").orElse(providers.environmentVariable("PUBLISH_TOKEN"))
    }

    pluginVerification {
        ides {
            recommended()
        }
    }
}
