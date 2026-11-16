<?php

/*
| SATISFACTION EN LIGNE (décision de la Direction du 16/11/2026, section 8) : le relais SERT le questionnaire publié par la mère et STOCKE des enveloppes
| chiffrées dans le navigateur avec la clé PUBLIQUE de la clinique. Il ne détient aucune clé privée et ne lit aucune réponse. Réglages en .env.
*/
return [
    // Débit des routes publiques, par adresse et par minute (limite de Laravel, table cache) : affichage du questionnaire et dépôt d'une réponse.
    'debit_page_par_minute' => (int) env('RELAIS_SATISFACTION_DEBIT_PAGE', 60),
    'debit_depot_par_minute' => (int) env('RELAIS_SATISFACTION_DEBIT_DEPOT', 10),

    // Plafond de réponses reçues par lien et par jour (un lien affiché en salle d'attente ne reçoit pas des milliers de réponses : au-delà, c'est un abus).
    'plafond_par_lien_et_jour' => (int) env('RELAIS_SATISFACTION_PLAFOND_JOUR', 500),

    // Taille maximale d'une enveloppe déposée (octets du corps) : une réponse chiffrée est petite.
    'enveloppe_octets_max' => (int) env('RELAIS_SATISFACTION_ENVELOPPE_OCTETS_MAX', 16384),

    // Taille maximale d'une publication de la mère (modèle de questions et clé publique).
    'publication_octets_max' => (int) env('RELAIS_SATISFACTION_PUBLICATION_OCTETS_MAX', 65536),

    // Un lien expiré ou révoqué depuis plus de N jours, sans enveloppe en attente, est retiré du relais à la relève suivante (le poste garde sa fiche).
    'conservation_jours' => (int) env('RELAIS_SATISFACTION_CONSERVATION_JOURS', 30),

    // Fuseau du jour d'expiration d'un lien et de la date de réception portée par une enveloppe.
    'fuseau' => 'Africa/Porto-Novo',
];
