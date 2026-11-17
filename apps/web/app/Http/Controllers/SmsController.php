<?php

namespace App\Http\Controllers;

use App\Relais\Sms\Envoyeur;
use App\Relais\Sms\FileSms;
use App\Relais\Sms\PiloteEchec;
use App\Relais\Sms\PiloteJournal;
use Illuminate\Http\Exceptions\HttpResponseException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * ADR-0009 : LES SMS PAR LE RELAIS. Contrat : packages/sync/banc/relais-sms.js (implémentation de référence).
 *
 * Mêmes barrières que `/mere/indicateurs-clinique` : le secret de la mère (`x-mere`), puis la SIGNATURE du corps exact (`x-signature: sha256=<HMAC-SHA256,
 * clé = RELAIS_SECRET_MERE>`), puis un schéma FERMÉ. Le relais ne juge pas le sens du texte (aucune règle métier ici) : la mère l'a composé et contrôlé.
 * Aucun refus ne répète un numéro ou un texte reçu ; le journal technique porte un identifiant et un code.
 */
class SmsController extends Controller
{
    private function refus(int $statut, string $code, string $motif = ''): never
    {
        throw new HttpResponseException(response()->json(['code' => $code, 'motif' => $motif], $statut));
    }

    private function exigerMere(Request $r): void
    {
        $secret = (string) config('relais.secret_mere');
        if ($secret === '' || ! hash_equals($secret, (string) $r->header('x-mere'))) {
            $this->refus(403, 'mere_requise');
        }
    }

    /** L'autorisation précède la validation : secret, taille, signature, PUIS le JSON. */
    private function corpsSigne(Request $r): mixed
    {
        $this->exigerMere($r);
        $corps = (string) $r->getContent();
        if (strlen($corps) > (int) config('relais.sms.octets_max', 4096)) {
            $this->refuser(413, 'corps_trop_gros', 'Un SMS est court : ce corps dépasse la taille permise.');
        }
        $attendue = 'sha256='.hash_hmac('sha256', $corps, (string) config('relais.secret_mere'));
        if (! hash_equals($attendue, (string) $r->header('x-signature'))) {
            $this->refuser(401, 'signature_invalide', 'La signature du corps ne correspond pas : dépôt refusé.');
        }

        return json_decode($corps, true);
    }

    private function refuser(int $statut, string $code, string $motif): never
    {
        FileSms::journal('sms_refuse', $code);
        $this->refus($statut, $code, $motif);
    }

    /** `POST /mere/sms` : déposer un SMS déjà composé. Idempotent par identifiant. */
    public function deposer(Request $r): JsonResponse
    {
        $json = $this->corpsSigne($r);
        $defauts = FileSms::valider($json);
        if ($defauts !== []) {
            $this->refuser(422, 'sms_invalide', 'SMS non conforme au schéma : '.implode(' ; ', array_slice($defauts, 0, 5)));
        }
        $res = FileSms::deposer($json['sms']);
        if ($res === null) {
            $this->refuser(429, 'plafond_atteint', 'Le plafond quotidien de SMS ('.FileSms::plafondJour().') est atteint : réessayer demain ou relever le plafond dans le .env du relais.');
        }

        return response()->json(['ok' => true, 'rejeu' => $res['rejeu'], 'sms' => FileSms::statut($res['ligne'])]);
    }

    /** `POST /mere/sms/statuts` : le statut d'une liste d'identifiants (200 au plus). */
    public function statuts(Request $r): JsonResponse
    {
        $json = $this->corpsSigne($r);
        $ids = is_array($json) && array_keys($json) === ['ids'] && is_array($json['ids']) && array_is_list($json['ids']) ? $json['ids'] : null;
        if ($ids === null || count($ids) > 200 || array_filter($ids, fn ($i) => ! is_string($i) || ! preg_match(FileSms::IDENTIFIANT, $i)) !== []) {
            $this->refuser(422, 'ids_invalides', 'Le corps doit porter « ids » : une liste de 200 identifiants au plus.');
        }

        return response()->json(['statuts' => FileSms::statuts(array_values(array_unique($ids)))]);
    }

    /** `GET /mere/sms/etat` : le plafond, le compte du jour, l'attente, le pilote (son nom seulement). Aucun numéro, aucun texte. */
    public function etat(Request $r): JsonResponse
    {
        $this->exigerMere($r);

        return response()->json(FileSms::etat());
    }

    // --- crochets du banc (config relais.banc) : jamais en production -------------------------------------------------------------------------

    private function exigerBanc(): void
    {
        if (! config('relais.banc')) {
            $this->refus(404, 'route_inconnue');
        }
    }

    /** Simule le passage du cron. `pilote` : `journal` (défaut) ou `echec` ; `avance_ms` : décale l'horloge pour franchir le délai entre deux tentatives. */
    public function bancTourner(Request $r): JsonResponse
    {
        $this->exigerBanc();
        $pilote = $r->input('pilote') === 'echec' ? new PiloteEchec() : new PiloteJournal();

        return response()->json(Envoyeur::tourner($pilote, (int) (microtime(true) * 1000) + max(0, (int) $r->input('avance_ms', 0))));
    }

    public function bancTout(): JsonResponse
    {
        $this->exigerBanc();

        return response()->json(['lignes' => DB::table('sms_sortants')->orderBy('id')->get(), 'audit' => DB::table('relais_audit')->where('acteur', 'sms')->orderBy('id')->get()]);
    }
}
