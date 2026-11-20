# Signer l'application mobile Android (E4702)

Un APK de production est **signé par la clé de la clinique**. Le dépôt ne contient **aucune clé** et le build « release » **échoue** tant qu'aucune clé complète n'est fournie : il n'est plus jamais signé avec la clé de débogage. Le build de débogage (`flutter run`) n'est pas concerné.

> Cette procédure n'a **pas** été exécutée avec le SDK Android (absent du poste de développement) : la logique de signature a été éprouvée dans un projet Gradle isolé (échec sans clé, échec si le fichier est introuvable, passage avec une clé complète). Le premier build réel d'un APK signé reste à faire sur un poste équipé du SDK Android.

## 1. Créer le fichier de clés (une seule fois, par la clinique)

```bash
keytool -genkeypair -v -keystore <chemin-hors-depot>/sigh-mobile.jks \
  -alias <alias-a-choisir> -keyalg RSA -keysize 2048 -validity 10000
```

* `-validity 10000` : environ 27 ans (Google Play en exige 25 ans au moins pour publier ; la durée ne se prolonge pas ensuite).
* `keytool` demande deux mots de passe (fichier de clés, clé) et l'identité du titulaire : saisir celle de la clinique, jamais celle d'une personne.
* Choisir des mots de passe longs et aléatoires ; ne jamais les écrire dans le dépôt, un message ou un document partagé.
* Le fichier de clés se crée **hors du dépôt** (dossier privé de la clinique), jamais sous `apps/`.

## 2. Sauvegarder (obligatoire)

Copier le fichier de clés **et** ses mots de passe en **au moins deux lieux sûrs hors du dépôt** (coffre de mots de passe de la clinique, support chiffré conservé séparément). Vérifier la copie (`keytool -list -keystore <copie>`).

**Si la clé est perdue** : un APK ne se met à jour que s'il est signé par la même clé. Sans elle, aucune mise à jour n'est possible : il faut publier une **nouvelle application** (autre identité de signature), chaque téléphone doit **désinstaller** l'ancienne et perd ses données locales non synchronisées. Si la clé est **divulguée**, n'importe qui peut signer une fausse mise à jour : la remplacer et en informer la Direction.

## 3. Renseigner la signature sur le poste de construction

Deux voies équivalentes (le fichier l'emporte sur l'environnement pour chaque valeur renseignée).

**Fichier** : copier `apps/mobile/android/key.properties.exemple` en `apps/mobile/android/key.properties` (ignoré par git) et renseigner `storeFile` (absolu, ou relatif au dossier `android/`), `storePassword`, `keyAlias`, `keyPassword`.

**Variables d'environnement** : `SIGH_KEYSTORE`, `SIGH_KEYSTORE_PASSWORD`, `SIGH_KEY_ALIAS`, `SIGH_KEY_PASSWORD`.

## 4. Construire l'APK signé

```bash
cd apps/mobile
flutter build apk --release \
  --dart-define=SIGH_RELAIS=https://sighnbg.cliniquebaguidi.com \
  --dart-define=SIGH_VERSION=1.0.0+1
```

Résultat : `build/app/outputs/flutter-apk/app-release.apk`. Contrôler la signature : `apksigner verify --print-certs app-release.apk` (outil du SDK Android).

Sans clé complète, la construction s'arrête avec **« SIGNATURE ANDROID ABSENTE »** en nommant les valeurs manquantes ; si le fichier de clés est introuvable, elle le dit aussi. Aucun APK n'est alors produit.
