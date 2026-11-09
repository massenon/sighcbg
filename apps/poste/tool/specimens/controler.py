#!/usr/bin/env python3
"""Contrôle du dossier `presentation/` : (1) aucune trace de l'autre clinique (Nassiera Too, sigle CNT) dans le TEXTE des PDF ni dans les fichiers texte ;
(2) chaque PDF s'ouvre et compte au moins une page ; (3) taille totale. Sort avec un code non nul au moindre manquement.

Usage : python3 tool/specimens/controler.py ../../presentation   (dépendance : PyMuPDF)
"""
import os
import re
import sys

try:
    import pymupdf as fitz
except ImportError:
    import fitz

INTERDIT = re.compile(r"nassi[eè]ra|\bCNT\b|CNT/|natitingou", re.IGNORECASE)


def main() -> int:
    racine = sys.argv[1] if len(sys.argv) > 1 else "../../presentation"
    erreurs, n, octets, pages = [], 0, 0, 0
    for d, _, fichiers in os.walk(racine):
        for f in sorted(fichiers):
            chemin = os.path.join(d, f)
            octets += os.path.getsize(chemin)
            if f.lower().endswith(".pdf"):
                n += 1
                doc = fitz.open(chemin)
                pages += doc.page_count
                if doc.page_count < 1:
                    erreurs.append(f"{chemin} : aucune page")
                for page in doc:
                    t = page.get_text()
                    m = INTERDIT.search(t)
                    if m:
                        erreurs.append(f"{chemin} p.{page.number + 1} : « {m.group(0)} »")
                        break
                doc.close()
            elif f.lower().endswith((".md", ".json", ".txt", ".py", ".dart")):
                t = open(chemin, encoding="utf-8").read()
                # les scripts de contrôle citent évidemment les motifs recherchés
                if f in ("controler.py",):
                    continue
                m = INTERDIT.search(t)
                if m:
                    erreurs.append(f"{chemin} : « {m.group(0)} »")
    print(f"{n} PDF, {pages} pages, {octets / 1e6:.1f} Mo ; {len(erreurs)} anomalie(s)")
    for e in erreurs:
        print("  -", e)
    return 1 if erreurs else 0


if __name__ == "__main__":
    sys.exit(main())
