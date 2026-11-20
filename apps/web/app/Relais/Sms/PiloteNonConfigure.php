<?php

namespace App\Relais\Sms;

/** Le pilote d'un nom que le relais ne connaît pas (`RELAIS_SMS_PILOTE` mal écrit) : il refuse tout, nommément. Retomber sur le journal marquerait « envoyé » un SMS jamais parti. */
class PiloteNonConfigure implements PiloteConfigurable
{
    public function __construct(private readonly string $demande = '')
    {
    }

    public function nom(): string
    {
        return 'inconnu';
    }

    public function parametresManquants(): array
    {
        return ['RELAIS_SMS_PILOTE'];
    }

    public function envoyer(string $numero, string $texte): ResultatEnvoi
    {
        return ResultatEnvoi::refuse('pilote_inconnu');
    }
}
