import 'package:sigh_domaine/sigh_domaine.dart' as d;

import '../core/service_parametres.dart';
import 'magasin.dart';

/// Le MODE de certification MECeF en vigueur à [maintenant] (lot L3, décision de la Direction du 09/11/2026) : le paramètre `mecef.mode` du registre du lot L0,
/// LU en base (défaut `boitier`, versionné par date, synchronisé par le journal), jamais une constante. Une valeur inconnue retombe sur le défaut.
///
/// Le mode ne s'inscrit pas dans `usagesParametres` : il ne fixe aucun contenu de la pièce (la pièce porte le mode sous lequel la tentative a eu lieu,
/// `modeMecef`), et l'inscrire interdirait de le rebasculer le jour même.
String modeMecefDuPoste(Magasin m, DateTime maintenant) {
  final service = serviceParametres(m, auteur: () => m.utilisateur, horloge: () => maintenant);
  return d.mecefModeEnVigueur(service.valeur(d.mecefCleMode, d.parametreDateIso(maintenant)));
}

/// Le MODÈLE du boîtier MECeF en vigueur à [maintenant] (décision de la Direction de Baguidi du 16/11/2026 : un ELTRADE CC300) : le réglage de clinique
/// `mecef.modeleBoitier` du registre, LU en base (semé à « ELTRADE CC300 », versionné par date, synchronisé par le journal). `null` : non renseigné.
String? modeleBoitierDuPoste(Magasin m, DateTime maintenant) {
  final service = serviceParametres(m, auteur: () => m.utilisateur, horloge: () => maintenant);
  return d.mecefModeleBoitierEnVigueur(service.valeur(d.mecefCleModeleBoitier, d.parametreDateIso(maintenant)));
}

/// L'adaptateur du mode en vigueur. Tant qu'aucun adaptateur réel n'existe (lot M3 : l'interface et le protocole du boîtier ELTRADE CC300, et le dossier
/// d'interface e-MECeF de la DGI ne figurent dans aucun document remis), c'est l'adaptateur « non configuré » : il REFUSE en nommant (le modèle compris) et ne
/// fabrique aucun numéro.
d.AdaptateurMecef adaptateurDuPoste(Magasin m, DateTime maintenant) =>
    d.adaptateurPourMode(modeMecefDuPoste(m, maintenant), modeleBoitier: modeleBoitierDuPoste(m, maintenant));
