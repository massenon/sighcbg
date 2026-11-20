// L'IMPORT DE LA LIASSE FISCALE DEPUIS UN POSTE RATTACHÉ (Direction de Baguidi, 18/11/2026, point 4 : « import de la liasse par un fileul »).
//
// La collection `documentsFiscaux` reste de FAMILLE R : la mère seule l'écrit, les fileuls la reçoivent, elle ne va jamais vers un téléphone (donnée financière, RG-13). Ce qui change : un fileul
// n'est plus réduit à lire. Il DÉPOSE une demande d'import (collection `validationsDeposees`, famille A, genre [valGenreLiasseImporter]) dont le contenu est le document que SON poste vient de
// valider avec le validateur strict ([lireDocumentFiscal]) ; la MÈRE rejoue cette validation stricte sur le contenu reçu (elle ne fait confiance à aucune lecture d'un autre poste), applique l'import
// sous le geste réservé `documents_fiscaux_importer` du COMPTE signataire (vérifié avant tout rejeu), sous le nom du déposant, et renvoie un verdict nommé sur la même fiche.
//
// La taille du document déposé est BORNÉE par un réglage de la clinique ([cleTailleMaxDepotFiscalKo], daté, borné), jamais par un nombre écrit ici ; la mère reborne à SA valeur. Une fois le
// verdict écrit, la mère VIDE le contenu du dépôt (une liasse n'a pas à rester dupliquée dans le registre des demandes : la version importée vit dans `documentsFiscaux`, la demande ne garde que son
// identité et des nombres de lignes — jamais un montant, E4805).
//
// Fonctions PURES : le poste y branche ses collections, son journal et son transport.

import 'dart:convert';

import '../droits/gestes_reserves.dart';
import '../validation/validation.dart' show RefusValidation, valInstant;
import '../validation/validation_deposee.dart';
import 'documents_fiscaux.dart';
import 'documents_fiscaux_import.dart';

/// Le genre de dépôt : la demande d'import d'une liasse ou d'un classeur, faite depuis un poste rattaché.
const String valGenreLiasseImporter = 'liasse_importer';

/// La clé du RÉGLAGE (en Ko) de la taille maximale d'un document fiscal déposé à la mère par un poste rattaché. Daté, borné par sa définition ; jamais en dur.
const String cleTailleMaxDepotFiscalKo = 'comptabilite.tailleMaxDepotFiscalKo';

/// La taille d'un contenu, en OCTETS, telle qu'elle voyage (JSON UTF-8).
int docFiscalOctets(Map<String, Object?> contenu) => utf8.encode(jsonEncode(contenu)).length;

/// Le motif d'un refus avec l'endroit fautif, sans jamais doubler le point final (même règle que [RefusImportFiscal.message]).
String _motif(RefusImportFiscal r) => r.chemin.isEmpty ? r.motif : '${refusFiscalSansPonctuationFinale(r.motif)} (${r.chemin}).';

RefusValidation _refus(RefusImportFiscal r) => RefusValidation(r.code, _motif(r), r.geste);

RefusImportFiscal? _taille(Map<String, Object?> contenu, int tailleMaxKo) {
  final o = docFiscalOctets(contenu);
  if (o <= tailleMaxKo * 1024) return null;
  return RefusImportFiscal(
      'DOCUMENT_TROP_VOLUMINEUX',
      'Le document pèse ${(o / 1024).ceil()} Ko : la clinique borne un document déposé à la mère à $tailleMaxKo Ko (réglage « taille maximale d’un document fiscal déposé »).',
      'Importer le document sur le poste mère, ou faire relever la limite par une version datée du réglage.');
}

/// DÉPOSE la demande d'import d'un document déjà LU ET VALIDÉ par le validateur strict sur ce poste ([document]). Les contrôles sont ceux de l'import direct, refaits à blanc : le geste réservé du
/// rôle ([gestes]), la source, l'auteur, la date de dépôt, l'unicité de la version, la taille bornée par [tailleMaxKo]. Un refus se nomme dès le poste, rien n'est déposé. Un dépôt identique qui
/// attend déjà la mère n'est pas doublé. [existantes] : TOUTES les fiches de `documentsFiscaux` que ce poste connaît (archivées comprises).
VerdictDepot liasseImporterDeposer({
  required DocumentFiscalLu document,
  required String? dateDepot,
  required String source,
  required String auteur,
  required String role,
  required String poste,
  required DateTime maintenant,
  required Iterable<Map<String, Object?>> existantes,
  required DroitsGestes gestes,
  required int tailleMaxKo,
  required List<Map<String, Object?>> depots,
  required String Function() nouvelId,
}) {
  final t = _taille(document.contenu, tailleMaxKo);
  if (t != null) return VerdictDepot.refus(_refus(t));
  final essai = preparerImportFiscal(
      document: document,
      dateDepot: dateDepot,
      source: source,
      auteur: auteur,
      maintenant: maintenant,
      existantes: existantes,
      peutImporter: gestes.peut(role, gesteDocumentsFiscauxImporter));
  if (!essai.accepte) return VerdictDepot.refus(_refus(essai.refus!));
  final fiche = essai.fiche!;
  final jour = '${fiche['dateEffet']}';
  final encode = jsonEncode(document.contenu);
  for (final d in depots) {
    if (d['statut'] != 'archive' &&
        d['etat'] == valDepotDeposee &&
        d['genre'] == valGenreLiasseImporter &&
        d['documentGenre'] == document.genre &&
        d['exercice'] == document.exercice &&
        d['dateDepot'] == jour &&
        '${d['source']}' == source.trim() &&
        d['contenu'] is Map &&
        jsonEncode(d['contenu']) == encode) {
      return VerdictDepot.ok(d, dejaDepose: true);
    }
  }
  final quoi = document.genre == docFiscalLiasse ? 'liasse' : 'classeur';
  return VerdictDepot.ok({
    'id': nouvelId(),
    'statut': 'actif',
    'genre': valGenreLiasseImporter,
    'famille': colDocumentsFiscaux,
    'cible': '${document.genre}|${document.exercice}|$jour',
    'libelle': 'Import de la $quoi ${document.exercice} (dépôt du $jour)',
    'etat': valDepotDeposee,
    'documentGenre': document.genre,
    'exercice': document.exercice,
    'dateDepot': jour,
    'source': source.trim(),
    'contenu': document.contenu,
    'octets': docFiscalOctets(document.contenu),
    'resume': docFiscalNombresDeLignes(document.contenu),
    'demandeRole': role,
    'demandePar': auteur.trim(),
    'demandePoste': poste,
    'demandeLe': valInstant(maintenant),
  });
}

/// Ce que la mère décide d'une demande d'import : le verdict à écrire et, quand l'import s'applique, la FICHE à ajouter à `documentsFiscaux`.
class ApplicationLiasseImporter {
  const ApplicationLiasseImporter({required this.etat, this.code, this.motif, this.geste, this.fiche, this.reference});
  final String etat;
  final String? code;
  final String? motif;
  final String? geste;

  /// Non nulle seulement quand [etat] vaut `appliquee` : la version à écrire (identité, source, date de dépôt, auteur, contenu).
  final Map<String, Object?>? fiche;

  /// L'identité de la version écrite (rendue au déposant avec le verdict).
  final String? reference;
}

/// APPLIQUE une demande d'import sur la mère. Les contrôles, dans l'ordre : le contenu est présent, sa taille tient dans la borne DE LA MÈRE, le document est RELU par le validateur strict
/// (`lireDocumentFiscal` sur le contenu reçu, jamais sur la lecture d'un autre poste), il est bien celui que la demande annonce, puis [preparerImportFiscal] sous le RÔLE et le NOM du déposant avec
/// le geste réservé relu dans la matrice de la mère et les versions de la mère. La date est celle du GESTE (`demandeLe`). `null` : rien à faire (demande déjà traitée).
ApplicationLiasseImporter? liasseImporterAppliquer(
  Map<String, Object?> depot, {
  required Iterable<Map<String, Object?>> existantes,
  required DroitsGestes gestes,
  required int tailleMaxKo,
  required DateTime maintenant,
}) {
  if (depot['genre'] != valGenreLiasseImporter || depot['etat'] != valDepotDeposee || depot['statut'] == 'archive') return null;
  ApplicationLiasseImporter non(RefusImportFiscal r) => ApplicationLiasseImporter(etat: valDepotRefusee, code: r.code, motif: _motif(r), geste: r.geste);
  final contenu = depot['contenu'];
  if (contenu is! Map || contenu.isEmpty) {
    return non(const RefusImportFiscal('CONTENU_ABSENT', 'La demande ne porte aucun document : il n’est jamais arrivé à la mère.', 'Refaire l’import depuis l’écran « Import de la liasse fiscale ».'));
  }
  final c = contenu.cast<String, Object?>();
  final t = _taille(c, tailleMaxKo);
  if (t != null) return non(t);
  final lu = lireDocumentFiscal(jsonEncode(c));
  if (lu.refus != null) return non(lu.refus!);
  final doc = lu.document!;
  if ('${depot['documentGenre']}' != doc.genre || '${depot['exercice']}' != '${doc.exercice}') {
    return non(const RefusImportFiscal('DEPOT_INCOHERENT', 'La demande annonce un document qui n’est pas celui qu’elle porte (genre ou exercice différents) : rien n’est importé.', 'Refaire l’import depuis l’écran « Import de la liasse fiscale ».'));
  }
  final quand = DateTime.tryParse('${depot['demandeLe'] ?? ''}')?.toLocal() ?? maintenant;
  final dateDepot = '${depot['dateDepot'] ?? ''}'.trim();
  final v = preparerImportFiscal(
      document: doc,
      dateDepot: dateDepot.isEmpty ? null : dateDepot,
      source: '${depot['source'] ?? ''}',
      auteur: '${depot['demandePar'] ?? ''}',
      maintenant: quand,
      existantes: existantes,
      peutImporter: gestes.peut('${depot['demandeRole'] ?? ''}', gesteDocumentsFiscauxImporter));
  if (!v.accepte) return non(v.refus!);
  return ApplicationLiasseImporter(etat: valDepotAppliquee, fiche: v.fiche, reference: '${v.fiche!['id']}');
}

/// Les demandes d'import de CE poste (ou de tous), la plus récente d'abord : l'écran dit « transmise à la mère, en attente », « appliquée » ou le motif nommé du refus.
List<Map<String, Object?>> liasseDepotsRecents(Iterable<Map<String, Object?>> depots) {
  final l = [for (final d in depots) if (d['statut'] != 'archive' && d['genre'] == valGenreLiasseImporter) d];
  l.sort((a, b) => '${b['demandeLe']}${b['id']}'.compareTo('${a['demandeLe']}${a['id']}'));
  return l;
}
