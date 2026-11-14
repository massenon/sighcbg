import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/service_installation.dart';
import '../../donnees/tarifs_poste.dart';
import '../../kit/validation_poste.dart';
import '../../shell/contexte_ecran.dart';

/// LE POSTE DE PRIX D'UN ÉCRAN, en UN seul exemplaire : « Tarifs et prix », « Référentiel produits » et la réception d'achat construisent le même [TarifsPoste] (mère ou fileul, matrice en force,
/// gestes réservés relus à chaque appel). Écrire trois fois ce câblage ferait diverger les trois écrans au premier droit ajouté.
///
/// Les deux droits sont distincts : [peutEditerEcran] (modifier « Tarifs et prix », ce qui propose le prix d'une PRESTATION) et [peutProposerPrixAchat] (modifier « Référentiel produits » : proposer
/// le prix d'ACHAT d'un produit). Le premier n'emporte jamais le second.
///
/// [droitProduit] : l'écran dont le droit d'ÉDITER vaut droit de proposer un prix d'achat (par défaut le référentiel des produits ; la réception d'achat passe le sien).
TarifsPoste tarifsDeLEcran(ContexteEcran c, {String droitProduit = 'm6-produits', bool? peutProposerPrixAchat}) {
  final m = c.magasin;
  final matrice = c.donnees?.matrice;
  return TarifsPoste(m,
      role: c.role,
      auteur: () => c.agent.nom.isEmpty ? 'Utilisateur' : c.agent.nom,
      fileul: ServiceInstallation.de(m).rattache,
      libelles: ValidationPoste(c).libelles,
      peutEditerEcran: c.droit.editer,
      peutEditerPour: matrice == null ? null : (r) => matrice.peutEditer(r, 'cfg-tarifs'),
      peutProposerPrixAchat: peutProposerPrixAchat ?? (matrice?.peutEditer(c.role, droitProduit) ?? false),
      peutProposerPrixAchatPour: matrice == null ? null : (r) => matrice.peutEditer(r, droitProduit),
      gestes: () => DroitsGestes(fiches: m.collection('rbac').actives, estArchive: matrice?.estArchive, ecranActif: matrice?.ecranActif),
      horloge: () => c.aujourdhui,
      etiquette: m.poste.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase());
}

/// Le prix d'achat EN VIGUEUR aujourd'hui d'un produit (jamais la fiche). Source unique de la colonne de « Référentiel produits », de celle de l'onglet Produits de « Tarifs et prix » et du filtre.
PrixProduit prixDuJour(ContexteEcran c, Map<String, Object?> produit) => TarifsPoste.prixProduit(c.magasin, produit, aujourdhui: c.aujourdhui, date: tarIso(c.aujourdhui));

/// Un article « à valoriser » : doté d'une prestation de prix mais sans prix d'achat en vigueur aujourd'hui (prix absent, jamais zéro : l'article ne se facture pas).
bool aValoriser(ContexteEcran c, Map<String, Object?> produit) => TarifsPoste.lire(c.magasin).parCode['${produit['code']}'] != null && prixDuJour(c, produit).absent;

/// Le prix d'achat en vigueur aujourd'hui (la version), `null` quand il est absent. Un article qui n'a PAS ENCORE de prestation de prix (avant la reprise de la mère, ou sur un fileul qui ne l'a pas encore
/// reçue) montre le prix que sa fiche tient : c'est le seul cas où la fiche est lue.
num? achatDuJour(ContexteEcran c, Map<String, Object?> p) {
  if (TarifsPoste.lire(c.magasin).parCode['${p['code']}'] == null) return p['prixAchat'] as num?;
  final r = prixDuJour(c, p);
  return r.absent ? null : r.achat;
}

/// Le prix de vente DÉRIVÉ (RG-02) en vigueur aujourd'hui ; même repli que [achatDuJour].
num? venteDuJour(ContexteEcran c, Map<String, Object?> p) {
  if (TarifsPoste.lire(c.magasin).parCode['${p['code']}'] == null) return p['prixVente'] as num?;
  final r = prixDuJour(c, p);
  return r.absent ? null : r.vente;
}
