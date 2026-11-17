<?php

namespace App\Relais\Sms;

/**
 * Le pilote de l'ESSAI (défaut, `RELAIS_SMS_PILOTE=journal`) : il n'envoie RIEN. Il accepte le SMS pour que la file, le plafond, l'effacement et le suivi de
 * statut s'éprouvent sans fournisseur. Le journal technique du relais en garde la trace (identifiant et longueur), jamais le numéro ni le texte.
 */
class PiloteJournal implements Pilote
{
    public function nom(): string
    {
        return 'journal';
    }

    public function envoyer(string $numero, string $texte): ResultatEnvoi
    {
        return ResultatEnvoi::accepte();
    }
}
