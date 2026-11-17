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

    // Lot BAK (ADR-0008) : le dossier des blocs opaques de la sauvegarde hors site (sur disque, jamais en base). Les limites (quota, etc.) sont EN BASE, réglables au panneau.
    'sauvegardes_dir' => env('RELAIS_SAUVEGARDES_DIR', storage_path('app/sauvegardes')),

    // Conservation du journal d'audit (jours). Les enveloppes ne sont JAMAIS purgées par le relais.
    'retention_audit_jours' => (int) env('RELAIS_RETENTION_AUDIT_JOURS', 365),

    // Conservation MINIMALE de l'audit (jours) : en deçà, la purge refuse (RG-12, un journal trop court ne prouve plus rien). Réglable ; jamais écrite dans la commande.
    'retention_audit_jours_min' => (int) env('RELAIS_RETENTION_AUDIT_JOURS_MIN', 30),

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

    // ADR-0009 : les SMS par le relais. Le relais transporte un SMS déjà composé par la mère (un numéro, un texte), l'envoie par la tâche planifiée
    // `relais:sms-envoyer` (cron `schedule:run`), puis EFFACE le numéro et le texte. Les identifiants du fournisseur ne vivent QUE dans le .env du relais.
    'sms' => [
        // `journal` (défaut) n'envoie rien : pilote de l'essai. `http` : pilote HTTP générique, entièrement réglé par les variables RELAIS_SMS_HTTP_*.
        // `twilio` : API Messages de Twilio (RELAIS_SMS_TWILIO_*). `vonage` : API SMS de Vonage (RELAIS_SMS_VONAGE_*). Un nom inconnu est un échec NOMMÉ (`pilote_inconnu`), jamais un envoi simulé.
        'pilote' => env('RELAIS_SMS_PILOTE', 'journal'),
        // Nombre maximal de SMS envoyés par jour (jour civil d'Africa/Porto-Novo) ; un dépôt qui le dépasserait est refusé (429 plafond_atteint).
        'plafond_jour' => (int) env('RELAIS_SMS_PLAFOND_JOUR', 100),
        // Tentatives avant abandon : cinq au plus (une valeur supérieure est ramenée à cinq).
        'tentatives_max' => (int) env('RELAIS_SMS_TENTATIVES_MAX', 5),
        // Conservation des lignes TERMINÉES (déjà effacées : statut, tentatives, horodatages), en jours.
        'conservation_jours' => (int) env('RELAIS_SMS_CONSERVATION_JOURS', 30),
        // SMS envoyés au plus par passage du cron.
        'lot' => (int) env('RELAIS_SMS_LOT', 20),
        // Longueur maximale d'un texte (caractères, 320 au plus) et taille maximale d'un corps de dépôt (octets).
        'longueur_max' => (int) env('RELAIS_SMS_LONGUEUR_MAX', 320),
        'octets_max' => (int) env('RELAIS_SMS_OCTETS_MAX', 4096),
        // Pilote HTTP GÉNÉRIQUE : aucune API de fournisseur n'est écrite dans le dépôt ; adresse, clé, en-tête, expéditeur et noms des champs viennent du .env.
        'http' => [
            'url' => env('RELAIS_SMS_HTTP_URL', ''),
            'cle' => env('RELAIS_SMS_HTTP_CLE', ''),
            'entete_cle' => env('RELAIS_SMS_HTTP_ENTETE_CLE', 'Authorization'),
            'prefixe_cle' => env('RELAIS_SMS_HTTP_PREFIXE_CLE', 'Bearer '),
            'expediteur' => env('RELAIS_SMS_EXPEDITEUR', ''),
            'champ_numero' => env('RELAIS_SMS_HTTP_CHAMP_NUMERO', 'to'),
            'champ_texte' => env('RELAIS_SMS_HTTP_CHAMP_TEXTE', 'text'),
            'champ_expediteur' => env('RELAIS_SMS_HTTP_CHAMP_EXPEDITEUR', 'from'),
            'delai_s' => (int) env('RELAIS_SMS_HTTP_DELAI_S', 10),
        ],
        // Pilote Twilio (API Messages 2010-04-01). Identifiants UNIQUEMENT dans le .env : jamais en base, jamais dans le dépôt. L'expéditeur est RELAIS_SMS_EXPEDITEUR
        // (un numéro Twilio) ; à défaut, RELAIS_SMS_TWILIO_SERVICE (identifiant d'un service de messagerie). L'adresse de base ne change que pour un essai local.
        'twilio' => [
            'url_base' => env('RELAIS_SMS_TWILIO_URL_BASE', 'https://api.twilio.com/2010-04-01'),
            'sid' => env('RELAIS_SMS_TWILIO_SID', ''),
            'token' => env('RELAIS_SMS_TWILIO_TOKEN', ''),
            'expediteur' => env('RELAIS_SMS_EXPEDITEUR', ''),
            'service' => env('RELAIS_SMS_TWILIO_SERVICE', ''),
            'delai_s' => (int) env('RELAIS_SMS_HTTP_DELAI_S', 10),
        ],
        // Pilote Vonage : API SMS (`/sms/json`, clé et secret d'API), PAS la Messages API — elle n'exige qu'une clé et un secret, sans application ni clé privée JWT,
        // ce qui convient à un cPanel mutualisé. L'expéditeur (RELAIS_SMS_EXPEDITEUR) est un numéro ou un nom alphanumérique admis par le pays de destination.
        'vonage' => [
            'url' => env('RELAIS_SMS_VONAGE_URL', 'https://rest.nexmo.com/sms/json'),
            'cle' => env('RELAIS_SMS_VONAGE_CLE', ''),
            'secret' => env('RELAIS_SMS_VONAGE_SECRET', ''),
            'expediteur' => env('RELAIS_SMS_EXPEDITEUR', ''),
            'delai_s' => (int) env('RELAIS_SMS_HTTP_DELAI_S', 10),
        ],
    ],

    // Règles d'alerte du relais. Une alerte porte un type, une heure, un détail technique : jamais un contenu métier.
    'alertes' => [
        ['type' => 'battement', 'libelle' => 'Battement manquant', 'canal' => 'Courriel + panneau', 'active' => true],
        ['type' => 'appareil_bloque', 'libelle' => 'Appareil bloqué', 'canal' => 'Courriel + panneau', 'active' => true],
        ['type' => 'disque', 'libelle' => 'Espace disque faible', 'canal' => 'Courriel', 'active' => true],
        ['type' => 'cron', 'libelle' => 'Tâche cron non exécutée', 'canal' => 'Panneau', 'active' => true],
        // Lot RLS-SYNC : seuils réglés en base (écran Paramètres), pas ici.
        ['type' => 'fileul_silencieux', 'libelle' => 'Fileul silencieux', 'canal' => 'Panneau', 'active' => true],
        ['type' => 'mobile_silencieux', 'libelle' => 'Mobile silencieux', 'canal' => 'Panneau', 'active' => true],
        ['type' => 'boite_grossit', 'libelle' => 'Boîte aux lettres qui grossit', 'canal' => 'Panneau', 'active' => true],
    ],
];
