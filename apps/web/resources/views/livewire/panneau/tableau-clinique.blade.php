<div wire:poll.30s>
    @include('livewire.panneau._entete', ['titre' => 'Tableau de bord de la clinique', 'description' => 'Les indicateurs agrégés que la mère publie : des nombres, rien d’autre. Lecture seule.', 'regle' => 'Ce tableau ne modifie rien : aucun paramètre de la clinique ne se règle depuis le web.'])

    <div class="note" role="note" id="note-visibilite">
        <strong>Ce que le relais voit.</strong> Des <strong>agrégats non nominatifs</strong> : des compteurs et des montants en FCFA (patients actifs, factures du mois, articles sous seuil,
        échéances en retard…), un code d’obligation fiscale et sa date, des identifiants techniques de postes, un numéro de version. Ils ne parviennent ici que si la Direction a ouvert,
        aux Paramètres du poste mère, l’interrupteur « publier les indicateurs au relais » ; chaque instantané est signé avec le secret de la mère.
        <br><strong>Ce que le relais ne voit toujours pas.</strong> Aucun dossier, aucun nom, aucun code patient, téléphone, adresse, motif, diagnostic, fournisseur ni agent : tout le contenu
        des dossiers voyage dans des enveloppes chiffrées de bout en bout, dont le relais ne détient pas la clé.
    </div>

    @if($jamais)
        <div class="carte" id="jamais-publie">
            <h2>Jamais publié</h2>
            <p>Aucun instantané n’a encore été reçu de la mère. L’interrupteur « publier les indicateurs au relais » est <strong>fermé par défaut</strong> aux Paramètres du poste mère :
                tant que la Direction ne l’a pas ouvert, ce tableau reste vide, et c’est voulu. Une fois ouvert, le premier instantané arrive au prochain tour de la mère.</p>
        </div>
    @else
        <div class="grille">
            <div class="carte" id="fraicheur">
                <h2>Fraîcheur</h2>
                @if($ancien)
                    <span class="puce alerte">Trop ancien</span>
                    <p>Dernier instantané reçu {{ \App\Relais\Format::depuis($recuLe) }}, au-delà de {{ $seuilTexte }}. La mère ne publie plus : interrupteur refermé, mère éteinte ou liaison coupée.</p>
                @else
                    <span class="puce ok">À jour</span>
                    <p>Dernier instantané reçu {{ \App\Relais\Format::depuis($recuLe) }}.</p>
                @endif
                <p class="doux">Calculé par la mère le {{ \App\Relais\Format::date($genereLe) }}. {{ $nbInstantanes }} instantané(s) conservé(s).</p>
            </div>
            <div class="carte">
                <h2>Prochaine échéance fiscale</h2>
                @if($prochaineCode)
                    <div class="valeur">{{ $prochaineCode }}</div><p>{{ \Carbon\Carbon::parse($prochaineDate)->format('d/m/Y') }}</p>
                @else
                    <div class="valeur">non disponible</div><p>aucune échéance à venir reçue.</p>
                @endif
            </div>
            <div class="carte">
                <h2>Application</h2>
                <div class="valeur">{{ $version }}</div>
                <p>Jeu de la clinique : <span class="puce {{ $etatJeu === 'production' ? 'ok' : 'attention' }}">{{ $etatJeu === 'production' ? 'production' : 'démonstration' }}</span></p>
            </div>
        </div>

        <div class="grille" id="cartes-indicateurs">
            @foreach($cartes as $cle => $carte)
                <div class="carte" data-indicateur="{{ $cle }}">
                    <h2>{{ $carte['libelle'] }}</h2>
                    <div class="valeur @unless($carte['disponible']) indisponible @endunless">{{ $carte['valeur'] }}</div>
                    @if($carte['variation'])
                        <span class="puce {{ $carte['variation']['ton'] }}" title="Variation par rapport à l’instantané précédent">{{ $carte['variation']['texte'] }}</span>
                        <span class="doux"> vs instantané précédent</span>
                    @elseif($carte['disponible'])
                        <span class="doux">pas de variation calculable</span>
                    @endif
                </div>
            @endforeach
        </div>
        <p class="doux">Les cumuls « du mois » repartent de zéro au changement de mois : une baisse en début de mois n’est pas une régression. « Non disponible » : la mère n’a reçu aucune fiche de ce domaine, ce n’est pas un zéro.</p>

        <div class="carte" id="evolution">
            <h2>Évolution sur les derniers instantanés</h2>
            <label for="courbe">Indicateur&nbsp;:</label>
            <select id="courbe" wire:model.live="courbe">
                @foreach($choixCourbes as $cle => $libelle)
                    <option value="{{ $cle }}">{{ $libelle }}</option>
                @endforeach
            </select>
            @if($courbeDonnees['n'] === 0)
                <p class="vide">Aucune valeur disponible pour « {{ $courbeLibelle }} » sur les instantanés conservés.</p>
            @else
                <svg class="courbe" viewBox="0 0 600 140" role="img" aria-label="Évolution de {{ $courbeLibelle }} sur {{ $courbeDonnees['n'] }} instantané(s)" preserveAspectRatio="none">
                    <line class="courbe-axe" x1="10" y1="130" x2="590" y2="130"/>
                    @if($courbeDonnees['n'] > 1)
                        <polyline class="courbe-trait" fill="none" points="{{ collect($courbeDonnees['points'])->map(fn ($p) => $p['x'].','.$p['y'])->implode(' ') }}"/>
                    @endif
                    @foreach($courbeDonnees['points'] as $p)
                        <circle class="courbe-point" cx="{{ $p['x'] }}" cy="{{ $p['y'] }}" r="3"/>
                    @endforeach
                </svg>
                <p class="doux">{{ $courbeLibelle }} : de {{ \App\Relais\VueIndicateurs::formater($courbeDonnees['min'], $courbeFormat) }} à {{ \App\Relais\VueIndicateurs::formater($courbeDonnees['max'], $courbeFormat) }} entre le {{ \App\Relais\Format::date($courbeDonnees['debut']) }} et le {{ \App\Relais\Format::date($courbeDonnees['fin']) }} ({{ $courbeDonnees['n'] }} point(s)).</p>
            @endif
        </div>

        <div class="carte" id="postes">
            <h2>Dernière synchronisation de chaque poste</h2>
            @if(count($postes) === 0)
                <p class="vide">Aucun poste connu de la mère n’est listé dans le dernier instantané.</p>
            @else
                <table>
                    <thead><tr><th>Appareil (identifiant technique)</th><th>Dernière synchronisation</th></tr></thead>
                    <tbody>
                    @foreach($postes as $p)
                        <tr>
                            <td><code>{{ $p['appareil'] }}</code></td>
                            <td>@if($p['derniere_synchro'] > 0){{ \App\Relais\Format::date($p['derniere_synchro']) }} ({{ \App\Relais\Format::depuis($p['derniere_synchro']) }})@else jamais synchronisé @endif</td>
                        </tr>
                    @endforeach
                    </tbody>
                </table>
            @endif
        </div>
    @endif
</div>
