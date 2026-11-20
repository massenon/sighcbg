<?php

namespace App\Http\Controllers;

use App\Relais\Format;
use App\Relais\Satisfaction\Publication;
use Carbon\Carbon;
use Illuminate\Http\Exceptions\HttpResponseException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * SATISFACTION EN LIGNE (décision de la Direction du 16/11/2026, section 8). Contrat : packages/sync/banc/relais-satisfaction.js.
 *
 * Deux familles de routes, deux publics :
 *  - PUBLIQUES (un patient, depuis chez lui, par un lien ou un QR) : afficher le questionnaire d'un JETON, déposer une ENVELOPPE chiffrée dans son
 *    navigateur. Jeton inconnu, expiré ou révoqué : LA MÊME réponse neutre, qui ne nomme rien ; la page ne porte aucun lien vers le logiciel.
 *  - de la MÈRE, SIGNÉES (secret de la mère, puis HMAC-SHA256 du corps exact) : publier ou révoquer un lien avec son modèle de questions et la clé
 *    PUBLIQUE de la clinique, relever les enveloppes, en accuser la relève (elles sont alors effacées).
 *
 * Ce contrôleur n'importe AUCUNE fonction de chiffrement et ne détient aucune clé : la clé privée ne quitte jamais le poste mère. Il voit un modèle de
 * questions (non secret), des enveloppes opaques, des jours de réception et des compteurs. Aucune adresse réseau n'est enregistrée avec une réponse.
 */
class SatisfactionController extends Controller
{
    private const NEUTRE = ['code' => 'lien_invalide', 'motif' => 'Ce lien n’est plus valable.'];

    private function refus(int $statut, string $code, string $motif = '', array $plus = []): never
    {
        throw new HttpResponseException(response()->json(['code' => $code, 'motif' => $motif] + $plus, $statut));
    }

    private function aujourdhui(): string
    {
        return Carbon::now(config('satisfaction.fuseau'))->format('Y-m-d');
    }

    /** L'autorisation de la mère PRÉCÈDE toute lecture du corps : secret, taille, puis signature du corps exact. */
    private function corpsDeLaMere(Request $r): array
    {
        $secret = (string) config('relais.secret_mere');
        if ($secret === '' || ! hash_equals($secret, (string) $r->header('x-mere'))) {
            $this->refus(403, 'mere_requise');
        }
        $corps = (string) $r->getContent();
        if (strlen($corps) > (int) config('satisfaction.publication_octets_max')) {
            $this->refus(413, 'corps_trop_gros', 'Ce corps dépasse la taille permise.');
        }
        $attendue = 'sha256='.hash_hmac('sha256', $corps, $secret);
        if (! hash_equals($attendue, (string) $r->header('x-signature'))) {
            DB::table('relais_audit')->insert(['quand' => Format::maintenant(), 'acteur' => 'mère', 'action' => 'satisfaction_refusee', 'detail' => 'signature_invalide']);
            $this->refus(401, 'signature_invalide', 'La signature du corps ne correspond pas : demande refusée.');
        }
        $json = json_decode($corps, true);

        return is_array($json) ? $json : [];
    }

    private function journal(string $action, string $detail): void
    {
        DB::table('relais_audit')->insert(['quand' => Format::maintenant(), 'acteur' => 'mère', 'action' => $action, 'detail' => mb_substr($detail, 0, 120)]);
    }

    /** Le lien OUVERT d'un jeton, ou null. Inconnu, mal formé, expiré, révoqué : null, sans distinction (les distinguer renseignerait sur ce qui existe). */
    private function lienOuvert(string $jeton): ?object
    {
        if (! preg_match('/^[a-z0-9]{16,64}$/', $jeton)) {
            return null;
        }
        $l = DB::table('satisfaction_liens')->where('jeton_hash', hash('sha256', $jeton))->first();
        if (! $l || $l->revoque_le !== null || strcmp($l->expire_le, $this->aujourdhui()) < 0) {
            return null;
        }

        return $l;
    }

    /** En-têtes des réponses publiques : aucune ressource externe, aucun cadre, aucun référent (le jeton est dans l'adresse), aucun cache. */
    private function entetes(Response|JsonResponse $rep): Response|JsonResponse
    {
        $rep->headers->set('Content-Security-Policy', "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'; connect-src 'self'; form-action 'none'; base-uri 'none'; frame-ancestors 'none'");
        $rep->headers->set('Referrer-Policy', 'no-referrer');
        $rep->headers->set('Cache-Control', 'no-store');
        $rep->headers->set('X-Robots-Tag', 'noindex, nofollow');
        $rep->headers->set('X-Content-Type-Options', 'nosniff');

        return $rep;
    }

    private function donneesPubliques(object $l, string $jeton): array
    {
        return [
            'clinique' => $l->clinique,
            'titre' => $l->titre,
            'description' => $l->description,
            'champs' => json_decode($l->champs, true),
            'jeton' => $jeton,
            'kid' => $l->kid,
            'cle_publique' => $l->cle_publique,
            'depot' => url('/satisfaction/'.$jeton.'/reponse'),
        ];
    }

    // --- routes publiques ------------------------------------------------------------------------------------------------------------------------

    public function page(string $jeton): Response
    {
        $l = $this->lienOuvert($jeton);
        if (! $l) {
            return $this->entetes(response()->view('satisfaction.invalide', [], 404));
        }

        return $this->entetes(response()->view('satisfaction.questionnaire', ['d' => $this->donneesPubliques($l, $jeton)]));
    }

    public function modele(string $jeton): JsonResponse
    {
        $l = $this->lienOuvert($jeton);

        return $this->entetes($l ? response()->json($this->donneesPubliques($l, $jeton)) : response()->json(self::NEUTRE, 404));
    }

    public function deposer(Request $r, string $jeton): JsonResponse
    {
        // Le lien d'abord : un jeton inconnu reçoit la réponse neutre quelle que soit la forme du corps.
        $l = $this->lienOuvert($jeton);
        if (! $l) {
            return $this->entetes(response()->json(self::NEUTRE, 404));
        }
        $corps = (string) $r->getContent();
        if (strlen($corps) > (int) config('satisfaction.enveloppe_octets_max')) {
            $this->refus(413, 'enveloppe_trop_grosse', 'Votre réponse est trop longue : raccourcissez le commentaire.');
        }
        $json = json_decode($corps, true);
        if (! is_array($json) || array_keys($json) !== ['enveloppe']) {
            $this->refus(422, 'enveloppe_invalide', 'Réponse illisible : rechargez la page et recommencez.');
        }
        $e = $json['enveloppe'];
        if (Publication::defautsEnveloppe($e) !== []) {
            $this->refus(422, 'enveloppe_invalide', 'Réponse illisible : rechargez la page et recommencez.');
        }
        if ($e['kid'] !== $l->kid) {
            $this->refus(409, 'cle_perimee', 'Le questionnaire a été mis à jour : rechargez la page et recommencez.');
        }
        $jour = $this->aujourdhui();
        $ok = DB::transaction(function () use ($l, $e, $jour) {
            $n = $l->jour_compte === $jour ? (int) $l->n_jour : 0;
            if ($n >= (int) config('satisfaction.plafond_par_lien_et_jour')) {
                return false;
            }
            DB::table('satisfaction_liens')->where('id', $l->id)->update(['jour_compte' => $jour, 'n_jour' => $n + 1]);
            $texte = json_encode($e, JSON_UNESCAPED_SLASHES);
            DB::table('satisfaction_enveloppes')->insert(['id' => (string) Str::uuid(), 'lien_id' => $l->id, 'enveloppe' => $texte, 'taille' => strlen($texte), 'recue_le' => $jour]);

            return true;
        });
        if (! $ok) {
            $this->refus(429, 'plafond_atteint', 'Ce questionnaire a reçu beaucoup de réponses aujourd’hui : réessayez demain.');
        }

        return $this->entetes(response()->json(['ok' => true], 202));
    }

    // --- routes de la mère (signées) ---------------------------------------------------------------------------------------------------------------

    public function publier(Request $r): JsonResponse
    {
        $p = $this->corpsDeLaMere($r);
        $defauts = Publication::defauts($p);
        if ($defauts !== []) {
            $this->journal('satisfaction_refusee', 'publication_invalide');
            $this->refus(422, 'publication_invalide', 'Publication non conforme : '.implode(' ; ', array_slice($defauts, 0, 5)));
        }
        $existant = DB::table('satisfaction_liens')->where('jeton_hash', $p['jeton_hash'])->first();
        if ($existant && $existant->revoque_le !== null) {
            $this->refus(409, 'lien_revoque', 'Ce lien est révoqué : il ne se republie pas. Ouvrir un nouveau lien.');
        }
        $ligne = [
            'ref' => $p['ref'], 'clinique' => $p['clinique'], 'titre' => $p['titre'], 'description' => $p['description'],
            'champs' => json_encode($p['champs'], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES), 'cle_publique' => $p['cle_publique'],
            'kid' => $p['kid'], 'expire_le' => $p['expire_le'], 'publie_le' => Format::maintenant(),
        ];
        if ($existant) {
            DB::table('satisfaction_liens')->where('id', $existant->id)->update($ligne);
        } else {
            DB::table('satisfaction_liens')->insert($ligne + ['jeton_hash' => $p['jeton_hash']]);
        }
        $this->journal('satisfaction_publiee', $p['ref']);

        return response()->json(['ok' => true, 'cree' => ! $existant]);
    }

    public function revoquer(Request $r): JsonResponse
    {
        $p = $this->corpsDeLaMere($r);
        $h = $p['jeton_hash'] ?? null;
        if (! is_string($h) || ! preg_match('/^[0-9a-f]{64}$/', $h)) {
            $this->refus(422, 'jeton_hash_invalide', 'jeton_hash : 64 caractères hexadécimaux attendus.');
        }
        $l = DB::table('satisfaction_liens')->where('jeton_hash', $h)->first();
        if (! $l) {
            $this->refus(404, 'lien_inconnu', 'Aucun lien publié ne porte ce jeton.');
        }
        if ($l->revoque_le === null) {
            DB::table('satisfaction_liens')->where('id', $l->id)->update(['revoque_le' => Format::maintenant()]);
            $this->journal('satisfaction_revoquee', $l->ref);
        }

        // Les enveloppes déjà déposées restent à relever : une réponse donnée avant la révocation est une vraie réponse.
        return response()->json(['ok' => true]);
    }

    public function relever(Request $r): JsonResponse
    {
        $p = $this->corpsDeLaMere($r);
        $limite = max(1, min(200, (int) ($p['limite'] ?? 100)));
        $this->purger();
        $lignes = DB::table('satisfaction_enveloppes as e')->join('satisfaction_liens as l', 'l.id', '=', 'e.lien_id')
            ->orderBy('e.rid')->limit($limite)->get(['e.id', 'l.ref', 'e.recue_le', 'e.enveloppe']);
        $out = $lignes->map(fn ($x) => ['id' => $x->id, 'ref' => $x->ref, 'recue_le' => $x->recue_le, 'enveloppe' => json_decode($x->enveloppe, true)])->all();
        if ($out !== []) {
            $this->journal('satisfaction_relevee', count($out).' enveloppe(s)');
        }

        return response()->json(['enveloppes' => $out, 'fin' => count($out) < $limite]);
    }

    public function acquitter(Request $r): JsonResponse
    {
        $p = $this->corpsDeLaMere($r);
        $ids = array_values(array_filter((array) ($p['ids'] ?? []), fn ($i) => is_string($i) && preg_match('/^[0-9a-f-]{36}$/', $i)));
        $n = $ids === [] ? 0 : DB::table('satisfaction_enveloppes')->whereIn('id', array_slice($ids, 0, 500))->delete();
        if ($n > 0) {
            $this->journal('satisfaction_acquittee', $n.' enveloppe(s) effacée(s)');
        }

        return response()->json(['acquittees' => $n]);
    }

    /** Un lien expiré ou révoqué depuis plus que la conservation, sans enveloppe en attente, quitte le relais (le poste garde sa fiche). */
    private function purger(): void
    {
        $jours = (int) config('satisfaction.conservation_jours');
        $seuilJour = Carbon::now(config('satisfaction.fuseau'))->subDays($jours)->format('Y-m-d');
        $seuilMs = Format::maintenant() - $jours * 86400000;
        DB::table('satisfaction_liens')
            ->where(fn ($q) => $q->where('expire_le', '<', $seuilJour)->orWhere('revoque_le', '<', $seuilMs))
            ->whereNotExists(fn ($q) => $q->select(DB::raw(1))->from('satisfaction_enveloppes')->whereColumn('satisfaction_enveloppes.lien_id', 'satisfaction_liens.id'))
            ->delete();
    }

    // --- crochets du banc (RELAIS_BANC=true) : jamais en production ----------------------------------------------------------------------------------

    public function bancTout(): JsonResponse
    {
        if (! config('relais.banc')) {
            $this->refus(404, 'route_inconnue');
        }

        return response()->json(['liens' => DB::table('satisfaction_liens')->get(), 'enveloppes' => DB::table('satisfaction_enveloppes')->get()]);
    }

    public function bancVieillir(Request $r): JsonResponse
    {
        if (! config('relais.banc')) {
            $this->refus(404, 'route_inconnue');
        }
        // Recule l'expiration d'un lien (essai de l'expiration sans attendre un jour).
        DB::table('satisfaction_liens')->where('ref', (string) $r->input('ref'))->update(['expire_le' => (string) $r->input('expire_le')]);

        return response()->json(['ok' => true]);
    }
}
