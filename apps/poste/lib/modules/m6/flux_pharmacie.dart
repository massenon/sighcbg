import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'flux_commun.dart';

/// Les DEUX pharmacies (`ecranPharmacie` de m6-stock.js). Le 25/08/2026 la Direction a tranché : la clinique distingue deux ordonnances, donc deux circuits — ils
/// n'ont ni le même justificatif de sortie, ni le même destinataire, ni le même rythme. La **pharmacie interne** sert les soins d'urgence administrés SUR PLACE : le
/// produit part vers la salle de soins, jamais vers le patient ; la **pharmacie externe** sert la voie orale que le patient EMPORTE. RG-03 s'applique aux deux :
/// toute sortie porte son justificatif (le n° d'ordonnance) et le stock ne devient jamais négatif — le refus NOMME l'article.
///
/// Aucune création manuelle : la délivrance naît d'une ordonnance du médecin passée en caisse. Corrigés dans la maquette avant le portage : E40 (états
/// « soldee » / « servie »), E41 (« inj » = injectable), E44 (message de succès jamais affiché).
///
/// DÉLIVRANCE LIGNE PAR LIGNE (Direction de Baguidi, 16/11/2026, E3300 à E3306) : chaque ligne RÉGLÉE à la caisse se délivre, même si le reste de l'ordonnance
/// ne l'est pas ; une ligne non réglée ou au « prix à valoriser » reste EN ATTENTE, affichée et nommée, sans commande « Délivrer ». Le geste passe par le moteur
/// unique `delivrerLignes` (le même que la file de la dispensation) : stock de DÉTAIL décompté (E45 levé), seule la LIGNE servie est marquée et l'ordonnance
/// devient « partiellement délivrée » tant qu'il lui reste des lignes (E46 levé), une ligne marquée ne ressort jamais du stock.
abstract class EcranPharmacie extends StatelessWidget with EcranMaquette {
  const EcranPharmacie(this.voie, {super.key});

  /// `parenterale` (interne) ou `orale` (externe).
  final String voie;

  String get note;

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final m = c.magasin;
    return ListenableBuilder(
      listenable: Listenable.merge([
        m.collection('ordonnances'),
        m.collection('produits'),
        m.collection('taches'),
        m.collection('factures'),
      ]),
      builder: (context, _) {
        final ls = lignesPharmacie(
            ordonnances: m.collection('ordonnances').actives,
            produits: m.collection('produits').actives,
            voie: voie,
            factures: m.collection('factures').toutes);
        final st = statsPharmacie(ls);
        final lignes = aDelivrerTriees(ls);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          KpiGrilleSigh(kpis: [
            KpiSigh(
                libelle: 'Lignes de cette pharmacie',
                valeur: nombre(st.lignes),
                icone: LucideIcons.pill,
                ton: TonSigh.navy),
            KpiSigh(
                libelle: 'À délivrer',
                valeur: nombre(st.aDelivrer),
                icone: LucideIcons.packageOpen,
                ton: TonSigh.info),
            KpiSigh(
                libelle: 'Bloquées faute de règlement',
                valeur: nombre(st.bloquees),
                icone: LucideIcons.lock,
                ton: st.bloquees > 0 ? TonSigh.attention : TonSigh.succes),
            KpiSigh(
                libelle: 'Non couvertes par le stock',
                valeur: nombre(st.decouvertes),
                icone: LucideIcons.triangleAlert,
                ton: st.decouvertes > 0 ? TonSigh.danger : TonSigh.succes,
                indice: 'RG-03 : refus nommé'),
          ]),
          const SizedBox(height: 16),
          NoteSigh(note, ton: TonSigh.info, icone: LucideIcons.route),
          const SizedBox(height: 16),
          TableauSigh(
            lignes: [
              for (final l in lignes)
                {
                  'id': l.id,
                  '_ligne': l,
                  'numero': l.numero,
                  'date': l.date,
                  'patient': '${l.patient} — ${l.patientCode}',
                  'designation': l.designation,
                  'quantite': l.quantite,
                  'posologie': l.posologie,
                  'stock': l.stock,
                  'etat': l.etat,
                }
            ],
            nomExport: 'pharmacie',
            messageVide: 'Aucun enregistrement.',
            colonnes: [
              const ColonneTableau(cle: 'numero', libelle: 'Ordonnance'),
              ColonneTableau(
                  cle: 'date',
                  libelle: 'Date',
                  texte: (r) => dateDe((r['_ligne'] as LignePharmacie).date)),
              const ColonneTableau(cle: 'patient', libelle: 'Patient'),
              const ColonneTableau(cle: 'designation', libelle: 'Produit'),
              const ColonneTableau(cle: 'quantite', libelle: 'Quantité', droite: true),
              const ColonneTableau(cle: 'posologie', libelle: 'Posologie'),
              ColonneTableau(
                  cle: 'stock',
                  libelle: 'Stock',
                  droite: true,
                  texte: (r) {
                    final l = r['_ligne'] as LignePharmacie;
                    return l.stock == null ? 'produit inconnu' : nombre(l.stock);
                  },
                  rendu: (_, r) {
                    final l = r['_ligne'] as LignePharmacie;
                    if (l.stock == null) {
                      return const Text('produit inconnu',
                          style: TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: JetonsShell.slate400));
                    }
                    return Text(nombre(l.stock),
                        style: TextStyle(
                            fontSize: 14,
                            height: 20 / 14,
                            fontWeight: l.couvert ? FontWeight.w400 : FontWeight.w600,
                            color: l.couvert ? JetonsShell.slate700 : JetonsShell.danger700));
                  }),
              ColonneTableau(
                  cle: 'etat',
                  libelle: 'État',
                  rendu: (_, r) {
                    final l = r['_ligne'] as LignePharmacie;
                    return BadgeSigh(l.etat,
                        ton: !l.paye
                            ? TonSigh.attention
                            : (!l.couvert ? TonSigh.danger : TonSigh.succes));
                  }),
            ],
            actionsLigne: (ctx, r) {
              final l = r['_ligne'] as LignePharmacie;
              if (!c.droit.editer) return const [];
              if (!l.paye) {
                // La LIGNE attend (la caisse ou son prix) : visible, nommée, jamais délivrable.
                final motif = l.attente ?? 'non réglée à la caisse';
                return [
                  BoutonIcone(
                      icone: LucideIcons.lock,
                      libelle: 'En attente : $motif',
                      onPressed: () => ToastsSigh.afficher(ctx,
                          'Délivrance en attente — « ${l.designation} » : $motif (ordonnance ${l.numero}).',
                          type: TypeToast.attention,
                          detail: motif == 'prix à valoriser'
                              ? 'L’article n’a pas encore de prix d’achat : la ligne s’encaissera, puis se délivrera, une fois le prix fixé. Les autres lignes réglées se délivrent.'
                              : 'Seule une ligne réglée à la caisse se délivre. Les autres lignes réglées de l’ordonnance se délivrent sans attendre celle-ci.'))
                ];
              }
              return [
                BoutonSigh(
                    libelle: 'Délivrer',
                    icone: LucideIcons.check,
                    taille: TailleBouton.sm,
                    onPressed: () => _delivrer(ctx, c, l))
              ];
            },
          ),
        ]);
      },
    );
  }

  Future<void> _delivrer(BuildContext ctx, ContexteEcran c, LignePharmacie l) async {
    // RG-03 : le refus NOMME l'article. Un refus muet ferait chercher la panne du côté du logiciel.
    if (!l.couvert) {
      ToastsSigh.afficher(ctx,
          'Délivrance refusée — stock insuffisant sur « ${l.designation} » : ${nombre(l.stock)} en rayon pour ${nombre(l.quantite)} demandé(s).',
          type: TypeToast.erreur);
      return;
    }
    final ok = await confirmerSigh(ctx,
        titre: 'Délivrer ${l.designation} ?',
        message: messageConfirmation(l, voie),
        libelleOk: 'Délivrer');
    if (!ok || !ctx.mounted) return;
    final mag = c.magasin;
    // Relue AU MOMENT du geste : une autre caisse, un autre poste ont pu changer la ligne pendant la confirmation.
    final ord = mag.collection('ordonnances').parId(l.ordonnance['id']) ?? l.ordonnance;
    final r = ecrireDelivrance(ctx, c, ord, lignes: [l.index], voie: voie);
    if (r == null || r.deja) return;
    final p = r.produits.isEmpty ? null : r.produits.last.patch;
    final reste = p == null ? null : (p['stockDetail'] ?? p['stock']);
    ToastsSigh.afficher(ctx, 'Délivré — stock ramené à ${nombre(reste)}.',
        type: TypeToast.succes,
        detail: '${l.designation} — ${l.patient}'
            '${r.etat == 'partielle' ? ' · ordonnance ${l.numero} partiellement délivrée' : ''}');
  }
}

class EcranPharmacieInterne extends EcranPharmacie {
  const EcranPharmacieInterne({super.key}) : super('parenterale');

  @override
  String get titre => 'Pharmacie interne — urgences';

  @override
  String get description =>
      'Produits administrés sur place : injectables, perfusions et solutés remis à la salle de soins.';

  @override
  String get regle =>
      'Le produit ne quitte pas la clinique : il est délivré à la salle de soins, qui l’administre. Il n’y a pas de vente au comptoir — la sortie de stock est justifiée par une prescription, pas par un ticket. RG-03 s’applique : le refus nomme l’article.';

  @override
  String get note =>
      'Cette pharmacie sert les soins d’urgence administrés sur place. Les produits partent vers la salle de soins, jamais vers le patient directement — c’est le personnel soignant qui les administre, et la traçabilité de l’administration relève de la prescription de soins.';
}

class EcranPharmacieExterne extends EcranPharmacie {
  const EcranPharmacieExterne({super.key}) : super('orale');

  @override
  String get titre => 'Pharmacie externe — voie orale';

  @override
  String get description =>
      'Traitements par voie orale que le patient emporte : délivrance au comptoir sur ordonnance réglée.';

  @override
  String get regle =>
      'Le patient emporte son traitement. La délivrance suppose une ordonnance réglée — c’est la même règle qu’au laboratoire et en salle de soins. RG-03 : toute sortie porte son justificatif, et le stock ne devient jamais négatif.';

  @override
  String get note =>
      'Cette pharmacie sert les traitements par voie orale que le patient emporte. La distinction avec la pharmacie interne n’est pas administrative : les deux circuits n’ont ni le même justificatif de sortie, ni le même destinataire.';
}
