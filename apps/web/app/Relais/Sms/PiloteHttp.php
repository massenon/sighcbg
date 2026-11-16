<?php

namespace App\Relais\Sms;

use Illuminate\Support\Facades\Http;

/**
 * Un pilote HTTP GÉNÉRIQUE (`RELAIS_SMS_PILOTE=http`). Il n'imite aucun fournisseur réel : l'adresse, la clé, l'en-tête qui la porte, son préfixe, l'expéditeur
 * et le NOM des champs du corps JSON viennent tous du `.env` du relais (`config('relais.sms.http')`). Un fournisseur dont l'API ne tient pas dans ce moule
 * aura son propre pilote derrière la même interface. Succès = réponse 2xx ; tout autre cas rend un code (`http_503`, `exception`), jamais le corps.
 */
class PiloteHttp implements Pilote
{
    public function __construct(private readonly array $reglages)
    {
    }

    public function nom(): string
    {
        return 'http';
    }

    public function envoyer(string $numero, string $texte): ResultatEnvoi
    {
        $r = $this->reglages;
        if (($r['url'] ?? '') === '') {
            return ResultatEnvoi::refuse('pilote_non_configure');
        }
        $corps = [($r['champ_numero'] ?? 'to') => $numero, ($r['champ_texte'] ?? 'text') => $texte];
        if (($r['expediteur'] ?? '') !== '') {
            $corps[$r['champ_expediteur'] ?? 'from'] = $r['expediteur'];
        }
        $entetes = [];
        if (($r['cle'] ?? '') !== '') {
            $entetes[$r['entete_cle'] ?? 'Authorization'] = ($r['prefixe_cle'] ?? '').$r['cle'];
        }
        try {
            $rep = Http::timeout((int) ($r['delai_s'] ?? 10))->withHeaders($entetes)->acceptJson()->asJson()->post($r['url'], $corps);
        } catch (\Throwable) {
            return ResultatEnvoi::refuse('exception');
        }

        return $rep->successful() ? ResultatEnvoi::accepte() : ResultatEnvoi::refuse('http_'.$rep->status());
    }
}
