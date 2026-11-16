import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart' show ImpressionPoste;
import '../../impression/pdf.dart' show PolicesPdf;
import '../../impression/piece.dart' show PieceA4;
import '../../kit/kit.dart';
import '../../kit/validation_poste.dart';
import '../../shell/contexte_ecran.dart';
import '../m6/flux_commun.dart' show modaleSaisie;
import '../mere/mrb_source.dart' show mrbSourceCourante;
import 'qual_affiche_pdf.dart';
import 'qual_commun.dart';
import 'qual_publique.dart';
import 'qual_qr.dart';

/// L'adresse du serveur qui sert la page publique d'une enquête. Le poste ne connaît pas l'adresse de la clinique sur le réseau : en exploitation, c'est
/// celle du serveur de la clinique ou du relais qui doit être communiquée (E574). Remplaçable par la configuration du poste.
String adresseDesLiens = 'http://serveur-clinique';

/// `lienDuJeton(code)` : l'adresse de la page publique — le jeton, jamais l'identifiant de l'enquête.
String lienDuJeton(String code) => '$adresseDesLiens/enquete-publique.php?jeton=${Uri.encodeQueryComponent(code)}';

/// `adm-enquetes` — « Enquêtes & questionnaires » : le générateur de questionnaires. Le questionnaire est une DONNÉE : le formulaire de
/// saisie naît du modèle (comme sur KoboCollect), ajouter une question au modèle suffit à la faire paraître à la prochaine saisie ; les réponses déjà
/// recueillies gardent leur forme. Le modèle de satisfaction amorcé est une proposition validée par la Direction le 01/09/2026.
///
/// Le partage à un tiers : un lien suppose d'être JOIGNABLE — le serveur de la clinique n'a aucun port ouvert sur Internet ; le lien interne et son QR
/// couvrent le tiers DANS la clinique et la tablette en mode kiosque. Depuis le 16/11/2026, un lien « Sur Internet, par le relais » fait répondre le
/// patient depuis chez lui : toujours anonyme, chiffré dans son navigateur avec la clé publique de la clinique, publié et relevé par le poste mère
/// (`packages/sync_dart/lib/src/satisfaction_en_ligne.dart`), les réponses redescendant par la synchronisation (E3700 à E3710). L'adresse porte un JETON daté et révocable, jamais l'identifiant de l'enquête. Les commandes
/// d'écriture (Nouveau modèle, Recueillir, Modifier, Partager) sont ABSENTES sans le droit d'écrire ; Révoquer sans le droit d'annuler.
class EcranEnquetes extends StatelessWidget with EcranMaquette {
  const EcranEnquetes({super.key});

  @override
  String get titre => 'Enquêtes & questionnaires';

  @override
  String get description =>
      'Le générateur de questionnaires : le formulaire de saisie naît du modèle, comme sur KoboCollect.';

  @override
  String get regle =>
      'Le questionnaire est une donnée : ajouter une question au modèle suffit à la faire paraître à la prochaine saisie — rien n’est codé. Les réponses déjà recueillies gardent leur forme. Le modèle de satisfaction amorcé est une proposition : aucun document de cadrage ne fixe de questionnaire.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final m = c.magasin;
    final enquetes = colEnquetes(m), reponses = colReponses(m), jetons = colJetons(m);
    return ListenableBuilder(
        listenable: Listenable.merge([enquetes, reponses, jetons, c.magasin.collection(valCollectionValidations)]),
        builder: (context, _) {
          final rows = enquetes.actives;
          final reps = reponses.actives;
          final liens = jetons.actives;
          final jour = jourIso(c);
          final ouverts = liens.where((j) => qualJetonOuvert(j, aLaDate: jour)).length;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            KpiGrilleSigh(kpis: [
              KpiSigh(
                  libelle: 'Modèles d’enquête',
                  valeur: nombre(rows.length),
                  icone: LucideIcons.clipboardList,
                  ton: TonSigh.navy),
              KpiSigh(
                  libelle: 'Réponses recueillies',
                  valeur: nombre(reps.length),
                  icone: LucideIcons.messagesSquare,
                  ton: TonSigh.info),
              KpiSigh(
                  libelle: 'Dont par lien partagé',
                  valeur: nombre(reps.where((x) => x['canal'] == qualCanalPublic).length),
                  icone: LucideIcons.link,
                  ton: TonSigh.neutre,
                  indice: 'Canal « $qualCanalPublic »'),
              KpiSigh(
                  libelle: 'Liens ouverts',
                  valeur: nombre(ouverts),
                  icone: LucideIcons.share2,
                  ton: ouverts > 0 ? TonSigh.attention : TonSigh.neutre,
                  indice: 'Datés et révocables'),
              KpiSigh(
                  libelle: 'Modèles en attente de validation',
                  valeur: nombre(rows.where((r) => r['aValider'] == true).length),
                  icone: LucideIcons.circleHelp,
                  ton: TonSigh.attention,
                  indice: 'Propositions — aucun document ne les fixe'),
            ]),
            const SizedBox(height: 16),
            OngletsSigh(onglets: [
              OngletDef(
                  id: 'modeles',
                  libelle: 'Modèles (${rows.length})',
                  construire: (ctx) => _tableModeles(context, c, rows, reps)),
              OngletDef(
                  id: 'partage',
                  libelle: 'Liens de partage (${liens.length})',
                  construire: (ctx) => _tablePartage(context, c, liens, reps, jour)),
            ]),
          ]);
        });
  }

  // ------------------------------------------------------------------------------------------------------------------------------------------
  // Modèles
  // ------------------------------------------------------------------------------------------------------------------------------------------
  Widget _tableModeles(BuildContext ecran, ContexteEcran c, List<Fiche> rows, List<Fiche> reps) => TableauSigh(
        titre: 'Modèles',
        lignes: rows,
        taillePage: 8,
        nomExport: 'enquetes',
        messageVide: 'Aucun modèle d’enquête.',
        actions: [
          if (c.droit.editer)
            BoutonSigh(
                libelle: 'Nouveau modèle',
                icone: LucideIcons.plus,
                taille: TailleBouton.sm,
                onPressed: () => _editerModele(ecran, null)),
        ],
        colonnes: [
          ColonneTableau(
              cle: 'titre',
              libelle: 'Enquête',
              texte: (r) => '${r['titre']} ${r['description'] ?? ''}',
              rendu: (_, r) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${r['titre']}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: JetonsShell.slate800,
                            fontSize: 14,
                            height: 20 / 14,
                            fontWeight: FontWeight.w500)),
                    Text('${r['description'] ?? ''}',
                        style: const TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12)),
                  ])),
          ColonneTableau(
              cle: 'questions',
              libelle: 'Questions',
              droite: true,
              valeur: (r) => (r['questions'] as List? ?? const []).length,
              texte: (r) => '${(r['questions'] as List? ?? const []).length}'),
          ColonneTableau(
              cle: 'reponses',
              libelle: 'Réponses',
              droite: true,
              valeur: (r) => reps.where((x) => x['enqueteId'] == r['id']).length,
              texte: (r) => '${reps.where((x) => x['enqueteId'] == r['id']).length}'),
          ColonneTableau(
              cle: 'aValider',
              libelle: 'Statut',
              texte: (r) => ValidationPoste(c).texteBadge('enquetes', r['id']),
              rendu: (_, r) =>
                  ValidationPoste(c).badge('enquetes', r['id']) ??
                  (r['aValider'] == true ? const BadgeSigh('À valider', ton: TonSigh.attention) : const BadgeSigh('Validé', ton: TonSigh.succes))),
        ],
        actionsLigne: (ctx, r) => [
          if (c.droit.editer)
            BoutonSigh(
                libelle: 'Recueillir',
                icone: LucideIcons.plus,
                taille: TailleBouton.sm,
                onPressed: () => _saisirReponse(ecran, r)),
          BoutonIcone(
              icone: LucideIcons.eye,
              libelle: 'Voir les réponses',
              onPressed: () => _voirReponses(ecran, r)),
          ...ValidationPoste(c).boutons(ctx, 'enquetes', r['id']),
          if (c.droit.editer)
            BoutonIcone(
                icone: LucideIcons.share2,
                libelle: 'Partager à un tiers',
                onPressed: () => _ouvrirPartage(ecran, r)),
          if (c.droit.editer)
            BoutonIcone(
                icone: LucideIcons.pencil,
                libelle: 'Modifier le modèle',
                onPressed: () => _editerModele(ecran, r)),
        ],
      );

  /// Recueillir une réponse : le formulaire NAÎT du modèle. Un canal, puis une question = un champ.
  void _saisirReponse(BuildContext ecran, Fiche enq) {
    final c = ContexteEcran.of(ecran);
    modaleSaisie(ecran,
        titre: 'Recueillir une réponse — ${enq['titre']}',
        sousTitre: 'Le formulaire est engendré depuis le modèle : modifier le modèle suffit à le changer.',
        taille: TailleModale.lg,
        libelleOk: 'Enregistrer la réponse',
        icone: LucideIcons.check,
        champs: [
          ChampDef(
              nom: '_canal',
              libelle: 'Canal de recueil',
              type: TypeChamp.select,
              requis: true,
              options: [for (final x in qualCanaux) OptionChamp(x)]),
          ...champsDeModele(enq['questions']),
        ],
        surValider: (v) {
          final valeurs = {...v}..remove('_canal');
          final fiche = qualReponse(enq, valeurs,
              aujourdhui: c.aujourdhui, canal: '${v['_canal']}', saisiPar: acteur(c).nom);
          colReponses(c.magasin).inserer(fiche, prefixe: 'REP');
          ToastsSigh.afficher(ecran, 'Réponse recueillie.', type: TypeToast.succes);
          return true;
        });
  }

  void _voirReponses(BuildContext ecran, Fiche r) {
    final c = ContexteEcran.of(ecran);
    final reps = [
      for (final x in colReponses(c.magasin).actives)
        if (x['enqueteId'] == r['id']) x
    ];
    afficherTiroir<void>(ecran,
        titre: '${r['titre']}',
        sousTitre: '${nombre(reps.length)} réponse(s)',
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final x in reps.take(30)) ...[
            CarteSigh(
                titre: '${dateJj(x['date'])} — ${x['canal'] ?? ''}',
                sansRemplissage: true,
                child: MiniTableauSigh(colonnes: [
                  ColonneMini('Question', (l) => '${l['q']}'),
                  ColonneMini('Réponse', (l) => '${l['r']}'),
                ], lignes: [
                  for (final q in (r['questions'] as List? ?? const []).cast<Map>())
                    {
                      'q': '${q['libelle']}',
                      'r': () {
                        final v = (x['reponses'] as Map?)?[q['code']];
                        return v == null || v == '' ? '—' : '$v';
                      }()
                    }
                ])),
            const SizedBox(height: 12),
          ]
        ]));
  }

  // ------------------------------------------------------------------------------------------------------------------------------------------
  // Créer ou modifier un modèle
  // ------------------------------------------------------------------------------------------------------------------------------------------
  void _editerModele(BuildContext ecran, Fiche? r) {
    final c = ContexteEcran.of(ecran);
    final creation = r == null;
    final ctl = ControleurFormulaire(const [
      ChampDef(nom: 'titre', libelle: 'Titre de l’enquête', requis: true, col: ColChamp.plein),
      ChampDef(nom: 'description', libelle: 'Description', col: ColChamp.plein),
    ], {
      'titre': r?['titre'],
      'description': r?['description']
    });
    final questions = <Fiche>[
      for (final q in (r?['questions'] as List? ?? const []).cast<Map>()) {...q.cast<String, Object?>()}
    ];
    afficherModale<void>(ecran,
        titre: creation ? 'Nouveau modèle d’enquête' : 'Modifier — ${r['titre']}',
        taille: TailleModale.lg,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FormulaireSigh(controleur: ctl),
          const SizedBox(height: 12),
          CarteSigh(titre: 'Questions', child: _EditeurQuestions(ecran, questions)),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              // Lot L1 : le choix « Valider » du pied de modale (la Direction, modèle en attente seulement ; ABSENT sinon).
              if (!creation)
                if (ValidationPoste(c).boutonModale(ecran, const ValidationCrud('enquetes'), r!, fermer) case final b?) b,
              BoutonSigh(
                  libelle: creation ? 'Créer le modèle' : 'Enregistrer',
                  icone: LucideIcons.save,
                  onPressed: () async {
                    final v = ctl.valider();
                    if (v == null) return;
                    if (questions.isEmpty) {
                      ToastsSigh.afficher(ecran, 'Un questionnaire sans question ne recueille rien.',
                          type: TypeToast.erreur);
                      return;
                    }
                    final col = colEnquetes(c.magasin);
                    // Lot L1 : la Direction qui enregistre VALIDE ; hors famille, le modèle naît ou repasse « à valider ». UNE ligne de journal.
                    final res = await ValidationPoste(c).enregistrer(ecran, const ValidationCrud('enquetes'), col,
                        avant: r,
                        valeurs: creation
                            ? {
                                ...v,
                                'statut': 'actif',
                                'reference': _prochaineReference(col),
                                'questions': [for (final q in questions) {...q}],
                                'aValider': true,
                                'creeLe': jourIso(c),
                                'source': 'Créé dans l’application — à valider',
                              }
                            : {...v, 'questions': [for (final q in questions) {...q}]},
                        prefixeId: 'ENQ');
                    if (res == null || !ecran.mounted) return;
                    fermer();
                    ToastsSigh.afficher(ecran, creation ? 'Modèle créé.' : 'Modèle enregistré.', type: TypeToast.succes);
                  }),
            ]);
  }

  /// `ENQ-NNN` : le numéro suit le registre (le plus grand déjà attribué + 1), non un compteur de page (E573).
  String _prochaineReference(CollectionMagasin col) => numeroSuivant('qualite.enquetes', existants: col.toutes);

  // ------------------------------------------------------------------------------------------------------------------------------------------
  // Partage à un tiers
  // ------------------------------------------------------------------------------------------------------------------------------------------
  Widget _tablePartage(BuildContext ecran, ContexteEcran c, List<Fiche> liens, List<Fiche> reps, String jour) {
    final tries = trierPar(liens, (j) => j['creeLe']).reversed.toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const NoteSigh(
          'Un lien interne ne fonctionne que pour qui est dans la clinique (salle d’attente, Wi-Fi, tablette posée à la sortie) : le serveur de la clinique n’a aucun port ouvert sur Internet, et ne l’aura pas. Pour qu’un patient réponde DEPUIS CHEZ LUI, choisir « Sur Internet, par le relais » : le questionnaire est servi par le relais de la clinique, la réponse y est CHIFFRÉE dans le téléphone du patient avec la clé publique de la clinique, et seul le poste mère peut la lire.',
          ton: TonSigh.info,
          icone: LucideIcons.wifi),
      const SizedBox(height: 12),
      const NoteSigh(
          'Un lien en ligne est toujours ANONYME : ni nom, ni numéro de dossier, aucune question sur la santé. Le poste mère le publie au relais au tour suivant (avec les questions du modèle : une question ajoutée y paraît), relève les réponses, les déchiffre et les enregistre au canal « Lien public » ; elles arrivent sur chaque poste par la synchronisation et entrent dans les statistiques de satisfaction.',
          icone: LucideIcons.shieldCheck),
      const SizedBox(height: 12),
      _CarteSatisfactionEnLigne(peutRelever: c.droit.editer),
      const SizedBox(height: 12),
      TableauSigh(
        titre: 'Liens de partage',
        lignes: tries,
        taillePage: 8,
        nomExport: 'liens-enquete',
        messageVide: 'Aucun lien de partage — en ouvrir un depuis l’onglet « Modèles ».',
        colonnes: [
          const ColonneTableau(cle: 'enqueteTitre', libelle: 'Enquête'),
          ColonneTableau(
              cle: 'jeton',
              libelle: 'Jeton',
              texte: (j) => '${'${j['jeton']}'.substring(0, min(8, '${j['jeton']}'.length))}…',
              rendu: (_, j) => mono('${'${j['jeton']}'.substring(0, min(8, '${j['jeton']}'.length))}…')),
          ColonneTableau(
              cle: 'anonyme',
              libelle: 'Recueil',
              texte: (j) => j['anonyme'] == true ? 'Anonyme' : 'Nominatif',
              rendu: (_, j) => j['anonyme'] == true
                  ? const BadgeSigh('Anonyme', ton: TonSigh.info)
                  : const BadgeSigh('Nominatif', ton: TonSigh.attention)),
          ColonneTableau(
              cle: 'publication',
              libelle: 'Canal',
              texte: (j) => qualLienEnLigne(j) ? qualEtatPublication(j).libelle : 'Interne',
              rendu: (_, j) {
                if (!qualLienEnLigne(j)) return const BadgeSigh('Interne', ton: TonSigh.neutre);
                final e = qualEtatPublication(j);
                return BadgeSigh(e.libelle, ton: tonQual(e.ton));
              }),
          ColonneTableau(cle: 'expireLe', libelle: 'Expire le', texte: (j) => dateJj(j['expireLe'])),
          ColonneTableau(
              cle: 'reponses',
              libelle: 'Réponses',
              droite: true,
              valeur: (j) => reps.where((x) => x['jetonId'] == j['id']).length,
              texte: (j) => '${reps.where((x) => x['jetonId'] == j['id']).length}'),
          ColonneTableau(
              cle: 'etat',
              libelle: 'État',
              texte: (j) => qualEtatJeton(j, aLaDate: jour).libelle,
              rendu: (_, j) {
                final e = qualEtatJeton(j, aLaDate: jour);
                return BadgeSigh(e.libelle, ton: tonQual(e.ton));
              }),
        ],
        actionsLigne: (ctx, j) => [
          BoutonIcone(
              icone: LucideIcons.qrCode,
              libelle: 'Afficher le lien et le QR',
              onPressed: () => _montrerLien(ecran, j)),
          if (qualJetonOuvert(j, aLaDate: jour) && c.droit.annuler)
            BoutonIcone(icone: LucideIcons.ban, libelle: 'Révoquer le lien', onPressed: () => _revoquer(ecran, j)),
        ],
      ),
    ]);
  }

  void _ouvrirPartage(BuildContext ecran, Fiche enq) {
    final c = ContexteEcran.of(ecran);
    final ctl = ControleurFormulaire(const [
      ChampDef(
          nom: 'anonyme',
          libelle: 'Recueil',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.plein,
          options: [
            OptionChamp('oui', 'Anonyme — aucun lien vers un dossier patient'),
            OptionChamp('non', 'Nominatif — le répondant se nomme, et le formulaire le dit'),
          ],
          aide:
              'Décision explicite : si l’enquête est annoncée anonyme, on ne stocke ni identité ni lien vers le dossier — sinon « anonyme » est un mensonge.'),
      ChampDef(nom: 'usage', libelle: 'Où le tiers répond-il ?', type: TypeChamp.select, requis: true, options: [
        OptionChamp('salle', 'Dans la clinique — QR affiché ou imprimé'),
        OptionChamp('tablette', 'Sur une tablette de la clinique (mode kiosque)'),
        OptionChamp('reseau', 'Sur le réseau local — lien communiqué'),
        OptionChamp(qualUsageRelais, 'Sur Internet, par le relais — depuis chez soi (anonyme, chiffré)'),
      ]),
      ChampDef(
          nom: 'expireLe',
          libelle: 'Le lien expire le',
          type: TypeChamp.date,
          requis: true,
          aide: 'Un lien sans terme collecte des réponses des mois après la clôture.'),
      ChampDef(nom: 'note', libelle: 'Note interne', col: ColChamp.plein),
    ], {
      'anonyme': 'oui',
      'usage': 'salle',
      'expireLe': iso(c.aujourdhui.add(const Duration(days: 30)))
    });
    afficherModale<void>(ecran,
        titre: 'Partager — ${enq['titre']}',
        sousTitre: 'Le lien porte un jeton tiré au hasard, jamais l’identifiant de l’enquête.',
        taille: TailleModale.lg,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FormulaireSigh(controleur: ctl),
          const SizedBox(height: 12),
          const NoteSigh(
              'Aucune donnée médicale sur une page publique. Une enquête de satisfaction interroge l’accueil, l’attente, la propreté, la clarté des explications — jamais le diagnostic ni le motif de venue. Un formulaire qui rappellerait « votre consultation du 3 septembre en gynécologie » exposerait le patient à quiconque regarde son écran.',
              ton: TonSigh.danger,
              icone: LucideIcons.shieldAlert),
          const SizedBox(height: 12),
          const NoteSigh(
              'La page publique ne porte ni ruban, ni recherche, ni session, ni fil d’Ariane : une page d’enquête qui afficherait la coquille de l’application serait une porte.',
              icone: LucideIcons.lock),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Ouvrir le lien',
                  icone: LucideIcons.share2,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) return;
                    final enLigne = v['usage'] == qualUsageRelais;
                    // Un lien en ligne est toujours anonyme (décision du 16/11/2026) : un choix « nominatif » est refusé en le nommant, jamais corrigé en silence.
                    if (enLigne && v['anonyme'] != 'oui') {
                      ToastsSigh.afficher(ecran, 'Un lien en ligne est toujours anonyme : aucun nom ni numéro de dossier n’est demandé. Choisir « Anonyme ».',
                          type: TypeToast.erreur);
                      return;
                    }
                    final alea = Random.secure();
                    final code = qualGenererJeton(alea.nextInt);
                    final res = colJetons(c.magasin).inserer(
                        enLigne
                            ? qualNouveauJetonEnLigne(
                                enquete: enq,
                                jeton: code,
                                expireLe: '${v['expireLe']}',
                                note: '${v['note'] ?? ''}',
                                aujourdhui: c.aujourdhui,
                                ouvertPar: acteur(c).nom)
                            : qualNouveauJeton(
                                enquete: enq,
                                jeton: code,
                                anonyme: '${v['anonyme']}',
                                usage: '${v['usage']}',
                                expireLe: '${v['expireLe']}',
                                note: '${v['note'] ?? ''}',
                                aujourdhui: c.aujourdhui,
                                ouvertPar: acteur(c).nom),
                        prefixe: 'JET');
                    fermer();
                    _montrerLien(ecran, res.fiche);
                  }),
            ]);
  }

  void _montrerLien(BuildContext ecran, Fiche j) {
    if (qualLienEnLigne(j)) {
      _montrerLienEnLigne(ecran, j);
      return;
    }
    final c = ContexteEcran.of(ecran);
    final lien = lienDuJeton('${j['jeton']}');
    final e = qualEtatJeton(j, aLaDate: jourIso(c));
    final nb = colReponses(c.magasin).actives.where((x) => x['jetonId'] == j['id']).length;
    afficherTiroir<void>(ecran,
        titre: 'Lien de partage',
        sousTitre: '${j['enqueteTitre']}',
        largeurMax: 672,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Align(alignment: Alignment.centerLeft, child: BadgeSigh(e.libelle, ton: tonQual(e.ton))),
          const SizedBox(height: 12),
          const LibelleChamp('Adresse à communiquer'),
          TextField(
              key: const Key('qual:adresse'),
              controller: TextEditingController(text: lien),
              readOnly: true,
              style: const TextStyle(fontFamily: 'LiberationMono', fontSize: 12, color: JetonsShell.slate900),
              decoration: decorationChamp()),
          const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                  'En exploitation, c’est l’adresse du serveur sur le réseau de la clinique qu’il faut communiquer (http://<serveur>/…) — celle-ci est celle du poste courant.',
                  style: TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12))),
          const SizedBox(height: 12),
          CarteSigh(
              titre: 'À afficher en salle d’attente',
              child: Wrap(spacing: 16, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                QrSigh(lien),
                ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text(
                          'Le patient scanne avec son téléphone et remplit sur place. C’est là qu’on obtient des réponses : à chaud, avant de partir.',
                          style: TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14)),
                      const SizedBox(height: 8),
                      Text(
                          j['anonyme'] == true
                              ? 'Recueil ANONYME : ni identité, ni adresse réseau, ni lien vers un dossier patient.'
                              : 'Recueil NOMINATIF : le formulaire demande le nom et l’annonce clairement.',
                          style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)),
                    ])),
              ])),
          const SizedBox(height: 12),
          DescListeSigh([
            ('Enquête', '${j['enqueteTitre']}'),
            ('Ouvert le', '${dateJj(j['creeLe'])} par ${j['ouvertPar'] ?? '—'}'),
            ('Expire le', dateJj(j['expireLe'])),
            ('Réponses reçues', nombre(nb)),
            ('Note interne', j['note'] == null ? '—' : '${j['note']}'),
          ]),
        ]),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Ouvrir la page publique',
                  icone: LucideIcons.externalLink,
                  variante: VarianteBouton.secondaire,
                  onPressed: () {
                    fermer();
                    ouvrirPagePublique(ecran, c.magasin, '${j['jeton']}', horloge: () => c.aujourdhui);
                  }),
              BoutonSigh(
                  libelle: 'Copier l’adresse',
                  icone: LucideIcons.copy,
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: lien));
                    if (ecran.mounted) ToastsSigh.afficher(ecran, 'Adresse copiée.', type: TypeToast.succes);
                  }),
            ]);
  }

  /// Le lien EN LIGNE : son adresse est celle que le poste mère a publiée au relais (`lienPublic`, écrite sur la fiche et revenue par la synchronisation).
  /// Tant qu'elle n'est pas publiée, ni QR ni adresse : on ne distribue pas un lien qui ne mène encore nulle part.
  void _montrerLienEnLigne(BuildContext ecran, Fiche j0) {
    final c = ContexteEcran.of(ecran);
    final j = colJetons(c.magasin).parId(j0['id']) ?? j0;
    final lien = '${j['lienPublic'] ?? ''}';
    final pub = qualEtatPublication(j);
    final e = qualEtatJeton(j, aLaDate: jourIso(c));
    final nb = colReponses(c.magasin).actives.where((x) => x['jetonId'] == j['id']).length;
    afficherTiroir<void>(ecran,
        titre: 'Lien en ligne',
        sousTitre: '${j['enqueteTitre']}',
        largeurMax: 672,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 8, runSpacing: 8, children: [BadgeSigh(e.libelle, ton: tonQual(e.ton)), BadgeSigh(pub.libelle, ton: tonQual(pub.ton))]),
          const SizedBox(height: 12),
          if (lien.isEmpty)
            const NoteSigh(
                'Le poste mère n’a pas encore publié ce lien au relais (il le fait au tour suivant de la synchronisation). Ni adresse ni QR tant que le lien ne mène nulle part.',
                ton: TonSigh.attention,
                icone: LucideIcons.hourglass)
          else ...[
            const LibelleChamp('Adresse publiée sur le relais'),
            TextField(
                key: const Key('qual:adresse-en-ligne'),
                controller: TextEditingController(text: lien),
                readOnly: true,
                style: const TextStyle(fontFamily: 'LiberationMono', fontSize: 12, color: JetonsShell.slate900),
                decoration: decorationChamp()),
            const SizedBox(height: 12),
            CarteSigh(
                titre: 'À afficher ou à remettre au patient',
                child: Wrap(spacing: 16, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  QrSigh(lien, libelle: 'Code QR du questionnaire en ligne'),
                  ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: const Text(
                          'Le patient scanne avec son téléphone et répond quand il veut, depuis chez lui. Sa réponse est chiffrée sur son téléphone : le relais la garde sans pouvoir la lire, le poste mère seul la déchiffre.',
                          style: TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14))),
                ])),
          ],
          const SizedBox(height: 12),
          DescListeSigh([
            ('Enquête', '${j['enqueteTitre']}'),
            ('Ouvert le', '${dateJj(j['creeLe'])} par ${j['ouvertPar'] ?? '—'}'),
            ('Expire le', dateJj(j['expireLe'])),
            ('Publié le', '${j['publieLe'] ?? ''}'.isEmpty ? '—' : dateJj(j['publieLe'])),
            ('Réponses reçues', nombre(nb)),
            ('Note interne', j['note'] == null ? '—' : '${j['note']}'),
          ]),
        ]),
        pied: (fermer) => [
              if (lien.isNotEmpty)
                BoutonSigh(
                    libelle: 'Imprimer l’affiche (QR)',
                    icone: LucideIcons.printer,
                    variante: VarianteBouton.secondaire,
                    onPressed: () => _imprimerAffiche(ecran, j, lien)),
              if (lien.isNotEmpty)
                BoutonSigh(
                    libelle: 'Copier l’adresse',
                    icone: LucideIcons.copy,
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: lien));
                      if (ecran.mounted) ToastsSigh.afficher(ecran, 'Adresse copiée.', type: TypeToast.succes);
                    }),
            ]);
  }

  /// L'affiche A4 du QR : enregistrée en PDF puis envoyée à l'imprimante par défaut ; un refus de l'imprimante est nommé, le chemin du PDF reste donné.
  Future<void> _imprimerAffiche(BuildContext ecran, Fiche j, String lien) async {
    final c = ContexteEcran.of(ecran);
    final ref = PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero());
    final octets = await pdfAfficheSatisfaction(
        titre: '${j['enqueteTitre'] ?? ''}',
        lien: lien,
        expireLe: '${j['expireLe'] ?? ''}',
        reference: ref,
        utilisateur: acteur(c).nom,
        edite: c.aujourdhui,
        polices: await PolicesPdf.charger());
    final chemin = await ImpressionPoste.enregistrer(octets, ref);
    final refus = await ImpressionPoste.imprimer(chemin);
    if (!ecran.mounted) return;
    ToastsSigh.afficher(ecran, refus ?? 'Affiche envoyée à l’imprimante.',
        type: refus == null ? TypeToast.succes : TypeToast.attention, detail: chemin);
  }

  Future<void> _revoquer(BuildContext ecran, Fiche j) async {
    final c = ContexteEcran.of(ecran);
    final ok = await confirmerSigh(ecran,
        titre: 'Révoquer ce lien ?',
        message: qualLienEnLigne(j)
            ? 'Le poste mère retirera le questionnaire du relais au tour suivant : le lien cessera de s’ouvrir et ne pourra pas être republié. Les réponses déjà déposées sont relevées quand même : révoquer ferme la porte, cela n’efface rien.'
            : 'Le formulaire cessera immédiatement de s’ouvrir. Les réponses déjà recueillies sont conservées : révoquer ferme la porte, cela n’efface rien.',
        libelleOk: 'Révoquer',
        dangereux: true);
    if (!ok || !ecran.mounted) return;
    final annuler = colJetons(c.magasin).mettreAJour(j['id'], {'revoqueLe': jourIso(c), 'revoquePar': acteur(c).nom});
    ToastsSigh.afficher(ecran, 'Lien révoqué.',
        type: TypeToast.succes, annuler: annuler, messageAnnulation: 'Révocation annulée.');
  }
}

// ----------------------------------------------------------------------------------------------------------------------------------------------
// L'éditeur de questions : une liste modifiable, comme les lignes d'une dépense
// ----------------------------------------------------------------------------------------------------------------------------------------------
class _EditeurQuestions extends StatefulWidget {
  const _EditeurQuestions(this.ecran, this.questions);
  final BuildContext ecran;
  final List<Fiche> questions;

  @override
  State<_EditeurQuestions> createState() => _EtatEditeur();
}

class _EtatEditeur extends State<_EditeurQuestions> {
  String _typeLibelle(Object? t) {
    for (final x in qualTypesQuestion) {
      if (x.$1 == t) return x.$2;
    }
    return '$t';
  }

  @override
  Widget build(BuildContext context) {
    final qs = widget.questions;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (qs.isEmpty)
        const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text('Aucune question — en ajouter au moins une.',
                style: TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12))),
      for (final (i, q) in qs.indexed)
        Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8), border: Border.all(color: JetonsShell.slate200)),
            child: Row(children: [
              Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${i + 1}. ${q['libelle']}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: JetonsShell.slate800, fontSize: 14, height: 20 / 14)),
                Text(
                    '${_typeLibelle(q['type'])}${(q['options'] as List? ?? const []).isNotEmpty ? ' — ${(q['options'] as List).join(' · ')}' : ''}',
                    style: const TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12)),
              ])),
              BoutonIcone(icone: LucideIcons.pencil, libelle: 'Modifier la question', onPressed: () => _editer(q, i)),
              const SizedBox(width: 4),
              BoutonIcone(
                  icone: LucideIcons.trash2,
                  libelle: 'Retirer la question',
                  onPressed: () => setState(() => qs.removeAt(i))),
            ])),
      Align(
          alignment: Alignment.centerLeft,
          child: BoutonSigh(
              libelle: 'Ajouter une question',
              icone: LucideIcons.plus,
              taille: TailleBouton.sm,
              variante: VarianteBouton.secondaire,
              onPressed: () => _editer(null, -1))),
    ]);
  }

  void _editer(Fiche? q, int idx) {
    final qs = widget.questions;
    modaleSaisie(widget.ecran,
        titre: q != null ? 'Modifier la question' : 'Nouvelle question',
        taille: TailleModale.md,
        libelleOk: q != null ? 'Enregistrer' : 'Ajouter',
        icone: q != null ? LucideIcons.save : LucideIcons.plus,
        champs: [
          const ChampDef(nom: 'libelle', libelle: 'Question', requis: true, col: ColChamp.plein),
          ChampDef(
              nom: 'type',
              libelle: 'Type de réponse',
              type: TypeChamp.select,
              requis: true,
              options: [for (final x in qualTypesQuestion) OptionChamp(x.$1, x.$2)]),
          const ChampDef(
              nom: 'optionsTexte',
              libelle: 'Choix proposés (séparés par |)',
              col: ColChamp.plein,
              aide: 'Pour une question à choix seulement.'),
        ],
        initial: q != null
            ? {'libelle': q['libelle'], 'type': q['type'], 'optionsTexte': (q['options'] as List? ?? const []).join('|')}
            : {'type': 'note'},
        surValider: (v) {
          final optionsTexte = '${v['optionsTexte'] ?? ''}';
          if (v['type'] == 'choix' && optionsTexte.trim().isEmpty) {
            ToastsSigh.afficher(widget.ecran, 'Une question à choix a besoin de ses choix.', type: TypeToast.erreur);
            return false;
          }
          final neuf = <String, Object?>{
            'code': q != null ? q['code'] : _codeNeuf(qs),
            'libelle': v['libelle'],
            'type': v['type'],
            'options': v['type'] == 'choix'
                ? [for (final x in optionsTexte.split('|')) if (x.trim().isNotEmpty) x.trim()]
                : null,
          };
          setState(() {
            if (q != null) {
              qs[idx] = neuf;
            } else {
              qs.add(neuf);
            }
          });
          return true;
        });
  }

  /// `'Q' + Date.now().toString(36).toUpperCase()` : un code horodaté, rendu unique dans le modèle.
  String _codeNeuf(List<Fiche> qs) {
    var n = DateTime.now().millisecondsSinceEpoch;
    String code() => 'Q${n.toRadixString(36).toUpperCase()}';
    while (qs.any((q) => q['code'] == code())) {
      n++;
    }
    return code();
  }
}

/// L'état de la satisfaction en ligne, lu au service du poste MÈRE (seul à détenir la clé privée et à parler au relais). Sur un fileul, la carte le dit :
/// la publication et la relève se font là-bas, automatiquement, et les réponses arrivent ici par la synchronisation.
class _CarteSatisfactionEnLigne extends StatefulWidget {
  const _CarteSatisfactionEnLigne({required this.peutRelever});
  final bool peutRelever;

  @override
  State<_CarteSatisfactionEnLigne> createState() => _EtatCarteSatisfaction();
}

class _EtatCarteSatisfaction extends State<_CarteSatisfactionEnLigne> {
  Future<Map<String, Object?>?>? _etat;
  bool _enCours = false;

  @override
  void initState() {
    super.initState();
    _etat = mrbSourceCourante()?.etatSatisfaction();
  }

  Future<void> _relever() async {
    final s = mrbSourceCourante();
    if (s == null) return;
    setState(() => _enCours = true);
    try {
      final r = await s.synchroniserSatisfaction();
      if (!mounted) return;
      final raison = r['raison'];
      ToastsSigh.afficher(
          context,
          raison == null
              ? 'Relève faite : ${r['recues'] ?? 0} réponse(s) reçue(s), ${r['illisibles'] ?? 0} écartée(s) ; ${r['publies'] ?? 0} lien(s) publié(s).'
              : raison == 'relais_non_configure'
                  ? 'Aucun relais n’est configuré sur le poste mère : rien n’est publié ni relevé.'
                  : 'Relève impossible pour l’instant (${r['code'] ?? raison}) : le prochain essai suit la synchronisation.',
          type: raison == null ? TypeToast.succes : TypeToast.attention);
    } catch (e) {
      if (mounted) ToastsSigh.afficher(context, '$e', type: TypeToast.erreur);
    } finally {
      if (mounted) {
        setState(() {
          _enCours = false;
          _etat = mrbSourceCourante()?.etatSatisfaction();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (mrbSourceCourante() == null) {
      return const NoteSigh(
          'Ce poste n’est pas le poste mère : la publication des liens en ligne et la relève des réponses se font au poste mère, automatiquement. Les réponses relevées arrivent ici par la synchronisation.',
          icone: LucideIcons.server);
    }
    return CarteSigh(
        titre: 'Satisfaction en ligne (poste mère)',
        child: FutureBuilder<Map<String, Object?>?>(
            future: _etat,
            builder: (context, snap) {
              final e = snap.data;
              final Widget corps;
              if (snap.connectionState != ConnectionState.done) {
                corps = const Text('Lecture de l’état…', style: TextStyle(color: JetonsShell.slate500, fontSize: 13));
              } else if (snap.hasError || e == null) {
                corps = Text(snap.hasError ? '${snap.error}' : 'Le service de la mère ne propose pas la satisfaction en ligne.',
                    style: const TextStyle(color: JetonsShell.slate500, fontSize: 13));
              } else {
                final derniere = e['derniere_releve_ms'] is num ? DateTime.fromMillisecondsSinceEpoch((e['derniere_releve_ms'] as num).toInt()) : null;
                corps = DescListeSigh([
                  ('Relais', e['relais_configure'] == true ? 'Configuré' : 'Non configuré : rien n’est publié ni relevé'),
                  ('Clé publique de la clinique', 'Identifiant ${e['kid'] ?? '—'} (la clé privée ne quitte pas le poste mère)'),
                  ('Liens en ligne', nombre(e['liens_en_ligne'] is num ? e['liens_en_ligne'] as num : 0)),
                  ('Dernière relève', derniere == null ? 'Jamais' : dateHeure(derniere)),
                  ('Réponses reçues', nombre(e['recues'] is num ? e['recues'] as num : 0)),
                  ('Réponses écartées (illisibles)', nombre(e['illisibles'] is num ? e['illisibles'] as num : 0)),
                  if (e['erreur'] != null) ('Dernière erreur', '${e['erreur']}'),
                ]);
              }
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                corps,
                if (widget.peutRelever) ...[
                  const SizedBox(height: 12),
                  Align(
                      alignment: Alignment.centerLeft,
                      child: BoutonSigh(
                          libelle: _enCours ? 'Relève en cours…' : 'Publier et relever maintenant',
                          icone: LucideIcons.refreshCw,
                          taille: TailleBouton.sm,
                          onPressed: _enCours ? null : _relever)),
                ],
              ]);
            }));
  }
}
