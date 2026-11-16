# Décisions Q1 à Q42 (reprises de Nassiera Too, validées pour Baguidi le 17/11/2026)

La Direction de Baguidi a validé : « elles valent pour Baguidi, c'est une clinique, mêmes fonctionnalités ». Chaque ligne est donc une DÉCISION. Là où une valeur est « semée » ou « d'attente », elle est réglable et marquée « à valider ».
Quand une question suppose un mécanisme que Baguidi n'a pas (clôture annuelle, OCR…), l'agent MESURE d'abord ce qui existe (grep, lecture), applique ce qui manque, et dit dans son rapport ce qui n'était pas applicable et pourquoi.

## A. Droits et circuits
1. Qui règle le circuit de clôture (démarrer, clôturer, rouvrir) : l'administrateur et la Directrice Administrative, par un droit réglable de la fiche RBAC.
2. Un comptable seul NE peut PAS démarrer ET clôturer : la séparation « jamais la personne qui a démarré » reste.
3. Écritures d'inventaire en clôture : un RÉGLAGE de clinique (comptable et administrateur semés).
4. Validateur des commandes de stock (RG-04) : un RÉGLAGE de clinique, Directrice Administrative semée.
5. Réglages « réservés à l'administrateur et à la DAF » (fichiers, lecture des scans, MECeF) : un DROIT PAR RÉGLAGE, réglable séparément.
6. Technicien de laboratoire : AUCUN nouveau rôle semé ; l'administrateur crée le rôle et coche le geste.
7. Administrateur et DAF peuvent déposer une proposition de prix depuis un fileul : OUI.

## B. Règles de calcul et de lecture (assistant, stock, comptabilité)
8. « Dernière visite » d'un patient : la plus récente des dates de consultation, d'admission et de facture.
9. Deux réponses : « recettes » = encaissé ; « chiffre d'affaires » = facturé.
10. Délai de péremption (constante de 90 jours aujourd'hui) : paramètre de clinique en base, 90 jours semés, versionné par date.
11. Stock à une date passée : non offert en v1, réponse « non calculable ».
12. Articles non comptés à l'inventaire : enregistrer « non compté » sur la ligne (changement du moteur d'inventaire).
13. Dette fournisseur : définition la plus prudente (hors payée et soldée), à confirmer par le Comptable.
14. Balance âgée des patients : réglage de clinique, 30 et 90 jours semés.
15. Pharmacie et caisse : même rôle caissier (rôle pharmacien archivé) : confirmé. **Précisé le 16/11/2026** : le rôle pharmacien (rouvert le 06/11/2026) est GARDÉ, et aucun rôle n'est écrit en dur pour décider d'un droit de pharmacie ou de caisse : la Direction peut séparer les deux en cochant des cases (ECARTS-MAQUETTE E3210 à E3214).
16. Paie dans l'assistant : AUCUNE intention de paie en v1, sans exception.
17. Seuils de l'assistant sur de vraies questions : bonne intention ≥ 90 %, mauvaise intention répondue ≤ 2 %, zéro réponse inventée, 100 % des écritures refusées.

## C. Prix, import, clôture
18. Doublon CERT-APT : DEUX certificats DISTINCTS (« Certificat médical d'aptitude » 7 000 et « Certificat d'aptitude » 5 000 chez Nassiera). Le code reste au certificat que la caisse lit déjà ; l'autre reçoit un NOUVEL identifiant unique construit sur la convention des codes de certificats existants (lu dans le référentiel, jamais inventé) ; le moteur refuse de le réutiliser (refus nommé) ; aucun prix ne change ; aucune facture émise n'est réécrite ; le nouveau code est « proposition à valider ». Pour Baguidi : le mécanisme d'arbitrage de doublon gagne une TROISIÈME issue « ce sont deux prestations distinctes » qui fait exactement cela.
19. Certificats « prix unique, couverture SOS seule » : à confirmer par la Direction après relecture des lignes (afficher les lignes concernées, marquer à valider).
20. « Une demande par ligne » pour les prix : lue comme la demande d'import vérifiée, rejouée ligne à ligne par la mère.
21. Le Oui d'un fileul vaut proposition (même la Direction) : OUI.
22. Garanties écrites chez le fileul ET demandées : OUI.
23. Courriers comme dernier jeu d'import, avec les droits de l'administration : OUI.
24. « Fiche de consultation » de la vue unifiée : lue comme le dossier de consultation, avec renvoi vers l'écran.
25. Stock détail initial et bon de transfert réservés à la mère : OUI.
26. Synchroniser budgets, immobilisations, couvertures : OUI (sinon un import chez un fileul reste local au poste, contre la continuité de service).
27. Garder catalogueTarifs : OUI pour l'instant.
28. Première analyse d'un article sans prestation de prix : garder le comportement du poste (acceptée dès l'analyse).
29. Ouverture de l'exercice suivant : décembre, réglable.
Les 199 codes d'actes à 0 : le lot MESURE, classe par cause, et rend la ligne « prix à définir » au lieu de 0, sans JAMAIS valoriser un prix à la place de la Direction (déjà posé en v18 : refus « tarif à valider » et onglet « Sans prix » ; vérifier la couverture complète).

## D. OCR, sauvegarde, import
30. Versions du texte lu conservées sans limite, moteur réglable en base, délai 120 s par page : OUI (valeur d'attente).
31. Sauvegarde hors site : blocs de 1 Mio, copies 7 (magasin) et 14 (fichiers), plancher 2, plafond 60 : OUI.
32. Quota du relais de 5 Gio : à MESURER d'abord sur l'hébergement réel avant de s'engager (ne rien coder en dur).
33. Destination des fichiers par défaut : « Aucune » tant que leur volume n'est pas mesuré.
34. SFTP : reporté.
35. Même inventaire = même lot (contenu normalisé), identité retenue tant que des fiches existent : OUI (déjà appliqué, à confirmer).

## E. Continuité de service
36. Principes P1 à P5 : jamais bloquant, décision humaine hors de la mère, file qui se rejoue, jamais d'auto-validation, alerte réglable : OUI.
37. Promotion d'un fileul en mère de secours : PAS maintenant ; la restauration depuis la sauvegarde hors site reste le chemin, avec un DOCUMENT DE PROCÉDURE écrit.

## F. Tableaux (export Excel et impression des lignes cochées)
38. Garder le CSV en plus du .xlsx : OUI, les deux. Le .xlsx est un vrai classeur (cellules numériques et dates, en-tête figé, largeurs).
39. Qui peut exporter : un droit réservé réglable par rôle ; défaut : les rôles qui lisent l'écran.
40. Limite de lignes par export : AUCUNE valeur codée en dur ; réglage de clinique, valeur d'attente large marquée « à fixer sur la plus grande table réelle » ; au-delà, refus NOMMÉ, jamais de troncature silencieuse.
41. Sélection conservée d'une page à l'autre : OUI, jusqu'à ce que l'agent la vide.
42. Impression de la sélection : un seul tableau par défaut ; un état par ligne là où un document unitaire existe.
(a) « Tout exporter » : tout le tableau, toutes les pages, avec ou sans le filtre actif ; en arrière-plan avec un compteur au-delà d'un seuil réglable. (b) cocher une, plusieurs ou toutes les lignes et exporter seulement celles-ci. (c) imprimer seulement les lignes cochées, au gabarit du document. Droits appliqués à la sortie (colonnes et lignes que l'écran montre) ; journal des exports nominatifs (RG-12).
