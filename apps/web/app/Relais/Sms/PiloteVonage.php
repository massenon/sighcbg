<?php

namespace App\Relais\Sms;

use Illuminate\Support\Facades\Http;

/**
 * Pilote Vonage (`RELAIS_SMS_PILOTE=vonage`) : l'API SMS (`POST` sur `/sms/json`, adresse réglée par `RELAIS_SMS_VONAGE_URL`), corps form-urlencoded `api_key`, `api_secret`, `from`, `to`,
 * `text`. C'est l'API SMS et non la Messages API : une clé et un secret suffisent (pas d'application ni de clé privée JWT), ce qui convient à un cPanel
 * mutualisé. Vonage répond 200 MÊME en cas de refus : le succès se lit dans `messages[0].status` (« 0 »). Le numéro y est écrit sans le « + » initial.
 * Un refus rend un code (`vonage_statut_9`, `vonage_http_503`), jamais le corps de la réponse (`error-text` peut citer le numéro).
 */
class PiloteVonage implements PiloteConfigurable
{
    public function __construct(private readonly array $reglages)
    {
    }

    public function nom(): string
    {
        return 'vonage';
    }

    public function parametresManquants(): array
    {
        $r = $this->reglages;
        $m = [];
        foreach (['cle' => 'RELAIS_SMS_VONAGE_CLE', 'secret' => 'RELAIS_SMS_VONAGE_SECRET', 'expediteur' => 'RELAIS_SMS_EXPEDITEUR', 'url' => 'RELAIS_SMS_VONAGE_URL'] as $cle => $env) {
            if (trim((string) ($r[$cle] ?? '')) === '') {
                $m[] = $env;
            }
        }

        return $m;
    }

    public function envoyer(string $numero, string $texte): ResultatEnvoi
    {
        if ($this->parametresManquants() !== []) {
            return ResultatEnvoi::refuse('vonage_parametre_manquant');
        }
        $r = $this->reglages;
        $corps = ['api_key' => $r['cle'], 'api_secret' => $r['secret'], 'from' => $r['expediteur'], 'to' => ltrim($numero, '+'), 'text' => $texte];
        try {
            $rep = Http::timeout((int) ($r['delai_s'] ?? 10))->acceptJson()->asForm()->post((string) $r['url'], $corps);
        } catch (\Throwable) {
            return ResultatEnvoi::refuse('exception');
        }
        if (! $rep->successful()) {
            return ResultatEnvoi::refuse('vonage_http_'.$rep->status());
        }
        $statut = $rep->json('messages.0.status');
        if ($statut === null) {
            return ResultatEnvoi::refuse('vonage_reponse_illisible');
        }

        return (string) $statut === '0' ? ResultatEnvoi::accepte() : ResultatEnvoi::refuse('vonage_statut_'.$statut);
    }
}
