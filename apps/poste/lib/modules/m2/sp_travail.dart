import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m1/commun_m1.dart' show imprimerM1;
import '../m1/pieces.dart' show EcranPieces;
import '../../impression/piece.dart' show BlocTexte, Signature;
import 'ag_commun.dart';
import 'ag_rendezvous.dart' show EcranCrudAg;
import 'sp_commun.dart';
import 'sp_ecrans.dart' show dateHeureFr, specVrai;

/// LA MÉDECINE DU TRAVAIL — cœur de métier de la clinique et seule spécialité aux écrans propres : les visites (embauche, périodique, reprise) et la
/// fiche d'aptitude, les entreprises clientes et leurs salariés, les conventions de visites. Les règles vivent dans `spec_travail.dart` du domaine.
///
/// L'entreprise cliente est un souscripteur de catégorie « entreprise » (M9) ; ses salariés sont les patients qui lui sont rattachés : ces écrans en
/// sont des VUES, une seconde liste divergerait de la première au premier recrutement. Les visites s'écrivent au registre des consultations (donc au
/// dossier du patient), la fiche d'aptitude est une pièce certifiante tarifée par la caisse comme les quatorze autres.

const _code = specCodeMedecineTravail;

List<Fiche> entreprisesClientes(Magasin m) => [
      for (final s in m.collection('souscripteurs').actives)
        if (s['categorie'] == 'entreprise') s
    ];

List<Fiche> visitesTravail(Magasin m) => [
      for (final x in m.collection('consultations').actives)
        if (specDeLaConsultation(x) == _code && x['statut'] == 'terminee') x
    ];

/// Les salariés d'une entreprise : les patients qui lui sont rattachés par `souscripteurId`.
List<Fiche> salariesDe(Magasin m, String entrepriseId) => [
      for (final p in m.collection('patients').actives)
        if (p['souscripteurId'] == entrepriseId) p
    ];

Fiche? conventionEnVigueur(Magasin m, String entrepriseId, String jour) => m
    .collection('conventionsVisites')
    .actives
    .where((x) => x['entrepriseId'] == entrepriseId && mdtConventionEnVigueur(x, jour))
    .firstOrNull;

TonSigh _tonAptitude(Object? a) => switch ('$a') {
      'Apte' => TonSigh.succes,
      'Apte avec aménagement de poste' => TonSigh.attention,
      'Inapte temporaire' => TonSigh.attention,
      'Inapte définitif' => TonSigh.danger,
      _ => TonSigh.neutre,
    };

String _jour(Object? v) {
  final d = agDate(v);
  return d == null ? '' : dateFR(d);
}

// =============================================================================================================================================
// LA VISITE ET LA FICHE D'APTITUDE
// =============================================================================================================================================

/// La fiche d'aptitude comme PIÈCE CERTIFIANTE : numérotée par la série annuelle du sigle FAP, facturée par `patFacturerPiece` (grille MT-FAP, seul SOS
/// couvre un certificat), inscrite au registre des pièces. Le geste est celui de la délivrance du registre des certificats : le mécanisme est UN.
/// Retourne la fiche posée sur la consultation (`ficheAptitude`) et de quoi défaire.
({Fiche fiche, VoidCallback annuler}) delivrerFicheAptitude(ContexteEcran c, Fiche consultation, {DateTime? date}) {
  final m = c.magasin;
  final jour = date ?? c.aujourdhui;
  final aptitude = '${consultation['aptitude'] ?? ''}';
  final valable = mdtValiditeFiche(jour, aptitude);
  final referenceFa = mdtReferenceFiche(m.collection('consultations').toutes, jour);
  final contenu =
      'Fiche d’aptitude $referenceFa — le salarié, examiné à la visite ${'${consultation['natureVisite'] ?? ''}'.isEmpty ? '' : '(${consultation['natureVisite']}) '}du ${_jour(consultation['date'])} pour ${consultation['entreprise'] ?? 'l’entreprise'}, '
      'est déclaré : $aptitude.${valable == null ? '' : ' Valable jusqu’au ${dateFR(DateTime.parse(valable))}.'}';
  final annulations = <VoidCallback>[];
  final pieces = m.collection('pieces');
  final fiche = EcranPieces.transformerPiece(c, {
    'typeId': mdtTypePiece.id,
    'patientCode': consultation['patientCode'],
    'medecin': consultation['medecin'],
    'dateDelivrance': iso(jour),
    'contenu': contenu,
    'remisA': 'L’employeur et le salarié',
  }, null);
  final ins = pieces.inserer(fiche, prefixe: 'PCE');
  annulations.add(ins.annuler);
  // `transformerPiece` a écrit, en plus de la pièce, sa facture et sa tâche d'encaissement : les défaire avec elle, sans quoi une délivrance annulée
  // laisserait à la caisse une pièce due pour une fiche qui n'existe plus.
  final factureId = fiche['factureId'];
  if (factureId != null) {
    annulations.add(() => m.collection('factures').archiver('$factureId'));
    for (final t in m.collection('taches').actives.where((t) => t['factureId'] == factureId)) {
      annulations.add(() => m.collection('taches').archiver('${t['id']}'));
    }
  }
  final fa = <String, Object?>{
    'reference': referenceFa,
    'conclusion': aptitude,
    'entreprise': '${consultation['entreprise'] ?? ''}',
    if (valable != null) 'valableJusqua': valable,
    'pieceId': ins.fiche['id'],
    'pieceReference': ins.fiche['reference'],
    if (ins.fiche['factureNumero'] != null) 'factureNumero': ins.fiche['factureNumero'],
  };
  annulations.add(m.collection('consultations').mettreAJour(consultation['id'], {'ficheAptitude': fa}));
  return (
    fiche: fa,
    annuler: () {
      for (final u in annulations.reversed) {
        u();
      }
    }
  );
}

/// LE geste unique d'une visite : refus nommé sans rien écrire, sinon la consultation (au dossier du patient, avec son avis d'aptitude), sa pièce de
/// caisse (l'acte MT01 / MT02 / MT03 au tarif de la grille), et — si demandé — la fiche d'aptitude.
ConsultationEnregistree enregistrerVisiteTravail(ContexteEcran c, Fiche spec, Map<String, Object?> v, {bool avecFiche = true}) {
  final m = c.magasin;
  final patient = patientParCode(m, v['patientCode']);
  if (patient == null) throw RefusSpec('Patient introuvable au répertoire : ${v['patientCode']}.');
  final nature = mdtNature(v['nature']);
  if (nature == null) throw const RefusSpec('Choisir la nature de la visite : embauche, périodique ou reprise.');
  final entreprise = entreprisesClientes(m).where((e) => e['id'] == v['entrepriseId']).firstOrNull;
  if (entreprise == null) throw const RefusSpec('Choisir l’entreprise cliente du salarié.');
  final refus = specRefusSaisie(spec['modele'], v);
  if (refus != null) throw RefusSpec(refus);
  final saisie = specSeparer(spec['modele'], v);
  final aptitude = '${saisie.reponses['aptitude'] ?? ''}';
  if (aptitude.isEmpty) throw const RefusSpec('Porter l’avis d’aptitude : c’est la conclusion de la visite.');
  final date = DateTime.tryParse('${v['date'] ?? ''}') ?? c.aujourdhui;
  final col = m.collection('consultations');
  final annulations = <VoidCallback>[];

  // La visite passe par la caisse ; un acte sans tarif est DIT, jamais facturé à zéro.
  final lg = ligneActe(c, patient, nature.acte, categorie: 'medecine_travail', date: date);
  EmissionSpec? emission;
  if (lg.ligne != null) {
    emission = emettrePiece(c, patient, [lg.ligne!], specTypeMedecineTravail, complement: {'entrepriseId': '${entreprise['id']}', 'specialite': _code});
    annulations.add(emission.annuler);
  }
  final montant = emission == null ? 0 : emission.factures.fold<num>(0, (a, f) => a + nombreOuZero(f['montantTTC']));
  final praticien = '${v['medecin'] ?? ''}';
  final praticienId = m.collection('personnel').actives.where((e) => e['nomComplet'] == praticien).map((e) => '${e['id']}').firstOrNull;
  final base = specNouvelleConsultation(
      fiche: spec,
      patient: patient,
      saisie: saisie,
      praticien: praticien,
      praticienId: praticienId,
      date: date,
      reference: agReferenceSuivante('C', 5, col.toutes),
      motif: '${v['motif'] ?? ''}'.trim().isEmpty ? '${nature.libelle} — ${entreprise['nom']}' : '${v['motif']}'.trim(),
      tarif: montant);
  final ins = col.inserer({
    ...base,
    'type': specTypeMedecineTravail,
    'natureVisite': nature.code,
    'entrepriseId': '${entreprise['id']}',
    'entreprise': '${entreprise['nom']}',
    'poste': '${saisie.reponses['poste'] ?? patient['profession'] ?? ''}',
    'aptitude': aptitude,
    if (emission != null) 'factureId': emission.factures.first['id'],
    if (emission != null) 'factureNumero': emission.factures.first['numero'],
  }, prefixe: 'CON');
  annulations.add(ins.annuler);
  if (emission != null) {
    for (final f in emission.factures) {
      m.collection('factures').mettreAJour(f['id'], {'consultationId': ins.fiche['id']});
    }
  }
  var ecrite = ins.fiche;
  if (avecFiche) {
    final fa = delivrerFicheAptitude(c, ecrite, date: date);
    annulations.add(fa.annuler);
    ecrite = col.parId(ecrite['id']) ?? ecrite;
  }
  return ConsultationEnregistree(
      ecrite,
      emission == null && lg.note != null ? EmissionSpec(const [], () {}, note: lg.note) : emission,
      () {
        for (final u in annulations.reversed) {
          u();
        }
      });
}

// =============================================================================================================================================
// m2-mdt-visites
// =============================================================================================================================================

/// Le CODE d'une nature de visite, y compris pour une fiche qui porterait le libellé accentué (« périodique ») au lieu du code.
String? _codeNature(Object? v) => mdtNature(v == 'périodique' ? 'periodique' : v)?.code;

/// `m2-mdt-visites` — « Visites de médecine du travail » : embauche, périodique, reprise, et la fiche d'aptitude. Le formulaire est celui du MODÈLE de la
/// fiche « Médecine du travail » (poste, risques, avis d'aptitude, examen par appareil) précédé de la nature, du salarié et de l'entreprise.
class EcranMdtVisites extends StatelessWidget with EcranMaquette {
  const EcranMdtVisites({super.key});

  @override
  String get titre => 'Visites de médecine du travail';

  @override
  String get description =>
      'Visites d’embauche, périodiques et de reprise ; avis d’aptitude et fiche d’aptitude, pièce certifiante tarifée par la caisse.';

  @override
  String get regle =>
      'La visite s’écrit au dossier du patient et passe par la caisse (acte de la grille : embauche, périodique ou reprise). La fiche d’aptitude est une pièce certifiante : numérotée, tarifée sur la grille MT-FAP et inscrite au registre des pièces. Une fiche s’archive avec sa visite, elle ne se supprime pas (RG-14).';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final m = c.magasin;
    return ListenableBuilder(
        listenable: Listenable.merge([m.collection('consultations'), m.collection('pieces'), m.collection('factures'), m.collection('specialites')]),
        builder: (context, _) {
          final rows = trierPar<Fiche>(visitesTravail(m), (x) => x['date'], descendant: true);
          final annee = '${c.aujourdhui.year}';
          final deLAnnee = rows.where((x) => '${x['date']}'.startsWith(annee)).toList();
          int n(String nature) => deLAnnee.where((x) => _codeNature(x['natureVisite']) == nature).length;
          final apt = rows.where((x) => x['aptitude'] == 'Apte').length;
          final sans = rows.where((x) => !specVrai(x['ficheAptitude'])).length;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            KpiGrilleSigh(kpis: [
              KpiSigh(libelle: 'Visites de l’année', valeur: nombre(deLAnnee.length), icone: LucideIcons.briefcase, ton: TonSigh.navy, indice: 'Embauche ${n('embauche')} · périodiques ${n('periodique')} · reprise ${n('reprise')}'),
              KpiSigh(libelle: 'Avis « Apte »', valeur: nombre(apt), icone: LucideIcons.circleCheck, ton: TonSigh.succes, indice: 'Sur ${nombre(rows.length)} visites'),
              KpiSigh(
                  libelle: 'Réserves ou inaptitudes',
                  valeur: nombre(rows.where((x) => specVrai(x['aptitude']) && x['aptitude'] != 'Apte').length),
                  icone: LucideIcons.triangleAlert,
                  ton: TonSigh.attention),
              KpiSigh(
                  libelle: 'Sans fiche d’aptitude',
                  valeur: nombre(sans),
                  icone: LucideIcons.fileSignature,
                  ton: sans > 0 ? TonSigh.attention : TonSigh.neutre,
                  indice: 'À délivrer depuis la ligne'),
            ]),
            const SizedBox(height: 16),
            TableauSigh(
              titre: 'Visites',
              lignes: rows,
              taillePage: 10,
              nomExport: 'visites-medecine-travail',
              libelleRecherche: 'Rechercher un salarié, une entreprise…',
              messageVide: 'Aucune visite de médecine du travail enregistrée.',
              triInitial: 'date',
              sensInitial: 'desc',
              filtres: [
                FiltreTableau(nom: 'nature', libelle: 'Nature', options: [for (final x in mdtNatures) OptionChamp(x.code, x.libelle)], correspond: (r, v) => _codeNature(r['natureVisite']) == v),
                FiltreTableau(nom: 'aptitude', libelle: 'Avis', options: [for (final a in mdtAptitudes) OptionChamp(a)], correspond: (r, v) => r['aptitude'] == v),
              ],
              actions: [
                if (c.droit.editer) BoutonSigh(libelle: 'Nouvelle visite', icone: LucideIcons.plus, taille: TailleBouton.sm, onPressed: () => _nouvelle(context)),
              ],
              alClicLigne: (r) => _detail(context, r),
              colonnes: [
                ColonneTableau(cle: 'date', libelle: 'Date', valeur: (r) => '${r['date'] ?? ''}', texte: (r) => dateHeureFr(r['date'])),
                ColonneTableau(cle: 'patient', libelle: 'Salarié', texte: (r) => '${r['patient']} ${r['patientCode'] ?? ''}'),
                const ColonneTableau(cle: 'entreprise', libelle: 'Entreprise'),
                ColonneTableau(cle: 'natureVisite', libelle: 'Nature', texte: (r) => mdtNature(r['natureVisite'])?.libelle ?? '${r['natureVisite'] ?? ''}'),
                const ColonneTableau(cle: 'poste', libelle: 'Poste'),
                ColonneTableau(
                    cle: 'aptitude',
                    libelle: 'Avis',
                    texte: (r) => '${r['aptitude'] ?? ''}',
                    rendu: (_, r) => specVrai(r['aptitude']) ? BadgeSigh('${r['aptitude']}', ton: _tonAptitude(r['aptitude'])) : const Text('')),
                ColonneTableau(
                    cle: 'fiche',
                    libelle: 'Fiche d’aptitude',
                    texte: (r) => (r['ficheAptitude'] as Map?)?['reference'] == null ? 'À délivrer' : '${(r['ficheAptitude'] as Map)['reference']}'),
              ],
              actionsLigne: (ctx, r) => [
                if (c.droit.editer && !specVrai(r['ficheAptitude']))
                  BoutonIcone(icone: LucideIcons.fileSignature, libelle: 'Délivrer la fiche d’aptitude', onPressed: () => _delivrer(context, r)),
                BoutonIcone(icone: LucideIcons.eye, libelle: 'Voir la visite', onPressed: () => _detail(context, r)),
              ],
            ),
          ]);
        });
  }

  void _delivrer(BuildContext ecran, Fiche r) {
    final c = ContexteEcran.of(ecran);
    if (!specVrai(r['aptitude'])) {
      ToastsSigh.afficher(ecran, 'Cette visite ne porte aucun avis d’aptitude : la fiche ne peut pas être établie.', type: TypeToast.erreur);
      return;
    }
    final fa = delivrerFicheAptitude(c, r);
    ToastsSigh.afficher(ecran, 'Fiche d’aptitude délivrée — ${fa.fiche['reference']}.',
        type: TypeToast.succes,
        detail: fa.fiche['factureNumero'] != null ? 'Pièce de caisse ${fa.fiche['factureNumero']} à encaisser.' : null,
        messageAnnulation: 'Délivrance annulée.',
        annuler: fa.annuler);
  }

  void _nouvelle(BuildContext ecran) {
    final c = ContexteEcran.of(ecran);
    final m = c.magasin;
    final spec = specialiteDeCode(m, _code);
    if (spec == null) {
      ToastsSigh.afficher(ecran, 'La fiche « Médecine du travail » est archivée : la rouvrir depuis « Spécialités » avant de saisir une visite.', type: TypeToast.erreur);
      return;
    }
    // L'entreprise est celle de la visite (champ dédié) : la question « Entreprise » du modèle sert la consultation libre, pas la visite.
    final champs = [
      const ChampDef.section('Visite'),
      ChampDef(
          nom: 'nature',
          libelle: 'Nature de la visite',
          type: TypeChamp.select,
          requis: true,
          options: [for (final x in mdtNatures) OptionChamp(x.code, x.libelle)]),
      ChampDef(
          nom: 'entrepriseId',
          libelle: 'Entreprise cliente',
          type: TypeChamp.select,
          requis: true,
          recherche: true,
          options: [const OptionChamp('', '— Choisir l’entreprise —'), for (final e in entreprisesClientes(m)) OptionChamp('${e['id']}', '${e['nom']}')]),
      for (final f in champsConsultationSpec(m, spec))
        if (f.nom != 'q_entreprise')
          f.nom == 'patientCode'
              ? ChampDef(
                  nom: f.nom,
                  libelle: 'Salarié (dossier du répertoire)',
                  type: f.type,
                  requis: true,
                  col: f.col,
                  recherche: true,
                  options: [const OptionChamp('', '— Choisir le salarié —'), ...f.options])
              : f,
      const ChampDef(nom: 'avecFiche', libelle: 'Délivrer la fiche d’aptitude (pièce tarifée par la caisse)', type: TypeChamp.case_, col: ColChamp.plein),
    ];
    final ctl = ControleurFormulaire(champs, {'date': dateHeureLocale(c.aujourdhui), 'avecFiche': true});
    afficherModale<void>(ecran,
        titre: 'Nouvelle visite de médecine du travail',
        sousTitre: 'Le formulaire est celui du modèle de la fiche « Médecine du travail ».',
        taille: TailleModale.lg,
        corps: FormulaireSigh(controleur: ctl),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Enregistrer la visite',
                  icone: LucideIcons.save,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) {
                      ToastsSigh.afficher(ecran, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                      return;
                    }
                    try {
                      final r = enregistrerVisiteTravail(c, spec, v, avecFiche: v['avecFiche'] == true);
                      fermer();
                      final f = r.emission?.factures.firstOrNull;
                      final fa = (r.consultation['ficheAptitude'] as Map?)?['reference'];
                      ToastsSigh.afficher(ecran, 'Visite enregistrée au dossier de ${r.consultation['patient']}.',
                          type: TypeToast.succes,
                          detail: [
                            if (fa != null) 'Fiche d’aptitude $fa.',
                            if (f != null) 'Pièce de caisse ${f['numero']} — ${money(f['montantTTC'])}.' else if (r.emission?.note != null) r.emission!.note!,
                          ].join(' '),
                          messageAnnulation: 'Visite annulée.',
                          annuler: r.annuler);
                    } on RefusSpec catch (e) {
                      ToastsSigh.afficher(ecran, e.message, type: TypeToast.erreur);
                    }
                  }),
            ]);
  }

  void _detail(BuildContext ecran, Fiche r) {
    final c = ContexteEcran.of(ecran);
    final spec = specialiteDeCode(c.magasin, _code);
    final lisibles = spec == null ? const <({String libelle, String valeur})>[] : specReponsesLisibles(spec['modele'], (r['reponses'] as Map?)?.cast<String, Object?>() ?? const {});
    final fa = (r['ficheAptitude'] as Map?)?.cast<String, Object?>();
    afficherTiroir<void>(ecran,
        titre: '${r['patient']}',
        sousTitre: '${r['reference'] ?? ''} — ${mdtNature(r['natureVisite'])?.libelle ?? 'Visite'}',
        largeurMax: 672,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DescListeSigh([
            ('Salarié', '${r['patient']} — ${r['patientCode']}'),
            ('Entreprise', r['entreprise']),
            ('Poste', r['poste']),
            ('Date', dateHeureFr(r['date'])),
            ('Médecin du travail', r['medecin']),
            ('Avis d’aptitude', r['aptitude']),
            ('Diagnostic', r['diagnostic']),
            if (fa != null) ('Fiche d’aptitude', '${fa['reference']}${fa['valableJusqua'] != null ? ' — valable jusqu’au ${_jour(fa['valableJusqua'])}' : ''}'),
            if (fa?['pieceReference'] != null) ('Pièce certifiante', '${fa!['pieceReference']}'),
            if (specVrai(r['factureNumero'])) ('Pièce de caisse (visite)', r['factureNumero']),
          ]),
          if (lisibles.isNotEmpty) ...[
            const SizedBox(height: 12),
            CarteSigh(
                titre: 'Réponses du formulaire',
                sansRemplissage: true,
                child: MiniTableauSigh(
                    colonnes: [ColonneMini('Question', (l) => '${l['q']}'), ColonneMini('Réponse', (l) => '${l['r']}')],
                    lignes: [for (final l in lisibles) {'q': l.libelle, 'r': l.valeur}])),
          ],
        ]),
        pied: (fermer) => [
              if (fa != null)
                BoutonSigh(
                    libelle: 'Imprimer la fiche d’aptitude',
                    icone: LucideIcons.printer,
                    variante: VarianteBouton.secondaire,
                    onPressed: () => imprimerM1(ecran,
                        titre: 'FICHE D’APTITUDE — MÉDECINE DU TRAVAIL',
                        sousTitre: 'N° ${fa['reference']}',
                        cartouche: [
                          ('Salarié', '${r['patient']}'),
                          ('Entreprise', '${r['entreprise'] ?? ''}'),
                          ('Poste', '${r['poste'] ?? ''}'),
                          ('Visite', '${mdtNature(r['natureVisite'])?.libelle ?? ''} du ${_jour(r['date'])}'),
                        ],
                        blocs: [
                          BlocTexte('Avis : ${fa['conclusion']}', gras: true),
                          if (fa['valableJusqua'] != null) BlocTexte('Valable jusqu’au ${_jour(fa['valableJusqua'])}.'),
                        ],
                        signatures: [Signature('Le Médecin du travail', nom: '${r['medecin']}', mention: 'Signature et cachet')])),
              if (c.droit.annuler)
                BoutonSigh(
                    libelle: 'Archiver',
                    icone: LucideIcons.archive,
                    variante: VarianteBouton.danger,
                    onPressed: () async {
                      fermer();
                      final motif = await confirmerAvecMotif(ecran,
                          titre: 'Archiver cette visite ?',
                          message: 'Archivage logique (RG-14) : la visite quitte le registre courant, elle ne disparaît pas. L’opération est annulable.',
                          libelleOk: 'Archiver',
                          dangereux: true);
                      if (motif == null || !ecran.mounted) return;
                      final col = c.magasin.collection('consultations');
                      col.mettreAJour(r['id'], {'_motifArchivage': motif});
                      final annuler = col.archiver(r['id']);
                      ToastsSigh.afficher(ecran, 'Visite archivée.', type: TypeToast.succes, annuler: annuler, messageAnnulation: 'Archivage annulé.');
                    }),
            ]);
  }
}

// =============================================================================================================================================
// m2-mdt-entreprises
// =============================================================================================================================================

/// `m2-mdt-entreprises` — « Entreprises clientes et salariés » : DEUX VUES — les entreprises (souscripteurs de catégorie « entreprise »), avec leur
/// convention et leurs visites de l'année, et les salariés (patients rattachés), avec leur dernière visite et l'échéance de la prochaine. Lecture seule :
/// l'entreprise se tient en M9, le salarié au répertoire des patients.
class EcranMdtEntreprises extends StatelessWidget with EcranMaquette {
  const EcranMdtEntreprises({super.key});

  @override
  String get titre => 'Entreprises clientes et salariés';

  @override
  String get description => 'Les entreprises qui confient leurs salariés à la clinique, leur convention de visites, et l’échéance de chaque salarié.';

  @override
  String get regle =>
      'Ce sont des vues, pas des registres : l’entreprise est un souscripteur (assurances & créances), le salarié un patient rattaché à cette entreprise. Un salarié jamais vu attend sa visite d’embauche ; les périodiques se comptent à douze mois (ou à la périodicité de la convention). Aucun avis d’aptitude n’est affiché ici : c’est une donnée de santé qui se lit au dossier.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final m = c.magasin;
    return ListenableBuilder(
        listenable: Listenable.merge([m.collection('souscripteurs'), m.collection('patients'), m.collection('consultations'), m.collection('conventionsVisites')]),
        builder: (context, _) {
          final jour = iso(c.aujourdhui);
          final entreprises = entreprisesClientes(m);
          final visites = visitesTravail(m);
          final lignesSal = <Fiche>[];
          for (final e in entreprises) {
            final conv = conventionEnVigueur(m, '${e['id']}', jour);
            final periodicite = (conv?['periodiciteMois'] as num?)?.toInt() ?? mdtPeriodiciteDefaut;
            for (final p in salariesDe(m, '${e['id']}')) {
              final siennes = visites.where((x) => x['patientId'] == p['id']).toList();
              final derniere = trierPar<Fiche>(siennes, (x) => x['date'], descendant: true).firstOrNull;
              final etat = mdtEtatSalarie(derniere == null ? null : agDate(derniere['date']), c.aujourdhui, periodiciteMois: periodicite);
              lignesSal.add({
                'id': p['id'],
                'patient': '${p['nom']} ${p['prenom']}',
                'patientCode': p['code'],
                'entreprise': e['nom'],
                'poste': p['profession'] ?? '',
                'derniere': derniere?['date'] ?? '',
                'etat': etat.etat.code,
                'etatLibelle': etat.etat.libelle,
                'echeance': etat.echeance ?? '',
                'visites': siennes.length,
              });
            }
          }
          final lignesEnt = [
            for (final e in entreprises)
              () {
                final conv = conventionEnVigueur(m, '${e['id']}', jour);
                final sal = lignesSal.where((x) => x['entreprise'] == e['nom']).toList();
                return <String, Object?>{
                  'id': e['id'],
                  'nom': e['nom'],
                  'assureur': e['assureurNom'] ?? e['assureur'] ?? '',
                  'effectif': e['effectif'] ?? 0,
                  'salaries': sal.length,
                  'convention': conv != null,
                  'conv': conv,
                  'visitesAnnee': visites.where((x) => x['entrepriseId'] == e['id'] && '${x['date']}'.startsWith('${c.aujourdhui.year}')).length,
                  'enRetard': sal.where((x) => x['etat'] == MdtEtat.enRetard.code).length,
                };
              }()
          ];
          final enRetard = lignesSal.where((x) => x['etat'] == MdtEtat.enRetard.code).length;
          final aPlanifier = lignesSal.where((x) => x['etat'] == MdtEtat.aPlanifier.code).length;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            KpiGrilleSigh(kpis: [
              KpiSigh(libelle: 'Entreprises clientes', valeur: nombre(entreprises.length), icone: LucideIcons.building2, ton: TonSigh.navy, indice: 'Avec convention : ${nombre(lignesEnt.where((x) => x['convention'] == true).length)}'),
              KpiSigh(libelle: 'Salariés connus', valeur: nombre(lignesSal.length), icone: LucideIcons.users, ton: TonSigh.info),
              KpiSigh(libelle: 'Visites à planifier', valeur: nombre(aPlanifier), icone: LucideIcons.calendarClock, ton: aPlanifier > 0 ? TonSigh.attention : TonSigh.neutre, indice: 'Échéance sous 30 jours'),
              KpiSigh(libelle: 'Visites en retard', valeur: nombre(enRetard), icone: LucideIcons.triangleAlert, ton: enRetard > 0 ? TonSigh.danger : TonSigh.neutre),
            ]),
            const SizedBox(height: 16),
            OngletsSigh(onglets: [
              OngletDef(id: 'entreprises', libelle: 'Entreprises (${lignesEnt.length})', construire: (_) => _tableEntreprises(context, c, lignesEnt)),
              OngletDef(id: 'salaries', libelle: 'Salariés (${lignesSal.length})', construire: (_) => _tableSalaries(context, c, lignesSal)),
            ]),
          ]);
        });
  }

  Widget _tableEntreprises(BuildContext ecran, ContexteEcran c, List<Fiche> rows) => TableauSigh(
        titre: 'Entreprises clientes',
        lignes: rows,
        taillePage: 10,
        nomExport: 'entreprises-clientes',
        messageVide: 'Aucune entreprise cliente : une entreprise est un souscripteur de catégorie « entreprise » (Assurances & créances).',
        colonnes: [
          const ColonneTableau(cle: 'nom', libelle: 'Entreprise'),
          const ColonneTableau(cle: 'assureur', libelle: 'Assureur'),
          const ColonneTableau(cle: 'effectif', libelle: 'Effectif déclaré', droite: true),
          const ColonneTableau(cle: 'salaries', libelle: 'Salariés connus', droite: true),
          ColonneTableau(
              cle: 'convention',
              libelle: 'Convention',
              texte: (r) => r['convention'] == true ? 'En vigueur' : 'Aucune',
              rendu: (_, r) => r['convention'] == true ? const BadgeSigh('En vigueur', ton: TonSigh.succes) : const BadgeSigh('Aucune', ton: TonSigh.neutre)),
          const ColonneTableau(cle: 'visitesAnnee', libelle: 'Visites de l’année', droite: true),
          const ColonneTableau(cle: 'enRetard', libelle: 'En retard', droite: true),
        ],
        alClicLigne: (r) {
          final conv = (r['conv'] as Map?)?.cast<String, Object?>();
          afficherTiroir<void>(ecran,
              titre: '${r['nom']}',
              sousTitre: 'Entreprise cliente',
              corps: DescListeSigh([
                ('Assureur', r['assureur']),
                ('Effectif déclaré', '${r['effectif']}'),
                ('Salariés connus', '${r['salaries']}'),
                ('Visites de l’année', '${r['visitesAnnee']}'),
                ('Convention', conv == null ? 'Aucune convention en vigueur' : 'Depuis le ${_jour(conv['dateDebut'])} — ${conv['visitesAnnuellesPrevues'] ?? 0} visites prévues par an'),
              ]));
        },
      );

  Widget _tableSalaries(BuildContext ecran, ContexteEcran c, List<Fiche> rows) => TableauSigh(
        titre: 'Salariés des entreprises clientes',
        lignes: rows,
        taillePage: 12,
        nomExport: 'salaries-entreprises',
        libelleRecherche: 'Rechercher un salarié, une entreprise…',
        messageVide: 'Aucun salarié rattaché à une entreprise cliente.',
        filtres: [
          FiltreTableau(nom: 'etat', libelle: 'État', options: [for (final e in MdtEtat.values) OptionChamp(e.code, e.libelle)], correspond: (r, v) => r['etat'] == v),
        ],
        colonnes: [
          ColonneTableau(cle: 'patient', libelle: 'Salarié', texte: (r) => '${r['patient']} ${r['patientCode']}'),
          const ColonneTableau(cle: 'entreprise', libelle: 'Entreprise'),
          const ColonneTableau(cle: 'poste', libelle: 'Poste'),
          ColonneTableau(cle: 'derniere', libelle: 'Dernière visite', valeur: (r) => '${r['derniere']}', texte: (r) => specVrai(r['derniere']) ? _jour(r['derniere']) : '—'),
          ColonneTableau(cle: 'echeance', libelle: 'Prochaine visite', valeur: (r) => '${r['echeance']}', texte: (r) => specVrai(r['echeance']) ? _jour(r['echeance']) : 'Visite d’embauche'),
          ColonneTableau(
              cle: 'etat',
              libelle: 'État',
              texte: (r) => '${r['etatLibelle']}',
              rendu: (_, r) => BadgeSigh('${r['etatLibelle']}',
                  ton: switch ('${r['etat']}') { 'a_jour' => TonSigh.succes, 'a_planifier' => TonSigh.attention, 'en_retard' => TonSigh.danger, _ => TonSigh.neutre })),
        ],
        actionsLigne: (ctx, r) => [
          if (ContexteEcran.of(ecran).ouvre?.call('m2-mdt-visites') ?? true)
            BoutonIcone(icone: LucideIcons.arrowRight, libelle: 'Ouvrir les visites', onPressed: () => ContexteEcran.of(ecran).aller('m2-mdt-visites')),
        ],
      );
}

// =============================================================================================================================================
// m2-mdt-conventions
// =============================================================================================================================================

/// `m2-mdt-conventions` — « Conventions de visites » : l'engagement entre la clinique et l'entreprise (période, périodicité, visites prévues à l'année).
/// La seule donnée nouvelle de la médecine du travail : l'entreprise s'y désigne, elle ne s'y recopie pas.
class EcranMdtConventions extends StatelessWidget with EcranMaquette {
  const EcranMdtConventions({super.key});

  @override
  String get titre => 'Conventions de visites';

  @override
  String get description => 'Les conventions de visites médicales passées avec les entreprises clientes : période, périodicité, visites prévues.';

  @override
  String get regle =>
      'Une convention sans date de fin se reconduit. Le décompte oppose les visites prévues à l’année aux visites réalisées pour l’entreprise. Une convention s’archive (RG-14), elle ne se supprime pas ; les tarifs restent ceux de la grille de la clinique.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final m = c.magasin;
    final jour = iso(c.aujourdhui);
    Fiche? entreprise(Object? id) => entreprisesClientes(m).where((e) => e['id'] == id).firstOrNull;
    List<ChampDef> champs() => [
          ChampDef(
              nom: 'entrepriseId',
              libelle: 'Entreprise cliente',
              type: TypeChamp.select,
              requis: true,
              col: ColChamp.plein,
              recherche: true,
              options: [const OptionChamp('', '— Choisir l’entreprise —'), for (final e in entreprisesClientes(m)) OptionChamp('${e['id']}', '${e['nom']}')]),
          const ChampDef(nom: 'dateDebut', libelle: 'Début de la convention', type: TypeChamp.date, requis: true),
          const ChampDef(nom: 'dateFin', libelle: 'Fin (vide : reconduction)', type: TypeChamp.date),
          const ChampDef(nom: 'periodiciteMois', libelle: 'Périodicité des visites (mois)', type: TypeChamp.nombre, requis: true),
          const ChampDef(nom: 'visitesAnnuellesPrevues', libelle: 'Visites prévues par an', type: TypeChamp.nombre, requis: true),
          const ChampDef(nom: 'observations', libelle: 'Observations', type: TypeChamp.textarea, lignes: 2, col: ColChamp.plein),
        ];
    return EcranCrudAg(
      collection: 'conventionsVisites',
      entite: 'convention',
      entiteP: 'conventions',
      triInitial: 'dateDebut',
      sensInitial: 'desc',
      colonnes: [
        const ColonneTableau(cle: 'entreprise', libelle: 'Entreprise'),
        ColonneTableau(cle: 'dateDebut', libelle: 'Début', texte: (r) => _jour(r['dateDebut'])),
        ColonneTableau(cle: 'dateFin', libelle: 'Fin', texte: (r) => specVrai(r['dateFin']) ? _jour(r['dateFin']) : 'Reconduction'),
        ColonneTableau(cle: 'periodiciteMois', libelle: 'Périodicité', droite: true, texte: (r) => '${r['periodiciteMois'] ?? mdtPeriodiciteDefaut} mois'),
        ColonneTableau(cle: 'visitesAnnuellesPrevues', libelle: 'Prévues / an', droite: true),
        ColonneTableau(
            cle: 'realisees',
            libelle: 'Réalisées (année)',
            droite: true,
            valeur: (r) => mdtDecompteConvention(r, visitesTravail(m), c.aujourdhui.year).realisees,
            texte: (r) => '${mdtDecompteConvention(r, visitesTravail(m), c.aujourdhui.year).realisees}'),
        ColonneTableau(
            cle: 'etat',
            libelle: 'État',
            texte: (r) => mdtConventionEnVigueur(r, jour) ? 'En vigueur' : 'Échue ou à venir',
            rendu: (_, r) => mdtConventionEnVigueur(r, jour) ? const BadgeSigh('En vigueur', ton: TonSigh.succes) : const BadgeSigh('Échue ou à venir', ton: TonSigh.attention)),
      ],
      kpis: (ctx, rows) {
        final enVigueur = rows.where((r) => mdtConventionEnVigueur(r, jour)).toList();
        final prevues = enVigueur.fold<int>(0, (a, r) => a + ((r['visitesAnnuellesPrevues'] as num?)?.toInt() ?? 0));
        final realisees = enVigueur.fold<int>(0, (a, r) => a + mdtDecompteConvention(r, visitesTravail(m), c.aujourdhui.year).realisees);
        final sans = entreprisesClientes(m).where((e) => conventionEnVigueur(m, '${e['id']}', jour) == null).length;
        return [
          KpiSigh(libelle: 'Conventions en vigueur', valeur: nombre(enVigueur.length), icone: LucideIcons.fileCheck2, ton: TonSigh.succes),
          KpiSigh(libelle: 'Visites prévues par an', valeur: nombre(prevues), icone: LucideIcons.calendarRange, ton: TonSigh.navy),
          KpiSigh(libelle: 'Réalisées cette année', valeur: nombre(realisees), icone: LucideIcons.stethoscope, ton: TonSigh.info),
          KpiSigh(libelle: 'Entreprises sans convention', valeur: nombre(sans), icone: LucideIcons.building2, ton: sans > 0 ? TonSigh.attention : TonSigh.neutre),
        ];
      },
      ouvrirFormulaire: (ecran, rec) => ouvrirFormulaireAg(ecran,
          collection: 'conventionsVisites',
          entite: 'convention de visites',
          champs: champs,
          initial: {'dateDebut': iso(c.aujourdhui), 'periodiciteMois': '$mdtPeriodiciteDefaut', 'visitesAnnuellesPrevues': '0'},
          record: rec,
          prefixe: 'CNV',
          avant: (v) {
            if (entreprise(v['entrepriseId']) == null) return 'Choisir l’entreprise cliente.';
            final fin = '${v['dateFin'] ?? ''}', debut = '${v['dateDebut'] ?? ''}';
            if (fin.isNotEmpty && fin.compareTo(debut) < 0) return 'La fin de la convention précède son début.';
            return null;
          },
          transformer: (v, r) => {
                ...v,
                'entreprise': '${entreprise(v['entrepriseId'])?['nom']}',
                'statut': r?['statut'] ?? 'actif',
              }),
      detail: (ecran, r) {
        final d = mdtDecompteConvention(r, visitesTravail(m), c.aujourdhui.year);
        return DescListeSigh([
          ('Entreprise', r['entreprise']),
          ('Période', '${_jour(r['dateDebut'])} → ${specVrai(r['dateFin']) ? _jour(r['dateFin']) : 'reconduction'}'),
          ('Périodicité', '${r['periodiciteMois'] ?? mdtPeriodiciteDefaut} mois'),
          ('Visites prévues par an', '${d.prevues}'),
          ('Réalisées cette année', '${d.realisees}'),
          ('Reste à réaliser', '${d.reste}'),
          ('Observations', r['observations']),
          ('Source', r['source']),
        ]);
      },
    );
  }
}
