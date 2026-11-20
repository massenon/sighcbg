<div>
    @include('livewire.panneau._entete', ['titre' => 'Comptes superadmin', 'description' => 'Les comptes qui administrent le relais : création par commande, mot de passe, sessions, double facteur.', 'regle' => 'Un compte se crée par commande (relais:superadmin, tâche cron à usage unique sur cPanel) : pas d’inscription publique. Mot de passe de 12 caractères au moins.'])
    @if($message)<p class="message" role="status">{{ $message }}</p>@endif
    @if($erreur)<p class="erreur" role="alert">{{ $erreur }}</p>@endif
    <div class="carte">
        <h2>Comptes</h2>
        <div class="table-wrap" tabindex="0"><table>
            <thead><tr><th>Courriel</th><th>Créé</th><th>Dernière connexion</th><th>Double facteur</th></tr></thead>
            <tbody>
            @foreach($comptes as $c)
                <tr>
                    <td>{{ $c->email }}</td>
                    <td>{{ $c->created_at ? $c->created_at->timezone('Africa/Porto-Novo')->format('d/m/Y') : 'n/d' }}</td>
                    <td>{{ \App\Relais\Format::depuis($c->derniere ? (int) $c->derniere : null) }}</td>
                    <td><span class="puce attention">Non activé</span></td>
                </tr>
            @endforeach
            </tbody>
        </table></div>
    </div>
    <div class="carte">
        <h2>Sessions ouvertes</h2>
        @if($sessions->isEmpty())
            <p class="vide">Aucune session enregistrée.</p>
        @else
            <div class="table-wrap" tabindex="0"><table>
                <thead><tr><th>Appareil</th><th>Adresse</th><th>Depuis</th></tr></thead>
                <tbody>
                @foreach($sessions as $s)
                    <tr><td>{{ \App\Livewire\Panneau\Superadmin::appareil($s->user_agent) }}</td><td>{{ \App\Livewire\Panneau\Superadmin::adresse($s->ip_address) }}</td><td>{{ \App\Relais\Format::depuis((int) $s->last_activity * 1000) }}</td></tr>
                @endforeach
                </tbody>
            </table></div>
        @endif
    </div>
    <div class="carte" id="sms">
        <h2>SMS du relais</h2>
        <p class="note">Le relais transporte des SMS déjà composés par la mère et les efface après l’envoi. Cette section ne montre que des compteurs et des noms de paramètres : jamais un numéro, jamais un texte, jamais une valeur du fichier de réglages.</p>
        <div class="table-wrap" tabindex="0"><table>
            <tbody>
                <tr>
                    <th>Pilote en service</th>
                    <td>{{ $sms['pilote'] }}
                        @if($sms['envoie'])<span class="puce ok">envoie réellement</span>@else<span class="puce attention">essai : n’envoie rien</span>@endif
                    </td>
                </tr>
                <tr>
                    <th>Paramètres manquants</th>
                    <td>
                        @if($sms['parametres_manquants'] === [])
                            <span class="puce ok">aucun</span>
                        @else
                            <span class="puce alerte">{{ count($sms['parametres_manquants']) }} manquant(s)</span>
                            {{ implode(', ', $sms['parametres_manquants']) }}
                            <div class="note">À renseigner dans le fichier de réglages du relais. Tant qu’ils manquent, la file n’est pas touchée.</div>
                        @endif
                    </td>
                </tr>
                <tr>
                    <th>Plafond du jour</th>
                    <td>{{ $sms['envoyes_aujourdhui'] }} envoyé(s) sur {{ $sms['plafond_jour'] }}
                        @if($sms['plafond_atteint'])<span class="puce alerte">plafond atteint</span>@endif
                    </td>
                </tr>
                <tr><th>File d’attente</th><td>{{ $sms['file'] }} en attente @if($sms['file_en_retard'] > 0)<span class="puce attention">{{ $sms['file_en_retard'] }} depuis plus d’une heure</span>@endif</td></tr>
                <tr><th>Échecs (après {{ $sms['tentatives_max'] }} tentatives)</th><td>{{ $sms['echecs'] }}</td></tr>
                <tr><th>Expirés (périmés après {{ $sms['validite_heures'] }} h d’attente)</th><td>{{ $sms['expires'] }}</td></tr>
                <tr><th>Envoyés (gardés {{ $sms['conservation_jours'] }} jours)</th><td>{{ $sms['envoyes'] }}</td></tr>
            </tbody>
        </table></div>
    </div>
    <form class="carte" wire:submit="changerMotDePasse">
        <h2>Changer le mot de passe</h2>
        <div class="champs">
            <label class="champ pleine" for="actuel"><span>Mot de passe actuel</span><input id="actuel" type="password" wire:model="actuel" autocomplete="current-password" required></label>
            <label class="champ" for="nouveau"><span>Nouveau mot de passe ({{ (int) config('relais.mdp_superadmin_min') }} caractères au moins)</span><input id="nouveau" type="password" wire:model="nouveau" autocomplete="new-password" required></label>
            <label class="champ" for="confirmation"><span>Confirmation</span><input id="confirmation" type="password" wire:model="confirmation" autocomplete="new-password" required></label>
        </div>
        <div class="actions"><button class="btn" type="submit">Changer le mot de passe</button></div>
    </form>
    <p class="note">Le double facteur n’est pas encore pris en charge par le relais : la colonne le dit au lieu de le laisser supposer.</p>
</div>
