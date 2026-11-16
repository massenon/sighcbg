#!/usr/bin/env python3
"""Engendre TOUTES les icônes de l'application depuis le logo de la Clinique Baguidi (apps/poste/assets/img/logo.png).

Règle : le logo est carré (marge de 6 %), fond blanc opaque (le logo est déjà un disque sur fond blanc : lisible à 16 px sur barre claire ou sombre).
Sorties : icône Windows multi-tailles (16/24/32/48/64/128/256), icône du poste (256), lanceur Android (cinq densités), favicon et icônes du relais web.
Usage, depuis la racine du dépôt : python3 tools/baguidi/generer-icones.py  (écrit aussi tools/baguidi/icones-attendues.json : empreintes de contrôle)."""
import hashlib, json, sys
from pathlib import Path
from PIL import Image

RACINE = Path(__file__).resolve().parents[2]
SOURCE = RACINE / 'apps/poste/assets/img/logo.png'
MARGE = 0.06


def carre(taille: int) -> Image.Image:
    logo = Image.open(SOURCE).convert('RGBA')
    cote = max(logo.size)
    toile = Image.new('RGBA', (cote, cote), (255, 255, 255, 255))
    toile.paste(logo, ((cote - logo.width) // 2, (cote - logo.height) // 2), logo)
    interieur = round(taille * (1 - 2 * MARGE))
    reduit = toile.resize((interieur, interieur), Image.LANCZOS)
    sortie = Image.new('RGBA', (taille, taille), (255, 255, 255, 255))
    d = (taille - interieur) // 2
    sortie.paste(reduit, (d, d), reduit)
    return sortie


def ico(chemin: Path, tailles):
    chemin.parent.mkdir(parents=True, exist_ok=True)
    carre(256).save(chemin, format='ICO', sizes=[(t, t) for t in tailles], bitmap_format='png')


def png(chemin: Path, t: int):
    chemin.parent.mkdir(parents=True, exist_ok=True)
    carre(t).convert('RGB').save(chemin, format='PNG', optimize=True)


def main():
    produits = []
    p = RACINE / 'apps/poste/windows/runner/resources/app_icon.ico'
    ico(p, [16, 24, 32, 48, 64, 128, 256]); produits.append(p)
    p = RACINE / 'apps/poste/assets/img/icone-poste.png'
    png(p, 256); produits.append(p)
    for dossier, t in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
        p = RACINE / f'apps/mobile/android/app/src/main/res/mipmap-{dossier}/ic_launcher.png'
        png(p, t); produits.append(p)
    p = RACINE / 'apps/web/public/favicon.ico'
    ico(p, [16, 32, 48]); produits.append(p)
    for nom, t in [('apple-touch-icon.png', 180), ('icon-192.png', 192), ('icon-512.png', 512)]:
        p = RACINE / 'apps/web/public' / nom
        png(p, t); produits.append(p)
    attendues = {str(p.relative_to(RACINE)): hashlib.sha256(p.read_bytes()).hexdigest() for p in produits}
    (RACINE / 'tools/baguidi/icones-attendues.json').write_text(json.dumps(attendues, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    print(f'{len(produits)} icônes écrites')


if __name__ == '__main__':
    sys.exit(main())
