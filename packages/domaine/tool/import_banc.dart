// L'OUTIL DU BANC DE SYNCHRONISATION POUR LA DEMANDE D'IMPORT (lot IMP-C, « option c » de la Direction du 12/11/2026).
//
// Le banc (`packages/sync/banc`) fait tourner une mère et des fileuls qui sont des processus de SYNCHRONISATION : ils ne tiennent pas de magasin métier. Pour éprouver la demande d'import
// de bout en bout, cet outil fait tenir à un processus distinct le rôle du POSTE (fileul ou mère) sur des magasins en mémoire, avec LA règle du domaine (`demande_import.dart`) et la matrice
// de production (`packages/rbac/data/rbac.json`) : rien n'est réécrit côté JavaScript. Le banc lui passe l'état des magasins, il rend l'état d'après, et c'est lui qui porte les demandes et
// les verdicts par le protocole.
//
// Usage : `dart run tool/import_banc.dart <fileul|mere|reconcilier>` ; JSON sur l'entrée standard, JSON sur la sortie standard.
//   fileul      {role, par, poste, jeu, lignes, magasin, idDemande}             → {ok, refus?, demande?, magasin}
//   mere        {demande, magasin, octetsMax?}                                   → {appliquee, code?, motif?, geste?, lot?, champs, magasin}
//   suite       {demande, magasin}                                               → {suite, restitution?, archives?, gardees?, marques?, magasin}   (lot IMP-D : ce que le verdict commande au fileul)
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';

/// Miroir de `collectionsActivite` du poste (`apps/poste/lib/sync/pont_activite.dart`) PRIVÉ des collections que la mère seule écrit (`produits`) : ce qu'un fileul peut pousser par le pont.
const _activite = {
  'patients', 'rendezvous', 'constantes', 'releves', 'observations', 'visites', 'appels', 'consultations', 'dossiersConsultation', 'antecedents', 'decisionsDroits', 'demandesImport', 'presences',
  'usagesParametres', 'factures', 'avoirs', 'ecritures', 'mouvements', 'lots', 'admissions',
};

final _regime = RegimeDemandesImport(
  collectionsDeLaMere: {...cfbEssentielles, 'utilisateurs', valCollectionValidations, parCollectionParametres}.difference({'rolesBase', 'modulesManifeste', 'reglages', 'audit'}),
  collectionsActivite: _activite,
);

MatriceDroits _matrice() => MatriceDroits.depuisJson((jsonDecode(File('../rbac/data/rbac.json').readAsStringSync()) as Map).cast<String, Object?>());

ProfilImport _profil(MatriceDroits m, String role) => ProfilImport(role: role, libelleRole: m.libelle(role) ?? role, droitEcran: (e) => m.droit(role, e));

Map<String, Object?> _magasin(Object? j) => ((j as Map?) ?? const {}).cast<String, Object?>();

void main(List<String> args) {
  final entree = (jsonDecode(stdin.readLineSync(encoding: utf8) ?? '{}') as Map).cast<String, Object?>();
  final m = _matrice();
  final sortie = <String, Object?>{};
  switch (args.isEmpty ? '' : args.first) {
    case 'fileul':
      final role = '${entree['role']}', poste = '${entree['poste']}';
      final port = PortImportMemoire(_magasin(entree['magasin']), profilFixe: _profil(m, role), utilisateurFixe: '${entree['par']}', prefixeId: 'P$poste-', jourFixe: '2026-11-12');
      final jeu = jeuImportParId('${entree['jeu']}')!;
      final lignes = [for (final l in (entree['lignes'] as List)) [for (final c in (l as List)) c]];
      final a = analyserLignes(jeu, lignes, 'fichier.xlsx', port);
      if (!_regime.exigeLaMere(jeu)) {
        // Un jeu restreint (ou qui touche l'activité) ne se dépose JAMAIS : refus avant même de regarder le fichier.
        sortie
          ..['ok'] = false
          ..['refus'] = {'code': 'JEU_NON_DEMANDABLE', 'motif': 'le jeu « ${jeu.libelle} » ne passe pas par une demande à la mère'};
      } else if (!a.accepte) {
        sortie
          ..['ok'] = false
          ..['refus'] = {'code': a.globaux.firstOrNull?.code ?? 'ANALYSE_REFUSEE', 'motif': '${a.problemes.map((p) => p.motif).join(' ; ')}'};
      } else {
        final r = importerDirectEtDemander(jeu: jeu, analyse: a, port: port, regime: _regime, idDemande: '${entree['idDemande']}', poste: poste);
        sortie['ok'] = r.ok;
        if (r.ok) {
          sortie['demande'] = r.demande;
        } else {
          sortie['refus'] = {'code': r.refus!.code, 'motif': r.refus!.motif, 'geste': r.refus!.geste};
        }
      }
      sortie['magasin'] = port.instantane();
    case 'mere':
      final d = (entree['demande'] as Map).cast<String, Object?>();
      final role = '${d['demandeRole']}';
      final port = PortImportMemoire(_magasin(entree['magasin']), profilFixe: _profil(m, role), utilisateurFixe: '${d['demandePar']}', prefixeId: 'M', jourFixe: '2026-11-12');
      final v = traiterDemandeImport(d, port, jeuImportParId, regime: _regime, octetsMax: (entree['octetsMax'] as num?)?.toInt());
      sortie
        ..['appliquee'] = v.appliquee
        ..['code'] = v.code
        ..['motif'] = v.motif
        ..['geste'] = v.geste
        ..['lot'] = v.lot
        ..['champs'] = v.versChamps(traitePar: 'Mère', traiteLe: '2026-11-12')
        ..['magasin'] = port.instantane();
    case 'suite':
      // Ce que le verdict commande au FILEUL (lot IMP-D) : restituer le lot sur refus (archivage RG-14, une pièce émise reste), lever le marquage « en attente de la mère » sur confirmation.
      final d = (entree['demande'] as Map).cast<String, Object?>();
      final port = PortImportMemoire(_magasin(entree['magasin']), profilFixe: const ProfilImport.aucunDroit(), utilisateurFixe: 'Poste', jourFixe: '2026-11-12');
      final suite = suiteDuVerdict(d);
      sortie['suite'] = suite.name;
      if (suite == SuiteDuVerdict.restituer) {
        final r = restituerLotDirect(jeuImportParId, d['lotLocalId'], codeRefus: '${d['resultatCode']}', motifRefus: '${d['resultatMotif']}', port: port);
        sortie
          ..['ok'] = r.ok
          ..['restitution'] = r.etat
          ..['archives'] = r.archives
          ..['gardees'] = r.gardees.length;
      } else if (suite == SuiteDuVerdict.leverLeMarquage) {
        final lot = port.parId(collectionLots, d['lotLocalId']);
        var marques = 0;
        for (final e in ((lot?['ecrits'] as List?) ?? const []).cast<Map>()) {
          final f = port.parId('${e['collection']}', e['id']);
          if (f != null && f.remove(champEnAttenteMere) != null) marques++;
        }
        sortie['marques'] = marques;
      }
      sortie['magasin'] = port.instantane();
    default:
      stderr.writeln('commande inconnue : fileul, mere ou suite');
      exit(2);
  }
  stdout.writeln(jsonEncode(sortie));
}
