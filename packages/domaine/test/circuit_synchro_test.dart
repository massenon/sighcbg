import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef M = Map<String, Object?>;
final auj = DateTime.utc(2026, 11, 16, 9);

M bon(String etape, {String ref = 'BEB-2026-0001', String id = 'BES1'}) => {'id': id, 'idSync': 'F1-$id', 'reference': ref, 'etape': etape, 'service': 'Labo', 'montantEstime': 1000, 'lignes': <M>[]};

/// Les gestes réservés d'ORIGINE (aucune fiche) : « Valider les achats » à la Directrice Administrative seule (Direction du 16/11/2026).
final _origine = DroitsGestes(fiches: const []);

void main() {
  group('rangs et refus de la mère', () {
    test('un état ne régresse jamais, un arbitrage ne s\'écrit pas depuis un poste, l\'aval suppose l\'arbitrage', () {
      expect(refusCircuitAchat('besoins', 'modifier', {'etape': 'soumis'}, etatActuel: 'accorde')!.code, 'etat_regressif');
      expect(refusCircuitAchat('besoins', 'modifier', {'etape': 'accorde'}, etatActuel: 'soumis')!.code, 'arbitrage_reserve');
      expect(refusCircuitAchat('besoins', 'modifier', {'etape': 'rejete'}, etatActuel: 'soumis')!.code, 'arbitrage_reserve');
      expect(refusCircuitAchat('besoins', 'modifier', {'etape': 'prepare'}, etatActuel: 'soumis')!.code, 'arbitrage_requis');
      expect(refusCircuitAchat('besoins', 'modifier', {'etape': 'prepare'}, etatActuel: 'accorde'), isNull);
      expect(refusCircuitAchat('besoins', 'modifier', {'etape': 'controle_stock'}, etatActuel: 'soumis'), isNull);
      expect(refusCircuitAchat('besoins', 'modifier', {'motif': 'x'}, etatActuel: 'accorde'), isNull, reason: 'une modification sans état n\'est pas concernée');
      expect(refusCircuitAchat('besoins', 'creer', {'etape': 'accorde'})!.code, 'arbitrage_requis');
      expect(refusCircuitAchat('besoins', 'creer', {'etape': 'soumis'}), isNull);
      expect(refusCircuitAchat('commandes', 'modifier', {'statutCommande': 'validee'}, etatActuel: 'attente_validation')!.code, 'arbitrage_reserve');
      expect(refusCircuitAchat('commandes', 'modifier', {'statutCommande': 'transmise'}, etatActuel: 'attente_validation')!.code, 'arbitrage_requis');
      expect(refusCircuitAchat('commandes', 'modifier', {'statutCommande': 'transmise'}, etatActuel: 'validee'), isNull);
      expect(refusCircuitAchat('commandes', 'modifier', {'statutCommande': 'brouillon'}, etatActuel: 'validee')!.code, 'etat_regressif');
      expect(refusCircuitAchat('factures', 'modifier', {'etape': 'x'}, etatActuel: 'y'), isNull, reason: 'les autres collections ne sont pas concernées');
    });
  });

  group('fusion de l\'état', () {
    test('un bon accordé ne repasse pas soumis par une fusion tardive ; l\'avance locale est gardée', () {
      final local = {...bon('soumis'), 'motif': 'précis'};
      final recu = {...bon('accorde'), 'arbitrePar': 'La DAF', 'arbitreLe': '2026-11-16T09:00:00Z', 'valideePar': 'La DAF'};
      final f = fusionnerCircuitAchat('besoins', {...local, 'etape': 'soumis'}, local, recu);
      expect(f['etape'], 'accorde');
      expect(f['arbitrePar'], 'La DAF');
      expect(f['motif'], 'précis', reason: 'les autres champs de la fusion sont intacts');
      final inverse = fusionnerCircuitAchat('besoins', {...recu}, recu, local);
      expect(inverse['etape'], 'accorde', reason: 'même résultat dans l\'autre sens');
    });
    test('deux décisions concurrentes : la plus ancienne l\'emporte partout, la perdante est nommée', () {
      final a = {...bon('accorde'), 'arbitrePar': 'DAF 1', 'arbitreLe': '2026-11-16T08:00:00Z'};
      final b = {...bon('rejete'), 'arbitrePar': 'DAF 2', 'arbitreLe': '2026-11-16T09:00:00Z', 'motifArbitrage': 'non'};
      final x = fusionnerCircuitAchat('besoins', {...a}, a, b);
      final y = fusionnerCircuitAchat('besoins', {...b}, b, a);
      expect([x['etape'], y['etape']], ['accorde', 'accorde']);
      expect((x['arbitrageConcurrent'] as Map)['etat'], 'rejete');
      expect(x['arbitrageConcurrent'], y['arbitrageConcurrent']);
    });
    test('un fileul n\'invente pas un arbitrage : le journal l\'emporte, même plus bas', () {
      final local = {...bon('accorde'), 'arbitrePar': 'Moi'};
      final recu = bon('soumis');
      expect(fusionnerCircuitAchat('besoins', {...local}, local, recu, posteFileul: true)['etape'], 'soumis');
      expect(fusionnerCircuitAchat('besoins', {...local}, local, recu)['etape'], 'accorde', reason: 'la mère, elle, détient légitimement ses décisions');
    });
    test('la commande : la validation voyage avec ses traces', () {
      final local = {'id': 'C1', 'statutCommande': 'attente_validation', 'reference': 'BC-2026-0001'};
      final recu = {...local, 'statutCommande': 'validee', 'valideePar': 'TACHEDI', 'dateValidation': '2026-11-16', 'valideeParAgent': 'La DAF'};
      final f = fusionnerCircuitAchat('commandes', {...local}, local, recu);
      expect([f['statutCommande'], f['valideeParAgent'], f['dateValidation']], ['validee', 'La DAF', '2026-11-16']);
    });
  });

  group('dépôt et application', () {
    List<M> nouveau(M b, {String decision = 'valider', String motif = '', String role = 'da'}) {
      final r = circuitDeposer(
          gestes: _origine,
          famille: circuitBesoinArbitrage, bon: b, decision: decision, motif: motif, role: role, acteur: 'La DAF', poste: 'F2', maintenant: auj, besoins: [b], commandes: const [], depots: const [], nouvelId: () => 'D1');
      return [if (r.ok) r.fiche! else {'refus': r.refus!.code}];
    }

    test('refus nommés avant tout dépôt', () {
      expect(nouveau(bon('soumis'), role: 'caissier').single['refus'], 'VALIDATION_RESERVEE');
      expect(nouveau(bon('soumis'), decision: 'rejeter').single['refus'], 'MOTIF_OBLIGATOIRE');
      expect(nouveau(bon('brouillon')).single['refus'], 'PAS_SOUMIS');
      expect(nouveau(bon('accorde'), decision: 'rejeter', motif: 'non').single['refus'], 'DEJA_ARBITRE');
      expect(nouveau(bon('soumis'), decision: 'peut-etre').single['refus'], 'DECISION_INCONNUE');
    });
    test('application sous le rôle et le nom de l\'auteur, à la date de son geste ; rejouée : sans effet', () {
      final b = bon('soumis');
      final d = nouveau(b, decision: 'rejeter', motif: 'Stock suffisant').single;
      final a = circuitAppliquer(gestes: _origine, d, besoins: [b], commandes: const [], maintenant: DateTime.utc(2030))!;
      expect(a.etat, valDepotAppliquee);
      expect(a.ecriture!.patch['etape'], 'rejete');
      expect(a.ecriture!.patch['arbitrePar'], 'La DAF');
      expect(a.ecriture!.patch['arbitreLe'], valInstant(auj), reason: 'la date est celle du geste, pas celle de l\'application');
      expect(a.ecriture!.patch['motifArbitrage'], 'Stock suffisant');
      final deja = circuitAppliquer(gestes: _origine, d, besoins: [bon('rejete')], commandes: const [], maintenant: auj)!;
      expect(deja.etat, valDepotSansEffet);
      final autre = circuitAppliquer(gestes: _origine, d, besoins: [bon('accorde')], commandes: const [], maintenant: auj)!;
      expect(autre.etat, valDepotRefusee);
      expect(autre.code, 'DEJA_ARBITRE');
      expect(circuitAppliquer(gestes: _origine, {...d, 'etat': valDepotAppliquee}, besoins: [b], commandes: const [], maintenant: auj), isNull);
      expect(circuitAppliquer(gestes: _origine, {...d, 'genre': valGenreReferentiel}, besoins: [b], commandes: const [], maintenant: auj), isNull);
    });
    test('un dépôt dont le rôle a été falsifié est refusé par la mère', () {
      final b = bon('soumis');
      final d = {...nouveau(b).single, 'demandeRole': 'caissier'};
      expect(circuitAppliquer(gestes: _origine, d, besoins: [b], commandes: const [], maintenant: auj)!.code, 'VALIDATION_RESERVEE');
    });
    test('un bon accordé fait naître les deux tâches (comptable, stock), un rejeté aucune', () {
      final accorde = {...bon('accorde'), 'arbitrePar': 'La DAF', 'arbitreLe': valInstant(auj)};
      expect([for (final n in notificationsDeBesoinAccorde(accorde)) n['poste']], ['comptable', 'stock']);
      expect(notificationsDeBesoinAccorde(bon('rejete')), isEmpty);
      expect(notificationsDeBesoinAccorde(bon('soumis')), isEmpty);
    });
    test('la commande : validation par la DAF, contrôle de l\'état', () {
      final c = {'id': 'C1', 'idSync': 'F1-C1', 'reference': 'BC-2026-0001', 'statutCommande': 'attente_validation'};
      final r = circuitDeposer(
          gestes: _origine,
          famille: circuitCommandeValidation, bon: c, role: 'da', acteur: 'La DAF', poste: 'F2', maintenant: auj, besoins: const [], commandes: [c], depots: const [], nouvelId: () => 'D2');
      expect(r.ok, isTrue);
      final a = circuitAppliquer(gestes: _origine, r.fiche!, besoins: const [], commandes: [c], maintenant: auj)!;
      expect(a.ecriture!.patch['statutCommande'], 'validee');
      expect(a.ecriture!.patch['valideeParAgent'], 'La DAF');
      expect(a.ecriture!.patch['dateValidation'], '2026-11-16');
      expect(circuitAppliquer(gestes: _origine, r.fiche!, besoins: const [], commandes: [{...c, 'statutCommande': 'transmise'}], maintenant: auj)!.etat, valDepotSansEffet);
      final brouillon = circuitDeposer(
          gestes: _origine,
          famille: circuitCommandeValidation, bon: {...c, 'statutCommande': 'brouillon'}, role: 'da', acteur: 'La DAF', poste: 'F2', maintenant: auj, besoins: const [], commandes: [{...c, 'statutCommande': 'brouillon'}], depots: const [], nouvelId: () => 'D3');
      expect(brouillon.refus!.code, 'PAS_SOUMISE');
    });
  });
}
