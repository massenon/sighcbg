# ADR-0007 : Le relais voit désormais des agrégats non nominatifs, publiés sur interrupteur ouvert, jamais de détail

| | |
|---|---|
| **Statut** | **accepté le 09/11/2026** par la Direction. Il **précise** ADR-0005 (relais opaque) : le relais reste opaque pour tout dossier ; il admet en plus un instantané d'agrégats non nominatifs. |
| **Date** | 09/11/2026 |
| **Décideurs** | Direction, ingénierie |
| **Lié à** | ADR-0005 (relais opaque), ADR-0006 (échanges entre pairs), `docs/prd/DECISIONS-2026-11-09.md` (règle générale : tout paramétrable l'est en base, avec un défaut) |

## Contexte

Le relais en ligne (Laravel, hébergement mutualisé) ne lit aucun dossier : il stocke des enveloppes chiffrées de bout en bout dont il n'a pas la clé. Il recevait déjà de la mère, en clair, trois compteurs de supervision (`patients_actifs`, `seq_max`, `retard_replication`) pour répondre à « la mère est-elle vivante, à jour, sauvegardée ? ».

La Direction veut, depuis le web, un **tableau de bord en lecture seule** de l'activité de la clinique : combien de patients, de consultations, de factures, quel montant facturé et encaissé, quel stock sous seuil, quelles échéances fiscales en retard. Elle a tranché le 09/11/2026 : **un panneau d'indicateurs agrégés non nominatifs publiés par le poste mère. Aucun paramètre modifiable depuis le web, aucune application métier web, aucun dossier lisible.**

## Décision

1. **Le relais reçoit un instantané d'agrégats non nominatifs**, publié par le poste mère à `POST /mere/indicateurs-clinique`. Il est composé de NOMBRES (comptes, montants en FCFA entiers, pourcentage, horodatages) et de quatre formes imposées seulement : un code d'obligation fiscale (`[A-Z0-9_-]{1,24}`), une date `AAAA-MM-JJ`, un numéro de version, l'identifiant technique d'un appareil. Jamais un nom, un code patient, un téléphone, une adresse, un motif, un diagnostic, un nom de fournisseur ou d'agent. Une mesure que la mère ne peut pas calculer vaut `null` (« non disponible »), jamais zéro.
2. **Le schéma est fermé et contrôlé aux deux bouts.** Le calculateur est une fonction pure du domaine (`packages/domaine/lib/src/mere/indicateurs_clinique.dart`) qui ne lit pas les champs nominatifs. La mère valide son instantané avant l'envoi ; le relais le revalide (`App\Relais\IndicateursClinique`) et refuse tout champ en trop, toute chaîne libre, tout type inattendu, tout corps trop volumineux. Les messages de refus nomment des chemins, jamais une valeur reçue.
3. **L'instantané est signé.** L'en-tête `x-mere` authentifie déjà la mère ; s'y ajoute `x-signature: sha256=<HMAC-SHA256 du corps exact, clé = secret de la mère>`, qui protège le corps de toute altération en route. Un instantané rejoué ou antérieur au dernier reçu est refusé.
4. **Un interrupteur, FERMÉ par défaut.** « Publier les indicateurs au relais » vit en base de la mère avec son défaut, comme l'intervalle de publication (défaut 15 minutes) et le seuil de péremption (défaut 90 jours). Tant que la Direction ne l'a pas ouvert, rien ne part, pas même une tentative. Les Paramètres du poste affichent l'interrupteur, l'intervalle et le **contenu exact du dernier instantané publié** : la Direction voit ce qui part.
5. **Côté relais : une table, une page, aucune écriture.** Table `indicateurs_clinique` (les N derniers instantanés, N réglable par `RELAIS_INDICATEURS_CLINIQUE_MAX`, 500 par défaut). Page « Tableau de bord de la clinique » dans le panneau superadmin : cartes, variation contre l'instantané précédent, fraîcheur avec alerte, courbe d'évolution, et une note permanente qui dit ce que le relais voit et ne voit pas. La page n'expose aucune route ni action d'écriture.

## Ce qui reste opaque (inchangé)

- **Tout dossier** : patients, consultations, ordonnances, résultats, factures détaillées, écritures, bulletins. Ils ne quittent la mère que dans des **enveloppes chiffrées de bout en bout** (AES-256-GCM, clé de clinique que seuls les appareils de la clinique détiennent). Le relais ne détient aucune clé et le contrôleur n'importe aucune fonction de chiffrement.
- **Tout nominatif** : aucun nom, code patient, téléphone, adresse, motif, diagnostic, fournisseur ou agent n'est dans l'instantané ni en base.
- **Toute règle métier** : le relais n'interprète pas les agrégats, il les affiche. Les seuils (stock, péremption, échéances) sont décidés par la mère avec les paramètres de la clinique.
- **Aucune écriture depuis le web** : aucun paramètre de la clinique ne se règle depuis le relais.

## Options écartées

- **Rester sur les trois compteurs historiques** : ne répond pas à la demande de la Direction.
- **Publier des listes (patients du jour, factures impayées nominatives)** : franchirait la limite posée ; un agrégat ne permet pas de remonter à une personne.
- **Un panneau web métier (lecture des dossiers chiffrés côté relais)** : écarté par la Direction (aucune application métier web, aucun dossier lisible).
- **Publier sans interrupteur** : un envoi en clair hors du poste est un acte que la Direction doit ouvrir en connaissance de cause.

## Conséquences

- **Un nouveau flux en clair** quitte la mère : il est borné par un schéma fermé, une signature, un interrupteur fermé par défaut et un aperçu exact aux Paramètres.
- **Deux exemplaires du schéma** (Dart et PHP) : un test du domaine lit le fichier PHP et échoue si un champ dérive ; un exemple JSON partagé (`packages/schema/indicateurs-clinique.exemple.json`) est validé par le calculateur Dart et par le validateur PHP.
- **Risque résiduel** : des agrégats sur de petits effectifs peuvent être indiscrets (un « 1 » sur un compteur rare) ; l'interrupteur et l'aperçu permettent à la Direction de juger. Le montant de stock, de péremption et d'échéance n'est pas un secret médical.
- **Non vérifié ici** : comportement sur l'hébergement cPanel réel et sur plusieurs machines ; PostgreSQL de production (les tests PHP tournent sur SQLite en mémoire).
