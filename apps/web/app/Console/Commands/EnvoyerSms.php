<?php

namespace App\Console\Commands;

use App\Relais\Sms\Envoyeur;
use Illuminate\Console\Command;

/** ADR-0009 : un tour d'envoi des SMS déposés par la mère. Planifié chaque minute (`routes/console.php`) ; sur cPanel, c'est le cron `schedule:run` qui le lance. */
class EnvoyerSms extends Command
{
    protected $signature = 'relais:sms-envoyer';

    protected $description = 'Envoie les SMS en attente (plafond du jour, cinq tentatives au plus, durée de validité), abandonne les périmés puis efface le numéro et le texte';

    public function handle(): int
    {
        $b = Envoyeur::tourner();
        // Le bilan ne porte que des compteurs : jamais un numéro ni un texte.
        $this->info(sprintf('SMS : %d envoyé(s), %d échec(s) à réessayer, %d abandon(s), %d expiré(s), %d ligne(s) purgée(s)%s.',
            $b['envoyes'], $b['echecs'], $b['abandons'], $b['expires'], $b['purges'], $b['plafond_atteint'] ? ', plafond du jour atteint' : ''));

        if ($b['configuration_manquante'] !== []) {
            $this->error('Pilote SMS non configuré : renseigner dans le .env '.implode(', ', $b['configuration_manquante']).'. La file n\'a pas été touchée.');

            return self::FAILURE;
        }

        return self::SUCCESS;
    }
}
