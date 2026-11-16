import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/core/matrice_vive.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/tarifs_poste.dart';
import 'package:sigh_poste/mere/client_mere.dart';
import 'package:sigh_poste/sync/configuration_sync.dart';
import 'package:sigh_poste/sync/moteur_fileul.dart';
import 'package:sigh_poste/sync/pont_activite.dart';
import 'package:sigh_poste/sync/service_demandes_tarif.dart';
import 'package:sigh_sync/sigh_sync.dart';

import 'aide_comptes.dart';

/// LE PRIX D'ACHAT D'UN PRODUIT ENTRE LA MÈRE ET DEUX FILEULS, contre la VRAIE mère Dart et de VRAIS moteurs de fileul : un fileul (gestionnaire de stock) PROPOSE un changement de prix d'achat,
/// la mère l'applique sous le rôle de son auteur (une seule version AJOUTÉE, jamais d'écriture de la fiche), le verdict revient, un SECOND fileul reçoit la version ; la décision de la mère
/// met la version en vigueur et la fiche des deux fileuls suit ; une demande forgée (médicament avec une marge) est REFUSÉE par la mère en nommant RG-02, et le refus revient au fileul.
typedef M = Map<String, Object?>;
final auj = DateTime(2026, 11, 14, 10);
final donnees = DonneesNavigation.depuisDossier();

class Fileul {
  Fileul(this.nom, this.port, this.role) {
    moteur = MoteurFileul.creer(dbChemin: ':memory:', mere: 'http://127.0.0.1:$port', nom: nom);
    appl = ApplicateurConfiguration(m, moteur.liste);
    pont = PontActivite(m, TransportFileul(lire: moteur.liste, ecrireFiche: (c, f, {required existe, required champs}) => moteur.ecrire(c, f, existe: existe, champs: champs)),
        etiquette: nom, enLectureSeule: collectionsDeLaMereSeule);
  }
  final String nom, role;
  final int port;
  final Magasin m = Magasin({'actes': <M>[], 'notifications': <M>[]});
  late final MoteurFileul moteur;
  late final ApplicateurConfiguration appl;
  late final PontActivite pont;

  TarifsPoste poste() => TarifsPoste(m, role: role, auteur: () => 'Gestionnaire $nom', fileul: true, peutProposerPrixAchat: true, horloge: () => auj, etiquette: nom);
}

void main() {
  test('BOUT EN BOUT : un fileul propose un prix d\'achat, la mère applique (une version ajoutée), un second fileul la reçoit ; la décision fait suivre la fiche ; une demande forgée est refusée nommée', () async {
    const port = 19781;
    final mere0 = await Mere.creer(ConfigMere(port: port, dbChemin: ':memory:', admin: 'secret-test', dossierSauvegardes: '/tmp/sigh-test-sauvegardes-prix-achat'));
    await mere0.demarrer();
    final console = ClientMere(base: Uri.parse('http://127.0.0.1:$port'), secretAdmin: 'secret-test');
    final mm = Magasin.depuisDossier(Magasin.collectionsDuJeu, 'assets/donnees/jeu');
    final nbProduits = TarifsPoste.assurerProduits(mm);
    expect(nbProduits, 150, reason: 'la mère reprend chaque produit en version 1');
    final pub = PublicateurConfiguration(mm, publierVersMereLocale(port: port, admin: 'secret-test'), delai: Duration.zero, collections: {...collectionsConfiguration()});
    final pontM = PontActivite(mm, TransportMereLocale(port: port, admin: 'secret-test'), etiquette: 'M');
    final f1 = Fileul('F1', port, 'stock'), f2 = Fileul('F2', port, 'stock');
    // AI (16/11/2026) : les demandes portent le compte nominatif qui les signe ; la mère vérifie qu'il existe chez elle, avec ce rôle.
    final agent1 = signerAvec(f1.m, mm, 'stock', nom: 'Gestionnaire F1');
    signerAvec(f2.m, mm, 'stock', nom: 'Gestionnaire F2');
    final applicateur = ApplicateurDemandesTarif.de(mm)
      ..etiquette = 'M'
      ..matrice = MatriceVive(donnees, mm)
      ..horloge = () => auj;
    Future<void> converger(bool Function() fini, String quoi) async {
      final fin = DateTime.now().add(const Duration(seconds: 120));
      while (!fini()) {
        await pub.pousser();
        for (final f in [f1, f2]) {
          await f.appl.tirer();
          await f.pont.cycle();
        }
        await pontM.cycle();
        if (DateTime.now().isAfter(fin)) fail('$quoi : pas de convergence (pub ${pub.erreur.value}, pontM ${pontM.erreur.value}, f1 ${f1.appl.erreur.value}/${f1.pont.erreur.value})');
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }

    try {
      applicateur.demarrer(intervalle: const Duration(milliseconds: 200));
      await pub.pousser();
      for (final f in [f1, f2]) {
        final code = await console.codeAppareil(f.nom).timeout(const Duration(seconds: 20));
        await f.moteur.rattacher('http://127.0.0.1:$port', code).timeout(const Duration(seconds: 20));
        f.moteur.demarrer();
      }
      await converger(
          () => [f1, f2].every((f) => f.m.collection('versionsTarif').toutes.where((v) => v['origine'] == 'reprise').length >= nbProduits && f.m.collection('produits').toutes.length >= nbProduits),
          'les deux fileuls reçoivent les produits ET leur version 1');
      // Un article sans aucune ligne de pièce : la date d'effet d'aujourd'hui n'y heurte aucun contrôle d'usage.
      final pieces = TarifsPoste.pieces(mm);
      final art = mm.collection('produits').actives.firstWhere((p) {
        final ids = {'${p['id']}'};
        return p['categorie'] == 'medicament' && tarUsages(TarifsPoste.lire(mm).parCode['${p['code']}']!, '2000-01-01', pieces, aujourdhui: tarIso(auj), produitsIds: ids).isEmpty;
      });
      final code = '${art['code']}', achat = art['prixAchat'] as num;

      // 1. Le fileul PROPOSE : rien n'est écrit chez lui, une demande part.
      final avantF = f1.m.collection('versionsTarif').toutes.length;
      final d = f1.poste().proposerPrixAchat(DemandeProduit(code: code, prixAchat: achat + 40, dateEffet: tarIso(auj), motif: 'Test synchronisation du prix d’achat'));
      expect(d.ok && d.depose, isTrue, reason: '${d.refus?.code} ${d.refus?.motif}');
      expect(f1.m.collection('versionsTarif').toutes.length, avantF, reason: 'un fileul n\'écrit pas une version (famille R)');
      // 2. La mère applique sous le rôle de l'auteur : UNE version AJOUTÉE ; la fiche ne change pas à la proposition.
      await converger(() => mm.collection('versionsTarif').toutes.any((v) => v['code'] == code && v['statut'] == 'propose'), 'la mère applique la proposition');
      final vs = TarifsPoste.lire(mm).versionsDe(code);
      expect(vs.length, 2, reason: 'la version 1 est conservée, une version est ajoutée');
      final v = vs.last;
      expect([v['proposePar'], v['proposeRole'], v['prixNonAssure'], v['version']], ['Gestionnaire F1', 'stock', achat + 40, 2]);
      expect(mm.collection('produits').parId(art['id'])!['prixAchat'], achat);
      // 3. Le verdict revient à F1 ; le SECOND fileul reçoit la version proposée (journal de configuration).
      await converger(() => f1.m.collection('propositionsTarif').toutes.any((x) => x['genre'] == 'propositionProduit' && x['etat'] == 'appliquee'), 'le verdict revient au fileul');
      await converger(() => f2.m.collection('versionsTarif').parId(v['id']) != null, 'le second fileul reçoit la version');
      expect(f2.m.collection('versionsTarif').parId(v['id'])!['statut'], 'propose');
      expect(f2.m.collection('produits').toutes.firstWhere((p) => p['code'] == code)['prixAchat'], achat, reason: 'aucun prix ne bouge avant le Oui, chez personne');
      // Une seconde proposition pour le même article est refusée NOMMÉE, localement, une fois la première reçue.
      final deux = f2.poste().proposerPrixAchat(DemandeProduit(code: code, prixAchat: achat + 90, dateEffet: tarIso(auj), motif: 'Seconde'));
      expect(deux.refus?.code, 'CHANGEMENT_EN_ATTENTE');

      // 4. La décision de la mère met la version en vigueur ; la fiche et le prix de vente (RG-02) suivent chez les DEUX fileuls.
      final daf = TarifsPoste(mm, role: 'da', auteur: () => 'La DAF', horloge: () => auj, etiquette: 'M');
      expect(daf.decider('${v['id']}', 'oui').ok, isTrue);
      expect(mm.collection('produits').parId(art['id'])!['prixAchat'], achat + 40);
      await converger(() => [f1, f2].every((f) => f.m.collection('produits').toutes.firstWhere((p) => p['code'] == code)['prixAchat'] == achat + 40), 'la fiche suit chez les deux fileuls');
      for (final f in [f1, f2]) {
        final p = f.m.collection('produits').toutes.firstWhere((p) => p['code'] == code);
        expect([p['prixAchat'], p['prixVente']], [achat + 40, achat + 40], reason: '${f.nom} : le prix de vente d\'un médicament suit sans marge');
        expect(TarifsPoste.prixProduit(f.m, p, aujourdhui: auj, date: '2020-01-01').achat, achat, reason: 'une pièce ancienne garde son prix');
      }

      // 5. Une demande FORGÉE (un médicament avec une marge, écrit à la main dans la collection des demandes) : la mère refait les contrôles et REFUSE en nommant RG-02.
      final autre = mm.collection('produits').actives.firstWhere((p) => p['categorie'] == 'medicament' && p['code'] != code);
      final forgee = f1.m.collection('propositionsTarif').inserer({
        'id': 'DTF1FORGEE',
        'statut': 'actif',
        'genre': 'propositionProduit',
        'etat': 'deposee',
        'demandePar': 'Gestionnaire F1',
        'demandeRole': 'stock',
        // Forgée par un compte VALIDE : c'est RG-02 qui doit la refuser, pas le contrôle du compte.
        champCompteDecision: agent1.utilisateurId,
        'demandeLe': tarIso(auj),
        'code': '${autre['code']}',
        'prixAchat': (autre['prixAchat'] as num) + 10,
        'prixVente': (autre['prixAchat'] as num) + 500,
        'dateEffet': tarIso(auj),
        'motif': 'Demande forgée',
      }).fiche;
      await converger(() => f1.m.collection('propositionsTarif').parId(forgee['id'])?['etat'] == 'refusee', 'la mère refuse la demande forgée');
      final verdict = f1.m.collection('propositionsTarif').parId(forgee['id'])!;
      expect(verdict['resultatCode'], 'RG02_MARGE');
      expect('${verdict['resultatMotif']}', contains('RG-02'));
      expect(TarifsPoste.lire(mm).versionsDe('${autre['code']}').length, 1, reason: 'le refus n\'écrit rien');
    } finally {
      applicateur.arreter();
      for (final f in [f1, f2]) {
        f.appl.arreter();
      }
      pub.arreter();
      try {
        await mere0.arreter();
      } catch (_) {}
    }
  }, timeout: const Timeout(Duration(seconds: 600)));
}
