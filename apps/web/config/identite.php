<?php

/*
| IDENTITÉ AFFICHÉE PAR LE RELAIS (coque du panneau, connexion, questionnaire public). Aucune valeur n'est écrite dans une vue : les vues lisent ce fichier.
| Les valeurs de départ sont celles de l'identité de la Clinique Baguidi (packages/domaine/lib/src/impression/identite.dart, fiche de la Direction du
| 06/11/2026) ; le relais ne connaît d'elle que ces deux libellés et son logo. Une autre installation les surcharge dans le .env.
*/
return [
    // Nom court affiché en tête de la barre latérale.
    'nom' => env('RELAIS_CLINIQUE_NOM', 'CLINIQUE BAGUIDI'),

    // Devise de la clinique, composée en police manuscrite (Dancing Script) : vide, rien ne s'affiche.
    'devise' => env('RELAIS_CLINIQUE_DEVISE', 'Votre bien-être est notre raison d’être.'),

    // Version affichée au pied de la barre latérale (à changer à chaque livraison du relais).
    'version' => env('RELAIS_VERSION', '1.0'),
];
