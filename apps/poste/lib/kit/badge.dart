import 'package:flutter/material.dart';

import 'ton.dart';

/// `.badge` : pastille pleine (rayon 9999), px 8 py 2, 12/16 en 500 — hauteur 20.
///
/// `icone` : depuis que le rouge est aussi la couleur d'ACTION (charte Baguidi), une alerte ne se signale jamais par la
/// couleur seule : les badges de rupture, de péremption et de retard portent une icône EN PLUS de leur libellé.
class BadgeSigh extends StatelessWidget {
  const BadgeSigh(this.libelle, {super.key, this.ton = TonSigh.neutre, this.icone});
  final String libelle;
  final TonSigh ton;
  final IconData? icone;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
            color: ton.fond50, borderRadius: BorderRadius.circular(9999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icone != null) ...[
            Icon(icone, size: 12, color: ton.texteBadge),
            const SizedBox(width: 4),
          ],
          // Flexible : dans une cellule étroite, le libellé garde le retour à la ligne qu'il avait sans l'icône.
          Flexible(
              child: Text(libelle,
                  style: TextStyle(
                      color: ton.texteBadge,
                      fontSize: 12,
                      height: 16 / 12,
                      fontWeight: FontWeight.w500))),
        ]),
      );
}
