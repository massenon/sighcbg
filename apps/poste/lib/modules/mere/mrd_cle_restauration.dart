import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/cle_clinique_poste.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../../shell/gestes_ecran.dart';
import '../cfg/cfg_base_portable.dart' show SelecteursBase;
import 'mrc_commun.dart' show MrcAccesRefuse;

/// `mere-cle-restauration` : remettre la CLÉ DE LA CLINIQUE sur un poste NEUF, depuis sa copie sous scellé (décision 12 de la Direction de Baguidi, 17/11/2026). Sans la clé, les sauvegardes, les
/// exports portables et le relais sont irrécupérables. Deux sources : le TEXTE de la copie sous scellé, ou un FICHIER de sauvegarde de clé (le format de « Sauvegarder la clé de chiffrement »,
/// chiffré par une phrase de passe). L'EMPREINTE notée sur le scellé est exigée AVANT acceptation ; la clé ne s'affiche JAMAIS (les champs sont masqués, l'écran ne la relit pas) et ne se
/// journalise JAMAIS. Écran de la poste mère, réservé d'origine à l'administrateur et à la DAF.
class EcranCleRestauration extends StatefulWidget with EcranMaquette {
  const EcranCleRestauration({super.key});
  @override
  String get titre => 'Restaurer la clé de la clinique';
  @override
  String get description => 'Sur un poste neuf : remettre la clé de chiffrement de la clinique depuis sa copie sous scellé, avec contrôle de l’empreinte.';
  @override
  String get regle =>
      'La clé n’est acceptée que si elle reproduit l’empreinte notée sur le scellé. Elle ne s’affiche jamais et n’est jamais écrite au journal : seule son empreinte l’est. '
      'Une autre clé déjà en service n’est remplacée que sur confirmation explicite.';
  @override
  State<EcranCleRestauration> createState() => _EtatCleRestauration();
}

class _EtatCleRestauration extends State<EcranCleRestauration> {
  final _texte = TextEditingController();
  final _fichier = TextEditingController();
  final _phrase = TextEditingController();
  final _empreinte = TextEditingController();
  bool _remplacer = false, _occupe = false, _depuisFichier = false;
  String? _acceptee;
  ErreurExport? _erreur;
  String? _courante;
  bool _lu = false;

  @override
  void dispose() {
    for (final c in [_texte, _fichier, _phrase, _empreinte]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _champ(String libelle, TextEditingController ctl, Key cle, {bool secret = false}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(libelle, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: JetonsShell.slate600)),
        const SizedBox(height: 4),
        TextField(key: cle, controller: ctl, obscureText: secret, enableSuggestions: false, autocorrect: false, style: styleSaisie, decoration: decorationChamp(indicatif: libelle)),
      ]);

  Future<void> _restaurer(ServiceCleClinique svc) async {
    setState(() {
      _occupe = true;
      _erreur = null;
      _acceptee = null;
    });
    try {
      final courte = await svc.restaurer(
          texte: _depuisFichier ? null : _texte.text,
          fichier: _depuisFichier ? _fichier.text : null,
          phrase: _depuisFichier ? _phrase.text : null,
          empreinteAttendue: _empreinte.text,
          remplacer: _remplacer);
      // Les champs qui ont porté la clé sont VIDÉS aussitôt : elle ne reste pas à l'écran.
      _texte.clear();
      _phrase.clear();
      _acceptee = courte;
      _courante = courte;
    } on ErreurExport catch (e) {
      _erreur = e;
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    if (!gestePeutEcran(c, gesteSystemeAdministrer)) return MrcAccesRefuse(role: c.role);
    final svc = ServiceCleClinique.de(c.magasin);
    if (svc == null) return const NoteSigh('Le service de restauration de la clé n’est pas disponible sur ce poste.', ton: TonSigh.attention, icone: LucideIcons.triangleAlert);
    if (!_lu) {
      _lu = true;
      svc.empreinteCourante().then((e) {
        if (mounted) setState(() => _courante = e);
      });
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      NoteSigh(
          _courante == null
              ? 'Aucune clé de clinique n’est connue de ce poste : c’est le cas d’un poste neuf.'
              : 'Clé en service : empreinte $_courante. Restaurer une AUTRE clé exige une confirmation explicite.',
          key: const Key('cle:etat'),
          ton: _courante == null ? TonSigh.attention : TonSigh.info,
          icone: LucideIcons.keyRound),
      const SizedBox(height: 16),
      CarteSigh(
        titre: 'Depuis la copie sous scellé',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            ChoiceChip(key: const Key('cle:source-texte'), label: const Text('Texte de la copie papier'), selected: !_depuisFichier, onSelected: (_) => setState(() => _depuisFichier = false)),
            const SizedBox(width: 8),
            ChoiceChip(key: const Key('cle:source-fichier'), label: const Text('Fichier de sauvegarde de clé'), selected: _depuisFichier, onSelected: (_) => setState(() => _depuisFichier = true)),
          ]),
          const SizedBox(height: 12),
          if (!_depuisFichier)
            _champ('Clé (64 caractères hexadécimaux ou Base64)', _texte, const Key('cle:texte'), secret: true)
          else ...[
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: _champ('Fichier de sauvegarde de clé (.cle)', _fichier, const Key('cle:fichier'))),
              const SizedBox(width: 8),
              BoutonSigh(
                  libelle: 'Parcourir',
                  variante: VarianteBouton.secondaire,
                  onPressed: () async {
                    final f = await SelecteursBase.fichier();
                    if (f != null) setState(() => _fichier.text = f);
                  }),
            ]),
            const SizedBox(height: 8),
            _champ('Phrase de passe du fichier', _phrase, const Key('cle:phrase'), secret: true),
          ],
          const SizedBox(height: 12),
          _champ('Empreinte notée sur le scellé (8 caractères au moins)', _empreinte, const Key('cle:empreinte')),
          if (_courante != null) ...[
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Checkbox(key: const Key('cle:remplacer'), value: _remplacer, onChanged: (v) => setState(() => _remplacer = v == true)),
              const Expanded(
                  child: Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text('Remplacer la clé en service par celle-ci (poste neuf uniquement : ce que l’ancienne clé a chiffré deviendrait illisible)', style: TextStyle(fontSize: 13)))),
            ]),
          ],
          const SizedBox(height: 12),
          BoutonSigh(key: const Key('cle:restaurer'), libelle: 'Contrôler l’empreinte et restaurer la clé', icone: LucideIcons.keyRound, onPressed: _occupe ? null : () => _restaurer(svc)),
          if (_acceptee != null) ...[
            const SizedBox(height: 12),
            NoteSigh('Clé restaurée : empreinte $_acceptee. La clé n’est ni affichée ni journalisée. Les exports et sauvegardes de la clinique peuvent de nouveau s’ouvrir sur ce poste.',
                key: const Key('cle:acceptee'), ton: TonSigh.succes, icone: LucideIcons.circleCheck),
          ],
          if (_erreur != null) ...[
            const SizedBox(height: 12),
            NoteSigh('${_erreur!.refus.code} : ${_erreur!.refus.motif}. ${_erreur!.refus.geste}', key: const Key('cle:erreur'), ton: TonSigh.danger, icone: LucideIcons.ban),
          ],
        ]),
      ),
    ]);
  }
}
