#!/usr/bin/env python3
"""Compacte les captures d'un manuel (palette adaptative de 256 couleurs, sans tramage) : une capture d'interface y perd trois fois son poids sans
perte visible du texte. À lancer après le test de capture, avant la génération du PDF :

    python3 docs/manuels/compacter-captures.py docs/manuels/src/utilisateur/captures

Idempotent : une image déjà en palette est laissée telle quelle. Nécessite Pillow.
"""
import sys
from pathlib import Path

from PIL import Image

dossier = Path(sys.argv[1] if len(sys.argv) > 1 else '.')
avant = apres = 0
for f in sorted(dossier.glob('*.png')):
    im = Image.open(f)
    taille = f.stat().st_size
    avant += taille
    if im.mode == 'P':
        apres += taille
        continue
    q = im.convert('RGB').quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    q.save(f, optimize=True)
    apres += f.stat().st_size
print(f'{dossier} : {avant / 1e6:.1f} Mo -> {apres / 1e6:.1f} Mo')
