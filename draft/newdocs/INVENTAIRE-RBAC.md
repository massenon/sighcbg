# Inventaire des accès par rôle — SIGH-CBG

Ce que **chaque rôle voit réellement** dans le méga-menu, produit en
interrogeant `N.tree(role)` — la fonction même qu'appelle le ruban — avec le
magasin chargé et ses surcharges enregistrées. Ce n'est pas ce que le
manifeste déclare : c'est ce que l'agent a sous les yeux.

| Symbole | Signification |
|---|---|
| L | lecture seule |
| **E** | écriture |
| **EA** | écriture et annulation |

## Synthèse

| Rôle | Écrans visibles | Dont modifiables | Accueil |
|---|---:|---:|---|
| Administrateur système | 140 | 140 | `dash-admin` |
| Direction / Gérance | 124 | 60 | `dash-direction` |
| Médecin | 14 | 7 | `dash-medecin` |
| Infirmier / Sage-femme | 8 | 8 | `dash-infirmier` |
| Comptable | 64 | 62 | `dash-comptable` |
| Responsable RH | 32 | 27 | `dash-rh` |

**Rôles archivés** (aucune session possible, droits transférés) : Directeur Médical, Directrice de l’Administration et des Finances (DAF), Pharmacien, Biologiste médical, Gestionnaire de Stock, Caissier — Dispensaire (Pharmacie), Réception / Accueil, Agent Administratif, Ambulancier, Aide-soignante, Technicien d’échographie, Surveillant, Assistant de Direction, Chirurgien, Anesthésiste — Réanimateur, Assistant Comptable, Ingénieur biomédical.

**Écrans fermés par activité** (pour tous les rôles, administrateur compris) : `dash-biomedical` — Poste d’ingénieur biomédical · `m5-banque-sang` — Banque de sang · `m5-donneurs` — Donneurs & transfusions · `m6-pharmacie-interne` — Officines et registre des délivrances · `m6-pharmacie-externe` — Officines et registre des délivrances · `m6-dispensation` — Officines et registre des délivrances · `m4-stats-maternite` — Statistiques des activités cliniques · `m2-stats-echographie` — Statistiques des activités cliniques · `m5-stats-examens` — Statistiques des activités cliniques · `m2-stats-consultations` — Statistiques des activités cliniques · `m3-stats-bloc` — Statistiques des activités cliniques · `m5-reactifs-stats` — Statistiques des activités cliniques · `m10-primes` — Primes (NS 132) · `m10-evaluations` — Évaluations & sanctions (barème NS 131) · `m10-sanctions` — Évaluations & sanctions (barème NS 131).

---

## Administrateur système  <small>`admin`</small>

140 écran(s) visible(s), dont 140 modifiable(s).

### Accueil

- **M13 — Courriers & orientation** : Courriers (départ / arrivée) **EA** · Répertoire des ambulances & urgences **EA** · Validations en attente **EA**
- **CFG — Tarification & information patient** : Référentiel tarifaire public **EA** · Catalogue des prestations **EA** · Tarifs des certificats & attestations **EA**

### Logistique

- **M6 — Pharmacie & Stocks** : Tableau de bord stock **EA** · Référentiel produits **EA** · Stock gros (magasin) **EA** · Stock détail (pharmacie) **EA** · Transferts gros → détail **EA** · Mouvements de stock **EA** · Lots & péremptions (FEFO) **EA** · Alertes & seuils **EA** · Inventaires **EA** · Pertes, casses & rebuts **EA** · Étiquetage & emplacements **EA** · Reprise SAGE 100 **EA** · Suivi des ventes **EA** · Point du stock valorisé **EA**
- **M7 — Achats & Fournisseurs** : Bons d’expression de besoins **EA** · Bons de commande **EA** · Bons de livraison **EA** · Réceptions & contrôles **EA** · Écarts de livraison **EA** · PV de réception — consommables **EA** · PV de réception — réactifs **EA** · Fournisseurs **EA** · Factures fournisseurs **EA**

### Financier

- **M12 — Comptabilité SYSCOHADA** : Tableau de bord comptable **EA** · Plan comptable OHADA **EA** · Journaux comptables **EA** · Écritures comptables **EA** · Dépenses journalières **EA** · Grand livre **EA** · Balance générale & âgée **EA** · Comptabilité analytique **EA** · Budgets **EA** · Immobilisations & amortissements **EA** · Banques & rapprochements **EA** · Compte de résultat **EA** · Seuil de rentabilité **EA** · États financiers **EA** · Baseline 2025 **EA** · Acompte sur impôt (AIB) **EA** · Échéances fiscales & paiements **EA** · Exercices & clôtures **EA**

### RH

- **M10 — Ressources humaines** : Fiches de poste **EA** · Tableau de bord RH **EA** · Personnel **EA** · Fiche employé **EA** · Contrats **EA** · Planning & gardes **EA** · Statistiques de garde **EA** · Statistiques des permanences **EA** · Taux de présence par service **EA** · Présences & absences **EA** · Congés **EA** · Ordres de mission **EA** · Événements du personnel **EA** · Frais de participation **EA** · Assurance du personnel **EA** · Prestataires externes **EA** · Sécurité & entretien **EA**
- **M11 — Paie & Primes** : Prêts-études et avances **EA** · Tableau de bord paie **EA** · Calcul de la paie **EA** · Bulletins de paie **EA** · Cotisations CNSS / ITS / VPS **EA** · Heures supplémentaires **EA** · Avances sur salaire **EA** · Redevance ORTB **EA** · Validation Direction **EA**

### Administration

- **M13 — Administration & Ambulance** : Courriers (départ / arrivée) **EA** · Réunions **EA** · Événements & notifications **EA** · Plan annuel de travail **EA** · Notes de service **EA** · Interventions ambulance **EA** · Répertoire des ambulances **EA** · Parc technique & maintenance **EA** · Validations en attente **EA** · Enquêtes & questionnaires **EA** · Satisfaction des patients **EA**
- **GED — Gestion documentaire** : Bibliothèque documentaire **EA** · Workflow de validation **EA** · Archivage & conservation **EA**
- **RAP — Rapports & Impression** : Bibliothèque des états **EA** · États de la Direction **EA** · Générateur de rapports **EA** · Historique des éditions **EA**

### Système

- **M14 — Sécurité & Utilisateurs** : Utilisateurs **EA** · Rôles & permissions (RBAC) **EA** · Prescripteurs & exécutants de soins **EA** · Sessions actives **EA** · Journal d’audit **EA** · Sauvegardes & restauration **EA**
- **CFG — Configuration Clinique** : Organisation & organigramme **EA** · Identité & papier à en-tête **EA** · Référentiel tarifaire **EA** · Catalogue tarifaire (deux prix) **EA** · Catalogue de l’imagerie **EA** · Papier à en-tête officiel **EA** · Types de pièces certifiantes **EA** · Rappels & messages **EA** · Certificats médicaux **EA** · Natures de facture **EA** · Centres de coûts **EA** · Règles métier versionnées **EA** · Paramètres fiscaux (IFU / RCCM) **EA** · Paramètres comptables & obligations **EA** · Notifications **EA** · Mon compte **EA** · Activité des modules **EA** · Paramètres système **EA**

### Pilotage

- **PIL — Pilotage & analyse** : Direction **EA** · Statistiques de la Direction **EA** · Tableau de bord dynamique croisé **EA** · Administrateur **EA** · Coût global de l’agent **EA** · Recettes & charges par groupe **EA**
- **DASH — Tableaux de bord par poste** : Médecin **EA** · Infirmier / Sage-femme **EA** · Pharmacie **EA** · Biologiste médical **EA** · Gestionnaire de stock **EA** · Caisse **EA** · Comptabilité **EA** · Ressources humaines **EA** · Accueil **EA** · Agent administratif **EA** · Ambulance **EA** · Aide-soignante **EA** · Échographie **EA** · Surveillant **EA** · Assistant de Direction **EA** · Chirurgien **EA** · Anesthésiste **EA** · Assistant Comptable **EA** · Espace patient **EA**

## Direction / Gérance  <small>`direction`</small>

124 écran(s) visible(s), dont 60 modifiable(s).

### Accueil

- **M13 — Courriers & orientation** : Courriers (départ / arrivée) **EA** · Répertoire des ambulances & urgences **EA** · Validations en attente **EA**
- **CFG — Tarification & information patient** : Référentiel tarifaire public **E** · Catalogue des prestations **E** · Tarifs des certificats & attestations **E**

### Logistique

- **M6 — Pharmacie & Stocks** : Tableau de bord stock L · Référentiel produits L · Stock gros (magasin) L · Stock détail (pharmacie) L · Transferts gros → détail L · Mouvements de stock L · Lots & péremptions (FEFO) L · Alertes & seuils L · Inventaires L · Pertes, casses & rebuts L · Étiquetage & emplacements L · Reprise SAGE 100 L · Suivi des ventes L · Point du stock valorisé L
- **M7 — Achats & Fournisseurs** : Bons d’expression de besoins **E** · Bons de commande **E** · Bons de livraison L · Réceptions & contrôles L · Écarts de livraison L · PV de réception — consommables L · PV de réception — réactifs L · Fournisseurs L · Factures fournisseurs L

### Financier

- **M12 — Comptabilité SYSCOHADA** : Tableau de bord comptable L · Plan comptable OHADA L · Journaux comptables L · Écritures comptables L · Dépenses journalières L · Grand livre L · Balance générale & âgée L · Comptabilité analytique L · Budgets L · Immobilisations & amortissements L · Banques & rapprochements L · Compte de résultat L · Seuil de rentabilité L · États financiers L · Baseline 2025 L · Acompte sur impôt (AIB) L · Échéances fiscales & paiements L · Exercices & clôtures L

### RH

- **M10 — Ressources humaines** : Fiches de poste L · Tableau de bord RH L · Personnel L · Fiche employé L · Contrats L · Planning & gardes L · Statistiques de garde L · Statistiques des permanences L · Taux de présence par service L · Présences & absences L · Congés L · Ordres de mission L · Événements du personnel L · Frais de participation L · Assurance du personnel L · Prestataires externes L · Sécurité & entretien L
- **M11 — Paie & Primes** : Prêts-études et avances L · Tableau de bord paie L · Calcul de la paie L · Bulletins de paie L · Cotisations CNSS / ITS / VPS L · Heures supplémentaires L · Avances sur salaire L · Redevance ORTB L · Validation Direction **E**

### Administration

- **M13 — Administration & Ambulance** : Courriers (départ / arrivée) **EA** · Réunions **EA** · Événements & notifications **EA** · Plan annuel de travail **EA** · Notes de service **EA** · Interventions ambulance **EA** · Répertoire des ambulances **EA** · Parc technique & maintenance **EA** · Validations en attente **EA** · Enquêtes & questionnaires **EA** · Satisfaction des patients **EA**
- **GED — Gestion documentaire** : Bibliothèque documentaire **E** · Workflow de validation **E** · Archivage & conservation **E**
- **RAP — Rapports & Impression** : Bibliothèque des états **E** · États de la Direction **E** · Générateur de rapports **E** · Historique des éditions **E**

### Système

- **M14 — Sécurité & Utilisateurs** : Utilisateurs **EA** · Rôles & permissions (RBAC) **EA** · Prescripteurs & exécutants de soins **EA** · Sessions actives **EA** · Journal d’audit **EA** · Sauvegardes & restauration **EA**
- **CFG — Configuration Clinique** : Organisation & organigramme **E** · Identité & papier à en-tête **E** · Référentiel tarifaire **E** · Catalogue tarifaire (deux prix) **E** · Catalogue de l’imagerie **E** · Papier à en-tête officiel **E** · Types de pièces certifiantes **E** · Rappels & messages **E** · Certificats médicaux **E** · Natures de facture **E** · Centres de coûts **E** · Règles métier versionnées **E** · Paramètres fiscaux (IFU / RCCM) **E** · Paramètres comptables & obligations **E** · Notifications **E** · Mon compte **E** · Activité des modules **E** · Paramètres système **E**

### Pilotage

- **PIL — Pilotage & analyse** : Direction **EA** · Statistiques de la Direction **EA** · Tableau de bord dynamique croisé **EA** · Coût global de l’agent **EA** · Recettes & charges par groupe **EA**
- **DASH — Tableaux de bord par poste** : Pharmacie **EA** · Chirurgien **EA** · Anesthésiste **EA** · Assistant Comptable **EA**

## Médecin  <small>`medecin`</small>

14 écran(s) visible(s), dont 7 modifiable(s).

### Logistique

- **M6 — Pharmacie & Stocks** : Tableau de bord stock L · Référentiel produits L · Mouvements de stock L · Lots & péremptions (FEFO) L · Alertes & seuils L · Pertes, casses & rebuts L · Étiquetage & emplacements L
- **M7 — Achats & Fournisseurs** : Bons d’expression de besoins **E**

### Administration

- **RAP — Rapports & Impression** : Bibliothèque des états **EA** · États de la Direction **EA** · Générateur de rapports **EA** · Historique des éditions **EA**

### Pilotage

- **DASH — Tableaux de bord par poste** : Médecin **EA** · Espace patient **EA**

## Infirmier / Sage-femme  <small>`infirmier`</small>

8 écran(s) visible(s), dont 8 modifiable(s).

### Accueil

- **M13 — Courriers & orientation** : Répertoire des ambulances & urgences **EA**

### Logistique

- **M7 — Achats & Fournisseurs** : Bons d’expression de besoins **E**

### Administration

- **M13 — Administration & Ambulance** : Répertoire des ambulances **EA**
- **RAP — Rapports & Impression** : Bibliothèque des états **EA** · États de la Direction **EA** · Générateur de rapports **EA** · Historique des éditions **EA**

### Pilotage

- **DASH — Tableaux de bord par poste** : Infirmier / Sage-femme **EA**

## Comptable  <small>`comptable`</small>

64 écran(s) visible(s), dont 62 modifiable(s).

### Accueil

- **M13 — Courriers & orientation** : Validations en attente L

### Logistique

- **M6 — Pharmacie & Stocks** : Tableau de bord stock **E** · Référentiel produits **E** · Stock gros (magasin) **E** · Stock détail (pharmacie) **E** · Transferts gros → détail **E** · Mouvements de stock **E** · Lots & péremptions (FEFO) **E** · Alertes & seuils **E** · Inventaires **E** · Pertes, casses & rebuts **E** · Étiquetage & emplacements **E** · Reprise SAGE 100 **E** · Suivi des ventes **E** · Point du stock valorisé **E**
- **M7 — Achats & Fournisseurs** : Bons d’expression de besoins **E** · Bons de commande **E** · Bons de livraison **E** · Réceptions & contrôles **E** · Écarts de livraison **E** · PV de réception — consommables **E** · PV de réception — réactifs **E** · Fournisseurs **E** · Factures fournisseurs **E**

### Financier

- **M12 — Comptabilité SYSCOHADA** : Tableau de bord comptable **EA** · Plan comptable OHADA **EA** · Journaux comptables **EA** · Écritures comptables **EA** · Dépenses journalières **EA** · Grand livre **EA** · Balance générale & âgée **EA** · Comptabilité analytique **EA** · Budgets **EA** · Immobilisations & amortissements **EA** · Banques & rapprochements **EA** · Compte de résultat **EA** · Seuil de rentabilité **EA** · États financiers **EA** · Baseline 2025 **EA** · Acompte sur impôt (AIB) **EA** · Échéances fiscales & paiements **EA** · Exercices & clôtures **EA**

### RH

- **M11 — Paie & Primes** : Prêts-études et avances **E** · Tableau de bord paie **E** · Calcul de la paie **E** · Bulletins de paie **E** · Cotisations CNSS / ITS / VPS **E** · Heures supplémentaires **E** · Avances sur salaire **E** · Redevance ORTB **E** · Validation Direction **E**

### Administration

- **M13 — Administration & Ambulance** : Validations en attente L
- **GED — Gestion documentaire** : Bibliothèque documentaire **E** · Workflow de validation **E** · Archivage & conservation **E**
- **RAP — Rapports & Impression** : Bibliothèque des états **E** · États de la Direction **E** · Générateur de rapports **E** · Historique des éditions **E**

### Pilotage

- **PIL — Pilotage & analyse** : Statistiques de la Direction **EA** · Tableau de bord dynamique croisé **EA** · Coût global de l’agent **EA** · Recettes & charges par groupe **EA**
- **DASH — Tableaux de bord par poste** : Comptabilité **EA**

## Responsable RH  <small>`rh`</small>

32 écran(s) visible(s), dont 27 modifiable(s).

### Logistique

- **M7 — Achats & Fournisseurs** : Bons d’expression de besoins **E**

### RH

- **M10 — Ressources humaines** : Fiches de poste **EA** · Tableau de bord RH **EA** · Personnel **EA** · Fiche employé **EA** · Contrats **EA** · Planning & gardes **EA** · Statistiques de garde **EA** · Statistiques des permanences **EA** · Taux de présence par service **EA** · Présences & absences **EA** · Congés **EA** · Ordres de mission **EA** · Événements du personnel **EA** · Frais de participation **EA** · Assurance du personnel **EA** · Prestataires externes **EA** · Sécurité & entretien **EA**
- **M11 — Paie & Primes** : Prêts-études et avances **E** · Tableau de bord paie **E** · Calcul de la paie **E** · Bulletins de paie **E** · Cotisations CNSS / ITS / VPS **E** · Heures supplémentaires **E** · Avances sur salaire **E** · Redevance ORTB **E** · Validation Direction L

### Administration

- **RAP — Rapports & Impression** : Bibliothèque des états L · États de la Direction L · Générateur de rapports L · Historique des éditions L

### Pilotage

- **DASH — Tableaux de bord par poste** : Ressources humaines **EA**
