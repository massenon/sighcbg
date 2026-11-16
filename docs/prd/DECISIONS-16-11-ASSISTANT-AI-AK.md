# Décisions du 16/11/2026 (reprises de Nassiera Too, validées pour Baguidi)

La Direction de Baguidi applique ces réponses à Baguidi (même métier). Seule différence de matériel : le boîtier MECeF de Baguidi est un **ELTRADE CC300**.

## 1. Délivrance ligne par ligne
Une ordonnance ne bloque plus toute la dispensation : chaque ligne RÉGLÉE se délivre (RG-03 : justificatif = n° d'ordonnance, stock jamais négatif) ; une ligne non réglée ou « prix à valoriser » reste en attente, nommée.

## 2. Assistant — relecture des 100 questions d'agents (84 validées, 1 reformulée, 2 refus gardés, 13 ouvertures)
- Refus gardés : dose d'un médicament (AVIS_MEDICAL_REFUSE) ; résultats d'un patient demandés par l'aide-soignante (RG-13).
- Reformulée en SUIVI : « commandes qui attendent ma validation » posée par la Direction (la validation RG-04 est à la DAF seule par défaut) : répondre en suivi (« voici les commandes en attente de la DAF »), jamais en « à valider par vous » si le rôle n'a pas le geste.
- « Recettes » : donner LES DEUX (encaissé ET facturé). Dette fournisseur : donner LES DEUX chiffres (factures non payées ET solde comptable du compte fournisseur) ET l'écart (remplace « une seule définition » de Q13).
- Stock à une date passée : VALIDÉ À CONSTRUIRE (reconstituer depuis les mouvements ; tant que non fiable, « non calculable », jamais zéro).
- Intentions à AJOUTER (lecture d'écrans existants, sous les droits de l'écran) : rôles qui ouvrent les écrans de la paie (admin) ; masse salariale du mois (Direction, lue sur le calcul de paie, droit de l'écran) ; balance des comptes du mois ; réunions de la semaine ; ambulance disponible ; ma prochaine garde ; échographies du jour ; congés de la semaine.
- Petits lots à faire : recherche patient par NOM (homonymes listés) et par CODE ; durée « articles immobiles » réglable ; balance des patients et nombre de jours LIBRE pour les impayés ; vue unifiée du dossier élargie (ordonnances, courriers, compte rendu opératoire, fiche d'anesthésie) ; aide d'utilisation (I24) et définitions (I25) : « pas de fiche » tant qu'aucune fiche validée.
- OUVERTURES de droits en LECTURE (fiches RBAC) : planning/gardes → Directeur Médical, Infirmier, Réception, Ambulancier, Chirurgien ; tarifs/prix → Biologiste, Technicien d'échographie, Comptable ; stock (labo/réactifs et pharmacie) → Biologiste, Anesthésiste ; plan des lits/admissions (qui est dans quel lit) → Agent administratif, Aide-soignante, Surveillant ; activité (tableau de bord d'activité) et état des ventes → Assistant de Direction.

## 3. Section AI — validations en attente de la mère
- Alerte au validateur et à l'administrateur quand une décision prise sur un fileul n'est pas appliquée par la mère au bout de **4 heures** (réglage de clinique en base).
- La mère VÉRIFIE que le compte inscrit sur la décision existe avec ce rôle dans les comptes de la clinique (sinon refus nommé).
- Date portée par la validation = **date de signature** ; la date d'application est gardée à côté.
- La pastille « N décisions en attente de la mère » compte les TROIS : validations, demandes de prix, demandes d'import.

## 4. Section AJ — prix et certificats
- Second certificat d'aptitude : code **CERT-APT-2**, « Certificat d'aptitude », **5 000**, couverture SOS seule (prix de la note de la Direction) ; rattaché au **générateur des pièces numérotées** (type de pièce à créer).
- Acte assurable dont la colonne « prix assuré » est vide : la ligne dit « prix assuré à définir » (prix non assuré affiché), jamais facturé au prix non assuré.
- L'indication « sans prix » est vue de TOUT le monde (la commande « Tarifer » reste réservée à qui décide un prix).
- Changement de jour : les listes de prix affichées sont aussi PROJETÉES au prix du jour sur le FILEUL (utile mère coupée).

## 5. Section AK — export des tableaux
- **Pas de limite** de lignes par défaut : seul le droit d'export compte. L'export (et l'impression) suit les FILTRES appliqués par l'utilisateur.

## 6. Clôture (lot CLO de Nassiera) — à vérifier dans Baguidi
Colonne N-1 du compte de résultat au même filtre de statut ; soldes d'ouverture et de clôture au grand livre (ouverture « écrite », « provisoire » ou « inconnue » : afficher « Inconnu », jamais zéro) ; journaux CL et AN réservés au moteur (pas de saisie manuelle) ; ouverture automatique de l'exercice suivant sans écrire aucune pièce.
