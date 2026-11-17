/// LES EXÉCUTEURS : un par intention. Chacun LIT le magasin par [ContexteAst.col] (fiches gelées, archivées écartées) et rend une [ReponseAst] qui CITE ses sources.
/// Aucun exécuteur n'écrit : le contexte ne porte aucune fonction d'écriture, et les fiches lues sont non modifiables.
///
/// Règles de toutes les réponses :
///  * jamais d'invention : une lecture vide se dit (`pas_de_donnees`), une donnée non renseignée se dit (`non_calculable`), un champ masqué par catégorie sensible
///    porte la mention réservée — jamais un trou qui se lirait comme une donnée absente ;
///  * un « homonyme » n'est jamais tranché : la liste est rendue, pas la première ;
///  * les sous-sources (un second écran, une seconde collection) ne sont lues que si l'agent voit leur écran, et la réponse nomme ce qu'elle n'a pas lu.
library;

import '../achats/factures_fournisseurs.dart' show detteFournisseurAValider, detteFournisseurOuverte;
import '../administration/adm_regles.dart' show admDisponibilite, admOrdreAppelRapide, admPerime;
import '../comptabilite/cpa_plan.dart' show cpaPlanComptable;
import '../droits/gestes_reserves.dart' show gesteReserve, gesteValiderAchats;
import '../imagerie/cr_moteur.dart' show modaliteDeCodeExamen;
import '../imagerie/img_demandes_etats.dart' show etatImagerie;
import '../paie/pai_moteur.dart' show PaiEntrees, paiActivites, paiCalculerTous;
import '../rh/espace_mes.dart' show agentDeMes;
import '../droits/donnees_sensibles.dart' show mentionReservee;
import '../pilotage/pil_stats.dart' show statutsRdvAVenir;
import '../parametres/parametres_clinique.dart' show bornesBalanceAgeePatientA, delaiPreavisPeremptionA, joursArticlesImmobilesA, seuilEntierA, tranchesBalanceAgeePatient;
import '../format/format_fr.dart' show money, nombreOuNul;
import '../format/js.dart' show nombreOuZero;
import '../labo/res_etats.dart' show etatResultat;
import '../labo/res_habilitations.dart' show peutVoirResultat;
import '../caisse/prise_en_charge.dart' show carteValide, couvertureALaDate;
import '../referentiels/regles.dart' show lireCodePatient, resultatRendu;
import '../stock/stock.dart' show etatStock, joursAvantPeremption, libelleCategorie, ordreFefo, seuilFixe, sousSeuil, valeurStock;
import '../tarifs/tarifs.dart' show ReferentielTarifs;
import 'ast_catalogue.dart' show refusAst;
import 'ast_contexte.dart';
import 'ast_reconnaissance.dart';
import 'ast_stock_date.dart';
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

/// La date d'un ÉTAT (un stock) : le jour visé, ou la FIN d'une période passée (« fin septembre », « le mois dernier ») ; sinon aujourd'hui.
String _dateEtat(ReconnaissanceAst r, ContexteAst cx) {
  final p = _periodeDe(r);
  if (p == null || p['debut'] == null || p['type'] == 'anciennete_jours') return cx.jour;
  final fin = '${p['fin'] ?? p['debut']}';
  return fin.compareTo(cx.jour) < 0 ? fin : cx.jour;
}

/// La période dite, sinon la SEMAINE en cours (lundi au dimanche) : réunions, congés.
({String debut, String fin, String libelle}) _plageSemaine(ReconnaissanceAst r, ContexteAst cx) {
  final p = _periodeDe(r);
  if (p != null && p['debut'] != null && p['type'] != 'anciennete_jours') return _plage(p, cx, joursParDefaut: 0);
  final j = DateTime.utc(cx.maintenant.year, cx.maintenant.month, cx.maintenant.day);
  final lundi = j.subtract(Duration(days: j.weekday - 1));
  final d = astIso(lundi), f = astIso(lundi.add(const Duration(days: 6)));
  return (debut: d, fin: f, libelle: 'la semaine du ${_d(d)} au ${_d(f)}');
}

/// La période dite, sinon le MOIS en cours : balance des comptes, masse salariale.
({String debut, String fin, String libelle}) _plageMois(ReconnaissanceAst r, ContexteAst cx) {
  final p = _periodeDe(r);
  if (p != null && p['debut'] != null && p['type'] != 'anciennete_jours') return _plage(p, cx, joursParDefaut: 0);
  final d = astIso(DateTime.utc(cx.maintenant.year, cx.maintenant.month, 1)), f = astIso(DateTime.utc(cx.maintenant.year, cx.maintenant.month + 1, 0));
  return (debut: d, fin: f, libelle: 'le mois du ${_d(d)} au ${_d(f)}');
}

String _q(num? v) => v == null ? '—' : (v == v.truncate() ? '${v.toInt()}' : '$v');

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
  // Dernière visite (Q8, décision du 15/11/2026) : le MAXIMUM des dates de consultation, d'admission et de facture, sur les seules sources que l'agent lit.
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
      // Un rendez-vous planifié, reporté ou non honoré n'est pas une visite (le registre des consultations les porte aussi) : seule une consultation TENUE compte.
      if (col == 'consultations' && (statutsRdvAVenir.contains(f['statut']) || f['statut'] == 'non_honore')) continue;
      if (_duPatient(f, p) && '${f[champ] ?? ''}'.isNotEmpty) dates.add((_jour10(f[champ]), nom));
    }
  }

  vue('m2-consultations', 'consultations', 'date', 'consultation');
  vue('m3-admissions', 'admissions', 'dateEntree', 'admission');
  vue('m8-factures', 'factures', 'date', 'facture');
  dates.sort((a, b) => b.$1.compareTo(a.$1));
  lignes.add(dates.isEmpty
      ? 'Dernière visite : aucune trace dans les sources que vous lisez.'
      : 'Dernière visite connue : ${_d(dates.first.$1)} (${dates.first.$2}). Définition arrêtée par la Direction : la plus récente des dates de consultation, d’admission et de facture que vous pouvez lire.');
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

/// Q9 (15/11/2026) puis relecture des questions d'agents (16/11/2026) : DEUX grandeurs, jamais confondues ni additionnées, et TOUJOURS données ensemble — l'ENCAISSÉ (lignes réglées,
/// date de règlement) et le FACTURÉ (montant TTC des factures, date de facture). Chacune est nommée et porte sa définition ; une grandeur vide le dit sans effacer l'autre.
ReponseAst _i14(ContexteAst cx, ReconnaissanceAst r, String q) {
  final pl = _plage(_periodeDe(r), cx, joursParDefaut: 0);
  num encaisse(String debut, String fin, Map<String, num> parType, Set<Object?> factures) {
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

  num facture(String debut, String fin, Map<String, num> parType, Set<Object?> factures) {
    var t = 0.0;
    for (final f in cx.col('factures')) {
      if (!_dans(f['date'], debut, fin)) continue;
      final m = nombreOuZero(f['montantTTC']);
      t += m;
      parType['${f['type'] ?? 'Autre'}'] = (parType['${f['type'] ?? 'Autre'}'] ?? 0) + m;
      factures.add(f['numero']);
    }
    return t;
  }

  const src = [SourceAst('m8-recettes', 'factures')];
  final cmp = _periodeDe(r, 'periodeComparee');
  final lignes = <String>[];
  final titres = <String>[];
  final parTypes = <String, Map<String, num>>{};
  var rien = true;

  void bloc(String nom, num Function(String, String, Map<String, num>, Set<Object?>) calc, String definition, String vide) {
    final parType = <String, num>{};
    final facts = <Object?>{};
    final total = calc(pl.debut, pl.fin, parType, facts);
    if (facts.isEmpty && total == 0) {
      lignes.add(vide);
      titres.add('$nom : aucun');
      return;
    }
    rien = false;
    titres.add('$nom ${pl.libelle} : ${money(total)}');
    lignes.add('$nom : ${money(total)} sur ${facts.length} facture(s). Définition : $definition');
    if (cmp != null) {
      final t2 = calc('${cmp['debut']}', '${cmp['fin']}', <String, num>{}, <Object?>{});
      lignes.add('$nom, période comparée (du ${_d(cmp['debut'])} au ${_d(cmp['fin'])}) : ${money(t2)} — écart ${money(total - t2)}.');
    }
    parTypes[nom] = parType;
  }

  bloc('Recettes (encaissé)', encaisse, 'somme des lignes réglées (`montantRegle`) dont la date de règlement tombe dans la période.',
      'Recettes (encaissé) ${pl.libelle} : aucune ligne de facture n’a été réglée sur cette période.');
  bloc('Chiffre d’affaires (facturé)', facture, 'somme du montant TTC des factures dont la date de facture tombe dans la période, réglées ou non (les avoirs se lisent à l’écran des factures).',
      'Chiffre d’affaires (facturé) ${pl.libelle} : aucune facture n’est datée de cette période.');
  lignes.add('Les deux chiffres sont donnés ENSEMBLE (décision du 16/11/2026) : ce sont deux grandeurs différentes, qui ne s’additionnent pas.');
  if (rien) return _vide('I14', 'Ni recettes ni chiffre d’affaires ${pl.libelle}', lignes, src);
  final types = <String>{for (final m in parTypes.values) ...m.keys}.toList()..sort();
  final enc = parTypes['Recettes (encaissé)'] ?? const <String, num>{};
  final fac = parTypes['Chiffre d’affaires (facturé)'] ?? const <String, num>{};
  return _rep('I14', titres.join(' ; '), lignes, src,
      tableau: TableauAst(['Type de facture', 'Encaissé', 'Facturé'], [for (final t in types) [t, enc.containsKey(t) ? money(enc[t]) : '—', fac.containsKey(t) ? money(fac[t]) : '—']]));
}

ReponseAst _i15(ContexteAst cx, ReconnaissanceAst r, String q) {
  final pl = _plage(_periodeDe(r), cx, joursParDefaut: seuilEntierA(cx.col('parametres'), 'assistant.horizonQuestionJours', cx.jour));
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
  // Q14 (décision du 15/11/2026) : les bornes de la balance âgée des patients sont un réglage de clinique (30 et 90 jours semés), jamais un littéral.
  final bornes = bornesBalanceAgeePatientA(cx.col('parametres'), cx.jour);
  final defTranches = tranchesBalanceAgeePatient(bornes.borne1, bornes.borne2);
  final tranches = <String, List<Map<String, Object?>>>{for (final t in defTranches) t.libelle: []};
  for (final f in retenues) {
    final a = age(f);
    for (final t in defTranches) {
      if (a > t.min && (t.max == null || a <= t.max!)) {
        tranches[t.libelle]!.add(f);
        break;
      }
    }
  }
  final total = retenues.fold<num>(0, (a, f) => a + nombreOuZero(f['reliquat']));
  return _rep('I16', '${retenues.length} facture(s) impayée(s) : ${money(total)}', [
    'Impayés de la PART PATIENT (reliquat), classés par ancienneté de la facture${seuil == null ? '' : ' (plus de $seuil jours)'}.',
    'Bornes de la balance âgée : ${bornes.borne1} et ${bornes.borne2} jours (réglage de clinique, valeur d’attente à valider).',
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
  final dateEtat = _dateEtat(r, cx);
  if (dateEtat.compareTo(cx.jour) < 0) return _i07ALaDate(cx, p, dateEtat);
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

/// Le stock d'UN article à une date passée, RECONSTITUÉ depuis les mouvements (décision du 16/11/2026) : sous le droit de l'écran des mouvements, qu'elle lit ; « non calculable »
/// dès que la reconstitution ne tient pas, jamais zéro.
ReponseAst _i07ALaDate(ContexteAst cx, Map<String, Object?> p, String date) {
  if (!cx.peutVoirEcran('m6-mouvements')) {
    return _refusLecture('I07', 'Le stock à une date passée lit les mouvements de stock', ['La reconstitution lit l’écran ${cx.ecran('m6-mouvements')}, hors de votre périmètre. Le stock d’aujourd’hui reste lisible.']);
  }
  const src = [SourceAst('m6-produits', 'produits'), SourceAst('m6-mouvements', 'mouvements')];
  final rec = reconstituerStockA([p], cx.col('mouvements'), date)['${p['id']}']!;
  if (!rec.fiable) {
    return ReponseAst(statut: 'non_calculable', code: 'NON_CALCULABLE', intention: 'I07', titre: '${p['designation']} — stock au ${_d(date)} : non calculable', lignes: [
      'La reconstitution depuis les mouvements ne tient pas : ${rec.motifs.take(3).join(' ; ')}${rec.motifs.length > 3 ? ' …' : ''}.',
      'Je ne donne ni zéro ni un chiffre approché. Le stock d’aujourd’hui reste lisible : ${p['stock'] ?? '—'}.',
    ], sources: src);
  }
  return _rep('I07', '${p['designation']} — ${_q(rec.total)} en stock au ${_d(date)} (reconstitué)', [
    'Stock reconstitué au ${_d(date)} au soir : stock d’aujourd’hui (${_q(nombreOuZero(p['stock']))}) moins l’effet de ${rec.mouvementsPosterieurs} mouvement(s) postérieur(s).',
    rec.gros != null ? 'Magasin (gros) : ${_q(rec.gros)} ; détail : ${_q(rec.detail)}.' : 'Répartition gros / détail : non reconstituable (un mouvement ne dit pas son magasin, ou la fiche ne porte pas la répartition) ; seul le total l’est.',
    'Méthode (décision du 16/11/2026) : stock actuel moins les mouvements postérieurs, par magasin ; un mouvement illisible, un stock incohérent ou un résultat négatif rendent la réponse « non calculable ».',
  ], src);
}

ReponseAst _i08(ContexteAst cx, ReconnaissanceAst r, String q) {
  final produits = cx.col('produits');
  final ruptures = [for (final p in produits) if (nombreOuZero(p['stock']) == 0) p];
  final sous = [for (final p in produits) if (nombreOuZero(p['stock']) > 0 && seuilFixe(p['seuilAlerte']) && sousSeuil(p['stock'], p['seuilAlerte'])) p];
  final sansSeuil = [for (final p in produits) if (!seuilFixe(p['seuilAlerte'])) p];
  final src = [const SourceAst('m6-alertes', 'produits'), if (cx.peutVoirEcran('m6-lots')) const SourceAst('m6-lots', 'lots')];
  final horizon = (_periodeDe(r)?['type'] == 'horizon_mois') ? (_periodeDe(r)!['n'] as int) * 30 : delaiPreavisPeremptionA(cx.col('parametres'), cx.jour);
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
  final texte = astNormaliser(q);
  final dormants = texte.contains('bouge') || texte.contains('sans sortie') || texte.contains('ne sortent plus') || texte.contains('dormants') || texte.contains('tourne pas') || texte.contains('tournent pas') ||
      texte.contains('immobile');
  // La durée d'un article « immobile » est un RÉGLAGE de clinique quand la question ne la dit pas (décision du 16/11/2026) ; le classement des sorties garde ses 30 jours.
  final dureeImmobile = joursArticlesImmobilesA(cx.col('parametres'), cx.jour);
  final pl = _plage(_periodeDe(r), cx, joursParDefaut: dormants ? dureeImmobile : seuilEntierA(cx.col('parametres'), 'assistant.horizonQuestionJours', cx.jour));
  final sorties = [for (final m in cx.col('mouvements')) if (m['type'] == 'sortie' && _dans(m['date'], pl.debut, pl.fin)) m];
  const src = [SourceAst('m6-mouvements', 'mouvements')];
  final parProduit = <String, num>{};
  final noms = <String, String>{};
  for (final m in sorties) {
    final k = '${m['produitId']}';
    parProduit[k] = (parProduit[k] ?? 0) + nombreOuZero(m['quantite']);
    noms[k] = '${m['produit'] ?? k}';
  }
  if (dormants) {
    final ids = parProduit.keys.toSet();
    final fixes = [for (final p in cx.col('produits')) if (nombreOuZero(p['stock']) > 0 && !ids.contains('${p['id']}')) p];
    if (fixes.isEmpty) return _vide('I09', 'Aucun article immobile ${pl.libelle}', const ['Tous les articles en stock ont eu au moins une sortie sur la période.'], src);
    return _rep('I09', '${fixes.length} article(s) en stock sans aucune sortie ${pl.libelle}', [
      'Définition : « ne tourne plus » = du stock et aucune sortie sur la période${_periodeDe(r) == null ? ' — durée réglée par la clinique ($dureeImmobile jours, réglage « Articles immobiles », valeur d’attente à valider)' : ' demandée'}.',
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
  final dateEtat = _dateEtat(r, cx);
  if (dateEtat.compareTo(cx.jour) < 0) return _i10ALaDate(cx, produits, dateEtat);
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

/// La valeur du stock à une date passée : les QUANTITÉS se reconstituent depuis les mouvements, la VALEUR non — le CUMP n'est conservé qu'à aujourd'hui, et valoriser une
/// quantité d'hier au CUMP du jour donnerait un chiffre qui a l'air juste et ne l'est pas. La réponse est donc « non calculable », quantités à l'appui quand elles tiennent.
ReponseAst _i10ALaDate(ContexteAst cx, List<Map<String, Object?>> produits, String date) {
  if (!cx.peutVoirEcran('m6-mouvements')) {
    return _refusLecture('I10', 'Le stock à une date passée lit les mouvements de stock', ['La reconstitution lit l’écran ${cx.ecran('m6-mouvements')}, hors de votre périmètre. La valeur d’aujourd’hui reste lisible.']);
  }
  const src = [SourceAst('m6-point-stock', 'produits'), SourceAst('m6-mouvements', 'mouvements')];
  final rec = reconstituerStockA(produits, cx.col('mouvements'), date);
  final non = [for (final p in produits) if (!(rec['${p['id']}']?.fiable ?? false)) p];
  final lignes = <String>[
    'La VALEUR au ${_d(date)} n’est pas calculable : le CUMP n’est conservé qu’à aujourd’hui, et valoriser une quantité d’une autre date au CUMP du jour serait un chiffre approché.',
  ];
  TableauAst? tableau;
  if (non.isEmpty) {
    final par = <String, num>{};
    final refs = <String, int>{};
    for (final p in produits) {
      final c = '${p['categorie'] ?? 'autre'}';
      par[c] = (par[c] ?? 0) + rec['${p['id']}']!.total!;
      refs[c] = (refs[c] ?? 0) + 1;
    }
    lignes.add('Les QUANTITÉS, elles, se reconstituent depuis les mouvements (stock actuel moins mouvements postérieurs) : ci-dessous, par catégorie.');
    tableau = TableauAst(['Catégorie', 'Références', 'Quantité au ${_d(date)}'], [for (final e in par.entries) [libelleCategorie(e.key), '${refs[e.key]}', _q(e.value)]]);
  } else {
    lignes.add('Même les quantités ne se reconstituent pas pour ${non.length} référence(s) : ${non.take(3).map((p) => '${p['designation']} (${rec['${p['id']}']?.motifs.first ?? 'non reconstituable'})').join(' ; ')}${non.length > 3 ? ' …' : ''}.');
  }
  return ReponseAst(statut: 'non_calculable', code: 'NON_CALCULABLE', intention: 'I10', titre: 'Valeur du stock au ${_d(date)} : non calculable', lignes: lignes, tableau: tableau, sources: src);
}

ReponseAst _i11(ContexteAst cx, ReconnaissanceAst r, String q) {
  final inv = [...cx.col('inventaires')]..sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));
  const src = [SourceAst('m6-inventaire', 'inventaires')];
  if (inv.isEmpty) return _vide('I11', 'Aucun inventaire enregistré', const [], src);
  final d = inv.first;
  final ecarts = [for (final l in ((d['lignes'] as List?) ?? const [])) if (l is Map && l['nonCompte'] != true && nombreOuZero(l['ecart']) != 0) l];
  final nonComptes = [for (final l in ((d['lignes'] as List?) ?? const [])) if (l is Map && l['nonCompte'] == true) l].length;
  return _rep('I11', 'Dernier inventaire : ${d['reference']} du ${_d(d['date'])}', [
    'Type : ${d['type'] ?? '—'} ; magasin : ${d['magasinLabel'] ?? d['magasin'] ?? '—'} ; état : ${d['statutInv'] ?? '—'}.',
    '${d['nbArticles'] ?? '—'} article(s) enregistrés, ${d['nbEcarts'] ?? ecarts.length} écart(s), valeur des écarts : ${money(d['valeurEcart'])}.',
    if (nonComptes > 0) '$nonComptes article(s) non compté(s) : ce ne sont pas des écarts, aucune régularisation n’a été générée pour eux.',
  ], src,
      tableau: ecarts.isEmpty
          ? null
          : TableauAst(['Article', 'Théorique', 'Physique', 'Écart'], [for (final l in ecarts.take(10)) ['${l['designation']}', '${l['theorique']}', '${l['physique']}', '${l['ecart']}']]));
}

// ----------------------------------------------------------------------------------------------------------------------------------------------------
// Achats
// ----------------------------------------------------------------------------------------------------------------------------------------------------

/// Le solde comptable (crédit − débit) des comptes fournisseurs 401… sur les écritures VALIDÉES (un brouillon n'est pas un fait comptable : compté et dit). [compte] : un sous-compte
/// précis ; sinon toute la classe 401.
({double solde, int nb, int brouillons}) _solde401(ContexteAst cx, {String? compte}) {
  var d = 0.0, c = 0.0;
  var nb = 0, br = 0;
  for (final e in cx.col('ecritures')) {
    final n = '${e['compte'] ?? ''}';
    if (!(compte == null ? n.startsWith('401') : n == compte)) continue;
    if (e['statut'] != 'validee') {
      br++;
      continue;
    }
    d += nombreOuZero(e['debit']);
    c += nombreOuZero(e['credit']);
    nb++;
  }
  return (solde: c - d, nb: nb, brouillons: br);
}

/// L'écran comptable qui porte le solde, parmi ceux que l'agent voit (grand livre d'abord) ; `null` : aucun.
String? _ecranCompta(ContexteAst cx) => cx.peutVoirEcran('m12-grand-livre') ? 'm12-grand-livre' : (cx.peutVoirEcran('m12-balance') ? 'm12-balance' : null);

/// LA DETTE FOURNISSEUR EN DEUX CHIFFRES ET UN ÉCART (décision du 16/11/2026, qui remplace « une seule définition » de Q13 pour l'assistant ; l'écran M7 garde la sienne) : les factures
/// fournisseurs non payées (définition prudente, inchangée) et le solde comptable 401, chacun sous le droit de SON écran ; sans les deux, l'écart est « non calculable ».
void _detteDeuxChiffres(ContexteAst cx, List<String> lignes, List<SourceAst> sources, List<String> non, {Map<String, Object?>? fournisseur}) {
  num? factures;
  if (cx.peutVoirEcran('m7-factures-fournisseurs')) {
    sources.add(const SourceAst('m7-factures-fournisseurs', 'facturesFournisseurs'));
    final due = [
      for (final x in cx.col('facturesFournisseurs'))
        if ((fournisseur == null || x['fournisseur'] == fournisseur['code']) && detteFournisseurOuverte(x)) x
    ];
    factures = due.fold<num>(0, (a, x) => a + nombreOuZero(x['montantFacture']));
    lignes.add('1. Factures fournisseurs non payées : ${money(factures)} sur ${due.length} facture(s). $detteFournisseurAValider');
  } else {
    non.add('m7-factures-fournisseurs');
    lignes.add('1. Factures fournisseurs non payées : non lues (écran hors de votre périmètre).');
  }
  num? compta;
  final ec = _ecranCompta(cx);
  if (ec != null) {
    sources.add(SourceAst(ec, 'ecritures'));
    String? sousCompte;
    if (fournisseur != null) {
      // Le sous-compte 401 du fournisseur : au plan comptable (statique), par son NOM ; plusieurs ou aucun : on ne choisit pas.
      final c = <String>{
        for (final x in cpaPlanComptable)
          if (x.$1.startsWith('401') && x.$1 != '401000' && _correspond(x.$2, '${fournisseur['nom'] ?? ''}')) x.$1
      };
      if (c.length == 1) sousCompte = c.first;
    }
    if (fournisseur != null && sousCompte == null) {
      final g = _solde401(cx);
      lignes.add('2. Solde comptable : aucun sous-compte 401 au nom de ce fournisseur au plan comptable — non calculable pour lui (le solde de l’ensemble des comptes 401 est ${money(g.solde)}).');
    } else {
      final s = _solde401(cx, compte: sousCompte);
      compta = s.solde;
      lignes.add('2. Solde comptable du compte fournisseur ${sousCompte ?? '(classe 401)'} : ${money(compta)} — écritures VALIDÉES, crédit moins débit, ${s.nb} ligne(s)${s.brouillons > 0 ? ' ; ${s.brouillons} écriture(s) en brouillon non comptée(s)' : ''}.');
    }
  } else {
    non.addAll(['m12-grand-livre', 'm12-balance']);
    lignes.add('2. Solde comptable du compte fournisseur (401) : non lu (écrans comptables hors de votre périmètre).');
  }
  if (factures != null && compta != null) {
    final e = factures - compta;
    lignes.add(e == 0
        ? 'Écart (factures non payées − solde comptable) : nul, les deux chiffres concordent.'
        : 'Écart (factures non payées − solde comptable) : ${money(e)}. Les deux chiffres ne disent pas la même chose : une facture réglée en partie compte entière côté factures, une facture non encore comptabilisée ou un règlement saisi d’un seul côté le creusent ; il se lève pièce par pièce, jamais en choisissant un chiffre.');
  } else {
    lignes.add('Écart : non calculable — il faut les deux chiffres.');
  }
}

ReponseAst _i12(ContexteAst cx, ReconnaissanceAst r, String q) {
  final requete = '${r.parametres['fournisseur'] ?? ''}'.trim();
  const src = [SourceAst('m7-fournisseurs', 'fournisseurs')];
  final t = astNormaliser(q);
  if (requete.isEmpty && RegExp(r'\b(coordonnees|telephone|tel|contact|livraisons?|commandes?|adresse)\b').hasMatch(t)) {
    // Les coordonnées, les livraisons ou les commandes sont celles d'UN fournisseur : on ne devine pas lequel.
    return ReponseAst(statut: 'precision', code: 'PRECISION_REQUISE', intention: 'I12', titre: 'De quel fournisseur parlez-vous ?', lignes: const ['Donnez le nom ou le code du fournisseur.'], geste: refusAst['PRECISION_REQUISE']!.geste);
  }
  if (requete.isEmpty) {
    // Sans nom : la dette GLOBALE envers les fournisseurs, en deux chiffres et un écart.
    final lignes = <String>[];
    final sources = <SourceAst>[];
    final non = <String>[];
    _detteDeuxChiffres(cx, lignes, sources, non);
    if (sources.isEmpty) return _refusLecture('I12', 'Ni les factures fournisseurs ni la comptabilité ne sont dans votre périmètre', [_nonLu(non.toSet().toList(), cx)]);
    if (non.isNotEmpty) lignes.add(_nonLu(non.toSet().toList(), cx));
    return _rep('I12', 'Dette envers les fournisseurs : deux chiffres et leur écart', lignes, sources);
  }
  final fs = [for (final f in cx.col('fournisseurs')) if (_correspond('${f['nom'] ?? ''} ${f['code'] ?? ''}', requete)) f];
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
  if (cx.peutVoirEcran('m7-factures-fournisseurs') || _ecranCompta(cx) != null) {
    lignes.add('Dette envers ce fournisseur — deux chiffres et leur écart :');
    _detteDeuxChiffres(cx, lignes, sources, non, fournisseur: f);
  } else {
    non.addAll(['m7-factures-fournisseurs', 'm12-grand-livre']);
  }
  if (non.isNotEmpty) lignes.add(_nonLu(non.toSet().toList(), cx));
  return _rep('I12', '${f['nom']}', lignes, sources);
}

/// RG-04 : la validation d'une commande appartient au titulaire du geste réservé « Valider les achats », LU dans la matrice. Un rôle qui ne le détient pas reçoit un SUIVI
/// (« en attente de la validation de <poste> »), jamais « à valider par vous » (décision du 16/11/2026) — aucun poste n'est écrit en dur.
ReponseAst _i13(ContexteAst cx, ReconnaissanceAst r, String q) {
  final cmds = cx.col('commandes');
  const src = [SourceAst('m7-commandes', 'commandes')];
  final att = [for (final c in cmds) if (c['statutCommande'] == 'attente_validation') c];
  final val = [for (final c in cmds) if (c['valideePar'] != null && '${c['valideePar']}'.isNotEmpty) c]..sort((a, b) => '${b['dateValidation']}'.compareTo('${a['dateValidation']}'));
  final geste = (gesteReserve(gesteValiderAchats)?.libelle ?? gesteValiderAchats).split(' :').first;
  final titulaires = cx.matrice?.titulaires(gesteValiderAchats);
  final qui = titulaires == null
      ? 'du titulaire du geste « $geste » (la matrice des gestes n’est pas lue ici)'
      : (titulaires.isEmpty ? 'd’aucun poste : personne ne détient aujourd’hui le geste « $geste » (à régler dans Rôles & permissions)' : 'de : ${titulaires.join(', ')}');
  final moi = cx.detient(gesteValiderAchats) == true;
  final lignes = [
    moi
        ? 'Vous détenez le geste réservé « $geste » (RG-04) : ces commandes attendent VOTRE validation, à poser vous-même à l’écran des commandes.'
        : 'SUIVI : vous ne détenez pas le geste réservé « $geste » ; ces commandes attendent la validation $qui. Elles ne sont pas à valider par vous.',
    if (val.isNotEmpty) 'Dernières validations (RG-04) : ${val.take(3).map((c) => '${c['reference']} par ${c['valideePar']} le ${_d(c['dateValidation'])}').join(' ; ')}.',
  ];
  if (att.isEmpty) return _vide('I13', 'Aucune commande n’attend de validation', lignes, src);
  final titre = moi
      ? '${att.length} commande(s) attendent votre validation'
      : '${att.length} commande(s) en attente de la validation ${titulaires == null || titulaires.isEmpty ? 'du titulaire du geste' : 'de ${titulaires.join(', ')}'} (suivi)';
  return _rep('I13', titre, lignes, src,
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
  // Vue unifiée élargie (décision du 16/11/2026) : courriers de référence, comptes rendus du bloc — chacun sous le droit de SON écran, référence et date seulement.
  void nature(String ecran, String col, String libelle, {bool soins = false}) {
    if (!cx.peutVoirEcran(ecran)) {
      non.add(ecran);
      return;
    }
    src.add(SourceAst(ecran, col));
    if (soins && !cx.sensible('hospitalisation_soins')) {
      if (cx.col(col).any((o) => _duPatient(o, p))) lignes.add('$libelle : ${mentionReservee('hospitalisation_soins')}');
      return;
    }
    for (final o in cx.col(col)) {
      if (_duPatient(o, p)) rows.add([libelle, '${o['numero'] ?? o['reference'] ?? '—'}', _d(o['date'] ?? o['dateOperation'] ?? o['dateReference'] ?? o['dateHeure'])]);
    }
  }

  nature('m1-reference', 'fichesReference', 'Courrier — fiche de référence');
  nature('m1-contre-reference', 'contreReferences', 'Courrier — contre-référence');
  nature('m3-bloc-cro', 'crOperatoires', 'Compte rendu opératoire', soins: true);
  nature('m3-cr-anesthesie', 'crAnesthesie', 'Fiche d’anesthésie (compte rendu)', soins: true);
  nature('m3-cpa', 'cpa', 'Consultation pré-anesthésique', soins: true);
  if (non.isNotEmpty) lignes.add(_nonLu(non, cx));
  rows.sort((a, b) => b[2].split('/').reversed.join().compareTo(a[2].split('/').reversed.join()));
  if (rows.isEmpty) return _vide('I17', '${p['code']} — aucun document du dossier dans votre périmètre', lignes, src);
  return _rep('I17', '${p['code']} — ${rows.length} document(s)', ['Références et dates seulement : le contenu se lit à l’écran de chaque document. Les documents numérisés du dossier suivent leur propre droit et ne sont pas lus ici.', ...lignes], src,
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
  } else if (codeAn == null && !r.parametres.containsKey('codePatient') && !r.parametres.containsKey('nomPatient') && r.parametres['patient'] == null) {
    // Sans patient ni code : les demandes NON RENDUES comptées par état — aucun patient, aucun résultat (relecture des questions d'agents, 16/11/2026).
    final toutes = cx.col('demandesAnalyses');
    final attente = [for (final d in toutes) if (!resultatRendu('${d['etatAnalyse']}')) d];
    final jour = _jourVise(r, cx);
    if (attente.isEmpty) return _vide('I19', 'Aucune demande d’analyse en attente de rendu', const ['Toutes les demandes enregistrées sont rendues.'], src);
    final par = <String, int>{};
    for (final d in attente) {
      final e = etatResultat(d['etatAnalyse']).label;
      par[e] = (par[e] ?? 0) + 1;
    }
    return _rep('I19', '${attente.length} demande(s) d’analyse non encore rendue(s)', [
      'Comptées par état ; aucun patient ni résultat n’est cité ici : la liste se lit à l’écran des demandes.',
      '${toutes.where((d) => _jour10(d['dateHeure']) == jour).length} demande(s) enregistrée(s) le ${_d(jour)}.',
    ], src, tableau: TableauAst(['État', 'Demandes'], [for (final e in par.entries) [e.key, '${e.value}']]));
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

// ----------------------------------------------------------------------------------------------------------------------------------------------------
// Relecture des 100 questions d'agents (Direction, 16/11/2026) : aide, glossaire, et huit lectures d'écrans existants, chacune sous le droit de SON écran.
// ----------------------------------------------------------------------------------------------------------------------------------------------------

/// I26 et I27 : reconnues pour dire « pas de fiche » — aucune fiche d'aide ni de glossaire n'est écrite et validée par la Direction. Improviser un mode d'emploi ou une définition
/// serait précisément ce que l'assistant s'interdit.
ReponseAst _pasDeFiche(String id, String quoi) => ReponseAst(
    statut: 'non_calculable', code: 'PAS_DE_FICHE', intention: id, titre: 'Pas de fiche validée pour cette question',
    lignes: ['Aucune fiche $quoi n’a été écrite et validée par la Direction : je ne réponds pas de mémoire.', 'Geste : ${refusAst['PAS_DE_FICHE']!.geste}.'], geste: refusAst['PAS_DE_FICHE']!.geste);

ReponseAst _i26(ContexteAst cx, ReconnaissanceAst r, String q) => _pasDeFiche('I26', 'd’aide (procédure, « comment faire »)');
ReponseAst _i27(ContexteAst cx, ReconnaissanceAst r, String q) => _pasDeFiche('I27', 'de définition (glossaire, règle de gestion)');

/// I28 : les rôles qui ouvrent les écrans de la paie, lus dans la matrice en force comme l'écran « Rôles & permissions ». Aucune donnée de paie n'est lue.
ReponseAst _i28(ContexteAst cx, ReconnaissanceAst r, String q) {
  const src = [SourceAst('m14-roles', 'rbac')];
  final m = cx.matrice;
  if (m == null) {
    return const ReponseAst(statut: 'non_calculable', code: 'NON_CALCULABLE', intention: 'I28', titre: 'Les rôles de la paie : non calculable ici',
        lignes: ['La matrice des droits n’est pas branchée à l’assistant sur ce poste : ouvrez « Rôles & permissions ».'], sources: src);
  }
  final ecrans = m.ecransDuModule('M11');
  if (ecrans.isEmpty) {
    return const ReponseAst(statut: 'non_calculable', code: 'NON_CALCULABLE', intention: 'I28', titre: 'Aucun écran de paie au manifeste lu', lignes: ['Le manifeste ne porte aucun écran du module de la paie : je ne compte rien.'], sources: src);
  }
  final rows = <List<String>>[];
  for (final x in m.roles()) {
    final vus = [for (final e in ecrans) if (m.roleVoit(x, e)) e];
    if (vus.isNotEmpty) rows.add([m.libelleRole(x), '${vus.length} / ${ecrans.length}', vus.length == ecrans.length ? 'tous' : vus.map(cx.ecran).join(', ')]);
  }
  if (rows.isEmpty) return _vide('I28', 'Aucun rôle n’ouvre les écrans de la paie', const ['La matrice en force ne donne la paie à aucun rôle actif.'], src);
  return _rep('I28', '${rows.length} rôle(s) ouvrent au moins un écran de la paie', [
    'Lu dans la matrice EN FORCE (décisions de la clinique comprises), comme l’écran « Rôles & permissions ». Ouvrir un écran ne veut pas dire pouvoir y écrire.',
    'Aucune donnée de paie n’est lue pour répondre, aucun nom de personne n’est donné.',
  ], src, tableau: TableauAst(['Rôle', 'Écrans de la paie ouverts', 'Lesquels'], rows));
}

/// I29 : la masse salariale BRUTE du mois, calculée comme l'écran « Calcul de la paie » (même moteur, mêmes entrées). L'assouplissement de Q16 ne va pas plus loin : aucun nom,
/// aucun salaire individuel, aucun bulletin.
ReponseAst _i29(ContexteAst cx, ReconnaissanceAst r, String q) {
  final pl = _plageMois(r, cx);
  final annee = int.parse(pl.debut.substring(0, 4)), mois = int.parse(pl.debut.substring(5, 7));
  const src = [SourceAst('m11-calcul', 'personnel')];
  final a = paiActivites(cx.col('modulesActifs'));
  final e = PaiEntrees(
    planning: cx.col('planning'),
    evaluations: cx.col('evaluations'),
    avances: cx.col('avances'),
    participations: cx.col('participations'),
    grille: cx.col('grillePrimes'),
    historique: cx.col('historiquePrimes'),
    heuresSup: cx.col('heuresSup'),
    prets: cx.col('pretsEtudes'),
    primesNs132: a.primesNs132,
    sanctionsNs131: a.sanctionsNs131,
    obligationsFiscales: cx.col('obligationsFiscales'),
    historiqueObligations: cx.col('historiqueObligations'),
    // Les taux et le barème DATÉS (lot 1) : le même calcul que l'écran, aux taux en vigueur au premier jour du mois.
    parametres: cx.col('parametres'),
  );
  final calc = paiCalculerTous(cx.col('personnel'), annee, mois, e, cx.maintenant);
  final libMois = '${mois.toString().padLeft(2, '0')}/$annee';
  if (calc.isEmpty) {
    return _vide('I29', 'Aucun agent payé pour $libMois', const ['Aucun agent du personnel ne porte de salaire de base : la masse salariale ne se calcule pas (elle n’est pas « nulle »).'], src);
  }
  final brut = calc.fold<num>(0, (s, x) => s + x.brut);
  final lignes = <String>[
    'Masse salariale BRUTE de $libMois : ${money(brut)} pour ${calc.length} agent(s).',
    'Calculée comme l’écran « Calcul de la paie » (planning validé → primes → sanctions). Aucun nom, aucun salaire individuel, aucun bulletin n’est donné par l’assistant.',
    if (!a.primesNs132 || !a.sanctionsNs131) 'Une activité de la paie est fermée dans Paramètres système : le brut en tient compte, comme à l’écran.',
  ];
  final src2 = [...src];
  if (cx.peutVoirEcran('m11-bulletins')) {
    final bul = [for (final b in cx.col('bulletins')) if ('${b['annee']}' == '$annee' && '${b['mois']}' == '$mois') b];
    src2.add(const SourceAst('m11-bulletins', 'bulletins'));
    lignes.add(bul.isEmpty
        ? 'Aucun bulletin généré pour ce mois : le chiffre ci-dessus est le calcul du jour.'
        : '${bul.length} bulletin(s) déjà généré(s) pour ce mois, brut total ${money(bul.fold<num>(0, (s, b) => s + nombreOuZero(b['brut'])))} : les bulletins validés font foi.');
  }
  return _rep('I29', 'Masse salariale brute de $libMois : ${money(brut)}', lignes, src2);
}

/// I30 : la balance des comptes d'une période (le mois par défaut), sur les écritures VALIDÉES ; les libellés viennent du plan comptable STATIQUE (lire la collection `comptes`
/// la ferait semer au premier accès : l'assistant ne provoque aucune écriture).
ReponseAst _i30(ContexteAst cx, ReconnaissanceAst r, String q) {
  final pl = _plageMois(r, cx);
  const src = [SourceAst('m12-balance', 'ecritures')];
  final e = [for (final x in cx.col('ecritures')) if (_dans(x['date'], pl.debut, pl.fin)) x];
  final val = [for (final x in e) if (x['statut'] == 'validee') x];
  final br = e.where((x) => x['statut'] != 'validee').length;
  if (val.isEmpty) {
    return _vide('I30', 'Aucune écriture validée sur ${pl.libelle}', [if (br > 0) '$br écriture(s) en brouillon : non comptées (un brouillon n’est pas un fait comptable).'], src);
  }
  final comptes = <String, ({double d, double c})>{};
  for (final x in val) {
    final n = '${x['compte'] ?? '?'}';
    final v = comptes[n] ?? (d: 0.0, c: 0.0);
    comptes[n] = (d: v.d + nombreOuZero(x['debit']), c: v.c + nombreOuZero(x['credit']));
  }
  final parClasse = <String, ({double d, double c})>{};
  for (final k in comptes.entries) {
    final cl = k.key.isEmpty ? '?' : k.key[0];
    final v = parClasse[cl] ?? (d: 0.0, c: 0.0);
    parClasse[cl] = (d: v.d + k.value.d, c: v.c + k.value.c);
  }
  final td = comptes.values.fold<double>(0, (a, v) => a + v.d), tc = comptes.values.fold<double>(0, (a, v) => a + v.c);
  final equilibre = (td - tc).abs() < 0.005;
  final classes = parClasse.keys.toList()..sort();
  String libelle(String n) => cpaPlanComptable.where((x) => x.$1 == n).map((x) => x.$2).firstOrNull ?? 'compte hors plan statique';
  final gros = comptes.entries.toList()..sort((a, b) => (b.value.d + b.value.c).compareTo(a.value.d + a.value.c));
  return _rep('I30', 'Balance des comptes, ${pl.libelle} : ${comptes.length} compte(s) mouvementé(s)', [
    'Total débit : ${money(td)} ; total crédit : ${money(tc)} — ${equilibre ? 'balance équilibrée (RG-10).' : 'DÉSÉQUILIBRÉE de ${money((td - tc).abs())} : une écriture validée ne s’équilibre pas, à corriger à l’écran des écritures (RG-10).'}',
    'Seules les écritures VALIDÉES datées de la période sont comptées${br > 0 ? ' ; $br brouillon(s) écarté(s)' : ''}.',
    'Les plus mouvementés : ${gros.take(3).map((x) => '${x.key} ${libelle(x.key)}').join(' ; ')}. Le détail compte par compte se lit à l’écran de la balance.',
  ], src, tableau: TableauAst(['Classe', 'Débit', 'Crédit', 'Solde'], [for (final c in classes) ['Classe $c', money(parClasse[c]!.d), money(parClasse[c]!.c), money(parClasse[c]!.d - parClasse[c]!.c)]]));
}

/// I31 : les réunions de la période (la semaine par défaut), lues au registre.
ReponseAst _i31(ContexteAst cx, ReconnaissanceAst r, String q) {
  final pl = _plageSemaine(r, cx);
  const src = [SourceAst('m13-reunions', 'reunions')];
  final l = [for (final x in cx.col('reunions')) if (_dans(x['date'], pl.debut, pl.fin)) x]..sort((a, b) => '${a['date']} ${a['heure'] ?? ''}'.compareTo('${b['date']} ${b['heure'] ?? ''}'));
  if (l.isEmpty) return _vide('I31', 'Aucune réunion enregistrée sur ${pl.libelle}', const ['Le registre ne porte aucune réunion à ces dates : ce n’est pas « aucune réunion n’a lieu », c’est « aucune n’est enregistrée ».'], src);
  return _rep('I31', '${l.length} réunion(s) sur ${pl.libelle}', const ['Le compte rendu de chaque réunion se lit à l’écran des réunions.'], src,
      tableau: TableauAst(['Date', 'Heure', 'Type', 'Lieu', 'Présidée par'], [for (final x in l.take(12)) [_d(x['date']), '${x['heure'] ?? '—'}', '${x['type'] ?? '—'}', '${x['lieu'] ?? '—'}', '${x['president'] ?? '—'}']]));
}

/// I32 : l'ambulance disponible, dans l'ordre d'appel rapide du répertoire (disponibles d'abord). Un numéro absent se dit, un numéro ancien est signalé, rien n'est déduit.
ReponseAst _i32(ContexteAst cx, ReconnaissanceAst r, String q) {
  const src = [SourceAst('m13-repertoire-ambulances', 'ambulances')];
  final l = admOrdreAppelRapide(cx.col('ambulances'));
  if (l.isEmpty) return _vide('I32', 'Aucune ambulance répertoriée', const ['Le répertoire des ambulances est vide : aucun numéro n’est inventé.'], src);
  final dispo = [for (final x in l) if (x['disponibilite'] == 'disponible') x];
  String tel(Map<String, Object?> x) => '${x['telephone'] ?? ''}'.trim().isEmpty ? 'numéro à renseigner' : '${x['telephone']}';
  final lignes = <String>[
    if (dispo.isEmpty) 'Aucun moyen n’est marqué « disponible » au répertoire : ${l.length} moyen(s), ${l.where((x) => x['disponibilite'] == 'en_course').length} en course.',
    'La disponibilité est celle portée au répertoire (mise à jour par l’accueil) : appeler pour confirmer.',
    if (l.any((x) => '${x['telephone'] ?? ''}'.trim().isNotEmpty && admPerime(x, cx.maintenant))) 'Au moins un numéro n’a pas été vérifié depuis longtemps : il est signalé, pas masqué.',
  ];
  return _rep('I32', dispo.isEmpty ? 'Aucune ambulance disponible au répertoire' : '${dispo.length} ambulance(s) disponible(s)', lignes, src,
      tableau: TableauAst(['Moyen', 'Disponibilité', 'Téléphone', 'Vérifié'], [
        for (final x in l.take(8)) ['${x['libelle'] ?? '—'}', admDisponibilite(x['disponibilite']).libelle, tel(x), '${x['verifieLe'] ?? ''}'.isEmpty ? 'jamais' : '${_d(x['verifieLe'])}${admPerime(x, cx.maintenant) ? ' (ancien)' : ''}']
      ]));
}

/// I33 : la prochaine garde de l'agent CONNECTÉ (espace « Mes ») : ses seules lignes du planning, à partir d'aujourd'hui. Une ligne non validée est dite à part.
ReponseAst _i33(ContexteAst cx, ReconnaissanceAst r, String q) {
  const src = [SourceAst('m10-mes', 'planning')];
  final nom = cx.session?.nom;
  if (nom == null || nom.isEmpty) {
    return const ReponseAst(statut: 'non_calculable', code: 'NON_CALCULABLE', intention: 'I33', titre: 'Je ne sais pas qui vous êtes sur ce poste',
        lignes: ['La session ne porte pas de nom d’agent : « ma garde » ne se lit que pour un compte nominatif.'], sources: src);
  }
  final a = agentDeMes(acteur: nom, personnelActif: cx.col('personnel'));
  if (a.agent == null) {
    return ReponseAst(statut: 'refus', code: a.refus?.code ?? 'NON_CALCULABLE', intention: 'I33', titre: 'Votre compte n’est rattaché à aucun agent du personnel', lignes: [a.refus?.motif ?? '', a.refus?.geste ?? ''].where((x) => x.isNotEmpty).toList(), sources: src);
  }
  final id = a.agent!['id'];
  bool valide(Map<String, Object?> x) => x['statut'] == 'validee' || x['validationEtat'] == 'valide' || x['validationEtat'] == 'validee';
  final miennes = [
    for (final x in cx.col('planning'))
      if (x['employeId'] == id && const ['garde', 'garde_hospi', 'garde_soins', 'permanence'].contains(x['type']) && _jour10(x['date']).compareTo(cx.jour) >= 0) x
  ]..sort((x, y) => _jour10(x['date']).compareTo(_jour10(y['date'])));
  final validees = [for (final x in miennes) if (valide(x)) x];
  final proposees = [for (final x in miennes) if (!valide(x)) x];
  final lignes = [
    if (proposees.isNotEmpty) '${proposees.length} ligne(s) proposée(s) non encore validée(s) (la première le ${_d(proposees.first['date'])}) : pas acquise(s).',
    'Seules VOS lignes du planning sont lues (espace « Mes »).',
  ];
  if (validees.isEmpty) return _vide('I33', 'Aucune garde ni permanence validée à venir à votre nom', lignes, src);
  final p = validees.first;
  return _rep('I33', 'Votre prochaine ${p['type'] == 'permanence' ? 'permanence' : 'garde'} : le ${_d(p['date'])}', lignes, src,
      tableau: TableauAst(['Date', 'Type', 'Service'], [for (final x in validees.take(5)) [_d(x['date']), '${x['type']}', '${x['service'] ?? '—'}']]));
}

/// I34 : les échographies de la journée (aujourd'hui par défaut) : demandes d'imagerie dont l'examen est de modalité échographie, comptées par état. Aucun patient nommé.
ReponseAst _i34(ContexteAst cx, ReconnaissanceAst r, String q) {
  final jour = _jourVise(r, cx);
  final ecran = cx.peutVoirEcran('m2-imagerie-demandes') ? 'm2-imagerie-demandes' : (cx.peutVoirEcran('m2-dashboard-imagerie') ? 'm2-dashboard-imagerie' : 'm2-imagerie');
  final src = [SourceAst(ecran, 'demandesImagerie')];
  final examens = cx.col('examensImagerie');
  final l = [
    for (final d in cx.col('demandesImagerie'))
      if (_jour10(d['dateHeure'] ?? d['date']) == jour && '${d['modalite'] ?? modaliteDeCodeExamen(examens, d['examenCode'])}' == 'echographie') d
  ];
  if (l.isEmpty) return _vide('I34', 'Aucune échographie enregistrée le ${_d(jour)}', const ['Aucune demande d’échographie n’est datée de ce jour au registre de l’imagerie.'], src);
  final par = <String, int>{};
  for (final d in l) {
    final e = etatImagerie(d['statut']).libelle;
    par[e] = (par[e] ?? 0) + 1;
  }
  return _rep('I34', '${l.length} échographie(s) le ${_d(jour)}', [
    'Par état : ${par.entries.map((e) => '${e.value} ${e.key.toLowerCase()}').join(' ; ')}.',
    'Les patients et les comptes rendus se lisent à l’écran de l’imagerie : ils ne sont pas recopiés ici.',
  ], src, tableau: TableauAst(['Heure', 'Examen', 'État'], [for (final d in l.take(12)) [_heure(d), '${d['examen'] ?? d['examenCode'] ?? '—'}', etatImagerie(d['statut']).libelle]]));
}

/// I35 : les congés ACCORDÉS qui chevauchent la période (la semaine par défaut) ; les demandes en attente sont comptées à part, jamais présentées comme des absences.
ReponseAst _i35(ContexteAst cx, ReconnaissanceAst r, String q) {
  final pl = _plageSemaine(r, cx);
  const src = [SourceAst('m10-conges', 'conges')];
  bool chevauche(Map<String, Object?> c) {
    final d = _jour10(c['dateDebut']), f = _jour10(c['dateFin']);
    return d.isNotEmpty && f.isNotEmpty && d.compareTo(pl.fin) <= 0 && f.compareTo(pl.debut) >= 0;
  }

  final tous = [for (final c in cx.col('conges')) if (chevauche(c)) c];
  final accordes = [for (final c in tous) if (c['statutConge'] == 'valide') c]..sort((a, b) => _jour10(a['dateDebut']).compareTo(_jour10(b['dateDebut'])));
  final attente = tous.where((c) => c['statutConge'] == 'en_attente').length;
  final lignes = [if (attente > 0) '$attente demande(s) en attente de décision sur la période : ce ne sont pas des absences acquises.'];
  if (accordes.isEmpty) return _vide('I35', 'Aucun congé accordé sur ${pl.libelle}', lignes, src);
  return _rep('I35', '${accordes.length} congé(s) accordé(s) sur ${pl.libelle}', lignes, src,
      tableau: TableauAst(['Agent', 'Service', 'Du', 'Au'], [for (final c in accordes.take(15)) ['${c['employe'] ?? '—'}', '${c['service'] ?? '—'}', _d(c['dateDebut']), _d(c['dateFin'])]]));
}

/// Les exécuteurs, par identifiant d'intention. Une intention du catalogue sans exécuteur ici n'est PAS livrée (le moteur la dit « indisponible »).
const Map<String, ExecuteurAst> executeursAst = {
  'I01': _i01, 'I02': _i02, 'I03': _i03, 'I04': _i04, 'I05': _i05, 'I06': _i06, 'I07': _i07, 'I08': _i08, 'I09': _i09, 'I10': _i10, 'I11': _i11, 'I12': _i12,
  'I13': _i13, 'I14': _i14, 'I15': _i15, 'I16': _i16, 'I17': _i17, 'I18': _i18, 'I19': _i19, 'I20': _i20, 'I21': _i21, 'I22': _i22, 'I23': _i23, 'I24': _i24, 'I25': _i25,
  'I26': _i26, 'I27': _i27, 'I28': _i28, 'I29': _i29, 'I30': _i30, 'I31': _i31, 'I32': _i32, 'I33': _i33, 'I34': _i34, 'I35': _i35,
};
