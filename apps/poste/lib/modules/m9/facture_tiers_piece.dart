import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';
import '../../impression/piece.dart';
import '../../core/service_parametres.dart';
import 'commun.dart';

/// Les signataires de la pièce, lus au RÉGLAGE de la clinique (`factureTiers.signataires`) puis à l'organigramme (le titulaire du poste) : aucun intitulé de poste ni nom n'est écrit ici.
List<Signature> signatairesPieceFactureTiers(Magasin m, DateTime date) {
  final p = serviceParametres(m, auteur: () => 'lecture');
  final reglage = p.valeur(factureTiersCleSignataires, parametreDateIso(date));
  return [for (final s in signatairesFactureTiers(postes: m.collection('postes').actives, reglage: reglage)) Signature(s.intitule, nom: s.titulaire, mention: 'Signature et cachet')];
}

/// LA FACTURE À UNE ENTREPRISE IMPRIMÉE (Direction de Baguidi, 17/11/2026, point 2) : l'en-tête légal UNIQUE de la clinique (fixé à la date de la pièce, jamais passé par l'appelant), l'acheteur
/// (nom et IFU), la ligne de prise en charge, les montants CALCULÉS depuis les lignes par la fonction unique de la normalisation (hors taxes, TVA, AIB au taux du barème que la pièce porte,
/// net à payer), le montant en lettres, le rattachement au relevé, les avoirs portés, le bloc fiscal MECeF (seulement quand la pièce est réellement certifiée : sinon le bandeau, jamais un faux
/// code) et les signatures (les signataires du réglage, puis l'entreprise). La facture du PATIENT reste sans acheteur ni AIB : cette pièce est la seule à en porter.
///
/// [avoirs] : les avoirs de la pièce (collection `avoirsTiers`). [libelleSituation] : le libellé de la situation d'AIB choisie, lu au barème. [signatures] : celles du paramétrage.
PieceA4 pieceFactureTiers(
  Fiche f, {
  List<Fiche> avoirs = const [],
  String? libelleSituation,
  bool mecefActif = true,
  required List<Signature> signatures,
  required String utilisateur,
  required DateTime edite,
  required String reference,
  IdentiteImprimee? identite,
}) {
  final i = identite ?? IdentiteImprimee.semence;
  final lignes = lignesFactureTiers(f);
  final taux = f['aibTaux'];
  final calcul = mecefMontants(lignes: lignes, totalAttendu: n(f['montantTTC']), aibTaux: taux is num ? taux : null);
  final mt = calcul.ok ? calcul.montants : null;
  TableauEtat rub(List<Fiche> r) => TableauEtat(colonnes: [
        ColonneEtat(libelle: 'Rubrique', valeur: (x) => x['k']),
        ColonneEtat(libelle: 'Montant', valeur: (x) => x['v'], droite: true),
      ], lignes: r);
  final avoirsActifs = [for (final a in avoirs) if (a['statut'] != 'archive' && a['factureId'] == f['id']) a];
  final cumul = avoirsActifs.fold<num>(0, (a, x) => a + n(x['montant']));
  final certifiee = mecefActif && porteBlocFiscal(f);
  final fn = mecefActif ? bandeauDemoMecef(f) : const <String>[];
  final graine = graineDe(f);
  return PieceA4(
    identite: i,
    titre: mecefActif ? 'Facture à une entreprise — normalisée' : 'Facture à une entreprise',
    sousTitre: '${f['numero']}${certifiee ? ' — ${f['numeroMecef']}' : ''}',
    reference: reference,
    utilisateur: utilisateur,
    edite: edite,
    cartouche: [
      ('Facture n°', '${f['numero']}'),
      ('Date', dateDe(f['date'])),
      ('Acheteur', '${f['acheteurNom'] ?? ''}'),
      ('IFU de l’acheteur', '${f['acheteurIfu'] ?? ''}'),
      ('Compagnie', '${f['compagnie'] ?? f['compagnieCode'] ?? ''}'),
      ('Souscripteur', '${f['souscripteur'] ?? ''}'),
      ('Période', '${dateDe(f['debut'])} au ${dateDe(f['fin'])}'),
      ('Situation d’AIB', '${libelleSituation ?? f['aibSituation'] ?? ''}'),
    ],
    blocs: [
      BlocTableau(TableauEtat(libelleTotal: 'TOTAL', colonnes: [
        ColonneEtat(libelle: 'Désignation', valeur: (l) => l['designation']),
        ColonneEtat(libelle: 'Qté', valeur: (l) => l['quantite'], droite: true, somme: (l) => n(l['quantite'])),
        ColonneEtat(libelle: 'P.U.', valeur: (l) => m(l['prixUnitaire']), droite: true),
        ColonneEtat(libelle: 'Montant', valeur: (l) => m(l['montant']), droite: true, somme: (l) => n(l['montant'])),
      ], lignes: lignes)),
      if (mt != null)
        BlocTableau(rub([
          {'k': 'TOTAL HT', 'v': m(mt.ht)},
          {'k': 'TVA', 'v': m(mt.tva)},
          {'k': 'TOTAL TTC', 'v': m(mt.total)},
          {'k': 'AIB ${f['aibTaux']} % (acompte sur impôt, retenu à l’acheteur sur le hors taxes)', 'v': m(mt.aib)},
          {'k': 'NET À PAYER (hors taxes + AIB)', 'v': m(mt.net)},
          if (mecefActif) {'k': 'Base normalisée MECeF', 'v': m(mt.base)},
        ]))
      else
        BlocTexte('Montants non calculables : ${calcul.refus?.motif ?? ''}', gras: true),
      if (f['aibMotif'] != null && '${f['aibMotif']}'.isNotEmpty) BlocTexte('Taux d’AIB : ${f['aibMotif']}', italique: true),
      if (mt != null) BlocTexte('${i.formuleArrete} : ${montantEnLettres(mt.net)}.', gras: true),
      BlocTexte(rattachementFactureTiers(f), italique: true),
      if (avoirsActifs.isNotEmpty) ...[
        BlocTableau(
            TableauEtat(libelleTotal: 'TOTAL DES AVOIRS', colonnes: [
              ColonneEtat(libelle: 'Avoir', valeur: (a) => a['reference']),
              ColonneEtat(libelle: 'Date', valeur: (a) => dateDe(a['date'])),
              ColonneEtat(libelle: 'Motif', valeur: (a) => a['motif']),
              ColonneEtat(libelle: 'Montant', valeur: (a) => m(a['montant']), droite: true, somme: (a) => n(a['montant'])),
            ], lignes: avoirsActifs),
            titre: 'Avoirs portés par la facture'),
        BlocTexte('Reste facturé après avoirs : ${m(n(f['montantTTC']) - cumul)} (hors taxes et AIB à recalculer sur ce reste).', gras: true),
      ],
      if (mecefActif && certifiee) ...[
        // Le QR est un EMPLACEMENT : la certification réelle vient du boîtier ; le code et les compteurs sont ceux que les autres factures normalisées impriment.
        const BlocTexte('QR CODE MECeF — emplacement réservé', italique: true),
        const BlocTexte('Code MECeF / DGI', gras: true),
        BlocTexte(codeMecef(graine), gras: true),
        BlocTexte('MECeF NIM : ${f['numeroMecef']}'),
        BlocTexte('MECeF Compteurs : ${compteurs(graine)}'),
        BlocTexte('IFU émetteur : ${i.ifu} — RCCM : ${i.rccm}'),
      ] else if (mecefActif) ...[
        for (final l in fn) BlocTexte(l, gras: l == fn.first),
      ],
      const BlocTexte(
          'Facture adressée à l’entreprise qui prend en charge le patient. Elle réclame les factures patients qu’elle désigne et ne les remplace pas : la facture du patient reste sans acheteur ni AIB.',
          italique: true),
      if (i.formulePolitesse.isNotEmpty) BlocTexte(i.formulePolitesse, gras: true),
    ],
    signatures: [...signatures, const Signature('Pour l’entreprise', mention: 'Reçu le / Signature et cachet')],
  );
}
