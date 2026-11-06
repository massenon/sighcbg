/* =============================================================================
 * M1 — Patients & Dossier Médical Informatisé
 * -----------------------------------------------------------------------------
 * CDCT §10.3 — RG-01 : identifiant unique <sigle>/[n° d’ordre]/[année] (lu sur
 * C.BRAND.sigle), généré automatiquement à la création et non modifiable ensuite.
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core, U = global.SIGH.ui, S = global.SIGH.store, D = global.SIGH.data,
      P = global.SIGH.print, G = global.SIGH.charts, K = global.SIGH.kit, PR = global.SIGH.parcours;
  var el = C.el;

  /* --- RG-01 : génération du prochain code patient ------------------------- */
  function prochainCode() {
    var rows = S.collection('patients').all();
    var annee = new Date().getFullYear();
    var suffixe = String(annee).slice(-2);
    var max = 0;
    rows.forEach(function (p) {
      var m = /^CNT(\d+)\/(\d{2})$/.exec(p.code || '');
      if (m && m[2] === suffixe) max = Math.max(max, Number(m[1]));
    });
    return 'CNT' + (max + 1) + '/' + suffixe;
  }

  /* Antécédents et allergies acceptent désormais plusieurs valeurs. Le jeu de
     démonstration antérieur en portait une seule, sous forme de chaîne : les
     deux formes doivent cohabiter sans rien casser à l'affichage. */
  function liste(v) {
    if (v == null || v === '') return [];
    var t = Array.isArray(v) ? v : [v];
    return t.filter(function (x) {
      return x && x !== 'Aucun antécédent notable' && x !== 'Aucune allergie connue';
    });
  }
  function texteListe(v, vide) {
    var t = liste(v);
    return t.length ? t.join(', ') : (vide || '—');
  }

  function age(p) {
    if (!p.dateNaissance) return null;
    return Math.max(0, Math.floor(C.daysBetween(p.dateNaissance, new Date()) / 365.25));
  }

  function carteValide(p) {
    if (!p.assureur || !p.carteExpiration) return false;
    return C.toDate(p.carteExpiration) >= new Date(2026, 7, 16);
  }

  /* --- Champs du formulaire patient --------------------------------------- */
  function champs(record) {
    return [
      { type: 'section', label: 'Identification' },
      {
        name: 'code', label: 'Code dossier', col: 'full', readonly: true,
        value: record ? record.code : prochainCode(),
        help: 'RG-01 — attribué automatiquement au format ' + C.BRAND.sigle + '/[n° d’ordre]/[année] ; non modifiable après création.',
      },
      { name: 'nom', label: 'Nom', required: true },
      { name: 'prenom', label: 'Prénom(s)', required: true },
      { name: 'sexe', label: 'Sexe', type: 'select', required: true, options: [{ value: 'M', label: 'Masculin' }, { value: 'F', label: 'Féminin' }] },
      {
        name: 'dateNaissance', label: 'Date de naissance', type: 'date', required: true,
        validate: function (v) { return C.toDate(v) > new Date() ? 'La date ne peut pas être dans le futur.' : null; },
      },
      { name: 'groupeSanguin', label: 'Groupe sanguin', type: 'select', options: D.GROUPES_SANGUINS },

      { type: 'section', label: 'Coordonnées' },
      { name: 'telephone', label: 'Téléphone', type: 'tel', required: true },
      {
        name: 'quartier', label: 'Quartier', type: 'select',
        options: Object.keys(C.groupBy(S.collection('patients').active(), 'quartier')).sort(),
      },
      { name: 'adresse', label: 'Adresse', col: 'full' },
      { name: 'personneAPrevenir', label: 'Personne à prévenir', col: 'full' },

      { type: 'section', label: 'Éléments médicaux' },
      {
        /* Un patient cumule souvent plusieurs antécédents et plusieurs
           allergies : la liste à choix unique obligeait à en taire. */
        name: 'antecedents', label: 'Antécédents', type: 'multiselect', col: 'full',
        options: D.ANTECEDENTS.filter(function (a) { return a !== 'Aucun antécédent notable'; }),
        help: 'Repris automatiquement sur toute prescription et à la dispensation en pharmacie. '
          + 'Laisser vide si aucun antécédent notable.',
      },
      { name: 'antecedentsAutres', label: 'Autres antécédents (texte libre)', col: 'full' },
      {
        name: 'allergies', label: 'Allergies connues', type: 'multiselect', col: 'full',
        options: D.ALLERGIES.filter(function (a) { return a !== 'Aucune allergie connue'; }),
        help: 'Toute allergie déclarée bloque la délivrance du produit correspondant (M6). '
          + 'Laisser vide si aucune allergie connue.',
      },
      { name: 'traitementEnCours', label: 'Traitement en cours', col: 'full' },

      { type: 'section', label: 'Couverture assurance (M9)' },
      {
        name: 'assureur', label: 'Compagnie d’assurance', type: 'select',
        options: D.ASSUREURS.map(function (a) { return { value: a.code, label: a.nom }; }),
      },
      { name: 'numeroPolice', label: 'Numéro de police' },
      { name: 'tauxPriseEnCharge', label: 'Taux de prise en charge (%)', type: 'number', min: 0, max: 100 },
      {
        name: 'carteExpiration', label: 'Expiration de la carte', type: 'date',
        help: 'RG-09 — au-delà de cette date, la facturation est intégrale au patient.',
      },
    ];
  }

  /* --- Colonnes du répertoire --------------------------------------------- */
  function colonnes() {
    return [
      { key: 'code', label: 'Code dossier', nowrap: true, render: function (r) { return el('span.font-mono.text-xs.font-semibold.text-navy-800', { text: r.code }); } },
      {
        key: 'nom', label: 'Patient',
        value: function (r) { return r.nom + ' ' + r.prenom; },
        render: function (r) {
          return el('div.flex.items-center.gap-2', null, [
            el('span.grid.h-7.w-7.shrink-0.place-items-center.rounded-full.bg-slate-100.text-\\[10px\\].font-semibold.text-slate-600', { text: C.initials(r.nom + ' ' + r.prenom) }),
            el('div.min-w-0', null, [
              el('p.truncate.text-sm.font-medium.text-slate-800', { text: r.nom + ' ' + r.prenom }),
              el('p.text-xs.text-slate-400', { text: (r.sexe === 'F' ? 'Femme' : 'Homme') + ' — ' + (age(r) != null ? age(r) + ' ans' : '—') }),
            ]),
          ]);
        },
      },
      { key: 'telephone', label: 'Téléphone', nowrap: true },
      { key: 'quartier', label: 'Quartier' },
      { key: 'groupeSanguin', label: 'Groupe', align: 'right' },
      {
        /* Trois états dits explicitement : la validité de la carte décide de la
           facturation (RG-09), elle ne se devine pas à une nuance de couleur. */
        key: 'assureur', label: 'Assurance',
        text: function (r) {
          if (!r.assureur) return 'Non assuré';
          return (r.assureurNom || r.assureur) + ' — ' + (carteValide(r) ? 'carte valide' : 'carte non valide');
        },
        render: function (r) {
          if (!r.assureur) return U.badge('Non assuré', 'neutral');
          var ok = carteValide(r);
          return el('div.min-w-0', null, [
            el('div.flex.flex-wrap.items-center.gap-1\\.5', null, [
              U.badge(r.assureur, 'navy'),
              ok
                ? U.badge('Carte valide', 'success')
                : el('span.inline-flex.items-center.rounded.bg-danger-50.px-1\\.5.py-0\\.5.text-\\[10px\\].font-semibold.text-danger-700', { text: 'CARTE NON VALIDE' }),
            ]),
            el('p.mt-0\\.5.truncate.text-xs.text-slate-400', { text: r.souscripteur || '' }),
          ]);
        },
      },
      { key: 'dateCreation', label: 'Créé le', nowrap: true, text: function (r) { return C.dateFR(r.dateCreation); }, render: function (r) { return C.dateFR(r.dateCreation); } },
    ];
  }

  /* --- Fiche patient (drawer) ---------------------------------------------- */
  /* --------------------------------------------------------------------------
   * Statut d'assurance — la question posée en premier au guichet.
   * Trois états, et non deux : non assuré · assuré carte valide · assuré carte
   * NON VALIDE. Le troisième est le seul qui change la facturation (RG-09),
   * c'est celui qui doit sauter aux yeux.
   * ----------------------------------------------------------------------- */
  function statutAssurance(p) {
    if (!p.assureur) {
      return [
        U.badge('Non assuré', 'neutral'),
        el('span.text-xs.text-slate-500', { text: 'Facturation intégrale au patient' }),
      ];
    }
    var valide = carteValide(p);
    return [
      U.badge(p.assureurNom || p.assureur, 'navy'),
      valide
        ? U.badge('Carte valide', 'success')
        : el('span.inline-flex.items-center.gap-1.rounded-lg.border.border-danger-300.bg-danger-50.px-2.py-1.text-xs.font-semibold.text-danger-700', null, [
          C.icon('shield-alert', 'h-3.5 w-3.5'), 'CARTE NON VALIDE',
        ]),
      el('span.text-xs', {
        class: valide ? 'text-slate-500' : 'text-danger-700',
        text: valide
          ? 'Expire le ' + C.dateFR(p.carteExpiration) + (p.souscripteur ? ' · ' + p.souscripteur : '')
          : 'Expirée le ' + C.dateFR(p.carteExpiration) + ' — facturation intégrale (RG-09)',
      }),
    ];
  }

  function fiche(p) {
    var wrap = el('div.space-y-4');

    /* Bandeau d'identité — le statut d'assurance y figure en clair : c'est la
       première question posée au guichet, elle ne doit pas se chercher dans un
       onglet. Une carte expirée s'affiche en rouge (RG-09). */
    var head = el('div.flex.items-start.gap-3.rounded-lg.bg-navy-50.p-3');
    head.appendChild(el('span.grid.h-12.w-12.shrink-0.place-items-center.rounded-full.bg-navy-900.text-sm.font-semibold.text-white', { text: C.initials(p.nom + ' ' + p.prenom) }));
    head.appendChild(el('div.min-w-0.flex-1', null, [
      el('p.text-sm.font-semibold.text-slate-900', { text: p.nom + ' ' + p.prenom }),
      el('p.font-mono.text-xs.text-navy-700', { text: p.code }),
      el('p.mt-1.text-xs.text-slate-500', { text: (p.sexe === 'F' ? 'Femme' : 'Homme') + ' — ' + (age(p) != null ? age(p) + ' ans' : 'âge inconnu') + ' — Groupe ' + (p.groupeSanguin || '?') }),
      el('div.mt-2.flex.flex-wrap.items-center.gap-2', null, statutAssurance(p)),
    ]));
    wrap.appendChild(head);

    if (p.assureur && !carteValide(p)) {
      wrap.appendChild(K.note('<strong>Carte d’assurance expirée</strong> le ' + C.dateFR(p.carteExpiration)
        + '. En application de la règle RG-09, la facturation est intégrale au patient tant que la carte n’est pas renouvelée.',
        { tone: 'danger', icon: 'shield-alert' }));
    }

    /* Tout ce que le dossier doit rassembler — la fiche est le point où le
       parcours du patient se relit d'un bloc, quel que soit le module qui a
       produit la donnée. */
    function sien(nom) {
      return S.collection(nom).active().filter(function (x) { return x.patientId === p.id; });
    }
    var consultations = sien('consultations').filter(function (c) { return c.type !== 'Domicile'; });
    var domicile = sien('consultations').filter(function (c) { return c.type === 'Domicile'; });
    var admissions = sien('admissions');
    var observations = sien('observations');
    var temperatures = sien('temperatures');
    var visitesRecues = sien('visitesPatients');
    var sorties = sien('sorties');
    var sortiesAvis = sien('sortiesAvisMedical');
    var maternite = sien('suiviMaternite');
    var accouchements = sien('accouchements');
    var naissances = sien('naissances');
    var deces = sien('deces');
    var analyses = sien('demandesAnalyses');
    var ordonnances = sien('ordonnances');
    var factures = sien('factures');
    var soins = sien('soins');

    /* Une allergie déclarée doit sauter aux yeux : elle conditionne toute
       prescription et toute dispensation. */
    if (liste(p.allergies).length) {
      wrap.appendChild(K.note('<strong>Allergie(s) déclarée(s) : ' + texteListe(p.allergies) + '.</strong> '
        + 'Vérifier toute prescription et toute dispensation avant délivrance.',
        { tone: 'warning', icon: 'triangle-alert' }));
    }

    wrap.appendChild(U.tabs([
      {
        id: 'admin', label: 'Administratif',
        render: function () {
          return U.descList([
            ['Code dossier', el('span.font-mono', { text: p.code })],
            ['Nom et prénoms', p.nom + ' ' + p.prenom],
            ['Sexe', p.sexe === 'F' ? 'Féminin' : 'Masculin'],
            ['Date de naissance', C.dateFR(p.dateNaissance) + (age(p) != null ? ' (' + age(p) + ' ans)' : '')],
            ['Téléphone', p.telephone],
            ['Quartier', p.quartier],
            ['Adresse', p.adresse],
            ['Personne à prévenir', p.personneAPrevenir],
            ['Groupe sanguin', p.groupeSanguin],
            ['Dossier créé le', C.dateFR(p.dateCreation)],
          ]);
        },
      },
      {
        id: 'medical', label: 'Médical', badge: consultations.length,
        render: function () {
          if (!consultations.length) return U.empty('Aucune consultation enregistrée.', { icon: 'stethoscope' });
          return K.miniTable([
            { label: 'Date', render: function (c) { return C.dateFR(c.date); } },
            { label: 'Motif', key: 'motif' },
            { label: 'Diagnostic', key: 'diagnostic' },
            { label: 'Médecin', key: 'medecin' },
          ], C.sortBy(consultations, 'date', 'desc').slice(0, 15));
        },
      },
      {
        id: 'antecedents', label: 'Antécédents & allergies',
        render: function () {
          return U.descList([
            ['Antécédents', liste(p.antecedents).length
              ? el('div.flex.flex-wrap.gap-1', null, liste(p.antecedents).map(function (a) { return U.badge(a, 'warning'); }))
              : U.badge('Aucun antécédent notable', 'success')],
            ['Autres antécédents', p.antecedentsAutres || '—'],
            ['Allergies connues', liste(p.allergies).length
              ? el('div.flex.flex-wrap.gap-1', null, liste(p.allergies).map(function (a) { return U.badge(a, 'danger'); }))
              : U.badge('Aucune allergie connue', 'success')],
            ['Traitement en cours', p.traitementEnCours || '—'],
            ['Groupe sanguin', p.groupeSanguin || '—'],
          ]);
        },
      },
      {
        id: 'soins', label: 'Soins', badge: soins.length,
        render: function () {
          if (!soins.length) return U.empty('Aucun acte de soins enregistré pour ce patient.', { icon: 'heart-pulse' });
          return K.miniTable([
            { label: 'Date', render: function (x) { return C.dateFR(x.date) + ' à ' + x.heure; } },
            { label: 'Acte', key: 'acte' },
            { label: 'Produit utilisé', render: function (x) { return x.produit || '—'; } },
            { label: 'Soignant', key: 'soignant' },
            { label: 'État', render: function (x) { return U.statut(x.etat === 'realise' ? 'validee' : 'planifiee'); } },
          ], C.sortBy(soins, 'date', 'desc').slice(0, 20));
        },
      },
      {
        id: 'hospi', label: 'Hospitalisations', badge: admissions.length + observations.length,
        render: function () {
          var box = el('div.space-y-3');

          /* Chambres et lits occupés — la question du service quand il cherche
             où se trouve un patient. */
          var enCours = admissions.filter(function (a) { return a.statut === 'en_cours'; });
          if (enCours.length) {
            box.appendChild(K.note('<strong>Patient actuellement hospitalisé</strong> — '
              + enCours.map(function (a) { return 'chambre ' + (a.chambre || '?') + ', lit ' + (a.lit || '?'); }).join(' · ')
              + '. Une feuille de température est ouverte tant que le séjour dure.',
            { tone: 'info', icon: 'bed-double' }));
          }

          box.appendChild(U.card('Admissions et lits occupés', admissions.length
            ? K.miniTable([
              { label: 'Entrée', render: function (a) { return C.dateFR(a.dateEntree); } },
              { label: 'Sortie', render: function (a) { return a.dateSortie ? C.dateFR(a.dateSortie) : 'en cours'; } },
              { label: 'Chambre', render: function (a) { return a.chambre || '—'; } },
              { label: 'Lit', render: function (a) { return a.lit || '—'; } },
              { label: 'Diagnostic', key: 'diagnosticEntree' },
              { label: 'Statut', render: function (a) { return U.statut(a.statut); } },
            ], C.sortBy(admissions, 'dateEntree', 'desc'))
            : U.empty('Aucune hospitalisation.', { icon: 'bed-double' })));

          /* Mises en observation — distinctes des séjours. */
          if (observations.length) {
            box.appendChild(U.card('Mises en observation', K.miniTable([
              { label: 'Entrée', render: function (o) { return C.dateFR(o.dateEntree) + ' ' + C.heure(o.dateEntree); } },
              { label: 'Motif', key: 'motif' },
              { label: 'Unité', render: function (o) { return (o.uniteLabel || '').replace('Salle d’observation — ', ''); } },
              { label: 'Constantes', align: 'right', render: function (o) { return String((o.constantes || []).length); } },
              { label: 'Issue', render: function (o) { return o.orientationLabel || 'en cours'; } },
            ], C.sortBy(observations, 'dateEntree', 'desc'))));
          }

          /* Feuilles de température : les anciennes et celle en cours. */
          box.appendChild(U.card('Feuilles de température', temperatures.length
            ? K.miniTable([
              { label: 'Date', render: function (t) { return C.dateFR(t.date); } },
              { label: 'Température', align: 'right', render: function (t) { return (t.temperature || t.matin || '—') + ' °C'; } },
              { label: 'Tension', render: function (t) { return t.tension || '—'; } },
              { label: 'Pouls', align: 'right', render: function (t) { return t.pouls ? t.pouls + ' bpm' : '—'; } },
              { label: 'Relevé par', render: function (t) { return t.soignant || t.par || '—'; } },
            ], C.sortBy(temperatures, 'date', 'desc').slice(0, 20))
            : U.empty('Aucune feuille de température — le patient n’a pas séjourné.', { icon: 'thermometer' })));

          if (visitesRecues.length) {
            box.appendChild(U.card('Visites reçues pendant l’hospitalisation', K.miniTable([
              { label: 'Date', render: function (v) { return C.dateFR(v.date); } },
              { label: 'Visiteur', render: function (v) { return v.visiteur || v.nom || '—'; } },
              { label: 'Lien', render: function (v) { return v.lien || '—'; } },
              { label: 'Heure', render: function (v) { return v.heure || '—'; } },
            ], C.sortBy(visitesRecues, 'date', 'desc').slice(0, 15))));
          }

          if (sorties.length || sortiesAvis.length) {
            box.appendChild(U.card('Sorties', el('div.space-y-3', null, [
              sorties.length ? K.miniTable([
                { label: 'Date', render: function (s) { return C.dateFR(s.date || s.dateSortie); } },
                { label: 'Motif', render: function (s) { return s.motif || s.diagnostic || '—'; } },
                { label: 'Solde apuré', render: function (s) { return s.soldeApure ? U.badge('Oui', 'success') : U.badge('Non', 'danger'); } },
              ], C.sortBy(sorties, 'date', 'desc')) : null,
              sortiesAvis.length ? el('div', null, [
                K.note('<strong>Sortie contre avis médical</strong> — décharge signée, motif consigné (RG-08).', { tone: 'danger', icon: 'triangle-alert' }),
                K.miniTable([
                  { label: 'Date', render: function (s) { return C.dateFR(s.date || s.dateSortie); } },
                  { label: 'Motif invoqué', render: function (s) { return s.motif || '—'; } },
                  { label: 'Décharge', render: function (s) { return s.decharge ? U.badge('Signée', 'warning') : U.badge('Manquante', 'danger'); } },
                ], sortiesAvis),
              ]) : null,
            ])));
          }
          return box;
        },
      },
      {
        id: 'maternite', label: 'Maternité', badge: maternite.length + accouchements.length,
        render: function () {
          if (!maternite.length && !accouchements.length && !naissances.length && !deces.length) {
            return U.empty('Aucun suivi de maternité pour ce dossier.', { icon: 'baby' });
          }
          var box = el('div.space-y-3');
          if (maternite.length) {
            box.appendChild(U.card('Suivi de grossesse', K.miniTable([
              { label: 'Date', render: function (m) { return C.dateFR(m.date || m.dateConsultation); } },
              { label: 'Terme', render: function (m) { return m.terme || m.semaines || '—'; } },
              { label: 'Observation', render: function (m) { return m.observation || m.conclusion || '—'; } },
              { label: 'Sage-femme', render: function (m) { return m.sageFemme || m.soignant || '—'; } },
            ], C.sortBy(maternite, 'date', 'desc'))));
          }
          if (accouchements.length) {
            box.appendChild(U.card('Accouchements', K.miniTable([
              { label: 'Date', render: function (a) { return C.dateFR(a.date || a.dateAccouchement); } },
              { label: 'Type', render: function (a) { return a.type || a.modeAccouchement || '—'; } },
              { label: 'Issue', render: function (a) { return a.issue || '—'; } },
              { label: 'Sage-femme', render: function (a) { return a.sageFemme || '—'; } },
            ], C.sortBy(accouchements, 'date', 'desc'))));
          }
          if (naissances.length) {
            box.appendChild(U.card('Registre des naissances', K.miniTable([
              { label: 'Date', render: function (n) { return C.dateFR(n.date || n.dateNaissance); } },
              { label: 'Enfant', render: function (n) { return (n.nom || '') + ' ' + (n.prenom || ''); } },
              { label: 'Sexe', render: function (n) { return n.sexe === 'F' ? 'Féminin' : 'Masculin'; } },
              { label: 'Poids', render: function (n) { return n.poids ? n.poids + ' g' : '—'; } },
            ], C.sortBy(naissances, 'date', 'desc'))));
          }
          if (deces.length) {
            box.appendChild(U.card('Registre des décès', K.miniTable([
              { label: 'Date', render: function (d) { return C.dateFR(d.date || d.dateDeces); } },
              { label: 'Cause', render: function (d) { return d.cause || '—'; } },
              { label: 'Constaté par', render: function (d) { return d.medecin || '—'; } },
            ], deces)));
          }
          return box;
        },
      },
      {
        id: 'laboratoire', label: 'Analyses & résultats', badge: analyses.length,
        render: function () {
          if (!analyses.length) return U.empty('Aucune demande d’analyse pour ce patient.', { icon: 'flask-conical' });
          /* Le RBAC métier s'applique ici comme ailleurs : un résultat masqué
             est annoncé, pas escamoté. */
          var vus = PR.filtrerResultats(analyses);
          var box = el('div.space-y-3');
          if (vus.length < analyses.length) {
            box.appendChild(K.note('<strong>' + (analyses.length - vus.length) + ' résultat(s) hors de votre périmètre.</strong> '
              + PR.capacites().label + ' — ' + (PR.capacites().note || ''), { tone: 'warning', icon: 'shield-alert' }));
          }
          box.appendChild(K.miniTable([
            { label: 'Date', render: function (a) { return C.dateFR(a.dateHeure); } },
            { label: 'Analyse', key: 'analyse' },
            { label: 'Prescripteur', key: 'prescripteur' },
            { label: 'État', render: function (a) { return U.statut(a.etatAnalyse); } },
            { label: 'Résultat', render: function (a) { return a.resultat != null ? String(a.resultat) : '—'; } },
            {
              label: 'Conclusion',
              render: function (a) {
                if (!a.conclusion) return '—';
                return a.conclusion === 'Normal' ? U.badge('Normal', 'success') : U.badge(a.conclusion, 'warning');
              },
            },
          ], C.sortBy(vus, 'dateHeure', 'desc').slice(0, 25)));
          return box;
        },
      },
      {
        id: 'ordonnances', label: 'Ordonnances', badge: ordonnances.length,
        render: function () {
          if (!ordonnances.length) return U.empty('Aucune ordonnance émise pour ce patient.', { icon: 'scroll-text' });
          return K.miniTable([
            { label: 'N°', render: function (o) { return el('span.font-mono.text-xs', { text: o.numero }); } },
            { label: 'Date', render: function (o) { return C.dateFR(o.date); } },
            { label: 'Prescripteur', key: 'medecin' },
            { label: 'Diagnostic', render: function (o) { return o.diagnostic || '—'; } },
            {
              label: 'Contenu',
              render: function (o) {
                var t = [];
                if ((o.medicaments || []).length) t.push(o.medicaments.length + ' médic.');
                if ((o.analyses || []).length) t.push(o.analyses.length + ' analyse(s)');
                if ((o.actes || []).length) t.push(o.actes.length + ' acte(s)');
                return t.join(' · ') || '—';
              },
            },
            { label: 'Montant', align: 'right', render: function (o) { return C.money(o.montant, false); } },
            {
              label: 'Dispensation',
              render: function (o) {
                var m = { servie: ['Servie', 'success'], en_attente: ['À délivrer', 'warning'], sans_objet: ['—', 'neutral'] };
                var x = m[o.statutDispensation] || m.sans_objet;
                return U.badge(x[0], x[1]);
              },
            },
          ], C.sortBy(ordonnances, 'date', 'desc').slice(0, 20));
        },
      },
      {
        id: 'domicile', label: 'À domicile', badge: domicile.length,
        render: function () {
          if (!domicile.length) return U.empty('Aucune consultation ni soin à domicile.', { icon: 'house' });
          return K.miniTable([
            { label: 'Date', render: function (d) { return C.dateFR(d.date); } },
            { label: 'Motif', key: 'motif' },
            { label: 'Praticien', key: 'medecin' },
            { label: 'Diagnostic', render: function (d) { return d.diagnostic || '—'; } },
            { label: 'Tarif', align: 'right', render: function (d) { return C.money(d.tarif || 0, false); } },
          ], C.sortBy(domicile, 'date', 'desc'));
        },
      },
      {
        id: 'financier', label: 'Financier', badge: factures.length,
        render: function () {
          var du = C.sum(factures, 'reliquat');
          var box = el('div.space-y-3');
          box.appendChild(U.kpiGrid([
            { label: 'Total facturé', value: C.money(C.sum(factures, 'montantTTC')), icon: 'receipt' },
            { label: 'Reste à payer', value: C.money(du), icon: 'wallet', tone: du > 0 ? 'danger' : 'success' },
          ], 'grid-cols-2'));
          /* Un patient assuré reçoit DEUX pièces : ce que l'assureur couvre et
             ce qu'il ne couvre pas. La fiche doit les distinguer, sans quoi le
             guichet ne sait pas ce qu'il réclame ni à qui. */
          if (p.assureur) {
            box.appendChild(K.note('Patient assuré : les prestations couvertes et non couvertes font '
              + '<strong>deux factures distinctes</strong> — pièce <strong>-A</strong> pour ce que l’assureur prend '
              + 'en charge, pièce <strong>-B</strong> pour ce qui reste au patient.', { tone: 'info', icon: 'files' }));
          }
          box.appendChild(factures.length
            ? K.miniTable([
              { label: 'N° facture', render: function (f) { return el('span.font-mono.text-xs', { text: f.numero }); } },
              { label: 'Date', render: function (f) { return C.dateFR(f.date); } },
              { label: 'Nature', key: 'type' },
              {
                label: 'Volet',
                render: function (f) {
                  if (f.volet === 'couvert') return U.badge('Couvert par l’assureur', 'success');
                  if (f.volet === 'non_couvert') return U.badge('Non couvert', 'warning');
                  return el('span.text-xs.text-slate-400', { text: 'Pièce unique' });
                },
              },
              { label: 'Montant', align: 'right', render: function (f) { return C.money(f.montantTTC, false); } },
              { label: 'Part assureur', align: 'right', render: function (f) { return f.partAssurance ? C.money(f.partAssurance, false) : '—'; } },
              { label: 'Part patient', align: 'right', render: function (f) { return C.money(f.partPatient != null ? f.partPatient : f.montantTTC, false); } },
              { label: 'Statut', render: function (f) { return U.statut(f.statutPaiement); } },
            ], C.sortBy(factures, 'date', 'desc').slice(0, 20))
            : U.empty('Aucune facture.', { icon: 'receipt' }));
          return box;
        },
      },
      {
        id: 'assurance', label: 'Assurance',
        render: function () {
          if (!p.assureur) return U.empty('Ce patient n’est couvert par aucune assurance.', { icon: 'shield-off' });
          return U.descList([
            ['Compagnie', p.assureurNom || p.assureur],
            ['Numéro de police', p.numeroPolice],
            ['Taux de prise en charge', p.tauxPriseEnCharge + ' %'],
            ['Expiration de la carte', C.dateFR(p.carteExpiration)],
            ['Validité (RG-09)', carteValide(p) ? U.badge('Carte valide', 'success') : U.badge('Carte expirée', 'danger')],
          ]);
        },
      },
      {
        id: 'audit', label: 'Traçabilité',
        render: function () {
          return U.timeline([
            { title: 'Dossier créé', detail: 'Code ' + p.code + ' attribué automatiquement (RG-01)', date: C.dateFR(p.dateCreation), tone: 'success' },
            p._modifieLe ? { title: 'Dossier modifié', detail: 'Par ' + p._modifiePar, date: C.dateHeure(p._modifieLe), tone: 'info' } : null,
            p._archiveLe ? { title: 'Dossier archivé', detail: p._motifArchivage || '—', date: C.dateHeure(p._archiveLe), tone: 'warning' } : null,
          ].filter(Boolean));
        },
      },
    ]));
    return wrap;
  }

  /* --- État imprimable : fiche patient ------------------------------------- */
  function etatFiche(p) {
    var consultations = C.sortBy(S.collection('consultations').active().filter(function (c) { return c.patientId === p.id; }), 'date', 'desc');
    var contenu = el('div.space-y-4');
    contenu.appendChild(P.tableau([
      { label: 'Rubrique', key: 'k' }, { label: 'Information', key: 'v' },
    ], [
      { k: 'Code dossier', v: p.code },
      { k: 'Nom et prénoms', v: p.nom + ' ' + p.prenom },
      { k: 'Sexe', v: p.sexe === 'F' ? 'Féminin' : 'Masculin' },
      { k: 'Date de naissance', v: C.dateFR(p.dateNaissance) + (age(p) != null ? ' (' + age(p) + ' ans)' : '') },
      { k: 'Groupe sanguin', v: p.groupeSanguin || '—' },
      { k: 'Antécédents', v: texteListe(p.antecedents, 'Aucun antécédent notable') },
      { k: 'Allergies connues', v: texteListe(p.allergies, 'Aucune allergie connue') },
      { k: 'Traitement en cours', v: p.traitementEnCours || '—' },
      { k: 'Téléphone', v: p.telephone },
      { k: 'Adresse', v: p.adresse || p.quartier },
      { k: 'Personne à prévenir', v: p.personneAPrevenir || '—' },
      { k: 'Assurance', v: p.assureurNom ? p.assureurNom + ' — ' + p.tauxPriseEnCharge + ' % (carte au ' + C.dateFR(p.carteExpiration) + ')' : 'Aucune' },
    ]));

    if (consultations.length) {
      contenu.appendChild(el('p.mt-4.mb-1.text-\\[11px\\].font-bold.uppercase.text-navy-900', { text: 'Historique des consultations' }));
      contenu.appendChild(P.tableau([
        { label: 'Date', value: function (c) { return C.dateFR(c.date); } },
        { label: 'Motif', key: 'motif' },
        { label: 'Diagnostic', key: 'diagnostic' },
        { label: 'Médecin', key: 'medecin' },
      ], consultations.slice(0, 20)));
    }

    P.etat({
      titre: 'Fiche patient',
      sousTitre: 'Dossier ' + p.code,
      cartouche: [
        ['Patient', p.nom + ' ' + p.prenom],
        ['Code dossier', p.code],
        ['Date de naissance', C.dateFR(p.dateNaissance)],
        ['Groupe sanguin', p.groupeSanguin || '—'],
      ],
      contenu: contenu,
      signatures: [{ role: 'Le Secrétaire Médical' }, { role: 'Le Directeur Médical', nom: 'BASSONGUI Chabi Séko' }],
    });
  }

  /* ==========================================================================
   * ÉCRAN — Répertoire des patients
   * ======================================================================== */
  global.SIGH.screen('m1-patients', {
    title: 'Répertoire des patients',
    description: 'Dossier patient unique et centralisé : identification, coordonnées, couverture assurance, historique médical et financier.',
    regle: '<strong>RG-01</strong> — Chaque patient est identifié par un code unique au format <code>' + C.BRAND.sigle + '/[n° d’ordre]/[année]</code>, généré automatiquement et non modifiable après création.',
    /* La création se déclenche depuis le bouton « Nouveau » de la barre du
       tableau, posé par kit.crud sur tous les écrans de gestion. Le bandeau ne
       le redouble pas : il ne porte que ce qui mène ailleurs. */
    actions: function () {
      return [
        K.btn('Plan de numérisation', { icon: 'scan-line', onclick: function () { global.SIGH.app.go('m1-numerisation'); } }),
      ];
    },
    render: K.crud({
      collection: 'patients', entite: 'patient', entiteP: 'patients', module: 'M1',
      columns: colonnes, fields: champs, defaultSort: 'code', drawerWidth: 'max-w-3xl',
      formSize: 'lg',
      source: 'Registres patients de la clinique — reprise progressive (CDCT §24).',
      onCreate: function () {
        return { code: prochainCode(), dateCreation: C.iso(new Date()), statut: 'actif', tauxPriseEnCharge: 0 };
      },
      transform: function (v) {
        var a = D.ASSUREURS.filter(function (x) { return x.code === v.assureur; })[0];
        v.assureurNom = a ? a.nom : null;
        v.age = null;
        return v;
      },
      beforeSave: function (v, record) {
        if (!record) {
          var exists = S.collection('patients').all().some(function (p) { return p.code === v.code; });
          if (exists) return 'Ce code dossier est déjà attribué. Recharger la page pour obtenir le suivant.';
        }
        return null;
      },
      filters: [
        { name: 'sexe', label: 'Sexe', options: [{ value: 'M', label: 'Masculin' }, { value: 'F', label: 'Féminin' }] },
        {
          name: 'couverture', label: 'Couverture',
          options: [{ value: 'assure', label: 'Assurés' }, { value: 'non', label: 'Non assurés' }, { value: 'expiree', label: 'Carte expirée' }],
          match: function (r, v) {
            if (v === 'assure') return !!r.assureur;
            if (v === 'non') return !r.assureur;
            if (v === 'expiree') return !!r.assureur && !carteValide(r);
            return true;
          },
        },
        {
          name: 'quartier', label: 'Quartier',
          options: Object.keys(C.groupBy(S.collection('patients').active(), 'quartier')).sort(),
          match: function (r, v) { return r.quartier === v; },
        },
      ],
      kpis: function (rows) {
        var assures = rows.filter(function (p) { return !!p.assureur; });
        var expirees = assures.filter(function (p) { return !carteValide(p); });
        var annee = rows.filter(function (p) { return C.toDate(p.dateCreation).getFullYear() === 2026; });
        return [
          { label: 'Dossiers actifs', value: C.num(rows.length), icon: 'users', tone: 'navy' },
          { label: 'Créés en 2026', value: C.num(annee.length), icon: 'user-plus', tone: 'success' },
          { label: 'Patients assurés', value: C.num(assures.length), icon: 'shield-check', tone: 'info', hint: C.pct(rows.length ? assures.length / rows.length * 100 : 0) + ' du répertoire' },
          { label: 'Cartes expirées', value: C.num(expirees.length), icon: 'shield-alert', tone: expirees.length ? 'danger' : 'neutral', hint: 'Facturation intégrale (RG-09)' },
        ];
      },
      detail: fiche,
      etat: etatFiche,
      detailSubtitle: function (p) { return p.code + ' — ' + (p.quartier || ''); },
      /* FUSION À ZONES (arbitrage du 31/08/2026, Bug 1) : le dossier de
         consultation à deux zones est un ONGLET du répertoire — mais gardé
         par les droits de l'ancien écran : la Direction l'a fermé nommément à
         certains profils (biologiste, échographiste), et la fusion ne doit
         rien rouvrir. Un onglet refusé est ABSENT, pas grisé. */
      extraTabs: function () {
        var session = S.session() || {};
        var nav = global.SIGH.nav;
        var d2 = nav && nav.droitsEcran ? nav.droitsEcran(session.role, 'm1-dossier-etendu', 'M1') : { voir: true };
        if (!d2.voir) return [];
        return [{
          id: 'dossiers-2-zones',
          label: 'Dossiers de consultation (2 zones)',
          badge: colDossiers().active().length,
          render: function () { return construireDossiersEtendus(); },
        }];
      },
    }),
  });

  /* ==========================================================================
   * ÉCRAN — Fiche patient (sélection puis consultation)
   * ======================================================================== */
  global.SIGH.screen('m1-patient-profil', {
    title: 'Fiche patient',
    description: 'Vue consolidée d’un dossier : administratif, médical, hospitalisations, financier et assurance.',
    render: function (root) {
      var patients = S.collection('patients').active();
      var host = el('div.space-y-4');
      var courant = patients[0];

      var selWrap = el('div.card');
      var body = el('div.card-body.flex.flex-wrap.items-end.gap-3');
      var tries = C.sortBy(patients, 'code');
      var sel = U.combo(tries.map(function (p) {
        return { value: p.id, label: p.nom + ' ' + p.prenom, detail: p.code + ' — ' + p.quartier, icon: 'user' };
      }), {
        value: tries.length ? tries[0].id : '',
        searchPlaceholder: 'Nom, prénom, code CNT, quartier…',
        placeholder: 'Choisir un dossier patient',
      });
      sel.classList.add('max-w-md');
      body.appendChild(el('div.flex-1', null, [el('label.label', { text: 'Sélectionner un dossier patient' }), sel]));
      /* Le droit décide de la COMMANDE, pas seulement de ce qui suit : un
         bouton qui mène à un refus fait perdre plus de temps qu'un bouton
         absent, et il fait douter du logiciel. */
      var droitsFiche = K.droits('M1');
      if (!droitsFiche.editer) {
        body.appendChild(K.note('<strong>Lecture seule</strong> — votre profil consulte le dossier '
          + 'sans le modifier. Ce périmètre est fixé par la matrice des droits (écran '
          + '<em>Rôles &amp; permissions</em>), non par cet écran.',
        { tone: 'neutral', icon: 'lock' }));
      }
      if (droitsFiche.editer) body.appendChild(K.btn('Modifier le dossier', {
        variant: 'primary', icon: 'pencil',
        onclick: function () {
          if (!courant) return;
          K.modifier(S.collection('patients', { module: 'M1', entite: 'Patient' }), champs(courant), courant, function () {
            patients = S.collection('patients').active();
            courant = patients.filter(function (p) { return p.id === sel.value; })[0] || courant;
            afficher();
          });
        },
      }));
      body.appendChild(K.btn('Fiche de consultation', {
        icon: 'clipboard-list',
        title: 'Ouvrir une consultation pour ce patient',
        onclick: function () { global.SIGH.app.go('m2-consultation-fiche'); },
      }));
      body.appendChild(K.btn('Documents numérisés', {
        icon: 'paperclip',
        onclick: function () { global.SIGH.app.go('m1-documents'); },
      }));
      body.appendChild(K.btn('Imprimer la fiche', { icon: 'printer', onclick: function () { etatFiche(courant); } }));
      body.appendChild(K.lien('m1-patients', 'Retour au répertoire', { icon: 'arrow-left' }));
      selWrap.appendChild(body);
      host.appendChild(selWrap);

      var ficheHost = el('div.card');
      var ficheBody = el('div.card-body');
      ficheHost.appendChild(ficheBody);
      host.appendChild(ficheHost);

      function afficher() {
        courant = patients.filter(function (p) { return p.id === sel.value; })[0] || patients[0];
        C.clear(ficheBody);
        if (!courant) { ficheBody.appendChild(U.empty('Aucun patient enregistré.', { icon: 'users' })); return; }
        ficheBody.appendChild(fiche(courant));
        U.icons(ficheBody);
      }
      sel.addEventListener('change', afficher);
      root.appendChild(host);
      afficher();
      return null;
    },
  });

  /* ==========================================================================
   * ÉCRAN — Dossier médical informatisé
   * ======================================================================== */
  global.SIGH.screen('m1-dossier-medical', {
    title: 'Dossier médical informatisé',
    description: 'Fusionné dans le répertoire des patients — un seul point d’entrée du dossier (Bug 1).',
    render: function (root) {
      /* PAGE CONSERVÉE, CONTENU FUSIONNÉ (arbitrage du 31/08/2026, Bug 1) :
         cet écran dupliquait les consultations sous un autre nom — un doublon
         que la Direction a demandé de résorber. Retirer l'entrée du manifeste
         casserait les liens et les surcharges qui la visent : l'écran renvoie. */
      root.appendChild(el('div.mx-auto.max-w-xl.space-y-4.py-10', null, [
        K.note('Le dossier médical informatisé est <strong>fusionné dans le répertoire des '
          + 'patients</strong> : la fiche de chaque patient y agrège consultations, hospitalisations, '
          + 'analyses, ordonnances et documents — et les épisodes de soins se tiennent dans '
          + '<strong>Consultations</strong> (M2), leur écran d’origine.', { tone: 'info', icon: 'merge' }),
        el('div.flex.flex-wrap.justify-center.gap-2', null, [
          K.btn('Ouvrir le répertoire des patients', {
            variant: 'primary', icon: 'users',
            onclick: function () { global.SIGH.app.go('m1-patients'); },
          }),
          K.btn('Consultations', {
            icon: 'stethoscope',
            onclick: function () { global.SIGH.app.go('m2-consultations'); },
          }),
        ]),
      ]));
      return null;
    },
  });

  /* ==========================================================================
   * ÉCRAN — Antécédents & allergies
   * ======================================================================== */
  global.SIGH.screen('m1-antecedents', {
    title: 'Antécédents & allergies',
    description: 'Recensement des antécédents médicaux, chirurgicaux et des allergies connues, consultables depuis toute prescription.',
    regle: 'Les éléments saisis ici <strong>appartiennent au dossier du patient</strong> : ils sont repris dans la fiche patient, '
      + 'à la prescription (M2) et à la dispensation en pharmacie (M6).',
    render: function (root) {
      var col = S.collection('patients', { module: 'M1', entite: 'Patient' });
      var host = el('div.space-y-4');
      var table;

      function risque(p) {
        return liste(p.antecedents).some(function (a) { return D.ANTECEDENTS_RISQUE.indexOf(a) !== -1; });
      }
      function allergique(p) { return liste(p.allergies).length > 0; }

      var kpiHost = el('div');
      function majKpis() {
        var rows = col.active();
        C.clear(kpiHost);
        kpiHost.appendChild(U.kpiGrid([
          { label: 'Dossiers renseignés', value: C.num(rows.filter(function (p) { return liste(p.antecedents).length > 0; }).length), icon: 'clipboard-list', tone: 'navy' },
          { label: 'Allergies déclarées', value: C.num(rows.filter(allergique).length), icon: 'triangle-alert', tone: 'warning' },
          { label: 'Antécédents à risque', value: C.num(rows.filter(risque).length), icon: 'heart-pulse', tone: 'danger' },
          { label: 'Sans antécédent notable', value: C.num(rows.filter(function (p) { return liste(p.antecedents).length === 0; }).length), icon: 'check', tone: 'success' },
        ]));
        U.icons(kpiHost);
      }
      majKpis();
      host.appendChild(kpiHost);

      host.appendChild(K.note('Les allergies déclarées sont remontées automatiquement à la prescription (M2) et à la dispensation en pharmacie (M6) afin de bloquer toute délivrance contre-indiquée.', { tone: 'info' }));

      /* Saisie des éléments médicaux d'un dossier — les mêmes champs que la
         section « Éléments médicaux » de la fiche patient. */
      function modifier(p) {
        var f = U.form([
          { name: 'antecedents', label: 'Antécédent principal', type: 'select', options: D.ANTECEDENTS, col: 'full' },
          { name: 'antecedentsAutres', label: 'Autres antécédents', col: 'full' },
          { name: 'allergies', label: 'Allergies connues', type: 'select', options: D.ALLERGIES, col: 'full' },
          { name: 'traitementEnCours', label: 'Traitement en cours', col: 'full' },
          { name: 'groupeSanguin', label: 'Groupe sanguin', type: 'select', options: D.GROUPES_SANGUINS },
        ], p);
        var m = U.modal({
          title: 'Antécédents et allergies',
          subtitle: p.nom + ' ' + p.prenom + ' — ' + p.code,
          size: 'md', body: f,
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Enregistrer', {
              variant: 'primary', icon: 'save',
              onclick: function () {
                var v = f.collect();
                if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                var res = col.update(p.id, v);
                m.close(); table.refresh(); majKpis();
                U.toast('Éléments médicaux enregistrés.', {
                  type: 'success', detail: p.code,
                  undo: function () { res.undo(); table.refresh(); majKpis(); },
                });
              },
            }),
          ],
        });
      }

      table = U.dataTable({
        title: 'Antécédents et allergies par dossier',
        rows: function () { return col.active(); },
        exportName: 'antecedents', pageSize: 12,
        searchPlaceholder: 'Patient, code dossier, antécédent…',
        filters: [
          { name: 'allergies', label: 'Allergie', options: D.ALLERGIES },
          { name: 'antecedents', label: 'Antécédent', options: D.ANTECEDENTS },
        ],
        columns: [
          { key: 'code', label: 'Dossier', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.code }); } },
          {
            key: 'nom', label: 'Patient',
            value: function (r) { return r.nom + ' ' + r.prenom; },
            render: function (r) { return r.nom + ' ' + r.prenom; },
          },
          { key: 'groupeSanguin', label: 'Groupe', align: 'right' },
          {
            key: 'antecedents', label: 'Antécédents',
            render: function (r) {
              if (!liste(r.antecedents).length) return el('span.text-xs.text-slate-400', { text: 'Aucun antécédent notable' });
              var bloc = el('div.space-y-0\\.5', null, [
                risque(r) ? U.badge(texteListe(r.antecedents), 'danger') : el('span.text-sm', { text: texteListe(r.antecedents) }),
              ]);
              if (r.antecedentsAutres) bloc.appendChild(el('p.text-xs.text-slate-400', { text: r.antecedentsAutres }));
              return bloc;
            },
          },
          {
            key: 'allergies', label: 'Allergies',
            render: function (r) {
              return allergique(r) ? U.badge(texteListe(r.allergies), 'warning')
                : el('span.text-xs.text-slate-400', { text: 'Aucune allergie connue' });
            },
          },
          { key: 'traitementEnCours', label: 'Traitement en cours', render: function (r) { return r.traitementEnCours || '—'; } },
          {
            key: '_risque', label: 'Risque', align: 'right',
            text: function (r) { return risque(r) ? 'Élevé' : 'Standard'; },
            render: function (r) { return risque(r) ? U.badge('Élevé', 'danger') : U.badge('Standard', 'neutral'); },
          },
        ],
        /* Le clic sur la ligne ouvre le formulaire : sans ce garde-fou, il
           contournerait le bouton retiré. Un contrôle qu'on peut contourner
           n'en est pas un. */
        onRowClick: function (r) {
          if (!K.droits('M1').editer) {
            U.toast('Modification impossible.', { type: 'error',
              detail: 'Votre profil consulte les antécédents sans les modifier.' });
            return;
          }
          modifier(r);
        },
        rowActions: function (r) {
          var actes = [];
          if (K.droits('M1').editer) {
            actes.push(K.iconBtn('pencil', 'Modifier les antécédents', function () { modifier(r); }));
          }
          actes.push(K.iconBtn('user', 'Ouvrir la fiche patient',
            function () { global.SIGH.app.go('m1-patient-profil'); }));
          return actes;
        },
      });
      host.appendChild(table);
      host.appendChild(K.source('Dossier patient — les éléments médicaux sont saisis par le personnel soignant habilité (RG-13).'));
      root.appendChild(host);
      return null;
    },
  });

  /* ==========================================================================
   * DOCUMENTS NUMÉRISÉS DU PATIENT
   * --------------------------------------------------------------------------
   * Le dossier papier ne disparaît pas d'un coup : la clinique numérise au fil
   * de l'eau et rattache. L'écran ne se contentait que d'afficher un inventaire
   * régénéré à chaque affichage ; il faut pouvoir DÉPOSER — un scan, une photo,
   * un PDF — et le retrouver au dossier.
   *
   * Le fichier est conservé dans le poste, comme le reste des données : aucune
   * requête réseau, conformément à la contrainte hors ligne de la clinique.
   * ======================================================================== */
  var TYPES_DOCUMENT = ['Ordonnance', 'Résultat de laboratoire', 'Compte rendu médical',
    'Consentement éclairé', 'Imagerie / Échographie', 'Bulletin d’hospitalisation',
    'Facture', 'Pièce d’identité', 'Carte d’assurance', 'Certificat médical'];

  function colDocs() { return S.collection('documentsPatient', { module: 'M1', entite: 'document', prefix: 'DOC' }); }

  function amorcerDocuments() {
    var db = S.raw();
    if (db.documentsPatient && db.documentsPatient.length) return;
    var pats = S.collection('patients').active();
    var rnd = C.seeded(11);
    var out = [];
    pats.slice(0, 45).forEach(function (p) {
      var n = C.between(rnd, 1, 3);
      for (var k = 0; k < n; k++) {
        out.push({
          id: 'DOC' + C.pad(out.length + 1, 4), statut: 'actif',
          reference: 'GED-' + C.pad(out.length + 1, 5),
          patientId: p.id, code: p.code, patient: p.nom + ' ' + p.prenom,
          type: C.pick(rnd, TYPES_DOCUMENT),
          date: C.iso(C.addDays(new Date(2026, 7, 16), -C.between(rnd, 0, 400))),
          fichier: null, format: C.pick(rnd, ['PDF', 'JPEG', 'PNG']),
          taille: C.between(rnd, 80, 3200) * 1024,
          donnees: null,
          etat: C.pick(rnd, ['valide', 'valide', 'en_attente']),
          depose: C.pick(rnd, ['OROU YO Edmond', 'KINNOU Addoul Ganiou', 'GARBA Yahouza']),
        });
      }
    });
    db.documentsPatient = out;
    S.save();
  }

  function poidsDoc(o) {
    if (!o) return '—';
    return o > 1024 * 1024 ? (o / 1024 / 1024).toFixed(1) + ' Mo' : Math.round(o / 1024) + ' Ko';
  }

  global.SIGH.screen('m1-documents', {
    title: 'Documents numérisés du patient',
    description: 'Ordonnances, résultats d’analyses, comptes rendus, consentements et imagerie rattachés au dossier patient.',
    regle: 'Un document se <strong>dépose</strong> depuis cet écran — PDF, PNG ou JPEG — et reste rattaché au '
      + 'dossier du patient. Le fichier est conservé <strong>dans le poste</strong>, sans requête réseau. '
      + '<strong>RG-14</strong> — retirer un document l’archive : il reste restaurable depuis la corbeille.',
    actions: function () {
      return [
        K.btn('Répertoire des patients', { icon: 'users', onclick: function () { global.SIGH.app.go('m1-patients'); } }),
        K.btn('Plan de numérisation', { icon: 'scan-line', onclick: function () { global.SIGH.app.go('m1-numerisation'); } }),
      ];
    },
    render: function (root) {
      amorcerDocuments();
      dessiner();
      return null;

      function dessiner() {
        C.clear(root);
        var rows = colDocs().active();
        var host = el('div.space-y-4');

        host.appendChild(U.kpiGrid([
          { label: 'Documents numérisés', value: C.num(rows.length), icon: 'files', tone: 'navy' },
          { label: 'Validés', value: C.num(rows.filter(function (r) { return r.etat === 'valide'; }).length), icon: 'file-check-2', tone: 'success' },
          { label: 'En attente de validation', value: C.num(rows.filter(function (r) { return r.etat === 'en_attente'; }).length), icon: 'file-clock', tone: 'warning' },
          { label: 'Dossiers couverts', value: C.num(Object.keys(C.groupBy(rows, 'code')).length), icon: 'folder-open', tone: 'info' },
        ]));

        host.appendChild(U.dataTable({
          title: 'Bibliothèque documentaire du patient',
          rows: rows, exportName: 'documents-patients', pageSize: 15, searchable: true,
          defaultSort: 'date', defaultDir: 'desc',
          filters: [
            { name: 'type', label: 'Type de document', options: TYPES_DOCUMENT },
            {
              name: 'fichier', label: 'Fichier',
              options: [{ value: 'oui', label: 'Fichier déposé' }, { value: 'non', label: 'Référencé seulement' }],
              match: function (r, v) { return v === 'oui' ? !!r.donnees : !r.donnees; },
            },
          ],
          columns: [
            { key: 'reference', label: 'Référence', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.reference }); } },
            { key: 'code', label: 'Dossier', nowrap: true },
            { key: 'patient', label: 'Patient' },
            { key: 'type', label: 'Type', render: function (r) { return U.badge(r.type, 'navy'); } },
            { key: 'date', label: 'Date', nowrap: true, text: function (r) { return C.dateFR(r.date); }, render: function (r) { return C.dateFR(r.date); } },
            {
              key: 'format', label: 'Fichier', nowrap: true,
              render: function (r) {
                return el('div.min-w-0', null, [
                  el('p.text-xs.text-slate-600', { text: (r.format || '—') + ' · ' + poidsDoc(r.taille) }),
                  r.donnees
                    ? el('p.text-\\[10px\\].text-success-600', { text: 'déposé' })
                    : el('p.text-\\[10px\\].text-slate-400', { text: 'référencé' }),
                ]);
              },
            },
            { key: 'depose', label: 'Déposé par' },
            { key: 'etat', label: 'Statut', render: function (r) { return U.statut(r.etat); } },
          ],
          /* Déposer, modifier ou retirer une pièce du dossier sont des
             ÉCRITURES : le profil qui ne fait que consulter le dossier voit
             les documents et les prévisualise, sans les toucher. */
          actions: [K.commande('Ajouter un document', {
            variant: 'primary', size: 'sm', icon: 'upload', onclick: function () { deposer(); },
          })],
          rowActions: function (r) {
            return [
              K.iconBtn('eye', 'Prévisualiser', function () { previsualiser(r); }),
              K.commandeIcone('pencil', 'Modifier', function () {
                K.modifier(colDocs(), champsDocument(), r, dessiner);
              }),
              K.commandeIcone('trash-2', 'Retirer du dossier', function () { retirer(r); }, { droit: 'annuler' }),
            ];
          },
        }));

        root.appendChild(host);
        U.icons(root);
      }

      function champsDocument() {
        return [
          {
            name: 'patientId', label: 'Dossier patient', type: 'select', required: true, col: 'full',
            options: C.sortBy(S.collection('patients').active(), 'code').map(function (p) {
              return { value: p.id, label: p.code + ' — ' + p.nom + ' ' + p.prenom };
            }),
          },
          { name: 'type', label: 'Type de document', type: 'select', required: true, options: TYPES_DOCUMENT },
          { name: 'date', label: 'Date du document', type: 'date', required: true },
          {
            name: 'etat', label: 'Statut', type: 'select', required: true,
            options: [{ value: 'en_attente', label: 'En attente de validation' }, { value: 'valide', label: 'Validé' }],
          },
          { name: 'depose', label: 'Déposé par', required: true },
        ];
      }

      /* --- Dépôt d'un fichier --------------------------------------------- */
      function deposer() {
        var input = el('input.input', {
          type: 'file',
          accept: '.pdf,.png,.jpg,.jpeg,.webp,application/pdf,image/png,image/jpeg,image/webp',
          'aria-label': 'Fichier à déposer',
        });
        var apercu = el('div.mt-2');
        var meta = { donnees: null, fichier: null, taille: 0, format: null };

        input.addEventListener('change', function () {
          var file = input.files && input.files[0];
          C.clear(apercu);
          if (!file) return;
          meta.fichier = file.name;
          meta.taille = file.size;
          meta.format = /pdf$/i.test(file.name) ? 'PDF' : (/png$/i.test(file.name) ? 'PNG' : (/webp$/i.test(file.name) ? 'WEBP' : 'JPEG'));
          if (file.size > 2 * 1024 * 1024) {
            apercu.appendChild(K.note('Fichier de ' + poidsDoc(file.size) + ' — au-delà de deux mégaoctets, '
              + 'le stockage local du navigateur sature vite. Numériser en résolution plus basse.',
            { tone: 'warning', icon: 'alert-triangle' }));
          }
          var lecteur = new FileReader();
          lecteur.onload = function () {
            meta.donnees = lecteur.result;
            if (meta.format === 'PDF') {
              apercu.appendChild(el('p.mt-2.text-xs.text-slate-500', { text: file.name + ' — ' + poidsDoc(file.size) + ' (PDF prêt à être rattaché)' }));
            } else {
              apercu.appendChild(el('img.mt-2.max-h-40.rounded-lg.border.border-slate-200.object-contain', { src: meta.donnees, alt: 'Aperçu du document' }));
            }
          };
          lecteur.readAsDataURL(file);
        });

        var f = U.form(champsDocument(), {
          date: C.iso(new Date()), etat: 'en_attente', depose: S.currentUser(),
        });

        var corps = el('div.space-y-3', null, [
          f,
          el('div', null, [el('label.label', { text: 'Fichier numérisé * — PDF, PNG ou JPEG' }), input, apercu]),
          K.note('Le fichier est conservé <strong>dans le poste</strong>, avec le reste des données : '
            + 'aucune requête réseau, même contrainte hors ligne que le reste du logiciel.', { tone: 'info' }),
        ]);

        var m = U.modal({
          title: 'Ajouter un document au dossier', size: 'lg', body: corps,
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Rattacher au dossier', {
              variant: 'primary', icon: 'upload',
              onclick: function () {
                var v = f.collect();
                if (!v) return;
                if (!meta.donnees) { U.toast('Choisir un fichier à déposer.', { type: 'warning' }); return; }
                var p = S.collection('patients').get(v.patientId);
                v.reference = 'GED-' + C.pad(colDocs().all().length + 1, 5);
                v.code = p ? p.code : null;
                v.patient = p ? p.nom + ' ' + p.prenom : '—';
                v.donnees = meta.donnees; v.fichier = meta.fichier;
                v.taille = meta.taille; v.format = meta.format;
                var res = colDocs().insert(v);
                m.close(); dessiner();
                U.toast('Document rattaché au dossier ' + v.code + '.', {
                  type: 'success', detail: v.type + ' — ' + meta.fichier,
                  undo: function () { res.undo(); dessiner(); },
                });
              },
            }),
          ],
        });
      }

      function previsualiser(r) {
        var corps;
        if (r.donnees && r.format === 'PDF') {
          corps = el('iframe.h-\\[70vh\\].w-full.rounded-lg.border.border-slate-200', { src: r.donnees, title: r.type });
        } else if (r.donnees) {
          corps = el('img.mx-auto.max-h-\\[70vh\\].rounded-lg.border.border-slate-200.object-contain', { src: r.donnees, alt: r.type });
        } else {
          corps = el('div.flex.h-64.flex-col.items-center.justify-center.gap-2.rounded-lg.border.border-dashed.border-slate-300.bg-slate-50', null, [
            C.icon('file-text', 'h-10 w-10 text-slate-300'),
            el('p.text-sm.text-slate-500', { text: 'Document référencé au dossier, fichier non encore déposé' }),
            el('p.text-xs.text-slate-400', { text: poidsDoc(r.taille) + ' — enregistré le ' + C.dateFR(r.date) }),
          ]);
        }
        U.modal({
          title: r.type, subtitle: r.reference + ' — ' + r.patient + ' (' + r.code + ')',
          size: 'lg', body: corps,
          footer: [K.btn('Imprimer', {
            icon: 'printer',
            onclick: function () {
              P.etat({
                titre: r.type, sousTitre: r.reference,
                cartouche: [['Patient', r.patient], ['Dossier', r.code], ['Date', C.dateFR(r.date)],
                  ['Format', r.format || '—'], ['Taille', poidsDoc(r.taille)], ['Déposé par', r.depose]],
                contenu: r.donnees && r.format !== 'PDF'
                  ? el('img.mx-auto.max-h-\\[180mm\\].object-contain', { src: r.donnees, alt: r.type })
                  : el('p', { text: 'Reproduction du document numérisé rattaché au dossier patient.' }),
              });
            },
          })],
        });
      }

      function retirer(r) {
        U.confirm({
          title: 'Retirer « ' + r.type + ' » du dossier ?',
          message: 'Le document est archivé, non supprimé (RG-14) : il reste consultable et restaurable '
            + 'depuis la corbeille. L’opération est journalisée.',
          confirmLabel: 'Retirer', danger: true, requireMotif: true,
        }).then(function (ok) {
          if (!ok) return;
          var res = colDocs().archive(r.id, ok.motif);
          dessiner();
          U.toast('Document retiré du dossier.', {
            type: 'success', undo: function () { res.undo(); dessiner(); },
          });
        });
      }
    },
  });

  /* ==========================================================================
   * ÉCRAN — Plan de numérisation des dossiers papier
   * ======================================================================== */
  global.SIGH.screen('m1-numerisation', {
    title: 'Plan de numérisation des dossiers',
    description: 'Suivi de la reprise progressive et priorisée des dossiers patients papier (CDCT §24).',
    regle: 'Le périmètre exclut la migration rétroactive intégrale : seuls les <strong>dossiers actifs</strong> sont numérisés en priorité, les dossiers inactifs restant numérisables à la demande.',
    render: function (root) {
      var TOTAL = 18000;
      var traites = 4230;
      var host = el('div.space-y-4');

      host.appendChild(U.kpiGrid([
        { label: 'Dossiers papier recensés', value: C.num(TOTAL), icon: 'archive', tone: 'neutral' },
        { label: 'Dossiers numérisés', value: C.num(traites), icon: 'scan-line', tone: 'success', hint: C.pct(traites / TOTAL * 100) + ' du fonds' },
        { label: 'Dossiers actifs prioritaires', value: C.num(6200), icon: 'star', tone: 'navy', hint: 'Vus au cours des 24 derniers mois' },
        { label: 'Reste à traiter (prioritaires)', value: C.num(6200 - traites), icon: 'clock', tone: 'warning' },
      ]));

      /* Avancement par lot */
      var lots = [
        { lot: 'Lot 1 — Hospitalisations en cours', total: 320, fait: 320 },
        { lot: 'Lot 2 — Patients suivis (chroniques)', total: 1450, fait: 1450 },
        { lot: 'Lot 3 — Maternité et suivis prénataux', total: 980, fait: 860 },
        { lot: 'Lot 4 — Patients assurés', total: 2300, fait: 1600 },
        { lot: 'Lot 5 — Consultations 2025-2026', total: 1150, fait: 0 },
        { lot: 'Lot 6 — Fonds inactif (à la demande)', total: 11800, fait: 0 },
      ];

      host.appendChild(U.card('Avancement par lot de reprise', el('div.space-y-4', null,
        lots.map(function (l) {
          var pct = Math.round(l.fait / l.total * 100);
          var d = el('div');
          var top = el('div.mb-1\\.5.flex.items-baseline.justify-between.gap-3');
          top.appendChild(el('span.text-sm.font-medium.text-slate-700', { text: l.lot }));
          top.appendChild(el('span.text-xs.num.text-slate-500', { text: C.num(l.fait) + ' / ' + C.num(l.total) + ' (' + pct + ' %)' }));
          d.appendChild(top);
          var bar = el('div.h-2.w-full.overflow-hidden.rounded-full.bg-slate-100');
          bar.appendChild(el('div.h-full.rounded-full', {
            class: pct === 100 ? 'bg-success-500' : (pct > 0 ? 'bg-navy-500' : 'bg-slate-300'),
            style: 'width:' + Math.max(1, pct) + '%;',
          }));
          d.appendChild(bar);
          return d;
        })
      ), [K.btn('Éditer l’état d’avancement', {
        icon: 'printer', size: 'sm',
        onclick: function () {
          P.etat({
            titre: 'État d’avancement de la numérisation',
            sousTitre: 'Reprise des dossiers patients — CDCT §24',
            cartouche: [['Fonds total', C.num(TOTAL) + ' dossiers'], ['Numérisés', C.num(traites)],
              ['Avancement', C.pct(traites / TOTAL * 100)], ['Date d’édition', C.dateFR(new Date())]],
            contenu: P.tableau([
              { label: 'Lot de reprise', key: 'lot' },
              { label: 'Total', key: 'total', align: 'right' },
              { label: 'Numérisés', key: 'fait', align: 'right' },
              { label: 'Avancement', align: 'right', value: function (l) { return Math.round(l.fait / l.total * 100) + ' %'; } },
            ], lots),
            signatures: [{ role: 'Le Secrétaire Médical' }, { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
          });
        },
      })]));

      host.appendChild(K.charts([
        {
          title: 'Cadence de numérisation (12 derniers mois)',
          render: function () {
            return G.barres(G.moisGlissants(12), [{ label: 'Dossiers numérisés', data: [0, 0, 120, 310, 480, 520, 610, 430, 380, 520, 460, 400] }]);
          },
        },
        {
          title: 'Répartition du fonds',
          render: function () {
            return G.anneau(['Numérisés', 'Prioritaires restants', 'Fonds inactif'],
              [traites, 6200 - traites, TOTAL - 6200], { legend: 'bottom' });
          },
        },
      ]));

      host.appendChild(K.source('Rapport de cadrage — environ 18 000 dossiers patients recensés.'));
      root.appendChild(host);
      return null;
    },
  });
  /* ==========================================================================
   * PATIENT EXTERNE — DEMANDE D'ANALYSES
   * --------------------------------------------------------------------------
   * MÉTHODE RETENUE, en réponse à la question de la Direction : la demande
   * naît à l'ACCUEIL, pas à la caisse ni au laboratoire.
   *
   *   — le patient arrive avec une ordonnance d'un médecin extérieur : il
   *     s'agit de TRANSCRIRE, pas de prescrire. L'accueil le peut sans
   *     habilitation médicale ;
   *   — son premier point de chute est l'accueil : l'obliger à monter d'abord
   *     au laboratoire lui impose un aller-retour ;
   *   — la CAISSE NE CRÉE JAMAIS la demande. Elle encaisse, elle ne prescrit
   *     pas : lui donner ce pouvoir ouvrirait une recette sans acte à
   *     l'origine.
   *
   * Le laboratoire garde sa saisie manuelle pour les patients qu'il reçoit
   * directement. Les deux voies coexistent et se distinguent par leur origine.
   *
   * DEUX CONTRAINTES qui ne sont pas décoratives :
   *   — les examens se COCHENT AU CATALOGUE, jamais un montant libre : sans
   *     lignes, la facture ne peut pas se régler examen par examen ;
   *   — l'IDENTITÉ est obligatoire. C'est au patient externe qu'on remet son
   *     résultat : sans nom, sexe, âge et téléphone, on ne peut ni le lui
   *     remettre ni le retrouver.
   * ======================================================================== */
  global.SIGH.screen('m1-externe', {
    title: 'Patient externe — demande d’analyses',
    description: 'Transcription de l’ordonnance d’un médecin extérieur, puis orientation vers la caisse.',
    regle: 'L’accueil <strong>transcrit</strong> une ordonnance extérieure, il ne prescrit pas. '
      + 'Les examens se cochent <strong>au catalogue</strong> — jamais un montant libre — pour que la caisse '
      + 'puisse encaisser prestation par prestation. '
      + 'La <strong>caisse ne crée jamais la demande</strong> : elle encaisse, elle ne prescrit pas. '
      + 'Le résultat est <strong>remis directement au patient</strong>, d’où l’identité obligatoire.',
    render: function (root) {
      var L = global.SIGH.labo;
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      afficherExterne();
      return null;

      function demandesExternes() {
        return S.collection('demandesAnalyses').active()
          .filter(function (d) { return d.origineDemande === 'externe'; });
      }

      function afficherExterne() {
        var dem = demandesExternes();
        var enAttente = dem.filter(function (d) { return d.bloqueParPaiement; });
        var rendus = dem.filter(function (d) { return d.etatAnalyse === 'valide'; });

        C.clear(vue);
        vue.appendChild(U.kpiGrid([
          { label: 'Demandes externes', value: C.num(dem.length), icon: 'user-plus', tone: 'navy' },
          {
            label: 'En attente de caisse', value: C.num(enAttente.length),
            icon: 'coins', tone: enAttente.length ? 'warning' : 'success',
          },
          { label: 'Résultats rendus', value: C.num(rendus.length), icon: 'file-check-2', tone: 'success' },
          {
            label: 'Patients externes',
            value: C.num(Object.keys(C.groupBy(dem, 'patientId')).length), icon: 'users', tone: 'info',
          },
        ]));

        vue.appendChild(K.note('Le patient externe arrive avec une ordonnance d’un médecin extérieur. '
          + 'L’accueil la <strong>transcrit</strong> en cochant les examens au catalogue, puis l’oriente vers la '
          + '<strong>caisse</strong>. Le prélèvement n’a lieu qu’après règlement, et le résultat lui est '
          + '<strong>remis directement</strong> — il n’a pas de clinicien dans la maison à qui l’adresser.',
        { tone: 'info', icon: 'route' }));

        var actions = [];
        if (K.droits('M1').editer) {
          actions.push(K.btn('Nouvelle demande externe', {
            variant: 'primary', size: 'sm', icon: 'plus', onclick: nouvelleDemande,
          }));
        }

        vue.appendChild(U.dataTable({
          title: 'Demandes de patients externes',
          rows: dem, exportName: 'demandes-externes', pageSize: 15, searchable: true,
          defaultSort: 'dateHeure', defaultDir: 'desc',
          emptyMessage: 'Aucune demande externe enregistrée.',
          actions: actions,
          filters: [{
            name: 'etat', label: 'État',
            options: [{ value: 'caisse', label: 'En attente de caisse' },
              { value: 'prelevement', label: 'À prélever' },
              { value: 'valide', label: 'Résultat rendu' }],
            match: function (r, v) {
              if (v === 'caisse') return !!r.bloqueParPaiement;
              if (v === 'valide') return r.etatAnalyse === 'valide';
              return !r.bloqueParPaiement && r.etatAnalyse !== 'valide';
            },
          }],
          columns: [
            { key: 'reference', label: 'N°', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.reference }); } },
            {
              key: 'dateHeure', label: 'Date', nowrap: true,
              text: function (r) { return C.dateFR(r.dateHeure); },
              render: function (r) { return C.dateFR(r.dateHeure); },
            },
            {
              key: 'patient', label: 'Patient',
              render: function (r) {
                return el('div.min-w-0', null, [
                  el('p.truncate.text-sm.font-medium.text-slate-800', { text: r.patient }),
                  el('p.text-xs.text-slate-400', { text: r.patientCode }),
                ]);
              },
            },
            { key: 'analyse', label: 'Examen' },
            { key: 'prescripteur', label: 'Prescripteur extérieur' },
            {
              key: 'etat', label: 'État', align: 'right',
              value: function (r) { return r.bloqueParPaiement ? 'caisse' : r.etatAnalyse; },
              render: function (r) {
                if (r.bloqueParPaiement) return U.badge('En attente de caisse', 'warning');
                if (r.etatAnalyse === 'valide') return U.badge('Résultat rendu', 'success');
                return U.badge('À prélever', 'info');
              },
            },
          ],
          rowActions: function (r) {
            var actes = [];
            if (r.factureId) {
              actes.push(K.iconBtn('coins', 'Voir la facture à la caisse', function () {
                global.SIGH.app.go('m8-caisse');
              }));
            }
            actes.push(K.iconBtn('folder-open', 'Ouvrir le dossier du patient', function () {
              global.SIGH.app.go('m1-patient-profil', { patient: r.patientId });
            }));
            return actes;
          },
        }));
        U.icons(vue);
      }

      function nouvelleDemande() {
        var champs = [
          { type: 'section', label: 'Identité du patient — obligatoire pour lui remettre son résultat' },
          { name: 'nom', label: 'Nom', type: 'text', required: true },
          { name: 'prenom', label: 'Prénoms', type: 'text', required: true },
          {
            name: 'sexe', label: 'Sexe', type: 'select', required: true,
            options: [{ value: 'M', label: 'Masculin' }, { value: 'F', label: 'Féminin' }],
          },
          { name: 'dateNaissance', label: 'Date de naissance', type: 'date', required: true },
          { name: 'telephone', label: 'Téléphone', type: 'text', required: true,
            hint: 'Le résultat lui est remis directement : sans téléphone, on ne peut pas le joindre.' },
          { name: 'residence', label: 'Lieu de résidence', type: 'text', required: true },

          { type: 'section', label: 'Ordonnance extérieure' },
          { name: 'prescripteur', label: 'Médecin prescripteur', type: 'text', required: true, col: 'full',
            hint: 'Nom du médecin extérieur qui a demandé les examens.' },
          { name: 'indication', label: 'Indication clinique', type: 'text', col: 'full' },
          {
            name: 'serviceDemandeur', label: 'Service concerné', type: 'select',
            options: (L ? L.SERVICES_DEMANDEURS : []).map(function (x) { return { value: x.label, label: x.label }; }),
          },
          {
            name: 'urgence', label: 'Caractère d’urgence', type: 'select', required: true,
            options: (L ? L.NIVEAUX_URGENCE : [{ id: 'aucune', label: 'Courant' }])
              .map(function (x) { return { value: x.id, label: x.label }; }),
          },

          { type: 'section', label: 'Examens demandés — au catalogue' },
          {
            name: 'analyses', label: 'Examens', type: 'multiselect', required: true, col: 'full',
            options: S.collection('analyses').active().map(function (a) {
              return { value: a.code, label: a.designation, detail: a.categorie + ' — ' + C.money(a.prix, false) };
            }),
            hint: 'Les examens se cochent au catalogue : c’est ce qui permet à la caisse d’encaisser '
              + 'prestation par prestation, et au patient de n’en régler qu’une partie s’il le faut.',
          },

          { type: 'section', label: 'Prise en charge' },
          {
            name: 'assureur', label: 'Assurance', type: 'select',
            options: [{ value: '', label: 'Aucune — paiement intégral' }]
              .concat(S.collection('assureurs').active().map(function (a) { return { value: a.nom, label: a.nom }; })),
          },
          { name: 'taux', label: 'Taux de prise en charge (%)', type: 'number', min: 0, max: 100 },
        ];

        var f = U.form(champs, { sexe: 'M', urgence: 'aucune', taux: 0 });
        var m = U.modal({
          title: 'Nouvelle demande — patient externe',
          subtitle: 'Transcription d’une ordonnance extérieure',
          size: 'xl',
          body: el('div.space-y-3', null, [
            K.note('<strong>Transcription, pas prescription.</strong> L’accueil reporte les examens portés sur '
              + 'l’ordonnance du médecin extérieur. Un dossier patient est ouvert, une facture part à la caisse, '
              + 'et le prélèvement reste bloqué tant qu’elle n’est pas réglée.', { tone: 'info' }),
            f,
          ]),
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Enregistrer et envoyer à la caisse', {
              variant: 'primary', icon: 'coins',
              onclick: function () {
                var v = f.collect();
                if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                var res;
                try { res = PR.ouvrirDemandeExterne(v); }
                catch (e) { U.toast('Demande impossible : ' + e.message, { type: 'error' }); return; }
                m.close();
                afficherExterne();

                var mr = U.modal({
                  title: 'Demande enregistrée',
                  subtitle: res.patient.nom + ' ' + res.patient.prenom + ' — ' + res.patient.code,
                  size: 'md',
                  body: el('div.space-y-3', null, [
                    U.descList([
                      ['Dossier ouvert', res.patient.code],
                      ['Examens demandés', C.num(res.demandes.length)],
                      ['Facture', res.facture.numero],
                      ['À régler à la caisse', C.money(res.facture.partPatient)],
                    ], 'grid-cols-2'),
                    K.note('Le patient se présente maintenant à la <strong>caisse</strong> avec son bulletin. '
                      + 'Le prélèvement n’aura lieu qu’après règlement — et seuls les examens réglés seront '
                      + 'transmis au laboratoire.', { tone: 'warning', icon: 'coins' }),
                  ]),
                  footer: [
                    K.btn('Fermer', { onclick: function () { mr.close(); } }),
                    K.btn('Imprimer le bulletin', {
                      icon: 'printer',
                      onclick: function () { bulletinExterne(res); },
                    }),
                    K.btn('Aller à la caisse', {
                      variant: 'primary', icon: 'coins',
                      onclick: function () { global.SIGH.app.go('m8-caisse'); },
                    }),
                  ],
                });
              },
            }),
          ],
        });
      }

      function bulletinExterne(res) {
        var pat = res.patient;
        P.etat({
          titre: 'Bulletin d’analyses bio-médicales',
          sousTitre: 'Patient externe — ' + res.facture.numero,
          cartouche: [
            ['Patient', pat.nom + ' ' + pat.prenom], ['Dossier', pat.code],
            ['Âge', pat.dateNaissance ? C.age(pat.dateNaissance) + ' ans' : '—'],
            ['Sexe', pat.sexe === 'F' ? 'Féminin' : 'Masculin'],
            ['Téléphone', pat.telephone || '—'],
            ['Résidence', pat.adresse || '—'],
            ['Prescripteur extérieur', pat.prescripteurExterieur || '—'],
            ['Date', C.dateFR(AUJ)],
            ['À régler à la caisse', C.money(res.facture.partPatient)],
          ],
          contenu: el('div.space-y-3', null, [
            P.tableau([
              { label: 'Examen demandé', key: 'analyse' },
              { label: 'Échantillon', key: 'echantillon' },
              {
                label: 'Tarif', align: 'right',
                value: function (d) { return C.money(d.prix, false); },
                somme: function (d) { return d.prix; },
              },
            ], res.demandes, { total: true }),
            el('p.mt-3.text-\[10px\].italic', {
              text: 'Patient adressé de l’extérieur. Ce bulletin accompagne le patient à la caisse puis à la '
                + 'salle de prélèvement. Le résultat lui est remis directement — la clinique ne dispose pas '
                + 'd’un clinicien prescripteur à qui l’adresser.',
            }),
          ]),
          signatures: [{ role: 'L’Accueil', mention: 'Transcription' },
            { role: 'Le Caissier', mention: 'Règlement' }],
        });
      }
    },
  });


  /* ==========================================================================
   * CERTIFICATS ET ATTESTATIONS
   * --------------------------------------------------------------------------
   * Quatorze pièces relevées sur les gabarits officiels de la clinique. Chacune
   * porte une référence de la forme « <SIGLE> n°/n°/<sigle clinique>/<direction>/<année> »,
   * un en-tête propre à sa famille, et son tarif.
   *
   * L'ASSURANCE NE COUVRE AUCUN CERTIFICAT, À L'EXCEPTION DE SOS : la mention
   * est portée en toutes lettres sur la grille tarifaire. C'est pourquoi la
   * couverture ne peut pas être un booléen — il aurait fallu choisir entre
   * exclure SOS à tort et ouvrir la couverture aux treize compagnies à tort.
   *
   * LE CERTIFICAT PRÉNUPTIAL NE SE SAISIT PAS : il se remplit depuis les
   * résultats VALIDÉS BIOLOGIQUEMENT du patient. Un examen non validé ne peut
   * pas y être coché — sans quoi le médecin attesterait d'un résultat que le
   * laboratoire n'a pas encore rendu.
   * ======================================================================== */
  /* Deux écrans posent la même question — les certificats et les constantes.
     Elle vit donc au module et non dans une fermeture. */
  function optionsPatientsM1() {
    return C.sortBy(S.collection('patients').active(), 'code').map(function (p2) {
      return { value: p2.code, label: p2.code + ' — ' + p2.nom + ' ' + p2.prenom };
    });
  }

  function colPieces() {
    return S.collection('pieces', { module: 'M1', entite: 'pièce certifiante', prefix: 'PCE' });
  }
  function colTypesPiece() {
    return S.collection('typesPiece', { module: 'CFG', entite: 'type de pièce', prefix: 'TPC' });
  }

  global.SIGH.screen('m1-pieces', {
    title: 'Certificats & attestations',
    description: 'Délivrance, numérotation et impression des quatorze pièces certifiantes de la clinique.',
    regle: 'Chaque pièce reçoit un <strong>numéro d’ordre</strong> dans l’année et la direction émettrice. '
      + 'Les certificats <strong>ne sont couverts par aucune assurance à l’exception de SOS</strong>. '
      + 'Le certificat prénuptial se remplit depuis les <strong>résultats validés biologiquement</strong>, '
      + 'jamais à la main.',
    render: function (root) {
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      afficher();
      return null;

      function types() { return colTypesPiece().active(); }

      /* Le numéro d'ordre est propre au sigle ET à l'année : deux pièces de
         familles différentes ne se disputent pas la même série, et la série
         repart à 1 chaque 1er janvier — comme le registre papier. */
      function numeroter(t) {
        var an = new Date().getFullYear();
        var n = colPieces().all().filter(function (x) {
          return x.sigle === t.sigle && x.annee === an;
        }).length + 1;
        return {
          numero: n, annee: an,
          reference: t.sigle + ' ' + C.pad(n, 3) + '/' + C.pad(n, 3) + '/' + C.BRAND.sigle + '/' + t.direction + '/' + an,
        };
      }

      function champs() {
        return [
          { name: 'typeId', label: 'Type de pièce', type: 'select', required: true,
            options: types().map(function (t) {
              return { value: t.id, label: t.libelle, detail: 'Sigle ' + t.sigle + ' — ' + t.direction };
            }) },
          { name: 'patientCode', label: 'Patient', type: 'select', required: true, options: optionsPatientsM1() },
          { name: 'medecin', label: 'Médecin signataire', type: 'select', required: true,
            options: S.collection('personnel').active().filter(function (a) {
              return a.fonction === 'medecin';
            }).map(function (a) { return { value: a.nomComplet, label: a.nomComplet + ' — ' + a.poste }; }) },
          { name: 'dateDelivrance', label: 'Date de délivrance', type: 'date', required: true },
          { name: 'contenu', label: 'Mentions portées sur la pièce', type: 'textarea', rows: 5,
            hint: 'Le corps du certificat, tel qu’il sera imprimé.' },
          { name: 'remisA', label: 'Remis à', type: 'text',
            hint: 'L’intéressé lui-même, ou la personne nommément désignée.' },
        ];
      }

      function afficher() {
        var rows = colPieces().active();
        var an = new Date().getFullYear();
        var cetteAnnee = rows.filter(function (r) { return r.annee === an; });
        var recettes = rows.reduce(function (n, r) { return n + (r.montant || 0); }, 0);

        C.clear(vue);
        vue.appendChild(U.kpiGrid([
          { label: 'Pièces délivrées', value: C.num(rows.length), icon: 'stamp', tone: 'navy' },
          { label: 'Sur l’exercice ' + an, value: C.num(cetteAnnee.length), icon: 'calendar', tone: 'info' },
          { label: 'Types disponibles', value: C.num(types().length), icon: 'files', tone: 'neutral' },
          { label: 'Recettes des certificats', value: C.money(recettes), icon: 'coins', tone: 'success' },
        ]));

        vue.appendChild(K.note('<strong>L’assurance ne couvre pas les certificats, à l’exception de SOS.</strong> '
          + 'La mention figure en toutes lettres sur la grille tarifaire de la clinique. Un assuré d’une autre '
          + 'compagnie règle donc intégralement, et la pièce de caisse en porte le motif.',
        { tone: 'warning', icon: 'shield-off' }));

        vue.appendChild(U.dataTable({
          rows: C.sortBy(rows, 'dateDelivrance').reverse(),
          empty: 'Aucune pièce délivrée.',
          actions: [K.creer(colPieces(), champs(), {
            module: 'M1', label: 'Délivrer une pièce', titre: 'Délivrer un certificat ou une attestation',
            entite: 'Pièce', size: 'lg', apres: afficher,
            transform: function (v) {
              var t = types().filter(function (x) { return x.id === v.typeId; })[0];
              var pt = S.collection('patients').active().filter(function (x) {
                return x.code === v.patientCode;
              })[0];
              var num = numeroter(t);
              var tarif = t.tarifCode && D.tarif ? D.tarif(t.tarifCode) : null;
              return Object.assign({}, v, num, {
                sigle: t.sigle, libelle: t.libelle, direction: t.direction,
                patientId: pt ? pt.id : null,
                patient: pt ? pt.nom + ' ' + pt.prenom : v.patientCode,
                montant: tarif ? tarif.prixNonAssure : null,
                /* La couverture est portée sur la pièce elle-même : au guichet,
                   la question « pourquoi je paie tout ? » doit trouver sa
                   réponse sur le document, pas dans une note de service. */
                couverture: tarif && tarif.assurable === 'sos'
                  ? 'Couvert par SOS uniquement — toute autre compagnie : à la charge du patient'
                  : 'Non couvert par les assurances',
              });
            },
          })].filter(Boolean),
          columns: [
            { key: 'reference', label: 'Référence',
              render: function (r) { return el('span.font-mono.text-xs', { text: r.reference }); } },
            { key: 'libelle', label: 'Pièce' },
            { key: 'patient', label: 'Patient', render: function (r) { return r.patient + ' — ' + r.patientCode; } },
            { key: 'dateDelivrance', label: 'Délivrée le', render: function (r) { return C.dateFR(r.dateDelivrance); } },
            { key: 'medecin', label: 'Signataire' },
            { key: 'montant', label: 'Montant', align: 'right',
              render: function (r) { return r.montant == null ? '—' : C.money(r.montant); } },
          ],
          rowActions: function (r) {
            return [K.iconBtn('printer', 'Imprimer la pièce', function () { imprimer(r); })]
              .concat(K.actionsLigne(colPieces(), champs(), {
                module: 'M1', refresh: afficher,
                titre: function (x) { return x.libelle; },
                detail: function (x) {
                  return el('div.space-y-4', null,
                    K.grid([
                      ['Référence', x.reference], ['Pièce', x.libelle],
                      ['Patient', x.patient + ' — ' + x.patientCode],
                      ['Délivrée le', C.dateFR(x.dateDelivrance)],
                      ['Signataire', x.medecin], ['Remise à', x.remisA || 'L’intéressé(e)'],
                      ['Montant', x.montant == null ? 'non tarifé' : C.money(x.montant)],
                      ['Couverture', x.couverture || '—'],
                    ]),
                    x.contenu ? K.section('Mentions portées',
                      el('p.whitespace-pre-line.text-sm.text-slate-600', { text: x.contenu })) : null);
                },
              })(r));
          },
        }));
        U.icons(vue);
      }

      function imprimer(r) {
        /* Toutes les pièces s'impriment sous l'UNIQUE en-tête légal (C.BRAND) —
           arbitrage de la Direction du 31/08/2026, Bugs 7/8/13 des
           Instructions. Les variantes par famille de document sont retirées. */
        P.etat({
          titre: (r.libelle || '').toUpperCase(),
          sousTitre: 'N°/Réf : ' + r.reference,
          cartouche: [
            ['Patient', r.patient], ['Dossier', r.patientCode],
            ['Délivrée le', C.dateFR(r.dateDelivrance)],
            ['Remise à', r.remisA || 'L’intéressé(e)'],
          ],
          contenu: el('div', null, [
            el('p.whitespace-pre-line.text-\\[11px\\].leading-relaxed', {
              text: r.contenu || 'En foi de quoi la présente pièce est établie pour servir et valoir ce que de droit.',
            }),
            el('p.mt-4.text-\\[10px\\].italic.text-slate-500', {
              text: r.couverture || '',
            }),
          ]),
          signatures: [{ role: 'Le Médecin', nom: r.medecin, mention: 'Signature et cachet' }],
        });
      }
    },
  });

  /* ==========================================================================
   * CONSTANTES RELEVÉES À L'ACCUEIL
   * --------------------------------------------------------------------------
   * La Direction a demandé que les constantes soient prises dès l'accueil et
   * qu'elles alimentent les feuilles de surveillance. C'est une seule et même
   * collection qui sert les deux vues du document papier :
   *
   *   - la FEUILLE DE TEMPÉRATURE, qui est un GRAPHIQUE à cinq échelles ;
   *   - la FICHE DE SURVEILLANCE, qui est le même relevé en tableau.
   *
   * Les tenir séparées produirait deux vérités divergentes sur les constantes
   * d'un même patient — exactement ce que la numérisation doit supprimer.
   * ======================================================================== */
  function colConstantes() {
    return S.collection('constantes', { module: 'M1', entite: 'relevé de constantes', prefix: 'CST' });
  }

  global.SIGH.screen('m1-constantes', {
    title: 'Constantes à l’accueil',
    description: 'Température, poids, taille, tension, SpO₂ et pouls relevés dès l’arrivée du patient.',
    regle: 'Les constantes prises à l’accueil <strong>alimentent la feuille de température et la fiche de '
      + 'surveillance</strong> : une seule collection, deux présentations. L’accueil relève des constantes — '
      + 'ce n’est pas une donnée clinique interprétée, et cela reste dans son périmètre.',
    render: function (root) {
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      afficher();
      return null;

      function champs() {
        return [
          { name: 'patientCode', label: 'Patient', type: 'select', required: true, options: optionsPatientsM1() },
          { name: 'dateHeure', label: 'Date et heure du relevé', type: 'datetime-local', required: true },
          { name: 'moment', label: 'Moment', type: 'select', required: true,
            options: [
              { value: 'matin', label: 'Matin' },
              { value: 'midi', label: 'Midi' },
              { value: 'soir', label: 'Soir' },
            ],
            hint: 'La feuille de température comporte trois colonnes par jour : matin, midi, soir.' },
          { type: 'section', label: 'Constantes' },
          { name: 'temperature', label: 'Température (°C)', type: 'number', step: 0.1, min: 30, max: 45 },
          { name: 'tensionSys', label: 'Tension systolique (cmHg)', type: 'number', min: 4, max: 30 },
          { name: 'tensionDia', label: 'Tension diastolique (cmHg)', type: 'number', min: 2, max: 20 },
          { name: 'pouls', label: 'Pouls (bpm)', type: 'number', min: 30, max: 220 },
          { name: 'fr', label: 'Fréquence respiratoire (/min)', type: 'number', min: 5, max: 70 },
          { name: 'spo2', label: 'SpO₂ (%)', type: 'number', min: 50, max: 100 },
          { name: 'diurese', label: 'Diurèse (L)', type: 'number', step: 0.1, min: 0, max: 5 },
          { type: 'section', label: 'Mensurations' },
          { name: 'poids', label: 'Poids (kg)', type: 'number', step: 0.1, min: 0, max: 250 },
          { name: 'taille', label: 'Taille (cm)', type: 'number', min: 20, max: 230 },
          { name: 'releveePar', label: 'Relevé par', type: 'text', required: true },
        ];
      }

      /* Un seuil dépassé se voit : c'est tout l'intérêt de relever à l'accueil
         plutôt qu'en salle. Les bornes sont celles de la feuille de température
         de la clinique. */
      function anormale(r) {
        var motifs = [];
        if (r.temperature != null && (r.temperature < 36 || r.temperature > 38)) motifs.push('température');
        if (r.pouls != null && (r.pouls < 60 || r.pouls > 100)) motifs.push('pouls');
        if (r.fr != null && (r.fr < 12 || r.fr > 20)) motifs.push('fréquence respiratoire');
        if (r.spo2 != null && r.spo2 < 94) motifs.push('SpO₂');
        return motifs;
      }

      function afficher() {
        var rows = colConstantes().active();
        var auj = rows.filter(function (r) {
          return String(r.dateHeure || '').slice(0, 10) === C.iso(new Date());
        });
        var alertes = rows.filter(function (r) { return anormale(r).length; });

        C.clear(vue);
        vue.appendChild(U.kpiGrid([
          { label: 'Relevés enregistrés', value: C.num(rows.length), icon: 'thermometer', tone: 'navy' },
          { label: 'Aujourd’hui', value: C.num(auj.length), icon: 'calendar', tone: 'info' },
          { label: 'Patients suivis', value: C.num(rows.map(function (r) { return r.patientId; })
            .filter(function (v, i, a) { return v && a.indexOf(v) === i; }).length), icon: 'users', tone: 'neutral' },
          { label: 'Constantes hors bornes', value: C.num(alertes.length), icon: 'triangle-alert',
            tone: alertes.length ? 'warning' : 'success' },
        ]));

        vue.appendChild(K.note('Ces relevés alimentent la <strong>feuille de température</strong> (graphique à '
          + 'cinq échelles) et la <strong>fiche de surveillance</strong> (le même relevé en tableau). Une seule '
          + 'collection, deux présentations : les tenir séparées produirait deux vérités divergentes sur les '
          + 'constantes d’un même patient.', { tone: 'info', icon: 'activity' }));

        vue.appendChild(U.dataTable({
          rows: C.sortBy(rows, 'dateHeure').reverse(),
          empty: 'Aucun relevé de constantes enregistré.',
          actions: [K.creer(colConstantes(), champs(), {
            module: 'M1', label: 'Nouveau relevé', titre: 'Relever les constantes',
            entite: 'Relevé', size: 'lg', apres: afficher,
            transform: function (v) {
              var pt = S.collection('patients').active().filter(function (x) {
                return x.code === v.patientCode;
              })[0];
              var imc = (v.poids && v.taille)
                ? Math.round((v.poids / Math.pow(v.taille / 100, 2)) * 10) / 10 : null;
              return Object.assign({}, v, {
                reference: C.nextRef('CST-', 5),
                patientId: pt ? pt.id : null,
                patient: pt ? pt.nom + ' ' + pt.prenom : v.patientCode,
                tension: (v.tensionSys != null && v.tensionDia != null)
                  ? v.tensionSys + '/' + v.tensionDia : null,
                /* L'IMC est CALCULÉ : le saisir autoriserait une valeur qui ne
                   correspond ni au poids ni à la taille de la même ligne. */
                imc: imc,
                origine: 'accueil',
              });
            },
          })].filter(Boolean),
          columns: [
            { key: 'dateHeure', label: 'Date et heure', render: function (r) { return C.dateHeure(r.dateHeure); } },
            { key: 'patient', label: 'Patient', render: function (r) { return r.patient + ' — ' + r.patientCode; } },
            { key: 'moment', label: 'Moment', render: function (r) {
              return { matin: 'Matin', midi: 'Midi', soir: 'Soir' }[r.moment] || '—'; } },
            { key: 'temperature', label: 'T°', align: 'right',
              render: function (r) { return r.temperature == null ? '—' : r.temperature + ' °C'; } },
            { key: 'tension', label: 'TA', align: 'right', render: function (r) { return r.tension || '—'; } },
            { key: 'pouls', label: 'Pouls', align: 'right',
              render: function (r) { return r.pouls == null ? '—' : r.pouls + ' bpm'; } },
            { key: 'spo2', label: 'SpO₂', align: 'right',
              render: function (r) { return r.spo2 == null ? '—' : r.spo2 + ' %'; } },
            { key: 'imc', label: 'IMC', align: 'right', render: function (r) { return r.imc == null ? '—' : r.imc; } },
            { key: 'alerte', label: 'Contrôle',
              render: function (r) {
                var m = anormale(r);
                return m.length ? U.badge('hors bornes : ' + m.join(', '), 'warning') : U.badge('normales', 'success');
              } },
          ],
          rowActions: K.actionsLigne(colConstantes(), champs(), {
            module: 'M1', refresh: afficher,
            titre: function (r) { return r.patient + ' — ' + C.dateHeure(r.dateHeure); },
            detail: function (r) {
              var m = anormale(r);
              return el('div.space-y-4', null,
                K.grid([
                  ['Patient', r.patient + ' — ' + r.patientCode],
                  ['Date et heure', C.dateHeure(r.dateHeure)],
                  ['Moment', { matin: 'Matin', midi: 'Midi', soir: 'Soir' }[r.moment] || '—'],
                  ['Température', r.temperature == null ? '—' : r.temperature + ' °C'],
                  ['Tension artérielle', r.tension || '—'],
                  ['Pouls', r.pouls == null ? '—' : r.pouls + ' bpm'],
                  ['Fréquence respiratoire', r.fr == null ? '—' : r.fr + ' /min'],
                  ['SpO₂', r.spo2 == null ? '—' : r.spo2 + ' %'],
                  ['Diurèse', r.diurese == null ? '—' : r.diurese + ' L'],
                  ['Poids', r.poids == null ? '—' : r.poids + ' kg'],
                  ['Taille', r.taille == null ? '—' : r.taille + ' cm'],
                  ['IMC', r.imc == null ? '—' : r.imc + ' (calculé)'],
                  ['Relevé par', r.releveePar || '—'],
                ]),
                m.length ? K.note('Constantes hors bornes : <strong>' + m.join(', ') + '</strong>. '
                  + 'Le logiciel signale, il ne diagnostique pas — l’appréciation revient au soignant.',
                { tone: 'warning', icon: 'triangle-alert' }) : null);
            },
          }),
        }));
        U.icons(vue);
      }
    },
  });


  /* ==========================================================================
   * FICHE DE RÉFÉRENCE ET FICHE DE CONTRE-RÉFÉRENCE
   * --------------------------------------------------------------------------
   * Deux pièces d'un même circuit, relevées sur le formulaire officiel :
   *
   *   - la RÉFÉRENCE est remplie « au centre qui fait la référence ». Elle part
   *     avec le patient. La clinique la remplit quand elle ORIENTE un patient
   *     ailleurs, et la reçoit quand un patient lui est ADRESSÉ.
   *
   *   - la CONTRE-RÉFÉRENCE revient du centre d'accueil, souvent des semaines
   *     plus tard — et parfois jamais. C'est pourquoi ce sont DEUX collections
   *     et non une : les fondre obligerait à distinguer « pas encore revenue »
   *     de « champs non remplis », alors que c'est précisément l'indicateur que
   *     la clinique veut suivre.
   *
   * LE LIEN EST LE NUMÉRO DE LA FICHE DE RÉFÉRENCE, comme sur le papier :
   * c'est le seul identifiant que les deux établissements partagent. Un
   * identifiant interne ne voyagerait pas.
   *
   * DEUX INDICATEURS QUE LE FORMULAIRE DEMANDE EXPRESSÉMENT :
   *   - la CONCORDANCE entre le diagnostic de référence et celui de sortie ;
   *   - le caractère JUSTIFIÉ ou non de la référence.
   * Ce sont eux qui disent si la clinique oriente à bon escient.
   * ======================================================================== */
  var SENS_REFERENCE = [
    { code: 'sortante', label: 'Sortante — la clinique réfère un patient ailleurs', icone: 'share-2' },
    { code: 'entrante', label: 'Entrante — un patient est adressé à la clinique', icone: 'download' },
  ];

  var MOTIFS_REFERENCE = [
    'Absence de médicaments',
    'Absence de moyens de diagnostic',
    'Absence de personnel qualifié',
    'Pas de réponse au traitement',
    'Autre (à préciser)',
  ];

  var MOYENS_TRANSPORT = ['Ambulance', 'Véhicule administratif', 'Taxi', 'Barque motorisée',
    'Moto', 'Moyen personnel', 'Autre'];

  var EVOLUTIONS = ['Guéri(e)', 'Évadé(e)', 'Décédé(e)', 'Sortie contre avis médical',
    'Référé vers un autre centre'];

  function colReference() {
    return S.collection('fichesReference', { module: 'M1', entite: 'fiche de référence', prefix: 'REF' });
  }
  function colContreRef() {
    return S.collection('contreReferences', { module: 'M1', entite: 'fiche de contre-référence', prefix: 'CRF' });
  }

  global.SIGH.screen('m1-reference', {
    title: 'Fiches de référence',
    description: 'Patients orientés vers un autre centre, et patients adressés à la clinique.',
    regle: 'La fiche part <strong>avec le patient</strong> et porte ses constantes, ses traitements reçus et '
      + 'le motif de la référence. Une fiche <strong>entrante</strong> ouvre un dossier local sans effacer '
      + 'la pièce d’origine — celle-ci est <strong>numérisée</strong> et conservée. '
      + 'La <strong>contre-référence</strong> attendue est suivie : son absence est un indicateur, pas un oubli.',
    render: function (root) {
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      afficher();
      return null;

      function champs() {
        return [
          { name: 'sens', label: 'Sens de la référence', type: 'select', required: true,
            options: SENS_REFERENCE.map(function (x) { return { value: x.code, label: x.label }; }) },
          { name: 'urgent', label: 'URGENT', type: 'checkbox' },
          { name: 'patientCode', label: 'Patient', type: 'select', required: true, options: optionsPatientsM1() },
          { type: 'section', label: 'Formation sanitaire' },
          { name: 'formationSanitaire', label: 'Nom de la formation sanitaire', type: 'text', required: true,
            hint: 'Pour une référence sortante : la clinique. Pour une entrante : le centre qui adresse.' },
          { name: 'centreAlerte', label: 'Centre d’accueil alerté', type: 'checkbox' },
          { name: 'dateAdmission', label: 'Date d’admission', type: 'date' },
          { name: 'heureAdmission', label: 'Heure d’admission', type: 'text' },
          { type: 'section', label: 'Constantes vitales à la référence' },
          { name: 'pouls', label: 'Pouls (bpm)', type: 'number' },
          { name: 'temperature', label: 'Température (°C)', type: 'number', step: 0.1 },
          { name: 'tension', label: 'Tension artérielle', type: 'text' },
          { name: 'abordVeineux', label: 'Abord veineux posé', type: 'checkbox' },
          { type: 'section', label: 'Personne à contacter' },
          { name: 'contactNom', label: 'Nom et prénom', type: 'text' },
          { name: 'contactAdresse', label: 'Adresse et téléphone', type: 'text' },
          { type: 'section', label: 'Éléments cliniques' },
          { name: 'symptomes', label: 'Symptômes dominants / diagnostic', type: 'textarea', rows: 3, required: true },
          { name: 'traitements', label: 'Traitements donnés', type: 'textarea', rows: 3 },
          { name: 'observations', label: 'Observations', type: 'textarea', rows: 2,
            hint: 'Décrire une situation pertinente dans le traitement ou la référence.' },
          { type: 'section', label: 'Référence' },
          { name: 'motifs', label: 'Motif de la référence', type: 'multiselect', required: true,
            options: MOTIFS_REFERENCE.map(function (x) { return { value: x, label: x }; }) },
          { name: 'motifAutre', label: 'Autre motif — à préciser', type: 'text' },
          { name: 'centreDestination', label: 'Centre ou service où le patient est référé', type: 'text', required: true },
          { name: 'dateReference', label: 'Date de la référence', type: 'date', required: true },
          { name: 'heureReference', label: 'Heure de la référence', type: 'text' },
          { name: 'moyen', label: 'Moyen de transport utilisé', type: 'select',
            options: MOYENS_TRANSPORT.map(function (x) { return { value: x, label: x }; }) },
          { name: 'agentReferent', label: 'Agent qui réfère — nom, qualification, téléphone', type: 'text', required: true },
          { type: 'section', label: 'Transport (rempli par l’ambulancier)' },
          { name: 'departLe', label: 'Date et heure de départ', type: 'text' },
          { name: 'arriveeLe', label: 'Date et heure d’arrivée au centre d’accueil', type: 'text' },
          { name: 'ambulancier', label: 'Nom de l’ambulancier', type: 'text' },
        ];
      }

      function afficher() {
        var rows = colReference().active();
        var sortantes = rows.filter(function (r) { return r.sens === 'sortante'; });
        var entrantes = rows.filter(function (r) { return r.sens === 'entrante'; });
        var urgentes = rows.filter(function (r) { return r.urgent; });
        var refs = colContreRef().active().map(function (c) { return c.numeroReference; });
        var sansRetour = sortantes.filter(function (r) { return refs.indexOf(r.numero) === -1; });

        C.clear(vue);
        vue.appendChild(U.kpiGrid([
          { label: 'Fiches de référence', value: C.num(rows.length), icon: 'share-2', tone: 'navy' },
          { label: 'Sortantes', value: C.num(sortantes.length), icon: 'arrow-up-right', tone: 'info' },
          { label: 'Entrantes', value: C.num(entrantes.length), icon: 'arrow-down-left', tone: 'success',
            hint: 'patients adressés à la clinique' },
          { label: 'Sans contre-référence', value: C.num(sansRetour.length), icon: 'clock',
            tone: sansRetour.length ? 'warning' : 'success',
            hint: 'le centre d’accueil n’a pas encore répondu' },
        ]));

        vue.appendChild(K.note('Une fiche <strong>entrante</strong> ouvre un dossier local <strong>sans '
          + 'effacer la pièce d’origine</strong> : celle-ci est numérisée et conservée au dossier, avec sa '
          + 'couverture d’assurance. Le patient référé arrive avec ses documents — les jeter reviendrait à '
          + 'perdre tout ce que le centre d’origine a déjà fait.', { tone: 'info', icon: 'paperclip' }));

        vue.appendChild(U.tabs([
          { id: 'toutes', label: 'Toutes', badge: rows.length, render: function () { return tableau(rows); } },
          { id: 'sortantes', label: 'Sortantes', badge: sortantes.length, render: function () { return tableau(sortantes); } },
          { id: 'entrantes', label: 'Entrantes', badge: entrantes.length, render: function () { return tableau(entrantes); } },
          { id: 'attente', label: 'Contre-référence attendue', badge: sansRetour.length,
            render: function () { return tableau(sansRetour); } },
        ]));
        U.icons(vue);
      }

      function tableau(rows) {
        return U.dataTable({
          rows: C.sortBy(rows, 'dateReference').reverse(),
          empty: 'Aucune fiche de référence enregistrée.',
          actions: [K.creer(colReference(), champs(), {
            module: 'M1', label: 'Nouvelle fiche de référence', titre: 'Fiche de référence',
            entite: 'Fiche de référence', size: 'xl', apres: afficher,
            transform: function (v) {
              var pt = S.collection('patients').active().filter(function (x) { return x.code === v.patientCode; })[0];
              return Object.assign({}, v, {
                numero: C.nextRef('REF-', 5),
                patientId: pt ? pt.id : null,
                patient: pt ? pt.nom + ' ' + pt.prenom : v.patientCode,
                age: pt ? C.age(pt.dateNaissance) : null,
                sexe: pt ? pt.sexe : null,
                adresse: pt ? pt.quartier : null,
              });
            },
          })].filter(Boolean),
          columns: [
            { key: 'numero', label: 'N° de référence',
              render: function (r) {
                return el('span.inline-flex.items-center.gap-2', null, [
                  el('span.font-mono.text-xs', { text: r.numero }),
                  r.urgent ? U.badge('URGENT', 'danger') : null,
                ]);
              } },
            { key: 'sens', label: 'Sens', render: function (r) {
              return r.sens === 'entrante' ? U.badge('Entrante', 'success') : U.badge('Sortante', 'info');
            } },
            { key: 'patient', label: 'Patient', render: function (r) { return r.patient + ' — ' + r.patientCode; } },
            { key: 'centreDestination', label: 'Centre destinataire' },
            { key: 'dateReference', label: 'Date', render: function (r) { return C.dateFR(r.dateReference); } },
            { key: 'agentReferent', label: 'Agent référent' },
            { key: 'retour', label: 'Contre-référence',
              render: function (r) {
                var cr = colContreRef().active().filter(function (c) { return c.numeroReference === r.numero; })[0];
                if (cr) return U.badge('Reçue le ' + C.dateFR(cr.dateArrivee), 'success');
                return r.sens === 'sortante' ? U.badge('Attendue', 'warning') : el('span.text-xs.text-slate-400', { text: '—' });
              } },
          ],
          rowActions: function (r) {
            return [K.iconBtn('printer', 'Imprimer la fiche', function () { imprimer(r); })]
              .concat(K.actionsLigne(colReference(), champs(), {
                module: 'M1', refresh: afficher, detail: detail,
                titre: function (x) { return x.numero; },
              })(r));
          },
        });
      }

      function detail(r) {
        var cr = colContreRef().active().filter(function (c) { return c.numeroReference === r.numero; })[0];
        return el('div.space-y-4', null,
          K.grid([
            ['N° de référence', r.numero],
            ['Sens', r.sens === 'entrante' ? 'Entrante — patient adressé à la clinique' : 'Sortante — patient orienté ailleurs'],
            ['Urgence', r.urgent ? 'OUI' : 'Non'],
            ['Patient', r.patient + ' — ' + r.patientCode],
            ['Formation sanitaire', r.formationSanitaire],
            ['Centre d’accueil alerté', r.centreAlerte ? 'Oui' : 'Non'],
            ['Constantes', [r.pouls ? 'pouls ' + r.pouls : null,
              r.temperature ? r.temperature + ' °C' : null,
              r.tension ? 'TA ' + r.tension : null].filter(Boolean).join(' · ') || '—'],
            ['Abord veineux', r.abordVeineux ? 'Posé' : 'Non posé'],
            ['Centre destinataire', r.centreDestination],
            ['Date et heure', C.dateFR(r.dateReference) + (r.heureReference ? ' à ' + r.heureReference : '')],
            ['Moyen de transport', r.moyen || '—'],
            ['Agent référent', r.agentReferent],
            ['Départ', r.departLe || '—'], ['Arrivée', r.arriveeLe || '—'],
            ['Ambulancier', r.ambulancier || '—'],
          ]),
          K.section('Symptômes dominants / diagnostic',
            el('p.whitespace-pre-line.text-sm.text-slate-600', { text: r.symptomes || '—' })),
          r.traitements ? K.section('Traitements donnés',
            el('p.whitespace-pre-line.text-sm.text-slate-600', { text: r.traitements })) : null,
          K.section('Motif de la référence',
            K.miniTable(['Motif'], (r.motifs || []).map(function (m) {
              return [m === 'Autre (à préciser)' && r.motifAutre ? m + ' — ' + r.motifAutre : m];
            }))),
          cr ? K.note('Contre-référence <strong>reçue</strong> le ' + C.dateFR(cr.dateArrivee)
            + ' — diagnostic de sortie : ' + (cr.diagnosticSortie || '—')
            + ' · concordance : ' + (cr.concordance ? 'OUI' : 'NON')
            + ' · référence ' + (cr.justifiee ? 'justifiée' : 'NON justifiée') + '.',
          { tone: cr.concordance ? 'success' : 'warning', icon: 'reply' })
            : (r.sens === 'sortante'
              ? K.note('Aucune contre-référence reçue à ce jour. Son absence est <strong>suivie</strong> : '
                + 'c’est un indicateur de la relation avec le centre d’accueil, pas un oubli de saisie.',
              { tone: 'warning', icon: 'clock' })
              : null));
      }

      function imprimer(r) {
        P.etat({
          titre: 'FICHE DE RÉFÉRENCE',
          sousTitre: 'N° ' + r.numero + (r.urgent ? '   —   URGENT' : ''),
          cartouche: [
            ['Formation sanitaire', r.formationSanitaire],
            ['Centre d’accueil alerté', r.centreAlerte ? 'Oui' : 'Non'],
            ['Patient', r.patient], ['Dossier', r.patientCode],
            ['Âge', r.age != null ? r.age + ' ans' : '—'], ['Sexe', r.sexe || '—'],
            ['Adresse', r.adresse || '—'],
            ['Personne à contacter', (r.contactNom || '—') + (r.contactAdresse ? ' — ' + r.contactAdresse : '')],
            ['Constantes vitales', [r.pouls ? 'Pouls ' + r.pouls : null,
              r.temperature ? 'T° ' + r.temperature : null,
              r.tension ? 'TA ' + r.tension : null].filter(Boolean).join('   ') || '—'],
            ['Abord veineux', r.abordVeineux ? 'Oui' : 'Non'],
            ['Centre destinataire', r.centreDestination],
            ['Date et heure de référence', C.dateFR(r.dateReference) + (r.heureReference ? ' à ' + r.heureReference : '')],
            ['Moyen utilisé', r.moyen || '—'],
          ],
          contenu: el('div', null, [
            el('p.mb-1.mt-2.text-\\[10px\\].font-semibold.uppercase', { text: 'Symptômes dominants / diagnostic' }),
            el('p.whitespace-pre-line.text-\\[10px\\].leading-relaxed', { text: r.symptomes || '—' }),
            el('p.mb-1.mt-3.text-\\[10px\\].font-semibold.uppercase', { text: 'Traitements donnés' }),
            el('p.whitespace-pre-line.text-\\[10px\\].leading-relaxed', { text: r.traitements || '—' }),
            el('p.mb-1.mt-3.text-\\[10px\\].font-semibold.uppercase', { text: 'Motif de la référence' }),
            el('p.text-\\[10px\\].leading-relaxed', {
              text: (r.motifs || []).join(' · ') + (r.motifAutre ? ' — ' + r.motifAutre : '') || '—',
            }),
            el('p.mb-1.mt-3.text-\\[10px\\].font-semibold.uppercase', { text: 'Transport' }),
            el('p.text-\\[10px\\].leading-relaxed', {
              text: 'Départ : ' + (r.departLe || '……………')
                + '     Arrivée au centre d’accueil : ' + (r.arriveeLe || '……………'),
            }),
          ]),
          signatures: [
            { role: 'L’agent qui réfère', nom: r.agentReferent, mention: 'Signature et téléphone' },
            { role: 'L’ambulancier', nom: r.ambulancier || '', mention: 'Signature et nom' },
          ],
        });
      }
    },
  });

  /* ==========================================================================
   * FICHE DE CONTRE-RÉFÉRENCE
   * --------------------------------------------------------------------------
   * Elle revient du centre d'accueil et dit ce qu'il est advenu du patient.
   * Deux champs en font tout l'intérêt et le formulaire les demande
   * expressément : la CONCORDANCE des diagnostics et le caractère JUSTIFIÉ de
   * la référence. Ce sont eux qui disent si la clinique oriente à bon escient —
   * une référence dont le diagnostic de sortie ne concorde pas est une
   * référence à comprendre, pas à cacher.
   * ======================================================================== */
  global.SIGH.screen('m1-contre-reference', {
    title: 'Fiches de contre-référence',
    description: 'Retours des centres d’accueil sur les patients référés : diagnostic de sortie, concordance, évolution.',
    regle: 'La contre-référence se rattache à la fiche de référence par son <strong>numéro</strong> — le seul '
      + 'identifiant que les deux établissements partagent. La <strong>concordance des diagnostics</strong> et '
      + 'le caractère <strong>justifié</strong> de la référence sont les deux indicateurs que le formulaire '
      + 'officiel demande : ils disent si la clinique oriente à bon escient.',
    render: function (root) {
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      afficher();
      return null;

      function champs() {
        return [
          { name: 'numeroReference', label: 'N° de la fiche de référence', type: 'select', required: true,
            options: colReference().active().filter(function (r) { return r.sens === 'sortante'; })
              .map(function (r) {
                return { value: r.numero, label: r.numero + ' — ' + r.patient,
                  detail: r.centreDestination + ' — ' + C.dateFR(r.dateReference) };
              }),
            hint: 'Le numéro est le seul lien que les deux établissements partagent.' },
          { name: 'centreAccueil', label: 'Nom du centre d’accueil', type: 'text', required: true },
          { name: 'service', label: 'Service', type: 'text' },
          { name: 'dateArrivee', label: 'Date d’arrivée', type: 'date', required: true },
          { name: 'heureArrivee', label: 'Heure d’arrivée', type: 'text' },
          { name: 'agentReferent', label: 'Nom de l’agent qui a référé', type: 'text' },
          { name: 'structureProvenance', label: 'Structure de provenance', type: 'text' },
          { name: 'hospitalise', label: 'Le patient a-t-il été hospitalisé ?', type: 'checkbox' },
          { name: 'numeroDossier', label: 'N° du dossier au centre d’accueil', type: 'text' },
          { type: 'section', label: 'Diagnostics' },
          { name: 'diagnosticEntree', label: 'Diagnostic d’entrée', type: 'textarea', rows: 2, required: true },
          { name: 'diagnosticSortie', label: 'Diagnostic de sortie', type: 'textarea', rows: 2, required: true },
          { name: 'concordance', label: 'Concordance entre les diagnostics de référence et de sortie', type: 'checkbox',
            hint: 'Une discordance n’est pas une faute : c’est une information à exploiter.' },
          { name: 'justifiee', label: 'Référence justifiée', type: 'checkbox' },
          { name: 'motifNonJustifiee', label: 'Si non justifiée — pourquoi', type: 'text' },
          { type: 'section', label: 'Évolution' },
          { name: 'evolution', label: 'Évolution de la maladie', type: 'select', required: true,
            options: EVOLUTIONS.map(function (x) { return { value: x, label: x }; }) },
          { name: 'observations', label: 'Observations et conseils à l’attention du centre de référence',
            type: 'textarea', rows: 3 },
          { name: 'chefService', label: 'Nom et prénom du chef de service ou son représentant', type: 'text', required: true },
        ];
      }

      function afficher() {
        var rows = colContreRef().active();
        var concordantes = rows.filter(function (r) { return r.concordance; });
        var justifiees = rows.filter(function (r) { return r.justifiee; });
        var deces = rows.filter(function (r) { return /Décédé/.test(r.evolution || ''); });

        C.clear(vue);
        vue.appendChild(U.kpiGrid([
          { label: 'Contre-références reçues', value: C.num(rows.length), icon: 'reply', tone: 'navy' },
          { label: 'Diagnostics concordants', value: C.num(concordantes.length), icon: 'check-check',
            tone: 'success',
            hint: rows.length ? C.pct(concordantes.length / rows.length) + ' des retours' : null },
          { label: 'Références justifiées', value: C.num(justifiees.length), icon: 'thumbs-up',
            tone: justifiees.length === rows.length ? 'success' : 'warning',
            hint: rows.length ? C.pct(justifiees.length / rows.length) + ' des retours' : null },
          { label: 'Décès au centre d’accueil', value: C.num(deces.length), icon: 'cross',
            tone: deces.length ? 'danger' : 'neutral' },
        ]));

        vue.appendChild(K.note('Une <strong>discordance</strong> de diagnostic ou une référence jugée '
          + '<strong>non justifiée</strong> n’est pas une faute à masquer : c’est l’information la plus utile '
          + 'que le centre d’accueil puisse renvoyer. Le taux de concordance mesure la qualité de l’orientation, '
          + 'pas la compétence d’un agent.', { tone: 'info', icon: 'target' }));

        vue.appendChild(U.dataTable({
          rows: C.sortBy(rows, 'dateArrivee').reverse(),
          empty: 'Aucune contre-référence reçue.',
          actions: [K.creer(colContreRef(), champs(), {
            module: 'M1', label: 'Enregistrer une contre-référence', titre: 'Fiche de contre-référence',
            entite: 'Contre-référence', size: 'xl', apres: afficher,
            transform: function (v) {
              var ref = colReference().active().filter(function (r) { return r.numero === v.numeroReference; })[0];
              return Object.assign({}, v, {
                reference: C.nextRef('CRF-', 5),
                patientId: ref ? ref.patientId : null,
                patient: ref ? ref.patient : '—',
                patientCode: ref ? ref.patientCode : null,
              });
            },
          })].filter(Boolean),
          columns: [
            { key: 'reference', label: 'Référence' },
            { key: 'numeroReference', label: 'Fiche de référence',
              render: function (r) { return el('span.font-mono.text-xs', { text: r.numeroReference }); } },
            { key: 'patient', label: 'Patient' },
            { key: 'centreAccueil', label: 'Centre d’accueil' },
            { key: 'dateArrivee', label: 'Arrivée', render: function (r) { return C.dateFR(r.dateArrivee); } },
            { key: 'evolution', label: 'Évolution' },
            { key: 'concordance', label: 'Concordance', align: 'center',
              render: function (r) {
                return r.concordance ? U.badge('Oui', 'success') : U.badge('NON', 'warning');
              } },
            { key: 'justifiee', label: 'Justifiée', align: 'center',
              render: function (r) {
                return r.justifiee ? U.badge('Oui', 'success') : U.badge('NON', 'warning');
              } },
          ],
          rowActions: K.actionsLigne(colContreRef(), champs(), {
            module: 'M1', refresh: afficher,
            titre: function (r) { return r.reference; },
            detail: function (r) {
              return el('div.space-y-4', null,
                K.grid([
                  ['Référence', r.reference],
                  ['Fiche de référence', r.numeroReference],
                  ['Patient', r.patient],
                  ['Centre d’accueil', r.centreAccueil], ['Service', r.service || '—'],
                  ['Arrivée', C.dateFR(r.dateArrivee) + (r.heureArrivee ? ' à ' + r.heureArrivee : '')],
                  ['Structure de provenance', r.structureProvenance || '—'],
                  ['Hospitalisé', r.hospitalise ? 'Oui' : 'Non'],
                  ['N° de dossier au centre d’accueil', r.numeroDossier || '—'],
                  ['Évolution', r.evolution],
                  ['Chef de service', r.chefService],
                ]),
                K.section('Diagnostic d’entrée', el('p.text-sm.text-slate-600', { text: r.diagnosticEntree })),
                K.section('Diagnostic de sortie', el('p.text-sm.text-slate-600', { text: r.diagnosticSortie })),
                K.note('Concordance des diagnostics : <strong>' + (r.concordance ? 'OUI' : 'NON')
                  + '</strong> — Référence <strong>' + (r.justifiee ? 'justifiée' : 'NON justifiée') + '</strong>'
                  + (r.motifNonJustifiee ? ' : ' + r.motifNonJustifiee : '') + '.',
                { tone: r.concordance && r.justifiee ? 'success' : 'warning', icon: 'target' }),
                r.observations ? K.section('Observations et conseils',
                  el('p.whitespace-pre-line.text-sm.text-slate-600', { text: r.observations })) : null);
            },
          }),
        }));
        U.icons(vue);
      }
    },
  });


  /* ==========================================================================
   * DOSSIER DE CONSULTATION ÉTENDU — DEUX ZONES, DEUX RESPONSABILITÉS
   * --------------------------------------------------------------------------
   * Structure dictée par la Direction le 25/08/2026.
   *
   * LA COUPURE EN DEUX ZONES N'EST PAS UNE COMMODITÉ D'AFFICHAGE, c'est une
   * frontière de responsabilité :
   *
   *   ZONE 1 — ACCUEIL : identification, coordonnées, couverture, constantes.
   *     L'accueil remplit, et ne voit rien d'autre (RG-13). Toute consultation
   *     de dossier par l'accueil est journalisée.
   *
   *   ZONE 2 — CONSULTATION : contrôle et historique, antécédents, examen
   *     physique, décisions. Le soignant remplit ; l'accueil n'y accède pas.
   *
   * Mêler les deux ferait qu'un secrétaire médical lirait un diagnostic en
   * cherchant un numéro de téléphone.
   *
   * LE CYCLE DE VIE EST ORDONNÉ : EN ATTENTE → EN CONSULTATION → EN ATTENTE
   * LABO → CLÔTURÉ. Les sauts sont refusés — clôturer un dossier resté « en
   * attente » signerait une consultation qui n'a pas eu lieu.
   *
   * LES ACTES CHIRURGICAUX ET LE BLOC NE S'ÉCRIVENT QUE PAR LE CHIRURGIEN.
   * La règle porte sur l'ÉCRITURE, jamais sur la lecture : le généraliste doit
   * pouvoir lire ce que le chirurgien a écrit — c'est son patient aussi.
   * ======================================================================== */
  function colDossiers() {
    return S.collection('dossiersConsultation', { module: 'M1', entite: 'dossier de consultation', prefix: 'DOS' });
  }

  /* ==========================================================================
   * DOSSIERS DE CONSULTATION À DEUX ZONES — FUSIONNÉS DANS LE RÉPERTOIRE
   * --------------------------------------------------------------------------
   * Arbitrage du 31/08/2026 (Bug 1 des Instructions) : le répertoire est
   * l'UNIQUE point d'entrée du dossier. La vue à deux zones vit ici, en
   * fonction de module, et le répertoire la monte en onglet — gardé par les
   * droits de l'ANCIEN écran (m1-dossier-etendu) : le biologiste, à qui la
   * Direction a fermé le dossier de consultation, ne gagne rien à la fusion.
   * Le cloisonnement Zone 1 / Zone 2 (RG-13) et la journalisation sont
   * inchangés : ils vivent dans la vue, pas dans l'écran qui la porte.
   * ======================================================================== */
  function construireDossiersEtendus() {
      var vue = el('div.space-y-4');
      afficher();
      return vue;

      function session() { return S.session() || {}; }
      function capacite() {
        var s2 = session();
        return s2.fonction || (s2.role === 'medecin' ? 'medecin' : s2.role) || 'accueil';
      }
      /* L'accueil est cloisonné : c'est le socle qui le dit, pas cet écran —
         trois écrans posent la même question. */
      function estAccueil() {
        var s2 = session();
        return s2.role === 'reception' || capacite() === 'accueil';
      }
      function estChirurgien() { return capacite() === 'chirurgien'; }

      function etatsDossier() { return D.ETATS_DOSSIER || []; }
      function etatDe(code) { return D.etatDossier ? D.etatDossier(code) : { label: code, couleur: 'neutral' }; }

      function afficher() {
        var rows = colDossiers().active();
        var parEtat = {};
        etatsDossier().forEach(function (e) {
          parEtat[e.code] = rows.filter(function (r) { return r.etat === e.code; }).length;
        });

        C.clear(vue);
        vue.appendChild(U.kpiGrid(etatsDossier().map(function (e) {
          return {
            label: e.label, value: C.num(parEtat[e.code] || 0),
            icon: { attente: 'clock', consultation: 'stethoscope',
              attente_labo: 'flask-conical', cloture: 'check-check' }[e.code] || 'file',
            tone: e.couleur, hint: e.note,
          };
        })));

        if (estAccueil()) {
          vue.appendChild(K.note('<strong>Profil accueil.</strong> Vous tenez la <strong>zone 1</strong> — '
            + 'identification, coordonnées, couverture et constantes. La <strong>zone 2</strong> (antécédents, '
            + 'examen physique, diagnostic, traitement) vous est fermée par RG-13, et chacune de vos '
            + 'recherches de dossier est <strong>journalisée</strong>. Ce n’est pas une défiance : c’est ce qui '
            + 'protège le dossier d’un voisin ou d’un notable.', { tone: 'warning', icon: 'shield' }));
        } else if (!estChirurgien()) {
          vue.appendChild(K.note('Les rubriques <strong>Actes chirurgicaux</strong> et <strong>Bloc</strong> '
            + 'sont en <strong>lecture seule</strong> pour votre profil : seul le chirurgien les renseigne. '
            + 'Vous les lisez — c’est votre patient aussi.', { tone: 'info', icon: 'scissors' }));
        }

        vue.appendChild(U.tabs([
          { id: 'dossiers', label: 'Dossiers', badge: rows.length, render: function () { return tableau(rows); } },
          { id: 'attente', label: 'En attente', badge: parEtat.attente || 0,
            render: function () { return tableau(rows.filter(function (r) { return r.etat === 'attente'; })); } },
          { id: 'labo', label: 'En attente labo', badge: parEtat.attente_labo || 0,
            render: function () { return tableau(rows.filter(function (r) { return r.etat === 'attente_labo'; })); } },
        ]));
        U.icons(vue);
      }

      /* --------------------------------------------------------------------
       * ZONE 1 — ACCUEIL
       * ------------------------------------------------------------------ */
      function champsZone1() {
        return [
          { type: 'section', label: 'Zone 1 — Accueil : identification' },
          { name: 'patientCode', label: 'Patient', type: 'select', required: true, options: optionsPatientsM1() },
          { name: 'dateArrivee', label: 'Date d’arrivée', type: 'date', required: true },
          { name: 'heureArrivee', label: 'Heure d’arrivée', type: 'text', required: true,
            hint: 'La Direction demande que l’heure d’arrivée soit conservée au dossier.' },
          { name: 'motifVenue', label: 'Motif de la venue', type: 'text', required: true },
          { name: 'service', label: 'Service demandé', type: 'select', required: true,
            options: [
              { value: 'medecine', label: 'Médecine' },
              { value: 'maternite', label: 'Maternité' },
              { value: 'specialite', label: 'Médecine et spécialité' },
              { value: 'chirurgie', label: 'Chirurgie' },
            ] },
          { name: 'accompagnant', label: 'Accompagnant', type: 'text' },
          { type: 'section', label: 'Zone 1 — Constantes relevées à l’accueil' },
          { name: 'temperature', label: 'Température (°C)', type: 'number', step: 0.1, min: 30, max: 45 },
          { name: 'poids', label: 'Poids (kg)', type: 'number', step: 0.1 },
          { name: 'taille', label: 'Taille (cm)', type: 'number' },
          { name: 'tension', label: 'Tension artérielle', type: 'text' },
          { name: 'pouls', label: 'Pouls (bpm)', type: 'number' },
          { name: 'spo2', label: 'SpO₂ (%)', type: 'number', min: 50, max: 100 },
          { name: 'recuPar', label: 'Reçu par', type: 'text', required: true },
        ];
      }

      /* --------------------------------------------------------------------
       * ZONE 2 — CONSULTATION
       * ------------------------------------------------------------------ */
      function champsZone2(dossier) {
        var out = [
          { type: 'section', label: 'Zone 2 — Contrôle et historique' },
          { name: 'typeVenue', label: 'Type de venue', type: 'select', required: true,
            options: [
              { value: 'premiere', label: 'Première consultation' },
              { value: 'controle', label: 'Contrôle' },
              { value: 'suivi', label: 'Suivi de traitement' },
              { value: 'urgence', label: 'Urgence' },
            ] },
          { name: 'histoire', label: 'Histoire de la maladie', type: 'textarea', rows: 4, required: true },
          { name: 'traitementEnCours', label: 'Traitement en cours à l’arrivée', type: 'textarea', rows: 2 },
        ];

        /* Les trois catégories d'antécédents, STRICTES. */
        (D.CATEGORIES_ANTECEDENT || []).forEach(function (cat) {
          out.push({ type: 'section', label: cat.label });
          out.push({ name: 'ant_' + cat.code, label: cat.label, type: 'textarea', rows: 3,
            hint: cat.note + ' — exemples : ' + cat.exemples.slice(0, 4).join(', ') + '…' });
        });

        /* L'examen physique, quatre temps, dans l'ordre. */
        out.push({ type: 'section', label: 'Examen physique' });
        (D.TEMPS_EXAMEN || []).forEach(function (t) {
          out.push({ name: 'exam_' + t.code, label: t.ordre + '. ' + t.label, type: 'textarea', rows: 2,
            hint: t.note });
        });

        /* Décisions. */
        out.push({ type: 'section', label: 'Décisions, analyses et traitements' });
        out.push({ name: 'diagnostic', label: 'Diagnostic retenu', type: 'textarea', rows: 2, required: true });
        out.push({ name: 'pathologies', label: 'Pathologies (référentiel)', type: 'multiselect',
          options: S.collection('pathologies').active().map(function (x) {
            return { value: x.code, label: x.libelle, detail: x.chapitre };
          }),
          hint: 'La pathologie est un CODE que la clinique compte ; le diagnostic est la phrase que vous rédigez.' });
        out.push({ name: 'analysesDemandees', label: 'Analyses demandées', type: 'textarea', rows: 2 });
        out.push({ name: 'traitement', label: 'Traitement prescrit', type: 'textarea', rows: 3 });
        out.push({ name: 'conduite', label: 'Conduite à tenir', type: 'textarea', rows: 2 });

        /* Les rubriques chirurgicales : présentes pour tous, ÉCRIVABLES par le
           seul chirurgien. On ne les masque pas au généraliste — il doit
           pouvoir les lire, c'est son patient. */
        out.push({ type: 'section',
          label: 'Actes chirurgicaux et bloc' + (estChirurgien() ? '' : ' — lecture seule') });
        (D.RUBRIQUES_CHIRURGICALES || []).forEach(function (rub) {
          var libelles = {
            actesChirurgicaux: 'Actes chirurgicaux envisagés ou pratiqués',
            indicationOperatoire: 'Indication opératoire',
            blocPrevu: 'Programmation au bloc',
            risqueOperatoire: 'Risque opératoire évalué',
          };
          out.push({
            name: rub, label: libelles[rub] || rub, type: 'textarea', rows: 2,
            disabled: !estChirurgien(),
            hint: estChirurgien() ? null
              : 'Renseigné par le chirurgien seulement. Vous le lisez — c’est votre patient aussi.',
          });
        });
        out.push({ name: 'soignant', label: 'Soignant', type: 'text', required: true });
        return out;
      }

      function tableau(rows) {
        return U.dataTable({
          rows: C.sortBy(rows, 'dateArrivee').reverse(),
          empty: 'Aucun dossier de consultation.',
          actions: [K.creer(colDossiers(), champsZone1(), {
            module: 'M1', label: 'Ouvrir un dossier (accueil)', titre: 'Zone 1 — Accueil',
            entite: 'Dossier', size: 'lg', apres: afficher,
            transform: function (v) {
              var pt = S.collection('patients').active().filter(function (x) { return x.code === v.patientCode; })[0];
              var imc = (v.poids && v.taille)
                ? Math.round((v.poids / Math.pow(v.taille / 100, 2)) * 10) / 10 : null;
              return Object.assign({}, v, {
                reference: C.nextRef('DOS-', 5),
                patientId: pt ? pt.id : null,
                patient: pt ? pt.nom + ' ' + pt.prenom : v.patientCode,
                nip: v.patientCode,
                age: pt ? C.age(pt.dateNaissance) : null,
                sexe: pt ? pt.sexe : null,
                assureur: pt ? pt.assureurNom || pt.assureur : null,
                imc: imc,
                /* Un dossier naît EN ATTENTE : l'accueil enregistre, il ne
                   consulte pas. */
                etat: 'attente',
                ouvertLe: new Date().toISOString(),
              });
            },
          })].filter(Boolean),
          columns: [
            { key: 'reference', label: 'Dossier' },
            { key: 'patient', label: 'Patient',
              render: function (r) { return r.patient + ' — ' + r.nip; } },
            { key: 'dateArrivee', label: 'Arrivée',
              render: function (r) { return C.dateFR(r.dateArrivee) + (r.heureArrivee ? ' ' + r.heureArrivee : ''); } },
            { key: 'service', label: 'Service' },
            { key: 'motifVenue', label: 'Motif' },
            { key: 'etat', label: 'État',
              render: function (r) { var e = etatDe(r.etat); return U.badge(e.label, e.couleur); } },
            { key: 'soignant', label: 'Soignant', render: function (r) { return r.soignant || '—'; } },
          ],
          rowActions: function (r) {
            var actes = [];
            /* L'accueil ne voit que la zone 1, et sa consultation est tracée. */
            if (estAccueil()) {
              actes.push(K.iconBtn('eye', 'Consulter la zone administrative', function () {
                consulterAccueil(r);
              }));
              return actes;
            }
            if (K.droits('M1').editer) {
              actes.push(K.btn('Zone 2 — Consultation', { variant: 'primary', size: 'sm', icon: 'stethoscope',
                onclick: function () { saisirZone2(r); } }));
              actes.push(K.iconBtn('arrow-right', 'Changer l’état du dossier', function () { changerEtat(r); }));
            }
            actes.push(K.iconBtn('eye', 'Voir le dossier complet', function () { consulterComplet(r); }));
            actes.push(K.iconBtn('printer', 'Imprimer le dossier', function () { imprimer(r); }));
            return actes;
          },
        });
      }

      /* La vue de l'accueil : zone 1 seulement, et la consultation est
         journalisée (RG-12) — demande expresse de la Direction. */
      function consulterAccueil(r) {
        var pt = S.collection('patients').active().filter(function (x) { return x.id === r.patientId; })[0];
        if (PR.journaliserRecherche) {
          PR.journaliserRecherche(pt, { ecran: 'm1-dossier-etendu', action: 'consultation_zone1' });
        }
        var vu = PR.dossierPourAccueil ? PR.dossierPourAccueil(pt) : { motif: null };
        U.drawer({
          title: r.patient + ' — ' + r.nip,
          subtitle: 'Zone 1 — Accueil',
          body: el('div.space-y-4', null, [
            K.grid([
              ['Dossier', r.reference], ['Patient', r.patient], ['NIP', r.nip],
              ['Âge', r.age != null ? r.age + ' ans' : '—'], ['Sexe', r.sexe || '—'],
              ['Couverture', r.assureur || 'Non assuré'],
              ['Arrivée', C.dateFR(r.dateArrivee) + (r.heureArrivee ? ' à ' + r.heureArrivee : '')],
              ['Motif de la venue', r.motifVenue],
              ['Service demandé', r.service],
              ['Reçu par', r.recuPar || '—'],
            ]),
            K.section('Constantes relevées à l’accueil',
              K.miniTable(['Constante', 'Valeur'], [
                ['Température', r.temperature != null ? r.temperature + ' °C' : '—'],
                ['Tension artérielle', r.tension || '—'],
                ['Pouls', r.pouls != null ? r.pouls + ' bpm' : '—'],
                ['SpO₂', r.spo2 != null ? r.spo2 + ' %' : '—'],
                ['Poids', r.poids != null ? r.poids + ' kg' : '—'],
                ['Taille', r.taille != null ? r.taille + ' cm' : '—'],
                ['IMC', r.imc != null ? r.imc + ' (calculé)' : '—'],
              ])),
            K.note(vu.motif || 'La zone clinique vous est fermée (RG-13). '
              + 'Cette consultation vient d’être <strong>journalisée</strong>.',
            { tone: 'warning', icon: 'shield' }),
          ]),
        });
      }

      function saisirZone2(r) {
        var f = U.form(champsZone2(r), r);
        var m = U.modal({
          title: 'Zone 2 — Consultation',
          subtitle: r.patient + ' — ' + r.nip + '   ·   arrivé le '
            + C.dateFR(r.dateArrivee) + ' à ' + (r.heureArrivee || '—'),
          size: 'xl',
          body: el('div.space-y-3', null, [
            /* Les constantes de l'accueil sont RAPPELÉES, non ressaisies : le
               soignant doit les avoir sous les yeux sans pouvoir les réécrire. */
            K.note('Constantes relevées à l’accueil — T° ' + (r.temperature != null ? r.temperature + ' °C' : '—')
              + '   ·   TA ' + (r.tension || '—')
              + '   ·   Pouls ' + (r.pouls != null ? r.pouls : '—')
              + '   ·   SpO₂ ' + (r.spo2 != null ? r.spo2 + ' %' : '—')
              + '   ·   Poids ' + (r.poids != null ? r.poids + ' kg' : '—')
              + (r.imc != null ? '   ·   IMC ' + r.imc : ''),
            { tone: 'info', icon: 'thermometer' }),
            f,
          ]),
          footer: [
            K.btn('Fermer sans enregistrer', { onclick: function () { m.close(); } }),
            K.btn('Enregistrer la consultation', { variant: 'primary', icon: 'save',
              onclick: function () {
                var v = f.collect();
                if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                /* Le contrôle d'écriture est REFAIT ici : un champ désactivé
                   dans le navigateur ne protège rien. */
                var refus = null;
                (D.RUBRIQUES_CHIRURGICALES || []).forEach(function (rub) {
                  var permis = D.peutEcrireRubrique(rub, capacite());
                  if (!permis.ok && v[rub] !== r[rub]) refus = permis.motif;
                  if (!permis.ok) v[rub] = r[rub];
                });
                if (refus) U.toast(refus, { type: 'warning' });

                var maj = Object.assign({}, v);
                /* Le dossier passe EN CONSULTATION s'il ne l'était pas : c'est
                   le fait de saisir qui le fait avancer, pas un bouton à part. */
                if (r.etat === 'attente') maj.etat = 'consultation';
                colDossiers().update(r.id, maj);
                m.close(); afficher();
                U.toast('Consultation enregistrée.', { type: 'success', detail: r.reference });
              } }),
          ],
        });
      }

      /* Le changement d'état, avec ses transitions permises. */
      function changerEtat(r) {
        var courant = etatDe(r.etat);
        var suivants = (courant.suivants || []).map(function (c) {
          var e = etatDe(c);
          return { value: c, label: e.label, detail: e.note };
        });
        if (!suivants.length) {
          U.toast('Le dossier est clôturé : aucun état suivant.', { type: 'info' });
          return;
        }
        var f = U.form([
          { name: 'etat', label: 'Nouvel état', type: 'select', required: true, options: suivants },
          { name: 'motifEtat', label: 'Précision', type: 'text' },
        ], {});
        var m = U.modal({
          title: 'État du dossier — ' + r.reference,
          subtitle: 'Actuellement : ' + courant.label,
          body: el('div.space-y-3', null, [
            K.note('Les <strong>sauts d’état sont refusés</strong> : clôturer un dossier resté « en attente » '
              + 'signerait une consultation qui n’a pas eu lieu. Depuis « ' + courant.label + ' », les états '
              + 'accessibles sont : ' + suivants.map(function (x) { return x.label; }).join(', ') + '.',
            { tone: 'info', icon: 'route' }),
            f,
          ]),
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Appliquer', { variant: 'primary', icon: 'check',
              onclick: function () {
                var v = f.collect();
                if (!v) return;
                if (D.transitionPermise && !D.transitionPermise(r.etat, v.etat)) {
                  U.toast('Transition refusée : « ' + courant.label + ' » ne mène pas à « '
                    + etatDe(v.etat).label + ' ».', { type: 'error' });
                  return;
                }
                colDossiers().update(r.id, {
                  etat: v.etat, motifEtat: v.motifEtat,
                  cloturLe: v.etat === 'cloture' ? new Date().toISOString() : null,
                });
                m.close(); afficher();
                U.toast('Dossier ' + etatDe(v.etat).label + '.', { type: 'success', detail: r.reference });
              } }),
          ],
        });
      }

      function consulterComplet(r) {
        function zone(titre, lignes) {
          return K.section(titre, K.miniTable(['Rubrique', 'Contenu'], lignes));
        }
        var ant = (D.CATEGORIES_ANTECEDENT || []).map(function (c) {
          return [c.label, r['ant_' + c.code] || '—'];
        });
        var exam = (D.TEMPS_EXAMEN || []).map(function (t) {
          return [t.ordre + '. ' + t.label, r['exam_' + t.code] || '—'];
        });
        U.drawer({
          title: r.patient + ' — ' + r.nip,
          subtitle: r.reference + '   ·   ' + etatDe(r.etat).label,
          body: el('div.space-y-4', null, [
            zone('Zone 1 — Accueil', [
              ['Arrivée', C.dateFR(r.dateArrivee) + (r.heureArrivee ? ' à ' + r.heureArrivee : '')],
              ['Motif de la venue', r.motifVenue || '—'],
              ['Service demandé', r.service || '—'],
              ['Couverture', r.assureur || 'Non assuré'],
              ['Constantes', [r.temperature != null ? r.temperature + ' °C' : null,
                r.tension ? 'TA ' + r.tension : null,
                r.pouls != null ? r.pouls + ' bpm' : null,
                r.spo2 != null ? r.spo2 + ' %' : null,
                r.imc != null ? 'IMC ' + r.imc : null].filter(Boolean).join('  ·  ') || '—'],
              ['Reçu par', r.recuPar || '—'],
            ]),
            zone('Zone 2 — Contrôle et historique', [
              ['Type de venue', r.typeVenue || '—'],
              ['Histoire de la maladie', r.histoire || '—'],
              ['Traitement en cours à l’arrivée', r.traitementEnCours || '—'],
            ]),
            zone('Antécédents — trois catégories', ant),
            zone('Examen physique — quatre temps', exam),
            zone('Décisions, analyses et traitements', [
              ['Diagnostic retenu', r.diagnostic || '—'],
              ['Pathologies codées', (r.pathologies || []).join(', ') || '—'],
              ['Analyses demandées', r.analysesDemandees || '—'],
              ['Traitement prescrit', r.traitement || '—'],
              ['Conduite à tenir', r.conduite || '—'],
            ]),
            zone('Actes chirurgicaux et bloc', (D.RUBRIQUES_CHIRURGICALES || []).map(function (rub) {
              var libelles = {
                actesChirurgicaux: 'Actes chirurgicaux', indicationOperatoire: 'Indication opératoire',
                blocPrevu: 'Programmation au bloc', risqueOperatoire: 'Risque opératoire',
              };
              return [libelles[rub] || rub, r[rub] || '—'];
            })),
            K.note('Le <strong>diagnostic</strong> est la phrase du médecin ; la <strong>pathologie</strong> '
              + 'est le code que la clinique compte. Les deux coexistent — n’avoir que le premier rendrait '
              + 'toute statistique de morbidité impossible.', { tone: 'info', icon: 'activity' }),
          ]),
        });
      }

      function imprimer(r) {
        function rubrique(titre, texte) {
          return el('div.mb-2', null, [
            el('p.text-\\[10px\\].font-semibold', { text: titre + ' :' }),
            el('p.whitespace-pre-line.text-\\[10px\\].leading-relaxed', { text: texte || '—' }),
          ]);
        }
        var corps = el('div');
        corps.appendChild(el('p.mb-2.text-\\[10px\\].font-bold.uppercase', { text: 'Zone 2 — Contrôle et historique' }));
        corps.appendChild(rubrique('Histoire de la maladie', r.histoire));
        corps.appendChild(rubrique('Traitement en cours à l’arrivée', r.traitementEnCours));

        corps.appendChild(el('p.mb-2.mt-3.text-\\[10px\\].font-bold.uppercase', { text: 'Antécédents' }));
        (D.CATEGORIES_ANTECEDENT || []).forEach(function (c) {
          corps.appendChild(rubrique(c.label, r['ant_' + c.code]));
        });

        corps.appendChild(el('p.mb-2.mt-3.text-\\[10px\\].font-bold.uppercase', { text: 'Examen physique' }));
        (D.TEMPS_EXAMEN || []).forEach(function (t) {
          corps.appendChild(rubrique(t.ordre + '. ' + t.label, r['exam_' + t.code]));
        });

        corps.appendChild(el('p.mb-2.mt-3.text-\\[10px\\].font-bold.uppercase',
          { text: 'Décisions, analyses et traitements' }));
        corps.appendChild(rubrique('Diagnostic retenu', r.diagnostic));
        corps.appendChild(rubrique('Analyses demandées', r.analysesDemandees));
        corps.appendChild(rubrique('Traitement prescrit', r.traitement));
        corps.appendChild(rubrique('Conduite à tenir', r.conduite));

        if ((D.RUBRIQUES_CHIRURGICALES || []).some(function (x) { return r[x]; })) {
          corps.appendChild(el('p.mb-2.mt-3.text-\\[10px\\].font-bold.uppercase',
            { text: 'Actes chirurgicaux et bloc' }));
          corps.appendChild(rubrique('Actes chirurgicaux', r.actesChirurgicaux));
          corps.appendChild(rubrique('Indication opératoire', r.indicationOperatoire));
          corps.appendChild(rubrique('Programmation au bloc', r.blocPrevu));
          corps.appendChild(rubrique('Risque opératoire', r.risqueOperatoire));
        }

        P.etat({
          titre: 'DOSSIER DE CONSULTATION',
          sousTitre: r.reference + ' — ' + r.patient,
          cartouche: [
            ['Patient', r.patient], ['NIP', r.nip],
            ['Âge', r.age != null ? r.age + ' ans' : '—'], ['Sexe', r.sexe || '—'],
            ['Arrivée', C.dateFR(r.dateArrivee) + (r.heureArrivee ? ' à ' + r.heureArrivee : '')],
            ['Service', r.service || '—'],
            ['Couverture', r.assureur || 'Non assuré'],
            ['Constantes à l’accueil', [r.temperature != null ? 'T° ' + r.temperature : null,
              r.tension ? 'TA ' + r.tension : null,
              r.pouls != null ? 'Pouls ' + r.pouls : null,
              r.imc != null ? 'IMC ' + r.imc : null].filter(Boolean).join('   ') || '—'],
            ['État du dossier', etatDe(r.etat).label],
          ],
          contenu: corps,
          signatures: [{ role: 'Le soignant', nom: r.soignant || '', mention: 'Signature et cachet' }],
        });
      }
  }

  global.SIGH.screen('m1-dossier-etendu', {
    title: 'Dossier de consultation étendu',
    description: 'Zone Accueil et zone Consultation : identification, constantes, antécédents, examen physique, décisions.',
    regle: 'Deux zones, deux responsabilités : l’<strong>accueil</strong> tient l’identification et les '
      + 'constantes, le <strong>soignant</strong> tient le clinique — et l’accueil n’y accède pas (RG-13). '
      + 'Les <strong>antécédents sont en trois catégories strictes</strong> : un antécédent chirurgical rangé '
      + 'dans les médicaux se perd au moment où le chirurgien en a besoin. Les <strong>actes chirurgicaux et '
      + 'le bloc</strong> ne s’écrivent que par le chirurgien — mais se lisent par tous.',
    render: function (root) {
      /* PAGE CONSERVÉE, CONTENU DÉMÉNAGÉ : retirer l'entrée du manifeste
         casserait les liens et surcharges qui la visent — l'écran renvoie. */
      root.appendChild(el('div.mx-auto.max-w-xl.space-y-4.py-10', null, [
        K.note('Le dossier de consultation à deux zones est <strong>fusionné dans le répertoire des '
          + 'patients</strong> (arbitrage du 31/08/2026, Bug 1 des Instructions) : un seul point '
          + 'd\u2019entrée, l\u2019onglet « Dossiers de consultation (2 zones) ». Le cloisonnement '
          + 'Zone 1 / Zone 2 et la journalisation y sont inchangés.', { tone: 'info', icon: 'merge' }),
        el('div.text-center', null,
          K.btn('Ouvrir le répertoire des patients', {
            variant: 'primary', icon: 'users',
            onclick: function () { global.SIGH.app.go('m1-patients', { onglet: 'dossiers-2-zones' }); },
          })),
      ]));
      return null;
    },
  });



  /* ==========================================================================
   * PHASE 9 \u2014 CERTIFICATS DES PATIENTS EXTERNES
   * --------------------------------------------------------------------------
   * Une VUE du registre des pi\u00e8ces certifiantes, filtr\u00e9e sur les patients
   * marqu\u00e9s EXTERNES (dossier ouvert \u00e0 l'accueil pour un adress\u00e9 de
   * l'ext\u00e9rieur). La d\u00e9livrance passe par l'\u00e9cran des certificats \u2014
   * une seconde saisie ici cr\u00e9erait deux num\u00e9rotations.
   * ======================================================================== */
  global.SIGH.screen('m1-certificats-externes', {
    title: 'Certificats \u2014 patients externes',
    description: 'Les pi\u00e8ces certifiantes d\u00e9livr\u00e9es aux patients venus de l\u2019ext\u00e9rieur : aptitude, visite, attestations.',
    regle: 'Une VUE du registre des pi\u00e8ces, filtr\u00e9e sur les patients <strong>externes</strong> \u2014 la '
      + 'pi\u00e8ce n\u2019existe qu\u2019une fois et sa num\u00e9rotation reste celle du registre annuel. Les '
      + 'certificats ne sont couverts par <strong>aucune assurance \u00e0 l\u2019exception de SOS</strong> '
      + '(mention manuscrite de la grille) : l\u2019externe les r\u00e8gle au tarif affich\u00e9. La d\u00e9livrance '
      + 'se fait \u00e0 l\u2019\u00e9cran \u00ab Certificats & attestations \u00bb.',
    render: function (root) {
      var host = el('div.space-y-4');
      root.appendChild(host);

      var externes = {};
      S.collection('patients').active().forEach(function (p) {
        if (p.externe) externes[p.code] = p;
      });
      var rows = S.collection('pieces').active().filter(function (r) {
        return externes[r.patientCode];
      });
      var an = new Date().getFullYear();

      host.appendChild(U.kpiGrid([
        { label: 'Pi\u00e8ces \u00e0 des externes', value: C.num(rows.length), icon: 'file-badge', tone: 'navy' },
        { label: 'Cette ann\u00e9e', value: C.num(rows.filter(function (r) { return r.annee === an; }).length),
          icon: 'calendar', tone: 'info' },
        { label: 'Patients externes au r\u00e9pertoire', value: C.num(Object.keys(externes).length),
          icon: 'user-plus', tone: 'neutral' },
        { label: 'Recettes de ces pi\u00e8ces', value: C.money(rows.reduce(function (n, r) { return n + (r.montant || 0); }, 0)),
          icon: 'receipt', tone: 'success' },
      ]));

      host.appendChild(K.note('Les six certificats tarif\u00e9s de la grille valent pour l\u2019externe comme pour '
        + 'le patient de la clinique \u2014 seul <strong>SOS</strong> les couvre. Pour d\u00e9livrer une pi\u00e8ce, '
        + 'passer par \u00ab Certificats & attestations \u00bb : le registre annuel y tient sa num\u00e9rotation.',
      { tone: 'info', icon: 'file-badge' }));

      host.appendChild(U.dataTable({
        title: 'Registre \u2014 pi\u00e8ces des externes', rows: rows,
        pageSize: 12, exportName: 'certificats-externes', searchable: true,
        defaultSort: 'dateDelivrance', defaultDir: 'desc',
        emptyMessage: 'Aucune pi\u00e8ce d\u00e9livr\u00e9e \u00e0 un patient externe. Le registre se remplit '
          + 'depuis \u00ab Certificats & attestations \u00bb, jamais ici.',
        columns: [
          { key: 'reference', label: 'R\u00e9f\u00e9rence', render: function (r) { return el('span.font-mono.text-xs', { text: r.reference }); } },
          { key: 'dateDelivrance', label: 'D\u00e9livr\u00e9e le', render: function (r) { return C.dateFR(r.dateDelivrance); } },
          {
            key: 'patientCode', label: 'Patient externe',
            render: function (r) {
              var p = externes[r.patientCode];
              return el('div.min-w-0', null, [
                el('p.truncate.text-sm.text-slate-800', { text: p ? p.nom + ' ' + p.prenom : r.patientCode }),
                el('p.font-mono.text-xs.text-slate-400', { text: r.patientCode }),
              ]);
            },
          },
          { key: 'libelle', label: 'Pi\u00e8ce', render: function (r) { return r.libelle || r.type || '\u2014'; } },
          { key: 'medecin', label: 'Signataire' },
          { key: 'montant', label: 'Montant', align: 'right', render: function (r) { return C.money(r.montant, false); } },
        ],
      }));
      U.icons(host);
      return null;
    },
  });

})(window);