<header class="page-entete">
    <h1>{{ $titre }}</h1>
    <p class="sous-titre">{{ $description }}</p>
    @isset($regle)<p class="note">{{ $regle }}</p>@endisset
</header>
