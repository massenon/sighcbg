import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../core/service_installation.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../../shell/gestes_ecran.dart';

/// `cfg-fiches-aide` — « Fiches d'aide de l'assistant » : rédiger, valider et archiver les fiches que l'assistant cite (intentions I26 « comment faire » et I27 « c'est quoi »).
///
/// L'assistant ne répond JAMAIS de mémoire : il cite une fiche écrite et VALIDÉE, avec son validateur nommé et la date, sinon il dit « pas de fiche validée ». Cet écran ne livre AUCUN contenu : il porte le
/// gabarit vide, la liste des neuf fiches attendues (relue du document des 100 questions) avec leur statut CALCULÉ, et les gestes. Le contenu est écrit puis validé par la Direction ; une fiche qui
/// engage un professionnel (la check-liste du bloc) ne se valide qu'avec le geste de ce professionnel, son nom et la date.
///
/// Placement : la CONFIGURATION de la clinique (l'assistant est un réglage de ce que la clinique dit à ses agents) ; la rédaction est le droit d'ÉCRIRE l'écran (matrice), la validation est un GESTE
/// RÉSERVÉ distinct (`fiches_aide_valider`). Une commande interdite est ABSENTE, jamais grisée. La liste des rôles auxquels une fiche peut être réservée est celle de la MATRICE.
class EcranFichesAide extends StatefulWidget with EcranMaquette {
  const EcranFichesAide({super.key});
  @override
  String get titre => 'Fiches d’aide de l’assistant';
  @override
  String get description => 'Rédiger, valider et archiver les fiches d’aide et de définition que l’assistant cite, avec la liste des fiches attendues et leur état.';
  @override
  String get regle =>
      'L’assistant ne cite qu’une fiche VALIDÉE, avec son validateur nommé et la date. Celui qui écrit une fiche ne la valide pas ; une fiche validée ne se réécrit pas (on la révise) ; rien n’est supprimé (archivage, RG-14). '
      'Une fiche qui engage un professionnel exige son nom et sa date.';

  @override
  State<EcranFichesAide> createState() => _EtatFichesAide();
}

String _jour(Object? v) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch('${v ?? ''}');
  return m == null ? '—' : '${m.group(3)}/${m.group(2)}/${m.group(1)}';
}

class _EtatFichesAide extends State<EcranFichesAide> {
  ControleurFormulaire? _ctl;
  String? _edition; // l'identifiant de la fiche en cours de modification ; null = création
  String? _aValider;
  String? _aArchiver;
  final _pro = TextEditingController();
  final _proLe = TextEditingController();
  final _motif = TextEditingController();
  RefusFicheAide? _refus;
  String? _confirmation;

  @override
  void dispose() {
    _pro.dispose();
    _proLe.dispose();
    _motif.dispose();
    _ctl?.dispose();
    super.dispose();
  }

  // --- ce que la matrice et le manifeste disent ---------------------------------------------------------------------------------------------------------------

  List<OptionChamp> _rolesMatrice(ContexteEcran c) {
    final m = c.donnees?.matrice;
    if (m == null) return const [];
    return [for (final r in m.rolesBruts) if (!m.estArchive('${r['id']}')) OptionChamp('${r['id']}', m.libelle('${r['id']}') ?? '${r['id']}')];
  }

  List<OptionChamp> _ecrans(ContexteEcran c) => [for (final e in c.donnees?.manifeste.tousLesEcrans ?? const <EcranNav>[]) if (!e.hub) OptionChamp(e.id, '${e.label} (${e.id})')];

  // --- le formulaire ------------------------------------------------------------------------------------------------------------------------------------------

  ControleurFormulaire _formulaire(ContexteEcran c, Map<String, Object?> initial) {
    final domaines = [for (final d in fichesAideDomainesPro) OptionChamp(d.id, d.libelle)];
    final attendues = [for (final a in fichesAideAttendues) OptionChamp('${a.numero}', 'Q${a.numero} — ${a.question}')];
    return ControleurFormulaire([
      const ChampDef.section('Intention et titre'),
      ChampDef(
          nom: 'type',
          libelle: 'Intention (type de réponse)',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.demi,
          options: [for (final e in ficheAideLibellesTypes.entries) OptionChamp(e.key, e.value)]),
      const ChampDef(nom: 'titre', libelle: 'Titre', requis: true, col: ColChamp.demi, aide: 'Le titre que l’assistant affiche au-dessus de la réponse.'),
      const ChampDef(
          nom: 'motsCles',
          libelle: 'Mots-clés',
          type: TypeChamp.textarea,
          lignes: 3,
          requis: true,
          col: ColChamp.plein,
          aide: 'Une expression par ligne : ce que l’agent écrirait dans sa question (ex. « courrier entrant »). Sans mot-clé, l’assistant ne reconnaîtrait jamais la fiche.'),
      const ChampDef.section('Contenu'),
      const ChampDef(
          nom: 'etapes',
          libelle: 'Pas à pas',
          type: TypeChamp.textarea,
          lignes: 6,
          col: ColChamp.plein,
          condition: (controle: 'type', quand: [ficheAideTypeAide]),
          aide: 'Une étape par ligne, dans l’ordre. Elles sont numérotées à l’affichage.'),
      const ChampDef(
          nom: 'definition',
          libelle: 'Définition',
          type: TypeChamp.textarea,
          lignes: 5,
          col: ColChamp.plein,
          condition: (controle: 'type', quand: [ficheAideTypeDefinition])),
      const ChampDef.section('Qui la voit, où, et ce qu’elle engage'),
      ChampDef(
          nom: 'roles',
          libelle: 'Rôles autorisés',
          type: TypeChamp.multiselect,
          col: ColChamp.plein,
          options: _rolesMatrice(c),
          aide: 'Liste des rôles de la matrice des droits. Aucun rôle choisi : la fiche est pour tous.'),
      ChampDef(nom: 'ecrans', libelle: 'Écrans cités', type: TypeChamp.multiselect, col: ColChamp.plein, options: _ecrans(c), aide: 'Les écrans que la réponse indique (lien profond, seulement si l’agent les voit).'),
      ChampDef(
          nom: 'domainePro',
          libelle: 'Engage un professionnel ?',
          type: TypeChamp.select,
          col: ColChamp.demi,
          options: domaines,
          aide: 'Un domaine professionnel (ex. le bloc) : la fiche ne se valide qu’avec le geste de ce professionnel, son nom et la date.'),
      ChampDef(nom: 'questionAttendue', libelle: 'Répond à la question attendue', type: TypeChamp.select, col: ColChamp.demi, options: attendues, aide: 'Relie la fiche à une question du document des 100 questions : son statut s’y reflète.'),
    ], initial);
  }

  Map<String, Object?> _initialDe(Map<String, Object?> f) => {
        'type': f['type'] ?? ficheAideTypeAide,
        'titre': f['titre'] ?? '',
        'motsCles': ((f['motsCles'] as List?) ?? const []).join('\n'),
        'etapes': ((f['etapes'] as List?) ?? const []).join('\n'),
        'definition': f['definition'] ?? '',
        'roles': [for (final r in (f['roles'] as List?) ?? const []) '$r'],
        'ecrans': [for (final r in (f['ecrans'] as List?) ?? const []) '$r'],
        'domainePro': f['domainePro'] ?? '',
        'questionAttendue': f['questionAttendue'] == null ? '' : '${f['questionAttendue']}',
      };

  void _ouvrirFormulaire(ContexteEcran c, {Map<String, Object?> initial = const {}, String? edition}) {
    _ctl?.dispose();
    setState(() {
      _ctl = _formulaire(c, _initialDe(initial));
      _edition = edition;
      _aValider = null;
      _aArchiver = null;
      _refus = null;
      _confirmation = null;
    });
  }

  List<String> _lignes(Object? v) => [for (final l in '${v ?? ''}'.split('\n')) if (l.trim().isNotEmpty) l.trim()];

  List<String> _rolesConnus(ContexteEcran c) => [for (final o in _rolesMatrice(c)) o.valeur];

  void _enregistrer(ContexteEcran c) {
    final ctl = _ctl!;
    final v = ctl.valider();
    if (v == null) return;
    final saisie = <String, Object?>{
      ...v,
      'motsCles': _lignes(v['motsCles']),
      if (v['type'] == ficheAideTypeAide) 'etapes': _lignes(v['etapes']),
    };
    final col = c.magasin.collection(colFichesAide);
    final a = acteur(c);
    final roles = _rolesConnus(c);
    final ecrans = [for (final o in _ecrans(c)) o.valeur];
    if (_edition == null) {
      final r = creerFicheAide(saisie: saisie, auteurId: a.utilisateurId, auteurNom: a.nom, maintenant: c.aujourdhui, rolesConnus: roles, ecransConnus: ecrans);
      if (!r.accepte) {
        setState(() => _refus = r.refus);
        return;
      }
      // L'identifiant est attribué par la collection (série du poste, préfixée de son étiquette : deux postes hors ligne ne forment jamais deux fiches du même identifiant).
      final id = '${col.inserer(r.fiche!, prefixe: 'FAI').fiche['id']}';
      c.magasin.journaliser('Création', 'CFG', 'Fiche d’aide', id, null, {'type': r.fiche!['type'], 'titre': r.fiche!['titre'], 'statut': ficheAideProposee});
      ToastsSigh.afficher(context, 'Fiche enregistrée.', type: TypeToast.succes, detail: 'Proposée : elle sera citée quand elle aura été validée.');
      setState(() {
        _confirmation = 'Fiche « ${r.fiche!['titre']} » enregistrée (proposée, non citée tant qu’elle n’est pas validée).';
        _ctl?.dispose();
        _ctl = null;
        _refus = null;
      });
      return;
    }
    final actuelle = col.parId(_edition);
    final r = modifierFicheAide(actuelle: actuelle, saisie: saisie, maintenant: c.aujourdhui, rolesConnus: roles, ecransConnus: ecrans);
    if (!r.accepte) {
      setState(() => _refus = r.refus);
      return;
    }
    final patch = {...r.fiche!};
    for (final k in const ['domainePro', 'questionAttendue', 'etapes', 'definition']) {
      if (!patch.containsKey(k)) patch[k] = null;
    }
    col.mettreAJour(_edition, patch, journaliser: false);
    c.magasin.journaliser('Modification', 'CFG', 'Fiche d’aide', '$_edition', {'statut': actuelle!['statut']}, {'titre': patch['titre'], 'statut': actuelle['statut']});
    ToastsSigh.afficher(context, 'Fiche modifiée.', type: TypeToast.succes);
    setState(() {
      _confirmation = 'Fiche « ${patch['titre']} » modifiée.';
      _ctl?.dispose();
      _ctl = null;
      _edition = null;
      _refus = null;
    });
  }

  void _valider(ContexteEcran c) {
    final col = c.magasin.collection(colFichesAide);
    final f = col.parId(_aValider);
    final a = acteur(c);
    final v = validerFicheAide(
        fiche: f,
        role: c.role,
        validateurId: a.utilisateurId,
        validateurNom: a.nom,
        maintenant: c.aujourdhui,
        gestes: droitsGestesEcran(c),
        rolesConnus: _rolesConnus(c),
        professionnel: _pro.text,
        professionnelLe: _proLe.text,
        estFileul: ServiceInstallation.de(c.magasin).rattache);
    if (!v.accepte) {
      setState(() => _refus = v.refus);
      return;
    }
    col.mettreAJour(_aValider, v.fiche!, journaliser: false);
    c.magasin.journaliser('Validation', 'CFG', 'Fiche d’aide', '$_aValider', {'statut': ficheAideProposee}, {'statut': ficheAideValidee, 'validePar': v.fiche!['validePar'], 'valideLe': v.fiche!['valideLe'], if (v.fiche!.containsKey('professionnel')) 'professionnel': v.fiche!['professionnel']});
    // Une fiche qui en REMPLACE une autre : l'ancienne est archivée (RG-14), jamais supprimée.
    final ancienne = v.archiver == null ? null : col.parId(v.archiver);
    if (ancienne != null) {
      final ar = archiverFicheAide(fiche: ancienne, motif: 'Remplacée par la fiche $_aValider, validée le ${_jour(v.fiche!['valideLe'])}', auteurNom: a.nom, maintenant: c.aujourdhui);
      if (ar.accepte) {
        col.mettreAJour(v.archiver, ar.fiche!, journaliser: false);
        c.magasin.journaliser('Archivage', 'CFG', 'Fiche d’aide', '${v.archiver}', {'statut': ancienne['statut']}, {'statut': ficheAideArchivee, 'motif': ar.fiche!['motifArchivage']});
      }
    }
    ToastsSigh.afficher(context, 'Fiche validée.', type: TypeToast.succes, detail: 'L’assistant la cite désormais, avec votre nom et la date.');
    setState(() {
      _confirmation = 'Fiche « ${f!['titre']} » validée par ${a.nom} : l’assistant la cite.';
      _aValider = null;
      _refus = null;
      _pro.clear();
      _proLe.clear();
    });
  }

  void _archiver(ContexteEcran c) {
    final col = c.magasin.collection(colFichesAide);
    final f = col.parId(_aArchiver);
    final r = archiverFicheAide(fiche: f, motif: _motif.text, auteurNom: acteur(c).nom, maintenant: c.aujourdhui);
    if (!r.accepte) {
      setState(() => _refus = r.refus);
      return;
    }
    col.mettreAJour(_aArchiver, r.fiche!, journaliser: false);
    c.magasin.journaliser('Archivage', 'CFG', 'Fiche d’aide', '$_aArchiver', {'statut': f!['statut']}, {'statut': ficheAideArchivee, 'motif': _motif.text.trim()});
    ToastsSigh.afficher(context, 'Fiche archivée.', type: TypeToast.succes, detail: 'Elle n’est plus citée ; rien n’est supprimé.');
    setState(() {
      _confirmation = 'Fiche « ${f['titre']} » archivée (jamais supprimée).';
      _aArchiver = null;
      _refus = null;
      _motif.clear();
    });
  }

  void _reviser(ContexteEcran c, Map<String, Object?> source) {
    final a = acteur(c);
    final r = reviserFicheAide(source: source, auteurId: a.utilisateurId, auteurNom: a.nom, maintenant: c.aujourdhui, rolesConnus: _rolesConnus(c));
    if (!r.accepte) {
      setState(() => _refus = r.refus);
      return;
    }
    final id = '${c.magasin.collection(colFichesAide).inserer(r.fiche!, prefixe: 'FAI').fiche['id']}';
    c.magasin.journaliser('Révision', 'CFG', 'Fiche d’aide', id, {'remplace': source['id']}, {'statut': ficheAideProposee});
    setState(() {
      _confirmation = 'Fiche de révision créée (proposée) : modifiez-la, puis faites-la valider. L’ancienne reste citée jusque-là et sera archivée à la validation de la nouvelle.';
      _refus = null;
    });
  }

  // --- les blocs ----------------------------------------------------------------------------------------------------------------------------------------------

  Widget _blocRefus() {
    final r = _refus;
    if (r == null) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(top: 12), child: NoteSigh('${r.code} : ${r.motif} ${r.geste}', key: const Key('aide:refus'), ton: TonSigh.danger, icone: LucideIcons.ban));
  }

  Widget _champTexte(String libelle, TextEditingController ctl, Key cle, {String? indice}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(libelle, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: JetonsShell.slate600)),
        const SizedBox(height: 4),
        TextField(key: cle, controller: ctl, style: styleSaisie, decoration: decorationChamp(indicatif: indice ?? libelle)),
      ]);

  BadgeSigh _badgeAttendue(String s) => switch (s) {
        attendueValidee => BadgeSigh(attendueLibelles[s]!, ton: TonSigh.succes, icone: LucideIcons.circleCheck),
        attendueProposee => BadgeSigh(attendueLibelles[s]!, ton: TonSigh.attention, icone: LucideIcons.clock),
        _ => BadgeSigh(attendueLibelles[s]!, ton: TonSigh.danger, icone: LucideIcons.fileX),
      };

  Widget _attendues(ContexteEcran c, List<Map<String, Object?>> fiches, bool peutRediger) {
    final statuts = {for (final a in fichesAideAttendues) a.numero: statutFicheAttendue(a, fiches)};
    final aEcrire = statuts.values.where((s) => s == attendueAEcrire).length;
    final proposees = statuts.values.where((s) => s == attendueProposee).length;
    final validees = statuts.values.where((s) => s == attendueValidee).length;
    final total = fichesAideAttendues.length;
    final texte = aEcrire == total
        ? 'Aucune des $total fiches attendues n’est encore écrite : tant qu’aucune n’est validée, l’assistant répond « pas de fiche validée » à ces questions (jamais de mémoire). Le contenu est à écrire et à faire valider par la Direction.'
        : '$total fiches attendues : $aEcrire pas encore écrite(s), $proposees écrite(s) en attente de validation, $validees validée(s). Tant qu’une fiche n’est pas validée, l’assistant répond « pas de fiche validée ».';
    return CarteSigh(
      titre: 'Fiches attendues ($total, document des 100 questions)',
      sansRemplissage: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: NoteSigh(texte, key: const Key('aide:attendues'), ton: aEcrire > 0 ? TonSigh.attention : TonSigh.succes, icone: LucideIcons.fileText)),
        MiniTableauSigh(colonnes: [
          ColonneMini('Question', (f) => '', rendu: (f) => Text('Q${f['numero']}', style: const TextStyle(fontWeight: FontWeight.w600))),
          ColonneMini('Posée par', (f) => '${f['role']}'),
          ColonneMini('Texte de la question', (f) => '${f['question']}'),
          ColonneMini('Intention', (f) => f['type'] == ficheAideTypeAide ? 'Aide (I26)' : 'Définition (I27)'),
          ColonneMini('Validation', (f) => f['pro'] == true ? 'Professionnel nommé' : 'Direction'),
          ColonneMini('État', (f) => '', rendu: (f) => _badgeAttendue('${f['statut']}')),
          ColonneMini('', (f) => '', rendu: (f) {
            if (!peutRediger || f['statut'] != attendueAEcrire) return const SizedBox.shrink();
            return BoutonSigh(
                key: Key('aide:rediger:${f['numero']}'),
                libelle: 'Rédiger',
                taille: TailleBouton.sm,
                variante: VarianteBouton.secondaire,
                icone: LucideIcons.pencil,
                onPressed: () => _ouvrirFormulaire(c, initial: {'type': f['type'], 'questionAttendue': f['numero'], if (f['domainePro'] != null) 'domainePro': f['domainePro']}));
          }),
        ], lignes: [
          for (final a in fichesAideAttendues)
            {'numero': a.numero, 'role': a.libelleRole, 'question': a.question, 'type': a.type, 'pro': a.domainePro != null, 'domainePro': a.domainePro, 'statut': statuts[a.numero]}
        ]),
      ]),
    );
  }

  Widget _gabarit(ContexteEcran c, bool peutRediger) => CarteSigh(
        titre: 'Gabarit vide',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
              'Une fiche porte : un TITRE ; une INTENTION (aide « comment faire » ou définition « c’est quoi ») ; des MOTS-CLÉS (ce que l’agent écrirait) ; les RÔLES autorisés (liste de la matrice, vide = tous) ; '
              'le contenu PAS À PAS (une étape par ligne) ou la DÉFINITION ; les écrans cités ; éventuellement un domaine qui engage un professionnel. Elle naît « proposée », avec son auteur ; '
              'elle devient citable quand une autre personne, qui détient le geste réservé, la valide.',
              style: TextStyle(fontSize: 13, color: JetonsShell.slate600)),
          const SizedBox(height: 8),
          const Text('Titre : …\nIntention : aide | définition\nMots-clés : … (un par ligne)\nRôles autorisés : … (aucun = tous)\nPas à pas : 1. … 2. …   |   Définition : …\nÉcrans cités : …',
              key: Key('aide:gabarit'), style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: JetonsShell.slate700)),
          if (peutRediger) ...[
            const SizedBox(height: 12),
            BoutonSigh(key: const Key('aide:nouvelle'), libelle: 'Nouvelle fiche (gabarit vide)', icone: LucideIcons.filePlus, onPressed: () => _ouvrirFormulaire(c)),
          ],
        ]),
      );

  Widget _tableauFiches(ContexteEcran c, List<Map<String, Object?>> fiches, {required bool peutRediger, required bool peutValider}) {
    final tri = [...fiches]..sort((a, b) {
        final aa = a['statut'] == ficheAideArchivee ? 1 : 0, bb = b['statut'] == ficheAideArchivee ? 1 : 0;
        return aa != bb ? aa - bb : '${b['creeLe']}'.compareTo('${a['creeLe']}');
      });
    return CarteSigh(
      titre: 'Fiches écrites',
      sansRemplissage: true,
      child: MiniTableauSigh(vide: 'Aucune fiche écrite : l’assistant répond « pas de fiche validée » à toute question d’aide ou de définition.', colonnes: [
        ColonneMini('Titre', (f) => '${f['titre']}'),
        ColonneMini('Intention', (f) => f['type'] == ficheAideTypeDefinition ? 'Définition (I27)' : 'Aide (I26)'),
        ColonneMini('État', (f) => '', rendu: (f) => switch ('${f['statut']}') {
              ficheAideValidee => ficheAideCitable(f) ? const BadgeSigh('Validée', ton: TonSigh.succes, icone: LucideIcons.circleCheck) : const BadgeSigh('Validée sans validateur : non citée', ton: TonSigh.danger, icone: LucideIcons.ban),
              ficheAideArchivee => const BadgeSigh('Archivée', icone: LucideIcons.archive),
              _ => const BadgeSigh('Proposée', ton: TonSigh.attention, icone: LucideIcons.clock),
            }),
        ColonneMini('Auteur', (f) => '${f['auteurNom'] ?? '—'}'),
        ColonneMini('Validée par', (f) => f['statut'] == ficheAideValidee ? '${f['validePar'] ?? '—'} · ${_jour(f['valideLe'])}${f['professionnel'] == null ? '' : ' · professionnel : ${f['professionnel']} (${_jour(f['professionnelLe'])})'}' : '—'),
        ColonneMini('Rôles', (f) => ((f['roles'] as List?) ?? const []).isEmpty ? 'Tous' : ((f['roles'] as List).map((r) => c.donnees?.matrice.libelle('$r') ?? '$r').join(', '))),
        ColonneMini('', (f) => '', rendu: (f) {
          final id = '${f['id']}';
          final st = '${f['statut']}';
          return Wrap(spacing: 6, runSpacing: 4, children: [
            if (peutRediger && st == ficheAideProposee)
              BoutonSigh(key: Key('aide:modifier:$id'), libelle: 'Modifier', taille: TailleBouton.sm, variante: VarianteBouton.secondaire, icone: LucideIcons.pencil, onPressed: () => _ouvrirFormulaire(c, initial: f, edition: id)),
            if (peutValider && st == ficheAideProposee)
              BoutonSigh(
                  key: Key('aide:valider:$id'),
                  libelle: 'Valider',
                  taille: TailleBouton.sm,
                  icone: LucideIcons.badgeCheck,
                  onPressed: () => setState(() {
                        _aValider = id;
                        _aArchiver = null;
                        _refus = null;
                        _confirmation = null;
                      })),
            if (peutRediger && st == ficheAideValidee)
              BoutonSigh(key: Key('aide:reviser:$id'), libelle: 'Réviser', taille: TailleBouton.sm, variante: VarianteBouton.secondaire, icone: LucideIcons.gitBranch, onPressed: () => _reviser(c, f)),
            if (peutRediger && st != ficheAideArchivee)
              BoutonSigh(
                  key: Key('aide:archiver:$id'),
                  libelle: 'Archiver',
                  taille: TailleBouton.sm,
                  variante: VarianteBouton.secondaire,
                  icone: LucideIcons.archive,
                  onPressed: () => setState(() {
                        _aArchiver = id;
                        _aValider = null;
                        _refus = null;
                        _confirmation = null;
                      })),
          ]);
        }),
      ], lignes: tri),
    );
  }

  Widget _panneauValidation(ContexteEcran c, Map<String, Object?> f) {
    final pro = domaineProFicheAide(f['domainePro'] as String?);
    final contenu = f['type'] == ficheAideTypeAide
        ? [for (var i = 0; i < ((f['etapes'] as List?) ?? const []).length; i++) '${i + 1}. ${(f['etapes'] as List)[i]}']
        : ['${f['definition'] ?? ''}'];
    return CarteSigh(
      titre: 'Valider la fiche « ${f['titre']} »',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Relisez la fiche telle que l’assistant la citera. Votre nom et la date du jour seront portés sur la fiche ; vous ne pouvez pas valider une fiche dont vous êtes l’auteur.', style: TextStyle(fontSize: 13, color: JetonsShell.slate600)),
        const SizedBox(height: 8),
        for (final l in contenu) Text(l, style: const TextStyle(fontSize: 13, color: JetonsShell.slate900)),
        if (pro != null) ...[
          const SizedBox(height: 12),
          NoteSigh('Cette fiche engage un professionnel (${pro.libelle}) : elle ne se valide qu’avec le geste réservé de ce professionnel, son nom et la date à laquelle il l’a validée.', ton: TonSigh.attention, icone: LucideIcons.stethoscope),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 2, child: _champTexte('Validé par (professionnel)', _pro, const Key('aide:pro'))),
            const SizedBox(width: 12),
            Expanded(child: _champTexte('Date de sa validation (AAAA-MM-JJ)', _proLe, const Key('aide:pro-le'), indice: 'AAAA-MM-JJ')),
          ]),
        ],
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [
          BoutonSigh(key: const Key('aide:valider-ok'), libelle: 'Valider la fiche', icone: LucideIcons.badgeCheck, onPressed: () => _valider(c)),
          BoutonSigh(libelle: 'Renoncer', variante: VarianteBouton.secondaire, onPressed: () => setState(() => _aValider = null)),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection(colFichesAide);
    final fileul = ServiceInstallation.de(c.magasin).rattache;
    final peutRediger = c.droit.editer;
    final peutValider = gestePeutEcran(c, gesteFichesAideValider) && !fileul;
    return ListenableBuilder(
      listenable: col,
      builder: (context, _) {
        final fiches = [for (final f in col.toutes) f];
        final aValider = _aValider == null ? null : col.parId(_aValider);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (fileul)
            const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: NoteSigh('Poste rattaché : vous pouvez rédiger et modifier des fiches (elles rejoignent la mère) ; la VALIDATION se fait sur le poste mère, qui vérifie le geste réservé et que l’auteur n’est pas le validateur.',
                    key: Key('aide:fileul'), ton: TonSigh.info, icone: LucideIcons.lock))
          else if (!gestePeutEcran(c, gesteFichesAideValider))
            const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: NoteSigh('Vous pouvez rédiger, pas valider : valider une fiche est le geste réservé « Valider une fiche d’aide de l’assistant » (Direction et DAF d’origine, réglable dans « Rôles et permissions › Gestes réservés »).',
                    key: Key('aide:sans-geste'), ton: TonSigh.info, icone: LucideIcons.lock)),
          _attendues(c, fiches, peutRediger),
          const SizedBox(height: 16),
          _gabarit(c, peutRediger),
          _blocRefus(),
          if (_confirmation != null) Padding(padding: const EdgeInsets.only(top: 12), child: NoteSigh(_confirmation!, key: const Key('aide:ok'), ton: TonSigh.succes, icone: LucideIcons.circleCheck)),
          if (_ctl != null && peutRediger) ...[
            const SizedBox(height: 16),
            CarteSigh(
              titre: _edition == null ? 'Rédiger une fiche' : 'Modifier la fiche',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                FormulaireSigh(controleur: _ctl!),
                const SizedBox(height: 12),
                Wrap(spacing: 8, children: [
                  BoutonSigh(key: const Key('aide:enregistrer'), libelle: 'Enregistrer (proposée)', icone: LucideIcons.save, onPressed: () => _enregistrer(c)),
                  BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: () => setState(() {
                        _ctl?.dispose();
                        _ctl = null;
                        _edition = null;
                      })),
                ]),
              ]),
            ),
          ],
          if (aValider != null && peutValider) ...[const SizedBox(height: 16), _panneauValidation(c, aValider)],
          if (_aArchiver != null && peutRediger) ...[
            const SizedBox(height: 16),
            CarteSigh(
              titre: 'Archiver la fiche « ${col.parId(_aArchiver)?['titre'] ?? _aArchiver} »',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Une fiche archivée n’est plus citée par l’assistant ; elle reste dans la corbeille et ne se supprime jamais.', style: TextStyle(fontSize: 13, color: JetonsShell.slate600)),
                const SizedBox(height: 8),
                _champTexte('Motif de l’archivage (obligatoire)', _motif, const Key('aide:motif')),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  BoutonSigh(key: const Key('aide:archiver-ok'), libelle: 'Confirmer l’archivage', icone: LucideIcons.archive, variante: VarianteBouton.danger, onPressed: () => _archiver(c)),
                  BoutonSigh(libelle: 'Renoncer', variante: VarianteBouton.secondaire, onPressed: () => setState(() => _aArchiver = null)),
                ]),
              ]),
            ),
          ],
          const SizedBox(height: 16),
          _tableauFiches(c, fiches, peutRediger: peutRediger, peutValider: peutValider),
        ]);
      },
    );
  }
}
