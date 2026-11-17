import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../mere/client_mere.dart';
import '../../shell/contexte_ecran.dart';
import '../../shell/gestes_ecran.dart';
import 'mra_commun.dart' show dateHeureMra, ageDepuis, grilleKpi, kpiMra, nonDisponible, styleMraPetit, tableauMra;
import 'mrb_source.dart' show mrbClientMere;

/// `mere-reprise-poste` : le CODE DE REPRISE d'un poste fileul (décision 12 de la Direction de Baguidi, 17/11/2026 ; E4608 : changement de machine d'un fileul).
///
/// Un poste neuf est un NOUVEL appareil : ses saisies en file portent des codes de dossier de la plage de l'ancien, que la mère refuse (`numero_hors_plage`). Le code de reprise lui passe
/// les plages et les baux de l'ancien et RÉVOQUE ce dernier (RG-14 : il reste au registre). Cet écran dit QUEL ancien poste est repris (son étiquette, son identifiant d'appairage, son état,
/// sa dernière synchronisation), émet le code par la mère (réservé à un geste de la fiche de rôle) et l'affiche UNE fois, avec la durée de validité que la MÈRE annonce.
/// Le code ne se lit qu'ici : il n'est ni gardé dans l'état de l'écran, ni écrit au journal (seuls le poste repris et l'échéance le sont), ni repris dans un message d'erreur.
abstract class SourceReprise {
  /// Tous les appareils que la mère connaît (le filtre « fileul » est une règle du domaine, `repPostesReprenables`).
  Future<List<Appareil>> appareils();

  /// Émet le code de reprise : refus nommé de la mère en [ErreurMere].
  Future<CodeReprise> emettre({required String uuid, required String etiquette});
}

class SourceRepriseClient implements SourceReprise {
  SourceRepriseClient(this._client);
  final ClientMere _client;
  @override
  Future<List<Appareil>> appareils() async => (await _client.etat()).appareils;
  @override
  Future<CodeReprise> emettre({required String uuid, required String etiquette}) => _client.codeReprise(uuid, etiquette);
}

/// Posée par les tests : une source sans réseau. Prioritaire.
SourceReprise? sourceRepriseInjectee;

SourceReprise? sourceRepriseCourante() {
  final i = sourceRepriseInjectee;
  if (i != null) return i;
  final c = mrbClientMere;
  return c == null ? null : SourceRepriseClient(c);
}

class EcranReprisePoste extends StatefulWidget with EcranMaquette {
  const EcranReprisePoste({super.key, this.source, this.maintenant});

  /// `null` : la source du poste mère (`mrbClientMere`) ; sans elle l'écran se dessine et dit « non disponible ».
  final SourceReprise? source;
  final DateTime Function()? maintenant;

  @override
  String get titre => 'Reprise d’un poste';
  @override
  String get description =>
      'Remplacer un poste fileul par un poste neuf : choisir l’ancien poste, générer un code de reprise qui passe ses plages de numéros et ses baux au nouveau et révoque l’ancien.';
  @override
  String get regle =>
      'Le code de reprise s’émet sur la mère, vaut le temps qu’elle annonce et ne sert qu’une fois. Il s’affiche une seule fois et n’est jamais écrit au journal : seuls le poste repris et l’échéance le sont. '
      'Un poste ne se reprend qu’une fois ; l’ancien poste est révoqué, jamais effacé (RG-14).';
  @override
  List<Widget> actionsEntete(BuildContext context) {
    final c = ContexteEcran.of(context);
    return [BoutonSigh(libelle: 'Appareils et appairage', variante: VarianteBouton.secondaire, onPressed: () => c.aller('mere-appareils'))];
  }

  @override
  State<EcranReprisePoste> createState() => _EtatReprise();
}

class _EtatReprise extends State<EcranReprisePoste> {
  List<Appareil>? _appareils;
  String? _panne;
  RepRefus? _refus;
  bool _charge = false, _occupe = false;
  String? _dernierPoste;

  SourceReprise? get _source => widget.source ?? sourceRepriseCourante();
  DateTime _maintenant() => (widget.maintenant ?? ContexteEcran.of(context).horloge ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _actualiser());
  }

  Future<void> _actualiser() async {
    final s = _source;
    if (s == null) {
      if (mounted) {
        setState(() {
          _panne = 'aucune liaison avec le service de la mère sur ce poste';
          _charge = true;
        });
      }
      return;
    }
    try {
      final l = await s.appareils();
      if (!mounted) return;
      setState(() {
        _appareils = l;
        _panne = null;
        _charge = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _panne = e is ErreurMere ? repRefus(e.code, motifMere: e.motif).motif : repRefus('mere_injoignable').motif;
        _charge = true;
      });
    }
  }

  RepPoste _poste(Appareil a) =>
      (uuid: a.uuid, etiquette: a.etiquette, role: a.role, revoque: a.revoque, dernierContact: a.dernierContact, derniereSeq: a.derniereSeq);

  /// Le geste : choisir le nom du poste neuf, demander le code à la mère, l'afficher UNE fois.
  Future<void> _generer(RepPoste ancien) async {
    final s = _source;
    if (s == null || _occupe) return;
    final c = ContexteEcran.of(context);
    if (!gestePeutEcran(c, gesteRepriseEmettre)) {
      setState(() => _refus = repRefus('acces_refuse'));
      return;
    }
    final ctl = TextEditingController(text: repEtiquetteProposee(ancien));
    final nomNeuf = await afficherModale<String>(context,
        titre: 'Reprendre l’identité de « ${repNomPoste(ancien)} »',
        sousTitre: 'Identifiant d’appairage : ${ancien.uuid}',
        taille: TailleModale.md,
        corps: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
              'Le code sera saisi sur le poste NEUF, à l’écran « Rejoindre une clinique ». À son appairage, la mère lui passe les plages de numéros de dossier et les baux de stock de l’ancien poste, '
              'puis RÉVOQUE l’ancien poste (il reste au registre, RG-14). Si l’export de l’ancien poste a été importé sur le poste neuf, sa file de saisies part à la mère sans doublon.',
              key: Key('rep:explication')),
          const SizedBox(height: 12),
          const Text('Nom du poste neuf', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: JetonsShell.slate600)),
          const SizedBox(height: 4),
          TextField(key: const Key('rep:etiquette'), controller: ctl, style: styleSaisie, decoration: decorationChamp(indicatif: 'Réception')),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(key: const Key('rep:confirmer'), libelle: 'Générer le code', icone: LucideIcons.keyRound, onPressed: () => Navigator.of(context, rootNavigator: true).pop(ctl.text.trim())),
            ]);
    ctl.dispose();
    if (nomNeuf == null || !mounted) return;
    setState(() {
      _occupe = true;
      _refus = null;
    });
    CodeReprise? code;
    try {
      code = await s.emettre(uuid: ancien.uuid, etiquette: nomNeuf.isEmpty ? repEtiquetteProposee(ancien) : nomNeuf);
    } on ErreurMere catch (e) {
      _refus = repRefus(e.code, motifMere: e.motif);
    } catch (_) {
      _refus = repRefus('mere_injoignable');
    }
    if (!mounted) return;
    setState(() {
      _occupe = false;
      _dernierPoste = code == null ? null : repNomPoste(ancien);
    });
    if (code == null) return;
    // RG-12 : le GESTE est tracé (qui, quel poste repris, jusqu'à quand) ; le code, JAMAIS.
    c.magasin.journaliser('Code de reprise émis', 'MERE', 'Poste', ancien.uuid, null,
        repJournalEmission(uuidAncien: ancien.uuid, etiquetteAncien: ancien.etiquette, expireMs: code.expireMs, validiteSecondes: code.validiteSecondes));
    final emis = _maintenant();
    await _afficherCode(ancien, code, emis);
    code = null;
    await _actualiser();
  }

  Future<void> _afficherCode(RepPoste ancien, CodeReprise code, DateTime emis) {
    final duree = repDureeLisible(code.validiteSecondes);
    final jusqua = code.expireMs == null ? null : dateHeureMra(DateTime.fromMillisecondsSinceEpoch(code.expireMs!));
    return afficherModale<void>(context,
        titre: 'Code de reprise',
        sousTitre: repNomPoste(ancien),
        taille: TailleModale.md,
        fermetureParFond: false,
        corps: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          SelectableText(code.code, key: const Key('rep:code'), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: 4)),
          const SizedBox(height: 8),
          Text(
              duree == null
                  ? 'À usage unique. La durée de validité n’est pas communiquée par la mère : le code expire quand elle le décide.'
                  : 'À usage unique, valable $duree${jusqua == null ? '' : ' (jusqu’à $jusqua)'}.',
              key: const Key('rep:validite'),
              style: styleMraPetit),
          const SizedBox(height: 12),
          const NoteSigh(
              'Ce code ne s’affiche qu’UNE fois : fermé, il ne se relit plus. Cette console ne l’écrit nulle part (ni journal, ni message). '
              'Saisissez-le sur le poste neuf, à l’écran « Rejoindre une clinique ».',
              key: Key('rep:une-fois'),
              ton: TonSigh.attention,
              icone: LucideIcons.eyeOff),
        ]),
        pied: (fermer) => [
              BoutonSigh(
                  key: const Key('rep:copier'),
                  libelle: 'Copier le code',
                  icone: LucideIcons.copy,
                  variante: VarianteBouton.secondaire,
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: code.code));
                    if (mounted) ToastsSigh.afficher(context, 'Code copié (il ne figure dans aucun journal).', type: TypeToast.succes);
                  }),
              BoutonSigh(key: const Key('rep:fermer'), libelle: 'Fermer', onPressed: fermer),
            ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final peut = gestePeutEcran(c, gesteRepriseEmettre);
    final tous = _appareils;
    final postes = tous == null ? null : repPostesReprenables([for (final a in tous) _poste(a)]);
    final parUuid = {for (final a in tous ?? const <Appareil>[]) a.uuid: a};
    final actifs = postes?.where((p) => !p.revoque).length;
    final maintenant = _maintenant();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_panne != null)
        Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: NoteSigh('Le service de la mère ne répond pas : $_panne', key: const Key('rep:panne'), ton: TonSigh.danger, icone: LucideIcons.triangleAlert)),
      if (!peut)
        Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: NoteSigh('${repRefus('acces_refuse').motif} ${repRefus('acces_refuse').geste}', key: const Key('rep:sans-droit'), ton: TonSigh.attention, icone: LucideIcons.shieldAlert)),
      if (_refus != null)
        Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: NoteSigh('${_refus!.code} : ${_refus!.motif} ${_refus!.geste}', key: const Key('rep:refus'), ton: TonSigh.danger, icone: LucideIcons.ban)),
      if (_dernierPoste != null && _refus == null)
        Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: NoteSigh('Un code de reprise a été émis pour « $_dernierPoste ». Il n’est plus affiché : s’il est perdu, générez-en un nouveau (l’ancien reste valable jusqu’à son expiration ou son usage).',
                key: const Key('rep:emis'), ton: TonSigh.info, icone: LucideIcons.keyRound)),
      grilleKpi([
        kpiMra('Postes fileuls appairés', postes?.length, icone: LucideIcons.monitor),
        kpiMra('Postes actifs', actifs, icone: LucideIcons.monitorCheck),
        kpiMra('Postes révoqués', postes == null ? null : postes.length - actifs!, icone: LucideIcons.monitorX),
      ]),
      const SizedBox(height: 16),
      tableauMra(
        colonnes: [
          const ColonneTableau(cle: 'poste', libelle: 'Poste'),
          ColonneTableau(
              cle: 'uuid',
              libelle: 'Identifiant d’appairage',
              triable: false,
              rendu: (_, l) => SelectableText('${l['uuid']}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              texte: (l) => '${l['uuid']}'),
          ColonneTableau(cle: 'etat', libelle: 'État', triable: false, rendu: (_, l) => BadgeSigh('${l['etat']}', ton: l['ton'] as TonSigh), texte: (l) => '${l['etat']}'),
          const ColonneTableau(cle: 'synchro', libelle: 'Dernière synchronisation', triable: false),
          const ColonneTableau(cle: 'retard', libelle: 'Opérations reçues', droite: true, triable: false),
        ],
        lignes: [
          for (final p in postes ?? const <RepPoste>[])
            {
              'id': p.uuid,
              'poste': repNomPoste(p),
              'uuid': p.uuid,
              'etat': p.revoque ? 'Révoqué' : 'Actif',
              'ton': p.revoque ? TonSigh.danger : TonSigh.succes,
              'synchro': p.dernierContact == null ? 'jamais synchronisé' : '${dateHeureMra(p.dernierContact!)} (${ageDepuis(p.dernierContact, maintenant)})',
              'retard': '${parUuid[p.uuid]?.derniereSeq ?? 0}',
            }
        ],
        messageVide: postes == null ? 'Postes $nonDisponible.' : 'Aucun poste fileul appairé.',
        indiceVide: postes == null ? 'Le service de la mère ne répond pas : un état inconnu ne rassure jamais.' : 'Appairez d’abord un poste (« Appareils et appairage ») : il n’y a rien à reprendre.',
        nomExport: 'reprise-postes',
        triInitial: 'poste',
        actionsLigne: peut
            ? (ctx, l) {
                final p = repPostesReprenables([for (final a in tous ?? const <Appareil>[]) _poste(a)]).firstWhere((x) => x.uuid == '${l['uuid']}');
                return [
                  BoutonSigh(
                      key: Key('rep:generer:${p.uuid}'),
                      libelle: 'Générer un code de reprise',
                      icone: LucideIcons.keyRound,
                      taille: TailleBouton.sm,
                      onPressed: _occupe ? null : () => _generer(p)),
                ];
              }
            : null,
      ),
      const SizedBox(height: 16),
      CarteSigh(
          titre: 'Ce que fait la reprise',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('1. Sur le poste neuf : importer l’export de l’ancien poste (« Export, import et mise à jour ») pour reprendre sa file de saisies non confirmées.', key: Key('rep:etape1')),
            const SizedBox(height: 6),
            const Text('2. Ici : choisir l’ancien poste et générer le code de reprise ; il s’affiche une seule fois.', key: Key('rep:etape2')),
            const SizedBox(height: 6),
            const Text('3. Sur le poste neuf : « Rejoindre une clinique », saisir l’adresse de la mère et ce code.', key: Key('rep:etape3')),
            const SizedBox(height: 6),
            const Text(
                '4. À l’appairage, la mère passe les plages de numéros et les baux de stock de l’ancien poste au nouveau, puis révoque l’ancien. Les saisies reprises partent sans doublon : leurs identifiants d’opération sont reconnus.',
                key: Key('rep:etape4')),
            const SizedBox(height: 6),
            const Text('Sans reprise, un poste neuf recevrait de nouvelles plages et la mère refuserait les saisies de l’ancien (« numero_hors_plage »).', style: styleMraPetit),
          ])),
    ]);
  }
}
