<?php

namespace App\Relais\Sms;

use App\Relais\Format;
use Illuminate\Support\Facades\DB;

/**
 * ADR-0009 : UN TOUR D'ENVOI, lancé par la tâche planifiée `relais:sms-envoyer` (le cron d'une minute `schedule:run` du cPanel : aucun démon).
 * Envoie les SMS en attente dont l'heure d'essai est venue, dans la limite du plafond du jour ; EFFACE le numéro et le texte dès que le fournisseur accepte,
 * ou au dernier échec ; purge les lignes terminées au-delà de la durée de conservation.
 */
class Envoyeur
{
    /** Le pilote du `.env` (`RELAIS_SMS_PILOTE`) ; un pilote lié au conteneur (tests) l'emporte. Un nom inconnu retombe sur le journal, qui n'envoie rien. */
    public static function pilote(): Pilote
    {
        if (app()->bound(Pilote::class)) {
            return app(Pilote::class);
        }

        return match ((string) config('relais.sms.pilote', 'journal')) {
            'http' => new PiloteHttp((array) config('relais.sms.http', [])),
            default => new PiloteJournal(),
        };
    }

    /** @return array{envoyes: int, echecs: int, abandons: int, purges: int, plafond_atteint: bool} */
    public static function tourner(?Pilote $pilote = null, ?int $maintenant = null): array
    {
        $m = $maintenant ?? Format::maintenant();
        $pilote ??= self::pilote();
        $bilan = ['envoyes' => 0, 'echecs' => 0, 'abandons' => 0, 'purges' => self::purger($m), 'plafond_atteint' => false];
        $restant = FileSms::plafondJour() - FileSms::envoyesAujourdhui($m);
        if ($restant <= 0) {
            $bilan['plafond_atteint'] = DB::table('sms_sortants')->where('statut', 'en_attente')->exists();

            return $bilan;
        }
        $lot = max(1, (int) config('relais.sms.lot', 20));
        $lignes = DB::table('sms_sortants')->where('statut', 'en_attente')->where('prochain_essai_le', '<=', $m)
            ->orderBy('depose_le')->orderBy('id')->limit(min($lot, $restant))->get();
        foreach ($lignes as $l) {
            try {
                $r = $pilote->envoyer((string) $l->numero, (string) $l->texte);
            } catch (\Throwable) {
                $r = ResultatEnvoi::refuse('exception');
            }
            $tentatives = (int) $l->tentatives + 1;
            if ($r->accepte) {
                DB::table('sms_sortants')->where('id', $l->id)->update([
                    'statut' => 'envoye', 'tentatives' => $tentatives, 'envoye_le' => $m, 'efface_le' => $m, 'numero' => null, 'texte' => null, 'derniere_erreur' => null,
                ]);
                FileSms::journal('sms_envoye', $l->uid.' pilote='.$pilote->nom().' longueur='.$l->longueur, $m);
                $bilan['envoyes']++;
            } elseif ($tentatives >= FileSms::tentativesMax()) {
                DB::table('sms_sortants')->where('id', $l->id)->update([
                    'statut' => 'echec', 'tentatives' => $tentatives, 'echec_le' => $m, 'efface_le' => $m, 'numero' => null, 'texte' => null, 'derniere_erreur' => $r->code,
                ]);
                FileSms::journal('sms_echec', $l->uid.' '.$r->code.' abandon apres '.$tentatives.' tentatives', $m);
                $bilan['abandons']++;
            } else {
                DB::table('sms_sortants')->where('id', $l->id)->update([
                    'tentatives' => $tentatives, 'prochain_essai_le' => $m + (FileSms::DELAIS_MS[$tentatives] ?? 3600000), 'derniere_erreur' => $r->code,
                ]);
                FileSms::journal('sms_echec', $l->uid.' '.$r->code.' tentative '.$tentatives, $m);
                $bilan['echecs']++;
            }
        }
        $bilan['plafond_atteint'] = FileSms::envoyesAujourdhui($m) >= FileSms::plafondJour() && DB::table('sms_sortants')->where('statut', 'en_attente')->exists();

        return $bilan;
    }

    /** Purge les lignes TERMINÉES (déjà effacées) au-delà de la conservation ; une ligne en attente n'est jamais purgée. */
    public static function purger(?int $maintenant = null): int
    {
        $m = $maintenant ?? Format::maintenant();
        $limite = $m - max(1, (int) config('relais.sms.conservation_jours', 30)) * 86400000;

        return DB::table('sms_sortants')->whereIn('statut', ['envoye', 'echec'])->where('efface_le', '<', $limite)->delete();
    }
}
