<?php

namespace App\Relais\Sms;

use Illuminate\Support\Facades\Http;

/**
 * Pilote Twilio (`RELAIS_SMS_PILOTE=twilio`) : API Messages 2010-04-01, `POST {url_base}/Accounts/{SID}/Messages.json`, authentification Basic SID:TOKEN, corps
 * form-urlencoded `To`, `From` (ou `MessagingServiceSid`) et `Body`. Tous les réglages viennent du `.env` (`config('relais.sms.twilio')`). Succès = réponse 2xx ;
 * tout autre cas rend un code (`twilio_http_401`, `exception`), jamais le corps de la réponse, qui pourrait répéter le texte ou le numéro.
 */
class PiloteTwilio implements PiloteConfigurable
{
    public function __construct(private readonly array $reglages)
    {
    }

    public function nom(): string
    {
        return 'twilio';
    }

    public function parametresManquants(): array
    {
        $r = $this->reglages;
        $m = [];
        foreach (['sid' => 'RELAIS_SMS_TWILIO_SID', 'token' => 'RELAIS_SMS_TWILIO_TOKEN', 'url_base' => 'RELAIS_SMS_TWILIO_URL_BASE'] as $cle => $env) {
            if (trim((string) ($r[$cle] ?? '')) === '') {
                $m[] = $env;
            }
        }
        if (trim((string) ($r['expediteur'] ?? '')) === '' && trim((string) ($r['service'] ?? '')) === '') {
            $m[] = 'RELAIS_SMS_EXPEDITEUR (ou RELAIS_SMS_TWILIO_SERVICE)';
        }

        return $m;
    }

    public function envoyer(string $numero, string $texte): ResultatEnvoi
    {
        if ($this->parametresManquants() !== []) {
            return ResultatEnvoi::refuse('twilio_parametre_manquant');
        }
        $r = $this->reglages;
        $corps = ['To' => $numero, 'Body' => $texte];
        if (trim((string) ($r['service'] ?? '')) !== '') {
            $corps['MessagingServiceSid'] = $r['service'];
        } else {
            $corps['From'] = $r['expediteur'];
        }
        $url = rtrim((string) $r['url_base'], '/').'/Accounts/'.rawurlencode((string) $r['sid']).'/Messages.json';
        try {
            $rep = Http::timeout((int) ($r['delai_s'] ?? 10))->withBasicAuth((string) $r['sid'], (string) $r['token'])->acceptJson()->asForm()->post($url, $corps);
        } catch (\Throwable) {
            return ResultatEnvoi::refuse('exception');
        }

        return $rep->successful() ? ResultatEnvoi::accepte() : ResultatEnvoi::refuse('twilio_http_'.$rep->status());
    }
}
