// UN RÉGLAGE DE CLINIQUE POSÉ SOUS UN GESTE RÉSERVÉ, DEPUIS N'IMPORTE QUEL POSTE (Direction de Baguidi, 16/11/2026, §7) : « encaisser le reste d'une facture qui a une ligne
// sans prix ». Non par défaut ; le geste `reglage_encaissement_sans_prix` (administrateur et DAF d'origine, jamais un rôle en dur) le pose ; un fileul DÉPOSE, la mère APPLIQUE
// sous le rôle de l'auteur avec SA matrice ; rejouable sans seconde version.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef F = Map<String, Object?>;

void main() {
  final maintenant = DateTime.utc(2026, 11, 16, 10);
  int serie = 0;
  String nouvelId() => 'VDP-T-${++serie}';
  F fiche(String role, Map<String, bool> gestes) => {'role': role, 'statut': 'actif', 'droitsGestes': gestes};

  test('le réglage : déclaré au registre, Non par défaut, famille « caisse », branché ; seul un « true » explicite rouvre', () {
    final d = definitionDeParametre(cleEncaisserResteSansPrix)!;
    expect([d.type, d.defaut, d.famille, d.branche], [TypeParametre.booleen, false, 'caisse', true]);
    expect(encaisserResteSansPrixDe(null), isFalse);
    expect(encaisserResteSansPrixDe('oui'), isFalse);
    expect(encaisserResteSansPrixDe(true), isTrue);
    expect(gesteDuReglage(cleEncaisserResteSansPrix), gesteReglageEncaissementSansPrix);
  });

  test('le geste : origine administrateur et DAF, jamais le caissier ni le comptable ; une fiche de rôle accorde et retire', () {
    final d = DroitsGestes(fiches: const []);
    expect(d.rolesAvec(gesteReglageEncaissementSansPrix, const ['admin', 'da', 'direction', 'caissier', 'comptable', 'stock']), ['admin', 'da']);
    final decide = DroitsGestes(fiches: [fiche('direction', {gesteReglageEncaissementSansPrix: true}), fiche('da', {gesteReglageEncaissementSansPrix: false})]);
    expect(decide.rolesAvec(gesteReglageEncaissementSansPrix, const ['admin', 'da', 'direction']), ['admin', 'direction']);
    expect(DroitsGestes(fiches: const [], ecranActif: (e, m) => m != 'CFG').peut('admin', gesteReglageEncaissementSansPrix), isFalse, reason: 'activité fermée : à personne');
  });

  test('DÉPOSER (fileul) : refus nommé sans le geste ; avec, un dépôt rejouable (pas de doublon) qui porte la clé, la valeur, la date et l’auteur', () {
    final gestes = DroitsGestes(fiches: const []);
    final sans = reglageDeposer(
        cle: cleEncaisserResteSansPrix,
        valeur: true,
        dateEffet: '2026-11-16',
        role: 'caissier',
        acteur: 'Caissière',
        poste: 'F1',
        maintenant: maintenant,
        gestes: gestes,
        versions: const [],
        usages: const [],
        depots: const [],
        nouvelId: nouvelId);
    expect(sans.refus?.code, 'REGLAGE_RESERVE');
    final ok = reglageDeposer(
        cle: cleEncaisserResteSansPrix,
        valeur: true,
        dateEffet: '2026-11-16',
        role: 'da',
        acteur: 'DAF',
        poste: 'F1',
        maintenant: maintenant,
        gestes: gestes,
        versions: const [],
        usages: const [],
        depots: const [],
        nouvelId: nouvelId,
        motif: 'Rupture de prix d’achat');
    expect(ok.ok, isTrue);
    final f = ok.fiche!;
    expect([f['genre'], f['cible'], f['valeur'], f['dateEffet'], f['demandeRole'], f['demandePar'], f['etat']],
        [valGenreReglage, cleEncaisserResteSansPrix, true, '2026-11-16', 'da', 'DAF', valDepotDeposee]);
    final bis = reglageDeposer(
        cle: cleEncaisserResteSansPrix,
        valeur: true,
        dateEffet: '2026-11-16',
        role: 'da',
        acteur: 'DAF',
        poste: 'F1',
        maintenant: maintenant,
        gestes: gestes,
        versions: const [],
        usages: const [],
        depots: [f],
        nouvelId: nouvelId);
    expect(bis.dejaDepose, isTrue);
    expect(reglageDeposer(
            cle: 'mecef.mode',
            valeur: 'boitier',
            dateEffet: '2026-11-16',
            role: 'da',
            acteur: 'DAF',
            poste: 'F1',
            maintenant: maintenant,
            gestes: gestes,
            versions: const [],
            usages: const [],
            depots: const [],
            nouvelId: nouvelId)
        .refus
        ?.code, 'REGLAGE_INCONNU', reason: 'seuls les réglages sous geste se déposent');
    expect(reglageDeposer(
            cle: cleEncaisserResteSansPrix,
            valeur: false,
            dateEffet: '2026-11-16',
            role: 'da',
            acteur: 'DAF',
            poste: 'F1',
            maintenant: maintenant,
            gestes: gestes,
            versions: const [],
            usages: const [],
            depots: const [],
            nouvelId: nouvelId)
        .refus
        ?.code, 'DEJA_REGLE', reason: 'Non est déjà le défaut');
  });

  test('APPLIQUER (mère) : sous le rôle de l’auteur, avec la matrice de la MÈRE ; une version datée ; rejoué, sans effet ; geste retiré entre-temps, refusé nommé', () {
    final depot = reglageDeposer(
            cle: cleEncaisserResteSansPrix,
            valeur: true,
            dateEffet: '2026-11-16',
            role: 'da',
            acteur: 'DAF',
            poste: 'F1',
            maintenant: maintenant,
            gestes: DroitsGestes(fiches: const []),
            versions: const [],
            usages: const [],
            depots: const [],
            nouvelId: nouvelId)
        .fiche!;
    final a = reglageAppliquer(depot, gestes: DroitsGestes(fiches: const []), versions: const [], usages: const [], maintenant: maintenant)!;
    expect(a.etat, valDepotAppliquee);
    expect([a.version!.cle, a.version!.valeur, a.version!.dateEffet, a.version!.auteur], [cleEncaisserResteSansPrix, true, '2026-11-16', 'DAF']);
    expect(a.version!.motif, contains('F1'), reason: 'la trace du poste qui a déposé');
    final rejoue = reglageAppliquer(depot, gestes: DroitsGestes(fiches: const []), versions: [a.version!], usages: const [], maintenant: maintenant)!;
    expect(rejoue.etat, valDepotSansEffet);
    final retire = reglageAppliquer(depot,
        gestes: DroitsGestes(fiches: [fiche('da', {gesteReglageEncaissementSansPrix: false})]), versions: const [], usages: const [], maintenant: maintenant)!;
    expect([retire.etat, retire.code], [valDepotRefusee, 'REGLAGE_RESERVE']);
    expect(reglageAppliquer({...depot, 'etat': valDepotAppliquee}, gestes: DroitsGestes(fiches: const []), versions: const [], usages: const [], maintenant: maintenant), isNull);
  });

  test('l’alerte d’une décision de réglage en retard va aux détenteurs du geste (matrice), puis à l’administrateur', () {
    final d = DecisionEnAttente(
        genre: genreDecisionValidation,
        id: 'VDP-1',
        libelle: 'Réglage',
        par: 'DAF',
        role: 'da',
        depuis: maintenant,
        famille: cleEncaisserResteSansPrix,
        sousGenre: valGenreReglage);
    expect(destinatairesAlerteDecision(d, gesteCircuit: gesteValiderAchats, gestePrix: gesteDeciderPrix), ['geste:$gesteReglageEncaissementSansPrix', posteAdministrateur]);
  });
}
