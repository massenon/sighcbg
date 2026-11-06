/* =============================================================================
 * M12 — Comptabilité SYSCOHADA
 * -----------------------------------------------------------------------------
 * CDCT §10.11 — plan comptable OHADA paramétrable, journaux, grand livre,
 * balance générale et âgée, immobilisations et amortissements, budgétisation,
 * comptabilité analytique par centre de coûts, rapprochements bancaires,
 * états financiers de synthèse et automatisation des écritures issues de la
 * caisse, de la pharmacie, des achats et de la paie.
 *
 * RG-10 — toute écriture est équilibrée (débit = crédit) avant validation.
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core, U = global.SIGH.ui, S = global.SIGH.store, D = global.SIGH.data,
      P = global.SIGH.print, G = global.SIGH.charts, K = global.SIGH.kit;
  var el = C.el;
  var AUJ = new Date(2026, 7, 16);

  /* Centres de coûts : référentiel administrable (écran cfg-centres-couts).
     La saisie comptable en propose la liste et permet d'en ouvrir un à la
     volée — attendre une livraison pour imputer une charge n'a pas de sens. */
  function colCentres() { return S.collection('centresCouts', { module: 'M12', entite: 'centre de coûts' }); }
  function optionsCentres() {
    return colCentres().active().map(function (c) { return { value: c.code, label: c.libelle, detail: c.type === 'support' ? 'Support' : 'Exploitation' }; });
  }

  function ecritures() { return S.collection('ecritures').active(); }
  function comptes() { return S.collection('comptes').active(); }

  function compteLibelle(num) {
    var c = D.PLAN_COMPTABLE.filter(function (x) { return x.num === num; })[0];
    return c ? c.libelle : num;
  }
  function journalLibelle(code) {
    var j = D.JOURNAUX.filter(function (x) { return x.code === code; })[0];
    return j ? j.libelle : code;
  }
  function centreLabel(id) {
    var c = D.CENTRES_COUT.filter(function (x) { return x.id === id; })[0];
    return c ? c.label : id;
  }
  function classeLibelle(n) {
    return {
      1: 'Classe 1 — Ressources durables', 2: 'Classe 2 — Actif immobilisé',
      3: 'Classe 3 — Stocks', 4: 'Classe 4 — Tiers', 5: 'Classe 5 — Trésorerie',
      6: 'Classe 6 — Charges', 7: 'Classe 7 — Produits', 8: 'Classe 8 — Autres charges et produits',
    }[n] || 'Classe ' + n;
  }
  function soldeCompte(num) {
    var e = ecritures().filter(function (x) { return x.compte === num; });
    return { debit: C.sum(e, 'debit'), credit: C.sum(e, 'credit'), solde: C.sum(e, 'debit') - C.sum(e, 'credit'), nb: e.length };
  }

  /* --- Colonnes réutilisables ---------------------------------------------- */
  var colNumeroEcr = {
    key: 'numero', label: 'N° pièce', nowrap: true,
    render: function (e) { return el('span.font-mono.text-xs.font-semibold.text-navy-800', { text: e.numero }); },
  };
  var colDateEcr = {
    key: 'date', label: 'Date', nowrap: true,
    text: function (e) { return C.dateFR(e.date); },
    render: function (e) { return C.dateFR(e.date); },
  };
  var colJournal = {
    key: 'journal', label: 'Journal', nowrap: true,
    render: function (e) { return U.badge(e.journal, 'navy'); },
  };
  var colCompte = {
    key: 'compte', label: 'Compte',
    render: function (e) {
      return el('div.min-w-0', null, [
        el('p.font-mono.text-xs.font-semibold.text-slate-700', { text: e.compte }),
        el('p.truncate.text-xs.text-slate-400', { text: e.compteLibelle || compteLibelle(e.compte) }),
      ]);
    },
  };
  var colDebit = {
    key: 'debit', label: 'Débit', align: 'right',
    text: function (e) { return e.debit ? C.money(e.debit, false) : ''; },
    render: function (e) { return e.debit ? el('span.font-medium', { text: C.money(e.debit, false) }) : el('span.text-slate-300', { text: '—' }); },
  };
  var colCredit = {
    key: 'credit', label: 'Crédit', align: 'right',
    text: function (e) { return e.credit ? C.money(e.credit, false) : ''; },
    render: function (e) { return e.credit ? el('span.font-medium', { text: C.money(e.credit, false) }) : el('span.text-slate-300', { text: '—' }); },
  };

  /* ==========================================================================
   * TABLEAU DE BORD COMPTABLE
   * ======================================================================== */
  global.SIGH.screen('m12-dashboard', {
    title: 'Tableau de bord — Comptabilité SYSCOHADA',
    description: 'Équilibre des journaux, trésorerie, charges et produits, créances et dettes.',
    render: K.dash({
      alerte: function () {
        var e = ecritures();
        var d = C.sum(e, 'debit'), c = C.sum(e, 'credit');
        var brouillons = e.filter(function (x) { return x.statut === 'brouillon'; });
        var wrap = el('div.grid.gap-2.sm\\:grid-cols-2');
        var a = false;
        if (Math.abs(d - c) > 0) {
          wrap.appendChild(K.note('<strong>RG-10 — déséquilibre constaté</strong> : écart de ' + C.money(Math.abs(d - c))
            + ' entre le total des débits et celui des crédits. À régulariser avant clôture.', { tone: 'danger', icon: 'scale-3d' }));
          a = true;
        }
        if (brouillons.length) {
          wrap.appendChild(K.note('<strong>' + brouillons.length + ' écriture(s) en brouillon</strong> à valider.', { tone: 'warning', icon: 'file-clock' }));
          a = true;
        }
        return a ? wrap : null;
      },
      kpis: function () {
        var e = ecritures();
        var charges = e.filter(function (x) { return String(x.compte)[0] === '6'; });
        var produits = e.filter(function (x) { return String(x.compte)[0] === '7'; });
        var caisse = soldeCompte('5711'), banque = soldeCompte('5211');
        var clients = soldeCompte('4111').solde + soldeCompte('4111').solde;
        var fournisseurs = soldeCompte('4011');
        var ca = C.sum(produits, 'credit');
        var ch = C.sum(charges, 'debit');
        return [
          { label: 'Trésorerie disponible', value: C.money(caisse.solde + banque.solde), icon: 'wallet', tone: 'navy' },
          { label: 'Chiffre d’affaires', value: C.money(ca), icon: 'trending-up', tone: 'success' },
          { label: 'Charges', value: C.money(ch), icon: 'trending-down', tone: 'warning' },
          { label: 'Résultat', value: C.money(ca - ch), icon: ca - ch >= 0 ? 'smile' : 'frown', tone: ca - ch >= 0 ? 'success' : 'danger' },
          { label: 'Créances clients', value: C.money(clients), icon: 'hand-coins', tone: 'info' },
          { label: 'Dettes fournisseurs', value: C.money(Math.abs(fournisseurs.solde)), icon: 'truck', tone: 'warning' },
          { label: 'Écritures de l’exercice', value: C.num(e.length), icon: 'book-open-check', tone: 'neutral' },
          {
            label: 'Équilibre (RG-10)',
            value: C.sum(e, 'debit') === C.sum(e, 'credit') ? 'Équilibré' : C.money(Math.abs(C.sum(e, 'debit') - C.sum(e, 'credit'))),
            icon: 'scale', tone: C.sum(e, 'debit') === C.sum(e, 'credit') ? 'success' : 'danger',
          },
        ];
      },
      sections: [
        {
          render: function () {
            return K.charts([
              {
                title: 'Produits et charges (12 mois)',
                render: function () {
                  var prod = K.parMois(ecritures().filter(function (e) { return String(e.compte)[0] === '7'; }), 'date', 'credit');
                  var ch = K.parMois(ecritures().filter(function (e) { return String(e.compte)[0] === '6'; }), 'date', 'debit');
                  return G.ligne(prod.labels, [
                    { label: 'Produits', data: prod.data, color: G.TONES.vert },
                    { label: 'Charges', data: ch.data, color: G.TONES.rouge },
                  ]);
                },
              },
              {
                title: 'Écritures par journal',
                render: function () {
                  var g = C.groupBy(ecritures(), 'journal');
                  var keys = Object.keys(g);
                  return G.anneau(keys.map(journalLibelle), keys.map(function (k) { return g[k].length; }), { legend: 'bottom' });
                },
              },
            ]);
          },
        },
        {
          render: function () {
            return K.charts([
              {
                title: 'Charges par centre de coûts',
                render: function () {
                  var g = C.groupBy(ecritures().filter(function (e) { return e.debit > 0 && String(e.compte)[0] === '6'; }), 'centreCout');
                  return K.ranking(Object.keys(g).map(function (k) {
                    return { label: centreLabel(k), value: C.sum(g[k], 'debit') };
                  }).sort(function (a, b) { return b.value - a.value; }), { format: function (v) { return C.money(v, false); } });
                },
              },
              {
                title: 'Origine des écritures',
                render: function () {
                  var g = C.groupBy(ecritures(), 'origine');
                  var keys = Object.keys(g);
                  return G.barres(keys, [{ label: 'Écritures', data: keys.map(function (k) { return g[k].length; }) }],
                    { horizontal: true, height: 260 });
                },
              },
            ]);
          },
        },
        {
          title: 'Automatisation des écritures',
          render: function () {
            return K.miniTable([
              { label: 'Opération métier', key: 'op' },
              { label: 'Module d’origine', key: 'mod' },
              { label: 'Journal', render: function (x) { return U.badge(x.journal, 'navy'); } },
              { label: 'Compte débité', render: function (x) { return el('span.font-mono.text-xs', { text: x.debit }); } },
              { label: 'Compte crédité', render: function (x) { return el('span.font-mono.text-xs', { text: x.credit }); } },
            ], [
              { op: 'Encaissement d’une facture patient', mod: 'M8 — Caisse', journal: 'CAI', debit: '5711', credit: '4111' },
              { op: 'Facturation d’une prestation', mod: 'M8 — Facturation', journal: 'VTE', debit: '4111', credit: '7061' },
              { op: 'Vente de médicaments', mod: 'M6 — Pharmacie', journal: 'VTE', debit: '4111', credit: '7011' },
              { op: 'Réception d’une commande', mod: 'M7 — Achats', journal: 'ACH', debit: '6011', credit: '4011' },
              { op: 'Facture assureur', mod: 'M9 — Assurances', journal: 'VTE', debit: '4111', credit: '7061' },
              { op: 'Salaires du mois', mod: 'M11 — Paie', journal: 'SAL', debit: '6611', credit: '422' },
              { op: 'Cotisations CNSS', mod: 'M11 — Paie', journal: 'SAL', debit: '6412', credit: '431' },
              { op: 'Perte ou casse de stock', mod: 'M6 — Stock', journal: 'OD', debit: '6511', credit: '3111' },
            ]);
          },
        },
        {
          title: 'Accès rapides',
          render: function () {
            return K.shortcuts([
              { id: 'm12-ecritures', icon: 'pencil-line', label: 'Saisir une écriture', detail: 'Équilibre contrôlé (RG-10)' },
              { id: 'm12-grand-livre', icon: 'book-open', label: 'Grand livre', detail: 'Par compte' },
              { id: 'm12-balance', icon: 'scale', label: 'Balance', detail: 'Générale et âgée' },
              { id: 'm12-etats-financiers', icon: 'file-spreadsheet', label: 'États financiers', detail: 'Bilan et résultat' },
            ]);
          },
        },
      ],
    }),
  });

  /* ==========================================================================
   * PLAN COMPTABLE
   * ======================================================================== */
  global.SIGH.screen('m12-plan-comptable', {
    title: 'Plan comptable OHADA',
    description: 'Le plan comptable SYSCOHADA RÉVISÉ au complet — 1 332 comptes, par classe.',
    regle: 'Le référentiel est le <strong>plan SYSCOHADA révisé</strong> remis par la Direction le 06/09/2026, '
      + 'qui remplace le plan de la clinique d’origine. Une écriture se passe sur un compte '
      + '<strong>imputable</strong> — une feuille du plan ; les niveaux supérieurs (classe, compte principal, '
      + 'compte divisionnaire) <strong>totalisent</strong> et ne s’imputent pas.',
    render: K.crud({
      collection: 'comptes', entite: 'compte', entiteP: 'comptes', module: 'M12',
      defaultSort: 'num', pageSize: 20,
      source: 'Plan comptable SYSCOHADA révisé — Direction, 06/09/2026.',
      columns: [
        { key: 'num', label: 'N° de compte', nowrap: true, render: function (c) { return el('span.font-mono.text-xs.font-semibold.text-navy-800', { text: c.num }); } },
        { key: 'libelle', label: 'Intitulé' },
        { key: 'classe', label: 'Classe', text: function (c) { return classeLibelle(c.classe); }, render: function (c) { return U.badge('Classe ' + c.classe, 'navy'); } },
        { key: 'journal', label: 'Journal usuel', render: function (c) { return U.badge(c.journal, 'neutral'); } },
        {
          key: 'niveau', label: 'Niveau', align: 'right',
          value: function (c) { return c.niveau || String(c.num).length; },
          render: function (c) { return U.badge('N' + (c.niveau || String(c.num).length), 'neutral'); },
        },
        {
          key: 'imputable', label: 'Imputable',
          text: function (c) { return c.imputable ? 'Oui' : 'Totalise'; },
          render: function (c) {
            return c.imputable ? U.badge('Imputable', 'success') : U.badge('Totalise', 'neutral');
          },
        },
        {
          key: 'mouvements', label: 'Écritures', align: 'right',
          value: function (c) { return soldeCompte(c.num).nb; },
          render: function (c) { return String(soldeCompte(c.num).nb); },
        },
        {
          key: 'solde', label: 'Solde', align: 'right',
          value: function (c) { return soldeCompte(c.num).solde; },
          text: function (c) { return C.money(soldeCompte(c.num).solde, false); },
          render: function (c) {
            var s = soldeCompte(c.num).solde;
            return el('span', { class: s < 0 ? 'font-semibold text-danger-600' : 'font-semibold', text: C.money(s, false) });
          },
        },
      ],
      fields: [
        { name: 'num', label: 'Numéro de compte', required: true, help: 'Code SYSCOHADA — de 1 à 4 chiffres (4011, 5711, 2458…).' },
        { name: 'libelle', label: 'Intitulé', required: true, col: 'full' },
        { name: 'classe', label: 'Classe', type: 'select', required: true, options: [1, 2, 3, 4, 5, 6, 7, 8].map(function (n) { return { value: n, label: classeLibelle(n) }; }) },
        { name: 'journal', label: 'Journal usuel', type: 'select', required: true, options: D.JOURNAUX.map(function (j) { return { value: j.code, label: j.code + ' — ' + j.libelle }; }) },
      ],
      transform: function (v) { v.classe = Number(v.classe); if (!v.source) v.source = 'CDCT'; return v; },
      beforeSave: function (v, record) {
        if (!/^[1-9]\d{0,3}$/.test(String(v.num))) return 'Le code SYSCOHADA comporte de 1 à 4 chiffres et ne commence pas par zéro.';
        if (!record && comptes().some(function (c) { return c.num === v.num; })) return 'Ce numéro de compte existe déjà.';
        return null;
      },
      filters: [
        { name: 'classe', label: 'Classe', options: [1, 2, 3, 4, 5, 6, 7, 8].map(function (n) { return { value: String(n), label: classeLibelle(n) }; }), match: function (c, v) { return String(c.classe) === v; } },
        { name: 'journal', label: 'Journal', options: D.JOURNAUX.map(function (j) { return { value: j.code, label: j.libelle }; }) },
        { name: 'imputable', label: 'Imputation',
          options: [{ value: 'oui', label: 'Comptes imputables' }, { value: 'non', label: 'Comptes qui totalisent' }],
          match: function (c, v) { return v === 'oui' ? !!c.imputable : !c.imputable; } },
      ],
      kpis: function (rows) {
        return [
          { label: 'Comptes paramétrés', value: C.num(rows.length), icon: 'list-tree', tone: 'navy' },
          { label: 'Comptes imputables', value: C.num(rows.filter(function (c) { return c.imputable; }).length), icon: 'file-check-2', tone: 'success', hint: 'les autres totalisent' },
          { label: 'Classes utilisées', value: C.num(Object.keys(C.groupBy(rows, 'classe')).length), icon: 'layers', tone: 'info' },
          { label: 'Comptes mouvementés', value: C.num(rows.filter(function (c) { return soldeCompte(c.num).nb > 0; }).length), icon: 'activity', tone: 'neutral' },
        ];
      },
      extraTabs: [{
        id: 'classes', label: 'Par classe',
        render: function () {
          var g = C.groupBy(comptes(), 'classe');
          var wrap = el('div.space-y-4');
          C.sortBy(Object.keys(g).map(Number)).forEach(function (cl) {
            wrap.appendChild(U.card(classeLibelle(cl), K.miniTable([
              { label: 'Compte', render: function (c) { return el('span.font-mono.text-xs', { text: c.num }); } },
              { label: 'Intitulé', key: 'libelle' },
              { label: 'Journal', render: function (c) { return U.badge(c.journal, 'neutral'); } },
              { label: 'Solde', align: 'right', render: function (c) { return C.money(soldeCompte(c.num).solde, false); } },
            ], C.sortBy(g[cl], 'num'))));
          });
          return wrap;
        },
      }],
    }),
    actions: function () {
      return [K.btn('Imprimer le plan comptable', {
        variant: 'primary', icon: 'printer',
        onclick: function () {
          P.etat({
            titre: 'Plan comptable SYSCOHADA',
            sousTitre: 'Référentiel des comptes utilisés par la clinique',
            cartouche: [['Comptes paramétrés', C.num(comptes().length)],
              ['Classes', C.num(Object.keys(C.groupBy(comptes(), 'classe')).length)],
              ['Exercice', '2026'], ['Date d’édition', C.dateFR(AUJ)]],
            contenu: P.tableau([
              { label: 'N° de compte', key: 'num' },
              { label: 'Intitulé', key: 'libelle' },
              { label: 'Classe', key: 'classe', align: 'right' },
              { label: 'Journal', key: 'journal' },
            ], C.sortBy(comptes(), 'num')),
            signatures: [{ role: 'Le Comptable', nom: 'SANOUSSI Adamon' },
              { role: 'La Direction', nom: 'SOKOU Peace' }],
          });
        },
      })];
    },
  });

  /* ==========================================================================
   * JOURNAUX COMPTABLES
   * ======================================================================== */
  global.SIGH.screen('m12-journaux', {
    title: 'Journaux comptables',
    regle: 'Écran <strong>calculé</strong> : un journal est la vue des écritures d’une nature donnée. '
      + 'Il ne se saisit pas — les écritures se corrigent depuis la saisie comptable, seul endroit où '
      + 'l’équilibre débit / crédit est contrôlé (RG-10).',
    description: 'Journaux d’achats, ventes, caisse, banque, salaires, immobilisations et opérations diverses.',
    render: function (root) {
      var host = el('div.space-y-4');
      var e = ecritures();

      var lignes = D.JOURNAUX.map(function (j) {
        var sel = e.filter(function (x) { return x.journal === j.code; });
        return {
          id: j.code, code: j.code, libelle: j.libelle,
          contrepartie: j.contrepartie,
          nb: sel.length, debit: C.sum(sel, 'debit'), credit: C.sum(sel, 'credit'),
          equilibre: C.sum(sel, 'debit') === C.sum(sel, 'credit'),
        };
      });

      host.appendChild(U.kpiGrid([
        { label: 'Journaux ouverts', value: C.num(lignes.length), icon: 'book', tone: 'navy' },
        { label: 'Écritures totales', value: C.num(e.length), icon: 'file-text', tone: 'info' },
        { label: 'Total débit', value: C.money(C.sum(e, 'debit')), icon: 'arrow-down-left', tone: 'warning' },
        { label: 'Total crédit', value: C.money(C.sum(e, 'credit')), icon: 'arrow-up-right', tone: 'success' },
      ]));

      host.appendChild(U.dataTable({
        title: 'Journaux comptables', rows: lignes, exportName: 'journaux', pageSize: 10,
        columns: [
          { key: 'code', label: 'Code', nowrap: true, render: function (j) { return el('span.font-mono.text-xs.font-semibold.text-navy-800', { text: j.code }); } },
          { key: 'libelle', label: 'Intitulé' },
          { key: 'contrepartie', label: 'Compte de contrepartie', render: function (j) { return j.contrepartie ? el('span.font-mono.text-xs', { text: j.contrepartie }) : el('span.text-xs.text-slate-400', { text: 'Variable' }); } },
          { key: 'nb', label: 'Écritures', align: 'right' },
          { key: 'debit', label: 'Total débit', align: 'right', text: function (j) { return C.money(j.debit, false); }, render: function (j) { return C.money(j.debit, false); } },
          { key: 'credit', label: 'Total crédit', align: 'right', text: function (j) { return C.money(j.credit, false); }, render: function (j) { return C.money(j.credit, false); } },
          {
            key: 'equilibre', label: 'Équilibre',
            text: function (j) { return j.equilibre ? 'Équilibré' : 'Déséquilibré'; },
            render: function (j) {
              return j.equilibre ? U.badge('Équilibré', 'success')
                : U.badge('Écart ' + C.money(Math.abs(j.debit - j.credit), false), 'danger');
            },
          },
        ],
        onRowClick: function (j) { consulter(j); },
        rowActions: function (j) {
          return [
            K.iconBtn('eye', 'Consulter le journal', function () { consulter(j); }),
            K.iconBtn('printer', 'Imprimer', function () { imprimer(j); }),
          ];
        },
      }));
      root.appendChild(host);
      return null;

      function consulter(j) {
        var sel = C.sortBy(e.filter(function (x) { return x.journal === j.code; }), 'date', 'desc');
        U.drawer({
          title: j.libelle, subtitle: 'Journal ' + j.code + ' — ' + sel.length + ' écriture(s)', width: 'max-w-4xl',
          body: el('div.space-y-4', null, [
            U.kpiGrid([
              { label: 'Total débit', value: C.money(j.debit), icon: 'arrow-down-left', tone: 'warning' },
              { label: 'Total crédit', value: C.money(j.credit), icon: 'arrow-up-right', tone: 'success' },
            ], 'grid-cols-2'),
            K.miniTable([
              { label: 'N° pièce', render: function (x) { return el('span.font-mono.text-xs', { text: x.numero }); } },
              { label: 'Date', render: function (x) { return C.dateFR(x.date); } },
              { label: 'Compte', render: function (x) { return el('span.font-mono.text-xs', { text: x.compte }); } },
              { label: 'Libellé', key: 'libelle' },
              { label: 'Débit', align: 'right', render: function (x) { return x.debit ? C.money(x.debit, false) : '—'; } },
              { label: 'Crédit', align: 'right', render: function (x) { return x.credit ? C.money(x.credit, false) : '—'; } },
            ], sel.slice(0, 40)),
          ]),
          footer: [K.btn('Imprimer le journal', { variant: 'primary', icon: 'printer', onclick: function () { imprimer(j); } })],
        });
      }

      function imprimer(j) {
        var sel = C.sortBy(e.filter(function (x) { return x.journal === j.code; }), 'date');
        P.etat({
          titre: 'Journal comptable — ' + j.libelle,
          sousTitre: 'Code journal ' + j.code + ' — exercice 2026',
          cartouche: [['Journal', j.code + ' — ' + j.libelle], ['Écritures', C.num(sel.length)],
            ['Total débit', C.money(j.debit)], ['Total crédit', C.money(j.credit)],
            ['Équilibre', j.equilibre ? 'Équilibré' : 'Écart de ' + C.money(Math.abs(j.debit - j.credit))],
            ['Date d’édition', C.dateFR(AUJ)]],
          contenu: P.tableau([
            { label: 'N° pièce', key: 'numero' },
            { label: 'Date', value: function (x) { return C.dateFR(x.date); } },
            { label: 'Compte', key: 'compte' },
            { label: 'Intitulé du compte', value: function (x) { return x.compteLibelle || compteLibelle(x.compte); } },
            { label: 'Libellé de l’opération', key: 'libelle' },
            /* LES TOTAUX DU JOURNAL SE REFONT DEPUIS SES PROPRES ÉCRITURES.
               Ils étaient transmis sous des clés qu'aucune colonne ne portait
               et ne s'imprimaient pas : un journal comptable dont le pied est
               vide ne prouve plus son équilibre (RG-10) au lecteur. */
            { label: 'Débit', align: 'right', value: function (x) { return x.debit ? C.money(x.debit, false) : ''; }, somme: function (x) { return x.debit; } },
            { label: 'Crédit', align: 'right', value: function (x) { return x.credit ? C.money(x.credit, false) : ''; }, somme: function (x) { return x.credit; } },
          ], sel, { total: true, totalLabel: 'TOTAUX' }),
          signatures: [{ role: 'Le Comptable', nom: 'SANOUSSI Adamon' },
            { role: 'La Direction', nom: 'SOKOU Peace' }],
        });
      }
    },
  });

  /* ==========================================================================
   * ÉCRITURES COMPTABLES
   * ======================================================================== */
  global.SIGH.screen('m12-ecritures', {
    title: 'Écritures comptables',
    description: 'Saisie, consultation et validation des écritures, avec contrôle d’équilibre.',
    regle: '<strong>RG-10</strong> — toute écriture doit être équilibrée (total débit = total crédit) avant validation dans le journal correspondant.',
    render: function (root) {
      var col = S.collection('ecritures', { module: 'M12', entite: 'EcritureComptable' });
      var host = el('div.space-y-4');
      var table;

      host.appendChild(U.kpiGrid([
        { label: 'Écritures enregistrées', value: C.num(col.active().length), icon: 'file-text', tone: 'navy' },
        { label: 'Validées', value: C.num(col.active().filter(function (e) { return e.statut === 'validee'; }).length), icon: 'check-circle-2', tone: 'success' },
        { label: 'En brouillon', value: C.num(col.active().filter(function (e) { return e.statut === 'brouillon'; }).length), icon: 'file-clock', tone: 'warning' },
        { label: 'Automatiques', value: C.num(col.active().filter(function (e) { return String(e.origine).indexOf('Automatique') === 0; }).length), icon: 'zap', tone: 'info' },
      ]));

      table = U.dataTable({
        title: 'Écritures comptables',
        rows: function () { return col.active(); },
        exportName: 'ecritures', pageSize: 20,
        defaultSort: 'date', defaultDir: 'desc',
        filters: [
          { name: 'journal', label: 'Journal', options: D.JOURNAUX.map(function (j) { return { value: j.code, label: j.libelle }; }) },
          { name: 'statut', label: 'Statut', options: [{ value: 'validee', label: 'Validée' }, { value: 'brouillon', label: 'Brouillon' }] },
          { name: 'centreCout', label: 'Centre de coûts', options: optionsCentres() },
        ],
        actions: [K.commande('Nouvelle écriture', { variant: 'primary', size: 'sm', icon: 'plus', onclick: function () { ouvrir(); } })].filter(Boolean),
        columns: [
          colNumeroEcr, colDateEcr, colJournal, colCompte,
          { key: 'libelle', label: 'Libellé de l’opération' },
          colDebit, colCredit,
          { key: 'centreCout', label: 'Centre de coûts', text: centreLabel, render: function (e) { return el('span.text-xs.text-slate-500', { text: centreLabel(e.centreCout) }); } },
          { key: 'origine', label: 'Origine', render: function (e) { return U.badge(e.origine, String(e.origine).indexOf('Automatique') === 0 ? 'info' : 'neutral'); } },
          { key: 'statut', label: 'Statut', render: function (e) { return U.statut(e.statut); } },
        ],
        onRowClick: function (e) { consulter(e); },
        rowActions: function (e) {
          var acts = [K.iconBtn('eye', 'Consulter', function () { consulter(e); })];
          if (e.statut === 'brouillon') {
            acts.push(K.iconBtn('check', 'Valider', function () {
              var res = col.update(e.id, { statut: 'validee' });
              table.refresh();
              U.toast('Écriture validée.', { type: 'success', undo: function () { res.undo(); table.refresh(); } });
            }, 'ghost'));
          }
          acts.push(K.iconBtn('archive', 'Archiver', function () {
            var res = col.archive(e.id);
            table.refresh();
            U.toast('Écriture archivée.', { type: 'success', undo: function () { res.undo(); table.refresh(); } });
          }, 'ghost'));
          return acts;
        },
      });
      host.appendChild(table);
      root.appendChild(host);
      return null;

      /* Saisie en partie double : plusieurs lignes, contrôle d'équilibre. */
      function ouvrir() {
        var lignes = [];
        var body = el('div.space-y-4');

        var f = U.form([
          { name: 'date', label: 'Date de l’opération', type: 'date', required: true, value: C.iso(AUJ) },
          { name: 'journal', label: 'Journal', type: 'select', required: true, options: D.JOURNAUX.map(function (j) { return { value: j.code, label: j.code + ' — ' + j.libelle }; }) },
          { name: 'libelle', label: 'Libellé de l’opération', required: true, col: 'full' },
          {
            name: 'centreCout', label: 'Centre de coûts', type: 'select', options: optionsCentres(),
            help: 'Axe d’imputation analytique. Un centre manquant se crée depuis le bouton ci-dessous, sans quitter la saisie.',
          },
          { name: 'piece', label: 'Référence de la pièce justificative' },
        ], {});
        body.appendChild(f);

        var ajout = el('div.flex.flex-wrap.items-end.gap-2.rounded-lg.border.border-slate-200.bg-slate-50.p-3');
        var listeComptes = C.sortBy(comptes(), 'num');
        var selCompte = U.combo(listeComptes.map(function (c) {
          return { value: c.num, label: c.libelle, detail: 'Compte ' + c.num, icon: 'hash' };
        }), {
          value: listeComptes.length ? listeComptes[0].num : '',
          searchPlaceholder: 'Numéro ou libellé du compte…',
          placeholder: 'Choisir un compte',
        });
        var debit = el('input.input.w-32', { type: 'number', min: 0, value: 0 });
        var credit = el('input.input.w-32', { type: 'number', min: 0, value: 0 });
        ajout.appendChild(el('div.min-w-\\[18rem\\].flex-1', null, [el('label.label', { text: 'Compte' }), selCompte]));
        ajout.appendChild(el('div', null, [el('label.label', { text: 'Débit' }), debit]));
        ajout.appendChild(el('div', null, [el('label.label', { text: 'Crédit' }), credit]));
        ajout.appendChild(K.btn('Ajouter la ligne', {
          variant: 'primary', icon: 'plus',
          onclick: function () {
            var d = Number(debit.value) || 0, cr = Number(credit.value) || 0;
            if (d === 0 && cr === 0) { U.toast('Renseigner un montant au débit ou au crédit.', { type: 'error' }); return; }
            if (d > 0 && cr > 0) { U.toast('Une ligne ne peut être simultanément au débit et au crédit.', { type: 'error' }); return; }
            lignes.push({ compte: selCompte.value, compteLibelle: compteLibelle(selCompte.value), debit: d, credit: cr });
            debit.value = 0; credit.value = 0;
            maj();
          },
        }));
        body.appendChild(ajout);

        var lignesHost = el('div');
        body.appendChild(lignesHost);

        function maj() {
          C.clear(lignesHost);
          var td = C.sum(lignes, 'debit'), tc = C.sum(lignes, 'credit');
          var equilibre = td === tc && td > 0;

          if (!lignes.length) {
            lignesHost.appendChild(U.empty('Aucune ligne saisie.', { icon: 'list' }));
          } else {
            var t = el('table.tbl');
            t.appendChild(el('thead', null, el('tr', null, [
              el('th', { text: 'Compte' }), el('th.text-right', { text: 'Débit' }),
              el('th.text-right', { text: 'Crédit' }), el('th'),
            ])));
            var tb = el('tbody');
            lignes.forEach(function (l, i) {
              tb.appendChild(el('tr', null, [
                el('td', null, el('div', null, [
                  el('p.font-mono.text-xs.font-semibold', { text: l.compte }),
                  el('p.text-xs.text-slate-400', { text: l.compteLibelle }),
                ])),
                el('td.text-right.num', { text: l.debit ? C.money(l.debit, false) : '—' }),
                el('td.text-right.num', { text: l.credit ? C.money(l.credit, false) : '—' }),
                el('td.text-right', null, K.iconBtn('x', 'Retirer', function () { lignes.splice(i, 1); maj(); }, 'ghost')),
              ]));
            });
            t.appendChild(tb);
            t.appendChild(el('tfoot', null, el('tr', null, [
              el('td.font-semibold', { text: 'TOTAUX' }),
              el('td.text-right.num.font-bold', { text: C.money(td, false) }),
              el('td.text-right.num.font-bold', { text: C.money(tc, false) }),
              el('td'),
            ])));
            lignesHost.appendChild(el('div.overflow-x-auto.rounded-lg.border.border-slate-200', null, t));
          }

          lignesHost.appendChild(equilibre
            ? K.note('<strong>RG-10 respectée</strong> — l’écriture est équilibrée : débit = crédit = ' + C.money(td) + '.', { tone: 'success', icon: 'scale' })
            : K.note('<strong>RG-10</strong> — l’écriture n’est pas équilibrée : écart de <strong>' + C.money(Math.abs(td - tc))
              + '</strong>. La validation est impossible tant que débit ≠ crédit.', { tone: 'danger', icon: 'scale-3d' }));
          U.icons(lignesHost);
        }
        maj();

        var m = U.modal({
          title: 'Nouvelle écriture comptable',
          subtitle: 'Saisie en partie double — contrôle d’équilibre appliqué (RG-10)',
          size: 'xl', body: body,
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            /* Créer un centre de coûts sans quitter la saisie : attendre une
               livraison pour imputer une charge n'aurait pas de sens. */
            K.btn('Nouveau centre de coûts', {
              icon: 'target',
              onclick: function () {
                var cf = U.form([
                  { name: 'libelle', label: 'Intitulé du centre', required: true, col: 'full' },
                  {
                    name: 'type', label: 'Type', type: 'select', required: true,
                    options: [{ value: 'exploitation', label: 'Centre d’exploitation' }, { value: 'support', label: 'Centre de support' }],
                  },
                  { name: 'responsable', label: 'Responsable', col: 'full' },
                ], {});
                var mc = U.modal({
                  title: 'Nouveau centre de coûts', size: 'md', body: cf,
                  footer: [
                    K.btn('Annuler', { onclick: function () { mc.close(); } }),
                    K.btn('Créer', {
                      variant: 'primary', icon: 'plus',
                      onclick: function () {
                        var cv = cf.collect();
                        if (!cv) return;
                        cv.code = 'CC' + C.pad(colCentres().all().length + 1, 2);
                        cv.source = 'Créé depuis la saisie comptable';
                        var res = colCentres().insert(cv);
                        mc.close();
                        /* Le combo n'est pas un <select> : on renouvelle ses
                           entrées par setOptions, puis on choisit la nouvelle. */
                        var ctrl = f.controls.centreCout;
                        if (ctrl && ctrl.setOptions) { ctrl.setOptions(optionsCentres(), true); ctrl.value = res.record.code; }
                        U.toast('Centre « ' + cv.libelle + ' » créé et sélectionné.', { type: 'success' });
                      },
                    }),
                  ],
                });
              },
            }),
            K.btn('Enregistrer en brouillon', {
              onclick: function () { enregistrer('brouillon'); },
            }),
            K.btn('Valider l’écriture', {
              variant: 'primary', icon: 'check',
              onclick: function () { enregistrer('validee'); },
            }),
          ],
        });

        function enregistrer(statut) {
          var v = f.collect();
          if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
          if (!lignes.length) { U.toast('Ajouter au moins une ligne.', { type: 'error' }); return; }
          var td = C.sum(lignes, 'debit'), tc = C.sum(lignes, 'credit');
          if (statut === 'validee' && td !== tc) {
            U.toast('RG-10 — écriture déséquilibrée : validation impossible.', {
              type: 'error', detail: 'Écart de ' + C.money(Math.abs(td - tc)) + '.',
            });
            return;
          }
          var num = v.journal + '-2026-' + C.pad(col.active().length + 1, 5);
          var crees = lignes.map(function (l) {
            return col.insert({
              numero: num, date: v.date, journal: v.journal, journalLibelle: journalLibelle(v.journal),
              compte: l.compte, compteLibelle: l.compteLibelle,
              libelle: v.libelle, debit: l.debit, credit: l.credit,
              centreCout: v.centreCout, piece: v.piece,
              origine: 'Saisie manuelle', statut: statut,
            });
          });
          m.close(); table.refresh();
          U.toast('Écriture ' + num + ' enregistrée (' + crees.length + ' ligne(s)).', {
            type: 'success',
            detail: statut === 'validee' ? 'Validée et équilibrée.' : 'Enregistrée en brouillon.',
            undo: function () { crees.forEach(function (r) { r.undo(); }); table.refresh(); },
          });
        }
      }

      function consulter(e) {
        var memeNumero = col.active().filter(function (x) { return x.numero === e.numero; });
        var td = C.sum(memeNumero, 'debit'), tc = C.sum(memeNumero, 'credit');
        U.drawer({
          title: 'Écriture ' + e.numero, subtitle: e.libelle + ' — ' + C.dateFR(e.date), width: 'max-w-3xl',
          body: el('div.space-y-4', null, [
            U.descList([['N° de pièce', e.numero], ['Date', C.dateFR(e.date)],
              ['Journal', journalLibelle(e.journal)], ['Libellé', e.libelle],
              ['Centre de coûts', centreLabel(e.centreCout)], ['Origine', e.origine],
              ['Pièce justificative', e.piece || '—'], ['Statut', U.statut(e.statut)]]),
            U.card('Lignes de l’écriture', K.miniTable([
              { label: 'Compte', render: function (x) { return el('span.font-mono.text-xs', { text: x.compte }); } },
              { label: 'Intitulé', render: function (x) { return x.compteLibelle || compteLibelle(x.compte); } },
              { label: 'Débit', align: 'right', render: function (x) { return x.debit ? C.money(x.debit, false) : '—'; } },
              { label: 'Crédit', align: 'right', render: function (x) { return x.credit ? C.money(x.credit, false) : '—'; } },
            ], memeNumero)),
            td === tc
              ? K.note('Écriture équilibrée : débit = crédit = ' + C.money(td) + ' (RG-10).', { tone: 'success', icon: 'scale' })
              : K.note('Écart de ' + C.money(Math.abs(td - tc)) + ' entre débit et crédit (RG-10).', { tone: 'danger', icon: 'scale-3d' }),
          ]),
        });
      }
    },
  });

  /* ==========================================================================
   * GRAND LIVRE
   * ======================================================================== */
  global.SIGH.screen('m12-grand-livre', {
    title: 'Grand livre',
    description: 'Détail chronologique des mouvements par compte, avec solde progressif.',
    regle: 'Écran en lecture seule. Le grand livre est <strong>reconstitué depuis les écritures</strong> : il ne se modifie pas ici. Toute correction passe par l’écriture d’origine (Écritures comptables), qui doit rester équilibrée (RG-10).',
    render: function (root) {
      var host = el('div.space-y-4');
      var mouvementes = comptes().filter(function (c) { return soldeCompte(c.num).nb > 0; });

      var listeMvt = C.sortBy(mouvementes, 'num');
      var selCompte = U.combo(listeMvt.map(function (c) {
        return { value: c.num, label: c.libelle, detail: 'Compte ' + c.num, icon: 'hash' };
      }), {
        value: listeMvt.length ? listeMvt[0].num : '',
        searchPlaceholder: 'Numéro ou libellé du compte…',
        placeholder: 'Choisir un compte',
      });
      selCompte.classList.add('max-w-lg');

      var barre = el('div.card');
      var bbody = el('div.card-body.flex.flex-wrap.items-end.gap-3');
      bbody.appendChild(el('div.flex-1', null, [el('label.label', { text: 'Compte' }), selCompte]));
      bbody.appendChild(K.btn('Imprimer le grand livre', { variant: 'primary', icon: 'printer', onclick: imprimer }));
      bbody.appendChild(K.btn('Grand livre complet', { icon: 'book-open', onclick: imprimerComplet }));
      barre.appendChild(bbody);
      host.appendChild(barre);

      var vue = el('div.space-y-4');
      host.appendChild(vue);
      selCompte.addEventListener('change', afficher);
      root.appendChild(host);
      afficher();
      return null;

      function mouvements() {
        return C.sortBy(ecritures().filter(function (e) { return e.compte === selCompte.value; }), 'date');
      }

      function avecSolde() {
        var solde = 0;
        return mouvements().map(function (e) {
          solde += (e.debit || 0) - (e.credit || 0);
          return Object.assign({}, e, { soldeProgressif: solde });
        });
      }

      function afficher() {
        var rows = avecSolde();
        var s = soldeCompte(selCompte.value);
        C.clear(vue);

        vue.appendChild(U.kpiGrid([
          { label: 'Mouvements', value: C.num(rows.length), icon: 'file-text', tone: 'navy' },
          { label: 'Total débit', value: C.money(s.debit), icon: 'arrow-down-left', tone: 'warning' },
          { label: 'Total crédit', value: C.money(s.credit), icon: 'arrow-up-right', tone: 'success' },
          { label: 'Solde', value: C.money(s.solde), icon: 'scale', tone: s.solde >= 0 ? 'navy' : 'danger', hint: s.solde >= 0 ? 'Débiteur' : 'Créditeur' },
        ]));

        vue.appendChild(U.dataTable({
          title: selCompte.value + ' — ' + compteLibelle(selCompte.value),
          rows: rows, exportName: 'grand-livre-' + selCompte.value, pageSize: 20,
          emptyMessage: 'Aucun mouvement sur ce compte.',
          columns: [
            colNumeroEcr, colDateEcr, colJournal,
            { key: 'libelle', label: 'Libellé' },
            { key: 'piece', label: 'Pièce' },
            colDebit, colCredit,
            {
              key: 'soldeProgressif', label: 'Solde', align: 'right', sortable: false,
              text: function (e) { return C.money(e.soldeProgressif, false); },
              render: function (e) {
                return el('span.font-semibold', {
                  class: e.soldeProgressif < 0 ? 'text-danger-600' : 'text-navy-900',
                  text: C.money(e.soldeProgressif, false),
                });
              },
            },
          ],
        }));
        U.icons(vue);
      }

      function imprimer() {
        var rows = avecSolde();
        var s = soldeCompte(selCompte.value);
        P.etat({
          titre: 'Grand livre',
          sousTitre: 'Compte ' + selCompte.value + ' — ' + compteLibelle(selCompte.value),
          cartouche: [['Compte', selCompte.value], ['Intitulé', compteLibelle(selCompte.value)],
            ['Mouvements', C.num(rows.length)], ['Total débit', C.money(s.debit)],
            ['Total crédit', C.money(s.credit)], ['Solde', C.money(s.solde)]],
          contenu: P.tableau([
            { label: 'Date', value: function (e) { return C.dateFR(e.date); } },
            { label: 'N° pièce', key: 'numero' },
            { label: 'Journal', key: 'journal' },
            { label: 'Libellé', key: 'libelle' },
            { label: 'Débit', align: 'right', value: function (e) { return e.debit ? C.money(e.debit, false) : ''; },
              somme: function (e) { return e.debit || 0; } },
            { label: 'Crédit', align: 'right', value: function (e) { return e.credit ? C.money(e.credit, false) : ''; },
              somme: function (e) { return e.credit || 0; } },
            { label: 'Solde', align: 'right', value: function (e) { return C.money(e.soldeProgressif, false); } },
          ], rows, { total: true }),
          signatures: [{ role: 'Le Comptable', nom: 'SANOUSSI Adamon' }],
        });
      }

      function imprimerComplet() {
        var blocs = el('div.space-y-4');
        C.sortBy(mouvementes, 'num').forEach(function (c) {
          var s = soldeCompte(c.num);
          var mvts = C.sortBy(ecritures().filter(function (e) { return e.compte === c.num; }), 'date');
          blocs.appendChild(el('div', null, [
            el('p.mb-1.mt-3.text-\\[11px\\].font-bold.text-navy-900', { text: c.num + ' — ' + c.libelle + '  (solde : ' + C.money(s.solde, false) + ')' }),
            P.tableau([
              { label: 'Date', value: function (e) { return C.dateFR(e.date); } },
              { label: 'N° pièce', key: 'numero' },
              { label: 'Libellé', key: 'libelle' },
              { label: 'Débit', align: 'right', value: function (e) { return e.debit ? C.money(e.debit, false) : ''; } },
              { label: 'Crédit', align: 'right', value: function (e) { return e.credit ? C.money(e.credit, false) : ''; } },
            ], mvts.slice(0, 15)),
          ]));
        });
        P.etat({
          titre: 'Grand livre général',
          sousTitre: 'Exercice 2026 — tous comptes mouvementés',
          cartouche: [['Comptes mouvementés', C.num(mouvementes.length)],
            ['Écritures', C.num(ecritures().length)],
            ['Total débit', C.money(C.sum(ecritures(), 'debit'))],
            ['Total crédit', C.money(C.sum(ecritures(), 'credit'))]],
          contenu: blocs,
          signatures: [{ role: 'Le Comptable', nom: 'SANOUSSI Adamon' },
            { role: 'La Direction', nom: 'SOKOU Peace' }],
        });
      }
    },
  });

  /* ==========================================================================
   * BALANCE
   * ======================================================================== */
  global.SIGH.screen('m12-balance', {
    title: 'Balance générale & âgée',
    description: 'Balance des comptes, contrôle d’équilibre et balance âgée des comptes de tiers.',
    regle: 'Écran en lecture seule. La balance est <strong>calculée à partir des écritures validées</strong>. Elle ne se saisit pas : corriger l’écriture concernée pour la faire évoluer.',
    render: function (root) {
      var host = el('div.space-y-4');

      var lignes = comptes().map(function (c) {
        var s = soldeCompte(c.num);
        return {
          id: c.num, num: c.num, libelle: c.libelle, classe: c.classe,
          debit: s.debit, credit: s.credit,
          soldeDebiteur: s.solde > 0 ? s.solde : 0,
          soldeCrediteur: s.solde < 0 ? -s.solde : 0,
          nb: s.nb,
        };
      }).filter(function (l) { return l.nb > 0; });

      var totalDebit = C.sum(lignes, 'debit');
      var totalCredit = C.sum(lignes, 'credit');
      var equilibre = totalDebit === totalCredit;

      host.appendChild(U.kpiGrid([
        { label: 'Comptes mouvementés', value: C.num(lignes.length), icon: 'list', tone: 'navy' },
        { label: 'Total débit', value: C.money(totalDebit), icon: 'arrow-down-left', tone: 'warning' },
        { label: 'Total crédit', value: C.money(totalCredit), icon: 'arrow-up-right', tone: 'success' },
        {
          label: 'Équilibre (RG-10)', value: equilibre ? 'Équilibrée' : C.money(Math.abs(totalDebit - totalCredit)),
          icon: equilibre ? 'scale' : 'scale-3d', tone: equilibre ? 'success' : 'danger',
        },
      ]));

      host.appendChild(equilibre
        ? K.note('La balance est <strong>équilibrée</strong> : le total des débits est égal au total des crédits (RG-10).', { tone: 'success', icon: 'scale' })
        : K.note('<strong>Balance déséquilibrée</strong> — écart de ' + C.money(Math.abs(totalDebit - totalCredit))
          + '. Ce contrôle doit être régularisé avant toute clôture (RG-10).', { tone: 'danger', icon: 'scale-3d' }));

      host.appendChild(U.tabs([
        {
          id: 'generale', label: 'Balance générale',
          render: function () {
            return U.dataTable({
              rows: lignes, exportName: 'balance-generale', pageSize: 25,
              defaultSort: 'num',
              filters: [{ name: 'classe', label: 'Classe', options: [1, 2, 3, 4, 5, 6, 7, 8].map(function (n) { return { value: String(n), label: classeLibelle(n) }; }), match: function (l, v) { return String(l.classe) === v; } }],
              columns: [
                { key: 'num', label: 'Compte', nowrap: true, render: function (l) { return el('span.font-mono.text-xs.font-semibold', { text: l.num }); } },
                { key: 'libelle', label: 'Intitulé' },
                { key: 'classe', label: 'Classe', align: 'right', render: function (l) { return U.badge('C' + l.classe, 'neutral'); } },
                { key: 'nb', label: 'Mvts', align: 'right' },
                { key: 'debit', label: 'Mouvement débit', align: 'right', text: function (l) { return C.money(l.debit, false); }, render: function (l) { return C.money(l.debit, false); } },
                { key: 'credit', label: 'Mouvement crédit', align: 'right', text: function (l) { return C.money(l.credit, false); }, render: function (l) { return C.money(l.credit, false); } },
                { key: 'soldeDebiteur', label: 'Solde débiteur', align: 'right', text: function (l) { return l.soldeDebiteur ? C.money(l.soldeDebiteur, false) : ''; }, render: function (l) { return l.soldeDebiteur ? el('span.font-semibold', { text: C.money(l.soldeDebiteur, false) }) : '—'; } },
                { key: 'soldeCrediteur', label: 'Solde créditeur', align: 'right', text: function (l) { return l.soldeCrediteur ? C.money(l.soldeCrediteur, false) : ''; }, render: function (l) { return l.soldeCrediteur ? el('span.font-semibold', { text: C.money(l.soldeCrediteur, false) }) : '—'; } },
              ],
              actions: [K.btn('Imprimer la balance', { size: 'sm', icon: 'printer', onclick: imprimerBalance })],
            });
          },
        },
        {
          id: 'agee', label: 'Balance âgée (tiers)',
          render: function () {
            var factures = S.collection('factures').active();
            var tranches = [
              { label: 'Moins de 30 jours', min: 0, max: 30 },
              { label: '30 à 60 jours', min: 30, max: 60 },
              { label: '60 à 90 jours', min: 60, max: 90 },
              { label: 'Plus de 90 jours', min: 90, max: 99999 },
            ];
            var rows = tranches.map(function (t) {
              var sel = factures.filter(function (f) {
                var j = C.daysBetween(f.date, AUJ);
                return f.reliquat > 0 && j >= t.min && j < t.max;
              });
              var selAss = factures.filter(function (f) {
                var j = C.daysBetween(f.date, AUJ);
                return f.assureur && j >= t.min && j < t.max;
              });
              return {
                id: t.label, tranche: t.label,
                nbPatients: sel.length, montantPatients: C.sum(sel, 'reliquat'),
                nbAssureurs: selAss.length, montantAssureurs: C.sum(selAss, 'partAssurance'),
                total: C.sum(sel, 'reliquat') + C.sum(selAss, 'partAssurance'),
              };
            });
            return el('div.space-y-3', null, [
              K.note('La balance âgée ventile les créances par ancienneté afin de piloter le recouvrement auprès des patients et des tiers payeurs.', { tone: 'info' }),
              U.dataTable({
                rows: rows, exportName: 'balance-agee', searchable: false, pageSize: 10,
                columns: [
                  { key: 'tranche', label: 'Ancienneté' },
                  { key: 'nbPatients', label: 'Factures patients', align: 'right' },
                  { key: 'montantPatients', label: 'Créances patients', align: 'right', text: function (r) { return C.money(r.montantPatients, false); }, render: function (r) { return C.money(r.montantPatients, false); } },
                  { key: 'nbAssureurs', label: 'Factures assureurs', align: 'right' },
                  { key: 'montantAssureurs', label: 'Créances assureurs', align: 'right', text: function (r) { return C.money(r.montantAssureurs, false); }, render: function (r) { return C.money(r.montantAssureurs, false); } },
                  { key: 'total', label: 'Total', align: 'right', text: function (r) { return C.money(r.total, false); }, render: function (r) { return el('span.font-bold.text-navy-900', { text: C.money(r.total, false) }); } },
                ],
                actions: [K.btn('Imprimer la balance âgée', {
                  size: 'sm', icon: 'printer',
                  onclick: function () {
                    P.etat({
                      titre: 'Balance âgée des comptes de tiers',
                      sousTitre: 'Situation au ' + C.dateFR(AUJ),
                      cartouche: [['Créances totales', C.money(C.sum(rows, 'total'))],
                        ['Dont patients', C.money(C.sum(rows, 'montantPatients'))],
                        ['Dont assureurs', C.money(C.sum(rows, 'montantAssureurs'))],
                        ['Date d’édition', C.dateFR(AUJ)]],
                      contenu: P.tableau([
                        { label: 'Ancienneté', key: 'tranche' },
                        { label: 'Factures patients', key: 'nbPatients', align: 'right' },
                        { label: 'Créances patients', align: 'right', value: function (r) { return C.money(r.montantPatients, false); } },
                        { label: 'Factures assureurs', key: 'nbAssureurs', align: 'right' },
                        { label: 'Créances assureurs', align: 'right', value: function (r) { return C.money(r.montantAssureurs, false); } },
                        { label: 'Total', align: 'right', value: function (r) { return C.money(r.total, false); } },
                      ], rows),
                      signatures: [{ role: 'Le Comptable', nom: 'SANOUSSI Adamon' },
                        { role: 'La Direction', nom: 'SOKOU Peace' }],
                    });
                  },
                })],
              }),
            ]);
          },
        },
      ]));
      root.appendChild(host);
      return null;

      function imprimerBalance() {
        P.etat({
          titre: 'Balance générale des comptes',
          sousTitre: 'Exercice 2026 — situation au ' + C.dateFR(AUJ),
          cartouche: [['Comptes mouvementés', C.num(lignes.length)],
            ['Total débit', C.money(totalDebit)], ['Total crédit', C.money(totalCredit)],
            ['Équilibre', equilibre ? 'Équilibrée' : 'Écart de ' + C.money(Math.abs(totalDebit - totalCredit))],
            ['Exercice', '2026'], ['Date d’édition', C.dateFR(AUJ)]],
          contenu: P.tableau([
            { label: 'Compte', key: 'num' },
            { label: 'Intitulé', key: 'libelle' },
            { label: 'Mvt débit', align: 'right', value: function (l) { return C.money(l.debit, false); }, somme: function (l) { return l.debit; } },
            { label: 'Mvt crédit', align: 'right', value: function (l) { return C.money(l.credit, false); }, somme: function (l) { return l.credit; } },
            { label: 'Solde débiteur', align: 'right', value: function (l) { return l.soldeDebiteur ? C.money(l.soldeDebiteur, false) : ''; }, somme: function (l) { return l.soldeDebiteur; } },
            { label: 'Solde créditeur', align: 'right', value: function (l) { return l.soldeCrediteur ? C.money(l.soldeCrediteur, false) : ''; }, somme: function (l) { return l.soldeCrediteur; } },
          ], C.sortBy(lignes, 'num'), { total: true, totalLabel: 'TOTAUX' }),
          signatures: [{ role: 'Le Comptable', nom: 'SANOUSSI Adamon' },
            { role: 'La Direction', nom: 'SOKOU Peace' }],
        });
      }
    },
  });

  /* ==========================================================================
   * COMPTABILITÉ ANALYTIQUE
   * ======================================================================== */
  global.SIGH.screen('m12-analytique', {
    title: 'Comptabilité analytique',
    description: 'Charges et produits ventilés par centre de coûts et par secteur d’activité.',
    regle: 'Écran en lecture seule. La ventilation analytique est <strong>déduite du centre de coûts porté par chaque écriture</strong>. Elle se corrige en modifiant l’écriture.',
    render: function (root) {
      var host = el('div.space-y-4');
      var e = ecritures();

      var rows = D.CENTRES_COUT.map(function (cc) {
        var sel = e.filter(function (x) { return x.centreCout === cc.id; });
        var charges = C.sum(sel.filter(function (x) { return String(x.compte)[0] === '6'; }), 'debit');
        var produits = C.sum(sel.filter(function (x) { return String(x.compte)[0] === '7'; }), 'credit');
        return {
          id: cc.id, centre: cc.label, nb: sel.length,
          charges: charges, produits: produits, resultat: produits - charges,
          marge: produits ? Math.round((produits - charges) / produits * 100) : 0,
        };
      });

      host.appendChild(U.kpiGrid([
        { label: 'Centres de coûts', value: C.num(rows.length), icon: 'layers', tone: 'navy' },
        { label: 'Produits analysés', value: C.money(C.sum(rows, 'produits')), icon: 'trending-up', tone: 'success' },
        { label: 'Charges analysées', value: C.money(C.sum(rows, 'charges')), icon: 'trending-down', tone: 'warning' },
        { label: 'Résultat analytique', value: C.money(C.sum(rows, 'resultat')), icon: 'scale', tone: C.sum(rows, 'resultat') >= 0 ? 'success' : 'danger' },
      ]));

      host.appendChild(U.dataTable({
        title: 'Résultat par centre de coûts', rows: rows, exportName: 'analytique', pageSize: 15,
        defaultSort: 'resultat', defaultDir: 'desc', searchable: false,
        columns: [
          { key: 'centre', label: 'Centre de coûts / secteur' },
          { key: 'nb', label: 'Écritures', align: 'right' },
          { key: 'produits', label: 'Produits', align: 'right', text: function (r) { return C.money(r.produits, false); }, render: function (r) { return el('span.text-success-700', { text: C.money(r.produits, false) }); } },
          { key: 'charges', label: 'Charges', align: 'right', text: function (r) { return C.money(r.charges, false); }, render: function (r) { return el('span.text-danger-600', { text: C.money(r.charges, false) }); } },
          {
            key: 'resultat', label: 'Résultat', align: 'right',
            text: function (r) { return C.money(r.resultat, false); },
            render: function (r) {
              return el('span.font-bold', { class: r.resultat >= 0 ? 'text-success-700' : 'text-danger-600', text: C.money(r.resultat, false) });
            },
          },
          {
            key: 'marge', label: 'Marge', align: 'right',
            render: function (r) { return r.produits ? U.badge(r.marge + ' %', r.marge >= 0 ? 'success' : 'danger') : '—'; },
          },
        ],
        actions: [K.btn('Imprimer la balance analytique', {
          size: 'sm', icon: 'printer',
          onclick: function () {
            P.etat({
              titre: 'Balance analytique',
              sousTitre: 'Résultat par centre de coûts — exercice 2026',
              cartouche: [['Centres de coûts', C.num(rows.length)],
                ['Produits', C.money(C.sum(rows, 'produits'))],
                ['Charges', C.money(C.sum(rows, 'charges'))],
                ['Résultat', C.money(C.sum(rows, 'resultat'))]],
              contenu: P.tableau([
                { label: 'Centre de coûts', key: 'centre' },
                { label: 'Écritures', key: 'nb', align: 'right' },
                { label: 'Produits', align: 'right', value: function (r) { return C.money(r.produits, false); },
                  somme: function (r) { return r.produits || 0; } },
                { label: 'Charges', align: 'right', value: function (r) { return C.money(r.charges, false); },
                  somme: function (r) { return r.charges || 0; } },
                { label: 'Résultat', align: 'right', value: function (r) { return C.money(r.resultat, false); },
                  somme: function (r) { return r.resultat || 0; } },
              ], rows, { total: true }),
              signatures: [{ role: 'Le Comptable', nom: 'SANOUSSI Adamon' },
                { role: 'La Direction', nom: 'GBAGUIDI Rafiou' }],
            });
          },
        })],
      }));

      host.appendChild(K.charts([
        {
          title: 'Résultat par centre de coûts',
          render: function () {
            var tri = C.sortBy(rows, 'resultat', 'desc');
            return G.barres(tri.map(function (r) { return r.centre; }), [
              { label: 'Produits', data: tri.map(function (r) { return r.produits; }), color: G.TONES.vert },
              { label: 'Charges', data: tri.map(function (r) { return r.charges; }), color: G.TONES.rouge },
            ], { horizontal: true, height: 340 });
          },
        },
        {
          title: 'Poids des secteurs dans les produits',
          render: function () {
            var avec = rows.filter(function (r) { return r.produits > 0; });
            return G.anneau(avec.map(function (r) { return r.centre; }), avec.map(function (r) { return r.produits; }), { legend: 'bottom' });
          },
        },
      ]));
      root.appendChild(host);
      return null;
    },
  });

  /* ==========================================================================
   * BUDGETS
   * ======================================================================== */
  global.SIGH.screen('m12-budgets', {
    title: 'Budgets',
    description: 'Budgétisation par centre de coûts et suivi du réalisé par rapport au prévisionnel.',
    render: function (root) {
      var col = S.collection('budgets', { module: 'M12', entite: 'Budget' });
      if (!col.all().length) {
        var rnd = C.seeded(2213);
        D.CENTRES_COUT.forEach(function (cc, i) {
          var prevu = C.between(rnd, 3, 40) * 500000;
          col.all().push({
            id: 'BUD' + C.pad(i + 1, 3), statut: 'actif',
            reference: 'BG-2026-' + C.pad(i + 1, 3),
            exercice: 2026, centreCout: cc.id, centre: cc.label,
            nature: 'Charges de fonctionnement',
            prevu: prevu,
          });
        });
        S.save();
      }

      var e = ecritures();
      function realise(centreId) {
        return C.sum(e.filter(function (x) { return x.centreCout === centreId && String(x.compte)[0] === '6'; }), 'debit');
      }

      return K.crud({
        collection: 'budgets', entite: 'budget', entiteP: 'budgets', module: 'M12',
        defaultSort: 'prevu', defaultDir: 'desc', pageSize: 15,
        columns: [
          { key: 'reference', label: 'N°', nowrap: true, render: function (b) { return el('span.font-mono.text-xs', { text: b.reference }); } },
          { key: 'exercice', label: 'Exercice', align: 'right' },
          { key: 'centre', label: 'Centre de coûts' },
          { key: 'nature', label: 'Nature' },
          { key: 'prevu', label: 'Budget prévu', align: 'right', text: function (b) { return C.money(b.prevu, false); }, render: function (b) { return el('span.font-semibold', { text: C.money(b.prevu, false) }); } },
          {
            key: 'realise', label: 'Réalisé', align: 'right',
            value: function (b) { return realise(b.centreCout); },
            text: function (b) { return C.money(realise(b.centreCout), false); },
            render: function (b) { return C.money(realise(b.centreCout), false); },
          },
          {
            key: 'ecart', label: 'Disponible', align: 'right',
            value: function (b) { return b.prevu - realise(b.centreCout); },
            text: function (b) { return C.money(b.prevu - realise(b.centreCout), false); },
            render: function (b) {
              var d = b.prevu - realise(b.centreCout);
              return el('span.font-semibold', { class: d < 0 ? 'text-danger-600' : 'text-success-700', text: C.money(d, false) });
            },
          },
          {
            key: 'consommation', label: 'Consommation', align: 'right',
            value: function (b) { return b.prevu ? Math.round(realise(b.centreCout) / b.prevu * 100) : 0; },
            render: function (b) {
              var pct = b.prevu ? Math.round(realise(b.centreCout) / b.prevu * 100) : 0;
              var wrap = el('div.flex.items-center.justify-end.gap-2');
              wrap.appendChild(el('div.h-1\\.5.w-20.overflow-hidden.rounded-full.bg-slate-100', null,
                el('div.h-full.rounded-full', {
                  class: pct > 100 ? 'bg-danger-500' : (pct > 80 ? 'bg-warning-500' : 'bg-success-500'),
                  style: 'width:' + Math.min(100, Math.max(2, pct)) + '%;',
                })));
              wrap.appendChild(el('span.w-10.text-right.text-xs.num.font-medium', { text: pct + ' %' }));
              return wrap;
            },
          },
        ],
        fields: [
          { name: 'exercice', label: 'Exercice', type: 'number', required: true, value: 2026 },
          { name: 'centreCout', label: 'Centre de coûts', type: 'select', required: true, options: optionsCentres() },
          { name: 'nature', label: 'Nature budgétaire', type: 'select', required: true, options: ['Charges de fonctionnement', 'Investissements', 'Charges de personnel', 'Achats de marchandises'] },
          { name: 'prevu', label: 'Montant prévisionnel (FCFA)', type: 'money', required: true, min: 0 },
        ],
        transform: function (v) {
          v.centre = centreLabel(v.centreCout);
          if (!v.reference) v.reference = C.nextRef('BG-2026-', 3);
          return v;
        },
        kpis: function (rows) {
          var prevu = C.sum(rows, 'prevu');
          var real = C.sum(rows, function (b) { return realise(b.centreCout); });
          return [
            { label: 'Budget total prévu', value: C.money(prevu), icon: 'target', tone: 'navy' },
            { label: 'Budget consommé', value: C.money(real), icon: 'trending-down', tone: 'warning' },
            { label: 'Disponible', value: C.money(prevu - real), icon: 'wallet', tone: prevu - real >= 0 ? 'success' : 'danger' },
            { label: 'Taux de consommation', value: C.pct(prevu ? real / prevu * 100 : 0), icon: 'percent', tone: 'info' },
          ];
        },
        extraTabs: [{
          id: 'suivi', label: 'Budget vs réalisé',
          render: function () {
            var rows = col.active();
            return U.card('Comparaison budget prévisionnel et réalisé',
              G.barres(rows.map(function (b) { return b.centre; }), [
                { label: 'Prévu', data: rows.map(function (b) { return b.prevu; }), color: G.TONES.navy },
                { label: 'Réalisé', data: rows.map(function (b) { return realise(b.centreCout); }), color: G.TONES.orange },
              ], { horizontal: true, height: 380 }));
          },
        }],
      })(root);
    },
  });

  /* ==========================================================================
   * IMMOBILISATIONS & AMORTISSEMENTS
   * ======================================================================== */
  global.SIGH.screen('m12-immobilisations', {
    title: 'Immobilisations & amortissements',
    description: 'Registre des immobilisations, plan d’amortissement linéaire et valeur nette comptable.',
    render: function (root) {
      var col = S.collection('immobilisations', { module: 'M12', entite: 'Immobilisation' });
      if (!col.all().length) {
        var rnd = C.seeded(2311);
        var BIENS = [
          ['Échographe', 'Matériel médical', 8500000, 5, '2411'],
          ['Automate de biochimie', 'Matériel de laboratoire', 6200000, 5, '2411'],
          ['Groupe électrogène 30 kVA', 'Matériel technique', 4500000, 10, '2411'],
          ['Ambulance médicalisée', 'Matériel de transport', 18000000, 5, '2451'],
          ['Table d’opération', 'Matériel médical', 3200000, 10, '2411'],
          ['Lits d’hospitalisation (lot de 12)', 'Mobilier médical', 2400000, 10, '2411'],
          ['Onduleurs (lot)', 'Matériel technique', 1200000, 3, '2411'],
          ['Serveur et postes informatiques', 'Matériel informatique', 3800000, 3, '2411'],
          ['Climatiseurs (lot de 8)', 'Installations', 2800000, 5, '2411'],
          ['Stérilisateur autoclave', 'Matériel médical', 2100000, 8, '2411'],
        ];
        BIENS.forEach(function (b, i) {
          var acq = new Date(2020 + C.between(rnd, 0, 5), C.between(rnd, 0, 11), C.between(rnd, 1, 28));
          col.all().push({
            id: 'IMM' + C.pad(i + 1, 3), statut: 'actif',
            reference: 'IM-' + C.pad(i + 1, 3),
            designation: b[0], categorie: b[1],
            valeurAcquisition: b[2], dureeAmortissement: b[3], compte: b[4],
            dateAcquisition: C.iso(acq),
            fournisseur: C.pick(rnd, D.FOURNISSEURS).nom,
            etat: C.pick(rnd, ['En service', 'En service', 'En service', 'En maintenance']),
          });
        });
        S.save();
      }

      function annuite(im) { return Math.round(im.valeurAcquisition / im.dureeAmortissement); }
      function anneesEcoulees(im) {
        return Math.min(im.dureeAmortissement, Math.max(0, Math.floor(C.daysBetween(im.dateAcquisition, AUJ) / 365.25)));
      }
      function amortiCumule(im) { return annuite(im) * anneesEcoulees(im); }
      function vnc(im) { return Math.max(0, im.valeurAcquisition - amortiCumule(im)); }

      return K.crud({
        collection: 'immobilisations', entite: 'immobilisation', entiteP: 'immobilisations', module: 'M12',
        defaultSort: 'valeurAcquisition', defaultDir: 'desc', pageSize: 15, drawerWidth: 'max-w-2xl',
        columns: [
          { key: 'reference', label: 'N°', nowrap: true, render: function (i) { return el('span.font-mono.text-xs', { text: i.reference }); } },
          { key: 'designation', label: 'Désignation' },
          { key: 'categorie', label: 'Catégorie', render: function (i) { return U.badge(i.categorie, 'navy'); } },
          { key: 'dateAcquisition', label: 'Acquisition', nowrap: true, text: function (i) { return C.dateFR(i.dateAcquisition); }, render: function (i) { return C.dateFR(i.dateAcquisition); } },
          { key: 'valeurAcquisition', label: 'Valeur d’origine', align: 'right', text: function (i) { return C.money(i.valeurAcquisition, false); }, render: function (i) { return el('span.font-semibold', { text: C.money(i.valeurAcquisition, false) }); } },
          { key: 'dureeAmortissement', label: 'Durée', align: 'right', render: function (i) { return i.dureeAmortissement + ' ans'; } },
          { key: 'annuite', label: 'Annuité', align: 'right', value: annuite, text: function (i) { return C.money(annuite(i), false); }, render: function (i) { return C.money(annuite(i), false); } },
          { key: 'cumul', label: 'Amort. cumulé', align: 'right', value: amortiCumule, text: function (i) { return C.money(amortiCumule(i), false); }, render: function (i) { return el('span.text-danger-600', { text: C.money(amortiCumule(i), false) }); } },
          {
            key: 'vnc', label: 'Valeur nette', align: 'right',
            value: vnc, text: function (i) { return C.money(vnc(i), false); },
            render: function (i) { return el('span.font-bold.text-navy-900', { text: C.money(vnc(i), false) }); },
          },
          { key: 'etat', label: 'État', render: function (i) { return U.badge(i.etat, i.etat === 'En service' ? 'success' : 'warning'); } },
        ],
        fields: [
          { name: 'designation', label: 'Désignation du bien', required: true, col: 'full' },
          { name: 'categorie', label: 'Catégorie', type: 'select', required: true, options: ['Matériel médical', 'Matériel de laboratoire', 'Matériel technique', 'Matériel de transport', 'Mobilier médical', 'Matériel informatique', 'Installations'] },
          { name: 'dateAcquisition', label: 'Date d’acquisition', type: 'date', required: true },
          { name: 'valeurAcquisition', label: 'Valeur d’acquisition (FCFA)', type: 'money', required: true, min: 0 },
          { name: 'dureeAmortissement', label: 'Durée d’amortissement (années)', type: 'number', required: true, min: 1, max: 30 },
          { name: 'compte', label: 'Compte d’immobilisation', type: 'select', options: D.PLAN_COMPTABLE.filter(function (c) { return c.classe === 2; }).map(function (c) { return { value: c.num, label: c.num + ' — ' + c.libelle }; }) },
          { name: 'fournisseur', label: 'Fournisseur' },
          { name: 'etat', label: 'État', type: 'select', options: ['En service', 'En maintenance', 'Hors service', 'Cédé'] },
        ],
        transform: function (v) { if (!v.reference) v.reference = C.nextRef('IM-', 3); return v; },
        onCreate: function () { return { dateAcquisition: C.iso(AUJ), dureeAmortissement: 5, etat: 'En service', compte: '2411' }; },
        filters: [
          { name: 'categorie', label: 'Catégorie', options: ['Matériel médical', 'Matériel de laboratoire', 'Matériel technique', 'Matériel de transport', 'Mobilier médical', 'Matériel informatique', 'Installations'] },
          { name: 'etat', label: 'État', options: ['En service', 'En maintenance', 'Hors service', 'Cédé'] },
        ],
        kpis: function (rows) {
          return [
            { label: 'Immobilisations', value: C.num(rows.length), icon: 'building', tone: 'navy' },
            { label: 'Valeur d’origine', value: C.money(C.sum(rows, 'valeurAcquisition')), icon: 'banknote', tone: 'info' },
            { label: 'Amortissements cumulés', value: C.money(C.sum(rows, amortiCumule)), icon: 'trending-down', tone: 'warning' },
            { label: 'Valeur nette comptable', value: C.money(C.sum(rows, vnc)), icon: 'wallet', tone: 'success' },
          ];
        },
        detail: function (im) {
          var plan = [];
          var reste = im.valeurAcquisition;
          for (var an = 1; an <= im.dureeAmortissement; an++) {
            var dot = an === im.dureeAmortissement ? reste : annuite(im);
            reste -= dot;
            plan.push({
              annee: C.toDate(im.dateAcquisition).getFullYear() + an - 1,
              base: im.valeurAcquisition, dotation: dot,
              cumul: im.valeurAcquisition - reste, vnc: reste,
            });
          }
          return el('div.space-y-4', null, [
            U.kpiGrid([
              { label: 'Valeur d’origine', value: C.money(im.valeurAcquisition), icon: 'banknote', tone: 'navy' },
              { label: 'Valeur nette comptable', value: C.money(vnc(im)), icon: 'wallet', tone: 'success' },
            ], 'grid-cols-2'),
            U.descList([['Référence', im.reference], ['Désignation', im.designation],
              ['Catégorie', im.categorie], ['Compte', im.compte],
              ['Date d’acquisition', C.dateFR(im.dateAcquisition)],
              ['Durée d’amortissement', im.dureeAmortissement + ' ans'],
              ['Annuité', C.money(annuite(im))], ['Années écoulées', String(anneesEcoulees(im))],
              ['Fournisseur', im.fournisseur], ['État', U.badge(im.etat, im.etat === 'En service' ? 'success' : 'warning')]]),
            U.card('Plan d’amortissement linéaire', K.miniTable([
              { label: 'Exercice', key: 'annee' },
              { label: 'Base amortissable', align: 'right', render: function (l) { return C.money(l.base, false); } },
              { label: 'Dotation', align: 'right', render: function (l) { return C.money(l.dotation, false); } },
              { label: 'Amort. cumulé', align: 'right', render: function (l) { return C.money(l.cumul, false); } },
              { label: 'Valeur nette', align: 'right', render: function (l) { return C.money(l.vnc, false); } },
            ], plan)),
          ]);
        },
        etat: function (im) {
          var plan = [];
          var reste = im.valeurAcquisition;
          for (var an = 1; an <= im.dureeAmortissement; an++) {
            var dot = an === im.dureeAmortissement ? reste : annuite(im);
            reste -= dot;
            plan.push({
              annee: C.toDate(im.dateAcquisition).getFullYear() + an - 1,
              dotation: C.money(dot, false),
              cumul: C.money(im.valeurAcquisition - reste, false),
              vnc: C.money(reste, false),
            });
          }
          P.etat({
            titre: 'Tableau d’amortissement',
            sousTitre: im.designation + ' — ' + im.reference,
            cartouche: [['Bien', im.designation], ['Référence', im.reference],
              ['Catégorie', im.categorie], ['Date d’acquisition', C.dateFR(im.dateAcquisition)],
              ['Valeur d’acquisition', C.money(im.valeurAcquisition)],
              ['Durée', im.dureeAmortissement + ' ans — mode linéaire']],
            contenu: P.tableau([
              { label: 'Exercice', key: 'annee' },
              { label: 'Dotation', key: 'dotation', align: 'right' },
              { label: 'Amortissement cumulé', key: 'cumul', align: 'right' },
              { label: 'Valeur nette comptable', key: 'vnc', align: 'right' },
            ], plan),
            signatures: [{ role: 'Le Comptable', nom: 'SANOUSSI Adamon' },
              { role: 'La Direction', nom: 'SOKOU Peace' }],
          });
        },
      })(root);
    },
  });

  /* ==========================================================================
   * BANQUES & RAPPROCHEMENTS
   * ======================================================================== */
  global.SIGH.screen('m12-banques', {
    title: 'Banques & rapprochements',
    description: 'Comptes bancaires, relevés et rapprochement avec la comptabilité.',
    render: function (root) {
      var col = S.collection('rapprochements', { module: 'M12', entite: 'Rapprochement' });
      if (!col.all().length) {
        var rnd = C.seeded(2417);
        var BANQUES = ['ECOBANK Bénin', 'Bank Of Africa Bénin', 'Orabank Bénin'];
        BANQUES.forEach(function (b, i) {
          for (var m = 0; m < 6; m++) {
            var soldeCompta = C.between(rnd, 500, 9000) * 1000;
            var ecart = rnd() > 0.6 ? C.between(rnd, -400, 400) * 1000 : 0;
            col.all().push({
              id: 'RAP' + C.uid(), statut: 'actif',
              reference: 'RB-' + C.pad(col.all().length + 1, 4),
              banque: b, compte: '5211',
              periode: C.MOIS[m + 2].charAt(0).toUpperCase() + C.MOIS[m + 2].slice(1) + ' 2026',
              soldeComptable: soldeCompta,
              soldeReleve: soldeCompta + ecart,
              ecart: ecart,
              statutRappro: ecart === 0 ? 'rapproche' : 'ecart',
              operateur: 'SANOUSSI Adamon',
            });
          }
        });
        S.save();
      }

      /* Les comptes bancaires deviennent un référentiel à part entière : la
         clinique doit pouvoir en ouvrir un nouveau sans attendre une livraison
         logicielle (demande de la Direction). Les rapprochements s'y adossent. */
      /* Les comptes de trésorerie sont amorcés AU SOCLE : la saisie des
         dépenses les lit aussi, et une page ne charge que le module de son
         écran. Les amorcer ici laissait la liste vide pour qui n'était pas
         passé par cet écran. */
      var colBanques = S.collection('banques', { module: 'M12', entite: 'compte bancaire', prefix: 'BQ' });

      var rows = col.active();
      var host = el('div.space-y-4');
      var banques = colBanques.active().map(function (b) { return b.banque; });

      function champsBanque() {
        return [
          { name: 'banque', label: 'Établissement bancaire', required: true, col: 'full' },
          { name: 'intitule', label: 'Intitulé du compte', required: true, col: 'full' },
          { name: 'numeroCompte', label: 'Numéro de compte', required: true },
          {
            name: 'compteComptable', label: 'Compte comptable (SYSCOHADA)', required: true,
            help: 'Classe 52 — banques. Sert à l’imputation automatique des mouvements.',
          },
          { name: 'devise', label: 'Devise', type: 'select', options: ['FCFA', 'EUR', 'USD'] },
          {
            name: 'statutCompte', label: 'État du compte', type: 'select', required: true,
            options: [{ value: 'actif', label: 'Actif' }, { value: 'cloture', label: 'Clôturé' }],
          },
        ];
      }

      host.appendChild(U.kpiGrid([
        { label: 'Comptes bancaires', value: C.num(colBanques.active().length), icon: 'landmark', tone: 'navy' },
        { label: 'Rapprochements effectués', value: C.num(rows.length), icon: 'check-circle-2', tone: 'info' },
        { label: 'Sans écart', value: C.num(rows.filter(function (r) { return r.statutRappro === 'rapproche'; }).length), icon: 'scale', tone: 'success' },
        { label: 'Avec écart', value: C.num(rows.filter(function (r) { return r.statutRappro === 'ecart'; }).length), icon: 'scale-3d', tone: 'danger' },
      ]));

      var tableBanques = U.dataTable({
        title: 'Comptes bancaires de la clinique',
        rows: function () { return colBanques.active(); },
        exportName: 'comptes-bancaires', pageSize: 10, searchable: true,
        emptyMessage: 'Aucun compte bancaire enregistré.',
        columns: [
          { key: 'banque', label: 'Établissement', render: function (b) { return el('span.font-medium.text-slate-800', { text: b.banque }); } },
          { key: 'intitule', label: 'Intitulé du compte' },
          { key: 'numeroCompte', label: 'N° de compte', nowrap: true, render: function (b) { return el('span.font-mono.text-xs', { text: b.numeroCompte }); } },
          { key: 'compteComptable', label: 'Compte SYSCOHADA', nowrap: true, render: function (b) { return U.badge(b.compteComptable, 'navy'); } },
          { key: 'devise', label: 'Devise', nowrap: true },
          {
            key: 'statutCompte', label: 'État',
            render: function (b) { return b.statutCompte === 'actif' ? U.badge('Actif', 'success') : U.badge('Clôturé', 'neutral'); },
          },
        ],
        rowActions: K.actionsLigne(colBanques, champsBanque, { entite: 'compte bancaire' }),
        actions: [K.creer(colBanques, champsBanque, {
          titre: 'Nouveau compte bancaire', entite: 'Compte',
          defauts: function () { return { devise: 'FCFA', statutCompte: 'actif', compteComptable: '5211' }; },
          apres: function () { tableBanques.refresh(); },
        })],
      });
      host.appendChild(tableBanques);

      host.appendChild(U.dataTable({
        title: 'États de rapprochement bancaire', rows: rows, exportName: 'rapprochements', pageSize: 15,
        defaultSort: 'periode', defaultDir: 'desc',
        filters: [
          { name: 'banque', label: 'Banque', options: banques },
          { name: 'statutRappro', label: 'Résultat', options: [{ value: 'rapproche', label: 'Sans écart' }, { value: 'ecart', label: 'Avec écart' }] },
        ],
        columns: [
          { key: 'reference', label: 'N°', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.reference }); } },
          { key: 'banque', label: 'Banque' },
          { key: 'compte', label: 'Compte', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.compte }); } },
          { key: 'periode', label: 'Période', nowrap: true },
          { key: 'soldeComptable', label: 'Solde comptable', align: 'right', text: function (r) { return C.money(r.soldeComptable, false); }, render: function (r) { return C.money(r.soldeComptable, false); } },
          { key: 'soldeReleve', label: 'Solde relevé', align: 'right', text: function (r) { return C.money(r.soldeReleve, false); }, render: function (r) { return C.money(r.soldeReleve, false); } },
          {
            key: 'ecart', label: 'Écart', align: 'right',
            text: function (r) { return C.money(r.ecart, false); },
            render: function (r) {
              return r.ecart === 0 ? U.badge('Rapproché', 'success')
                : el('span.font-semibold.text-danger-600', { text: (r.ecart > 0 ? '+' : '') + C.money(r.ecart, false) });
            },
          },
          { key: 'operateur', label: 'Effectué par' },
        ],
        rowActions: function (r) {
          return [K.iconBtn('printer', 'Imprimer l’état', function () {
            P.etat({
              titre: 'État de rapprochement bancaire',
              sousTitre: r.banque + ' — ' + r.periode,
              cartouche: [['Banque', r.banque], ['Compte comptable', r.compte],
                ['Période', r.periode], ['Référence', r.reference],
                ['Effectué par', r.operateur], ['Date d’édition', C.dateFR(AUJ)]],
              contenu: el('div.space-y-3', null, [
                P.tableau([{ label: 'Rubrique', key: 'k' }, { label: 'Montant', key: 'v', align: 'right' }], [
                  { k: 'Solde du compte en comptabilité', v: C.money(r.soldeComptable, false) },
                  { k: 'Solde du relevé bancaire', v: C.money(r.soldeReleve, false) },
                  { k: 'ÉCART CONSTATÉ', v: C.money(r.ecart, false) },
                ]),
                el('p.mt-3.text-\\[10px\\].italic', {
                  text: r.ecart === 0
                    ? 'Le rapprochement ne fait apparaître aucun écart : la comptabilité et le relevé bancaire concordent.'
                    : 'Un écart de ' + C.money(Math.abs(r.ecart)) + ' est constaté. Il doit être justifié (chèques en circulation, '
                      + 'virements non encore comptabilisés, frais bancaires) puis régularisé par écriture d’opérations diverses.',
                }),
              ]),
              signatures: [{ role: 'Le Comptable', nom: r.operateur },
                { role: 'La Direction', nom: 'SOKOU Peace' }],
            });
          })];
        },
      }));
      root.appendChild(host);
      return null;
    },
  });

  /* ==========================================================================
   * ÉTATS FINANCIERS
   * ======================================================================== */
  global.SIGH.screen('m12-etats-financiers', {
    title: 'États financiers de synthèse',
    description: 'Bilan, compte de résultat et tableau des flux de trésorerie au format SYSCOHADA.',
    render: function (root) {
      var host = el('div.space-y-4');
      var e = ecritures();

      function soldeClasse(prefixe) {
        var sel = e.filter(function (x) { return String(x.compte).indexOf(prefixe) === 0; });
        return C.sum(sel, 'debit') - C.sum(sel, 'credit');
      }

      var immo = S.collection('immobilisations').active();
      var actifImmobilise = C.sum(immo, 'valeurAcquisition');
      var amortissements = C.sum(immo, function (im) {
        var annuite = Math.round(im.valeurAcquisition / im.dureeAmortissement);
        var ans = Math.min(im.dureeAmortissement, Math.max(0, Math.floor(C.daysBetween(im.dateAcquisition, AUJ) / 365.25)));
        return annuite * ans;
      });
      var stocks = C.sum(S.collection('produits').active(), function (p) { return p.stock * p.cump; });
      var creances = C.sum(S.collection('factures').active(), 'reliquat');
      var tresorerie = soldeCompte('5711').solde + soldeCompte('5211').solde;
      var produits = C.sum(e.filter(function (x) { return String(x.compte)[0] === '7'; }), 'credit');
      var charges = C.sum(e.filter(function (x) { return String(x.compte)[0] === '6'; }), 'debit');
      var resultat = produits - charges;
      var dettes = Math.abs(soldeCompte('4011').solde) + Math.abs(soldeCompte('422').solde) + Math.abs(soldeCompte('431').solde);

      host.appendChild(U.kpiGrid([
        { label: 'Total de l’actif', value: C.money(actifImmobilise - amortissements + stocks + creances + tresorerie), icon: 'layers', tone: 'navy' },
        { label: 'Chiffre d’affaires', value: C.money(produits), icon: 'trending-up', tone: 'success' },
        { label: 'Total des charges', value: C.money(charges), icon: 'trending-down', tone: 'warning' },
        { label: 'Résultat de l’exercice', value: C.money(resultat), icon: resultat >= 0 ? 'smile' : 'frown', tone: resultat >= 0 ? 'success' : 'danger' },
      ]));

      host.appendChild(U.tabs([
        {
          id: 'bilan', label: 'Bilan',
          render: function () {
            var actif = [
              { poste: 'Immobilisations corporelles brutes', montant: actifImmobilise },
              { poste: 'Amortissements cumulés', montant: -amortissements },
              { poste: 'Immobilisations nettes', montant: actifImmobilise - amortissements },
              { poste: 'Stocks', montant: stocks },
              { poste: 'Créances clients et comptes rattachés', montant: creances },
              { poste: 'Trésorerie — actif', montant: tresorerie },
            ];
            var passif = [
              { poste: 'Capital et réserves', montant: 25000000 },
              { poste: 'Résultat de l’exercice', montant: resultat },
              { poste: 'Dettes fournisseurs', montant: Math.abs(soldeCompte('4011').solde) },
              { poste: 'Dettes sociales (personnel, CNSS)', montant: Math.abs(soldeCompte('422').solde) + Math.abs(soldeCompte('431').solde) },
              { poste: 'Dettes fiscales (ITS, TVA)', montant: Math.abs(soldeCompte('4472').solde) + Math.abs(soldeCompte('4432').solde) },
            ];
            return el('div.grid.gap-4.lg\\:grid-cols-2', null, [
              U.card('ACTIF', K.miniTable([
                { label: 'Poste', key: 'poste' },
                { label: 'Montant', align: 'right', render: function (l) { return C.money(l.montant, false); } },
              ], actif.concat([{ poste: 'TOTAL ACTIF', montant: actifImmobilise - amortissements + stocks + creances + tresorerie }]))),
              U.card('PASSIF', K.miniTable([
                { label: 'Poste', key: 'poste' },
                { label: 'Montant', align: 'right', render: function (l) { return C.money(l.montant, false); } },
              ], passif.concat([{ poste: 'TOTAL PASSIF', montant: C.sum(passif, 'montant') }]))),
            ]);
          },
        },
        {
          id: 'resultat', label: 'Compte de résultat',
          render: function () {
            var g = C.groupBy(e.filter(function (x) { return String(x.compte)[0] === '7'; }), 'compte');
            var lignesProduits = Object.keys(g).map(function (k) {
              return { poste: compteLibelle(k), compte: k, montant: C.sum(g[k], 'credit') };
            });
            var gc = C.groupBy(e.filter(function (x) { return String(x.compte)[0] === '6'; }), 'compte');
            var lignesCharges = Object.keys(gc).map(function (k) {
              return { poste: compteLibelle(k), compte: k, montant: C.sum(gc[k], 'debit') };
            });
            return el('div.space-y-4', null, [
              U.card('PRODUITS', K.miniTable([
                { label: 'Compte', render: function (l) { return el('span.font-mono.text-xs', { text: l.compte }); } },
                { label: 'Poste', key: 'poste' },
                { label: 'Montant', align: 'right', render: function (l) { return C.money(l.montant, false); } },
              ], C.sortBy(lignesProduits, 'montant', 'desc').concat([{ compte: '', poste: 'TOTAL DES PRODUITS', montant: produits }]))),
              U.card('CHARGES', K.miniTable([
                { label: 'Compte', render: function (l) { return el('span.font-mono.text-xs', { text: l.compte }); } },
                { label: 'Poste', key: 'poste' },
                { label: 'Montant', align: 'right', render: function (l) { return C.money(l.montant, false); } },
              ], C.sortBy(lignesCharges, 'montant', 'desc').concat([{ compte: '', poste: 'TOTAL DES CHARGES', montant: charges }]))),
              el('div.rounded-xl.border.p-4', {
                class: resultat >= 0 ? 'border-success-200 bg-success-50' : 'border-danger-200 bg-danger-50',
              }, [
                el('p.text-xs.font-medium', { class: resultat >= 0 ? 'text-success-700' : 'text-danger-700', text: 'RÉSULTAT DE L’EXERCICE' }),
                el('p.mt-1.text-2xl.font-bold.num', { class: resultat >= 0 ? 'text-success-800' : 'text-danger-800', text: C.money(resultat) }),
                el('p.mt-1.text-xs', { class: resultat >= 0 ? 'text-success-600' : 'text-danger-600', text: resultat >= 0 ? 'Bénéfice' : 'Perte' }),
              ]),
            ]);
          },
        },
        {
          id: 'flux', label: 'Tableau des flux',
          render: function () {
            var flux = [
              { poste: 'Encaissements des clients', montant: C.sum(S.collection('factures').active(), 'montantPaye') },
              { poste: 'Décaissements fournisseurs', montant: -C.sum(S.collection('commandes').active(), 'montant') },
              { poste: 'Décaissements de personnel', montant: -C.sum(S.collection('personnel').active(), 'salaireBase') * 8 },
              { poste: 'Flux de trésorerie d’exploitation', montant: tresorerie },
              { poste: 'Acquisitions d’immobilisations', montant: -actifImmobilise },
              { poste: 'Flux de trésorerie d’investissement', montant: -actifImmobilise },
            ];
            return U.card('Tableau des flux de trésorerie', K.miniTable([
              { label: 'Poste', key: 'poste' },
              {
                label: 'Montant', align: 'right',
                render: function (l) {
                  return el('span', { class: l.montant < 0 ? 'text-danger-600' : 'text-success-700', text: C.money(l.montant, false) });
                },
              },
            ], flux));
          },
        },
      ]));

      host.appendChild(el('div.flex.flex-wrap.gap-2', null, [
        K.btn('Imprimer le bilan', { variant: 'primary', icon: 'printer', onclick: imprimerBilan }),
        K.btn('Imprimer le compte de résultat', { icon: 'printer', onclick: imprimerResultat }),
      ]));

      host.appendChild(K.note('Les états financiers sont produits à partir des écritures enregistrées. Ils constituent une <strong>vue de synthèse du prototype</strong> et devront être validés par le service comptable avant tout usage réglementaire.', { tone: 'warning' }));

      root.appendChild(host);
      return null;

      function imprimerBilan() {
        var actifNet = actifImmobilise - amortissements + stocks + creances + tresorerie;
        P.etat({
          titre: 'Bilan',
          sousTitre: 'Exercice 2026 — arrêté au ' + C.dateFR(AUJ),
          cartouche: [['Exercice', '2026'], ['Date d’arrêté', C.dateFR(AUJ)],
            ['Total actif', C.money(actifNet)], ['Résultat', C.money(resultat)],
            ['Référentiel', 'SYSCOHADA'], ['IFU', C.BRAND.ifu]],
          contenu: el('div.space-y-4', null, [
            el('p.text-\\[11px\\].font-bold.uppercase.text-navy-900', { text: 'Actif' }),
            P.tableau([{ label: 'Poste', key: 'p' }, { label: 'Montant', key: 'm', align: 'right' }], [
              { p: 'Immobilisations corporelles brutes', m: C.money(actifImmobilise, false) },
              { p: 'Amortissements cumulés', m: '− ' + C.money(amortissements, false) },
              { p: 'Immobilisations nettes', m: C.money(actifImmobilise - amortissements, false) },
              { p: 'Stocks', m: C.money(stocks, false) },
              { p: 'Créances clients', m: C.money(creances, false) },
              { p: 'Trésorerie', m: C.money(tresorerie, false) },
              { p: 'TOTAL ACTIF', m: C.money(actifNet, false) },
            ]),
            el('p.mt-3.text-\\[11px\\].font-bold.uppercase.text-navy-900', { text: 'Passif' }),
            P.tableau([{ label: 'Poste', key: 'p' }, { label: 'Montant', key: 'm', align: 'right' }], [
              { p: 'Capital et réserves', m: C.money(25000000, false) },
              { p: 'Résultat de l’exercice', m: C.money(resultat, false) },
              { p: 'Dettes fournisseurs', m: C.money(Math.abs(soldeCompte('4011').solde), false) },
              { p: 'Dettes sociales', m: C.money(Math.abs(soldeCompte('422').solde) + Math.abs(soldeCompte('431').solde), false) },
              { p: 'Dettes fiscales', m: C.money(Math.abs(soldeCompte('4472').solde) + Math.abs(soldeCompte('4432').solde), false) },
            ]),
          ]),
          signatures: [{ role: 'Le Comptable', nom: 'SANOUSSI Adamon' },
            { role: 'La Direction', nom: 'SOKOU Peace' },
            { role: 'Le Directeur Général', nom: 'GBAGUIDI Rafiou' }],
        });
      }

      function imprimerResultat() {
        var g = C.groupBy(e.filter(function (x) { return String(x.compte)[0] === '7'; }), 'compte');
        var gc = C.groupBy(e.filter(function (x) { return String(x.compte)[0] === '6'; }), 'compte');
        P.etat({
          titre: 'Compte de résultat',
          sousTitre: 'Exercice 2026',
          cartouche: [['Exercice', '2026'], ['Produits', C.money(produits)],
            ['Charges', C.money(charges)], ['Résultat', C.money(resultat)],
            ['Référentiel', 'SYSCOHADA'], ['Date d’édition', C.dateFR(AUJ)]],
          contenu: el('div.space-y-4', null, [
            el('p.text-\\[11px\\].font-bold.uppercase.text-navy-900', { text: 'Produits' }),
            P.tableau([
              { label: 'Compte', key: 'compte' }, { label: 'Poste', key: 'poste' },
              { label: 'Montant', key: 'montant', align: 'right' },
            ], Object.keys(g).map(function (k) {
              return { compte: k, poste: compteLibelle(k), montant: C.money(C.sum(g[k], 'credit'), false) };
            }).concat([{ compte: '', poste: 'TOTAL DES PRODUITS', montant: C.money(produits, false) }])),
            el('p.mt-3.text-\\[11px\\].font-bold.uppercase.text-navy-900', { text: 'Charges' }),
            P.tableau([
              { label: 'Compte', key: 'compte' }, { label: 'Poste', key: 'poste' },
              { label: 'Montant', key: 'montant', align: 'right' },
            ], Object.keys(gc).map(function (k) {
              return { compte: k, poste: compteLibelle(k), montant: C.money(C.sum(gc[k], 'debit'), false) };
            }).concat([{ compte: '', poste: 'TOTAL DES CHARGES', montant: C.money(charges, false) }])),
            el('p.mt-4.text-\\[12px\\].font-bold', { text: 'RÉSULTAT DE L’EXERCICE : ' + C.money(resultat) + ' (' + (resultat >= 0 ? 'bénéfice' : 'perte') + ')' }),
          ]),
          signatures: [{ role: 'Le Comptable', nom: 'SANOUSSI Adamon' },
            { role: 'La Direction', nom: 'GBAGUIDI Rafiou' }],
        });
      }
    },
  });

  /* ==========================================================================
   * EXERCICES & CLÔTURES
   * ======================================================================== */
  global.SIGH.screen('m12-cloture', {
    title: 'Exercices & périodes comptables',
    description: 'Suivi des exercices et des périodes, sans interruption de service à la fin de l’année.',
    regle: 'Une période se <strong>verrouille</strong> quand ses écritures sont validées et sa balance équilibrée '
      + '(RG-10) — mais le <strong>logiciel ne se clôture pas en fin d’exercice</strong> : le travail continue sur '
      + 'l’année suivante et les données des années antérieures restent consultables. C’est une demande écrite du '
      + 'cahier de charge du 30/12/2024.',
    render: function (root) {
      var e = ecritures();
      var host = el('div.space-y-4');
      host.appendChild(K.note('<strong>Aucune clôture ne ferme le logiciel.</strong> Le passage à l’exercice suivant '
        + 'est automatique : la saisie continue sans interruption, et les exercices antérieurs restent ouverts à la '
        + 'consultation et à l’édition d’états. Verrouiller une période empêche d’y saisir, pas d’y lire.',
      { tone: 'success', icon: 'infinity' }));

      var periodes = C.MOIS.map(function (m, i) {
        var sel = e.filter(function (x) {
          var d = C.toDate(x.date);
          return d.getFullYear() === 2026 && d.getMonth() === i;
        });
        var debit = C.sum(sel, 'debit'), credit = C.sum(sel, 'credit');
        var brouillons = sel.filter(function (x) { return x.statut === 'brouillon'; }).length;
        return {
          id: String(i), mois: m.charAt(0).toUpperCase() + m.slice(1) + ' 2026', index: i,
          nb: sel.length, debit: debit, credit: credit,
          equilibre: debit === credit, brouillons: brouillons,
          cloturable: sel.length > 0 && debit === credit && brouillons === 0,
          statutPeriode: i < AUJ.getMonth() ? 'cloturee' : (i === AUJ.getMonth() ? 'ouverte' : 'future'),
        };
      });

      host.appendChild(U.kpiGrid([
        { label: 'Exercice en cours', value: '2026', icon: 'calendar', tone: 'navy' },
        { label: 'Périodes clôturées', value: C.num(periodes.filter(function (p) { return p.statutPeriode === 'cloturee'; }).length), icon: 'lock', tone: 'success' },
        { label: 'Écritures en brouillon', value: C.num(C.sum(periodes, 'brouillons')), icon: 'file-clock', tone: 'warning' },
        { label: 'Total des écritures', value: C.num(e.length), icon: 'book-open-check', tone: 'info' },
      ]));

      host.appendChild(U.dataTable({
        title: 'Périodes comptables — exercice 2026', rows: periodes, exportName: 'cloture', pageSize: 12,
        searchable: false,
        columns: [
          { key: 'mois', label: 'Période', nowrap: true },
          { key: 'nb', label: 'Écritures', align: 'right' },
          { key: 'debit', label: 'Total débit', align: 'right', text: function (p) { return C.money(p.debit, false); }, render: function (p) { return C.money(p.debit, false); } },
          { key: 'credit', label: 'Total crédit', align: 'right', text: function (p) { return C.money(p.credit, false); }, render: function (p) { return C.money(p.credit, false); } },
          {
            key: 'equilibre', label: 'Équilibre',
            text: function (p) { return p.equilibre ? 'Équilibrée' : 'Déséquilibrée'; },
            render: function (p) {
              if (!p.nb) return el('span.text-xs.text-slate-400', { text: '—' });
              return p.equilibre ? U.badge('Équilibrée', 'success') : U.badge('Écart ' + C.money(Math.abs(p.debit - p.credit), false), 'danger');
            },
          },
          {
            key: 'brouillons', label: 'Brouillons', align: 'right',
            render: function (p) { return p.brouillons ? el('span.font-semibold.text-warning-600', { text: String(p.brouillons) }) : '—'; },
          },
          {
            key: 'statutPeriode', label: 'Statut',
            render: function (p) {
              var m = { cloturee: ['Clôturée', 'neutral'], ouverte: ['Ouverte', 'success'], future: ['À venir', 'neutral'] };
              var x = m[p.statutPeriode];
              return U.badge(x[0], x[1]);
            },
          },
        ],
        rowActions: function (p) {
          if (p.statutPeriode !== 'ouverte') return [];
          return [K.btn(p.cloturable ? 'Clôturer' : 'Non clôturable', {
            size: 'sm', variant: p.cloturable ? 'primary' : 'secondary', icon: 'lock',
            onclick: function () {
              if (!p.cloturable) {
                U.toast('Clôture impossible.', {
                  type: 'error',
                  detail: p.brouillons ? p.brouillons + ' écriture(s) en brouillon à valider.' : 'La balance de la période n’est pas équilibrée (RG-10).',
                });
                return;
              }
              U.confirm({
                title: 'Clôturer la période ' + p.mois + ' ?',
                message: 'Après clôture, aucune écriture ne pourra plus être saisie sur cette période. '
                  + 'La balance est équilibrée à ' + C.money(p.debit) + ' au débit comme au crédit.',
                confirmLabel: 'Clôturer la période',
              }).then(function (ok) {
                if (!ok) return;
                S.log('Validation', 'M12', 'ClotureComptable', p.mois, null, { debit: p.debit, credit: p.credit });
                U.toast('Période ' + p.mois + ' clôturée.', { type: 'success' });
              });
            },
          })];
        },
      }));

      host.appendChild(K.note('La clôture annuelle génère les écritures de détermination du résultat et reporte les soldes à nouveau sur l’exercice suivant.', { tone: 'info' }));
      root.appendChild(host);
      return null;
    },
  });

  /* ==========================================================================
   * LES DEUX ANOMALIES DU CLASSEUR 2025 — DIAGNOSTIC, PAS RÉPARATION
   * --------------------------------------------------------------------------
   * La Direction a demandé de corriger (26/08/2026). Corriger un écart, ce
   * n'est pas le gommer : c'est trouver la ligne qui l'explique et dire
   * laquelle des deux sources fait foi.
   *
   * Le diagnostic est CALCULÉ à chaque affichage, jamais écrit en dur :
   * `npm run compta` régénère data-compta.js depuis le classeur Excel, et un
   * montant codé ici serait faux à la première régénération.
   * ======================================================================== */

  /* Cherche la ligne dont une ÉCHÉANCE MENSUELLE vaut exactement l'écart.
     Un écart d'arrondi ne tombe pas sur un montant que le classeur porte par
     ailleurs : la coïncidence, si elle existe, est l'explication. */
  function expliquerEcart(E) {
    var ecart = Math.abs(E.controle.ecart || 0);
    if (!ecart) return null;

    var mensuelles = [], totales = [];
    (E.depenses || []).forEach(function (d) {
      var mois = [];
      (d.mois || []).forEach(function (m, i) { if (Math.round(m) === ecart) mois.push(i); });
      if (mois.length) mensuelles.push({ ligne: d, mois: mois });
      if (Math.round(d.total) === ecart) totales.push(d);
    });

    /* Contrôle préalable : chaque ligne du détail somme-t-elle à son propre
       total ? Si non, l'écart vient du détail et non de la ligne TOTAL. */
    var incoherentes = (E.depenses || []).filter(function (d) {
      var somme = (d.mois || []).reduce(function (a, b) { return a + b; }, 0);
      return Math.round((somme - d.total) * 100) !== 0;
    });

    return { ecart: ecart, mensuelles: mensuelles, totales: totales, incoherentes: incoherentes };
  }

  /* Rattachement PROPOSÉ des trois postes sans numéro de compte. Les trois
     relèvent du même emprunt bancaire ; le classeur porte déjà les comptes
     d'accueil, ce qui rend la proposition vérifiable plutôt qu'inventée. */
  var COMPTES_PROPOSES = {
    'FONDS DE GARANTIE': {
      compte: '275', intitule: 'Dépôts et cautionnements versés',
      motif: 'Un fonds de garantie adossé à un emprunt est un dépôt, non une charge. '
        + 'Le classeur porte déjà ce compte pour ses autres cautionnements.',
    },
    'FRAIS DOSSIER SUR EMPRUNT': {
      compte: '6318', intitule: 'Autres frais bancaires',
      motif: 'Frais perçus par la banque à l’ouverture du dossier : même nature que les '
        + 'comptes 631810, 631820 et 631830 déjà utilisés par le classeur.',
    },
    'TAXE SUR EMPRUNT': {
      compte: '6468', intitule: 'Autres droits',
      motif: 'Droit assis sur l’emprunt, de même nature que la cotisation CCIB déjà '
        + 'imputée à ce compte dans le classeur.',
    },
  };

  function propositionCompte(libelle) {
    return COMPTES_PROPOSES[String(libelle || '').trim().toUpperCase()] || null;
  }

  /* ==========================================================================
   * BASELINE 2025 — compte de résultat réel de l'exercice précédent
   * ======================================================================== */
  global.SIGH.screen('m12-baseline-2025', {
    title: 'Baseline financière 2025',
    description: 'Compte de résultat réel de l’exercice 2025, servant de référence de comparaison à l’exercice courant.',
    regle: 'Le compte de résultat 2025 n’est pas un simple archivage : il constitue la <strong>référence de comparaison</strong> '
      + 'des tableaux de bord (2025 réel / 2026 réel / budget 2026), conformément au principe de reprise des documents de cadrage.',
    render: function (root) {
      var E = global.SIGH.compta.EXERCICE_2025;
      var host = el('div.space-y-4');
      var moisCourts = E.mois.map(function (m) { return m.slice(0, 4) + '. 25'; });

      host.appendChild(U.kpiGrid([
        { label: 'Chiffre d’affaires 2025', value: C.money(E.totalChiffreAffaires), icon: 'trending-up', tone: 'success' },
        { label: 'Charges d’exploitation', value: C.money(E.totalCharges), icon: 'trending-down', tone: 'warning' },
        {
          label: 'Résultat 2025', value: C.money(E.resultat),
          icon: E.resultat >= 0 ? 'smile' : 'frown', tone: E.resultat >= 0 ? 'success' : 'danger',
          hint: C.pct(E.totalChiffreAffaires ? E.resultat / E.totalChiffreAffaires * 100 : 0) + ' du chiffre d’affaires',
        },
        { label: 'Chiffre d’affaires moyen', value: C.money(E.totalChiffreAffaires / 12), icon: 'calendar', tone: 'navy', hint: 'par mois' },
        { label: 'Meilleur mois', value: C.MOIS[E.chiffreAffaires.indexOf(Math.max.apply(null, E.chiffreAffaires))], icon: 'award', tone: 'success', hint: C.money(Math.max.apply(null, E.chiffreAffaires)) },
        { label: 'Mois le plus faible', value: C.MOIS[E.chiffreAffaires.indexOf(Math.min.apply(null, E.chiffreAffaires))], icon: 'trending-down', tone: 'neutral', hint: C.money(Math.min.apply(null, E.chiffreAffaires)) },
        { label: 'Postes de charges', value: C.num(E.postesCharges().length), icon: 'list', tone: 'info' },
        { label: 'Hors exploitation', value: C.money(E.totalHorsExploitation), icon: 'landmark', tone: 'neutral', hint: 'Emprunt, cautionnements, immobilisation' },
      ]));

      /* Contrôles relevés sur le classeur source */
      var ctrl = E.controle;
      if (ctrl.postesSansCompte || ctrl.ecart) {
        var alertes = el('div.space-y-3');

        /* --- L'ÉCART, EXPLIQUÉ ----------------------------------------- */
        if (ctrl.ecart) {
          var diag = expliquerEcart(E);
          alertes.appendChild(K.note('<strong>Écart de ' + C.money(Math.abs(ctrl.ecart)) + '</strong> entre la ligne '
            + '« TOTAL » du classeur (' + C.money(ctrl.totalClasseur) + ') et la somme de son propre détail ('
            + C.money(ctrl.totalDetail) + ').', { tone: 'danger', icon: 'scale-3d' }));

          if (diag && !diag.incoherentes.length && diag.mensuelles.length) {
            var l = diag.mensuelles[0];
            var moisNoms = l.mois.map(function (i) { return C.MOIS[i]; }).join(' et ');
            alertes.appendChild(K.note('<strong>Diagnostic : l’écart n’est pas un arrondi.</strong> '
              + 'Les ' + (E.depenses || []).length + ' lignes du détail somment <strong>exactement</strong> à leur '
              + 'propre total — le détail est cohérent avec lui-même. Et le montant de l’écart, '
              + C.money(diag.ecart) + ', est <strong>précisément l’échéance mensuelle</strong> de la ligne '
              + '« ' + l.ligne.libelle + ' » (' + moisNoms + '). La ligne « TOTAL » du classeur '
              + '<strong>omet une échéance</strong> ; c’est elle qui est fautive, non le détail.<br>'
              + '<strong>Conséquence retenue :</strong> la baseline s’appuie sur le détail, soit '
              + C.money(ctrl.totalDetail) + '. Le service comptable est invité à corriger la formule de '
              + 'totalisation du classeur — la correction porte sur le document source, pas sur le logiciel.',
              { tone: 'info', icon: 'search-check' }));
          } else if (diag && diag.incoherentes.length) {
            alertes.appendChild(K.note('<strong>' + diag.incoherentes.length + ' ligne(s) ne somment pas à leur '
              + 'propre total</strong> : l’écart vient du détail lui-même et non de la ligne TOTAL. À reprendre '
              + 'ligne par ligne avec le service comptable.', { tone: 'warning', icon: 'triangle-alert' }));
          }
        }

        /* --- LES POSTES SANS COMPTE, AVEC LEUR RATTACHEMENT PROPOSÉ ----- */
        if (ctrl.postesSansCompte) {
          var sansCompte = (E.depenses || []).filter(function (d) { return !d.num; });
          alertes.appendChild(K.note('<strong>' + ctrl.postesSansCompte + ' poste(s) de dépense sans numéro de '
            + 'compte</strong> dans le classeur source, pour ' + C.money(ctrl.montantSansCompte) + '. Les trois '
            + 'relèvent du <strong>même emprunt bancaire</strong>. Un rattachement est proposé ci-dessous : '
            + 'c’est une <strong>proposition à valider</strong> par le service comptable, pas une imputation '
            + 'appliquée — rattacher d’office un montant à un compte fausserait la balance sans que personne '
            + 'ne l’ait décidé.', { tone: 'warning', icon: 'help-circle' }));

          alertes.appendChild(K.miniTable([
            { key: 'poste', label: 'Poste du classeur' },
            { key: 'montant', label: 'Montant 2025', align: 'right' },
            {
              key: 'compte', label: 'Compte proposé',
              render: function (r) {
                if (!r.compte) return el('span.text-xs.italic.text-slate-400', { text: 'à déterminer' });
                return el('div', null, [
                  el('span.font-mono.text-xs.font-semibold', { text: r.compte }),
                  el('p.text-[10px].text-slate-500', { text: r.intitule }),
                ]);
              },
            },
            {
              key: 'motif', label: 'Pourquoi ce compte',
              render: function (r) { return el('span.text-xs.text-slate-600', { text: r.motif }); },
            },
          ], sansCompte.map(function (d) {
            var pr = propositionCompte(d.libelle);
            return {
              poste: d.libelle,
              montant: C.money(d.total, false),
              compte: pr ? pr.compte : null,
              intitule: pr ? pr.intitule : '',
              motif: pr ? pr.motif : 'Aucune proposition : le libellé ne permet pas de trancher.',
            };
          })));
        }

        host.appendChild(U.card('Contrôles de cohérence du document source', alertes));
      }

      host.appendChild(K.charts([
        {
          title: 'Chiffre d’affaires mensuel 2025',
          render: function () {
            return G.barres(moisCourts, [{ label: 'Chiffre d’affaires', data: E.chiffreAffaires, color: G.TONES.vert }]);
          },
        },
        {
          title: 'Chiffre d’affaires, charges et résultat',
          render: function () {
            var charges = E.mois.map(function (_, i) { return Math.round(E.chargesDuMois(i)); });
            var resultats = E.mois.map(function (_, i) { return Math.round(E.resultatDuMois(i)); });
            return G.ligne(moisCourts, [
              { label: 'Chiffre d’affaires', data: E.chiffreAffaires, color: G.TONES.vert, fill: false },
              { label: 'Charges', data: charges, color: G.TONES.rouge, fill: false },
              { label: 'Résultat', data: resultats, color: G.TONES.navy, fill: false },
            ]);
          },
        },
      ]));

      host.appendChild(U.tabs([
        {
          id: 'mensuel', label: 'Détail mensuel',
          render: function () {
            var rows = E.mois.map(function (m, i) {
              return {
                id: String(i), mois: m.charAt(0).toUpperCase() + m.slice(1) + ' 2025',
                ca: E.chiffreAffaires[i],
                charges: Math.round(E.chargesDuMois(i)),
                resultat: Math.round(E.resultatDuMois(i)),
                marge: E.chiffreAffaires[i] ? Math.round(E.resultatDuMois(i) / E.chiffreAffaires[i] * 100) : 0,
              };
            });
            return U.dataTable({
              rows: rows, exportName: 'baseline-2025-mensuel', pageSize: 13, searchable: false,
              columns: [
                { key: 'mois', label: 'Mois', nowrap: true },
                { key: 'ca', label: 'Chiffre d’affaires', align: 'right', text: function (r) { return C.money(r.ca, false); }, render: function (r) { return el('span.font-semibold.text-success-700', { text: C.money(r.ca, false) }); } },
                { key: 'charges', label: 'Charges', align: 'right', text: function (r) { return C.money(r.charges, false); }, render: function (r) { return el('span.text-danger-600', { text: C.money(r.charges, false) }); } },
                {
                  key: 'resultat', label: 'Résultat', align: 'right',
                  text: function (r) { return C.money(r.resultat, false); },
                  render: function (r) {
                    return el('span.font-bold', { class: r.resultat >= 0 ? 'text-success-700' : 'text-danger-600', text: C.money(r.resultat, false) });
                  },
                },
                { key: 'marge', label: 'Marge', align: 'right', render: function (r) { return U.badge(r.marge + ' %', r.marge >= 0 ? 'success' : 'danger'); } },
              ],
            });
          },
        },
        {
          id: 'charges', label: 'Postes de charges', badge: E.postesCharges().length,
          render: function () {
            var postes = E.postesCharges();
            return el('div.space-y-3', null, [
              K.ranking(postes.slice(0, 12).map(function (p) {
                return { label: p.libelle, value: p.total };
              }), { format: function (v) { return C.money(v, false); }, tone: 'warning' }),
              U.dataTable({
                rows: postes, exportName: 'baseline-2025-charges', pageSize: 20,
                defaultSort: 'total', defaultDir: 'desc',
                columns: [
                  {
                    key: 'num', label: 'Compte', nowrap: true,
                    render: function (p) {
                      return p.num
                        ? el('span.font-mono.text-xs.font-semibold', { text: p.num })
                        : U.badge('À rattacher', 'warning');
                    },
                  },
                  { key: 'libelle', label: 'Poste de charge' },
                  {
                    key: 'total', label: 'Total 2025', align: 'right',
                    text: function (p) { return C.money(p.total, false); },
                    render: function (p) { return el('span.font-semibold', { text: C.money(p.total, false) }); },
                  },
                  {
                    key: 'moyenne', label: 'Moyenne mensuelle', align: 'right',
                    value: function (p) { return p.total / 12; },
                    text: function (p) { return C.money(p.total / 12, false); },
                    render: function (p) { return C.money(p.total / 12, false); },
                  },
                  {
                    key: 'poids', label: 'Poids', align: 'right',
                    value: function (p) { return p.total / E.totalCharges * 100; },
                    render: function (p) { return U.badge(C.pct(p.total / E.totalCharges * 100), 'neutral'); },
                  },
                ],
              }),
            ]);
          },
        },
        {
          id: 'comparaison', label: 'Comparaison 2025 / 2026',
          render: function () {
            var factures = S.collection('factures').active();
            var rows = E.mois.map(function (m, i) {
              var ca2026 = C.sum(factures.filter(function (f) {
                var d = C.toDate(f.date);
                return d.getFullYear() === 2026 && d.getMonth() === i;
              }), 'montantTTC');
              var ca2025 = E.chiffreAffaires[i];
              return {
                id: String(i), mois: m.charAt(0).toUpperCase() + m.slice(1),
                ca2025: ca2025, ca2026: ca2026,
                ecart: ca2026 - ca2025,
                evolution: ca2025 ? Math.round((ca2026 - ca2025) / ca2025 * 100) : 0,
              };
            });
            return el('div.space-y-3', null, [
              K.note('L’exercice 2026 est alimenté par le jeu de démonstration du prototype : la comparaison illustre le mécanisme, '
                + 'elle ne reflétera l’activité réelle qu’après la bascule en production.', { tone: 'info' }),
              U.card('Chiffre d’affaires 2025 et 2026',
                G.barres(moisCourts.map(function (m) { return m.slice(0, 4); }), [
                  { label: '2025 (réel)', data: rows.map(function (r) { return r.ca2025; }), color: G.TONES.navy },
                  { label: '2026 (prototype)', data: rows.map(function (r) { return r.ca2026; }), color: G.TONES.vert },
                ])),
              U.dataTable({
                rows: rows, exportName: 'comparaison-2025-2026', pageSize: 13, searchable: false,
                columns: [
                  { key: 'mois', label: 'Mois', nowrap: true },
                  { key: 'ca2025', label: 'CA 2025 (réel)', align: 'right', text: function (r) { return C.money(r.ca2025, false); }, render: function (r) { return C.money(r.ca2025, false); } },
                  { key: 'ca2026', label: 'CA 2026', align: 'right', text: function (r) { return C.money(r.ca2026, false); }, render: function (r) { return C.money(r.ca2026, false); } },
                  {
                    key: 'ecart', label: 'Écart', align: 'right',
                    text: function (r) { return C.money(r.ecart, false); },
                    render: function (r) {
                      return el('span', { class: r.ecart >= 0 ? 'text-success-700' : 'text-danger-600', text: (r.ecart > 0 ? '+' : '') + C.money(r.ecart, false) });
                    },
                  },
                  {
                    key: 'evolution', label: 'Évolution', align: 'right',
                    render: function (r) { return U.badge((r.evolution > 0 ? '+' : '') + r.evolution + ' %', r.evolution >= 0 ? 'success' : 'danger'); },
                  },
                ],
              }),
            ]);
          },
        },
      ]));

      host.appendChild(K.source('Classeur comptable SYSCOHADA et compte de résultat 2025 — feuilles « DEPENSES25 » et « Recette ».'));
      root.appendChild(host);
      return null;
    },
    actions: function () {
      return [K.btn('Imprimer le compte de résultat 2025', {
        variant: 'primary', icon: 'printer',
        onclick: function () {
          var E = global.SIGH.compta.EXERCICE_2025;
          P.etat({
            titre: 'Compte de résultat — exercice 2025',
            sousTitre: 'Baseline financière de référence',
            cartouche: [
              ['Exercice', '2025'],
              ['Chiffre d’affaires', C.money(E.totalChiffreAffaires)],
              ['Charges d’exploitation', C.money(E.totalCharges)],
              ['Résultat', C.money(E.resultat)],
              ['Hors exploitation', C.money(E.totalHorsExploitation)],
              ['Date d’édition', C.dateFR(AUJ)],
            ],
            contenu: el('div.space-y-4', null, [
              el('p.text-\\[11px\\].font-bold.uppercase.text-navy-900', { text: 'Chiffre d’affaires mensuel' }),
              P.tableau([
                { label: 'Mois', key: 'm' },
                { label: 'Chiffre d’affaires', key: 'ca', align: 'right' },
                { label: 'Charges', key: 'ch', align: 'right' },
                { label: 'Résultat', key: 'res', align: 'right' },
              ], E.mois.map(function (m, i) {
                return {
                  m: m.charAt(0).toUpperCase() + m.slice(1),
                  ca: C.money(E.chiffreAffaires[i], false),
                  ch: C.money(Math.round(E.chargesDuMois(i)), false),
                  res: C.money(Math.round(E.resultatDuMois(i)), false),
                };
              }), {
                total: {
                  m: 'TOTAL 2025', ca: C.money(E.totalChiffreAffaires, false),
                  ch: C.money(E.totalCharges, false), res: C.money(E.resultat, false),
                },
                totalLabel: '',
              }),
              el('p.mt-4.text-\\[11px\\].font-bold.uppercase.text-navy-900', { text: 'Postes de charges' }),
              P.tableau([
                { label: 'Compte', value: function (p) { return p.num || '(à rattacher)'; } },
                { label: 'Libellé', key: 'libelle' },
                { label: 'Total 2025', align: 'right', value: function (p) { return C.money(p.total, false); },
                  somme: function (p) { return p.total || 0; } },
                { label: 'Poids', align: 'right', value: function (p) { return C.pct(p.total / E.totalCharges * 100); } },
              ], E.postesCharges(), { total: true }),
              el('p.mt-3.text-\\[9px\\].italic.text-slate-600', {
                text: 'Les postes « emprunt », « dépôts et cautionnements » et « matériel de bureau » figurant au classeur des '
                  + 'dépenses constituent des mouvements de bilan et sont exclus des charges d’exploitation retenues ci-dessus.',
              }),
            ]),
            signatures: [{ role: 'Le Comptable', nom: 'SANOUSSI Adamon' },
              { role: 'La Direction', nom: 'SOKOU Peace' },
              { role: 'Le Directeur Général', nom: 'GBAGUIDI Rafiou' }],
          });
        },
      })];
    },
  });
  /* ==========================================================================
   * ÉCHÉANCES FISCALES & PAIEMENTS
   * --------------------------------------------------------------------------
   * Demande de la Direction : que le logiciel prévienne des paiements à venir,
   * rappelle ceux qui approchent, et permette de valider un paiement effectué.
   *
   * Le calendrier fiscal donne les obligations ; cet écran les déroule sur
   * l'exercice, en fait des échéances datées, et suit leur état :
   *   à venir · déclaration attendue · à payer · en retard · payé.
   *
   * Une échéance dépassée et non payée est un risque de pénalité — elle est
   * donc signalée à l'ouverture, et pas seulement listée.
   * ======================================================================== */
  function colEcheances() { return S.collection('echeancesFiscales', { module: 'M12', entite: 'échéance fiscale', prefix: 'ECH' }); }

  var ETATS_ECHEANCE = [
    { id: 'payee', label: 'Payée', tone: 'success' },
    { id: 'en_retard', label: 'En retard', tone: 'danger' },
    { id: 'a_payer', label: 'À payer', tone: 'warning' },
    { id: 'declaration', label: 'Déclaration attendue', tone: 'info' },
    { id: 'a_venir', label: 'À venir', tone: 'neutral' },
  ];

  function etatEcheance(id) {
    return ETATS_ECHEANCE.filter(function (e) { return e.id === id; })[0] || ETATS_ECHEANCE[4];
  }

  /** Reporte au jour ouvrable suivant — précision du comptable. */
  function jourOuvrableSuivant(d) {
    var x = new Date(d.getTime());
    while (x.getDay() === 0 || x.getDay() === 6) x = C.addDays(x, 1);
    return x;
  }

  /* Déroule le calendrier sur l'exercice : chaque obligation mensuelle donne
     douze échéances, chaque obligation annuelle en donne une. */
  /* Le calendrier est désormais amorcé par le MAGASIN : trois modules le
     lisent. Cette fonction reste comme filet — elle ne fait rien si la
     collection est déjà là, ce qui est le cas normal. */
  function amorcerEcheances() {
    var db = S.raw();
    if (db.echeancesFiscales && db.echeancesFiscales.length) return;
    var annee = AUJ.getFullYear();
    var out = [], n = 0;
    D.CALENDRIER_FISCAL.forEach(function (o) {
      var dates = [];
      if (o.periodicite === 'mensuelle') {
        for (var m = 0; m < 12; m++) dates.push(new Date(annee, m, o.jour));
      } else {
        dates.push(new Date(annee, o.mois, Math.min(o.jour, 28)));
      }
      dates.forEach(function (d) {
        n++;
        var echue = jourOuvrableSuivant(d);
        var passee = echue < AUJ;
        out.push({
          id: 'ECH' + C.pad(n, 4), statut: 'actif',
          code: o.code, libelle: o.libelle, famille: o.famille,
          periodicite: o.periodicite, part: o.part, declaration: o.declaration, note: o.note,
          exercice: annee,
          periode: o.periodicite === 'mensuelle' ? C.MOIS[Math.max(0, d.getMonth() - 1)] + ' ' + annee : String(annee),
          echeance: C.iso(echue),
          reportee: C.iso(echue) !== C.iso(d),
          /* Les échéances passées sont réputées honorées, sauf les deux plus
             récentes — pour que l'écran ait quelque chose à montrer. */
          paye: passee && C.daysBetween(echue, AUJ) > 25,
          datePaiement: null, montant: null, reference: null, valideePar: null,
        });
      });
    });
    out.forEach(function (e) {
      if (e.paye) {
        e.datePaiement = e.echeance;
        e.valideePar = 'SANOUSSI Adamon';
        e.reference = 'QUIT-' + e.code + '-' + e.exercice;
      }
    });
    db.echeancesFiscales = out;
    S.save();
  }

  /** État calculé d'une échéance — jamais stocké, toujours recalculé. */
  function calculerEtat(e) {
    if (e.paye) return 'payee';
    var j = C.daysBetween(AUJ, e.echeance);
    if (j < 0) return 'en_retard';
    if (j <= 10) return 'a_payer';
    if (e.declaration && j <= 30) return 'declaration';
    return 'a_venir';
  }

  global.SIGH.screen('m12-echeances', {
    title: 'Échéances fiscales & paiements',
    description: 'Suivi des obligations fiscales et sociales : ce qui est dû, ce qui approche, ce qui est réglé.',
    regle: 'Chaque obligation du calendrier est déroulée sur l’exercice. Une échéance <strong>dépassée et non '
      + 'réglée</strong> est signalée à l’ouverture de l’écran — une pénalité se constate rarement à temps. '
      + 'La validation d’un paiement porte son auteur, sa date et sa référence de quittance (RG-12).',
    actions: function () {
      return [
        K.btn('Obligations & règles', { icon: 'book-open-check', onclick: function () { global.SIGH.app.go('cfg-comptabilite'); } }),
      ];
    },
    render: function (root) {
      amorcerEcheances();
      dessiner();
      return null;

      function lignes() {
        return colEcheances().active().map(function (e) {
          return Object.assign({}, e, {
            etat: calculerEtat(e),
            jours: C.daysBetween(AUJ, e.echeance),
          });
        });
      }

      function dessiner() {
        C.clear(root);
        var rows = lignes();
        var retard = rows.filter(function (e) { return e.etat === 'en_retard'; });
        var aPayer = rows.filter(function (e) { return e.etat === 'a_payer'; });
        var declarations = rows.filter(function (e) { return e.etat === 'declaration'; });
        var payees = rows.filter(function (e) { return e.etat === 'payee'; });
        var host = el('div.space-y-4');

        host.appendChild(U.kpiGrid([
          {
            label: 'En retard', value: C.num(retard.length), icon: 'alarm-clock',
            tone: retard.length ? 'danger' : 'success',
            hint: retard.length ? 'Risque de pénalité' : 'Aucun retard',
          },
          {
            label: 'À payer sous 10 jours', value: C.num(aPayer.length), icon: 'coins',
            tone: aPayer.length ? 'warning' : 'success',
          },
          { label: 'Déclarations attendues', value: C.num(declarations.length), icon: 'file-pen-line', tone: 'info' },
          {
            label: 'Réglées sur l’exercice', value: C.num(payees.length), icon: 'check-circle-2', tone: 'success',
            hint: C.num(rows.length) + ' échéances au total',
          },
        ]));

        /* --- Barre de notification --------------------------------------
           Ce que la Direction demandait : être prévenu, pas devoir chercher. */
        var barre = el('div.space-y-2');
        if (retard.length) {
          barre.appendChild(alerte('danger', 'alarm-clock',
            retard.length + ' échéance(s) dépassée(s) et non réglée(s)',
            retard.slice(0, 3).map(function (e) {
              return e.code + ' — ' + C.dateFR(e.echeance) + ' (' + Math.abs(e.jours) + ' j de retard)';
            }).join(' · ') + (retard.length > 3 ? ' …' : ''),
            retard[0]));
        }
        if (aPayer.length) {
          barre.appendChild(alerte('warning', 'coins',
            aPayer.length + ' paiement(s) à effectuer sous dix jours',
            aPayer.slice(0, 3).map(function (e) {
              return e.code + ' le ' + C.dateFR(e.echeance);
            }).join(' · ') + (aPayer.length > 3 ? ' …' : ''),
            aPayer[0]));
        }
        if (declarations.length) {
          barre.appendChild(alerte('info', 'file-pen-line',
            declarations.length + ' déclaration(s) à préparer',
            'Une déclaration précède le paiement : ' + declarations.slice(0, 2).map(function (e) {
              return e.code + ' — ' + e.declaration;
            }).join(' · '), null));
        }
        if (!retard.length && !aPayer.length && !declarations.length) {
          barre.appendChild(alerte('success', 'check-circle-2',
            'Aucune échéance en attente immédiate',
            'La prochaine obligation tombe le ' + (rows.filter(function (e) { return e.jours >= 0 && !e.paye; })
              .sort(function (a, b) { return a.jours - b.jours; })[0] || {}).echeance, null));
        }
        host.appendChild(barre);

        host.appendChild(U.dataTable({
          title: 'Échéances de l’exercice ' + AUJ.getFullYear(),
          rows: rows, exportName: 'echeances-fiscales', pageSize: 20, searchable: true,
          defaultSort: 'echeance',
          filters: [
            {
              name: 'etat', label: 'État',
              options: ETATS_ECHEANCE.map(function (e) { return { value: e.id, label: e.label }; }),
            },
            {
              name: 'famille', label: 'Obligation',
              options: Object.keys(C.groupBy(rows, 'famille')).sort(),
            },
            {
              name: 'periodicite', label: 'Périodicité',
              options: [{ value: 'mensuelle', label: 'Mensuelle' }, { value: 'annuelle', label: 'Annuelle' }],
            },
          ],
          columns: [
            { key: 'code', label: 'Code', nowrap: true, render: function (e) { return el('span.font-mono.text-xs.font-semibold', { text: e.code }); } },
            {
              key: 'libelle', label: 'Obligation',
              render: function (e) {
                return el('div.min-w-0', null, [
                  el('p.truncate.text-sm.text-slate-800', { text: e.libelle }),
                  el('p.truncate.text-xs.text-slate-400', {
                    text: e.periode + (e.part && e.part < 100 ? ' · tranche de ' + e.part + ' %' : ''),
                  }),
                ]);
              },
            },
            {
              key: 'echeance', label: 'Échéance', nowrap: true,
              text: function (e) { return C.dateFR(e.echeance); },
              render: function (e) {
                return el('div', null, [
                  el('p.text-sm.text-slate-700', { text: C.dateFR(e.echeance) }),
                  e.reportee ? el('p.text-\\[10px\\].text-warning-600', { text: 'reportée — jour ouvrable' }) : null,
                ]);
              },
              sortValue: function (e) { return C.toDate(e.echeance).getTime(); },
            },
            {
              key: 'jours', label: 'Délai', align: 'right',
              render: function (e) {
                if (e.paye) return el('span.text-xs.text-slate-400', { text: '—' });
                if (e.jours < 0) return el('span.num.font-semibold.text-danger-600', { text: Math.abs(e.jours) + ' j de retard' });
                return el('span.num', {
                  class: e.jours <= 10 ? 'font-semibold text-warning-700' : 'text-slate-600',
                  text: 'dans ' + e.jours + ' j',
                });
              },
            },
            {
              key: 'etat', label: 'État',
              text: function (e) { return etatEcheance(e.etat).label; },
              render: function (e) {
                var s = etatEcheance(e.etat);
                return U.badge(s.label, s.tone);
              },
            },
            {
              key: 'montant', label: 'Montant réglé', align: 'right',
              text: function (e) { return e.montant ? String(e.montant) : ''; },
              render: function (e) {
                return e.montant
                  ? el('span.font-semibold', { text: C.money(e.montant, false) })
                  : el('span.text-xs.text-slate-300', { text: '—' });
              },
            },
            {
              key: 'valideePar', label: 'Validé par',
              render: function (e) {
                return e.valideePar
                  ? el('div', null, [
                    el('p.text-xs.text-slate-600', { text: e.valideePar }),
                    el('p.text-\\[10px\\].text-slate-400', { text: e.reference || '' }),
                  ])
                  : el('span.text-xs.text-slate-300', { text: 'non réglée' });
              },
            },
          ],
          onRowClick: fiche,
          rowActions: function (e) {
            if (e.paye) {
              return [
                K.iconBtn('printer', 'Éditer la quittance', function () { imprimerQuittance(e); }),
                K.iconBtn('undo-2', 'Annuler la validation', function () { annulerPaiement(e); }),
              ];
            }
            return [
              K.iconBtn('check', 'Valider le paiement effectué', function () { validerPaiement(e); }),
              K.iconBtn('bell', 'Rappeler cette échéance', function () { rappeler(e); }),
            ];
          },
        }));

        root.appendChild(host);
        U.icons(root);

        /* Notification sonore à l'ouverture — le comptable ne consulte pas
           l'écran tous les jours ; c'est l'écran qui doit l'avertir. */
        if (retard.length || aPayer.length) {
          setTimeout(function () {
            U.alerter(
              (retard.length ? retard.length + ' échéance(s) en retard' : aPayer.length + ' paiement(s) sous dix jours'),
              {
                son: retard.length ? 'alerte' : 'rappel',
                type: retard.length ? 'error' : 'warning',
                detail: (retard[0] || aPayer[0]).libelle + ' — ' + C.dateFR((retard[0] || aPayer[0]).echeance),
                duration: 9000,
              }
            );
          }, 800);
        }
      }

      function alerte(tone, icone, titre, detail, cible) {
        var d = el('div.flex.items-start.gap-3.rounded-lg.border.px-3.py-2\\.5', {
          class: 'border-' + tone + '-200 bg-' + tone + '-50',
        });
        d.appendChild(el('span.mt-0\\.5.shrink-0', { class: 'text-' + tone + '-600' }, C.icon(icone, 'h-4 w-4')));
        d.appendChild(el('div.min-w-0.flex-1', null, [
          el('p.text-sm.font-semibold', { class: 'text-' + tone + '-900', text: titre }),
          el('p.mt-0\\.5.text-xs', { class: 'text-' + tone + '-800', text: detail }),
        ]));
        if (cible) {
          d.appendChild(K.btn('Valider le paiement', {
            size: 'sm', variant: tone === 'danger' ? 'danger' : 'primary', icon: 'check',
            onclick: function () { validerPaiement(cible); },
          }));
        }
        return d;
      }

      /* --- Validation d'un paiement effectué ---------------------------- */
      function validerPaiement(e) {
        var f = U.form([
          { name: 'datePaiement', label: 'Date du paiement', type: 'date', required: true, value: C.iso(AUJ) },
          { name: 'montant', label: 'Montant réglé (FCFA)', type: 'money', required: true, min: 1 },
          {
            name: 'moyen', label: 'Moyen de règlement', type: 'select', required: true,
            options: ['Virement bancaire', 'Chèque', 'Espèces', 'Mobile Money'],
          },
          { name: 'reference', label: 'Référence de quittance', required: true, help: 'Numéro du reçu délivré par l’administration.' },
          { name: 'valideePar', label: 'Validé par', required: true, value: S.currentUser() },
          { name: 'observation', label: 'Observation', type: 'textarea', rows: 2, col: 'full' },
        ], {});

        var m = U.modal({
          title: 'Valider le paiement — ' + e.code,
          subtitle: e.libelle + ' · échéance du ' + C.dateFR(e.echeance),
          size: 'lg',
          body: el('div.space-y-3', null, [
            U.descList([
              ['Obligation', e.libelle],
              ['Période', e.periode],
              ['Échéance', C.dateFR(e.echeance) + (e.reportee ? ' (reportée au jour ouvrable)' : '')],
              ['Part', e.part ? e.part + ' %' : '—'],
              ['Déclaration préalable', e.declaration || 'aucune'],
            ]),
            f,
            e.jours < 0
              ? K.note('<strong>Échéance dépassée de ' + Math.abs(e.jours) + ' jour(s).</strong> '
                + 'Une pénalité de retard peut s’appliquer : la consigner en observation.', { tone: 'danger', icon: 'alarm-clock' })
              : K.note('La validation est <strong>journalisée</strong> avec son auteur, sa date et sa référence '
                + 'de quittance (RG-12). Elle reste annulable.', { tone: 'info' }),
          ]),
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Confirmer le paiement', {
              variant: 'primary', icon: 'check',
              onclick: function () {
                var v = f.collect();
                if (!v) return;
                var res = colEcheances().update(e.id, {
                  paye: true, datePaiement: v.datePaiement, montant: v.montant,
                  moyen: v.moyen, reference: v.reference, valideePar: v.valideePar,
                  observation: v.observation || null,
                });
                S.log('Paiement fiscal validé', 'M12', e.libelle, e.code,
                  { etat: 'non réglée' }, { montant: v.montant, reference: v.reference });
                m.close(); dessiner();
                U.toast(e.code + ' — paiement de ' + C.money(v.montant) + ' validé.', {
                  type: 'success', detail: 'Quittance ' + v.reference,
                  undo: function () { res.undo(); dessiner(); },
                });
              },
            }),
          ],
        });
      }

      function annulerPaiement(e) {
        U.confirm({
          title: 'Annuler la validation du paiement ' + e.code + ' ?',
          message: 'L’échéance redeviendra due. L’annulation est journalisée — elle ne fait pas disparaître '
            + 'la trace du paiement initialement enregistré.',
          confirmLabel: 'Annuler la validation', danger: true, requireMotif: true,
        }).then(function (ok) {
          if (!ok) return;
          var res = colEcheances().update(e.id, {
            paye: false, datePaiement: null, montant: null, reference: null, valideePar: null,
            motifAnnulation: ok.motif,
          });
          dessiner();
          U.toast('Validation annulée — l’échéance redevient due.', {
            type: 'warning', undo: function () { res.undo(); dessiner(); },
          });
        });
      }

      function rappeler(e) {
        U.alerter('Rappel — ' + e.libelle, {
          son: 'rappel', type: 'info',
          detail: 'Échéance du ' + C.dateFR(e.echeance)
            + (e.declaration ? ' · ' + e.declaration : '')
            + (e.jours >= 0 ? ' · dans ' + e.jours + ' jour(s)' : ' · dépassée de ' + Math.abs(e.jours) + ' jour(s)'),
          duration: 9000,
        });
      }

      function fiche(e) {
        U.drawer({
          title: e.code + ' — ' + e.libelle,
          subtitle: e.periode + ' · échéance du ' + C.dateFR(e.echeance),
          width: 'max-w-2xl',
          body: el('div.space-y-4', null, [
            U.descList([
              ['Obligation', e.libelle], ['Périodicité', e.periodicite],
              ['Période concernée', e.periode],
              ['Échéance', C.dateFR(e.echeance) + (e.reportee ? ' — reportée au jour ouvrable suivant' : '')],
              ['Part', e.part ? e.part + ' %' : '—'],
              ['Déclaration préalable', e.declaration || 'aucune'],
              ['État', etatEcheance(e.etat).label],
              ['Montant réglé', e.montant ? C.money(e.montant) : '—'],
              ['Quittance', e.reference || '—'],
              ['Validé par', e.valideePar || '—'],
            ]),
            K.note(e.note, { tone: 'info' }),
          ]),
          footer: e.paye
            ? [K.btn('Éditer la quittance', { variant: 'primary', icon: 'printer', onclick: function () { imprimerQuittance(e); } })]
            : [K.btn('Valider le paiement', { variant: 'primary', icon: 'check', onclick: function () { validerPaiement(e); } })],
        });
      }

      function imprimerQuittance(e) {
        P.etat({
          titre: 'Justificatif de paiement — obligation fiscale',
          sousTitre: e.code + ' · ' + e.libelle,
          cartouche: [['Obligation', e.libelle], ['Code', e.code],
            ['Période', e.periode], ['Échéance', C.dateFR(e.echeance)],
            ['Date de paiement', e.datePaiement ? C.dateFR(e.datePaiement) : '—'],
            ['Montant réglé', e.montant ? C.money(e.montant) : '—'],
            ['Moyen', e.moyen || '—'], ['Quittance', e.reference || '—']],
          contenu: el('div.space-y-3', null, [
            P.tableau([{ label: 'Rubrique', key: 'k' }, { label: 'Information', key: 'v' }], [
              { k: 'Obligation', v: e.libelle },
              { k: 'Base réglementaire', v: e.note },
              { k: 'Part acquittée', v: e.part ? e.part + ' %' : 'Intégralité' },
              { k: 'Déclaration préalable', v: e.declaration || 'Sans objet' },
              { k: 'Référence de quittance', v: e.reference || '—' },
              { k: 'Validé par', v: e.valideePar || '—' },
              { k: 'Observation', v: e.observation || '—' },
            ]),
          ]),
          signatures: [{ role: 'Le Comptable', nom: e.valideePar || 'SANOUSSI Adamon' },
            { role: 'La Direction', nom: 'SOKOU Peace' }],
        });
      }
    },
  });

  /* ==========================================================================
   * DÉPENSES JOURNALIÈRES — saisie au fil de l'eau et historique
   * --------------------------------------------------------------------------
   * Une dépense de trésorerie directe est un décaissement qui constate une
   * charge sans passer par un compte fournisseur : on paie, et c'est fini.
   * Elle produit UNE écriture à deux lignes, toujours la même :
   *
   *     DÉBIT   compte de charge (classe 6)   — la charge est constatée
   *     CRÉDIT  compte de trésorerie (5xx)    — l'argent est sorti
   *
   * TROIS RÈGLES :
   *   1. RG-10 — l'écriture est contrôlée ÉQUILIBRÉE avant d'être posée. Le
   *      cas est trivial aujourd'hui ; le contrôle est là pour le jour où une
   *      dépense portera plusieurs lignes de charge.
   *   2. Elle naît EN BROUILLON. La validation comptable reste un geste
   *      humain, et d'autant plus qu'ici la saisie est ouverte à la caisse.
   *   3. Une dépense SANS JUSTIFICATIF est une charge contestable. Le reçu
   *      n'est pas bloquant — on n'empêche pas d'enregistrer une dépense
   *      réelle parce que le vendeur n'a pas de carnet — mais elle est
   *      comptée et signalée. C'est la première chose qu'un contrôle demande.
   * ======================================================================== */
  function colDepenses() {
    return S.collection('depenses', { module: 'M12', entite: 'dépense', prefix: 'DEP' });
  }
  function colTresorerie() {
    return S.collection('banques', { module: 'M12', entite: 'compte de trésorerie', prefix: 'BQ' });
  }

  /** Les comptes de charge du plan réel de la clinique — classe 6 et 671. */
  function comptesCharge() {
    return (D.PLAN_COMPTABLE || []).filter(function (c) {
      return /^6/.test(String(c.num));
    });
  }
  function categorieDepense(id) {
    return (D.CATEGORIES_DEPENSE || []).filter(function (c) { return c.id === id; })[0] || null;
  }
  function libelleCategorieDepense(id) {
    var c = categorieDepense(id);
    return c ? c.label : (id || '—');
  }
  function compteTresorerie(id) {
    return colTresorerie().active().filter(function (b) { return b.id === id; })[0] || null;
  }

  global.SIGH.screen('m12-depenses', {
    title: 'Dépenses journalières',
    description: 'Saisie au fil de l’eau des charges de trésorerie directes, avec justificatif, écriture automatique et historique.',
    regle: 'Une dépense de trésorerie constate une charge et sort de l’argent : elle produit une écriture '
      + '<strong>débit charge / crédit trésorerie</strong>, contrôlée <strong>équilibrée</strong> avant '
      + 'd’être posée (RG-10) et créée <strong>en brouillon</strong> — la validation comptable reste un '
      + 'geste humain. Le <strong>justificatif n’est pas bloquant mais il est compté</strong> : une charge '
      + 'sans reçu est une charge contestable.',
    actions: function () {
      return [
        K.btn('Écritures comptables', { icon: 'pencil-line',
          onclick: function () { global.SIGH.app.go('m12-ecritures'); } }),
      ];
    },
    render: function (root) {
      var vue = el('div.space-y-4');
      /* La plage de dates survit au redessin : la remettre à zéro à chaque
         saisie ferait perdre le filtre au moment où l'on s'en sert le plus. */
      var dDu = el('input.input', { type: 'date' });
      var dAu = el('input.input', { type: 'date' });
      dDu.addEventListener('change', function () { afficher(); });
      dAu.addEventListener('change', function () { afficher(); });

      root.appendChild(vue);
      amorcer();
      afficher();
      return null;

      function dansPlage(r) {
        var d = String(r.date || '').slice(0, 10);
        if (dDu.value && d < dDu.value) return false;
        if (dAu.value && d > dAu.value) return false;
        return true;
      }

      /* ------------------------------------------------------------------ */
      function amorcer() {
        var col = colDepenses();
        if (col.all().length) return;
        /* Un historique de neuf mois : sans lui, les indicateurs et les
           graphiques seraient à zéro et on croirait l'écran cassé. Les
           libellés sont ceux d'une clinique, pas des chaînes de test. */
        var rnd = C.seeded(4417);
        var MODELES = [
          ['medical', '6011', 'Achat de gants d’examen — boîte de 100', 12000, 45000],
          ['medical', '6041', 'Compresses stériles et sparadrap', 8000, 32000],
          ['medical', '6056', 'Petit matériel de soins', 15000, 60000],
          ['fonctionnement', '6052', 'Facture d’électricité SBEE', 180000, 420000],
          ['fonctionnement', '6051', 'Facture d’eau SONEB', 25000, 75000],
          ['fonctionnement', '6047', 'Fournitures de bureau', 12000, 55000],
          ['fonctionnement', '6043', 'Produits d’entretien et désinfectants', 15000, 48000],
          ['logistique', '6042', 'Carburant — groupe électrogène', 30000, 90000],
          ['logistique', '616', 'Transport de plis et courses', 3000, 12000],
          ['logistique', '6181', 'Déplacement à Cotonou — retrait de réactifs', 25000, 65000],
          ['entretien', '6241', 'Réparation de la plomberie du bloc', 20000, 85000],
          ['entretien', '6243', 'Maintenance du groupe électrogène', 35000, 120000],
          ['personnel', '6371', 'Vacation de personnel externe', 40000, 150000],
          ['personnel', '6384', 'Frais de mission — formation', 20000, 80000],
          ['fiscal', '6318', 'Frais bancaires BOA', 8000, 25000],
          ['fiscal', '6462', 'Droits de timbre', 2000, 8000],
          ['divers', '6383', 'Réception — visite de la zone sanitaire', 15000, 50000],
        ];
        var tresor = colTresorerie().active();
        var agents = S.collection('personnel').active()
          .filter(function (a) { return /comptab|caiss|direct/i.test(a.poste || ''); });

        S.enLot(function () {
          for (var k = 0; k < 190; k++) {
            var m = C.pick(rnd, MODELES);
            var jour = C.addDays(AUJ, -C.between(rnd, 0, 270));
            /* UNE PIÈCE SUR CINQ PORTE PLUSIEURS LIGNES (arbitrage du
               31/08/2026) : c'est la forme qu'exerce l'écran, et le total est
               LA SOMME des lignes — jamais un nombre tiré à part. */
            var lignes = [{ libelle: m[2], compteCharge: m[1], montant: C.between(rnd, m[3], m[4]) }];
            if (rnd() > 0.8) {
              var m2 = C.pick(rnd, MODELES);
              lignes.push({ libelle: m2[2], compteCharge: m2[1], montant: C.between(rnd, m2[3], m2[4]) });
              if (rnd() > 0.6) {
                var m3 = C.pick(rnd, MODELES);
                lignes.push({ libelle: m3[2], compteCharge: m3[1], montant: C.between(rnd, m3[3], m3[4]) });
              }
            }
            var montant = C.sum(lignes, 'montant');
            var compte = montant > 100000
              ? (tresor.filter(function (b) { return b.nature === 'banque'; })[0] || tresor[0])
              : (tresor.filter(function (b) { return b.nature === 'caisse'; })[0] || tresor[0]);
            var qui = agents.length ? C.pick(rnd, agents) : null;
            col.all().push({
              id: 'DEP' + C.pad(k + 1, 4), statut: 'actif',
              reference: 'DEP-' + String(C.toDate(jour).getFullYear()) + '-' + C.pad(k + 1, 4),
              date: C.iso(jour),
              lignes: lignes,
              montant: montant,
              libelle: lignes[0].libelle + (lignes.length > 1 ? ' (+' + (lignes.length - 1) + ' autre(s))' : ''),
              compteCharge: lignes[0].compteCharge,
              compteTresorerie: compte ? compte.id : null,
              categorie: m[0],
              /* Une dépense sur six n'a pas de reçu. C'est la réalité du
                 terrain, et c'est précisément ce que l'écran doit compter. */
              justificatif: rnd() > 0.17 ? {
                nom: 'recu-' + C.pad(k + 1, 4) + '.jpg', type: 'image/jpeg',
                taille: C.between(rnd, 60000, 240000),
              } : null,
              saisiPar: qui ? qui.nomComplet : 'Caisse',
              saisiLe: C.iso(jour),
              ecritureId: null,
            });
          }
        });
        S.save();
      }

      /* ------------------------------------------------------------------
       * L'ÉCRITURE. Débit charge, crédit trésorerie, contrôlée équilibrée.
       * ---------------------------------------------------------------- */
      /* Les lignes d'une dépense — héritage compris : une pièce d'avant
         l'arbitrage (libellé + compte + montant en tête) se lit comme UNE
         ligne, sans migration. */
      function lignesDe(dep) {
        if (dep.lignes && dep.lignes.length) return dep.lignes;
        return [{ libelle: dep.libelle, compteCharge: dep.compteCharge, montant: Number(dep.montant) || 0 }];
      }

      function poserEcriture(dep) {
        var tres = compteTresorerie(dep.compteTresorerie);
        var col = S.collection('ecritures', { module: 'M12', entite: 'écriture' });

        /* UNE ÉCRITURE PLATE PAR LIGNE, comme le moteur d'encaissement et le
           jeu de démonstration : même numéro de pièce, même date, un compte et
           un sens chacune. C'est cette forme que lisent le grand livre, la
           balance et le compte de résultat — en inventer une seconde rendrait
           la dépense invisible de tous les trois. */
        var base = {
          numero: dep.reference,
          date: dep.date,
          journal: tres && tres.nature === 'caisse' ? 'CAI' : 'BQE',
          journalLibelle: tres && tres.nature === 'caisse'
            ? 'Journal de caisse-dépenses' : 'Journal de banque',
          libelle: dep.libelle,
          pieceId: dep.id, pieceNumero: dep.reference,
          origine: 'Dépense journalière',
          /* EN BROUILLON : la validation comptable reste un geste humain, et
             d'autant plus qu'ici la saisie est ouverte à la caisse. */
          statut: 'brouillon',
        };
        /* ARBITRAGE DU 31/08/2026 : une facture porte UN OU PLUSIEURS libellés
           de dépense — un DÉBIT par ligne de charge, un crédit de trésorerie
           du TOTAL. C'est exactement le cas que le contrôle RG-10 attendait. */
        var lignes = lignesDe(dep).map(function (l) {
          return Object.assign({}, base, {
            compte: l.compteCharge, compteLibelle: compteLibelle(l.compteCharge),
            libelle: l.libelle,
            debit: Number(l.montant) || 0, credit: 0,
          });
        }).concat([
          Object.assign({}, base, {
            compte: tres ? tres.compteComptable : '5711',
            compteLibelle: tres ? tres.intitule : 'Caisse',
            libelle: 'Décaissement — ' + (tres ? tres.intitule : 'trésorerie'),
            debit: 0, credit: Number(dep.montant) || 0,
          }),
        ]);

        /* RG-10, contrôlé AVANT d'écrire : un déséquilibre ne doit pas entrer
           au journal, fût-il en brouillon. */
        var debit = C.sum(lignes, 'debit'), credit = C.sum(lignes, 'credit');
        if (debit !== credit) {
          U.toast('Écriture refusée.', { type: 'error',
            detail: 'RG-10 — débit ' + C.money(debit) + ' contre crédit ' + C.money(credit) + '.' });
          S.log('Écriture de dépense refusée — déséquilibre', 'M12', 'Ecriture', dep.reference,
            null, { debit: debit, credit: credit });
          return null;
        }

        var posees = lignes.map(function (l) { return col.insert(l).record; });
        S.log('Écriture de dépense', 'M12', 'Ecriture', dep.reference, null,
          { debit: debit, credit: credit, lignes: posees.length });
        /* On retient les DEUX identifiants : archiver la dépense doit archiver
           l'écriture entière, pas la moitié — une demi-écriture au journal
           serait pire qu'aucune. */
        return { id: posees[0].id, ids: posees.map(function (x) { return x.id; }) };
      }

      /* ------------------------------------------------------------------ */
      function champs() {
        var tresor = colTresorerie().active().map(function (b) {
          return { value: b.id, label: b.intitule,
            detail: (b.compteComptable || '') + (b.numeroCompte ? ' · ' + b.numeroCompte : '') };
        });
        return [
          { name: 'date', label: 'Date de la transaction', type: 'date', required: true },
          { name: 'compteTresorerie', label: 'Compte de trésorerie', type: 'select', required: true,
            options: tresor, help: 'D’où l’argent est sorti.' },
          { name: 'categorie', label: 'Catégorie de dépenses', type: 'select', required: true,
            options: (D.CATEGORIES_DEPENSE || []).map(function (c) {
              return { value: c.id, label: c.label };
            }),
            help: 'La lecture de gestion, distincte du compte : c’est elle que lit la Direction, '
              + 'qui ne raisonne pas en numéros de compte.' },
          { name: 'libelle', label: 'Objet de la pièce (facultatif)', col: 'full',
            placeholder: 'Repris de la première ligne si vide',
            help: 'La pièce porte SES LIGNES ci-dessous : le montant total est leur somme, jamais saisi à part.' },
        ];
      }

      /* --------------------------------------------------------------------
       * L'ÉDITEUR DE LIGNES — l'arbitrage du 31/08/2026
       * --------------------------------------------------------------------
       * « Une facture peut présenter un ou plusieurs libellés de dépenses » :
       * chaque ligne porte son libellé, son compte de charge et son montant,
       * avec ajout, édition et suppression DANS la modale. Le total de la
       * pièce est LA SOMME des lignes — le fournir à part, c'est le bug des
       * totaux, déjà payé deux fois sur ce prototype.
       * ------------------------------------------------------------------ */
      function editeurLignes(initiales) {
        var lignes = (initiales || []).map(function (l) { return Object.assign({}, l); });
        var bloc = el('div.rounded-lg.border.border-slate-200.p-3');
        bloc.appendChild(el('p.label', { text: 'Lignes de la dépense *' }));
        var zone = el('div');
        bloc.appendChild(zone);

        function formLigne(valeurs, surValide) {
          var fL = U.form([
            { name: 'libelle', label: 'Libellé de la ligne', required: true, col: 'full' },
            { name: 'compteCharge', label: 'Compte de charge (SYSCOHADA)', type: 'select', required: true,
              options: comptesCharge().map(function (c2) { return { value: c2.num, label: c2.num + ' — ' + c2.libelle }; }) },
            { name: 'montant', label: 'Montant (FCFA)', type: 'number', min: 1, required: true },
          ], valeurs || {});
          var mL = U.modal({
            title: valeurs ? 'Modifier la ligne' : 'Ajouter une ligne', size: 'lg', body: fL,
            footer: [
              K.btn('Annuler', { onclick: function () { mL.close(); } }),
              K.btn(valeurs ? 'Enregistrer' : 'Ajouter', { variant: 'primary', icon: 'check',
                onclick: function () {
                  var vL = fL.collect(); if (!vL) return;
                  vL.montant = Number(vL.montant);
                  surValide(vL); mL.close(); dessiner();
                } }),
            ],
          });
        }

        function dessiner() {
          C.clear(zone);
          if (!lignes.length) {
            zone.appendChild(el('p.py-2.text-xs.text-slate-400', { text: 'Aucune ligne — la pièce en exige au moins une.' }));
          } else {
            var t = el('table.tbl');
            var tb = el('tbody');
            lignes.forEach(function (l, i) {
              var tr = el('tr');
              tr.appendChild(el('td.text-sm', { text: l.libelle }));
              tr.appendChild(el('td.font-mono.text-xs.text-slate-500', { text: l.compteCharge }));
              tr.appendChild(el('td.num.text-right.text-sm', { text: C.money(l.montant, false) }));
              var actions = el('td.text-right');
              actions.appendChild(K.iconBtn('pencil', 'Modifier la ligne', function () {
                formLigne(l, function (vL) { lignes[i] = vL; });
              }));
              actions.appendChild(K.iconBtn('trash-2', 'Retirer la ligne', function () {
                lignes.splice(i, 1); dessiner();
              }, 'ghost'));
              tr.appendChild(actions);
              tb.appendChild(tr);
            });
            var pied = el('tr.border-t.border-slate-300');
            pied.appendChild(el('td.text-sm.font-semibold', { text: 'TOTAL — ' + lignes.length + ' ligne(s)' }));
            pied.appendChild(el('td'));
            pied.appendChild(el('td.num.text-right.text-sm.font-semibold',
              { text: C.money(C.sum(lignes, 'montant'), false) }));
            pied.appendChild(el('td'));
            tb.appendChild(pied);
            t.appendChild(tb);
            zone.appendChild(el('div.overflow-x-auto', null, t));
          }
          zone.appendChild(el('div.mt-2', null,
            K.btn('Ajouter une ligne', { size: 'sm', icon: 'plus',
              onclick: function () { formLigne(null, function (vL) { lignes.push(vL); }); } })));
          U.icons(zone);
        }
        dessiner();

        return {
          bloc: bloc,
          lire: function () { return lignes.slice(); },
          total: function () { return C.sum(lignes, 'montant'); },
        };
      }

      /* Le dépôt du reçu : U.form ne connaît pas de type « file ». Le champ se
         monte à côté, et le FileReader produit une donnée en base 64 conservée
         DANS LE POSTE — aucune requête réseau, comme le reste du logiciel. */
      function champFichier() {
        var input = el('input.input', {
          type: 'file', accept: '.pdf,.png,.jpg,.jpeg,image/png,image/jpeg,application/pdf',
          'aria-label': 'Reçu ou facture',
        });
        var apercu = el('div.mt-2');
        var meta = { valeur: null };
        input.addEventListener('change', function () {
          var file = input.files && input.files[0];
          C.clear(apercu);
          meta.valeur = null;
          if (!file) return;
          if (file.size > 2 * 1024 * 1024) {
            apercu.appendChild(K.note('Fichier de ' + Math.round(file.size / 1024) + ' Ko — au-delà de '
              + 'deux mégaoctets le stockage local sature vite. Photographier en résolution plus basse.',
            { tone: 'warning', icon: 'triangle-alert' }));
          }
          var lecteur = new FileReader();
          lecteur.onload = function () {
            meta.valeur = { nom: file.name, type: file.type, taille: file.size, donnees: lecteur.result };
            if (/pdf$/i.test(file.name)) {
              apercu.appendChild(el('p.mt-2.text-xs.text-slate-500',
                { text: file.name + ' — PDF prêt à être rattaché' }));
            } else {
              apercu.appendChild(el('img.mt-2.max-h-40.rounded-lg.border.border-slate-200.object-contain',
                { src: lecteur.result, alt: 'Aperçu du reçu' }));
            }
          };
          lecteur.readAsDataURL(file);
        });
        return {
          bloc: el('div', null, [
            el('label.label', { text: 'Reçu / facture (photo)' }), input, apercu,
            el('p.mt-1.text-xs.text-slate-500', {
              text: 'Facultatif, mais une dépense sans justificatif est signalée : c’est la première '
                + 'pièce qu’un contrôle réclame.' }),
          ]),
          lire: function () { return meta.valeur; },
        };
      }

      /* ------------------------------------------------------------------ */
      function totauxDepuisLignes(v, editeur) {
        var lignes = editeur.lire();
        if (!lignes.length) {
          U.toast('La pièce exige au moins une ligne de dépense.', { type: 'error' });
          return null;
        }
        return {
          lignes: lignes,
          /* LE TOTAL EST LEUR SOMME — jamais un nombre choisi à part. */
          montant: C.sum(lignes, 'montant'),
          libelle: (v.libelle || '').trim()
            || (lignes[0].libelle + (lignes.length > 1 ? ' (+' + (lignes.length - 1) + ' autre(s))' : '')),
          compteCharge: lignes[0].compteCharge,
        };
      }

      function nouvelle() {
        if (!K.droits('M12').editer) return;
        var f = U.form(champs(), { date: C.iso(AUJ), categorie: 'fonctionnement' });
        var editeur = editeurLignes([]);
        var fichier = champFichier();
        var m = U.modal({
          title: 'Nouvelle dépense',
          subtitle: 'Une pièce, une ou plusieurs lignes de charge — le total est leur somme.',
          size: 'lg', body: el('div.space-y-3', null, [f, editeur.bloc, fichier.bloc]),
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Enregistrer', { variant: 'primary', icon: 'check',
              onclick: function () {
                var v = f.collect();
                if (!v) return;
                var t = totauxDepuisLignes(v, editeur);
                if (!t) return;
                var sess = S.session() || {};
                var rec = colDepenses().insert({
                  reference: C.nextRef('DEP-' + String(C.toDate(v.date).getFullYear()) + '-', 4),
                  date: v.date,
                  lignes: t.lignes, montant: t.montant,
                  libelle: t.libelle, compteCharge: t.compteCharge,
                  compteTresorerie: v.compteTresorerie, categorie: v.categorie,
                  justificatif: fichier.lire(),
                  saisiPar: sess.nomComplet || sess.nom || 'Utilisateur',
                  saisiLe: C.iso(AUJ),
                }).record;
                var ec = poserEcriture(rec);
                if (ec) colDepenses().update(rec.id, { ecritureId: ec.id, ecritureIds: ec.ids });
                m.close(); afficher();
                U.toast('Dépense enregistrée.', { type: 'success',
                  detail: C.money(rec.montant) + ' en ' + t.lignes.length + ' ligne(s) — écriture '
                    + (ec ? 'en brouillon, à valider' : 'non posée')
                    + (rec.justificatif ? '' : ' · sans justificatif'),
                  undo: function () { colDepenses().archive(rec.id); afficher(); },
                  undoMessage: 'Dépense annulée.' });
              } }),
          ],
        });
      }

      function modifier(r) {
        var f = U.form(champs(), r);
        var editeur = editeurLignes(lignesDe(r));
        var fichier = champFichier();
        var m = U.modal({
          title: 'Modifier la dépense — ' + r.reference,
          subtitle: 'L’écriture liée sera refaite. Elle repart en brouillon.',
          size: 'lg',
          body: el('div.space-y-3', null, [
            f,
            editeur.bloc,
            /* Le reçu déjà joint reste, sauf si on en dépose un autre :
               rouvrir la fiche ne doit pas faire perdre la pièce. */
            r.justificatif ? K.note('Reçu déjà joint : <strong>' + r.justificatif.nom + '</strong>. '
              + 'Déposer un autre fichier le remplacera.', { tone: 'info', icon: 'paperclip' }) : null,
            fichier.bloc,
          ].filter(Boolean)),
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Enregistrer', { variant: 'primary', icon: 'check',
              onclick: function () {
                var v = f.collect();
                if (!v) return;
                var t = totauxDepuisLignes(v, editeur);
                if (!t) return;
                colDepenses().update(r.id, {
                  date: v.date,
                  lignes: t.lignes, montant: t.montant, libelle: t.libelle,
                  compteCharge: t.compteCharge, compteTresorerie: v.compteTresorerie,
                  categorie: v.categorie, justificatif: fichier.lire() || r.justificatif || null,
                });
                /* L'écriture suit la dépense : la laisser telle quelle
                   ferait diverger la comptabilité de la pièce qui la fonde. */
                /* TOUTES les lignes de l'ancienne écriture, pas la première :
                   en laisser une seule mettrait le journal en déséquilibre. */
                (r.ecritureIds || [r.ecritureId]).filter(Boolean).forEach(function (id) {
                  S.collection('ecritures').archive(id);
                });
                var ec = poserEcriture(colDepenses().get(r.id));
                if (ec) colDepenses().update(r.id, { ecritureId: ec.id, ecritureIds: ec.ids });
                m.close(); afficher();
                U.toast('Dépense modifiée.', { type: 'success',
                  detail: 'L’écriture a été refaite et repart en brouillon.' });
              } }),
          ],
        });
      }

      function supprimer(r) {
        U.confirm({
          title: 'Archiver la dépense ' + r.reference + ' ?',
          message: 'La dépense et son écriture sont archivées, jamais supprimées (RG-14). '
            + 'Elles restent consultables depuis la corbeille.',
          danger: true, confirmLabel: 'Archiver',
        }).then(function (ok) {
          if (!ok) return;
          var ids = (r.ecritureIds || [r.ecritureId]).filter(Boolean);
          colDepenses().archive(r.id);
          ids.forEach(function (id) { S.collection('ecritures').archive(id); });
          afficher();
          U.toast('Dépense archivée.', { type: 'success',
            undo: function () {
              colDepenses().restore(r.id);
              ids.forEach(function (id) { S.collection('ecritures').restore(id); });
              afficher();
            },
            undoMessage: 'Archivage annulé.' });
        });
      }

      function consulter(r) {
        var tres = compteTresorerie(r.compteTresorerie);
        U.drawer({
          title: r.libelle,
          subtitle: r.reference + ' — ' + C.dateFR(r.date),
          body: el('div.space-y-4', null, [
            U.descList([
              ['Référence', r.reference],
              ['Date de la transaction', C.dateFR(r.date)],
              ['Montant décaissé', C.money(r.montant) + ' — ' + lignesDe(r).length + ' ligne(s)'],
              ['Compte de trésorerie', tres ? tres.intitule + ' (' + tres.compteComptable + ')' : '—'],
              ['Catégorie de gestion', libelleCategorieDepense(r.categorie)],
              ['Justificatif', r.justificatif ? r.justificatif.nom : 'AUCUN — charge contestable'],
              ['Saisie par', (r.saisiPar || '—') + ' le ' + C.dateFR(r.saisiLe || r.date)],
              ['Écriture', r.ecritureId ? r.ecritureId + ' — en brouillon jusqu’à validation' : 'non posée'],
            ]),
            K.section('Lignes de la pièce',
              K.miniTable(['Libellé', 'Compte de charge', 'Montant'],
                lignesDe(r).map(function (l) {
                  return [l.libelle, l.compteCharge + ' — ' + compteLibelle(l.compteCharge), C.money(l.montant, false)];
                }))),
            K.note('Un <strong>débit par ligne de charge</strong>, un crédit de trésorerie du total ('
              + (tres ? tres.compteComptable : '5711') + '). Écriture équilibrée (RG-10), en brouillon : '
              + 'la validation comptable reste un geste humain.', { tone: 'info', icon: 'scale' }),
          ]),
          footer: [
            K.btn('Imprimer la pièce', { icon: 'printer', onclick: function () { imprimerPiece(r); } }),
          ],
        });
      }

      function imprimerPiece(r) {
        var tres = compteTresorerie(r.compteTresorerie);
        P.etat({
          titre: 'Pièce de dépense',
          sousTitre: r.reference + ' — ' + C.dateFR(r.date),
          cartouche: [
            ['Référence', r.reference], ['Date', C.dateFR(r.date)],
            ['Montant', C.money(r.montant) + ' (' + lignesDe(r).length + ' ligne(s))'],
            ['Trésorerie', tres ? tres.intitule : '—'],
            ['Catégorie', libelleCategorieDepense(r.categorie)],
            ['Justificatif', r.justificatif ? r.justificatif.nom : 'AUCUN'],
            ['Saisie par', r.saisiPar || '—'],
          ],
          contenu: el('div.space-y-3', null, [
            el('p.font-semibold', { text: 'Objet de la dépense' }),
            el('p', { text: r.libelle }),
            el('p.mt-3.font-semibold', { text: 'Écriture comptable' }),
            P.tableau([
              { label: 'Compte', value: function (x) { return x.compte; } },
              { label: 'Libellé', value: function (x) { return x.libelle; } },
              { label: 'Débit', align: 'right',
                value: function (x) { return x.debit ? C.money(x.debit, false) : ''; },
                somme: function (x) { return x.debit; } },
              { label: 'Crédit', align: 'right',
                value: function (x) { return x.credit ? C.money(x.credit, false) : ''; },
                somme: function (x) { return x.credit; } },
            ], lignesDe(r).map(function (l) {
              return { compte: l.compteCharge, libelle: l.libelle, debit: l.montant, credit: 0 };
            }).concat([
              { compte: tres ? tres.compteComptable : '5711',
                libelle: 'Décaissement — ' + (tres ? tres.intitule : 'trésorerie'),
                debit: 0, credit: r.montant },
            ]), { total: true }),
            r.justificatif ? null : el('p.mt-3.text-\\[10px\\].italic', {
              text: 'Aucun justificatif joint : cette charge est contestable en cas de contrôle.' }),
          ].filter(Boolean)),
          signatures: [{ role: 'Le bénéficiaire' }, { role: 'Le Comptable' },
            { role: 'La Direction', nom: 'SOKOU Peace' }],
        });
      }

      /* ------------------------------------------------------------------ */
      function afficher() {
        C.clear(vue);
        var rows = colDepenses().active().filter(dansPlage);
        var droits = K.droits('M12');

        var jour = C.iso(AUJ);
        var duJour = rows.filter(function (r) { return r.date === jour; });
        var duMois = rows.filter(function (r) { return String(r.date).slice(0, 7) === jour.slice(0, 7); });
        var sansRecu = rows.filter(function (r) { return !r.justificatif; });

        /* QUATRE indicateurs, pas cinq — arbitrage du 31/08/2026. La « dépense
           moyenne » est retirée : c'est le seul des cinq qui ne commande
           aucune action, et un bandeau se lit d'un regard. */
        vue.appendChild(U.kpiGrid([
          { label: 'Dépensé aujourd’hui', value: C.money(C.sum(duJour, 'montant')),
            icon: 'calendar', tone: 'navy', hint: C.num(duJour.length) + ' pièce(s)' },
          { label: 'Dépensé ce mois', value: C.money(C.sum(duMois, 'montant')),
            icon: 'calendar-range', tone: 'info', hint: C.num(duMois.length) + ' pièce(s)' },
          { label: 'Total enregistré', value: C.money(C.sum(rows, 'montant')),
            icon: 'wallet', tone: 'warning', hint: C.num(rows.length) + ' dépense(s)' },
          { label: 'Sans justificatif', value: C.num(sansRecu.length),
            icon: 'file-x', tone: sansRecu.length ? 'danger' : 'success',
            hint: sansRecu.length ? C.money(C.sum(sansRecu, 'montant')) + ' contestables' : 'toutes justifiées' },
        ]));

        if (sansRecu.length) {
          vue.appendChild(K.note('<strong>' + sansRecu.length + ' dépense(s) sans justificatif</strong>, '
            + 'pour ' + C.money(C.sum(sansRecu, 'montant')) + '. Le reçu n’est pas bloquant à la saisie — '
            + 'on n’empêche pas d’enregistrer une dépense réelle parce que le vendeur n’a pas de carnet — '
            + 'mais ces charges sont <strong>contestables en cas de contrôle</strong>. Le filtre '
            + '« Justificatif » les isole.', { tone: 'warning', icon: 'file-x' }));
        }

        /* Le filtre de date est un FILTRE, pas un tri : « du 1er au 15 août »
           ne se répond pas par un classement décroissant. */
        var barre = el('div.card');
        barre.appendChild(el('div.card-body.flex.flex-wrap.items-end.gap-3', null, [
          el('div', null, [el('label.label', { text: 'Du' }), dDu]),
          el('div', null, [el('label.label', { text: 'Au' }), dAu]),
          K.btn('Aujourd’hui', { size: 'sm', icon: 'calendar', onclick: function () {
            dDu.value = C.iso(AUJ); dAu.value = C.iso(AUJ); afficher();
          } }),
          K.btn('Ce mois', { size: 'sm', icon: 'calendar-range', onclick: function () {
            dDu.value = C.iso(AUJ).slice(0, 8) + '01'; dAu.value = C.iso(AUJ); afficher();
          } }),
          K.btn('Tout l’historique', { size: 'sm', icon: 'history', onclick: function () {
            dDu.value = ''; dAu.value = ''; afficher();
          } }),
        ]));
        vue.insertBefore(barre, vue.firstChild);

        vue.appendChild(U.dataTable({
          rows: rows, exportName: 'depenses-journalieres', pageSize: 15, searchable: true,
          defaultSort: 'date', defaultDir: 'desc',
          filters: [
            { name: 'categorie', label: 'Catégorie de dépenses',
              options: (D.CATEGORIES_DEPENSE || []).map(function (c) {
                return { value: c.id, label: c.label };
              }) },
            { name: 'compteCharge', label: 'Compte de charge',
              options: Object.keys(C.groupBy(rows, 'compteCharge')).sort().map(function (num) {
                return { value: num, label: num + ' — ' + compteLibelle(num) };
              }) },
            { name: 'compteTresorerie', label: 'Trésorerie',
              options: colTresorerie().active().map(function (b) {
                return { value: b.id, label: b.intitule };
              }) },
            { name: 'justificatif', label: 'Justificatif',
              options: [{ value: 'oui', label: 'Avec reçu' }, { value: 'non', label: 'Sans reçu' }],
              match: function (r, v) { return v === 'oui' ? !!r.justificatif : !r.justificatif; } },
          ],
          columns: [
            { key: 'date', label: 'Date', nowrap: true,
              text: function (r) { return C.dateFR(r.date); },
              render: function (r) { return C.dateFR(r.date); } },
            { key: 'reference', label: 'N°', nowrap: true,
              render: function (r) { return el('span.font-mono.text-xs', { text: r.reference }); } },
            { key: 'libelle', label: 'Libellé de la dépense' },
            { key: 'categorie', label: 'Catégorie', text: function (r) { return libelleCategorieDepense(r.categorie); },
              render: function (r) { return U.badge(libelleCategorieDepense(r.categorie), 'navy'); } },
            { key: 'compteCharge', label: 'Compte SYSCOHADA',
              render: function (r) {
                return el('div', null, [
                  el('span.font-mono.text-xs', { text: r.compteCharge }),
                  el('p.text-[10px].text-slate-400', { text: compteLibelle(r.compteCharge) }),
                ]);
              } },
            { key: 'compteTresorerie', label: 'Sortie de',
              text: function (r) { var b = compteTresorerie(r.compteTresorerie); return b ? b.intitule : '—'; },
              render: function (r) {
                var b = compteTresorerie(r.compteTresorerie);
                return b ? U.badge(b.banque, b.nature === 'caisse' ? 'warning' : 'info')
                  : el('span.text-slate-300', { text: '—' });
              } },
            { key: 'justificatif', label: 'Reçu', align: 'center',
              text: function (r) { return r.justificatif ? 'oui' : 'non'; },
              render: function (r) {
                return r.justificatif ? U.badge('Joint', 'success') : U.badge('Absent', 'danger');
              } },
            { key: 'montant', label: 'Montant', align: 'right',
              text: function (r) { return C.money(r.montant, false); },
              render: function (r) {
                return el('span.font-bold.text-navy-800', { text: C.money(r.montant, false) });
              } },
          ],
          onRowClick: consulter,
          rowActions: function (r) {
            var actes = [K.iconBtn('eye', 'Consulter', function () { consulter(r); })];
            /* Les commandes suivent les DROITS du profil : proposer une
               modification qu'on refusera ensuite promet une porte fermée. */
            if (droits.editer) {
              actes.push(K.iconBtn('pencil-line', 'Modifier', function () { modifier(r); }));
            }
            if (droits.annuler) {
              actes.push(K.iconBtn('archive', 'Archiver', function () { supprimer(r); }));
            }
            actes.push(K.iconBtn('printer', 'Imprimer la pièce', function () { imprimerPiece(r); }));
            return actes;
          },
          actions: [
            droits.editer ? K.btn('Nouvelle dépense', { variant: 'primary', icon: 'plus',
              onclick: nouvelle }) : null,
            K.btn('État des dépenses', { icon: 'printer', onclick: function () { imprimerEtat(rows); } }),
          ].filter(Boolean),
        }));

        if (!droits.editer) {
          vue.appendChild(K.note('Votre profil consulte les dépenses sans les saisir. '
            + 'La matrice des droits (M14) décide de cette ouverture.', { tone: 'neutral', icon: 'lock' }));
        }

        /* --- Les lectures graphiques, APRÈS les données ------------------ */
        var parMois = {}, ordre = [];
        rows.forEach(function (r) {
          var k = String(r.date).slice(0, 7);
          if (!parMois[k]) { parMois[k] = 0; ordre.push(k); }
          parMois[k] += Number(r.montant) || 0;
        });
        ordre.sort();

        var parCat = C.groupBy(rows, 'categorie');
        var catsRows = Object.keys(parCat).map(function (k) {
          return { id: k, label: libelleCategorieDepense(k),
            total: C.sum(parCat[k], 'montant'), nombre: parCat[k].length };
        });
        catsRows = C.sortBy(catsRows, 'total', 'desc');

        vue.appendChild(K.charts([
          {
            title: 'Dépenses par mois',
            render: function () {
              return G.barres(ordre.map(function (k) {
                return (C.MOIS[Number(k.split('-')[1]) - 1] || k).slice(0, 4) + ' ' + k.slice(2, 4);
              }), [{ label: 'Décaissé', data: ordre.map(function (k) { return parMois[k]; }),
                color: G.TONES.rouge }]);
            },
          },
          {
            title: 'Répartition par catégorie de dépenses',
            render: function () {
              return G.anneau(catsRows.map(function (r) { return r.label; }),
                catsRows.map(function (r) { return r.total; }));
            },
          },
        ]));

        vue.appendChild(U.card('Cumul par catégorie', U.dataTable({
          rows: catsRows, exportName: 'depenses-categories', pageSize: 10, searchable: false,
          columns: [
            { key: 'label', label: 'Catégorie de dépenses' },
            { key: 'nombre', label: 'Pièces', align: 'right' },
            { key: 'total', label: 'Montant', align: 'right',
              text: function (r) { return C.money(r.total, false); },
              render: function (r) { return el('span.font-semibold', { text: C.money(r.total, false) }); } },
          ],
        })));
      }

      function imprimerEtat(rows) {
        var lignes = C.sortBy(rows.slice(), 'date');
        P.etat({
          titre: 'État des dépenses de trésorerie',
          sousTitre: C.num(lignes.length) + ' dépense(s) — ' + C.money(C.sum(lignes, 'montant')),
          cartouche: [
            ['Nombre de pièces', C.num(lignes.length)],
            ['Total décaissé', C.money(C.sum(lignes, 'montant'))],
            ['Sans justificatif', C.num(lignes.filter(function (r) { return !r.justificatif; }).length)],
            ['Édité le', C.dateFR(AUJ)],
          ],
          contenu: P.tableau([
            { label: 'Date', value: function (r) { return C.dateFR(r.date); } },
            { label: 'N°', value: function (r) { return r.reference; } },
            { label: 'Libellé', value: function (r) { return r.libelle; } },
            { label: 'Compte', value: function (r) { return r.compteCharge; } },
            { label: 'Catégorie', value: function (r) { return libelleCategorieDepense(r.categorie); } },
            { label: 'Reçu', value: function (r) { return r.justificatif ? 'oui' : 'NON'; } },
            { label: 'Montant', align: 'right',
              value: function (r) { return C.money(r.montant, false); },
              somme: function (r) { return r.montant; } },
          ], lignes, { total: true }),
          signatures: [{ role: 'Le Comptable' },
            { role: 'La Direction', nom: 'SOKOU Peace' }],
        });
      }
    },
  });

  /* ==========================================================================
   * LE MOTEUR COMMUN AUX DEUX ÉCRANS
   * --------------------------------------------------------------------------
   * Le compte de résultat et le seuil de rentabilité lisent LES MÊMES
   * écritures et posent la même question — « combien de produits, combien de
   * charges » — pour en tirer deux lectures différentes. Deux moteurs auraient
   * divergé au premier correctif, et personne n'aurait su lequel croire.
   *
   * ON NE RETIENT QUE LES ÉCRITURES VALIDÉES. Un brouillon n'est pas un fait
   * comptable : le compter donnerait un résultat qui change quand le comptable
   * rectifie une saisie. Le nombre de brouillons écartés est ANNONCÉ — un
   * écart silencieux entre le journal et le résultat serait pire.
   * ======================================================================== */
  function ecrituresRetenues(bornes) {
    var brouillons = 0;
    var retenues = ecritures().filter(function (e) {
      if (bornes && !C.dansBornes(e.date, bornes)) return false;
      if (e.statut === 'brouillon') { brouillons++; return false; }
      return true;
    });
    return { lignes: retenues, brouillons: brouillons };
  }

  /** Le solde d'une rubrique : produits au crédit, charges au débit. */
  function soldeRubrique(lignes, rubrique) {
    var total = 0;
    lignes.forEach(function (e) {
      var r = D.rubriqueDuCompte(e.compte);
      if (!r || r.id !== rubrique.id) return;
      /* Un produit vit au CRÉDIT, une charge au DÉBIT. Prendre la différence
         dans le bon sens fait que les avoirs et les annulations se déduisent
         d'eux-mêmes, sans traitement particulier. */
      total += rubrique.sens === 'produit' ? (e.credit - e.debit) : (e.debit - e.credit);
    });
    return total;
  }

  /** La cascade SYSCOHADA — chaque solde retranche au précédent. */
  function soldesGestion(bornes) {
    var src = ecrituresRetenues(bornes);
    var r = {};
    (D.RUBRIQUES_RESULTAT || []).forEach(function (rub) { r[rub.id] = soldeRubrique(src.lignes, rub); });

    var margeCommerciale = r.ventes_march - r.achats_march;
    var production = r.production;
    var valeurAjoutee = margeCommerciale + production - r.consommations;
    var ebe = valeurAjoutee - r.personnel - r.impots;
    var exploitation = ebe - r.dotations - r.autres_charges;
    var financier = r.produits_fin - r.charges_fin;
    var net = exploitation + financier - r.impot_societes;

    return {
      rubriques: r,
      margeCommerciale: margeCommerciale,
      production: production,
      valeurAjoutee: valeurAjoutee,
      ebe: ebe,
      exploitation: exploitation,
      financier: financier,
      net: net,
      chiffreAffaires: r.ventes_march + production,
      brouillons: src.brouillons,
      nbLignes: src.lignes.length,
    };
  }

  /** Charges fixes et variables — le socle du seuil de rentabilité. */
  function chargesParNature(bornes) {
    var src = ecrituresRetenues(bornes);
    var fixe = 0, variable = 0, parCompte = {};
    src.lignes.forEach(function (e) {
      var num = String(e.compte || '');
      if (!/^6/.test(num)) return;
      var montant = (e.debit || 0) - (e.credit || 0);
      if (!montant) return;
      var nature = natureRetenue(num);
      if (nature === 'variable') variable += montant; else fixe += montant;
      if (!parCompte[num]) {
        parCompte[num] = { compte: num, libelle: compteLibelle(num), montant: 0, nature: nature };
      }
      parCompte[num].montant += montant;
    });
    return {
      fixe: fixe, variable: variable,
      comptes: C.sortBy(Object.keys(parCompte).map(function (k) { return parCompte[k]; }), 'montant', 'desc'),
      brouillons: src.brouillons,
    };
  }

  /* La nature retenue : celle du référentiel, sauf si la clinique l'a corrigée.
     La correction vit dans le magasin — c'est une décision de gestion, pas une
     donnée du plan comptable, et elle doit survivre au rechargement. */
  var CLE_NATURES = 'sigh-cbg:natures-charges';
  function naturesCorrigees() {
    try { return JSON.parse(S.storage.get(CLE_NATURES)) || {}; } catch (e) { return {}; }
  }
  function natureRetenue(num) {
    var corr = naturesCorrigees();
    return corr[num] || D.natureCharge(num);
  }
  function corrigerNature(num, nature) {
    var corr = naturesCorrigees();
    corr[num] = nature;
    S.storage.set(CLE_NATURES, JSON.stringify(corr));
  }

  /* ==========================================================================
   * COMPTE DE RÉSULTAT
   * ======================================================================== */
  global.SIGH.screen('m12-compte-resultat', {
    title: 'Compte de résultat',
    description: 'Soldes intermédiaires de gestion SYSCOHADA : marge, valeur ajoutée, EBE, résultat d’exploitation et résultat net.',
    regle: 'Le compte de résultat <strong>ne s’écrit pas d’un bloc</strong> : il se construit par soldes '
      + 'successifs, chacun retranchant au précédent. C’est cette cascade qui dit <strong>d’où vient</strong> '
      + 'le résultat, et pas seulement combien il vaut. Seules les écritures <strong>validées</strong> sont '
      + 'retenues — un brouillon n’est pas un fait comptable — et le nombre de brouillons écartés est annoncé.',
    actions: function () {
      return [
        K.btn('Seuil de rentabilité', { icon: 'target',
          onclick: function () { global.SIGH.app.go('m12-seuil-rentabilite'); } }),
        K.btn('Baseline 2025', { icon: 'history',
          onclick: function () { global.SIGH.app.go('m12-baseline-2025'); } }),
      ];
    },
    render: function (root) {
      var selPeriode = el('select.select');
      C.PERIODES.forEach(function (x) { selPeriode.appendChild(el('option', { value: x.id }, x.label)); });
      selPeriode.value = 'annee';
      var inDate = el('input.input', { type: 'date', value: C.iso(AUJ) });
      var vue = el('div.space-y-4');

      var barre = el('div.card');
      barre.appendChild(el('div.card-body.flex.flex-wrap.items-end.gap-3', null, [
        el('div', null, [el('label.label', { text: 'Période' }), selPeriode]),
        el('div', null, [el('label.label', { text: 'Arrêté au' }), inDate]),
        K.btn('Imprimer le compte de résultat', { variant: 'primary', icon: 'printer', onclick: imprimer }),
      ]));
      [selPeriode, inDate].forEach(function (c) { c.addEventListener('change', afficher); });
      root.appendChild(el('div.space-y-4', null, [barre, vue]));
      afficher();
      return null;

      function bornes() { return C.bornes(selPeriode.value, inDate.value); }

      function cascade(s2) {
        return [
          { cle: 'ventes_march', label: 'Ventes de marchandises', montant: s2.rubriques.ventes_march, sens: '+' },
          { cle: 'achats_march', label: 'Achats de marchandises consommés', montant: -s2.rubriques.achats_march, sens: '−' },
          { cle: 'marge', label: 'MARGE COMMERCIALE', montant: s2.margeCommerciale, solde: true,
            note: 'RG-02 facture les médicaments au prix d’achat, sans marge : ce solde doit être '
              + 'nul ou quasi nul. S’il ne l’est pas, c’est un signal, pas une bonne nouvelle.' },
          { cle: 'production', label: 'Prestations de services vendues', montant: s2.production, sens: '+' },
          { cle: 'consommations', label: 'Consommations intermédiaires', montant: -s2.rubriques.consommations, sens: '−' },
          { cle: 'va', label: 'VALEUR AJOUTÉE', montant: s2.valeurAjoutee, solde: true,
            note: 'Ce que la clinique crée par son travail, avant de rémunérer qui que ce soit.' },
          { cle: 'personnel', label: 'Charges de personnel', montant: -s2.rubriques.personnel, sens: '−' },
          { cle: 'impots', label: 'Impôts et taxes', montant: -s2.rubriques.impots, sens: '−' },
          { cle: 'ebe', label: 'EXCÉDENT BRUT D’EXPLOITATION', montant: s2.ebe, solde: true, fort: true,
            note: 'Ce qui reste après avoir payé les hommes et l’État. C’est LUI qu’on regarde pour '
              + 'savoir si l’exploitation tient debout : il ignore les amortissements et le '
              + 'financement, qui dépendent de décisions passées et non de l’activité de l’année.' },
          { cle: 'dotations', label: 'Dotations aux amortissements', montant: -s2.rubriques.dotations, sens: '−' },
          { cle: 'autres', label: 'Autres charges d’exploitation', montant: -s2.rubriques.autres_charges, sens: '−' },
          { cle: 'expl', label: 'RÉSULTAT D’EXPLOITATION', montant: s2.exploitation, solde: true },
          { cle: 'fin', label: 'RÉSULTAT FINANCIER', montant: s2.financier, solde: true,
            note: 'Les intérêts d’emprunt sont ici, PAS dans l’exploitation : les y mettre ferait '
              + 'juger l’activité sur des choix de financement.' },
          { cle: 'is', label: 'Impôt sur le résultat', montant: -s2.rubriques.impot_societes, sens: '−' },
          { cle: 'net', label: 'RÉSULTAT NET DE L’EXERCICE', montant: s2.net, solde: true, fort: true },
        ];
      }

      function afficher() {
        C.clear(vue);
        var b = bornes();
        var s2 = soldesGestion(b);
        var lignes = cascade(s2);

        vue.appendChild(K.note('<strong>' + C.libellePeriode(b) + '</strong> — '
          + C.num(s2.nbLignes) + ' écriture(s) validée(s) retenue(s).'
          + (s2.brouillons ? ' <strong>' + C.num(s2.brouillons) + ' brouillon(s) écarté(s)</strong> : '
            + 'un brouillon n’est pas un fait comptable, et le compter donnerait un résultat qui '
            + 'change quand le comptable rectifie une saisie.' : ''),
          { tone: s2.brouillons ? 'warning' : 'info', icon: 'book-open-text' }));

        vue.appendChild(U.kpiGrid([
          { label: 'Chiffre d’affaires', value: C.money(s2.chiffreAffaires), icon: 'trending-up', tone: 'success' },
          { label: 'Valeur ajoutée', value: C.money(s2.valeurAjoutee), icon: 'sparkles', tone: 'navy' },
          { label: 'Excédent brut d’exploitation', value: C.money(s2.ebe),
            icon: 'activity', tone: s2.ebe >= 0 ? 'success' : 'danger',
            hint: s2.chiffreAffaires ? C.pct(s2.ebe / s2.chiffreAffaires * 100) + ' du CA' : '' },
          { label: 'Résultat net', value: C.money(s2.net),
            icon: s2.net >= 0 ? 'smile' : 'frown', tone: s2.net >= 0 ? 'success' : 'danger',
            hint: s2.chiffreAffaires ? C.pct(s2.net / s2.chiffreAffaires * 100) + ' du CA' : '' },
        ]));

        var table = el('table.tbl');
        var tb = el('tbody');
        lignes.forEach(function (l) {
          var tr = el('tr', { class: l.solde ? 'bg-slate-50' : '' });
          tr.appendChild(el('td', null, el('div', null, [
            el('span', { class: l.solde ? (l.fort ? 'font-bold text-navy-800' : 'font-semibold') : '',
              text: (l.sens ? l.sens + '  ' : '') + l.label }),
            l.note ? el('p.mt-0\.5.text-\[10px\].text-slate-500', { text: l.note }) : null,
          ].filter(Boolean))));
          tr.appendChild(el('td.text-right.num', null, el('span', {
            class: l.solde
              ? (l.montant >= 0 ? 'font-bold text-success-700' : 'font-bold text-danger-600')
              : 'text-slate-700',
            text: C.money(l.montant, false),
          })));
          tb.appendChild(tr);
        });
        table.appendChild(tb);
        vue.appendChild(U.card('Soldes intermédiaires de gestion', table));

        vue.appendChild(K.charts([{
          title: 'De la valeur ajoutée au résultat net',
          render: function () {
            return G.barres(
              ['Valeur ajoutée', 'EBE', 'Résultat d’exploitation', 'Résultat net'],
              [{ label: 'Montant', data: [s2.valeurAjoutee, s2.ebe, s2.exploitation, s2.net],
                color: G.TONES.navy }], { horizontal: true, height: 240 });
          },
        }]));
      }

      function imprimer() {
        var b = bornes();
        var s2 = soldesGestion(b);
        P.etat({
          titre: 'Compte de résultat',
          sousTitre: C.libellePeriode(b),
          cartouche: [
            ['Période', C.libellePeriode(b)],
            ['Écritures retenues', C.num(s2.nbLignes)],
            ['Brouillons écartés', C.num(s2.brouillons)],
            ['Chiffre d’affaires', C.money(s2.chiffreAffaires)],
            ['Valeur ajoutée', C.money(s2.valeurAjoutee)],
            ['Excédent brut d’exploitation', C.money(s2.ebe)],
            ['Résultat d’exploitation', C.money(s2.exploitation)],
            ['Résultat net', C.money(s2.net)],
          ],
          contenu: P.tableau([
            { label: 'Solde intermédiaire de gestion', value: function (r) {
              return (r.sens ? r.sens + ' ' : '') + r.label;
            } },
            { label: 'Montant', align: 'right', value: function (r) { return C.money(r.montant, false); } },
          ], cascade(s2), { total: false }),
          signatures: [{ role: 'Le Comptable' },
            { role: 'La Direction', nom: 'SOKOU Peace' }],
        });
      }
    },
  });

  /* ==========================================================================
   * SEUIL DE RENTABILITÉ
   * ======================================================================== */
  global.SIGH.screen('m12-seuil-rentabilite', {
    title: 'Seuil de rentabilité',
    description: 'Charges fixes et variables, marge sur coût variable, seuil, point mort et marge de sécurité.',
    regle: 'Le seuil repose sur <strong>une distinction et une seule</strong> : les charges qui suivent '
      + 'l’activité et celles qui tombent qu’on travaille ou non. Cette répartition est un '
      + '<strong>jugement de gestion, pas une donnée du plan comptable</strong> : elle est proposée, '
      + 'affichée et corrigeable compte par compte. La cacher donnerait un seuil qui a l’air d’un fait '
      + 'alors qu’il dépend d’un choix.',
    actions: function () {
      return [
        K.btn('Compte de résultat', { icon: 'chart-no-axes-combined',
          onclick: function () { global.SIGH.app.go('m12-compte-resultat'); } }),
      ];
    },
    render: function (root) {
      var selPeriode = el('select.select');
      C.PERIODES.forEach(function (x) { selPeriode.appendChild(el('option', { value: x.id }, x.label)); });
      selPeriode.value = 'annee';
      var inDate = el('input.input', { type: 'date', value: C.iso(AUJ) });
      var vue = el('div.space-y-4');

      var barre = el('div.card');
      barre.appendChild(el('div.card-body.flex.flex-wrap.items-end.gap-3', null, [
        el('div', null, [el('label.label', { text: 'Période' }), selPeriode]),
        el('div', null, [el('label.label', { text: 'Arrêté au' }), inDate]),
        K.btn('Imprimer l’analyse', { variant: 'primary', icon: 'printer', onclick: imprimer }),
      ]));
      [selPeriode, inDate].forEach(function (c) { c.addEventListener('change', afficher); });
      root.appendChild(el('div.space-y-4', null, [barre, vue]));
      afficher();
      return null;

      function bornes() { return C.bornes(selPeriode.value, inDate.value); }

      function calcul() {
        var b = bornes();
        var s2 = soldesGestion(b);
        var ch = chargesParNature(b);
        var ca = s2.chiffreAffaires;
        var marge = ca - ch.variable;
        var taux = ca ? marge / ca : 0;
        var seuil = taux > 0 ? ch.fixe / taux : null;
        var securite = seuil != null ? ca - seuil : null;
        /* LE POINT MORT : la date à laquelle le seuil est atteint, en supposant
           l'activité régulière sur la période. C'est une approximation, et
           l'écran le dit — une clinique n'a pas un rythme constant. */
        var pointMort = (seuil != null && ca > 0 && seuil <= ca)
          ? C.addDays(b.debut, Math.round(seuil / ca * b.jours)) : null;
        return { b: b, ca: ca, fixe: ch.fixe, variable: ch.variable, marge: marge,
          taux: taux, seuil: seuil, securite: securite, pointMort: pointMort,
          comptes: ch.comptes, brouillons: ch.brouillons };
      }

      function afficher() {
        C.clear(vue);
        var r = calcul();

        vue.appendChild(K.note('La répartition <strong>fixe / variable</strong> est une '
          + '<strong>proposition</strong>. Aucun plan comptable ne la porte : elle relève de l’analyse '
          + 'de gestion. Elle est affichée compte par compte ci-dessous et se corrige d’un clic — '
          + 'le seuil se recalcule aussitôt.', { tone: 'warning', icon: 'triangle-alert' }));

        vue.appendChild(U.kpiGrid([
          { label: 'Chiffre d’affaires', value: C.money(r.ca), icon: 'trending-up', tone: 'success' },
          { label: 'Charges variables', value: C.money(r.variable), icon: 'activity', tone: 'info',
            hint: r.ca ? C.pct(r.variable / r.ca * 100) + ' du CA' : '' },
          { label: 'Charges fixes', value: C.money(r.fixe), icon: 'anchor', tone: 'warning' },
          { label: 'Marge sur coût variable', value: C.money(r.marge), icon: 'scale', tone: 'navy',
            hint: 'taux : ' + C.pct(r.taux * 100) },
          { label: 'Seuil de rentabilité', value: r.seuil != null ? C.money(r.seuil) : 'incalculable',
            icon: 'target', tone: 'navy',
            hint: r.seuil == null ? 'marge sur coût variable nulle ou négative' : 'CA à atteindre' },
          { label: 'Marge de sécurité',
            value: r.securite != null ? C.money(r.securite) : '—',
            icon: r.securite != null && r.securite >= 0 ? 'shield-check' : 'shield-alert',
            tone: r.securite != null && r.securite >= 0 ? 'success' : 'danger',
            hint: r.securite != null && r.ca
              ? C.pct(r.securite / r.ca * 100) + ' du CA' : '' },
        ]));

        if (r.seuil == null) {
          vue.appendChild(K.note('<strong>Le seuil ne peut pas être calculé.</strong> La marge sur coût '
            + 'variable est nulle ou négative : chaque prestation vendue coûte plus qu’elle ne rapporte, '
            + 'et aucun volume d’activité ne couvrirait les charges fixes. Ce n’est pas un défaut '
            + 'd’affichage, c’est le diagnostic.', { tone: 'danger', icon: 'triangle-alert' }));
        } else {
          vue.appendChild(K.note('<strong>' + C.money(r.seuil) + '</strong> de chiffre d’affaires '
            + 'couvrent les charges. Au-delà, chaque franc encaissé rapporte '
            + C.pct(r.taux * 100) + ' de marge.'
            + (r.pointMort ? ' <strong>Point mort atteint le ' + C.dateFR(r.pointMort) + '</strong> — '
              + 'en supposant l’activité régulière sur la période, ce qu’une clinique n’est jamais tout '
              + 'à fait.' : ' Le seuil n’est pas atteint sur la période retenue.')
            + '<br><em>Le seuil suppose la structure constante</em> : il vaut pour un niveau d’activité '
            + 'voisin de l’actuel. L’extrapoler au double serait faux — il faudrait embaucher, et les '
            + 'charges fixes changeraient de palier.',
          { tone: r.securite >= 0 ? 'success' : 'danger', icon: 'target' }));
        }

        vue.appendChild(K.charts([{
          title: 'Couverture des charges par le chiffre d’affaires',
          render: function () {
            return G.barres(['Chiffre d’affaires', 'Charges variables', 'Charges fixes',
              'Seuil de rentabilité'],
            [{ label: 'Montant', data: [r.ca, r.variable, r.fixe, r.seuil || 0],
              color: G.TONES.navy }], { horizontal: true, height: 240 });
          },
        }]));

        var droits = K.droits('M12');
        vue.appendChild(U.card('Nature des charges — proposition corrigeable', U.dataTable({
          rows: r.comptes, exportName: 'nature-charges', pageSize: 20, searchable: true,
          filters: [{ name: 'nature', label: 'Nature',
            options: [{ value: 'fixe', label: 'Fixe' }, { value: 'variable', label: 'Variable' }] }],
          columns: [
            { key: 'compte', label: 'Compte', nowrap: true,
              render: function (x) { return el('span.font-mono.text-xs', { text: x.compte }); } },
            { key: 'libelle', label: 'Intitulé' },
            { key: 'nature', label: 'Nature retenue',
              render: function (x) {
                return x.nature === 'variable'
                  ? U.badge('Variable — suit l’activité', 'info')
                  : U.badge('Fixe — tombe de toute façon', 'warning');
              } },
            { key: 'montant', label: 'Montant', align: 'right',
              text: function (x) { return C.money(x.montant, false); },
              render: function (x) { return el('span.font-semibold', { text: C.money(x.montant, false) }); } },
          ],
          rowActions: function (x) {
            if (!droits.editer) return [];
            return [K.iconBtn('repeat', 'Basculer en ' + (x.nature === 'variable' ? 'fixe' : 'variable'),
              function () {
                corrigerNature(x.compte, x.nature === 'variable' ? 'fixe' : 'variable');
                afficher();
                U.toast('Nature corrigée.', { type: 'success',
                  detail: x.compte + ' — ' + (x.nature === 'variable' ? 'désormais fixe' : 'désormais variable')
                    + '. Le seuil est recalculé.' });
              })];
          },
        })));

        if (!droits.editer) {
          vue.appendChild(K.note('Votre profil consulte l’analyse sans corriger la nature des charges. '
            + 'La matrice des droits (M14) décide de cette ouverture.', { tone: 'neutral', icon: 'lock' }));
        }
      }

      function imprimer() {
        var r = calcul();
        P.etat({
          titre: 'Seuil de rentabilité',
          sousTitre: C.libellePeriode(r.b),
          cartouche: [
            ['Période', C.libellePeriode(r.b)],
            ['Chiffre d’affaires', C.money(r.ca)],
            ['Charges variables', C.money(r.variable)],
            ['Charges fixes', C.money(r.fixe)],
            ['Marge sur coût variable', C.money(r.marge)],
            ['Taux de marge', C.pct(r.taux * 100)],
            ['Seuil de rentabilité', r.seuil != null ? C.money(r.seuil) : 'incalculable'],
            ['Point mort', r.pointMort ? C.dateFR(r.pointMort) : 'non atteint sur la période'],
          ],
          contenu: el('div.space-y-3', null, [
            el('p.font-semibold', { text: 'Méthode' }),
            el('p', { text: 'Marge sur coût variable = chiffre d’affaires − charges variables. '
              + 'Seuil de rentabilité = charges fixes ÷ taux de marge. Marge de sécurité = chiffre '
              + 'd’affaires − seuil : c’est ce que la clinique peut perdre avant de perdre de l’argent.' }),
            el('p.mt-2.font-semibold', { text: 'Réserve' }),
            el('p', { text: 'La répartition fixe / variable est une proposition de gestion, non une '
              + 'donnée du plan comptable. Le seuil suppose en outre la structure constante : il vaut '
              + 'pour un niveau d’activité voisin de l’actuel.' }),
            el('p.mt-3.font-semibold', { text: 'Détail des charges' }),
            P.tableau([
              { label: 'Compte', value: function (x) { return x.compte; } },
              { label: 'Intitulé', value: function (x) { return x.libelle; } },
              { label: 'Nature', value: function (x) { return x.nature === 'variable' ? 'Variable' : 'Fixe'; } },
              { label: 'Montant', align: 'right',
                value: function (x) { return C.money(x.montant, false); },
                somme: function (x) { return x.montant; } },
            ], r.comptes, { total: true }),
          ]),
          signatures: [{ role: 'Le Comptable' },
            { role: 'La Direction', nom: 'SOKOU Peace' }],
        });
      }
    },
  });

  /* ==========================================================================
   * ACOMPTE SUR IMPÔT ASSIS SUR LES BÉNÉFICES (AIB)
   * --------------------------------------------------------------------------
   * La clinique est COLLECTEUR : elle retient l'AIB sur ce qu'elle paie à ses
   * fournisseurs et prestataires, et le reverse à l'État le 10 du mois suivant.
   * L'écran tient les deux temps du geste :
   *
   *   1. « À retenir » — les factures fournisseurs réglées dont la retenue
   *      n'est pas encore enregistrée. Le taux est CALCULÉ depuis le statut de
   *      l'IFU du tiers ; quand il ne peut pas l'être, la commande est
   *      VERROUILLÉE et dit pourquoi — une retenue qu'on ne sait pas expliquer
   *      au fournisseur est une retenue qu'on ne fait pas.
   *   2. « Registre » — ce qui a été retenu, et l'annexe mensuelle imprimable,
   *      dans la forme du journal réel de la clinique (N° IFU, tiers,
   *      adresse/téléphone, montant, taux, montant AIB).
   *
   * L'AIB SUBI par la clinique sur ses propres factures est une CRÉANCE (4492)
   * et se suit à part : le confondre avec la dette (4478) ferait d'un acompte
   * versé un impôt collecté.
   * ======================================================================== */
  function colAIB() {
    return S.collection('retenuesAIB', { module: 'M12', entite: 'retenue d’AIB', prefix: 'AIB' });
  }
  /* Le tiers se lit dans le MAGASIN et non dans la semence : le statut de son
     IFU est une donnée que la clinique VÉRIFIE et SAISIT — elle ne se devine
     pas, et elle doit survivre au rechargement. */
  function fournisseurDe(nom) {
    return S.collection('fournisseurs').active().filter(function (f) {
      return f.nom === nom || f.code === nom;
    })[0] || null;
  }

  global.SIGH.screen('m12-aib', {
    title: 'Acompte sur impôt (AIB)',
    description: 'Retenues d’AIB sur les fournisseurs et prestataires, annexe mensuelle et reversement à l’État.',
    regle: 'L’AIB est un <strong>acompte prélevé à la source</strong> : ce que la clinique RETIENT est une '
      + '<strong>dette envers l’État</strong> (compte ' + D.PARAM_AIB.comptes.retenu + '), reversée le 10 du '
      + 'mois suivant ; ce qu’elle SUBIT sur ses propres factures est une <strong>créance</strong> (compte '
      + D.PARAM_AIB.comptes.subi + '), imputée sur l’impôt sur les bénéfices. Le taux se déduit du '
      + '<strong>statut de l’IFU</strong> du tiers : sans ce statut, aucune retenue ne s’enregistre.',
    render: function (root) {
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      afficher();
      return null;

      function afficher() {
        C.clear(vue);
        var G = D.PARAM_AIB.generalisation;
        var retenues = colAIB().active();
        var enregistrees = {};
        retenues.forEach(function (r) { if (r.factureRef) enregistrees[r.factureRef] = true; });

        /* Les factures fournisseurs réglées : c'est sur le RÈGLEMENT que la
           retenue se pratique, pas sur la réception.
           LA FILE EST AMORCÉE PAR L'ÉCRAN M7 qui la porte : sur un poste qui
           ne l'a pas ouvert, elle est VIDE — et « 0 règlement à traiter »
           serait un zéro faux, pire qu'une absence. On l'annonce. */
        var amorcee = S.collection('facturesFournisseurs').all().length > 0;
        var factures = !amorcee ? [] : S.collection('facturesFournisseurs').active().filter(function (fa) {
          return fa.statutPaiement === 'payee' && !enregistrees[fa.reference];
        });

        vue.appendChild(K.note('<strong>' + C.escapeHtml(G.texte) + '</strong><br>'
          + '<em>Source : ' + C.escapeHtml(G.source) + '</em>',
        { tone: 'warning', icon: 'percent' }));

        var totalRetenu = C.sum(retenues, 'montantAIB');
        var au5 = retenues.filter(function (r) { return r.generalise; });
        vue.appendChild(U.kpiGrid([
          { label: 'AIB retenu (registre)', value: C.money(totalRetenu), icon: 'percent', tone: 'navy',
            hint: 'dette envers l’État — compte ' + D.PARAM_AIB.comptes.retenu },
          { label: 'Tiers concernés', value: C.num(Object.keys(C.groupBy(retenues, 'tiers')).length),
            icon: 'building-2', tone: 'info' },
          { label: 'Au taux généralisé de 5 %', value: C.num(au5.length), icon: 'alert-triangle',
            tone: au5.length ? 'warning' : 'neutral', hint: 'IFU désactivé ou absent du fichier actif' },
          { label: 'Règlements à traiter', value: amorcee ? C.num(factures.length) : '—', icon: 'file-clock',
            tone: !amorcee ? 'neutral' : (factures.length ? 'warning' : 'success'),
            hint: amorcee ? 'factures réglées, retenue non enregistrée'
              : 'file non amorcée — ouvrir « Factures fournisseurs »' },
        ]));

        /* --- 1. À retenir ------------------------------------------------- */
        var lignes = factures.map(function (fa) {
          var f = fournisseurDe(fa.fournisseurNom);
          var statut = (f && f.ifuStatut) || 'inconnu';
          var t = D.tauxAIB(statut, fa.date);
          return { facture: fa, fournisseur: f, statut: statut, taux: t };
        });

        var corps = el('div.space-y-2');
        if (!amorcee) {
          corps.appendChild(K.note('Le registre des <strong>factures fournisseurs</strong> n’a pas encore été '
            + 'ouvert sur ce poste : la file n’est pas amorcée. Annoncer « aucun règlement » ici serait un '
            + 'zéro faux.', { tone: 'info', icon: 'inbox' }));
          corps.appendChild(el('div.mt-2', null,
            K.lien('m7-factures-fournisseurs', 'Ouvrir les factures fournisseurs', { size: 'sm', icon: 'arrow-right' })));
        } else if (!lignes.length) {
          corps.appendChild(K.note('Aucun règlement en attente de retenue.', { tone: 'success', icon: 'check-check' }));
        }
        lignes.slice(0, 12).forEach(function (x) {
          var t = x.taux;
          var montant = x.facture.montantFacture || 0;
          var ligne = el('div.flex.flex-wrap.items-center.gap-3.rounded-lg.border.border-slate-200.px-3.py-2\\.5');
          ligne.appendChild(el('div.min-w-0.flex-1', null, [
            el('p.text-sm.font-medium.text-slate-800', { text: x.facture.fournisseurNom }),
            el('p.text-xs.text-slate-500', {
              text: x.facture.reference + ' · ' + C.dateFR(x.facture.date) + ' · ' + C.money(montant)
                + ' · IFU ' + ((x.fournisseur && x.fournisseur.ifu) || 'non renseigné'),
            }),
            el('p.mt-0\\.5.text-\\[11px\\]', {
              class: t.taux == null ? 'text-warning-700' : 'text-slate-500', text: t.motif,
            }),
          ]));
          ligne.appendChild(t.taux == null
            ? U.badge('Taux à déterminer', 'warning')
            : U.badge('AIB ' + t.taux + ' %' + (t.generalise ? ' — généralisé' : ''), t.generalise ? 'warning' : 'navy'));
          /* Une retenue dont le taux n'est pas déterminé ne s'enregistre pas :
             la commande est ABSENTE, et le motif ci-dessus dit pourquoi. */
          if (t.taux != null) {
            ligne.appendChild(K.commande('Enregistrer la retenue', {
              size: 'sm', variant: 'primary', icon: 'save',
              onclick: function () { enregistrer(x, montant); },
            }));
          } else if (x.fournisseur) {
            /* Le statut de l'IFU se CONSTATE auprès de la DGI, puis se saisit :
               c'est lui qui débloque le taux, jamais une valeur par défaut. */
            ligne.appendChild(K.commande('Statut de l’IFU', {
              size: 'sm', icon: 'badge-check',
              onclick: function () { declarerStatut(x.fournisseur); },
            }));
          }
          corps.appendChild(ligne);
        });
        if (lignes.length > 12) {
          corps.appendChild(el('p.text-xs.text-slate-400', {
            text: 'et ' + (lignes.length - 12) + ' autre(s) règlement(s) — la liste s’écoule au fil des retenues.',
          }));
        }
        vue.appendChild(U.card('À retenir — règlements fournisseurs sans retenue enregistrée', corps));

        /* --- 2. Le registre ----------------------------------------------- */
        var table = U.dataTable({
          rows: retenues, searchable: true, pageSize: 10, exportName: 'retenues-aib',
          columns: [
            { key: 'date', label: 'Date', render: function (r) { return C.dateFR(r.date); } },
            { key: 'ifu', label: 'N° IFU', render: function (r) { return el('span.font-mono.text-xs', { text: r.ifu || '—' }); } },
            { key: 'tiers', label: 'Fournisseur ou prestataire' },
            { key: 'contact', label: 'Adresse / Tél.' },
            { key: 'montant', label: 'Montant', align: 'right', text: function (r) { return C.money(r.montant, false); } },
            { key: 'taux', label: 'Taux', align: 'right',
              render: function (r) { return U.badge(r.taux + ' %', r.generalise ? 'warning' : 'neutral'); } },
            { key: 'montantAIB', label: 'Montant AIB', align: 'right',
              render: function (r) { return el('span.font-semibold', { text: C.money(r.montantAIB, false) }); } },
          ],
          actions: [K.btn('Éditer l’annexe AIB', { icon: 'printer', onclick: annexe })],
        });
        vue.appendChild(U.card('Registre des retenues', table));

        /* --- 3. Le barème ------------------------------------------------- */
        vue.appendChild(U.card('Barème de l’AIB — le champ d’application de chaque taux',
          el('div.space-y-3', null, [
            K.note('Le barème est une <strong>donnée</strong>, pas du code : une règle <strong>arrêtée</strong> '
              + 's’applique aussitôt, une règle en attente ne s’applique pas. C’est ce qui permet de tenir la '
              + 'généralisation du 5 % — la seule règle écrite — sans inventer le champ des deux autres.',
            { tone: 'info', icon: 'scale' }),
            K.miniTable([
              { label: 'Taux', align: 'right',
                render: function (r) { return U.badge(r.taux + ' %', r.arrete ? 'success' : 'warning'); } },
              { label: 'S’applique à', render: function (r) {
                return r.condition || el('span.text-xs.italic.text-warning-700', {
                  text: r.conditionProposee ? 'Proposition : ' + r.conditionProposee : 'À arrêter par la Direction',
                });
              } },
              { label: 'Statut de l’IFU visé',
                render: function (r) { return (r.statutsIfu || []).map(function (s) {
                  var d = (D.PARAM_AIB.statutsIfu || []).filter(function (x) { return x.id === s; })[0];
                  return d ? d.label : s;
                }).join(' · '); } },
              { label: 'Effet', render: function (r) { return r.dateEffet ? C.dateFR(r.dateEffet) : '—'; } },
              { label: 'État', render: function (r) {
                return r.arrete ? U.badge('Arrêtée', 'success') : U.badge('En attente', 'warning');
              } },
              { label: 'Source', render: function (r) {
                return el('span.text-xs.text-slate-500', { text: r.source || '—' });
              } },
              { label: '', render: function (r) {
                if (r.arrete) return el('span.text-xs.text-slate-400', { text: 'Décidée' });
                return K.commande('Arrêter la règle', {
                  size: 'sm', icon: 'gavel', onclick: function () { arreter(r); },
                });
              } },
            ], D.baremeAIB()),
          ])));

        vue.appendChild(K.note('L’AIB que la clinique <strong>subit</strong> sur ses propres factures est une '
          + '<strong>créance</strong> sur l’État (compte ' + D.PARAM_AIB.comptes.subi + ') : elle s’impute sur '
          + 'l’impôt sur les bénéfices (' + D.PARAM_AIB.comptes.imputation + '), elle ne se confond pas avec la '
          + 'dette du collecteur. ' + C.escapeHtml(D.PARAM_AIB.noteTauxParDefaut),
        { tone: 'info', icon: 'scale' }));
        vue.appendChild(K.source('Registre du magasin — échéance de reversement : ' + D.PARAM_AIB.echeance));
        U.icons(vue);
      }

      /* ARRÊTER UNE RÈGLE DU BARÈME est un geste de la Direction : elle écrit
         la condition, la date d'effet et la source, et la règle s'applique à
         la retenue suivante. Tant qu'elle ne l'a pas fait, le moteur refuse —
         il ne choisit pas un taux à sa place. */
      function arreter(regle) {
        var form = U.form([
          { name: 'condition', label: 'À qui ce taux s’applique-t-il ?', type: 'textarea', rows: 2,
            required: true, col: 'full', value: regle.conditionProposee || '',
            help: 'La condition telle qu’elle pourra être opposée au tiers comme à l’administration.' },
          { name: 'dateEffet', label: 'Date d’effet', type: 'date',
            help: 'Laisser vide si la règle vaut dès son adoption.' },
          { name: 'source', label: 'Fondement', required: true, col: 'full', value: regle.source || '',
            help: 'Texte, note ou décision sur laquelle la règle repose.' },
        ], {});
        var m = U.modal({
          title: 'Arrêter la règle — AIB ' + regle.taux + ' %', size: 'md',
          body: el('div.space-y-3', null, [
            K.note('Une fois arrêtée, cette règle <strong>s’appliquera d’elle-même</strong> aux retenues '
              + 'suivantes. Les retenues déjà enregistrées gardent le taux qu’elles portent : le passé ne '
              + 'se réécrit pas.', { tone: 'warning' }),
            regle.motifAttente ? K.note(C.escapeHtml(regle.motifAttente), { tone: 'info' }) : null,
            form,
          ].filter(Boolean)),
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Arrêter la règle', {
              variant: 'primary', icon: 'gavel',
              onclick: function () {
                var v = form.collect();
                if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                var col = S.collection('baremeAIB', { module: 'M12', entite: 'règle d’AIB', prefix: 'BAIB' });
                var maj = col.update(regle.id, {
                  arrete: true, condition: v.condition, dateEffet: v.dateEffet || null,
                  source: v.source, arreteLe: C.iso(new Date()), arretePar: S.currentUser(),
                });
                m.close();
                U.toast('Règle arrêtée — AIB ' + regle.taux + ' %.', {
                  type: 'success', detail: 'Elle s’applique dès la prochaine retenue.',
                  undo: function () { if (maj) maj.undo(); afficher(); },
                });
                afficher();
              },
            }),
          ],
        });
      }

      /* LE STATUT DE L'IFU EST UN CONSTAT, PAS UNE SUPPOSITION. Il se relève
         au fichier de la DGI, se date et porte le nom de qui l'a vérifié :
         c'est ce constat qui autorise — ou non — le taux généralisé. */
      function declarerStatut(f) {
        var form = U.form([
          { name: 'ifu', label: 'Numéro IFU du tiers', value: f.ifu || '',
            help: 'Tel qu’il figure sur ses factures. Laisser vide s’il n’en porte pas.' },
          { name: 'ifuStatut', label: 'Statut au fichier de la DGI', type: 'select', required: true,
            value: f.ifuStatut || 'inconnu',
            options: D.PARAM_AIB.statutsIfu.map(function (s) { return { value: s.id, label: s.label }; }) },
          { name: 'ifuVerifieLe', label: 'Vérifié le', type: 'date', required: true, value: C.iso(new Date()) },
        ], {});
        var m = U.modal({
          title: 'Statut de l’IFU — ' + f.nom, size: 'md',
          body: el('div.space-y-3', null, [
            K.note('Un IFU <strong>désactivé</strong> ou <strong>absent du fichier actif</strong> entraîne '
              + 'le taux généralisé de ' + D.PARAM_AIB.generalisation.taux + ' % depuis le 07/09/2026. '
              + 'Le constat est daté : il pourra être opposé au tiers comme à l’administration.',
            { tone: 'info' }),
            form,
          ]),
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Enregistrer le constat', {
              variant: 'primary', icon: 'save',
              onclick: function () {
                var v = form.collect();
                if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                var maj = S.collection('fournisseurs').update(f.id, {
                  ifu: v.ifu || null, ifuStatut: v.ifuStatut, ifuVerifieLe: v.ifuVerifieLe,
                  ifuVerifiePar: S.currentUser(),
                });
                m.close();
                U.toast('Statut de l’IFU enregistré.', {
                  type: 'success',
                  detail: 'Le taux d’AIB applicable en découle.',
                  undo: function () { maj.undo(); afficher(); },
                });
                afficher();
              },
            }),
          ],
        });
      }

      function enregistrer(x, montant) {
        var t = x.taux;
        var aib = Math.round(montant * t.taux / 100);
        var f = x.fournisseur || {};
        U.confirm({
          title: 'Enregistrer une retenue d’AIB de ' + C.money(aib) + ' ?',
          message: 'Tiers : <strong>' + C.escapeHtml(x.facture.fournisseurNom) + '</strong><br>'
            + 'Montant de la facture : ' + C.money(montant) + '<br>'
            + 'Taux appliqué : <strong>' + t.taux + ' %</strong> — ' + C.escapeHtml(t.motif) + '<br><br>'
            + 'La retenue diminue la dette envers le fournisseur et crée une <strong>dette envers '
            + 'l’État</strong> (compte ' + D.PARAM_AIB.comptes.retenu + '), reversée à l’échéance du 10.',
          confirmLabel: 'Enregistrer',
        }).then(function (ok) {
          if (!ok) return;
          var piece = 'AIB-' + String(x.facture.reference || '').replace(/[^0-9A-Za-z-]/g, '');
          var r = colAIB().insert({
            date: x.facture.date, factureRef: x.facture.reference,
            tiers: x.facture.fournisseurNom, ifu: f.ifu || null, ifuStatut: t.statut,
            contact: [f.adresse, f.tel].filter(Boolean).join(' · ') || '—',
            montant: montant, taux: t.taux, montantAIB: aib,
            generalise: !!t.generalise, motif: t.motif, piece: piece,
          });
          /* L'écriture naît en BROUILLON et ÉQUILIBRÉE (RG-10) : la retenue
             solde une partie de la dette fournisseur au profit de l'État. */
          var ecr = S.collection('ecritures');
          var e1 = ecr.insert({
            numero: piece, date: x.facture.date, journal: 'OD', journalLibelle: 'Opérations diverses',
            compte: D.COMPTES_SIGH.fournisseurs, compteLibelle: D.libelleCompte(D.COMPTES_SIGH.fournisseurs),
            libelle: 'AIB retenu — ' + x.facture.fournisseurNom, debit: aib, credit: 0,
            origine: 'Automatique — AIB', statut: 'brouillon',
          });
          var e2 = ecr.insert({
            numero: piece, date: x.facture.date, journal: 'OD', journalLibelle: 'Opérations diverses',
            compte: D.COMPTES_SIGH.etatRetenuesSource, compteLibelle: D.libelleCompte(D.COMPTES_SIGH.etatRetenuesSource),
            libelle: 'AIB retenu — ' + x.facture.fournisseurNom, debit: 0, credit: aib,
            origine: 'Automatique — AIB', statut: 'brouillon',
          });
          U.toast('Retenue enregistrée — ' + C.money(aib) + '.', {
            type: 'success',
            detail: 'Écriture en brouillon : ' + D.COMPTES_SIGH.fournisseurs + ' au débit, '
              + D.COMPTES_SIGH.etatRetenuesSource + ' au crédit.',
            undo: function () { r.undo(); e1.undo(); e2.undo(); afficher(); },
          });
          afficher();
        });
      }

      function annexe() {
        var retenues = colAIB().active();
        if (!retenues.length) { U.toast('Le registre est vide.', { type: 'warning' }); return; }
        P.etat({
          titre: 'Annexe AIB',
          sousTitre: 'Acompte sur impôt assis sur les bénéfices — retenues à la source',
          cartouche: [
            ['Retenues', C.num(retenues.length)],
            ['Total retenu', C.money(C.sum(retenues, 'montantAIB'))],
            ['Compte', D.PARAM_AIB.comptes.retenu + ' — ' + (D.libelleCompte(D.PARAM_AIB.comptes.retenu) || '')],
            ['Échéance', D.PARAM_AIB.echeance],
          ],
          contenu: P.tableau([
            { label: 'N° IFU', value: function (r) { return r.ifu || '—'; } },
            { label: 'Nom du fournisseur ou prestataire', value: function (r) { return r.tiers; } },
            { label: 'Adresse / Tél.', value: function (r) { return r.contact; } },
            { label: 'Montant', align: 'right',
              value: function (r) { return C.money(r.montant, false); },
              somme: function (r) { return r.montant; } },
            { label: 'Taux', align: 'right', value: function (r) { return r.taux + ' %'; } },
            { label: 'Montant AIB', align: 'right',
              value: function (r) { return C.money(r.montantAIB, false); },
              somme: function (r) { return r.montantAIB; } },
          ], retenues, { total: true }),
          signatures: [{ role: 'Le Comptable' }, { role: 'La Direction' }],
        });
      }
    },
  });

})(window);
