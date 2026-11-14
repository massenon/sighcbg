import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/jetons_shell.dart';
import '../kit/kit.dart';
import '../shell/contexte_ecran.dart';
import 'ocr_poste.dart';

/// LES COMPOSANTS DE LA LECTURE OCR (lots OCR-prep et OCR-C) : le bloc de la carte « Pièce numérisée » — état d'indexation en toutes lettres, marquage « lu par machine, à vérifier » ou
/// « corrigé par … », commandes « Relancer la lecture » et « Corriger le texte lu » ABSENTES sans le droit (jamais grisées), historique des versions — et le réglage, décidé à la mère.
/// Toutes les règles sont celles du domaine ; ces composants ne décident rien, ils montrent et enchaînent. AUCUN moteur n'est livré : sans moteur, l'état dit
/// « aucun moteur d'OCR installé sur ce poste ».

TonSigh tonEtatOcr(EtatIndexation e) => switch (e) {
      EtatIndexation.indexe || EtatIndexation.ocrCorrige => TonSigh.succes,
      EtatIndexation.ocrIndexe => TonSigh.attention,
      EtatIndexation.ocrEnAttente || EtatIndexation.ocrEnCours => TonSigh.info,
      EtatIndexation.ocrEchec => TonSigh.danger,
      EtatIndexation.nonIndexe => TonSigh.neutre,
    };

String _dateFr(Object? iso) {
  final s = '${iso ?? ''}';
  if (s.length < 16) return 'date inconnue';
  return '${s.substring(8, 10)}/${s.substring(5, 7)}/${s.substring(0, 4)} ${s.substring(11, 16)}';
}

String _confiance(Object? c) => c is num ? '${(c * 100).round()} % en moyenne' : 'non fournie par le moteur';

/// Le bloc de la carte « Pièce numérisée » : sous les lignes du scan.
class BlocOcrPiece extends StatefulWidget {
  const BlocOcrPiece({super.key, required this.famille, required this.scan, required this.type, required this.peutEditer, required this.peutCategorie});
  final String famille;
  final Map<String, Object?> scan;
  final String? type;

  /// Le droit d'ÉDITER l'écran de la pièce : la relance et la correction n'existent que pour qui peut déposer.
  final bool peutEditer;
  final bool Function(String categorie)? peutCategorie;

  @override
  State<BlocOcrPiece> createState() => _BlocOcrPieceState();
}

class _BlocOcrPieceState extends State<BlocOcrPiece> {
  RefusFichier? _refus;

  Future<void> _corriger(OcrPoste o, FicheDoc courante) async {
    final texte = TextEditingController(text: '${courante['texteBrut'] ?? ''}');
    final motif = TextEditingController();
    final refus = ValueNotifier<RefusFichier?>(null);
    await afficherModale<void>(context,
        titre: 'Corriger le texte lu',
        taille: TailleModale.md,
        corps: ValueListenableBuilder<RefusFichier?>(
            valueListenable: refus,
            builder: (_, ref, __) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const NoteSigh(
                      'Votre correction est une NOUVELLE VERSION signée de votre nom, de la date et de l’heure : le texte lu par la machine est conservé, rien n’est réécrit. La version corrigée devient celle que la recherche lit. Le scan reste la seule référence.',
                      key: Key('ocr:correction-note'),
                      icone: LucideIcons.signature),
                  const SizedBox(height: 10),
                  const LibelleChamp('Texte corrigé'),
                  TextField(key: const Key('ocr:correction-texte'), controller: texte, maxLines: 8, style: styleSaisie, decoration: decorationChamp(indicatif: 'Texte du scan')),
                  const SizedBox(height: 8),
                  const LibelleChamp('Motif (facultatif)'),
                  TextField(key: const Key('ocr:correction-motif'), controller: motif, style: styleSaisie, decoration: decorationChamp(indicatif: 'Ex. accents rétablis, nom du patient')),
                  if (ref != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: NoteSigh('${ref.code} : ${ref.motif} ${ref.geste}', key: const Key('ocr:correction-refus'), ton: TonSigh.attention, icone: LucideIcons.triangleAlert)),
                ])),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  key: const Key('ocr:correction-enregistrer'),
                  libelle: 'Enregistrer la correction',
                  icone: LucideIcons.check,
                  onPressed: () {
                    final r = o.corriger(
                        scan: widget.scan,
                        texte: texte.text,
                        famille: widget.famille,
                        type: widget.type,
                        peutEditer: widget.peutEditer,
                        peutCategorie: widget.peutCategorie,
                        motif: motif.text,
                        corrigeDe: '${courante['id']}');
                    if (!r.ok) {
                      refus.value = r.refus;
                      return;
                    }
                    fermer();
                    ToastsSigh.afficher(context, 'Correction enregistrée.', type: TypeToast.succes, detail: 'Nouvelle version signée ; le texte lu par la machine est conservé dans l’historique.');
                  }),
            ]);
  }

  @override
  Widget build(BuildContext context) {
    final m = ContexteEcran.of(context).magasin;
    final o = OcrPoste.de(m);
    if (o == null) return const SizedBox.shrink();
    return ListenableBuilder(
        listenable: Listenable.merge([o, m.collection(ocrLectures), m.collection(ocrFile), m.collection(ocrReglages)]),
        builder: (context, _) {
          final x = widget.scan;
          // Un document du dossier patient dont le profil ne lit pas le type : rien du texte lu n'est montré (zone 2).
          if (widget.famille == docFamillePatient && (widget.peutCategorie == null || !docPeutLire(widget.peutCategorie!, widget.type))) return const SizedBox.shrink();
          final e = o.etatDe(x);
          if (e.etat == EtatIndexation.indexe) return const SizedBox.shrink();
          final sha = '${x['sha256']}';
          final courante = o.versionCourante(sha);
          final historique = o.historique(sha, famille: widget.famille, type: widget.type, peutCategorie: widget.peutCategorie);
          final file = m.collection(ocrFile).parId('OCQ-${sha.substring(0, 16)}');
          final enfants = <Widget>[
            Row(children: [
              BadgeSigh(e.court[0].toUpperCase() + e.court.substring(1), key: Key('ocr:etat-${e.code}'), ton: tonEtatOcr(e.etat)),
            ]),
            Text('${e.libelle}.', key: const Key('ocr:libelle'), style: const TextStyle(color: JetonsShell.slate600, fontSize: 12, height: 16 / 12)),
          ];
          if (courante != null && !ocrEstCorrigee(courante)) {
            enfants.add(const NoteSigh(
                'Texte lu par machine, à vérifier. La reconnaissance de caractères peut se tromper (accents, chiffres, mots coupés) : le texte sert à RETROUVER une pièce, jamais à la citer. Le scan reste la seule référence.',
                key: Key('ocr:marque'),
                ton: TonSigh.attention,
                icone: LucideIcons.scanText));
          }
          if (courante != null && ocrEstCorrigee(courante)) {
            enfants.add(NoteSigh(
                'Texte corrigé par ${courante['corrigePar']} le ${_dateFr(courante['corrigeLe'])}${'${courante['motif'] ?? ''}'.isEmpty ? '' : ' — motif : ${courante['motif']}'}. Le texte lu par la machine est conservé dans l’historique ci-dessous.',
                key: const Key('ocr:corrige'),
                icone: LucideIcons.signature));
          }
          if (e.etat == EtatIndexation.ocrEchec) {
            enfants.add(Text('${file?['geste'] ?? ''}', key: Key('ocr:echec-${file?['code']}'), style: const TextStyle(color: JetonsShell.danger700, fontSize: 12, height: 16 / 12)));
          }
          if (e.etat == EtatIndexation.nonIndexe) {
            enfants.add(const Text('La recherche par le contenu ne lit pas cette pièce ; elle reste retrouvable par ses données de fiche.',
                style: TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)));
          }
          final commandes = <Widget>[
            if (o.relancePossible(x, peutDeposer: widget.peutEditer))
              BoutonSigh(
                  key: const Key('ocr:relancer'),
                  libelle: 'Relancer la lecture',
                  icone: LucideIcons.refreshCw,
                  taille: TailleBouton.sm,
                  variante: VarianteBouton.secondaire,
                  onPressed: () async {
                    final r = o.relancer(x, peutDeposer: widget.peutEditer, famille: widget.famille, type: widget.type);
                    if (!r.ok) {
                      setState(() => _refus = r.refus);
                      return;
                    }
                    setState(() => _refus = null);
                    ToastsSigh.afficher(context, 'Lecture relancée.', type: TypeToast.succes, detail: 'Une nouvelle version sera ajoutée ; l’ancienne reste lisible.');
                    await o.vider(1);
                  }),
            if (courante != null && o.correctionPossible(x, famille: widget.famille, type: widget.type, peutEditer: widget.peutEditer, peutCategorie: widget.peutCategorie))
              BoutonSigh(
                  key: const Key('ocr:corriger'),
                  libelle: 'Corriger le texte lu',
                  icone: LucideIcons.pencil,
                  taille: TailleBouton.sm,
                  variante: VarianteBouton.secondaire,
                  onPressed: () => _corriger(o, courante)),
          ];
          if (commandes.isNotEmpty) enfants.add(Wrap(spacing: 8, runSpacing: 8, children: commandes));
          if (_refus != null) {
            enfants.add(NoteSigh('${_refus!.code} : ${_refus!.motif} ${_refus!.geste}', key: const Key('ocr:refus'), ton: TonSigh.attention, icone: LucideIcons.triangleAlert));
          }
          if (historique.isNotEmpty) {
            enfants.add(Material(
                type: MaterialType.transparency,
                child: ExpansionTile(
                    key: Key('ocr:historique-${historique.length}'),
                    tilePadding: EdgeInsets.zero,
                    title: Text('Versions du texte de ce scan (${historique.length})', style: const TextStyle(color: JetonsShell.slate700, fontSize: 14)),
                    children: [
                      for (final h in historique)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Container(
                                key: Key('ocr:version-${h['rang']}'),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: JetonsShell.slate50, borderRadius: BorderRadius.circular(6)),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(
                                      h['nature'] == 'correction'
                                          ? 'Version ${h['rang']}${h['courante'] == true ? ' (courante)' : ''} : corrigée par ${h['par']}'
                                          : 'Version ${h['rang']}${h['courante'] == true ? ' (courante)' : ''} : lue par machine (${h['moteur']})',
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                                  Text('${_dateFr(h['quand'])}${'${h['motif']}'.isEmpty ? '' : ' · motif : ${h['motif']}'}${h['nature'] == 'machine' ? ' · ${_confiance(m.collection(ocrLectures).parId(h['id'])?['confiance'])}' : ''}',
                                      style: const TextStyle(color: JetonsShell.slate500, fontSize: 12)),
                                  if (h['signatureInvalide'] == true)
                                    const Text('Signature non retrouvée : cette version n’est pas prise en compte.', key: Key('ocr:signature-invalide'), style: TextStyle(color: JetonsShell.danger700, fontSize: 12)),
                                  const SizedBox(height: 4),
                                  Text(h['nature'] == 'correction' ? 'Texte corrigé' : 'Texte lu par machine, à vérifier', style: const TextStyle(color: JetonsShell.slate600, fontSize: 12)),
                                  SelectableText('${h['texteBrut']}', key: Key('ocr:texte-${h['rang']}'), style: const TextStyle(color: JetonsShell.slate700, fontSize: 12)),
                                ])))
                    ])));
          }
          return Column(key: Key('ocr:bloc-${e.code}'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < enfants.length; i++) ...[if (i > 0) const SizedBox(height: 8), enfants[i]]
          ]);
        });
  }
}

/// La carte « Lecture des scans (OCR) » des paramètres : le réglage EN FORCE (décidé à la mère, reçu des fileuls), ce que CE poste sait faire (moteurs installés) et, sur la mère seulement
/// et avec le droit de l'écran, la commande de réglage. Un fileul LIT : la commande est absente et la carte dit où se règle.
class CarteReglageOcr extends StatelessWidget {
  const CarteReglageOcr({super.key, required this.peutRegler});

  /// Le droit de modifier l'écran des paramètres système (la matrice).
  final bool peutRegler;

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final o = OcrPoste.de(c.magasin);
    if (o == null) return const SizedBox.shrink();
    return ListenableBuilder(
        listenable: Listenable.merge([o, c.magasin.collection(ocrReglages)]),
        builder: (context, _) {
          final r = o.reglage;
          final mere = o.reglageEstIci;
          final choisi = r.moteur;
          final dispo = choisi == null ? null : o.moteurs.containsKey(choisi);
          return CarteSigh(titre: 'Lecture des scans (OCR)', child: Column(key: const Key('ocr:carte-reglage'), crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.regle ? (r.actif ? 'Lecture activée' : 'Lecture désactivée') : 'Lecture désactivée (aucun réglage posé : valeur par défaut, à valider par la Direction)',
                key: const Key('ocr:reglage-etat'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Moteur : ${choisi ?? 'aucun choisi'} · langue ${r.langue} · délai ${r.delaiMs ~/ 1000} s${r.regleLe == null ? '' : ' · réglé le ${_dateFr(r.regleLe)} par ${r.reglePar ?? 'auteur inconnu'}'}${(r.motif ?? '').isEmpty ? '' : ' (« ${r.motif} »)'}',
                key: const Key('ocr:reglage-detail'), style: const TextStyle(color: JetonsShell.slate600, fontSize: 12)),
            const SizedBox(height: 6),
            if (r.actif && dispo == false)
              NoteSigh('Le moteur « $choisi », choisi au réglage de la mère, n’est pas installé sur ce poste : ce poste ne lit aucun scan et le dit (« texte non indexé »). Il reçoit pourtant les textes lus par les autres postes.',
                  key: const Key('ocr:moteur-indisponible'), ton: TonSigh.attention, icone: LucideIcons.triangleAlert)
            else if (!o.moteurInstalle)
              NoteSigh('${ocrRaisonSansMoteur[0].toUpperCase()}${ocrRaisonSansMoteur.substring(1)}. La Direction a décidé de choisir le moteur après un essai sur trois vrais scans.', key: const Key('ocr:sans-moteur')),
            const SizedBox(height: 8),
            if (mere && peutRegler)
              BoutonSigh(key: const Key('ocr:bouton-reglage'), libelle: 'Régler la lecture des scans', icone: LucideIcons.scanText, variante: VarianteBouton.secondaire, onPressed: () => _ouvrirReglage(context, o, peutRegler))
            else
              Text(mere ? 'Votre profil ne peut pas modifier les paramètres système.' : 'Ce réglage se décide sur le poste mère et descend ici par la synchronisation : un poste fileul le lit, il ne le modifie pas.',
                  key: const Key('ocr:reglage-lecture-seule'), style: const TextStyle(color: JetonsShell.slate500, fontSize: 12)),
          ]));
        });
  }
}

Future<void> _ouvrirReglage(BuildContext context, OcrPoste o, bool peutRegler) async {
  final r = o.reglage;
  var actif = r.actif;
  var moteur = r.moteur != null && o.moteurs.containsKey(r.moteur) ? r.moteur : null;
  final langue = TextEditingController(text: r.langue);
  final delai = TextEditingController(text: '${r.delaiMs ~/ 1000}');
  final motif = TextEditingController();
  final refus = ValueNotifier<RefusFichier?>(null);
  await afficherModale<void>(context,
      titre: 'Lecture des scans (OCR)',
      taille: TailleModale.sm,
      corps: StatefulBuilder(
          builder: (_, setS) => ValueListenableBuilder<RefusFichier?>(
              valueListenable: refus,
              builder: (_, ref, __) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    NoteSigh(
                        o.moteurInstalle
                            ? 'La lecture des scans est désactivée par défaut (à valider par la Direction). Ce réglage se décide ici, à la mère : il descend à tous les postes. Le texte lu par machine est toujours marqué « à vérifier ».'
                            : '${ocrRaisonSansMoteur[0].toUpperCase()}${ocrRaisonSansMoteur.substring(1)}. Il n’y a rien à activer tant qu’un moteur n’est pas installé sur la mère.',
                        key: const Key('ocr:reglage-note')),
                    const SizedBox(height: 12),
                    Row(children: [
                      Checkbox(key: const Key('ocr:actif'), value: actif, onChanged: (v) => setS(() => actif = v ?? false)),
                      const Expanded(child: Text('Activer la lecture automatique des scans', style: TextStyle(fontSize: 14))),
                    ]),
                    const Text('Moteur d’OCR', style: TextStyle(color: JetonsShell.slate600, fontSize: 12)),
                    DropdownButtonFormField<String>(
                        key: const Key('ocr:moteur'),
                        initialValue: moteur,
                        hint: Text(o.moteurInstalle ? 'Choisir un moteur' : 'Aucun moteur installé'),
                        items: [for (final m in o.moteurs.values) DropdownMenuItem(value: m.id, child: Text('${m.libelle}${m.version.isEmpty ? '' : ' ${m.version}'}'))],
                        onChanged: o.moteurInstalle ? (v) => setS(() => moteur = v) : null),
                    const SizedBox(height: 12),
                    const Text('Langue (code du moteur, « fra » pour le français)', style: TextStyle(color: JetonsShell.slate600, fontSize: 12)),
                    TextField(key: const Key('ocr:langue'), controller: langue),
                    const SizedBox(height: 12),
                    const Text('Délai de lecture par page (secondes)', style: TextStyle(color: JetonsShell.slate600, fontSize: 12)),
                    TextField(key: const Key('ocr:delai'), controller: delai, keyboardType: TextInputType.number),
                    const SizedBox(height: 12),
                    const Text('Motif (consigné dans le journal)', style: TextStyle(color: JetonsShell.slate600, fontSize: 12)),
                    TextField(key: const Key('ocr:motif'), controller: motif, maxLines: 2),
                    if (ref != null)
                      Padding(padding: const EdgeInsets.only(top: 8), child: NoteSigh('${ref.code} : ${ref.motif} ${ref.geste}', key: const Key('ocr:reglage-refus'), ton: TonSigh.attention)),
                  ]))),
      pied: (fermer) => [
            BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
            BoutonSigh(
                key: const Key('ocr:enregistrer'),
                libelle: 'Enregistrer',
                icone: LucideIcons.check,
                onPressed: () {
                  final s = int.tryParse(delai.text.trim());
                  final x = o.definirReglage(peutRegler: peutRegler, actif: actif, moteur: moteur, langue: langue.text.trim(), motif: motif.text, delaiMs: s == null || s <= 0 ? null : s * 1000);
                  if (!x.ok) {
                    refus.value = x.refus;
                    return;
                  }
                  fermer();
                  ToastsSigh.afficher(context, actif ? 'Lecture des scans activée.' : 'Lecture des scans désactivée.', type: TypeToast.succes);
                }),
          ]);
}
