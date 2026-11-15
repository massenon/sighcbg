// LE CIRCUIT DU LABORATOIRE ET DE L'IMAGERIE : ce qui arrive aux demandes APRÈS la caisse. Les demandes elles-mêmes sont nées de la prescription
// (`csPrescrire`) et n'ont été libérées que par l'encaissement (`encaisser`). Ici, le prélèvement, la réception, la saisie, la validation technique puis
// biologique ; l'exécution et le compte rendu d'imagerie. Rien n'est inventé hors des catalogues du socle : les variables, les bornes, les unités et
// les options viennent des collections `variablesLabo`, `unitesLabo`, `variablesImagerie`.
//
// Honnêteté sur les personnes : la clinique n'a ni biologiste ni radiologue au personnel. Le prélèvement et la saisie sont portés par l'infirmier, la
// validation biologique par le médecin (qualité écrite « Médecin ») ; l'imagerie est réalisée par le vacataire échographiste du socle.
import 'package:sigh_domaine/sigh_domaine.dart' as d;
import 'package:sigh_poste/donnees/magasin.dart';

import 'clinique_base.dart';

const String _maintenantLimite = '2026-11-07T11:30:00.000Z';

DateTime _borne(DateTime t) {
  final lim = DateTime.parse(_maintenantLimite);
  return t.isAfter(lim) ? lim : t;
}

/// Une valeur de variable : au milieu des bornes du laboratoire, ou franchement hors bornes pour l'unique variable choisie comme anormale.
Object? _valeurVariable(Jeu j, Fiche v, bool anormal, {String? groupe}) {
  final t = j.t;
  final ops = [for (final o in (v['valeurs'] as List? ?? d.valeursTypeVariable['${v['type']}'] ?? const <Object?>[])) '$o'];
  final normal = v['normal'] == null ? null : '${v['normal']}';
  switch (v['type']) {
    case 'numerique':
      final mn = v['min'] as num?;
      final mx = v['max'] as num?;
      if (mn == null && mx == null) return null;
      final dec = (v['decimales'] as num?)?.toInt() ?? 1;
      final double x;
      if (mn != null && mx != null) {
        x = anormal
            ? (t.chance(0.5) ? mx + (mx - mn) * (0.1 + t.reel() * 0.3) : mn - (mx - mn) * (0.1 + t.reel() * 0.2))
            : mn + (mx - mn) * (0.15 + t.reel() * 0.7);
      } else if (mx != null) {
        x = anormal ? mx * (1.2 + t.reel() * 0.5) : mx * (0.3 + t.reel() * 0.5);
      } else {
        x = anormal ? mn! * (0.6 - t.reel() * 0.2) : mn! * (1.1 + t.reel() * 0.4);
      }
      final f = [1, 10, 100, 1000][dec.clamp(0, 3)];
      final r = (x * f).round() / f;
      return dec == 0 ? r.round() : r;
    case 'binaire':
    case 'ternaire':
    case 'titre':
    case 'liste':
      if (ops.isEmpty) return null;
      if (groupe != null && v['code'] == 'GSRH') {
        final pos = groupe.endsWith('+') ? 'Positif' : 'Négatif';
        final g = groupe.replaceAll(RegExp(r'[+-]'), '');
        final cible = ops.where((o) => o.startsWith('$g ') && o.contains(pos)).firstOrNull;
        if (cible != null) return cible;
      }
      if (anormal) {
        final autres = ops.where((o) => o != normal && o != 'Négatif' && o != ops.first).toList();
        return autres.isEmpty ? ops.last : t.choisir(autres);
      }
      return normal ?? ops.first;
    case 'reactif':
      return ops.isNotEmpty ? ops.first : null;
    case 'lot':
      return 'LOT-DEMO-${pad(t.entre(100, 999), 4)}';
    case 'expiration':
      return '2027-06-30';
    default:
      return null;
  }
}

/// Les valeurs d'un examen (les variables du catalogue du socle) et le nombre de valeurs hors bornes : 78 % des examens sont entièrement normaux, les
/// autres portent UNE valeur anormale.
({Map<String, Object?> valeurs, int anormales}) _resultatExamen(Jeu j, List<Fiche> variables, {String? groupe}) {
  final t = j.t;
  final valeurs = <String, Object?>{};
  var anormales = 0;
  bool candidate(Fiche v) =>
      v['accompagnement'] != true && ((v['type'] == 'numerique' && (v['min'] != null || v['max'] != null)) || v['normal'] != null);
  final candidates = [for (final v in variables) if (candidate(v)) v];
  final cible = t.chance(0.22) && candidates.isNotEmpty ? candidates[t.entier(candidates.length)] : null;
  for (final v in variables) {
    final anormal = identical(v, cible);
    final val = _valeurVariable(j, v, anormal, groupe: groupe);
    if (val == null) continue;
    valeurs['${v['code']}'] = val;
    if (anormal) anormales++;
  }
  return (valeurs: valeurs, anormales: anormales);
}

/// Les analyses dont la désignation du catalogue des analyses ne retrouve pas son examen structuré par le nom (« HIV » pour « VIH »).
const Map<String, String> _examenDeAnalyse = {'L21': 'VIH', 'L17': 'GSRH', 'L47': 'VS', 'L19': 'AGHBS', 'L41': 'TGO'};

/// Le résultat TEXTE d'une analyse sans modèle structuré au catalogue du socle (bandelette urinaire, hémoglobine capillaire).
(String, String)? _resultatTexte(Jeu j, String analyseCode) {
  switch (analyseCode) {
    case 'L05':
      return ('Leucocytes négatif · Nitrites négatif · Protéines négatif · Glucose négatif · Sang négatif', 'Normal');
    case 'L18':
      return ('Hémoglobine capillaire ${(11 + j.t.entre(0, 40) / 10).toStringAsFixed(1)} g/dl', 'Normal');
    default:
      return null;
  }
}

String _symbole(Map<String, String> unites, Object? id) => unites['$id'] ?? '—';

/// Fait avancer les demandes d'analyses payées : 60 sont rendues (validées biologiquement), les plus récentes restent aux étapes intermédiaires du
/// circuit (à prélever, prélevées, reçues au laboratoire, saisies en attente de validation biologique). Les demandes non payées restent bloquées.
void finaliserAnalyses(Jeu j, {int rendues = 60}) {
  final examens = j.lire('examensLabo');
  final variables = j.lire('variablesLabo').where((v) => v['actif'] != false).toList();
  final unites = {for (final u in j.lire('unitesLabo')) '${u['id']}': '${u['symbole']}'};
  final tous = j.ctx.collection('demandesAnalyses').toutes;
  final payees = [for (final x in tous) if (x['bloqueParPaiement'] != true) x];
  payees.sort((a, b) => '${a['regleLe']}'.compareTo('${b['regleLe']}'));
  if (payees.length < rendues) throw StateError('Seulement ${payees.length} demandes d\'analyses payées pour $rendues à rendre.');
  final nInter = payees.length - rendues;
  final t = j.t;
  for (final (i, dem) in payees.indexed) {
    final reglee = DateTime.parse('${dem['regleLe']}');
    final intermediaire = i >= rendues;
    // Rang parmi les intermédiaires, du plus ancien (0) au plus récent : les plus anciens sont les plus avancés dans le circuit.
    final r = intermediaire ? i - rendues : -1;
    final etat = !intermediaire
        ? 'valide'
        : (r < (nInter * 0.25).ceil()
            ? 'valide_technique'
            : (r < (nInter * 0.5).ceil() ? 'en_cours' : (r < (nInter * 0.7).ceil() ? 'preleve' : 'attente_prelevement')));
    if (etat == 'attente_prelevement') continue;
    final preleveLe = _borne(reglee.add(Duration(minutes: t.entre(15, 50))));
    final patch = <String, Object?>{
      'prelevePar': infirmierNom,
      'preleveParId': infirmierSoignantId,
      'preleveLe': iso8601(preleveLe),
    };
    if (etat != 'preleve') {
      final recu = _borne(preleveLe.add(Duration(minutes: t.entre(25, 70))));
      patch.addAll({'recuLaboLe': iso8601(recu), 'recuPar': infirmierNom, 'etatAnalyse': 'en_cours', 'laborantin': infirmierNom});
      if (etat != 'en_cours') {
        final code = d.codeExamenSaisie(dem, examens) ?? _examenDeAnalyse['${dem['analyseCode']}'];
        final vars = code == null ? <Fiche>[] : d.variablesExamen(code, variables);
        final groupe = j.parId('patients', dem['patientId'])?['groupeSanguin'] as String?;
        final res = _resultatExamen(j, vars, groupe: groupe);
        final texte = vars.isEmpty ? _resultatTexte(j, '${dem['analyseCode']}') : null;
        final saisi = _borne(recu.add(Duration(minutes: t.entre(50, 150))));
        final tech = _borne(saisi.add(Duration(minutes: t.entre(10, 30))));
        patch.addAll({
          if (texte == null) 'valeurs': res.valeurs,
          'resultat': texte?.$1 ?? d.resumeResultat(vars, res.valeurs, (u) => _symbole(unites, u)),
          'resultatStructure': texte == null,
          'conclusion': texte != null ? texte.$2 : (res.anormales > 0 ? 'Anormal' : 'Normal'),
          'anormales': texte != null ? 0 : res.anormales,
          'saisiPar': infirmierNom,
          'saisiLe': iso8601(saisi),
          'valideTechniquePar': infirmierNom,
          'valideTechniqueLe': iso8601(tech),
          'etatAnalyse': 'valide_technique',
        });
        if (etat == 'valide') {
          final bio = _borne(tech.add(Duration(minutes: t.entre(25, 110))));
          patch.addAll({
            'etatAnalyse': 'valide',
            'valideLe': iso8601(bio),
            'valideBiologiquePar': medecinNom,
            'qualiteValidateur': 'Médecin',
            'version': 1,
          });
        }
      }
    }
    j.maj('demandesAnalyses', dem['id'], patch);
  }
}

// --------------------------------------------------------------------------------------------------------------------------------------------
// L'imagerie
// --------------------------------------------------------------------------------------------------------------------------------------------

/// Une mesure plausible : selon le code de la variable connu (rythme cardiaque, intervalles de l'ECG), sinon selon l'unité.
String _mesure(Jeu j, Fiche x) {
  final t = j.t;
  final code = '${x['code']}';
  final u = '${x['unite'] ?? ''}';
  if (code == 'FC') return '${t.entre(62, 96)}';
  if (code == 'PR') return '${t.entre(130, 190)}';
  if (code == 'QRS') return '${t.entre(80, 105)}';
  if (code == 'QT') return '${t.entre(360, 430)}';
  if (code == 'THO_ICT') return '0,${t.entre(42, 48)}';
  if (u == 'cm') return '${t.entre(5, 14)}';
  if (u == 'mm') return '${t.entre(8, 40)}';
  if (u == 'ml') return '${t.entre(20, 120)}';
  if (u == 'ms') return '${t.entre(80, 400)}';
  return '${t.entre(5, 60)}';
}

/// Les valeurs d'un compte rendu : chaque variable prend sa valeur NORMALE ; 70 % des examens sont entièrement normaux, les autres portent UNE variable à
/// la valeur anormale (liste ou binaire à valeur normale déclarée). Une variable répétée (blocs obstétricaux) n'est pas renseignée ici. Les champs de
/// précision d'une valeur « Autre » ne sont jamais ouverts. Rend aussi les libellés des variables anormales (la conclusion les nomme).
({Map<String, Object?> valeurs, List<String> ecarts}) _valeursImagerie(Jeu j, List<Fiche> vars) {
  final t = j.t;
  final v = <String, Object?>{};
  final ecarts = <String>[];
  final compteurs = {for (final x in vars) if (x['repete'] != null) '${x['repete']}'};
  final candidates = [
    for (final x in vars)
      if ((x['type'] == 'liste' || x['type'] == 'binaire') && x['normal'] != null && x['repete'] == null && !compteurs.contains('${x['code']}')) x
  ];
  final cible = t.chance(0.3) && candidates.isNotEmpty ? candidates[t.entier(candidates.length)] : null;
  for (final x in vars) {
    final code = '${x['code']}';
    if (x['repete'] != null) continue;
    final ops = [for (final o in (x['options'] as List? ?? const [])) '$o'];
    switch (x['type']) {
      case 'liste':
      case 'binaire':
        String? choix;
        if (compteurs.contains(code)) {
          choix = ops.isNotEmpty ? ops.first : null;
        } else if (identical(x, cible)) {
          final autres = ops.where((o) => o != '${x['normal']}' && o != 'Autre').toList();
          choix = autres.isEmpty ? null : t.choisir(autres);
          if (choix != null) ecarts.add('${x['libelle']} : $choix');
        } else {
          choix = x['normal'] != null ? '${x['normal']}' : (ops.where((o) => o != 'Autre').isEmpty ? null : ops.where((o) => o != 'Autre').first);
        }
        if (choix == null) continue;
        v[code] = choix;
        for (final c in (x['conditionnels'] as List? ?? const [])) {
          final cm = (c as Map).cast<String, Object?>();
          if (d.valeurCorrespond((cm['quand'] as List? ?? const []), choix) && choix != 'Autre') {
            v['${cm['code']}'] = 'précision à rédiger par le réalisateur (donnée de démonstration)';
          }
        }
      case 'mesure':
        v[code] = _mesure(j, x);
      case 'dimensions':
        v['${code}_a'] = '${t.entre(30, 90)}';
        v['${code}_b'] = '${t.entre(20, 60)}';
        v['${code}_c'] = '${t.entre(15, 45)}';
      case 'gestationnel':
        v['${code}_sa'] = '${t.entre(8, 36)}';
        v['${code}_j'] = '${t.entre(0, 6)}';
      case 'multiple':
        if (ops.isNotEmpty) v[code] = [ops.first];
      default:
        break;
    }
  }
  return (valeurs: v, ecarts: ecarts);
}

const String _conclusionNormale = 'Examen sans anomalie significative, à confronter à la clinique.';

/// Fait avancer les demandes d'imagerie payées : les plus anciennes sont rendues (compte rendu, demande validée), puis des examens exécutés (compte rendu
/// en rédaction), puis des examens payés restant à exécuter. Les demandes non payées restent « demandées ». Le réalisateur est le vacataire échographiste
/// du socle ; le prescripteur est celui de la demande.
void finaliserImagerie(Jeu j, {int executees = 6, int payeesAExecuter = 5}) {
  final catalogue = j.lire('examensImagerie');
  final variablesAll = j.lire('variablesImagerie');
  final prestataires = j.lire('prestataires');
  final echo = prestataires.firstWhere((x) => x['specialite'] == 'Échographie');
  final tous = j.ctx.collection('demandesImagerie').toutes;
  final payees = [for (final x in tous) if (x['bloqueParPaiement'] != true) x];
  payees.sort((a, b) => '${a['regleLe']}'.compareTo('${b['regleLe']}'));
  final nExec = executees < payees.length ? executees : 0;
  final nPaye = payeesAExecuter < (payees.length - nExec) ? payeesAExecuter : 0;
  final nRendues = payees.length - nExec - nPaye;
  final t = j.t;
  for (final (i, dem) in payees.indexed) {
    if (i >= nRendues + nExec) continue; // payée, à exécuter : rien de plus
    final reglee = DateTime.parse('${dem['regleLe']}');
    final rendu = i < nRendues;
    final code = '${dem['examenCode']}';
    final vars = d.variablesDeExamen(variablesAll, code);
    final modalite = d.modaliteDemandeDeExamen(catalogue, code);
    final libres = d.rubriquesLibresDe(catalogue, code);
    final pat = j.parId('patients', dem['patientId']);
    final exec = _borne(reglee.add(Duration(minutes: t.entre(40, 180))));
    final nCr = j.ctx.collection('resultatsImagerie').toutes.length + 1;
    final entete = d.ficheDepuisEntete(
      {
        'examenCode': code,
        'patientCode': dem['patientCode'],
        'indication': dem['indication'],
        'ddr': '',
        'condition': 'Bonne',
        'provenance': 'Clinique Baguidi — ${dem['secteurDemandeur'] ?? 'consultation'}',
        'realisateurId': echo['id'],
      },
      reference: 'IMG-${pad(nCr, 4)}',
      dateIso: iso8601(exec),
      examenLibelle: '${dem['examen']}',
      patient: pat,
      age: pat == null ? null : d.ageDePatient(pat, DateTime.utc(2026, 11, 7)),
      prescripteur: '${dem['prescripteur']}',
      prescripteurId: null,
      realisateur: '${echo['nom']}',
    );
    final res = _valeursImagerie(j, vars);
    final valeurs = res.valeurs;
    final conclusion = res.ecarts.isEmpty ? _conclusionNormale : 'Anomalie relevée — ${res.ecarts.join(' ; ')}. À corréler à la clinique.';
    final cr = <String, Object?>{
      ...entete,
      'demandeImagerieId': dem['id'],
      'demandeReference': dem['reference'],
      'valeurs': valeurs,
      'modalite': modalite,
      'fictif': true,
    };
    for (final r in libres) {
      cr[r.code] = '';
    }
    if (rendu) {
      for (final r in libres) {
        if (r.code == 'conclusion') cr[r.code] = conclusion;
        if (r.code == 'resultats') cr[r.code] = 'Voir les variables ci-dessus : aucune anomalie rédigée en complément.';
        if (r.code == 'recommandation') cr[r.code] = 'Contrôle selon l’évolution clinique.';
      }
    }
    final ins = j.ajouter('resultatsImagerie', cr, 'IMG', largeur: 5);
    if (rendu) {
      final renduLe = _borne(exec.add(Duration(minutes: t.entre(30, 150))));
      final r = d.rendreCompteRendu(ins, maintenant: iso8601(renduLe));
      j.maj('resultatsImagerie', ins['id'], r.patchCompteRendu);
      if (r.patchDemande != null) j.maj('demandesImagerie', dem['id'], {...r.patchDemande!, 'executeLe': iso8601(exec)});
      j.ajouter('notifications', r.notification, 'NOT');
    } else {
      final p = d.patchEnregistrerCR(valeurs, libres, demande: dem, maintenantIso: iso8601(exec));
      j.maj('resultatsImagerie', ins['id'], p.patch);
      if (p.patchDemande != null) j.maj('demandesImagerie', dem['id'], p.patchDemande!);
    }
  }
}

/// Un dossier de consultation « en attente du laboratoire » se clôt quand tout ce qu'il attendait est rendu ; sinon il reste en attente (état ordonné
/// du moteur : attente → consultation → attente du laboratoire → clôturé).
void cloturerDossiersRendus(Jeu j) {
  final dossiers = j.ctx.collection('dossiersConsultation').toutes.where((x) => x['etat'] == 'attente_labo').toList();
  final analyses = j.ctx.collection('demandesAnalyses').toutes;
  final imageries = j.ctx.collection('demandesImagerie').toutes;
  for (final dos in dossiers) {
    final id = dos['id'];
    final aA = analyses.where((x) => x['dossierConsultationId'] == id).toList();
    final aI = imageries.where((x) => x['dossierConsultationId'] == id).toList();
    final fini = aA.every((x) => x['etatAnalyse'] == 'valide') && aI.every((x) => x['statut'] == 'validee');
    if (!fini) continue;
    final dernier = [
      for (final x in aA) '${x['valideLe']}',
      for (final x in aI) '${x['valideLe']}',
    ]..sort();
    final quand = dernier.isEmpty ? iso8601(DateTime.utc(2026, 11, 7, 9)) : dernier.last;
    j.maj('dossiersConsultation', id, {'etat': 'cloture', 'cloturLe': quand});
  }
}
