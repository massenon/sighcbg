import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/parametres_poste.dart';
import 'package:sigh_poste/core/service_installation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/acteur.dart';
import 'package:sigh_poste/kit/validation_poste.dart';
import 'package:sigh_poste/mere/client_mere.dart';
import 'package:sigh_poste/modules/m14/commun_m14.dart' show rolesDe;
import 'package:sigh_poste/shell/contexte_ecran.dart';
import 'package:sigh_poste/sync/configuration_sync.dart';
import 'package:sigh_poste/sync/moteur_fileul.dart';
import 'package:sigh_poste/sync/pont_activite.dart';
import 'package:sigh_poste/sync/service_validations_deposees.dart';
import 'package:sigh_sync/sigh_sync.dart';

/// LA CONTINUITÉ DES VALIDATIONS, CONTRE LA VRAIE MÈRE DART (Direction, 15/11/2026) : « une validation à faire ne doit JAMAIS empêcher le fileul de travailler ; le poste de la mère
/// n'est pas fait pour valider ». Un VALIDATEUR d'un FILEUL rattaché (la Direction n'est jamais la mère) valide un référentiel : son geste se DÉPOSE, la mère l'APPLIQUE sous son rôle en
/// refaisant tous les contrôles, le verdict revient. Aucun humain devant la mère ; mère coupée, l'état dit « en attente de la mère » (jamais « validé ») et le poste travaille.
typedef M = Map<String, Object?>;
final auj = DateTime(2026, 11, 15, 10);

Magasin jeu() => Magasin.depuisDossier(Magasin.collectionsDuJeu, 'assets/donnees/jeu')..horloge = () => auj;

ContexteEcran contexte(Magasin m, String role, String nom) => ContexteEcran(
    ecranId: 'adm-validations', role: role, droit: const Droit(voir: true, editer: true, annuler: false), magasin: m, aller: (_) {}, utilisateur: nom, horloge: () => auj, child: const SizedBox());

void main() {
  test('BOUT EN BOUT : la Direction (fileul) valide, la mère applique sous son rôle ; idempotent ; mère coupée = « en attente » ; refus nommé qui revient ; le fileul travaille toujours', () async {
    const port = 19577;
    final mere0 = await Mere.creer(ConfigMere(port: port, dbChemin: ':memory:', admin: 'secret-test', dossierSauvegardes: '/tmp/sigh-test-sauvegardes-validations'));
    await mere0.demarrer();
    final console = ClientMere(base: Uri.parse('http://127.0.0.1:$port'), secretAdmin: 'secret-test');
    final moteur = MoteurFileul.creer(dbChemin: ':memory:', mere: 'http://127.0.0.1:1', nom: 'Direction');
    final mm = jeu();
    // Le fileul démarre SANS référentiel : il le reçoit de la mère (famille R), comme en production.
    final mf = Magasin({'actes': <M>[], 'notifications': <M>[], 'validationsReferentiels': <M>[], 'objectifsPilotage': <M>[]})..horloge = () => auj;
    await ServiceInstallation.de(mf).attacher(StockageMemoire(), const ParametresPoste(uuidPoste: 'u', rejoint: true));
    expect(ServiceInstallation.de(mf).rattache, isTrue);
    final pub = PublicateurConfiguration(mm, publierVersMereLocale(port: port, admin: 'secret-test'), delai: Duration.zero);
    final appl = ApplicateurConfiguration(mf, moteur.liste);
    final pontM = PontActivite(mm, TransportMereLocale(port: port, admin: 'secret-test'), etiquette: 'M');
    final pontF = PontActivite(mf, TransportFileul(lire: moteur.liste, ecrireFiche: (c, f, {required existe, required champs}) => moteur.ecrire(c, f, existe: existe, champs: champs)), etiquette: 'F');
    // LA MÈRE : l'application des dépôts est celle de la production (`main.dart` la démarre) ; le test la démarre comme le poste mère.
    final mereSvc = ServiceValidationsDeposees.de(mm)
      ..etiquette = 'M'
      ..horloge = () => auj;
    final filSvc = ServiceValidationsDeposees.de(mf)
      ..etiquette = 'F'
      ..horloge = () => auj;
    var mereJoignable = true;
    Future<void> tour() async {
      await pub.pousser();
      await appl.tirer();
      if (mereJoignable) {
        await pontF.cycle();
        await pontM.cycle();
      }
    }

    Future<void> converger(bool Function() fini, String quoi) async {
      final fin = DateTime.now().add(const Duration(seconds: 120));
      while (!fini()) {
        await tour();
        if (DateTime.now().isAfter(fin)) fail('$quoi : pas de convergence (pub ${pub.erreur.value}, appl ${appl.erreur.value}, pontF ${pontF.erreur.value}, pontM ${pontM.erreur.value})');
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }

    try {
      mereSvc.demarrerMere(intervalle: const Duration(milliseconds: 200));
      filSvc.demarrerFileul(intervalle: const Duration(milliseconds: 200));
      await pub.pousser();
      final code = await console.codeAppareil('Direction').timeout(const Duration(seconds: 20));
      await moteur.rattacher('http://127.0.0.1:$port', code).timeout(const Duration(seconds: 20));
      moteur.demarrer();
      await converger(() => mf.collection('actes').toutes.length >= 78 && mf.collection('objectifsPilotage').toutes.length >= 8, 'réception du référentiel par le fileul');
      final vpDir = ValidationPoste(contexte(mf, 'direction', 'La Direction'));
      final nom = acteur(contexte(mf, 'direction', 'La Direction')).nom;
      expect(vpDir.fileul, isTrue);
      expect(vpDir.peutValider('actes'), isTrue, reason: 'la Direction valide les tarifs depuis SON poste, fileul ou non');
      expect(vpDir.etat('actes', 'ACT001')!.enAttente, isTrue);
      expect(vpDir.texteBadge('actes', 'ACT001'), 'À valider');

      // 1. Le geste est DÉPOSÉ, jamais refusé « réglé sur la mère » ; rien n'est écrit chez le fileul ; le badge dit l'attente, JAMAIS « validé ».
      final r = vpDir.valider('actes', 'ACT001');
      expect(r.ok && r.depose, isTrue, reason: '${r.refus?.code} ${r.refus?.motif}');
      expect(mf.collection('actes').parId('ACT001')!['tarifProvisoire'], isTrue, reason: 'rien n\'est écrit chez le fileul : la configuration est tenue par la mère');
      expect(vpDir.texteBadge('actes', 'ACT001'), 'Transmise à la mère, en attente');
      expect(vpDir.bouton(_NeantContexte.ctx, 'actes', 'ACT001'), isNull, reason: 'le geste est déjà déposé : pas de second bouton');
      // 2. IDEMPOTENCE du dépôt : le même geste refait n'ajoute rien.
      expect(mf.collection('validationsDeposees').toutes.length, 1);
      expect(vpDir.valider('actes', 'ACT001').depotId, r.depotId);
      expect(mf.collection('validationsDeposees').toutes.length, 1);
      // 3. Un rôle hors famille est refusé AVANT tout dépôt, nommé ; un dépôt falsifié (rôle caissier) est refusé PAR LA MÈRE, qui refait les contrôles.
      expect(ValidationPoste(contexte(mf, 'caissier', 'Un caissier')).valider('actes', 'ACT002').refus!.code, 'VALIDATION_RESERVEE');
      expect(mf.collection('validationsDeposees').toutes.length, 1);

      // 4. La mère applique (sans humain) ; la validation revient au fileul avec la configuration ; le verdict aussi ; l'auteur est notifié.
      await converger(() => mf.collection('validationsDeposees').toutes.single['etat'] == 'appliquee' && mf.collection('actes').parId('ACT001')!['tarifProvisoire'] == false, 'la validation est appliquée par la mère et reprise par le fileul');
      final chezMere = mm.collection('actes').parId('ACT001')!;
      expect([chezMere['tarifProvisoire'], chezMere['validePar'], chezMere['valideLe'] == valInstant(auj)], [false, nom, true], reason: 'sous le nom de l\'auteur, à la date de son geste');
      final direct = valValiderReferentiel('actes', 'ACT003',
          role: 'direction', acteur: nom, maintenant: auj, lire: (n) => mm.collection(n).toutes, libelles: {for (final r in rolesDe(mm)) r.id: r.label});
      expect(chezMere['valideRole'], direct.valideRole, reason: 'les mêmes traces que le geste direct de la Direction sur la mère');
      expect(vpDir.texteBadge('actes', 'ACT001'), startsWith('Validé'));
      await converger(() => mf.collection('notifications').toutes.any((x) => x['type'] == 'validation_confirmee'), 'l\'auteur est notifié du verdict');
      // 5. IDEMPOTENCE de l'application : la mère rejouée n'écrit pas de seconde validation ; refaire le geste est refusé en le nommant.
      final lignes = mm.collection('audit').toutes.where((x) => '${x['action']}' == 'Validation').length;
      expect(mereSvc.traiter(), 0);
      expect(mm.collection('audit').toutes.where((x) => '${x['action']}' == 'Validation').length, lignes);
      expect(vpDir.valider('actes', 'ACT001').refus!.code, 'DEJA_VALIDE');

      // 6. Mode « fiche » (constante du code) : le barème de l'ITS se valide depuis le fileul, la mère crée la fiche VRF.
      expect(vpDir.valider('bareme_its', 'bareme-its').depose, isTrue);
      await converger(() => mf.collection('validationsReferentiels').toutes.any((x) => x['id'] == 'VRF-bareme-its' && x['valideLe'] != null), 'la fiche de validation créée par la mère arrive au fileul');

      // 7. MÈRE INJOIGNABLE : le validateur dépose, le poste continue de travailler, l'état dit « en attente de la mère » — jamais « validé ».
      mereJoignable = false;
      final hors = ValidationPoste(contexte(mf, 'da', 'La DAF')).valider('objectifs_pilotage', 'dso');
      expect(hors.depose, isTrue, reason: '${hors.refus?.code} ${hors.refus?.motif}');
      mf.collection('notifications').inserer({'type': 'travail', 'libelle': 'le fileul continue', 'statut': 'actif'}, prefixe: 'NOT');
      for (var i = 0; i < 3; i++) {
        await tour();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      expect(mm.collection('validationsDeposees').toutes.any((x) => x['cible'] == 'dso'), isFalse, reason: 'rien n\'est arrivé à la mère');
      expect(ValidationPoste(contexte(mf, 'da', 'La DAF')).texteBadge('objectifs_pilotage', 'dso'), 'Transmise à la mère, en attente');
      expect(mf.collection('objectifsPilotage').parId('dso')!['aValider'], isTrue, reason: 'jamais validé avant la confirmation');
      // La mère revient : le dépôt part, est appliqué, le verdict revient.
      mereJoignable = true;
      await converger(() => mf.collection('validationsDeposees').toutes.any((x) => x['cible'] == 'dso' && x['etat'] == 'appliquee') && mf.collection('objectifsPilotage').parId('dso')!['aValider'] == false, 'à son retour, la mère applique le dépôt');

      // 8. REFUS NOMMÉ QUI REVIENT : l'élément a disparu chez la mère (archivé) entre le geste et l'application.
      final refus = ValidationPoste(contexte(mf, 'direction', 'La Direction')).valider('actes', 'ACT002');
      expect(refus.depose, isTrue);
      mm.collection('actes').archiver('ACT002');
      await converger(() => mf.collection('validationsDeposees').toutes.any((x) => x['cible'] == 'ACT002' && x['etat'] == 'refusee'), 'le refus nommé revient au fileul');
      final v = mf.collection('validationsDeposees').toutes.firstWhere((x) => x['cible'] == 'ACT002');
      expect(v['resultatCode'], 'INTROUVABLE');
      await converger(() => mf.collection('notifications').toutes.any((x) => x['type'] == 'validation_refusee'), 'l\'auteur est notifié du refus');
    } finally {
      mereSvc.arreter();
      filSvc.arreter();
      appl.arreter();
      try {
        await mere0.arreter();
      } catch (_) {}
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}

/// Un contexte de construction qui ne sert qu'à interroger l'absence d'un bouton (il n'est jamais monté).
class _NeantContexte {
  static final BuildContext ctx = _Faux();
}

class _Faux extends Fake implements BuildContext {}
