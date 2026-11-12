// LA DEMANDE D'IMPORT D'UN FILEUL À LA MÈRE (lot IMP-C, « option c » de la Direction du 12/11/2026), rejouée sur deux magasins en mémoire : le fileul écrit chez lui ET dépose
// une demande ; la mère rejoue sous le rôle de l'auteur et reste la seule autorité ; le verdict revient, l'écriture locale est réglée sans rien perdre en silence.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

ProfilImport profilDe(MatriceDroits m, String role) => ProfilImport(role: role, libelleRole: m.libelle(role) ?? role, droitEcran: (e) => m.droit(role, e));

void main() {
  final base = MatriceDroits.depuisJson((jsonDecode(File('../rbac/data/rbac.json').readAsStringSync()) as Map).cast<String, Object?>());
  // Les collections que la mère seule écrit (comme `collectionsConfiguration()` du poste) et celles de l'activité que le pont synchronise.
  final deLaMere = {...cfbEssentielles, 'utilisateurs', valCollectionValidations, parCollectionParametres}.difference({'rolesBase', 'modulesManifeste', 'reglages', 'audit'});
  const activite = {'patients', 'rendezvous', 'factures', 'avoirs', 'ecritures', 'mouvements', 'lots', 'admissions'};
  final regime = RegimeDemandesImport(collectionsDeLaMere: deLaMere, collectionsActivite: activite);

  List<List<Object?>> fichier(List<String> codes) => [
        [for (final c in jeuFournisseurs.colonnes) c.label],
        for (final code in codes) [...ligneExemple(jeuFournisseurs)]..[0] = code..[1] = 'FOURNISSEUR $code',
      ];
  // Le fileul : comptable (droit d'importer les fournisseurs dans la matrice d'origine), identifiants propres au poste.
  PortImportMemoire fileul({String role = 'comptable', Map<String, Object?> jeu = const {}}) =>
      PortImportMemoire(jeu, profilFixe: profilDe(base, role), utilisateurFixe: 'COMPTABLE F1', prefixeId: 'FOURF1-');
  PortImportMemoire mere(ProfilImport p, {Map<String, Object?> jeu = const {}}) => PortImportMemoire(jeu, profilFixe: p, utilisateurFixe: 'COMPTABLE F1', prefixeId: 'FOUR', jourFixe: '2026-11-12');

  ImportDirectEtDemande deposer(PortImportMemoire f, List<String> codes, {String id = 'DIM1'}) {
    final a = analyserFichier(jeuFournisseurs, fichier(codes), 'fournisseurs.xlsx', f);
    expect(a.accepte, isTrue, reason: a.problemes.map((p) => p.motif).join(' / '));
    return importerDirectEtDemander(jeu: jeuFournisseurs, analyse: a, port: f, regime: regime, idDemande: id, poste: 'F1');
  }

  group('quels jeux passent par une demande', () {
    test('seuls les référentiels que la mère seule écrit, non restreints, sans cible d\'activité', () {
      final demandables = {for (final j in jeuxImport) if (regime.exigeLaMere(j)) j.id};
      expect(demandables, {'actes', 'analyses', 'fournisseurs', 'assureurs', 'souscripteurs', 'plan-comptable', 'produits', 'emplacements'},
          reason: 'mesuré : les jeux dont toutes les cibles sont de la configuration de la mère');
      for (final jamais in ['personnel', 'patients', 'soldes-ouverture', 'stock-detail', 'transferts', 'inventaire', 'courriers', 'grand-stock']) {
        expect(demandables.contains(jamais), isFalse, reason: '$jamais ne passe jamais par une demande');
      }
      expect({for (final j in jeuxImport) if (j.restreint) j.id}.intersection(demandables), isEmpty, reason: 'un jeu restreint ne passe JAMAIS par une demande');
      expect(regime.reserveALaMere(jeuPersonnel), isTrue, reason: 'le personnel se règle à la mère : le fileul le dit');
    });
  });

  group('le fileul : écriture directe ET demande', () {
    test('il voit son import tout de suite (fiches provisoires, identifiants propres au poste) et la demande part vérifiée', () {
      final f = fileul();
      final r = deposer(f, ['SOBAPS', 'NSIA']);
      expect(r.ok, isTrue);
      final fiches = f.actives('fournisseurs');
      expect(fiches, hasLength(2), reason: 'visible chez le fileul immédiatement');
      expect(fiches.every((x) => x['provisoireMere'] == true && x['demandeImport'] == 'DIM1' && '${x['id']}'.startsWith('FOURF1-')), isTrue);
      final d = r.demande!;
      expect(d['etat'], demandeImportEnAttente);
      expect(d['demandeRole'], 'comptable');
      expect(d['demandePar'], 'COMPTABLE F1');
      expect((d['lignes'] as List), hasLength(3), reason: 'l\'en-tête et deux lignes : la mère doit pouvoir rejouer');
      expect(d['lotLocal'], isNotNull);
      final lot = f.toutes(collectionLots).single;
      expect(lot['etatMere'], 'en_attente');
      expect(f.journal.any((l) => l.startsWith('Demande d’import déposée à la mère')), isTrue, reason: 'RG-12 : journal côté fileul');
    });

    test('sans le droit du rôle : refus nommé du moteur, RIEN d\'écrit, RIEN de déposé', () {
      final f = fileul(role: 'medecin');
      final a = analyserFichier(jeuFournisseurs, fichier(['X']), 'f.xlsx', fileul());
      final r = importerDirectEtDemander(jeu: jeuFournisseurs, analyse: a, port: f, regime: regime, idDemande: 'DIM9', poste: 'F1');
      expect(r.ok, isFalse);
      expect(r.refus!.code, 'DROIT_IMPORT_REFUSE');
      expect(f.toutes('fournisseurs'), isEmpty);
    });

    test('un jeu restreint ne se dépose JAMAIS (refus nommé, rien écrit)', () {
      final f = fileul(role: 'admin');
      final a = analyserFichier(jeuPersonnel, [[for (final c in jeuPersonnel.colonnes) c.label]], 'p.xlsx', f);
      final r = importerDirectEtDemander(jeu: jeuPersonnel, analyse: a, port: f, regime: regime, idDemande: 'DIM8', poste: 'F1');
      expect(r.ok, isFalse);
      expect(r.refus!.code, 'JEU_NON_DEMANDABLE');
    });
  });

  group('la mère : seule autorité', () {
    Map<String, Object?> demandeValide() => deposer(fileul(), ['SOBAPS', 'NSIA']).demande!;

    test('elle rejoue sous le rôle de l\'auteur et applique par le chemin de l\'import local, lot et journal à elle', () {
      final m = mere(profilDe(base, 'comptable'));
      final v = traiterDemandeImport(demandeValide(), m, jeuImportParId, regime: regime);
      expect(v.appliquee, isTrue, reason: '${v.code} ${v.motif}');
      expect(v.ecrits, 2);
      expect(m.actives('fournisseurs'), hasLength(2));
      expect(m.actives('fournisseurs').every((x) => x['provisoireMere'] == null && x['lotImport'] == v.lot), isTrue, reason: 'les fiches de la mère ne portent aucun marquage provisoire');
      expect(m.journal.any((l) => l.startsWith('Import|')), isTrue);
      final champs = v.versChamps(traitePar: 'Mère', traiteLe: '2026-11-12');
      expect(champs['etat'], demandeImportAppliquee);
      expect(champs['lignes'], isEmpty, reason: 'les lignes du fichier sont effacées dès le verdict');
    });

    test('REFUS : le rôle de l\'auteur n\'a plus (ou n\'a jamais eu) le droit, relu à la mère — un fileul falsifié ne se prête pas les droits d\'un autre', () {
      final d = demandeValide();
      final m = mere(profilDe(base, 'medecin'));
      final v = traiterDemandeImport({...d, 'demandeRole': 'medecin'}, m, jeuImportParId, regime: regime);
      expect(v.appliquee, isFalse);
      expect(v.code, 'DROIT_IMPORT_REFUSE');
      expect(m.toutes('fournisseurs'), isEmpty);
      expect(m.toutes(collectionLots), isEmpty, reason: 'un refus de droit ne se consigne pas');
    });

    test('REFUS NOMMÉ : une fiche équivalente créée à la mère entre-temps (DOUBLON_MAGASIN), le fichier consigné, rien écrit', () {
      final m = mere(profilDe(base, 'comptable'), jeu: {
        'fournisseurs': [
          {'id': 'F1', 'code': 'SOBAPS', 'nom': 'Existant', 'statut': 'actif'}
        ]
      });
      final v = traiterDemandeImport(demandeValide(), m, jeuImportParId, regime: regime);
      expect(v.appliquee, isFalse);
      expect(v.code, 'DOUBLON_MAGASIN');
      expect(v.motif, contains('rejoué à la mère'));
      expect(v.lot, isNotNull, reason: 'le fichier refusé est consigné à l\'historique de la mère');
      expect(m.actives('fournisseurs'), hasLength(1));
    });

    test('FORGÉE : une demande pour un jeu restreint est refusée en le nommant, même si l\'auteur a tous les droits', () {
      final m = mere(profilDe(base, 'admin'));
      final d = {...demandeValide(), 'jeu': 'patients', 'lignes': [[for (final c in jeuPatients.colonnes) c.label]]};
      final v = traiterDemandeImport(d, m, jeuImportParId, regime: regime);
      expect(v.code, 'JEU_RESTREINT');
      expect(m.toutes('patients'), isEmpty);
    });

    test('FORGÉE : un jeu qui touche l\'activité (stock) ou un jeu inconnu ne passe pas', () {
      final m = mere(profilDe(base, 'admin'));
      expect(traiterDemandeImport({...demandeValide(), 'jeu': 'grand-stock'}, m, jeuImportParId, regime: regime).code, 'JEU_NON_DEMANDABLE');
      expect(traiterDemandeImport({...demandeValide(), 'jeu': 'inconnu'}, m, jeuImportParId, regime: regime).code, 'JEU_INCONNU');
    });

    test('FORGÉE : des lignes démesurées (au-delà de la borne du jeu) sont refusées avant tout rejeu', () {
      final m = mere(profilDe(base, 'comptable'));
      final enorme = [
        for (var i = 0; i < 3; i++) ['X' * 400000]
      ];
      final v = traiterDemandeImport({...demandeValide(), 'lignes': enorme}, m, jeuImportParId, regime: regime, octetsMax: 50 * 1024);
      expect(v.code, 'FICHIER_TROP_GROS');
    });

    test('un verdict n\'est jamais écrit deux fois', () {
      final m = mere(profilDe(base, 'comptable'));
      final d = demandeValide();
      final v = traiterDemandeImport(d, m, jeuImportParId, regime: regime);
      final dejaTraitee = {...d, ...v.versChamps(traitePar: 'Mère', traiteLe: '2026-11-12')};
      expect(traiterDemandeImport(dejaTraitee, m, jeuImportParId, regime: regime).code, 'DEMANDE_DEJA_TRAITEE');
      expect(m.actives('fournisseurs'), hasLength(2), reason: 'pas de seconde écriture');
    });
  });

  group('le fileul règle son écriture locale quand le verdict revient', () {
    test('APPLIQUÉE : l\'écriture provisoire reste tant que la copie de la mère n\'est pas visible, puis elle est ARCHIVÉE (jamais supprimée)', () {
      final f = fileul();
      final d = deposer(f, ['SOBAPS']).demande!;
      final v = traiterDemandeImport(d, mere(profilDe(base, 'comptable')), jeuImportParId, regime: regime);
      final avecVerdict = {...d, ...v.versChamps(traitePar: 'Mère', traiteLe: '2026-11-12')};
      var copie = false;
      final r1 = reconcilierEcrituresLocales(avecVerdict, f, copieDeLaMereVisible: (c, lot) => copie);
      expect(r1.issue, 'attente_copie');
      expect(f.actives('fournisseurs'), hasLength(1), reason: 'toujours visible : le fileul ne se retrouve pas sans rien');
      copie = true;
      final r2 = reconcilierEcrituresLocales(avecVerdict, f, copieDeLaMereVisible: (c, lot) => lot == v.lot);
      expect(r2.issue, 'retenue');
      expect(r2.archivees, 1);
      expect(f.actives('fournisseurs'), isEmpty);
      expect(f.toutes('fournisseurs').single['statut'], 'archive');
      expect(f.toutes('fournisseurs').single['_motifArchivage'], contains('Retenue par la mère'));
      expect(r2.aNotifier, isTrue);
      expect(reconcilierEcrituresLocales(avecVerdict, f, copieDeLaMereVisible: (c, lot) => true).issue, 'sans_objet', reason: 'idempotent');
    });

    test('REFUSÉE : l\'écriture locale RESTE, marquée « non retenue par la mère » avec le code, le motif et le geste ; une notification le dit', () {
      final f = fileul();
      final d = deposer(f, ['SOBAPS']).demande!;
      final m = mere(profilDe(base, 'comptable'), jeu: {
        'fournisseurs': [
          {'id': 'F1', 'code': 'SOBAPS', 'nom': 'Existant', 'statut': 'actif'}
        ]
      });
      final v = traiterDemandeImport(d, m, jeuImportParId, regime: regime);
      final avecVerdict = {...d, ...v.versChamps(traitePar: 'Mère', traiteLe: '2026-11-12')};
      final r = reconcilierEcrituresLocales(avecVerdict, f, copieDeLaMereVisible: (c, lot) => false);
      expect(r.issue, 'non_retenue');
      expect(r.marquees, 1);
      final fiche = f.actives('fournisseurs').single;
      expect(fiche['nonRetenueMere'], isTrue);
      expect(fiche['provisoireMere'], isFalse);
      expect(fiche['motifNonRetenue'], contains('DOUBLON_MAGASIN'));
      expect(r.detail, contains('non retenue par la mère'));
      expect(f.toutes(collectionLots).single['etatMere'], 'non_retenue');
    });

    test('ÉCRASÉE par la synchronisation : la fiche locale a disparu avant le verdict, c\'est compté et DIT', () {
      final f = fileul();
      final d = deposer(f, ['SOBAPS', 'NSIA']).demande!;
      f.toutes('fournisseurs').removeAt(0); // la synchronisation a remplacé une des deux fiches
      final v = traiterDemandeImport(d, mere(profilDe(base, 'comptable')), jeuImportParId, regime: regime);
      final r = reconcilierEcrituresLocales({...d, ...v.versChamps(traitePar: 'Mère', traiteLe: '2026-11-12')}, f, copieDeLaMereVisible: (c, lot) => true);
      expect(r.issue, 'retenue');
      expect(r.ecrasees, 1);
      expect(r.detail, contains('remplacées par la synchronisation'));
    });

    test('sans verdict, rien ne bouge', () {
      final f = fileul();
      final d = deposer(f, ['SOBAPS']).demande!;
      expect(reconcilierEcrituresLocales(d, f, copieDeLaMereVisible: (c, l) => true).issue, 'en_attente');
      expect(f.actives('fournisseurs').single['provisoireMere'], isTrue);
    });
  });

  group('le protocole : ce qu\'un fileul falsifié n\'écrit pas', () {
    test('création : « en attente », sans verdict ; jamais d\'état traité ni de champ de verdict', () {
      expect(refusDemandeImportDuFileul('creer', {'etat': 'en_attente', 'jeu': 'assureurs', 'lignes': []}), isNull);
      expect(refusDemandeImportDuFileul('creer', {'jeu': 'assureurs'}), isNull);
      expect(refusDemandeImportDuFileul('creer', {'etat': 'appliquee'}), isNotNull);
      expect(refusDemandeImportDuFileul('creer', {'etat': 'en_attente', 'resultatCode': 'X'}), isNotNull);
      expect(refusDemandeImportDuFileul('creer', {'traitePar': 'Mère'}), isNotNull);
    });
    test('modification : ni l\'état ni le verdict ne se réécrivent', () {
      expect(refusDemandeImportDuFileul('modifier', {'etat': 'en_attente'}), isNotNull, reason: 'remettre en attente une demande traitée la ferait rejouer');
      expect(refusDemandeImportDuFileul('modifier', {'resultatMotif': 'ok'}), isNotNull);
      expect(refusDemandeImportDuFileul('modifier', {'fichier': 'autre.xlsx'}), isNull);
    });
  });
}
