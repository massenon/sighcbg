<?php

namespace App\Relais\Sms;

use App\Relais\Format;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * ADR-0009 : LA FILE DES SMS SORTANTS. Aucune règle métier : la mère a composé le texte et contrôlé qu'il ne porte aucun contenu médical ; le relais ne contrôle
 * que la FORME (schéma fermé, longueurs, format international du numéro), borne le nombre d'envois par jour, envoie par un pilote, puis EFFACE le numéro et
 * le texte. Le journal technique (`relais_audit`) porte un identifiant et un code, jamais un numéro ni un texte.
 */
class FileSms
{
    public const NUMERO = '/^\+[1-9][0-9]{7,14}$/';

    public const IDENTIFIANT = '/^[A-Za-z0-9_-]{8,64}$/';

    /** Les délais entre deux tentatives (ms), indexés par le nombre d'échecs déjà subis. */
    public const DELAIS_MS = [1 => 60000, 2 => 300000, 3 => 900000, 4 => 3600000];

    public static function plafondJour(): int
    {
        return max(0, (int) config('relais.sms.plafond_jour', 100));
    }

    /** Cinq tentatives AU PLUS (ADR-0009) : le réglage peut abaisser ce nombre, jamais le dépasser. */
    public static function tentativesMax(): int
    {
        return max(1, min(5, (int) config('relais.sms.tentatives_max', 5)));
    }

    public static function longueurMax(): int
    {
        return max(1, min(320, (int) config('relais.sms.longueur_max', 320)));
    }

    /** Début du jour civil d'Africa/Porto-Novo (ms) : c'est le jour du plafond. */
    public static function debutDuJour(?int $maintenant = null): int
    {
        $m = $maintenant ?? Format::maintenant();

        return Carbon::createFromTimestampMs($m)->timezone('Africa/Porto-Novo')->startOfDay()->getTimestampMs();
    }

    public static function envoyesAujourdhui(?int $maintenant = null): int
    {
        return DB::table('sms_sortants')->where('envoye_le', '>=', self::debutDuJour($maintenant))->count();
    }

    public static function enAttente(): int
    {
        return DB::table('sms_sortants')->where('statut', 'en_attente')->count();
    }

    /**
     * Le schéma FERMÉ d'un dépôt : `{"sms": {"id", "numero", "texte"}}`, rien d'autre. Rend la liste des défauts, nommés par leur CHEMIN, jamais par la valeur
     * reçue (un refus ne répète jamais un numéro ni un texte).
     *
     * @return list<string>
     */
    public static function valider(mixed $corps): array
    {
        if (! is_array($corps) || array_keys($corps) !== ['sms'] || ! is_array($corps['sms']) || array_is_list($corps['sms'])) {
            return ['corps : un seul objet « sms » attendu'];
        }
        $s = $corps['sms'];
        $defauts = [];
        foreach (array_keys($s) as $k) {
            if (! in_array($k, ['id', 'numero', 'texte'], true)) {
                $defauts[] = 'sms.'.(is_string($k) ? substr(preg_replace('/[^A-Za-z0-9_]/', '?', $k), 0, 32) : '?').' : champ inattendu';
            }
        }
        if (! is_string($s['id'] ?? null) || ! preg_match(self::IDENTIFIANT, $s['id'])) {
            $defauts[] = 'sms.id : 8 à 64 caractères parmi lettres, chiffres, « - » et « _ »';
        }
        if (! is_string($s['numero'] ?? null) || ! preg_match(self::NUMERO, $s['numero'])) {
            $defauts[] = 'sms.numero : format international attendu (« + » puis 8 à 15 chiffres)';
        }
        $t = $s['texte'] ?? null;
        if (! is_string($t) || $t === '' || ! mb_check_encoding($t, 'UTF-8')) {
            $defauts[] = 'sms.texte : texte non vide attendu';
        } elseif (mb_strlen($t) > self::longueurMax()) {
            $defauts[] = 'sms.texte : '.self::longueurMax().' caractères au plus';
        } elseif (preg_match('/[\x00-\x09\x0B-\x1F\x7F]/', $t)) {
            $defauts[] = 'sms.texte : caractère de contrôle refusé';
        }

        return $defauts;
    }

    /**
     * Dépose un SMS validé. Rend `['ligne' => objet, 'rejeu' => bool]` ou `null` si le plafond du jour serait dépassé.
     *
     * @param  array{id: string, numero: string, texte: string}  $sms
     */
    public static function deposer(array $sms, ?int $maintenant = null): ?array
    {
        $m = $maintenant ?? Format::maintenant();
        $deja = DB::table('sms_sortants')->where('uid', $sms['id'])->first();
        if ($deja) {
            return ['ligne' => $deja, 'rejeu' => true];
        }
        if (self::envoyesAujourdhui($m) + self::enAttente() >= self::plafondJour()) {
            return null;
        }
        DB::table('sms_sortants')->insert([
            'uid' => $sms['id'], 'numero' => $sms['numero'], 'texte' => $sms['texte'], 'longueur' => mb_strlen($sms['texte']),
            'statut' => 'en_attente', 'tentatives' => 0, 'depose_le' => $m, 'prochain_essai_le' => $m,
        ]);
        self::journal('sms_depose', $sms['id'].' longueur='.mb_strlen($sms['texte']), $m);

        return ['ligne' => DB::table('sms_sortants')->where('uid', $sms['id'])->first(), 'rejeu' => false];
    }

    /** Le statut public d'une ligne : jamais le numéro ni le texte, même avant l'envoi. */
    public static function statut(object $l): array
    {
        return [
            'id' => $l->uid, 'statut' => $l->statut, 'tentatives' => (int) $l->tentatives, 'longueur' => (int) $l->longueur,
            'depose_le' => (int) $l->depose_le, 'envoye_le' => $l->envoye_le === null ? null : (int) $l->envoye_le,
            'echec_le' => $l->echec_le === null ? null : (int) $l->echec_le, 'erreur' => $l->derniere_erreur,
        ];
    }

    /** @param list<string> $ids */
    public static function statuts(array $ids): array
    {
        $lignes = DB::table('sms_sortants')->whereIn('uid', $ids)->get()->keyBy('uid');

        return array_map(fn (string $id) => isset($lignes[$id]) ? self::statut($lignes[$id]) : ['id' => $id, 'statut' => 'inconnu'], $ids);
    }

    public static function etat(?int $maintenant = null): array
    {
        $pilote = Envoyeur::pilote();

        return [
            'plafond_jour' => self::plafondJour(),
            'envoyes_aujourdhui' => self::envoyesAujourdhui($maintenant),
            'en_attente' => self::enAttente(),
            'tentatives_max' => self::tentativesMax(),
            'longueur_max' => self::longueurMax(),
            'pilote' => $pilote->nom(),
            // Les NOMS des variables du .env encore vides pour ce pilote (jamais leurs valeurs) : l'écran de la mère les affiche.
            'parametres_manquants' => $pilote instanceof PiloteConfigurable ? $pilote->parametresManquants() : [],
        ];
    }

    public static function journal(string $action, string $detail, ?int $quand = null): void
    {
        DB::table('relais_audit')->insert(['quand' => $quand ?? Format::maintenant(), 'acteur' => 'sms', 'action' => $action, 'detail' => $detail]);
    }
}
