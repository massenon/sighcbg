# Outil des spécimens d'impression

Produit le dossier `presentation/` (à la racine du dépôt) : un PDF de chaque document imprimable de chaque module, à l'identité de la clinique. **Ne tourne jamais dans la suite normale** :
`test/specimens_ignores_test.dart` vérifie que chaque cas porte `skip: !actif`.

```bash
# depuis apps/poste
rm -rf ../../presentation
SIGH_SPECIMENS=1 SIGH_SPECIMENS_SORTIE=../../presentation flutter test tool/specimens/generer_specimens_test.dart
python3 tool/specimens/finaliser.py ../../presentation     # tampon SPÉCIMEN, INDEX.md, README.md
python3 tool/specimens/controler.py ../../presentation     # identité (aucune trace de l'autre clinique), PDF lisibles
```

Variables : `SIGH_SPECIMENS=1` (obligatoire), `SIGH_SPECIMENS_SORTIE` (défaut `../../presentation`), `SIGH_SPECIMENS_ECRANS` (préfixes d'écrans à rejouer, `-` = aucun),
`SIGH_SPECIMENS_RECETTES` (préfixes d'identifiants de pièces par fabrique), `SIGH_BAVARD=1` (trace chaque clic de l'explorateur). Un rejeu partiel **fusionne** avec le dossier existant.

## Deux voies, qui se complètent

1. **L'explorateur** (`explorateur.dart`) ouvre chaque écran du manifeste (spécialités comprises, tableaux de bord exceptés des liens) sous un rôle qui y a droit — le poste habituel du module
   d'abord (`noms.dart`, `rolesParModule`) — sur le **jeu livré** (`assets/donnees/jeu`), puis tape les commandes d'édition (vue, lignes ouvertes, tiroirs, onglets, commandes d'icône de chaque ligne),
   clique « Enregistrer en PDF » dans l'aperçu et **capture le PDF par le crochet `ImpressionPoste.enregistrer`**. Rien n'est écrit sur le disque par l'application.
2. **`directs.dart`** produit ce que le balayage n'atteint pas : *recettes* (la fabrique d'impression publique appelée dans le contexte réel d'un écran, avec une fiche du jeu), *alimentations* (un
   registre VIDE au jeu livré reçoit une fiche d'exemple dans un magasin éphémère, puis l'écran est exploré comme les autres), *gestes* (choisir la compagnie avant d'éditer un relevé) et deux
   enregistrements par le **moteur de l'écran** (visite de médecine du travail et sa fiche d'aptitude, consultation de spécialité). Ce qui est bâti pour le spécimen est dit au README du dossier.

`noms.dart` écrit `presentation/<module>/<document>.pdf` : **un spécimen par document** (une même pièce vue depuis un tableau de bord et depuis son écran garde celle de l'écran du module ; les titres qui
portent une donnée — journal, mois — sont ramenés au titre du gabarit ; les « Sélection — … » forment un gabarit unique dans `transverse/`).

## Pièges appris

- **`Magasin.depuisDossier(collectionsDuJeu)` lit la copie de test des bancs de parité** (`test/fixtures/jeu_reference`), pas le jeu livré : `magasinLivre()` passe `assets/donnees/jeu`.
- **Les messages (« PDF enregistré ») recouvrent les commandes de ligne** en haut à droite : l'explorateur les retire (`ToastsSigh.viderPourTests`) après chaque geste.
- **Un tiroir glisse depuis la droite** : tant qu'il n'est pas en place ses boutons sont hors écran ; l'explorateur laisse quatre images avant de chercher dedans. Une modale ou un tiroir ouvert **ne laisse compter
  que ses propres commandes** (celles de la page sont recouvertes par le voile).
- **Un bouton peut être un raccourci de navigation** (« Relevé & facture mensuelle ») : les libellés du ruban sont exclus, et un changement d'écran inattendu rouvre l'écran d'origine.
- **Un état de plus d'une page échouait** : le gabarit PDF plaçait le tableau dans une `Column`, que `MultiPage` ne sait pas couper (voir le commit « fix(impression) »). Corrigé dans `lib/impression/pdf.dart`.
- Les erreurs **asynchrones** de fabrication d'un PDF sont recueillies (`runZonedGuarded`) et notées dans `couverture.json`, jamais jetées au banc.
- Le tampon « SPÉCIMEN » est posé par `tamponner.py` (PyMuPDF), **après** l'écriture : le gabarit d'impression n'est pas touché. Un PDF déjà tamponné n'est pas retamponné.
