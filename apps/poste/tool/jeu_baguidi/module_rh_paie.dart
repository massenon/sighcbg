// SOUS-LOT « RH ET PAIE » (JEU-3) : contrats, fiches de poste, congés, planning, présences, heures supplémentaires, une avance et un prêt d'études, puis
// 24 bulletins (août, septembre, octobre pour les huit agents salariés) avec leur journal de paie.
//
// RIEN N'EST CALCULÉ ICI : chaque bulletin sort de `paiCalculer`, `paiBulletinDe`, la pièce de paie de `paiPieceDePaie` et les imputations de
// `paiImputationsDeRetenues` — les moteurs de `packages/domaine`, appelés comme le poste les appelle (voir `lib/modules/m11/pai_commun.dart`, `pai_calcul.dart`,
// `pai_validation.dart`). Le déroulé est CHRONOLOGIQUE, comme à la clinique : l'avance est accordée avant le bulletin de septembre, la validation d'août
// puis de septembre écrit les retenues qu'elle porte, octobre reste à valider.
//
// Choix à connaître :
//  - août et septembre sont VALIDÉS par la Direction (BAGUIDI Rafiou, puis SOKOU Peace) ; les bulletins sont générés par les RH (MABOUDOU Nawal, puis
//    TOUNGOUH A. Zoulkifouli). Séparation des tâches (A2) contrôlée par le moteur AVANT chaque validation ;
//  - octobre est « brouillon » : bulletins à l'état `a_valider` (c'est l'état que le moteur donne à un lot généré et non validé), SANS écriture comptable
//    (le poste ne pose la pièce de paie qu'à la validation) ;
//  - les salaires sont les valeurs d'attente de `personnes.dart` (`salaireProvisoire`) : les bulletins le portent ;
//  - AUCUNE évaluation NS 131, aucune sanction : on ne fait pas porter une sanction fictive à une personne réelle ;
//  - primes NS 132 selon la grille du socle (héritée du logiciel d'origine, à confirmer) : une fonction sans prime au barème n'en reçoit aucune ;
//  - aucun badge, aucun événement, aucune participation, aucune évaluation ; aucun numéro de téléphone, de CNSS ni de compte bancaire.
import 'package:sigh_domaine/sigh_domaine.dart' as d;
import 'package:sigh_poste/donnees/magasin.dart';

import 'contexte.dart';

const String _sourceDemo = 'Jeu de démonstration Baguidi : valeur d’attente fictive, à remplacer par la Direction';

String _pad(int n, int l) => n.toString().padLeft(l, '0');

void generer(Contexte ctx) {
  final t = ctx.tirageDe('rh_paie');
  final personnel = ctx.fiches('personnel');
  final utilisateurs = ctx.fiches('utilisateurs');
  Fiche agent(String id) => personnel.firstWhere((p) => p['id'] == id);
  String compteDe(String employeId) => '${utilisateurs.firstWhere((u) => u['employeId'] == employeId)['id']}';

  // Série par collection : préfixe + rang, ordre d'écriture = ordre du fichier.
  final rangs = <String, int>{};
  Fiche ajouter(String col, String prefixe, Fiche f, {int largeur = 4}) {
    final n = (rangs[col] ?? ctx.collection(col).toutes.length) + 1;
    rangs[col] = n;
    final fiche = {'id': '$prefixe${_pad(n, largeur)}', 'statut': 'actif', ...f};
    ctx.ajouter(col, fiche);
    return ctx.collection(col).parId(fiche['id'])!;
  }

  _contrats(ctx, personnel, ajouter);
  _fichesPoste(ajouter);
  final conges = _conges(ctx, agent, ajouter);
  _planning(ctx, agent, conges, ajouter);
  _presences(ctx, t, agent, conges, ajouter);
  _heuresSup(ctx, agent, ajouter);
  _paie(ctx, agent, compteDe, ajouter);

  ctx.note('rh_paie : ${ctx.fiches('contrats').length} contrats, ${ctx.fiches('fichesPoste').length} fiches de poste, ${ctx.fiches('conges').length} congés, '
      '${ctx.fiches('planning').length} vacations, ${ctx.fiches('presences').length} pointages, ${ctx.fiches('heuresSup').length} déclarations d\'heures, '
      '${ctx.fiches('avances').length} avance, ${ctx.fiches('pretsEtudes').length} prêt, ${ctx.fiches('bulletins').length} bulletins, '
      '${ctx.fiches('ecritures').where((e) => e['journal'] == 'SAL').length} lignes d\'écriture de paie');
}

// --- contrats ----------------------------------------------------------------------------------------------------------------------------------

typedef _Ajout = Fiche Function(String col, String prefixe, Fiche f, {int largeur});

/// Un CDI par agent, à compter de la date d'embauche d'attente déjà posée au personnel : aucune date plus ancienne n'est inventée.
void _contrats(Contexte ctx, List<Fiche> personnel, _Ajout ajouter) {
  for (final p in personnel) {
    final v = d.rhaContratEnregistrable({
      'employeId': p['id'],
      'nature': 'CDI',
      'dateDebut': p['dateEmbauche'],
      'dateDebutProvisoire': true,
      'salaire': p['salaireBase'],
      'salaireProvisoire': true,
      'source': _sourceDemo,
    }, p, reference: 'CT-${_pad(ctx.fiches('contrats').length + 1, 4)}');
    ajouter('contrats', 'CON', v);
  }
}

// --- fiches de poste -----------------------------------------------------------------------------------------------------------------------------

/// Les six postes du jeu. Le contenu des missions n'a pas été remis : fiche non rédigée, marquée « à compléter par la Direction », jamais inventée.
void _fichesPoste(_Ajout ajouter) {
  const postes = [
    ('Direction Générale', 'À compléter par la Direction'),
    ('Comptabilité', 'Direction Générale'),
    ('Ressources humaines', 'Direction Générale'),
    ('Médecine générale', 'Direction Générale'),
    ('Soins infirmiers', 'Direction Générale'),
    ('Administration système', 'À compléter par la Direction'),
  ];
  for (final (intitule, rattachement) in postes) {
    ajouter('fichesPoste', 'FDP', {
      'intitule': intitule,
      'rattachement': rattachement,
      'resume': 'Missions à compléter par la Direction.',
      'missions': <Object?>[],
      'missionsAcompleter': true,
      'redigee': false,
      'source': 'Poste de la Clinique Baguidi (organisation de démonstration) : missions à compléter par la Direction',
    });
  }
}

// --- congés ------------------------------------------------------------------------------------------------------------------------------------

typedef _Conge = ({String employeId, DateTime debut, DateTime fin});

/// Trois congés accordés dont un EN COURS au 07/11/2026 (TOUNGOUH, du 04 au 13/11). Aucun ne touche un agent soumis à un régime de garde.
List<_Conge> _conges(Contexte ctx, Fiche Function(String) agent, _Ajout ajouter) {
  final liste = <(String, String, DateTime, DateTime, String)>[
    ('m-002', 'Congé annuel', DateTime(2026, 9, 14), DateTime(2026, 9, 18), 'ZIME Nadège'),
    ('m-007', 'Absence autorisée', DateTime(2026, 10, 12), DateTime(2026, 10, 13), 'SANOUSSI Adamon'),
    ('m-008', 'Congé annuel', DateTime(2026, 11, 4), DateTime(2026, 11, 13), 'MABOUDOU Nawal'),
  ];
  final out = <_Conge>[];
  for (final (id, nature, debut, fin, remplacant) in liste) {
    final v = d.rhaCongeEnregistrable({
      'employeId': id,
      'nature': nature,
      'dateDebut': Contexte.date(debut),
      'dateFin': Contexte.date(fin),
      'remplacant': remplacant,
      'statutConge': 'valide',
      'motif': '',
      'fictif': true,
      'source': _sourceDemo,
    }, agent(id), reference: 'CG-${_pad(ctx.fiches('conges').length + 1, 4)}');
    ajouter('conges', 'CNG', v);
    out.add((employeId: id, debut: debut, fin: fin));
  }
  return out;
}

bool _enConge(List<_Conge> conges, String id, DateTime jour) => conges.any((c) => c.employeId == id && !jour.isBefore(c.debut) && !jour.isAfter(c.fin));

// --- planning ----------------------------------------------------------------------------------------------------------------------------------

const String _regimeMedecin = 'Médecins';
const String _regimeInfirmier = 'Infirmiers';

/// Le planning ne concerne que les fonctions SOUMISES à un régime de la clinique (`regimesTravail`) : le médecin (garde de 24 h, repos de 48 h, donc une
/// garde tous les quatre jours ici) et l'infirmier (garde soins, du lundi au vendredi). Direction, comptabilité et RH n'ont aucune vacation : elles pointent.
/// L'infirmier est en « garde soins » et non en « permanence » : le type ne produit donc aucune ligne de prime garde/permanence (la grille n'en donne
/// qu'à l'occurrence de « garde » et « permanence »).
void _planning(Contexte ctx, Fiche Function(String) agent, List<_Conge> conges, _Ajout ajouter) {
  final medecin = agent('m-004');
  final infirmier = agent('m-005');
  Fiche vacation(Fiche a, DateTime jour, String type, String regime) => {
        'date': Contexte.date(jour),
        'employeId': a['id'],
        'employe': a['nomComplet'],
        'fonction': a['fonction'],
        'service': a['service'],
        'type': type,
        'statut': 'validee',
        'regimeLibelle': regime,
      };
  var rangGarde = 0;
  for (final jour in _jours(ctx.joursOuvres(), tousLesJours: true)) {
    if (!_enConge(conges, '${medecin['id']}', jour) && jour.difference(Contexte.debutFenetre).inDays % 4 == 0) {
      ajouter('planning', 'PLN', vacation(medecin, jour, 'garde', _regimeMedecin), largeur: 5);
      rangGarde++;
    }
    if (jour.weekday <= DateTime.friday && !_enConge(conges, '${infirmier['id']}', jour)) {
      ajouter('planning', 'PLN', vacation(infirmier, jour, 'garde_soins', _regimeInfirmier), largeur: 5);
    }
  }
  ctx.note('rh_paie : $rangGarde gardes du médecin (régime Médecins, repos 48 h respecté), garde soins de l\'infirmier du lundi au vendredi');
}

/// Tous les jours de la fenêtre (dimanches compris) quand [tousLesJours], sinon les jours ouvrés de [source].
List<DateTime> _jours(List<DateTime> source, {bool tousLesJours = false}) => tousLesJours
    ? [for (var j = Contexte.debutFenetre; !j.isAfter(Contexte.finFenetre); j = DateTime(j.year, j.month, j.day + 1)) j]
    : source;

// --- présences ---------------------------------------------------------------------------------------------------------------------------------

/// Un pointage par agent et par jour ouvré (lundi au vendredi). Six retards signalés tirés dans le flux `rh_paie`, un absent justifié fixé, les congés en
/// `conge`. Le médecin ne pointe pas pendant le repos de 48 h qui suit une garde. Heures d'arrivée et de départ : valeurs de démonstration.
void _presences(Contexte ctx, Tirage t, Fiche Function(String) agent, List<_Conge> conges, _Ajout ajouter) {
  final gardes = {
    for (final p in ctx.fiches('planning'))
      if (p['type'] == 'garde') '${p['date']}'
  };
  bool repos(DateTime jour) => [1, 2].any((k) => gardes.contains(Contexte.date(DateTime(jour.year, jour.month, jour.day - k))));
  final agents = [for (var i = 1; i <= 8; i++) 'm-${_pad(i, 3)}'];
  final absent = ('m-006', DateTime(2026, 9, 8));

  // Les couples (agent, jour) concernés, dans l'ordre : on tire les retards parmi ceux qui pointent vraiment.
  final couples = <(String, DateTime)>[
    for (final jour in ctx.joursOuvres().where((j) => j.weekday <= DateTime.friday))
      for (final id in agents)
        if (!_enConge(conges, id, jour) && !(id == 'm-004' && repos(jour)) && !(id == absent.$1 && jour == absent.$2)) (id, jour)
  ];
  final retards = {for (final i in t.melanger([for (var i = 0; i < couples.length; i++) i]).take(6)) i};

  var rang = 0;
  for (final jour in ctx.joursOuvres().where((j) => j.weekday <= DateTime.friday)) {
    for (final id in agents) {
      final a = agent(id);
      final base = {
        'date': Contexte.date(jour),
        'employeId': id,
        'employe': a['nomComplet'],
        'matricule': a['matricule'],
        'service': a['service'],
      };
      if (_enConge(conges, id, jour)) {
        ajouter('presences', 'PRS', {...base, 'etat': 'conge', 'motif': 'Congé accordé'}, largeur: 5);
        continue;
      }
      if (id == 'm-004' && repos(jour)) continue;
      if (id == absent.$1 && jour == absent.$2) {
        ajouter('presences', 'PRS', {...base, 'etat': 'absent', 'motif': 'Absence justifiée : justificatif remis aux ressources humaines', 'justifie': true}, largeur: 5);
        continue;
      }
      final k = couples.indexWhere((c) => c.$1 == id && c.$2 == jour);
      final enRetard = retards.contains(k);
      final arrivee = enRetard ? '08:${_pad(t.entre(10, 50), 2)}' : '07:${_pad(t.entre(20, 58), 2)}';
      final depart = '${t.entre(16, 17)}:${_pad(t.entre(0, 59), 2)}';
      ajouter(
          'presences',
          'PRS',
          {
            ...base,
            'etat': enRetard ? 'retard' : 'present',
            'heureArrivee': arrivee,
            'heureDepart': depart,
            if (enRetard) 'motif': 'Retard signalé à l\'arrivée',
          },
          largeur: 5);
      rang++;
    }
  }
  ctx.note('rh_paie : $rang pointages de présence, 6 retards signalés, 1 absent justifié');
}

// --- heures supplémentaires ----------------------------------------------------------------------------------------------------------------------

/// Deux déclarations VALIDÉES : seules les validées entrent au brut (E691). Taux horaire et montant par `paiHeuresSupTransform`.
void _heuresSup(Contexte ctx, Fiche Function(String) agent, _Ajout ajouter) {
  final liste = [
    ('m-007', 'Septembre 2026', 6, DateTime(2026, 9, 26)),
    ('m-002', 'Octobre 2026', 4, DateTime(2026, 10, 24)),
  ];
  for (final (id, periode, heures, jour) in liste) {
    final v = d.paiHeuresSupTransform({
      'employeId': id,
      'periode': periode,
      'heures': heures,
      'majoration': 25,
      'motif': 'Surcroît d’activité',
      'valide': true,
      'date': Contexte.date(jour),
      'fictif': true,
      'source': _sourceDemo,
    }, agent(id), reference: () => d.paiReferenceSuivante('HS-', 4, ctx.collection('heuresSup').toutes));
    ajouter('heuresSup', 'HSU', v);
  }
}

// --- la paie -----------------------------------------------------------------------------------------------------------------------------------

d.PaiEntrees _entrees(Contexte ctx) => d.PaiEntrees(
      planning: ctx.fiches('planning'),
      evaluations: ctx.fiches('evaluations'),
      avances: ctx.fiches('avances'),
      participations: ctx.fiches('participations'),
      grille: ctx.fiches('grillePrimes'),
      historique: ctx.fiches('historiquePrimes'),
      heuresSup: ctx.fiches('heuresSup'),
      prets: ctx.fiches('pretsEtudes'),
      // Les deux bascules (NS 132, NS 131) sont OUVERTES par défaut : `modulesActifs` est vide, comme au poste neuf.
      primesNs132: d.paiActivites(ctx.collection('modulesActifs').toutes).primesNs132,
      sanctionsNs131: d.paiActivites(ctx.collection('modulesActifs').toutes).sanctionsNs131,
      obligationsFiscales: ctx.collection('obligationsFiscales').toutes,
      historiqueObligations: ctx.collection('historiqueObligations').toutes,
    );

/// Génère le lot d'un mois (par [auteur], un agent des RH) ; le valide si [validateur] est donné, en posant l'écriture et les retenues comme le fait
/// l'écran de validation.
void _lot(Contexte ctx, int mois, DateTime generation, {required Fiche auteur, required String auteurCompte, Fiche? validateur, String? validateurCompte, DateTime? validation, required _Ajout ajouter}) {
  final annee = 2026;
  final calculs = d.paiCalculerTous(ctx.fiches('personnel'), annee, mois, _entrees(ctx), Contexte.maintenant);
  final periode = d.paiPeriodeLibelle(annee, mois);
  for (final c in calculs) {
    final ref = d.paiReferenceSuivante('BP-', 5, ctx.collection('bulletins').toutes);
    final b = d.paiBulletinDe(c, ref, genereePar: '${auteur['nomComplet']}', genereeParId: auteurCompte, dateGeneration: Contexte.date(generation));
    ajouter('bulletins', 'BUL', {...b, 'salaireProvisoire': true, 'source': 'Calcul du moteur de paie sur salaire d’attente (fictif de démonstration)'}, largeur: 5);
  }
  if (validateur == null) return;

  final lot = [for (final b in ctx.fiches('bulletins')) if (b['periode'] == periode && b['statutBulletin'] == 'a_valider') b];
  final nom = '${validateur['nomComplet']}';
  final refus = d.paiControleSeparation(lot, nom, validateurId: validateurCompte) ?? d.paiControleNetNegatif(lot);
  if (refus != null) throw StateError('Validation de $periode refusée par le moteur : $refus');
  final date = Contexte.date(validation!);
  final piece = d.paiPieceDePaie(periode, lot, date: date, ecritures: ctx.collection('ecritures').toutes, montantTexte: (n) => '$n');
  if (!piece.ok) throw StateError('Écriture de paie de $periode refusée : ${piece.refus}');
  for (final f in piece.fiches) {
    ajouter('ecritures', 'ECR', {'statut': 'brouillon', ...f}, largeur: 5);
  }
  final imputations = d.paiImputationsDeRetenues(lot,
      prets: ctx.fiches('pretsEtudes'), avances: ctx.fiches('avances'), participations: ctx.fiches('participations'), date: date, acteur: nom);
  for (final i in imputations) {
    ctx.collection(i.collection).mettreAJour(i.id, i.champs, journaliser: false);
  }
  for (final b in lot) {
    ctx.collection('bulletins').mettreAJour(
        b['id'], {'statutBulletin': 'valide', 'validePar': nom, 'valideParId': validateurCompte, 'dateValidation': date, 'ecritureNumero': piece.numero},
        journaliser: false);
  }
}

void _paie(Contexte ctx, Fiche Function(String) agent, String Function(String) compteDe, _Ajout ajouter) {
  final rh1 = agent('m-003'); // MABOUDOU Nawal
  final rh2 = agent('m-008'); // TOUNGOUH A. Zoulkifouli
  final dir1 = agent('m-001'); // BAGUIDI Rafiou
  final dir2 = agent('m-006'); // SOKOU Peace

  // AOÛT : généré par les RH le 28/08, validé par la Direction le 31/08.
  _lot(ctx, 7, DateTime(2026, 8, 28),
      auteur: rh1, auteurCompte: compteDe('m-003'), validateur: dir1, validateurCompte: compteDe('m-001'), validation: DateTime(2026, 8, 31), ajouter: ajouter);

  // Avant le bulletin de septembre : l'avance est accordée (en cours de retenue), le prêt d'études aussi (première retenue en octobre).
  final zime = agent('m-007');
  final plafond = d.paiAvanceRefus(60000, zime);
  if (plafond != null) throw StateError(plafond);
  final avance = d.paiAvanceTransform({
    'employeId': 'm-007',
    'date': '2026-09-03',
    'montant': 60000,
    'nbMensualites': 3,
    'motif': 'Besoin personnel',
    'statutAvance': 'en_cours',
    'fictif': true,
    'source': _sourceDemo,
  }, zime, reference: () => d.paiReferenceSuivante('AVS-', 4, ctx.collection('avances').toutes));
  ajouter('avances', 'AVA', avance);
  final pret = d.paiPretTransform({
    'employeId': 'm-005',
    'nature': 'pret_etudes',
    'objet': 'Prêt d’études (fictif de démonstration)',
    'montant': 120000,
    'dateAccord': '2026-09-20',
    'premiereEcheance': '2026-10',
    'nbEcheances': 6,
    'autorisePar': '${dir1['nomComplet']}',
    'fictif': true,
    'source': _sourceDemo,
  }, agent('m-005'), reference: d.paiReferenceSuivante('PRT-', 4, ctx.collection('pretsEtudes').toutes));
  ajouter('pretsEtudes', 'PRT', pret);

  // SEPTEMBRE : généré le 28/09 par l'autre agent des RH, validé le 30/09 par l'autre membre de la Direction.
  _lot(ctx, 8, DateTime(2026, 9, 28),
      auteur: rh2, auteurCompte: compteDe('m-008'), validateur: dir2, validateurCompte: compteDe('m-006'), validation: DateTime(2026, 9, 30), ajouter: ajouter);

  // OCTOBRE : généré le 05/11, reste en brouillon (à valider).
  _lot(ctx, 9, DateTime(2026, 11, 5), auteur: rh1, auteurCompte: compteDe('m-003'), ajouter: ajouter);
}
