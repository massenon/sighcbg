import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/seuils_poste.dart';
import '../../kit/kit.dart';
import '../../kit/validation_poste.dart';
import '../../shell/contexte_ecran.dart';
import '../cfg/cfb_configuration_fiscale.dart';
import '../m2/cr_commun.dart' show dateHeureDe;
import 'qual_commun.dart';

/// `adm-validations` — « Validations en attente » : le centre qui répond à « qu'est-ce qui attend une validation, et de QUI ? ». Il ORIENTE, il ne valide
/// JAMAIS en masse : la validation est un geste humain, porté à SON POSTE, par la personne qui engage sa responsabilité (doctrine des deux verrous du
/// laboratoire). Quatre familles : les gestes de poste (comptés depuis les registres), les référentiels qui attendent un PROFESSIONNEL nommé, ce qui
/// attend un ARBITRAGE de la Direction, et ce que la Direction a déjà validé le 01/09.
///
/// Une file amorcée par un écran d'un autre module (bons de besoins, commandes) s'annonce « non amorcée » plutôt que d'afficher un 0 faux. L'écran ne
/// porte AUCUNE commande d'écriture : « Y aller » et « Ouvrir » naviguent, rien ne se valide ici. Les règles sont dans `qual_validations.dart`.
class EcranValidations extends StatelessWidget with EcranMaquette {
  const EcranValidations({super.key});

  @override
  String get titre => 'Validations en attente';

  @override
  String get description =>
      'Tout ce qui attend une validation, classé par poste et par responsable — avec le chemin vers le geste.';

  @override
  String get regle =>
      'Cet écran oriente, il ne valide jamais en masse : la validation est un geste humain, porté à son poste, le biologiste au laboratoire, le comptable au journal, la DA sur le bon, la Direction à l’écran du référentiel. Les comptes de la liste des référentiels sont relus dans le magasin à chaque affichage ; chaque profil n’y voit que les familles de son ressort, et la Direction ne signe jamais à la place d’un professionnel nommé.';

  /// Les sept profils qui ouvraient déjà le centre gardent tout ce qu'ils y voyaient ; le biologiste, l'échographiste et les praticiens du bloc n'y voient
  /// QUE les familles de référentiels de leur rôle.
  static const _elargis = ['da', 'admin', 'direction', 'dm', 'comptable', 'surveillant', 'agentadmin'];

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final m = c.magasin;
    final noms = [
      'demandesAnalyses',
      'ecritures',
      'besoins',
      'commandes',
      'factures',
      'resultatsImagerie',
      'echeancesFiscales',
      'materiel',
      'ambulances',
      'identiteLegale',
      'obligationsFiscales',
      'historiqueObligations',
      // LA LIGNE DES SEUILS (lot B) : le compte des versions Enregistrées, et le droit de les valider (fiches `rbac`), relus à chaque changement.
      'seuilsDelta',
      'rbac',
      // Le compte d'une famille est LU dans le magasin : toute collection qu'elle lit rafraîchit le centre.
      ...valCollectionsLues(),
    ];
    final restreint = !_elargis.contains(c.role);
    final vp = ValidationPoste(c);
    return ListenableBuilder(
        listenable: Listenable.merge([for (final n in noms) m.collection(n)]),
        builder: (context, _) {
          final files = qualFilesValidation(
              demandesAnalyses: m.collection('demandesAnalyses').toutes,
              ecritures: m.collection('ecritures').toutes,
              besoinsToutes: m.collection('besoins').toutes,
              commandesToutes: m.collection('commandes').toutes,
              factures: m.collection('factures').toutes,
              resultatsImagerie: m.collection('resultatsImagerie').toutes,
              echeancesFiscales: m.collection('echeancesFiscales').toutes,
              aujourdhui: jourIso(c));
          final aCompleter = qualACompleter(materiel: m.collection('materiel').toutes, ambulancesToutes: m.collection('ambulances').toutes);
          // LES RÉFÉRENTIELS : un compte par famille, relu dans le magasin (moteur de validation commun), jamais un littéral.
          final familles = valReferentielsVisiblesPar(c.role, vp.lire, vp.libelles);
          final totalFamilles = familles.fold<int>(0, (n, x) => n + (x.enAttente ?? 0));
          final totalGestes = files.fold<int>(0, (n, x) => n + (x.compte ?? 0));
          final cf = ConfigurationFiscalePoste(c);
          final configuration = _configurationAValider(cf);
          bool ouvrable(String ecran) => c.ouvre?.call(ecran) ?? true;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            KpiGrilleSigh(kpis: [
              if (!restreint) ...[
                KpiSigh(
                    libelle: 'Gestes de validation en attente',
                    valeur: nombre(totalGestes),
                    icone: LucideIcons.listChecks,
                    ton: totalGestes > 0 ? TonSigh.attention : TonSigh.succes),
                KpiSigh(
                    libelle: 'Files concernées',
                    valeur: '${files.where((x) => (x.compte ?? 0) > 0).length} / ${files.length}',
                    icone: LucideIcons.layoutGrid,
                    ton: TonSigh.neutre),
              ],
              KpiSigh(
                  libelle: 'Référentiels en attente de validation',
                  valeur: nombre(totalFamilles),
                  icone: LucideIcons.userCheck,
                  ton: totalFamilles > 0 ? TonSigh.attention : TonSigh.succes),
              KpiSigh(
                  libelle: 'Familles concernées',
                  valeur: '${familles.where((x) => (x.enAttente ?? 0) > 0).length} / ${familles.length}',
                  icone: LucideIcons.layers,
                  ton: TonSigh.neutre),
            ]),
            if (!restreint) ...[
              const SizedBox(height: 16),
              CarteSigh(
                  titre: 'À valider À SON POSTE, l’écran oriente, le poste valide',
                  child: LayoutBuilder(builder: (context, k) {
                    final deux = k.maxWidth >= 768;
                    final l = deux ? (k.maxWidth - 12) / 2 : k.maxWidth;
                    return Wrap(spacing: 12, runSpacing: 12, children: [
                      for (final f in files) SizedBox(width: l, child: _file(c, f)),
                    ]);
                  })),
            ],
            const SizedBox(height: 16),
            // Une ligne par famille : compte réel, profil nommé, lien vers l'écran où se trouve l'artefact. Aucune commande d'écriture ici.
            CarteSigh(
                titre: restreint
                    ? 'Les référentiels de votre ressort : la validation se fait à l’écran de chacun'
                    : 'Référentiels en attente de validation, par famille : la Direction ne signe pas à la place d’un professionnel nommé',
                child: familles.isEmpty
                    ? const Text('Aucun référentiel en attente de validation ne relève de votre profil.',
                        style: TextStyle(color: JetonsShell.slate500, fontSize: 14, height: 20 / 14))
                    : Column(children: [
                        for (final (i, x) in familles.indexed) ...[
                          if (i > 0) const SizedBox(height: 8),
                          _famille(c, x, ouvrable(ecranDeFamille(x.ecran))),
                        ]
                      ])),
            // LIGNE « SEUILS ENREGISTRÉS À VALIDER » (lot B) : visible du SEUL porteur du droit de les valider — le geste réservé de la fiche de rôle, jamais une liste de rôles :
            // ni l'administrateur ni la Direction, qui ouvrent pourtant le centre, ne la voient sans lui. Le centre ORIENTE : le geste (avec son motif) reste à l'écran
            // « Valeurs de référence », un seuil à la fois, aucune validation en lot.
            if (SeuilsPoste(c).droitValider) ...[
              const SizedBox(height: 16),
              _ligneSeuils(c, seuilsEnAttente(m.collection('seuilsDelta').actives).total, ouvrable(SeuilsPoste.ecran)),
            ],
            if (!restreint) ...[
              const SizedBox(height: 16),
              CarteSigh(
                  titre: 'Données à compléter : le marquage tombe par la SAISIE, jamais par une signature',
                  child: Column(children: [
                    for (final (i, p) in aCompleter.indexed) ...[
                      if (i > 0) const SizedBox(height: 8),
                      _bloc(c, p.titre, '${p.qui} · ${p.motif}', p.ecran, attention: false, ouvrable: ouvrable(p.ecran)),
                    ]
                  ])),
              const SizedBox(height: 16),
              CarteSigh(
                  titre: 'En attente d’un ARBITRAGE de la Direction : elle seule peut trancher',
                  child: Column(children: [
                    for (final (i, x) in configuration.indexed) ...[
                      if (i > 0) const SizedBox(height: 8),
                      _bloc(c, x.libelle, 'État : ${x.attente} · ${x.motif}', x.ecran, attention: true, cle: 'qual:config:${x.nom}'),
                    ],
                    for (final (i, a) in qualArbitrages.indexed) ...[
                      if (i > 0 || configuration.isNotEmpty) const SizedBox(height: 8),
                      _bloc(c, a.libelle, a.detail, a.ecran, attention: true),
                    ]
                  ])),
            ],
            sourceQual('Compté à chaque affichage depuis les registres du magasin, rien n’est fourni.'),
          ]);
        });
  }

  Widget _ligneSeuils(ContexteEcran c, int attente, bool ouvrable) {
    final porteurs = [for (final r in SeuilsPoste(c).gestes.rolesAvec(gesteValiderSeuil, c.donnees?.matrice.rolesBruts.map((r) => '${r['id']}') ?? const <String>[])) c.donnees?.matrice.libelle(r) ?? r];
    return CarteSigh(
        titre: 'Seuils de variation à valider : la validation reste à son poste, au porteur du droit',
        child: Container(
            key: const Key('qual:seuils-a-valider'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: JetonsShell.slate200)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Seuils enregistrés à valider',
                    style: TextStyle(color: JetonsShell.slate800, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500)),
                Text(
                    'Seuils de variation brutale du laboratoire, sans effet tant qu’ils ne sont pas validés · valide : ${porteurs.isEmpty ? 'aucun rôle' : porteurs.join(', ')} · la validation se fait à l’écran « Valeurs de référence », un seuil à la fois, avec son motif.',
                    style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)),
              ])),
              const SizedBox(width: 12),
              Text(nombre(attente),
                  key: const Key('qual:seuils-a-valider:compte'),
                  style: TextStyle(color: attente > 0 ? JetonsShell.warning700 : JetonsShell.slate300, fontSize: 18, height: 28 / 18, fontWeight: FontWeight.w600)),
              if (ouvrable) ...[
                const SizedBox(width: 12),
                BoutonSigh(
                    key: const Key('qual:seuils-a-valider:ouvrir'),
                    libelle: 'Ouvrir',
                    icone: LucideIcons.arrowRight,
                    taille: TailleBouton.sm,
                    variante: VarianteBouton.secondaire,
                    onPressed: () => c.aller(SeuilsPoste.ecran)),
              ],
            ])));
  }

  /// Une famille : libellé, profil qui valide, compte réel (« — » tant qu'elle n'est pas amorcée), « sur N », et « Ouvrir » quand l'écran est ouvert au profil.
  Widget _famille(ContexteEcran c, CompteFamille x, bool ouvrable) => Container(
      key: Key('val:famille:${x.famille}'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: JetonsShell.slate200)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(x.libelle,
              style: const TextStyle(color: JetonsShell.slate800, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500)),
          Text('Valide : ${x.profil}${x.nonAmorce ? ' · non amorcé sur ce poste, ouvrir l’écran pour le charger' : ''}',
              style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)),
        ])),
        const SizedBox(width: 12),
        Text(x.enAttente == null ? '—' : nombre(x.enAttente),
            key: Key('val:en-attente:${x.famille}'),
            style: TextStyle(
                color: (x.enAttente ?? 0) > 0 ? JetonsShell.warning700 : JetonsShell.slate300,
                fontSize: 18,
                height: 28 / 18,
                fontWeight: FontWeight.w600)),
        const SizedBox(width: 12),
        Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(x.total == null ? '' : 'sur ${nombre(x.total)}',
                style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12))),
        if (ouvrable) ...[
          const SizedBox(width: 12),
          BoutonSigh(
              libelle: 'Ouvrir',
              icone: LucideIcons.arrowRight,
              taille: TailleBouton.sm,
              variante: VarianteBouton.secondaire,
              onPressed: () => c.aller(ecranDeFamille(x.ecran))),
        ],
      ]));

  /// LA CONFIGURATION FISCALE À VALIDER (Direction, 06/11/2026) : deux lignes dans la famille des arbitrages, tant que l'état n'est pas « validé ».
  /// L'état vient du moteur (`cfbEtatIdentite`, `cfbEtatObligations`), jamais recopié ici ; elles reviennent sur « modifié depuis la validation ».
  List<_LigneConfiguration> _configurationAValider(ConfigurationFiscalePoste cf) {
    String attente(CfbEtatConfiguration e) => e.etat == 'modifie_depuis'
        ? 'Modifiée le ${e.modifieLe == null ? '?' : dateHeureDe(e.modifieLe)} depuis la validation du ${dateHeureDe(e.validationAnterieure?['valideLe'])} : à revalider'
        : 'À valider (première configuration)';
    final ei = cf.etatIdentite();
    final eo = cf.etatObligations();
    return [
      if (ei.etat != 'valide')
        _LigneConfiguration(
            'identite',
            'Identité légale à valider (première configuration)',
            attente(ei),
            'cfg-fiscalite',
            'IFU, RCCM, forme, autorisation, adresse fiscale, devise et régime de TVA s’impriment sur toutes les pièces : la Direction, la DAF ou l’administrateur les vérifie et valide à l’écran Paramètres fiscaux.'),
      if (eo.etat != 'valide')
        _LigneConfiguration(
            'obligations',
            'Obligations fiscales à valider',
            attente(eo),
            'cfg-comptabilite',
            'Obligations mensuelles, IS, patente, CCIB, TVM et redevances ORTB prélevées sur les salaires : à vérifier et valider à l’écran Paramètres comptables & obligations.'),
    ];
  }

  /// Une file de gestes : icône, intitulé, poste (ou « non amorcée »), compte, « Y aller ».
  Widget _file(ContexteEcran c, QualFile f) => Container(
      padding: const EdgeInsets.all(20),
      decoration: decorationCarte(),
      child: Row(children: [
        Icon(iconeQual(f.icone), size: 24, color: JetonsShell.navy600),
        const SizedBox(width: 12),
        Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(f.libelle,
              style: const TextStyle(
                  color: JetonsShell.slate800, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500)),
          Text(f.sousTitre,
              style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)),
        ])),
        const SizedBox(width: 12),
        Text(f.compte == null ? '—' : nombre(f.compte),
            key: Key('qual:compte:${f.ecran}'),
            style: TextStyle(
                color: (f.compte ?? 0) > 0 ? JetonsShell.warning700 : JetonsShell.slate300,
                fontSize: 18,
                height: 28 / 18,
                fontWeight: FontWeight.w600)),
        const SizedBox(width: 12),
        BoutonSigh(
            libelle: 'Y aller',
            icone: LucideIcons.arrowRight,
            taille: TailleBouton.sm,
            variante: VarianteBouton.secondaire,
            onPressed: () => c.aller(f.ecran)),
      ]));

  Widget _bloc(ContexteEcran c, String titre, String detail, String ecran, {required bool attention, String? cle, bool ouvrable = true}) => Container(
      key: cle == null ? null : Key(cle),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: attention ? JetonsShell.warning50 : null,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: attention ? JetonsShell.warning200 : JetonsShell.slate200)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titre,
              style: const TextStyle(
                  color: JetonsShell.slate800, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500)),
          Text(detail,
              style: TextStyle(
                  color: attention ? JetonsShell.slate600 : JetonsShell.slate500, fontSize: 12, height: 16 / 12)),
        ])),
        if (ouvrable) ...[
          const SizedBox(width: 12),
          BoutonSigh(
              libelle: 'Ouvrir',
              icone: LucideIcons.arrowRight,
              taille: TailleBouton.sm,
              variante: VarianteBouton.secondaire,
              onPressed: () => c.aller(ecran)),
        ],
      ]));
}

/// L'écran OÙ SE VALIDE une famille. Le registre du domaine nomme `cfg-bareme-aib` pour le barème de l'AIB (vecteur de la réplique d'origine, qui a un écran de ce
/// nom) ; Baguidi tient ce barème, ses situations et ses décisions à `m12-aib` et `cfg-validations-aib` : le lien du centre des validations y mène, jamais à une
/// adresse qui n'existe pas ici.
String ecranDeFamille(String ecran) => ecran == 'cfg-bareme-aib' ? 'm12-aib' : ecran;

class _LigneConfiguration {
  const _LigneConfiguration(this.nom, this.libelle, this.attente, this.ecran, this.motif);
  final String nom, libelle, attente, ecran, motif;
}
