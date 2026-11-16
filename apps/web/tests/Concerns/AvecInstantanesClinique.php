<?php

namespace Tests\Concerns;

/** Outils des tests des indicateurs agrégés de la clinique (ADR-0007) : instantané valide, corps signé comme le fait la mère. */
trait AvecInstantanesClinique
{
    private const SECRET_INDICATEURS = 'secret-mere-indicateurs-test';

    /** Un instantané valide, modifiable par le test. */
    protected function instantane(array $remplace = []): array
    {
        $i = [
            'schema' => 1,
            'genere_le' => (int) (microtime(true) * 1000) - 1000,
            'version_application' => '1.4.2',
            'etat_jeu' => 'demonstration',
            'patients' => ['actifs' => 120, 'nouveaux_mois' => 7],
            'activite_mois' => ['m2_consultations' => 40, 'm2_visites' => 6, 'm2_rendezvous' => null, 'm3_admissions' => 3],
            'facturation_mois' => ['factures_emises' => 31, 'montant_facture' => 1520000, 'montant_encaisse' => 980000, 'reste_du' => 540000],
            'stock' => ['articles_sous_seuil' => 4, 'lots_proches_peremption' => 2, 'lots_perimes' => 0],
            'comptabilite' => ['echeances_en_retard' => 1, 'brouillons_non_valides' => 12, 'prochaine_echeance_code' => 'AIB', 'prochaine_echeance_date' => '2026-11-12'],
            'utilisateurs_actifs' => 9,
            'taux_occupation_lits_pct' => 25,
            'postes' => [['appareil' => 'poste-a1', 'derniere_synchro' => (int) (microtime(true) * 1000) - 60000]],
        ];

        return array_replace_recursive($i, $remplace);
    }

    /** Envoie un corps signé avec le secret de la mère (ou avec `$signature` si le test veut une signature fautive). */
    protected function publier(array $corps, ?string $secret = null, ?string $signature = null, ?string $brut = null)
    {
        $brut ??= json_encode($corps, JSON_UNESCAPED_UNICODE);
        $secret ??= self::SECRET_INDICATEURS;

        return $this->call('POST', '/mere/indicateurs-clinique', [], [], [], [
            'HTTP_X_MERE' => $secret,
            'HTTP_X_SIGNATURE' => $signature ?? 'sha256='.hash_hmac('sha256', $brut, $secret),
            'CONTENT_TYPE' => 'application/json',
            'HTTP_ACCEPT' => 'application/json',
        ], $brut);
    }
}
