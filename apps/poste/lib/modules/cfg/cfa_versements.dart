import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../../shell/gestes_ecran.dart';
import 'cfa_commun.dart';

/// LES TYPES ET LES MODALITÉS DE VERSEMENT (Direction de Baguidi, 20/11/2026, §13) — les paramètres du règlement en plusieurs versements, administrables : créer, modifier, archiver
/// (annulable, RG-14) et restaurer. Aucun type n'est écrit dans une règle : le caissier ne choisit que ce que la clinique a réglé ici. Le geste est RÉSERVÉ (`versement_regler`) : sans lui,
/// les commandes sont ABSENTES et l'écran se lit seulement.
bool cfaPeutRegler(ContexteEcran c) => gestesEcran(c).peut(c.role, gesteVersementRegler);

const _noteAConfirmer =
    'Valeurs d’ATTENTE, « à confirmer par la Direction » : aucun document ne fixe les types de versement de Baguidi, leurs comptes de trésorerie réels ni la liste officielle des opérateurs Mobile Money. Les corriger arrête la valeur.';

/// Les comptes de TRÉSORERIE (classe 5) du plan comptable, pour le choix du compte d'un type. Le compte déjà porté reste proposé même s'il n'est plus au plan.
List<OptionChamp> _comptesTresorerie(Magasin m, [Object? actuel]) {
  final l = <OptionChamp>[
    for (final x in m.collection('comptes').actives)
      if ('${x['classe']}' == '5' && '${x['num']}'.length >= 6) OptionChamp('${x['num']}', '${x['num']} — ${x['libelle']}')
  ];
  final a = '${actuel ?? ''}';
  if (a.isNotEmpty && !l.any((o) => o.valeur == a)) l.insert(0, OptionChamp(a, a));
  return l;
}

/// Le bouton qui sème les valeurs d'attente quand la collection est vide (poste neuf) : sans lui, la liste d'un poste neuf ne montrerait rien alors que le caissier se sert des valeurs d'attente.
Widget _initialiser(ContexteEcran c, String collection, List<Map<String, Object?>> semence) {
  final col = c.magasin.collection(collection);
  return ListenableBuilder(
      listenable: col,
      builder: (ctx, _) => col.toutes.isNotEmpty || !cfaPeutRegler(c)
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                const Expanded(child: NoteSigh('Aucune fiche enregistrée : les valeurs d’attente servent au guichet sans être modifiables. Les enregistrer pour les régler.', ton: TonSigh.attention)),
                const SizedBox(width: 12),
                BoutonSigh(
                    libelle: 'Enregistrer les valeurs d’attente',
                    icone: LucideIcons.listPlus,
                    onPressed: () {
                      for (final f in semence) {
                        col.inserer(f);
                      }
                    }),
              ])));
}

Widget cfaOngletTypesVersement(BuildContext context) {
  final c = ContexteEcran.of(context);
  final col = c.magasin.collection(colTypesVersement);
  return ListenableBuilder(
      listenable: col,
      builder: (ctx, _) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const NoteSigh(_noteAConfirmer, ton: TonSigh.attention, icone: LucideIcons.triangleAlert),
          const SizedBox(height: 12),
          _initialiser(c, colTypesVersement, typesVersementSemence()),
          CfaTableau(
            collection: colTypesVersement,
            titre: 'Types de versement',
            entite: 'Type de versement',
            libelleNouveau: 'Nouveau type',
            titreCreation: 'Type de versement',
            prefixeId: 'TV',
            taillePage: 20,
            triInitial: 'ordre',
            nomExport: 'types-versement',
            peutEcrire: cfaPeutRegler,
            colonnes: [
              ColonneTableau(cle: 'code', libelle: 'Code', sansCoupure: true, texte: (n) => '${n['code'] ?? ''}', rendu: (_, n) => cfaCode(n['code'])),
              ColonneTableau(cle: 'libelle', libelle: 'Type', texte: (n) => '${n['libelle'] ?? ''}', rendu: (_, n) => cfaGras('${n['libelle'] ?? ''}')),
              ColonneTableau(cle: 'compteTresorerie', libelle: 'Compte de trésorerie', sansCoupure: true, texte: (n) => '${n['compteTresorerie'] ?? ''}'),
              ColonneTableau(
                  cle: 'referenceExigee',
                  libelle: 'Référence',
                  texte: (n) => n['referenceExigee'] == true ? 'Exigée' : 'Facultative',
                  rendu: (_, n) => BadgeSigh(n['referenceExigee'] == true ? 'Exigée' : 'Facultative', ton: n['referenceExigee'] == true ? TonSigh.navy : TonSigh.neutre)),
              ColonneTableau(
                  cle: 'actif',
                  libelle: 'État',
                  texte: (n) => n['actif'] == false ? 'Inactif' : (n['aConfirmer'] == true ? 'À confirmer' : 'En service'),
                  rendu: (_, n) => BadgeSigh(n['actif'] == false ? 'Inactif' : (n['aConfirmer'] == true ? 'À confirmer' : 'En service'),
                      ton: n['actif'] == false ? TonSigh.neutre : (n['aConfirmer'] == true ? TonSigh.attention : TonSigh.succes))),
            ],
            champs: (e) => [
              const ChampDef(nom: 'libelle', libelle: 'Libellé du type', requis: true, col: ColChamp.plein),
              // Le code est celui que les versements portent : il ne se change pas après création (une pièce émise ne se réécrit pas).
              if (e == null)
                ChampDef(
                    nom: 'code',
                    libelle: 'Code',
                    requis: true,
                    aide: 'Minuscules, chiffres et tiret bas (ex. « cheque »). Ne se change plus une fois le type créé.',
                    valider: (v, _) {
                      final t = '$v'.trim();
                      if (!RegExp(r'^[a-z][a-z0-9_]{1,29}$').hasMatch(t)) return 'Minuscules, chiffres et « _ », 2 à 30 caractères, commençant par une lettre.';
                      if (col.toutes.any((x) => '${x['code']}' == t)) return 'Ce code existe déjà (archivé compris).';
                      return null;
                    }),
              ChampDef(nom: 'compteTresorerie', libelle: 'Compte de trésorerie (débité par un versement)', type: TypeChamp.select, requis: true, col: ColChamp.plein, options: _comptesTresorerie(c.magasin, e?['compteTresorerie'])),
              const ChampDef(nom: 'referenceExigee', libelle: 'La référence de transaction est exigée', type: TypeChamp.case_, col: ColChamp.plein),
              const ChampDef(nom: 'actif', libelle: 'Proposé au guichet', type: TypeChamp.case_, col: ColChamp.plein),
            ],
            valeursInitiales: () => {'actif': true, 'referenceExigee': false, 'compteTresorerie': compteCaisse},
            preparer: (f) => {...f, 'actif': f['actif'] != false},
            fiche: (s, e) => {
              ...s,
              'ordre': e?['ordre'] ?? (col.toutes.length + 1),
              // Corrigé par la Direction : la valeur d'attente cesse d'être « à confirmer ».
              'aConfirmer': false,
              'source': e == null ? 'Saisie par la Direction' : (e['source'] ?? 'Saisie par la Direction'),
            },
          ),
          const SizedBox(height: 16),
          _archives(c, col, 'Types archivés', (f) => '${f['libelle'] ?? f['code']}'),
        ]);
      });
}

Widget cfaOngletModalitesVersement(BuildContext context) {
  final c = ContexteEcran.of(context);
  final col = c.magasin.collection(colModalitesVersement);
  final types = c.magasin.collection(colTypesVersement);
  return ListenableBuilder(
      listenable: Listenable.merge([col, types]),
      builder: (ctx, _) {
        final enService = typesVersementEnService(types.toutes);
        String libType(Object? code) => libelleDeType(types.toutes, code);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const NoteSigh(_noteAConfirmer, ton: TonSigh.attention, icone: LucideIcons.triangleAlert),
          const SizedBox(height: 12),
          _initialiser(c, colModalitesVersement, modalitesVersementSemence()),
          CfaTableau(
            collection: colModalitesVersement,
            titre: 'Modalités de versement (opérateurs Mobile Money, banques…)',
            entite: 'Modalité de versement',
            libelleNouveau: 'Nouvelle modalité',
            titreCreation: 'Modalité de versement',
            prefixeId: 'MV',
            taillePage: 20,
            triInitial: 'ordre',
            nomExport: 'modalites-versement',
            peutEcrire: cfaPeutRegler,
            colonnes: [
              ColonneTableau(cle: 'libelle', libelle: 'Modalité', texte: (n) => '${n['libelle'] ?? ''}', rendu: (_, n) => cfaGras('${n['libelle'] ?? ''}')),
              ColonneTableau(cle: 'type', libelle: 'Rattachée au type', texte: (n) => libType(n['type']), rendu: (_, n) => BadgeSigh(libType(n['type']), ton: TonSigh.navy)),
              ColonneTableau(
                  cle: 'actif',
                  libelle: 'État',
                  texte: (n) => n['actif'] == false ? 'Inactive' : (n['aConfirmer'] == true ? 'À confirmer' : 'En service'),
                  rendu: (_, n) => BadgeSigh(n['actif'] == false ? 'Inactive' : (n['aConfirmer'] == true ? 'À confirmer' : 'En service'),
                      ton: n['actif'] == false ? TonSigh.neutre : (n['aConfirmer'] == true ? TonSigh.attention : TonSigh.succes))),
            ],
            champs: (e) => [
              const ChampDef(nom: 'libelle', libelle: 'Modalité (ex. nom de l’opérateur)', requis: true, col: ColChamp.plein),
              ChampDef(nom: 'type', libelle: 'Type de versement', type: TypeChamp.select, requis: true, col: ColChamp.plein, options: [for (final t in enService) OptionChamp(t.code, t.libelle)]),
              const ChampDef(nom: 'actif', libelle: 'Proposée au guichet', type: TypeChamp.case_, col: ColChamp.plein),
            ],
            valeursInitiales: () => {'actif': true},
            preparer: (f) => {...f, 'actif': f['actif'] != false},
            fiche: (s, e) => {...s, 'ordre': e?['ordre'] ?? (col.toutes.length + 1), 'aConfirmer': false, 'source': e == null ? 'Saisie par la Direction' : (e['source'] ?? 'Saisie par la Direction')},
          ),
          const SizedBox(height: 16),
          _archives(c, col, 'Modalités archivées', (f) => '${f['libelle'] ?? f['id']} — ${libType(f['type'])}'),
        ]);
      });
}

/// Les fiches ARCHIVÉES d'une collection de paramètres, avec « Restaurer » (RG-14 : l'archivage s'annule) — la commande n'existe que pour qui règle les versements.
Widget _archives(ContexteEcran c, CollectionMagasin col, String titre, String Function(Fiche) libelle) {
  final archivees = col.archivees;
  if (archivees.isEmpty) return const SizedBox.shrink();
  return CarteSigh(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(titre.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: JetonsShell.slate500)),
    const SizedBox(height: 8),
    for (final f in archivees)
      Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(libelle(f), style: const TextStyle(fontSize: 14, color: JetonsShell.slate700))),
            if (cfaPeutRegler(c))
              BoutonIcone(icone: LucideIcons.archiveRestore, libelle: 'Restaurer', onPressed: () {
                col.restaurer(f['id']);
              }),
          ])),
  ]));
}
