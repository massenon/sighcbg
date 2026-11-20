<!doctype html>
<html lang="fr">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex, nofollow">
    <title>Connexion — Relais SIGH-CBG</title>
    <link rel="icon" href="{{ asset('favicon.ico') }}" sizes="16x16 32x32 48x48">
    <link rel="apple-touch-icon" href="{{ asset('apple-touch-icon.png') }}">
    <link rel="stylesheet" href="{{ asset('css/jetons.css') }}">
    <link rel="stylesheet" href="{{ asset('css/panneau.css') }}">
</head>
<body>
<main class="accueil">
    <section class="accueil-carte" aria-labelledby="connexion-titre">
        <div class="accueil-tete">
            <img src="{{ asset('img/logo.png') }}" alt="" width="72" height="72">
            <p class="marque-nom">{{ config('identite.nom') }}</p>
            @if((string) config('identite.devise') !== '')<p class="devise">{{ config('identite.devise') }}</p>@endif
        </div>
        <form class="accueil-corps" method="post" action="{{ route('panneau.connexion.envoi') }}">
            @csrf
            <h1 id="connexion-titre">Relais SIGH-CBG</h1>
            <p class="sous-titre">Accès réservé à l'administrateur système.</p>
            <label class="champ" for="courriel"><span>Courriel</span>
                <input id="courriel" name="courriel" type="email" value="{{ old('courriel') }}" autocomplete="username" required autofocus></label>
            <label class="champ" for="mot_de_passe"><span>Mot de passe</span>
                <input id="mot_de_passe" name="mot_de_passe" type="password" autocomplete="current-password" required></label>
            @error('courriel') <div class="erreur" role="alert">{{ $message }}</div> @enderror
            <button class="btn" type="submit">Se connecter</button>
        </form>
    </section>
</main>
</body>
</html>
