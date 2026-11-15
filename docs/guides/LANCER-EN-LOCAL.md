# Lancer SIGH-CBG en local

Prérequis : Git, Flutter (avec Windows Desktop et Visual Studio 2022 C++ sous Windows), Node 20+, PostgreSQL 15+, PHP 8.2+ et Composer (relais uniquement).

## 1. Cloner

```bash
git clone https://github.com/massenon/sighcbg.git
cd sighcbg
git checkout livraison/baguidi-v19
```

## 2. Vérifier avant de lancer

```bash
cd packages/domaine && dart pub get && dart test && cd ../..
cd packages/sync_dart && dart pub get && dart test && cd ../..
cd packages/rbac && node --test && cd ../..
node tools/baguidi/controle-identite.mjs
```

## 3. Lancer le poste (fileul)

```bash
cd apps/poste
flutter pub get
flutter run -d windows --dart-define=SIGH_MODE=fileul
```

Sous Linux, remplacer `-d windows` par `-d linux`. Le premier lancement charge le jeu de démonstration Baguidi.

## 4. Lancer la mère

```bash
cd apps/poste
flutter run -d windows --dart-define=SIGH_MODE=mere
```

## 5. Relais web en local (PostgreSQL)

```sql
CREATE USER sigh_relais WITH PASSWORD 'choisir-un-mot-de-passe';
CREATE DATABASE sigh_relais OWNER sigh_relais;
```

```bash
cd apps/web
composer install
cp .env.example .env
php artisan key:generate
# renseigner DB_PASSWORD et RELAIS_SECRET_MERE dans .env
php artisan migrate
php artisan relais:superadmin votre@courriel.bj --mot-de-passe='douze-caracteres-minimum'
php artisan serve
```

## 6. Suites complètes (longues)

```bash
cd apps/poste && flutter test          # environ 20 minutes, seule sur la machine
cd apps/mobile && flutter test
cd apps/web && php artisan test        # SQLite en mémoire
npm run banc:sync                      # banc de synchronisation de référence
```

## 7. Installateur Windows

```bat
cd apps\poste
build_windows.bat
```

Résultat : `build\installer\SIGH_Poste_Setup_<version>.exe` et son `.sha256` (Inno Setup 6 requis).
