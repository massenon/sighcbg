/* =============================================================================
 * SIGH-CBG — Trousse à outils des écrans
 * -----------------------------------------------------------------------------
 * Fabrique les deux gabarits qui structurent la quasi-totalité du prototype :
 *   kit.crud()  — écran de gestion : onglets, KPI, tableau, création, édition,
 *                 archivage annulable, duplication, fiche détaillée, impression.
 *   kit.dash()  — tableau de bord : KPI, graphiques, cartes, actions rapides.
 * Conformité transverse : RG-12 (journalisation) et RG-14 (archivage logique)
 * sont assurées par le magasin de données ; l'annulation est proposée sur
 * chaque mutation via les toasts.
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core, U = global.SIGH.ui, S = global.SIGH.store,
      P = global.SIGH.print, G = global.SIGH.charts, N = global.SIGH.nav;
  var el = C.el;

  function A() { return global.SIGH.app; }

  /* --- Boutons usuels ------------------------------------------------------ */
  function btn(label, opts) {
    opts = opts || {};
    var b = el('button.btn', {
      type: 'button',
      class: (opts.variant ? 'btn-' + opts.variant : 'btn-secondary') + (opts.size ? ' btn-' + opts.size : ''),
      onclick: opts.onclick, title: opts.title,
    });
    if (opts.icon) b.appendChild(C.icon(opts.icon, 'h-4 w-4'));
    if (label) b.appendChild(document.createTextNode(label));
    return b;
  }
  function iconBtn(icon, title, onclick, variant) {
    return el('button.btn.btn-icon.btn-sm', {
      type: 'button', title: title, 'aria-label': title, onclick: onclick,
      class: variant ? 'btn-' + variant : 'btn-ghost',
    }, C.icon(icon, 'h-4 w-4'));
  }
  function lien(id, label, opts) {
    opts = opts || {};
    return el('a.btn', {
      href: A().href(id),
      class: (opts.variant ? 'btn-' + opts.variant : 'btn-secondary') + (opts.size ? ' btn-' + opts.size : ''),
    }, [opts.icon ? C.icon(opts.icon, 'h-4 w-4') : null, label]);
  }

  /* --- Mise en page -------------------------------------------------------- */
  function section(title, subtitle) {
    var d = el('div.mb-3.mt-6');
    d.appendChild(el('h2.text-sm.font-semibold.text-slate-900', { text: title }));
    if (subtitle != null && subtitle !== false) {
      /* DEUX FORMES : une chaîne est un sous-titre ; un NŒUD est le CONTENU
         de la section. Une trentaine d'appelants passent un nœud (miniTable,
         paragraphe), et `{text: nœud}` l'avalait en « [object HTMLElement] » —
         le tiroir montrait son titre et perdait son tableau, sans un mot.
         C'est la sonde du scénario 46 qui l'a pris sur le fait. */
      if (typeof subtitle === 'string' || typeof subtitle === 'number') {
        d.appendChild(el('p.text-xs.text-slate-500', { text: subtitle }));
      } else {
        d.appendChild(subtitle);
      }
    }
    return d;
  }
  function grid(cols, children) {
    return el('div.grid.gap-4', { class: cols }, children);
  }
  function row(children) { return el('div.flex.flex-wrap.items-center.gap-2', null, children); }

  /** Bandeau d'information rattaché à une règle de gestion ou à un document. */
  function note(texte, opts) {
    opts = opts || {};
    var tone = opts.tone || 'info';
    var d = el('div.flex.items-start.gap-2.rounded-lg.border.px-3.py-2', {
      class: 'border-' + tone + '-200 bg-' + tone + '-50',
    });
    d.appendChild(el('span.shrink-0', { class: 'text-' + tone + '-600' }, C.icon(opts.icon || 'info', 'h-4 w-4')));
    /* LA NOTE ÉCHAPPE D'ABORD, PUIS RÉACTIVE UN SOUS-ENSEMBLE FERMÉ de balises
       de mise en forme — le mécanisme déjà posé sur les modales. Le texte
       d'une note paraît statique, mais plusieurs y interpolent une donnée
       saisie : le libellé d'un rôle, que l'administrateur renomme depuis
       `m14-roles`, le nom d'un patient, un motif d'archivage. C'est l'ORDRE
       qui rend la fonction sûre, et toutes les balises réellement employées
       dans les notes du prototype — strong, em, br, code — sont dans
       l'ensemble autorisé. */
    d.appendChild(el('p.text-xs', { class: 'text-' + tone + '-900', html: U.texteEnrichi(texte) }));
    return d;
  }

  /** Mention de provenance : rattache un écran à son document de cadrage. */
  function source(texte) {
    return el('p.mt-2.flex.items-center.gap-1\\.5.text-xs.text-slate-400', null, [
      C.icon('file-check-2', 'h-3.5 w-3.5'),
      el('span', { text: 'Source : ' + texte }),
    ]);
  }

  /* ==========================================================================
   * GABARIT « ÉCRAN DE GESTION »
   * -------------------------------------------------------------------------
   * config = {
   *   collection : nom de la collection du magasin
   *   entite     : libellé au singulier (« patient »)
   *   module     : code module (M1…)
   *   columns    : colonnes du tableau (cf. ui.dataTable)
   *   fields     : champs du formulaire de création / édition
   *   filters    : filtres du tableau
   *   kpis(rows) : blocs KPI calculés
   *   detail(r)  : contenu de la fiche détaillée (drawer)
   *   etat(r)    : état imprimable d'un enregistrement
   *   onCreate   : valeurs par défaut à la création
   *   extraTabs  : onglets additionnels
   *   readonly   : masque les actions de modification
   * }
   * ======================================================================== */
  /* ==========================================================================
   * DROITS DU PROFIL SUR L'ÉCRAN COURANT
   * --------------------------------------------------------------------------
   * La matrice RBAC ne décide pas seulement des écrans VISIBLES : elle décide
   * aussi de ce qu'on peut y FAIRE. Plutôt que de protéger chaque bouton sur
   * chaque écran — cent trente-cinq fois la même ligne, et autant d'oublis —
   * les fabriques du kit consultent ce point unique.
   *
   *   editer  absent → pas de bouton « Nouveau », pas de crayon ;
   *   annuler absent → pas d'archivage ;
   *   les deux absents → l'écran le DIT, il ne se contente pas de masquer.
   * ======================================================================== */
  function droits(code) {
    var app = global.SIGH && global.SIGH.app;
    if (app && typeof app.droits === 'function') return app.droits(code);
    return { voir: true, editer: true, annuler: true, lectureSeule: false };
  }

  /* ==========================================================================
   * UNE COMMANDE D'ÉCRITURE SE DÉCLARE COMME TELLE.
   * --------------------------------------------------------------------------
   * `crud`, `creer` et `actionsLigne` consultent déjà les droits ; les écrans
   * construits à la main, non — et l'audit en a relevé trente-quatre. Un
   * assistant de direction se voyait offrir « Nouvelle commande » et
   * « Valider (DA) », une aide-soignante « Nouvelle ordonnance », un
   * technicien d'échographie « Enregistrer et prescrire ».
   *
   * On ne devine pas ce qui est une écriture à partir du libellé : une
   * protection qui dépend d'un mot change de sens le jour où quelqu'un
   * renomme un bouton. C'est l'AUTEUR qui le déclare, en appelant `commande`
   * au lieu de `btn`.
   *
   * La commande refusée est ABSENTE, non grisée — un bouton grisé invite à
   * chercher pourquoi, un bouton absent dit que ce n'est pas ici que cela se
   * règle. `C.append` ignore les `null` : elle peut donc rester en place dans
   * un tableau d'actions sans que l'appelant ait à filtrer.
   * ======================================================================== */
  function commande(label, opts) {
    var o = opts || {};
    var d = droits(o.moduleCode);
    var accorde = o.droit === 'annuler' ? d.annuler : d.editer;
    return accorde ? btn(label, o) : null;
  }

  /** Même règle pour une commande rendue par une icône seule. */
  function commandeIcone(icone, titre, onclick, opts) {
    var o = typeof opts === 'string' ? { variant: opts } : (opts || {});
    var d = droits(o.moduleCode);
    var accorde = o.droit === 'annuler' ? d.annuler : d.editer;
    return accorde ? iconBtn(icone, titre, onclick, o.variant) : null;
  }

  /** Bandeau affiché quand le profil n'a qu'un droit de lecture sur l'écran. */
  function bandeauLectureSeule(d) {
    var session = S.session() || {};
    var role = N.ROLES[session.role] ? N.ROLES[session.role].label : session.role;
    return note('<strong>Lecture seule</strong> — le profil « ' + role + ' » consulte cet écran sans '
      + 'pouvoir y créer, modifier ni archiver. Ce périmètre est fixé par la matrice des droits '
      + 'd’accès (écran <em>Rôles &amp; permissions</em>) et non par l’écran lui-même.',
    { tone: 'warning', icon: 'lock' });
  }

  function crud(config) {
    var cfg = Object.assign({
      entite: 'enregistrement', entiteP: null, module: '—',
      columns: [], fields: [], filters: [], readonly: false,
      pageSize: 12, selectable: true,
    }, config);
    cfg.entiteP = cfg.entiteP || cfg.entite + 's';

    return function (root) {
      var col = S.collection(cfg.collection, { module: cfg.module, entite: cfg.entite });
      var host = el('div.space-y-4');
      var tableRef = { current: null };
      /* Les droits du profil sur le module de cet écran. Le readonly déclaré
         par l'écran l'emporte toujours : une règle métier prime sur un droit. */
      var D_ = droits(cfg.module);
      var peutEditer = !cfg.readonly && D_.editer;
      var peutAnnuler = !cfg.readonly && D_.annuler;

      function refresh() {
        if (tableRef.current) tableRef.current.refresh();
        if (kpiHost) renderKpis();
      }

      /* Une annulation doit être VISIBLE : le magasin restaure la donnée, mais
         c'est ici que la vue est réaffichée. Sans cette enveloppe, l'utilisateur
         cliquerait « Annuler » sans rien voir revenir dans le tableau. */
      function annulable(undo) {
        return function () { undo(); refresh(); };
      }

      /* --- Formulaire de création / édition ------------------------------- */
      function openForm(record) {
        var isEdit = !!record;
        var f = U.form(typeof cfg.fields === 'function' ? cfg.fields(record) : cfg.fields, record || (cfg.onCreate ? cfg.onCreate() : {}));
        var m = U.modal({
          title: (isEdit ? 'Modifier ' : 'Nouveau ') + (isEdit ? 'l’enregistrement' : cfg.entite),
          subtitle: isEdit ? (record.code || record.reference || record.numero || record.id) : 'Les champs marqués d’un astérisque sont obligatoires.',
          size: cfg.formSize || 'lg',
          body: f,
          footer: [
            btn('Annuler', { onclick: function () { m.close(); } }),
            btn(isEdit ? 'Enregistrer' : 'Créer', {
              variant: 'primary', icon: isEdit ? 'save' : 'plus',
              onclick: function () {
                var values = f.collect();
                if (!values) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                if (cfg.beforeSave) {
                  var err = cfg.beforeSave(values, record);
                  if (err) { U.toast(err, { type: 'error' }); return; }
                }
                if (cfg.transform) values = cfg.transform(values, record);
                var res = isEdit ? col.update(record.id, values) : col.insert(values);
                m.close(); refresh();
                U.toast(isEdit ? 'Modifications enregistrées.' : 'Nouveau ' + cfg.entite + ' créé.', {
                  type: 'success', undo: annulable(res.undo),
                  detail: res.record.code || res.record.reference || res.record.numero || null,
                });
              },
            }),
          ],
        });
      }

      /* --- Archivage annulable (RG-14) ------------------------------------- */
      function askArchive(record) {
        U.confirm({
          title: 'Archiver cet enregistrement ?',
          message: 'L’enregistrement ne sera pas supprimé : il est archivé et reste consultable dans l’onglet « Archivés ». '
            + 'L’opération est journalisée et peut être annulée.',
          confirmLabel: 'Archiver', danger: true, requireMotif: true,
        }).then(function (r) {
          if (!r) return;
          var res = col.archive(record.id, r.motif);
          refresh();
          U.toast('Enregistrement archivé.', { type: 'success', undo: annulable(res.undo), undoMessage: 'Archivage annulé.' });
        });
      }

      /* --- Fiche détaillée --------------------------------------------------*/
      function openDetail(record) {
        var body = cfg.detail ? cfg.detail(record, { refresh: refresh, edit: function () { openForm(record); } })
          : U.descList(Object.keys(record).filter(function (k) { return k[0] !== '_'; })
            .map(function (k) { return [k, record[k]]; }));
        var footer = [];
        if (cfg.etat) footer.push(btn('Imprimer', { icon: 'printer', onclick: function () { cfg.etat(record); } }));
        if (peutEditer) footer.push(btn('Modifier', { variant: 'primary', icon: 'pencil', onclick: function () { d.close(); openForm(record); } }));
        /* Le pied de la fiche porte AUSSI l'archivage (Bug 10 des Instructions) :
           consulter puis devoir refermer pour retrouver la ligne et son icône
           faisait faire le tour de l'écran pour un geste. Même garde que
           partout : la commande est ABSENTE sans le droit, jamais grisée. */
        if (peutAnnuler) footer.push(btn('Archiver', {
          variant: 'danger', icon: 'archive',
          onclick: function () { d.close(); askArchive(record); },
        }));
        var d = U.drawer({
          title: record.nomComplet || record.designation || record.libelle || record.patient || record.code || record.reference || record.numero || 'Détail',
          subtitle: cfg.detailSubtitle ? cfg.detailSubtitle(record) : (record.code || record.reference || record.numero || ''),
          body: body, footer: footer.length ? footer : null,
          width: cfg.drawerWidth || 'max-w-2xl',
        });
        return d;
      }

      /* --- KPI --------------------------------------------------------------*/
      var kpiHost = cfg.kpis ? el('div') : null;
      function renderKpis() {
        C.clear(kpiHost);
        try {
          var specs = cfg.kpis(col.active(), col);
          if (specs && specs.length) kpiHost.appendChild(U.kpiGrid(specs, cfg.kpiCols));
        } catch (e) { console.error('[SIGH] KPI ' + cfg.collection + ' :', e); }
        U.icons(kpiHost);
      }
      /* Une restriction s’annonce : masquer sans le dire ferait croire à une
         panne. Le bandeau nomme le profil et renvoie à la matrice des droits. */
      if (!cfg.readonly && D_.lectureSeule) host.appendChild(bandeauLectureSeule(D_));
      if (kpiHost) { renderKpis(); host.appendChild(kpiHost); }

      if (cfg.intro) host.appendChild(cfg.intro());

      /* --- Tableau ----------------------------------------------------------*/
      function makeTable(rowsFn, archived) {
        var columns = (typeof cfg.columns === 'function' ? cfg.columns() : cfg.columns).slice();
        var t = U.dataTable({
          columns: columns,
          rows: rowsFn,
          filters: cfg.filters,
          pageSize: cfg.pageSize,
          selectable: cfg.selectable && !archived,
          exportName: cfg.collection,
          searchPlaceholder: 'Rechercher un ' + cfg.entite + '…',
          emptyMessage: archived ? 'Aucun enregistrement archivé.' : 'Aucun ' + cfg.entite + ' enregistré.',
          emptyHint: archived ? null : 'Utiliser le bouton « Nouveau » pour créer le premier enregistrement.',
          onRowClick: openDetail,
          defaultSort: cfg.defaultSort, defaultDir: cfg.defaultDir,
          /* `creerVers` : certains écrans ne peuvent pas créer avec le formulaire
             générique — une facture se compose de lignes, de remises et d'une
             répartition. Le bouton conduit alors à l'écran de saisie complet
             plutôt que d'ouvrir une modale qui perdrait l'essentiel. */
          actions: archived ? null : (!peutEditer ? null : [
            cfg.creerVers
              ? btn('Nouveau', {
                variant: 'primary', size: 'sm', icon: 'plus',
                onclick: function () { A().go(cfg.creerVers); },
              })
              : btn('Nouveau', { variant: 'primary', size: 'sm', icon: 'plus', onclick: function () { openForm(null); } }),
          ]),
          bulkActions: archived ? null : function (getSelected, clear) {
            return [
              btn('Imprimer la sélection', {
                size: 'sm', icon: 'printer',
                onclick: function () {
                  var sel = getSelected();
                  P.etat({
                    titre: 'Sélection — ' + cfg.entiteP,
                    sousTitre: sel.length + ' enregistrement(s)',
                    contenu: P.tableau(
                      (typeof cfg.columns === 'function' ? cfg.columns() : cfg.columns)
                        .filter(function (c) { return c.key !== '_actions'; })
                        .map(function (c) { return { label: c.label, align: c.align, value: function (r) { return textOf(c, r); } }; }),
                      sel),
                  });
                },
              }),
              !peutAnnuler ? null : btn('Archiver', {
                size: 'sm', variant: 'danger', icon: 'archive',
                onclick: function () {
                  var sel = getSelected();
                  U.confirm({
                    title: 'Archiver ' + sel.length + ' enregistrement(s) ?',
                    message: 'Archivage logique : les données restent consultables et l’opération est annulable.',
                    confirmLabel: 'Archiver', danger: true,
                  }).then(function (ok) {
                    if (!ok) return;
                    var undos = sel.map(function (r) { return col.archive(r.id).undo; });
                    clear(); refresh();
                    U.toast(sel.length + ' enregistrement(s) archivé(s).', {
                      type: 'success',
                      undo: function () { undos.forEach(function (u) { u(); }); refresh(); },
                    });
                  });
                },
              }),
            ].filter(Boolean);
          },
          rowActions: function (r) {
            if (archived) {
              return [iconBtn('archive-restore', 'Restaurer', function () {
                col.restore(r.id); refresh();
                U.toast('Enregistrement restauré.', { type: 'success' });
              }, 'ghost')];
            }
            var acts = [];
            acts.push(iconBtn('eye', 'Consulter', function () { openDetail(r); }));
            if (cfg.etat) acts.push(iconBtn('printer', 'Imprimer l’état', function () { cfg.etat(r); }));
            /* Pas de duplication : un doublon que rien ne distingue de
               l'original est un doublon que quelqu'un modifiera par erreur.
               Retirée sur décision de la Direction. */
            if (peutEditer) {
              acts.push(iconBtn('pencil', 'Modifier', function () { openForm(r); }));
            }
            if (peutAnnuler) {
              acts.push(iconBtn('archive', 'Archiver', function () { askArchive(r); }, 'ghost'));
            }
            return acts;
          },
        });
        return t;
      }

      function textOf(c, r) {
        var v = c.text ? c.text(r) : (c.value ? c.value(r) : r[c.key]);
        if (v instanceof Node) v = v.textContent;
        return v == null ? '' : String(v);
      }

      /* --- Plage de dates (optionnelle) -------------------------------------
         `plageDates: { champ: 'date', aujourdhui?: Date }` — un FILTRE du/au
         avec raccourcis, jamais un tri (la doctrine du laboratoire, portée au
         kit) : « montrez-moi les rendez-vous du 21 août » ne se répond pas en
         triant. Vide, la plage laisse tout passer. */
      var duPlage = '', auPlage = '';
      function dansPlage(r) {
        if (!cfg.plageDates) return true;
        var v = String(r[cfg.plageDates.champ] || '').slice(0, 10);
        if (duPlage && v < duPlage) return false;
        if (auPlage && v > auPlage) return false;
        return true;
      }
      if (cfg.plageDates) {
        var AUJP = cfg.plageDates.aujourdhui || new Date();
        var duSel = el('input.input', { type: 'date' });
        var auSel = el('input.input', { type: 'date' });
        function poserPlage(du, au) {
          duSel.value = du; auSel.value = au;
          duPlage = du; auPlage = au; refresh();
        }
        [duSel, auSel].forEach(function (x) {
          x.addEventListener('change', function () { duPlage = duSel.value; auPlage = auSel.value; refresh(); });
        });
        var barrePlage = el('div.card');
        barrePlage.appendChild(el('div.card-body.flex.flex-wrap.items-end.gap-3', null, [
          el('div', null, [el('label.label', { text: 'Du' }), duSel]),
          el('div', null, [el('label.label', { text: 'Au' }), auSel]),
          btn('Aujourd’hui', { icon: 'calendar', onclick: function () { poserPlage(C.iso(AUJP), C.iso(AUJP)); } }),
          btn('Sept derniers jours', { icon: 'calendar-days', onclick: function () { poserPlage(C.iso(C.addDays(AUJP, -6)), C.iso(AUJP)); } }),
          btn('Toute la période', { icon: 'calendar-off', onclick: function () { poserPlage('', ''); } }),
        ]));
        host.appendChild(barrePlage);
      }

      /* --- Onglets ----------------------------------------------------------*/
      var onglets = [{
        id: 'liste', label: cfg.tabLabel || ('Tous les ' + cfg.entiteP),
        badge: col.active().length,
        render: function () {
          var t = makeTable(function () { return col.active().filter(dansPlage); }, false);
          tableRef.current = t;
          return t;
        },
      }];
      /* `extraTabs` accepte une FONCTION : un onglet gardé par un droit se
         décide au rendu, pas à l'enregistrement de l'écran. */
      var extras = typeof cfg.extraTabs === 'function' ? (cfg.extraTabs() || []) : (cfg.extraTabs || []);
      extras.forEach(function (t) { onglets.push(t); });
      onglets.push({
        id: 'archives', label: 'Archivés', badge: col.archived().length,
        render: function () { return makeTable(function () { return col.archived().filter(dansPlage); }, true); },
      });

      host.appendChild(U.tabs(onglets));
      /* Bloc libre sous le tableau : la lecture graphique vient APRÈS les
         données, jamais à leur place. */
      if (cfg.apresTableau) host.appendChild(cfg.apresTableau(col));
      if (cfg.source) host.appendChild(source(cfg.source));
      root.appendChild(host);

      /* Exposé pour les actions d'en-tête de page. */
      root._crud = { openForm: openForm, refresh: refresh, collection: col };
      return null;
    };
  }

  /* ==========================================================================
   * GABARIT « REGISTRE »
   * -------------------------------------------------------------------------
   * Même chose qu'un écran de gestion, pour les registres tenus au fil de l'eau
   * (soins, visites, appels, pertes, réactifs…). La seule différence : à la
   * première ouverture, la collection est amorcée par le jeu de démonstration
   * déclaré dans `seed()`. Les enregistrements deviennent alors de vraies
   * données — consultables, modifiables, archivables et journalisées — au lieu
   * d'une liste régénérée à chaque affichage, donc figée en lecture.
   * ======================================================================== */
  function amorcer(nom, seed) {
    var db = S.raw();
    if (seed && (!db[nom] || !db[nom].length)) {
      db[nom] = seed() || [];
      S.save();
    }
  }

  function registre(config) {
    var rendu = crud(config);
    return function (root) {
      amorcer(config.collection, config.seed);
      return rendu(root);
    };
  }

  /* ==========================================================================
   * FILE D'ATTENTE INTER-MODULES
   * --------------------------------------------------------------------------
   * Ce que la prescription a adressé à ce poste de travail. Le même bloc sert
   * à la caisse, à la pharmacie, au laboratoire et à la salle de soins : chacun
   * voit ce qui l'attend, sans avoir à chercher dans le module d'origine.
   *
   * Une tâche « bloquée » est affichée mais non exécutable : elle attend
   * l'encaissement. C'est la traduction visible de la règle posée par la
   * Direction — rien n'est délivré ni prélevé avant le passage en caisse.
   * ======================================================================== */
  function fileAttente(type, cfg) {
    cfg = cfg || {};
    var PR = global.SIGH.parcours;
    var host = el('div');
    host.refresh = dessiner;
    dessiner();
    return host;

    function dessiner() {
      C.clear(host);
      var taches = PR.aFaire(null, type);
      var pretes = taches.filter(function (t) { return t.statut === 'en_attente'; });
      var bloquees = taches.filter(function (t) { return t.statut === 'bloque'; });

      if (!taches.length) {
        host.appendChild(U.card(cfg.titre || 'File d’attente',
          U.empty(cfg.vide || 'Rien en attente — la file est vide.', { icon: 'check-circle-2' })));
        U.icons(host);
        return;
      }

      /* L'ORDRE DE LA FILE : CE QUI EST PAYÉ D'ABORD.
         Une tâche bloquée par la caisse ne peut PAS être traitée : la laisser
         remonter par sa date fait perdre du temps à chaque coup d'œil, et fait
         appeler un patient qu'on devra renvoyer au guichet. Les tâches prêtes
         passent donc devant, les plus anciennes en tête ; les bloquées suivent,
         visibles — le laboratoire doit savoir ce qui arrive — mais après. */
      var ordonnees = pretes.slice().sort(function (a, b) {
        return String(a.date || '').localeCompare(String(b.date || ''));
      }).concat(bloquees.slice().sort(function (a, b) {
        return String(a.date || '').localeCompare(String(b.date || ''));
      }));

      var t = U.dataTable({
        /* Vague 53 : la recherche est TOUJOURS offerte sur une file — même
           courte, on y cherche un nom au guichet. */
        rows: ordonnees, pageSize: 8, searchable: true,
        exportName: 'file-' + type,
        columns: [
          {
            key: 'reference', label: 'Origine', nowrap: true,
            render: function (r) {
              return el('div', null, [
                el('span.font-mono.text-xs', { text: r.reference }),
                r.urgent ? el('span.ml-1', null, U.badge('Urgent', 'danger')) : null,
              ]);
            },
          },
          {
            key: 'patient', label: 'Patient',
            render: function (r) {
              return el('div.min-w-0', null, [
                el('p.truncate.text-sm.font-medium.text-slate-800', { text: r.patient }),
                el('p.font-mono.text-xs.text-slate-400', { text: r.patientCode }),
              ]);
            },
          },
          { key: 'detail', label: 'À faire' },
          {
            key: 'montant', label: 'Montant', align: 'right',
            text: function (r) { return C.money(r.montant || 0, false); },
            render: function (r) { return C.money(r.montant || 0, false); },
          },
          {
            key: 'statut', label: 'État', nowrap: true,
            render: function (r) {
              return r.statut === 'bloque'
                ? U.badge('Attente encaissement', 'warning')
                : U.badge('À traiter', 'info');
            },
          },
        ],
        rowActions: function (r) {
          if (r.statut === 'bloque') {
            return [iconBtn('lock', 'Bloquée jusqu’à l’encaissement', function () {
              U.toast('Cette opération attend le passage en caisse.', { type: 'warning' });
            })];
          }
          /* LA FILE OBÉIT AUX DROITS, ET DEPUIS LE KIT. Cinq écrans affichent
             cette même file — caisse, pharmacie, laboratoire, salle de soins,
             tableaux de bord ; écrire la protection cinq fois aurait garanti
             autant d'oublis. Un profil qui LIT l'écran voit la file, ce qui
             est utile (le magasinier a besoin de savoir ce qui attend en
             caisse), mais ne l'exécute pas.
             Le bouton est VERROUILLÉ, pas retiré : le retirer ferait croire
             que la tâche n'existe pas, et il faut au contraire qu'on voie ce
             qui attend. Il dit pourquoi. */
          if (!droits().editer) {
            return [iconBtn('lock', 'Votre profil consulte cette file sans l’exécuter', function () {
              U.toast('Votre profil consulte cette file sans pouvoir la traiter.', { type: 'warning' });
            })];
          }
          return [iconBtn(cfg.icon || 'check', cfg.action || 'Traiter', function () {
            if (cfg.onAction) cfg.onAction(r, dessiner);
          })];
        },
      });

      host.appendChild(U.card(
        (cfg.titre || 'File d’attente') + ' — ' + pretes.length + ' à traiter'
          + (bloquees.length ? ', ' + bloquees.length + ' en attente de caisse' : ''),
        t));
      U.icons(host);
    }
  }

  /** Mention expliquant qu'un écran est, à dessein, non modifiable. */
  function lectureSeule(raison) {
    return note('<strong>État calculé — lecture seule.</strong> ' + raison, { tone: 'neutral', icon: 'lock' });
  }

  /**
   * modifier(col, champs, record, apres) — modale d'édition standard sur un
   * enregistrement d'une collection existante. Sert aux écrans qui présentent
   * une vue d'une collection tenue ailleurs (pertes issues des mouvements,
   * prises en charge issues des factures…) : la donnée y reste corrigible,
   * l'opération est journalisée et annulable.
   */
  function modifier(col, champs, record, apres, avant, transform) {
    var f = U.form(typeof champs === 'function' ? champs(record) : champs, record);
    var m = U.modal({
      title: 'Modifier l’enregistrement',
      subtitle: record.reference || record.numero || record.code || record.id,
      size: 'lg', body: f,
      footer: [
        btn('Annuler', { onclick: function () { m.close(); } }),
        btn('Enregistrer', {
          variant: 'primary', icon: 'save',
          onclick: function () {
            var v = f.collect();
            if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
            /* Le contrôle métier de l'appelant : il refuse EN LE DISANT
               (son propre toast) et retourne false — rien n'est écrit. */
            if (typeof avant === 'function' && avant(v, record) === false) return;
            if (typeof transform === 'function') v = transform(v);
            var res = col.update(record.id, v);
            m.close();
            if (apres) apres();
            U.toast('Modifications enregistrées.', {
              type: 'success',
              undo: function () { res.undo(); if (apres) apres(); },
            });
          },
        }),
      ],
    });
    return m;
  }

  /**
   * creer(col, champs, opts) — bouton « Nouveau » pour un tableau adossé à une
   * collection mais construit à la main (onglets d'un référentiel, par exemple),
   * là où `kit.crud()` ne s'applique pas. Complète `actionsLigne` : ensemble,
   * les deux donnent un CRUD entier à un tableau existant.
   */
  function creer(col, champs, opts) {
    opts = opts || {};
    if (!droits(opts.module).editer) return null;
    return btn(opts.label || 'Nouveau', {
      variant: 'primary', size: 'sm', icon: 'plus',
      onclick: function () {
        var f = U.form(typeof champs === 'function' ? champs(null) : champs, opts.defauts ? opts.defauts() : {});
        var m = U.modal({
          title: opts.titre || 'Nouvel enregistrement',
          subtitle: 'Les champs marqués d’un astérisque sont obligatoires.',
          size: opts.size || 'lg', body: f,
          footer: [
            btn('Annuler', { onclick: function () { m.close(); } }),
            btn('Créer', {
              variant: 'primary', icon: 'plus',
              onclick: function () {
                var v = f.collect();
                if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                /* `avant` : contrôle métier de l'appelant — refus dit par lui,
                   retour false, rien n'est écrit. */
                if (typeof opts.avant === 'function' && opts.avant(v, null) === false) return;
                if (opts.transform) v = opts.transform(v);
                var res = col.insert(v);
                m.close();
                if (opts.apres) opts.apres();
                U.toast((opts.entite || 'Enregistrement') + ' créé.', {
                  type: 'success',
                  detail: res.record.libelle || res.record.designation || res.record.code || null,
                  undo: function () { col.archive(res.record.id); if (opts.apres) opts.apres(); },
                  undoMessage: 'Création annulée — la fiche est archivée.',
                });
              },
            }),
          ],
        });
      },
    });
  }

  /**
   * actionsLigne(col, champs, opts) — jeu d'actions « consulter / modifier /
   * archiver » à brancher sur le `rowActions` d'un tableau adossé à une
   * collection. Le rafraîchissement se débrouille seul : il remonte du bouton
   * jusqu'au tableau qui le contient, de sorte qu'un écran existant devient
   * modifiable en une seule ligne.
   */
  function actionsLigne(col, champs, opts) {
    opts = opts || {};

    function rafraichirDepuis(noeud) {
      if (opts.refresh) { opts.refresh(); return; }
      var t = noeud && noeud.closest ? noeud.closest('.card') : null;
      while (t && typeof t.refresh !== 'function') t = t.parentElement && t.parentElement.closest ? t.parentElement.closest('.card') : null;
      if (t && typeof t.refresh === 'function') t.refresh();
    }

    return function (r) {
      var actes = [];
      var rafraichir = function () { rafraichirDepuis(actes[actes.length - 1]); };
      if (opts.detail) {
        actes.push(iconBtn('eye', 'Consulter', function () {
          U.drawer({
            title: opts.titre ? opts.titre(r) : (r.reference || r.numero || r.code || 'Détail'),
            subtitle: opts.sousTitre ? opts.sousTitre(r) : '',
            body: opts.detail(r), width: opts.width || 'max-w-2xl',
          });
        }));
      }
      if (opts.etat) actes.push(iconBtn('printer', 'Imprimer l’état', function () { opts.etat(r); }));
      var dr = droits(opts.module);
      if (dr.editer) actes.push(iconBtn('pencil', 'Modifier', function () { modifier(col, champs, r, rafraichir, opts.avant, opts.transform); }));
      if (opts.archivable !== false && dr.annuler) {
        actes.push(iconBtn('archive', 'Archiver', function () {
          U.confirm({
            title: 'Archiver cet enregistrement ?',
            message: 'Archivage logique (RG-14) : la donnée reste consultable et l’opération est annulable.',
            confirmLabel: 'Archiver', danger: true, requireMotif: true,
          }).then(function (rep) {
            if (!rep) return;
            var res = col.archive(r.id, rep.motif);
            if (rafraichir) rafraichir();
            U.toast('Enregistrement archivé.', {
              type: 'success',
              undo: function () { res.undo(); if (rafraichir) rafraichir(); },
              undoMessage: 'Archivage annulé.',
            });
          });
        }, 'ghost'));
      }
      return actes;
    };
  }

  /* ==========================================================================
   * GABARIT « TABLEAU DE BORD »
   * ======================================================================== */
  /** Une section est-elle un bloc d'accès rapides ? */
  function estAccesRapide(s) { return s && (s.rapide === true || s.title === 'Accès rapides'); }

  /**
   * Le bandeau du premier regard.
   *
   * { question, valeur, unite, ton, icone, ecran, lienLabel, vide, note }
   *
   * `vide` est le texte affiché quand le compte est nul. Il est OBLIGATOIRE et
   * doit être positif : « rien ne vous attend » est une information, pas un
   * vide — laisser un bandeau gris sans phrase ferait douter de l'écran.
   */
  /**
   * Annonce sonore d'un premier regard grave.
   *
   * Le drapeau vit dans la SESSION du navigateur, non dans le magasin : il doit
   * se remettre à zéro quand l'agent revient le lendemain, mais pas d'un écran
   * à l'autre dans la même journée.
   */
  function annoncer(o) {
    try {
      var cle = 'sigh-cbg:annonce:' + (o.ecran || 'general') + ':' + C.iso(new Date());
      if (global.sessionStorage && global.sessionStorage.getItem(cle)) return;
      if (global.sessionStorage) global.sessionStorage.setItem(cle, '1');
      /* Un navigateur qui refuse l'audio retombe sur le bandeau, qui reste
         lisible : le son ajoute, il ne remplace pas. */
      U.alerter(C.num(o.valeur) + ' ' + (o.unite || '') + ' — ' + (o.question || ''),
        { type: 'error', son: 'alerte', duration: 9000 });
    } catch (e) { /* l'audio ou le stockage de session est indisponible */ }
  }

  function bandeauPremierRegard(o) {
    var rien = !o.valeur;
    var ton = rien ? 'success' : (o.ton || 'navy');
    var TONS = {
      navy: ['border-navy-200', 'bg-navy-50', 'text-navy-900', 'text-navy-700'],
      danger: ['border-rose-200', 'bg-rose-50', 'text-rose-900', 'text-rose-700'],
      warning: ['border-amber-200', 'bg-amber-50', 'text-amber-900', 'text-amber-700'],
      info: ['border-sky-200', 'bg-sky-50', 'text-sky-900', 'text-sky-700'],
      success: ['border-emerald-200', 'bg-emerald-50', 'text-emerald-900', 'text-emerald-700'],
    };
    var t = TONS[ton] || TONS.navy;

    var bloc = el('div.flex.flex-wrap.items-center.gap-4.rounded-xl.border.px-5.py-4', {
      class: t[0] + ' ' + t[1],
    });
    bloc.appendChild(el('span.shrink-0', { class: t[3] },
      C.icon(rien ? 'check-check' : (o.icone || 'eye'), 'h-7 w-7')));

    var texte = el('div.min-w-0.flex-1');
    texte.appendChild(el('p.text-xs.font-semibold.uppercase.tracking-wide', {
      class: t[3], text: 'À regarder en premier',
    }));
    if (rien) {
      texte.appendChild(el('p.mt-0\\.5.text-lg.font-semibold', { class: t[2], text: o.vide }));
    } else {
      texte.appendChild(el('p.mt-0\\.5.text-lg.font-semibold', { class: t[2] }, [
        el('span.text-2xl.font-bold', { text: C.num(o.valeur) }),
        el('span', { text: ' ' + (o.unite || '') + ' — ' + o.question }),
      ]));
    }
    if (o.note) {
      texte.appendChild(el('p.mt-1.text-xs', { class: t[3], text: o.note }));
    }
    bloc.appendChild(texte);

    if (o.ecran && !rien) {
      bloc.appendChild(lien(o.ecran, o.lienLabel || 'Y aller', {
        variant: 'primary', icon: 'arrow-right', size: 'sm',
      }));
    }
    return bloc;
  }

  function dash(config) {
    return function (root) {
      var host = el('div.space-y-5');

      /* ====================================================================
       * UN TABLEAU DE BORD DONT LE POSTE N'EXISTE PAS L'ANNONCE (doctrine
       * BAGUIDI, 02/09/2026) : si le rôle dont cet écran est la page
       * d'accueil est ARCHIVÉ, le tableau le dit en tête au lieu d'afficher
       * des indicateurs vides comme si de rien n'était. Posé UNE fois ici :
       * tout tableau présent ou futur en hérite.
       * ================================================================== */
      try {
        var entree = global.SIGH.app && global.SIGH.app.entry && global.SIGH.app.entry();
        var ecranId = entree && entree.id;
        if (ecranId && N.roleArchive) {
          /* Un tableau partagé par un rôle ACTIF (dash-direction sert la
             Direction, même si dm/da sont archivés) ne s'annonce pas. */
          var titulaires = Object.keys(N.ROLES || {}).filter(function (rid) {
            return N.ROLES[rid].home === ecranId;
          });
          if (titulaires.length && titulaires.every(function (rid) { return N.roleArchive(rid); })) {
            var fiche = (S.collection('rbac').all() || []).filter(function (x) {
              return titulaires.indexOf(x.role) !== -1 && x.statut === 'archive';
            })[0] || {};
            host.appendChild(note('<strong>Poste sans titulaire — rôle archivé.</strong> '
              + C.escapeHtml(fiche.motifArchivage || fiche.motif
                || 'Ce poste n’a pas de titulaire chez BAGUIDI ; le rôle est archivé (RG-14), jamais supprimé.'),
            { tone: 'warning', icon: 'archive' }));
          }
        }
      } catch (e) { /* l'annonce ne doit jamais empêcher le tableau */ }

      function poser(s) {
        try {
          var content = s.render();
          if (!content) return;
          if (s.title) {
            host.appendChild(U.card(s.title, content, s.actions ? s.actions() : null));
          } else {
            host.appendChild(content);
          }
        } catch (e) {
          console.error('[SIGH] Section « ' + (s.title || '?') + ' » :', e);
          host.appendChild(U.card(s.title || 'Section', U.errorState('Cette section n’a pas pu être affichée.')));
        }
      }

      /* Un crochet AVANT le rendu : un poste peut vouloir dire quelque chose
         à l'ouverture — un rappel du matin, par exemple — que le bandeau du
         premier regard ne saurait pas porter, parce qu'il ne porte qu'UNE
         question. Un crochet qui échoue ne doit pas empêcher le tableau de
         s'afficher. */
      if (typeof config.avant === 'function') {
        try { config.avant(); } catch (e) { console.error('[SIGH] Rappel d ouverture :', e); }
      }

      if (config.alerte) {
        var a = config.alerte();
        if (a) host.appendChild(a);
      }

      /* LE PREMIER REGARD — la chose que ce profil vérifie en arrivant.
         Posé AVANT tout le reste : l'ordre de lecture est la seule chose qu'un
         tableau de bord contrôle vraiment. Il porte UNE question, son compte et
         le lien qui y mène — un bandeau de quatre indicateurs demande à être lu
         et comparé, celui-ci demande à être vu. */
      if (config.premierRegard) {
        try {
          var pr = config.premierRegard();
          if (pr) {
            host.appendChild(bandeauPremierRegard(pr));
            /* Le son porte l'attention sur ce qui est GRAVE, et seulement là.
               Une fois par session et par écran : rouvrir la même page dix
               fois dans la journée ne doit pas sonner dix fois, sinon on coupe
               le son et l'alerte suivante passe inaperçue. */
            if (pr.valeur && pr.ton === 'danger') annoncer(pr);
          }
        } catch (e) { console.error('[SIGH] Premier regard :', e); }
      }

      /* Les accès rapides ouvrent le tableau de bord : sur ces postes, l'écran
         d'accueil sert d'abord de rampe de lancement vers les écrans de travail
         du profil ; les indicateurs viennent ensuite. */
      var sections = config.sections || [];
      /* DANS LE GROUPE RAPIDE, LES RACCOURCIS PASSENT DEVANT. Les accès
         rapides et les parcours portent tous deux `rapide`, et l'ordre de
         déclaration mettait les parcours en tête. Ce qu'on cherche en
         arrivant, ce sont les raccourcis ; le mode d'emploi se lit ensuite. */
      var rapides = sections.filter(estAccesRapide);
      rapides.filter(function (s) { return s.title === 'Accès rapides'; }).forEach(poser);
      rapides.filter(function (s) { return s.title !== 'Accès rapides'; }).forEach(poser);

      if (config.kpis) {
        try {
          host.appendChild(U.kpiGrid(config.kpis(), config.kpiCols || 'grid-cols-2 lg:grid-cols-4'));
        } catch (e) { console.error('[SIGH] KPI tableau de bord :', e); }
      }

      sections.filter(function (s) { return !estAccesRapide(s); }).forEach(poser);

      root.appendChild(host);
      return null;
    };
  }

  /** Grille de graphiques à deux colonnes. */
  function charts(items) {
    var g = el('div.grid.gap-4.lg\\:grid-cols-2');
    items.forEach(function (it) {
      if (!it) return;
      g.appendChild(U.card(it.title, it.render(), it.actions || null));
    });
    return g;
  }

  /** Liste compacte « libellé → valeur » avec barre de proportion. */
  function ranking(items, opts) {
    opts = opts || {};
    var max = Math.max.apply(null, items.map(function (i) { return i.value; }).concat([1]));
    var list = el('div.space-y-2\\.5');
    if (!items.length) return U.empty('Aucune donnée.', { icon: 'bar-chart-3' });
    items.forEach(function (i) {
      var r = el('div');
      var top = el('div.mb-1.flex.items-baseline.justify-between.gap-3');
      top.appendChild(el('span.truncate.text-sm.text-slate-700', { text: i.label }));
      top.appendChild(el('span.shrink-0.text-sm.font-semibold.num.text-slate-900', { text: opts.format ? opts.format(i.value) : C.num(i.value) }));
      r.appendChild(top);
      var bar = el('div.h-1\\.5.w-full.overflow-hidden.rounded-full.bg-slate-100');
      bar.appendChild(el('div.h-full.rounded-full', {
        class: 'bg-' + (i.tone || opts.tone || 'navy') + '-500',
        style: 'width:' + Math.max(2, Math.round(i.value / max * 100)) + '%;',
      }));
      r.appendChild(bar);
      list.appendChild(r);
    });
    return list;
  }

  /** Tableau simple, sans interaction — pour les encarts de tableau de bord.
      Deux formes de colonnes : objets {key,label,align,render,value}, ou simples
      chaînes — une chaîne devient {label, key: rang} et les lignes sont alors des
      tableaux de valeurs. Sans cette normalisation, un appel en colonnes-chaînes
      rendait un tableau aux en-têtes vides et aux cellules « — », sans un mot. */
  function miniTable(columns, rows, opts) {
    opts = opts || {};
    if (!rows.length) return U.empty(opts.empty || 'Aucune donnée.', { icon: 'inbox' });
    columns = columns.map(function (c, i) {
      return typeof c === 'string' ? { label: c, key: i } : c;
    });
    var t = el('table.tbl');
    var thead = el('thead'), htr = el('tr');
    columns.forEach(function (c) { htr.appendChild(el('th', { class: c.align === 'right' ? 'text-right' : '', text: c.label })); });
    thead.appendChild(htr); t.appendChild(thead);
    var tb = el('tbody');
    rows.forEach(function (r) {
      var tr = el('tr');
      columns.forEach(function (c) {
        var td = el('td', { class: c.align === 'right' ? 'text-right num' : '' });
        var v = c.render ? c.render(r) : (c.value ? c.value(r) : r[c.key]);
        if (v instanceof Node) td.appendChild(v); else td.textContent = v == null ? '—' : String(v);
        tr.appendChild(td);
      });
      tb.appendChild(tr);
    });
    t.appendChild(tb);
    return el('div.-mx-5.-mb-5.overflow-x-auto', null, t);
  }

  /* --- Raccourcis d'accès à d'autres écrans -------------------------------- */
  function shortcuts(items) {
    var g = el('div.grid.gap-3.sm\\:grid-cols-2.lg\\:grid-cols-4');
    items.forEach(function (i) {
      var a = el('a.group.flex.items-start.gap-3.rounded-xl.border.border-slate-200.bg-white.p-4.shadow-card.transition-colors.hover\\:border-navy-300.hover\\:bg-navy-50',
        { href: A().href(i.id) });
      a.appendChild(el('span.grid.h-9.w-9.shrink-0.place-items-center.rounded-lg.bg-navy-50.text-navy-700', null, C.icon(i.icon, 'h-4 w-4')));
      a.appendChild(el('span.min-w-0', null, [
        el('span.block.text-sm.font-medium.text-slate-800', { text: i.label }),
        i.detail ? el('span.mt-0\\.5.block.text-xs.text-slate-500', { text: i.detail }) : null,
      ]));
      g.appendChild(a);
    });
    return g;
  }

  /* ==========================================================================
   * PARCOURS MÉTIER
   * --------------------------------------------------------------------------
   * parcours([{ titre, icone, ton, etapes: [{ label, ecran, poste, detail }] }])
   *
   * Une grille de liens dit OÙ aller ; elle ne dit pas CE QU'IL FAUT FAIRE ni
   * DANS QUEL ORDRE. Un parcours affiche la chaîne complète : première action
   * en bouton, étapes suivantes visibles.
   *
   * Une étape dont l'écran est fermé au profil reste VISIBLE mais non
   * cliquable : promettre une porte fermée est pire que ne rien promettre, et
   * masquer l'étape ferait croire qu'elle n'existe pas.
   * ======================================================================== */
  function parcours(groupes) {
    var g = el('div.grid.gap-4.lg\\:grid-cols-2');
    (groupes || []).forEach(function (p2) {
      var carte = el('div.rounded-xl.border.border-slate-200.bg-white.p-4.shadow-card');

      var tete = el('div.mb-3.flex.items-center.gap-2.5');
      tete.appendChild(el('span.grid.h-9.w-9.shrink-0.place-items-center.rounded-lg.bg-navy-50.text-navy-700',
        null, C.icon(p2.icone || 'route', 'h-4 w-4')));
      tete.appendChild(el('div.min-w-0', null, [
        el('p.text-sm.font-semibold.text-slate-800', { text: p2.titre }),
        p2.detail ? el('p.text-xs.text-slate-500', { text: p2.detail }) : null,
      ]));
      carte.appendChild(tete);

      var chaine = el('ol.space-y-1\.5');
      (p2.etapes || []).forEach(function (e, i) {
        var ouvert = !e.ecran || ecranOuvert(e.ecran);
        var li = el('li.flex.items-start.gap-2');

        li.appendChild(el('span.mt-0\.5.grid.h-5.w-5.shrink-0.place-items-center.rounded-full.text-\\[10px\\].font-bold', {
          class: i === 0 ? 'bg-navy-700 text-white' : 'bg-slate-100 text-slate-500',
          text: String(i + 1),
        }));

        var corps = el('span.min-w-0.flex-1');
        if (e.ecran && ouvert) {
          corps.appendChild(el('a.text-sm.font-medium.text-navy-800.hover\\:underline', {
            href: A().href(e.ecran), text: e.label,
          }));
        } else {
          corps.appendChild(el('span.text-sm', {
            class: ouvert ? 'text-slate-700' : 'text-slate-400',
            text: e.label,
          }));
        }
        /* Le poste qui prend la suite est nommé : l'accueil doit savoir que la
           caisse enchaîne, sans croire que c'est à lui de le faire. */
        if (e.poste) {
          corps.appendChild(el('span.ml-1\.5.rounded.bg-slate-100.px-1\.5.py-0\.5.text-\\[10px\\].font-medium.text-slate-500',
            { text: e.poste }));
        }
        if (!ouvert) {
          corps.appendChild(el('span.ml-1\.5.text-\\[10px\\].italic.text-slate-400',
            { text: '— fermé à votre profil' }));
        }
        if (e.detail) {
          corps.appendChild(el('span.mt-0\.5.block.text-xs.text-slate-500', { text: e.detail }));
        }
        li.appendChild(corps);
        chaine.appendChild(li);
      });
      carte.appendChild(chaine);

      /* Le bouton porte la PREMIÈRE action : c'est par là qu'on commence. */
      var premiere = (p2.etapes || [])[0];
      if (premiere && premiere.ecran && ecranOuvert(premiere.ecran)) {
        carte.appendChild(el('div.mt-3', null,
          lien(premiere.ecran, p2.action || 'Commencer', {
            variant: 'primary', size: 'sm', icon: 'arrow-right',
          })));
      }
      g.appendChild(carte);
    });
    return g;
  }

  /* L écran est-il ouvert au profil courant ? N.can attend une ENTRÉE du
     manifeste, non un identifiant : on la résout d abord. Un identifiant
     inconnu est traité comme fermé — mieux vaut ne rien promettre. */
  function ecranOuvert(id) {
    if (!id) return true;
    var e = N.get(id);
    if (!e) return false;
    return N.can(sessionRole(), e);
  }

  function sessionRole() {
    var s2 = S.session();
    return (s2 && s2.role) || 'admin';
  }

  /* --- Agrégations fréquentes ---------------------------------------------- */
  function parMois(rows, dateKey, valueKey, nbMois) {
    var n = nbMois || 12, labels = G.moisGlissants(n), buckets = new Array(n).fill(0);
    var ref = new Date(2026, 7, 1);
    rows.forEach(function (r) {
      var d = C.toDate(r[dateKey]);
      if (isNaN(d)) return;
      var diff = (ref.getFullYear() - d.getFullYear()) * 12 + (ref.getMonth() - d.getMonth());
      var idx = n - 1 - diff;
      if (idx >= 0 && idx < n) buckets[idx] += valueKey ? (Number(r[valueKey]) || 0) : 1;
    });
    return { labels: labels, data: buckets };
  }

  function repartition(rows, key, labelFn) {
    var g = C.groupBy(rows, key);
    var keys = Object.keys(g);
    return {
      labels: keys.map(function (k) { return labelFn ? labelFn(k) : k; }),
      data: keys.map(function (k) { return g[k].length; }),
      keys: keys,
    };
  }

  /* ==========================================================================
   * PAGES D'ACCUEIL DE MODULE (hubs)
   * -------------------------------------------------------------------------
   * Une page par module, engendrée depuis le manifeste : chaque écran y est
   * présenté par une carte — icône, titre, description reprise de sa propre
   * déclaration. C'est le point d'entrée du module, atteint depuis le fil
   * d'Ariane, l'intitulé du module dans le ruban et les raccourcis permanents.
   * ======================================================================== */
  function hubCartes(mod, role) {
    var grille = el('div.grid.gap-3.sm\\:grid-cols-2.xl\\:grid-cols-3');
    /* L'IDENTIFIANT DE L'ÉCRAN DOIT ÊTRE PASSÉ. `N.can` interroge
       `ecranActif(entry.id, code)` pour savoir si l'activité est fermée ; une
       entrée synthétique sans `id` faisait manquer ce contrôle, et un écran
       fermé partout ailleurs restait offert sur le hub. Un écran fermé qu'on
       peut encore atteindre n'est pas fermé. */
    var visibles = mod.items.filter(function (it) {
      return N.can(role, {
        id: it.id,
        roles: it.roles || mod.roles || N.ALL,
        module: mod.code,
      });
    });
    visibles.forEach(function (it) {
      var def = global.SIGH.screens[it.id] || {};
      var carte = el('a.hub-card.group.flex.gap-3.rounded-xl.border.border-slate-200.bg-white.p-4.shadow-card.transition-all.hover\\:-translate-y-0\\.5.hover\\:border-navy-300.hover\\:shadow-raise',
        { href: A().href(it.id) });
      carte.appendChild(el('span.grid.h-10.w-10.shrink-0.place-items-center.rounded-lg.bg-navy-50.text-navy-700.transition-colors.group-hover\\:bg-navy-900.group-hover\\:text-white',
        null, C.icon(it.icon || mod.icon, 'h-5 w-5')));
      var corps = el('span.min-w-0.flex-1');
      corps.appendChild(el('span.block.text-sm.font-semibold.text-slate-900', { text: def.title || it.label }));
      corps.appendChild(el('span.mt-1.block.text-xs.leading-relaxed.text-slate-500', {
        text: def.description || 'Écran du module ' + mod.label + '.',
      }));
      carte.appendChild(corps);
      carte.appendChild(C.icon('arrow-right', 'h-4 w-4 shrink-0 text-slate-300 transition-colors group-hover:text-navy-700'));
      grille.appendChild(carte);
    });
    if (!visibles.length) return U.empty('Aucun écran de ce module n’est accessible à votre profil.', { icon: 'lock' });
    return grille;
  }

  function hub(mod) {
    return function (root) {
      var role = S.session() ? S.session().role : 'admin';
      var host = el('div.space-y-4');
      host.appendChild(hubCartes(mod, role));

      /* Passage direct vers les autres modules du même domaine. */
      var voisins = (N.tree(role).filter(function (d) { return d.domain === mod.domain; })[0] || { modules: [] })
        .modules.filter(function (m) { return m.code !== mod.code; });
      if (voisins.length) {
        var l = el('div.flex.flex-wrap.items-center.gap-2');
        l.appendChild(el('span.text-xs.text-slate-500', { text: 'Autres modules du domaine ' + mod.domain + ' :' }));
        voisins.forEach(function (m) {
          l.appendChild(el('a.inline-flex.items-center.gap-1\\.5.rounded-lg.border.border-slate-200.bg-white.px-2\\.5.py-1\\.5.text-xs.font-medium.text-slate-600.hover\\:border-navy-300.hover\\:text-navy-800',
            { href: A().href(m.hub) }, [C.icon(m.icon, 'h-3.5 w-3.5'), m.label]));
        });
        host.appendChild(l);
      }
      root.appendChild(host);
      return null;
    };
  }

  /* Enregistrement des hubs — le manifeste en est la seule source. */
  N.NAV.forEach(function (domaine) {
    domaine.modules.forEach(function (m) {
      var mod = N.module(m.code);
      global.SIGH.screen(N.hubId(m.code), {
        title: mod.label,
        description: 'Tous les écrans du module ' + mod.code + ' — ' + mod.label + '.',
        render: hub(mod),
      });
    });
  });

  global.SIGH.kit = {
    btn: btn, iconBtn: iconBtn, lien: lien,
    commande: commande, commandeIcone: commandeIcone,
    section: section, grid: grid, row: row, note: note, source: source,
    crud: crud, registre: registre, lectureSeule: lectureSeule, fileAttente: fileAttente,
    droits: droits, bandeauLectureSeule: bandeauLectureSeule,
    modifier: modifier, actionsLigne: actionsLigne, creer: creer,
    dash: dash, charts: charts, ranking: ranking, miniTable: miniTable,
    bandeauPremierRegard: bandeauPremierRegard, parcours: parcours,
    shortcuts: shortcuts, parMois: parMois, repartition: repartition,
  };
})(window);
