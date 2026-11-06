/* =============================================================================
 * SIGH-CBG — Noyau : configuration de marque, formats, utilitaires DOM
 * -----------------------------------------------------------------------------
 * BRAND provient du « Brand Configuration Center » (draf1 §18) : aucune mention
 * légale n'est écrite en dur dans les pages, tous les états officiels lisent ici.
 * ========================================================================== */
(function (global) {
  'use strict';

  /* --- Identité de l'établissement (Instructions.txt, Direction 02/09/2026) --
   * AUCUNE donnée officielle ne s'invente : toute valeur non fournie reste
   * VIDE et les écrans le disent (« à compléter par la Direction »). ------- */
  var BRAND = {
    sigle: 'CBG',
    nom: 'CLINIQUE BAGUIDI « L’AS DE CŒUR »',
    /* Sous-titre officiel de l'en-tête, relevé tel quel sur Instructions.txt. */
    sousTitre: 'CENTRE DE MÉDECINE DU TRAVAIL – MÉDECINE GÉNÉRALE',
    slogan: 'Votre bien-être est notre raison d’être.',
    /* Forme juridique NON FOURNIE — à compléter par la Direction. */
    forme: '',
    formeMotif: 'À compléter par la Direction — la forme juridique exacte n’a pas été fournie.',
    adresse: 'Quartier Zongo II, Parakou',
    bp: '02 BP : 105 PARAKOU (Rép. du Bénin)',
    pays: 'République du Bénin',
    telephones: ['95 74 69 56', '95 95 99 14', '97 09 34 99'],
    /* Aucune ligne dédiée aux rendez-vous n'est documentée chez BAGUIDI. */
    telephoneRdv: null,
    email: 'cliniquebaguidi@yahoo.fr',
    ifu: '3201001996110',
    /* La date d'attribution figure sur l'en-tête officiel de la clinique. */
    ifuDate: '26 novembre 2010',
    /* RCCM FOURNI par la Direction le 07/09/2026. La date d'immatriculation
       fait partie de la mention : c'est elle qu'on lit sur les pièces. */
    rccm: 'RB/PKO/17 A 4240 du 19/03/2009',
    rccmDate: '19 mars 2009',
    rccmMotif: null,
    /* N° d'autorisation d'ouverture NON FOURNI — à compléter par la Direction. */
    autorisation: '',
    autorisationMotif: 'À compléter par la Direction — le numéro d’autorisation d’ouverture n’a pas été fourni.',
    autorisationExercice: null,
    autorisationExerciceMotif: 'Non fournie — à compléter par la Direction si elle doit figurer sur les états.',
    /* Référentiel de PRÉSENTATION (Instructions.txt « NOS SPÉCIALITÉS ») —
       il décrit l'offre de soins affichée, pas le périmètre du logiciel. */
    specialites: ['Médecine du travail', 'Santé publique', 'Gynécologie', 'Chirurgie',
      'Urologie', 'Rhumatologie', 'Ophtalmologie', 'Orthophonie', 'Endocrinologie',
      'Pédiatrie', 'Neurologie', 'Cardiologie', 'Kinésithérapie',
      'Imagerie (Radiologie-Échographie)'],
    devise: 'FCFA',
    /* Formules de pièces héritées du prototype d'origine : aucune pièce de
       caisse BAGUIDI n'a été fournie (M8 est d'ailleurs désactivé). */
    formuleArrete: 'Arrêtée la présente facture à la somme de',
    formulePolitesse: 'QUE DIEU VOUS GUÉRISSE ! AMINE !',
    /* Logo officiel vendoré depuis ../logo.png — aucune requête réseau. */
    logo: 'assets/img/logo.png',
    codeDevise: 'XOF',
  };

  /* --- Formats ------------------------------------------------------------ */
  var MOIS = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet',
    'août', 'septembre', 'octobre', 'novembre', 'décembre'];
  var JOURS = ['dimanche', 'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi'];

  /** Cadre un nombre sur `largeur` chiffres (2 par défaut) : pad(7, 4) → "0007". */
  function pad(n, largeur) { return String(n).padStart(largeur || 2, '0'); }

  /** Montant en francs CFA — pas de décimale, séparateur d'espace insécable. */
  function money(v, withCurrency) {
    var n = Number(v) || 0;
    var s = Math.round(Math.abs(n)).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
    if (n < 0) s = '-' + s;
    return withCurrency === false ? s : s + ' ' + BRAND.devise;
  }
  function num(v, dec) {
    var n = Number(v) || 0;
    return n.toFixed(dec == null ? 0 : dec).replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
  }
  function pct(v, dec) { return num(v, dec == null ? 1 : dec) + ' %'; }

  function toDate(d) { return d instanceof Date ? d : new Date(d); }
  function dateFR(d) { var x = toDate(d); return pad(x.getDate()) + '/' + pad(x.getMonth() + 1) + '/' + x.getFullYear(); }
  function dateLong(d) { var x = toDate(d); return x.getDate() + ' ' + MOIS[x.getMonth()] + ' ' + x.getFullYear(); }
  function dateJour(d) { var x = toDate(d); return JOURS[x.getDay()] + ' ' + x.getDate() + ' ' + MOIS[x.getMonth()] + ' ' + x.getFullYear(); }
  function heure(d) { var x = toDate(d); return pad(x.getHours()) + 'h' + pad(x.getMinutes()); }
  function dateHeure(d) { return dateFR(d) + ' à ' + heure(d); }

  /** Âge en années révolues, depuis une date de naissance. */
  function age(naissance) {
    if (!naissance) return null;
    return Math.max(0, Math.floor(daysBetween(naissance, new Date()) / 365.25));
  }
  function iso(d) { var x = toDate(d); return x.getFullYear() + '-' + pad(x.getMonth() + 1) + '-' + pad(x.getDate()); }
  function moisAnnee(d) { var x = toDate(d); return MOIS[x.getMonth()] + ' ' + x.getFullYear(); }

  /** Ancienneté / il y a X — pour timelines et journaux d'audit. */
  function ilYA(d) {
    var diff = (Date.now() - toDate(d).getTime()) / 1000;
    if (diff < 60) return 'à l’instant';
    if (diff < 3600) return 'il y a ' + Math.floor(diff / 60) + ' min';
    if (diff < 86400) return 'il y a ' + Math.floor(diff / 3600) + ' h';
    if (diff < 2592000) return 'il y a ' + Math.floor(diff / 86400) + ' j';
    return dateFR(d);
  }

  function addDays(d, n) { var x = new Date(toDate(d).getTime()); x.setDate(x.getDate() + n); return x; }
  function daysBetween(a, b) { return Math.round((toDate(b) - toDate(a)) / 86400000); }

  /* --------------------------------------------------------------------------
   * PÉRIODICITÉS — les six pas de découpage que la clinique demande
   * --------------------------------------------------------------------------
   * « Journalier ou hebdomadaire ou mensuel ou trimestriel ou semestriel ou
   * annuel », plus une plage libre. Elles vivaient dans le module de
   * facturation ; le gestionnaire de stock demande les mêmes sur ses points de
   * vente et de stock, qui sont des écrans de M6 — et une page ne charge que
   * le module de son écran. Leur place est donc ici.
   * ----------------------------------------------------------------------- */
  var PERIODES = [
    { id: 'jour', label: 'Journalière', jours: 1 },
    { id: 'semaine', label: 'Hebdomadaire', jours: 7 },
    { id: 'mois', label: 'Mensuelle', jours: 30 },
    { id: 'trimestre', label: 'Trimestrielle', jours: 91 },
    { id: 'semestre', label: 'Semestrielle', jours: 182 },
    { id: 'annee', label: 'Annuelle', jours: 365 },
  ];

  /** Bornes d'une période finissant à la date choisie. */
  function bornes(periodeId, fin) {
    var p = PERIODES.filter(function (x) { return x.id === periodeId; })[0] || PERIODES[0];
    var f = toDate(fin);
    return { debut: addDays(f, -(p.jours - 1)), fin: f, label: p.label, jours: p.jours };
  }

  /** Bornes d'une plage libre, remises dans l'ordre si l'agent les a inversées. */
  function bornesLibres(du, au) {
    var a = toDate(du), b = toDate(au);
    if (a.getTime() > b.getTime()) { var t = a; a = b; b = t; }
    return { debut: a, fin: b, label: 'Plage libre', jours: daysBetween(a, b) + 1 };
  }

  /** Une date tombe-t-elle dans les bornes ? Les deux extrémités sont incluses. */
  function dansBornes(date, b) {
    if (!date || !b) return false;
    var d = toDate(date).getTime();
    return d >= toDate(b.debut).getTime() && d <= toDate(b.fin).getTime();
  }

  /** Intitulé lisible d'une période — c'est lui qui coiffe les états imprimés. */
  function libellePeriode(b) {
    if (!b) return '';
    if (b.jours === 1) return 'Journée du ' + dateFR(b.debut);
    return 'Du ' + dateFR(b.debut) + ' au ' + dateFR(b.fin);
  }

  /* --------------------------------------------------------------------------
   * Montant en toutes lettres — mention obligatoire sur les factures
   * normalisées : « Arrêté la présente facture à la somme de … ».
   * Applique les accords français : « quatre-vingts » et « cents » prennent un
   * s lorsqu'ils terminent le nombre, « mille » reste invariable.
   * ----------------------------------------------------------------------- */
  var UNITES = ['zéro', 'un', 'deux', 'trois', 'quatre', 'cinq', 'six', 'sept', 'huit', 'neuf',
    'dix', 'onze', 'douze', 'treize', 'quatorze', 'quinze', 'seize'];
  var DIZAINES = ['', '', 'vingt', 'trente', 'quarante', 'cinquante', 'soixante', 'soixante', 'quatre-vingt', 'quatre-vingt'];

  function centaineEnLettres(n) {
    if (n < 17) return UNITES[n];
    if (n < 20) return 'dix-' + UNITES[n - 10];
    if (n < 100) {
      var d = Math.floor(n / 10), u = n % 10;
      var base = DIZAINES[d];
      if (d === 7 || d === 9) u += 10;
      if (u === 0) return d === 8 ? base + 's' : base;
      if (u === 1 && d !== 8 && d !== 7 && d !== 9) return base + ' et un';
      if (u === 11 && d === 7) return base + ' et onze';
      return base + '-' + (u < 17 ? UNITES[u] : 'dix-' + UNITES[u - 10]);
    }
    var c = Math.floor(n / 100), r = n % 100;
    var tete = c === 1 ? 'cent' : UNITES[c] + ' cent';
    if (r === 0) return c === 1 ? 'cent' : tete + 's';
    return tete + ' ' + centaineEnLettres(r);
  }

  function nombreEnLettres(n) {
    n = Math.round(Math.abs(Number(n) || 0));
    if (n === 0) return 'zéro';
    var tranches = [
      { valeur: 1e9, singulier: 'milliard', pluriel: 'milliards' },
      { valeur: 1e6, singulier: 'million', pluriel: 'millions' },
      { valeur: 1e3, singulier: 'mille', pluriel: 'mille' },
    ];
    var mots = [];
    tranches.forEach(function (t) {
      var q = Math.floor(n / t.valeur);
      if (!q) return;
      n -= q * t.valeur;
      if (t.valeur === 1e3 && q === 1) mots.push('mille');
      else mots.push(centaineEnLettres(q) + ' ' + (q > 1 ? t.pluriel : t.singulier));
    });
    if (n > 0) mots.push(centaineEnLettres(n));
    return mots.join(' ');
  }

  /** Montant en lettres suivi de la devise, prêt pour la mention légale. */
  function montantEnLettres(v) {
    return nombreEnLettres(v) + ' francs CFA';
  }

  /* --- Identifiants ------------------------------------------------------- */
  /**
   * RG-01 — code dossier <SIGLE>/[n° d'ordre]/[année], non modifiable.
   *
   * Le préfixe est LU SUR BRAND.sigle (CBG chez BAGUIDI) : la règle vit à UN
   * seul endroit — c'est le piège du code qui vivait à deux endroits, documenté
   * et payé sur le prototype d'origine. Le séparateur lève l'ambiguïté :
   * « CBG530/25 » se lit mal, « CBG/530/25 » ne laisse aucun doute.
   *
   * RG-01 interdisant de modifier un code attribué, le format ne vaut que pour
   * les dossiers À VENIR : cette fonction est appelée à la création, jamais à
   * l'affichage. Renuméroter l'existant romprait le lien avec l'archive papier.
   */
  function codePatient(ordre, annee) {
    var y = String(annee == null ? new Date().getFullYear() : annee).slice(-2);
    return BRAND.sigle + '/' + ordre + '/' + y;
  }
  var _seq = {};
  function nextRef(prefix, width) {
    _seq[prefix] = (_seq[prefix] || 0) + 1;
    return prefix + String(_seq[prefix]).padStart(width || 5, '0');
  }
  function uid() {
    return 'x' + Date.now().toString(36) + Math.random().toString(36).slice(2, 7);
  }

  /* --- Chaînes ------------------------------------------------------------ */
  function slug(s) {
    return String(s).normalize('NFD').replace(/[̀-ͯ]/g, '')
      .toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
  }
  function initials(s) {
    return String(s).trim().split(/\s+/).slice(0, 2).map(function (w) { return w[0] || ''; }).join('').toUpperCase();
  }
  function escapeHtml(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }
  /** Recherche insensible aux accents et à la casse. */
  function norm(s) {
    return String(s == null ? '' : s).normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
  }
  function matches(haystack, needle) { return norm(haystack).indexOf(norm(needle)) !== -1; }

  /* --- DOM ---------------------------------------------------------------- */
  function $(sel, root) { return (root || document).querySelector(sel); }
  function $$(sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); }

  /**
   * Crée un élément.
   *   el('div.card', {onclick: fn}, [enfant | 'texte'])
   *
   * Le sélecteur accepte `tag`, `#id` et des classes séparées par des points.
   * Les classes Tailwind contenant un point, un crochet ou une barre oblique
   * s'échappent par une contre-oblique — indispensable pour des utilitaires
   * comme `gap-2\.5`, `w-\[22rem\]` ou `bg-navy-950\/40` :
   *   el('div.flex.gap-2\\.5.w-\\[22rem\\]')  →  class="flex gap-2.5 w-[22rem]"
   */
  function splitSpec(spec) {
    var parts = [], buf = '', s = String(spec);
    for (var i = 0; i < s.length; i++) {
      var ch = s[i];
      if (ch === '\\' && i + 1 < s.length) { buf += s[i + 1]; i++; continue; }
      if (ch === '.' || ch === '#') { parts.push(buf); buf = ch; continue; }
      buf += ch;
    }
    parts.push(buf);
    return parts.filter(function (p) { return p !== ''; });
  }

  function el(spec, attrs, children) {
    var parts = splitSpec(spec);
    var node = document.createElement(parts[0] && parts[0][0] !== '.' && parts[0][0] !== '#' ? parts[0] : 'div');
    parts.forEach(function (p, i) {
      if (i === 0 && p[0] !== '.' && p[0] !== '#') return;
      if (p[0] === '.') node.classList.add(p.slice(1));
      else if (p[0] === '#') node.id = p.slice(1);
    });
    if (attrs) {
      Object.keys(attrs).forEach(function (k) {
        var v = attrs[k];
        if (v == null || v === false) return;
        if (k === 'class') node.className += (node.className ? ' ' : '') + v;
        else if (k === 'html') node.innerHTML = v;
        else if (k === 'text') node.textContent = v;
        else if (k === 'dataset') Object.keys(v).forEach(function (d) { node.dataset[d] = v[d]; });
        else if (k.slice(0, 2) === 'on' && typeof v === 'function') node.addEventListener(k.slice(2), v);
        else if (v === true) node.setAttribute(k, '');
        else node.setAttribute(k, v);
      });
    }
    append(node, children);
    return node;
  }
  function append(node, children) {
    if (children == null) return node;
    (Array.isArray(children) ? children : [children]).forEach(function (c) {
      if (c == null || c === false) return;
      node.appendChild(typeof c === 'string' || typeof c === 'number' ? document.createTextNode(String(c)) : c);
    });
    return node;
  }
  function clear(node) { while (node && node.firstChild) node.removeChild(node.firstChild); return node; }

  /** Icône Lucide — rendue en SVG au moment du montage par app.js. */
  function icon(name, cls) {
    return el('i', { 'data-lucide': name, class: cls || 'h-4 w-4' });
  }

  /* --- Divers ------------------------------------------------------------- */
  function debounce(fn, ms) {
    var t; return function () {
      var self = this, args = arguments;
      clearTimeout(t); t = setTimeout(function () { fn.apply(self, args); }, ms || 200);
    };
  }
  function groupBy(arr, key) {
    return arr.reduce(function (acc, item) {
      var k = typeof key === 'function' ? key(item) : item[key];
      (acc[k] = acc[k] || []).push(item); return acc;
    }, {});
  }
  function sum(arr, key) {
    return arr.reduce(function (a, x) { return a + (Number(typeof key === 'function' ? key(x) : x[key]) || 0); }, 0);
  }
  function sortBy(arr, key, dir) {
    var s = arr.slice(), d = dir === 'desc' ? -1 : 1;
    return s.sort(function (a, b) {
      var x = typeof key === 'function' ? key(a) : a[key];
      var y = typeof key === 'function' ? key(b) : b[key];
      if (x == null) return 1; if (y == null) return -1;
      if (typeof x === 'number' && typeof y === 'number') return (x - y) * d;
      return String(x).localeCompare(String(y), 'fr', { numeric: true }) * d;
    });
  }
  /** PRNG déterministe : les jeux de démonstration sont stables d'une session à l'autre. */
  function seeded(seed) {
    var s = seed || 42;
    return function () { s = (s * 9301 + 49297) % 233280; return s / 233280; };
  }
  function pick(rnd, arr) { return arr[Math.floor(rnd() * arr.length) % arr.length]; }
  function between(rnd, a, b) { return Math.floor(rnd() * (b - a + 1)) + a; }

  global.SIGH = global.SIGH || {};
  global.SIGH.core = {
    BRAND: BRAND, MOIS: MOIS, JOURS: JOURS,
    money: money, num: num, pct: pct, pad: pad,
    dateFR: dateFR, dateLong: dateLong, dateJour: dateJour, heure: heure, age: age,
    dateHeure: dateHeure, iso: iso, moisAnnee: moisAnnee, ilYA: ilYA,
    addDays: addDays, daysBetween: daysBetween, toDate: toDate,
    PERIODES: PERIODES, bornes: bornes, bornesLibres: bornesLibres,
    dansBornes: dansBornes, libellePeriode: libellePeriode,
    codePatient: codePatient, nextRef: nextRef, uid: uid,
    nombreEnLettres: nombreEnLettres, montantEnLettres: montantEnLettres,
    slug: slug, initials: initials, escapeHtml: escapeHtml, norm: norm, matches: matches,
    $: $, $$: $$, el: el, append: append, clear: clear, icon: icon,
    debounce: debounce, groupBy: groupBy, sum: sum, sortBy: sortBy,
    seeded: seeded, pick: pick, between: between,
  };
})(window);
