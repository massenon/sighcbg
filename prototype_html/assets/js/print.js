/* =============================================================================
 * SIGH-CBG — Moteur d'impression des états officiels
 * -----------------------------------------------------------------------------
 * CDCT §4.2 / §21 — draf1 §10.14 « Modèle officiel des documents ».
 * Tout état édité reprend automatiquement le papier à en-tête de la clinique :
 * logo, dénomination, BP, téléphones, autorisation d'ouverture, IFU, RCCM,
 * e-mail ; et un pied de page normalisé : pagination, date/heure d'impression,
 * utilisateur générateur et identifiant unique du document.
 *
 * Parcours imposé : prévisualiser → imprimer / exporter PDF → archiver.
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core, U = global.SIGH.ui;
  var el = C.el, B = C.BRAND;
  var compteur = 0;

  /* --- Racine d'impression ------------------------------------------------ */
  function root() {
    var r = document.getElementById('print-root');
    if (!r) {
      r = el('div#print-root');
      document.body.appendChild(r);
    }
    return r;
  }

  /** Chemin du logo, ajusté à la profondeur de la page courante. */
  function logoSrc() {
    var base = document.documentElement.getAttribute('data-root') || '';
    return base + B.logo;
  }

  /* ==========================================================================
   * EN-TÊTE OFFICIEL — le papier à en-tête BAGUIDI (Instructions.txt)
   * --------------------------------------------------------------------------
   * TROIS ZONES en tableau : gauche = logo circulaire (~2,5 cm) avec le slogan
   * en cursive ROUGE juste dessous ; centre = dénomination en rouge/noir très
   * lisible + sous-titre ; droite = adresse, téléphones, IFU, e-mail.
   * Sous l'en-tête, DOUBLE LIGNE FINE (rouge puis bleue) séparant l'en-tête du
   * corps de la pièce. RCCM et autorisation NON FOURNIS : la mention reste
   * vide et le dit — aucune donnée officielle ne s'invente.
   * ======================================================================== */
  function entete() {
    var head = el('header.print-entete.pb-1');
    var table = el('table.w-full.border-collapse');
    var tr = el('tr.align-middle');

    /* Zone gauche — logo circulaire + slogan cursive rouge. */
    var tdG = el('td.w-\\[24\\%\\].pr-2.text-center.align-middle');
    tdG.appendChild(el('img.mx-auto.h-\\[2\\.4cm\\].w-\\[2\\.4cm\\].rounded-full.object-contain', {
      src: logoSrc(), alt: 'Logo ' + B.sigle,
      onerror: function () { this.style.visibility = 'hidden'; },
    }));
    tdG.appendChild(el('p.mt-1.font-slogan.text-\\[11px\\].leading-tight.text-coeur-500', { text: B.slogan }));
    tr.appendChild(tdG);

    /* Zone centrale — dénomination rouge/noir + sous-titre. */
    var tdC = el('td.px-2.text-center.align-middle');
    tdC.appendChild(el('p.font-heading.text-\\[19px\\].font-bold.leading-tight.tracking-tight.text-coeur-500', { text: B.nom }));
    tdC.appendChild(el('p.mt-0\\.5.text-\\[10px\\].font-semibold.uppercase.leading-snug.tracking-wide.text-anthracite-900', { text: B.sousTitre }));
    tr.appendChild(tdC);

    /* Zone droite — coordonnées et mentions légales. */
    var tdD = el('td.w-\\[30\\%\\].pl-2.text-right.align-middle');
    tdD.appendChild(el('p.text-\\[9px\\].leading-snug.text-slate-700', { text: B.bp }));
    tdD.appendChild(el('p.text-\\[9px\\].leading-snug.text-slate-700', { text: 'Téléphones : ' + B.telephones.join(' / ') }));
    tdD.appendChild(el('p.text-\\[9px\\].font-semibold.leading-snug.text-slate-800', {
      text: 'IFU : ' + B.ifu + (B.ifuDate ? ' du ' + B.ifuDate : ''),
    }));
    tdD.appendChild(el('p.text-\\[9px\\].leading-snug.text-slate-700', { text: 'E-mail : ' + B.email }));
    tdD.appendChild(el('p.text-\\[9px\\].leading-snug.text-slate-700', { text: B.adresse + ' — ' + B.pays }));
    if (B.rccm) {
      tdD.appendChild(el('p.text-\\[9px\\].leading-snug.text-slate-700', { text: 'RCCM : ' + B.rccm }));
    } else {
      tdD.appendChild(el('p.text-\\[8px\\].italic.leading-snug.text-slate-500', { text: 'RCCM : à compléter par la Direction' }));
    }
    tr.appendChild(tdD);

    table.appendChild(tr);
    head.appendChild(table);

    /* Double ligne fine — rouge puis bleue. */
    var sep = el('div.mt-1');
    sep.appendChild(el('div.h-\\[2px\\].w-full.bg-coeur-500'));
    sep.appendChild(el('div.mt-\\[2px\\].h-\\[2px\\].w-full.bg-sante-600'));
    head.appendChild(sep);
    return head;
  }

  /* ==========================================================================
   * PIED DE PAGE NORMALISÉ
   * ======================================================================== */
  function pied(ref) {
    var f = el('footer.print-pied.mt-6.border-t.border-slate-300.pt-2');
    var row = el('div.flex.items-end.justify-between.gap-4.text-\\[8px\\].text-slate-500');
    row.appendChild(el('div', null, [
      el('p', { text: B.nom + ' — IFU ' + B.ifu + (B.rccm ? ' — RCCM ' + B.rccm : ' — RCCM : à compléter par la Direction') }),
      el('p', { text: 'Document généré par ' + global.SIGH.store.currentUser() + ' le ' + C.dateHeure(new Date()) }),
    ]));
    row.appendChild(el('div.text-right', null, [
      el('p.font-mono', { text: 'Réf. document : ' + ref }),
      el('p', { text: 'Édité depuis le SIGH-' + B.sigle }),
    ]));
    f.appendChild(row);
    return f;
  }

  /* ==========================================================================
   * BLOCS RÉUTILISABLES
   * ======================================================================== */
  /** Bloc de signatures — CDCT §10.4 (sortie : patient + infirmier + gardien). */
  function signatures(liste) {
    var grid = el('div.mt-8.grid.gap-6', { class: 'grid-cols-' + Math.min(liste.length, 4) });
    liste.forEach(function (s) {
      var box = el('div.text-center');
      box.appendChild(el('p.text-\\[10px\\].font-semibold.text-slate-700', { text: s.role }));
      if (s.nom) box.appendChild(el('p.text-\\[9px\\].text-slate-500', { text: s.nom }));
      box.appendChild(el('div.mx-auto.mt-10.w-full.border-b.border-dotted.border-slate-400'));
      box.appendChild(el('p.mt-1.text-\\[8px\\].text-slate-400', { text: s.mention || 'Signature' }));
      grid.appendChild(box);
    });
    return grid;
  }

  /** Tableau normalisé pour les états. */
  function tableau(colonnes, lignes, options) {
    var o = options || {};
    var t = el('table.w-full.border-collapse.text-\\[10px\\]');
    var thead = el('thead'), htr = el('tr');
    colonnes.forEach(function (c) {
      htr.appendChild(el('th.border.border-slate-400.bg-slate-100.px-2.py-1.text-left.font-semibold.text-slate-800', {
        class: c.align === 'right' ? 'text-right' : '', text: c.label,
      }));
    });
    thead.appendChild(htr); t.appendChild(thead);
    var tb = el('tbody');
    lignes.forEach(function (r) {
      var tr = el('tr');
      colonnes.forEach(function (c) {
        var v = typeof c.value === 'function' ? c.value(r) : r[c.key];
        tr.appendChild(el('td.border.border-slate-300.px-2.py-1.align-top', {
          class: c.align === 'right' ? 'text-right num' : '',
          text: v == null || v === '' ? '' : String(v),
        }));
      });
      tb.appendChild(tr);
    });
    t.appendChild(tb);
    /* Une colonne qui déclare `somme` fait totaliser les lignes RÉELLEMENT
       imprimées. C'est le seul moyen d'empêcher un total de diverger de son
       tableau : la somme n'est pas transmise, elle est refaite. */
    function sommeDe(c) {
      if (!c.somme) return null;
      var lire = typeof c.somme === 'function' ? c.somme
        : function (r) { return r[c.key]; };
      return lignes.reduce(function (n, r) {
        var v = lire(r);
        return n + (typeof v === 'number' && isFinite(v) ? v : 0);
      }, 0);
    }

    var colonnesSommees = colonnes.filter(function (c) { return c.somme; });
    /* `total: true` suffit dès qu'une colonne sait se totaliser : l'appelant
       n'a plus à recopier des montants qu'il aurait pu se tromper à calculer. */
    var afficherTotal = o.total === true ? colonnesSommees.length > 0 : !!o.total;

    if (afficherTotal) {
      var tf = el('tfoot'), ftr = el('tr');
      colonnes.forEach(function (c, i) {
        var texte = '';
        if (i === 0) {
          texte = o.totalLabel || 'TOTAL';
        } else if (c.somme) {
          var v = sommeDe(c);
          texte = c.formatTotal ? c.formatTotal(v) : C.money(v, false);
        } else if (o.total && o.total !== true && o.total[c.key] != null) {
          /* Mention de pied qui n'est pas une somme : solde reporté, renvoi
             réglementaire. Elle reste possible et prime sur le vide. */
          texte = o.total[c.key];
        }
        ftr.appendChild(el('td.border.border-slate-400.bg-slate-50.px-2.py-1.font-bold', {
          class: c.align === 'right' ? 'text-right num' : '',
          text: texte,
        }));
      });
      tf.appendChild(ftr); t.appendChild(tf);
    }
    return t;
  }

  /** Cartouche « informations » à deux colonnes. */
  function cartouche(pairs) {
    var box = el('div.mb-4.grid.grid-cols-2.gap-x-8.gap-y-1.rounded.border.border-slate-300.bg-slate-50.px-3.py-2.text-\\[10px\\]');
    pairs.forEach(function (p) {
      if (!p) return;
      var row = el('div.flex.gap-2');
      row.appendChild(el('span.shrink-0.font-semibold.text-slate-600', { text: p[0] + ' :' }));
      row.appendChild(el('span.text-slate-800', { text: p[1] == null || p[1] === '' ? '—' : String(p[1]) }));
      box.appendChild(row);
    });
    return box;
  }

  /* ==========================================================================
   * COMPOSITION ET PRÉVISUALISATION DE L'ÉTAT
   * ======================================================================== */
  /**
   * etat({ titre, sousTitre, contenu, cartouche, signatures, filigrane, lieuDate })
   * Affiche la prévisualisation ; l'impression (ou « Enregistrer en PDF » du
   * navigateur) est déclenchée depuis la barre d'action.
   */
  function etat(options) {
    var o = Object.assign({
      titre: 'État', sousTitre: null, contenu: null, cartouche: null,
      signatures: null, filigrane: null, lieuDate: true, archive: true,
    }, options);

    compteur++;
    var ref = B.sigle + '-' + C.iso(new Date()).replace(/-/g, '') + '-' + C.pad(compteur, 4);

    /* --- Feuille A4 --- */
    var sheet = el('article.print-sheet.relative.mx-auto.bg-white.text-slate-900', {
      style: 'width:210mm;min-height:297mm;padding:12mm;box-sizing:border-box;',
    });

    if (o.filigrane) {
      sheet.appendChild(el('div.pointer-events-none.absolute.inset-0.grid.place-items-center', null,
        el('span.select-none.text-\\[70px\\].font-bold.uppercase.tracking-widest.text-slate-900\\/5', {
          style: 'transform:rotate(-35deg);', text: o.filigrane,
        })));
    }

    var inner = el('div.relative.flex.min-h-full.flex-col');
    inner.appendChild(entete());

    var titleBlock = el('div.my-4.text-center');
    titleBlock.appendChild(el('h1.inline-block.border-b-2.border-navy-900.px-6.pb-1.text-\\[15px\\].font-bold.uppercase.tracking-wide.text-navy-950', { text: o.titre }));
    if (o.sousTitre) titleBlock.appendChild(el('p.mt-1.text-\\[10px\\].text-slate-600', { text: o.sousTitre }));
    inner.appendChild(titleBlock);

    if (o.cartouche) inner.appendChild(cartouche(o.cartouche));

    var body = el('div.flex-1.text-\\[10px\\].leading-relaxed');
    C.append(body, o.contenu);
    inner.appendChild(body);

    if (o.lieuDate) {
      inner.appendChild(el('p.mt-6.text-right.text-\\[10px\\].italic.text-slate-700', {
        text: 'Fait à Parakou, le ' + C.dateLong(new Date()),
      }));
    }
    if (o.signatures) inner.appendChild(signatures(o.signatures));
    inner.appendChild(pied(ref));
    sheet.appendChild(inner);

    return afficher(sheet, o.titre, ref, false, o.archive);
  }

  /* --------------------------------------------------------------------------
   * Prévisualisation commune au A4 et au rouleau : la feuille vit dans
   * #print-root — seul élément imprimable — et s'affiche dans une surcouche.
   * ----------------------------------------------------------------------- */
  function afficher(sheet, titre, ref, etroit, archivable) {
    /* --- Prévisualisation --- */
    var host = root();
    C.clear(host);
    host.appendChild(sheet);

    var overlay = el('div.print-chrome.fixed.inset-0.z-\\[70\\].flex.flex-col.bg-slate-800\\/80.no-print');
    var bar = el('div.flex.flex-wrap.items-center.gap-2.border-b.border-slate-700.bg-slate-900.px-4.py-2.5');
    bar.appendChild(el('span.mr-auto.flex.items-center.gap-2.text-sm.font-medium.text-white', null, [
      C.icon('file-text', 'h-4 w-4'), titre,
    ]));
    bar.appendChild(el('span.hidden.text-xs.text-slate-400.sm\\:block', { text: 'Réf. ' + ref }));
    bar.appendChild(el('button.btn.btn-sm.btn-secondary', {
      type: 'button',
      onclick: function () { U.exportCSV ? imprimer() : imprimer(); },
    }, [C.icon('printer', 'h-4 w-4'), 'Imprimer / Enregistrer en PDF']));
    if (archivable !== false) {
      bar.appendChild(el('button.btn.btn-sm.btn-secondary', {
        type: 'button',
        onclick: function () {
          global.SIGH.store.log('Impression', 'RAP', 'Document', ref, null, { titre: titre });
          U.toast('Document archivé dans la GED.', { type: 'success', detail: 'Réf. ' + ref });
        },
      }, [C.icon('archive', 'h-4 w-4'), 'Archiver']));
    }
    bar.appendChild(el('button.btn.btn-sm.btn-primary', { type: 'button', onclick: fermer }, [C.icon('x', 'h-4 w-4'), 'Fermer']));
    overlay.appendChild(bar);

    var scroll = el('div.flex-1.overflow-auto.p-6');
    var frame = el('div.mx-auto.shadow-pop', { style: 'width:' + (etroit ? '80mm' : '210mm') + ';' });
    scroll.appendChild(frame);
    overlay.appendChild(scroll);
    document.body.appendChild(overlay);
    document.body.style.overflow = 'hidden';

    /* La feuille vit dans #print-root (imprimable) et est affichée dans l'overlay. */
    frame.appendChild(sheet);
    U.icons(overlay);

    function imprimer() {
      /* On replace la feuille dans #print-root le temps de l'impression. */
      host.appendChild(sheet);
      document.body.classList.add('printing');
      var restore = function () {
        document.body.classList.remove('printing');
        frame.appendChild(sheet);
        global.removeEventListener('afterprint', restore);
      };
      global.addEventListener('afterprint', restore);
      global.print();
      setTimeout(restore, 1500);
    }
    function fermer() {
      overlay.remove();
      C.clear(host);
      document.body.style.overflow = '';
    }

    document.addEventListener('keydown', function esc(e) {
      if (e.key === 'Escape' && document.body.contains(overlay)) { fermer(); document.removeEventListener('keydown', esc); }
    });

    return { ref: ref, imprimer: imprimer, fermer: fermer, sheet: sheet };
  }

  /* ==========================================================================
   * TICKET DE CAISSE — gabarit rouleau
   * --------------------------------------------------------------------------
   * Relevé sur le ticket n° 22118 réellement émis par la clinique : rouleau
   * étroit, bloc MECeF, OPÉRATEUR, TYPE VENTE, ASSUREUR, ASSURÉ, lignes,
   * montant total, montant en lettres, puis PART ASSUREUR / PART ASSURÉ.
   * Le A4 ne convient pas ici : la caisse imprime sur une bande de 80 mm.
   * ======================================================================== */
  function ticket(o) {
    o = o || {};
    compteur++;
    var ref = B.sigle + '-' + C.iso(new Date()).replace(/-/g, '') + '-' + C.pad(compteur, 4);

    var sheet = el('article.print-sheet.mx-auto.bg-white.text-slate-900', {
      style: 'width:80mm;padding:4mm;box-sizing:border-box;font-family:ui-monospace,Menlo,Consolas,monospace;',
    });

    function ligneTexte(texte, classe) {
      return el('p', { class: classe || 'text-[9px] leading-snug', text: texte });
    }
    function separateur() {
      return el('p.my-1.text-\\[9px\\].leading-none.text-slate-400', { text: '--------------------------------' });
    }
    function paire(g, d, gras) {
      return el('div.flex.justify-between.gap-2', { class: gras ? 'font-bold' : '' }, [
        el('span.text-\\[9px\\]', { text: g }),
        el('span.text-\\[9px\\].text-right', { text: d }),
      ]);
    }

    /* En-tête de la clinique, resserré */
    sheet.appendChild(el('p.text-center.text-\\[11px\\].font-bold.leading-tight', { text: B.nom }));
    sheet.appendChild(ligneTexte(B.bp, 'text-[8px] text-center leading-snug'));
    sheet.appendChild(ligneTexte('TÉL. ' + B.telephones.join(' / '), 'text-[8px] text-center leading-snug'));
    sheet.appendChild(ligneTexte('IFU ' + B.ifu, 'text-[8px] text-center leading-snug'));
    sheet.appendChild(ligneTexte(B.rccm ? 'RCCM ' + B.rccm : 'RCCM : à compléter par la Direction',
      'text-[8px] text-center leading-snug'));
    sheet.appendChild(separateur());

    /* Bloc MECeF — structure du ticket réel */
    if (o.mecef) {
      sheet.appendChild(el('div.flex.items-start.gap-2', null, [
        el('div.shrink-0.border.border-slate-800', {
          style: 'width:18mm;height:18mm;background:repeating-conic-gradient(#0f172a 0% 25%, #ffffff 0% 50%) 0 0/3mm 3mm;',
          title: 'Code QR MECeF',
        }),
        el('div.min-w-0.flex-1', null, [
          ligneTexte('NIM : ' + (o.mecef.nim || '—'), 'text-[8px] leading-snug'),
          ligneTexte('CODE DGI : ' + (o.mecef.code || '—'), 'text-[8px] leading-snug break-all'),
          ligneTexte('CPT : ' + (o.mecef.compteurs || '—'), 'text-[8px] leading-snug'),
          ligneTexte('HEURE : ' + (o.mecef.heure || C.heure(new Date().toISOString())), 'text-[8px] leading-snug'),
        ]),
      ]));
      sheet.appendChild(separateur());
    }

    sheet.appendChild(paire('OPÉRATEUR', o.operateur || S().currentUser()));
    sheet.appendChild(paire('TYPE VENTE', o.typeVente || 'COMPTANT'));
    if (o.assureur) sheet.appendChild(paire('ASSUREUR', o.assureur));
    if (o.assure) sheet.appendChild(paire('ASSURÉ', o.assure));
    /* L'opération de caisse est DISSOCIÉE du dossier patient : une vente au
       comptoir — un carnet, un certificat — n'oblige pas à ouvrir un dossier.
       La pièce le dit plutôt que de laisser une ligne vide, qui se lirait
       comme un oubli de saisie. */
    sheet.appendChild(paire('DOSSIER', o.dossier || 'VENTE AU COMPTOIR — sans dossier'));
    sheet.appendChild(paire('N° PIÈCE', o.numero || ref));
    sheet.appendChild(paire('DATE', C.dateFR(o.date || new Date()) + ' ' + C.heure(o.date || new Date().toISOString())));
    sheet.appendChild(separateur());

    (o.lignes || []).forEach(function (l) {
      sheet.appendChild(ligneTexte(l.designation, 'text-[9px] leading-snug'));
      sheet.appendChild(paire(
        '  ' + C.num(l.quantite) + ' x ' + C.money(l.prixUnitaire, false),
        C.money(l.montant, false)));
    });
    sheet.appendChild(separateur());

    sheet.appendChild(paire('MONTANT TOTAL', C.money(o.total || 0, false), true));
    if (o.remise) sheet.appendChild(paire('REMISE', '- ' + C.money(o.remise, false)));
    if (o.partAssureur) sheet.appendChild(paire('PART ASSUREUR', C.money(o.partAssureur, false)));
    /* La PART NON ASSURÉE se distingue de la part assuré : elle porte les
       lignes qu'AUCUNE compagnie ne couvre. C'est elle qui explique au guichet
       pourquoi un assuré règle intégralement certaines prestations. */
    if (o.partNonAssuree) {
      sheet.appendChild(paire('DONT PART NON ASSURÉE', C.money(o.partNonAssuree, false)));
    }
    sheet.appendChild(paire(o.assureur ? 'PART ASSURÉ' : 'NET À PAYER', C.money(o.partPatient || 0, false), true));
    if (o.regle != null) sheet.appendChild(paire('RÉGLÉ', C.money(o.regle, false)));
    if (o.rendu) sheet.appendChild(paire('RENDU', C.money(o.rendu, false)));
    /* Le TOTAL DÛ est ce qui reste après le versement. Sur un règlement
       partiel — que la caisse pratique — son absence laissait le patient
       repartir sans savoir ce qu'il devait encore. */
    var duRestant = o.reste != null ? o.reste
      : (o.regle != null ? Math.max(0, (o.partPatient || 0) - o.regle) : null);
    if (duRestant != null) {
      sheet.appendChild(paire('TOTAL DÛ', C.money(duRestant, false), true));
    }
    /* La base MECeF est portée sur la pièce : le cahier de charge exige que la
       facture normalisée ne porte QUE ce que le patient règle — ni la part
       assureur, ni les remises. L'imprimer permet de le vérifier sans ouvrir
       le logiciel. */
    if (o.baseMecef != null) {
      sheet.appendChild(paire('BASE MECeF', C.money(o.baseMecef, false)));
    }

    sheet.appendChild(separateur());
    sheet.appendChild(ligneTexte(B.formuleArrete + ' :', 'text-[8px] leading-snug'));
    sheet.appendChild(ligneTexte(C.montantEnLettres(o.partPatient || 0), 'text-[8px] font-semibold leading-snug'));
    sheet.appendChild(separateur());
    sheet.appendChild(ligneTexte(B.formulePolitesse, 'text-[9px] font-bold text-center leading-snug'));
    sheet.appendChild(ligneTexte('Réf. ' + ref, 'text-[7px] text-center text-slate-400 mt-1'));

    afficher(sheet, o.titre || 'Ticket de caisse', ref, true);
    return ref;
  }

  function S() { return global.SIGH.store; }

  global.SIGH.print = {
    etat: etat, entete: entete, pied: pied, ticket: ticket,
    tableau: tableau, cartouche: cartouche, signatures: signatures,
  };
})(window);
