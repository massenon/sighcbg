import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart' show mobRefusDroitRetire;

import '../moteur/droits_mobile.dart';

/// Un écran OUVERT dont le droit est retiré à chaud se ferme : retour à l'accueil, sans crash, et on le DIT (une porte qui se ferme sans un mot ferait croire à une
/// panne). La garde écoute la matrice : elle se déclenche à l'instant où la mère livre la décision, pas à la prochaine ouverture.
///
/// [ecriture] : l'écran est une saisie. Le droit de voir peut rester alors que celui d'écrire est retiré : la saisie se ferme, la lecture (le dossier) reste ouverte.
/// [droits] absent : aucune garde (tests d'un écran isolé) ; le moteur réel fournit toujours la sienne.
class GardeDroit extends StatefulWidget {
  const GardeDroit({super.key, required this.droits, required this.ecran, this.ecriture = false, this.permis, required this.construire});
  final SuiviDroits? droits;
  final String ecran;
  final bool ecriture;
  /// Un droit plus fin que « voir / écrire cet écran » (la prescription dépend de la nature) ; absent, la garde juge [ecran].
  final bool Function()? permis;

  /// Reconstruit l'écran à chaque décision de la mère : les commandes qui perdent leur droit DISPARAISSENT de l'écran resté ouvert.
  final WidgetBuilder construire;

  @override
  State<GardeDroit> createState() => _GardeDroitState();
}

class _GardeDroitState extends State<GardeDroit> {
  bool _fermeture = false;

  bool get _permis {
    final d = widget.droits;
    if (d == null) return true;
    if (widget.permis != null) return widget.permis!();
    return widget.ecriture ? d.peutEditer(widget.ecran) : d.peutVoir(widget.ecran);
  }

  void _fermer() {
    if (_fermeture) return;
    _fermeture = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messager = ScaffoldMessenger.maybeOf(context);
      final motif = mobRefusDroitRetire(widget.ecran, ecriture: widget.ecriture).motif;
      Navigator.of(context).popUntil((r) => r.isFirst);
      messager?.showSnackBar(SnackBar(key: const Key('droit-retire'), content: Text('$motif Retour à l’accueil.'), duration: const Duration(seconds: 6)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.droits;
    if (d == null) return widget.construire(context);
    return ValueListenableBuilder<EtatDroits>(
      valueListenable: d,
      builder: (context, _, __) {
        if (_permis) return widget.construire(context);
        _fermer();
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
    );
  }
}
