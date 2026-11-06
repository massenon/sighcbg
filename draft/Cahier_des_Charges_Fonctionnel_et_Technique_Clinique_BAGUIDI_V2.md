_Cahier des Charges Fonctionnel et Technique – Logiciel de Gestion des Stocks, des Achats, de la_ 

Clinique BAGUIDI – « L'As du Cœur » _Pharmacie et des Ressources Humaines_ 

##### **CAHIER DES CHARGES FONCTIONNEL ET TECHNIQUE** 

# **Logiciel de Gestion des Stocks, des Achats, de la Pharmacie et des Ressources Humaines** 

_Document contractuel de référence — Architecture fonctionnelle, technique, données, interfaces et sécurité_ 

### **CLINIQUE BAGUIDI « L'AS DU CŒUR » – PARAKOU** 

|**Référence document**|**Date**|**Version**|**Statut**|**Difusion**|
|---|---|---|---|---|
|BAG-CDC-2026-02|14 juillet 2026|V2.1|Projet — Révision architecture<br>desktop/réseau local, AIB paie,<br>exports normalisés, analytque<br>et budgétaire — Pour<br>validaton DG|Restreinte|



_Document confidentiel — Diffusion restreinte à la Direction Générale de la Clinique BAGUIDI et à l'équipe de mission_ 

Cabinet Massenon & Kowi Conseil — Document confidentiel — Page 1 / 37 

_Cahier des Charges Fonctionnel et Technique – Logiciel de Gestion des Stocks, des Achats, de la_ 

Clinique BAGUIDI – « L'As du Cœur » _Pharmacie et des Ressources Humaines_ 

## **SOMMAIRE** 

|1. Préambule et objet du document........................................................................................................6|
|---|
|2. Contexte du projet................................................................................................................................7|
|3. Objectfs du projet................................................................................................................................8|
|4. Périmètre fonctonnel...........................................................................................................................9|
|4.1. Modules inclus dans le périmètre.................................................................................................9|
|4.2. Domaines expressément exclus du périmètre..............................................................................9|
|5. Acteurs du système et rôles...............................................................................................................10|
|6. Glossaire.............................................................................................................................................11|
|7. Règles de geston générales...............................................................................................................12|
|8. Exigences fonctonnelles détaillées par module................................................................................13|
|8.1. Module M1 – Geston des Achats et des Fournisseurs...............................................................13|
|8.2. Module M2 – Geston des Bons de Commande..........................................................................13|
|8.3. Module M3 – Geston des Bons de Livraison et de la Récepton................................................13|
|8.4. Modules M4 et M5 – Geston des Stocks Pharmacie de Gros et de Détail.................................14|
|8.5. Module M6 – Geston du Laboratoire et des Réactfs.................................................................14|
|8.6. Module M7 – Geston des Fournitures Administratves et Consommables...............................14|
|8.7. Module M8 – Geston des Fiches de Stock et des Fiches de Sorte............................................14|
|8.8. Module M9 – Geston des Seuils d'Alerte et des Dates de Pérempton.....................................15|
|8.9. Module M10 – Geston des Inventaires......................................................................................15|
|8.10. Module M11 – Geston des Factures Fournisseurs et de l'AIB..................................................15|
|8.11. Modules M12 et M13 – Intégraton Caisse et Geston des Assurances....................................15|
|8.12. Module M14 – Geston des Ressources Humaines et de la Paie..............................................16|
|8.13. Module M15 – Tableaux de Bord, Rapports de Geston et Impression des États....................16|
|8.14. Module M16 – Facturaton complète, Comptabilité générale, Analytque et Budgétaire.......17|
|9. Stack Technologique Recommandé...................................................................................................19|
|9.1. Architecture générale retenue — Desktop mult-poste en réseau local....................................19|
|9.2. Stack retenu en détail..................................................................................................................19|
|9.3. Justfcaton du choix...................................................................................................................20|
|9.4. Alternatves envisagées et écartées............................................................................................21|
|10. Architecture Base de Données & Schéma........................................................................................23|
|10.1. Principes de Modélisaton.........................................................................................................23|
|10.2. Modèle Conceptuel — Domaines de Données.........................................................................23|
|10.3. Détail des Tables Clés................................................................................................................23|
|10.4. Règles d'Intégrité Transversales................................................................................................25|
|10.5. Diagramme Relatonnel — Vue Simplifée (texte).....................................................................26|
|11. Cartographie des Interfaces & Design Système...............................................................................27|



Cabinet Massenon & Kowi Conseil — Document confidentiel — Page 2 / 37 

_Cahier des Charges Fonctionnel et Technique – Logiciel de Gestion des Stocks, des Achats, de la_ 

Clinique BAGUIDI – « L'As du Cœur » _Pharmacie et des Ressources Humaines_ 

|11.1. Séquence de Démarrage (Splash — Welcome — Login)...........................................................27|
|---|
|11.2. Shell Applicatf...........................................................................................................................27|
|11.3. Cartographie Détaillée par Module...........................................................................................27|
|11.4. Design System — Charte Graphique.........................................................................................28|
|12. Architecture de Sécurité...................................................................................................................29|
|12.1. Matrice des Rôles (RBAC)..........................................................................................................29<br>|
|12.2. Authentfcaton & Sessions.......................................................................................................29|
|12.3. Protecton des Données & Conformité.....................................................................................29|
|12.4. Audit & Traçabilité.....................................................................................................................30|
|12.5. Sécurité applicatve transverse.................................................................................................30|
|13. Exigences non fonctonnelles...........................................................................................................31|
|13.1. Performance et disponibilité.....................................................................................................31|
|13.2. Sauvegarde et contnuité...........................................................................................................31|
|13.3. Ergonomie..................................................................................................................................31|
|13.4. Interopérabilité..........................................................................................................................31|
|14. Profls utlisateurs et droits d'accès — Synthèse..............................................................................32|
|15. Cas d'utlisaton principaux (Use Cases)...........................................................................................33<br>|
|UC-01 – Émetre et faire valider un bon de commande....................................................................33|
|UC-02 – Réceptonner une livraison...................................................................................................33|
|UC-03 – Délivrer un produit sur tcket patent...................................................................................33|
|UC-04 – Traiter un retour patent.......................................................................................................33|
|UC-05 – Clôturer l'inventaire quotdien.............................................................................................33|
|UC-06 – Générer la paie mensuelle d'un médecin de garde..............................................................33|
|UC-07 – Facturer mensuellement une compagnie d'assurance........................................................33|
|UC-08 – Clôturer la comptabilité mensuelle......................................................................................33|
|16. Scénarios méters illustratfs............................................................................................................34|
|Scénario A – Rupture de stock imminente.....................................................................................34|
|Scénario B – Produit proche de la pérempton..............................................................................34|
|Scénario C – Patent assuré avec taux de prise en charge de 80%................................................34|
|Scénario D – Écart constaté lors de l'inventaire.............................................................................34|
|17. Interfaces avec les systèmes existants.............................................................................................35|
|17.1. Interface avec le logiciel de caisse.............................................................................................35|
|17.2. Interface avec le logiciel de geston des assurances.................................................................35|
|18. États et rapports à produire.............................................................................................................36|
|19. Critères de recete et d'acceptaton.................................................................................................37|
|20. Hypothèses, contraintes et exclusions.............................................................................................38|
|20.1. Hypothèses................................................................................................................................38|
|20.2. Contraintes................................................................................................................................38|



Cabinet Massenon & Kowi Conseil — Document confidentiel — Page 3 / 37 

Clinique BAGUIDI – « L'As du Cœur » _Cahier des Charges Fonctionnel et Technique – Logiciel de Gestion des Stocks, des Achats, de la Pharmacie et des Ressources Humaines_ 

|20.3. Exclusions expressément confrmées........................................................................................38|
|---|
|21. Annexes............................................................................................................................................39|
|Annexe 1 – Documents sources ayant servi à l'élaboraton du présent cahier des charges.............39|
|Annexe 2 – Tableau de correspondance périmètre / journaux Excel actuels....................................39|



Cabinet Massenon & Kowi Conseil — Document confidentiel — Page 4 / 37 

_Cahier des Charges Fonctionnel et Technique – Logiciel de Gestion des Stocks, des Achats, de la_ 

Clinique BAGUIDI – « L'As du Cœur » _Pharmacie et des Ressources Humaines_ 

## **1. Préambule et objet du document** 

Le présent Cahier des Charges Fonctionnel et Technique (CdCF) fait suite au Rapport de Cadrage, de Collecte d'Informations et d'Analyse des Besoins remis à la Direction Générale de la Clinique BAGUIDI « L'As du Cœur » à l'issue de la réunion de cadrage du 13 juillet 2026. Il a pour objet de décrire, de manière structurée et exhaustive, les exigences fonctionnelles, l'architecture technique, le modèle de données, la cartographie des interfaces et le dispositif de sécurité auxquels devra répondre le futur logiciel de gestion des stocks, des achats, de la pharmacie, des ressources humaines et de la comptabilité de la clinique. 

Cette version enrichie du document intègre, à la demande de la Direction Générale, le périmètre étendu à seize modules fonctionnels — dont un module de facturation complète et de comptabilité générale — ainsi que trois volets techniques structurants : le stack technologique recommandé, l'architecture de la base de données, la cartographie des interfaces utilisateur et du design system, et l'architecture de sécurité. Il constitue la référence contractuelle destinée à guider le développement de la solution et servira de base aux Spécifications Fonctionnelles Détaillées (SFD) et à la proposition financière. 

Cabinet Massenon & Kowi Conseil — Document confidentiel — Page 5 / 37 

_Cahier des Charges Fonctionnel et Technique – Logiciel de Gestion des Stocks, des Achats, de la_ 

Clinique BAGUIDI – « L'As du Cœur » _Pharmacie et des Ressources Humaines_ 

## **2. Contexte du projet** 

La Clinique BAGUIDI « L'As du Cœur », établissement de santé privé basé à Parakou, gère aujourd'hui l'ensemble de ses achats, de ses stocks, de sa pharmacie et de sa comptabilité à travers des outils bureautiques (Microsoft Excel) et des supports papier (cahiers de stock et de sortie), sans intégration avec le logiciel de caisse et le logiciel de gestion des assurances déjà en place. Cette situation, détaillée dans le Rapport de Cadrage associé au présent document, expose l'établissement à des risques de rupture de stock, de péremption, d'écarts d'inventaire et de perte de traçabilité. 

Le présent projet vise à doter la clinique d'un outil de gestion intégré couvrant les achats, les fournisseurs, la pharmacie de gros et de détail, le laboratoire, les réactifs, les fournitures administratives, les inventaires, la gestion des ressources humaines et de la paie, la facturation complète et la comptabilité générale, ainsi que l'interfaçage avec le logiciel de caisse existant et la gestion des assurés. 

Cabinet Massenon & Kowi Conseil — Document confidentiel — Page 6 / 37 

Clinique BAGUIDI – « L'As du Cœur » _Cahier des Charges Fonctionnel et Technique – Logiciel de Gestion des Stocks, des Achats, de la Pharmacie et des Ressources Humaines_ 

## **3. Objectifs du projet** 

1. Fiabiliser et automatiser le suivi des stocks de la pharmacie de gros, de la pharmacie de détail, du laboratoire et des réactifs ; 

2. Sécuriser le processus d'achat, depuis l'expression du besoin jusqu'à la réception et au règlement des fournisseurs ; 

3. Automatiser l'inventaire quotidien et le rapprochement entre les recettes, les dépenses et les stocks ; 

4. Mettre en place des alertes automatiques sur les seuils de stock et les dates de péremption ; 

5. Interfacer le futur outil avec le logiciel de caisse existant et le dispositif de gestion des assurances, sans les remplacer ; 

6. Automatiser la gestion de la paie du personnel permanent et des prestataires (médecins par garde et permanence, réparateurs, agents d'entretien) ; 

7. Étendre le système à la facturation complète, à la comptabilité générale, analytique et budgétaire de la clinique, en remplacement progressif des journaux Excel actuels ; 

8. Fournir à la Direction Générale des tableaux de bord et rapports de gestion fiables, imprimables et exportables en PDF et Excel à tous les niveaux, dans le respect des en-têtes des journaux actuellement utilisés ; 

9. Retenir une architecture technique de type application desktop fonctionnant en réseau local, robuste, sécurisée et indépendante d'une connexion internet permanente, adaptée aux contraintes réelles d'exploitation de la clinique (absence de serveur local et de cloud). 

Cabinet Massenon & Kowi Conseil — Document confidentiel — Page 7 / 37 

_Cahier des Charges Fonctionnel et Technique – Logiciel de Gestion des Stocks, des Achats, de la_ 

Clinique BAGUIDI – « L'As du Cœur » _Pharmacie et des Ressources Humaines_ 

## **4. Périmètre fonctionnel** 

#### **4.1. Modules inclus dans le périmètre** 

|**N°**|**Module**|
|---|---|
|M1|Geston des Achats et des Fournisseurs|
|M2|Geston des Bons de Commande|
|M3|Geston des Bons de Livraison et de la Récepton|
|M4|Geston des Stocks – Pharmacie de Gros|
|M5|Geston des Stocks – Pharmacie de Détail|
|M6|Geston du Laboratoire et des Réactfs|
|M7|Geston des Fournitures Administratves et Consommables|
|M8|Geston des Fiches de Stock et des Fiches de Sorte|
|M9|Geston des Seuils d'Alerte et des Dates de Pérempton|
|M10|Geston des Inventaires|
|M11|Geston des Factures Fournisseurs et de l'AIB|
|M12|Intégraton avec le Logiciel de Caisse existant|
|M13|Geston des Assurances|
|M14|Geston des Ressources Humaines et de la Paie|
|M15|Tableaux de Bord et Rapports de Geston, Impression des États|
|M16|Facturaton complète, Comptabilité générale, Analytque et Budgétaire|



#### **4.2. Domaines expressément exclus du périmètre** 

- Dossier Patient Informatisé (DPI) ; 

- Module de Consultation médicale et d'Hospitalisation ; 

- Business Intelligence avancée et data warehouse ; 

- Application mobile et Portail Patient ; 

- Remplacement du logiciel de caisse ou du logiciel d'assurance existants — seule une interface avec ces derniers est demandée ; 

- Gestion des vaccins, non concernés par l'activité pharmaceutique actuelle de la clinique. 

Cabinet Massenon & Kowi Conseil — Document confidentiel — Page 8 / 37 

_Cahier des Charges Fonctionnel et Technique – Logiciel de Gestion des Stocks, des Achats, de la_ 

Clinique BAGUIDI – « L'As du Cœur » _Pharmacie et des Ressources Humaines_ 

## **5. Acteurs du système et rôles** 

|**Acteur**|**Rôle principal dans le système**|
|---|---|
|Directeur Général|Validaton des bons de commande, consultaton des tableaux de bord et des<br>états fnanciers, supervision générale|
|Comptable – Achats/Stocks|Créaton des bons de commande, récepton des livraisons, geston des fches de<br>stock, inventaire|
|Comptable – Caisse/Facturaton|Suivi des recetes, rapprochement caisse-stock, geston des opératons diverses<br>et de l'AIB|
|Comptable – Comptabilité générale|Tenue des journaux comptables, du grand livre, des états fnanciers et des<br>immobilisatons|
|Responsable Pharmacie de Gros|Geston des entrées, du stockage et des transferts vers la Pharmacie de Détail|
|Responsable Pharmacie de Détail|Dispensaton des produits sur tcket, geston des retours, mise à jour du stock<br>détail|
|Responsable Laboratoire|Geston du stock de réactfs, enregistrement des consommatons liées aux<br>analyses|
|Responsable Ressources Humaines|Geston des fches du personnel, saisie des heures de garde, génératon des fches<br>de paie|
|Caissière|Validaton quotdienne du cumul des dépenses, clôture de l'inventaire journalier|
|Administrateur système|Paramétrage, geston des droits d'accès, supervision technique de la soluton|



Cabinet Massenon & Kowi Conseil — Document confidentiel — Page 9 / 37 

_Cahier des Charges Fonctionnel et Technique – Logiciel de Gestion des Stocks, des Achats, de la_ 

Clinique BAGUIDI – « L'As du Cœur » _Pharmacie et des Ressources Humaines_ 

## **6. Glossaire** 

|**Terme / Sigle**|**Défniton**|
|---|---|
|AIB|Acompte sur Impôt assis sur les Bénéfces, retenue à la source appliquée aux achats et<br>prestatons (taux observés de 3% et 5%)|
|IFU|Identfant Fiscal Unique du fournisseur ou du prestataire|
|SoBAPS|Société Béninoise pour l'Approvisionnement en Produits de Santé, fournisseur principal<br>de produits pharmaceutques|
|FEFO|First Expired, First Out – méthode de sorte de stock privilégiant les produits dont la date<br>de pérempton est la plus proche|
|SYSCOHADA|Système Comptable de l'Organisaton pour l'Harmonisaton en Afrique du Droit des<br>Afaires, référentel comptable applicable au Bénin|
|APDP|Autorité de Protecton des Données à caractère Personnel du Bénin|
|RBAC|Role-Based Access Control – modèle de geston des droits d'accès basé sur des rôles|
|Pharmacie Gros|Structure de stockage principal recevant les livraisons fournisseurs|
|Pharmacie Détail|Structure de dispensaton directe aux patents, alimentée par la Pharmacie de Gros|
|Ticket Infrmier / Ticket<br>Patent|Documents émis par la caisse lors de la facturaton d'une ordonnance|
|OD|Opératon Diverse – écriture comptable de régularisaton|
|IMO|Immobilisaton – bien durable inscrit à l'actf de la clinique|
|KKiaPay|Passerelle de paiement mobile utlisée par la clinique pour l'encaissement électronique|
|API|Applicaton Programming Interface – interface de programmaton permetant l'échange<br>de données entre deux logiciels|
|ORM|Object-Relatonal Mapping – couche logicielle traduisant les objets applicatfs en<br>requêtes de base de données|



Cabinet Massenon & Kowi Conseil — Document confidentiel — Page 10 / 37 

_Cahier des Charges Fonctionnel et Technique – Logiciel de Gestion des Stocks, des Achats, de la_ 

Clinique BAGUIDI – « L'As du Cœur » _Pharmacie et des Ressources Humaines_ 

## **7. Règles de gestion générales** 

10. Tout bon de commande doit être validé par le Directeur Général avant transmission au fournisseur ; aucune commande ne peut être envoyée sans cette validation ; 

11. Toute entrée de stock en Pharmacie de Gros doit être rattachée à un bon de livraison fournisseur et à un bon de commande préalable, sauf commande d'urgence documentée ; 

12. Tout transfert de la Pharmacie de Gros vers la Pharmacie de Détail doit être tracé, daté et rattaché à un responsable identifié ; 

13. Toute sortie de produit en Pharmacie de Détail doit être rattachée à un ticket émis par la caisse mentionnant l'identité du patient ; 

14. Un produit ne peut être sorti du stock si la quantité disponible est nulle ou insuffisante ; le système doit empêcher toute sortie générant un stock négatif ; 

15. La sortie des produits doit respecter, sauf exception justifiée, la règle FEFO (premier périmé, premier sorti) ; 

16. Tout retour patient – caisse – pharmacie doit être accompagné d'une observation obligatoire et entraîner la régularisation automatique du stock et de la facturation ; 

17. L'AIB doit être calculé automatiquement sur chaque facture fournisseur, selon un taux paramétrable par fournisseur ; 

18. L'AIB doit également être calculé automatiquement sur les rémunérations versées via le circuit de la paie aux prestataires et vacataires soumis à cette retenue (notamment les médecins vacataires et prestataires occasionnels), selon la même logique de taux paramétrable que pour les fournisseurs ; 

19. La clôture de l'inventaire quotidien doit être validée par la caissière et ne peut être modifiée a posteriori sans traçabilité de la modification ; 

20. Toute écriture comptable générée automatiquement par un module métier (achats, stock, caisse, paie) doit demeurer équilibrée (débit = crédit) et non modifiable manuellement, seule une écriture de contre-passation étant autorisée ; 

21. La rémunération des médecins de garde doit être calculée automatiquement à partir des heures déclarées et d'un taux horaire distinct entre période de permanence (8h–20h) et période de garde (20h–8h). 

Cabinet Massenon & Kowi Conseil — Document confidentiel — Page 11 / 37 

_Cahier des Charges Fonctionnel et Technique – Logiciel de Gestion des Stocks, des Achats, de la_ 

Clinique BAGUIDI – « L'As du Cœur » _Pharmacie et des Ressources Humaines_ 

## **8. Exigences fonctionnelles détaillées par module** 

Chaque module fait l'objet d'une description de son objectif, de ses fonctionnalités détaillées et de ses principales règles de gestion spécifiques. 

#### **8.1. Module M1 – Gestion des Achats et des Fournisseurs** 

Objectif : centraliser la gestion de la base fournisseurs et du processus d'achat, depuis l'expression du besoin jusqu'à la réception. 

|**Réf.**|**Exigence fonctonnelle**|
|---|---|
|EF-M1-01|Créer, modifer et consulter une fche fournisseur (raison sociale, code, adresse, téléphone, IFU,<br>numéro d'enregistrement client, taux d'AIB applicable)|
|EF-M1-02|Rechercher un fournisseur par nom, code ou catégorie de produits fournis|
|EF-M1-03|Consulter l'historique des commandes et des livraisons par fournisseur|
|EF-M1-04|Associer chaque fournisseur à une ou plusieurs catégories de produits (pharmaceutque,<br>laboratoire, fournitures, entreten)|
|EF-M1-05|Générer un tableau de suivi des dépenses par fournisseur et par période|



#### **8.2. Module M2 – Gestion des Bons de Commande** 

|**Réf.**|**Exigence fonctonnelle**|
|---|---|
|EF-M2-01|Créer un bon de commande avec numéro séquentel automatque, date, fournisseur, liste des<br>produits, quanttés demandées et prix unitaires|
|EF-M2-02|Soumetre le bon de commande à l'approbaton du Directeur Général (workfow : Brouillon / En<br>atente / Approuvé / Rejeté)|
|EF-M2-03|Éditer et imprimer le bon de commande au format normalisé|
|EF-M2-04|Transmetre électroniquement ou imprimer le bon de commande validé pour envoi au fournisseur|
|EF-M2-05|Permetre la saisie de commandes d'urgence avec motf obligatoire, hors circuit de validaton<br>standard|
|EF-M2-06|Générer une facture proforma à la demande|



#### **8.3. Module M3 – Gestion des Bons de Livraison et de la Réception** 

|**Réf.**|**Exigence fonctonnelle**|
|---|---|
|EF-M3-01|Enregistrer un bon de livraison (numéro, date, fournisseur, produits livrés, quanttés, numéros de<br>lot, dates de pérempton, prix, montant HT, AIB, net à payer)|
|EF-M3-02|Rapprocher automatquement les quanttés livrées et commandées, avec signalement des écarts|
|EF-M3-03|Bloquer l'entrée en stock de tout produit dont la pérempton est dépassée ou trop proche|
|EF-M3-04|Valider l'entrée en stock en Pharmacie de Gros, avec horodatage et identfcaton du|



Cabinet Massenon & Kowi Conseil — Document confidentiel — Page 12 / 37 

Clinique BAGUIDI – « L'As du Cœur » _Cahier des Charges Fonctionnel et Technique – Logiciel de Gestion des Stocks, des Achats, de la Pharmacie et des Ressources Humaines_ 

|**Réf.**|**Exigence fonctonnelle**<br>réceptonnaire|
|---|---|
|EF-M3-05|Associer chaque bon de livraison à la facture normalisée correspondante|



#### **8.4. Modules M4 et M5 – Gestion des Stocks Pharmacie de Gros et de Détail** 

|**Réf.**|**Exigence fonctonnelle**|
|---|---|
|EF-M4-01|Créer une fche de stock par produit (entête clinique, date, nom, dosage, forme, stock d'alerte,<br>entrées/sortes/solde)|
|EF-M4-02|Calculer automatquement le solde de stock à chaque mouvement|
|EF-M4-03|Gérer les transferts de la Pharmacie de Gros vers la Pharmacie de Détail|
|EF-M4-04|Consulter en temps réel le niveau de stock de chaque produit, par pharmacie|
|EF-M4-05|Gérer les numéros de lot et les dates de pérempton à l'unité de conditonnement|
|EF-M4-06|Gérer le circuit de retour Patent – Caisse – Pharmacie de Détail avec observaton obligatoire|
|EF-M4-07|Empêcher toute sorte de stock supérieure à la quantté disponible|



#### **8.5. Module M6 – Gestion du Laboratoire et des Réactifs** 

|**Réf.**|**Exigence fonctonnelle**|
|---|---|
|EF-M6-01|Créer une fche de stock par réactf (nom, dosage, unité, seuil d'alerte, date de pérempton)|
|EF-M6-02|Enregistrer les entrées de réactfs reçues de la Pharmacie de Gros ou d'un fournisseur spécialisé|
|EF-M6-03|Enregistrer les sortes de réactfs par analyse réalisée, ratachées au tcket patent|
|EF-M6-04|Éditer un cahier de stock et de sorte numérique du laboratoire|



#### **8.6. Module M7 – Gestion des Fournitures Administratives et Consommables** 

|**Réf.**|**Exigence fonctonnelle**|
|---|---|
|EF-M7-01|Gérer un stock distnct pour les fournitures administratves, produits d'entreten et consommables<br>non pharmaceutques|
|EF-M7-02|Permetre la demande interne de fournitures avec validaton par un responsable habilité|
|EF-M7-03|Suivre les charges récurrentes non stockées (eau, électricité, gasoil, abonnements)|



#### **8.7. Module M8 – Gestion des Fiches de Stock et des Fiches de Sortie** 

|**Réf.**|**Exigence fonctonnelle**|
|---|---|
|EF-M8-01|Générer automatquement une fche de stock consultable et imprimable pour chaque produit|
|EF-M8-02|Générer une fche de sorte par mouvement (produit, date, quantté, bénéfciaire)|
|EF-M8-03|Permetre l'export des fches au format PDF et tableur|



Cabinet Massenon & Kowi Conseil — Document confidentiel — Page 13 / 37 

_Cahier des Charges Fonctionnel et Technique – Logiciel de Gestion des Stocks, des Achats, de la_ 

Clinique BAGUIDI – « L'As du Cœur » _Pharmacie et des Ressources Humaines_ 

|**Réf.**|**Exigence fonctonnelle**|
|---|---|
|EF-M8-04|Historiser toutes les modifcatons apportées à une fche de stock|



#### **8.8. Module M9 – Gestion des Seuils d'Alerte et des Dates de Péremption** 

|**Réf.**|**Exigence fonctonnelle**|
|---|---|
|EF-M9-01|Paramétrer un seuil d'alerte minimum par produit et par pharmacie|
|EF-M9-02|Déclencher une alerte visuelle et/ou notfcaton au franchissement du seuil|
|EF-M9-03|Paramétrer un délai d'alerte avant pérempton, confgurable par catégorie de produit|
|EF-M9-04|Générer une liste consolidée des produits proches de la pérempton|
|EF-M9-05|Appliquer la règle FEFO lors de la propositon de sorte de stock|



#### **8.9. Module M10 – Gestion des Inventaires** 

|**Réf.**|**Exigence fonctonnelle**|
|---|---|
|EF-M10-01|Générer automatquement, chaque matn, un état consolidé des recetes et dépenses de la veille|
|EF-M10-02|Calculer automatquement le cumul des dépenses et le rapprocher d'un panier normalisé de<br>référence|
|EF-M10-03|Permetre la validaton de l'inventaire quotdien par la caissière, avec horodatage|
|EF-M10-04|Empêcher la modifcaton d'un inventaire validé sans traçabilité explicite|
|EF-M10-05|Permetre un inventaire physique ponctuel avec calcul automatque des écarts|
|**8.10. Module**<br>**Réf.**|**M11 – Gestion des Factures Fournisseurs et de l'AIB**<br>**Exigence fonctonnelle**|
|EF-M11-01|Enregistrer les factures normalisées et les ratacher au bon de livraison correspondant|
|EF-M11-02|Calculer automatquement l'AIB selon le taux paramétré pour le fournisseur|
|EF-M11-03|Générer automatquement l'annexe mensuelle AIB (IFU, fournisseur, montant, taux, montant<br>d'AIB)|
|EF-M11-04|Enregistrer les opératons de régularisaton de surplus d'AIB par fournisseur|
|EF-M11-05|Éditer un état des factures fournisseurs par période, avec statut de règlement|



#### **8.10. Module M11 – Gestion des Factures Fournisseurs et de l'AIB** 

#### **8.11. Modules M12 et M13 – Intégration Caisse et Gestion des Assurances** 

|**Réf.**|**Exigence fonctonnelle**|
|---|---|
|EF-M12-01<br>EF-M12-02|Recevoir, via interface électronique, les informatons de facturaton émises par le logiciel de caisse<br>Rapprocher automatquement chaque tcket émis par la caisse avec la sorte de stock<br>correspondante|



Cabinet Massenon & Kowi Conseil — Document confidentiel — Page 14 / 37 

_Cahier des Charges Fonctionnel et Technique – Logiciel de Gestion des Stocks, des Achats, de la_ 

Clinique BAGUIDI – « L'As du Cœur » _Pharmacie et des Ressources Humaines_ 

|**Réf.**|**Exigence fonctonnelle**|
|---|---|
|EF-M12-03|Signaler tout écart entre le produit facturé et le produit efectvement délivré|
|EF-M13-01|Interfacer le système avec le logiciel de geston des assurances pour vérifer la validité des cartes<br>et récupérer le taux de prise en charge|
|EF-M13-02|Générer mensuellement, pour chaque compagnie d'assurance partenaire, une facture normalisée<br>détaillée par patent assuré|
|EF-M13-03|Conserver l'historique des taux de prise en charge appliqués|



#### **8.12. Module M14 – Gestion des Ressources Humaines et de la Paie** 

|**Réf.**|**Exigence fonctonnelle**|
|---|---|
|EF-M14-01|Gérer une fche par agent (identté, situaton matrimoniale, catégorie, numéro CNSS, salaire de<br>base)|
|EF-M14-02|Saisir mensuellement les heures de garde et de permanence de chaque médecin|
|EF-M14-03|Calculer automatquement la rémunératon des médecins par garde et permanence|
|EF-M14-04|Gérer les avances sur salaire et les déduire automatquement du bulletn|
|EF-M14-05|Calculer la part patronale des cotsatons sociales et l'IRPP|
|EF-M14-06|Générer et éditer automatquement une fche de paie individuelle mensuelle|
|EF-M14-07|Gérer distnctement la rémunératon des prestataires externes|
|EF-M14-08|Calculer et appliquer automatquement l'AIB sur les rémunératons des prestataires et vacataires<br>soumis à cete retenue, selon un taux paramétrable, et intégrer ce montant dans le bulletn ou<br>l'état de paiement correspondant|
|**8.13. Module**<br>**États**<br>**Réf.**|**M15 – Tableaux de Bord, Rapports de Gestion et Impression des**<br>**Exigence fonctonnelle**|
|EF-M15-01|Tableau de bord des niveaux de stock par produit, pharmacie et catégorie|
|EF-M15-02|Tableau de bord des achats et des dépenses par fournisseur et par période|
|EF-M15-03|Rapport quotdien d'inventaire|
|EF-M15-04|Rapport mensuel de facturaton par compagnie d'assurance|
|EF-M15-05|État récapitulatf mensuel de la paie et des heures de garde|
|EF-M15-06|Impression normalisée de l'ensemble des états et documents (bons, factures, fches de paie, états<br>fnanciers)|
|EF-M15-07|Export, pour chaque module et à tous les niveaux du système, de l'ensemble des états aux formats<br>PDF et Excel|
|EF-M15-08|Garantr que tout export Excel respecte strictement les en-têtes et la structure des onglets du<br>classeur Excel « Journal de Janvier » actuellement utlisé par la clinique (Achats, Ventes, Salaires,<br>|
||Caisse-Dépenses, Opératons Diverses, Prestatons, Point AIB, Immobilisatons), afn d'assurer la|



#### **8.13. Module M15 – Tableaux de Bord, Rapports de Gestion et Impression des États** 

Cabinet Massenon & Kowi Conseil — Document confidentiel — Page 15 / 37 

_Cahier des Charges Fonctionnel et Technique – Logiciel de Gestion des Stocks, des Achats, de la_ 

Clinique BAGUIDI – « L'As du Cœur » _Pharmacie et des Ressources Humaines_ 

|**Réf.**|**Exigence fonctonnelle**|
|---|---|
||contnuité de lecture pour les utlisateurs et les ters habitués à ce format|
|EF-M15-09|Permetre l'impression directe, depuis n'importe quel poste du réseau local, de tout état consulté<br>à l'écran, sans passer par un export intermédiaire|



###### **_8.13.1. Conformité des exports aux en-têtes des journaux existants_** 

Afin de garantir la continuité avec les pratiques actuelles de la clinique et de faciliter l'appropriation du nouvel outil, tout export ou impression Excel généré par le système — quel que soit le module d'origine — doit reprendre à l'identique les en-têtes de colonnes des onglets du classeur Excel actuellement en usage, rappelés ci-dessous. 

|**Onglet du classeur actuel**|**En-têtes de colonnes à respecter**|
|---|---|
|Achats (ACH), Ventes (VEN), Salaires (SAL),<br>Caisse-Dépenses, Opératons Diverses<br>(OD), Prestatons (PRE), Immobilisatons<br>(IMO)|Date | Pièces | Références | Compte | Débit | Crédit | Libellés | Mode<br>de paiement (le cas échéant, pour Achats et Caisse-Dépenses)|
|Point AIB|Num IFU | Nom du fournisseur ou Prestataire | Adresse/Tél | Montant<br>| Taux | Montant AIB|



#### **8.14. Module M16 – Facturation complète, Comptabilité générale, Analytique et Budgétaire** 

Objectif : étendre le système à la tenue comptable complète de la clinique, conformément au référentiel SYSCOHADA révisé en vigueur au Bénin, en remplacement progressif des journaux Excel actuellement tenus (Achats, Ventes, Salaires, Opérations Diverses, Immobilisations), et à doter la Direction Générale d'une comptabilité analytique par centre de coût ainsi que d'un dispositif de gestion budgétaire prévisionnelle. 

|**Réf.**|**Exigence fonctonnelle**|
|---|---|
|EF-M16-01|Tenir un plan comptable paramétrable conforme au référentel SYSCOHADA révisé|
|EF-M16-02|Générer automatquement les écritures comptables à partr des mouvements des modules<br>Achats, Stock, Caisse et Paie|
|EF-M16-03|Tenir les journaux comptables (Achats, Ventes, Banque, Caisse, Opératons Diverses, Salaires) de<br>manière automatsée|
|EF-M16-04|Générer le Grand Livre, la Balance générale, le Bilan et le Compte de Résultat|
|EF-M16-05|Gérer les immobilisatons (fche d'immobilisaton, plan d'amortssement), en remplacement de<br>l'onglet Immobilisatons actuel|
|EF-M16-06|Produire les déclaratons fscales périodiques (AIB et autres taxes applicables) destnées à<br>l'administraton fscale béninoise, y compris l'AIB retenu sur les rémunératons de prestataires<br>versées via la paie|
|EF-M16-07|Permetre le rapprochement bancaire entre les comptes de la clinique et les écritures comptables<br>enregistrées|



Cabinet Massenon & Kowi Conseil — Document confidentiel — Page 16 / 37 

_Cahier des Charges Fonctionnel et Technique – Logiciel de Gestion des Stocks, des Achats, de la_ 

Clinique BAGUIDI – « L'As du Cœur » _Pharmacie et des Ressources Humaines_ 

|**Réf.**|**Exigence fonctonnelle**|
|---|---|
|EF-M16-08|Gérer la facturaton complète des patents non assurés et assurés, en complément de l'interfaçage<br>avec la caisse existante|
|EF-M16-09|Défnir un plan analytque par centre de coût (Pharmacie de Gros, Pharmacie de Détail,<br>Laboratoire, Administraton, Ressources Humaines) et afecter automatquement chaque écriture<br>comptable pertnente à un ou plusieurs centres de coût|
|EF-M16-10|Établir un budget prévisionnel annuel, décliné par mois et par poste de dépense/centre de coût,<br>saisi ou importé par la Directon Générale en début d'exercice|
|EF-M16-11|Suivre en contnu la consommaton budgétaire réelle par rapport au budget prévisionnel, avec<br>calcul automatque des écarts en valeur et en pourcentage|
|EF-M16-12|Déclencher une alerte visuelle en cas de dépassement ou d'approche d'un seuil budgétaire<br>paramétrable, par poste ou par centre de coût|
|EF-M16-13|Éditer un rapport analytque et budgétaire périodique (mensuel, trimestriel, annuel), exportable<br>en PDF et Excel, destné à la Directon Générale|



Cabinet Massenon & Kowi Conseil — Document confidentiel — Page 17 / 37 

_Cahier des Charges Fonctionnel et Technique – Logiciel de Gestion des Stocks, des Achats, de la_ 

Clinique BAGUIDI – « L'As du Cœur » _Pharmacie et des Ressources Humaines_ 

## **9. Stack Technologique Recommandé** 

Le présent chapitre a été révisé à la suite des précisions apportées par la Direction Générale sur les conditions réelles d'exploitation informatique de la clinique : le logiciel doit être une application de type bureautique (desktop), installée sur les postes de travail et fonctionnant en réseau local, avec une interface propre à chaque rôle (Ressources Humaines, Comptabilité, Direction Générale, Pharmacie, Laboratoire, Caisse) selon ses permissions. La clinique dispose d'une connexion internet mais ne possède à ce jour ni serveur local dédié, ni hébergement cloud. Le stack initialement proposé (architecture web Laravel nécessitant un serveur d'application et supposant une continuité réseau) n'est donc plus adapté : une solution entièrement dépendante d'un serveur distant ou d'internet exposerait la clinique à un blocage total de son activité en cas de coupure de connexion. Le cabinet propose en conséquence un stack alternatif, conçu pour fonctionner de manière totalement autonome sur le réseau local de la clinique, sans aucune dépendance à internet pour les opérations courantes. 

#### **9.1. Architecture générale retenue — Desktop multi-poste en réseau local** 

Le cabinet recommande une architecture client-serveur de données déployée entièrement sur le réseau local (LAN) de la clinique, sans nécessiter de serveur dédié ni d'hébergement cloud : un poste de travail existant (par exemple celui de la comptabilité) héberge le moteur de base de données partagée, tandis que chaque utilisateur (RH, Comptable, Direction Générale, Pharmacie, Laboratoire, Caisse) installe sur son propre poste l'application desktop, qui se connecte à cette base via le réseau local filaire ou Wi-Fi interne. Aucune connexion internet n'est requise pour le fonctionnement quotidien : la connexion internet existante de la clinique n'est mobilisée que pour des usages non critiques et optionnels (mises à jour logicielles, sauvegarde chiffrée complémentaire hors site, consultation distante ponctuelle par la Direction Générale). Cette approche élimine le risque de blocage total de l'activité en cas de coupure internet, tout en restant peu coûteuse puisqu'elle ne requiert l'acquisition d'aucun matériel serveur supplémentaire. 

|**Couche**|**Rôle**|
|---|---|
|Poste client (applicaton desktop)|Applicaton installée sur chaque poste (RH, Comptabilité, Directon, Pharmacie<br>Gros/Détail, Laboratoire, Caisse), présentant une interface propre au rôle et aux<br>permissions de l'utlisateur connecté|
|Poste hôte de la base de données<br>(réseau local)|Poste de travail existant désigné (ex. comptabilité) hébergeant le moteur de base<br>de données partagée, accessible en lecture/écriture par tous les postes clients via<br>le réseau local ; aucun matériel serveur dédié n'est nécessaire|
|Connexion internet (usage<br>optonnel)|Mobilisée uniquement pour les mises à jour logicielles, la sauvegarde chifrée hors<br>site et un éventuel accès distant sécurisé de la Directon Générale ; son absence<br>n'interrompt jamais le fonctonnement courant du logiciel|



#### **9.2. Stack retenu en détail** 

|**Couche / Besoin**|**Technologie retenue**|**Justfcaton**|
|---|---|---|
|Framework applicatf|.NET 8 (C#) avec WPF, ou Java 21|Frameworks matures pour applicatons de|



Cabinet Massenon & Kowi Conseil — Document confidentiel — Page 18 / 37 

_Cahier des Charges Fonctionnel et Technique – Logiciel de Gestion des Stocks, des Achats, de la_ 

Clinique BAGUIDI – « L'As du Cœur » _Pharmacie et des Ressources Humaines_ 

|**Couche / Besoin**|**Technologie retenue**|**Justfcaton**|
|---|---|---|
|desktop|avec JavaFX|geston desktop mult-fenêtres, avec geston<br>natve de rôles/permissions et impression ;<br>compétences disponibles localement,<br>notamment en Java|
|Base de données partagée<br>en réseau local|PostgreSQL 15 (ou MySQL/MariaDB<br>10.6+) installé sur le poste hôte|Moteur transactonnel robuste, fonctonnant<br>sur un simple poste de bureau performant,<br>sans nécessiter de serveur dédié ; accessible<br>en réseau local via TCP/IP|
|Couche d'accès aux<br>données (ORM)|Entty Framework Core (.NET) ou<br>Hibernate/JPA (Java)|Fiabilise les requêtes, applique les règles<br>d'intégrité décrites en secton 10.4, accélère<br>le développement|
|||Éditon des bons de commande, factures,|
|Génératon de documents<br>PDF|QuestPDF / iTextSharp (.NET) ou<br>iText/JasperReports (Java)|fches de stock, fches de paie et états<br>fnanciers au format PDF imprimable, sans<br>connexion internet|
|Export Excel|ClosedXML/EPPlus (.NET) ou<br>Apache POI (Java)|Génératon d'exports Excel respectant<br>strictement les en-têtes des journaux actuels<br>(secton 8.13.1), directement depuis le poste<br>client|
|Authentfcaton & droits|Module d'authentfcaton interne à<br>l'applicaton (identfants stockés<br>de manière chifrée dans la base<br>locale) + modèle RBAC applicatf|Implémentaton du modèle RBAC décrit en<br>secton 12.1, sans dépendance à un annuaire<br>ou service cloud externe|
|Notfcatons et alertes|Mécanisme de rafraîchissement<br>périodique (polling) sur le réseau<br>local|Alertes de seuil de stock et de pérempton<br>fonctonnant entèrement en local, sans<br>service ters ni connexion internet|
|Tests automatsés|xUnit/NUnit (.NET) ou JUnit (Java)|Fiabilisaton des calculs sensibles (AIB, paie,<br>comptabilité, budgétaire) avant chaque mise<br>à jour|
|Installaton et déploiement|Programme d'installaton<br>(.msi/.exe ou paquet Java) sur<br>chaque poste, avec confguraton<br>automatque de la connexion au<br>poste hôte de données|Déploiement simple ne nécessitant pas de<br>compétence système avancée sur site|
|Sauvegardes|Sauvegarde automatque<br>quotdienne locale (sur disque<br>externe ou clé réseau) + opton de<br>sauvegarde chifrée vers un espace<br>cloud lorsque la connexion internet<br>est disponible|Contnuité des données garante même en<br>l'absence totale d'internet ; le cloud<br>n'intervient qu'en complément, jamais<br>comme conditon de fonctonnement|



#### **9.3. Justification du choix** 

La contrainte déterminante de ce projet est l'absence de serveur local et d'hébergement cloud, combinée à une connexion internet présente mais non garantie en continu. Une architecture web classique (telle qu'envisagée initialement avec Laravel) suppose la disponibilité permanente d'un 

Cabinet Massenon & Kowi Conseil — Document confidentiel — Page 19 / 37 

_Cahier des Charges Fonctionnel et Technique – Logiciel de Gestion des Stocks, des Achats, de la_ 

Clinique BAGUIDI – « L'As du Cœur » _Pharmacie et des Ressources Humaines_ 

serveur d'application — local ou distant — pour que les postes clients puissent fonctionner ; en l'absence de serveur local et sans hebergement cloud, toute coupure internet ou indisponibilité du service d'hébergement distant aurait pour conséquence de bloquer l'intégralité de l'activité de gestion de la clinique, ce qui est inacceptable pour un établissement de santé fonctionnant en continu. Une architecture desktop multi-poste en réseau local, en revanche, ne dépend que de l'infrastructure réseau interne de la clinique (postes de travail et réseau local filaire ou Wi-Fi), totalement maîtrisée sur site et indépendante d'internet. Elle préserve néanmoins l'ensemble des bénéfices recherchés : interfaces différenciées par rôle et permission (RH, Comptabilité, Direction, Pharmacie, Laboratoire, Caisse), base de données partagée unique garantissant la cohérence des informations entre tous les postes, et calculs automatisés (AIB, paie, comptabilité, analytique et budgétaire) exécutés localement sans latence réseau externe. 

#### **9.4. Alternatives envisagées et écartées** 

|**Alternatve**|**Avantages**|**Raisons de non-priorisaton**|
|---|---|---|
|Applicaton web (Laravel/PHP) hébergée<br>sur serveur local ou cloud — stack<br>initalement envisagé|Écosystème très répandu,<br>compétences locales<br>abondantes, coût de licence nul|Suppose l'existence d'un serveur<br>local ou d'un hébergement cloud,<br>absents à ce jour à la clinique ; toute<br>panne ou coupure réseau bloquerait<br>l'ensemble de l'actvité, incompatble<br>avec la contrainte de contnuité de<br>service exprimée|
|Applicaton Electron<br>(JavaScript/TypeScript) avec base<br>embarquée|Réutlisaton de compétences<br>web, développement rapide<br>d'interfaces|Consommaton mémoire élevée sur<br>des postes de bureau standards ;<br>geston mult-utlisateur en réseau<br>local moins natve qu'avec un vrai<br>client-serveur applicatf|
|Progiciel de geston intégré (ERP)<br>généraliste du marché|Rapidité de mise en œuvre<br>initale|Rigidité de paramétrage pour les<br>spécifcités locales (AIB, SYSCOHADA,<br>circuit caisse-pharmacie) et coûts de<br>licence récurrents, souvent liés à un<br>hébergement cloud imposé|
|Soluton 100% cloud (SaaS)|Aucune installaton locale, mises<br>à jour automatques|Dépendance totale à la connexion<br>internet pour chaque opératon,<br>directement incompatble avec<br>l'absence de garante de connectvité<br>contnue à la clinique|



Cabinet Massenon & Kowi Conseil — Document confidentiel — Page 20 / 37 

_Cahier des Charges Fonctionnel et Technique – Logiciel de Gestion des Stocks, des Achats, de la_ 

Clinique BAGUIDI – « L'As du Cœur » _Pharmacie et des Ressources Humaines_ 

## **10. Architecture Base de Données & Schéma** 

#### **10.1. Principes de Modélisation** 

- Normalisation des tables transactionnelles jusqu'à la troisième forme normale (3NF), afin d'éviter toute redondance source d'incohérence entre les modules ; 

- Clés primaires techniques de type entier auto-incrément (bigint) pour les performances internes, doublées d'un identifiant public (UUID) pour toute référence exposée à l'extérieur du système (interfaces caisse/assurance) ; 

- Horodatage systématique de chaque enregistrement (date de création, date de dernière modification) et suppression logique (soft delete) plutôt que suppression physique, afin de préserver l'historique à des fins d'audit ; 

- Séparation claire entre les tables de référentiel (produits, fournisseurs, agents, compagnies d'assurance) et les tables de mouvement (entrées, sorties, écritures comptables), conformément aux domaines fonctionnels décrits en section 10.2 ; 

- Doublement, au niveau de la base de données, des principales règles de gestion critiques (contraintes de non-négativité des stocks, unicité des numéros de documents) afin de garantir l'intégrité même en cas de contournement de la couche applicative ; 

- Convention de nommage homogène (snake_case, noms de tables au pluriel) facilitant la lisibilité et la maintenance par toute équipe technique amenée à reprendre le projet. 

#### **10.2. Modèle Conceptuel — Domaines de Données** 

|**Domaine**|**Principales enttés**|
|---|---|
|Référentel|Utlisateurs, Rôles et Permissions, Produits, Fournisseurs, Compagnies d'Assurance,<br>Agents|
|Achats|Bon de Commande, Ligne de Commande, Bon de Livraison, Ligne de Livraison, Facture<br>Fournisseur|
|Stock|Lot, Mouvement de Stock, Fiche de Stock, Seuil d'Alerte, Transfert entre Pharmacies|
|Pharmacie|Stock Gros, Stock Détail, Retour Patent|
|Laboratoire|Réactf, Consommaton de Réactf|
|Ressources Humaines / Paie|Agent, Fiche de Garde, Bulletn de Paie, Avance sur Salaire|
|Caisse / Assurance|Ticket Caisse, Patent Assuré, Prise en Charge|
|Comptabilité, Analytque et<br>Budgétaire (M16)|Plan Comptable, Écriture Comptable, Journal, Immobilisaton, Déclaraton Fiscale,<br>Centre de Coût, Budget Prévisionnel, Suivi Budgétaire|
|Reportng|Inventaire Journalier, Indicateur de Tableau de Bord|



#### **10.3. Détail des Tables Clés** 

Cabinet Massenon & Kowi Conseil — Document confidentiel — Page 21 / 37 

_Cahier des Charges Fonctionnel et Technique – Logiciel de Gestion des Stocks, des Achats, de la_ 

Clinique BAGUIDI – « L'As du Cœur » _Pharmacie et des Ressources Humaines_ 

Le détail ci-dessous présente, à titre indicatif, la structure des tables les plus structurantes du schéma. Il sera complété et finalisé lors de la rédaction des Spécifications Fonctionnelles Détaillées. 

###### **_Table : produits_** 

|**Champ**|**Type**|**Descripton**|
|---|---|---|
|id|bigint, PK|Identfant technique|
|code|varchar(20), unique|Code produit interne|
|designaton|varchar(150)|Désignaton du produit|
|dosage|varchar(50)|Dosage, le cas échéant|
|forme|varchar(30)|Comprimé, injectable, etc.|
|categorie|varchar(30)|Médicament, réactf, fourniture, consommable|
|seuil_alerte|int|Seuil minimum de stock|
|unite|varchar(20)|Unité de mesure|
|created_at / updated_at /<br>deleted_at|tmestamp|Horodatage et suppression logique|



###### **_Table : fournisseurs_** 

|**Champ**|**Type**|**Descripton**|
|---|---|---|
|id|bigint, PK|Identfant technique|
|code_client|varchar(20)|Code d'enregistrement chez le fournisseur|
|raison_sociale|varchar(150)|Nom du fournisseur|
|ifu|varchar(20)|Identfant Fiscal Unique|
|adresse / telephone|varchar|Coordonnées|
|taux_aib|decimal(4,2)|Taux d'AIB applicable (ex. 0.03 ou 0.05)|
|categorie|varchar(30)|Catégorie de produits fournis|



###### **_Tables : bons_commande / lignes_commande_** 

|**Champ**|**Type**|**Descripton**|
|---|---|---|
|id|bigint, PK|Identfant technique|
|numero|varchar(20), unique|Numéro séquentel du bon de commande|
|fournisseur_id|bigint, FK|Référence vers fournisseurs|
|statut|enum|Brouillon / En atente / Approuvé / Rejeté|
|valide_par / valide_le|bigint FK / tmestamp|Traçabilité de la validaton par le Directeur Général|
|lignes_commande.produit_id|bigint, FK|Produit commandé|
|lignes_commande.quantte /<br>prix_unitaire|int / decimal|Quantté demandée et prix unitaire|



Cabinet Massenon & Kowi Conseil — Document confidentiel — Page 22 / 37 

_Cahier des Charges Fonctionnel et Technique – Logiciel de Gestion des Stocks, des Achats, de la_ 

Clinique BAGUIDI – « L'As du Cœur » _Pharmacie et des Ressources Humaines_ 

###### **_Tables : lots / mouvements_stock_** 

|**Champ**|**Type**|**Descripton**|
|---|---|---|
|lots.numero_lot|varchar(30)|Numéro de lot fournisseur|
|lots.produit_id|bigint, FK|Produit concerné|
|lots.date_perempton|date|Date de pérempton|
|lots.quantte_restante|int|Quantté disponible dans le lot|
|mouvements_stock.type|enum|Entrée / Sorte / Transfert / Retour|
|mouvements_stock.pharmacie|enum|Gros / Détail / Laboratoire|
|mouvements_stock.lot_id /<br>quantte / utlisateur_id / date|bigint / int / bigint /<br>tmestamp|Traçabilité complète du mouvement|



**_Tables : agents / fiches_garde / bulletins_paie_** 

|**Champ**|**Type**|**Descripton**|
|---|---|---|
|agents.matricule|varchar(20), unique|Matricule de l'agent|
|agents.nom / prenom /<br>situaton_matrimoniale /<br>categorie|varchar|Identté et statut de l'agent|
|agents.numero_cnss /<br>salaire_base|varchar / decimal|Données de paie|
|fches_garde.agent_id / date /<br>type / heures|bigint / date / enum /<br>decimal|Permanence ou garde, nombre d'heures|
|bulletns_paie.agent_id / mois<br>/ montant_du /<br>avances_deduites / irpp|bigint / date / decimal|Éléments consttutfs de la paie mensuelle|



**_Tables : tickets_caisse / patients_assures_** 

|**Champ**|**Type**|**Descripton**|
|---|---|---|
|tckets_caisse.numero / date / type|varchar / date / enum|Ticket Infrmier ou Ticket Patent|
|tckets_caisse.patent_id / lignes|bigint / json ou table<br>liée|Patent concerné et produits/analyses facturés|
|patents_assures.numero_carte /<br>compagnie_id|varchar / bigint FK|Identfant et compagnie d'assurance|
|patents_assures.taux_prise_en_charge|decimal(4,2)|Taux appliqué (ex. 0.80 pour 80%)|



#### **10.4. Règles d'Intégrité Transversales** 

- Contraintes de clé étrangère (Foreign Key) avec restriction de suppression (ON DELETE RESTRICT) sur toutes les tables de référentiel référencées par des mouvements, afin d'éviter la suppression d'un produit ou d'un fournisseur encore utilisé ; 

Cabinet Massenon & Kowi Conseil — Document confidentiel — Page 23 / 37 

_Cahier des Charges Fonctionnel et Technique – Logiciel de Gestion des Stocks, des Achats, de la_ 

Clinique BAGUIDI – « L'As du Cœur » _Pharmacie et des Ressources Humaines_ 

- Contrainte de vérification (CHECK) interdisant toute quantité de stock négative au niveau de la table des lots ; 

- Contrainte d'unicité sur le couple (type de document, numéro) pour les bons de commande, bons de livraison et factures, garantissant l'absence de doublon ; 

- Déclencheurs applicatifs (equivalents de triggers métier) garantissant l'équilibre systématique des écritures comptables générées automatiquement (débit = crédit) ; 

- Table d'audit générique (journal des événements) enregistrant, pour chaque action sensible, l'utilisateur, l'horodatage, la table concernée et la nature de l'opération, conformément à l'exigence de traçabilité décrite en section 12.4. 

#### **10.5. Diagramme Relationnel — Vue Simplifiée (texte)** 

À défaut de représentation graphique dans le présent document, les relations principales entre entités sont décrites textuellement ci-dessous ; le diagramme entité-association graphique sera produit lors des Spécifications Fonctionnelles Détaillées. 

Fournisseur (1) → (N) Bon de Commande → (N) Ligne de Commande → (1) Produit 

Bon de Commande (1) → (N) Bon de Livraison → (N) Ligne de Livraison → (1) Lot → (1) Produit 

Lot (1) → (N) Mouvement de Stock → (1) Pharmacie (Gros / Détail / Laboratoire) 

Ticket Caisse (1) → (N) Mouvement de Stock (sortie) ; Ticket Caisse (N) → (1) Patient Assuré (optionnel) → (1) Compagnie d'Assurance 

Agent (1) → (N) Fiche de Garde ; Agent (1) → (N) Bulletin de Paie 

Facture Fournisseur (1) → (N) Écriture Comptable → (1) Compte du Plan Comptable (M16) 

Cabinet Massenon & Kowi Conseil — Document confidentiel — Page 24 / 37 

_Cahier des Charges Fonctionnel et Technique – Logiciel de Gestion des Stocks, des Achats, de la_ 

Clinique BAGUIDI – « L'As du Cœur » _Pharmacie et des Ressources Humaines_ 

## **11. Cartographie des Interfaces & Design Système** 

#### **11.1. Séquence de Démarrage (Splash — Welcome — Login)** 

###### **_11.1.1. Splash Screen (3 secondes)_** 

Écran d'ouverture affiché pendant trois secondes au lancement de l'application, sur fond navy (#1F3864) pleine page. Le logo de la Clinique BAGUIDI est centré verticalement et horizontalement, accompagné d'une fine barre de progression de couleur or (#B08D57) en partie basse de l'écran. Le numéro de version de l'application est affiché discrètement en pied d'écran, en gris clair. 

###### **_11.1.2. Welcome Screen_** 

Écran d'accueil présentant le nom complet de la solution (« Logiciel de Gestion – Clinique BAGUIDI »), une accroche institutionnelle courte, et un bouton d'action principal « Se connecter » de couleur or sur fond navy. Un visuel discret évoquant l'univers médical (icone abstraite, sans photographie de personne réelle) peut accompagner la composition, dans le respect de la sobriété institutionnelle recherchée. 

###### **_11.1.3. Login Screen — Double panneau 40/60_** 

Écran de connexion structuré en deux panneaux verticaux : un panneau de gauche occupant 40% de la largeur, de couleur navy, présentant le logo, le nom de la clinique et une phrase de positionnement institutionnel ; un panneau de droite occupant 60% de la largeur, sur fond blanc, contenant le formulaire de connexion (identifiant, mot de passe, case « se souvenir de moi », bouton « Se connecter » en or, lien « Mot de passe oublié » en gris). Ce découpage 40/60 permet d'affirmer l'identité institutionnelle tout en laissant l'espace nécessaire à un formulaire clair et lisible. 

#### **11.2. Shell Applicatif** 

Une fois connecté, l'utilisateur évolue dans un shell applicatif commun à l'ensemble des modules, structuré comme suit : 

- Une barre latérale gauche (sidebar) regroupant les modules par domaine fonctionnel (Achats & Fournisseurs, Stocks & Pharmacie, Laboratoire, Ressources Humaines, Comptabilité, Tableaux de Bord), repérable par icônes et libellés, avec mise en évidence en or du module actif ; 

- Une barre supérieure (topbar) affichant le fil d'Ariane (breadcrumb) de navigation, un accès rapide aux alertes (seuils de stock, péremptions), et le profil de l'utilisateur connecté ; 

- Une zone de contenu principale, occupant l'espace central, présentant selon les cas des tableaux de données, des formulaires de saisie ou des tableaux de bord graphiques ; 

- Un pied de page discret rappelant la version de l'application et un lien vers l'assistance technique. 

#### **11.3. Cartographie Détaillée par Module** 

|**Module**|**Écrans principaux**|
|---|---|
|M1 – Achats & Fournisseurs|Liste des fournisseurs, fche fournisseur, historique des commandes|



Cabinet Massenon & Kowi Conseil — Document confidentiel — Page 25 / 37 

_Cahier des Charges Fonctionnel et Technique – Logiciel de Gestion des Stocks, des Achats, de la_ 

Clinique BAGUIDI – « L'As du Cœur » _Pharmacie et des Ressources Humaines_ 

|**Module**|**Écrans principaux**|
|---|---|
|M2 – Bons de Commande|Liste des bons de commande, formulaire de créaton, écran de validaton DG, aperçu<br>imprimable|
|M3 – Bons de Livraison|Formulaire de récepton, écran de rapprochement commande/livraison, alerte d'écart|
|M4/M5 – Stocks Pharmacie|Tableau de bord des stocks, fche produit, écran de transfert Gros → Détail, écran de<br>retour patent|
|M6 – Laboratoire|Fiche de stock réactf, écran de sorte par analyse|
|M7 – Fournitures|Liste des fournitures, formulaire de demande interne, écran de validaton|
|M8 – Fiches de Stock/Sorte|Écran de consultaton et d'export des fches|
|M9 – Alertes & Péremptons|Tableau de bord des alertes, paramétrage des seuils|
|M10 – Inventaires|Écran de clôture quotdienne, écran d'inventaire physique et des écarts|
|M11 – Factures & AIB|Liste des factures, formulaire de saisie, annexe AIB générée|
|M12/M13 – Caisse &<br>Assurances|Écran de rapprochement tcket/stock, écran de vérifcaton de carte d'assurance,<br>facture mensuelle assureur|
|M14 – RH & Paie|Fiche agent, saisie des heures de garde, génératon des bulletns de paie|
|M15 – Tableaux de Bord|Tableaux de bord graphiques par domaine, centre d'impression des états|
|M16 – Comptabilité,<br>Analytque et Budgétaire|Plan comptable, journaux, grand livre, bilan, compte de résultat, immobilisatons, suivi<br>budgétaire par centre de coût, rapport analytque|



#### **11.4. Design System — Charte Graphique** 

|**Élément**|**Spécifcaton**|
|---|---|
|Couleur primaire|Navy #1F3864 — en-têtes, sidebar, éléments structurants|
|Couleur d'accent|Or #B08D57 — actons principales, mise en valeur, indicateurs positfs|
|Couleur de texte|Gris #333333 — texte courant, garantssant un contraste de lecture optmal|
|Couleurs d'état|Vert pour un statut validé/en stock sufsant ; orange pour une alerte de seuil ; rouge<br>pour une rupture ou une pérempton imminente|
|Typographie de ttre|Police avec empatement (de type Cambria), réservée aux ttres et sous-ttres|
|Typographie courante|Police sans empatement (de type Calibri), pour l'ensemble des textes courants et<br>formulaires|
|Composants|Boutons arrondis avec état actf/inactf, badges de statut colorés, tableaux à lignes<br>alternées (zebra), cartes de synthèse pour les tableaux de bord|
|Grille et espacement|Grille responsive à 12 colonnes, espacements multples de 8 pixels, points de rupture<br>adaptés aux postes de bureau et aux tabletes utlisées au comptoir de la pharmacie|
|Icônes|Jeu d'icônes vectorielles homogène (type outline), cohérent avec la sobriété<br>insttutonnelle recherchée|



Cabinet Massenon & Kowi Conseil — Document confidentiel — Page 26 / 37 

_Cahier des Charges Fonctionnel et Technique – Logiciel de Gestion des Stocks, des Achats, de la_ 

Clinique BAGUIDI – « L'As du Cœur » _Pharmacie et des Ressources Humaines_ 

## **12. Architecture de Sécurité** 

#### **12.1. Matrice des Rôles (RBAC)** 

Le système repose sur un modèle de contrôle d'accès basé sur les rôles (Role-Based Access Control). Chaque utilisateur se voit attribuer un ou plusieurs rôles, chaque rôle disposant d'un ensemble de permissions granulaires (consultation, création, modification, validation, suppression) par module. 

|**Rôle**|**Droits par défaut**|
|---|---|
|Directeur Général|Validaton des bons de commande ; consultaton complète de tous les modules, y<br>compris comptabilité et paie ; aucun droit de suppression de données|
|Comptable Achats/Stock|Créaton et geston des modules M1 à M11 ; pas d'accès aux données de paie<br>individuelles|
|Comptable Caisse/Facturaton|Geston du module M12/M13 et de l'inventaire M10 ; consultaton des stocks|
|Comptable Comptabilité<br>générale|Geston exclusive du module M16 ; consultaton des modules amont (achats, caisse,<br>paie) sans droit de modifcaton|
|Pharmacie Gros / Détail|Geston des modules M4/M5 relatfs à leur périmètre ; pas d'accès aux modules RH<br>et comptabilité|
|Laboratoire|Geston du module M6 uniquement|
|Responsable RH|Geston exclusive du module M14 ; aucun accès aux modules de stock ou de<br>comptabilité|
|Administrateur système|Paramétrage technique, geston des comptes et des rôles ; accès aux journaux<br>d'audit ; pas d'accès fonctonnel direct aux données méter sans justfcaton|



#### **12.2. Authentification & Sessions** 

- Authentification individuelle par identifiant et mot de passe, avec politique de complexité minimale et renouvellement périodique imposé ; 

- Verrouillage temporaire du compte après un nombre paramétrable de tentatives infructueuses ; 

- Authentification à double facteur (2FA) recommandée pour les comptes à privilèges élevés (Direction Générale, Administrateur système, Comptabilité générale) ; 

- Expiration automatique de session après une durée d'inactivité paramétrable, avec reconnexion obligatoire ; 

- Journalisation de chaque connexion et déconnexion, avec horodatage et poste d'origine. 

#### **12.3. Protection des Données & Conformité** 

- Chiffrement des données sensibles au repos (base de données) et en transit (protocole HTTPS/TLS) ; 

- Application du principe de minimisation : chaque profil n'accède qu'aux données strictement nécessaires à l'exercice de sa fonction ; 

Cabinet Massenon & Kowi Conseil — Document confidentiel — Page 27 / 37 

_Cahier des Charges Fonctionnel et Technique – Logiciel de Gestion des Stocks, des Achats, de la_ 

Clinique BAGUIDI – « L'As du Cœur » _Pharmacie et des Ressources Humaines_ 

- Conformité aux exigences de l'Autorité de Protection des Données à caractère Personnel du Bénin (APDP) en matière de traitement des données de santé et des données à caractère personnel des patients et des employés ; 

- Anonymisation ou pseudonymisation des données patient dans tout environnement de test ou de démonstration. 

#### **12.4. Audit & Traçabilité** 

- Journalisation exhaustive de toute opération de création, modification ou suppression sur les données critiques (stock, factures, paie, comptabilité), incluant l'utilisateur, la date et la nature de l'action ; 

- Conservation de la piste d'audit pendant une durée minimale alignée sur les obligations comptables et fiscales en vigueur au Bénin ; 

- Capacité d'édition, à la demande de la Direction Générale, d'un rapport d'audit sur une période et un périmètre donnés ; 

- Immutabilité des écritures comptables validées, toute correction devant transiter par une écriture de contre-passation tracée. 

#### **12.5. Sécurité applicative transverse** 

- Protection contre les injections SQL par l'usage systématique de l'ORM et de requêtes préparées ; 

- Protection contre les failles de type CSRF (Cross-Site Request Forgery) et XSS (Cross-Site Scripting) au niveau du framework applicatif ; 

- Limitation du taux de requêtes (rate limiting) sur les points d'accès sensibles (connexion, API d'intégration caisse/assurance) ; 

- Sauvegardes automatiques chiffrées et testées périodiquement par une procédure de restauration ; 

- Plan de reprise d'activité (PRA) documentant les modalités de restauration du service en cas d'incident majeur (panne serveur, sinistre) ; 

- Application régulière des correctifs de sécurité du système d'exploitation, du serveur web et des dépendances applicatives. 

Cabinet Massenon & Kowi Conseil — Document confidentiel — Page 28 / 37 

_Cahier des Charges Fonctionnel et Technique – Logiciel de Gestion des Stocks, des Achats, de la_ 

Clinique BAGUIDI – « L'As du Cœur » _Pharmacie et des Ressources Humaines_ 

## **13. Exigences non fonctionnelles** 

#### **13.1. Performance et disponibilité** 

- Temps de réponse inférieur à trois secondes pour les opérations courantes sur le réseau local ; 

- Disponibilité du système pendant les heures d'ouverture, y compris lors de l'inventaire matinal, et fonctionnement compatible avec une activité continue (gardes de nuit) ; 

- Indépendance totale du fonctionnement courant vis-à-vis de la connexion internet : toute coupure internet ne doit avoir aucun impact sur la disponibilité du logiciel sur le réseau local de la clinique (cf. section 9.1). 

#### **13.2. Sauvegarde et continuité** 

- Sauvegarde automatique quotidienne locale (poste hôte de données vers un support externe), avec conservation d'un historique d'au moins douze mois ; 

- Sauvegarde complémentaire chiffrée vers un espace cloud lorsque la connexion internet est disponible, à titre de sécurisation supplémentaire et non comme condition de fonctionnement ; 

- Procédure de restauration testée et documentée (cf. section 12.5). 

#### **13.3. Ergonomie** 

- Interface simple et intuitive, accessible à des utilisateurs non spécialistes en informatique ; 

- Interface entièrement en langue française, conforme au design system décrit en section 11.4. 

#### **13.4. Interopérabilité** 

- Interface technique documentée avec le logiciel de caisse existant, fonctionnant sur le même réseau local ; 

- Interface technique documentée avec le logiciel de gestion des assurances existant ; 

- Capacité d'export/import de données aux formats standards (CSV, Excel, PDF), à tous les niveaux du système, dans le respect des en-têtes décrits en section 8.13.1. 

Cabinet Massenon & Kowi Conseil — Document confidentiel — Page 29 / 37 

_Cahier des Charges Fonctionnel et Technique – Logiciel de Gestion des Stocks, des Achats, de la_ 

Clinique BAGUIDI – « L'As du Cœur » _Pharmacie et des Ressources Humaines_ 

## **14. Profils utilisateurs et droits d'accès — Synthèse** 

La matrice ci-dessous complète, à un niveau synthétique, la matrice RBAC détaillée en section 12.1. 

|**Profl**|**Achats / Stock**|**Pharmacie**|**RH / Paie**|**Comptabilité**|**Tableaux de bord**|
|---|---|---|---|---|---|
|Directeur Général|Validaton|Consultaton|Consultaton|Consultaton|Consultaton<br>complète|
|Comptable Achats/Stock|Geston|Consultaton|–|–|Restreinte|
|Comptable Caisse|Consultaton|Consultaton|–|–|Inventaire /<br>Recetes|
|Comptable Générale<br>(M16)|Consultaton|–|Consultaton|Geston|Financière|
|Pharmacie Gros/Détail|Consultaton|Geston|–|–|–|
|Responsable RH|–|–|Geston|–|RH|
|Administrateur|Paramétrage|Paramétrage|Paramétrage|Paramétrage|Paramétrage|



Cabinet Massenon & Kowi Conseil — Document confidentiel — Page 30 / 37 

_Cahier des Charges Fonctionnel et Technique – Logiciel de Gestion des Stocks, des Achats, de la_ 

Clinique BAGUIDI – « L'As du Cœur » _Pharmacie et des Ressources Humaines_ 

## **15. Cas d'utilisation principaux (Use Cases)** 

#### **UC-01 – Émettre et faire valider un bon de commande** 

Acteur principal : Comptable Achats. Le comptable sélectionne un fournisseur, saisit les produits et quantités, puis soumet le bon à l'approbation du Directeur Général, qui approuve ou rejette la demande. 

#### **UC-02 – Réceptionner une livraison** 

Acteur principal : Comptable Achats. À la réception, le comptable saisit les quantités, lots et péremptions ; le système compare aux quantités commandées et signale les écarts avant validation de l'entrée en stock. 

#### **UC-03 – Délivrer un produit sur ticket patient** 

Acteur principal : Pharmacie Détail. Sur présentation du ticket caisse, l'agent sélectionne les produits ; le système vérifie la disponibilité, applique la règle FEFO et met à jour le stock. 

#### **UC-04 – Traiter un retour patient** 

Acteur principal : Caisse / Pharmacie Détail. En cas de non-conformité, l'agent enregistre le retour avec observation obligatoire ; le système régularise le stock et la facturation. 

#### **UC-05 – Clôturer l'inventaire quotidien** 

Acteur principal : Caissière. Le système présente l'état consolidé des recettes et dépenses de la veille ; la caissière vérifie et valide, verrouillant les données de la journée. 

#### **UC-06 – Générer la paie mensuelle d'un médecin de garde** 

Acteur principal : Responsable RH. À partir des heures déclarées, le système calcule automatiquement la rémunération due et génère la fiche de paie. 

#### **UC-07 – Facturer mensuellement une compagnie d'assurance** 

Acteur principal : Comptable Caisse. Le système consolide les prestations délivrées aux patients assurés sur le mois et génère la facture normalisée destinée à l'assureur. 

#### **UC-08 – Clôturer la comptabilité mensuelle** 

Acteur principal : Comptable Comptabilité Générale. Le système consolide les écritures générées automatiquement par les modules Achats, Stock, Caisse et Paie, permet leur vérification, et génère la balance et les états financiers du mois. 

Cabinet Massenon & Kowi Conseil — Document confidentiel — Page 31 / 37 

_Cahier des Charges Fonctionnel et Technique – Logiciel de Gestion des Stocks, des Achats, de la_ 

Clinique BAGUIDI – « L'As du Cœur » _Pharmacie et des Ressources Humaines_ 

## **16. Scénarios métiers illustratifs** 

##### **Scénario A – Rupture de stock imminente** 

Le stock de Paracetamol 1g solution injectable atteint le seuil d'alerte paramétré. Le système génère une alerte sur le tableau de bord du comptable Achats, qui peut initier directement un bon de commande pré-rempli. 

##### **Scénario B – Produit proche de la péremption** 

Un lot de Glucose 5% arrive à 90 jours de sa péremption. Le système le signale dans la liste de vigilance et propose sa sortie prioritaire (FEFO). 

##### **Scénario C – Patient assuré avec taux de prise en charge de 80%** 

Un patient couvert par une compagnie d'assurance partenaire se présente à la caisse. La validité de sa carte est vérifiée via l'interface d'assurance, un taux de 80% est appliqué à la charge de l'assureur, et la facture mensuelle correspondante est automatiquement alimentée. 

##### **Scénario D – Écart constaté lors de l'inventaire** 

Un écart est constaté entre le stock théorique et le comptage physique de la Pharmacie de Détail. Le système enregistre l'écart, exige une justification, et génère une écriture de régularisation comptable automatique. 

Cabinet Massenon & Kowi Conseil — Document confidentiel — Page 32 / 37 

_Cahier des Charges Fonctionnel et Technique – Logiciel de Gestion des Stocks, des Achats, de la_ 

Clinique BAGUIDI – « L'As du Cœur » _Pharmacie et des Ressources Humaines_ 

## **17. Interfaces avec les systèmes existants** 

#### **17.1. Interface avec le logiciel de caisse** 

La nature exacte de l'interface (API temps réel, export/import périodique, ou base de données partagée) sera déterminée lors d'un cadrage technique dédié avec l'éditeur du logiciel de caisse actuellement utilisé par la clinique. 

#### **17.2. Interface avec le logiciel de gestion des assurances** 

L'interface devra permettre la vérification en temps réel de la validité d'une carte d'assuré et la récupération du taux de prise en charge applicable, ainsi que la transmission des données nécessaires à l'édition de la facture mensuelle par compagnie. 

Cabinet Massenon & Kowi Conseil — Document confidentiel — Page 33 / 37 

_Cahier des Charges Fonctionnel et Technique – Logiciel de Gestion des Stocks, des Achats, de la_ 

Clinique BAGUIDI – « L'As du Cœur » _Pharmacie et des Ressources Humaines_ 

## **18. États et rapports à produire** 

|**État / Rapport**|**Fréquence**|**Destnataire**|
|---|---|---|
|Bon de commande|À la demande|Fournisseur / Directon|
|Fiche de stock par produit|Temps réel|Pharmacie / Comptabilité|
|Liste des alertes de stock et de pérempton|Quotdienne|Comptabilité / Directon|
|État d'inventaire quotdien|Quotdienne|Caisse / Comptabilité / Directon|
|Annexe AIB mensuelle|Mensuelle|Comptabilité / Administraton fscale|
|Facture mensuelle par compagnie<br>d'assurance|Mensuelle|Compagnies d'assurance partenaires|
|État récapitulatf de la paie et des gardes|Mensuelle|Directon / RH|
|Journaux comptables, Grand Livre, Balance|Mensuelle|Comptabilité / Directon|
|Bilan et Compte de Résultat|Annuelle (et à la demande)|Directon / Administraton fscale|
|Tableau de bord des achats et dépenses|Mensuelle|Directon|



Cabinet Massenon & Kowi Conseil — Document confidentiel — Page 34 / 37 

_Cahier des Charges Fonctionnel et Technique – Logiciel de Gestion des Stocks, des Achats, de la_ 

Clinique BAGUIDI – « L'As du Cœur » _Pharmacie et des Ressources Humaines_ 

## **19. Critères de recette et d'acceptation** 

22. Chaque module fonctionnel du périmètre (M1 à M16) doit être opérationnel et testé en conditions réelles avant mise en production ; 

23. Le workflow de validation des bons de commande par le Directeur Général doit fonctionner sans exception, avec traçabilité complète ; 

24. Les alertes de seuil de stock et de péremption doivent se déclencher de manière fiable, testées sur un jeu de données représentatif ; 

25. La clôture de l'inventaire quotidien doit produire un résultat cohérent avec un contrôle manuel effectué en parallèle pendant la période de recette (durée minimale de deux semaines) ; 

26. Le calcul automatique de l'AIB et des écritures comptables générées par le module M16 doit être validé par le service comptable sur un échantillon de pièces réelles ; 

27. Le calcul automatique de la paie des médecins de garde doit être validé par comparaison avec au moins un mois de paie calculé manuellement ; 

28. L'interface avec le logiciel de caisse doit être testée sur un périmètre pilote avant généralisation ; 

29. La matrice RBAC doit être validée profil par profil, avec confirmation qu'aucun utilisateur n'accède à des données hors de son périmètre autorisé ; 

30. Aucune anomalie bloquante ne doit subsister sur les fonctionnalités classées « Must have » à l'issue de la phase de recette. 

Cabinet Massenon & Kowi Conseil — Document confidentiel — Page 35 / 37 

_Cahier des Charges Fonctionnel et Technique – Logiciel de Gestion des Stocks, des Achats, de la_ 

Clinique BAGUIDI – « L'As du Cœur » _Pharmacie et des Ressources Humaines_ 

## **20. Hypothèses, contraintes et exclusions** 

#### **20.1. Hypothèses** 

- La clinique met à disposition les données historiques nécessaires à la reprise (produits, fournisseurs, stocks initiaux, personnel, plan comptable actuel) dans un format exploitable ; 

- Les éditeurs des logiciels de caisse et d'assurance existants acceptent de participer aux ateliers techniques nécessaires à la définition des interfaces ; 

- Un référent métier est désigné par la clinique pour chaque module pendant toute la durée du projet ; 

- Un poste de travail existant, suffisamment performant, est mis à disposition par la clinique pour héberger la base de données partagée en réseau local ; aucun serveur dédié ni hébergement cloud n'est requis pour le fonctionnement courant ; 

#### **20.2. Contraintes** 

- Continuité de service exigée pendant toute la période de déploiement, la clinique fonctionnant 24 heures sur 24 ; 

- Charge de travail administrative limitée, imposant une solution simple d'utilisation et un accompagnement au changement adapté. 

#### **20.3. Exclusions expressément confirmées** 

- Le présent cahier des charges ne couvre pas le dossier patient informatisé, la consultation, l'hospitalisation, le portail patient, l'application mobile ni la Business Intelligence avancée ; 

- Le présent cahier des charges ne prévoit pas le remplacement du logiciel de caisse ni du logiciel d'assurance, mais uniquement leur interfaçage ; 

- La gestion des vaccins est exclue du périmètre ; 

- L'impression d'étiquettes produits n'est pas requise dans la première version de la solution. 

Cabinet Massenon & Kowi Conseil — Document confidentiel — Page 36 / 37 

Clinique BAGUIDI – « L'As du Cœur » _Cahier des Charges Fonctionnel et Technique – Logiciel de Gestion des Stocks, des Achats, de la Pharmacie et des Ressources Humaines_ 

## **21. Annexes** 

#### **Annexe 1 – Documents sources ayant servi à l'élaboration du présent cahier des charges** 

- Rapport de Cadrage et d'Analyse des Besoins – Réf. BAG-RC-2026-01 du 13 juillet 2026 ; 

- Classeur Excel « Journal de Janvier 2026 » (Achats, Ventes, Salaires, Caisse-Dépenses, Opérations Diverses, Prestations, Point AIB, Immobilisations) ; 

- Bon de livraison SoBAPS n° 26BLP0704 du 17 juin 2026 ; 

- Fiche de suivi des heures de garde et de permanence médicale – juin 2026 ; 

- Notes manuscrites de cadrage rédigées en séance par les consultants. 

**Annexe 2 – Tableau de correspondance périmètre / journaux Excel actuels** 

|**Journal Excel actuel**|**Module cible correspondant**|
|---|---|
|ACH – Journal Achats|M1, M2, M3, M11, M16|
|VEN – Journal Ventes|M12, M13, M16|
|SAL – Journal Salaires|M14, M16|
|Caisse-Dépenses|M10, M12, M16|
|OD – Opératons Diverses|M11, M16|
|PRE – Prestatons|M14|
|Point AIB|M11, M16|
|IMO – Immobilisatons|M16|



Le présent Cahier des Charges Fonctionnel et Technique sera complété par les Spécifications Fonctionnelles Détaillées, le détail des maquettes d'écran et la proposition financière, après validation formelle du présent document par la Direction Générale de la Clinique BAGUIDI. 

Cabinet Massenon & Kowi Conseil — Document confidentiel — Page 37 / 37 

