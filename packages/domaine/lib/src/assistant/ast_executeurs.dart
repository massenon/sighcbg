/// LES EXÉCUTEURS : un par intention. Chacun LIT le magasin par [ContexteAst.col] (fiches gelées, archivées écartées) et rend une [ReponseAst] qui CITE ses sources.
/// Aucun exécuteur n'écrit : le contexte ne porte aucune fonction d'écriture, et les fiches lues sont non modifiables.
///
/// Règles de toutes les réponses :
///  * jamais d'invention : une lecture vide se dit (`pas_de_donnees`), une donnée non renseignée se dit (`non_calculable`), un champ masqué par catégorie sensible
///    porte la mention réservée — jamais un trou qui se lirait comme une donnée absente ;
///  * un « homonyme » n'est jamais tranché : la liste est rendue, pas la première ;
///  * les sous-sources (un second écran, une seconde collection) ne sont lues que si l'agent voit leur écran, et la réponse nomme ce qu'elle n'a pas lu.
library;

import '../droits/donnees_sensibles.dart' show mentionReservee;
import '../format/format_fr.dart' show money, nombreOuNul;
import '../format/js.dart' show nombreOuZero;
import '../labo/res_etats.dart' show etatResultat;
import '../labo/res_habilitations.dart' show peutVoirResultat;
import '../caisse/prise_en_charge.dart' show carteValide, couvertureALaDate;
import '../referentiels/regles.dart' show lireCodePatient, resultatRendu;
import '../stock/stock.dart' show delaiPreavisPeremption, etatStock, joursAvantPeremption, libelleCategorie, ordreFefo, seuilFixe, sousSeuil, valeurStock;
import '../tarifs/tarifs.dart' show ReferentielTarifs;
import 'ast_contexte.dart';
import 'ast_reconnaissance.dart';
import 'ast_texte.dart';

typedef ExecuteurAst = ReponseAst Function(ContexteAst cx, ReconnaissanceAst r, String question);

// ----------------------------------------------------------------------------------------------------------------------------------------------------
// Outils communs
// ----------------------------------------------------------------------------------------------------------------------------------------------------

String _d(Object? iso) {
  final t = '${iso ?? ''}';
  if (t.length < 10 || !RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(t)) return t.isEmpty ? '—' : t;
  return '${t.substring(8, 10)}/${t.substring(5, 7)}/${t.substring(0, 4)}';
}

String _jour10(Object? v) {
  final t = '${v ?? ''}';
  return t.length >= 10 ? t.substring(0, 10) : t;
}

ReponseAst _rep(String id, String titre, List<String> lignes, List<SourceAst> src, {TableauAst? tableau}) =>
    ReponseAst(statut: 'reponse', intention: id, titre: titre, lignes: lignes, tableau: tableau, sources: src);

ReponseAst _vide(String id, String titre, List<String> lignes, List<SourceAst> src) =>
    ReponseAst(statut: 'pas_de_donnees', code: 'AUCUN_RESULTAT', intention: id, titre: titre, lignes: lignes, sources: src);

ReponseAst _refusLecture(String id, String titre, List<String> lignes) =>
    ReponseAst(statut: 'refus', code: 'LECTURE_NON_AUTORISEE', intention: id, titre: titre, lignes: lignes);

/// Ce que l'agent n'a pas pu lire faute d'écran : toujours dit, jamais compté pour zéro.
String _nonLu(List<String> ecrans, ContexteAst cx) => 'Non lu (hors de votre périmètre) : ${ecrans.map(cx.ecran).join(', ')}.';

/// Les mots d'une requête sont-ils TOUS dans le libellé (exacts, ou à une faute près pour les mots longs) ?
bool _correspond(String libelle, String requete) {
  final l = astNormaliser(libelle).split(' ');
  final q = astNormaliser(requete).split(' ').where((x) => x.isNotEmpty).toList();
  if (q.isEmpty) return false;
  for (final m in q) {
    final t = astTolerance(m.length);
    final ok = l.any((x) => x == m || (t > 0 && x.length >= 4 && astDistance(x, m, t) <= t) || (m.length >= 4 && x.startsWith(m)));
    if (!ok) return false;
  }
  return true;
}

bool _exact(String libelle, String requete) => astNormaliser(libelle) == astNormaliser(requete);

/// La date visée par la question : le début de la période si elle porte sur un jour, sinon aujourd'hui.
String _jourVise(ReconnaissanceAst r, ContexteAst cx) {
  final p = r.parametres['periode'];
  if (p is Map && p['debut'] is String && p['type'] != 'anciennete_jours') return p['debut'] as String;
  return cx.jour;
}

({String debut, String fin, String libelle}) _plage(Map<String, Object?>? p, ContexteAst cx, {required int joursParDefaut}) {
  String debut, fin;
  if (p == null || p['debut'] == null) {
    final j = DateTime.utc(cx.maintenant.year, cx.maintenant.month, cx.maintenant.day);
    fin = astIso(j);
    debut = astIso(j.subtract(Duration(days: joursParDefaut)));
    return (debut: debut, fin: fin, libelle: 'les $joursParDefaut derniers jours (du ${_d(debut)} au ${_d(fin)})');
  }
  debut = '${p['debut']}';
  fin = '${p['fin']}';
  return (debut: debut, fin: fin, libelle: debut == fin ? 'le ${_d(debut)}' : 'du ${_d(debut)} au ${_d(fin)}');
}

Map<String, Object?>? _periodeDe(ReconnaissanceAst r, [String cle = 'periode']) => (r.parametres[cle] as Map?)?.cast<String, Object?>();

bool _dans(Object? date, String debut, String fin) {
  final j = _jour10(date);
  return j.isNotEmpty && j.compareTo(debut) >= 0 && j.compareTo(fin) <= 0;
}

String _nomPatient(Map<String, Object?> p) => '${p['nom'] ?? ''} ${p['prenom'] ?? ''}'.trim();

bool _duPatient(Map<String, Object?> f, Map<String, Object?> p) =>
    (f['patientId'] != null && f['patientId'] == p['id']) || (f['patientCode'] != null && f['patientCode'] == p['code']);

// ----------------------------------------------------------------------------------------------------------------------------------------------------
// Patients
// ----------------------------------------------------------------------------------------------------------------------------------------------------

const _srcPatients = SourceAst('m1-patients', 'patients');

({List<Map<String, Object?>> trouves, String? note}) _chercherPatients(ContexteAst cx, Map<String, Object?> p) {
  final liste = cx.col('patients');
  var code = p['codePatient'] as String?;
  if (p['patient'] == 'contexte') code = cx.patientContexte;
  if (code != null) {
    final c = lireCodePatient(code);
    if (c == null) return (trouves: const [], note: null);
    return (
      trouves: [
        for (final f in liste)
          if (lireCodePatient(f['code']) case final x? when x.rang == c.rang && x.annee == c.annee) f
      ],
      note: null,
    );
  }
  final nom = p['nomPatient'] as String?;
  if (nom == null) return (trouves: const [], note: null);
  var out = [
    for (final f in liste)
      if (_correspond('${f['nom'] ?? ''} ${f['prenom'] ?? ''}', nom)) f
  ];
  String? note;
  final annee = p['anneeNaissance'];
  if (annee != null) {
    // Filtrer sur l'année de naissance à un profil qui ne lit pas l'identité détaillée la lui révélerait par déduction : le filtre est alors ignoré, et dit.
    if (cx.sensible('identite_detaillee')) {
      out = [for (final f in out) if ('${f['dateNaissance'] ?? ''}'.startsWith('$annee')) f];
    } else {
      note = 'Le filtre sur l’année de naissance est ignoré : ${mentionReservee('identite_detaillee')}.';
    }
  }
  return (trouves: out, note: note);
}

/// Un patient, ou la réponse qui dit pourquoi il n'y en a pas un seul (aucun, ou des homonymes jamais tranchés).
({Map<String, Object?>? patient, ReponseAst? reponse, String? note}) _unPatient(ContexteAst cx, ReconnaissanceAst r, String id) {
  final res = _chercherPatients(cx, r.parametres);
  final trouves = res.trouves;
  final critere = r.parametres['codePatient'] ?? r.parametres['nomPatient'] ?? (r.parametres['patient'] == 'contexte' ? (cx.patientContexte ?? 'le patient de la conversation') : '');
  if (r.parametres['patient'] == 'contexte' && cx.patientContexte == null && !r.parametres.containsKey('codePatient') && !r.parametres.containsKey('nomPatient')) {
    return (
      patient: null,
      reponse: ReponseAst(statut: 'precision', code: 'PRECISION_REQUISE', intention: id, titre: 'De quel patient parlez-vous ?', lignes: const ['Aucun patient n’a été nommé plus tôt dans cette conversation.'], sources: const []),
      note: null
    );
  }
  if (trouves.isEmpty) {
    return (patient: null, reponse: _vide(id, 'Aucun patient ne correspond à « $critere »', ['Vérifiez l’orthographe ou le code (forme CBG/rang/année).', if (res.note != null) res.note!], const [_srcPatients]), note: res.note);
  }
  if (trouves.length > 1) {
    final lignes = [
      for (final f in trouves.take(8)) '${f['code']} — ${_nomPatient(f)}${cx.sensible('identite_detaillee') && f['dateNaissance'] != null ? ' (né(e) le ${_d(f['dateNaissance'])})' : ''}',
      if (trouves.length > 8) '… et ${trouves.length - 8} autres.',
      if (res.note != null) res.note!,
    ];
    return (
      patient: null,
      reponse: ReponseAst(
          statut: 'ambigue', code: 'HOMONYMES', intention: id, titre: '${trouves.length} patients correspondent à « $critere »',
          lignes: ['Choisissez par le code : je ne prends jamais le premier.', ...lignes], sources: const [_srcPatients], propositions: [for (final f in trouves.take(8)) '${f['code']}']),
      note: res.note
    );
  }
  return (patient: trouves.first, reponse: null, note: res.note);
}

ReponseAst _i01(ContexteAst cx, ReconnaissanceAst r, String q) {
  final u = _unPatient(cx, r, 'I01');
  if (u.reponse != null) return u.reponse!;
  final p = u.patient!;
  final lignes = <String>[
    'Code : ${p['code']}',
    'Nom : ${_nomPatient(p)}${p['sexe'] != null && '${p['sexe']}'.isNotEmpty ? ' (${p['sexe']})' : ''}',
    if (cx.sensible('identite_detaillee')) 'Né(e) le : ${_d(p['dateNaissance'])}' else mentionReservee('identite_detaillee'),
  ];
  // Dernière venue : définition PROPOSÉE, sur les seules sources que l'agent lit.
  final dates = <(String, String)>[];
  final nonLus = <String>[];
  final src = <SourceAst>[_srcPatients];
  void vue(String ecran, String col, String champ, String nom) {
    if (!cx.peutVoirEcran(ecran)) {
      nonLus.add(ecran);
      return;
    }
    src.add(SourceAst(ecran, col));
    for (final f in cx.col(col)) {
      if (_duPatient(f, p) && '${f[champ] ?? ''}'.isNotEmpty) dates.add((_jour10(f[champ]), nom));
    }
  }

  vue('m2-consultations', 'consultations', 'date', 'consultation');
  vue('m3-admissions', 'admissions', 'dateEntree', 'admission');
  vue('m8-factures', 'factures', 'date', 'facture');
  dates.sort((a, b) => b.$1.compareTo(a.$1));
  lignes.add(dates.isEmpty
      ? 'Dernière venue : aucune trace dans les sources que vous lisez.'
      : 'Dernière venue connue : ${_d(dates.first.$1)} (${dates.first.$2}). Définition proposée : la date la plus récente parmi les consultations, admissions et factures que vous pouvez lire.');
  if (nonLus.isNotEmpty) lignes.add(_nonLu(nonLus, cx));
  if (u.note != null) lignes.add(u.note!);
  return _rep('I01', 'Dossier ${p['code']}', lignes, src);
}

ReponseAst _i02(ContexteAst cx, ReconnaissanceAst r, String q) {
  if (!cx.sensible('couverture_assurance')) {
    return _refusLecture('I02', 'Couverture d’assurance réservée', [mentionReservee('couverture_assurance')]);
  }
  final u = _unPatient(cx, r, 'I02');
  if (u.reponse != null) return u.reponse!;
  final p = u.patient!;
  final date = _jourVise(r, cx);
  final couvs = [for (final c in cx.col('couverturesAssurance')) c];
  final c = couvertureALaDate(p, couvs, date);
  const src = [_srcPatients];
  if (c == null) {
    return _rep('I02', '${p['code']} — aucune carte à la date du ${_d(date)}', ['Aucune couverture d’assurance n’est enregistrée à cette date. Ce n’est pas une carte « invalide » : il n’y en a pas.'], src);
  }
  final valide = carteValide(p, couvs, date);
  final exp = c['carteExpiration'];
  return _rep('I02', '${p['code']} — carte ${valide ? 'valide' : 'NON valide'} au ${_d(date)}', [
    'Compagnie : ${c['assureurNom'] ?? c['assureur'] ?? '—'}',
    'Police : ${c['numeroPolice'] ?? '—'}',
    if (c['tauxPriseEnCharge'] != null) 'Taux de prise en charge : ${c['tauxPriseEnCharge']} %',
    exp == null || '$exp'.isEmpty ? 'Expiration : non renseignée (la carte ne peut pas être dite valide).' : 'Expire le : ${_d(exp)}',
    if (!valide) 'RG-09 : sans carte valide à la date de facturation, la facture est intégralement au patient.',
  ], src);
}

// ----------------------------------------------------------------------------------------------------------------------------------------------------
// Facturation
// ----------------------------------------------------------------------------------------------------------------------------------------------------

ReponseAst _i03(ContexteAst cx, ReconnaissanceAst r, String q) {
  final u = _unPatient(cx, r, 'I03');
  if (u.reponse != null) return u.reponse!;
  final p = u.patient!;
  final factures = [for (final f in cx.col('factures')) if (_duPatient(f, p)) f]..sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));
  final src = [_srcPatients, const SourceAst('m8-factures', 'factures')];
  if (factures.isEmpty) return _vide('I03', '${p['code']} — aucune facture', ['Aucune facture n’est enregistrée pour ce patient.'], src);
  final dues = [for (final f in factures) if (f['statutPaiement'] != 'soldee' && nombreOuZero(f['reliquat']) > 0) f];
  final total = dues.fold<num>(0, (a, f) => a + nombreOuZero(f['reliquat']));
  final der = factures.first;
  return _rep('I03', '${p['code']} — reste à payer : ${money(total)}', [
    dues.isEmpty ? 'Toutes les factures sont soldées.' : '${dues.length} facture(s) non soldée(s) : ${dues.take(5).map((f) => '${f['numero']} (${money(f['reliquat'])})').join(', ')}.',
    'Dernière facture : ${der['numero']} du ${_d(der['date'])}, ${money(der['montantTTC'])}, ${der['statutPaiement'] ?? '—'}.',
    'Le reste à payer est la part PATIENT (reliquat) ; la part de l’assureur est une créance de l’écran Créances.',
  ], src);
}

ReponseAst _i14(ContexteAst cx, ReconnaissanceAst r, String q) {
  final pl = _plage(_periodeDe(r), cx, joursParDefaut: 0);
  num somme(String debut, String fin, Map<String, num> parType, Set<Object?> factures) {
    var t = 0.0;
    for (final f in cx.col('factures')) {
      for (final l in ((f['lignes'] as List?) ?? const [])) {
        if (l is Map && _dans(l['payeLe'], debut, fin)) {
          final m = nombreOuZero(l['montantRegle']);
          t += m;
          parType['${f['type'] ?? 'Autre'}'] = (parType['${f['type'] ?? 'Autre'}'] ?? 0) + m;
          factures.add(f['numero']);
        }
      }
    }
    return t;
  }

  final parType = <String, num>{};
  final facts = <Object?>{};
  final total = somme(pl.debut, pl.fin, parType, facts);
  const src = [SourceAst('m8-recettes', 'factures')];
  final lignes = <String>[];
  final cmp = _periodeDe(r, 'periodeComparee');
  if (cmp != null) {
    final t2 = somme('${cmp['debut']}', '${cmp['fin']}', <String, num>{}, <Object?>{});
    lignes.add('Période comparée (du ${_d(cmp['debut'])} au ${_d(cmp['fin'])}) : ${money(t2)} — écart ${money(total - t2)}.');
  }
  if (facts.isEmpty && total == 0) {
    return _vide('I14', 'Aucune recette ${pl.libelle}', ['Aucune ligne de facture n’a été réglée sur cette période.', ...lignes], src);
  }
  final types = parType.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return _rep('I14', 'Recettes ${pl.libelle} : ${money(total)}', [
    '${facts.length} facture(s) concernée(s) par au moins un règlement sur la période.',
    ...lignes,
    'Définition : somme des lignes réglées (`montantRegle`) dont la date de règlement tombe dans la période.',
  ], src, tableau: TableauAst(['Type de facture', 'Montant réglé'], [for (final e in types) [e.key, money(e.value)]]));
}

ReponseAst _i15(ContexteAst cx, ReconnaissanceAst r, String q) {
  final pl = _plage(_periodeDe(r), cx, joursParDefaut: 30);
  final factures = [for (final f in cx.col('factures')) if (_dans(f['date'], pl.debut, pl.fin)) f];
  final avoirs = [for (final a in cx.col('avoirs')) if (_dans(a['date'], pl.debut, pl.fin)) a];
  final src = [const SourceAst('m8-factures', 'factures'), const SourceAst('m8-facture-avoir', 'avoirs')];
  if (factures.isEmpty && avoirs.isEmpty) return _vide('I15', 'Aucune facture ni avoir ${pl.libelle}', const [], src);
  final nonCert = [for (final f in factures) if (f['statutMecef'] != 'valide') f];
  final tot = factures.fold<num>(0, (a, f) => a + nombreOuZero(f['montantTTC']));
  final totAv = avoirs.fold<num>(0, (a, f) => a + nombreOuZero(f['montant']));
  return _rep('I15', '${factures.length} facture(s) et ${avoirs.length} avoir(s) ${pl.libelle}', [
    'Montant facturé : ${money(tot)} ; avoirs : ${money(totAv)}.',
    '${nonCert.length} facture(s) non certifiée(s) MECeF (statut différent de « valide »)${nonCert.isEmpty ? '.' : ' : ${nonCert.take(6).map((f) => f['numero']).join(', ')}${nonCert.length > 6 ? '…' : ''}.'}',
  ], src);
}

ReponseAst _i16(ContexteAst cx, ReconnaissanceAst r, String q) {
  final dues = [for (final f in cx.col('factures')) if (f['statutPaiement'] != 'soldee' && nombreOuZero(f['reliquat']) > 0) f];
  const src = [SourceAst('m8-reliquats', 'factures'), SourceAst('m9-creances', 'factures')];
  final auj = DateTime.utc(cx.maintenant.year, cx.maintenant.month, cx.maintenant.day);
  int age(Map<String, Object?> f) {
    final d = DateTime.tryParse(_jour10(f['date']));
    return d == null ? 0 : auj.difference(DateTime.utc(d.year, d.month, d.day)).inDays;
  }

  final seuil = _periodeDe(r)?['type'] == 'anciennete_jours' ? (_periodeDe(r)!['n'] as int) : null;
  final retenues = seuil == null ? dues : [for (final f in dues) if (age(f) > seuil) f];
  if (retenues.isEmpty) return _vide('I16', seuil == null ? 'Aucun impayé patient' : 'Aucun impayé de plus de $seuil jours', const ['La part des assureurs se lit à l’écran Créances.'], src);
  final tranches = <String, List<Map<String, Object?>>>{'0 à 30 jours': [], '31 à 60 jours': [], '61 à 90 jours': [], 'plus de 90 jours': []};
  for (final f in retenues) {
    final a = age(f);
    tranches[a <= 30 ? '0 à 30 jours' : a <= 60 ? '31 à 60 jours' : a <= 90 ? '61 à 90 jours' : 'plus de 90 jours']!.add(f);
  }
  final total = retenues.fold<num>(0, (a, f) => a + nombreOuZero(f['reliquat']));
  return _rep('I16', '${retenues.length} facture(s) impayée(s) : ${money(total)}', [
    'Impayés de la PART PATIENT (reliquat), classés par ancienneté de la facture${seuil == null ? '' : ' (plus de $seuil jours)'}.',
    'La part de l’assureur est la créance de l’écran Créances : elle n’est pas recalculée ici.',
  ], src, tableau: TableauAst(['Ancienneté', 'Factures', 'Montant'], [for (final e in tranches.entries) [e.key, '${e.value.length}', money(e.value.fold<num>(0, (a, f) => a + nombreOuZero(f['reliquat'])))]]));
}

// ----------------------------------------------------------------------------------------------------------------------------------------------------
// Hospitalisation
// ----------------------------------------------------------------------------------------------------------------------------------------------------

ReponseAst _i04(ContexteAst cx, ReconnaissanceAst r, String q) {
  final en = [for (final a in cx.col('admissions')) if (a['statut'] == 'en_cours') a];
  final lits = cx.col('lits');
  final src = [const SourceAst('m3-admissions', 'admissions'), if (cx.peutVoirEcran('m3-plan-lits')) const SourceAst('m3-plan-lits', 'lits')];
  final detail = cx.sensible('hospitalisation_soins');
  final litCherche = r.parametres['lit'] as String?;
  final lignes = <String>[];
  if (litCherche != null) {
    final a = en.where((x) => astNormaliser('${x['lit'] ?? ''}').contains(astNormaliser(litCherche))).toList();
    if (a.isEmpty) return _vide('I04', 'Aucune admission en cours dans le lit « $litCherche »', const ['Le lit est libre ou n’existe pas : le plan des lits ne le dit que s’il est renseigné.'], src);
    return _rep('I04', '${a.length} admission(s) en cours dans le lit « $litCherche »',
        [for (final x in a) detail ? '${x['lit']} — ${x['patient']} (${x['patientCode']}), entré(e) le ${_d(x['dateEntree'])}' : '${x['lit']} — ${mentionReservee('hospitalisation_soins')}'], src);
  }
  lignes.add(lits.isEmpty
      ? 'Lits libres : non calculables — le plan des lits n’est pas renseigné (aucun lit enregistré).'
      : '${lits.length} lit(s) au plan ; ${en.length} admission(s) en cours ; lits libres = ${lits.length - en.length} (un lit ne porte qu’une admission active).');
  if (en.isEmpty) return ReponseAst(statut: 'pas_de_donnees', code: 'AUCUN_RESULTAT', intention: 'I04', titre: 'Aucune admission en cours', lignes: lignes, sources: src);
  return _rep('I04', '${en.length} admission(s) en cours', [
    ...lignes,
    if (!detail) mentionReservee('hospitalisation_soins'),
  ], src,
      tableau: detail
          ? TableauAst(['Lit', 'Patient', 'Entrée', 'Motif'], [for (final a in en.take(15)) ['${a['lit'] ?? '—'}', '${a['patient'] ?? '—'} (${a['patientCode'] ?? '—'})', _d(a['dateEntree']), '${a['diagnosticEntree'] ?? '—'}']])
          : null);
}

// ----------------------------------------------------------------------------------------------------------------------------------------------------
// Tarifs
// ----------------------------------------------------------------------------------------------------------------------------------------------------

String _prix(num? v) => v == null ? '— (valeur manquante, non saisie)' : money(v);

ReponseAst _i05(ContexteAst cx, ReconnaissanceAst r, String q) {
  final requete = '${r.parametres['acte']}';
  final jour = _jourVise(r, cx);
  final ref = ReferentielTarifs(cx.col('tarifs'), cx.col('versionsTarif'));
  var cands = [for (final t in ref.tarifs) if (t['statut'] != 'archive' && _correspond('${t['libelle'] ?? ''}', requete)) t];
  final exacts = [for (final t in cands) if (_exact('${t['libelle']}', requete)) t];
  if (exacts.length == 1) cands = exacts;
  const srcT = SourceAst('cfg-tarifs', 'tarifs');
  if (cands.isEmpty) {
    if (cx.peutVoirEcran('m6-produits')) {
      final prods = [for (final p in cx.col('produits')) if (_correspond('${p['designation'] ?? ''}', requete)) p];
      if (prods.length == 1) {
        final p = prods.first;
        return _rep('I05', '${p['designation']} — ${money(p['prixVente'])}', [
          'Prix de vente (RG-02 : prix d’achat, sans marge). Valorisation du jour : la grille des actes ne couvre pas les produits.',
          if (p['valorisationProvisoire'] == true) 'Valeur d’attente : à confirmer par la Direction.',
        ], const [SourceAst('m6-produits', 'produits')]);
      }
      if (prods.length > 1) {
        return ReponseAst(statut: 'ambigue', code: 'HOMONYMES', intention: 'I05', titre: '${prods.length} produits correspondent à « $requete »',
            lignes: ['Précisez le produit : ${prods.take(6).map((p) => p['designation']).join(' ; ')}.'], sources: const [SourceAst('m6-produits', 'produits')]);
      }
    }
    return _vide('I05', 'Aucun acte, analyse ni produit « $requete »', const ['Rien dans le référentiel de prix ne porte ce nom : je n’en propose pas un voisin.'], const [srcT]);
  }
  if (cands.length > 1) {
    return ReponseAst(statut: 'ambigue', code: 'HOMONYMES', intention: 'I05', titre: '${cands.length} actes correspondent à « $requete »',
        lignes: ['Précisez lequel : ${cands.take(6).map((t) => t['libelle']).join(' ; ')}${cands.length > 6 ? ' …' : ''}.'], sources: const [srcT]);
  }
  final t = cands.first;
  final s = ref.instantane(t, jour);
  if (s == null) {
    return _vide('I05', '${t['libelle']} — aucun prix à la date du ${_d(jour)}', ['Aucune version de prix valide ne couvre cette date.'], const [srcT]);
  }
  return _rep('I05', '${t['libelle']} — prix au ${_d(jour)}', [
    'Non assuré : ${_prix(s.na)}',
    s.nc ? 'Assuré : non couvert (l’assuré paie le tarif non assuré).' : (t['assurable'] == 'sos' ? 'Assuré : couvert par SOS seulement ; toute autre compagnie : tarif non assuré.' : 'Assuré : ${_prix(s.pa)}'),
    'Version ${s.version}${s.dateEffet != null ? ', effective le ${_d(s.dateEffet)}' : ''}.',
    if (s.provisoire) 'Valeur d’attente : tarif provisoire, à confirmer par la Direction.',
  ], const [srcT]);
}

ReponseAst _i06(ContexteAst cx, ReconnaissanceAst r, String q) {
  final requete = '${r.parametres['acte']}';
  final ref = ReferentielTarifs(cx.col('tarifs'), cx.col('versionsTarif'));
  var cands = [for (final t in ref.tarifs) if (_correspond('${t['libelle'] ?? ''}', requete)) t];
  final exacts = [for (final t in cands) if (_exact('${t['libelle']}', requete)) t];
  if (exacts.length == 1) cands = exacts;
  const src = [SourceAst('cfg-tarifs', 'versionsTarif')];
  if (cands.isEmpty) return _vide('I06', 'Aucun acte « $requete »', const [], src);
  if (cands.length > 1) {
    return ReponseAst(statut: 'ambigue', code: 'HOMONYMES', intention: 'I06', titre: '${cands.length} actes correspondent à « $requete »',
        lignes: ['Précisez lequel : ${cands.take(6).map((t) => t['libelle']).join(' ; ')}.'], sources: src);
  }
  final t = cands.first;
  final v = ref.versionsDe('${t['code']}');
  if (v.isEmpty) return _vide('I06', '${t['libelle']} — aucune version enregistrée', const [], src);
  return _rep('I06', '${t['libelle']} — ${v.length} version(s) de prix', [
    if (v.length == 1) 'Un seul prix a été enregistré : aucun changement depuis.',
  ], src,
      tableau: TableauAst(['Version', 'Effet', 'Non assuré', 'Assuré', 'État'], [
        for (final x in v)
          ['${x['version']}', _d(x['dateEffet']), _prix(nombreOuNul(x['prixNonAssure'])), x['etatAssure'] == 'nc' ? 'non couvert' : (x['etatAssure'] == 'unique' ? 'identique' : _prix(nombreOuNul(x['prixAssure']))), '${x['statut']}${x['provisoire'] == true ? ' (provisoire)' : ''}']
      ]));
}

ReponseAst _i18(ContexteAst cx, ReconnaissanceAst r, String q) {
  final types = cx.col('typesPiece');
  final texte = astNormaliser(q);
  final cands = [
    for (final t in types)
      if (texte.contains(astNormaliser('${t['libelle'] ?? ''}')) || _correspond('${t['libelle'] ?? ''}', texte.replaceAll(RegExp(r'\b(combien|coute|prix|tarif|un|une|le|la|de|du|d|certificat|attestation|quel|est|que)\b'), ' ').trim().isEmpty ? '__' : texte.replaceAll(RegExp(r'\b(combien|coute|prix|tarif|un|une|le|la|de|du|d|certificat|attestation|quel|est|que)\b'), ' ').trim())) t
  ];
  const src = [SourceAst('cfg-types-piece', 'typesPiece'), SourceAst('cfg-tarifs', 'tarifs')];
  final ref = ReferentielTarifs(cx.col('tarifs'), cx.col('versionsTarif'));
  final jour = _jourVise(r, cx);
  Iterable<Map<String, Object?>> choisis = cands;
  if (cands.isEmpty) choisis = types;
  final lignes = <String>[];
  final rows = <List<String>>[];
  for (final t in choisis.take(cands.isEmpty ? 20 : 6)) {
    final res = ref.aLaDate(t['tarifCode'], jour, false, aujourdhui: cx.jour);
    rows.add(['${t['sigle']} — ${t['libelle']}', res.absent ? '— (aucun prix en vigueur)' : _prix(res.montant)]);
  }
  lignes.add(cands.isEmpty ? 'Aucun type de pièce ne porte ce nom : voici tous les types de pièce et leur prix.' : 'Prix non assuré (guichet).');
  lignes.add('Les certificats ne sont couverts que par SOS ; toute autre compagnie : à la charge du patient.');
  lignes.add('Consultation du prix seulement : la délivrance se fait à l’écran des pièces.');
  if (rows.isEmpty) return _vide('I18', 'Aucun type de pièce enregistré', const [], src);
  return _rep('I18', cands.length == 1 ? '${cands.first['libelle']} — prix' : 'Prix des certificats et attestations', lignes, src, tableau: TableauAst(['Pièce', 'Prix'], rows));
}

// ----------------------------------------------------------------------------------------------------------------------------------------------------
// Stocks
// ----------------------------------------------------------------------------------------------------------------------------------------------------

ReponseAst _i07(ContexteAst cx, ReconnaissanceAst r, String q) {
  final requete = '${r.parametres['article']}';
  final produits = cx.col('produits');
  var cands = [for (final p in produits) if (_correspond('${p['designation'] ?? ''}', requete)) p];
  final exacts = [for (final p in cands) if (_exact('${p['designation']}', requete)) p];
  if (exacts.length == 1) cands = exacts;
  const src = [SourceAst('m6-produits', 'produits'), SourceAst('m6-lots', 'lots')];
  if (cands.isEmpty) return _vide('I07', 'Aucun article « $requete »', const ['Rien dans le référentiel des articles ne porte ce nom : je n’en propose pas un voisin.'], src);
  if (cands.length > 1) {
    return ReponseAst(statut: 'ambigue', code: 'HOMONYMES', intention: 'I07', titre: '${cands.length} articles correspondent à « $requete »',
        lignes: ['Précisez lequel : ${cands.take(6).map((p) => p['designation']).join(' ; ')}${cands.length > 6 ? ' …' : ''}.'], sources: src);
  }
  final p = cands.first;
  final seuil = p['seuilAlerte'];
  final lignes = <String>[
    'Stock total : ${p['stock'] ?? 0} ${p['unite'] ?? ''}'.trim(),
    if (p['stockGros'] != null) 'Magasin (gros) : ${p['stockGros']} ; détail : ${p['stockDetail'] ?? 0}',
    seuilFixe(seuil) ? 'Seuil d’alerte : $seuil — état : ${etatStock(p['stock'], seuil)}' : 'Seuil d’alerte : non fixé (aucune alerte possible sur cet article).',
    if (p['emplacement'] != null && '${p['emplacement']}'.isNotEmpty) 'Emplacement : ${p['emplacement']}',
  ];
  var tableau;
  if (cx.peutVoirEcran('m6-lots')) {
    final lots = ordreFefo([for (final l in cx.col('lots')) if (l['produitId'] == p['id']) l]);
    lignes.add(lots.isEmpty ? 'Aucun lot avec du stock (ordre FEFO sans objet).' : 'Ordre de sortie FEFO (RG-05) : le premier lot est celui qui périme le plus tôt.');
    if (lots.isNotEmpty) {
      tableau = TableauAst(['Rang', 'Lot', 'Péremption', 'Quantité'], [
        for (var i = 0; i < lots.length && i < 8; i++) ['${i + 1}', '${lots[i]['numeroLot']}', _d(lots[i]['datePeremption']), '${lots[i]['quantiteRestante']}']
      ]);
    }
  } else {
    lignes.add(_nonLu(['m6-lots'], cx));
  }
  return _rep('I07', '${p['designation']} — ${p['stock'] ?? 0} en stock', lignes, src, tableau: tableau);
}

ReponseAst _i08(ContexteAst cx, ReconnaissanceAst r, String q) {
  final produits = cx.col('produits');
  final ruptures = [for (final p in produits) if (nombreOuZero(p['stock']) == 0) p];
  final sous = [for (final p in produits) if (nombreOuZero(p['stock']) > 0 && seuilFixe(p['seuilAlerte']) && sousSeuil(p['stock'], p['seuilAlerte'])) p];
  final sansSeuil = [for (final p in produits) if (!seuilFixe(p['seuilAlerte'])) p];
  final src = [const SourceAst('m6-alertes', 'produits'), if (cx.peutVoirEcran('m6-lots')) const SourceAst('m6-lots', 'lots')];
  final horizon = (_periodeDe(r)?['type'] == 'horizon_mois') ? (_periodeDe(r)!['n'] as int) * 30 : delaiPreavisPeremption;
  final lignes = <String>[
    '${ruptures.length} article(s) en rupture (stock nul)${ruptures.isEmpty ? '.' : ' : ${ruptures.take(6).map((p) => p['designation']).join(', ')}${ruptures.length > 6 ? '…' : ''}.'}',
    '${sous.length} article(s) sous leur seuil d’alerte, hors rupture${sous.isEmpty ? '.' : ' : ${sous.take(6).map((p) => '${p['designation']} (${p['stock']}/${p['seuilAlerte']})').join(', ')}${sous.length > 6 ? '…' : ''}.'}',
    if (sansSeuil.isNotEmpty) '${sansSeuil.length} article(s) sans seuil fixé : ils ne peuvent pas être « sous le seuil » et sont comptés à part.',
  ];
  if (cx.peutVoirEcran('m6-lots')) {
    final auj = cx.maintenant;
    final proches = <(int, Map<String, Object?>)>[];
    for (final l in cx.col('lots')) {
      if (nombreOuZero(l['quantiteRestante']) <= 0) continue;
      final j = joursAvantPeremption(auj, l['datePeremption']);
      if (j != null && j <= horizon) proches.add((j, l));
    }
    proches.sort((a, b) => a.$1.compareTo(b.$1));
    lignes.add('${proches.length} lot(s) périmé(s) ou périmant dans $horizon jours${proches.isEmpty ? '.' : ' : ${proches.take(5).map((x) => '${x.$2['produit']} lot ${x.$2['numeroLot']} (${x.$1 < 0 ? 'périmé' : 'dans ${x.$1} j'})').join(', ')}${proches.length > 5 ? '…' : ''}.'}');
  } else {
    lignes.add(_nonLu(['m6-lots'], cx));
  }
  if (ruptures.isEmpty && sous.isEmpty && sansSeuil.isEmpty && lignes.length == 3) return _vide('I08', 'Aucune alerte de stock', lignes, src);
  return _rep('I08', 'Alertes de stock', lignes, src);
}

ReponseAst _i09(ContexteAst cx, ReconnaissanceAst r, String q) {
  final pl = _plage(_periodeDe(r), cx, joursParDefaut: 30);
  final sorties = [for (final m in cx.col('mouvements')) if (m['type'] == 'sortie' && _dans(m['date'], pl.debut, pl.fin)) m];
  const src = [SourceAst('m6-mouvements', 'mouvements')];
  final parProduit = <String, num>{};
  final noms = <String, String>{};
  for (final m in sorties) {
    final k = '${m['produitId']}';
    parProduit[k] = (parProduit[k] ?? 0) + nombreOuZero(m['quantite']);
    noms[k] = '${m['produit'] ?? k}';
  }
  final texte = astNormaliser(q);
  final dormants = texte.contains('bouge') || texte.contains('sans sortie') || texte.contains('ne sortent plus') || texte.contains('dormants') || texte.contains('tourne pas') || texte.contains('tournent pas');
  if (dormants) {
    final ids = parProduit.keys.toSet();
    final fixes = [for (final p in cx.col('produits')) if (nombreOuZero(p['stock']) > 0 && !ids.contains('${p['id']}')) p];
    if (fixes.isEmpty) return _vide('I09', 'Aucun article immobile ${pl.libelle}', const ['Tous les articles en stock ont eu au moins une sortie sur la période.'], src);
    return _rep('I09', '${fixes.length} article(s) en stock sans aucune sortie ${pl.libelle}', [
      'Définition PROPOSÉE : « ne tourne plus » = du stock et aucune sortie sur la période (aucun document ne la fixe).',
      fixes.take(10).map((p) => '${p['designation']}').join(' ; ') + (fixes.length > 10 ? ' …' : ''),
    ], src);
  }
  if (sorties.isEmpty) return _vide('I09', 'Aucune sortie de stock ${pl.libelle}', const [], src);
  final n = (r.parametres['topN'] as int?) ?? 10;
  final tries = parProduit.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return _rep('I09', 'Les $n articles les plus sortis ${pl.libelle}', ['${sorties.length} mouvement(s) de sortie lus.'], src,
      tableau: TableauAst(['Rang', 'Article', 'Quantité sortie'], [for (var i = 0; i < tries.length && i < n; i++) ['${i + 1}', noms[tries[i].key]!, '${tries[i].value}']]));
}

ReponseAst _i10(ContexteAst cx, ReconnaissanceAst r, String q) {
  final produits = cx.col('produits');
  const src = [SourceAst('m6-point-stock', 'produits')];
  if (produits.isEmpty) return _vide('I10', 'Aucun article au stock', const [], src);
  final par = <String, List<Map<String, Object?>>>{};
  for (final p in produits) {
    (par['${p['categorie'] ?? 'autre'}'] ??= []).add(p);
  }
  final total = valeurStock(produits);
  final prov = produits.where((p) => p['valorisationProvisoire'] == true).length;
  return _rep('I10', 'Valeur du stock au CUMP : ${money(total)}', [
    '${produits.length} références valorisées (quantité × CUMP).',
    if (prov > 0) '$prov référence(s) valorisée(s) à titre PROVISOIRE (valeur d’attente à confirmer par la Direction).',
    'Aucun axe de secteur n’existe au magasin : la ventilation est par catégorie d’article.',
  ], src, tableau: TableauAst(['Catégorie', 'Références', 'Valeur'], [for (final e in par.entries) [libelleCategorie(e.key), '${e.value.length}', money(valeurStock(e.value))]]));
}

ReponseAst _i11(ContexteAst cx, ReconnaissanceAst r, String q) {
  final inv = [...cx.col('inventaires')]..sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));
  const src = [SourceAst('m6-inventaire', 'inventaires')];
  if (inv.isEmpty) return _vide('I11', 'Aucun inventaire enregistré', const [], src);
  final d = inv.first;
  final ecarts = [for (final l in ((d['lignes'] as List?) ?? const [])) if (l is Map && nombreOuZero(l['ecart']) != 0) l];
  return _rep('I11', 'Dernier inventaire : ${d['reference']} du ${_d(d['date'])}', [
    'Type : ${d['type'] ?? '—'} ; magasin : ${d['magasinLabel'] ?? d['magasin'] ?? '—'} ; état : ${d['statutInv'] ?? '—'}.',
    '${d['nbArticles'] ?? '—'} article(s) comptés, ${d['nbEcarts'] ?? ecarts.length} écart(s), valeur des écarts : ${money(d['valeurEcart'])}.',
  ], src,
      tableau: ecarts.isEmpty
          ? null
          : TableauAst(['Article', 'Théorique', 'Physique', 'Écart'], [for (final l in ecarts.take(10)) ['${l['designation']}', '${l['theorique']}', '${l['physique']}', '${l['ecart']}']]));
}

// ----------------------------------------------------------------------------------------------------------------------------------------------------
// Achats
// ----------------------------------------------------------------------------------------------------------------------------------------------------

ReponseAst _i12(ContexteAst cx, ReconnaissanceAst r, String q) {
  final requete = '${r.parametres['fournisseur']}';
  final fs = [for (final f in cx.col('fournisseurs')) if (_correspond('${f['nom'] ?? ''} ${f['code'] ?? ''}', requete)) f];
  const src = [SourceAst('m7-fournisseurs', 'fournisseurs')];
  if (fs.isEmpty) return _vide('I12', 'Aucun fournisseur « $requete »', const [], src);
  if (fs.length > 1) {
    return ReponseAst(statut: 'ambigue', code: 'HOMONYMES', intention: 'I12', titre: '${fs.length} fournisseurs correspondent à « $requete »',
        lignes: ['Précisez lequel : ${fs.take(6).map((f) => f['nom']).join(' ; ')}.'], sources: src);
  }
  final f = fs.first;
  final lignes = <String>[
    '${f['nom']} (${f['code']}) — ${f['type'] ?? '—'}, ${f['ville'] ?? '—'}.',
    'Téléphone : ${'${f['tel'] ?? ''}'.isEmpty ? 'non renseigné' : f['tel']}.',
    if (f['delai'] != null) 'Délai de livraison habituel : ${f['delai']} jours.',
  ];
  final sources = [...src];
  final non = <String>[];
  if (cx.peutVoirEcran('m7-commandes')) {
    sources.add(const SourceAst('m7-commandes', 'commandes'));
    final c = [for (final x in cx.col('commandes')) if (x['fournisseur'] == f['code']) x];
    final par = <String, int>{};
    for (final x in c) {
      par['${x['statutCommande']}'] = (par['${x['statutCommande']}'] ?? 0) + 1;
    }
    lignes.add('${c.length} commande(s)${par.isEmpty ? '.' : ' : ${par.entries.map((e) => '${e.value} ${e.key}').join(', ')}.'}');
  } else {
    non.add('m7-commandes');
  }
  if (cx.peutVoirEcran('m7-factures-fournisseurs')) {
    sources.add(const SourceAst('m7-factures-fournisseurs', 'facturesFournisseurs'));
    final due = [for (final x in cx.col('facturesFournisseurs')) if (x['fournisseur'] == f['code'] && x['statutPaiement'] != 'payee') x];
    final dette = due.fold<num>(0, (a, x) => a + nombreOuZero(x['montantFacture']));
    lignes.add(due.isEmpty ? 'Dette ouverte : aucune facture fournisseur non soldée.' : 'Dette ouverte : ${money(dette)} sur ${due.length} facture(s) non soldée(s).');
  } else {
    non.add('m7-factures-fournisseurs');
  }
  if (non.isNotEmpty) lignes.add(_nonLu(non, cx));
  return _rep('I12', '${f['nom']}', lignes, sources);
}

ReponseAst _i13(ContexteAst cx, ReconnaissanceAst r, String q) {
  final cmds = cx.col('commandes');
  const src = [SourceAst('m7-commandes', 'commandes')];
  final att = [for (final c in cmds) if (c['statutCommande'] == 'attente_validation') c];
  final val = [for (final c in cmds) if (c['valideePar'] != null && '${c['valideePar']}'.isNotEmpty) c]..sort((a, b) => '${b['dateValidation']}'.compareTo('${a['dateValidation']}'));
  final lignes = [
    if (val.isNotEmpty) 'Dernières validations (RG-04, Directrice Administrative) : ${val.take(3).map((c) => '${c['reference']} par ${c['valideePar']} le ${_d(c['dateValidation'])}').join(' ; ')}.',
  ];
  if (att.isEmpty) return _vide('I13', 'Aucune commande n’attend de validation', lignes, src);
  return _rep('I13', '${att.length} commande(s) en attente de validation', lignes, src,
      tableau: TableauAst(['Commande', 'Fournisseur', 'Date', 'Montant'], [for (final c in att.take(10)) ['${c['reference'] ?? '—'}', '${c['fournisseurNom'] ?? c['fournisseur']}', _d(c['date']), money(c['montant'])]]));
}

// ----------------------------------------------------------------------------------------------------------------------------------------------------
// Documents, laboratoire
// ----------------------------------------------------------------------------------------------------------------------------------------------------

ReponseAst _i17(ContexteAst cx, ReconnaissanceAst r, String q) {
  final u = _unPatient(cx, r, 'I17');
  if (u.reponse != null) return u.reponse!;
  final p = u.patient!;
  final src = <SourceAst>[_srcPatients];
  final lignes = <String>[];
  final rows = <List<String>>[];
  final non = <String>[];
  if (cx.peutVoirEcran('m2-ordonnances')) {
    src.add(const SourceAst('m2-ordonnances', 'ordonnances'));
    if (cx.sensible('notes_consultation')) {
      for (final o in cx.col('ordonnances')) {
        if (_duPatient(o, p)) rows.add(['Ordonnance', '${o['numero']}', _d(o['date'])]);
      }
    } else {
      lignes.add(mentionReservee('notes_consultation'));
    }
  } else {
    non.add('m2-ordonnances');
  }
  if (cx.peutVoirEcran('m1-pieces')) {
    src.add(const SourceAst('m1-pieces', 'pieces'));
    for (final o in cx.col('pieces')) {
      if (_duPatient(o, p)) rows.add(['${o['libelle']}', '${o['reference']}', _d(o['dateDelivrance'])]);
    }
  } else {
    non.add('m1-pieces');
  }
  if (non.isNotEmpty) lignes.add(_nonLu(non, cx));
  rows.sort((a, b) => b[2].split('/').reversed.join().compareTo(a[2].split('/').reversed.join()));
  if (rows.isEmpty) return _vide('I17', '${p['code']} — aucune ordonnance ni pièce', lignes, src);
  return _rep('I17', '${p['code']} — ${rows.length} document(s)', ['Les documents numérisés du dossier suivent leur propre droit et ne sont pas lus ici.', ...lignes], src,
      tableau: TableauAst(['Nature', 'Référence', 'Date'], rows.take(12).toList()));
}

ReponseAst _i19(ContexteAst cx, ReconnaissanceAst r, String q) {
  final codeAn = r.parametres['codeAnalyse'] as String?;
  const src = [SourceAst('m5-demandes', 'demandesAnalyses')];
  List<Map<String, Object?>> demandes;
  String titre;
  if (codeAn != null && !r.parametres.containsKey('codePatient') && !r.parametres.containsKey('nomPatient')) {
    demandes = [for (final d in cx.col('demandesAnalyses')) if (d['codeAnalyse'] == codeAn) d];
    titre = 'Demande $codeAn';
    if (demandes.isEmpty) return _vide('I19', 'Aucune demande portant le code $codeAn', const [], src);
  } else {
    final u = _unPatient(cx, r, 'I19');
    if (u.reponse != null) return u.reponse!;
    final p = u.patient!;
    demandes = [for (final d in cx.col('demandesAnalyses')) if (_duPatient(d, p) && (codeAn == null || d['codeAnalyse'] == codeAn)) d]
      ..sort((a, b) => '${b['dateHeure']}'.compareTo('${a['dateHeure']}'));
    titre = '${p['code']} — demandes d’analyses';
    if (demandes.isEmpty) return _vide('I19', '${p['code']} — aucune demande d’analyse', const [], src);
  }
  final rows = <List<String>>[];
  var masques = 0;
  for (final d in demandes.take(10)) {
    final e = etatResultat(d['etatAnalyse']);
    var resultat = 'pas encore rendu';
    if (resultatRendu('${d['etatAnalyse']}')) {
      final v = peutVoirResultat(d, cx.session);
      if (v.autorise && cx.sensible('resultats_analyses')) {
        resultat = 'rendu : à lire à l’écran Résultats (les valeurs ne sont pas recopiées ici)';
      } else {
        masques++;
        resultat = 'non montré — ${v.autorise ? mentionReservee('resultats_analyses') : v.motif}';
      }
    } else if (!cx.sensible('resultats_analyses')) {
      resultat = 'non montré — ${mentionReservee('resultats_analyses')}';
    }
    rows.add(['${d['codeAnalyse'] ?? d['reference']}', '${d['analyse'] ?? '—'}', e.label, resultat]);
  }
  return _rep('I19', titre, [
    '${demandes.length} demande(s)${demandes.length > 10 ? ' (10 plus récentes affichées)' : ''}. Seuls les résultats RENDUS (validés biologiquement) sont lisibles, sous vos habilitations.',
    if (masques > 0) '$masques résultat(s) rendu(s) non montré(s) à votre profil.',
  ], src, tableau: TableauAst(['Code', 'Analyse', 'État', 'Résultat'], rows));
}

// ----------------------------------------------------------------------------------------------------------------------------------------------------
// RH, pilotage, système
// ----------------------------------------------------------------------------------------------------------------------------------------------------

ReponseAst _i20(ContexteAst cx, ReconnaissanceAst r, String q) {
  final jour = _jourVise(r, cx);
  const src = [SourceAst('m10-planning', 'planning')];
  final lignes = [
    for (final l in cx.col('planning'))
      if (l['statut'] == 'validee' && _jour10(l['date']) == jour && const ['garde', 'garde_soins', 'permanence'].contains(l['type'])) l
  ];
  if (lignes.isEmpty) {
    return _vide('I20', 'Aucune garde posée au planning validé le ${_d(jour)}', const ['Un jour sans ligne ne veut pas dire « personne » : le planning n’y a rien posé, ou ne l’a pas encore validé.'], src);
  }
  return _rep('I20', 'Garde et permanence du ${_d(jour)}', ['Planning VALIDÉ uniquement.'], src,
      tableau: TableauAst(['Agent', 'Type', 'Service'], [for (final l in lignes) ['${l['employe'] ?? '—'}', '${l['type']}', '${l['service'] ?? '—'}']]));
}

ReponseAst _i21(ContexteAst cx, ReconnaissanceAst r, String q) {
  final jour = _jourVise(r, cx);
  final src = <SourceAst>[];
  final rows = <List<String>>[];
  final non = <String>[];
  void ligne(String ecran, String col, String libelle, int Function(List<Map<String, Object?>>) f) {
    if (!cx.peutVoirEcran(ecran)) {
      non.add(ecran);
      return;
    }
    src.add(SourceAst(ecran, col));
    rows.add([libelle, '${f(cx.col(col))}']);
  }

  ligne('m2-consultations', 'consultations', 'Consultations', (l) => l.where((c) => _jour10(c['date']) == jour).length);
  ligne('m3-admissions', 'admissions', 'Admissions du jour', (l) => l.where((c) => _jour10(c['dateEntree']) == jour).length);
  ligne('m3-admissions', 'admissions', 'Admissions en cours', (l) => l.where((c) => c['statut'] == 'en_cours').length);
  ligne('m5-demandes', 'demandesAnalyses', 'Demandes d’analyses', (l) => l.where((c) => _jour10(c['dateHeure']) == jour).length);
  ligne('m8-factures', 'factures', 'Factures émises', (l) => l.where((c) => _jour10(c['date']) == jour).length);
  if (rows.isEmpty) return _refusLecture('I21', 'Aucun indicateur dans votre périmètre', [_nonLu(non, cx)]);
  return _rep('I21', 'Indicateurs du ${_d(jour)}', [if (non.isNotEmpty) _nonLu(non.toSet().toList(), cx), 'Un compte à 0 est un compte lu : un écran hors périmètre n’est jamais compté pour zéro.'], src.toSet().toList(), tableau: TableauAst(['Indicateur', 'Valeur'], rows));
}

ReponseAst _i22(ContexteAst cx, ReconnaissanceAst r, String q) {
  final notes = cx.col('notifications');
  final nonLues = [for (final n in notes) if (n['lue'] != true) n];
  final lignes = <String>[];
  final sync = cx.etatSynchro?.call();
  lignes.add(sync == null ? 'État de la synchronisation : l’assistant ne le lit pas (il appartient au poste : voir l’écran de supervision).' : 'Synchronisation : $sync');
  if (notes.isEmpty) return ReponseAst(statut: 'pas_de_donnees', code: 'AUCUN_RESULTAT', intention: 'I22', titre: 'Aucune notification enregistrée', lignes: lignes, sources: const [SourceAst('cfg-notifications', 'notifications')]);
  final par = <String, int>{};
  for (final n in nonLues) {
    par['${n['poste'] ?? 'général'}'] = (par['${n['poste'] ?? 'général'}'] ?? 0) + 1;
  }
  return _rep('I22', '${nonLues.length} notification(s) non lue(s)', [
    ...lignes,
    'Le détail (patients, montants) reste au centre de notifications, sous vos droits : il n’est pas recopié ici.',
  ], const [SourceAst('cfg-notifications', 'notifications')], tableau: par.isEmpty ? null : TableauAst(['Poste', 'Non lues'], [for (final e in par.entries) [e.key, '${e.value}']]));
}

ReponseAst _i23(ContexteAst cx, ReconnaissanceAst r, String q) {
  final t = astNormaliser(q);
  final cibles = <(List<String>, String, String)>[
    (['recette', 'chiffre d affaires', 'encaisse'], 'm8-recettes', 'Recettes'),
    (['stock'], 'm6-point-stock', 'Point de stock'),
    (['vente'], 'm6-point-ventes', 'Point des ventes'),
    (['creance', 'impaye'], 'm9-creances', 'Créances'),
    (['inventaire'], 'm6-inventaire', 'Inventaires'),
    (['balance', 'grand livre'], 'm12-balance', 'Balance générale'),
    (['bulletin', 'paie'], 'm11-bulletins', 'Bulletins de paie'),
    (['bilan', 'compte de resultat'], 'm12-compte-resultat', 'Compte de résultat'),
    (['facture'], 'm8-factures', 'Factures'),
  ];
  var ecran = 'rapports-bibliotheque';
  var nom = 'Bibliothèque des états';
  for (final c in cibles) {
    if (c.$1.any(t.contains)) {
      ecran = c.$2;
      nom = c.$3;
      break;
    }
  }
  if (!cx.peutVoirEcran(ecran)) {
    return _refusLecture('I23', 'L’état « $nom » n’est pas dans votre périmètre', ['Le droit d’un état est celui de son écran (${cx.ecran(ecran)}).']);
  }
  final gabarit = r.parametres['gabarit'];
  return ReponseAst(
      statut: 'reponse', intention: 'I23', titre: 'L’état est à l’écran « ${cx.ecran(ecran)} »',
      lignes: ['Je n’imprime rien moi-même : ouvrez l’écran, réglez les filtres, puis imprimez depuis l’écran.', if (gabarit != null) 'Gabarit demandé : ${gabarit == 'rouleau80' ? 'rouleau 80 mm' : 'A4'} (choix fait à l’impression).'],
      sources: [SourceAst(ecran, '—')], ecranRenvoi: ecran);
}

String _heure(Map<String, Object?> x) {
  final h = '${x['heure'] ?? ''}';
  if (h.isNotEmpty) return h;
  final dh = '${x['dateHeure'] ?? ''}';
  return dh.length >= 16 ? dh.substring(11, 16) : '—';
}

ReponseAst _i24(ContexteAst cx, ReconnaissanceAst r, String q) {
  final jour = _jourVise(r, cx);
  final rdv = [for (final x in cx.col('rendezvous')) if (_jour10(x['date'] ?? x['dateHeure']) == jour) x];
  final file = cx.col('fileAttente');
  final src = [const SourceAst('m2-agenda', 'rendezvous'), if (cx.peutVoirEcran('m2-file-attente')) const SourceAst('m2-file-attente', 'fileAttente')];
  final lignes = <String>[
    if (cx.peutVoirEcran('m2-file-attente')) (file.isEmpty ? 'File d’attente : aucun enregistrement (ce n’est pas « personne n’attend » : le registre est vide).' : 'File d’attente : ${file.length} enregistrement(s).') else _nonLu(['m2-file-attente'], cx),
  ];
  if (rdv.isEmpty) return _vide('I24', 'Aucun rendez-vous enregistré le ${_d(jour)}', lignes, src);
  return _rep('I24', '${rdv.length} rendez-vous le ${_d(jour)}', lignes, src,
      tableau: TableauAst(['Heure', 'Patient', 'Statut'], [for (final x in rdv.take(15)) [_heure(x), '${x['patient'] ?? x['visiteurNom'] ?? '—'}', '${x['statut'] ?? '—'}']]));
}

ReponseAst _i25(ContexteAst cx, ReconnaissanceAst r, String q) {
  final jour = cx.jour;
  const src = [SourceAst('m12-echeances', 'echeancesFiscales')];
  final toutes = cx.col('echeancesFiscales');
  if (toutes.isEmpty) return _vide('I25', 'Aucune échéance fiscale enregistrée', const [], src);
  final impayees = [for (final e in toutes) if (e['paye'] != true) e];
  final retard = [for (final e in impayees) if ('${e['echeance']}'.compareTo(jour) < 0) e]..sort((a, b) => '${a['echeance']}'.compareTo('${b['echeance']}'));
  final avenir = [for (final e in impayees) if ('${e['echeance']}'.compareTo(jour) >= 0) e]..sort((a, b) => '${a['echeance']}'.compareTo('${b['echeance']}'));
  final texte = astNormaliser(q);
  final veutRetard = texte.contains('retard') || texte.contains('depasse');
  final rows = [for (final e in (veutRetard ? retard : [...retard.take(3), ...avenir]).take(8)) ['${e['libelle']}', '${e['periode'] ?? '—'}', _d(e['echeance']), '${e['echeance']}'.compareTo(jour) < 0 ? 'en retard' : 'à venir']];
  return _rep('I25', '${retard.length} échéance(s) en retard, ${avenir.length} à venir', [
    'Une échéance est « en retard » quand sa date est passée et qu’elle n’est pas payée. Les échéances tombant un week-end sont déjà reportées au jour ouvrable suivant.',
  ], src, tableau: TableauAst(['Échéance', 'Période', 'Date', 'État'], rows));
}

/// Les exécuteurs, par identifiant d'intention. Une intention du catalogue sans exécuteur ici n'est PAS livrée (le moteur la dit « indisponible »).
const Map<String, ExecuteurAst> executeursAst = {
  'I01': _i01, 'I02': _i02, 'I03': _i03, 'I04': _i04, 'I05': _i05, 'I06': _i06, 'I07': _i07, 'I08': _i08, 'I09': _i09, 'I10': _i10, 'I11': _i11, 'I12': _i12,
  'I13': _i13, 'I14': _i14, 'I15': _i15, 'I16': _i16, 'I17': _i17, 'I18': _i18, 'I19': _i19, 'I20': _i20, 'I21': _i21, 'I22': _i22, 'I23': _i23, 'I24': _i24, 'I25': _i25,
};
