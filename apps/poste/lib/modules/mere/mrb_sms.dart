import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../../shell/gestes_ecran.dart';
import 'mrb_commun.dart';
import 'mrb_source.dart';

/// LES SMS PAR LE RELAIS (ADR-0009, décision de la Direction de Baguidi du 16/11/2026) : deux écrans de la poste mère.
///
///  * `mere-sms-passerelle` — « Passerelle SMS » : l'interrupteur (FERMÉ par défaut), le plafond quotidien LU au relais (il se règle dans le `.env` du relais,
///    jamais depuis le poste), la liste des mots interdits telle qu'elle est (proposition à valider par un médecin) et « Tester l'envoi » ;
///  * `mere-sms-journal` — « Journal des envois SMS » : ce que la mère a déposé (numéro MASQUÉ, longueur, modèle, statut suivi au relais) et « Composer un SMS »
///    depuis un modèle de message.
///
/// Régler, tester et composer sont le GESTE RÉSERVÉ `reglage_sms` de la matrice (origine proposée : l'administrateur et la DAF) en plus du droit d'écrire sur
/// l'écran : sans lui, les commandes sont ABSENTES, jamais grisées. Aucun rôle n'est écrit ici.

bool mrbPeutRegleSms(ContexteEcran c) => c.peutEcrire && gestePeutEcran(c, gesteReglageSms);

String mrbLibelleStatutSms(Object? s) => switch (s) {
      'en_attente' => 'En attente d’envoi au relais',
      'envoye' => 'Envoyé (numéro et texte effacés au relais)',
      'echec' => 'Échec après cinq tentatives (effacé au relais)',
      'non_depose' => 'Non déposé (refusé ou relais injoignable)',
      _ => '$s',
    };

TonSigh mrbTonStatutSms(Object? s) => switch (s) {
      'envoye' => TonSigh.succes,
      'en_attente' => TonSigh.info,
      'echec' || 'non_depose' => TonSigh.danger,
      _ => TonSigh.neutre,
    };

/// Les modèles de message ACTIFS du magasin (`modelesMessage`), tels que « Rappels & messages » les administre : (libellé, texte).
List<(String, String)> mrbModelesSms(ContexteEcran c) => [
      for (final m in c.magasin.collection('modelesMessage').actives)
        if (m['actif'] != false && '${m['texte'] ?? ''}'.isNotEmpty) ('${m['libelle'] ?? m['occasion'] ?? 'Modèle'}', '${m['texte']}'),
    ];

/// La fenêtre de composition : choisir un modèle, saisir le numéro (et la date du rendez-vous si le modèle la demande), VOIR le texte exact qui partira, puis
/// déposer. La composition et ses refus sont ceux du domaine (`smsComposer`) ; le service de la mère les refait avant l'envoi.
Future<void> mrbComposerSms(BuildContext contexte, {required MrbSource source, required List<(String, String)> modeles, required String auteur, bool essai = false, VoidCallback? apres}) async {
  await afficherModale<void>(contexte,
      titre: essai ? 'Tester l’envoi' : 'Composer un SMS',
      sousTitre: essai ? 'Un SMS d’essai, composé et contrôlé comme les autres.' : 'Depuis un modèle de message. Aucun contenu médical, aucun nom.',
      taille: TailleModale.lg,
      corps: _Composition(source: source, modeles: essai ? const [('Message d’essai', smsModeleEssai)] : modeles, auteur: auteur, essai: essai, apres: apres));
}

class _Composition extends StatefulWidget {
  const _Composition({required this.source, required this.modeles, required this.auteur, required this.essai, this.apres});
  final MrbSource source;
  final List<(String, String)> modeles;
  final String auteur;
  final bool essai;
  final VoidCallback? apres;
  @override
  State<_Composition> createState() => _EtatComposition();
}

class _EtatComposition extends State<_Composition> {
  final _numero = TextEditingController();
  final _rdv = TextEditingController();
  final _date = TextEditingController();
  int _modele = 0;
  bool _envoi = false;
  String? _refusDepot;

  @override
  void dispose() {
    _numero.dispose();
    _rdv.dispose();
    _date.dispose();
    super.dispose();
  }

  String get _texteModele => widget.modeles.isEmpty ? '' : widget.modeles[_modele].$2;

  SmsCompose _composer() => smsComposer(
        modele: _texteModele,
        numero: _numero.text,
        clinique: IdentiteClinique.nom,
        telephone: CfaIdentite.telephoneRdv,
        rdv: _rdv.text,
        date: _date.text,
      );

  Future<void> _deposer(SmsCompose r) async {
    setState(() {
      _envoi = true;
      _refusDepot = null;
    });
    try {
      await widget.source.envoyerSms(numero: r.numero!, texte: r.texte!, modele: widget.modeles[_modele].$1, auteur: widget.auteur, essai: widget.essai);
      if (!mounted) return;
      ToastsSigh.afficher(context, 'SMS déposé au relais : il part au prochain passage de la tâche planifiée.', type: TypeToast.succes);
      widget.apres?.call();
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _envoi = false;
          _refusDepot = e is MrbIndisponible ? 'Non disponible : ${e.motif}' : 'Refusé : ${mrbCause(e)}';
        });
      }
    }
  }

  Widget _champ(String libelle, TextEditingController ctl, Key cle, {String? aide}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(libelle, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: JetonsShell.slate600)),
          const SizedBox(height: 4),
          TextField(key: cle, controller: ctl, style: styleSaisie, decoration: decorationChamp(indicatif: aide ?? libelle), onChanged: (_) => setState(() {})),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    if (widget.modeles.isEmpty) {
      return const NoteSigh('Aucun modèle de message actif : les modèles s’écrivent à « Rappels & messages ».', ton: TonSigh.attention, icone: LucideIcons.info);
    }
    final r = _composer();
    final saisi = _numero.text.trim().isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!widget.essai) ...[
        const Text('Modèle de message', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: JetonsShell.slate600)),
        const SizedBox(height: 4),
        SelecteurSigh(
          key: const Key('sms:modele'),
          libelle: 'Modèle de message',
          valeur: '$_modele',
          options: [for (var i = 0; i < widget.modeles.length; i++) OptionChamp('$i', widget.modeles[i].$1)],
          surChange: (v) => setState(() => _modele = int.tryParse(v) ?? 0),
        ),
        const SizedBox(height: 12),
      ],
      _champ('Numéro de téléphone', _numero, const Key('sms:numero'), aide: 'Avec ou sans indicatif (+229)'),
      if (_texteModele.contains('{{rdv}}')) _champ('Date et heure du rendez-vous', _rdv, const Key('sms:rdv'), aide: 'Par exemple 18/11/2026 à 09h00'),
      if (_texteModele.contains('{{date}}')) _champ('Date de l’occasion', _date, const Key('sms:date'), aide: 'Par exemple 18/11/2026'),
      const Text('Le texte qui partira, tel quel', style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: JetonsShell.slate50, borderRadius: BorderRadius.circular(8), border: Border.all(color: JetonsShell.slate200)),
        child: SelectableText(r.texte ?? '(texte non composé)', key: const Key('sms:apercu'), style: const TextStyle(fontSize: 13, height: 20 / 13)),
      ),
      if (r.texte != null)
        Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('${r.texte!.runes.length} caractère(s) sur $smsLongueurMax', style: const TextStyle(fontSize: 12, color: JetonsShell.slate500))),
      if (r.nomRetire)
        const Padding(
            padding: EdgeInsets.only(top: 8),
            child: NoteSigh('Le nom du patient n’est jamais envoyé : la variable {{nom}} du modèle est retirée. Le relais ne voit qu’un numéro et ce texte.',
                icone: LucideIcons.eyeOff)),
      if (saisi && r.refus != null)
        Padding(
            padding: const EdgeInsets.only(top: 8),
            child: NoteSigh('${r.refus!.motif} ${r.refus!.geste}', key: const Key('sms:refus'), ton: TonSigh.danger, icone: LucideIcons.ban)),
      if (_refusDepot != null) Padding(padding: const EdgeInsets.only(top: 8), child: NoteSigh(_refusDepot!, key: const Key('sms:refus-depot'), ton: TonSigh.danger, icone: LucideIcons.triangleAlert)),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerRight,
        child: BoutonSigh(
            key: const Key('sms:deposer'),
            libelle: widget.essai ? 'Envoyer le SMS d’essai' : 'Déposer au relais',
            icone: LucideIcons.send,
            onPressed: saisi && r.ok && !_envoi ? () => _deposer(r) : null),
      ),
    ]);
  }
}

// =============================================================================================================================================
// mere-sms-passerelle
// =============================================================================================================================================

class EcranSmsPasserelle extends StatefulWidget with EcranMaquette {
  const EcranSmsPasserelle({super.key});
  @override
  String get titre => 'Passerelle SMS';
  @override
  String get description => 'Les SMS partent par le relais : réglage de la passerelle, plafond quotidien lu au relais, envoi d’essai.';
  @override
  String get regle =>
      'Le relais ne voit qu’un numéro et un texte déjà composés par la mère, qu’il efface après l’envoi. Aucun contenu médical, aucun nom : un rappel dit le jour, l’heure et la clinique.';

  @override
  State<EcranSmsPasserelle> createState() => _EtatPasserelle();
}

class _EtatPasserelle extends MrbEtatEcran<EcranSmsPasserelle, MrbSms?> {
  @override
  Future<MrbSms?> charger(MrbSource s) => s.sms();

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final d = donnees;
    final peut = mrbPeutRegleSms(c);
    final s = source;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      mrbBandeauPanne(panne),
      const NoteSigh(
          'La mère compose le SMS depuis un modèle de message et le dépose au relais, qui l’envoie par une tâche planifiée puis EFFACE le numéro et le texte. '
          'Le relais ne voit jamais le dossier, le nom, le motif ni le diagnostic. Les identifiants du fournisseur de SMS ne vivent que dans le fichier de réglages du relais.',
          icone: LucideIcons.shieldCheck),
      const SizedBox(height: 12),
      if (d == null && panne == null && !enCours)
        const NoteSigh('Le service de la mère ne propose pas la passerelle SMS : réglages non disponibles.', ton: TonSigh.attention, icone: LucideIcons.info),
      if (d != null) ...[
        mrbGrilleKpi([
          mrbKpi('Passerelle', d.actif ? 'Ouverte' : 'Fermée',
              indice: d.actif ? 'les SMS composés partent par le relais' : 'fermée par défaut : rien ne part', ton: d.actif ? TonSigh.succes : TonSigh.neutre, icone: LucideIcons.messageSquare),
          mrbKpi('Plafond quotidien', d.plafondJour == null ? null : '${d.plafondJour}',
              indice: d.plafondJour == null ? (d.erreurRelais ?? 'non lu : relais non configuré ou injoignable') : 'SMS par jour, réglé dans le fichier de réglages du relais',
              icone: LucideIcons.gauge),
          mrbKpi('Envoyés aujourd’hui', d.envoyesAujourdhui == null ? null : '${d.envoyesAujourdhui}', indice: d.enAttenteRelais == null ? null : '${d.enAttenteRelais} en attente au relais', icone: LucideIcons.send),
          mrbKpi('Fournisseur', d.pilote == null ? null : (d.pilote == 'journal' ? 'Essai (n’envoie rien)' : d.pilote),
              indice: d.pilote == 'journal' ? 'pilote d’essai du relais : aucun SMS ne part réellement' : null, ton: d.pilote == 'journal' ? TonSigh.attention : TonSigh.navy, icone: LucideIcons.radioTower),
        ]),
        const SizedBox(height: 12),
        if (!d.relaisConfigure)
          const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: NoteSigh('Aucun relais n’est configuré sur cette mère : aucun SMS ne peut partir, même passerelle ouverte.', ton: TonSigh.attention, icone: LucideIcons.triangleAlert)),
        CarteSigh(
          titre: 'Réglage',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Checkbox(
                  key: const Key('sms:interrupteur'),
                  value: d.actif,
                  onChanged: peut && s != null
                      ? (v) => geste(context, () => s.reglerSms(actif: v == true), ok: v == true ? 'Passerelle SMS ouverte.' : 'Passerelle SMS fermée : plus rien ne part.')
                      : null,
                  activeColor: JetonsShell.navy900,
                  visualDensity: VisualDensity.compact),
              Expanded(
                  child: Text(d.actif ? 'Passerelle SMS : OUVERTE' : 'Passerelle SMS : FERMÉE (aucun SMS ne part)',
                      key: const Key('sms:etat-interrupteur'), style: const TextStyle(fontWeight: FontWeight.w600))),
            ]),
            if (!peut)
              const Padding(
                  padding: EdgeInsets.only(left: 12, bottom: 4),
                  child: Text('Lecture seule : régler la passerelle et tester l’envoi sont réservés par la matrice des droits (geste « Régler la passerelle SMS »).',
                      key: Key('sms:lecture-seule'), style: TextStyle(fontSize: 12, color: JetonsShell.slate500))),
            if (peut && s != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: BoutonSigh(
                    key: const Key('sms:tester'),
                    libelle: 'Tester l’envoi',
                    icone: LucideIcons.sendHorizontal,
                    variante: VarianteBouton.secondaire,
                    onPressed: d.actif ? () => mrbComposerSms(context, source: s, modeles: const [], auteur: c.utilisateur, essai: true, apres: actualiser) : null),
              ),
          ]),
        ),
        const SizedBox(height: 16),
        CarteSigh(
          titre: 'Mots interdits dans un SMS',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            NoteSigh('${d.statutMotsInterdits.isEmpty ? smsStatutMotsInterdits : d.statutMotsInterdits}. Un texte qui en contient un est refusé, au poste puis par la mère, en nommant le mot.',
                key: const Key('sms:statut-mots'), ton: TonSigh.attention, icone: LucideIcons.stethoscope),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final m in smsMotsInterdits) BadgeSigh(m)]),
          ]),
        ),
      ],
    ]);
  }
}

// =============================================================================================================================================
// mere-sms-journal
// =============================================================================================================================================

class EcranSmsJournal extends StatefulWidget with EcranMaquette {
  const EcranSmsJournal({super.key});
  @override
  String get titre => 'Journal des envois SMS';
  @override
  String get description => 'Les SMS déposés au relais par la mère : numéro masqué, longueur, modèle et statut suivi jusqu’à l’envoi.';
  @override
  String get regle => 'Le journal ne garde ni le texte ni le numéro en clair : le relais efface les deux après l’envoi, la mère ne garde que le numéro masqué.';

  @override
  State<EcranSmsJournal> createState() => _EtatJournal();
}

class _EtatJournal extends MrbEtatEcran<EcranSmsJournal, MrbSms?> {
  @override
  Future<MrbSms?> charger(MrbSource s) => s.sms();

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final d = donnees;
    final s = source;
    final peut = mrbPeutRegleSms(c);
    final lignes = <Ligne>[
      for (final e in d?.journal ?? const <Map<String, Object?>>[])
        {
          'depose': e['depose_le'] is num ? (e['depose_le'] as num).toInt() : 0,
          'numero': '${e['numero_masque'] ?? ''}',
          'modele': e['essai'] == true ? 'Message d’essai' : '${e['modele'] ?? '—'}',
          'longueur': e['longueur'] is num ? (e['longueur'] as num).toInt() : 0,
          'statut': '${e['statut'] ?? ''}',
          'tentatives': e['tentatives'] is num ? (e['tentatives'] as num).toInt() : 0,
          'erreur': '${e['erreur'] ?? ''}',
        }
    ];
    final compte = {for (final st in ['en_attente', 'envoye', 'echec', 'non_depose']) st: lignes.where((l) => l['statut'] == st).length};
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      mrbBandeauPanne(panne),
      mrbGrilleKpi([
        mrbKpi('Déposés', d == null ? null : '${lignes.length}', indice: '200 derniers au plus', icone: LucideIcons.messageSquare),
        mrbKpi('Envoyés', d == null ? null : '${compte['envoye']}', ton: TonSigh.succes, icone: LucideIcons.checkCheck),
        mrbKpi('En attente', d == null ? null : '${compte['en_attente']}', ton: TonSigh.info, icone: LucideIcons.hourglass),
        mrbKpi('Échecs ou refus', d == null ? null : '${compte['echec']! + compte['non_depose']!}', ton: (compte['echec']! + compte['non_depose']!) > 0 ? TonSigh.danger : TonSigh.neutre, icone: LucideIcons.ban),
      ]),
      const SizedBox(height: 12),
      if (d != null && !d.actif)
        const Padding(padding: EdgeInsets.only(bottom: 12), child: NoteSigh('La passerelle SMS est fermée : rien ne part. Elle s’ouvre à l’écran « Passerelle SMS ».', ton: TonSigh.attention, icone: LucideIcons.info)),
      if (s != null && d != null && (peut || c.peutEcrire))
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            if (peut)
              BoutonSigh(
                  key: const Key('sms:composer'),
                  libelle: 'Composer un SMS',
                  icone: LucideIcons.messageSquarePlus,
                  onPressed: d.actif ? () => mrbComposerSms(context, source: s, modeles: mrbModelesSms(c), auteur: c.utilisateur, apres: actualiser) : null),
            if (c.peutEcrire)
              BoutonSigh(
                  key: const Key('sms:suivre'),
                  libelle: 'Relever les statuts',
                  icone: LucideIcons.refreshCw,
                  variante: VarianteBouton.secondaire,
                  onPressed: () => geste(context, () async {
                        final n = await s.suivreSms();
                        if (context.mounted) ToastsSigh.afficher(context, n == 0 ? 'Aucun statut n’a changé.' : '$n statut(s) mis à jour.', type: TypeToast.info);
                      })),
          ]),
        ),
      CarteSigh(
        titre: 'Envois',
        sansRemplissage: true,
        child: MrbTableau(
          messageVide: d == null ? 'Journal non lu : le service de la mère ne répond pas.' : 'Aucun SMS n’a encore été déposé.',
          indiceVide: 'Le texte des SMS n’est pas gardé : le relais l’efface après l’envoi.',
          colonnes: [
            ColonneTableau(cle: 'depose', libelle: 'Déposé le', sansCoupure: true, texte: (l) => (l['depose'] as int) == 0 ? '—' : mrbDateHeureMs(l['depose']! as int)),
            const ColonneTableau(cle: 'numero', libelle: 'Numéro (masqué)'),
            const ColonneTableau(cle: 'modele', libelle: 'Modèle'),
            ColonneTableau(cle: 'longueur', libelle: 'Caractères', texte: (l) => '${l['longueur']}'),
            ColonneTableau(cle: 'statut', libelle: 'Statut', texte: (l) => mrbLibelleStatutSms(l['statut'])),
            ColonneTableau(cle: 'tentatives', libelle: 'Tentatives', texte: (l) => '${l['tentatives']} / $smsTentativesMax'),
            ColonneTableau(cle: 'erreur', libelle: 'Refus', texte: (l) => '${l['erreur']}'.isEmpty ? '—' : '${l['erreur']}'),
          ],
          lignes: lignes,
        ),
      ),
    ]);
  }
}
