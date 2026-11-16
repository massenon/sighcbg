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

## 7. Compléments du 16/11/2026 (discussion Nassiera, validés pour Baguidi)
- Export : la LIMITE de lignes se règle par un GESTE RÉSERVÉ réglable (pas par le seul écran des paramètres) ; DEUX droits séparés : exporter (.xlsx, CSV) et imprimer depuis un tableau ; TOUT export et toute impression de tableau sont journalisés avec les IDENTIFIANTS des fiches (au plus 50 par entrée) et leur nombre total ; le texte MASQUÉ sort masqué, un montant ou une date sortent en VRAI nombre / VRAIE date (décimales comprises, pas le texte arrondi) ; les grilles de SAISIE en cours (panier, lignes en composition…) et les DOCUMENTS imprimés n'ont ni cases ni « Exporter » (liste écrite avec motif) ; dans la GED les cases servent seulement à exporter/imprimer, JAMAIS à valider en masse ; imprimer les PIÈCES COMPLÈTES cochées (factures, bons…), chacune sur sa page. L'export suit les filtres de l'utilisateur. CERT-APT-2 : couverture SOS seule confirmée.
- Ligne sans prix sur une facture : par DÉFAUT, RIEN de la facture ne s'encaisse tant qu'une ligne attend son prix (remplace la v21 « les autres lignes s'encaissent ») ; un RÉGLAGE de clinique permet d'encaisser le reste ; il est réglé par le rôle qui a le droit (geste réservé de la matrice) sur N'IMPORTE QUEL poste, et se propage par la synchronisation. Une facture en attente de prix (ni payée ni certifiée MECeF) est COMPLÉTÉE quand le prix est posé (ce n'est pas réécrire une pièce émise). Le prix est lu à la DATE DE LA PIÈCE : il faut une version de prix datée de ce jour (date passée = décision réservée) — le repli « premier prix validé après la pièce » de la v21 est RETIRÉ. L'alerte « prix manquant » (une par code, sans nom de patient) va aux rôles qui peuvent MODIFIER « Tarifs et prix » (actes, analyses, imagerie) ou le « Référentiel produits » (médicaments), lus dans la matrice.
- Aucune liste de rôles écrite en dur dans le code (toutes les décisions de droit passent par la matrice ou un geste réservé ; un cliquet global le garde).
- Fiscal : boutons « Confirmer » (motif obligatoire, tracé) pour la CNSS et le barème AIB ; AIB : DEUX barèmes en paramètres — taux de retenue sur la facture d'un tiers (3 % personne physique, 5 % personne morale) et barème par situation de l'acheteur (1 % IFU actif, 5 % sans IFU actif, 3 % prestation de service) ; le comptable choisit le barème à chaque opération.
- NON repris : le RCCM NAT/2021/M02-020 (identité de la clinique sœur). Baguidi garde RB/PKO/17 A 4240.

## 8. Lots du 16/11/2026 après-midi (discussion Nassiera, validés pour Baguidi)
- **Aucune trace de la clinique sœur, NULLE PART** (décision de la Direction de Baguidi) : ni dans le code, ni dans les données livrées, ni dans les documents, ni dans les DONNÉES DE TEST (fixtures, vecteurs, banc, tests). Le contrôle d'identité couvre désormais aussi les tests.
- **SMS par le relais** : le relais envoie les SMS par une tâche planifiée ; il ne voit que le numéro et le texte d'un message déjà composé par la mère, l'efface une fois envoyé ; plafond par jour ; identifiants du fournisseur dans le `.env` du relais, jamais dans le dépôt ; aucun contenu médical dans un SMS (un rappel dit le jour, l'heure et la clinique). Décision d'architecture écrite. Poste : écrans « Passerelle SMS » (avec « Tester l'envoi ») et « Journal des envois SMS ».
- **Satisfaction en ligne** : questionnaire sur le relais (lien ou QR), réponses CHIFFRÉES dans le navigateur, illisibles par le relais, redescendues à la mère et aux fileuls pour les statistiques ; aucun nom ni numéro de dossier demandé.
- **Planning individuel** : pour chaque agent, un régime individuel qui déroge champ par champ au régime de sa catégorie ou le remplace ; la fiche du personnel porte un planning hebdomadaire ou mensuel ; les valeurs d'attente sont marquées champ par champ.
- **Écran des modes MECeF** : choix du mode (boîtier ou e-MECeF), sans aucun numéro simulé ; le boîtier de Baguidi est l'ELTRADE CC300 ; un réglage décrit l'IMPRIMANTE DE CAISSE (modèle à renseigner par la clinique : aucun modèle n'est fourni pour Baguidi, valeur « à renseigner »).
- **Facturation des patients** : le bloc « FACTURE NORMALISÉE » (IFU de l'acheteur, Nom de l'acheteur, Taux d'AIB et ses phrases) DISPARAÎT de la facture d'un patient ; le moteur n'y exige ni n'applique d'AIB (le patient paie le total) ; la facture reste normalisée MECeF, sans acheteur ni AIB. La saisie de l'acheteur et de l'AIB ne reste que là où elle a un sens (assureur, entreprise, achats).
- NON repris pour Baguidi : l'adresse du relais et de la messagerie de la clinique sœur ; Baguidi fournira les siennes (réglages à renseigner).
