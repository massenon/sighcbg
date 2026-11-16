import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/service_installation.dart';
import '../donnees/magasin.dart';
import '../donnees/tarifs_poste.dart';
import '../shell/contexte_ecran.dart';
import 'droits_import.dart';
import 'fichier_import.dart';
import 'port_magasin.dart';
import 'selecteurs_import.dart';
import '../sync/service_demandes_import.dart';

/// Les gestes du module d'importation, UNE fois pour tous ses habillages (la page d'un jeu du module IMP, la fenêtre en trois étapes posée sur les écrans
/// métier) : les règles ne vivent pas dans une présentation.

PortMagasin portImport(ContexteEcran c) => PortMagasin(c.magasin, aujourdhui: () => c.aujourdhui, nomAgent: c.agent.nom, profil: profilImportDe(c));

/// Les choix de l'agent pour une analyse : « ignorer les existants » (ignoré tel quel sur un jeu qui ne l'autorise pas : le moteur refuse alors en le disant)
/// et les colonnes réservées que sa matrice lui accorde.
OptionsImport optionsImport(ContexteEcran c, JeuImport j, {bool ignorerExistants = false}) =>
    OptionsImport(ignorerExistants: ignorerExistants, colonnesAccordees: DroitsImport(c).colonnesAccordees(j));

/// Analyse COMPLÈTE d'un fichier choisi, sans rien écrire (hors la consignation d'un fichier REFUSÉ, qui est une trace et non une donnée métier). La borne de
/// taille du jeu est vérifiée avant toute lecture.
({AnalyseImport analyse, Fiche? lotRefuse}) verifierFichier(ContexteEcran c, JeuImport j, FichierChoisi f, {bool ignorerExistants = false}) {
  final port = portImport(c);
  final lu = lireFichierImport(f);
  final a = analyserFichier(j, lu.lignes, f.nom, port,
      motifIllisible: lu.motif,
      empreinte: importCrc32(f.octets),
      options: optionsImport(c, j, ignorerExistants: ignorerExistants),
      octets: f.octets.length,
      octetsMax: octetsMaxDe(c.magasin, j));
  return (analyse: a, lotRefuse: a.accepte ? null : consigner(j, a, port));
}

/// L'APPLICATION d'un fichier vérifié, UNE fois pour tous les habillages. Sur un fileul rattaché, un jeu dont les cibles sont de la configuration de la mère s'écrit DIRECTEMENT ici
/// ET dépose une demande à la mère (décision de la Direction du 12/11/2026, « option c ») ; partout ailleurs, c'est l'import local ordinaire. [demande] est l'identifiant de la demande
/// déposée, ou `null` quand il n'y en a pas eu.
({ResultatImport resultat, String? demande}) appliquerImportPoste(ContexteEcran c, JeuImport j, AnalyseImport a) {
  final svc = ServiceDemandesImport.de(c.magasin);
  if (svc.reserveALaMere(j)) {
    return (
      resultat: ResultatImport.refus(
          'RESERVE_A_LA_MERE',
          (j.id == 'tarifs' || j.id == 'tarifs-produits')
              ? 'le référentiel de prix est écrit par la mère seule (famille R) : un fichier de prix ne passe pas par une demande'
              : j.reserveMere
                  ? 'le jeu « ${j.libelle} » écrit des mouvements de stock : il est réservé au poste de la mère (un seul stock, RG-03), jamais par une demande'
                  : 'le jeu « ${j.libelle} » porte des données restreintes que la mère seule écrit : il ne passe pas par une demande',
          (j.id == 'tarifs' || j.id == 'tarifs-produits')
              ? 'Importez ce fichier au poste principal, ou proposez le changement à l’écran « ${j.id == 'tarifs' ? 'Tarifs et prix' : 'Référentiel produits'} » : la demande part à la mère, qui la décide.'
              : 'Importez ce jeu au poste de la mère, par un profil qui en détient le droit.'),
      demande: null
    );
  }
  if (svc.passeParUneDemande(j)) return svc.importerEtDemander(j, a, profil: profilImportDe(c), nomAgent: c.agent.nom);
  final r = appliquer(j, a, portImport(c));
  // Une version validée à l'import prend effet à sa date : les listes de lecture (projection) sont refaites aussitôt, comme après une décision à l'écran.
  if (r.ok && (j.id == 'tarifs' || j.id == 'tarifs-produits')) TarifsPoste.projeter(c.magasin, c.aujourdhui);
  // Un article créé par un import (référentiel produits, Grand Stock) reçoit sa version 1 de prix d'achat par la MÈRE, aussitôt : la reprise ne pose jamais de date d'effet inventée.
  if (r.ok && j.cibles.contains('produits') && !ServiceInstallation.de(c.magasin).rattache) {
    TarifsPoste.assurerProduits(c.magasin);
    TarifsPoste.projeterProduits(c.magasin, c.aujourdhui);
  }
  // Une analyse créée par un import ouvre son identité de prix « sans prix, à valider » (mère seule) et prévient la DAF.
  if (r.ok && j.cibles.contains('analyses') && !ServiceInstallation.de(c.magasin).rattache) TarifsPoste.assurerAnalyses(c.magasin);
  return (resultat: r, demande: null);
}

/// Le texte de la voie que suivra l'import sur CE poste, dit AVANT l'envoi : `null` quand c'est l'import ordinaire.
String? voieImportPoste(ContexteEcran c, JeuImport j) {
  final svc = ServiceDemandesImport.de(c.magasin);
  if (svc.reserveALaMere(j)) {
    if (j.id == 'tarifs' || j.id == 'tarifs-produits') return 'Le référentiel de prix est écrit par la mère seule : ce fichier s’importe au poste principal, ou le changement se propose à l’écran « ${j.id == 'tarifs' ? 'Tarifs et prix' : 'Référentiel produits'} ».';
    return 'Ce jeu porte des données restreintes que la mère seule écrit : il s’importe au poste de la mère, jamais par une demande.';
  }
  if (svc.passeParUneDemande(j)) {
    return 'Ce référentiel est écrit par la mère. Vos fiches s’enregistrent tout de suite chez vous (marquées « en attente de la mère ») et une demande vérifiée part automatiquement à la mère, '
        'qui reste seule autorité : elle l’applique sous les mêmes identifiants que les vôtres (une fiche par code, jamais deux) ou la refuse en le disant. En cas de refus, votre écriture est '
        'restituée (archivée, RG-14, sauf ce qu’une pièce émise utilise). Si la mère est injoignable, la demande attend dans votre file : rien n’est dit « appliqué » avant sa confirmation.'
        '${j.cibles.contains('lots') ? ' Un stock chez vous d’abord : les articles, les lots et les entrées de ce fichier ne sont vus que de votre poste tant que la mère n’a pas confirmé (vous pouvez en sortir ; aucun autre poste n’y touche, rien n’est compté deux fois). Si elle refuse, chaque entrée est contre-passée par un mouvement inverse nommé ; un article dont vous avez déjà sorti du stock reste chez vous, marqué « refusée par la mère » (restitution partielle).' : ''}';
  }
  return null;
}
