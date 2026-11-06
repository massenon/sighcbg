/* =============================================================================
 * M7 — Achats & Fournisseurs
 * -----------------------------------------------------------------------------
 * CDCT §10.1 — cycle complet : quantification → validation par la Direction
 * Administrative → commande → réception → vérification par 2 à 3 personnes →
 * approvisionnement → enregistrement au stock gros.
 * Le bon d'expression de besoins distingue la QUANTITÉ DEMANDÉE de la
 * QUANTITÉ ACCORDÉE, conformément au processus réel de la clinique.
 * RG-04 — toute commande de stock gros est validée par la DA avant transmission.
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core, U = global.SIGH.ui, S = global.SIGH.store, D = global.SIGH.data,
      P = global.SIGH.print, G = global.SIGH.charts, K = global.SIGH.kit;
  var el = C.el;
  var AUJ = new Date(2026, 7, 16);

  /* Les besoins du LABORATOIRE et des services passent par M7 (Instructions.txt,
     02/09/2026) — le laboratoire clinique est fermé, pas ses expressions de
     besoins. La liste reflète les services BAGUIDI. */
  var SERVICES_DEMANDEURS = ['Laboratoire', 'Pharmacie', 'Médecine du travail', 'Médecine générale',
    'Soins infirmiers', 'Administration', 'Entretien'];

  /* Étapes du workflow d'expression de besoins (draf1 §11). */
  var ETAPES_BESOIN = [
    { id: 'brouillon', label: 'Brouillon', tone: 'neutral' },
    { id: 'soumis', label: 'Soumis', tone: 'info' },
    { id: 'controle_stock', label: 'Contrôle stock', tone: 'info' },
    { id: 'validation_da', label: 'Validation DA', tone: 'warning' },
    { id: 'accorde', label: 'Quantité accordée', tone: 'navy' },
    { id: 'prepare', label: 'Préparation', tone: 'navy' },
    { id: 'livre', label: 'Livré', tone: 'success' },
    { id: 'cloture', label: 'Clôturé', tone: 'neutral' },
  ];
  function etapeLabel(id) {
    var e = ETAPES_BESOIN.filter(function (x) { return x.id === id; })[0];
    return e ? e.label : id;
  }
  function etapeTone(id) {
    var e = ETAPES_BESOIN.filter(function (x) { return x.id === id; })[0];
    return e ? e.tone : 'neutral';
  }

  function produits() { return S.collection('produits').active(); }
  function fournisseurs() { return S.collection('fournisseurs').active(); }
  function optionsProduits() {
    return C.sortBy(produits(), 'designation').map(function (p) {
      return { value: p.id, label: p.designation + ' (' + p.unite + ')' };
    });
  }
  function optionsFournisseurs() {
    return fournisseurs().map(function (f) { return { value: f.code, label: f.nom }; });
  }

  /* ==========================================================================
   * AMORÇAGE
   * ======================================================================== */
  function amorcer() {
    var besoins = S.collection('besoins', { module: 'M7', entite: 'BonExpressionBesoin' });
    if (besoins.all().length) return;
    var rnd = C.seeded(911);
    var prods = produits();
    var cmds = S.collection('commandes', { module: 'M7', entite: 'BonCommande' });
    var livs = S.collection('livraisons', { module: 'M7', entite: 'BonLivraison' });

    for (var i = 0; i < 40; i++) {
      var etape = C.pick(rnd, ETAPES_BESOIN).id;
      var nb = C.between(rnd, 1, 5);
      var lignes = [];
      for (var k = 0; k < nb; k++) {
        var p = C.pick(rnd, prods);
        var dem = C.between(rnd, 5, 120);
        var acc = ['brouillon', 'soumis', 'controle_stock', 'validation_da'].indexOf(etape) !== -1
          ? null : Math.round(dem * (0.6 + rnd() * 0.4));
        lignes.push({
          produitId: p.id, produit: p.designation, unite: p.unite,
          quantiteDemandee: dem, quantiteAccordee: acc,
          quantiteLivree: ['livre', 'cloture'].indexOf(etape) !== -1 ? acc : null,
          prixAchat: p.prixAchat,
        });
      }
      besoins.all().push({
        id: 'BEB' + C.pad(i + 1, 4), statut: 'actif',
        reference: 'BEB-2026-' + C.pad(i + 1, 4),
        date: C.iso(C.addDays(AUJ, -C.between(rnd, 0, 180))),
        service: C.pick(rnd, SERVICES_DEMANDEURS),
        demandeur: C.pick(rnd, ['SANOUSSI Adamon', 'AKONDE Octave', 'IDOHOU Abraham', 'MABOUDOU Nawal']),
        etape: etape,
        motif: C.pick(rnd, ['Réapprovisionnement mensuel', 'Rupture constatée', 'Besoin exceptionnel', 'Dotation de service']),
        lignes: lignes,
        montantEstime: C.sum(lignes, function (l) { return l.quantiteDemandee * l.prixAchat; }),
        valideePar: ['validation_da', 'accorde', 'prepare', 'livre', 'cloture'].indexOf(etape) !== -1 ? 'SOKOU Peace' : null,
      });
    }

    for (var j = 0; j < 30; j++) {
      var f = C.pick(rnd, D.FOURNISSEURS);
      var nbL = C.between(rnd, 2, 7);
      var lignesC = [];
      for (var m = 0; m < nbL; m++) {
        var pc = C.pick(rnd, prods);
        var q = C.between(rnd, 10, 300);
        lignesC.push({ produitId: pc.id, produit: pc.designation, unite: pc.unite, quantite: q, prixUnitaire: pc.prixAchat, montant: q * pc.prixAchat });
      }
      var statutC = C.pick(rnd, ['brouillon', 'attente_validation', 'validee', 'validee', 'transmise', 'livree', 'soldee']);
      cmds.all().push({
        id: 'BC' + C.pad(j + 1, 4), statut: 'actif',
        reference: 'BC-2026-' + C.pad(j + 1, 4),
        date: C.iso(C.addDays(AUJ, -C.between(rnd, 0, 200))),
        fournisseur: f.code, fournisseurNom: f.nom,
        lignes: lignesC, montant: C.sum(lignesC, 'montant'),
        statutCommande: statutC,
        valideePar: ['validee', 'transmise', 'livree', 'soldee'].indexOf(statutC) !== -1 ? 'SOKOU Peace' : null,
        dateValidation: ['validee', 'transmise', 'livree', 'soldee'].indexOf(statutC) !== -1 ? C.iso(C.addDays(AUJ, -C.between(rnd, 0, 190))) : null,
        delaiLivraison: f.delai,
      });

      if (['livree', 'soldee'].indexOf(statutC) !== -1) {
        var ecart = rnd() > 0.75;
        livs.all().push({
          id: 'BL' + C.pad(j + 1, 4), statut: 'actif',
          reference: '26LNA' + C.pad(C.between(rnd, 1, 99999), 5),
          commandeRef: 'BC-2026-' + C.pad(j + 1, 4),
          date: C.iso(C.addDays(AUJ, -C.between(rnd, 0, 180))),
          fournisseur: f.code, fournisseurNom: f.nom,
          lignes: lignesC.map(function (l) {
            var livree = ecart && rnd() > 0.6 ? Math.max(0, l.quantite - C.between(rnd, 1, 20)) : l.quantite;
            return Object.assign({}, l, { quantiteLivree: livree, ecart: livree - l.quantite });
          }),
          montant: C.sum(lignesC, 'montant'),
          controlePar: ['SANOUSSI Adamon', 'SOKOU Peace'],
          statutReception: ecart ? 'ecart' : 'conforme',
        });
      }
    }
    S.save();
  }

  /* ==========================================================================
   * BONS D'EXPRESSION DE BESOINS
   * ======================================================================== */
  global.SIGH.screen('m7-besoins', {
    title: 'Bons d’expression de besoins',
    description: 'Demandes internes des services : désignation, date, secteur demandeur, quantité voulue et quantité accordée.',
    regle: 'Le bon distingue la <strong>quantité demandée</strong> de la <strong>quantité accordée</strong> — distinction propre au processus réel de la clinique. '
      + 'Le circuit est : brouillon → soumis → contrôle stock → validation DA → quantité accordée → préparation → livraison → clôture.',
    render: function (root) {
      amorcer();
      var col = S.collection('besoins', { module: 'M7', entite: 'BonExpressionBesoin' });
      var host = el('div.space-y-4');
      var table;

      host.appendChild(U.kpiGrid([
        { label: 'Bons enregistrés', value: C.num(col.active().length), icon: 'clipboard-list', tone: 'navy' },
        { label: 'En attente de validation DA', value: C.num(col.active().filter(function (b) { return b.etape === 'validation_da' || b.etape === 'soumis' || b.etape === 'controle_stock'; }).length), icon: 'hourglass', tone: 'warning' },
        { label: 'Livrés', value: C.num(col.active().filter(function (b) { return ['livre', 'cloture'].indexOf(b.etape) !== -1; }).length), icon: 'check-circle-2', tone: 'success' },
        { label: 'Montant estimé cumulé', value: C.money(C.sum(col.active(), 'montantEstime')), icon: 'wallet', tone: 'info' },
      ]));

      /* Vue du circuit */
      var circuit = el('div.flex.flex-wrap.items-center.gap-1\\.5');
      ETAPES_BESOIN.forEach(function (e, i) {
        var n = col.active().filter(function (b) { return b.etape === e.id; }).length;
        circuit.appendChild(el('span.inline-flex.items-center.gap-1\\.5.rounded-lg.border.px-2\\.5.py-1\\.5', {
          class: 'border-' + e.tone + '-200 bg-' + e.tone + '-50',
        }, [
          el('span.text-xs.font-medium', { class: 'text-' + e.tone + '-900', text: e.label }),
          el('span.rounded-full.bg-white.px-1\\.5.text-\\[10px\\].font-semibold.num', { class: 'text-' + e.tone + '-700', text: String(n) }),
        ]));
        if (i < ETAPES_BESOIN.length - 1) circuit.appendChild(C.icon('chevron-right', 'h-3.5 w-3.5 text-slate-300'));
      });
      host.appendChild(U.card('Circuit de traitement', circuit));

      table = U.dataTable({
        title: 'Bons d’expression de besoins',
        rows: function () { return col.active(); },
        exportName: 'bons-expression-besoins', pageSize: 12,
        defaultSort: 'date', defaultDir: 'desc',
        filters: [
          { name: 'etape', label: 'Étape', options: ETAPES_BESOIN.map(function (e) { return { value: e.id, label: e.label }; }) },
          { name: 'service', label: 'Service demandeur', options: SERVICES_DEMANDEURS },
        ],
        actions: [K.commande('Nouveau bon', { variant: 'primary', size: 'sm', icon: 'plus', onclick: function () { ouvrir(null); } })],
        columns: [
          { key: 'reference', label: 'N° bon', nowrap: true, render: function (b) { return el('span.font-mono.text-xs.font-semibold', { text: b.reference }); } },
          { key: 'date', label: 'Date', nowrap: true, text: function (b) { return C.dateFR(b.date); }, render: function (b) { return C.dateFR(b.date); } },
          { key: 'service', label: 'Service demandeur' },
          { key: 'demandeur', label: 'Demandeur' },
          { key: 'nbLignes', label: 'Articles', align: 'right', value: function (b) { return (b.lignes || []).length; }, render: function (b) { return String((b.lignes || []).length); } },
          {
            key: 'quantites', label: 'Demandé / Accordé', align: 'right', sortable: false,
            text: function (b) {
              return C.sum(b.lignes || [], 'quantiteDemandee') + ' / ' + C.sum((b.lignes || []).filter(function (l) { return l.quantiteAccordee != null; }), 'quantiteAccordee');
            },
            render: function (b) {
              var dem = C.sum(b.lignes || [], 'quantiteDemandee');
              var acc = C.sum((b.lignes || []).filter(function (l) { return l.quantiteAccordee != null; }), 'quantiteAccordee');
              var complet = acc === dem;
              return el('span.num', null, [
                el('span.font-medium.text-slate-700', { text: C.num(dem) }),
                el('span.text-slate-400', { text: ' / ' }),
                el('span', { class: acc === 0 ? 'text-slate-400' : (complet ? 'font-semibold text-success-600' : 'font-semibold text-warning-600'), text: acc ? C.num(acc) : '—' }),
              ]);
            },
          },
          {
            key: 'montantEstime', label: 'Montant estimé', align: 'right',
            text: function (b) { return C.money(b.montantEstime, false); },
            render: function (b) { return C.money(b.montantEstime, false); },
          },
          { key: 'etape', label: 'Étape', render: function (b) { return U.badge(etapeLabel(b.etape), etapeTone(b.etape)); } },
        ],
        onRowClick: function (b) { consulter(b); },
        rowActions: function (b) {
          return [
            K.iconBtn('eye', 'Consulter', function () { consulter(b); }),
            K.iconBtn('printer', 'Imprimer le bon', function () { etat(b); }),
            K.commandeIcone('pencil', 'Modifier', function () { ouvrir(b); }),
            K.commandeIcone('archive', 'Archiver', function () {
              var res = col.archive(b.id);
              table.refresh();
              U.toast('Bon archivé.', { type: 'success', undo: function () { res.undo(); table.refresh(); } });
            }, { droit: 'annuler', variant: 'ghost' }),
          ];
        },
      });
      host.appendChild(table);
      root.appendChild(host);
      return null;

      function ouvrir(record) {
        var lignes = record ? (record.lignes || []).slice() : [];
        var body = el('div.space-y-4');
        var f = U.form([
          { name: 'date', label: 'Date', type: 'date', required: true },
          { name: 'service', label: 'Service demandeur', type: 'select', required: true, options: SERVICES_DEMANDEURS },
          { name: 'demandeur', label: 'Demandeur', required: true },
          { name: 'etape', label: 'Étape du circuit', type: 'select', required: true, options: ETAPES_BESOIN.map(function (e) { return { value: e.id, label: e.label }; }) },
          { name: 'motif', label: 'Motif de la demande', col: 'full' },
        ], record || { date: C.iso(AUJ), etape: 'brouillon', demandeur: S.currentUser() });
        body.appendChild(f);

        /* Lignes de la demande */
        var ajout = el('div.flex.flex-wrap.items-end.gap-2.rounded-lg.border.border-slate-200.bg-slate-50.p-3');
        var optsBesoin = optionsProduits();
        var selP = U.combo(optsBesoin, {
          value: optsBesoin.length ? optsBesoin[0].value : '',
          searchPlaceholder: 'Désignation ou code article…',
          placeholder: 'Choisir un article',
        });
        var qD = el('input.input.w-24', { type: 'number', min: 1, value: 10 });
        var qA = el('input.input.w-24', { type: 'number', min: 0, placeholder: '—' });
        ajout.appendChild(el('div.min-w-\\[14rem\\].flex-1', null, [el('label.label', { text: 'Article' }), selP]));
        ajout.appendChild(el('div', null, [el('label.label', { text: 'Qté demandée' }), qD]));
        ajout.appendChild(el('div', null, [el('label.label', { text: 'Qté accordée' }), qA]));
        ajout.appendChild(K.btn('Ajouter', {
          variant: 'primary', icon: 'plus',
          onclick: function () {
            var p = produits().filter(function (x) { return x.id === selP.value; })[0];
            var d = Number(qD.value) || 0;
            if (!p || d <= 0) { U.toast('Sélectionner un article et une quantité.', { type: 'error' }); return; }
            var a = qA.value === '' ? null : Number(qA.value);
            if (a != null && a > d) { U.toast('La quantité accordée ne peut excéder la quantité demandée.', { type: 'error' }); return; }
            lignes.push({ produitId: p.id, produit: p.designation, unite: p.unite, quantiteDemandee: d, quantiteAccordee: a, quantiteLivree: null, prixAchat: p.prixAchat });
            qD.value = 10; qA.value = '';
            maj();
          },
        }));
        body.appendChild(ajout);

        var lignesHost = el('div');
        body.appendChild(lignesHost);

        function maj() {
          C.clear(lignesHost);
          if (!lignes.length) { lignesHost.appendChild(U.empty('Aucun article dans la demande.', { icon: 'clipboard-list' })); U.icons(lignesHost); return; }
          var t = el('table.tbl');
          t.appendChild(el('thead', null, el('tr', null, [
            el('th', { text: 'Article' }), el('th.text-right', { text: 'Demandée' }),
            el('th.text-right', { text: 'Accordée' }), el('th.text-right', { text: 'Montant estimé' }), el('th'),
          ])));
          var tb = el('tbody');
          lignes.forEach(function (l, i) {
            tb.appendChild(el('tr', null, [
              el('td', null, el('div', null, [
                el('p.text-sm.text-slate-700', { text: l.produit }),
                el('p.text-xs.text-slate-400', { text: l.unite }),
              ])),
              el('td.text-right.num', { text: C.num(l.quantiteDemandee) }),
              el('td.text-right.num', null, l.quantiteAccordee != null
                ? el('span.font-semibold', { class: l.quantiteAccordee < l.quantiteDemandee ? 'text-warning-600' : 'text-success-600', text: C.num(l.quantiteAccordee) })
                : el('span.text-slate-400', { text: '—' })),
              el('td.text-right.num', { text: C.money(l.quantiteDemandee * l.prixAchat, false) }),
              el('td.text-right', null, K.iconBtn('x', 'Retirer', function () { lignes.splice(i, 1); maj(); }, 'ghost')),
            ]));
          });
          t.appendChild(tb);
          t.appendChild(el('tfoot', null, el('tr', null, [
            el('td.font-semibold', { colspan: 3, text: 'TOTAL ESTIMÉ' }),
            el('td.text-right.num.font-bold.text-navy-900', { text: C.money(C.sum(lignes, function (l) { return l.quantiteDemandee * l.prixAchat; }), false) }),
            el('td'),
          ])));
          lignesHost.appendChild(el('div.overflow-x-auto.rounded-lg.border.border-slate-200', null, t));
          U.icons(lignesHost);
        }
        maj();

        var m = U.modal({
          title: record ? 'Modifier le bon ' + record.reference : 'Nouveau bon d’expression de besoins',
          subtitle: 'La quantité accordée est renseignée après validation de la Direction (RG-04).',
          size: 'xl', body: body,
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn(record ? 'Enregistrer' : 'Créer le bon', {
              variant: 'primary', icon: 'save',
              onclick: function () {
                var v = f.collect();
                if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                if (!lignes.length) { U.toast('Ajouter au moins un article.', { type: 'error' }); return; }
                v.lignes = lignes;
                v.montantEstime = C.sum(lignes, function (l) { return l.quantiteDemandee * l.prixAchat; });
                if (!v.reference) v.reference = C.nextRef('BEB-2026-', 4);
                if (['validation_da', 'accorde', 'prepare', 'livre', 'cloture'].indexOf(v.etape) !== -1 && !v.valideePar) {
                  v.valideePar = 'SOKOU Peace';
                }
                var res = record ? col.update(record.id, v) : col.insert(v);
                m.close(); table.refresh();
                U.toast(record ? 'Bon mis à jour.' : 'Bon créé — ' + res.record.reference, { type: 'success', undo: res.undo });
              },
            }),
          ],
        });
      }

      function consulter(b) {
        var idx = ETAPES_BESOIN.map(function (e) { return e.id; }).indexOf(b.etape);
        U.drawer({
          title: 'Bon ' + b.reference, subtitle: b.service + ' — ' + C.dateFR(b.date), width: 'max-w-3xl',
          body: el('div.space-y-4', null, [
            U.descList([['Référence', b.reference], ['Date', C.dateFR(b.date)],
              ['Service demandeur', b.service], ['Demandeur', b.demandeur],
              ['Motif', b.motif], ['Étape', U.badge(etapeLabel(b.etape), etapeTone(b.etape))],
              ['Validé par', b.valideePar || 'En attente'], ['Montant estimé', C.money(b.montantEstime)]]),
            U.card('Avancement du circuit', U.timeline(ETAPES_BESOIN.map(function (e, i) {
              return {
                title: e.label,
                detail: i === idx ? 'Étape courante' : (i < idx ? 'Franchie' : 'À venir'),
                date: i <= idx ? '✓' : '—',
                tone: i < idx ? 'success' : (i === idx ? 'navy' : 'neutral'),
              };
            }))),
            U.card('Articles demandés', K.miniTable([
              { label: 'Article', key: 'produit' },
              { label: 'Unité', key: 'unite' },
              { label: 'Demandée', align: 'right', key: 'quantiteDemandee' },
              { label: 'Accordée', align: 'right', render: function (l) { return l.quantiteAccordee != null ? String(l.quantiteAccordee) : '—'; } },
              { label: 'Livrée', align: 'right', render: function (l) { return l.quantiteLivree != null ? String(l.quantiteLivree) : '—'; } },
            ], b.lignes || [])),
          ]),
          footer: [
            K.btn('Imprimer', { icon: 'printer', onclick: function () { etat(b); } }),
            K.btn('Modifier', { variant: 'primary', icon: 'pencil', onclick: function () { ouvrir(b); } }),
          ],
        });
      }

      function etat(b) {
        P.etat({
          titre: 'Bon d’expression de besoins',
          sousTitre: b.reference,
          cartouche: [['Référence', b.reference], ['Date', C.dateFR(b.date)],
            ['Service demandeur', b.service], ['Demandeur', b.demandeur],
            ['Motif', b.motif || '—'], ['Étape', etapeLabel(b.etape)]],
          contenu: P.tableau([
            { label: 'Désignation', key: 'produit' },
            { label: 'Unité', key: 'unite' },
            { label: 'Quantité voulue', key: 'quantiteDemandee', align: 'right' },
            { label: 'Quantité accordée', align: 'right', value: function (l) { return l.quantiteAccordee != null ? l.quantiteAccordee : ''; } },
            { label: 'Quantité livrée', align: 'right', value: function (l) { return l.quantiteLivree != null ? l.quantiteLivree : ''; } },
          ], b.lignes || []),
          signatures: [
            { role: 'Le Demandeur', nom: b.demandeur },
            { role: 'Le Gestionnaire de Stock', mention: 'Contrôle de disponibilité' },
            { role: 'La Direction', nom: 'SOKOU Peace', mention: 'Validation (RG-04)' },
          ],
        });
      }
    },
  });

  /* ==========================================================================
   * BONS DE COMMANDE
   * ======================================================================== */
  global.SIGH.screen('m7-commandes', {
    title: 'Bons de commande',
    description: 'Commandes fournisseurs, validation par la Direction et transmission.',
    regle: '<strong>RG-04</strong> — toute commande d’achat de stock gros doit être <strong>validée par la Direction</strong> avant transmission au fournisseur.',
    render: function (root) {
      amorcer();
      var col = S.collection('commandes', { module: 'M7', entite: 'BonCommande' });
      var host = el('div.space-y-4');
      var table;

      var STATUTS_CMD = [
        { value: 'brouillon', label: 'Brouillon' },
        { value: 'attente_validation', label: 'En attente de validation DA' },
        { value: 'validee', label: 'Validée' },
        { value: 'transmise', label: 'Transmise au fournisseur' },
        { value: 'livree', label: 'Livrée' },
        { value: 'soldee', label: 'Soldée' },
      ];
      function toneCmd(s) {
        return { brouillon: 'neutral', attente_validation: 'warning', validee: 'info', transmise: 'navy', livree: 'success', soldee: 'success' }[s] || 'neutral';
      }
      function labelCmd(s) {
        var x = STATUTS_CMD.filter(function (o) { return o.value === s; })[0];
        return x ? x.label : s;
      }

      var enAttente = col.active().filter(function (c) { return c.statutCommande === 'attente_validation'; });
      if (enAttente.length) {
        host.appendChild(K.note('<strong>' + enAttente.length + ' commande(s)</strong> en attente de validation par la Direction. '
          + 'Aucune transmission au fournisseur n’est possible avant cette validation (RG-04).', { tone: 'warning', icon: 'shield-alert' }));
      }

      host.appendChild(U.kpiGrid([
        { label: 'Commandes enregistrées', value: C.num(col.active().length), icon: 'truck', tone: 'navy' },
        { label: 'En attente de validation', value: C.num(enAttente.length), icon: 'hourglass', tone: 'warning' },
        { label: 'Montant commandé', value: C.money(C.sum(col.active(), 'montant')), icon: 'wallet', tone: 'info' },
        { label: 'Livrées', value: C.num(col.active().filter(function (c) { return ['livree', 'soldee'].indexOf(c.statutCommande) !== -1; }).length), icon: 'check-circle-2', tone: 'success' },
      ]));

      table = U.dataTable({
        title: 'Bons de commande',
        rows: function () { return col.active(); },
        exportName: 'bons-commande', pageSize: 12,
        defaultSort: 'date', defaultDir: 'desc',
        filters: [
          { name: 'statutCommande', label: 'Statut', options: STATUTS_CMD },
          { name: 'fournisseur', label: 'Fournisseur', options: optionsFournisseurs() },
        ],
        actions: [K.commande('Nouvelle commande', { variant: 'primary', size: 'sm', icon: 'plus', onclick: function () { ouvrir(null); } })],
        columns: [
          { key: 'reference', label: 'N° commande', nowrap: true, render: function (c) { return el('span.font-mono.text-xs.font-semibold', { text: c.reference }); } },
          { key: 'date', label: 'Date', nowrap: true, text: function (c) { return C.dateFR(c.date); }, render: function (c) { return C.dateFR(c.date); } },
          { key: 'fournisseurNom', label: 'Fournisseur' },
          { key: 'nbLignes', label: 'Articles', align: 'right', value: function (c) { return (c.lignes || []).length; }, render: function (c) { return String((c.lignes || []).length); } },
          {
            key: 'montant', label: 'Montant', align: 'right',
            text: function (c) { return C.money(c.montant, false); },
            render: function (c) { return el('span.font-semibold', { text: C.money(c.montant, false) }); },
          },
          { key: 'delaiLivraison', label: 'Délai', align: 'right', render: function (c) { return (c.delaiLivraison || '—') + ' j'; } },
          { key: 'statutCommande', label: 'Statut', render: function (c) { return U.badge(labelCmd(c.statutCommande), toneCmd(c.statutCommande)); } },
          { key: 'valideePar', label: 'Validée par (RG-04)', render: function (c) { return c.valideePar || el('span.text-xs.text-slate-400', { text: 'En attente' }); } },
        ],
        onRowClick: function (c) { consulter(c); },
        rowActions: function (c) {
          /* C.append attend un NŒUD ; ici on empile dans un tableau. Une
             commande refusée vaut null et ne s'empile pas. */
          function pousser(liste, cmd) { if (cmd) liste.push(cmd); }
          var acts = [K.iconBtn('eye', 'Consulter', function () { consulter(c); })];
          if (c.statutCommande === 'attente_validation') {
            /* LA VALIDATION RG-04 EST L'ACTE DE LA DIRECTRICE
               ADMINISTRATIVE. L'offrir à qui lit les commandes ferait croire
               que la commande peut partir sans elle. */
            pousser(acts, K.commandeIcone('shield-check', 'Valider (Direction)', function () { valider(c); }, 'ghost'));
          }
          acts.push(K.iconBtn('printer', 'Imprimer', function () { etat(c); }));
          pousser(acts, K.commandeIcone('pencil', 'Modifier', function () { ouvrir(c); }));
          return acts;
        },
      });
      host.appendChild(table);
      root.appendChild(host);
      return null;

      function valider(c) {
        U.confirm({
          title: 'Valider la commande ' + c.reference + ' ?',
          message: 'En application de la règle RG-04, cette validation autorise la transmission au fournisseur '
            + c.fournisseurNom + ' pour un montant de ' + C.money(c.montant) + '. L’opération est journalisée.',
          confirmLabel: 'Valider la commande',
        }).then(function (ok) {
          if (!ok) return;
          var res = col.update(c.id, { statutCommande: 'validee', valideePar: 'SOKOU Peace', dateValidation: C.iso(AUJ) });
          table.refresh();
          U.toast('Commande validée par la Direction.', { type: 'success', undo: function () { res.undo(); table.refresh(); } });
        });
      }

      function ouvrir(record) {
        var lignes = record ? (record.lignes || []).slice() : [];
        var body = el('div.space-y-4');
        var f = U.form([
          { name: 'date', label: 'Date de la commande', type: 'date', required: true },
          { name: 'fournisseur', label: 'Fournisseur', type: 'select', required: true, options: optionsFournisseurs() },
          { name: 'statutCommande', label: 'Statut', type: 'select', required: true, options: STATUTS_CMD },
          { name: 'observations', label: 'Observations', type: 'textarea', rows: 2, col: 'full' },
        ], record || { date: C.iso(AUJ), statutCommande: 'brouillon' });
        body.appendChild(f);

        var ajout = el('div.flex.flex-wrap.items-end.gap-2.rounded-lg.border.border-slate-200.bg-slate-50.p-3');
        var optsCmd = optionsProduits();
        var selP = U.combo(optsCmd, {
          value: optsCmd.length ? optsCmd[0].value : '',
          searchPlaceholder: 'Désignation ou code article…',
          placeholder: 'Choisir un article',
        });
        var qte = el('input.input.w-24', { type: 'number', min: 1, value: 10 });
        var pu = el('input.input.w-28', { type: 'number', min: 0 });
        selP.addEventListener('change', function () {
          var p = produits().filter(function (x) { return x.id === selP.value; })[0];
          if (p) pu.value = p.prixAchat;
        });
        var p0 = produits().filter(function (x) { return x.id === selP.value; })[0];
        if (p0) pu.value = p0.prixAchat;

        ajout.appendChild(el('div.min-w-\\[14rem\\].flex-1', null, [el('label.label', { text: 'Article' }), selP]));
        ajout.appendChild(el('div', null, [el('label.label', { text: 'Quantité' }), qte]));
        ajout.appendChild(el('div', null, [el('label.label', { text: 'Prix unitaire' }), pu]));
        ajout.appendChild(K.btn('Ajouter', {
          variant: 'primary', icon: 'plus',
          onclick: function () {
            var p = produits().filter(function (x) { return x.id === selP.value; })[0];
            var q = Number(qte.value) || 0, prix = Number(pu.value) || 0;
            if (!p || q <= 0) { U.toast('Sélectionner un article et une quantité.', { type: 'error' }); return; }
            lignes.push({ produitId: p.id, produit: p.designation, unite: p.unite, quantite: q, prixUnitaire: prix, montant: q * prix });
            qte.value = 10; maj();
          },
        }));
        body.appendChild(ajout);

        var lignesHost = el('div');
        body.appendChild(lignesHost);
        function maj() {
          C.clear(lignesHost);
          if (!lignes.length) { lignesHost.appendChild(U.empty('Aucun article dans la commande.', { icon: 'truck' })); U.icons(lignesHost); return; }
          var t = el('table.tbl');
          t.appendChild(el('thead', null, el('tr', null, [
            el('th', { text: 'Article' }), el('th.text-right', { text: 'Quantité' }),
            el('th.text-right', { text: 'P.U.' }), el('th.text-right', { text: 'Montant' }), el('th'),
          ])));
          var tb = el('tbody');
          lignes.forEach(function (l, i) {
            tb.appendChild(el('tr', null, [
              el('td', { text: l.produit }),
              el('td.text-right.num', { text: C.num(l.quantite) + ' ' + l.unite }),
              el('td.text-right.num', { text: C.money(l.prixUnitaire, false) }),
              el('td.text-right.num.font-semibold', { text: C.money(l.montant, false) }),
              el('td.text-right', null, K.iconBtn('x', 'Retirer', function () { lignes.splice(i, 1); maj(); }, 'ghost')),
            ]));
          });
          t.appendChild(tb);
          t.appendChild(el('tfoot', null, el('tr', null, [
            el('td.font-semibold', { colspan: 3, text: 'TOTAL' }),
            el('td.text-right.num.font-bold.text-navy-900', { text: C.money(C.sum(lignes, 'montant'), false) }),
            el('td'),
          ])));
          lignesHost.appendChild(el('div.overflow-x-auto.rounded-lg.border.border-slate-200', null, t));
          U.icons(lignesHost);
        }
        maj();

        var m = U.modal({
          title: record ? 'Modifier la commande ' + record.reference : 'Nouveau bon de commande',
          size: 'xl', body: body,
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn(record ? 'Enregistrer' : 'Créer la commande', {
              variant: 'primary', icon: 'save',
              onclick: function () {
                var v = f.collect();
                if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                if (!lignes.length) { U.toast('Ajouter au moins un article.', { type: 'error' }); return; }
                var four = D.FOURNISSEURS.filter(function (x) { return x.code === v.fournisseur; })[0];
                v.fournisseurNom = four ? four.nom : v.fournisseur;
                v.delaiLivraison = four ? four.delai : null;
                v.lignes = lignes; v.montant = C.sum(lignes, 'montant');
                if (!v.reference) v.reference = C.nextRef('BC-2026-', 4);
                if (['validee', 'transmise', 'livree', 'soldee'].indexOf(v.statutCommande) !== -1 && !v.valideePar) {
                  v.valideePar = 'SOKOU Peace'; v.dateValidation = C.iso(AUJ);
                }
                var res = record ? col.update(record.id, v) : col.insert(v);
                m.close(); table.refresh();
                U.toast(record ? 'Commande mise à jour.' : 'Commande créée — ' + res.record.reference, { type: 'success', undo: res.undo });
              },
            }),
          ],
        });
      }

      function consulter(c) {
        U.drawer({
          title: 'Commande ' + c.reference, subtitle: c.fournisseurNom + ' — ' + C.dateFR(c.date), width: 'max-w-3xl',
          body: el('div.space-y-4', null, [
            U.descList([['Référence', c.reference], ['Date', C.dateFR(c.date)],
              ['Fournisseur', c.fournisseurNom], ['Délai de livraison', (c.delaiLivraison || '—') + ' jours'],
              ['Montant', C.money(c.montant)], ['Statut', U.badge(labelCmd(c.statutCommande), toneCmd(c.statutCommande))],
              ['Validée par (RG-04)', c.valideePar || 'En attente'],
              ['Date de validation', c.dateValidation ? C.dateFR(c.dateValidation) : '—']]),
            c.statutCommande === 'attente_validation'
              ? K.note('Cette commande <strong>ne peut être transmise</strong> au fournisseur tant que la Direction ne l’a pas validée (RG-04).', { tone: 'warning', icon: 'shield-alert' })
              : null,
            U.card('Articles commandés', K.miniTable([
              { label: 'Article', key: 'produit' },
              { label: 'Quantité', align: 'right', render: function (l) { return l.quantite + ' ' + l.unite; } },
              { label: 'P.U.', align: 'right', render: function (l) { return C.money(l.prixUnitaire, false); } },
              { label: 'Montant', align: 'right', render: function (l) { return C.money(l.montant, false); } },
            ], c.lignes || [])),
          ]),
          footer: [
            c.statutCommande === 'attente_validation'
              ? K.commande('Valider (Direction)', { variant: 'success', icon: 'shield-check', onclick: function () { valider(c); } }) : null,
            K.btn('Imprimer', { variant: 'primary', icon: 'printer', onclick: function () { etat(c); } }),
          ].filter(Boolean),
        });
      }

      function etat(c) {
        P.etat({
          titre: 'Bon de commande',
          sousTitre: c.reference,
          cartouche: [['Référence', c.reference], ['Date', C.dateFR(c.date)],
            ['Fournisseur', c.fournisseurNom], ['Délai de livraison', (c.delaiLivraison || '—') + ' jours'],
            ['Statut', labelCmd(c.statutCommande)], ['Validée par', c.valideePar || 'En attente']],
          contenu: P.tableau([
            { label: 'Désignation', key: 'produit' },
            { label: 'Unité', key: 'unite' },
            { label: 'Quantité', key: 'quantite', align: 'right' },
            { label: 'Prix unitaire', align: 'right', value: function (l) { return C.money(l.prixUnitaire, false); } },
            {
              label: 'Montant', align: 'right',
              value: function (l) { return C.money(l.montant, false); },
              /* Le bon de commande engage la clinique : son total doit être
                 celui de ses propres lignes, refait à l’impression. */
              somme: function (l) { return l.montant; },
            },
          ], c.lignes || [], { total: true }),
          signatures: [
            { role: 'Le Gestionnaire de Stock' },
            { role: 'La Direction', nom: 'SOKOU Peace', mention: 'Bon pour commande (RG-04)' },
          ],
        });
      }
    },
  });

  /* ==========================================================================
   * BONS DE LIVRAISON
   * ======================================================================== */
  global.SIGH.screen('m7-livraisons', {
    title: 'Bons de livraison',
    description: 'Bordereaux de livraison fournisseurs, rapprochés des bons de commande correspondants.',
    render: function (root) {
      amorcer();
      var col = S.collection('livraisons', { module: 'M7', entite: 'BonLivraison' });
      var host = el('div.space-y-4');

      host.appendChild(U.kpiGrid([
        { label: 'Bons de livraison', value: C.num(col.active().length), icon: 'package-check', tone: 'navy' },
        { label: 'Réceptions conformes', value: C.num(col.active().filter(function (l) { return l.statutReception === 'conforme'; }).length), icon: 'check-circle-2', tone: 'success' },
        { label: 'Avec écart', value: C.num(col.active().filter(function (l) { return l.statutReception === 'ecart'; }).length), icon: 'triangle-alert', tone: 'danger' },
        { label: 'Valeur livrée', value: C.money(C.sum(col.active(), 'montant')), icon: 'wallet', tone: 'info' },
      ]));

      host.appendChild(U.dataTable({
        title: 'Bons de livraison',
        rows: function () { return col.active(); },
        exportName: 'bons-livraison', pageSize: 12,
        defaultSort: 'date', defaultDir: 'desc',
        filters: [
          { name: 'fournisseur', label: 'Fournisseur', options: optionsFournisseurs() },
          { name: 'statutReception', label: 'Réception', options: [{ value: 'conforme', label: 'Conforme' }, { value: 'ecart', label: 'Avec écart' }] },
        ],
        columns: [
          { key: 'reference', label: 'N° BL', nowrap: true, render: function (l) { return el('span.font-mono.text-xs.font-semibold', { text: l.reference }); } },
          { key: 'commandeRef', label: 'Commande', nowrap: true, render: function (l) { return el('span.font-mono.text-xs.text-slate-500', { text: l.commandeRef }); } },
          { key: 'date', label: 'Date', nowrap: true, text: function (l) { return C.dateFR(l.date); }, render: function (l) { return C.dateFR(l.date); } },
          { key: 'fournisseurNom', label: 'Fournisseur' },
          { key: 'nbLignes', label: 'Articles', align: 'right', value: function (l) { return (l.lignes || []).length; }, render: function (l) { return String((l.lignes || []).length); } },
          {
            key: 'montant', label: 'Montant', align: 'right',
            text: function (l) { return C.money(l.montant, false); },
            render: function (l) { return C.money(l.montant, false); },
          },
          {
            key: 'statutReception', label: 'Réception',
            render: function (l) { return l.statutReception === 'conforme' ? U.badge('Conforme', 'success') : U.badge('Écart constaté', 'danger'); },
          },
        ],
        onRowClick: function (l) {
          U.drawer({
            title: 'Bon de livraison ' + l.reference, subtitle: l.fournisseurNom + ' — ' + C.dateFR(l.date), width: 'max-w-3xl',
            body: el('div.space-y-4', null, [
              U.descList([['N° bordereau', l.reference], ['Commande rattachée', l.commandeRef],
                ['Fournisseur', l.fournisseurNom], ['Date de livraison', C.dateFR(l.date)],
                ['Montant', C.money(l.montant)],
                ['Contrôlé par', (l.controlePar || []).join(', ')],
                ['Réception', l.statutReception === 'conforme' ? U.badge('Conforme', 'success') : U.badge('Écart constaté', 'danger')]]),
              U.card('Articles livrés', K.miniTable([
                { label: 'Article', key: 'produit' },
                { label: 'Commandé', align: 'right', key: 'quantite' },
                { label: 'Livré', align: 'right', key: 'quantiteLivree' },
                {
                  label: 'Écart', align: 'right',
                  render: function (x) {
                    return x.ecart ? el('span.font-semibold.text-danger-600', { text: String(x.ecart) }) : U.badge('OK', 'success');
                  },
                },
                { label: 'Montant', align: 'right', render: function (x) { return C.money(x.montant, false); } },
              ], l.lignes || [])),
            ]),
            footer: [K.btn('Imprimer', { variant: 'primary', icon: 'printer', onclick: function () { etat(l); } })],
          });
        },
        /* Le bordereau se corrige : une date mal saisie, un contrôleur oublié
           ou un écart constaté après coup ne doivent pas obliger à ressaisir. */
        rowActions: function (l) {
          return [K.iconBtn('printer', 'Imprimer', function () { etat(l); })]
            .concat(K.actionsLigne(col, champsLivraison, { entite: 'bon de livraison' })(l));
        },
        actions: [K.creer(col, champsLivraison, {
          titre: 'Nouveau bon de livraison', entite: 'Bon de livraison',
          defauts: function () { return { date: C.iso(AUJ), statutReception: 'conforme' }; },
          transform: function (v) {
            v.reference = C.nextRef('BL-', 5);
            var f = D.FOURNISSEURS.filter(function (x) { return x.code === v.fournisseur; })[0];
            v.fournisseurNom = f ? f.nom : v.fournisseur;
            v.lignes = v.lignes || [];
            v.montant = v.montant || 0;
            v.controlePar = v.controlePar ? [v.controlePar] : [];
            return v;
          },
          apres: function () { global.location.reload(); },
        })],
      }));
      root.appendChild(host);
      return null;

      function champsLivraison() {
        return [
          { name: 'commandeRef', label: 'Commande rattachée', required: true },
          {
            name: 'fournisseur', label: 'Fournisseur', type: 'select', required: true,
            options: optionsFournisseurs(),
          },
          { name: 'date', label: 'Date de livraison', type: 'date', required: true },
          { name: 'montant', label: 'Montant livré (FCFA)', type: 'money', min: 0 },
          {
            name: 'statutReception', label: 'Réception', type: 'select', required: true,
            options: [{ value: 'conforme', label: 'Conforme' }, { value: 'ecart', label: 'Écart constaté' }],
          },
          { name: 'controlePar', label: 'Contrôlé par', col: 'full' },
        ];
      }

      function etat(l) {
        P.etat({
          titre: 'Bon de livraison',
          sousTitre: l.reference + ' — ' + l.fournisseurNom,
          cartouche: [['N° bordereau', l.reference], ['Commande', l.commandeRef],
            ['Fournisseur', l.fournisseurNom], ['Date', C.dateFR(l.date)],
            ['Contrôlé par', (l.controlePar || []).join(', ')],
            ['Réception', l.statutReception === 'conforme' ? 'Conforme' : 'Écart constaté']],
          contenu: P.tableau([
            { label: 'Désignation', key: 'produit' },
            { label: 'Unité', key: 'unite' },
            { label: 'Qté commandée', key: 'quantite', align: 'right' },
            { label: 'Qté livrée', key: 'quantiteLivree', align: 'right' },
            { label: 'Écart', align: 'right', value: function (x) { return x.ecart || 0; } },
            { label: 'Montant', align: 'right', value: function (x) { return C.money(x.montant, false); },
              somme: function (x) { return x.montant || 0; } },
          ], l.lignes || [], { total: true }),
          signatures: [
            { role: 'Le Livreur', mention: 'Fournisseur' },
            { role: 'Le Gestionnaire de Stock' },
            { role: 'Le Contrôleur', mention: 'Vérification contradictoire' },
          ],
        });
      }
    },
  });

  /* ==========================================================================
   * RÉCEPTIONS & CONTRÔLES
   * ======================================================================== */
  global.SIGH.screen('m7-receptions', {
    title: 'Réceptions & contrôles',
    description: 'Réception physique des livraisons, vérification contradictoire par 2 à 3 personnes et entrée en stock gros.',
    regle: 'La vérification est réalisée par <strong>2 à 3 personnes</strong> (processus de la clinique). '
      + 'Après validation, les quantités reçues sont enregistrées au stock gros et le CUMP est recalculé.',
    render: function (root) {
      amorcer();
      var cmds = S.collection('commandes', { module: 'M7', entite: 'BonCommande' });
      var host = el('div.space-y-4');
      var table;

      function aReceptionner() {
        return cmds.active().filter(function (c) { return ['validee', 'transmise'].indexOf(c.statutCommande) !== -1; });
      }

      host.appendChild(U.kpiGrid([
        { label: 'Commandes à réceptionner', value: C.num(aReceptionner().length), icon: 'package-open', tone: 'warning' },
        { label: 'Réceptions réalisées', value: C.num(cmds.active().filter(function (c) { return ['livree', 'soldee'].indexOf(c.statutCommande) !== -1; }).length), icon: 'check-circle-2', tone: 'success' },
        { label: 'Valeur attendue', value: C.money(C.sum(aReceptionner(), 'montant')), icon: 'wallet', tone: 'info' },
        { label: 'Fournisseurs concernés', value: C.num(Object.keys(C.groupBy(aReceptionner(), 'fournisseur')).length), icon: 'truck', tone: 'neutral' },
      ]));

      /* Modèle de référence : la liasse SoBAPS analysée lors du cadrage. */
      var ex = D.PARAM_FISCAL.exemple;
      host.appendChild(U.card('Modèle de référence — liasse SoBAPS du cadrage', el('div.space-y-3', null, [
        K.miniTable([
          { label: 'Étape', key: 'etape' },
          { label: 'Document', render: function (x) { return el('span.font-mono.text-xs.font-semibold', { text: x.num }); } },
          { label: 'Date', key: 'date' },
          { label: 'Montant', align: 'right', key: 'montant' },
        ], [
          { etape: '1. Pro-forma / bon de commande', num: ex.proforma, date: '09/07/2026', montant: C.money(ex.totalTTC, false) },
          { etape: '2. Bordereau de livraison', num: ex.bonLivraison, date: '10/07/2026', montant: C.money(ex.totalTTC, false) },
          { etape: '3. Facture de vente normalisée', num: ex.facture, date: '10/07/2026', montant: C.money(ex.totalTTC, false) },
        ]),
        K.note('Les trois documents portent le <strong>même montant</strong> : c’est ce rapprochement que le système contrôle. '
          + 'La convention de numérotation du fournisseur est <code>' + D.PARAM_FISCAL.numerotation.modele + '</code> — '
          + '<strong>B</strong> pour le bon, <strong>L</strong> pour la livraison, <strong>F</strong> pour la facture.',
          { tone: 'info', icon: 'file-check-2' }),
        K.note('La facture est certifiée <strong>MECeF</strong> : code DGI <code>' + ex.codeMecef + '</code>, '
          + 'total HT ' + C.money(ex.totalHT) + ', AIB 1 % ' + C.money(ex.aib) + ', net à payer ' + C.money(ex.totalTTC) + '. '
          + 'La TVA y est portée à zéro, les produits de santé étant exonérés.', { tone: 'success', icon: 'shield-check' }),
      ])));

      table = U.dataTable({
        title: 'Commandes en attente de réception',
        rows: aReceptionner,
        exportName: 'receptions-attendues', pageSize: 10,
        emptyMessage: 'Aucune commande en attente de réception.',
        columns: [
          { key: 'reference', label: 'N° commande', nowrap: true, render: function (c) { return el('span.font-mono.text-xs.font-semibold', { text: c.reference }); } },
          { key: 'date', label: 'Date', nowrap: true, text: function (c) { return C.dateFR(c.date); }, render: function (c) { return C.dateFR(c.date); } },
          { key: 'fournisseurNom', label: 'Fournisseur' },
          { key: 'nbLignes', label: 'Articles', align: 'right', value: function (c) { return (c.lignes || []).length; }, render: function (c) { return String((c.lignes || []).length); } },
          { key: 'montant', label: 'Montant', align: 'right', text: function (c) { return C.money(c.montant, false); }, render: function (c) { return C.money(c.montant, false); } },
          { key: 'valideePar', label: 'Validée par' },
        ],
        rowActions: function (c) {
          return [K.btn('Réceptionner', { size: 'sm', variant: 'primary', icon: 'package-check', onclick: function () { receptionner(c); } })];
        },
      });
      host.appendChild(table);
      root.appendChild(host);
      return null;

      function receptionner(c) {
        var saisies = {};
        var body = el('div.space-y-4');
        body.appendChild(K.note('Saisir les quantités <strong>réellement reçues</strong>. Tout écart entre la commande et la livraison est signalé et pris en compte lors de la livraison suivante.', { tone: 'info' }));

        var f = U.form([
          { name: 'referenceBL', label: 'N° bordereau de livraison', required: true, placeholder: 'ex. 26LNA00026' },
          { name: 'date', label: 'Date de réception', type: 'date', required: true, value: C.iso(AUJ) },
          { name: 'controleur1', label: 'Contrôleur 1', required: true, value: 'SANOUSSI Adamon' },
          { name: 'controleur2', label: 'Contrôleur 2', required: true, value: 'SOKOU Peace' },
          { name: 'controleur3', label: 'Contrôleur 3 (facultatif)' },
          { name: 'observations', label: 'Observations', type: 'textarea', rows: 2, col: 'full' },
        ], {});
        body.appendChild(f);

        var t = el('table.tbl');
        t.appendChild(el('thead', null, el('tr', null, [
          el('th', { text: 'Article' }), el('th.text-right', { text: 'Commandé' }),
          el('th.text-right', { text: 'Reçu' }), el('th.text-right', { text: 'Écart' }),
        ])));
        var tb = el('tbody');
        (c.lignes || []).forEach(function (l) {
          var tr = el('tr');
          tr.appendChild(el('td', null, el('div', null, [
            el('p.text-sm.text-slate-700', { text: l.produit }),
            el('p.text-xs.text-slate-400', { text: l.unite }),
          ])));
          tr.appendChild(el('td.text-right.num', { text: C.num(l.quantite) }));
          var input = el('input.input.w-24.text-right', { type: 'number', min: 0, value: l.quantite });
          tr.appendChild(el('td.text-right', null, input));
          var ecartCell = el('td.text-right.num', { text: '0' });
          tr.appendChild(ecartCell);
          saisies[l.produitId] = { ligne: l, recu: l.quantite, ecart: 0 };
          input.addEventListener('input', function () {
            var r = Number(input.value) || 0;
            var e = r - l.quantite;
            saisies[l.produitId] = { ligne: l, recu: r, ecart: e };
            ecartCell.textContent = (e > 0 ? '+' : '') + C.num(e);
            ecartCell.className = 'text-right num ' + (e === 0 ? '' : 'font-semibold text-danger-600');
          });
          tb.appendChild(tr);
        });
        t.appendChild(tb);
        body.appendChild(el('div.overflow-x-auto.rounded-lg.border.border-slate-200', null, t));

        var m = U.modal({
          title: 'Réception de la commande ' + c.reference,
          subtitle: c.fournisseurNom + ' — ' + C.money(c.montant),
          size: 'xl', body: body,
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Valider la réception', {
              variant: 'primary', icon: 'package-check',
              onclick: function () {
                var v = f.collect();
                if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                var vals = Object.keys(saisies).map(function (k) { return saisies[k]; });
                var ecarts = vals.filter(function (x) { return x.ecart !== 0; });

                var controleurs = [v.controleur1, v.controleur2, v.controleur3].filter(Boolean);
                var bl = S.collection('livraisons', { module: 'M7', entite: 'BonLivraison' }).insert({
                  reference: v.referenceBL, commandeRef: c.reference, date: v.date,
                  fournisseur: c.fournisseur, fournisseurNom: c.fournisseurNom,
                  lignes: vals.map(function (x) {
                    return Object.assign({}, x.ligne, { quantiteLivree: x.recu, ecart: x.ecart });
                  }),
                  montant: C.sum(vals, function (x) { return x.recu * x.ligne.prixUnitaire; }),
                  controlePar: controleurs,
                  statutReception: ecarts.length ? 'ecart' : 'conforme',
                  observations: v.observations,
                });

                /* Entrée en stock gros et recalcul du CUMP */
                var annulations = [];
                vals.forEach(function (x) {
                  if (x.recu <= 0) return;
                  var p = produits().filter(function (pp) { return pp.id === x.ligne.produitId; })[0];
                  if (!p) return;
                  var avant = { stockGros: p.stockGros, stock: p.stock, cump: p.cump };
                  /* CUMP = (valeur du stock existant + valeur de l'entrée) / quantité totale */
                  var nouvelleQte = p.stock + x.recu;
                  var nouveauCump = nouvelleQte > 0
                    ? Math.round((p.stock * p.cump + x.recu * x.ligne.prixUnitaire) / nouvelleQte)
                    : x.ligne.prixUnitaire;
                  S.collection('produits').update(p.id, {
                    stockGros: p.stockGros + x.recu, stock: nouvelleQte, cump: nouveauCump,
                  });
                  var mv = S.collection('mouvements', { module: 'M6', entite: 'MouvementStock' }).insert({
                    reference: C.nextRef('M', 6), date: v.date,
                    produitId: p.id, produit: p.designation,
                    type: 'entree', typeLabel: 'Entrée', quantite: x.recu, stockType: 'gros',
                    justificatif: 'Bon de livraison ' + v.referenceBL,
                    utilisateur: controleurs[0],
                  });
                  annulations.push(function () { S.collection('produits').update(p.id, avant); mv.undo(); });
                });

                var maj = cmds.update(c.id, { statutCommande: 'livree' });
                m.close(); table.refresh();
                U.toast('Réception enregistrée — ' + (ecarts.length ? ecarts.length + ' écart(s) constaté(s).' : 'livraison conforme.'), {
                  type: ecarts.length ? 'warning' : 'success',
                  detail: 'Stock gros mis à jour, CUMP recalculé.',
                  undo: function () {
                    annulations.forEach(function (u) { u(); });
                    bl.undo(); maj.undo(); table.refresh();
                  },
                });
              },
            }),
          ],
        });
      }
    },
  });

  /* ==========================================================================
   * ÉCARTS DE LIVRAISON
   * ======================================================================== */
  global.SIGH.screen('m7-ecarts', {
    title: 'Écarts de livraison',
    description: 'Suivi des manquants entre commande et livraison, avec prise en compte automatique lors de la livraison suivante.',
    regle: 'Écran en lecture seule. Les écarts sont la <strong>différence entre quantités commandées et reçues</strong> : ils se corrigent en modifiant la réception correspondante.',
    render: function (root) {
      amorcer();
      var livs = S.collection('livraisons').active().filter(function (l) { return l.statutReception === 'ecart'; });
      var rows = [];
      livs.forEach(function (l) {
        (l.lignes || []).forEach(function (x) {
          if (x.ecart && x.ecart !== 0) {
            rows.push({
              id: l.id + '-' + x.produitId,
              bl: l.reference, commande: l.commandeRef, date: l.date,
              fournisseur: l.fournisseurNom, produit: x.produit, unite: x.unite,
              commande_qte: x.quantite, livree: x.quantiteLivree, ecart: x.ecart,
              valeur: Math.abs(x.ecart) * x.prixUnitaire,
              regularise: false,
            });
          }
        });
      });

      var host = el('div.space-y-4');
      host.appendChild(U.kpiGrid([
        { label: 'Écarts constatés', value: C.num(rows.length), icon: 'triangle-alert', tone: 'danger' },
        { label: 'Livraisons concernées', value: C.num(livs.length), icon: 'package-x', tone: 'warning' },
        { label: 'Valeur des manquants', value: C.money(C.sum(rows, 'valeur')), icon: 'wallet', tone: 'danger' },
        { label: 'Fournisseurs concernés', value: C.num(Object.keys(C.groupBy(rows, 'fournisseur')).length), icon: 'truck', tone: 'neutral' },
      ]));

      host.appendChild(K.note('Les manquants sont notifiés au fournisseur et <strong>reportés automatiquement sur la livraison suivante</strong>, conformément au processus de la clinique.', { tone: 'warning', icon: 'repeat' }));

      host.appendChild(U.dataTable({
        title: 'Écarts entre commande et livraison', rows: rows, exportName: 'ecarts-livraison', pageSize: 15,
        emptyMessage: 'Aucun écart de livraison constaté.',
        filters: [{ name: 'fournisseur', label: 'Fournisseur', options: Object.keys(C.groupBy(rows, 'fournisseur')).sort() }],
        columns: [
          { key: 'bl', label: 'N° BL', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.bl }); } },
          { key: 'commande', label: 'Commande', nowrap: true, render: function (r) { return el('span.font-mono.text-xs.text-slate-500', { text: r.commande }); } },
          { key: 'date', label: 'Date', nowrap: true, text: function (r) { return C.dateFR(r.date); }, render: function (r) { return C.dateFR(r.date); } },
          { key: 'fournisseur', label: 'Fournisseur' },
          { key: 'produit', label: 'Article' },
          { key: 'commande_qte', label: 'Commandé', align: 'right' },
          { key: 'livree', label: 'Livré', align: 'right' },
          {
            key: 'ecart', label: 'Écart', align: 'right',
            render: function (r) { return el('span.font-semibold.text-danger-600', { text: String(r.ecart) }); },
          },
          {
            key: 'valeur', label: 'Valeur', align: 'right',
            text: function (r) { return C.money(r.valeur, false); },
            render: function (r) { return C.money(r.valeur, false); },
          },
        ],
        actions: [K.btn('Éditer l’état des manquants', {
          size: 'sm', icon: 'printer',
          onclick: function () {
            P.etat({
              titre: 'État des écarts de livraison',
              sousTitre: 'Manquants à reporter sur les prochaines livraisons',
              cartouche: [['Écarts constatés', C.num(rows.length)],
                ['Valeur totale', C.money(C.sum(rows, 'valeur'))],
                ['Date d’édition', C.dateFR(AUJ)], ['Établi par', S.currentUser()]],
              contenu: P.tableau([
                { label: 'N° BL', key: 'bl' }, { label: 'Fournisseur', key: 'fournisseur' },
                { label: 'Article', key: 'produit' },
                { label: 'Commandé', key: 'commande_qte', align: 'right' },
                { label: 'Livré', key: 'livree', align: 'right' },
                { label: 'Écart', key: 'ecart', align: 'right' },
                { label: 'Valeur', align: 'right', value: function (r) { return C.money(r.valeur, false); },
                  somme: function (r) { return r.valeur || 0; } },
              ], rows, { total: true }),
              signatures: [{ role: 'Le Gestionnaire de Stock' },
                { role: 'La Direction', nom: 'SOKOU Peace' }],
            });
          },
        })],
      }));
      root.appendChild(host);
      return null;
    },
  });

  /* ==========================================================================
   * FOURNISSEURS
   * ======================================================================== */
  global.SIGH.screen('m7-fournisseurs', {
    title: 'Fournisseurs',
    description: 'Référentiel des fournisseurs, habilitation pour les retours de produits périmés et historique des commandes.',
    render: K.crud({
      collection: 'fournisseurs', entite: 'fournisseur', entiteP: 'fournisseurs', module: 'M7',
      defaultSort: 'nom',
      source: 'Facture fournisseur SoBAPS et retours CAME identifiés au cadrage.',
      columns: [
        { key: 'code', label: 'Code', nowrap: true, render: function (f) { return el('span.font-mono.text-xs.font-semibold', { text: f.code }); } },
        { key: 'nom', label: 'Raison sociale' },
        { key: 'type', label: 'Type', render: function (f) { return U.badge(f.type, 'navy'); } },
        { key: 'ville', label: 'Ville' },
        { key: 'tel', label: 'Téléphone', nowrap: true },
        { key: 'delai', label: 'Délai (j)', align: 'right' },
        {
          key: 'habilite', label: 'Retours périmés',
          text: function (f) { return f.habilite ? 'Habilité' : 'Non habilité'; },
          render: function (f) { return f.habilite ? U.badge('Habilité', 'success') : el('span.text-xs.text-slate-400', { text: 'Non habilité' }); },
        },
        {
          key: 'commandes', label: 'Commandes', align: 'right', sortable: false,
          value: function (f) { return S.collection('commandes').active().filter(function (c) { return c.fournisseur === f.code; }).length; },
          render: function (f) { return String(S.collection('commandes').active().filter(function (c) { return c.fournisseur === f.code; }).length); },
        },
      ],
      fields: [
        { name: 'code', label: 'Code fournisseur', required: true },
        { name: 'nom', label: 'Raison sociale', required: true, col: 'full' },
        { name: 'type', label: 'Type', type: 'select', required: true, options: ['Grossiste pharmaceutique', 'Centrale d’achat', 'Réactifs & consommables labo', 'Matériel médical', 'Fournitures & entretien', 'Prestataire de services'] },
        { name: 'ville', label: 'Ville' },
        { name: 'tel', label: 'Téléphone', type: 'tel' },
        { name: 'delai', label: 'Délai de livraison (jours)', type: 'number', min: 0 },
        { name: 'habilite', label: 'Habilité pour les retours de produits périmés', type: 'checkbox', col: 'full' },
      ],
      kpis: function (rows) {
        var cmds = S.collection('commandes').active();
        return [
          { label: 'Fournisseurs référencés', value: C.num(rows.length), icon: 'truck', tone: 'navy' },
          { label: 'Habilités aux retours', value: C.num(rows.filter(function (f) { return f.habilite; }).length), icon: 'shield-check', tone: 'success' },
          { label: 'Volume d’achats', value: C.money(C.sum(cmds, 'montant')), icon: 'wallet', tone: 'info' },
          { label: 'Délai moyen', value: (rows.length ? Math.round(C.sum(rows, 'delai') / rows.length) : 0) + ' j', icon: 'clock', tone: 'neutral' },
        ];
      },
      detail: function (f) {
        var cmds = S.collection('commandes').active().filter(function (c) { return c.fournisseur === f.code; });
        return el('div.space-y-4', null, [
          U.descList([['Code', f.code], ['Raison sociale', f.nom], ['Type', f.type],
            ['Adresse', f.adresse || f.ville], ['Téléphone', f.tel],
            ['IFU', f.ifu ? el('span.font-mono', { text: f.ifu }) : '—'],
            ['Délai de livraison', f.delai + ' jours'],
            ['Code client chez le fournisseur', f.codeClient || '—'],
            ['Domiciliation bancaire', f.banque ? f.banque + ' — compte ' + f.compte + ' (clé ' + f.cleRib + ')' : '—'],
            ['Certifications', f.certification || '—'],
            ['Retours de périmés', f.habilite ? U.badge('Habilité', 'success') : U.badge('Non habilité', 'neutral')],
            ['Provenance', f.source ? el('span.text-xs.text-slate-500', { text: f.source }) : '—']]),
          U.kpiGrid([
            { label: 'Commandes passées', value: C.num(cmds.length), icon: 'truck', tone: 'navy' },
            { label: 'Volume cumulé', value: C.money(C.sum(cmds, 'montant')), icon: 'wallet', tone: 'info' },
          ], 'grid-cols-2'),
          cmds.length ? U.card('Historique des commandes', K.miniTable([
            { label: 'N°', render: function (c) { return el('span.font-mono.text-xs', { text: c.reference }); } },
            { label: 'Date', render: function (c) { return C.dateFR(c.date); } },
            { label: 'Montant', align: 'right', render: function (c) { return C.money(c.montant, false); } },
            { label: 'Statut', render: function (c) { return U.badge(c.statutCommande, 'navy'); } },
          ], C.sortBy(cmds, 'date', 'desc').slice(0, 12))) : U.empty('Aucune commande enregistrée.', { icon: 'truck' }),
        ]);
      },
      etat: function (f) {
        var cmds = S.collection('commandes').active().filter(function (c) { return c.fournisseur === f.code; });
        P.etat({
          titre: 'Fiche fournisseur',
          sousTitre: f.nom,
          cartouche: [['Code', f.code], ['Raison sociale', f.nom], ['Type', f.type],
            ['Ville', f.ville], ['Téléphone', f.tel], ['Délai', f.delai + ' jours']],
          contenu: cmds.length
            ? P.tableau([
              { label: 'N° commande', key: 'reference' },
              { label: 'Date', value: function (c) { return C.dateFR(c.date); } },
              { label: 'Articles', value: function (c) { return (c.lignes || []).length; }, align: 'right' },
              { label: 'Montant', align: 'right', value: function (c) { return C.money(c.montant, false); },
                somme: function (c) { return c.montant || 0; } },
              { label: 'Statut', key: 'statutCommande' },
            ], C.sortBy(cmds, 'date', 'desc'), { total: true })
            : el('p.italic', { text: 'Aucune commande enregistrée auprès de ce fournisseur.' }),
          signatures: [{ role: 'Le Gestionnaire de Stock' }],
        });
      },
    }),
  });

  /* ==========================================================================
   * FACTURES FOURNISSEURS
   * ======================================================================== */
  global.SIGH.screen('m7-factures-fournisseurs', {
    title: 'Factures fournisseurs',
    description: 'Rapprochement facture pro-forma → validation → facture normalisée → bordereau de livraison.',
    regle: 'Le système détecte les incohérences <strong>commande ≠ livraison</strong> et <strong>livraison ≠ facture</strong> et génère une anomalie.',
    render: function (root) {
      amorcer();
      var col = S.collection('facturesFournisseurs', { module: 'M7', entite: 'FactureFournisseur' });
      if (!col.all().length) {
        var rnd = C.seeded(1013);
        S.collection('livraisons').active().forEach(function (l, i) {
          var anomalie = rnd() > 0.75;
          var montantFacture = anomalie ? Math.round(l.montant * (1 + (rnd() - 0.5) * 0.12)) : l.montant;
          col.all().push({
            id: 'FF' + C.pad(i + 1, 4), statut: 'actif',
            reference: 'FF-2026-' + C.pad(i + 1, 4),
            numeroFournisseur: 'FN' + C.between(rnd, 100000, 999999),
            date: l.date, blRef: l.reference, commandeRef: l.commandeRef,
            fournisseur: l.fournisseur, fournisseurNom: l.fournisseurNom,
            montantLivraison: l.montant, montantFacture: montantFacture,
            ecart: montantFacture - l.montant,
            statutRappro: anomalie ? 'anomalie' : 'rapproche',
            statutPaiement: C.pick(rnd, ['impayee', 'payee', 'payee', 'partielle']),
            echeance: C.iso(C.addDays(l.date, 30)),
          });
        });
        S.save();
      }

      var rows = col.active();
      var host = el('div.space-y-4');
      var anomalies = rows.filter(function (r) { return r.statutRappro === 'anomalie'; });

      if (anomalies.length) {
        host.appendChild(K.note('<strong>' + anomalies.length + ' anomalie(s) de rapprochement</strong> détectée(s) : le montant facturé diffère du montant livré. Vérification requise avant règlement.', { tone: 'danger', icon: 'triangle-alert' }));
      }

      host.appendChild(U.kpiGrid([
        { label: 'Factures fournisseurs', value: C.num(rows.length), icon: 'file-text', tone: 'navy' },
        { label: 'Rapprochées', value: C.num(rows.filter(function (r) { return r.statutRappro === 'rapproche'; }).length), icon: 'check-circle-2', tone: 'success' },
        { label: 'Anomalies', value: C.num(anomalies.length), icon: 'triangle-alert', tone: 'danger' },
        { label: 'Impayées', value: C.money(C.sum(rows.filter(function (r) { return r.statutPaiement !== 'payee'; }), 'montantFacture')), icon: 'wallet', tone: 'warning' },
      ]));

      host.appendChild(U.dataTable({
        title: 'Factures fournisseurs', rows: rows, exportName: 'factures-fournisseurs', pageSize: 12,
        rowActions: K.actionsLigne(col, [
          { name: 'numero', label: 'N° de facture', required: true },
          { name: 'date', label: 'Date de facture', type: 'date', required: true },
          { name: 'fournisseur', label: 'Fournisseur', required: true },
          { name: 'montant', label: 'Montant (FCFA)', type: 'number', min: 0 },
          { name: 'echeance', label: 'Échéance', type: 'date' },
          {
            name: 'statutPaiement', label: 'Règlement', type: 'select',
            options: [{ value: 'impayee', label: 'Impayée' }, { value: 'partielle', label: 'Partielle' }, { value: 'soldee', label: 'Soldée' }],
          },
        ]),
        defaultSort: 'date', defaultDir: 'desc',
        filters: [
          { name: 'statutRappro', label: 'Rapprochement', options: [{ value: 'rapproche', label: 'Rapprochée' }, { value: 'anomalie', label: 'Anomalie' }] },
          { name: 'statutPaiement', label: 'Règlement', options: [{ value: 'payee', label: 'Payée' }, { value: 'partielle', label: 'Partielle' }, { value: 'impayee', label: 'Impayée' }] },
          { name: 'fournisseur', label: 'Fournisseur', options: optionsFournisseurs() },
        ],
        columns: [
          { key: 'reference', label: 'N° interne', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.reference }); } },
          { key: 'numeroFournisseur', label: 'N° fournisseur', nowrap: true },
          { key: 'date', label: 'Date', nowrap: true, text: function (r) { return C.dateFR(r.date); }, render: function (r) { return C.dateFR(r.date); } },
          { key: 'fournisseurNom', label: 'Fournisseur' },
          { key: 'blRef', label: 'BL rattaché', nowrap: true, render: function (r) { return el('span.font-mono.text-xs.text-slate-500', { text: r.blRef }); } },
          {
            key: 'montantLivraison', label: 'Montant livré', align: 'right',
            text: function (r) { return C.money(r.montantLivraison, false); },
            render: function (r) { return C.money(r.montantLivraison, false); },
          },
          {
            key: 'montantFacture', label: 'Montant facturé', align: 'right',
            text: function (r) { return C.money(r.montantFacture, false); },
            render: function (r) { return el('span.font-semibold', { text: C.money(r.montantFacture, false) }); },
          },
          {
            key: 'ecart', label: 'Écart', align: 'right',
            text: function (r) { return C.money(r.ecart, false); },
            render: function (r) {
              return r.ecart === 0 ? U.badge('Conforme', 'success')
                : el('span.font-semibold.text-danger-600', { text: (r.ecart > 0 ? '+' : '') + C.money(r.ecart, false) });
            },
          },
          { key: 'echeance', label: 'Échéance', nowrap: true, text: function (r) { return C.dateFR(r.echeance); }, render: function (r) { return C.dateFR(r.echeance); } },
          {
            key: 'statutPaiement', label: 'Règlement',
            render: function (r) {
              var m = { payee: ['Payée', 'success'], partielle: ['Partielle', 'warning'], impayee: ['Impayée', 'danger'] };
              return U.badge(m[r.statutPaiement][0], m[r.statutPaiement][1]);
            },
          },
        ],
        onRowClick: function (r) {
          U.drawer({
            title: 'Facture ' + r.reference, subtitle: r.fournisseurNom + ' — ' + C.dateFR(r.date),
            body: el('div.space-y-4', null, [
              U.descList([['Référence interne', r.reference], ['N° fournisseur', r.numeroFournisseur],
                ['Fournisseur', r.fournisseurNom], ['Date', C.dateFR(r.date)],
                ['Commande', r.commandeRef], ['Bordereau de livraison', r.blRef],
                ['Montant livré', C.money(r.montantLivraison)], ['Montant facturé', C.money(r.montantFacture)],
                ['Écart', r.ecart === 0 ? U.badge('Conforme', 'success') : U.badge(C.money(r.ecart), 'danger')],
                ['Échéance', C.dateFR(r.echeance)]]),
              r.statutRappro === 'anomalie'
                ? K.note('<strong>Anomalie de rapprochement.</strong> Le montant facturé ne correspond pas au montant effectivement livré. '
                  + 'Le règlement doit être suspendu jusqu’à régularisation avec le fournisseur.', { tone: 'danger', icon: 'triangle-alert' })
                : K.note('Rapprochement conforme : commande, livraison et facture concordent.', { tone: 'success', icon: 'check-circle-2' }),
            ]),
          });
        },
      }));
      root.appendChild(host);
      return null;
    },
  });
  /* ==========================================================================
   * PV DE RÉCEPTION — CONSOMMABLES ET RÉACTIFS (phase 5, cible Instructions)
   * --------------------------------------------------------------------------
   * Le procès-verbal CONSTATE la réception : ce qui a été commandé, ce qui est
   * arrivé, l'état des lots, les réserves — et il se SIGNE à trois (magasinier,
   * DAF, représentant du fournisseur). Deux écrans, une mécanique : les
   * réactifs de laboratoire n'appellent pas les mêmes contrôles (chaîne du
   * froid, lots, péremptions courtes) que les consommables de soins.
   * ======================================================================== */
  function colPV() {
    return S.collection('pvReceptions', { module: 'M7', entite: 'PV de réception', prefix: 'PVR' });
  }
  function estReactif(produitId) {
    var pr = produits().filter(function (x) { return x.id === produitId; })[0];
    return !!pr && (pr.categorie === 'reactif' || pr.categorie === 'conso_labo');
  }
  function lignesDeNature(liv, nature) {
    return (liv.lignes || []).filter(function (l) {
      var reactif = estReactif(l.produitId);
      return nature === 'reactifs' ? reactif : !reactif;
    });
  }

  function amorcerPV() {
    var col = colPV();
    if (col.all().length) return;
    var rnd = C.seeded(1517);
    var livs = S.collection('livraisons').active();
    var n = 0;

    function poser(nature, lignes, meta) {
      n++;
      var reserves = lignes.some(function (l) { return (l.ecart || 0) < 0; });
      col.all().push({
        id: 'PVR' + C.pad(n, 4), statut: 'actif',
        reference: 'PV-' + (nature === 'reactifs' ? 'REA' : 'CON') + '-2026-' + C.pad(n, 4),
        nature: nature,
        date: meta.date,
        livraisonRef: meta.reference || null, commandeRef: meta.commandeRef || null,
        fournisseurNom: meta.fournisseurNom,
        lignes: lignes,
        chaineFroid: nature === 'reactifs' ? rnd() > 0.1 : null,
        conclusion: reserves ? 'Conforme avec réserves' : 'Conforme',
        reserves: reserves ? 'Écarts de quantité constatés sur ' + lignes.filter(function (l) { return (l.ecart || 0) < 0; }).length + ' ligne(s).' : '',
        magasinier: 'SANOUSSI Adamon',
        representantFournisseur: 'Livreur ' + (meta.fournisseurNom || ''),
      });
    }

    /* CHAQUE NATURE A SON REGISTRE : on balaie TOUTES les livraisons par
       nature — se limiter aux huit premières laissait le registre des
       réactifs vide quand le tirage du jeu n'y avait mis aucun réactif. */
    ['consommables', 'reactifs'].forEach(function (nature) {
      var pris = 0;
      livs.forEach(function (liv) {
        if (pris >= 4) return;
        var lignes = lignesDeNature(liv, nature);
        if (!lignes.length) return;
        pris++;
        poser(nature, lignes.map(function (l) {
          return { produit: l.produit, unite: l.unite,
            commandee: l.quantite, livree: l.quantiteLivree, ecart: l.ecart || 0 };
        }), liv);
      });
      /* Aucune livraison du jeu ne porte cette nature : le PV de
         démonstration est fabriqué depuis le catalogue — un registre vide
         ferait croire que l'écran ne fonctionne pas. */
      if (!pris) {
        var refs = produits().filter(function (p) {
          var reactif = p.categorie === 'reactif' || p.categorie === 'conso_labo';
          return nature === 'reactifs' ? reactif : !reactif;
        }).slice(0, 5);
        if (refs.length) {
          var f = C.pick(rnd, D.FOURNISSEURS);
          poser(nature, refs.map(function (p) {
            var q = C.between(rnd, 10, 60);
            return { produit: p.designation, unite: p.unite, commandee: q, livree: q, ecart: 0 };
          }), { date: C.iso(C.addDays(AUJ, -C.between(rnd, 3, 40))), fournisseurNom: f.nom });
        }
      }
    });
    S.save();
  }

  function ecranPV(nature, titre, description, regle) {
    return {
      title: titre,
      description: description,
      regle: regle,
      render: function (root) {
        amorcer(); amorcerPV();
        var vue = el('div.space-y-4');
        root.appendChild(vue);
        afficher();
        return null;

        function rows() {
          return colPV().active().filter(function (r) { return r.nature === nature; });
        }

        function afficher() {
          C.clear(vue);
          var r2 = rows();
          var reserves = r2.filter(function (r) { return r.conclusion === 'Conforme avec réserves'; });
          var nonConformes = r2.filter(function (r) { return r.conclusion === 'Non conforme'; });

          vue.appendChild(U.kpiGrid([
            { label: 'PV établis', value: C.num(r2.length), icon: 'clipboard-check', tone: 'navy' },
            { label: 'Conformes', value: C.num(r2.filter(function (r) { return r.conclusion === 'Conforme'; }).length), icon: 'check-circle-2', tone: 'success' },
            { label: 'Avec réserves', value: C.num(reserves.length), icon: 'triangle-alert', tone: reserves.length ? 'warning' : 'neutral' },
            { label: 'Non conformes', value: C.num(nonConformes.length), icon: 'x-circle', tone: nonConformes.length ? 'danger' : 'neutral' },
          ]));

          vue.appendChild(U.dataTable({
            title: 'Registre des procès-verbaux',
            rows: r2, exportName: 'pv-reception-' + nature, pageSize: 12, searchable: true,
            defaultSort: 'date', defaultDir: 'desc',
            emptyMessage: 'Aucun PV établi.',
            emptyHint: 'Un PV se dresse à la réception d\u2019une livraison — bouton « Nouveau PV ».',
            actions: [K.commande('Nouveau PV', {
              variant: 'primary', size: 'sm', icon: 'plus', onclick: nouveau,
            })].filter(Boolean),
            columns: [
              { key: 'reference', label: 'N° PV', nowrap: true, render: function (r) { return el('span.font-mono.text-xs.font-semibold', { text: r.reference }); } },
              { key: 'date', label: 'Date', nowrap: true, text: function (r) { return C.dateFR(r.date); }, render: function (r) { return C.dateFR(r.date); } },
              { key: 'livraisonRef', label: 'Bon de livraison', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.livraisonRef }); } },
              { key: 'fournisseurNom', label: 'Fournisseur' },
              { key: 'lignes', label: 'Lignes', align: 'right', value: function (r) { return (r.lignes || []).length; }, render: function (r) { return String((r.lignes || []).length); } },
              {
                key: 'conclusion', label: 'Conclusion',
                render: function (r) {
                  var ton = r.conclusion === 'Conforme' ? 'success'
                    : (r.conclusion === 'Non conforme' ? 'danger' : 'warning');
                  return U.badge(r.conclusion, ton);
                },
              },
              { key: 'magasinier', label: 'Magasinier' },
            ],
            onRowClick: consulter,
            rowActions: function (r) {
              return [
                K.iconBtn('eye', 'Consulter', function () { consulter(r); }),
                K.iconBtn('printer', 'Imprimer le PV', function () { imprimer(r); }),
              ];
            },
          }));
          U.icons(vue);
        }

        function nouveau() {
          var livs = C.sortBy(S.collection('livraisons').active().filter(function (l) {
            return lignesDeNature(l, nature).length > 0;
          }), 'date', 'desc');
          if (!livs.length) { U.toast('Aucune livraison ne porte de ' + (nature === 'reactifs' ? 'réactifs' : 'consommables') + '.', { type: 'warning' }); return; }

          var f = U.form([
            { name: 'livraisonRef', label: 'Bon de livraison', type: 'select', required: true, col: 'full',
              options: livs.map(function (l) {
                return { value: l.reference, label: l.reference + ' — ' + (l.fournisseurNom || ''),
                  detail: C.dateFR(l.date) + ' · ' + lignesDeNature(l, nature).length + ' ligne(s) concernée(s)' };
              }) },
            { name: 'date', label: 'Date du PV', type: 'date', required: true, value: C.iso(AUJ) },
          ].concat(nature === 'reactifs' ? [
            { name: 'chaineFroid', label: 'Chaîne du froid respectée à l\u2019arrivée', type: 'checkbox',
              help: 'Un réactif arrivé hors température se refuse — le PV en fait foi.' },
          ] : []).concat([
            { name: 'conclusion', label: 'Conclusion du contrôle', type: 'select', required: true,
              options: ['Conforme', 'Conforme avec réserves', 'Non conforme'] },
            { name: 'reserves', label: 'Réserves et observations', type: 'textarea', rows: 3, col: 'full',
              help: 'Obligatoires dès que la conclusion n\u2019est pas « Conforme » : une réserve muette ne protège personne.' },
            { name: 'representantFournisseur', label: 'Représentant du fournisseur (nom)', required: true },
          ]), { conclusion: 'Conforme', chaineFroid: true });

          var m = U.modal({
            title: 'Nouveau PV de réception — ' + (nature === 'reactifs' ? 'réactifs' : 'consommables'),
            size: 'lg', body: f,
            footer: [
              K.btn('Annuler', { onclick: function () { m.close(); } }),
              K.btn('Établir le PV', {
                variant: 'primary', icon: 'clipboard-check',
                onclick: function () {
                  var v = f.collect(); if (!v) return;
                  if (v.conclusion !== 'Conforme' && !(v.reserves || '').trim()) {
                    U.toast('Une conclusion avec réserves ou non conforme EXIGE ses réserves écrites.', { type: 'error' });
                    return;
                  }
                  var liv = livs.filter(function (l) { return l.reference === v.livraisonRef; })[0];
                  var lignes = lignesDeNature(liv, nature);
                  var sess = S.session() || {};
                  var res = colPV().insert({
                    reference: C.nextRef('PV-' + (nature === 'reactifs' ? 'REA' : 'CON') + '-2026-', 4),
                    nature: nature,
                    date: v.date,
                    livraisonRef: liv.reference, commandeRef: liv.commandeRef,
                    fournisseurNom: liv.fournisseurNom,
                    lignes: lignes.map(function (l) {
                      return { produit: l.produit, unite: l.unite,
                        commandee: l.quantite, livree: l.quantiteLivree, ecart: l.ecart || 0 };
                    }),
                    chaineFroid: nature === 'reactifs' ? !!v.chaineFroid : null,
                    conclusion: v.conclusion,
                    reserves: v.reserves || '',
                    magasinier: sess.nomComplet || 'SANOUSSI Adamon',
                    representantFournisseur: v.representantFournisseur,
                  });
                  m.close(); afficher();
                  U.toast('PV ' + res.record.reference + ' établi.', {
                    type: 'success', detail: v.conclusion,
                    undo: function () { res.undo(); afficher(); },
                  });
                  imprimer(res.record);
                },
              }),
            ],
          });
        }

        function consulter(r) {
          U.drawer({
            title: 'PV ' + r.reference,
            subtitle: r.livraisonRef + ' — ' + (r.fournisseurNom || ''),
            body: el('div.space-y-4', null, [
              U.descList([
                ['Référence', r.reference], ['Date', C.dateFR(r.date)],
                ['Bon de livraison', r.livraisonRef], ['Commande', r.commandeRef || '—'],
                ['Fournisseur', r.fournisseurNom || '—'],
                nature === 'reactifs' ? ['Chaîne du froid', r.chaineFroid ? 'Respectée' : 'ROMPUE'] : null,
                ['Conclusion', r.conclusion],
                ['Magasinier', r.magasinier], ['Représentant fournisseur', r.representantFournisseur || '—'],
              ].filter(Boolean)),
              K.section('Lignes contrôlées',
                K.miniTable(['Article', 'Commandée', 'Livrée', 'Écart'],
                  (r.lignes || []).map(function (l) {
                    return [l.produit, String(l.commandee), String(l.livree),
                      (l.ecart || 0) === 0 ? '—' : String(l.ecart)];
                  }))),
              /* Les réserves sont un texte SAISI : elles passent par le canal
                 échappé de K.note (texteEnrichi), jamais concaténées en HTML. */
              r.reserves ? K.note('Réserves : ' + r.reserves, { tone: 'warning', icon: 'triangle-alert' }) : null,
            ].filter(Boolean)),
            footer: [K.btn('Imprimer le PV', { icon: 'printer', onclick: function () { imprimer(r); } })],
          });
        }

        function imprimer(r) {
          P.etat({
            titre: 'PROCÈS-VERBAL DE RÉCEPTION',
            sousTitre: (nature === 'reactifs' ? 'Réactifs et consommables de laboratoire' : 'Consommables') + ' — ' + r.reference,
            cartouche: [['N° PV', r.reference], ['Date', C.dateFR(r.date)],
              ['Bon de livraison', r.livraisonRef], ['Commande', r.commandeRef || '—'],
              ['Fournisseur', r.fournisseurNom || '—'], ['Conclusion', r.conclusion]],
            contenu: el('div.space-y-3', null, [
              P.tableau([
                { label: 'Article', value: function (l) { return l.produit; } },
                { label: 'Unité', value: function (l) { return l.unite || '—'; } },
                { label: 'Qté commandée', align: 'right', value: function (l) { return String(l.commandee); },
                  somme: function (l) { return l.commandee; } },
                { label: 'Qté livrée', align: 'right', value: function (l) { return String(l.livree); },
                  somme: function (l) { return l.livree; } },
                { label: 'Écart', align: 'right', value: function (l) { return (l.ecart || 0) === 0 ? '' : String(l.ecart); } },
              ], r.lignes || []),
              nature === 'reactifs' ? el('p.text-\[10px\]', { text: 'Chaîne du froid à l\u2019arrivée : '
                + (r.chaineFroid ? 'respectée.' : 'ROMPUE — réserve majeure.') }) : null,
              r.reserves ? el('p.text-\[10px\]', { text: 'Réserves : ' + r.reserves }) : null,
              el('p.mt-3.text-\[10px\].italic', { text: 'Le présent procès-verbal est établi '
                + 'contradictoirement entre la clinique et le représentant du fournisseur.' }),
            ].filter(Boolean)),
            signatures: [
              { role: 'Le Magasinier', nom: r.magasinier },
              { role: 'La Direction', nom: 'SOKOU Peace' },
              { role: 'Le représentant du fournisseur', nom: r.representantFournisseur || '' },
            ],
          });
        }
      },
    };
  }

  global.SIGH.screen('m7-pv-reception-consommables', ecranPV('consommables',
    'PV de réception — consommables',
    'Procès-verbaux de réception des consommables : quantités, écarts, réserves et signatures.',
    'Le PV <strong>constate</strong> la réception et se signe à trois — magasinier, Direction, représentant du '
      + 'fournisseur. Une conclusion « avec réserves » ou « non conforme » <strong>exige ses réserves '
      + 'écrites</strong> : une réserve muette ne protège personne.'));

  global.SIGH.screen('m7-pv-reception-reactifs', ecranPV('reactifs',
    'PV de réception — réactifs',
    'Procès-verbaux de réception des réactifs de laboratoire : chaîne du froid, lots, écarts, réserves.',
    'Les réactifs appellent un contrôle propre : la <strong>chaîne du froid</strong> à l\u2019arrivée fait '
      + 'partie du PV — un réactif arrivé hors température se refuse, et le PV en fait foi devant le '
      + 'fournisseur. Signature à trois, comme pour les consommables.'));

})(window);
