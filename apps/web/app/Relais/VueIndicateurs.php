<?php

namespace App\Relais;

/**
 * Mise en forme PURE des indicateurs agrégés pour le tableau de bord de la clinique (ADR-0007). Hors du composant Livewire à dessein : une méthode publique
 * d'un composant est appelable depuis le navigateur ; ces fonctions n'ont aucune raison de l'être, et la page n'expose ainsi aucune action.
 */
class VueIndicateurs
{
    /** `hausse` : une hausse est une bonne nouvelle ; `baisse` : une baisse l'est ; `neutre` : on ne juge pas. */
    public const CARTES = [
        'patients_actifs' => ['Patients actifs', 'patients.actifs', 'entier', 'neutre'],
        'nouveaux_patients' => ['Nouveaux patients du mois', 'patients.nouveaux_mois', 'entier', 'hausse'],
        'consultations' => ['Consultations du mois (M2)', 'activite_mois.m2_consultations', 'entier', 'hausse'],
        'visites' => ['Visites du mois (M2)', 'activite_mois.m2_visites', 'entier', 'hausse'],
        'admissions' => ['Admissions du mois (M3)', 'activite_mois.m3_admissions', 'entier', 'neutre'],
        'factures' => ['Factures émises du mois', 'facturation_mois.factures_emises', 'entier', 'hausse'],
        'facture' => ['Montant facturé du mois', 'facturation_mois.montant_facture', 'fcfa', 'hausse'],
        'encaisse' => ['Montant encaissé du mois', 'facturation_mois.montant_encaisse', 'fcfa', 'hausse'],
        'reste_du' => ['Reste dû du mois', 'facturation_mois.reste_du', 'fcfa', 'baisse'],
        'sous_seuil' => ['Articles sous leur seuil', 'stock.articles_sous_seuil', 'entier', 'baisse'],
        'peremption' => ['Lots proches de la péremption', 'stock.lots_proches_peremption', 'entier', 'baisse'],
        'perimes' => ['Lots périmés en stock', 'stock.lots_perimes', 'entier', 'baisse'],
        'retards' => ['Échéances fiscales en retard', 'comptabilite.echeances_en_retard', 'entier', 'baisse'],
        'brouillons' => ['Brouillons comptables non validés', 'comptabilite.brouillons_non_valides', 'entier', 'baisse'],
        'utilisateurs' => ['Utilisateurs actifs', 'utilisateurs_actifs', 'entier', 'neutre'],
        'occupation' => ['Taux d’occupation des lits', 'taux_occupation_lits_pct', 'pct', 'neutre'],
    ];

    public static function lire(array $charge, string $chemin): int|string|null
    {
        $v = $charge;
        foreach (explode('.', $chemin) as $k) {
            if (! is_array($v) || ! array_key_exists($k, $v)) {
                return null;
            }
            $v = $v[$k];
        }

        return is_int($v) || is_string($v) ? $v : null;
    }

    public static function formater(int|string|null $v, string $format): string
    {
        if ($v === null) {
            return 'non disponible';
        }

        return match ($format) {
            'fcfa' => number_format((int) $v, 0, ',', "\u{202F}")."\u{00A0}FCFA",
            'pct' => $v.' %',
            default => number_format((int) $v, 0, ',', "\u{202F}"),
        };
    }

    /** Variation entre l'instantané et le précédent : null si l'un des deux manque. */
    public static function variation(int|string|null $v, int|string|null $avant, string $format, string $sens): ?array
    {
        if (! is_int($v) || ! is_int($avant)) {
            return null;
        }
        $d = $v - $avant;
        $texte = $d === 0 ? 'stable' : (($d > 0 ? '+' : '−').self::formater(abs($d), $format));
        $ton = match (true) {
            $d === 0, $sens === 'neutre' => 'neutre',
            ($d > 0) === ($sens === 'hausse') => 'ok',
            default => 'alerte',
        };

        return ['texte' => $texte, 'ton' => $ton];
    }

    /** Seuil au-delà duquel un instantané est « trop ancien » : le plus grand du plancher et de trois fois l'intervalle observé entre les deux derniers. */
    public static function seuilAncien(array $instantanes): int
    {
        $plancher = (int) config('relais.seuil_indicateurs_clinique_ms');
        if (count($instantanes) >= 2) {
            return max($plancher, 3 * max(0, $instantanes[0]['recu_le'] - $instantanes[1]['recu_le']));
        }

        return $plancher;
    }

    /** Points de la courbe (du plus ancien au plus récent), en coordonnées d'un cadre 600 x 140. */
    public static function courbe(array $instantanes, string $cle): array
    {
        $def = self::CARTES[$cle] ?? self::CARTES['facture'];
        $serie = [];
        foreach (array_reverse($instantanes) as $i) {
            $v = self::lire($i['charge'], $def[1]);
            if (is_int($v)) {
                $serie[] = ['quand' => $i['recu_le'], 'v' => $v];
            }
        }
        if ($serie === []) {
            return ['points' => [], 'min' => null, 'max' => null, 'n' => 0];
        }
        $min = min(array_column($serie, 'v'));
        $max = max(array_column($serie, 'v'));
        $t0 = $serie[0]['quand'];
        $t1 = $serie[count($serie) - 1]['quand'];
        $pts = [];
        foreach ($serie as $p) {
            $x = $t1 === $t0 ? 300 : 10 + 580 * (($p['quand'] - $t0) / ($t1 - $t0));
            $y = $max === $min ? 70 : 130 - 120 * (($p['v'] - $min) / ($max - $min));
            $pts[] = ['x' => round($x, 1), 'y' => round($y, 1)];
        }

        return ['points' => $pts, 'min' => $min, 'max' => $max, 'n' => count($serie), 'debut' => $t0, 'fin' => $t1];
    }

}
