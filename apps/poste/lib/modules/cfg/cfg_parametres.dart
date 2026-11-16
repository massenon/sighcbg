import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../core/service_installation.dart';
import '../../core/service_parametres.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../../shell/gestes_ecran.dart';
import '../../sync/configuration_sync.dart' show ApplicateurConfiguration;
import '../../sync/service_validations_deposees.dart';
import 'cfa_commun.dart';

/// L'onglet « Paramètres » de « Paramètres système » (lot L0, décision de la Direction du 09/11/2026) : TOUT ce qui est paramétrable se règle ici, est ENREGISTRÉ
/// EN BASE avec un défaut semé, et se VERSIONNE PAR DATE. Un réglage n'écrase jamais l'ancien : il ajoute une version à partir d'une date d'effet, de sorte que
/// la valeur appliquée à une pièce déjà émise reste retrouvable. Une valeur déjà utilisée par une pièce ne se réécrit pas (refus nommé, avec le geste).
///
/// Les règles sont au domaine (`ServiceParametres`) ; cet écran ne fait que les mettre en page. Les paramètres se règlent sur la MÈRE : un fileul les reçoit par
/// le journal et les consulte (la commande de réglage y est absente, et la collection refuse l'écriture). Le panneau web du relais n'en montre aucun : il ne
/// voit jamais leur contenu (enveloppes chiffrées).
class PanneauParametres extends StatelessWidget {
  const PanneauParametres({super.key, required this.c, required this.estMere});
  final ContexteEcran c;
  final bool estMere;

  /// Un réglage qui a SON droit (Q5 : un droit par réglage ; Q3 : qui passe l'inventaire en clôture se règle par le circuit de clôture) ne se règle pas par le seul droit d'éditer l'écran.
  bool _geste(String famille) => switch (famille) {
        'mecef' => gestePeutEcran(c, gesteReglageMecef),
        'cloture' => gestePeutEcran(c, gesteCircuitCloture),
        _ => true,
      };

  /// Un paramètre qui déclare SON geste réservé (`DefinitionParametre.geste` : la limite de lignes par export, Direction du 16/11/2026) ne se règle pas par le seul droit
  /// d'éditer l'écran ; le geste est relu de la matrice à chaque affichage.
  bool _gesteDuParametre(DefinitionParametre d) => d.geste == null || gestePeutEcran(c, d.geste!);

  ServiceParametres _service() => serviceParametres(c.magasin, auteur: () => acteurNom(c), horloge: () => c.aujourdhui);

  @override
  Widget build(BuildContext context) {
    final service = _service();
    final aujourdhui = parametreDateIso(c.aujourdhui);
    return ListenableBuilder(
        listenable: Listenable.merge([c.magasin.collection(parCollectionParametres), c.magasin.collection(parCollectionUsages)]),
        builder: (ctx, _) {
          final familles = service.parFamille(aujourdhui);
          final peutRegler = estMere && c.droit.editer;
          return cfaPile([
            cfaLectureSeule(c),
            if (!estMere) NoteSigh(ApplicateurConfiguration.motifGarde, ton: TonSigh.info, icone: LucideIcons.lock),
            const NoteSigh(
                'Un réglage ajoute une version à partir d’une date d’effet : la valeur en vigueur se lit à la date de la pièce, jamais à celle du jour. Une valeur déjà utilisée par une pièce ne se réécrit pas. Les paramètres voyagent chiffrés vers le relais, qui ne les lit pas.',
                ton: TonSigh.info,
                icone: LucideIcons.history),
            for (final e in familles.entries)
              // une famille qui a son PROPRE écran (copie hors site : droit, motif, refus nommés) n'est pas montrée ici : le panneau générique contournerait ses règles
              if (!parFamillesReglageDedie.contains(e.key))
              cfaSection(
                  libellesFamillesParametres[e.key] ?? e.key,
                  cfaPile([
                    for (final p in e.value)
                      // Un réglage qui relève d'un GESTE RÉSERVÉ (`reglagesSousGeste`, 16/11/2026, §7) se pose sous ce geste depuis N'IMPORTE QUEL poste : la mère écrit, un fileul dépose.
                      // Les autres réglages portant un geste dans leur DÉFINITION (limite d'export…) se règlent sur l'écran, et le refus est NOMMÉ sur la carte.
                      gesteDuReglage(p.definition.cle) != null
                          ? _Carte(c: c, service: service, p: p, aujourdhui: aujourdhui, peutRegler: gestePeutEcran(c, gesteDuReglage(p.definition.cle)!), sousGeste: true)
                          : _Carte(
                              c: c,
                              service: service,
                              p: p,
                              aujourdhui: aujourdhui,
                              peutRegler: peutRegler && _geste(e.key) && _gesteDuParametre(p.definition),
                              refusGeste: peutRegler && _geste(e.key) && !_gesteDuParametre(p.definition) ? p.definition.geste : null)
                  ], espace: 12)),
            cfaSource('Défauts : décisions de la Direction du 09/11/2026 (DECISIONS-A-VALIDER, section D). Rien n’est codé dans l’écran : valeurs et versions sont en base.'),
          ]);
        });
  }
}

String _libelleValeur(DefinitionParametre d, Object? v) {
  if (v is bool) return v ? 'Oui' : 'Non';
  if (v is String && d.libellesChoix.containsKey(v)) return d.libellesChoix[v]!;
  return v == null ? '—' : '$v';
}

class _Carte extends StatelessWidget {
  const _Carte({required this.c, required this.service, required this.p, required this.aujourdhui, required this.peutRegler, this.sousGeste = false, this.refusGeste});
  final ContexteEcran c;
  final ServiceParametres service;
  final ParametreAffiche p;
  final String aujourdhui;
  final bool peutRegler;

  /// Le réglage relève d'un geste réservé : il se règle depuis n'importe quel poste (un fileul DÉPOSE, la mère applique).
  final bool sousGeste;

  /// Ce poste dépose-t-il au lieu d'écrire ? (rattaché à une mère : la configuration est tenue par elle, famille R).
  bool get _depose => ServiceInstallation.de(c.magasin).rattache;

  /// Le geste réservé que le profil (qui édite l'écran) ne détient pas : la commande est absente et le refus est NOMMÉ sur la carte.
  final String? refusGeste;

  DefinitionParametre get d => p.definition;

  String get _origine => p.origine == 'defaut'
      ? 'Défaut semé'
      : (p.dateEffet == null ? 'Défaut semé (version 0)' : 'Version ${p.version}, effective depuis le ${_dateFr(p.dateEffet!)}');

  @override
  Widget build(BuildContext context) {
    return CarteSigh(
        titre: d.libelle.isEmpty ? d.cle : d.libelle,
        child: cfaPile([
          DescListeSigh([
            ('Valeur en vigueur aujourd’hui', cfaGras(_libelleValeur(d, p.valeur))),
            ('Origine', _origine),
            ('Défaut', _libelleValeur(d, d.defaut)),
            ('Prochaine version', p.prochaine == null ? 'Aucune' : '${_libelleValeur(d, p.prochaine!.valeur)} à partir du ${_dateFr(p.prochaine!.dateEffet!)}'),
            ('Clé', cfaCode(d.cle)),
          ]),
          if (d.aide.isNotEmpty) cfaDiscret(d.aide),
          if (!d.branche)
            BadgeSigh('Enregistré, pas encore appliqué par l’écran concerné (${d.appliquePar ?? 'lot à venir'})', ton: TonSigh.attention),
          if (d.source != null) cfaDiscret('Source : ${d.source}'),
          if (sousGeste) cfaDiscret('Se règle sous le geste réservé « ${gesteReserve(gesteDuReglage(d.cle)!)?.libelle ?? gesteDuReglage(d.cle)} », depuis n’importe quel poste : un poste rattaché transmet la demande à la mère, qui l’applique.'),
          if (sousGeste && ServiceValidationsDeposees.de(c.magasin).depotReglageEnAttente(d.cle) != null)
            const BadgeSigh('Réglage transmis à la mère, en attente de confirmation', ton: TonSigh.info),
          if (refusGeste != null)
            NoteSigh(
                'Réglage réservé : il se règle par le geste réservé « ${gesteReserve(refusGeste!)?.libelle ?? refusGeste} », que votre profil ne détient pas. Le droit d’éditer cet écran ne suffit pas (Rôles et permissions › Gestes réservés).',
                key: Key('parametre:reserve:${d.cle}'),
                ton: TonSigh.attention,
                icone: LucideIcons.lock),
          Row(children: [
            if (peutRegler)
              BoutonSigh(libelle: 'Régler à partir d’une date', icone: LucideIcons.slidersHorizontal, taille: TailleBouton.sm, onPressed: () => _regler(context)),
            if (peutRegler) const SizedBox(width: 8),
            BoutonSigh(libelle: 'Historique (${p.nbVersions})', icone: LucideIcons.history, variante: VarianteBouton.secondaire, taille: TailleBouton.sm, onPressed: () => _historique(context)),
          ]),
        ], espace: 10));
  }

  void _historique(BuildContext ctx) {
    final versions = service.historique(d.cle);
    afficherModale<void>(ctx,
        titre: 'Historique : ${d.libelle.isEmpty ? d.cle : d.libelle}',
        sousTitre: d.cle,
        taille: TailleModale.lg,
        corps: versions.isEmpty
            ? const Text('Aucune version enregistrée : le défaut s’applique.', style: TextStyle(color: JetonsShell.slate600, fontSize: 14))
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final v in versions)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: DescListeSigh([
                        ('Version', 'v${v.version}${v.dateEffet == null ? ' (défaut semé)' : ''}'),
                        ('Valeur', _libelleValeur(d, v.valeur)),
                        ('Effective depuis', v.dateEffet == null ? 'toujours' : _dateFr(v.dateEffet!)),
                        ('Réglée par', v.auteur),
                        if (v.motif != null) ('Motif', v.motif),
                      ])),
              ]),
        pied: (fermer) => [BoutonSigh(libelle: 'Fermer', variante: VarianteBouton.secondaire, onPressed: fermer)]);
  }

  void _regler(BuildContext ctx) {
    final champs = <ChampDef>[
      switch (d.type) {
        TypeParametre.booleen => ChampDef(
            nom: 'valeur', libelle: 'Nouvelle valeur', type: TypeChamp.select, requis: true, options: const [OptionChamp('oui', 'Oui'), OptionChamp('non', 'Non')]),
        TypeParametre.choix => ChampDef(
            nom: 'valeur',
            libelle: 'Nouvelle valeur',
            type: TypeChamp.select,
            requis: true,
            options: [for (final k in d.choix ?? const <String>[]) OptionChamp(k, d.libellesChoix[k] ?? k)]),
        TypeParametre.entier || TypeParametre.nombre => const ChampDef(nom: 'valeur', libelle: 'Nouvelle valeur', type: TypeChamp.nombre, requis: true),
        TypeParametre.texte => const ChampDef(nom: 'valeur', libelle: 'Nouvelle valeur', requis: true),
      },
      const ChampDef(
          nom: 'dateEffet',
          libelle: 'Effective à partir du',
          type: TypeChamp.date,
          requis: true,
          aide: 'Les pièces émises à cette date ou après l’utiliseront. Une date antérieure à une pièce qui a déjà utilisé la valeur est refusée.'),
      const ChampDef(nom: 'motif', libelle: 'Motif', type: TypeChamp.textarea, col: ColChamp.plein),
    ];
    final initial = p.valeur is bool ? (p.valeur == true ? 'oui' : 'non') : p.valeur;
    final ctl = ControleurFormulaire(champs, {'valeur': initial, 'dateEffet': aujourdhui});
    afficherModale<void>(ctx,
        titre: 'Régler : ${d.libelle.isEmpty ? d.cle : d.libelle}',
        sousTitre: 'Valeur actuelle : ${_libelleValeur(d, p.valeur)}',
        taille: TailleModale.md,
        corps: FormulaireSigh(controleur: ctl),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Enregistrer',
                  icone: LucideIcons.save,
                  onPressed: () {
                    final saisie = ctl.valider();
                    if (saisie == null) {
                      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                      return;
                    }
                    final valeur = _convertir(saisie['valeur']);
                    if (valeur == null) {
                      ToastsSigh.afficher(ctx, 'La valeur saisie n’est pas du bon type.', type: TypeToast.erreur, detail: 'Saisir ${_typeLisible(d.type)}.');
                      return;
                    }
                    if (sousGeste) {
                      final g = ServiceValidationsDeposees.de(c.magasin).reglerSousGeste(d.cle, valeur.$1, '${saisie['dateEffet']}',
                          role: c.role, acteur: acteurNom(c), estMere: !_depose, motif: '${saisie['motif'] ?? ''}', gestes: droitsGestesEcran(c));
                      if (g.refus != null) {
                        ToastsSigh.afficher(ctx, g.refus!.motif, type: TypeToast.erreur, detail: g.refus!.geste, duree: const Duration(seconds: 10));
                        return;
                      }
                      fermer();
                      ToastsSigh.afficher(ctx, g.version != null ? 'Nouvelle version enregistrée.' : 'Réglage transmis à la mère, en attente de confirmation.',
                          type: g.version != null ? TypeToast.succes : TypeToast.info,
                          detail: g.version != null
                              ? 'Version ${g.version!.version}, effective à partir du ${_dateFr('${saisie['dateEffet']}')}. Elle part vers les fileuls (chiffrée).'
                              : 'La mère l’applique sous votre rôle, contrôles refaits ; la nouvelle valeur revient ici par la synchronisation. D’ici là, la valeur actuelle s’applique.');
                      return;
                    }
                    // Le geste réservé du paramètre est RELU au moteur (un bouton absent ne protège rien) : refus nommé `reglage_reserve` sinon.
                    final r = service.regler(d.cle, valeur.$1, '${saisie['dateEffet']}', motif: '${saisie['motif'] ?? ''}', detientGeste: (g) => gestePeutEcran(c, g));
                    if (!r.ok) {
                      // Un refus se NOMME : le motif dit pourquoi, le geste dit quoi faire.
                      ToastsSigh.afficher(ctx, r.refus!.motif, type: TypeToast.erreur, detail: r.refus!.geste, duree: const Duration(seconds: 10));
                      return;
                    }
                    fermer();
                    ToastsSigh.afficher(ctx, 'Nouvelle version enregistrée.',
                        type: TypeToast.succes, detail: 'Version ${r.valeur!.version}, effective à partir du ${_dateFr('${saisie['dateEffet']}')}. Elle part vers les fileuls et le relais (chiffrée).');
                  }),
            ]);
  }

  /// La saisie convertie au type du paramètre ; `null` si elle n'en est pas (le contrôle fin, lui, est celui du domaine). Enveloppée dans un enregistrement : une
  /// valeur booléenne `false` ne se confond ainsi pas avec « pas de valeur ».
  (Object?,)? _convertir(Object? brut) {
    switch (d.type) {
      case TypeParametre.booleen:
        return brut == 'oui' ? (true,) : (brut == 'non' ? (false,) : null);
      case TypeParametre.choix:
      case TypeParametre.texte:
        return brut is String ? (brut,) : null;
      case TypeParametre.entier:
        final n = int.tryParse('$brut'.trim());
        return n == null ? null : (n,);
      case TypeParametre.nombre:
        final n = num.tryParse('$brut'.trim().replaceAll(',', '.'));
        return n == null ? null : (n,);
    }
  }
}

String _typeLisible(TypeParametre t) => switch (t) {
      TypeParametre.booleen => 'oui ou non',
      TypeParametre.choix => 'l’une des valeurs proposées',
      TypeParametre.entier => 'un nombre entier',
      TypeParametre.nombre => 'un nombre',
      TypeParametre.texte => 'un texte',
    };

/// AAAA-MM-JJ → JJ/MM/AAAA (le format de la clinique).
String _dateFr(String iso) {
  final p = iso.split('-');
  return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : iso;
}
