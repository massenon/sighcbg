<!doctype html>
<html lang="fr">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex, nofollow">
    <title>{{ $titre ?? 'Panneau du relais' }} · SIGH-CBG</title>
    <link rel="icon" href="{{ asset('favicon.ico') }}" sizes="16x16 32x32 48x48">
    <link rel="apple-touch-icon" href="{{ asset('apple-touch-icon.png') }}">
    <link rel="stylesheet" href="{{ asset('css/jetons.css') }}">
    <link rel="stylesheet" href="{{ asset('css/panneau.css') }}">
    @livewireStyles
</head>
<body>
@php
    // Entrées groupées : route => [libellé, icône]. Un seul endroit décide de la navigation, du fil d'Ariane et du titre de l'onglet.
    $groupes = [
        'Supervision' => [
            'panneau.tableau' => ['Tableau de bord du relais', 'tableau'],
            'panneau.clinique' => ['Tableau de bord de la clinique', 'clinique'],
            'panneau.synchronisation' => ['Synchronisation', 'synchro'],
            'panneau.alertes' => ['Alertes et notifications', 'alerte'],
        ],
        'Appareils et données' => [
            'panneau.appareils' => ['Appareils', 'appareil'],
            'panneau.boites' => ['Boîtes aux lettres', 'boite'],
            'panneau.codes' => ['Codes d’appairage', 'cle'],
            'panneau.indicateurs' => ['Indicateurs reçus', 'indicateur'],
            'panneau.consultation' => ['Consultation des copies', 'oeil'],
        ],
        'Sécurité' => [
            'panneau.journal' => ['Journal d’audit du relais', 'journal'],
            'panneau.superadmin' => ['Comptes superadmin', 'comptes'],
            'panneau.opacite' => ['Preuve d’opacité', 'cadenas'],
        ],
        'Exploitation' => [
            'panneau.parametres' => ['Paramètres du relais', 'reglages'],
            'panneau.hebergement' => ['Hébergement', 'serveur'],
            'panneau.sauvegarde' => ['Sauvegarde du relais', 'base'],
        ],
    ];
    // Réservé au superadmin : un compte qui ne l'est pas ne voit aucune entrée (et n'ouvre aucune route).
    $visibles = auth()->user()?->superadmin === true ? $groupes : [];
    $courant = null; $groupeCourant = null;
    foreach ($visibles as $nomGroupe => $entrees) {
        foreach ($entrees as $route => [$libelle]) {
            if (request()->routeIs($route)) { $courant = $libelle; $groupeCourant = $nomGroupe; }
        }
    }
    $devise = (string) config('identite.devise');
@endphp
@include('layouts._icones')
<a class="lien-evitement" href="#contenu">Aller au contenu</a>
<div class="coque" id="coque">
    <aside class="barre" id="barre" aria-label="Navigation du panneau">
        <div class="barre-tete">
            <img src="{{ asset('img/logo.png') }}" alt="" width="44" height="44">
            <div class="marque">
                <p class="marque-nom">{{ config('identite.nom') }}</p>
                <p class="marque-sous">Relais en ligne</p>
            </div>
            <button type="button" class="barre-fermer" id="menu-fermer" aria-label="Fermer le menu"><svg class="icone" aria-hidden="true"><use href="#i-fermer"/></svg></button>
        </div>
        @if($devise !== '')<p class="devise barre-devise">{{ $devise }}</p>@endif
        <nav class="barre-nav" aria-label="Pages du panneau">
            @foreach($visibles as $nomGroupe => $entrees)
                <p class="nav-groupe" id="g-{{ $loop->index }}">{{ $nomGroupe }}</p>
                <ul class="nav-liste" aria-labelledby="g-{{ $loop->index }}">
                    @foreach($entrees as $route => [$libelle, $icone])
                        <li><a class="nav-lien" href="{{ route($route) }}" @if(request()->routeIs($route)) aria-current="page" @endif><svg class="icone" aria-hidden="true"><use href="#i-{{ $icone }}"/></svg><span>{{ $libelle }}</span></a></li>
                    @endforeach
                </ul>
            @endforeach
        </nav>
        <div class="barre-pied">
            <p class="utilisateur">{{ auth()->user()?->email }}<small>Superadmin du relais</small></p>
            <form method="post" action="{{ route('panneau.deconnexion') }}">@csrf <button type="submit" class="deconnexion"><svg class="icone" aria-hidden="true"><use href="#i-sortie"/></svg>Se déconnecter</button></form>
            <p class="version">SIGH-CBG · relais {{ config('identite.version') }}</p>
        </div>
    </aside>
    <div class="voile" id="voile"></div>
    <div class="zone">
        <header class="haut">
            <button type="button" class="burger" id="menu-ouvrir" aria-controls="barre" aria-expanded="false" aria-label="Ouvrir le menu"><svg class="icone" aria-hidden="true"><use href="#i-menu"/></svg></button>
            <nav class="ariane" aria-label="Fil d’Ariane">
                <ol>
                    <li><a href="{{ route('panneau.tableau') }}">Panneau</a></li>
                    @if($groupeCourant)<li class="ariane-groupe"><span>{{ $groupeCourant }}</span></li>@endif
                    @if($courant)<li><span aria-current="page">{{ $courant }}</span></li>@endif
                </ol>
            </nav>
        </header>
        <main class="contenu" id="contenu" tabindex="-1">
            {{ $slot }}
        </main>
    </div>
</div>
<script src="{{ asset('js/panneau.js') }}" defer></script>
@livewireScripts
</body>
</html>
