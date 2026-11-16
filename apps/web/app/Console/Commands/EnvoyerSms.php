<?php

namespace App\Console\Commands;

use App\Relais\Sms\Envoyeur;
use Illuminate\Console\Command;

/** ADR-0009 : un tour d'envoi des SMS déposés par la mère. Planifié chaque minute (`routes/console.php`) ; sur cPanel, c'est le cron `schedule:run` qui le lance. */
class EnvoyerSms extends Command
{
    protected $signature = 'relais:sms-envoyer';

    protected $description = 'Envoie les SMS en attente (plafond du jour, cinq tentatives au plus) puis efface leur numéro et leur texte';

    public function handle(): int
    {
        $b = Envoyeur::tourner();
        // Le bilan ne porte que des compteurs : jamais un numéro ni un texte.
        $this->info(sprintf('SMS : %d envoyé(s), %d échec(s) à réessayer, %d abandon(s), %d ligne(s) purgée(s)%s.',
            $b['envoyes'], $b['echecs'], $b['abandons'], $b['purges'], $b['plafond_atteint'] ? ', plafond du jour atteint' : ''));

        return self::SUCCESS;
    }
}
