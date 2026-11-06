/* =============================================================================
 * M2 — Rendez-vous, Visites & Consultations (y compris à domicile)
 * -----------------------------------------------------------------------------
 * CDCT §10.5 et §10.6 — remplacement de l'agenda physique, registre des appels,
 * suivi des visites, consultations et soins à domicile avec facturation propre.
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core, U = global.SIGH.ui, S = global.SIGH.store, D = global.SIGH.data,
      P = global.SIGH.print, G = global.SIGH.charts, K = global.SIGH.kit, PR = global.SIGH.parcours;
  var el = C.el;
  var AUJ = new Date(2026, 7, 16);

  /* Objets d'appel relevés au standard — liste administrable. */
  var OBJETS_APPEL = ['Prise de rendez-vous', 'Report de rendez-vous', 'Demande de résultat d’analyse',
    'Renseignement tarifaire', 'Suivi post-hospitalisation', 'Rappel de règlement',
    'Demande d’ambulance', 'Information administrative'];

  function patients() { return S.collection('patients').active(); }
  function medecins() {
    return S.collection('personnel').active().filter(function (e) { return e.fonction === 'medecin'; });
  }
  function optionsPatients() {
    return C.sortBy(patients(), 'code').map(function (p) {
      return { value: p.code, label: p.code + ' — ' + p.nom + ' ' + p.prenom };
    });
  }
  function optionsMedecins() {
    return medecins().map(function (m) { return { value: m.nomComplet, label: m.nomComplet }; });
  }

  /* --- Catalogues de prescription ------------------------------------------
   * Le prescripteur doit atteindre TOUT ce que la clinique sait faire : les
   * médicaments de la pharmacie, les 48 analyses, les actes de chaque secteur
   * et les catégories d'hospitalisation. Ces listes viennent des référentiels
   * administrables — rien n'est écrit ici.
   * ---------------------------------------------------------------------- */
  function optionsMedicaments() {
    return S.collection('produits').active()
      .filter(function (p) { return p.categorie === 'medicament' || p.categorie === 'conso_medical'; })
      .map(function (p) {
        return {
          value: p.id, label: p.designation,
          detail: C.money(p.prixAchat, false) + ' · stock ' + (p.stockDetail != null ? p.stockDetail : p.stock),
        };
      });
  }
  function optionsAnalyses() {
    return D.ANALYSES.map(function (a) {
      return { value: a.code, label: a.designation, detail: a.categorie + ' · ' + C.money(a.prix, false) };
    });
  }
  function optionsActes() {
    return S.collection('actes').active().map(function (a) {
      return {
        value: a.code, label: a.libelle,
        detail: a.secteur + (a.prix ? ' · ' + C.money(a.prix, false) : ' · tarif à valider'),
      };
    });
  }

  /* --- Colonnes communes --------------------------------------------------- */
  function colDate(label) {
    return {
      key: 'date', label: label || 'Date', nowrap: true,
      text: function (r) { return C.dateFR(r.date) + ' ' + C.heure(r.date); },
      render: function (r) {
        return el('div', null, [
          el('p.text-sm.text-slate-700', { text: C.dateFR(r.date) }),
          el('p.text-xs.text-slate-400', { text: C.heure(r.date) }),
        ]);
      },
      sortValue: function (r) { return C.toDate(r.date).getTime(); },
    };
  }
  var colPatient = {
    key: 'patient', label: 'Patient',
    render: function (r) {
      return el('div.min-w-0', null, [
        el('p.truncate.text-sm.font-medium.text-slate-800', { text: r.patient }),
        el('p.font-mono.text-xs.text-slate-400', { text: r.patientCode }),
      ]);
    },
  };

  /* --- Champs communs ------------------------------------------------------ */
  function champsConsultation() {
    return [
      { type: 'section', label: 'Patient et praticien' },
      { name: 'patientCode', label: 'Dossier patient', type: 'select', required: true, options: optionsPatients(), col: 'full' },
      { name: 'medecin', label: 'Praticien', type: 'select', required: true, options: optionsMedecins() },
      {
        name: 'type', label: 'Type', type: 'select', required: true,
        options: ['Consultation', 'Contrôle', 'Urgence', 'Domicile'],
      },
      { type: 'section', label: 'Rendez-vous' },
      { name: 'date', label: 'Date et heure', type: 'datetime-local', required: true },
      { name: 'motif', label: 'Motif', required: true, col: 'full' },
      { name: 'diagnostic', label: 'Diagnostic', col: 'full', type: 'textarea', rows: 2 },
      { name: 'tarif', label: 'Tarif (FCFA)', type: 'money', min: 0 },
      {
        name: 'statut', label: 'Statut', type: 'select', required: true,
        options: [{ value: 'planifiee', label: 'Planifiée' }, { value: 'en_cours', label: 'En cours' }, { value: 'terminee', label: 'Terminée' }],
      },
    ];
  }

  function completerPatient(v) {
    var p = patients().filter(function (x) { return x.code === v.patientCode; })[0];
    if (p) { v.patientId = p.id; v.patient = p.nom + ' ' + p.prenom; }
    if (!v.reference) v.reference = C.nextRef('C', 5);
    return v;
  }

  /* --------------------------------------------------------------------------
   * FUSION RENDEZ-VOUS & VISITES (Bug 3 des Instructions, phase 3b)
   * --------------------------------------------------------------------------
   * L'accueil enregistre aussi des venues pour des INDIVIDUS NON ENREGISTRÉS —
   * visiteur, accompagnant, délégué, rendez-vous d'affaire privée avec la
   * Direction. Leur ouvrir un dossier patient polluerait la base médicale ;
   * les refuser ferait tenir un second agenda papier. Le formulaire porte donc
   * les deux voies : sélectionner un dossier, OU nommer le venu.
   * ------------------------------------------------------------------------ */
  function champsRendezVous() {
    function indexDe(champs, nom) {
      for (var i = 0; i < champs.length; i++) if (champs[i].name === nom) return i;
      return -1;
    }
    var champs = champsConsultation().slice();
    /* Le dossier n'est plus obligatoire : un individu non enregistré n'en a pas. */
    var iPat = indexDe(champs, 'patientCode');
    champs[iPat] = Object.assign({}, champs[iPat], {
      required: false,
      help: 'Laisser vide pour un individu non enregistré — renseigner alors son nom ci-dessous.',
    });
    champs.splice(iPat + 1, 0, {
      name: 'visiteurNom', label: 'Individu non enregistré (nom et prénoms)', col: 'full',
      help: 'Visiteur, accompagnant, affaire privée : la venue s’enregistre SANS ouvrir de dossier patient.',
    });
    /* Les natures de la cible : consultation, contrôle, urgence, visite,
       affaire privée. */
    var iType = indexDe(champs, 'type');
    champs[iType] = Object.assign({}, champs[iType], {
      options: ['Consultation', 'Contrôle', 'Urgence', 'Domicile', 'Visite', 'Affaire privée'],
    });
    return champs;
  }

  function validerVenue(v) {
    if (!v.patientCode && !(v.visiteurNom || '').trim()) {
      return 'Sélectionner un dossier patient, ou nommer l’individu non enregistré.';
    }
    return null;
  }

  function completerVenue(v) {
    if (v.patientCode) return completerPatient(v);
    /* Individu non enregistré : la venue porte son nom, PAS un dossier —
       aucun code CNT n'est consommé (RG-01 protège la série). */
    v.patient = (v.visiteurNom || '').trim();
    v.patientCode = 'NON-PATIENT';
    v.patientId = null;
    v.nonPatient = true;
    if (!v.reference) v.reference = C.nextRef('C', 5);
    return v;
  }

  /* --- Détail d'une consultation ------------------------------------------- */
  function detail(r) {
    var p = patients().filter(function (x) { return x.id === r.patientId; })[0];
    var wrap = el('div.space-y-4');
    wrap.appendChild(U.descList([
      ['Référence', el('span.font-mono', { text: r.reference || r.id })],
      ['Date', C.dateFR(r.date) + ' à ' + C.heure(r.date)],
      ['Patient', r.nonPatient
        ? el('span', null, [el('span', { text: r.patient + ' ' }), U.badge('individu non enregistré', 'info')])
        : r.patient],
      ['Dossier', el('span.font-mono', { text: r.nonPatient ? '— (sans dossier)' : r.patientCode })],
      ['Praticien', r.medecin],
      ['Type', r.type],
      ['Statut', U.statut(r.statut)],
      ['Tarif', C.money(r.tarif || 0)],
    ]));
    wrap.appendChild(U.card('Motif et diagnostic', el('div.space-y-3', null, [
      el('div', null, [el('p.text-xs.text-slate-500', { text: 'Motif de consultation' }), el('p.mt-0\\.5.text-sm.text-slate-800', { text: r.motif || '—' })]),
      el('div', null, [el('p.text-xs.text-slate-500', { text: 'Diagnostic' }), el('p.mt-0\\.5.text-sm.text-slate-800', { text: r.diagnostic || 'Non renseigné' })]),
    ])));
    if (p && p.assureur) {
      wrap.appendChild(K.note('Patient couvert par <strong>' + p.assureurNom + '</strong> à hauteur de ' + p.tauxPriseEnCharge
        + ' %. La facturation appliquera la répartition patient / assureur (RG-09).', { tone: 'info', icon: 'shield-check' }));
    }
    return wrap;
  }

  /* --- État imprimable : compte rendu de consultation ---------------------- */
  function etatConsultation(r) {
    var p = patients().filter(function (x) { return x.id === r.patientId; })[0];
    var contenu = el('div.space-y-3');
    contenu.appendChild(el('p', null, [
      el('span.font-semibold', { text: 'Motif de consultation : ' }),
      el('span', { text: r.motif || '—' }),
    ]));
    contenu.appendChild(el('p', null, [
      el('span.font-semibold', { text: 'Diagnostic retenu : ' }),
      el('span', { text: r.diagnostic || '—' }),
    ]));
    contenu.appendChild(el('div.mt-4.min-h-\\[60mm\\].rounded.border.border-slate-300.p-3', null, [
      el('p.mb-2.text-\\[10px\\].font-semibold.uppercase.text-slate-500', { text: 'Observations et conduite à tenir' }),
      el('p.text-\\[10px\\].text-slate-400', { text: '(Espace réservé à la rédaction manuscrite ou à la saisie)' }),
    ]));
    P.etat({
      titre: 'Compte rendu de consultation',
      sousTitre: r.type + ' du ' + C.dateFR(r.date),
      cartouche: [
        ['Patient', r.patient], ['Dossier', r.patientCode],
        ['Date de naissance', p ? C.dateFR(p.dateNaissance) : '—'],
        ['Praticien', r.medecin],
        ['Référence', r.reference || r.id],
        ['Type', r.type],
      ],
      contenu: contenu,
      signatures: [{ role: 'Le Médecin traitant', nom: r.medecin }],
    });
  }

  /* ==========================================================================
   * AGENDA
   * ======================================================================== */
  /** Les pathologies actives du référentiel. */
  function pathologiesActives() {
    return S.collection('pathologies', { module: 'M2', entite: 'pathologie', prefix: 'PATH' }).active();
  }

  /** Options de sélection, groupées par chapitre pour rester lisibles. */
  function optionsPathologies() {
    return pathologiesActives().map(function (x) {
      var ch = D.CHAPITRES_PATHOLOGIE.filter(function (y) { return y.id === x.chapitre; })[0];
      return {
        value: x.code, label: x.libelle,
        detail: (ch ? ch.label : x.chapitre) + (x.notifiable ? ' · déclaration obligatoire' : ''),
      };
    });
  }

  /* ==========================================================================
   * LES DEUX PIÈCES QUE LE PATIENT EMPORTE
   * --------------------------------------------------------------------------
   * L'ordonnance va à la pharmacie, le bulletin d'analyses au laboratoire —
   * en passant tous deux par la caisse. Elles s'impriment depuis l'ordonnance
   * ENREGISTRÉE et jamais depuis l'état d'un formulaire : le papier doit dire
   * exactement ce qui est parti dans le logiciel, sans quoi la caisse encaisse
   * autre chose que ce que le laboratoire attend.
   * ======================================================================== */
  function etatOrdonnanceMedicale(r) {
    if (!r) return;
    var lignes = (r.medicaments || []).map(function (l) {
      return {
        produit: l.produit, detail: l.posologie || '',
        quantite: l.quantite + ' ' + (l.unite || ''), prix: l.prix, total: l.total,
      };
    });
    P.etat({
      titre: 'Ordonnance médicale',
      sousTitre: r.numero,
      cartouche: [['Patient', r.patient], ['Dossier', r.patientCode], ['Date', C.dateFR(r.date)],
        ['Prescripteur', r.medecin], ['Diagnostic', r.diagnostic || '—'],
        ['Règlement', r.statutPaiement === 'soldee' ? 'Réglée' : 'En attente']],
      contenu: [
        lignes.length ? P.tableau([
          { label: 'Désignation', key: 'produit' },
          { label: 'Posologie', key: 'detail' },
          { label: 'Quantité', align: 'right', key: 'quantite' },
          /* On ne totalise PAS le prix unitaire : additionner des prix
             unitaires ne produit aucune grandeur. */
          { label: 'Prix unitaire', align: 'right', value: function (l) { return C.money(l.prix, false); } },
          {
            label: 'Montant', align: 'right',
            value: function (l) { return C.money(l.total, false); },
            /* LA SOMME EST REFAITE DEPUIS LES LIGNES IMPRIMÉES. Le pied
               recevait un objet dont les clés — `prix`, `total` — ne
               correspondaient à AUCUNE colonne porteuse de `key` : il
               cherchait `total[undefined]` et n’affichait rien. Un pied vide
               se lit comme une mise en page, pas comme un défaut. */
            somme: function (l) { return l.total; },
          },
        ], lignes, { total: true }) : null,
        (r.analyses || []).length ? el('div', null, [
          el('p.mt-3.text-\[11px\].font-bold.uppercase', { text: 'Analyses demandées' }),
          P.tableau([
            { label: 'Analyse demandée', key: 'designation' },
            { label: 'Échantillon', key: 'echantillon' },
            { label: 'Tarif', align: 'right', value: function (l) { return C.money(l.prix, false); },
              somme: function (l) { return l.prix || 0; } },
          ], r.analyses, { total: true }),
        ]) : null,
        (r.actes || []).length ? el('div', null, [
          el('p.mt-3.text-\[11px\].font-bold.uppercase', { text: 'Actes prescrits' }),
          P.tableau([
            { label: 'Acte prescrit', key: 'libelle' },
            { label: 'Secteur', key: 'secteur' },
            { label: 'Tarif', align: 'right', value: function (l) { return l.prix ? C.money(l.prix, false) : 'à valider'; },
              somme: function (l) { return l.prix || 0; } },
          ], r.actes, { total: true }),
        ]) : null,
        !lignes.length && !(r.analyses || []).length && !(r.actes || []).length
          ? el('p.italic.text-slate-500', { text: 'Cette ordonnance ne porte aucune ligne.' }) : null,
      ],
      signatures: [{ role: 'Le Médecin prescripteur', nom: r.medecin, mention: 'Signature et cachet' },
        { role: 'Le Pharmacien', mention: 'Dispensation' }],
    });
  }

  /**
   * Le BULLETIN D'ANALYSES — la pièce que le patient porte à la caisse puis à
   * la salle de prélèvement. Sa forme suit le formulaire papier de la
   * clinique : identité, service demandeur, indication, urgence, puis les
   * examens groupés par section.
   */
  function etatBulletinAnalyses(r) {
    if (!r) return;
    var L = global.SIGH.labo;
    var pat = S.collection('patients').active().filter(function (x) {
      return x.code === r.patientCode || x.id === r.patientId;
    })[0];

    var lignes = (r.analyses || []).map(function (a) {
      var ex = L ? (L.examen(a.code) || L.EXAMENS.filter(function (x) {
        return x.designation.toUpperCase() === String(a.designation || '').toUpperCase();
      })[0]) : null;
      return {
        section: ex ? L.section(ex.section) : (a.categorie || '—'),
        designation: a.designation || (ex ? ex.designation : a.code),
        echantillon: a.echantillon || (ex ? ex.echantillon : '—'),
        prix: a.prix,
      };
    });

    P.etat({
      titre: 'Bulletin d’analyses bio-médicales',
      sousTitre: r.numero,
      cartouche: [
        ['Patient', r.patient], ['Dossier', r.patientCode],
        ['Âge', pat && pat.dateNaissance ? C.age(pat.dateNaissance) + ' ans' : '—'],
        ['Sexe', pat ? (pat.sexe === 'F' ? 'Féminin' : 'Masculin') : '—'],
        ['Date', C.dateFR(r.date)],
        ['Prescripteur', r.medecin],
        ['Indication', r.diagnostic || '—'],
        ['Service demandeur', r.serviceDemandeur || r.secteurDemandeur || '—'],
        ['Priorité', r.urgent ? 'URGENT' : 'Courant'],
        ['Règlement', r.statutPaiement === 'soldee' ? 'Réglé' : 'À régler à la caisse'],
      ],
      contenu: el('div.space-y-3', null, [
        lignes.length
          ? P.tableau([
            { label: 'Section', key: 'section' },
            { label: 'Examen demandé', key: 'designation' },
            { label: 'Échantillon', key: 'echantillon' },
            {
              label: 'Tarif', align: 'right',
              value: function (l) { return C.money(l.prix, false); },
              somme: function (l) { return l.prix; },
            },
          ], lignes, { total: true })
          : el('p.italic.text-slate-500', { text: 'Aucune analyse demandée sur cette ordonnance.' }),
        el('p.mt-3.text-\[10px\].italic', {
          text: 'Ce bulletin accompagne le patient à la caisse puis à la salle de prélèvement, et suit '
            + 'ensuite l’échantillon jusqu’au laboratoire. Le résultat est transmis au clinicien '
            + 'prescripteur ; il est remis directement au patient lorsque celui-ci est adressé de l’extérieur.',
        }),
      ]),
      signatures: [{ role: 'Le Médecin prescripteur', nom: r.medecin, mention: 'Signature et cachet' },
        { role: 'Le Préleveur', mention: 'Heure de prélèvement' }],
    });
  }

  global.SIGH.screen('m2-agenda', {
    title: 'Agenda',
    description: 'Vue calendaire des rendez-vous et consultations, par praticien et par jour.',
    regle: 'L’agenda ne montre pas que la semaine en cours : une <strong>plage de dates</strong> permet de '
      + 'retrouver les semaines passées ou à venir. Un rendez-vous se prend depuis cet écran, par praticien '
      + 'et par jour, et déclenche la notification du praticien concerné.',
    actions: function () {
      return [
        K.btn('Rendez-vous', { icon: 'calendar-check', onclick: function () { global.SIGH.app.go('m2-rendezvous'); } }),
        K.btn('Visites sans rendez-vous', { icon: 'user-check', onclick: function () { global.SIGH.app.go('m2-visites'); } }),
      ];
    },
    render: function (root) {
      var host = el('div.space-y-4');
      var cons = S.collection('consultations').active();
      /* Plage affichée — modifiable, pour retrouver une semaine passée. */
      var debutSel = el('input.input', { type: 'date', value: C.iso(C.addDays(AUJ, -2)) });
      var finSel = el('input.input', { type: 'date', value: C.iso(C.addDays(AUJ, 4)) });
      var semaine = [];
      function calculerJours() {
        semaine = [];
        var d = C.toDate(debutSel.value), f = C.toDate(finSel.value);
        var n = Math.max(1, Math.min(31, C.daysBetween(d, f) + 1));
        for (var i = 0; i < n; i++) semaine.push(C.addDays(d, i));
      }
      calculerJours();

      host.appendChild(U.kpiGrid([
        { label: 'Rendez-vous aujourd’hui', value: C.num(cons.filter(function (c) { return C.iso(c.date) === C.iso(AUJ); }).length), icon: 'calendar-check', tone: 'navy' },
        { label: 'Cette semaine', value: C.num(cons.filter(function (c) { return Math.abs(C.daysBetween(AUJ, c.date)) <= 3; }).length), icon: 'calendar-days', tone: 'info' },
        { label: 'À confirmer', value: C.num(cons.filter(function (c) { return c.statut === 'planifiee'; }).length), icon: 'clock', tone: 'warning' },
        { label: 'Praticiens', value: C.num(medecins().length), icon: 'user-round', tone: 'neutral' },
      ]));

      var barre = el('div.card');
      barre.appendChild(el('div.card-body.flex.flex-wrap.items-end.gap-3', null, [
        el('div', null, [el('label.label', { text: 'Du' }), debutSel]),
        el('div', null, [el('label.label', { text: 'Au' }), finSel]),
        K.btn('Semaine en cours', { icon: 'calendar-days', onclick: function () {
          debutSel.value = C.iso(C.addDays(AUJ, -2)); finSel.value = C.iso(C.addDays(AUJ, 4)); redessiner();
        } }),
        K.commande('Nouveau rendez-vous', { variant: 'primary', icon: 'plus', onclick: nouveauRdv }),
      ]));
      host.appendChild(barre);

      var carteGrille = el('div');
      host.appendChild(carteGrille);
      debutSel.addEventListener('change', redessiner);
      finSel.addEventListener('change', redessiner);

      function redessiner() {
        calculerJours();
        cons = S.collection('consultations').active();
        C.clear(carteGrille);
        carteGrille.appendChild(construireGrille());
        U.icons(carteGrille);
      }

      function construireGrille() {
      /* Grille de la plage choisie */
      var grille = el('div.grid.gap-3', { class: 'md:grid-cols-4 lg:grid-cols-7' });
      semaine.forEach(function (jour) {
        var duJour = C.sortBy(cons.filter(function (c) { return C.iso(c.date) === C.iso(jour); }), 'date');
        var estAuj = C.iso(jour) === C.iso(AUJ);
        var carte = el('div.rounded-xl.border.bg-white.p-3.shadow-card', {
          class: estAuj ? 'border-navy-400 ring-1 ring-navy-200' : 'border-slate-200',
        });
        carte.appendChild(el('p.text-xs.font-semibold.uppercase.tracking-wide', {
          class: estAuj ? 'text-navy-800' : 'text-slate-500',
          text: C.JOURS[jour.getDay()].slice(0, 3) + '. ' + jour.getDate(),
        }));
        carte.appendChild(el('p.mb-2.text-\\[10px\\].text-slate-400', { text: C.MOIS[jour.getMonth()] }));
        if (!duJour.length) {
          carte.appendChild(el('p.py-4.text-center.text-xs.text-slate-300', { text: 'Aucun' }));
        } else {
          var liste = el('div.space-y-1\\.5');
          duJour.slice(0, 6).forEach(function (c) {
            liste.appendChild(el('button.block.w-full.rounded-md.border.border-slate-200.px-2.py-1\\.5.text-left.transition-colors.hover\\:border-navy-300.hover\\:bg-navy-50', {
              type: 'button',
              onclick: function () {
                /* Bug 10 des Instructions : la fiche d'un rendez-vous porte
                   ÉDITER et SUPPRIMER dans son pied — consulter puis refaire
                   le tour de l'écran pour agir faisait perdre le geste. Les
                   commandes sont ABSENTES sans le droit, jamais grisées. */
                var colC = S.collection('consultations', { module: 'M2', entite: 'Consultation' });
                var t = U.drawer({
                  title: c.patient, subtitle: c.patientCode + ' — ' + C.dateFR(c.date), body: detail(c),
                  footer: [
                    K.btn('Imprimer', { icon: 'printer', onclick: function () { etatConsultation(c); } }),
                    K.commande('Éditer le rendez-vous', {
                      variant: 'primary', icon: 'pencil',
                      onclick: function () { t.close(); K.modifier(colC, champsRendezVous, c, redessiner); },
                    }),
                    K.commande('Annuler le rendez-vous', {
                      variant: 'danger', icon: 'archive', droit: 'annuler',
                      onclick: function () {
                        t.close();
                        U.confirm({
                          title: 'Annuler ce rendez-vous ?',
                          message: 'Le rendez-vous est archivé (RG-14), pas supprimé : il reste consultable et l’opération est annulable.',
                          confirmLabel: 'Annuler le rendez-vous', danger: true, requireMotif: true,
                        }).then(function (r) {
                          if (!r) return;
                          var res = colC.archive(c.id, r.motif);
                          redessiner();
                          U.toast('Rendez-vous annulé.', { type: 'success', undo: function () { res.undo(); redessiner(); } });
                        });
                      },
                    }),
                  ].filter(Boolean),
                });
              },
            }, [
              el('span.block.text-\\[11px\\].font-semibold.text-navy-800', { text: C.heure(c.date) }),
              el('span.block.truncate.text-\\[11px\\].text-slate-600', { text: c.patient }),
              el('span.block.truncate.text-\\[10px\\].text-slate-400', { text: c.motif }),
            ]));
          });
          if (duJour.length > 6) liste.appendChild(el('p.text-center.text-\\[10px\\].text-slate-400', { text: '+ ' + (duJour.length - 6) + ' autre(s)' }));
          carte.appendChild(liste);
        }
        grille.appendChild(carte);
      });
      return U.card('Du ' + C.dateFR(semaine[0]) + ' au ' + C.dateFR(semaine[semaine.length - 1])
        + ' — ' + C.num(semaine.length) + ' jour(s)', grille,
        [K.lien('m2-rendezvous', 'Gérer les rendez-vous', { size: 'sm', icon: 'arrow-right' })]);
      }
      redessiner();
      setTimeout(rappelerEcheances, 900);

      /* --------------------------------------------------------------------
       * Prise de rendez-vous — par praticien et par jour, avec notification
       * sonore du praticien concerné (le personnel ne regarde pas l'écran en
       * permanence).
       * ------------------------------------------------------------------ */
      function nouveauRdv() {
        var f = U.form([
          { name: 'patientCode', label: 'Dossier patient', type: 'select', required: true, col: 'full', options: optionsPatients() },
          { name: 'medecin', label: 'Praticien', type: 'select', required: true, options: optionsMedecins() },
          {
            name: 'type', label: 'Nature', type: 'select', required: true,
            options: ['Consultation', 'Contrôle', 'Urgence'],
          },
          { name: 'date', label: 'Date et heure', type: 'datetime-local', required: true, value: new Date().toISOString().slice(0, 16) },
          { name: 'motif', label: 'Motif', required: true, col: 'full' },
          { name: 'tarif', label: 'Tarif prévu (FCFA)', type: 'money', min: 0 },
          { name: 'notifier', label: 'Notifier le praticien', type: 'checkbox', value: true },
        ], {});

        var m = U.modal({
          title: 'Nouveau rendez-vous', size: 'lg',
          body: el('div.space-y-3', null, [
            K.note('Le rendez-vous est enregistré au nom du praticien choisi et apparaît immédiatement '
              + 'dans son agenda du jour. La notification sonore prévient le poste concerné.', { tone: 'info' }),
            f,
          ]),
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Enregistrer le rendez-vous', {
              variant: 'primary', icon: 'calendar-check',
              onclick: function () {
                var v = f.collect();
                if (!v) return;
                var notifier = v.notifier;
                delete v.notifier;
                v.statut = 'planifiee';
                v.date = new Date(v.date).toISOString();
                completerPatient(v);
                var res = S.collection('consultations', { module: 'M2', entite: 'Consultation' }).insert(v);
                m.close();
                redessiner();
                if (notifier) {
                  U.alerter('Rendez-vous transmis à ' + v.medecin + '.', {
                    son: 'rappel', type: 'success',
                    detail: v.patient + ' — ' + C.dateFR(v.date) + ' à ' + C.heure(v.date) + ' · ' + v.motif,
                    undo: function () { res.undo(); redessiner(); },
                  });
                } else {
                  U.toast('Rendez-vous enregistré.', {
                    type: 'success', detail: v.patient + ' — ' + C.dateFR(v.date),
                    undo: function () { res.undo(); redessiner(); },
                  });
                }
              },
            }),
          ],
        });
      }

      /* Rappel des échéances proches — consultations, rendez-vous, réunions.
         C'est la notification automatique demandée : elle se déclenche à
         l'ouverture de l'agenda, sans action de l'utilisateur. */
      function rappelerEcheances() {
        var maintenant = AUJ.getTime();
        var proches = S.collection('consultations').active().filter(function (c) {
          if (c.statut !== 'planifiee') return false;
          var t = C.toDate(c.date).getTime();
          return t >= maintenant && t - maintenant <= 2 * 3600000;
        });
        var reunions = [];
        try {
          reunions = S.collection('reunions').active().filter(function (r) {
            return C.iso(r.date) === C.iso(AUJ);
          });
        } catch (e) { /* le module M13 peut ne pas avoir amorcé ses réunions */ }

        if (!proches.length && !reunions.length) return;
        var parts = [];
        if (proches.length) parts.push(proches.length + ' consultation(s) dans les deux heures');
        if (reunions.length) parts.push(reunions.length + ' réunion(s) aujourd’hui');
        U.alerter('Échéances du jour : ' + parts.join(' · '), {
          son: 'information', type: 'info',
          detail: proches.length ? 'Prochaine : ' + proches[0].patient + ' à ' + C.heure(proches[0].date) : null,
        });
      }

      host.appendChild(K.charts([
        {
          title: 'Charge par praticien (30 derniers jours)',
          render: function () {
            var recent = cons.filter(function (c) { return C.daysBetween(c.date, AUJ) <= 30 && C.daysBetween(c.date, AUJ) >= 0; });
            var g = C.groupBy(recent, 'medecin');
            return K.ranking(Object.keys(g).map(function (k) { return { label: k, value: g[k].length }; })
              .sort(function (a, b) { return b.value - a.value; }));
          },
        },
        {
          title: 'Répartition par type',
          render: function () {
            var g = C.groupBy(cons, 'type');
            var keys = Object.keys(g);
            return G.anneau(keys, keys.map(function (k) { return g[k].length; }), { legend: 'bottom' });
          },
        },
      ]));
      root.appendChild(host);
      return null;

      /* ------------------------------------------------------------------
       * Passage sans rendez-vous : le patient se présente, l'accueil
       * l'enregistre et l'oriente. Si le dossier n'existe pas encore, il se
       * crée ici même — on ne renvoie pas un patient au comptoir voisin.
       * ---------------------------------------------------------------- */
    },
  });

  /* --------------------------------------------------------------------------
   * ENREGISTRER UNE VISITE SANS RENDEZ-VOUS — Bug 0a des Instructions
   * --------------------------------------------------------------------------
   * DÉCLARÉE AU MODULE, et non plus dans la fermeture de l'écran agenda :
   * le bouton « Nouvelle visite » de m2-visites l'appelait aussi, et une
   * fonction déclarée dans la fermeture d'un écran est INVISIBLE au suivant —
   * le clic levait une ReferenceError que ni check.js ni la lecture ne
   * voyaient. Le piège documenté du prototype, rencontré une fois de plus.
   * ------------------------------------------------------------------------ */
  function nouvelleVisite() {
    var f = U.form([
      { name: 'patientCode', label: 'Dossier patient', type: 'select', required: true, col: 'full', options: optionsPatients() },
      { name: 'date', label: 'Heure d’arrivée', type: 'datetime-local', required: true, value: new Date().toISOString().slice(0, 16) },
      { name: 'motif', label: 'Motif du passage', required: true, col: 'full' },
      {
        name: 'type', label: 'Nature', type: 'select', required: true,
        options: ['Consultation', 'Urgence', 'Contrôle'],
      },
      {
        name: 'orientation', label: 'Orientation', type: 'select', required: true,
        options: ['Médecine générale', 'Chirurgie', 'Maternité', 'Laboratoire', 'Imagerie / Échographie',
          'Salle de soins', 'Mise en observation', 'Pharmacie', 'Retour à domicile'],
        help: 'Service vers lequel le patient est dirigé après l’accueil.',
      },
      { name: 'medecin', label: 'Praticien pressenti', type: 'select', options: optionsMedecins() },
      { name: 'priorite', label: 'Passage prioritaire', type: 'checkbox' },
      { name: 'tarif', label: 'Tarif de la consultation (FCFA)', type: 'money', min: 0 },
    ], {});

    var m = U.modal({
      title: 'Enregistrer un passage sans rendez-vous', size: 'lg',
      body: el('div.space-y-3', null, [
        K.note('L’heure d’arrivée est tracée : c’est elle qui mesure l’attente à l’accueil. '
          + 'L’orientation dirige le patient vers le service compétent et prépare sa prise en charge.', { tone: 'info' }),
        f,
      ]),
      footer: [
        K.btn('Annuler', { onclick: function () { m.close(); } }),
        K.btn('Enregistrer le passage', {
          variant: 'primary', icon: 'user-check',
          onclick: function () {
            var v = f.collect();
            if (!v) return;
            var prioritaire = v.priorite;
            delete v.priorite;
            v.statut = 'en_cours';
            v.date = new Date(v.date).toISOString();
            v.sansRendezVous = true;
            completerPatient(v);
            var res = S.collection('consultations', { module: 'M2', entite: 'Consultation' }).insert(v);
            m.close();
            if (prioritaire) {
              U.alerter('Passage prioritaire — ' + v.patient + ' orienté vers ' + v.orientation + '.', {
                son: 'alerte', type: 'warning', detail: v.motif,
              });
            } else {
              U.toast('Passage enregistré — ' + v.patient + '.', {
                type: 'success', detail: 'Orienté vers ' + v.orientation,
                undo: function () { res.undo(); },
              });
            }
            setTimeout(function () { global.location.reload(); }, 900);
          },
        }),
      ],
    });
  }

  /* ==========================================================================
   * RENDEZ-VOUS
   * ======================================================================== */
  global.SIGH.screen('m2-rendezvous', {
    title: 'Rendez-vous & visites',
    description: 'Prise de rendez-vous et enregistrement des venues — patients, individus non enregistrés, affaires privées.',
    regle: 'Écran FUSIONNÉ (Bug 3 des Instructions) : rendez-vous de consultation, de contrôle, visites '
      + 'spontanées et <strong>affaires privées</strong> s’enregistrent ici, pour un patient du répertoire '
      + '<strong>ou un individu non enregistré</strong> — un visiteur ne consomme pas de code CNT (RG-01). '
      + 'La plage de dates FILTRE la liste : « les rendez-vous du 21 août » ne se répond pas en triant.',
    actions: function () {
      return [
        K.btn('Agenda', { icon: 'calendar-days', onclick: function () { global.SIGH.app.go('m2-agenda'); } }),
        K.commande('Nouvelle visite', { variant: 'primary', icon: 'user-check',
          onclick: function () { nouvelleVisite(); } }),
      ];
    },
    render: K.crud({
      collection: 'consultations', entite: 'rendez-vous', entiteP: 'rendez-vous', module: 'M2',
      defaultSort: 'date', defaultDir: 'desc', formSize: 'lg',
      source: 'Agenda physique de l’accueil — CDCT §10.6 ; fusion RDV + visites : Instructions, Bug 3.',
      /* Bug 11 : le FILTRE par plage de dates, avec ses raccourcis. */
      plageDates: { champ: 'date', aujourdhui: AUJ },
      columns: [
        { key: 'reference', label: 'N°', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.reference || '—' }); } },
        colDate('Date et heure'), colPatient,
        { key: 'medecin', label: 'Praticien' },
        { key: 'motif', label: 'Motif' },
        { key: 'type', label: 'Type', render: function (r) { return U.badge(r.type, r.type === 'Urgence' ? 'danger' : 'navy'); } },
        { key: 'statut', label: 'Statut', render: function (r) { return U.statut(r.statut); } },
      ],
      fields: champsRendezVous, transform: completerVenue, beforeSave: validerVenue,
      onCreate: function () { return { statut: 'planifiee', type: 'Consultation', tarif: 3000 }; },
      filters: [
        { name: 'statut', label: 'Statut', options: [{ value: 'planifiee', label: 'Planifiée' }, { value: 'en_cours', label: 'En cours' }, { value: 'terminee', label: 'Terminée' }] },
        { name: 'type', label: 'Type', options: ['Consultation', 'Contrôle', 'Urgence', 'Domicile', 'Visite', 'Affaire privée'] },
        { name: 'medecin', label: 'Praticien', options: optionsMedecins() },
        { name: 'venu', label: 'Venu', options: [{ value: 'patient', label: 'Patients du répertoire' }, { value: 'externe', label: 'Individus non enregistrés' }],
          match: function (r, v) { return v === 'externe' ? !!r.nonPatient : !r.nonPatient; } },
      ],
      kpis: function (rows) {
        return [
          { label: 'Rendez-vous enregistrés', value: C.num(rows.length), icon: 'calendar-days', tone: 'navy' },
          { label: 'Planifiés', value: C.num(rows.filter(function (r) { return r.statut === 'planifiee'; }).length), icon: 'clock', tone: 'warning' },
          { label: 'Honorés', value: C.num(rows.filter(function (r) { return r.statut === 'terminee'; }).length), icon: 'check-circle-2', tone: 'success' },
          { label: 'Urgences', value: C.num(rows.filter(function (r) { return r.type === 'Urgence'; }).length), icon: 'siren', tone: 'danger' },
        ];
      },
      detail: detail, etat: etatConsultation,
    }),
  });

  /* ==========================================================================
   * VISITES
   * ======================================================================== */
  global.SIGH.screen('m2-visites', {
    title: 'Registre des visites de suivi clinique',
    description: 'Passages sans rendez-vous et suivi clinique — l’enregistrement des venues se fait dans Rendez-vous & visites.',
    regle: 'La visite est le passage <strong>sans rendez-vous</strong> : l’accueil l’enregistre, l’oriente '
      + 'vers le service compétent et la prise en charge démarre. C’est le premier maillon du parcours — '
      + 'ce qui n’est pas enregistré ici n’existe nulle part ensuite. La prise de rendez-vous et les venues '
      + 'd’individus non enregistrés vivent dans <strong>Rendez-vous &amp; visites</strong> (fusion, Bug 3).',
    actions: function () {
      return [
        K.btn('Rendez-vous & visites', { icon: 'calendar-plus', onclick: function () { global.SIGH.app.go('m2-rendezvous'); } }),
        K.btn('Répertoire des patients', { icon: 'users', onclick: function () { global.SIGH.app.go('m1-patients'); } }),
        /* Une ÉCRITURE se déclare comme telle : commande, pas bouton. */
        K.commande('Nouvelle visite', { variant: 'primary', icon: 'user-plus', onclick: function () { nouvelleVisite(); } }),
      ];
    },
    render: function (root) {
      var cons = S.collection('consultations').active();
      var visites = cons.filter(function (c) { return c.type !== 'Domicile'; });
      var host = el('div.space-y-4');

      host.appendChild(U.kpiGrid([
        { label: 'Visites enregistrées', value: C.num(visites.length), icon: 'footprints', tone: 'navy' },
        { label: 'Visites du jour', value: C.num(visites.filter(function (v) { return C.iso(v.date) === C.iso(AUJ); }).length), icon: 'calendar-check', tone: 'info' },
        { label: 'Urgences', value: C.num(visites.filter(function (v) { return v.type === 'Urgence'; }).length), icon: 'siren', tone: 'danger' },
        { label: 'Patients distincts', value: C.num(Object.keys(C.groupBy(visites, 'patientId')).length), icon: 'users', tone: 'success' },
      ]));

      host.appendChild(U.dataTable({
        title: 'Registre des visites', rows: visites, exportName: 'visites', pageSize: 15,
        defaultSort: 'date', defaultDir: 'desc',
        filters: [{ name: 'type', label: 'Type', options: ['Consultation', 'Contrôle', 'Urgence'] }],
        columns: [colDate(), colPatient,
          { key: 'motif', label: 'Motif de la visite' },
          { key: 'medecin', label: 'Orienté vers' },
          { key: 'type', label: 'Type', render: function (r) { return U.badge(r.type, r.type === 'Urgence' ? 'danger' : 'navy'); } },
          { key: 'statut', label: 'Statut', render: function (r) { return U.statut(r.statut); } },
        ],
        onRowClick: function (r) { U.drawer({ title: r.patient, subtitle: r.patientCode, body: detail(r) }); },
        rowActions: function (r) {
          return [K.iconBtn('printer', 'Imprimer le compte rendu', function () { etatConsultation(r); })];
        },
      }));
      root.appendChild(host);
      return null;
    },
  });

  /* ==========================================================================
   * CONSULTATIONS
   * ======================================================================== */
  global.SIGH.screen('m2-consultations', {
    title: 'Consultations',
    description: 'Enregistrement des consultations, diagnostics et actes réalisés, avec édition du compte rendu.',
    render: K.crud({
      collection: 'consultations', entite: 'consultation', entiteP: 'consultations', module: 'M2',
      defaultSort: 'date', defaultDir: 'desc', formSize: 'lg',
      columns: [
        colDate(), colPatient,
        { key: 'motif', label: 'Motif' },
        { key: 'diagnostic', label: 'Diagnostic' },
        { key: 'medecin', label: 'Praticien' },
        { key: 'tarif', label: 'Tarif', align: 'right', text: function (r) { return C.money(r.tarif || 0, false); }, render: function (r) { return C.money(r.tarif || 0, false); } },
        { key: 'statut', label: 'Statut', render: function (r) { return U.statut(r.statut); } },
      ],
      fields: champsConsultation, transform: completerPatient,
      onCreate: function () { return { statut: 'en_cours', type: 'Consultation', tarif: 3000, date: new Date().toISOString().slice(0, 16) }; },
      filters: [
        { name: 'statut', label: 'Statut', options: [{ value: 'planifiee', label: 'Planifiée' }, { value: 'en_cours', label: 'En cours' }, { value: 'terminee', label: 'Terminée' }] },
        { name: 'medecin', label: 'Praticien', options: optionsMedecins() },
      ],
      kpis: function (rows) {
        var mois = rows.filter(function (r) {
          var d = C.toDate(r.date);
          return d.getFullYear() === AUJ.getFullYear() && d.getMonth() === AUJ.getMonth();
        });
        return [
          { label: 'Consultations totales', value: C.num(rows.length), icon: 'stethoscope', tone: 'navy' },
          { label: 'Ce mois-ci', value: C.num(mois.length), icon: 'calendar-check', tone: 'success' },
          { label: 'Recette consultations', value: C.money(C.sum(rows, 'tarif')), icon: 'coins', tone: 'info' },
          { label: 'Tarif moyen', value: C.money(rows.length ? C.sum(rows, 'tarif') / rows.length : 0), icon: 'trending-up', tone: 'neutral' },
        ];
      },
      detail: detail, etat: etatConsultation,
    }),
  });

  /* ==========================================================================
   * FICHE DE CONSULTATION (saisie)
   * ======================================================================== */
  global.SIGH.screen('m2-consultation-fiche', {
    title: 'Fiche de consultation',
    description: 'Saisie guidée d’une consultation : motif, examen clinique, diagnostic, prescription et orientation.',
    render: function (root) {
      var host = el('div.grid.gap-4.lg\\:grid-cols-3');
      /* L'ordonnance issue du dernier « Enregistrer et prescrire ». C'est elle
         que les deux boutons d'impression reprennent. */
      var derniereOrdonnance = null;

      /* Colonne principale : formulaire */
      var f = U.form([
        { type: 'section', label: 'Identification' },
        { name: 'patientCode', label: 'Dossier patient', type: 'select', required: true, options: optionsPatients(), col: 'full' },
        { name: 'medecin', label: 'Praticien', type: 'select', required: true, options: optionsMedecins() },
        { name: 'date', label: 'Date et heure', type: 'datetime-local', required: true, value: new Date().toISOString().slice(0, 16) },

        { type: 'section', label: 'Motif et examen clinique' },
        { name: 'motif', label: 'Motif de consultation', required: true, col: 'full' },
        { name: 'temperature', label: 'Température (°C)', type: 'number', step: '0.1' },
        { name: 'tension', label: 'Tension artérielle (mmHg)', placeholder: '120/80' },
        { name: 'poids', label: 'Poids (kg)', type: 'number', step: '0.1' },
        { name: 'fc', label: 'Fréquence cardiaque (bpm)', type: 'number' },
        { name: 'examen', label: 'Examen clinique', type: 'textarea', rows: 3, col: 'full' },

        { type: 'section', label: 'Conclusion' },
        /* Deux champs, et non un seul. La PATHOLOGIE est un code que la
           clinique compte ; le DIAGNOSTIC est la phrase que le médecin écrit.
           N'avoir que le second rend toute statistique de morbidité
           impossible — « paludisme simple », « accès palustre » et « palu »
           ne se regroupent pas d'eux-mêmes. */
        {
          name: 'pathologies', label: 'Pathologie(s) retenue(s)', type: 'multiselect', required: true, col: 'full',
          options: optionsPathologies(),
          help: 'Référentiel de morbidité de la clinique. Plusieurs pathologies peuvent coexister ; '
            + 'la première citée est retenue comme principale.',
        },
        { name: 'diagnostic', label: 'Diagnostic rédigé', required: true, col: 'full',
          help: 'Ce que ce cas-ci a de particulier — la pathologie ci-dessus sert au comptage.' },
        { name: 'conduite', label: 'Conduite à tenir', type: 'textarea', rows: 2, col: 'full' },
        /* « Il faut que le médecin ait accès à tous les médicaments, toutes
           les analyses, tous les actes […] pour qu'il puisse les prescrire. »
           Les catalogues complets, en sélection multiple — et non une zone de
           texte libre qui n'engage rien en aval. */
        { name: 'medicaments', label: 'Médicaments prescrits', type: 'multiselect', col: 'full', options: optionsMedicaments(), help: 'Catalogue complet de la pharmacie. Quantités et posologies se précisent à l’ordonnance.' },
        { name: 'analyses', label: 'Analyses prescrites', type: 'multiselect', col: 'full', options: optionsAnalyses(), help: 'Les 48 analyses du catalogue. Chaque analyse cochée engendre sa demande au laboratoire.' },
        { name: 'actes', label: 'Actes prescrits', type: 'multiselect', col: 'full', options: optionsActes(), help: 'Actes infirmiers, médicaux et chirurgicaux, par secteur.' },
        { name: 'hospitalisation', label: 'Catégorie d’hospitalisation', type: 'select', col: 'full', options: [{ value: '', label: '— Aucune —' }].concat(D.TYPES_CHAMBRE.map(function (t) { return { value: t.id || t.label, label: 'Chambre ' + t.label + ' — ' + C.money(t.tarif, false) + '/jour' }; })) },
        { name: 'prescription', label: 'Prescription libre (mentions complémentaires)', type: 'textarea', rows: 2, col: 'full' },
        { name: 'tarif', label: 'Tarif de la consultation (FCFA)', type: 'money', value: 3000 },
        {
          name: 'orientation', label: 'Orientation', type: 'select',
          options: ['Retour à domicile', 'Hospitalisation', 'Laboratoire', 'Imagerie / Échographie', 'Pharmacie', 'Référence externe'],
        },
      ], {});

      /* ----------------------------------------------------------------------
       * BUG 14 DES INSTRUCTIONS — les constantes relevées à l'ACCUEIL se
       * REPRENNENT ici, sans double saisie : au choix du patient, le dernier
       * relevé de la collection `constantes` (celle que tient m1-constantes)
       * pré-remplit température, tension, poids et pouls. Le médecin corrige
       * s'il re-mesure — un champ déjà saisi n'est jamais écrasé.
       * -------------------------------------------------------------------- */
      var noteConstantes = el('p.mt-2.hidden.text-xs.text-slate-500');
      function reprendreConstantes() {
        var code = f.controls.patientCode && f.controls.patientCode.value;
        if (!code) return;
        var releves = S.collection('constantes').active()
          .filter(function (r) { return r.patientCode === code; })
          .sort(function (a, b) { return String(b.dateHeure || '').localeCompare(String(a.dateHeure || '')); });
        var dernier = releves[0];
        if (!dernier) { noteConstantes.classList.add('hidden'); return; }
        var repris = [];
        function poser(ctrl, valeur, libelle) {
          if (!ctrl || valeur == null || valeur === '') return;
          if (ctrl.value !== '' && ctrl.value != null) return; /* la saisie du médecin prime */
          ctrl.value = valeur;
          repris.push(libelle);
        }
        poser(f.controls.temperature, dernier.temperature, 'température');
        poser(f.controls.tension, dernier.tension, 'tension');
        poser(f.controls.poids, dernier.poids, 'poids');
        poser(f.controls.fc, dernier.pouls, 'fréquence cardiaque');
        if (repris.length) {
          noteConstantes.textContent = 'Constantes reprises du relevé de l’accueil du '
            + C.dateFR(dernier.dateHeure) + ' (' + repris.join(', ') + ') — corrigez si vous re-mesurez.';
          noteConstantes.classList.remove('hidden');
        }
      }
      if (f.controls.patientCode && f.controls.patientCode.addEventListener) {
        f.controls.patientCode.addEventListener('change', reprendreConstantes);
      }
      f.appendChild(noteConstantes);

      var actions = el('div.mt-4.flex.flex-wrap.gap-2');
      /* ENREGISTRER UNE CONSULTATION ET PRESCRIRE : l'écriture médicale par
         excellence. Elle était offerte à l'aide-soignante, au surveillant et
         au technicien d'échographie, qui ont tous trois M2 en LECTURE. Pour
         le dernier, ce n'était pas une habilitation trop large : c'était un
         exercice illégal. */
      C.append(actions, K.commande('Enregistrer et prescrire', {
        variant: 'primary', icon: 'save',
        onclick: function () {
          var v = f.collect();
          if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
          v.type = v.orientation === 'Hospitalisation' ? 'Urgence' : 'Consultation';
          v.statut = 'terminee';
          /* La première pathologie citée est la principale : c'est elle qui
             compte au tableau de morbidité, les autres sont associées. */
          var listePath = pathologiesActives();
          v.pathologiePrincipale = (v.pathologies || [])[0] || null;
          v.pathologiesLibelles = (v.pathologies || []).map(function (code) {
            var x = listePath.filter(function (y) { return y.code === code; })[0];
            return x ? x.libelle : code;
          });
          v.notifiable = (v.pathologies || []).some(function (code) {
            var x = listePath.filter(function (y) { return y.code === code; })[0];
            return x && x.notifiable;
          });
          completerPatient(v);
          var res = S.collection('consultations', { module: 'M2', entite: 'Consultation' }).insert(v);

          /* La consultation ne s'arrête pas à elle-même : ce qui y est
             prescrit part au laboratoire, à la pharmacie et à la caisse,
             d'un seul geste (parcours transactionnel). */
          var aPrescrire = (v.medicaments || []).length + (v.analyses || []).length + (v.actes || []).length;
          if (!aPrescrire) {
            U.toast('Consultation enregistrée.', {
              type: 'success', undo: res.undo, detail: v.patient + ' — ' + v.diagnostic,
            });
            return;
          }
          var ord;
          try {
            ord = PR.prescrire({
              patientCode: v.patientCode, medecin: v.medecin, diagnostic: v.diagnostic,
              date: v.date ? new Date(v.date).toISOString() : null,
              consultationId: res.record.id,
              medicaments: (v.medicaments || []).map(function (id) { return { produitId: id, quantite: 1 }; }),
              analyses: v.analyses || [], actes: v.actes || [],
            });
          } catch (e) {
            U.toast('Consultation enregistrée, prescription impossible : ' + e.message, { type: 'warning' });
            return;
          }
          derniereOrdonnance = ord.ordonnance.id;
          var envois = [];
          if (ord.demandes.length) envois.push(ord.demandes.length + ' analyse(s) au laboratoire');
          if ((v.medicaments || []).length) envois.push('pharmacie informée');
          envois.push('facture ' + ord.facture.numero + ' en attente à la caisse');
          U.toast('Consultation et ordonnance ' + ord.ordonnance.numero + ' enregistrées.', {
            type: 'success', duration: 9000, detail: envois.join(' · '),
          });

          /* Les deux pièces sont ce que le patient emporte : on les propose
             immédiatement plutôt que d'attendre qu'il redescende les chercher. */
          var m = U.modal({
            title: 'Pièces à remettre au patient',
            subtitle: 'Ordonnance ' + ord.ordonnance.numero,
            size: 'md',
            body: el('div.space-y-3', null, [
              K.note('Ces deux feuilles accompagnent le patient à la <strong>caisse</strong>, puis à la '
                + '<strong>pharmacie</strong> et à la <strong>salle de prélèvement</strong>. Elles reprennent '
                + 'exactement ce qui vient d’être transmis.', { tone: 'info', icon: 'printer' }),
              U.descList([
                ['Ordonnance', C.num((ord.ordonnance.medicaments || []).length) + ' médicament(s)'],
                ['Bulletin d’analyses', C.num(ord.demandes.length) + ' examen(s)'],
                ['Actes prescrits', C.num((ord.ordonnance.actes || []).length)],
                ['À régler à la caisse', C.money(ord.facture.montantTTC)],
              ], 'grid-cols-2'),
            ]),
            footer: [
              K.btn('Plus tard', { onclick: function () { m.close(); } }),
              (ord.ordonnance.medicaments || []).length ? K.btn('Ordonnance', {
                icon: 'file-text',
                onclick: function () { etatOrdonnanceMedicale(S.collection('ordonnances').get(ord.ordonnance.id)); },
              }) : null,
              ord.demandes.length ? K.btn('Bulletin d’analyses', {
                variant: 'primary', icon: 'flask-conical',
                onclick: function () { etatBulletinAnalyses(S.collection('ordonnances').get(ord.ordonnance.id)); },
              }) : null,
            ].filter(Boolean),
          });
        },
      }));
      /* Les deux pièces s'impriment depuis l'ordonnance ENREGISTRÉE.
         Tant qu'elle n'existe pas, le bouton le dit plutôt que de sortir une
         feuille vide — c'est le défaut signalé par la Direction. */
      function ordonnanceCourante() {
        if (derniereOrdonnance) return S.collection('ordonnances').get(derniereOrdonnance) || null;
        return null;
      }
      function exigerOrdonnance(quoi) {
        var ord = ordonnanceCourante();
        if (ord) return ord;
        U.toast('Aucune ordonnance à imprimer.', {
          type: 'error',
          detail: 'Cliquer d’abord sur « Enregistrer et prescrire » : ' + quoi + ' reprend ce qui a '
            + 'réellement été transmis au laboratoire et à la pharmacie, et non le contenu du formulaire.',
        });
        return null;
      }

      actions.appendChild(K.btn('Éditer l’ordonnance', {
        icon: 'file-text',
        onclick: function () {
          var ord = exigerOrdonnance('l’ordonnance');
          if (ord) etatOrdonnanceMedicale(ord);
        },
      }));
      actions.appendChild(K.btn('Éditer le bulletin d’analyses', {
        icon: 'flask-conical',
        onclick: function () {
          var ord = exigerOrdonnance('le bulletin');
          if (ord) etatBulletinAnalyses(ord);
        },
      }));

      var principal = el('div.lg\\:col-span-2');
      principal.appendChild(U.card('Consultation', el('div', null, [f, actions])));
      host.appendChild(principal);

      /* Colonne latérale : aide et rappels */
      var aside = el('div.space-y-4');
      aside.appendChild(U.card('Rappels de facturation', el('div.space-y-3', null, [
        K.note('<strong>RG-02</strong> — Les médicaments sont facturés au <strong>prix d’achat, sans marge</strong>. Les actes et analyses suivent le référentiel tarifaire de la clinique.', { tone: 'info' }),
        K.note('<strong>RG-09</strong> — La prise en charge par une compagnie d’assurance n’est appliquée que si la carte est valide au moment de la facturation.', { tone: 'warning', icon: 'shield-alert' }),
      ])));
      aside.appendChild(U.card('Enchaînement du parcours', U.timeline([
        { title: 'Accueil', detail: 'Création ou recherche du dossier (M1)', date: 'Étape 1', tone: 'success' },
        { title: 'Consultation', detail: 'Diagnostic et prescription (M2)', date: 'Étape 2', tone: 'navy' },
        { title: 'Analyses / Pharmacie', detail: 'Demande laboratoire (M5), dispensation (M6)', date: 'Étape 3', tone: 'info' },
        { title: 'Facturation', detail: 'Facture normalisée MECeF (M8)', date: 'Étape 4', tone: 'warning' },
        { title: 'Comptabilité', detail: 'Écriture automatique SYSCOHADA (M12)', date: 'Étape 5', tone: 'neutral' },
      ])));
      host.appendChild(aside);
      root.appendChild(host);
      return null;
    },
  });

  /* ==========================================================================
   * ORDONNANCES
   * ======================================================================== */
  /* ==========================================================================
   * PATHOLOGIES & MORBIDITÉ
   * --------------------------------------------------------------------------
   * Le référentiel que la consultation consomme, et le tableau qu'il permet.
   * C'est cette seconde partie qui justifie la première : sans code, on ne
   * compte rien, et la clinique ne sait pas ce qu'elle traite.
   *
   * Le classement suit les grands chapitres de la CIM-10 SANS en reprendre la
   * codification : la clinique ne code pas en CIM, et lui imposer une
   * nomenclature qu'elle n'emploie pas ferait saisir n'importe quoi.
   * ======================================================================== */
  global.SIGH.screen('m2-pathologies', {
    title: 'Pathologies & morbidité',
    description: 'Référentiel des pathologies de la clinique et tableau de morbidité issu des consultations.',
    regle: 'La <strong>pathologie</strong> est un code que la clinique compte ; le <strong>diagnostic</strong> est '
      + 'la phrase que le médecin rédige. Les deux coexistent sur la consultation — n’avoir que le second '
      + 'rendrait toute statistique impossible. La liste est <strong>administrable</strong> : c’est le tableau '
      + 'de morbidité qui doit la faire évoluer, pas une mise à jour du logiciel. '
      + 'Les libellés proposés restent <strong>à arrêter par le Directeur Médical</strong>.',
    render: function (root) {
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      afficher();
      return null;

      function col() {
        return S.collection('pathologies', { module: 'M2', entite: 'pathologie', prefix: 'PATH' });
      }

      function consultations() {
        return S.collection('consultations').active();
      }

      /** Le nombre de cas par code, sur l'ensemble des consultations. */
      function comptage() {
        var out = {};
        consultations().forEach(function (c) {
          (c.pathologies || []).forEach(function (code) {
            out[code] = (out[code] || 0) + 1;
          });
        });
        return out;
      }

      function afficher() {
        var rows = col().active();
        var cas = comptage();
        var totalCas = Object.keys(cas).reduce(function (n, k) { return n + cas[k]; }, 0);
        var notifiables = rows.filter(function (x) { return x.notifiable; });
        var casNotifiables = notifiables.reduce(function (n, x) { return n + (cas[x.code] || 0); }, 0);

        C.clear(vue);
        vue.appendChild(U.kpiGrid([
          { label: 'Pathologies au référentiel', value: C.num(rows.length), icon: 'list', tone: 'navy' },
          { label: 'Chapitres couverts', value: C.num(D.CHAPITRES_PATHOLOGIE.length), icon: 'layers', tone: 'info' },
          { label: 'Cas enregistrés', value: C.num(totalCas), icon: 'activity', tone: 'success',
            hint: 'sur ' + C.num(consultations().length) + ' consultations' },
          {
            label: 'Cas à déclaration obligatoire', value: C.num(casNotifiables),
            icon: 'siren', tone: casNotifiables ? 'danger' : 'neutral',
            hint: C.num(notifiables.length) + ' pathologies notifiables',
          },
        ]));

        vue.appendChild(K.note('Une pathologie <strong>notifiable</strong> relève de la déclaration obligatoire aux '
          + 'autorités sanitaires. Le signaler permet de repérer les cas à déclarer sans relire tout le registre — '
          + 'la clinique reste responsable de la déclaration elle-même, que le logiciel ne transmet pas.',
        { tone: 'warning', icon: 'siren' }));

        vue.appendChild(U.tabs([
          { id: 'morbidite', label: 'Tableau de morbidité', badge: Object.keys(cas).length, render: ongletMorbidite },
          { id: 'referentiel', label: 'Référentiel', badge: rows.length, render: ongletReferentiel },
        ]));
        U.icons(vue);
      }

      function ongletMorbidite() {
        var cas = comptage();
        var rows = col().active().map(function (x) {
          var ch = D.CHAPITRES_PATHOLOGIE.filter(function (y) { return y.id === x.chapitre; })[0];
          return Object.assign({}, x, {
            cas: cas[x.code] || 0,
            chapitreLabel: ch ? ch.label : x.chapitre,
          });
        }).filter(function (x) { return x.cas > 0; })
          .sort(function (a, b) { return b.cas - a.cas; });

        if (!rows.length) {
          return U.card('Tableau de morbidité',
            U.empty('Aucun cas rattaché à une pathologie.', {
              icon: 'activity',
              hint: 'Les consultations enregistrées avant la mise en place du référentiel ne portent qu’un '
                + 'diagnostic rédigé : elles ne peuvent pas être comptées rétrospectivement.',
            }));
        }

        var parChapitre = C.groupBy(rows, 'chapitreLabel');
        var bloc = el('div.space-y-4');

        bloc.appendChild(el('div.grid.gap-4.lg\:grid-cols-2', null, [
          U.card('Les pathologies les plus fréquentes',
            K.ranking(rows.slice(0, 12).map(function (x) {
              return { label: x.libelle, value: x.cas, tone: x.notifiable ? 'danger' : 'navy' };
            }), { format: function (v) { return C.num(v) + ' cas'; } })),
          U.card('Répartition par chapitre',
            G.camembert(Object.keys(parChapitre),
              Object.keys(parChapitre).map(function (k) {
                return parChapitre[k].reduce(function (n, x) { return n + x.cas; }, 0);
              }), { height: 300, legend: 'bottom' })),
        ]));

        bloc.appendChild(U.dataTable({
          title: 'Tableau de morbidité', rows: rows, exportName: 'morbidite',
          pageSize: 20, searchable: true, defaultSort: 'cas', defaultDir: 'desc',
          columns: [
            { key: 'code', label: 'Code', nowrap: true, render: function (x) { return el('span.font-mono.text-xs', { text: x.code }); } },
            { key: 'libelle', label: 'Pathologie', render: function (x) { return el('span.font-medium.text-slate-800', { text: x.libelle }); } },
            { key: 'chapitreLabel', label: 'Chapitre' },
            {
              key: 'notifiable', label: 'Déclaration', align: 'right',
              text: function (x) { return x.notifiable ? 'obligatoire' : ''; },
              render: function (x) { return x.notifiable ? U.badge('Obligatoire', 'danger') : el('span.text-xs.text-slate-300', { text: '—' }); },
            },
            { key: 'cas', label: 'Cas', align: 'right', render: function (x) { return el('span.font-semibold', { text: C.num(x.cas) }); } },
          ],
          actions: [K.btn('Imprimer le tableau', { size: 'sm', icon: 'printer', onclick: function () { imprimer(rows); } })],
        }));
        return bloc;
      }

      function ongletReferentiel() {
        var cas = comptage();
        var rows = col().active().map(function (x) {
          var ch = D.CHAPITRES_PATHOLOGIE.filter(function (y) { return y.id === x.chapitre; })[0];
          return Object.assign({}, x, { cas: cas[x.code] || 0, chapitreLabel: ch ? ch.label : x.chapitre });
        });

        return U.dataTable({
          title: 'Référentiel des pathologies', rows: rows, exportName: 'pathologies',
          pageSize: 25, searchable: true, defaultSort: 'chapitreLabel',
          filters: [
            {
              name: 'chapitre', label: 'Chapitre',
              options: D.CHAPITRES_PATHOLOGIE.map(function (x) { return { value: x.id, label: x.label }; }),
            },
            {
              name: 'notifiable', label: 'Déclaration obligatoire',
              options: [{ value: 'oui', label: 'Notifiable' }, { value: 'non', label: 'Non notifiable' }],
              match: function (r, v) { return v === 'oui' ? !!r.notifiable : !r.notifiable; },
            },
          ],
          columns: [
            { key: 'code', label: 'Code', nowrap: true, render: function (x) { return el('span.font-mono.text-xs', { text: x.code }); } },
            { key: 'libelle', label: 'Pathologie' },
            { key: 'chapitreLabel', label: 'Chapitre', render: function (x) { return U.badge(x.chapitreLabel, 'navy'); } },
            {
              key: 'notifiable', label: 'Déclaration',
              text: function (x) { return x.notifiable ? 'obligatoire' : ''; },
              render: function (x) { return x.notifiable ? U.badge('Obligatoire', 'danger') : el('span.text-xs.text-slate-300', { text: '—' }); },
            },
            { key: 'cas', label: 'Cas enregistrés', align: 'right' },
            {
              key: 'aValider', label: 'Provenance', align: 'right',
              text: function (x) { return x.aValider ? 'à valider' : 'arrêtée'; },
              render: function (x) {
                return x.aValider ? U.badge('À valider', 'warning') : U.badge('Arrêtée', 'success');
              },
            },
          ],
          actions: [K.creer(col(), champs(), {
            module: 'M2', label: 'Nouvelle pathologie', titre: 'Nouvelle pathologie', entite: 'Pathologie',
            defauts: function () { return { chapitre: 'autres', notifiable: false }; },
            transform: function (v) {
              v.notifiable = !!v.notifiable;
              v.aValider = true;
              v.source = 'Ajoutée dans l’application le ' + C.dateFR(AUJ) + ' — à arrêter par le Directeur Médical';
              return v;
            },
            apres: afficher,
          })].filter(Boolean),
          rowActions: K.actionsLigne(col(), champs(), { module: 'M2', refresh: afficher }),
        });
      }

      function champs() {
        return [
          { name: 'code', label: 'Code', type: 'text', required: true, hint: 'Court, stable — il sert au comptage.' },
          { name: 'libelle', label: 'Intitulé de la pathologie', type: 'text', required: true, col: 'full' },
          {
            name: 'chapitre', label: 'Chapitre', type: 'select', required: true,
            options: D.CHAPITRES_PATHOLOGIE.map(function (x) { return { value: x.id, label: x.label }; }),
          },
          {
            name: 'notifiable', label: 'Déclaration obligatoire', type: 'checkbox',
            hint: 'Pathologie à déclarer aux autorités sanitaires. Le logiciel la signale ; il ne la transmet pas.',
          },
        ];
      }

      function imprimer(rows) {
        var total = rows.reduce(function (n, x) { return n + x.cas; }, 0);
        P.etat({
          titre: 'Tableau de morbidité',
          sousTitre: 'Consultations enregistrées — situation au ' + C.dateFR(AUJ),
          cartouche: [['Pathologies rencontrées', C.num(rows.length)],
            ['Cas totaux', C.num(total)],
            ['Dont à déclaration obligatoire',
              C.num(rows.filter(function (x) { return x.notifiable; }).reduce(function (n, x) { return n + x.cas; }, 0))],
            ['Établi par', S.currentUser()], ['Date d’édition', C.dateFR(AUJ)]],
          contenu: el('div.space-y-3', null, [
            P.tableau([
              { label: 'Code', key: 'code' },
              { label: 'Pathologie', key: 'libelle' },
              { label: 'Chapitre', key: 'chapitreLabel' },
              { label: 'Déclaration', value: function (x) { return x.notifiable ? 'Obligatoire' : ''; } },
              {
                label: 'Cas', align: 'right',
                value: function (x) { return C.num(x.cas); },
                somme: function (x) { return x.cas; },
                /* Des cas ne sont pas des francs : le pied se formate en
                   nombre, sinon le total du tableau de morbidité s’imprimerait
                   en FCFA. */
                formatTotal: function (v) { return C.num(v); },
              },
              {
                /* `key` sert ici au PIED, pas aux cellules : `value` l’emporte
                   pour les lignes, mais c’est par `key` que la mention de pied
                   ci-dessous retrouve sa colonne. */
                label: 'Part', align: 'right', key: 'part',
                value: function (x) { return total ? Math.round(x.cas / total * 1000) / 10 + ' %' : ''; },
              },
            ], rows, {
              /* La part vaut 100 % par construction ; on la laisse au pied
                 comme mention, elle n’est pas une somme. */
              total: { part: '100 %' }, totalLabel: 'TOTAL',
            }),
            el('p.mt-3.text-\[10px\].italic', {
              text: 'Le comptage porte sur les pathologies codées à la consultation. Les consultations '
                + 'antérieures à la mise en place du référentiel ne portent qu’un diagnostic rédigé et ne '
                + 'peuvent pas être comptées rétrospectivement. Les pathologies à déclaration obligatoire '
                + 'sont signalées ; leur déclaration aux autorités sanitaires relève de la clinique.',
            }),
          ]),
          signatures: [{ role: 'Le Directeur Médical', nom: 'BASSONGUI Chabi Séko' },
            { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
        });
      }
    },
  });

  global.SIGH.screen('m2-ordonnances', {
    title: 'Ordonnances',
    description: 'Prescriptions émises, suivi de leur dispensation en pharmacie et réédition.',
    regle: 'Prescrire engage <strong>quatre services d’un seul geste</strong> : la demande d’analyse part au laboratoire, '
      + 'les médicaments sont annoncés à la pharmacie, la facture attend à la caisse. '
      + 'Rien n’est délivré ni prélevé avant l’encaissement. <strong>RG-02</strong> — médicaments au prix d’achat, sans marge.',
    actions: function () {
      return [
        K.btn('File d’attente caisse', { icon: 'coins', onclick: function () { global.SIGH.app.go('m8-caisse'); } }),
        K.btn('Demandes d’analyses', { icon: 'flask-conical', onclick: function () { global.SIGH.app.go('m5-demandes'); } }),
        K.commande('Nouvelle ordonnance', {
          variant: 'primary', icon: 'file-plus',
          onclick: function () { formulairePrescription(); },
        }),
      ];
    },
    render: function (root) {
      amorcerOrdonnances();
      dessiner();
      return null;

      function dessiner() {
        C.clear(root);
        var col = S.collection('ordonnances');
        var rows = col.active();
        var host = el('div.space-y-4');

        host.appendChild(U.kpiGrid([
          { label: 'Ordonnances émises', value: C.num(rows.length), icon: 'file-text', tone: 'navy' },
          {
            label: 'En attente d’encaissement',
            value: C.num(rows.filter(function (r) { return r.statutPaiement !== 'soldee'; }).length),
            icon: 'coins', tone: 'warning',
          },
          {
            label: 'À délivrer en pharmacie',
            value: C.num(rows.filter(function (r) { return r.statutDispensation === 'en_attente'; }).length),
            icon: 'pill', tone: 'info',
          },
          { label: 'Valeur prescrite', value: C.money(C.sum(rows, 'montant')), icon: 'coins', tone: 'success', hint: 'Au prix d’achat (RG-02)' },
        ]));

        host.appendChild(U.dataTable({
          title: 'Ordonnances', rows: rows, exportName: 'ordonnances', pageSize: 12,
          defaultSort: 'date', defaultDir: 'desc',
          filters: [
            {
              name: 'statutDispensation', label: 'Dispensation',
              options: [{ value: 'en_attente', label: 'À délivrer' }, { value: 'servie', label: 'Servie' },
                { value: 'sans_objet', label: 'Sans médicament' }],
            },
            {
              name: 'statutPaiement', label: 'Règlement',
              options: [{ value: 'impayee', label: 'Impayée' }, { value: 'soldee', label: 'Réglée' }],
            },
          ],
          actions: [K.commande('Nouvelle ordonnance', { variant: 'primary', size: 'sm', icon: 'plus', onclick: function () { formulairePrescription(); } })],
          columns: [
            {
              key: 'numero', label: 'N° ordonnance', nowrap: true,
              render: function (r) {
                return el('div', null, [
                  el('span.font-mono.text-xs', { text: r.numero }),
                  r.urgent ? el('span.ml-1', null, U.badge('Urgent', 'danger')) : null,
                ]);
              },
            },
            { key: 'date', label: 'Date', nowrap: true, text: function (r) { return C.dateFR(r.date); }, render: function (r) { return C.dateFR(r.date); } },
            colPatient,
            { key: 'medecin', label: 'Prescripteur' },
            {
              key: 'lignes', label: 'Contenu',
              value: function (r) { return (r.medicaments || []).length + (r.analyses || []).length + (r.actes || []).length; },
              render: function (r) {
                var t = [];
                if ((r.medicaments || []).length) t.push(U.badge(r.medicaments.length + ' médic.', 'info'));
                if ((r.analyses || []).length) t.push(U.badge(r.analyses.length + ' analyse(s)', 'navy'));
                if ((r.actes || []).length) t.push(U.badge(r.actes.length + ' acte(s)', 'neutral'));
                return el('div.flex.flex-wrap.gap-1', null, t);
              },
            },
            { key: 'montant', label: 'Montant', align: 'right', text: function (r) { return C.money(r.montant, false); }, render: function (r) { return C.money(r.montant, false); } },
            {
              key: 'statutPaiement', label: 'Caisse',
              render: function (r) {
                return r.statutPaiement === 'soldee' ? U.badge('Réglée', 'success') : U.badge('À encaisser', 'warning');
              },
            },
            {
              key: 'statutDispensation', label: 'Pharmacie',
              render: function (r) {
                var m = { servie: ['Servie', 'success'], en_attente: ['À délivrer', 'warning'], sans_objet: ['—', 'neutral'] };
                var s = m[r.statutDispensation] || m.sans_objet;
                return U.badge(s[0], s[1]);
              },
            },
          ],
          onRowClick: ouvrirDossier,
          rowActions: function (r) {
            return [
              K.iconBtn('printer', 'Imprimer', function () { etatOrdonnance(r); }),
              K.iconBtn('eye', 'Suivre le parcours', function () { ouvrirDossier(r); }),
            ];
          },
        }));

        root.appendChild(host);
        U.icons(root);
      }

      /* --- Le parcours complet d'une ordonnance, pièce par pièce ----------- */
      function ouvrirDossier(r) {
        var d = PR.dossier(r.id) || { ordonnance: r, demandes: [], mouvements: [], taches: [] };
        var corps = el('div.space-y-4');

        corps.appendChild(U.descList([
          ['Patient', r.patient], ['Dossier', r.patientCode], ['Prescripteur', r.medecin],
          ['Diagnostic', r.diagnostic || '—'], ['Date', C.dateFR(r.date)],
          ['Facture', d.facture ? d.facture.numero : '—'],
        ]));

        if ((r.medicaments || []).length) {
          corps.appendChild(U.card('Médicaments prescrits', K.miniTable([
            { label: 'Produit', key: 'produit' },
            { label: 'Posologie', key: 'posologie' },
            { label: 'Quantité', align: 'right', render: function (l) { return l.quantite + ' ' + (l.unite || ''); } },
            { label: 'Montant', align: 'right', render: function (l) { return C.money(l.total, false); } },
          ], r.medicaments)));
        }
        if ((r.analyses || []).length) {
          corps.appendChild(U.card('Analyses demandées', K.miniTable([
            { label: 'Analyse', key: 'designation' },
            { label: 'Échantillon', key: 'echantillon' },
            {
              label: 'État', render: function (l) {
                var dem = d.demandes.filter(function (x) { return x.analyseCode === l.code; })[0];
                if (!dem) return '—';
                return dem.bloqueParPaiement ? U.badge('Attente caisse', 'warning') : U.statut(dem.etatAnalyse);
              },
            },
            { label: 'Tarif', align: 'right', render: function (l) { return C.money(l.prix, false); } },
          ], r.analyses)));
        }
        if ((r.actes || []).length) {
          corps.appendChild(U.card('Actes prescrits', K.miniTable([
            { label: 'Acte', key: 'libelle' },
            { label: 'Secteur', key: 'secteur' },
            {
              label: 'Tarif', align: 'right',
              render: function (l) {
                return l.prix ? C.money(l.prix, false) : el('span.text-warning-600', { text: 'à valider' });
              },
            },
          ], r.actes)));
        }

        corps.appendChild(U.card('Suivi inter-modules', U.timeline(etapes(d))));

        U.drawer({
          title: r.numero, subtitle: r.patient + ' — ' + C.dateFR(r.date),
          width: 'max-w-3xl',
          body: corps,
          footer: [K.btn('Imprimer l’ordonnance', { variant: 'primary', icon: 'printer', onclick: function () { etatOrdonnance(r); } })],
        });
      }

      function etapes(d) {
        var o = d.ordonnance, out = [];
        out.push({ date: C.dateFR(o.date), titre: 'Prescription établie',
          detail: 'Par ' + o.medecin + ' — ' + C.money(o.montant, false), tone: 'success' });
        if (d.demandes.length) {
          out.push({ date: C.dateFR(o.date), titre: d.demandes.length + ' demande(s) d’analyse créée(s) d’office',
            detail: 'Transmises au laboratoire — module M5', tone: 'info' });
        }
        out.push({
          date: o.statutPaiement === 'soldee' ? C.dateFR(o.date) : '—',
          titre: o.statutPaiement === 'soldee' ? 'Encaissement validé par la caisse' : 'En attente d’encaissement',
          detail: d.facture ? d.facture.numero + ' — ' + C.money(d.facture.partPatient, false) + ' à la charge du patient' : '—',
          tone: o.statutPaiement === 'soldee' ? 'success' : 'warning',
        });
        if (o.statutDispensation !== 'sans_objet') {
          out.push({
            date: o.dispenseLe ? C.dateFR(o.dispenseLe) : '—',
            titre: o.statutDispensation === 'servie' ? 'Médicaments délivrés' : 'Délivrance en attente',
            detail: o.statutDispensation === 'servie'
              ? d.mouvements.length + ' sortie(s) de stock — justificatif ' + o.numero
              : 'La pharmacie ne peut servir qu’après encaissement (RG-03)',
            tone: o.statutDispensation === 'servie' ? 'success' : 'warning',
          });
        }
        return out;
      }

      /* --- Modal de prescription ------------------------------------------ */
      function formulairePrescription() {
        var lignes = [];
        var corps = el('div.space-y-4');

        var entete = U.form([
          { name: 'patientCode', label: 'Dossier patient', type: 'select', required: true, options: optionsPatients(), col: 'full' },
          { name: 'medecin', label: 'Médecin prescripteur', type: 'select', required: true, options: optionsMedecins() },
          { name: 'date', label: 'Date et heure', type: 'datetime-local', required: true, value: new Date().toISOString().slice(0, 16) },
          { name: 'diagnostic', label: 'Diagnostic', col: 'full' },
          { name: 'urgent', label: 'Prescription urgente' },
        ].map(function (f) { return f.name === 'urgent' ? Object.assign({ type: 'checkbox' }, f) : f; }), {});
        corps.appendChild(U.card('Patient et prescripteur', entete));

        /* Médicaments : autant de lignes que nécessaire. */
        var hoteLignes = el('div.space-y-2');
        var cartMed = U.card('Médicaments', el('div.space-y-3', null, [
          hoteLignes,
          K.btn('Ajouter un médicament', { size: 'sm', icon: 'plus', onclick: function () { ajouterLigne(); } }),
        ]));
        corps.appendChild(cartMed);

        /* Analyses et actes : sélection multiple sur le catalogue complet. */
        var complements = U.form([
          {
            name: 'analyses', label: 'Analyses de laboratoire', type: 'multiselect', col: 'full',
            options: D.ANALYSES.map(function (a) {
              return { value: a.code, label: a.designation, detail: a.categorie + ' · ' + C.money(a.prix, false) };
            }),
            help: 'Chaque analyse cochée engendre sa demande au laboratoire, sans ressaisie.',
          },
          {
            name: 'actes', label: 'Actes et soins', type: 'multiselect', col: 'full',
            options: optionsActes(),
            help: 'Catalogue des activités par secteur — document « Répartition des activités » de la clinique.',
          },
        ], {});
        corps.appendChild(U.card('Analyses et actes', complements));

        var total = el('p.text-sm.font-semibold.text-slate-800');
        var pied = el('div.flex.items-center.justify-between.gap-3', null, [
          el('div', null, [
            el('p.text-xs.text-slate-500', { text: 'Total de la prescription' }),
            total,
          ]),
        ]);
        corps.appendChild(U.card('Récapitulatif', pied));

        ajouterLigne();
        recalculer();
        complements.addEventListener('change', recalculer);

        var m = U.modal({
          title: 'Nouvelle ordonnance', size: 'xl', body: corps,
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Prescrire et transmettre', { variant: 'primary', icon: 'send', onclick: valider }),
          ],
        });

        function ajouterLigne() {
          var ligne = el('div.grid.grid-cols-1.gap-2.rounded-lg.border.border-slate-200.p-2.sm\\:grid-cols-12');
          var produit = U.combo(optionsProduits(), { placeholder: '— Médicament —' });
          var qte = el('input.input', { type: 'number', min: 1, value: 1, 'aria-label': 'Quantité' });
          var poso = el('input.input', { type: 'text', placeholder: 'Posologie (ex. 1 cp × 3/j)', 'aria-label': 'Posologie' });
          var duree = el('input.input', { type: 'text', placeholder: 'Durée', 'aria-label': 'Durée' });
          var sup = K.iconBtn('trash-2', 'Retirer la ligne', function () {
            var i = lignes.indexOf(ref); if (i >= 0) lignes.splice(i, 1);
            if (produit.destroy) produit.destroy();
            ligne.remove(); recalculer();
          });
          ligne.appendChild(el('div.sm\\:col-span-5', null, produit));
          ligne.appendChild(el('div.sm\\:col-span-1', null, qte));
          ligne.appendChild(el('div.sm\\:col-span-3', null, poso));
          ligne.appendChild(el('div.sm\\:col-span-2', null, duree));
          ligne.appendChild(el('div.sm\\:col-span-1.flex.items-center.justify-end', null, sup));
          var ref = { produit: produit, qte: qte, poso: poso, duree: duree };
          lignes.push(ref);
          produit.addEventListener('change', recalculer);
          qte.addEventListener('input', recalculer);
          hoteLignes.appendChild(ligne);
          U.icons(ligne);
        }

        function collecterMedicaments() {
          return lignes.map(function (l) {
            return { produitId: l.produit.value, quantite: Number(l.qte.value) || 0, posologie: l.poso.value, duree: l.duree.value };
          }).filter(function (l) { return l.produitId && l.quantite > 0; });
        }

        function recalculer() {
          var med = collecterMedicaments();
          var mMed = C.sum(med, function (l) {
            var p = S.collection('produits').get(l.produitId);
            return (p ? p.prixAchat : 0) * l.quantite;
          });
          var ctrl = complements.controls;
          var mAna = C.sum(ctrl.analyses.value || [], function (code) {
            var a = D.ANALYSES.filter(function (x) { return x.code === code; })[0];
            return a ? a.prix : 0;
          });
          var mAct = C.sum(ctrl.actes.value || [], function (code) {
            var a = S.collection('actes').active().filter(function (x) { return x.code === code; })[0];
            return (a && a.prix) || 0;
          });
          total.textContent = C.money(mMed + mAna + mAct)
            + '  (médicaments ' + C.money(mMed, false) + ' · analyses ' + C.money(mAna, false) + ' · actes ' + C.money(mAct, false) + ')';
        }

        function valider() {
          var v = entete.collect();
          if (!v) return;
          var comp = complements.collect() || {};
          var med = collecterMedicaments();
          if (!med.length && !(comp.analyses || []).length && !(comp.actes || []).length) {
            U.toast('Une ordonnance doit porter au moins un médicament, une analyse ou un acte.', { type: 'warning' });
            return;
          }
          var res;
          try {
            res = PR.prescrire({
              patientCode: v.patientCode, medecin: v.medecin, diagnostic: v.diagnostic,
              date: v.date ? new Date(v.date).toISOString() : null, urgent: !!v.urgent,
              medicaments: med, analyses: comp.analyses || [], actes: comp.actes || [],
            });
          } catch (e) {
            U.toast('Prescription impossible : ' + e.message, { type: 'error' });
            return;
          }
          m.close();
          var envois = [];
          if (res.demandes.length) envois.push(res.demandes.length + ' demande(s) au laboratoire');
          if (med.length) envois.push('pharmacie informée');
          envois.push('facture ' + res.facture.numero + ' en attente à la caisse');
          U.toast('Ordonnance ' + res.ordonnance.numero + ' transmise.', {
            type: 'success', detail: envois.join(' · '), duration: 7000,
          });
          dessiner();
        }
      }

      /* Une seule fonction d'impression pour les deux écrans : deux copies
         auraient divergé au premier changement de maquette. */
      function etatOrdonnance(r) { etatOrdonnanceMedicale(r); }

      function etatOrdonnanceAncienne(r) {
        var lignes = (r.medicaments || []).map(function (l) {
          return { produit: l.produit, detail: l.posologie || '', quantite: l.quantite + ' ' + (l.unite || ''), prix: l.prix, total: l.total };
        });
        P.etat({
          titre: 'Ordonnance médicale',
          sousTitre: r.numero,
          cartouche: [['Patient', r.patient], ['Dossier', r.patientCode], ['Date', C.dateFR(r.date)],
            ['Prescripteur', r.medecin], ['Diagnostic', r.diagnostic || '—'],
            ['Règlement', r.statutPaiement === 'soldee' ? 'Réglée' : 'En attente']],
          contenu: [
            lignes.length ? P.tableau([
              { label: 'Désignation', key: 'produit' },
              { label: 'Posologie', key: 'detail' },
              { label: 'Quantité', align: 'right', key: 'quantite' },
              { label: 'Prix unitaire', align: 'right', value: function (l) { return C.money(l.prix, false); } },
              {
                label: 'Montant', align: 'right',
                value: function (l) { return C.money(l.total, false); },
                somme: function (l) { return l.total; },
              },
            ], lignes, { total: true }) : null,
            (r.analyses || []).length ? P.tableau([
              { label: 'Analyse demandée', key: 'designation' },
              { label: 'Échantillon', key: 'echantillon' },
              { label: 'Délai', key: 'delai' },
              { label: 'Tarif', align: 'right', value: function (l) { return C.money(l.prix, false); },
                somme: function (l) { return l.prix || 0; } },
            ], r.analyses, { total: true }) : null,
            (r.actes || []).length ? P.tableau([
              { label: 'Acte prescrit', key: 'libelle' },
              { label: 'Secteur', key: 'secteur' },
              { label: 'Tarif', align: 'right', value: function (l) { return l.prix ? C.money(l.prix, false) : 'à valider'; },
                somme: function (l) { return l.prix || 0; } },
            ], r.actes, { total: true }) : null,
          ],
          signatures: [{ role: 'Le Médecin prescripteur', nom: r.medecin, mention: 'Signature et cachet' },
            { role: 'Le Pharmacien', mention: 'Dispensation' }],
        });
      }
    },
  });

  /* Historique : les ordonnances antérieures sont reconstituées une seule fois
     depuis les consultations terminées, puis vivent leur vie dans la collection.
     Elles arrivent réglées et servies — elles ne doivent pas encombrer les files
     d'attente du jour. */
  function amorcerOrdonnances() {
    var db = S.raw();
    if (db.ordonnances && db.ordonnances.length) return;
    var cons = S.collection('consultations').active().filter(function (c) { return c.statut === 'terminee'; });
    var prods = S.collection('produits').active().filter(function (p) { return p.categorie === 'medicament'; });
    var rnd = C.seeded(97);
    db.ordonnances = cons.slice(0, 120).map(function (c, i) {
      var med = [];
      var nb = C.between(rnd, 1, 4);
      for (var k = 0; k < nb; k++) {
        var p = C.pick(rnd, prods);
        var q = C.between(rnd, 1, 20);
        med.push({ produitId: p.id, produit: p.designation, unite: p.unite, quantite: q,
          posologie: '', duree: '', prix: p.prixAchat, total: p.prixAchat * q });
      }
      var montant = C.sum(med, 'total');
      return {
        id: 'ORD' + C.pad(i + 1, 4), statut: 'actif',
        numero: 'ORD-2026-' + C.pad(i + 1, 5),
        date: c.date, patientId: c.patientId, patientCode: c.patientCode, patient: c.patient,
        medecin: c.medecin, diagnostic: c.diagnostic, consultationId: c.id,
        medicaments: med, analyses: [], actes: [],
        montantMedicaments: montant, montantAnalyses: 0, montantActes: 0, montant: montant,
        urgent: false,
        statutPaiement: 'soldee',
        statutDispensation: C.pick(rnd, ['servie', 'servie', 'servie', 'en_attente']),
        statutAnalyses: 'sans_objet', statutActes: 'sans_objet',
      };
    });
    S.save();
  }

  function optionsProduits() {
    return S.collection('produits').active()
      .filter(function (p) { return p.categorie === 'medicament' || p.categorie === 'conso_medical'; })
      .map(function (p) {
        return {
          value: p.id, label: p.designation,
          detail: C.money(p.prixAchat, false) + ' · stock ' + (p.stockDetail != null ? p.stockDetail : p.stock) + ' ' + (p.unite || ''),
        };
      });
  }
  /* ==========================================================================
   * CONSULTATIONS & SOINS À DOMICILE
   * ======================================================================== */
  global.SIGH.screen('m2-domicile', {
    title: 'Consultations & soins à domicile',
    description: 'Planification, réalisation et facturation spécifique des prestations réalisées au domicile du patient.',
    regle: 'La facturation à domicile applique un <strong>coût additionnel de déplacement</strong> qui s’ajoute au prix des actes, analyses et médicaments (CDCT §10.5). La facture normalisée est délivrée après règlement.',
    render: K.crud({
      collection: 'consultations', entite: 'intervention à domicile', entiteP: 'interventions à domicile', module: 'M2',
      defaultSort: 'date', defaultDir: 'desc', formSize: 'lg',
      columns: [
        colDate(), colPatient,
        { key: 'motif', label: 'Prestation' },
        { key: 'medecin', label: 'Intervenant' },
        { key: 'tarif', label: 'Montant', align: 'right', text: function (r) { return C.money(r.tarif || 0, false); }, render: function (r) { return C.money(r.tarif || 0, false); } },
        { key: 'statut', label: 'Statut', render: function (r) { return U.statut(r.statut); } },
      ],
      fields: function () {
        return champsConsultation().concat([
          { name: 'fraisDeplacement', label: 'Frais de déplacement (FCFA)', type: 'money', value: 5000, help: 'Coût additionnel propre aux prestations à domicile.' },
          { name: 'adresseIntervention', label: 'Adresse d’intervention', col: 'full' },
        ]);
      },
      transform: function (v) { v.type = 'Domicile'; return completerPatient(v); },
      onCreate: function () { return { type: 'Domicile', statut: 'planifiee', tarif: 10000, fraisDeplacement: 5000 }; },
      /* On restreint l'affichage aux interventions à domicile. */
      intro: function () {
        return K.note('Cet écran ne présente que les prestations de type <strong>Domicile</strong>. Les consultations réalisées à la clinique sont gérées depuis l’écran « Consultations ».', { tone: 'info' });
      },
      kpis: function (rows) {
        var dom = rows.filter(function (r) { return r.type === 'Domicile'; });
        return [
          { label: 'Interventions à domicile', value: C.num(dom.length), icon: 'house-plus', tone: 'navy' },
          { label: 'Planifiées', value: C.num(dom.filter(function (r) { return r.statut === 'planifiee'; }).length), icon: 'calendar-clock', tone: 'warning' },
          { label: 'Réalisées', value: C.num(dom.filter(function (r) { return r.statut === 'terminee'; }).length), icon: 'check-circle-2', tone: 'success' },
          { label: 'Recette domicile', value: C.money(C.sum(dom, 'tarif')), icon: 'coins', tone: 'info' },
        ];
      },
      detail: detail, etat: etatConsultation,
    }),
  });

  /* ==========================================================================
   * REGISTRE DES APPELS
   * ======================================================================== */
  global.SIGH.screen('m2-registre-appels', {
    title: 'Registre des appels',
    description: 'Appels entrants et sortants liés à la prise de rendez-vous, aux résultats et au suivi des patients.',
    render: K.registre({
      collection: 'appels', entite: 'appel', entiteP: 'appels', module: 'M2',
      defaultSort: 'dateHeure', defaultDir: 'desc', pageSize: 15,
      source: 'Registre tenu au standard de la clinique.',
      seed: function () {
        var rnd = C.seeded(131);
        var pats = S.collection('patients').active();
        var out = [];
        for (var i = 0; i < 90; i++) {
          var p = C.pick(rnd, pats);
          var d = C.addDays(AUJ, -C.between(rnd, 0, 45));
          d.setHours(C.between(rnd, 7, 19), C.between(rnd, 0, 59));
          out.push({
            id: 'APL' + C.pad(i + 1, 4),
            reference: 'A' + C.pad(i + 1, 5),
            dateHeure: d.toISOString(),
            sens: rnd() > 0.4 ? 'entrant' : 'sortant',
            interlocuteur: p.nom + ' ' + p.prenom,
            telephone: p.telephone,
            objet: C.pick(rnd, OBJETS_APPEL),
            agent: C.pick(rnd, ['OROU YO Edmond', 'Secrétaire médicale', 'Caisse']),
            suite: C.pick(rnd, ['Rendez-vous fixé', 'Information donnée', 'Rappel à programmer', 'Transféré au médecin', 'Sans suite']),
            statut: 'actif',
          });
        }
        return C.sortBy(out, 'dateHeure', 'desc');
      },
      columns: [
        { key: 'reference', label: 'N°', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.reference }); } },
        {
          key: 'dateHeure', label: 'Date et heure', nowrap: true,
          text: function (r) { return C.dateHeure(r.dateHeure); },
          render: function (r) { return C.dateHeure(r.dateHeure); },
          sortValue: function (r) { return C.toDate(r.dateHeure).getTime(); },
        },
        {
          key: 'sens', label: 'Sens',
          render: function (r) { return U.badge(r.sens === 'entrant' ? 'Entrant' : 'Sortant', r.sens === 'entrant' ? 'info' : 'success'); },
        },
        { key: 'interlocuteur', label: 'Interlocuteur' },
        { key: 'telephone', label: 'Téléphone', nowrap: true },
        { key: 'objet', label: 'Objet' },
        { key: 'agent', label: 'Traité par' },
        { key: 'suite', label: 'Suite donnée' },
      ],
      filters: [
        { name: 'sens', label: 'Sens', options: [{ value: 'entrant', label: 'Entrant' }, { value: 'sortant', label: 'Sortant' }] },
        { name: 'objet', label: 'Objet', options: OBJETS_APPEL },
      ],
      fields: [
        { name: 'dateHeure', label: 'Date et heure', type: 'datetime-local', required: true },
        {
          name: 'sens', label: 'Sens de l’appel', type: 'select', required: true,
          options: [{ value: 'entrant', label: 'Entrant' }, { value: 'sortant', label: 'Sortant' }],
        },
        { name: 'interlocuteur', label: 'Interlocuteur', required: true },
        { name: 'telephone', label: 'Téléphone', type: 'tel' },
        { name: 'objet', label: 'Objet de l’appel', type: 'select', required: true, options: OBJETS_APPEL, col: 'full' },
        { name: 'agent', label: 'Traité par', required: true },
        {
          name: 'suite', label: 'Suite donnée', type: 'select',
          options: ['Rendez-vous fixé', 'Information donnée', 'Rappel à programmer', 'Transféré au médecin', 'Sans suite'],
        },
        { name: 'observations', label: 'Observations', type: 'textarea', rows: 2, col: 'full' },
      ],
      onCreate: function () {
        return { dateHeure: new Date(2026, 7, 16, 9, 0).toISOString().slice(0, 16), sens: 'entrant', agent: S.currentUser() };
      },
      kpis: function (rows) {
        return [
          { label: 'Appels enregistrés', value: C.num(rows.length), icon: 'phone', tone: 'navy' },
          { label: 'Entrants', value: C.num(rows.filter(function (r) { return r.sens === 'entrant'; }).length), icon: 'phone-incoming', tone: 'info' },
          { label: 'Sortants', value: C.num(rows.filter(function (r) { return r.sens === 'sortant'; }).length), icon: 'phone-outgoing', tone: 'success' },
          { label: 'Rappels à programmer', value: C.num(rows.filter(function (r) { return r.suite === 'Rappel à programmer'; }).length), icon: 'phone-call', tone: 'warning' },
        ];
      },
      detail: function (r) {
        return U.descList([
          ['Référence', r.reference], ['Date et heure', C.dateHeure(r.dateHeure)],
          ['Sens', r.sens === 'entrant' ? 'Entrant' : 'Sortant'],
          ['Interlocuteur', r.interlocuteur], ['Téléphone', r.telephone],
          ['Objet', r.objet], ['Traité par', r.agent], ['Suite donnée', r.suite || '—'],
          ['Observations', r.observations || '—'],
        ]);
      },
    }),
  });

  /* ==========================================================================
   * REGISTRE DES PRESCRIPTIONS — DEUX TYPES, QUATRE ORIGINES
   * --------------------------------------------------------------------------
   * La clinique prescrit deux choses distinctes et depuis quatre endroits :
   *
   *   - l'ORDONNANCE porte des médicaments : elle part à la pharmacie, sort du
   *     stock (RG-03) et se délivre au comptoir ;
   *   - les SOINS portent des actes : ils ne sortent pas du stock, ils sont
   *     ADRESSÉS à un secteur et quelqu'un les exécute, sous son nom.
   *
   * Les confondre rendait invisible tout le travail infirmier — sept
   * infirmiers et trois sages-femmes exécutent des actes que rien ne traçait.
   *
   * Les quatre origines sont consultation, hospitalisation, bloc et maternité.
   * Le prototype ne connaissait que la première.
   * ======================================================================== */
  function colPrescriptions() {
    return S.collection('prescriptions', { module: 'M2', entite: 'prescription', prefix: 'PRS' });
  }
  function colSoignants() {
    return S.collection('soignants', { module: 'M14', entite: 'soignant', prefix: 'SOI' });
  }
  function prescripteurs() {
    return colSoignants().active().filter(function (x) { return x.prescrit; });
  }
  function libelleOrigine(code) {
    var o = (D.ORIGINES_PRESCRIPTION || []).filter(function (x) { return x.code === code; })[0];
    return o ? o.label : (code || '—');
  }
  function libelleSecteur(code) {
    var o = (D.SECTEURS_SOINS || []).filter(function (x) { return x.code === code; })[0];
    if (o) return o.label;
    return code === 'pharmacie' ? 'Pharmacie' : (code || '—');
  }

  global.SIGH.screen('m2-prescriptions', {
    title: 'Prescriptions',
    description: 'Registre unique des prescriptions d’ordonnance et de soins, quelle qu’en soit l’origine.',
    regle: 'Deux prescriptions distinctes : l’<strong>ordonnance</strong> porte des médicaments et sort du stock ; '
      + 'la <strong>prescription de soins</strong> porte des actes et s’adresse à un secteur. '
      + 'Quatre origines : consultation, hospitalisation, bloc et maternité. '
      + 'Seuls <strong>médecins et sages-femmes</strong> prescrivent — le contrôle est au moteur, pas à l’écran.',
    render: function (root) {
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      afficher();
      return null;

      function afficher() {
        var rows = colPrescriptions().active();
        var soins = rows.filter(function (r) { return r.type === 'soins'; });
        var ordo = rows.filter(function (r) { return r.type === 'ordonnance'; });
        var enCours = rows.filter(function (r) { return r.statut === 'en_cours'; });
        var bloquees = rows.filter(function (r) { return r.statutPaiement !== 'payee'; });

        C.clear(vue);
        vue.appendChild(U.kpiGrid([
          { label: 'Prescriptions', value: C.num(rows.length), icon: 'clipboard-plus', tone: 'navy' },
          { label: 'Ordonnances', value: C.num(ordo.length), icon: 'scroll-text', tone: 'info',
            hint: 'médicaments — vers la pharmacie' },
          { label: 'Prescriptions de soins', value: C.num(soins.length), icon: 'hand-heart', tone: 'success',
            hint: 'actes — vers un secteur d’exécution' },
          { label: 'En attente de règlement', value: C.num(bloquees.length), icon: 'lock',
            tone: bloquees.length ? 'warning' : 'neutral', hint: 'exécution bloquée' },
        ]));

        vue.appendChild(K.note('Une prescription non réglée reste <strong>visible mais non exécutable</strong> : '
          + 'l’encaissement la débloque. C’est la même règle que pour la délivrance en pharmacie et pour le '
          + 'laboratoire — le poste voit ce qui l’attend sans pouvoir le servir avant paiement.',
        { tone: 'info', icon: 'lock' }));

        vue.appendChild(U.tabs([
          { id: 'toutes', label: 'Toutes', badge: rows.length, render: function () { return tableau(rows); } },
          { id: 'soins', label: 'Prescriptions de soins', badge: soins.length, render: function () { return tableau(soins); } },
          { id: 'ordonnances', label: 'Ordonnances', badge: ordo.length, render: function () { return tableau(ordo); } },
          { id: 'encours', label: 'En cours', badge: enCours.length, render: function () { return tableau(enCours); } },
        ]));
        U.icons(vue);
      }

      function champs() {
        return [
          { name: 'patientCode', label: 'Patient', type: 'select', required: true, options: optionsPatients() },
          {
            name: 'prescripteurId', label: 'Prescripteur', type: 'select', required: true,
            options: prescripteurs().map(function (x) {
              return { value: x.id, label: x.nomComplet + ' — ' + x.poste };
            }),
            hint: 'Médecins et sages-femmes seulement : l’infirmier n’est pas habilité à prescrire.',
          },
          {
            name: 'origine', label: 'Origine de la prescription', type: 'select', required: true,
            options: (D.ORIGINES_PRESCRIPTION || []).map(function (o) { return { value: o.code, label: o.label }; }),
          },
          {
            name: 'secteurDestinataire', label: 'Secteur destinataire', type: 'select', required: true,
            options: (D.SECTEURS_SOINS || []).map(function (o) { return { value: o.code, label: o.label }; }),
            hint: 'Sans destinataire, la prescription n’apparaîtrait sur aucun poste.',
          },
          {
            name: 'modalite', label: 'Modalité de traitement', type: 'select', required: true,
            options: (D.MODALITES_TRAITEMENT || []).map(function (m) { return { value: m.code, label: m.label }; }),
            hint: 'Ambulatoire : salle de soins seule. Hospitalisation : première administration en salle de soins, '
              + 'les suivantes en hospitalisation.',
          },
          { name: 'indication', label: 'Indication', type: 'textarea', rows: 2 },
          {
            name: 'actes', label: 'Actes prescrits', type: 'multiselect', required: true,
            options: (D.tarifParFamille ? D.tarifParFamille('AMI') : []).map(function (a) {
              return {
                value: a.code,
                label: a.code + ' — ' + a.libelle,
                detail: a.prixNonAssure == null ? 'tarif non renseigné au document'
                  : C.money(a.prixNonAssure) + ' non assuré · ' + C.money(a.prixAssure) + ' assuré',
              };
            }),
          },
          {
            name: 'nbAdministrations', label: 'Nombre d’administrations par acte', type: 'number',
            min: 1, max: 60, value: 1,
            hint: 'C’est ce nombre qui fait vivre le relais : une administration unique ne quitte jamais la salle de soins.',
          },
        ];
      }

      /* La prescription passe OBLIGATOIREMENT par le moteur : c'est lui qui
         refuse un prescripteur non habilité, applique le tarif assuré ou non
         assuré selon RG-09 et notifie le secteur destinataire. K.creer()
         insérerait lui-même et produirait une seconde fiche, vide. On lui
         emprunte donc seulement le contrôle des droits. */
      function nouvelle() {
        if (!K.droits('M2').editer) return null;
        return K.btn('Nouvelle prescription de soins', {
          variant: 'primary', size: 'sm', icon: 'plus',
          onclick: function () {
            var f = U.form(champs(), { modalite: 'ambulatoire', nbAdministrations: 1 });
            var m = U.modal({
              title: 'Prescrire des soins',
              subtitle: 'Les champs marqués d’un astérisque sont obligatoires.',
              size: 'lg', body: f,
              footer: [
                K.btn('Annuler', { onclick: function () { m.close(); } }),
                K.btn('Prescrire', {
                  variant: 'primary', icon: 'plus',
                  onclick: function () {
                    var v = f.collect();
                    if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                    var pres;
                    try {
                      pres = PR.prescrireSoins({
                        patientCode: v.patientCode,
                        prescripteurId: v.prescripteurId,
                        origine: v.origine,
                        secteurDestinataire: v.secteurDestinataire,
                        modalite: v.modalite,
                        indication: v.indication,
                        actes: (v.actes || []).map(function (c) {
                          return { code: c, nbAdministrations: v.nbAdministrations || 1 };
                        }),
                      });
                    } catch (err) {
                      /* Le refus d'habilitation se dit, il ne se tait pas. */
                      U.toast(err.message, { type: 'error' });
                      return;
                    }
                    m.close();
                    afficher();
                    U.toast('Prescription ' + pres.reference + ' enregistrée.', {
                      type: 'success',
                      detail: libelleSecteur(pres.secteurDestinataire) + ' — première administration : '
                        + libelleSecteur(pres.premierAdministrateur),
                      undo: function () { colPrescriptions().archive(pres.id); afficher(); },
                      undoMessage: 'Prescription annulée — la fiche est archivée.',
                    });
                  },
                }),
              ],
            });
          },
        });
      }

      function tableau(rows) {
        return U.dataTable({
          rows: C.sortBy(rows, 'date').reverse(),
          empty: 'Aucune prescription enregistrée.',
          actions: [boutonPrescrire()].filter(Boolean),
          columns: [
            { key: 'reference', label: 'Référence' },
            { key: 'date', label: 'Date', render: function (r) { return C.dateHeure(r.date); } },
            { key: 'patient', label: 'Patient', render: function (r) { return r.patient + ' — ' + r.patientCode; } },
            {
              key: 'type', label: 'Type', render: function (r) {
                return U.badge(r.type === 'soins' ? 'Soins' : 'Ordonnance',
                  r.type === 'soins' ? 'success' : 'info');
              },
            },
            { key: 'origine', label: 'Origine', render: function (r) { return libelleOrigine(r.origine); } },
            { key: 'secteurDestinataire', label: 'Destinataire', render: function (r) { return libelleSecteur(r.secteurDestinataire); } },
            { key: 'prescripteur', label: 'Prescripteur' },
            {
              key: 'montant', label: 'Montant', align: 'right',
              render: function (r) { return C.money(r.montant || 0); },
            },
            {
              key: 'statutPaiement', label: 'Règlement', render: function (r) {
                return r.statutPaiement === 'payee'
                  ? U.badge('Réglée', 'success') : U.badge('Non réglée', 'warning');
              },
            },
          ],
          rowActions: K.actionsLigne(colPrescriptions(), null, {
            module: 'M2', detail: detail, refresh: afficher,
            titre: function (r) { return r.reference; },
          }),
        });
      }

      function boutonPrescrire() {
        return nouvelle();
      }

      function detail(r) {
        var lignes = (r.lignes || []).map(function (l, i) {
          var rang = PR.rangSuivant(r.id, i);
          var att = D.secteurAdministrateur(r.modalite, rang);
          return [
            l.libelle,
            String(l.quantite || 1),
            (rang - 1) + ' / ' + (l.nbAdministrations || 1),
            libelleSecteur(att.secteur),
            l.prix == null ? 'tarif non renseigné' : C.money(l.prix),
          ];
        });
        return el('div.space-y-4', null,
          K.grid([
            ['Référence', r.reference], ['Date', C.dateHeure(r.date)],
            ['Patient', r.patient + ' — ' + r.patientCode],
            ['Type', r.type === 'soins' ? 'Prescription de soins' : 'Ordonnance'],
            ['Origine', libelleOrigine(r.origine)],
            ['Prescripteur', r.prescripteur],
            ['Secteur destinataire', libelleSecteur(r.secteurDestinataire)],
            ['Modalité', r.modalite === 'ambulatoire' ? 'Ambulatoire' : 'En hospitalisation'],
            ['Tarif appliqué', r.assure ? 'Assuré (carte valide à la date)' : 'Non assuré'],
            ['Règlement', r.statutPaiement === 'payee' ? 'Réglée' : 'Non réglée'],
          ]),
          r.indication ? K.section('Indication', el('p.text-sm.text-slate-600', { text: r.indication })) : null,
          K.section('Lignes et avancement des administrations',
            K.miniTable(['Acte', 'Qté', 'Administré', 'Prochain secteur', 'Prix'], lignes)),
          K.note('Le <strong>prochain secteur</strong> n’est pas un choix d’organisation : il découle du rang. '
            + 'Traitement ambulatoire, la salle de soins administre du premier au dernier passage ; traitement '
            + 'hospitalier, la <strong>première</strong> administration revient à la salle de soins et les '
            + '<strong>suivantes</strong> à l’hospitalisation.', { tone: 'info', icon: 'route' }));
      }
    },
  });

  /* ==========================================================================
   * SALLE DE SOINS
   * --------------------------------------------------------------------------
   * Le poste voit ce qui LUI revient, calculé par la règle de relais et non
   * par un filtre écrit ici : trois écrans posent la même question, y répondre
   * trois fois aurait produit trois réponses divergentes au premier correctif.
   * ======================================================================== */
  function ecranAdministration(id, secteur, titre, description, regle) {
    global.SIGH.screen(id, {
      title: titre,
      description: description,
      regle: regle,
      render: function (root) {
        var vue = el('div.space-y-4');
        root.appendChild(vue);
        afficher();
        return null;

        function executants() {
          return colSoignants().active().filter(function (x) {
            return x.execute && (x.secteurs || []).indexOf(secteur) !== -1;
          });
        }

        function afficher() {
          var dus = PR.soinsDuSecteur(secteur);
          var lignes = dus.reduce(function (n, d) { return n + d.lignes.length; }, 0);
          var bloquees = dus.reduce(function (n, d) {
            return n + d.lignes.filter(function (l) { return l.bloque; }).length;
          }, 0);
          var premieres = dus.reduce(function (n, d) {
            return n + d.lignes.filter(function (l) { return l.rang === 1; }).length;
          }, 0);

          C.clear(vue);
          vue.appendChild(U.kpiGrid([
            { label: 'Patients concernés', value: C.num(dus.length), icon: 'users', tone: 'navy' },
            { label: 'Administrations dues', value: C.num(lignes), icon: 'syringe', tone: 'info' },
            { label: 'Premières administrations', value: C.num(premieres), icon: 'flag', tone: 'success' },
            { label: 'Bloquées faute de règlement', value: C.num(bloquees), icon: 'lock',
              tone: bloquees ? 'warning' : 'neutral' },
          ]));

          vue.appendChild(K.note(regle, { tone: 'info', icon: 'route' }));

          var rows = [];
          dus.forEach(function (d) {
            d.lignes.forEach(function (l) {
              rows.push({
                id: d.prescription.id + ':' + l.index,
                prescription: d.prescription, ligne: l,
                reference: d.prescription.reference,
                patient: d.prescription.patient,
                patientCode: d.prescription.patientCode,
                libelle: l.ligne.libelle,
                rang: l.rang, total: l.total,
                motif: l.motif, bloque: l.bloque,
              });
            });
          });

          vue.appendChild(U.dataTable({
            rows: rows,
            empty: 'Aucune administration due à ce poste pour l’instant.',
            columns: [
              { key: 'reference', label: 'Prescription' },
              { key: 'patient', label: 'Patient', render: function (r) { return r.patient + ' — ' + r.patientCode; } },
              { key: 'libelle', label: 'Acte ou produit' },
              {
                key: 'rang', label: 'Passage', align: 'center',
                render: function (r) { return r.rang + ' / ' + r.total; },
              },
              {
                key: 'motif', label: 'Pourquoi ce poste',
                render: function (r) { return el('span.text-xs.text-slate-500', { text: r.motif }); },
              },
              {
                key: 'bloque', label: 'État', render: function (r) {
                  return r.bloque ? U.badge('Non réglée', 'warning') : U.badge('Exécutable', 'success');
                },
              },
            ],
            rowActions: function (r) {
              if (r.bloque) {
                return [K.iconBtn('lock', 'Bloquée : la prescription n’est pas réglée', function () {
                  U.toast('Administration bloquée — la prescription ' + r.reference + ' n’est pas réglée.',
                    { type: 'warning' });
                })];
              }
              /* LES DROITS DE L'ÉCRAN, PAS CEUX D'UN AUTRE MODULE. La salle
                 de soins est un écran de M2 ; interroger M3 donnait le droit
                 d'administrer à l'aide-soignante, qui a M3 en écriture et M2
                 en lecture. La matrice descend au niveau de l'écran : c'est
                 l'écran qu'il faut lui nommer. */
              if (!K.droits().editer) return [];
              return [K.btn('Administrer', {
                variant: 'primary', size: 'sm', icon: 'check',
                onclick: function () { administrer(r); },
              })];
            },
          }));
          U.icons(vue);
        }

        function administrer(r) {
          var exs = executants();
          var f = U.form([
            {
              name: 'executantId', label: 'Exécutant', type: 'select', required: true,
              options: exs.map(function (x) { return { value: x.id, label: x.nomComplet + ' — ' + x.poste }; }),
              hint: 'Infirmiers et sages-femmes. Le médecin prescrit, il n’exécute pas les soins.',
            },
            { name: 'observation', label: 'Observation', type: 'textarea', rows: 2 },
          ], {});
          var m = U.modal({
            title: 'Administrer — ' + r.libelle,
            subtitle: r.patient + ' — passage ' + r.rang + ' sur ' + r.total,
            body: el('div.space-y-3', null,
              K.note(r.motif, { tone: 'info', icon: 'route' }), f),
            footer: [
              K.btn('Annuler', { onclick: function () { m.close(); } }),
              K.btn('Confirmer l’administration', {
                variant: 'primary', icon: 'check',
                onclick: function () {
                  var v = f.collect();
                  if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                  var res = PR.administrer(r.prescription.id, {
                    ligneIndex: r.ligne.index, secteur: secteur,
                    executantId: v.executantId, observation: v.observation,
                  });
                  if (!res.ok) { U.toast(res.motif, { type: 'error' }); return; }
                  m.close();
                  afficher();
                  U.toast('Administration n° ' + res.rang + ' enregistrée.', {
                    type: 'success', detail: r.libelle + ' — ' + r.patient,
                  });
                },
              }),
            ],
          });
        }
      },
    });
  }

  ecranAdministration('m2-salle-soins', 'salle_soins', 'Salle de soins',
    'Administrations dues à la salle de soins : ambulatoires et premières administrations des hospitalisés.',
    'La salle de soins administre <strong>tous</strong> les traitements ambulatoires, du premier au dernier passage, '
      + 'et la <strong>première</strong> administration des traitements hospitaliers. Le relais passe ensuite à '
      + 'l’hospitalisation — c’est le circuit décrit par la Direction, appliqué par le moteur et non laissé à '
      + 'l’usage.');


  /* ==========================================================================
   * ÉCHOGRAPHIE ET IMAGERIE
   * --------------------------------------------------------------------------
   * L'écran applique la spécification que l'échographiste a écrite de sa main
   * sur son brouillon : des LISTES DE CHOIX partout où la valeur est
   * catégorielle, MAIS « Annexes » et « Conclusion » en TEXTE LIBRE — « à
   * remplir par moi-même », dit le document. Fermer ces deux rubriques dans un
   * formulaire à cases irait contre une instruction écrite.
   *
   * L'âge gestationnel est un COUPLE « n SA + n jours » et non un texte : le
   * saisir librement autoriserait « 7 mois », qui ne se compare à rien et ne
   * permet aucune datation de terme.
   *
   * Le compte rendu porte DEUX intervenants nommés : le PRESCRIPTEUR et le
   * RÉALISATEUR. Les cinq pièces réelles portent toutes « Réalisé par : AHOHOU
   * Rodrigue » avec ses téléphones — l'échographiste engage sa signature.
   * ======================================================================== */
  function colImagerie() {
    return S.collection('resultatsImagerie', { module: 'M2', entite: 'compte rendu d’imagerie', prefix: 'IMG' });
  }
  function IM() { return D.IMAGERIE || {}; }

  /* --------------------------------------------------------------------------
   * PHASE 8 — LE PARAMÉTRAGE DE L'IMAGERIE VIT AU MAGASIN
   * --------------------------------------------------------------------------
   * `examensImagerie` et `variablesImagerie` sont semées au socle depuis
   * D.IMAGERIE (la semence) et administrées par `cfg-imagerie-catalogue` :
   * lire la constante ici, c'était rendre le catalogue inmodifiable — le
   * défaut déjà corrigé sur les actes (D2). Le repli sur D.IMAGERIE couvre
   * un magasin d'ancienne génération, jamais le cas nominal.
   * ------------------------------------------------------------------------ */
  function colDemandesImagerie() {
    return S.collection('demandesImagerie', { module: 'M2', entite: 'demande d’imagerie', prefix: 'IME' });
  }
  function colCliches() {
    return S.collection('clichesImagerie', { module: 'M2', entite: 'cliché', prefix: 'CLI' });
  }
  function imExamens() {
    var c = S.collection('examensImagerie').active();
    return c.length ? c : (IM().EXAMENS || []);
  }
  function imExamen(code) {
    return imExamens().filter(function (x) { return x.code === code; })[0] || null;
  }
  function imVariablesDe(codeExamen) {
    var c = S.collection('variablesImagerie').active()
      .filter(function (v) { return v.examen === codeExamen && v.actif !== false; })
      .sort(function (a, b) { return (a.ordre || 0) - (b.ordre || 0); });
    if (c.length) return c;
    return IM().variablesDe ? IM().variablesDe(codeExamen) : [];
  }
  function imRubriquesDe(codeExamen) {
    var vus = {}, out = [];
    imVariablesDe(codeExamen).forEach(function (v) {
      if (vus[v.rubrique]) return;
      vus[v.rubrique] = true; out.push(v.rubrique);
    });
    return out;
  }

  /* Les états de la demande d'imagerie — LES MÊMES que le laboratoire :
     demandée (caisse) → payée (exécutable) → exécutée (CR saisi) →
     validée (CR rendu au prescripteur). */
  var ETATS_IMAGERIE = [
    { id: 'demandee', label: 'Demandée — attente caisse', tone: 'warning' },
    { id: 'payee', label: 'Payée — à exécuter', tone: 'info' },
    { id: 'executee', label: 'Exécutée — CR en rédaction', tone: 'navy' },
    { id: 'validee', label: 'Validée — CR rendu', tone: 'success' },
  ];
  function etatImagerie(id) {
    return ETATS_IMAGERIE.filter(function (x) { return x.id === id; })[0]
      || { id: id, label: id, tone: 'neutral' };
  }

  /* --- La saisie du compte rendu, partagée entre l'écran de saisie et le
         registre des demandes : UNE mécanique, deux portes. ----------------- */
  function champDeCR(v) {
    if (v.type === 'gestationnel') {
      return [
        { name: v.code + '_sa', label: v.libelle + ' — semaines d’aménorrhée', type: 'number', min: 1, max: 45 },
        { name: v.code + '_j', label: v.libelle + ' — jours', type: 'number', min: 0, max: 6 },
      ];
    }
    if (v.type === 'dimensions') {
      return [
        { name: v.code + '_a', label: v.libelle + ' — longueur (mm)', type: 'number', step: 0.1 },
        { name: v.code + '_b', label: v.libelle + ' — largeur (mm)', type: 'number', step: 0.1 },
        { name: v.code + '_c', label: v.libelle + ' — épaisseur (mm)', type: 'number', step: 0.1 },
      ];
    }
    if (v.type === 'liste' || v.type === 'binaire') {
      return [{ name: v.code, label: v.libelle, type: 'select',
        options: (v.options || []).map(function (o) { return { value: o, label: o }; }) }];
    }
    if (v.type === 'mesure') {
      return [{ name: v.code, label: v.libelle + (v.unite ? ' (' + v.unite + ')' : ''),
        type: 'number', step: 0.1 }];
    }
    if (v.type === 'zone') return [{ name: v.code, label: v.libelle, type: 'textarea', rows: 3 }];
    return [{ name: v.code, label: v.libelle, type: 'text' }];
  }

  function valeurLisibleCR(v, valeurs) {
    if (v.type === 'gestationnel') {
      var sa = valeurs[v.code + '_sa'], j = valeurs[v.code + '_j'];
      return sa == null ? '—' : (C.pad(sa, 2) + ' SA + ' + C.pad(j || 0, 2) + ' jours');
    }
    if (v.type === 'dimensions') {
      var a = valeurs[v.code + '_a'], b = valeurs[v.code + '_b'], c2 = valeurs[v.code + '_c'];
      if (a == null && b == null) return '—';
      return [a, b, c2].filter(function (x) { return x != null; }).join(' x ') + ' mm';
    }
    var val = valeurs[v.code];
    if (val == null || val === '') return '—';
    return String(val) + (v.unite ? ' ' + v.unite : '');
  }

  function saisirCR(rec, apres) {
    var vars = imVariablesDe(rec.examenCode);
    var rubriques = imRubriquesDe(rec.examenCode);
    var champs = [];
    rubriques.forEach(function (rub) {
      champs.push({ type: 'section', label: rub });
      vars.filter(function (v) { return v.rubrique === rub; }).forEach(function (v) {
        champs = champs.concat(champDeCR(v));
      });
    });
    (IM().RUBRIQUES_LIBRES || []).forEach(function (r) {
      champs.push({ type: 'section', label: r.label });
      champs.push({ name: r.code, label: r.label, type: 'textarea', rows: 4,
        required: !!r.requis, hint: r.note });
    });

    var valeurs = Object.assign({}, rec.valeurs || {},
      { annexes: rec.annexes || '', conclusion: rec.conclusion || '' });
    var f = U.form(champs, valeurs);

    var m = U.modal({
      title: rec.examen + ' — ' + rec.patient,
      subtitle: 'Indication : ' + rec.indication + '   ·   Réalisé par ' + rec.realisateur,
      size: 'xl', body: f,
      footer: [
        K.btn('Fermer sans enregistrer', { onclick: function () { m.close(); } }),
        K.btn('Enregistrer', { variant: 'primary', icon: 'save',
          onclick: function () {
            var v = f.collect();
            if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
            var annexes = v.annexes, conclusion = v.conclusion;
            delete v.annexes; delete v.conclusion;
            colImagerie().update(rec.id, { valeurs: v, annexes: annexes, conclusion: conclusion });
            /* La demande suit son compte rendu : exécutée dès la saisie. */
            if (rec.demandeImagerieId) {
              var dem = colDemandesImagerie().get(rec.demandeImagerieId);
              if (dem && (dem.statut === 'payee' || dem.statut === 'executee')) {
                colDemandesImagerie().update(dem.id, {
                  statut: 'executee', executeLe: new Date().toISOString(),
                });
              }
            }
            m.close();
            if (apres) apres();
            U.toast('Compte rendu enregistré.', { type: 'success', detail: rec.reference });
          } }),
      ],
    });
  }

  function rendreCR(r, apres) {
    if (!r.conclusion) {
      U.toast('La conclusion est obligatoire avant de rendre le compte rendu.', { type: 'error' });
      return;
    }
    U.confirm({
      title: 'Rendre le compte rendu au prescripteur ?',
      message: 'Le compte rendu <strong>' + r.reference + '</strong> sera transmis à '
        + r.prescripteur + '. Une correction ultérieure devra être signalée comme telle.',
      confirmLabel: 'Rendre',
    }).then(function (ok) {
      if (!ok) return;
      colImagerie().update(r.id, { statut: 'rendu', renduLe: new Date().toISOString() });
      if (r.demandeImagerieId) {
        colDemandesImagerie().update(r.demandeImagerieId, {
          statut: 'validee', valideLe: new Date().toISOString(),
        });
      }
      PR.notifier({
        type: 'imagerie_rendue', poste: 'consultation',
        libelle: 'Compte rendu d’imagerie rendu — ' + r.patient,
        detail: r.examen + ' — ' + r.reference + ' — prescripteur ' + r.prescripteur,
        patientId: r.patientId, reference: r.reference,
      });
      if (apres) apres();
      U.toast('Compte rendu rendu au prescripteur.', { type: 'success', detail: r.reference });
    });
  }

  function detailCR(r) {
    var vars = imVariablesDe(r.examenCode);
    var lignes = vars.map(function (v) {
      return [v.rubrique, v.libelle, valeurLisibleCR(v, r.valeurs || {})];
    });
    return el('div.space-y-4', null,
      K.grid([
        ['Référence', r.reference], ['Examen', r.examen],
        ['Patient', r.patient + ' — ' + r.patientCode],
        ['Âge', r.age != null ? r.age + ' ans' : '—'],
        ['Indication', r.indication], ['DDR', r.ddr || '—'],
        ['Condition de l’examen', r.condition || '—'],
        ['Prescripteur', r.prescripteur], ['Réalisé par', r.realisateur],
        ['État', r.statut === 'rendu' ? 'Rendu au prescripteur' : 'En rédaction'],
      ]),
      K.section('Résultats', K.miniTable(['Rubrique', 'Variable', 'Valeur'], lignes)),
      r.annexes ? K.section('Annexes', el('p.whitespace-pre-line.text-sm.text-slate-600', { text: r.annexes })) : null,
      r.conclusion ? K.section('Conclusion', el('p.whitespace-pre-line.text-sm.font-medium.text-slate-800', { text: r.conclusion })) : null);
  }

  function imprimerCR(r) {
    var vars = imVariablesDe(r.examenCode);
    var rubriques = imRubriquesDe(r.examenCode);
    var corps = el('div');
    rubriques.forEach(function (rub) {
      corps.appendChild(el('p.mb-1.mt-3.text-\\[10px\\].font-semibold.uppercase.tracking-wide', { text: rub }));
      var lignes = vars.filter(function (v) { return v.rubrique === rub; }).map(function (v) {
        var lu = valeurLisibleCR(v, r.valeurs || {});
        var hors = IM().ecart(v, (r.valeurs || {})[v.code]);
        return el('p.text-\\[10px\\].leading-relaxed', null, [
          el('span.font-medium', { text: v.libelle + ' : ' }),
          el(hors ? 'span.font-bold' : 'span', { text: lu }),
        ]);
      });
      lignes.forEach(function (l) { corps.appendChild(l); });
    });
    if (r.annexes) {
      corps.appendChild(el('p.mb-1.mt-3.text-\\[10px\\].font-semibold.uppercase.tracking-wide', { text: 'Annexes' }));
      corps.appendChild(el('p.whitespace-pre-line.text-\\[10px\\].leading-relaxed', { text: r.annexes }));
    }
    corps.appendChild(el('p.mb-1.mt-3.text-\\[10px\\].font-semibold.uppercase.tracking-wide', { text: 'Conclusion' }));
    corps.appendChild(el('p.whitespace-pre-line.text-\\[10px\\].font-semibold.leading-relaxed', { text: r.conclusion || '—' }));

    P.etat({
      titre: (r.examen || '').toUpperCase(),
      sousTitre: r.reference + ' — ' + r.patient,
      cartouche: [
        ['Nom et prénoms', r.patient], ['Âge', r.age != null ? r.age + ' ans' : '—'],
        ['Indication', r.indication], ['DDR', r.ddr || '—'],
        ['Prescripteur', r.prescripteur],
        ['Condition de l’examen', r.condition || '—'],
      ],
      contenu: corps,
      signatures: [{ role: 'Réalisé par', nom: r.realisateur, mention: 'Signature' }],
    });
  }

  global.SIGH.screen('m2-imagerie', {
    title: 'Échographie & imagerie',
    description: 'Comptes rendus d’échographie et d’électrocardiogramme, saisis par variables et rendus au prescripteur.',
    regle: 'Les résultats se saisissent par <strong>listes de choix</strong> — c’est la demande écrite de '
      + 'l’échographiste. Seules <strong>Annexes</strong> et <strong>Conclusion</strong> restent en texte '
      + 'libre : « à remplir par moi-même ». Le compte rendu porte le <strong>prescripteur</strong> et le '
      + '<strong>réalisateur</strong>, tous deux nommés.',
    render: function (root) {
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      afficher();
      return null;

      function examens() { return imExamens(); }

      function afficher() {
        var rows = colImagerie().active();
        var rendus = rows.filter(function (r) { return r.statut === 'rendu'; });
        var brouillons = rows.filter(function (r) { return r.statut !== 'rendu'; });
        var obst = rows.filter(function (r) { return /OBS/.test(r.examenCode || ''); });

        C.clear(vue);
        vue.appendChild(U.kpiGrid([
          { label: 'Comptes rendus', value: C.num(rows.length), icon: 'scan-line', tone: 'navy' },
          { label: 'Rendus au prescripteur', value: C.num(rendus.length), icon: 'send', tone: 'success' },
          { label: 'En cours de rédaction', value: C.num(brouillons.length), icon: 'pencil',
            tone: brouillons.length ? 'warning' : 'neutral' },
          { label: 'Examens obstétricaux', value: C.num(obst.length), icon: 'baby', tone: 'info' },
        ]));

        vue.appendChild(K.note('Les listes de choix pré-insérées viennent du <strong>brouillon manuscrit de '
          + 'l’échographiste</strong> et des cinq comptes rendus réels de la clinique. '
          + '<strong>Annexes et Conclusion restent libres</strong> — c’est écrit de sa main sur le brouillon.',
        { tone: 'info', icon: 'pen-line' }));

        vue.appendChild(U.dataTable({
          rows: C.sortBy(rows, 'date').reverse(),
          empty: 'Aucun compte rendu d’imagerie enregistré.',
          actions: K.droits('M2').editer ? [K.btn('Nouveau compte rendu', {
            variant: 'primary', size: 'sm', icon: 'plus', onclick: choisirExamen,
          })] : [],
          columns: [
            { key: 'reference', label: 'Référence' },
            { key: 'date', label: 'Date', render: function (r) { return C.dateHeure(r.date); } },
            { key: 'patient', label: 'Patient', render: function (r) { return r.patient + ' — ' + r.patientCode; } },
            { key: 'examen', label: 'Examen' },
            { key: 'prescripteur', label: 'Prescripteur' },
            { key: 'realisateur', label: 'Réalisé par' },
            { key: 'statut', label: 'État', render: function (r) {
              return r.statut === 'rendu' ? U.badge('Rendu', 'success') : U.badge('En rédaction', 'warning');
            } },
          ],
          rowActions: function (r) {
            var actes = [K.iconBtn('printer', 'Imprimer le compte rendu', function () { imprimer(r); })];
            if (K.droits('M2').editer && r.statut !== 'rendu') {
              actes.push(K.iconBtn('pencil', 'Poursuivre la saisie', function () { saisir(r.examenCode, r); }));
              actes.push(K.iconBtn('send', 'Rendre au prescripteur', function () { rendre(r); }));
            }
            return actes.concat(K.actionsLigne(colImagerie(), null, {
              module: 'M2', refresh: afficher, detail: detail,
              titre: function (x) { return x.reference + ' — ' + x.examen; },
            })(r));
          },
        }));
        U.icons(vue);
      }

      /* Le choix de l'examen précède la saisie : les variables en dépendent
         entièrement, et un formulaire unique aurait affiché des rubriques sans
         objet — le plus sûr moyen de faire remplir n'importe quoi. */
      function choisirExamen() {
        var f = U.form([
          { name: 'examenCode', label: 'Examen', type: 'select', required: true,
            options: examens().map(function (x) { return { value: x.code, label: x.label }; }) },
          { name: 'patientCode', label: 'Patient', type: 'select', required: true, options: optionsPatients() },
          { name: 'indication', label: 'Indication', type: 'text', required: true,
            hint: 'Ce que le prescripteur cherche — « Kyste ovarien ? », « RAU », « Terme », « Croissance ».' },
          { name: 'prescripteurId', label: 'Prescripteur', type: 'select', required: true,
            options: prescripteurs().map(function (x) {
              return { value: x.id, label: x.nomComplet + ' — ' + x.poste };
            }) },
          { name: 'realisateurId', label: 'Réalisé par', type: 'select', required: true,
            options: colSoignants().active().filter(function (x) { return x.realiseImagerie || x.qualite === 'medecin'; })
              .map(function (x) { return { value: x.id, label: x.nomComplet + ' — ' + x.poste }; }) },
          { name: 'ddr', label: 'DDR — date des dernières règles', type: 'text',
            hint: 'Laisser « inconnue » si la patiente ne la connaît pas — c’est le cas sur les pièces réelles.' },
          { name: 'condition', label: 'Condition de l’examen', type: 'select',
            options: [{ value: 'Bonne', label: 'Bonne' }, { value: 'Moyenne', label: 'Moyenne' },
              { value: 'Difficile', label: 'Difficile' }] },
        ], { ddr: 'inconnue', condition: 'Bonne' });

        var m = U.modal({
          title: 'Nouveau compte rendu d’imagerie',
          subtitle: 'L’examen choisi détermine les variables à renseigner.',
          size: 'lg', body: f,
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Continuer vers la saisie', { variant: 'primary', icon: 'arrow-right',
              onclick: function () {
                var v = f.collect();
                if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                var pt = S.collection('patients').active().filter(function (x) { return x.code === v.patientCode; })[0];
                var ex = imExamen(v.examenCode);
                var rec = colImagerie().insert({
                  reference: C.nextRef('IMG-', 4),
                  date: new Date().toISOString(),
                  examenCode: v.examenCode, examen: ex ? ex.label : v.examenCode,
                  patientId: pt ? pt.id : null,
                  patient: pt ? pt.nom + ' ' + pt.prenom : v.patientCode,
                  patientCode: v.patientCode,
                  age: pt ? C.age(pt.dateNaissance) : null,
                  indication: v.indication, ddr: v.ddr, condition: v.condition,
                  prescripteurId: v.prescripteurId, prescripteur: nomSoignant2(v.prescripteurId),
                  realisateurId: v.realisateurId, realisateur: nomSoignant2(v.realisateurId),
                  valeurs: {}, annexes: '', conclusion: '',
                  statut: 'brouillon',
                }).record;
                m.close();
                saisir(v.examenCode, rec);
              } }),
          ],
        });
      }

      /* La mécanique du compte rendu vit AU MODULE (phase 8) : le registre
         des demandes et le tableau de bord s'en servent aussi — UNE
         mécanique, plusieurs portes. */
      function saisir(codeExamen, rec) { saisirCR(rec, afficher); }
      function rendre(r) { rendreCR(r, afficher); }
      function detail(r) { return detailCR(r); }
      function imprimer(r) { imprimerCR(r); }
    },
  });

  function nomSoignant2(id) {
    var x = colSoignants().active().filter(function (y) { return y.id === id; })[0];
    return x ? x.nomComplet : '—';
  }

  /* ==========================================================================
   * PHASE 8 — L'IMAGERIE ÉCLATÉE : DEMANDES, TABLEAU DE BORD, GALERIE
   * --------------------------------------------------------------------------
   * L'imagerie suit désormais LES MÊMES ÉTATS que le laboratoire — demandée →
   * payée → exécutée → validée — portés par `demandesImagerie` et le moteur
   * `PR.ouvrirDemandeImagerie` (la ligne payable porte `demandeImagerieId`).
   * L'écran de saisie (m2-imagerie) reste la porte du compte rendu ; la voie
   * directe y demeure ouverte — c'est la saisie « manuelle » du poste, comme
   * au laboratoire — et se distingue par l'absence de demande liée.
   * ======================================================================== */

  /** Le compte rendu d'une demande, s'il existe. */
  function crDeDemande(dem) {
    return colImagerie().active().filter(function (r) {
      return r.demandeImagerieId === dem.id;
    })[0] || null;
  }

  /** Ouvre (en le créant au besoin) le compte rendu d'une demande PAYÉE. */
  function saisirDepuisDemande(dem, apres) {
    var cr = crDeDemande(dem);
    if (!cr) {
      var pt = S.collection('patients').active().filter(function (x) { return x.id === dem.patientId; })[0];
      var realisateur = colSoignants().active().filter(function (x) { return x.realiseImagerie; })[0];
      cr = colImagerie().insert({
        reference: C.nextRef('IMG-', 4),
        date: new Date().toISOString(),
        examenCode: dem.examenCode, examen: dem.examen,
        patientId: dem.patientId, patient: dem.patient, patientCode: dem.patientCode,
        age: pt ? C.age(pt.dateNaissance) : null,
        indication: dem.indication || '—', ddr: 'inconnue', condition: 'Bonne',
        prescripteur: dem.prescripteur,
        realisateurId: realisateur ? realisateur.id : null,
        realisateur: realisateur ? realisateur.nomComplet : (S.currentUser() || '—'),
        valeurs: {}, annexes: '', conclusion: '',
        statut: 'brouillon',
        demandeImagerieId: dem.id, demandeReference: dem.reference,
      }).record;
    }
    saisirCR(cr, apres);
  }

  /* --------------------------------------------------------------------------
   * REGISTRE DES DEMANDES D'IMAGERIE
   * ----------------------------------------------------------------------- */
  global.SIGH.screen('m2-imagerie-demandes', {
    title: 'Demandes d’imagerie',
    description: 'Le registre des examens demandés, aux mêmes états que le laboratoire : demandé, payé, exécuté, validé.',
    regle: 'La demande naît <strong>bloquée par le paiement</strong> : c’est l’encaissement de SA ligne '
      + 'qui la rend exécutable — la caisse encaisse des examens nommés. Le compte rendu ne se saisit '
      + 'que sur une demande <strong>payée</strong>, et sa validation (rendu au prescripteur) clôt le '
      + 'circuit. Un examen sans tarif validé est <strong>refusé en le nommant</strong> — un tiret '
      + 'n’est pas un zéro.',
    render: function (root) {
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      afficher();
      return null;

      function rows() { return colDemandesImagerie().active(); }

      function afficher() {
        var r0 = rows();
        var parEtat = {};
        ETATS_IMAGERIE.forEach(function (e) {
          parEtat[e.id] = r0.filter(function (r) { return r.statut === e.id; });
        });

        C.clear(vue);
        vue.appendChild(U.kpiGrid(ETATS_IMAGERIE.map(function (e) {
          return { label: e.label, value: C.num(parEtat[e.id].length),
            icon: e.id === 'demandee' ? 'wallet' : (e.id === 'payee' ? 'scan-line'
              : (e.id === 'executee' ? 'pencil' : 'file-check-2')),
            tone: parEtat[e.id].length ? e.tone : 'neutral' };
        })));

        vue.appendChild(U.dataTable({
          title: 'Registre des demandes', rows: rows,
          exportName: 'demandes-imagerie', pageSize: 12, searchable: true,
          defaultSort: 'dateHeure', defaultDir: 'desc',
          emptyMessage: 'Aucune demande d’imagerie. Une demande s’ouvre ici ou naît d’une consultation.',
          /* OUVRIR une demande est un acte de PRESCRIPTION : l'échographiste
             exécute et saisit le CR (son droit d'écran l'y autorise), mais
             prescrire serait un exercice illégal — la commande de création
             lui est fermée NOMMÉMENT, comme ses écrans de prescription. */
          actions: ((S.session() || {}).role === 'echographiste' ? [] : [K.commande('Nouvelle demande', {
            variant: 'primary', size: 'sm', icon: 'plus', onclick: nouvelleDemande,
          })]).filter(Boolean),
          columns: [
            { key: 'reference', label: 'N°', render: function (r) {
              return el('div', null, [
                el('span.font-mono.text-xs', { text: r.reference }),
                r.factureNumero ? el('p.font-mono.text-[10px].text-slate-400', { text: r.factureNumero }) : null,
              ]);
            } },
            { key: 'dateHeure', label: 'Date', render: function (r) { return C.dateFR(r.dateHeure); } },
            { key: 'patient', label: 'Patient', render: function (r) { return r.patient + ' — ' + (r.patientCode || '—'); } },
            { key: 'examen', label: 'Examen' },
            { key: 'prescripteur', label: 'Prescripteur' },
            { key: 'prix', label: 'Tarif', align: 'right', render: function (r) { return C.money(r.prix, false); } },
            {
              key: 'statut', label: 'État',
              value: function (r) { return etatImagerie(r.statut).label; },
              render: function (r) {
                var e = etatImagerie(r.statut);
                return U.badge(e.label, e.tone);
              },
            },
          ],
          onRowClick: function (r) {
            var cr = crDeDemande(r);
            U.drawer({
              title: r.examen, subtitle: r.patient + ' — ' + r.reference,
              body: cr ? detailCR(cr) : el('div.space-y-4', null,
                K.grid([
                  ['Référence', r.reference], ['Date', C.dateFR(r.dateHeure)],
                  ['Patient', r.patient], ['Examen', r.examen],
                  ['Prescripteur', r.prescripteur], ['Indication', r.indication || '—'],
                  ['Tarif', C.money(r.prix)], ['Facture', r.factureNumero || '—'],
                  ['État', etatImagerie(r.statut).label],
                ]),
                r.statut === 'demandee'
                  ? K.note('L’examen attend son règlement : la balle est à la caisse ('
                    + (r.factureNumero || 'pièce à émettre') + ').', { tone: 'warning', icon: 'wallet' })
                  : null),
            });
          },
          rowActions: function (r) {
            var actes = [];
            if (r.statut === 'demandee') {
              /* Verrouillé et non masqué : la balle est à la caisse. */
              var b = K.btn('Saisir le CR', {
                size: 'sm', icon: 'lock',
                title: 'Examen non réglé — le patient doit passer à la caisse.',
                onclick: function () {
                  U.toast('Saisie impossible : examen non réglé.', { type: 'error',
                    detail: 'La caisse doit encaisser la pièce ' + (r.factureNumero || '') + ' d’abord.' });
                },
              });
              b.classList.add('opacity-50', 'cursor-not-allowed');
              b.setAttribute('aria-disabled', 'true');
              actes.push(b);
            }
            if (r.statut === 'payee' || r.statut === 'executee') {
              actes.push(K.commande(r.statut === 'payee' ? 'Saisir le CR' : 'Poursuivre le CR', {
                size: 'sm', variant: 'primary', icon: 'file-pen-line',
                onclick: function () { saisirDepuisDemande(r, afficher); },
              }));
            }
            if (r.statut === 'executee') {
              var cr = crDeDemande(r);
              if (cr) {
                actes.push(K.commande('Rendre', {
                  size: 'sm', icon: 'send',
                  onclick: function () { rendreCR(cr, afficher); },
                }));
              }
            }
            if (r.statut === 'validee') {
              var cr2 = crDeDemande(r);
              if (cr2) actes.push(K.iconBtn('printer', 'Imprimer le compte rendu', function () { imprimerCR(cr2); }));
            }
            return actes.filter(Boolean);
          },
        }));
        U.icons(vue);
      }

      function nouvelleDemande() {
        var f = U.form([
          { name: 'patientCode', label: 'Patient', type: 'select', required: true, col: 'full', options: optionsPatients() },
          {
            name: 'examens', label: 'Examens demandés', type: 'multiselect', required: true, col: 'full',
            options: imExamens().map(function (x) {
              var t = D.tarif ? D.tarif((x.tarifCode || x.code)) : null;
              return { value: x.code, label: x.label,
                detail: t && t.prixNonAssure != null
                  ? C.money(t.prixNonAssure) + ' non assuré · ' + (t.prixAssure != null ? C.money(t.prixAssure) + ' assuré' : '—')
                  : 'tarif non renseigné' };
            }),
          },
          { name: 'prescripteur', label: 'Prescripteur', type: 'select', required: true,
            options: prescripteurs().map(function (x) { return { value: x.nomComplet, label: x.nomComplet + ' — ' + x.poste }; }) },
          { name: 'indication', label: 'Indication', type: 'textarea', rows: 2, required: true, col: 'full' },
          { name: 'urgent', label: 'Examen urgent', type: 'checkbox' },
        ], {});
        var m = U.modal({
          title: 'Nouvelle demande d’imagerie', size: 'lg', body: f,
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Émettre la demande', {
              variant: 'primary', icon: 'send',
              onclick: function () {
                var v = f.collect();
                if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                var pt = S.collection('patients').active().filter(function (x) { return x.code === v.patientCode; })[0];
                if (!pt) { U.toast('Patient introuvable.', { type: 'error' }); return; }
                var res;
                try {
                  res = PR.ouvrirDemandeImagerie({
                    patientId: pt.id, examens: v.examens,
                    prescripteur: v.prescripteur, indication: v.indication, urgent: !!v.urgent,
                  });
                } catch (err) { U.toast(err.message, { type: 'error' }); return; }
                m.close(); afficher();
                U.toast('Demande émise — ' + res.demandes.length + ' examen(s).', {
                  type: 'success', duration: 8000,
                  detail: 'Facture ' + res.facture.numero + ' à la caisse ; l’examen sera exécutable après règlement.',
                });
              },
            }),
          ],
        });
      }
    },
  });

  /* --------------------------------------------------------------------------
   * TABLEAU DE BORD DE L'IMAGERIE — le poste de travail de l'échographiste
   * ----------------------------------------------------------------------- */
  global.SIGH.screen('m2-dashboard-imagerie', {
    title: 'Poste d’imagerie',
    description: 'Le premier regard du poste : les examens payés à exécuter, les comptes rendus en rédaction, la file d’attente.',
    regle: 'Un examen ne s’exécute qu’une fois <strong>réglé</strong> — la file du poste ne porte que les '
      + 'demandes payées. Ce tableau LIT les registres, il n’ouvre aucune saisie propre : la donnée '
      + 'n’existe qu’une fois.',
    render: function (root) {
      var host = el('div.space-y-4');
      root.appendChild(host);
      afficher();
      return null;

      function afficher() {
        var dems = colDemandesImagerie().active();
        var payees = dems.filter(function (r) { return r.statut === 'payee'; });
        var attente = dems.filter(function (r) { return r.statut === 'demandee'; });
        var crs = colImagerie().active();
        var redaction = crs.filter(function (r) { return r.statut !== 'rendu'; });
        var moisCourant = C.iso(new Date()).slice(0, 7);
        var rendusMois = crs.filter(function (r) {
          return r.statut === 'rendu' && String(r.renduLe || r.date || '').slice(0, 7) === moisCourant;
        });

        C.clear(host);
        host.appendChild(U.kpiGrid([
          { label: 'Payés — à exécuter', value: C.num(payees.length), icon: 'scan-line',
            tone: payees.length ? 'warning' : 'success', hint: payees.length ? 'Le premier regard du poste' : 'Rien n’attend' },
          { label: 'En attente de caisse', value: C.num(attente.length), icon: 'wallet', tone: 'neutral',
            hint: 'Visibles, non exécutables' },
          { label: 'CR en rédaction', value: C.num(redaction.length), icon: 'pencil',
            tone: redaction.length ? 'info' : 'neutral' },
          { label: 'Rendus ce mois-ci', value: C.num(rendusMois.length), icon: 'file-check-2', tone: 'success' },
        ]));

        if (payees.length) {
          host.appendChild(U.dataTable({
            title: 'À exécuter — examens réglés', rows: payees,
            pageSize: 8, exportName: 'imagerie-a-executer',
            defaultSort: 'dateHeure', defaultDir: 'asc',
            columns: [
              { key: 'reference', label: 'N°', render: function (r) { return el('span.font-mono.text-xs', { text: r.reference }); } },
              { key: 'patient', label: 'Patient' },
              { key: 'examen', label: 'Examen' },
              { key: 'urgent', label: 'Priorité', render: function (r) {
                return r.urgent ? U.badge('Urgent', 'danger') : el('span.text-xs.text-slate-400', { text: 'Courante' });
              } },
            ],
            rowActions: function (r) {
              return [K.commande('Saisir le CR', {
                size: 'sm', variant: 'primary', icon: 'file-pen-line',
                moduleCode: 'M2',
                onclick: function () { saisirDepuisDemande(r, afficher); },
              })].filter(Boolean);
            },
          }));
        } else {
          host.appendChild(U.card('À exécuter',
            U.empty('Aucun examen réglé en attente : rien ne vous attend.', { icon: 'check-circle-2' })));
        }

        host.appendChild(K.fileAttente('imagerie', {
          titre: 'File d’attente du poste',
          vide: 'Aucune tâche d’imagerie en file.',
          icon: 'scan-line',
        }));
        U.icons(host);
      }
    },
  });

  /* --------------------------------------------------------------------------
   * GALERIE DES CLICHÉS — la bibliothèque d'images liée au dossier
   * ----------------------------------------------------------------------- */
  global.SIGH.screen('m2-echographie-galerie', {
    title: 'Galerie des clichés',
    description: 'Les clichés d’échographie conservés au poste, rattachés au patient et au compte rendu.',
    regle: 'Un cliché se rattache à un <strong>patient</strong> et, si possible, à son compte rendu : une '
      + 'image orpheline ne se retrouve plus. Conservation locale, <strong>mêmes précautions de taille '
      + 'que les documents du dossier</strong> — au-delà de deux mégaoctets, le stockage du navigateur '
      + 'sature vite. L’archivage est logique (RG-14) : rien ne s’efface.',
    render: function (root) {
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      afficher();
      return null;

      function afficher() {
        var rows = colCliches().active();
        var parPatient = {};
        rows.forEach(function (r) { parPatient[r.patientId || r.patient] = true; });

        C.clear(vue);
        vue.appendChild(U.kpiGrid([
          { label: 'Clichés conservés', value: C.num(rows.length), icon: 'images', tone: 'navy' },
          { label: 'Patients concernés', value: C.num(Object.keys(parPatient).length), icon: 'users', tone: 'info' },
          { label: 'Liés à un compte rendu', value: C.num(rows.filter(function (r) { return r.crReference; }).length),
            icon: 'file-check-2', tone: 'success' },
          { label: 'Sans compte rendu lié', value: C.num(rows.filter(function (r) { return !r.crReference; }).length),
            icon: 'help-circle', tone: 'neutral' },
        ]));

        var barre = el('div.card');
        var actions = el('div.card-body.flex.flex-wrap.items-center.gap-3');
        var cmd = K.commande('Ajouter un cliché', {
          variant: 'primary', size: 'sm', icon: 'image-plus', onclick: ajouter,
        });
        if (cmd) actions.appendChild(cmd);
        barre.appendChild(actions);
        vue.appendChild(barre);

        if (!rows.length) {
          vue.appendChild(U.card('Galerie',
            U.empty('Aucun cliché conservé. Les images s’ajoutent depuis ce poste, rattachées au patient.',
              { icon: 'images' })));
        } else {
          var grille = el('div.grid.gap-4.sm:grid-cols-2.lg:grid-cols-3');
          C.sortBy(rows, 'date').reverse().forEach(function (r) {
            var carte = el('div.card.overflow-hidden');
            carte.appendChild(el('img.h-44.w-full.bg-slate-100.object-contain', {
              src: r.fichier, alt: 'Cliché — ' + r.examen,
            }));
            carte.appendChild(el('div.card-body.space-y-1', null, [
              el('p.text-sm.font-medium.text-slate-800', { text: r.patient }),
              el('p.text-xs.text-slate-500', { text: r.examen + ' — ' + C.dateFR(r.date) }),
              r.legende ? el('p.text-xs.text-slate-600', { text: r.legende }) : null,
              el('div.flex.items-center.justify-between.pt-1', null, [
                r.crReference
                  ? el('span.font-mono.text-[10px].text-navy-700', { text: r.crReference })
                  : el('span.text-[10px].text-slate-400', { text: 'sans CR lié' }),
                K.commandeIcone('archive', 'Archiver le cliché', function () {
                  U.confirm({
                    title: 'Archiver ce cliché ?',
                    message: 'Archivage logique (RG-14) : le cliché reste restaurable depuis la Corbeille.',
                    confirmLabel: 'Archiver', danger: true,
                  }).then(function (ok) {
                    if (!ok) return;
                    colCliches().archive(r.id);
                    afficher();
                    U.toast('Cliché archivé.', { type: 'success' });
                  });
                }),
              ].filter(Boolean)),
            ].filter(Boolean)));
            grille.appendChild(carte);
          });
          vue.appendChild(grille);
        }
        U.icons(vue);
      }

      function ajouter() {
        var meta = {};
        var input = el('input.input', { type: 'file', accept: 'image/png,image/jpeg,image/webp' });
        var apercu = el('div');
        input.addEventListener('change', function () {
          C.clear(apercu);
          var file = input.files && input.files[0];
          if (!file) return;
          if (file.size > 2 * 1024 * 1024) {
            apercu.appendChild(K.note('Fichier de ' + Math.round(file.size / 1024) + ' Ko — au-delà de deux '
              + 'mégaoctets, le stockage local sature vite. Exporter le cliché en résolution plus basse.',
            { tone: 'warning', icon: 'alert-triangle' }));
          }
          var lecteur = new FileReader();
          lecteur.onload = function () {
            meta.fichier = lecteur.result;
            apercu.appendChild(el('img.mt-2.max-h-40.rounded-lg.border.border-slate-200.object-contain',
              { src: meta.fichier, alt: 'Aperçu du cliché' }));
          };
          lecteur.readAsDataURL(file);
        });

        var crs = colImagerie().active();
        var f = U.form([
          { name: 'patientCode', label: 'Patient', type: 'select', required: true, col: 'full', options: optionsPatients() },
          {
            name: 'crReference', label: 'Compte rendu lié', type: 'select', col: 'full',
            options: [{ value: '', label: '— aucun —' }].concat(crs.map(function (r) {
              return { value: r.reference, label: r.reference + ' — ' + r.examen + ' — ' + r.patient };
            })),
          },
          { name: 'examen', label: 'Examen', type: 'select', required: true,
            options: imExamens().map(function (x) { return { value: x.label, label: x.label }; }) },
          { name: 'legende', label: 'Légende', type: 'text', col: 'full',
            hint: 'Ce que montre le cliché — coupe, mesure, structure visée.' },
        ], {});

        var m = U.modal({
          title: 'Ajouter un cliché', size: 'lg',
          body: el('div.space-y-3', null, [
            f,
            el('div', null, [el('label.label', { text: 'Image * — PNG, JPEG ou WEBP' }), input, apercu]),
          ]),
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Conserver le cliché', {
              variant: 'primary', icon: 'image-plus',
              onclick: function () {
                var v = f.collect();
                if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                if (!meta.fichier) {
                  U.toast('Choisir une image.', { type: 'error',
                    detail: 'Un cliché sans image n’est qu’une légende.' });
                  return;
                }
                var pt = S.collection('patients').active().filter(function (x) { return x.code === v.patientCode; })[0];
                colCliches().insert({
                  date: new Date().toISOString(),
                  patientId: pt ? pt.id : null,
                  patient: pt ? pt.nom + ' ' + pt.prenom : v.patientCode,
                  patientCode: v.patientCode,
                  examen: v.examen, legende: v.legende || '',
                  crReference: v.crReference || null,
                  fichier: meta.fichier,
                  deposePar: S.currentUser(),
                });
                m.close(); afficher();
                U.toast('Cliché conservé.', { type: 'success' });
              },
            }),
          ],
        });
      }
    },
  });


  /* ==========================================================================
   * FILE D'ATTENTE — FIFO TEMPÉRÉ PAR LA PRIORITÉ DE TRIAGE
   * --------------------------------------------------------------------------
   * L'ordre d'arrivée gouverne, SAUF urgence. Les deux règles pures sont
   * mauvaises et la clinique les a toutes deux vécues :
   *
   *   - un FIFO strict fait attendre une urgence vitale derrière douze
   *     consultations de routine ;
   *   - une priorité sans FIFO fait passer indéfiniment les mêmes, et personne
   *     ne sait plus qui est arrivé quand.
   *
   * D'où le rang calculé : la priorité classe d'abord, l'heure d'arrivée
   * départage à priorité égale. Le rang n'est JAMAIS saisi — le saisir
   * permettrait de faire passer quelqu'un devant sans que rien ne le trace.
   *
   * L'heure d'arrivée est celle du dossier patient : c'est la même donnée, et
   * la Direction a demandé qu'elle soit conservée.
   * ======================================================================== */
  var PRIORITES = [
    { code: 'urgence_vitale', label: 'Urgence vitale', rang: 1, couleur: 'danger',
      note: 'Prise en charge immédiate, avant tout autre patient.' },
    { code: 'urgence', label: 'Urgence', rang: 2, couleur: 'warning',
      note: 'Passe devant les consultations programmées et les arrivées libres.' },
    { code: 'rdv', label: 'Sur rendez-vous', rang: 3, couleur: 'info',
      note: 'Le rendez-vous a réservé une plage : il prime sur l’arrivée libre.' },
    { code: 'ordre_arrivee', label: 'Par ordre d’arrivée', rang: 4, couleur: 'neutral',
      note: 'Le cas courant — la sage-femme reçoit par ordre d’arrivée.' },
  ];

  var POSTES_FILE = [
    { code: 'accueil', label: 'Accueil' },
    { code: 'consultation', label: 'Consultation' },
    { code: 'caisse', label: 'Caisse' },
    { code: 'prelevement', label: 'Salle de prélèvement' },
    { code: 'pharmacie', label: 'Pharmacie' },
    { code: 'salle_soins', label: 'Salle de soins' },
    { code: 'imagerie', label: 'Échographie' },
  ];

  function colFile() {
    return S.collection('fileAttente', { module: 'M2', entite: 'ticket de file', prefix: 'FIL' });
  }
  function prioriteDe(code) {
    return PRIORITES.filter(function (x) { return x.code === code; })[0] || PRIORITES[3];
  }
  function libellePoste(code) {
    var x = POSTES_FILE.filter(function (y) { return y.code === code; })[0];
    return x ? x.label : code;
  }

  /* Le classement, écrit UNE fois : l'écran de gestion et l'écran d'appel
     doivent afficher exactement le même ordre, sans quoi le patient appelé ne
     serait pas celui que l'agent voit en tête. */
  function fileTriee(poste) {
    return colFile().active()
      .filter(function (t) { return t.poste === poste && t.etat === 'attente'; })
      .sort(function (a, b) {
        var pa = prioriteDe(a.priorite).rang, pb = prioriteDe(b.priorite).rang;
        if (pa !== pb) return pa - pb;
        return String(a.arriveeLe).localeCompare(String(b.arriveeLe));
      });
  }

  global.SIGH.screen('m2-file-attente', {
    title: 'File d’attente',
    description: 'Gestion des files par poste : ordre d’arrivée tempéré par la priorité de triage.',
    regle: 'L’ordre d’<strong>arrivée</strong> gouverne, <strong>sauf urgence</strong>. Le rang est '
      + '<strong>calculé</strong>, jamais saisi : le saisir permettrait de faire passer quelqu’un devant '
      + 'sans que rien ne le trace. À priorité égale, c’est l’heure d’arrivée qui départage.',
    render: function (root) {
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      afficher();
      return null;

      function afficher() {
        var tous = colFile().active();
        var attente = tous.filter(function (t) { return t.etat === 'attente'; });
        var urgences = attente.filter(function (t) { return prioriteDe(t.priorite).rang <= 2; });
        var servis = tous.filter(function (t) { return t.etat === 'servi'; });

        C.clear(vue);
        vue.appendChild(U.kpiGrid([
          { label: 'Patients en attente', value: C.num(attente.length), icon: 'users', tone: 'navy' },
          { label: 'Dont urgences', value: C.num(urgences.length), icon: 'siren',
            tone: urgences.length ? 'danger' : 'success' },
          { label: 'Servis aujourd’hui', value: C.num(servis.filter(function (t) {
            return String(t.serviLe || '').slice(0, 10) === C.iso(new Date());
          }).length), icon: 'check-check', tone: 'success' },
          { label: 'Attente moyenne', value: attenteMoyenne(servis), icon: 'clock', tone: 'info',
            hint: 'sur les patients déjà servis' },
        ]));

        vue.appendChild(K.note('Le <strong>rang</strong> affiché n’est pas un champ : il découle de la priorité '
          + 'et de l’heure d’arrivée. Faire passer un patient devant se fait en changeant sa '
          + '<strong>priorité</strong>, ce qui est tracé — et non en réécrivant un numéro.',
        { tone: 'info', icon: 'list-ordered' }));

        vue.appendChild(U.tabs(POSTES_FILE.map(function (po) {
          var f = fileTriee(po.code);
          return { id: po.code, label: po.label, badge: f.length,
            render: function () { return panneau(po, f); } };
        })));
        U.icons(vue);
      }

      function attenteMoyenne(servis) {
        var avec = servis.filter(function (t) { return t.arriveeLe && t.serviLe; });
        if (!avec.length) return '—';
        var total = avec.reduce(function (n, t) {
          return n + (C.toDate(t.serviLe).getTime() - C.toDate(t.arriveeLe).getTime());
        }, 0);
        return Math.round(total / avec.length / 60000) + ' min';
      }

      function panneau(po, f) {
        return el('div.space-y-3', null,
          U.dataTable({
            rows: f.map(function (t, i) { return Object.assign({ rang: i + 1 }, t); }),
            empty: 'Personne n’attend à ce poste.',
            actions: K.droits('M2').editer ? [K.btn('Inscrire un patient', {
              variant: 'primary', size: 'sm', icon: 'user-plus',
              onclick: function () { inscrire(po.code); },
            })] : [],
            columns: [
              { key: 'rang', label: 'Rang', align: 'center',
                render: function (r) {
                  return el('span.inline-flex.h-7.w-7.items-center.justify-center.rounded-full.bg-navy-900.text-xs.font-bold.text-white',
                    { text: String(r.rang) });
                } },
              { key: 'numero', label: 'N° d’appel',
                render: function (r) { return el('span.font-mono.text-sm.font-semibold', { text: r.numero }); } },
              { key: 'patient', label: 'Patient' },
              { key: 'priorite', label: 'Priorité',
                render: function (r) {
                  var pr = prioriteDe(r.priorite);
                  return U.badge(pr.label, pr.couleur);
                } },
              { key: 'arriveeLe', label: 'Arrivé à',
                render: function (r) { return C.heure(r.arriveeLe); } },
              { key: 'attente', label: 'Attente', align: 'right',
                render: function (r) {
                  var mn = Math.round((Date.now() - C.toDate(r.arriveeLe).getTime()) / 60000);
                  return el('span', { class: mn > 45 ? 'font-semibold text-amber-700' : '',
                    text: mn + ' min' });
                } },
              { key: 'motif', label: 'Motif' },
            ],
            rowActions: function (r) {
              if (!K.droits('M2').editer) return [];
              return [
                K.btn('Appeler', { variant: 'primary', size: 'sm', icon: 'megaphone',
                  onclick: function () { appeler(r); } }),
                K.iconBtn('arrow-up', 'Modifier la priorité', function () { changerPriorite(r); }),
              ];
            },
          }));
      }

      /* Les praticiens qui reçoivent : dérivés du personnel soignant, jamais
         ressaisis — une seconde liste de noms divergerait du dossier RH au
         premier recrutement. */
      function optionsPraticiens() {
        return S.collection('soignants').active()
          .filter(function (x) { return x.prescrit; })
          .map(function (x) { return { value: x.nomComplet, label: x.nomComplet, detail: x.qualiteLabel || '' }; });
      }

      function inscrire(poste) {
        var champs = [
          { name: 'patientCode', label: 'Patient', type: 'select', required: true, options: optionsPatients() },
          { name: 'priorite', label: 'Priorité de triage', type: 'select', required: true,
            options: PRIORITES.map(function (x) { return { value: x.code, label: x.label, detail: x.note }; }) },
          { name: 'motif', label: 'Motif', type: 'text', required: true },
        ];
        /* Le praticien ne se demande QU'EN CONSULTATION, et il reste
           facultatif : la file est souvent commune, le prochain libre prend le
           suivant. L'imposer ferait désigner quelqu'un au hasard, et le
           tableau de bord du médecin porterait des patients qu'un autre
           recevra. */
        if (poste === 'consultation') {
          champs.push({
            name: 'praticien', label: 'Praticien attendu', type: 'select',
            options: [{ value: '', label: '— File commune —' }].concat(optionsPraticiens()),
            help: 'À renseigner seulement si le patient est adressé à un praticien précis '
              + '(rendez-vous nominatif, suivi en cours). Sinon, laisser en file commune.',
          });
        }
        var f = U.form(champs, { priorite: 'ordre_arrivee', praticien: '' });
        var m = U.modal({
          title: 'Inscrire un patient — ' + libellePoste(poste),
          subtitle: 'Le rang sera calculé : priorité d’abord, heure d’arrivée ensuite.',
          body: f,
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Inscrire', { variant: 'primary', icon: 'user-plus',
              onclick: function () {
                var v = f.collect();
                if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                var pt = S.collection('patients').active().filter(function (x) { return x.code === v.patientCode; })[0];
                /* Le numéro d'appel est propre au poste et à la journée : c'est
                   ce que le patient lit sur l'écran, et il doit repartir à 1
                   chaque matin comme le ticket papier. */
                var jour = C.iso(new Date());
                var n = colFile().all().filter(function (t) {
                  return t.poste === poste && String(t.arriveeLe || '').slice(0, 10) === jour;
                }).length + 1;
                var rec = colFile().insert({
                  numero: libellePoste(poste).slice(0, 1).toUpperCase() + C.pad(n, 3),
                  poste: poste, posteLabel: libellePoste(poste),
                  patientId: pt ? pt.id : null,
                  patient: pt ? pt.nom + ' ' + pt.prenom : v.patientCode,
                  patientCode: v.patientCode,
                  priorite: v.priorite, motif: v.motif,
                  /* Vide = file commune. C'est une information, pas un oubli. */
                  praticien: v.praticien || null,
                  arriveeLe: new Date().toISOString(),
                  etat: 'attente',
                }).record;
                m.close(); afficher();
                U.toast('Patient inscrit — numéro ' + rec.numero + '.', {
                  type: 'success', detail: rec.patient + ' — ' + prioriteDe(v.priorite).label,
                  undo: function () { colFile().archive(rec.id); afficher(); },
                  undoMessage: 'Inscription annulée.',
                });
              } }),
          ],
        });
      }

      function appeler(r) {
        colFile().update(r.id, { etat: 'servi', serviLe: new Date().toISOString(), appelePar: S.currentUser() });
        afficher();
        /* Un appel sonne : l'écran d'affichage est dans la salle d'attente, le
           patient ne regarde pas forcément au bon moment. */
        U.sonner('appel');
        U.toast('Patient appelé — ' + r.numero + '.', { type: 'success', detail: r.patient });
      }

      function changerPriorite(r) {
        var f = U.form([
          { name: 'priorite', label: 'Nouvelle priorité', type: 'select', required: true,
            options: PRIORITES.map(function (x) { return { value: x.code, label: x.label, detail: x.note }; }) },
          { name: 'motifChangement', label: 'Motif du changement', type: 'text', required: true,
            hint: 'Obligatoire : faire passer un patient devant un autre doit s’expliquer.' },
        ], { priorite: r.priorite });
        var m = U.modal({
          title: 'Modifier la priorité — ' + r.patient,
          subtitle: 'Le rang se recalcule ; le changement est journalisé (RG-12).',
          body: f,
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Appliquer', { variant: 'primary', icon: 'check',
              onclick: function () {
                var v = f.collect();
                if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                colFile().update(r.id, { priorite: v.priorite, motifChangement: v.motifChangement });
                m.close(); afficher();
                U.toast('Priorité modifiée.', { type: 'success',
                  detail: r.patient + ' — ' + prioriteDe(v.priorite).label });
              } }),
          ],
        });
      }
    },
  });

  /* ==========================================================================
   * ÉCRAN D'APPEL DES PATIENTS
   * --------------------------------------------------------------------------
   * Destiné à un écran de salle d'attente : gros caractères, aucun détail
   * médical. Le patient y lit son NUMÉRO, jamais son nom ni son motif — une
   * salle d'attente n'est pas un lieu où l'on annonce publiquement pourquoi
   * quelqu'un consulte.
   * ======================================================================== */
  global.SIGH.screen('m2-affichage', {
    title: 'Écran d’appel des patients',
    description: 'Affichage de salle d’attente : numéros appelés et numéros suivants, sans aucune donnée médicale.',
    regle: 'Cet écran est destiné à la <strong>salle d’attente</strong>. Il n’affiche que des '
      + '<strong>numéros</strong> — jamais le nom du patient ni son motif. Une salle d’attente n’est pas un '
      + 'lieu où l’on annonce publiquement pourquoi quelqu’un consulte.',
    render: function (root) {
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      afficher();
      /* L'écran vit sans personne devant le clavier : il se rafraîchit seul. */
      var minuteur = setInterval(afficher, 15000);
      root.addEventListener('sigh:unmount', function () { clearInterval(minuteur); });
      return null;

      function afficher() {
        C.clear(vue);
        var cartes = el('div.grid.gap-4.sm\\:grid-cols-2.lg\\:grid-cols-3');
        POSTES_FILE.forEach(function (po) {
          var f = fileTriee(po.code);
          var dernier = C.sortBy(colFile().active().filter(function (t) {
            return t.poste === po.code && t.etat === 'servi';
          }), 'serviLe').reverse()[0];

          var carte = el('div.rounded-xl.border.border-slate-200.bg-white.p-5.shadow-sm');
          carte.appendChild(el('p.text-xs.font-semibold.uppercase.tracking-wide.text-slate-400', { text: po.label }));
          carte.appendChild(el('p.mt-2.text-xs.text-slate-500', { text: 'Numéro appelé' }));
          carte.appendChild(el('p.text-4xl.font-bold.tracking-tight.text-navy-900', {
            text: dernier ? dernier.numero : '—',
          }));
          carte.appendChild(el('p.mt-3.text-xs.text-slate-500', { text: 'Prochains numéros' }));
          carte.appendChild(el('p.text-lg.font-semibold.text-slate-700', {
            text: f.slice(0, 3).map(function (t) { return t.numero; }).join('   ·   ') || '—',
          }));
          carte.appendChild(el('p.mt-3.text-xs.text-slate-400', {
            text: f.length + ' patient(s) en attente',
          }));
          cartes.appendChild(carte);
        });
        vue.appendChild(cartes);
        vue.appendChild(el('p.text-center.text-xs.text-slate-400', {
          text: 'Actualisé automatiquement toutes les 15 secondes — dernière actualisation à '
            + C.heure(new Date().toISOString()),
        }));
        U.icons(vue);
      }
    },
  });


  /* ==========================================================================
   * PHASE 9 \u2014 AGENDA M\u00c9DECIN ET FILE PAR CABINET
   * --------------------------------------------------------------------------
   * Deux VUES des registres existants, jamais une seconde collection : le
   * m\u00e9decin lit SON agenda, le cabinet lit SA file. La doctrine des deux
   * listes (vague 35) tient : les patients qui attendent NOMM\u00c9MENT un
   * praticien et le vivier commun ne se fondent pas.
   * ======================================================================== */
  global.SIGH.screen('m2-agenda-medecin', {
    title: 'Agenda du m\u00e9decin',
    description: 'Les consultations d\u2019un praticien \u2014 pass\u00e9es, du jour et \u00e0 venir \u2014 lues depuis le registre.',
    regle: 'Une VUE du registre des consultations, filtr\u00e9e sur UN praticien : la donn\u00e9e n\u2019existe '
      + 'qu\u2019une fois. Un m\u00e9decin connect\u00e9 s\u2019ouvre sur son propre agenda.',
    render: function (root) {
      var host = el('div.space-y-4');
      root.appendChild(host);
      var medecins = S.collection('personnel').active()
        .filter(function (a) { return a.fonction === 'medecin'; });
      var sess = S.session() || {};
      var moi = medecins.filter(function (a) { return a.nomComplet === (sess.nomComplet || sess.nom); })[0];

      var sel = el('select.select');
      medecins.forEach(function (a) {
        sel.appendChild(el('option', { value: a.nomComplet }, a.nomComplet + ' \u2014 ' + (a.poste || '')));
      });
      if (moi) sel.value = moi.nomComplet;
      var barre = el('div.card');
      barre.appendChild(el('div.card-body.max-w-xl', null,
        el('div', null, [el('label.label', { text: 'Praticien' }), sel])));
      host.appendChild(barre);
      var vue = el('div.space-y-4');
      host.appendChild(vue);
      sel.addEventListener('change', afficher);
      afficher();
      U.icons(host);
      return null;

      function afficher() {
        var nom = sel.value;
        var rows = S.collection('consultations').active()
          .filter(function (r) { return r.medecin === nom; });
        var aujourdHui = C.iso(new Date());
        var duJour = rows.filter(function (r) { return String(r.date || '').slice(0, 10) === aujourdHui; });
        var aVenir = rows.filter(function (r) {
          return String(r.date || '').slice(0, 10) > aujourdHui && r.statut === 'planifiee';
        });
        C.clear(vue);
        vue.appendChild(U.kpiGrid([
          { label: 'Consultations au registre', value: C.num(rows.length), icon: 'stethoscope', tone: 'navy' },
          { label: 'Aujourd\u2019hui', value: C.num(duJour.length), icon: 'calendar', tone: duJour.length ? 'warning' : 'neutral' },
          { label: 'Planifi\u00e9es \u00e0 venir', value: C.num(aVenir.length), icon: 'calendar-plus', tone: 'info' },
          { label: 'Terminees ce mois-ci', value: C.num(rows.filter(function (r) {
            return r.statut === 'terminee' && String(r.date || '').slice(0, 7) === aujourdHui.slice(0, 7);
          }).length), icon: 'check-circle-2', tone: 'success' },
        ]));
        vue.appendChild(U.dataTable({
          title: 'Agenda \u2014 ' + nom, rows: C.sortBy(rows, 'date').reverse(),
          pageSize: 12, exportName: 'agenda-medecin',
          emptyMessage: 'Aucune consultation au registre pour ce praticien.',
          columns: [
            { key: 'date', label: 'Date et heure', render: function (r) { return C.dateHeure(r.date); } },
            { key: 'patient', label: 'Patient', render: function (r) { return r.patient + ' \u2014 ' + (r.patientCode || '\u2014'); } },
            { key: 'motif', label: 'Motif' },
            { key: 'type', label: 'Type', render: function (r) { return U.badge(r.type || 'Consultation', r.type === 'Urgence' ? 'danger' : 'neutral'); } },
            { key: 'statut', label: '\u00c9tat', render: function (r) { return U.statut(r.statut); } },
          ],
        }));
        U.icons(vue);
      }
    },
  });

  global.SIGH.screen('m2-file-cabinet', {
    title: 'File par cabinet',
    description: 'Qui attend quel praticien \u2014 et le vivier commun, que personne ne doit perdre de vue.',
    regle: 'DEUX listes, jamais fondues (doctrine de la vague 35) : les patients qui attendent '
      + '<strong>nomm\u00e9ment</strong> un praticien, et le <strong>vivier commun</strong> \u2014 la file de '
      + 'consultation est souvent commune dans une clinique de cette taille, et n\u2019afficher que \u00ab ses \u00bb '
      + 'patients ferait manquer la charge du service. Le rang n\u2019est jamais saisi.',
    render: function (root) {
      var host = el('div.space-y-4');
      root.appendChild(host);
      var tickets = S.collection('fileAttente').active()
        .filter(function (x) { return x.poste === 'consultation' && x.etat !== 'servi' && x.etat !== 'clos'; });
      var nommes = tickets.filter(function (x) { return x.praticien; });
      var vivier = tickets.filter(function (x) { return !x.praticien; });
      var parPraticien = {};
      nommes.forEach(function (x) { (parPraticien[x.praticien] = parPraticien[x.praticien] || []).push(x); });

      host.appendChild(U.kpiGrid([
        { label: 'En file de consultation', value: C.num(tickets.length), icon: 'list-ordered', tone: 'navy' },
        { label: 'Attendent un praticien nomm\u00e9', value: C.num(nommes.length), icon: 'user-check', tone: 'info' },
        { label: 'Vivier commun', value: C.num(vivier.length), icon: 'users', tone: vivier.length ? 'warning' : 'neutral',
          hint: 'Visibles de TOUS les cabinets' },
        { label: 'Cabinets sollicit\u00e9s', value: C.num(Object.keys(parPraticien).length), icon: 'door-open', tone: 'neutral' },
      ]));

      Object.keys(parPraticien).sort().forEach(function (nom) {
        host.appendChild(U.card('Cabinet \u2014 ' + nom + ' (' + parPraticien[nom].length + ')',
          K.miniTable(['Patient', 'Priorit\u00e9', 'Arriv\u00e9 \u00e0'],
            parPraticien[nom].map(function (x2) {
              return [x2.patient || x2.nom || '\u2014', x2.priorite || 'ordre d\u2019arriv\u00e9e',
                x2.arriveeLe ? C.dateHeure(x2.arriveeLe) : '\u2014'];
            }))));
      });

      host.appendChild(U.card('Vivier commun \u2014 par ordre d\u2019arriv\u00e9e, urgences en t\u00eate',
        vivier.length
          ? K.miniTable(['Patient', 'Priorit\u00e9', 'Arriv\u00e9 \u00e0'],
            vivier.map(function (x2) {
              return [x2.patient || x2.nom || '\u2014', x2.priorite || 'ordre d\u2019arriv\u00e9e',
                x2.arriveeLe ? C.dateHeure(x2.arriveeLe) : '\u2014'];
            }))
          : U.empty('Vivier vide \u2014 personne n\u2019attend sans praticien d\u00e9sign\u00e9.', { icon: 'users' })));
      U.icons(host);
      return null;
    },
  });

})(window);