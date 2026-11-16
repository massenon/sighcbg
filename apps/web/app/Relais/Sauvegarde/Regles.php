<?php

namespace App\Relais\Sauvegarde;

/**
 * LES RÈGLES PURES de la rotation et de la purge, portées de `packages/sync/banc/sauvegarde-regles.js` (exécutable de référence ; vecteurs
 * `packages/domaine/test/vecteurs/sauvegarde_horssite.json` rejoués par `SauvegardeReglesTest`). Aucune base, aucun disque, aucune horloge.
 */
class Regles
{
    public const TYPES = ['magasin', 'fichiers'];

    /**
     * Parmi les copies COMPLÈTES (la plus récente d'abord : date, puis identifiant), les `$garder` premières restent courantes, les suivantes sont à ARCHIVER (jamais supprimées).
     *
     * @param  list<array{id: string, type?: string, etat: string, date: int}>  $copies
     * @return array{ok: true, gardees: list<string>, archiver: list<string>}|array{ok: false, code: string, motif: string, geste: string, plancher: int, plafond: int}
     */
    public static function rotation(array $copies, mixed $garder, int $plancher, int $plafond): array
    {
        if (! is_int($garder) || $garder < $plancher || $garder > $plafond) {
            return ['ok' => false, 'code' => 'ROTATION_HORS_BORNES', 'motif' => "garder ".(is_scalar($garder) ? $garder : '?')." copie(s) est hors des bornes du relais ($plancher à $plafond)", 'geste' => 'Choisir un nombre de copies dans les bornes du relais.', 'plancher' => $plancher, 'plafond' => $plafond];
        }
        $completes = array_values(array_filter($copies, fn ($c) => $c['etat'] === 'complete'));
        usort($completes, fn ($a, $b) => ($b['date'] <=> $a['date']) ?: strcmp($b['id'], $a['id']));

        return ['ok' => true, 'gardees' => array_column(array_slice($completes, 0, $garder), 'id'), 'archiver' => array_column(array_slice($completes, $garder), 'id')];
    }

    /**
     * L'ORDRE DE PURGE quand l'espace manque : parmi les copies ARCHIVÉES ou ABANDONNÉES, la plus ancienne d'abord. Une copie courante, en cours, ou l'une des `$plancher` plus récentes
     * copies restaurables (complètes ou archivées) de son type n'est JAMAIS candidate.
     *
     * @param  list<array{id: string, type: string, etat: string, date: int}>  $copies
     * @return list<string>
     */
    public static function ordrePurge(array $copies, int $plancher): array
    {
        $protegees = [];
        foreach (self::TYPES as $t) {
            $restaurables = array_values(array_filter($copies, fn ($c) => $c['type'] === $t && in_array($c['etat'], ['complete', 'archivee'], true)));
            usort($restaurables, fn ($a, $b) => ($b['date'] <=> $a['date']) ?: strcmp($b['id'], $a['id']));
            foreach (array_slice($restaurables, 0, $plancher) as $c) {
                $protegees[$c['id']] = true;
            }
        }
        $candidates = array_values(array_filter($copies, fn ($c) => in_array($c['etat'], ['archivee', 'abandonnee'], true) && ! isset($protegees[$c['id']])));
        usort($candidates, fn ($a, $b) => ($a['date'] <=> $b['date']) ?: strcmp($a['id'], $b['id']));

        return array_column($candidates, 'id');
    }

    /** Le contrôle du plan d'une copie AVANT tout dépôt (miroir de `verifierPlan`). Un champ absent n'est PAS compté comme zéro. */
    public static function verifierPlan(int $octetsCopie, ?array $etat): ?array
    {
        $e = $etat ?? [];
        $l = $e['limites'] ?? [];
        if (isset($l['tailleMaxCopie']) && $octetsCopie > $l['tailleMaxCopie']) {
            return ['code' => 'SAUVEGARDE_TROP_GROSSE'];
        }
        if (isset($l['quotaOctets'], $e['utilise'])) {
            $libre = $l['quotaOctets'] - $e['utilise'] + ($e['liberable'] ?? 0);
            if ($octetsCopie > $libre) {
                return ['code' => 'ESPACE_RELAIS_INSUFFISANT'];
            }
        }

        return null;
    }

    /** Les signatures de fichier d'au moins quatre octets (miroir de `SIGNATURES_CLAIR`) : un chiffré les porterait par hasard moins d'une fois sur quatre milliards. */
    public const SIGNATURES_CLAIR = ['SQLite format 3', '%PDF-', "\x89PNG\r\n\x1a\n", 'RIFF', "PK\x03\x04", "\xFF\xD8\xFF\xE0", "\xFF\xD8\xFF\xE1"];

    public const SEUIL_ENTROPIE = 7.5;

    public const TAILLE_MESURABLE = 4096;

    /** L'entropie de Shannon, en bits par octet. */
    public static function entropie(string $octets): float
    {
        $n = strlen($octets);
        if ($n === 0) {
            return 0.0;
        }
        $h = 0.0;
        foreach (count_chars($octets, 1) as $c) {
            $h -= ($c / $n) * log($c / $n, 2);
        }

        return $h;
    }

    /**
     * Le GARDE-FOU « bloc non chiffré » (miroir de `blocSuspect`) : le relais ne détient aucune clé et ne PROUVE donc pas qu'un bloc est chiffré ; il refuse ce qui ne l'est manifestement pas
     * (signature de fichier au début, ou entropie de texte sur un bloc d'au moins 4 Kio). Rend `null` ou un refus nommé.
     *
     * @return array{code: string, motif: string, geste: string}|null
     */
    public static function blocSuspect(string $octets): ?array
    {
        $geste = 'Chiffrer le bloc par la clé de la clinique AVANT de le déposer : un relais ou un dossier distant ne reçoit que des blocs opaques.';
        foreach (self::SIGNATURES_CLAIR as $sig) {
            if (strlen($octets) >= strlen($sig) && str_starts_with($octets, $sig)) {
                return ['code' => 'BLOC_NON_CHIFFRE', 'motif' => 'ce bloc commence par une signature de fichier : il n\'a pas été chiffré', 'geste' => $geste];
            }
        }
        if (strlen($octets) >= self::TAILLE_MESURABLE && self::entropie($octets) < self::SEUIL_ENTROPIE) {
            return ['code' => 'BLOC_NON_CHIFFRE', 'motif' => 'l\'entropie de ce bloc est celle d\'un texte ou d\'une base, pas d\'un chiffrement', 'geste' => $geste];
        }

        return null;
    }
}
