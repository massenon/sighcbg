#!/usr/bin/env python3
"""Appose la mention « SPÉCIMEN · DONNÉES FICTIVES » sur chaque PDF du dossier `presentation/` (filigrane diagonal discret, sans toucher au gabarit
d'impression : le PDF d'origine reste celui du poste, la mention est ajoutée APRÈS coup, sur une copie).

Usage : python3 tool/specimens/tamponner.py ../../presentation
Rejouable : un PDF déjà tamponné (métadonnée `keywords` contenant « specimen-tamponne ») est laissé tel quel.
Dépendance : PyMuPDF (`pip install pymupdf`). Sans elle, les spécimens restent valides, simplement sans filigrane.
"""
import math
import os
import sys

try:
    import pymupdf as fitz
except ImportError:  # anciennes versions
    import fitz

MARQUE = "specimen-tamponne"
TEXTE = "SPÉCIMEN · DONNÉES FICTIVES"


def tamponner(chemin: str) -> bool:
    doc = fitz.open(chemin)
    if MARQUE in (doc.metadata.get("keywords") or ""):
        doc.close()
        return False
    for page in doc:
        r = page.rect
        angle = 38 if r.height > r.width * 0.9 else 0
        # La mention doit tenir DANS la page, même tournée : longueur maximale = 90 % de la place offerte dans le sens du texte.
        cos, sin = math.cos(math.radians(angle)), math.sin(math.radians(angle))
        lmax = 0.85 * min(r.width / cos, r.height / sin if sin else 1e9)
        par_point = 1.05 * fitz.Font("helv").text_length(TEXTE, fontsize=100) / 100
        taille = max(6.0, min(r.width * 0.075, lmax / par_point))
        longueur = par_point * taille
        c = fitz.Point(r.width / 2, r.height / 2)
        depart = fitz.Point(c.x - longueur / 2, c.y)
        morph = (c, fitz.Matrix(-angle)) if angle else None
        page.insert_text(depart, TEXTE, fontname="helv", fontsize=taille, color=(0.78, 0.1, 0.1), fill_opacity=0.16, morph=morph, overlay=True)
    meta = doc.metadata
    meta["keywords"] = (meta.get("keywords") or "") + " " + MARQUE
    doc.set_metadata(meta)
    tmp = chemin + ".tmp"
    doc.save(tmp, garbage=3, deflate=True)
    doc.close()
    os.replace(tmp, chemin)
    return True


def main() -> None:
    racine = sys.argv[1] if len(sys.argv) > 1 else "../../presentation"
    n = 0
    for d, _, fichiers in os.walk(racine):
        for f in sorted(fichiers):
            if f.lower().endswith(".pdf") and tamponner(os.path.join(d, f)):
                n += 1
    print(f"{n} PDF tamponné(s) dans {racine}")


if __name__ == "__main__":
    main()
