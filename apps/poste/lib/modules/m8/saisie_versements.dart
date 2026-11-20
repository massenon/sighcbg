import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import 'commun.dart';

/// LA SAISIE DES VERSEMENTS (Direction de Baguidi, 20/11/2026, §13) : le bloc que les portes d'encaissement de la caisse partagent. Le caissier ajoute autant de versements qu'il en
/// faut (type, modalité éventuelle, référence saisie à la main, montant) ; la liste des versements saisis et le RESTE À RÉPARTIR se recalculent à chaque ajout ; la validation finale se
/// fait au pied de la modale de la porte. Aucun type ni modalité n'est écrit ici : les listes viennent des paramètres (`typesVersement`, `modalitesVersement`).
class SaisieVersements {
  SaisieVersements({required Magasin magasin, required this.aRepartir, this.toast}) : _magasin = magasin {
    types = typesVersementEnService(magasin.collection(colTypesVersement).toutes);
    final modalites = modalitesVersementEnService(magasin.collection(colModalitesVersement).toutes);
    form = ControleurFormulaire([
      ChampDef(nom: 'versement_type', libelle: 'Type de versement', type: TypeChamp.select, requis: true, options: [for (final t in types) OptionChamp(t.code, t.libelle)]),
      // Une liste de modalités PAR type qui en a (le champ n'apparaît que pour son type) : la liste vient des paramètres.
      for (final t in types)
        if (modalites.any((x) => x.type == t.code))
          ChampDef(
              nom: 'versement_modalite_${t.code}',
              libelle: 'Modalité (${t.libelle})',
              type: TypeChamp.select,
              sansPreselection: true,
              condition: (controle: 'versement_type', quand: [t.code]),
              options: [for (final x in modalites) if (x.type == t.code) OptionChamp(x.id, x.libelle)]),
      const ChampDef(nom: 'versement_montant', libelle: 'Montant du versement (FCFA)', type: TypeChamp.nombre, indicatif: 'Vide : le reste à répartir'),
      const ChampDef(nom: 'versement_reference', libelle: 'Référence de la transaction', indicatif: 'N° de transaction, chèque…', aide: 'Saisie à la main (aucune lecture automatique). Obligatoire pour les types qui l’exigent.'),
    ], {
      'versement_type': types.isEmpty ? '' : types.first.code,
    });
    form.addListener(_notifier);
  }

  final Magasin _magasin;

  /// Ce que les versements doivent totaliser (le total des prestations cochées, ou le reste dû d'une pièce sans lignes) : lu à chaque affichage.
  final num Function() aRepartir;

  /// Annonce un refus (toast de la porte). Sans toast, le refus reste affiché sous la liste.
  final void Function(String titre, String detail)? toast;

  late final List<TypeVersement> types;
  late final ControleurFormulaire form;
  final List<VersementSaisi> saisis = [];
  final ValueNotifier<int> version = ValueNotifier(0);
  String? _refusLocal;

  void _notifier() => version.value++;

  num get totalSaisi => saisis.fold<num>(0, (a, v) => a + v.montant);
  num get reste => aRepartir() - totalSaisi;

  TypeVersement? _type(String code) {
    for (final t in types) {
      if (t.code == code) return t;
    }
    return null;
  }

  VersementSaisi? _depuisFormulaire() {
    final code = '${form['versement_type']}';
    final t = _type(code);
    final brut = '${form['versement_montant']}'.trim();
    final montant = brut.isEmpty ? reste : (num.tryParse(brut.replaceAll(RegExp(r'\s'), '').replaceAll(',', '.')) ?? 0);
    final mod = '${form['versement_modalite_$code'] ?? ''}';
    return VersementSaisi(montant: montant, type: t?.code ?? code, modalite: mod.isEmpty ? null : mod, reference: '${form['versement_reference']}');
  }

  /// Ajoute le versement du formulaire à la liste. Refus nommé (montant, plafond, référence exigée) : rien n'est ajouté.
  bool ajouter() {
    final v = _depuisFormulaire();
    if (v == null) return false;
    final t = _type(v.type);
    String? refus;
    if (t == null) {
      refus = 'Choisir un type de versement.';
    } else if (!(v.montant > 0)) {
      refus = 'Le montant du versement doit être supérieur à zéro (rien à répartir ?).';
    } else if (v.montant > reste + 0.5) {
      refus = 'Ce versement (${money(v.montant)}) dépasse le reste à répartir (${money(reste)}) : un versement ne dépasse jamais le dû.';
    } else if (t.referenceExigee && v.reference.trim().isEmpty) {
      refus = 'Le type « ${t.libelle} » exige la référence de la transaction (saisie à la main).';
    } else if (saisis.any((x) => x.type == v.type && v.reference.trim().isNotEmpty && x.reference.trim().toLowerCase() == v.reference.trim().toLowerCase())) {
      refus = 'La référence « ${v.reference.trim()} » est déjà saisie pour ce type : une transaction ne règle qu’une fois.';
    }
    if (refus != null) {
      _refusLocal = refus;
      toast?.call('Versement non ajouté.', refus);
      version.value++;
      return false;
    }
    saisis.add(v);
    _refusLocal = null;
    form.poser('versement_montant', '');
    form.poser('versement_reference', '');
    version.value++;
    return true;
  }

  void retirer(int i) {
    saisis.removeAt(i);
    _refusLocal = null;
    version.value++;
  }

  /// La liste à valider : les versements saisis, plus celui du formulaire s'il reste quelque chose à répartir (le cas ordinaire : un seul versement, d'un seul geste). Null : refus déjà annoncé.
  List<VersementSaisi>? finaliser() {
    if (reste > 0.5 || saisis.isEmpty) {
      if (!ajouter()) return null;
    }
    return List.of(saisis);
  }

  String libelleType(String code) => _type(code)?.libelle ?? libelleDeType(_magasin.collection(colTypesVersement).toutes, code, repli: modeLabel);

  String nomModalite(String? id) => id == null ? '' : (libelleModalite(_magasin.collection(colModalitesVersement).toutes, id) ?? '');

  Widget construire() => ValueListenableBuilder<int>(
      valueListenable: version,
      builder: (context, _, __) {
        final r = reste;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text('VERSEMENTS',
              style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.6)),
          const SizedBox(height: 6),
          if (saisis.isEmpty)
            const Text('Aucun versement ajouté : le formulaire ci-dessous vaut un seul versement du reste à répartir. « Ajouter un versement » permet de régler en plusieurs modes (Mobile Money puis espèces…).',
                key: Key('versements:aucun'), style: TextStyle(color: JetonsShell.slate500, fontSize: 13)),
          for (final (i, v) in saisis.indexed)
            Container(
              key: Key('versements:ligne:$i'),
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: JetonsShell.slate50, borderRadius: BorderRadius.circular(8), border: Border.all(color: JetonsShell.slate200)),
              child: Row(children: [
                Expanded(
                    child: Text(
                        '${libelleType(v.type)}${v.modalite == null ? '' : ' — ${nomModalite(v.modalite)}'}${v.reference.trim().isEmpty ? '' : ' · réf. ${v.reference.trim()}'}',
                        style: const TextStyle(color: JetonsShell.slate800, fontSize: 14))),
                Text(money(v.montant), key: Key('versements:ligne:$i:montant'), style: const TextStyle(color: JetonsShell.navy900, fontSize: 14, fontWeight: FontWeight.w600)),
                BoutonIcone(icone: LucideIcons.x, libelle: 'Retirer ce versement', onPressed: () => retirer(i)),
              ]),
            ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: JetonsShell.slate50, borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              const Text('RESTE À RÉPARTIR', style: TextStyle(color: JetonsShell.slate500, fontSize: 12, letterSpacing: 0.6)),
              const Spacer(),
              Text(money(r < 0 ? 0 : r), key: const Key('versements:reste'), style: const TextStyle(color: JetonsShell.navy900, fontSize: 16, fontWeight: FontWeight.w700)),
            ]),
          ),
          if (_refusLocal != null && toast == null)
            Padding(padding: const EdgeInsets.only(top: 6), child: NoteSigh(_refusLocal!, ton: TonSigh.danger, icone: LucideIcons.circleAlert)),
          const SizedBox(height: 10),
          FormulaireSigh(controleur: form),
          const SizedBox(height: 8),
          Align(
              alignment: Alignment.centerLeft,
              child: BoutonSigh(
                  libelle: 'Ajouter un versement',
                  icone: LucideIcons.plus,
                  variante: VarianteBouton.secondaire,
                  onPressed: r > 0.5 ? ajouter : null)),
        ]);
      });
}
