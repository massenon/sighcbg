import 'package:sigh_domaine/sigh_domaine.dart';

import 'magasin.dart';

/// Les GESTES RÉSERVÉS lus des fiches `rbac` du magasin, À CHAQUE appel (jamais mis en cache) : une décision de la clinique vaut à la lecture suivante. Pour les objets de
/// données qui n'ont que le magasin (planning, espace « Mes », verrou de secours, copie hors site, identifiants). Les gestes transverses (`module: '*'`) ne lisent pas
/// l'activité des écrans ; un écran qui a son contexte passe par `gestesEcran` (matrice en force, rôle archivé compris). Aucun nom de rôle ici.
DroitsGestes gestesDuMagasin(Magasin m) => DroitsGestes(fiches: m.collection('rbac').actives);
