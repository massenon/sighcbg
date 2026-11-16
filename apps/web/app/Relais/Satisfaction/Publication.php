<?php

namespace App\Relais\Satisfaction;

/**
 * SATISFACTION EN LIGNE : les FORMES que le relais accepte, et rien d'autre. Schéma FERMÉ (tout champ inattendu est refusé), comme les indicateurs de
 * l'ADR-0007. Aucune règle de gestion : le relais ne juge ni les questions (la mère les engendre par le générateur du domaine) ni les réponses (il ne
 * peut pas les lire). Il vérifie des longueurs, des types et des alphabets, pour ne stocker que ce qu'il sait servir sans danger.
 */
class Publication
{
    public const CLES = ['jeton_hash', 'ref', 'expire_le', 'clinique', 'titre', 'description', 'champs', 'cle_publique', 'kid'];

    public const CLES_CHAMP = ['nom', 'libelle', 'type', 'requis', 'options', 'lignes'];

    public const CLES_ENVELOPPE = ['v', 'kid', 'epk', 'iv', 'ct'];

    /** Les défauts d'une publication de la mère ; liste vide = conforme. */
    public static function defauts(mixed $p): array
    {
        if (! is_array($p) || array_is_list($p)) {
            return ['la publication doit être un objet'];
        }
        $d = [];
        $inattendus = array_diff(array_keys($p), self::CLES);
        if ($inattendus !== []) {
            $d[] = 'champ(s) inattendu(s) : '.implode(', ', array_slice($inattendus, 0, 5));
        }
        foreach (self::CLES as $k) {
            if (! array_key_exists($k, $p)) {
                $d[] = "champ manquant : $k";
            }
        }
        if ($d !== []) {
            return $d;
        }
        if (! is_string($p['jeton_hash']) || ! preg_match('/^[0-9a-f]{64}$/', $p['jeton_hash'])) {
            $d[] = 'jeton_hash : 64 caractères hexadécimaux attendus';
        }
        if (! is_string($p['ref']) || ! preg_match('/^[A-Za-z0-9._:-]{1,64}$/', $p['ref'])) {
            $d[] = 'ref : identifiant technique attendu';
        }
        if (! is_string($p['expire_le']) || ! self::estDate($p['expire_le'])) {
            $d[] = 'expire_le : date AAAA-MM-JJ attendue';
        }
        foreach (['clinique' => 80, 'titre' => 120] as $k => $max) {
            if (! self::texte($p[$k], 1, $max)) {
                $d[] = "$k : texte de 1 à $max caractères attendu";
            }
        }
        if (! self::texte($p['description'], 0, 500)) {
            $d[] = 'description : texte de 500 caractères au plus attendu';
        }
        if (! is_string($p['cle_publique']) || ! preg_match('/^[A-Za-z0-9_-]{43}$/', $p['cle_publique'])) {
            $d[] = 'cle_publique : 32 octets en base64url attendus';
        }
        if (! is_string($p['kid']) || ! preg_match('/^[0-9a-f]{16}$/', $p['kid'])) {
            $d[] = 'kid : 16 caractères hexadécimaux attendus';
        }
        if (! is_array($p['champs']) || ! array_is_list($p['champs']) || count($p['champs']) < 1 || count($p['champs']) > 40) {
            $d[] = 'champs : liste de 1 à 40 champs attendue';

            return $d;
        }
        $noms = [];
        foreach ($p['champs'] as $i => $c) {
            foreach (self::defautsChamp($c) as $x) {
                $d[] = "champs[$i] : $x";
            }
            if (is_array($c) && isset($c['nom']) && is_string($c['nom'])) {
                if (isset($noms[$c['nom']])) {
                    $d[] = "champs[$i] : nom en double";
                }
                $noms[$c['nom']] = true;
            }
        }

        return $d;
    }

    private static function defautsChamp(mixed $c): array
    {
        if (! is_array($c) || array_is_list($c)) {
            return ['objet attendu'];
        }
        $d = [];
        if (array_diff(array_keys($c), self::CLES_CHAMP) !== [] || count(array_intersect(array_keys($c), self::CLES_CHAMP)) !== count(self::CLES_CHAMP)) {
            return ['clés attendues : '.implode(', ', self::CLES_CHAMP)];
        }
        // Un nom commençant par « _ » est réservé au poste (le nom du répondant d'un lien nominatif) : il n'existe pas en ligne, où tout est anonyme.
        if (! is_string($c['nom']) || ! preg_match('/^[A-Za-z0-9][A-Za-z0-9_]{0,39}$/', $c['nom'])) {
            $d[] = 'nom : identifiant de 40 caractères au plus attendu';
        }
        if (! self::texte($c['libelle'], 1, 200)) {
            $d[] = 'libelle : texte de 1 à 200 caractères attendu';
        }
        if (! in_array($c['type'], ['select', 'textarea'], true)) {
            $d[] = 'type : select ou textarea attendu';
        }
        if (! is_bool($c['requis'])) {
            $d[] = 'requis : vrai ou faux attendu';
        }
        if (! is_int($c['lignes']) || $c['lignes'] < 1 || $c['lignes'] > 10) {
            $d[] = 'lignes : entier de 1 à 10 attendu';
        }
        if (! is_array($c['options']) || ! array_is_list($c['options']) || count($c['options']) > 20) {
            $d[] = 'options : liste de 20 choix au plus attendue';
        } else {
            foreach ($c['options'] as $o) {
                if (! self::texte($o, 1, 120)) {
                    $d[] = 'options : choix de 1 à 120 caractères attendus';
                    break;
                }
            }
            if ($c['type'] === 'select' && count($c['options']) === 0) {
                $d[] = 'options : une liste a besoin de ses choix';
            }
        }

        return $d;
    }

    /** Les défauts d'une enveloppe déposée par un navigateur (forme seulement : le relais ne sait pas la lire). */
    public static function defautsEnveloppe(mixed $e): array
    {
        if (! is_array($e) || array_is_list($e) || array_diff(array_keys($e), self::CLES_ENVELOPPE) !== [] || count($e) !== count(self::CLES_ENVELOPPE)) {
            return ['clés attendues : '.implode(', ', self::CLES_ENVELOPPE)];
        }
        $d = [];
        if ($e['v'] !== 'sat1') {
            $d[] = 'version inconnue';
        }
        if (! is_string($e['kid']) || ! preg_match('/^[0-9a-f]{16}$/', $e['kid'])) {
            $d[] = 'kid invalide';
        }
        if (! is_string($e['epk']) || ! preg_match('/^[A-Za-z0-9_-]{43}$/', $e['epk'])) {
            $d[] = 'epk invalide';
        }
        if (! is_string($e['iv']) || ! preg_match('/^[A-Za-z0-9_-]{16}$/', $e['iv'])) {
            $d[] = 'iv invalide';
        }
        if (! is_string($e['ct']) || ! preg_match('/^[A-Za-z0-9_-]+$/', $e['ct'])) {
            $d[] = 'ct invalide';
        } else {
            // Le clair est bourré à un multiple de 256 octets ; le chiffré porte en plus l'étiquette de 16 octets.
            $n = intdiv(strlen($e['ct']) * 3, 4);
            if ($n < 272 || ($n - 16) % 256 !== 0) {
                $d[] = 'ct : longueur inattendue';
            }
        }

        return $d;
    }

    private static function texte(mixed $v, int $min, int $max): bool
    {
        if (! is_string($v)) {
            return false;
        }
        $n = mb_strlen($v);
        // Aucun caractère de contrôle : le relais sert ce texte tel quel (échappé) à des inconnus.
        return $n >= $min && $n <= $max && ! preg_match('/[\x00-\x08\x0B-\x1F\x7F]/u', $v) && mb_check_encoding($v, 'UTF-8');
    }

    private static function estDate(string $s): bool
    {
        if (! preg_match('/^(\d{4})-(\d{2})-(\d{2})$/', $s, $m)) {
            return false;
        }

        return checkdate((int) $m[2], (int) $m[3], (int) $m[1]);
    }
}
