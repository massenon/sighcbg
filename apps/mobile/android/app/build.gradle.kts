plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// SIGNATURE DE PRODUCTION (E4702). Aucune clé n'est dans le dépôt : elle se lit dans `android/key.properties` (ignoré par git, modèle `key.properties.exemple`) ou, à défaut,
// dans les variables d'environnement SIGH_KEYSTORE, SIGH_KEYSTORE_PASSWORD, SIGH_KEY_ALIAS, SIGH_KEY_PASSWORD. SANS clé complète, la construction « release » ÉCHOUE (plus de
// signature avec la clé de débogage). Le build de débogage n'est pas concerné. Procédure : docs/guides/SIGNATURE-ANDROID.md.
val cleProprietes = java.util.Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun cleSignature(nomPropriete: String, nomEnv: String): String? =
    (cleProprietes.getProperty(nomPropriete) ?: System.getenv(nomEnv))?.trim()?.takeIf { it.isNotEmpty() }
val signatureFichier = cleSignature("storeFile", "SIGH_KEYSTORE")
val signatureMotDePasse = cleSignature("storePassword", "SIGH_KEYSTORE_PASSWORD")
val signatureAlias = cleSignature("keyAlias", "SIGH_KEY_ALIAS")
val signatureMotDePasseCle = cleSignature("keyPassword", "SIGH_KEY_PASSWORD")
val signatureManquante = listOf(
    "storeFile (SIGH_KEYSTORE)" to signatureFichier,
    "storePassword (SIGH_KEYSTORE_PASSWORD)" to signatureMotDePasse,
    "keyAlias (SIGH_KEY_ALIAS)" to signatureAlias,
    "keyPassword (SIGH_KEY_PASSWORD)" to signatureMotDePasseCle,
).filter { it.second == null }.map { it.first }

android {
    namespace = "bj.baguidi.sigh_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "bj.baguidi.sigh_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (signatureManquante.isEmpty()) {
            create("production") {
                storeFile = rootProject.file(signatureFichier!!)
                storePassword = signatureMotDePasse
                keyAlias = signatureAlias
                keyPassword = signatureMotDePasseCle
            }
        }
    }

    buildTypes {
        release {
            // Jamais la clé de débogage : sans clé de production, aucune signature n'est posée et la garde ci-dessous interrompt la construction.
            signingConfig = signingConfigs.findByName("production")
        }
    }
}

// LA GARDE : toute construction « release » (assembleRelease, bundleRelease, packageRelease) s'interrompt, avec un message clair, si la clé de production est incomplète ou illisible.
gradle.taskGraph.whenReady {
    val release = allTasks.any { it.project == project && Regex("^(assemble|bundle|package).*Release$").matches(it.name) }
    if (release) {
        if (signatureManquante.isNotEmpty()) {
            throw GradleException(
                "SIGNATURE ANDROID ABSENTE : le build release exige la clé de la clinique, et il manque " + signatureManquante.joinToString(", ") +
                    ". Renseigner android/key.properties (modèle : key.properties.exemple) ou les variables d'environnement SIGH_*. " +
                    "Voir docs/guides/SIGNATURE-ANDROID.md. Aucun APK n'a été produit, la clé de débogage n'est jamais utilisée pour une release."
            )
        }
        if (!rootProject.file(signatureFichier!!).exists()) {
            throw GradleException("SIGNATURE ANDROID : le fichier de clés « $signatureFichier » est introuvable (chemin relatif au dossier android/). Aucun APK n'a été produit.")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
