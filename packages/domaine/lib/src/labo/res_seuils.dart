/// LES SEUILS DE VARIATION BRUTALE (« delta check ») — lot A2 des antériorités du laboratoire. Port du COMPORTEMENT du moteur de la clinique sœur
/// (`SIGH.laboSeuils`), non de son code : fonctions pures, la fiche arrive en argument, le verdict dit ce qu'il faut écrire.
///
/// Un seuil dit de combien une variable NUMÉRIQUE peut bouger entre deux mesures rendues du même patient avant que le laboratoire s'arrête pour relire.
/// Cinq règles, toutes tenues ICI (le comparatif, l'écran de validation biologique et l'écran de réglage les appellent) :
///  1. AUCUN seuil par défaut : aucun n'est semé ni proposé, aucun document de cadrage n'en donne ; c'est une décision du biologiste médical. Un seuil
///     vide veut dire « pas d'alerte configurée », jamais zéro (zéro et négatif sont refusés en le disant).
///  2. DEUX états. « Enregistré » : saisi, SANS EFFET. « Validé » : en vigueur. Enregistrer garde l'état Enregistré, même pour le profil qui peut
///     valider ; Valider est un second geste, motivé, qui fait passer de Enregistré à Validé (demande explicite de la Direction).
///  3. VALIDER est un GESTE RÉSERVÉ, un DROIT DE LA FICHE de rôle (`droitsGestes`, lot B : [gesteValiderSeuil] du référentiel des gestes réservés,
///     `gestes_reserves.dart`), jamais un nom de rôle écrit ici ni un droit d'écran. Le Biologiste médical le détient d'origine ; une fiche l'accorde ou le
///     retire à un rôle, à chaud. Le moteur REVÉRIFIE : masquer un bouton ne protège rien. Décisions de la Direction du 13/11/2026, inchangées : l'administrateur
///     système ne valide pas par défaut (il n'est pas dans l'origine, et « sans fiche, tous les droits » ne vaut pas pour un geste réservé : aucune exception de
///     nom de rôle n'est donc nécessaire) mais la Direction peut le lui accorder ; la fonction du technicien de laboratoire qui valide par intérim est exclue
///     par défaut, et accordable par le geste [gesteValiderSeuilInterim] sur la fiche du rôle sous lequel il se connecte.
///     L'administrateur garde ENREGISTRER (éditer) : régler un seuil sans effet n'engage personne, seule la validation rend le seuil opposable.
///  4. Une version VALIDÉE est IMMUABLE : la modifier AJOUTE une version datée, l'ancienne reste lisible. Une mesure se juge au seuil EN VIGUEUR À LA
///     DATE de sa validation biologique (à aujourd'hui tant qu'elle n'est pas rendue) : une alerte déjà levée garde le seuil sous lequel elle l'a été.
///     La date d'effet ne peut pas être passée.
///  5. L'alerte SIGNALE, elle ne bloque jamais et ne crée aucune notification (donc aucune donnée médicale hors de l'écran). DÉLAI MAXIMAL entre deux
///     mesures (lot B) : un nombre entier de jours, VIDE par défaut (aucun document ne le fixe, aucune valeur n'est proposée), porté par la fiche du seuil
///     (même version, même validation). Au-delà, la variation n'est PAS ÉVALUÉE et le verdict le dit (« non évalué » n'est pas « pas d'alerte »).
/// FORME DU SEUIL (décidée par la Direction le 13/11/2026, « l'une ou l'autre ») : une variation ABSOLUE (unité de la variable) et/ou RELATIVE (%) ;
/// l'alerte part dès que l'UNE des deux est atteinte. Si la valeur précédente est nulle ou proche de zéro ([epsilonValeurPrecedente]), le pourcentage
/// n'est PAS calculé (un pourcentage est trompeur près de zéro) : seul le seuil absolu juge, et l'écran dit que le relatif n'a pas pu s'évaluer.
library;

import 'res_habilitations.dart';

/// Un refus NOMMÉ : le code, ce qui s'est passé, et le geste qui débloque. Rien n'est écrit.
class RefusSeuil {
  const RefusSeuil(this.code, this.motif, this.geste);
  final String code;
  final String motif;
  final String geste;
  @override
  String toString() => motif;
}

/// La ligne de journal d'un geste (RG-12). L'extrait est court : la trace complète est la version elle-même, immuable une fois validée.
class JournalSeuil {
  const JournalSeuil(this.action, this.reference, this.avant, this.apres);
  final String action;
  final String reference;
  final Object? avant;
  final Object? apres;
}

/// Ce qu'un geste décide d'écrire : une CRÉATION ([fiche], sans identifiant), ou une MISE À JOUR ([id] + [patch]) ; ou un refus.
class VerdictSeuil {
  const VerdictSeuil.refus(RefusSeuil r)
      : ok = false,
        refus = r,
        creation = false,
        fiche = null,
        id = null,
        patch = null,
        journal = null,
        archivage = false;
  const VerdictSeuil.ok({this.creation = false, this.fiche, this.id, this.patch, this.journal, this.archivage = false})
      : ok = true,
        refus = null;
  final bool ok;
  final RefusSeuil? refus;
  final bool creation;
  final FicheLabo? fiche;
  final String? id;
  final FicheLabo? patch;
  final JournalSeuil? journal;

  /// Abandon d'un brouillon : la fiche s'ARCHIVE (RG-14), elle ne se supprime pas.
  final bool archivage;
}

/// L'état affiché d'une variable : `aucun` | `enregistre` | `valide` | `enregistre_sur_valide` (un brouillon attend sa validation, la version
/// validée reste en force).
class EtatSeuil {
  const EtatSeuil(this.variableId, this.etat, this.versions, this.brouillon, this.enVigueur, this.retire, this.aVenir);
  final String variableId;
  final String etat;
  final List<FicheLabo> versions;
  final FicheLabo? brouillon;
  final FicheLabo? enVigueur;
  final bool retire;
  final FicheLabo? aVenir;
}

/// Le jour (`AAAA-MM-JJ`) d'une date ISO ou d'un instant ; vide = [aujourdhui].
String jourSeuil(Object? date, DateTime aujourdhui) {
  final s = date == null ? '' : '$date';
  if (s.isEmpty) return _iso(aujourdhui);
  return s.length > 10 ? s.substring(0, 10) : s;
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _dateFr(String iso) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(iso);
  return m == null ? iso : '${m.group(3)}/${m.group(2)}/${m.group(1)}';
}

/// Les versions d'une variable, de la plus ancienne à la plus récente. [seuilsActifs] : les fiches `seuilsDelta` NON archivées.
List<FicheLabo> versionsSeuil(String variableId, Iterable<FicheLabo> seuilsActifs) {
  final l = [for (final x in seuilsActifs) if (x['variableId'] == variableId) x];
  l.sort((a, b) => _version(a).compareTo(_version(b)));
  return l;
}

int _version(FicheLabo x) => (x['version'] as num?)?.toInt() ?? 0;

/// Le seuil VALIDÉ en vigueur à une date : la version validée la plus récente dont la date d'effet est atteinte. Jamais un Enregistré.
FicheLabo? seuilEnVigueur(String variableId, Object? date, Iterable<FicheLabo> seuilsActifs, {required DateTime aujourdhui}) {
  final d = jourSeuil(date, aujourdhui);
  final c = [
    for (final x in versionsSeuil(variableId, seuilsActifs))
      if (x['etat'] == 'valide' && '${x['dateEffet'] ?? ''}'.compareTo(d) <= 0) x
  ]..sort((a, b) {
      final k = '${a['dateEffet'] ?? ''}'.compareTo('${b['dateEffet'] ?? ''}');
      return k != 0 ? k : _version(a).compareTo(_version(b));
    });
  return c.isEmpty ? null : c.last;
}

FicheLabo? brouillonSeuil(String variableId, Iterable<FicheLabo> seuilsActifs) {
  for (final x in versionsSeuil(variableId, seuilsActifs)) {
    if (x['etat'] == 'enregistre') return x;
  }
  return null;
}

EtatSeuil etatSeuil(String variableId, Iterable<FicheLabo> seuilsActifs, {required DateTime aujourdhui}) {
  final vig = seuilEnVigueur(variableId, null, seuilsActifs, aujourdhui: aujourdhui);
  final b = brouillonSeuil(variableId, seuilsActifs);
  final vs = versionsSeuil(variableId, seuilsActifs);
  final actif = vig != null && vig['retrait'] != true ? vig : null;
  final auj = _iso(aujourdhui);
  FicheLabo? aVenir;
  for (final x in vs) {
    if (x['etat'] == 'valide' && '${x['dateEffet'] ?? ''}'.compareTo(auj) > 0) {
      aVenir = x;
      break;
    }
  }
  return EtatSeuil(variableId, b != null ? (actif != null ? 'enregistre_sur_valide' : 'enregistre') : (actif != null ? 'valide' : 'aucun'), vs, b, actif,
      vig != null && vig['retrait'] == true, aVenir);
}

double? _nombre(Object? x) {
  if (x == null || x == '') return null;
  if (x is num) return x.toDouble();
  return double.tryParse('$x'.trim().replaceAll(',', '.'));
}

String _chaine(num n) => n == n.truncateToDouble() ? '${n.toInt()}' : '$n';

/// « 1 G/l ou 20 % » : ce que dit un seuil, dans l'unité de la variable ([suffixe] : « G/l » précédé d'une espace, ou vide).
String texteSeuil(FicheLabo s, [String suffixe = '']) {
  final t = <String>[];
  final a = _nombre(s['ecartAbsolu']), r = _nombre(s['ecartRelatif']);
  if (a != null) t.add('${_chaine(a)}$suffixe');
  if (r != null) t.add('${_chaine(r)} %');
  return t.join(' ou ');
}

/// Le délai d'un seuil, pour l'écran de réglage (vide quand aucun délai n'est réglé).
String texteDelai(FicheLabo s) {
  final n = _nombre(s['delaiMaxJours']);
  return n == null ? '' : 'délai entre deux mesures : ${n.toInt()} jour${n > 1 ? 's' : ''}';
}

/// Le contrôle de date d'effet : jamais passée, jamais antérieure à une version déjà validée.
RefusSeuil? controleDatesSeuil(String variableId, String d, Iterable<FicheLabo> seuilsActifs, {required DateTime aujourdhui}) {
  final auj = _iso(aujourdhui);
  if (d.compareTo(auj) < 0) {
    return RefusSeuil(
        'DATE_EFFET_PASSEE',
        'La date d’effet (${_dateFr(d)}) est passée : un seuil ne s’applique jamais en arrière, une alerte déjà levée garde le seuil sous lequel elle l’a été.',
        'Choisir une date d’effet à partir d’aujourd’hui (${_dateFr(auj)}).');
  }
  final valides = [for (final x in versionsSeuil(variableId, seuilsActifs)) if (x['etat'] == 'valide') x]..sort((a, b) {
      final k = '${a['dateEffet'] ?? ''}'.compareTo('${b['dateEffet'] ?? ''}');
      return k != 0 ? k : _version(a).compareTo(_version(b));
    });
  if (valides.isNotEmpty && d.compareTo('${valides.last['dateEffet']}') < 0) {
    final der = valides.last;
    return RefusSeuil(
        'DATE_EFFET_ANTERIEURE',
        'La date d’effet (${_dateFr(d)}) est antérieure à la version ${der['version']} déjà validée (${_dateFr('${der['dateEffet']}')}).',
        'Choisir une date d’effet au plus tôt le ${_dateFr('${der['dateEffet']}')}.');
  }
  return null;
}

/// ENREGISTRER : saisit un seuil (ou son retrait), état Enregistré, SANS EFFET. Une seconde saisie remplace le brouillon, jamais une version validée.
/// [droitEditer] : le droit d'éditer l'écran des valeurs de référence, lu à la matrice par l'appelant et REVÉRIFIÉ ici.
VerdictSeuil enregistrerSeuil({
  required FicheLabo? variable,
  required String variableId,
  required Iterable<FicheLabo> seuilsActifs,
  required bool droitEditer,
  required String profil,
  Object? ecartAbsolu,
  Object? ecartRelatif,
  bool retrait = false,
  Object? delaiMaxJours,
  Object? dateEffet,
  String? note,
  required String acteur,
  required String role,
  required DateTime maintenant,
}) {
  if (!droitEditer) {
    return VerdictSeuil.refus(RefusSeuil('DROIT_REFUSE', 'Le profil $profil ne règle pas les seuils de variation brutale (écran « Valeurs de référence »).',
        'Demander à un profil qui modifie les valeurs de référence du laboratoire.'));
  }
  if (variable == null || variable['statut'] == 'archive') {
    return VerdictSeuil.refus(RefusSeuil('VARIABLE_INTROUVABLE', 'Aucune variable « $variableId » au catalogue du laboratoire.',
        'Choisir une variable à l’écran « Valeurs de référence ».'));
  }
  final accomp = variable['accompagnement'];
  if (variable['type'] != 'numerique' || (accomp != null && accomp != false)) {
    return VerdictSeuil.refus(RefusSeuil(
        'VARIABLE_NON_NUMERIQUE',
        'Un seuil de variation ne se pose que sur une variable numérique : « ${variable['libelle']} » est de type « ${variable['type']} » et se compare en texte.',
        'Choisir une variable numérique.'));
  }
  final abs = _nombre(ecartAbsolu), rel = _nombre(ecartRelatif);
  if ((abs != null && !(abs > 0)) || (rel != null && !(rel > 0))) {
    return const VerdictSeuil.refus(RefusSeuil('SEUIL_INVALIDE', 'Un seuil est un nombre strictement positif : zéro alerterait à chaque mesure.',
        'Saisir un nombre supérieur à zéro, ou laisser vide pour ne pas alerter.'));
  }
  // LE DÉLAI MAXIMAL ENTRE DEUX MESURES : un nombre ENTIER de jours, au moins 1, VIDE par défaut. Il se pose AVEC le seuil : même version, même validation.
  final delai = _nombre(delaiMaxJours);
  if (delai != null && !(delai == delai.truncateToDouble() && delai >= 1)) {
    return const VerdictSeuil.refus(RefusSeuil('DELAI_INVALIDE', 'Le délai maximal entre deux mesures est un nombre entier de jours, au moins 1 : zéro refuserait d’évaluer toute variation.',
        'Saisir un nombre entier de jours supérieur à zéro, ou laisser vide pour n’imposer aucun délai.'));
  }
  if (retrait) {
    if (delai != null) {
      return const VerdictSeuil.refus(RefusSeuil('RETRAIT_AVEC_VALEURS', 'Retirer le seuil ne porte aucun délai.', 'Vider le délai, ou décocher le retrait.'));
    }
    if (abs != null || rel != null) {
      return const VerdictSeuil.refus(RefusSeuil('RETRAIT_AVEC_VALEURS', 'Retirer le seuil ne porte aucune valeur.', 'Vider les deux champs, ou décocher le retrait.'));
    }
    if (seuilEnVigueur(variableId, '9999-12-31', seuilsActifs, aujourdhui: maintenant) == null) {
      return VerdictSeuil.refus(RefusSeuil('RIEN_A_RETIRER', 'Aucun seuil validé sur « ${variable['libelle']} » : il n’y a rien à retirer.', 'Fermer la fenêtre.'));
    }
  } else if (abs == null && rel == null) {
    return const VerdictSeuil.refus(RefusSeuil('SEUIL_VIDE', 'Aucune valeur saisie : un seuil vide veut dire « pas d’alerte configurée », il ne s’enregistre pas.',
        'Saisir une variation absolue ou relative, ou ne rien enregistrer.'));
  }
  final d = jourSeuil(dateEffet, maintenant);
  final refusDate = controleDatesSeuil(variableId, d, seuilsActifs, aujourdhui: maintenant);
  if (refusDate != null) return VerdictSeuil.refus(refusDate);
  final b = brouillonSeuil(variableId, seuilsActifs);
  final champs = <String, Object?>{
    'ecartAbsolu': abs,
    'ecartRelatif': rel,
    'delaiMaxJours': delai?.toInt(),
    'retrait': retrait,
    'dateEffet': d,
    'note': (note ?? '').trim().isEmpty ? null : note!.trim(),
    'enregistrePar': acteur,
    'enregistreLe': maintenant.toUtc().toIso8601String(),
    'enregistreRole': role,
  };
  final derniere = versionsSeuil(variableId, seuilsActifs).fold<int>(0, (m, x) => _version(x) > m ? _version(x) : m);
  final apres = {'v': b != null ? _version(b) : derniere + 1, 'du': d, 'abs': abs, 'rel': rel, 'delai': delai?.toInt(), 'retrait': retrait};
  if (b != null) {
    return VerdictSeuil.ok(
        id: '${b['id']}',
        patch: champs,
        journal: JournalSeuil('Seuil de variation enregistré (sans effet)', '${variable['code']}', {'abs': b['ecartAbsolu'], 'rel': b['ecartRelatif'], 'du': b['dateEffet']}, apres));
  }
  return VerdictSeuil.ok(
      creation: true,
      fiche: {
        'variableId': variableId,
        'variableCode': variable['code'],
        'variableLibelle': variable['libelle'],
        'examen': variable['examen'],
        'examenLibelle': variable['examenLibelle'],
        'unite': variable['unite'],
        'version': derniere + 1,
        'etat': 'enregistre',
        'valideLe': null,
        'validePar': null,
        'valideRole': null,
        'motifValidation': null,
        'statut': 'actif',
        ...champs,
      },
      journal: JournalSeuil('Seuil de variation enregistré (sans effet)', '${variable['code']}', null, apres));
}

/// Peut-on valider avec CETTE fonction de session ? Le droit du geste est la première porte ; la fonction exclut PAR DÉFAUT le technicien de laboratoire qui
/// signe par intérim (il ne valide pas un seuil) — sauf si la fiche accorde [gesteValiderSeuilInterim] (l'appelant le lit et passe `true`). Une fonction non
/// déclarée (ou inconnue) laisse le droit du geste décider.
bool fonctionPeutValiderSeuil(SessionLabo? session) {
  final f = (session?.fonction ?? '').trim();
  if (f.isEmpty) return true;
  final cap = capacitesLabo[f];
  if (cap == null) return true;
  return cap.validerBiologique == true;
}

/// VALIDER : le brouillon devient la version en vigueur à sa date d'effet. Deux droits revérifiés ICI : [droitValider] (le geste réservé de la fiche, lu par
/// l'appelant) et [fonctionHabilitee] ([fonctionPeutValiderSeuil], ou l'intérim accordé par la fiche). Motif obligatoire.
VerdictSeuil validerSeuil({
  required String variableId,
  required Iterable<FicheLabo> seuilsActifs,
  required bool droitValider,
  required bool fonctionHabilitee,
  required String profil,
  String? motif,
  required String acteur,
  required String libelleRole,
  required DateTime maintenant,
}) {
  if (!droitValider) {
    return VerdictSeuil.refus(RefusSeuil(
        'VALIDATION_RESERVEE',
        'Valider un seuil de variation brutale est un droit réservé (geste « Valider un seuil » de la fiche de rôle) : le profil $profil ne le détient pas.',
        'Demander au Biologiste médical de valider depuis son poste, ou faire accorder le geste « Valider un seuil » à ce rôle par un administrateur (Rôles et permissions, gestes réservés).'));
  }
  if (!fonctionHabilitee) {
    return VerdictSeuil.refus(RefusSeuil(
        'FONCTION_NON_HABILITEE',
        'La fonction exercée par $acteur ne porte pas la validation biologique : le technicien de laboratoire, même par intérim, ne valide pas un seuil de variation, sauf si la fiche de son rôle l’y autorise.',
        'Demander au Biologiste médical de valider depuis son poste, ou faire accorder le geste « Valider un seuil par intérim » à ce rôle (Rôles et permissions, gestes réservés).'));
  }
  final b = brouillonSeuil(variableId, seuilsActifs);
  if (b == null) {
    return const VerdictSeuil.refus(RefusSeuil('SEUIL_NON_ENREGISTRE', 'Aucun seuil Enregistré à valider sur cette variable : un seuil se saisit et s’enregistre d’abord.',
        'Régler le seuil, l’enregistrer, puis le valider.'));
  }
  if ((motif ?? '').trim().isEmpty) {
    return const VerdictSeuil.refus(RefusSeuil('MOTIF_OBLIGATOIRE', 'Le motif de la validation est obligatoire : il dit sur quoi le seuil s’appuie.', 'Saisir le motif, puis valider.'));
  }
  final refusDate = controleDatesSeuil(variableId, '${b['dateEffet']}', seuilsActifs, aujourdhui: maintenant);
  if (refusDate != null) {
    return VerdictSeuil.refus(RefusSeuil(refusDate.code, refusDate.motif,
        'Enregistrer de nouveau le seuil avec une date d’effet à partir d’aujourd’hui, puis le valider.'));
  }
  final m = motif!.trim();
  return VerdictSeuil.ok(
      id: '${b['id']}',
      patch: {
        'etat': 'valide',
        'valideLe': maintenant.toUtc().toIso8601String(),
        'validePar': acteur,
        'valideRole': libelleRole,
        'motifValidation': m,
      },
      journal: JournalSeuil('Seuil de variation validé', '${b['variableCode']}', {'etat': 'enregistre'},
          {'v': _version(b), 'du': b['dateEffet'], 'abs': b['ecartAbsolu'], 'rel': b['ecartRelatif'], 'motif': m.length > 40 ? m.substring(0, 40) : m}));
}

/// Abandonne le brouillon (archivage RG-14, jamais une suppression) : la version validée, s'il y en a une, reste en force.
VerdictSeuil abandonnerSeuil({
  required String variableId,
  required Iterable<FicheLabo> seuilsActifs,
  required bool droitEditer,
  required String profil,
}) {
  if (!droitEditer) {
    return VerdictSeuil.refus(RefusSeuil('DROIT_REFUSE', 'Le profil $profil ne règle pas les seuils de variation brutale.',
        'Demander à un profil qui modifie les valeurs de référence du laboratoire.'));
  }
  final b = brouillonSeuil(variableId, seuilsActifs);
  if (b == null) {
    return const VerdictSeuil.refus(RefusSeuil('SEUIL_NON_ENREGISTRE', 'Aucun seuil Enregistré à abandonner sur cette variable.', 'Fermer la fenêtre.'));
  }
  return VerdictSeuil.ok(
      id: '${b['id']}',
      archivage: true,
      journal: JournalSeuil('Seuil de variation abandonné (brouillon)', '${b['variableCode']}', {'etat': 'enregistre', 'abs': b['ecartAbsolu'], 'rel': b['ecartRelatif']},
          {'statut': 'archive'}));
}

/// La garde du magasin (`S.garder`) : une version VALIDÉE est immuable, d'où qu'arrive l'écriture. [avant] : la fiche telle qu'elle est au magasin
/// (`null` à l'insertion). Rend le motif du refus ou `null`.
String? gardeSeuil(String operation, FicheLabo fiche, FicheLabo? avant) {
  if (operation == 'inserer') {
    return avant != null ? 'Le seuil « ${fiche['id']} » existe déjà : une version ne se réécrit pas.' : null;
  }
  if (avant == null) return null;
  if (operation == 'archiver') {
    return avant['etat'] == 'valide'
        ? 'Une version de seuil validée ne s’archive pas : elle se remplace par une nouvelle version, et reste lisible (RG-14).'
        : null;
  }
  if (operation != 'modifier') return null;
  if (avant['etat'] == 'valide') return 'Un seuil validé est IMMUABLE : le modifier ajoute une version datée, il ne réécrit pas l’ancienne.';
  final vide = fiche['valideLe'] == null || fiche['valideLe'] == '' || fiche['validePar'] == null || fiche['validePar'] == '' || '${fiche['motifValidation'] ?? ''}'.trim().isEmpty;
  if (fiche['etat'] == 'valide' && vide) return 'Un seuil ne devient « validé » qu’avec son auteur, sa date et son motif.';
  return null;
}

/// Une raison d'alerte : le seuil atteint et la mesure qui l'atteint.
class RaisonAlerte {
  const RaisonAlerte(this.type, this.seuil, this.mesure);
  final String type;
  final double seuil;
  final double mesure;
}

/// L'alerte d'une variation. [alerte] est vrai quand le seuil est atteint ; [nonEvaluable] quand un seuil purement relatif ne peut s'évaluer (valeur
/// précédente nulle : pas de pourcentage inventé).
class AlerteVariation {
  const AlerteVariation(this.alerte, this.seuil, this.raisons, this.nonEvaluable,
      {this.nonEvalue, this.ageJours, this.delaiMaxJours, this.ageInconnu = false});
  final bool alerte;
  final FicheLabo seuil;
  final List<RaisonAlerte> raisons;
  final bool nonEvaluable;

  /// `'delai'` quand la mesure précédente est plus ancienne que le délai réglé : la variation n'est PAS évaluée (« non évalué » n'est pas « pas d'alerte »).
  final String? nonEvalue;

  /// L'âge de la mesure précédente en jours de calendrier (`null` : incalculable), et le délai réglé sur le seuil (`null` : aucun).
  final int? ageJours;
  final int? delaiMaxJours;

  /// Un délai est réglé mais l'âge est incalculable : ni zéro ni dépassé, la variation s'évalue et l'écran le dit.
  final bool ageInconnu;
}

/// Les versions de seuil à l'état Enregistré (sans effet), toutes variables : ce que le centre des validations compte. [seuilsActifs] : les fiches
/// `seuilsDelta` NON archivées. Lu à chaque appel, jamais écrit.
({int total, List<String> variables}) seuilsEnAttente(Iterable<FicheLabo> seuilsActifs) {
  final l = [for (final x in seuilsActifs) if (x['etat'] == 'enregistre') x];
  return (total: l.length, variables: [for (final x in l) '${x['variableId']}']);
}
