import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_sync/sigh_sync.dart';

import 'base_portable_poste.dart';
import 'magasin.dart';

/// « PRÉPARER LA MISE À JOUR » AU POSTE (Direction de Baguidi, 17/11/2026, décision 12). Une mise à jour ne s'installe qu'avec une SAUVEGARDE VÉRIFIÉE et un EXPORT PORTABLE vérifié, tous deux de
/// moins de N heures (N : réglage daté `maj.sauvegardeMaxHeures`, jamais une valeur écrite ici). Cette préparation les déclenche s'ils manquent, juge le résultat avec les règles du domaine
/// (`majPreparation`) et, si tout est en règle, écrit le fichier d'AUTORISATION que lit l'installeur Windows (`autorisation-mise-a-jour.txt`, valable quelques heures, une mise à jour).
/// Sinon l'autorisation est RETIRÉE et la mise à jour est BLOQUÉE avec un message nommé. Le blocage ne se lève que par le geste réservé `maj_lever_blocage` (force majeure, motif écrit,
/// auteur et date au journal).
///
/// Sur la MÈRE, la sauvegarde est celle de sa base (copie chiffrée locale relue : déchiffrée, intégrité contrôlée). Un FILEUL n'a pas de sauvegarde de la mère : son export portable, qui porte
/// sa file de saisies, EN TIENT LIEU (les deux preuves sont alors la même).
class ServiceMiseAJour {
  ServiceMiseAJour({
    required this.magasin,
    required this.dossierDonnees,
    required this.base,
    required this.role,
    required this.peut,
    required this.versionCourante,
    this.mere,
    this.maxHeures,
    this.dossierExports,
    DateTime Function()? horloge,
  }) : horloge = horloge ?? magasin.horloge;

  final Magasin magasin;
  final String dossierDonnees;
  final ServiceBasePortable base;
  final String Function() role;
  final bool Function(String geste) peut;
  final String versionCourante;
  final Mere? Function()? mere;
  final int Function()? maxHeures;
  final String? dossierExports;
  final DateTime Function() horloge;

  static final Expando<ServiceMiseAJour> _installes = Expando<ServiceMiseAJour>('ServiceMiseAJour');
  static ServiceMiseAJour? de(Magasin m) => _installes[m];
  void installer() => _installes[magasin] = this;

  PreuvesPoste get preuves => PreuvesPoste(dossierDonnees);
  File get fichierAutorisation => File('$dossierDonnees/$majFichierAutorisation');
  int get heures => maxHeures?.call() ?? majHeuresDefaut;
  String get _dossierExports => dossierExports ?? '$dossierDonnees/exports';

  PreuveMaj? get preuveExport => preuves.preuve('export');
  PreuveMaj? get preuveSauvegarde => role() == epRoleFileul ? preuveExport : preuves.preuve('sauvegarde');

  /// Le verdict d'AUJOURD'HUI sur les preuves connues (sans rien déclencher).
  VerdictMaj verdict() => majPreparation(maintenant: horloge(), maxHeures: heures, sauvegarde: preuveSauvegarde, export: preuveExport);

  /// L'autorisation écrite est-elle encore valable pour l'installeur ? (`null` : oui ; sinon le refus nommé).
  RefusSauvegarde? autorisation() => majLireAutorisation(fichierAutorisation.existsSync() ? fichierAutorisation.readAsStringSync() : null, horloge());

  void _droit(String geste) {
    if (!peut(geste)) {
      throw refusPoste('GESTE_RESERVE', 'ce geste est réservé : « ${gesteReserve(geste)?.libelle ?? geste} » est un droit de la fiche de rôle', 'Demander à un rôle qui détient ce droit.');
    }
  }

  /// La sauvegarde de la mère, relue (déchiffrée, base ouverte, intégrité contrôlée) : la preuve n'est posée que si la relecture réussit.
  Future<bool> sauvegarder() async {
    _droit(gesteBaseExporter);
    final m = mere?.call();
    if (role() == epRoleFileul) return false;
    if (m == null) throw refusPoste('CONTENU_INCOMPLET', 'le service de la mère n’est pas en marche : aucune sauvegarde ne peut être faite ni relue', 'Démarrer le service de la mère.');
    await m.sauvegarderChiffre(prefixe: 'avant-maj');
    final r = await m.verifierDerniereSauvegarde();
    final ok = r['ok'] == true;
    preuves.poser('sauvegarde', horloge(), verifiee: ok, detail: '${r['fichier'] ?? r['code'] ?? ''}');
    magasin.journaliser('Sauvegarde avant mise à jour', 'CFG', 'Base', 'avant-maj', null, {'verifiee': ok, if (!ok) 'code': r['code'], 'operations': r['operations']});
    return ok;
  }

  /// PRÉPARE : sauvegarde et export manquants ou trop anciens sont refaits, puis le verdict décide de l'autorisation. Rend le verdict.
  Future<VerdictMaj> preparer() async {
    _droit(gesteBaseExporter);
    final avant = verdict();
    final codes = avant.refus.map((r) => r.code).toSet();
    try {
      if (role() != epRoleFileul && codes.any((c) => c.startsWith('SAUVEGARDE_'))) await sauvegarder();
      if (codes.any((c) => c.startsWith('EXPORT_')) || (role() == epRoleFileul && codes.any((c) => c.startsWith('SAUVEGARDE_')))) {
        await base.exporter(dossierDestination: _dossierExports, prefixe: 'sigh-avant-maj');
      }
    } catch (_) {
      // Une préparation qui échoue ne laisse JAMAIS une autorisation d'avant : le blocage reste, la cause remonte nommée.
      retirerAutorisation();
      rethrow;
    }
    final v = verdict();
    if (v.autorisee) {
      _ecrireAutorisation(levee: false);
      magasin.journaliser('Mise à jour préparée', 'CFG', 'Base', 'maj', null, {'maxHeures': v.maxHeures, 'version': versionCourante, 'schema': schemaDonneesCourant});
    } else {
      retirerAutorisation();
      magasin.journaliser('Mise à jour bloquée', 'CFG', 'Base', 'maj', null, {'codes': [for (final r in v.refus) r.code]}, succes: false);
    }
    return v;
  }

  void _ecrireAutorisation({required bool levee}) {
    fichierAutorisation
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(majTexteAutorisation(
          maintenant: horloge(),
          validiteHeures: majValiditeAutorisationHeures,
          versionCourante: versionCourante,
          schema: schemaDonneesCourant,
          levee: levee,
          sauvegarde: preuveSauvegarde?.date.toLocal(),
          export: preuveExport?.date.toLocal()));
  }

  void retirerAutorisation() {
    if (fichierAutorisation.existsSync()) fichierAutorisation.deleteSync();
  }

  /// LÈVE le blocage (force majeure) : geste réservé `maj_lever_blocage`, motif obligatoire ; l'autorisation est écrite avec `levee=oui` et le journal garde l'auteur, la date et le motif.
  void lever({required String motif}) {
    final refus = majControlerLevee(aLeDroit: peut(gesteMajLeverBlocage), motif: motif);
    if (refus != null) throw ErreurExport(refus);
    _ecrireAutorisation(levee: true);
    magasin.journaliser('Blocage de mise à jour levé (force majeure)', 'CFG', 'Base', 'maj', null, {'motif': motif.trim(), 'verdict': [for (final r in verdict().refus) r.code]});
  }
}
