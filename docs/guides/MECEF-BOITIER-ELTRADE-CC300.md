# Boîtier MECeF ELTRADE CC300 : ce qu'il faut obtenir du fournisseur

La Direction de Baguidi a indiqué le 16/11/2026 que son boîtier MECeF est un **ELTRADE CC300** (`docs/prd/DECISIONS-16-11-ASSISTANT-AI-AK.md`). Le dépôt ne contient rien d'autre sur ce boîtier : ni manuel, ni fiche technique, ni protocole, ni pilote, ni simulateur.

## Ce que fait le logiciel aujourd'hui

- Le **modèle** est un réglage de clinique : la clé `mecef.modeleBoitier` (famille `mecef`) du registre des paramètres. Il est semé à « ELTRADE CC300 », il est versionné par date, et seule la mère l'écrit (famille R, jamais envoyé vers un téléphone). Le droit « configuration MECeF » (`reglage_mecef`) permet de le changer depuis « Configuration fiscale » ou depuis les Paramètres.
- Le modèle est affiché sur l'écran de configuration MECeF. Il est porté sur la pièce (`modeleBoitierMecef`) et au journal MECeF, aux mêmes endroits que le mode (`modeMecef`), à chaque tentative faite en mode « Boîtier physique ».
- **L'adaptateur reste non configuré.** L'écran le dit : « adaptateur ELTRADE CC300 : intégration à fournir par l'éditeur du boîtier ». Une vente est encaissée, puis reste en attente de certification avec le refus `MECEF_NON_CONFIGURE`. Le poste ne fabrique aucun numéro fiscal et n'envoie aucune requête réseau.
- Le point d'extension existe déjà : l'interface `AdaptateurMecef` (`packages/domaine/lib/src/mecef/mode.dart`). L'adaptateur réel du boîtier l'implémentera (lot M3).

## Ce qu'il faut obtenir du fournisseur (ou de l'éditeur) du boîtier

Rien de ce qui suit n'est affirmé ici. Ce sont les questions à poser, reprises de l'ADR-0003 (« Le boîtier MECeF : ce qu'il change ») et appliquées au CC300.

1. **Le manuel d'intégration du CC300** : la documentation destinée aux éditeurs de logiciels de caisse, et non le manuel de l'utilisateur final.
2. **L'interface physique et le pilote** : série, USB (avec ou sans port série virtuel) ou réseau ; paramètres de liaison ; pilote à installer sous Windows.
3. **Le protocole** : format des trames ou des commandes ; jeu de commandes pour ouvrir une facture, y ajouter une ligne, la totaliser, la clôturer, émettre un avoir et réimprimer un duplicata ; codes de retour et codes d'erreur.
4. **Un kit de développement et un simulateur** (logiciel ou boîtier de test), pour éprouver l'adaptateur sans émettre de vraies factures normalisées.
5. **Le certificat, ou l'agrément DGI, du modèle et de son intégration** : la liste des mentions obligatoires sur la facture normalisée (code MECeF, compteurs, signature, QR code éventuel) et leur format d'impression.
6. **Le comportement hors ligne** : capacité de la mémoire (nombre de factures, nombre de jours), qui transmet à la DGI, quand, et ce qui se passe quand la mémoire est pleine.
7. **Les incidents** : coupure de courant ou de liaison pendant une émission, panne de papier, reprise sans doublon fiscal, réglage de l'horloge.
8. **L'organisation** : nombre de boîtiers prévus et postes de caisse rattachés à chacun ; contact technique et conditions de support.

## Ce qui ne change pas tant que ces pièces manquent

- Aucun numéro n'est simulé comme fiscal. La retransmission d'une vente en attente ne consomme pas l'unique essai du caissier.
- Le mode « e-MECeF » reste « non configuré : dossier d'interface DGI requis ».
- Brancher l'adaptateur réel rendra l'émission asynchrone : `normaliserVente` devra le devenir (lot M3, déjà signalé dans le code).
