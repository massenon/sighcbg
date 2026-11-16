/// LA CORRECTION SIGNÉE DU TEXTE LU PAR MACHINE (lot C, conçu pour Baguidi : la clinique sœur ne l'a pas commencé ; décisions de la Direction rappelées dans la demande du lot).
///
/// Un utilisateur habilité corrige le texte produit par le moteur. La correction n'est JAMAIS une réécriture : c'est une NOUVELLE VERSION de la collection `lecturesOcr` (ajout seul,
/// comme une lecture), `texteSource: 'humain'`, qui porte l'AUTEUR, la date et l'heure, le motif (facultatif), la version qu'elle corrige (`corrigeDe`) et une SIGNATURE d'intégrité.
/// Le texte machine reste, intact, dans l'historique ; la version humaine devient la version COURANTE (`ocrVersionCourante`) : c'est elle qui est indexée et affichée « corrigé par X ».
///
/// TROIS RÈGLES :
///  - le droit de corriger suit la matrice, sans nom de rôle : par défaut (le plus prudent, HYPOTHÈSE À VALIDER) ceux qui peuvent ÉDITER l'écran du document concerné ;
///  - on ne corrige que ce qu'on a le droit de LIRE : pour un document du dossier patient, les catégories sensibles de son type (`docPeutLire`), exactement comme pour le consulter ;
///  - tout refus se nomme (code, motif, geste) ; un texte inchangé, vide ou démesuré n'est pas une correction.
library;

import 'doc_ocr.dart';
import 'doc_regles.dart' show docPeutLire, docCategoriesManquantes;
import 'doc_sha256.dart';

/// La taille maximale d'un texte corrigé (la même borne que le texte brut d'une lecture : un texte plus long serait tronqué en silence, on le refuse plutôt).
const int ocrCorrectionMax = ocrBrutMax;

/// Le droit de corriger LE TEXTE d'un document, refusé en nommant, ou `null` si c'est permis. [peutEditerEcran] : le droit d'ÉDITER l'écran du document (la matrice) ;
/// [famille] et [type] : le document ; [peutCategorie] : `AccesSensible.peut`. L'ordre des contrôles est celui de la question posée : d'abord le droit d'écrire, puis celui de lire.
RefusFichier? ocrRefusCorrection({required bool peutEditerEcran, required String famille, required String? type, required bool Function(String categorie)? peutCategorie}) {
  if (!peutEditerEcran) {
    return ocrRefus(CodeOcr.droitRefuse, 'votre profil ne peut pas modifier les pièces de cet écran : il ne peut donc pas en corriger le texte lu');
  }
  if (famille == 'patient') {
    if (peutCategorie == null || !docPeutLire(peutCategorie, type)) {
      final manque = peutCategorie == null ? '' : ' (catégorie manquante : ${docCategoriesManquantes(peutCategorie, type).join(', ')})';
      return ocrRefus(CodeOcr.zoneRefusee, 'on ne corrige que ce qu’on a le droit de lire : ce profil ne lit pas un document de type « ${type ?? 'inconnu'} »$manque');
    }
  }
  return null;
}

/// La correction demandée : refus nommé, ou la fiche de la NOUVELLE version à ajouter. [versions] : les versions de l'empreinte ; [corrigeDe] : l'identifiant de la version corrigée (par
/// défaut la version courante) ; [natif] : le fichier porte une couche texte (elle prime, rien à corriger). Ne contrôle PAS le droit (voir [ocrRefusCorrection]) : l'appelant l'a fait.
({RefusFichier? refus, FicheDoc? fiche}) ocrNouvelleCorrection({
  required String sha,
  required String texte,
  required Iterable<FicheDoc> versions,
  required bool natif,
  required String auteur,
  required String corrigeLe,
  String? corrigeDe,
  String? motif,
  String? auteurId,
}) {
  if (natif) return (refus: ocrRefus(CodeOcr.texteNatif, 'ce fichier porte déjà une couche texte : elle prime, il n’y a pas de texte lu à corriger'), fiche: null);
  if (auteur.trim().isEmpty) return (refus: ocrRefus(CodeOcr.auteurRequis, 'une correction est signée : aucun auteur connu', 'Ouvrir une session, puis corriger.'), fiche: null);
  final liste = versions.where((v) => '${v['sha256']}' == sha).toList();
  if (liste.isEmpty) return (refus: ocrRefus(CodeOcr.sansLecture, 'ce scan n’a aucun texte lu à corriger', 'Attendre la lecture, ou la relancer.'), fiche: null);
  final parent = corrigeDe == null ? ocrVersionCourante(liste) : liste.where((v) => v['id'] == corrigeDe).firstOrNull;
  if (parent == null) return (refus: ocrRefus(CodeOcr.versionInconnue, 'la version à corriger n’existe pas pour ce scan', 'Rouvrir l’historique des lectures.'), fiche: null);
  final propre = texte.replaceAll('\r\n', '\n').trim();
  if (propre.isEmpty) return (refus: ocrRefus(CodeOcr.texteVide, 'le texte corrigé est vide', 'Saisir le texte, ou laisser la version actuelle.'), fiche: null);
  if (propre.length > ocrCorrectionMax) {
    return (refus: ocrRefus(CodeOcr.texteTropLong, 'le texte corrigé dépasse $ocrCorrectionMax caractères', 'Ne garder que le texte utile à la recherche.'), fiche: null);
  }
  if (propre == '${parent['texteBrut'] ?? ''}'.replaceAll('\r\n', '\n').trim()) {
    return (refus: ocrRefus(CodeOcr.aucunChangement, 'le texte n’a pas changé : ce n’est pas une correction', 'Modifier le texte avant d’enregistrer.'), fiche: null);
  }
  final m = (motif ?? '').trim();
  final parentId = '${parent['id']}';
  final norm = ocrMotsNormalises(propre);
  final signature = ocrSignature(sha: sha, corrigeDe: parentId, texte: propre, auteur: auteur.trim(), corrigeLe: corrigeLe, motif: m);
  return (
    refus: null,
    fiche: {
      // identifiant déterministe : une même correction rejouée (même texte, auteur, date) ne fait qu'une version, comme une lecture
      'id': 'COR-${sha.substring(0, 16)}-${docSha256(<int>[...parentId.codeUnits, ...signature.codeUnits]).substring(0, 12)}',
      'sha256': sha,
      'texteBrut': propre,
      'brutTronque': false,
      'texte': norm.take(ocrMotsMax).join(' '),
      'motsTronques': norm.length > ocrMotsMax,
      'nbMots': norm.length,
      'texteSource': 'humain',
      'corrigeDe': parentId,
      'corrigePar': auteur.trim(),
      if (auteurId != null && auteurId.isNotEmpty) 'corrigeParId': auteurId,
      'corrigeLe': corrigeLe,
      'motif': m,
      'signature': signature,
      'langue': '${parent['langue'] ?? ocrLangueDefaut}',
      // le tri des versions lit `ocrLe` : la date de la correction est celle de la version
      'ocrLe': corrigeLe,
      'ocrPar': auteur.trim(),
    }
  );
}

/// L'historique lisible d'une empreinte : de la plus récente à la plus ancienne, chaque ligne dit ce qu'est la version (lecture machine ou correction), qui, quand, pourquoi, si c'est la
/// courante, et si la signature d'une correction ne se retrouve pas (`signatureInvalide` : elle n'est alors jamais courante).
List<Map<String, Object?>> ocrHistorique(Iterable<FicheDoc> versions) {
  final ordre = ocrVersionsOrdonnees(versions);
  final courante = ocrVersionCourante(ordre);
  return [
    for (var i = ordre.length - 1; i >= 0; i--)
      {
        'rang': i + 1,
        'id': ordre[i]['id'],
        'nature': ocrEstCorrigee(ordre[i]) ? 'correction' : 'machine',
        'par': ocrEstCorrigee(ordre[i]) ? ordre[i]['corrigePar'] : ordre[i]['ocrPar'],
        'quand': ordre[i]['ocrLe'],
        'motif': ordre[i]['motif'] ?? '',
        'corrigeDe': ordre[i]['corrigeDe'],
        'courante': courante != null && courante['id'] == ordre[i]['id'],
        'signatureInvalide': !ocrSignatureValide(ordre[i]),
        'texteBrut': ordre[i]['texteBrut'] ?? '',
        'moteur': ordre[i]['moteur'],
      }
  ];
}
