<?php

namespace App\Relais;

use Illuminate\Support\Facades\DB;

/**
 * INDICATEURS AGRÉGÉS DE LA CLINIQUE (Direction, 09/11/2026, ADR-0007).
 *
 * Le relais reste opaque pour tout dossier. Il accepte de la mère, en clair, un instantané de NOMBRES : plus quelques valeurs de FORME IMPOSÉE : un code
 * d'obligation fiscale, une date, un numéro de version, l'identifiant technique d'un appareil. Le schéma ci-dessous est FERMÉ : tout champ absent, tout
 * champ en trop, toute chaîne libre, tout type inattendu est refusé AVANT l'écriture. C'est la réplique exacte de `packages/domaine/lib/src/mere/
 * indicateurs_clinique.dart` (un test Dart lit ce fichier et échoue si les champs dérivent).
 */
class IndicateursClinique
{
    public const VERSION_SCHEMA = 1;

    public const MAX_POSTES = 50;

    private const PLAFOND = 10000000000000;

    private const E_NULLABLE = 'entier_ou_nul';

    private const SCHEMA_CHAMPS = [
        'schema' => 'schema',
        'genere_le' => 'instant_ms',
        'version_application' => 'version',
        'etat_jeu' => 'etat_jeu',
        'patients' => ['actifs' => self::E_NULLABLE, 'nouveaux_mois' => self::E_NULLABLE],
        'activite_mois' => ['m2_consultations' => self::E_NULLABLE, 'm2_visites' => self::E_NULLABLE, 'm2_rendezvous' => self::E_NULLABLE, 'm3_admissions' => self::E_NULLABLE],
        'facturation_mois' => ['factures_emises' => self::E_NULLABLE, 'montant_facture' => self::E_NULLABLE, 'montant_encaisse' => self::E_NULLABLE, 'reste_du' => self::E_NULLABLE],
        'stock' => ['articles_sous_seuil' => self::E_NULLABLE, 'lots_proches_peremption' => self::E_NULLABLE, 'lots_perimes' => self::E_NULLABLE],
        'comptabilite' => ['echeances_en_retard' => self::E_NULLABLE, 'brouillons_non_valides' => self::E_NULLABLE, 'prochaine_echeance_code' => 'code_ou_nul', 'prochaine_echeance_date' => 'date_ou_nul'],
        'utilisateurs_actifs' => self::E_NULLABLE,
        'taux_occupation_lits_pct' => 'pct_ou_nul',
        'postes' => ['__liste__' => ['appareil' => 'identifiant', 'derniere_synchro' => 'instant_ms']],
    ];

    /** Défauts du schéma : liste vide = conforme. Les messages nomment des CHEMINS, jamais une valeur reçue. */
    public static function valider(mixed $instantane): array
    {
        $defauts = [];
        self::parcourir(self::SCHEMA_CHAMPS, $instantane, '', $defauts);

        return $defauts;
    }

    private static function parcourir(array $schema, mixed $valeur, string $chemin, array &$defauts): void
    {
        if (! is_array($valeur) || array_is_list($valeur) && $valeur !== []) {
            $defauts[] = ($chemin === '' ? 'instantané' : $chemin).' : objet attendu';

            return;
        }
        foreach (array_keys($valeur) as $k) {
            if (! array_key_exists($k, $schema)) {
                $defauts[] = ($chemin === '' ? '' : $chemin.'.').mb_substr((string) $k, 0, 40).' : champ inattendu';
            }
        }
        foreach ($schema as $k => $regle) {
            $c = $chemin === '' ? $k : $chemin.'.'.$k;
            if (! array_key_exists($k, $valeur)) {
                $defauts[] = $c.' : champ manquant';

                continue;
            }
            if (is_array($regle) && array_key_exists('__liste__', $regle)) {
                $liste = $valeur[$k];
                if (! is_array($liste) || ($liste !== [] && ! array_is_list($liste))) {
                    $defauts[] = $c.' : liste attendue';
                } elseif (count($liste) > self::MAX_POSTES) {
                    $defauts[] = $c.' : plus de '.self::MAX_POSTES.' éléments';
                } else {
                    foreach ($liste as $i => $element) {
                        self::parcourir($regle['__liste__'], $element, $c.'['.$i.']', $defauts);
                    }
                }
            } elseif (is_array($regle)) {
                self::parcourir($regle, $valeur[$k], $c, $defauts);
            } elseif (! self::feuille($regle, $valeur[$k])) {
                $defauts[] = $c.' : valeur refusée ('.$regle.')';
            }
        }
    }

    private static function entier(mixed $v): bool
    {
        return is_int($v) && $v >= 0 && $v <= self::PLAFOND;
    }

    private static function feuille(string $genre, mixed $v): bool
    {
        return match ($genre) {
            self::E_NULLABLE => $v === null || self::entier($v),
            'pct_ou_nul' => $v === null || (is_int($v) && $v >= 0 && $v <= 100),
            'instant_ms' => self::entier($v),
            'code_ou_nul' => $v === null || (is_string($v) && preg_match('/^[A-Z0-9_-]{1,24}$/D', $v) === 1),
            'date_ou_nul' => $v === null || (is_string($v) && preg_match('/^\d{4}-\d{2}-\d{2}$/D', $v) === 1),
            'version' => is_string($v) && preg_match('/^\d{1,3}(\.\d{1,3}){2}(\+\d{1,6})?$/D', $v) === 1,
            'etat_jeu' => $v === 'demonstration' || $v === 'production',
            'schema' => $v === self::VERSION_SCHEMA,
            'identifiant' => is_string($v) && preg_match('/^[A-Za-z0-9_-]{1,40}$/D', $v) === 1,
            default => false,
        };
    }

    /** Écrit l'instantané (déjà validé) puis purge au-delà des N derniers. */
    public static function enregistrer(array $instantane): void
    {
        DB::transaction(function () use ($instantane) {
            DB::table('indicateurs_clinique')->insert([
                'recu_le' => Format::maintenant(),
                'genere_le' => $instantane['genere_le'],
                'version_schema' => $instantane['schema'],
                'charge' => json_encode($instantane, JSON_UNESCAPED_UNICODE),
            ]);
            self::purger();
        });
    }

    public static function purger(): void
    {
        $max = max(2, (int) config('relais.indicateurs_clinique_max'));
        $seuil = DB::table('indicateurs_clinique')->orderByDesc('id')->skip($max)->take(1)->value('id');
        if ($seuil !== null) {
            DB::table('indicateurs_clinique')->where('id', '<=', $seuil)->delete();
        }
    }

    /** Les instantanés, du plus récent au plus ancien, décodés. */
    public static function derniers(int $n): array
    {
        return DB::table('indicateurs_clinique')->orderByDesc('id')->limit($n)->get()->map(fn ($l) => [
            'recu_le' => (int) $l->recu_le,
            'genere_le' => (int) $l->genere_le,
            'charge' => json_decode($l->charge, true) ?: [],
        ])->all();
    }
}
