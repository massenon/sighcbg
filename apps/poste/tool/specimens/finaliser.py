#!/usr/bin/env python3
"""Dernière étape du dossier `presentation/` : (1) apposer la mention SPÉCIMEN (tamponner.py) ; (2) réécrire INDEX.md et README.md (à partir de README.modele.md) avec pages, taille et particularité de chaque
spécimen, la liste des documents NON produits (non_produits.json) et les gabarits recensés sans spécimen propre.

Usage : python3 tool/specimens/finaliser.py ../../presentation   (dépendance : PyMuPDF)
"""
import json
import os
import sys

try:
    import pymupdf as fitz
except ImportError:
    import fitz

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tamponner import tamponner  # noqa: E402

MODULES = {
    "M1": "M1 — Patients & dossier médical",
    "M2": "M2 — Rendez-vous, consultations, imagerie, spécialités",
    "SPEC": "M2 — Rendez-vous, consultations, imagerie, spécialités",
    "M3": "M3 — Hospitalisation, soins & bloc",
    "M4": "M4 — Maternité, naissances & décès",
    "M5": "M5 — Laboratoire & banque de sang",
    "M6": "M6 — Pharmacie & stocks",
    "M7": "M7 — Achats & fournisseurs",
    "M8": "M8 — Facturation & caisse",
    "M9": "M9 — Assurances & créances",
    "M10": "M10 — Ressources humaines",
    "M11": "M11 — Paie & primes",
    "M12": "M12 — Comptabilité & gestion",
    "M13": "M13 — Administration & ambulance",
    "M14": "M14 — Sécurité & utilisateurs",
    "MECEF": "MECeF — Facture normalisée",
    "GED": "GED — Gestion documentaire",
    "RAP": "RAP — Rapports & états officiels",
    "PIL": "PIL — Pilotage & statistiques",
    "CFG": "CFG — Configuration de la clinique",
    "TRANSVERSE": "Transverse — gabarit commun des listes filtrées",
}
ORDRE = list(MODULES)

# Ce que tel spécimen montre de particulier, au-delà de l'en-tête et du pied communs (clé : nom de fichier sans extension).
PARTICULARITES = {
    "ticket-de-caisse-80-mm": "Rouleau 80 mm (gabarit distinct du A4) : bloc MECeF, trois parts, montant arrêté en lettres.",
    "badge-du-personnel-carte-cr80": "Carte CR80 (85,6 × 54 mm), recto puis verso ; QR = matricule et n° de série seulement ; ni IFU ni RCCM.",
    "planche-de-badges-a4": "Planche A4 de cartes CR80.",
    "facture-d-avoir": "Filigrane « AVOIR », lignes annulées nommées, total négatif calculé.",
    "facture-normalisee": "Trois parts (assureur, non assurée, patient), base MECeF, montant arrêté en lettres.",
    "facture-pro-forma": "Pièce non fiscale : ni bloc MECeF ni identifiant fiscal.",
    "recu-de-paiement": "Détail des prestations réglées et de celles qui restent dues.",
    "engagement-de-paiement": "Échéancier par tranches de 30 jours.",
    "bulletin-de-paie": "Bulletin individuel : rubriques, retenues, net à payer.",
    "journal-de-paie": "Total général calculé depuis les lignes imprimées.",
    "grand-livre": "État de plusieurs pages : en-tête sur la première page, pied et pagination sur toutes.",
    "plan-comptable-syscohada": "État de plusieurs pages (plan de 93 comptes).",
    "bilan": "Feuillet de la liasse (références AD, AI, XB…) : mêmes références et même ordre que le formulaire déposé.",
    "compte-de-resultat": "Feuillet 7/51 de la liasse.",
    "tableau-des-flux-de-tresorerie": "Feuillet 8/51 de la liasse, avec sa ligne de contrôle.",
    "sortie-contre-avis-medical": "Filigrane « Document officiel », trois signatures.",
    "fiche-d-aptitude-medecine-du-travail": "Pièce certifiante de médecine du travail (avis d’aptitude, validité, cachet du médecin du travail).",
    "partographie": "Partogramme coté (alerte à 4 cm, action décalée de 4 h).",
    "dossier-obstetrical": "Le cahier de la parturiente : CPN, partogramme, accouchement, nouveau-né.",
    "selection-liste-filtree-d-un-registre": "Gabarit commun des « Imprimer la sélection » de tous les registres ; rappelle les filtres en force.",
}


def pages_et_taille(chemin):
    d = fitz.open(chemin)
    n = d.page_count
    d.close()
    return n, os.path.getsize(chemin)


def main():
    racine = sys.argv[1] if len(sys.argv) > 1 else "../../presentation"
    ici = os.path.dirname(os.path.abspath(__file__))
    nb = 0
    for d, _, fs in os.walk(racine):
        for f in fs:
            if f.lower().endswith(".pdf") and tamponner(os.path.join(d, f)):
                nb += 1
    print(f"{nb} PDF tamponné(s)")

    couv = json.load(open(os.path.join(racine, "couverture.json"), encoding="utf-8"))
    lignes = couv["specimens"]
    for l in lignes:
        l["pages"], l["octets"] = pages_et_taille(os.path.join(racine, l["fichier"]))
    # classement : par module dans l'ordre du logiciel, puis par document
    lignes.sort(key=lambda l: (ORDRE.index(l["module"]) if l["module"] in ORDRE else 99, l["document"].lower()))
    total = sum(l["octets"] for l in lignes)
    out = []
    out.append("# Index et couverture des spécimens\n")
    out.append("Fichier **engendré** par `apps/poste/tool/specimens/finaliser.py` à partir de `couverture.json` (écrit par `generer_specimens_test.dart`) : ne pas l’éditer à la main.\n")
    out.append(f"**{len(lignes)} spécimens**, {sum(l['pages'] for l in lignes)} pages, {total / 1e6:.1f} Mo de PDF.\n")
    out.append("## Couverture par module\n")
    out.append("| Module | Spécimens |\n|---|---|")
    regroupe = {}
    for l in lignes:
        regroupe.setdefault(MODULES.get(l["module"], l["module"]), []).append(l)
    for nom in dict.fromkeys(MODULES.get(l["module"], l["module"]) for l in lignes):
        out.append(f"| {nom} | {len(regroupe[nom])} |")
    out.append("")
    for nom, ls in regroupe.items():
        out.append(f"## {nom}\n")
        out.append("| Document | Fichier | Pages | Écran source | Rôle | Particularité |")
        out.append("|---|---|---|---|---|---|")
        for l in ls:
            stem = os.path.splitext(os.path.basename(l["fichier"]))[0]
            out.append(f"| {l['document']} | [`{l['fichier']}`]({l['fichier']}) | {l['pages']} | `{l['ecran']}` | {l['role']} | {PARTICULARITES.get(stem, '')} |")
        out.append("")
    np = json.load(open(os.path.join(ici, "non_produits.json"), encoding="utf-8"))
    out.append("## Documents NON produits, et pourquoi\n")
    out.append("| Module | Document | Écran | Raison |\n|---|---|---|---|")
    for x in np:
        out.append(f"| {x['module']} | {x['document']} | `{x['ecran']}` | {x['raison']} |")
    out.append("")
    mg = couv.get("memeGabarit", [])
    if mg:
        out.append("## Éditions qui partagent le gabarit « liste filtrée d’un registre »\n")
        out.append("Un seul spécimen (`transverse/`) les représente ; les éditions suivantes ne diffèrent que par les colonnes du registre :\n")
        for g in mg:
            out.append(f"- {g}")
        out.append("")
    open(os.path.join(racine, "INDEX.md"), "w", encoding="utf-8").write("\n".join(out))
    # README.md : texte du modèle + chiffres + index par module (nom lisible du document, lien, ce qu'il montre de particulier)
    modele = open(os.path.join(ici, "README.modele.md"), encoding="utf-8").read()
    chiffres = f"**{len(lignes)} spécimens** en {len(regroupe)} rubriques, {sum(l['pages'] for l in lignes)} pages, {total / 1e6:.1f} Mo (le plus lourd : {max(lignes, key=lambda l: l['octets'])['fichier']}, {max(l['octets'] for l in lignes) / 1e3:.0f} Ko)."
    idx = []
    for nom, ls in regroupe.items():
        idx.append(f"### {nom}\n")
        for l in ls:
            stem = os.path.splitext(os.path.basename(l["fichier"]))[0]
            note = PARTICULARITES.get(stem, "")
            plus = f" — {note}" if note else ""
            idx.append(f"- [{l['document']}]({l['fichier']}) ({l['pages']} p.){plus}")
        idx.append("")
    open(os.path.join(racine, "README.md"), "w", encoding="utf-8").write(modele.replace("{{CHIFFRES}}", chiffres).replace("{{INDEX_PAR_MODULE}}", "\n".join(idx)).replace("{{NB_NON_PRODUITS}}", str(len(np))))
    json.dump(couv, open(os.path.join(racine, "couverture.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"INDEX.md : {len(lignes)} spécimens, {total / 1e6:.1f} Mo")


if __name__ == "__main__":
    main()
