<?php

namespace App\Relais\Sms;

/** Un pilote qui refuse TOUT (code `essai_echec`) : réservé au banc d'essai (`RELAIS_BANC=true`) pour éprouver les cinq tentatives et l'effacement sur échec. */
class PiloteEchec implements Pilote
{
    public function nom(): string
    {
        return 'echec';
    }

    public function envoyer(string $numero, string $texte): ResultatEnvoi
    {
        return ResultatEnvoi::refuse('essai_echec');
    }
}
