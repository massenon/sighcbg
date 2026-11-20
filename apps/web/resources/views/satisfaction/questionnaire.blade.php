<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex, nofollow">
    <meta name="referrer" content="no-referrer">
    <title>{{ $d['titre'] }}</title>
    <link rel="icon" href="{{ asset('favicon.ico') }}">
    <link rel="stylesheet" href="{{ asset('css/jetons.css') }}">
    <link rel="stylesheet" href="{{ asset('css/satisfaction.css') }}">
</head>
<body>
{{-- Page PUBLIQUE tendue à des inconnus : aucun lien vers le logiciel, aucun cookie, aucune ressource externe. Le formulaire est rendu depuis les champs
     PUBLIÉS par la mère (engendrés par le générateur du domaine) ; la réponse est chiffrée dans le navigateur avant de partir (js/satisfaction.js). --}}
<main class="page">
    <header class="carte entete">
        <img src="{{ asset('img/logo.png') }}" alt="" width="56" height="56">
        <div>
            <p class="clinique">{{ $d['clinique'] }}</p>
            @if((string) config('identite.devise') !== '')<p class="devise">{{ config('identite.devise') }}</p>@endif
        </div>
    </header>

    <section class="carte" aria-labelledby="sat-titre">
        <h1 id="sat-titre">{{ $d['titre'] }}</h1>
        @if ($d['description'] !== '')
            <p class="description">{{ $d['description'] }}</p>
        @endif
        <p class="mention">Questionnaire ANONYME : on ne vous demande ni votre nom, ni votre numéro de dossier, et aucune question ne porte sur votre santé.
            Votre réponse est chiffrée sur votre téléphone avant de partir : seule la clinique peut la lire.</p>

        <p id="sat-sans-js" class="etat erreur">Ce questionnaire chiffre votre réponse dans votre navigateur : activez JavaScript pour répondre.</p>

        <form id="sat-formulaire" hidden novalidate>
            @foreach ($d['champs'] as $c)
                <div class="champ">
                    <label for="sat-{{ $c['nom'] }}">{{ $c['libelle'] }}@if ($c['requis']) <span class="requis" aria-hidden="true">*</span>@endif</label>
                    @if ($c['type'] === 'select')
                        <select id="sat-{{ $c['nom'] }}" name="{{ $c['nom'] }}" @if ($c['requis']) required @endif>
                            <option value="">Choisir…</option>
                            @foreach ($c['options'] as $o)
                                <option value="{{ $o }}">{{ $o }}</option>
                            @endforeach
                        </select>
                    @else
                        <textarea id="sat-{{ $c['nom'] }}" name="{{ $c['nom'] }}" rows="{{ $c['lignes'] }}" maxlength="1000" @if ($c['requis']) required @endif></textarea>
                    @endif
                </div>
            @endforeach
            <p id="sat-etat" class="etat" role="status" aria-live="polite"></p>
            <button type="submit" class="btn">Envoyer ma réponse</button>
        </form>

        <div id="sat-merci" class="merci" hidden>
            <p class="titre-merci">Merci !</p>
            <p>Votre réponse a bien été envoyée.</p>
        </div>
    </section>
</main>
<script type="application/json" id="sat-donnees">@json($d)</script>
<script src="{{ asset('js/satisfaction.js') }}" defer></script>
</body>
</html>
