<?php

return [
    /*
    | Le RELAIS est opaque : il ne détient AUCUNE clé. Ce secret n'authentifie que la mère de la clinique auprès
    | du relais (déposer dans les boîtes, relever les enveloppes des mobiles, révoquer). À poser dans .env.
    */
    'secret_mere' => env('RELAIS_SECRET_MERE', ''),

    // Silence de la mère au-delà duquel le relais lève l'alerte « battement ». 5 minutes par défaut (spec §13).
    'seuil_battement_ms' => (int) env('RELAIS_SEUIL_BATTEMENT_MS', 300000),

    // Crochets réservés au banc d'essai (altérer / retirer une enveloppe). JAMAIS en production.
    'banc' => (bool) env('RELAIS_BANC', false),

    // Conservation du journal d'audit (jours). Les enveloppes ne sont JAMAIS purgées par le relais.
    'retention_audit_jours' => (int) env('RELAIS_RETENTION_AUDIT_JOURS', 365),

    // Espace disque libre (en %) sous lequel l'alerte « disque » se lève.
    'seuil_disque_pct' => (int) env('RELAIS_SEUIL_DISQUE_PCT', 10),

    // Silence du cron (schedule:run) au-delà duquel l'alerte « cron » se lève.
    'seuil_cron_ms' => (int) env('RELAIS_SEUIL_CRON_MS', 300000),

    // Tableau de bord de la clinique (ADR-0007) : indicateurs agrégés NON nominatifs publiés par la mère, sur interrupteur ouvert côté poste.
    // Nombre d'instantanés conservés (les plus anciens sont purgés à chaque réception).
    'indicateurs_clinique_max' => (int) env('RELAIS_INDICATEURS_CLINIQUE_MAX', 500),
    // Plancher de l'alerte « instantané trop ancien » : l'alerte se lève au-delà du plus grand de ce seuil et de trois fois l'intervalle observé.
    'seuil_indicateurs_clinique_ms' => (int) env('RELAIS_SEUIL_INDICATEURS_CLINIQUE_MS', 3600000),
    // Taille maximale du corps d'un instantané (octets) : un instantané est petit, un corps volumineux est refusé sans être lu.
    'indicateurs_clinique_octets_max' => (int) env('RELAIS_INDICATEURS_CLINIQUE_OCTETS_MAX', 16384),

    // Règles d'alerte du relais. Une alerte porte un type, une heure, un détail technique : jamais un contenu métier.
    'alertes' => [
        ['type' => 'battement', 'libelle' => 'Battement manquant', 'canal' => 'Courriel + panneau', 'active' => true],
        ['type' => 'appareil_bloque', 'libelle' => 'Appareil bloqué', 'canal' => 'Courriel + panneau', 'active' => true],
        ['type' => 'disque', 'libelle' => 'Espace disque faible', 'canal' => 'Courriel', 'active' => true],
        ['type' => 'cron', 'libelle' => 'Tâche cron non exécutée', 'canal' => 'Panneau', 'active' => true],
    ],
];
