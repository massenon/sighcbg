/// Règles de l'écran « Reprise d'un poste » de la console de la mère (`mere-reprise-poste`) et de l'accueil d'un poste NEUF par un code de reprise
/// (Direction de Baguidi, 17/11/2026 : mise à jour du logiciel et changement de machine, E4608).
///
/// Une REPRISE d'identité remet à un poste neuf ce qui n'appartient qu'à l'ancien : ses plages de numéros de dossier et ses baux de stock (sans eux, la mère refuse les saisies de sa
/// file, `numero_hors_plage`) ; l'ancien poste est RÉVOQUÉ, jamais effacé (RG-14). Rien n'est décidé ici : ces fonctions ne font que LIRE ce que la mère annonce (durée de validité du code,
/// refus nommés, ce qu'elle a repris) et le rendre lisible. Aucune durée, aucun rôle, aucun nom de poste n'est écrit dans ce fichier.
library;

/// Un poste tel que la mère l'annonce (`GET /admin/etat`), réduit à ce que l'écran de reprise lit.
typedef RepPoste = ({String uuid, String etiquette, String role, bool revoque, DateTime? dernierContact, int derniereSeq});

/// Le genre d'appareil dont l'identité se reprend : un POSTE FILEUL. Un mobile se ré-appaire (code mobile) et la mère ne se « reprend » pas : elle se restaure (clé de la clinique, export).
const String repGenreReprenable = 'fileul';

/// Les postes dont l'identité peut être reprise : les fileuls, les ACTIFS d'abord puis les révoqués (un poste perdu et révoqué par prudence se reprend encore : ses plages restent les siennes
/// tant qu'aucun autre poste ne les a reprises ; c'est la mère qui le refuse, en nommant, quand il l'a été), par étiquette.
List<RepPoste> repPostesReprenables(Iterable<RepPoste> postes) {
  final l = [for (final p in postes) if (p.role == repGenreReprenable) p];
  int c(RepPoste a, RepPoste b) {
    if (a.revoque != b.revoque) return a.revoque ? 1 : -1;
    final n = (a.etiquette.isEmpty ? a.uuid : a.etiquette).toLowerCase().compareTo((b.etiquette.isEmpty ? b.uuid : b.etiquette).toLowerCase());
    return n != 0 ? n : a.uuid.compareTo(b.uuid);
  }

  l.sort(c);
  return l;
}

/// Nom d'un poste dans la liste : son étiquette, sinon son identifiant d'appairage.
String repNomPoste(RepPoste p) => p.etiquette.trim().isEmpty ? p.uuid : p.etiquette.trim();

/// L'étiquette proposée au poste NEUF : celle du poste qu'il remplace (le poste garde son nom ; l'agent peut la changer).
String repEtiquetteProposee(RepPoste ancien) => ancien.etiquette.trim();

/// La clé du RÉGLAGE de la mère : la durée de validité, en MINUTES, d'un code d'appairage (poste ordinaire, mobile, reprise d'un poste). Daté, borné (`min`/`max` de la définition) ; la mère le lit
/// à CHAQUE émission et RENVOIE la durée avec le code (`validite_s`) : aucun écran ne l'écrit (consigne de la Direction du 18/11/2026 : plus de valeur en dur).
const String cleValiditeCodeAppairage = 'mere.validiteCodeAppairageMinutes';

/// Durée de validité lisible, à partir des SECONDES que la mère annonce (`validite_s`) : « 15 minutes », « 1 heure », « 90 secondes ». Jamais une valeur supposée : une durée absente ou
/// non positive rend `null`, et l'écran dit « durée non communiquée par la mère ».
String? repDureeLisible(int? secondes) {
  if (secondes == null || secondes <= 0) return null;
  String u(int n, String un, String plusieurs) => '$n ${n > 1 ? plusieurs : un}';
  if (secondes % 3600 == 0) return u(secondes ~/ 3600, 'heure', 'heures');
  if (secondes % 60 == 0) return u(secondes ~/ 60, 'minute', 'minutes');
  if (secondes < 120) return u(secondes, 'seconde', 'secondes');
  return u((secondes / 60).ceil(), 'minute', 'minutes');
}

/// La phrase que les écrans d'appairage disent d'un code émis : la durée est CELLE QUE LA MÈRE ANNONCE (`validite_s`), jamais un nombre écrit dans l'écran. Une mère qui n'annonce rien : l'écran le dit.
String repPhraseValiditeCode(int? secondes) {
  final d = repDureeLisible(secondes);
  return d == null
      ? 'À usage unique. La durée de validité n’est pas communiquée par la mère : le code expire quand elle le décide.'
      : 'À usage unique, valable $d.';
}

/// Temps restant avant l'expiration que la mère a posée (`expire`, ms epoch) ; jamais négatif.
Duration repTempsRestant(int expireMs, int maintenantMs) => Duration(milliseconds: expireMs > maintenantMs ? expireMs - maintenantMs : 0);

/// « 12 min 05 s » : le compte à rebours d'un code affiché.
String repCompteARebours(Duration d) {
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  if (s >= 3600) return '${s ~/ 3600} h ${((s % 3600) ~/ 60).toString().padLeft(2, '0')} min';
  return '${s ~/ 60} min ${(s % 60).toString().padLeft(2, '0')} s';
}

/// Un refus LISIBLE : ce qui s'est passé, et le geste qui le corrige. Le code est celui de la mère, repris tel quel (jamais reformulé en un autre).
typedef RepRefus = ({String code, String motif, String geste});

/// Les refus que la reprise peut rencontrer, nommés. [motifMere] : le motif que la mère a écrit ; il prime pour un code qu'on ne connaît pas (on ne le masque jamais). Le code de reprise lui-même
/// n'entre jamais dans un refus.
RepRefus repRefus(String code, {String motifMere = ''}) {
  switch (code) {
    case 'appareil_inconnu':
      return (code: code, motif: 'La mère ne connaît pas ce poste, ou ce n’est pas un poste fileul : il n’y a rien à reprendre.', geste: 'Choisissez un poste de la liste « Postes appairés » (relue depuis la mère), puis recommencez.');
    case 'deja_repris':
      return (code: code, motif: 'Ce poste a déjà été repris par un autre poste : ses plages de numéros et ses baux ne sont plus les siens.', geste: 'Reprenez le poste qui l’a remplacé (c’est lui qui porte désormais ces plages), ou appairez un poste ordinaire.');
    case 'code_expire':
      return (code: code, motif: 'Ce code de reprise a expiré.', geste: 'Générez-en un nouveau sur la mère (écran « Reprise d’un poste »), puis saisissez-le sur le poste neuf.');
    case 'code_utilise':
      return (code: code, motif: 'Ce code de reprise a déjà servi (usage unique).', geste: 'Générez-en un nouveau sur la mère si le poste neuf n’est pas encore appairé.');
    case 'code_invalide' || 'code_inconnu':
      return (code: code, motif: 'Code inconnu de la mère.', geste: 'Vérifiez la saisie (le code se lit lettre pour lettre) ou générez-en un nouveau.');
    case 'admin_requis':
      return (code: code, motif: 'La mère a refusé la demande : le secret d’administration de ce poste n’est pas reconnu.', geste: 'Ce poste doit être le poste mère, avec son secret d’administration ; sinon, faites la demande depuis la mère.');
    case 'acces_refuse':
      return (code: code, motif: 'Votre rôle ne détient pas le droit « Émettre un code de reprise d’un poste ».', geste: 'La matrice des rôles (fiche du rôle › gestes réservés) l’accorde ; demandez-le à l’administrateur ou à la Directrice Administrative.');
    case 'mere_injoignable':
      return (code: code, motif: 'La mère ne répond pas.', geste: 'Vérifiez que le service de la mère est démarré sur ce poste, puis recommencez.');
    default:
      return (code: code, motif: motifMere.isEmpty ? 'Refus de la mère.' : motifMere, geste: 'Relevez le code du refus pour l’exploitant.');
  }
}

/// Ce que la mère rapporte d'une reprise passée à l'appairage (`reprise` : `{de, plages, baux}`), déjà lu.
typedef RepRepriseFaite = ({String de, int plages, int baux});

/// Lit le compte rendu de la mère ; `null` si ce n'était pas une reprise (appairage ordinaire) ou si la forme est inattendue.
RepRepriseFaite? repLireRepriseFaite(Object? brut) {
  if (brut is! Map) return null;
  final de = brut['de'];
  if (de is! String || de.isEmpty) return null;
  int n(Object? v) => v is num ? v.toInt() : 0;
  return (de: de, plages: n(brut['plages']), baux: n(brut['baux']));
}

/// La phrase que le poste NEUF affiche une fois appairé par un code de reprise : ce qui est repris, et ce qui est révoqué.
String repPhraseRepriseFaite(RepRepriseFaite r) {
  String s(int n, String un, String plusieurs) => '$n ${n > 1 ? plusieurs : un}';
  return 'Reprise d’identité : ce poste remplace le poste ${r.de}. La mère lui a passé ${s(r.plages, 'plage de numéros', 'plages de numéros')} et ${s(r.baux, 'bail de stock', 'baux de stock')}, '
      'et a révoqué l’ancien poste (il reste au registre, RG-14). Les saisies de la file de l’ancien poste, si son export a été repris ici, partent à la mère sans doublon.';
}

/// Ce que le poste mère écrit au JOURNAL quand un code de reprise est émis : QUI est repris, jusqu'à quand le code vaut. JAMAIS le code lui-même, ni rien dont on le déduirait.
Map<String, Object?> repJournalEmission({required String uuidAncien, required String etiquetteAncien, int? expireMs, int? validiteSecondes}) => {
      'poste': uuidAncien,
      'etiquette': etiquetteAncien,
      if (expireMs != null) 'expire': expireMs,
      if (validiteSecondes != null) 'validite_s': validiteSecondes,
    };
