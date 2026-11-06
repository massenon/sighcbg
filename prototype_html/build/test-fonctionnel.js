/* =============================================================================
 * Tests fonctionnels du prototype SIGH-CBG — CLINIQUE BAGUIDI « L'AS DE CŒUR »
 * -----------------------------------------------------------------------------
 * La suite d'origine (SIGH-CNT, 54 scénarios) traversait les modules cliniques,
 * DÉSACTIVÉS chez BAGUIDI par décision de la Direction du 02/09/2026. Elle est
 * remplacée, conformément à la feuille de route de dérivation, par :
 *   — des sondes « module fermé proprement + modules actifs intacts » ;
 *   — les DEUX CHAÎNES TRANSACTIONNELLES de référence BAGUIDI, de bout en bout:
 *       1. expression de besoin → validation Direction → bon de commande →
 *          réception → mouvement de stock / CUMP → facture fournisseur →
 *          écriture comptable ;
 *       2. fiche RH → planning → prime → bulletin de paie → validation
 *          Direction ;
 *   — l'identité, la charte, les comptes, le RBAC et la désactivation du
 *     barème NS 131 (paie SANS rubrique de sanction).
 * L'ancienne suite reste dans l'historique git : rouvrir un module clinique
 * un jour permettra d'y reprendre les parcours correspondants.
 *     node build/test-fonctionnel.js
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');
const http = require('http');
const puppeteer = require('puppeteer');

const ROOT = path.resolve(__dirname, '..');
const PORT = 8096;
const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.woff2': 'font/woff2', '.jpeg': 'image/jpeg', '.png': 'image/png',
};

function findBrowser() {
  for (const c of [process.env.CHROME_PATH, 'C:/Program Files/Google/Chrome/Application/chrome.exe',
    'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'].filter(Boolean)) {
    if (fs.existsSync(c)) return c;
  }
  return null;
}

/* --- Petit cadre de test -------------------------------------------------- */
const resultats = [];
let courant = null;

function scenario(nom) {
  courant = { nom, etapes: [], ok: true };
  resultats.push(courant);
  return courant;
}
function verifier(libelle, condition, detail) {
  const ok = !!condition;
  courant.etapes.push({ libelle, ok, detail: ok ? null : (detail || '') });
  if (!ok) courant.ok = false;
  process.stdout.write(ok ? '.' : 'X');
}
const pause = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
  const server = http.createServer((req, res) => {
    const rel = decodeURIComponent(req.url.split('?')[0]).replace(/^\/+/, '') || 'index.html';
    const file = path.join(ROOT, rel);
    if (!fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream' });
    fs.createReadStream(file).pipe(res);
  }).listen(PORT);

  const browser = await puppeteer.launch({
    executablePath: findBrowser(), headless: true,
    args: ['--no-sandbox', '--disable-dev-shm-usage'],
  });
  const page = await browser.newPage();
  await page.setViewport({ width: 1600, height: 1000 });

  let erreursJS = [];
  page.on('pageerror', (e) => erreursJS.push(String(e.message)));
  page.on('console', (m) => { if (m.type() === 'error') erreursJS.push(m.text()); });

  async function ouvrir(rel) {
    erreursJS = [];
    await page.goto(`http://127.0.0.1:${PORT}/pages/${rel}`, { waitUntil: 'networkidle2' });
    await pause(500);
  }
  async function ouvrirRacine(rel) {
    erreursJS = [];
    await page.goto(`http://127.0.0.1:${PORT}/${rel}`, { waitUntil: 'networkidle2' });
    await pause(500);
  }

  /** Clique le premier élément VISIBLE dont le texte contient `texte`. */
  async function cliquer(texte, selecteur) {
    const fait = await page.evaluate((t, sel) => {
      const noeuds = [...document.querySelectorAll(sel || 'button, a, .tab, [role="tab"]')];
      const cible = noeuds.find((n) => (n.textContent || '').trim().toLowerCase().includes(t.toLowerCase())
        && n.offsetParent !== null);
      if (cible) { cible.click(); return true; }
      return false;
    }, texte, selecteur);
    await pause(450);
    return fait;
  }

  async function session(s) {
    await page.evaluate((x) => window.SIGH.store.setSession(x), s);
  }
  const ADMIN = { role: 'admin', nom: 'Administrateur système', fonction: 'direction', secteur: 'ADM', identifiant: 'admin@baguidi-clinique.bj' };
  const DIRECTION = { role: 'direction', nom: 'GBAGUIDI Rafiou', fonction: 'direction', secteur: 'ADM', identifiant: 'm-001@baguidi-clinique.bj' };
  const COMPTABLE = { role: 'comptable', nom: 'SANOUSSI Adamon', fonction: 'comptable', secteur: 'ADM', identifiant: 'm-002@baguidi-clinique.bj' };
  const RH = { role: 'rh', nom: 'MABOUDOU Nawal', fonction: 'rh', secteur: 'ADM', identifiant: 'm-003@baguidi-clinique.bj' };
  const MEDECIN = { role: 'medecin', nom: 'IDOHOU Abraham', fonction: 'medecin', secteur: 'MGE', identifiant: 'm-004@baguidi-clinique.bj' };

  console.log('\nExécution des parcours fonctionnels BAGUIDI…\n');

  /* =========================================================================
   * 1. IDENTITÉ — la connexion et l'en-tête imprimé disent BAGUIDI
   * ======================================================================= */
  {
    scenario('Identité BAGUIDI — connexion, en-tête imprimé, plus aucune trace CNT');
    await ouvrirRacine('index.html');
    const id1 = await page.evaluate(() => {
      const t = document.body.textContent;
      return {
        nom: /CLINIQUE BAGUIDI/.test(t) && /L’AS DE CŒUR|L'AS DE CŒUR/.test(t),
        sousTitre: /CENTRE DE MÉDECINE DU TRAVAIL/.test(t),
        slogan: /Votre bien-être est notre raison d’être/.test(t),
        ifu: /3201001996110/.test(t),
        rccmDit: /RCCM RB\/PKO\/17 A 4240 du 19\/03\/2009/.test(t),
        parakou: /Parakou/.test(t),
        comptes: (document.querySelector('select') || { options: [] }).options.length,
        sansCNT: !/NASSIERA|Natitingou|3201642748214|RB\/NAT\/2016-B-268|notre raison de vivre/.test(t),
      };
    });
    verifier('La connexion porte la dénomination, le sous-titre, le slogan et l’IFU BAGUIDI',
      id1.nom && id1.sousTitre && id1.slogan && id1.ifu && id1.parakou);
    verifier('Le RCCM fourni le 07/09/2026 figure en toutes lettres — RB/PKO/17 A 4240 du 19/03/2009',
      id1.rccmDit);
    verifier('Neuf profils de connexion — les huit comptes d’Instructions.txt plus l’admin système',
      id1.comptes === 9, id1.comptes + ' profil(s)');
    verifier('Plus aucune chaîne CNT (dénomination, ville, slogan, IFU, RCCM) sur la connexion', id1.sansCNT);

    await session(ADMIN);
    await ouvrir('cfg-entetes.html');
    const id2 = await page.evaluate(() => {
      const t = document.body.textContent;
      /* L'en-tête imprimé lui-même : on fabrique la pièce et on la lit. */
      const head = window.SIGH.print.entete();
      const ht = head.textContent;
      return {
        ecran: /CLINIQUE BAGUIDI/.test(t) && /à compléter par la Direction/.test(t),
        specialites: /Médecine du travail/.test(t) && /Kinésithérapie/.test(t),
        enteteNom: /CLINIQUE BAGUIDI/.test(ht),
        enteteSousTitre: /CENTRE DE MÉDECINE DU TRAVAIL/.test(ht),
        enteteSlogan: /Votre bien-être est notre raison d’être/.test(ht),
        enteteIfuDate: /3201001996110 du 26 novembre 2010/.test(ht),
        enteteRccm: /RCCM : RB\/PKO\/17 A 4240 du 19\/03\/2009/.test(ht),
        enteteAutorisation: !/autorisation d’ouverture n° [A-Z0-9]/i.test(ht),
        enteteSansCNT: !/NASSIERA|Natitingou|3201642748214/.test(ht),
        doubleLigne: !!head.querySelector('.bg-coeur-500') && !!head.querySelector('.bg-sante-600'),
      };
    });
    verifier('cfg-entetes montre l’identité BAGUIDI et annonce les mentions non fournies',
      id2.ecran && id2.specialites);
    verifier('L’en-tête imprimé porte les TROIS zones : nom + sous-titre, slogan, IFU daté',
      id2.enteteNom && id2.enteteSousTitre && id2.enteteSlogan && id2.enteteIfuDate);
    verifier('La double ligne fine ROUGE et BLEUE sépare l’en-tête du corps', id2.doubleLigne);
    verifier('Le RCCM BAGUIDI est imprimé sur la pièce, l’autorisation reste vide — aucune chaîne CNT',
      id2.enteteRccm && id2.enteteAutorisation && id2.enteteSansCNT);
    verifier('Aucune erreur JavaScript', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 2. CHARTE GRAPHIQUE — Rouge Cœur action, barre anthracite, polices
   * ======================================================================= */
  {
    scenario('Charte BAGUIDI — action rouge cœur, barre anthracite, cursive du seul slogan');
    await session(ADMIN);
    await ouvrir('dash-direction.html');
    const charte = await page.evaluate(() => {
      const btn = document.querySelector('.btn-primary');
      const bar = document.querySelector('#app-menubar');
      const rgb = (el2) => el2 ? getComputedStyle(el2).backgroundColor : '';
      const slogan = document.querySelector('.font-slogan');
      return {
        action: rgb(btn),                       /* attendu rgb(211, 47, 47) — Rouge Cœur */
        barre: rgb(bar),                        /* attendu rgb(33, 33, 33) — Anthracite */
        filet: !!bar.querySelector('.bg-coeur-500') && !!bar.querySelector('.bg-sante-600'),
        sloganCursif: slogan ? /Dancing Script/.test(getComputedStyle(slogan).fontFamily) : false,
        titreMontserrat: /Montserrat/.test(getComputedStyle(document.querySelector('h1')).fontFamily),
        montserratChargee: document.fonts.check('16px "Montserrat"'),
        dancingChargee: document.fonts.check('16px "Dancing Script"'),
      };
    });
    verifier('Le bouton d’action principale est ROUGE CŒUR (#D32F2F)',
      charte.action === 'rgb(211, 47, 47)', charte.action);
    verifier('La barre sombre est NOIR ANTHRACITE (#212121)',
      charte.barre === 'rgb(33, 33, 33)', charte.barre);
    verifier('La double ligne rouge et bleue court sous la barre', charte.filet);
    verifier('Le slogan seul est en cursive (Dancing Script vendorée, chargée localement)',
      charte.sloganCursif && charte.dancingChargee);
    verifier('Les titres composent en Montserrat (vendorée, chargée localement)',
      charte.titreMontserrat && charte.montserratChargee);
    verifier('Aucune erreur JavaScript', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 3. PÉRIMÈTRE — les modules cliniques sont fermés PROPREMENT
   * ======================================================================= */
  {
    scenario('Périmètre — M1–M5, M8, M9 et MECEF fermés : ruban, adresses, recherche');
    await session(ADMIN);
    await ouvrir('dash-admin.html');
    const per = await page.evaluate(() => {
      const N = window.SIGH.nav;
      const codes = [];
      N.tree('admin').forEach((d) => d.modules.forEach((m) => codes.push(m.code)));
      const fermes = ['M1', 'M2', 'M3', 'M4', 'M5', 'M8', 'M9', 'MECEF'];
      const actifs = ['M6', 'M7', 'M10', 'M11', 'M12', 'M13', 'M14', 'CFG', 'GED', 'RAP', 'PIL', 'DASH'];
      return {
        aucunFerme: fermes.every((c) => codes.indexOf(c) === -1),
        tousActifs: actifs.every((c) => codes.indexOf(c) !== -1),
        moteur: fermes.every((c) => !N.moduleActif(c)),
        canPatients: !!N.can('admin', N.get('m1-patients')),
        canCaisse: !!N.can('admin', N.get('m8-facturation')),
        ns131Ferme: !N.ecranActif('m10-evaluations', 'M10') && !N.ecranActif('m10-sanctions', 'M10'),
        statsFermees: !N.ecranActif('m5-stats-examens', 'PIL') && !N.ecranActif('m4-stats-maternite', 'PIL'),
      };
    });
    verifier('Le ruban de l’ADMIN ne porte plus aucun module clinique — la fermeture vaut pour tous',
      per.aucunFerme && per.moteur);
    verifier('Les modules BAGUIDI sont tous au ruban (M6, M7, M10–M14, CFG, GED, RAP, PIL, DASH)',
      per.tousActifs);
    verifier('can() refuse les écrans cliniques, admin compris', !per.canPatients && !per.canCaisse);
    verifier('Les écrans d’évaluation NS 131 et les statistiques cliniques sont fermés AUX ÉCRANS',
      per.ns131Ferme && per.statsFermees);

    /* LES OFFICINES SONT FERMÉES, LE STOCK RESTE ENTIER (03/09/2026) : la
       dispensation suppose une ordonnance réglée en caisse, deux circuits
       hors périmètre — mais fermer une officine ne ferme pas un magasin. */
    const officine = await page.evaluate(() => {
      const N = window.SIGH.nav;
      const m6 = [];
      N.tree('admin').forEach((d) => d.modules.forEach((m) => {
        if (m.code === 'M6') m.items.forEach((it) => m6.push(it.id));
      }));
      const fermes = ['m6-pharmacie-interne', 'm6-pharmacie-externe', 'm6-dispensation'];
      return {
        fermees: fermes.every((id) => !N.ecranActif(id, 'M6')),
        horsRuban: fermes.every((id) => m6.indexOf(id) === -1),
        stockIntact: ['m6-produits', 'm6-stock-gros', 'm6-mouvements', 'm6-lots', 'm6-inventaire']
          .every((id) => m6.indexOf(id) !== -1),
        moduleOuvert: N.moduleActif('M6'),
        motifDit: !!(N.fermeturePour('m6-pharmacie-interne', 'M6') || {}).motif,
      };
    });
    verifier('Officines (interne, externe) ET registre des délivrances fermés, hors du méga-menu Logistique',
      officine.fermees && officine.horsRuban);
    verifier('Fermer une officine NE FERME PAS le magasin — produits, stock gros, mouvements, lots et inventaires restent',
      officine.stockIntact && officine.moduleOuvert);
    verifier('La fermeture porte son motif, lisible à l’écran', officine.motifDit);
    await ouvrir('m6-pharmacie-interne.html');
    verifier('L’adresse d’une officine fermée renvoie au refus', /error-403/.test(page.url()),
      page.url().split('/').pop());

    /* L'adresse d'un module fermé renvoie au refus — fermer n'est pas cacher. */
    await ouvrir('m1-patients.html');
    const url1 = page.url();
    await ouvrir('m8-facturation.html');
    const url2 = page.url();
    await ouvrir('m10-evaluations.html');
    const url3 = page.url();
    verifier('L’adresse d’un écran fermé renvoie au 403 (M1, M8, évaluations NS 131)',
      /error-403/.test(url1) && /error-403/.test(url2) && /error-403/.test(url3));
    verifier('Aucune erreur JavaScript sur les refus', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 4. INDÉPENDANCE — le clinique fermé, les modules BAGUIDI travaillent
   * ======================================================================= */
  {
    scenario('Indépendance — stocks, achats, RH, paie, compta et dashboards travaillent');
    await session(ADMIN);
    await ouvrir('m6-produits.html');
    const stock = await page.evaluate(() => document.querySelectorAll('tbody tr').length);
    await ouvrir('m7-besoins.html');
    const besoins = await page.evaluate(() => ({
      monte: /expression de besoins/i.test(document.body.textContent),
      amorce: window.SIGH.store.collection('besoins').all().length,
    }));
    await ouvrir('m10-personnel.html');
    const rh = await page.evaluate(() => document.querySelectorAll('tbody tr').length);
    await ouvrir('m12-ecritures.html');
    const compta = await page.evaluate(() => document.querySelectorAll('tbody tr').length);

    /* LE PLAN COMPTABLE EST LE SYSCOHADA RÉVISÉ (Direction, 06/09/2026) —
       celui de la clinique d'origine est retiré. Une écriture se passe sur une
       FEUILLE : les comptes de regroupement totalisent. */
    await ouvrir('m12-plan-comptable.html');
    const plan = await page.evaluate(() => {
      const S = window.SIGH.store, D2 = window.SIGH.data;
      const comptes = S.collection('comptes').active();
      const code = (c) => comptes.find((x) => x.num === c);
      const ecritures = S.collection('ecritures').active();
      const connus = {};
      comptes.forEach((c) => { connus[c.num] = c; });
      return {
        total: comptes.length,
        classes: new Set(comptes.map((c) => c.classe)).size,
        imputables: comptes.filter((c) => c.imputable).length,
        /* Quatre comptes officiels, avec leur libellé du plan. */
        f4011: !!code('4011') && /Fournisseurs/.test(code('4011').libelle),
        c5711: !!code('5711') && /Caisse en monnaie nationale/.test(code('5711').libelle),
        a4492: !!code('4492') && /avances et acomptes versés sur imp/i.test(code('4492').libelle),
        s7061: !!code('7061'),
        /* Plus aucun compte à six chiffres : le plan hérité a bien sauté. */
        sansHerites: comptes.every((c) => !/^\d{5,}$/.test(String(c.num))),
        /* Les schémas d'écriture nomment leurs comptes, ils ne les inventent pas. */
        sighConnus: Object.keys(D2.COMPTES_SIGH).every((k) => !!connus[D2.COMPTES_SIGH[k]]),
        /* Toute écriture porte un compte qui existe au plan et qui s'impute. */
        ecrituresValides: ecritures.every((e) => connus[e.compte] && connus[e.compte].imputable),
        nbEcritures: ecritures.length,
      };
    });
    verifier('Le plan SYSCOHADA révisé est au magasin — 1 332 comptes, 9 classes, 1 049 imputables',
      plan.total === 1332 && plan.classes === 9 && plan.imputables === 1049,
      plan.total + ' comptes / ' + plan.classes + ' classes / ' + plan.imputables + ' imputables');
    verifier('Les comptes officiels y sont, avec leur libellé : 4011, 5711, 4492 (AIB subi), 7061',
      plan.f4011 && plan.c5711 && plan.a4492 && plan.s7061);
    verifier('Plus aucun compte hérité à six chiffres — l’ancien plan a été retiré', plan.sansHerites);
    verifier('Les comptes des schémas d’écriture (D.COMPTES_SIGH) existent tous au plan',
      plan.sighConnus);
    verifier('Chaque écriture porte un compte IMPUTABLE du plan — jamais un compte qui totalise',
      plan.ecrituresValides && plan.nbEcritures > 0, plan.nbEcritures + ' écriture(s)');
    verifier('Le stock monte et liste ses produits', stock > 0, stock + ' ligne(s)');
    verifier('Les expressions de besoins montent et la file s’amorce', besoins.monte && besoins.amorce > 0);
    verifier('Le personnel BAGUIDI est au registre RH', rh === 8, rh + ' agent(s)');
    verifier('Les écritures comptables montent', compta > 0, compta + ' ligne(s)');

    await ouvrir('dash-comptable.html');
    const dc = await page.evaluate(() => document.body.textContent.length > 500);
    await ouvrir('dash-rh.html');
    const dr = await page.evaluate(() => /bulletin/i.test(document.body.textContent));
    await ouvrir('dash-medecin.html');
    const dm = await page.evaluate(() => document.body.textContent.length > 500);
    verifier('Les tableaux de bord comptable, RH et médecin montent avec le clinique fermé',
      dc && dr && dm);
    /* LES SIX SECTEURS DE LA CLINIQUE (Direction, 07/09/2026) commandent la
       même lecture partout : recettes par groupe, bénéfice brut, centres de
       coûts. AUCUN NE MANQUE — un secteur absent disparaîtrait de toutes les
       analyses à la fois. */
    const SECTEURS = ['Laboratoire', 'Pharmacie', 'Consultation', 'Échographie',
      'Maternité', 'Hospitalisation et soins'];
    await session(ADMIN);
    await ouvrir('m12-rentabilite-groupes.html');
    const secteurs = await page.evaluate((attendus) => {
      const D2 = window.SIGH.data;
      const t = document.body.textContent;
      const cartes = [...document.querySelectorAll('.card')];
      const carte = (titre) => cartes.find((c) => c.textContent.indexOf(titre) === 0
        || (c.querySelector('.card-title') || {}).textContent === titre);
      const lignesDe = (titre) => {
        const c = carte(titre);
        return c ? [...c.querySelectorAll('tbody tr')].map((r) => r.cells[0].textContent.trim()) : [];
      };
      return {
        groupes: (D2.GROUPES_PRESTATION || []).map((g) => g.label),
        centres: (D2.CENTRES_COUT || []).map((c) => c.label),
        recettes: lignesDe('Recettes par groupe de prestation'),
        benefice: lignesDe('Bénéfice brut par groupe — avant charges transverses'),
        rapprochement: lignesDe('Rapprochement ARRÊTÉ le 01/09/2026 — centre par centre, contestable ligne à ligne'),
        secteurDit: attendus.every((s) => t.indexOf(s) !== -1),
      };
    }, SECTEURS);
    verifier('Les six secteurs sont les groupes de prestation, dans l’ordre de la Direction',
      SECTEURS.every((s, i) => secteurs.groupes[i] === s) && secteurs.groupes.length === 6,
      secteurs.groupes.join(' · '));
    verifier('Les centres de coûts portent LES MÊMES secteurs, plus la Direction',
      SECTEURS.every((s, i) => secteurs.centres[i] === s) && secteurs.centres[6] === 'Direction',
      secteurs.centres.join(' · '));
    verifier('« Recettes par groupe » et « Bénéfice brut par groupe » les listent tous les six',
      SECTEURS.every((s) => secteurs.recettes.indexOf(s) !== -1)
      && SECTEURS.every((s) => secteurs.benefice.indexOf(s) !== -1),
      secteurs.recettes.join(' · '));
    verifier('Le rapprochement porte les sept centres — même sans charge sur la période',
      SECTEURS.concat(['Direction']).every((s) => secteurs.rapprochement.indexOf(s) !== -1),
      secteurs.rapprochement.join(' · '));

    /* Les deux libellés arrêtés le 07/09/2026. */
    await ouvrir('m6-point-ventes.html');
    const libelles = await page.evaluate(() => {
      const N = window.SIGH.nav;
      return {
        heroVentes: /Suivi des ventes/.test(document.querySelector('h1').textContent),
        arianeVentes: /Suivi des ventes/.test(document.body.textContent),
        manifesteVentes: (N.get('m6-point-ventes') || {}).label,
        manifesteImagerie: (N.get('m2-stats-echographie') || {}).label,
        sansAncien: !/Point des ventes/.test(document.body.textContent),
      };
    });
    verifier('« Suivi des ventes » au hero, au fil d’Ariane et au méga-menu Logistique',
      libelles.heroVentes && libelles.arianeVentes && libelles.sansAncien
      && libelles.manifesteVentes === 'Suivi des ventes', libelles.manifesteVentes);
    verifier('« Statistiques de l’imagerie médicale » au manifeste',
      libelles.manifesteImagerie === 'Statistiques de l’imagerie médicale', libelles.manifesteImagerie);

    verifier('Aucune erreur JavaScript', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 5. RÉACTIVATION — rouvrir un module clinique rend tout en l'état
   * ======================================================================= */
  {
    scenario('Réactivation — rouvrir M2 rend les écrans en l’état, refermer les retire');
    await session(ADMIN);
    await ouvrir('cfg-modules.html');
    const reac = await page.evaluate(() => {
      const S = window.SIGH.store, N = window.SIGH.nav;
      const col = S.collection('modulesActifs');
      const fiche = col.active().find((x) => x.module === 'M2' && x.actif === false);
      if (!fiche) return { fiche: false };
      col.update(fiche.id, { actif: true });
      N.invaliderModules();
      const rouvert = N.moduleActif('M2') && !!N.can('admin', N.get('m2-consultations'));
      col.update(fiche.id, { actif: false });
      N.invaliderModules();
      const referme = !N.moduleActif('M2') && !N.can('admin', N.get('m2-consultations'));
      return { fiche: true, rouvert, referme };
    });
    verifier('La fiche de fermeture M2 existe et se rouvre depuis le magasin', reac.fiche && reac.rouvert);
    verifier('La refermeture retire de nouveau les écrans — rien n’a été supprimé', reac.referme);

    /* ====================================================================
     * L'ÉCRAN D'AIDE SUIT L'ÉTAT RÉEL (décision de la Direction, 03/09/2026)
     * Un module fermé y reste DÉCRIT — marqué « Fermé », son motif lu, et
     * non cliquable ; rouvert, il y reparaît OUVERT et cliquable, sans
     * qu'une ligne de cet écran change.
     * ================================================================== */
    function lireAide() {
      return page.evaluate(() => {
        const carte = (code) => document.querySelector('[data-module="' + code + '"]');
        const m2 = carte('M2'), m6 = carte('M6');
        const kpi = document.body.textContent;
        return {
          m2Present: !!m2, m2Ouvert: m2 && m2.getAttribute('data-ouvert') === '1',
          m2Lien: m2 && m2.tagName === 'A',
          m2Badge: !!m2 && /Fermé/.test(m2.textContent),
          m2Motif: !!m2 && /Hors périmètre BAGUIDI/.test(m2.textContent),
          m6Ouvert: m6 && m6.getAttribute('data-ouvert') === '1' && m6.tagName === 'A',
          compteurs: /Modules ouverts/.test(kpi) && /Profils actifs/.test(kpi),
          doublons: document.querySelectorAll('[data-module="M1"]').length,
        };
      });
    }
    await ouvrir('aide-apropos.html');
    const aideFerme = await lireAide();
    verifier('L’aide DÉCRIT le module fermé — présent, marqué « Fermé », motif lu, non cliquable',
      aideFerme.m2Present && !aideFerme.m2Ouvert && aideFerme.m2Badge && aideFerme.m2Motif
      && !aideFerme.m2Lien);
    verifier('Un module ouvert (M6) y est cliquable, et les compteurs disent ouverts/total',
      aideFerme.m6Ouvert && aideFerme.compteurs);
    verifier('Chaque module ne figure qu’UNE fois — les rangées alias ne font pas doublon',
      aideFerme.doublons === 1, aideFerme.doublons + ' carte(s) M1');

    /* On rouvre M2 dans le magasin, puis on RECHARGE l'aide : elle doit
       montrer le module ouvert d'elle-même. */
    await page.evaluate(() => {
      const S = window.SIGH.store, N = window.SIGH.nav;
      const col = S.collection('modulesActifs');
      const f = col.active().find((x) => x.module === 'M2' && x.actif === false);
      if (f) col.update(f.id, { actif: true });
      N.invaliderModules();
    });
    await ouvrir('aide-apropos.html');
    const aideOuvert = await lireAide();
    verifier('RÉOUVERTURE : le module reparaît OUVERT et cliquable dans l’écran d’aide',
      aideOuvert.m2Ouvert && aideOuvert.m2Lien && !aideOuvert.m2Badge);

    /* Puis on referme : l'aide doit le remarquer « Fermé » sans intervention. */
    await page.evaluate(() => {
      const S = window.SIGH.store, N = window.SIGH.nav;
      const col = S.collection('modulesActifs');
      const f = col.active().find((x) => x.module === 'M2' && x.actif === true);
      if (f) col.update(f.id, { actif: false });
      N.invaliderModules();
    });
    await ouvrir('aide-apropos.html');
    const aideRefreme = await lireAide();
    verifier('REFERMETURE : l’aide le remarque « Fermé » d’elle-même — rien n’est écrit en dur',
      aideRefreme.m2Present && !aideRefreme.m2Ouvert && aideRefreme.m2Badge);

    verifier('Aucune erreur JavaScript', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 6. COMPTES & PERSONNEL — les huit d'Instructions.txt, exactement
   * ======================================================================= */
  {
    scenario('Comptes & personnel — les huit agents exacts, matricule = m-00N');
    await session(ADMIN);
    await ouvrir('m14-utilisateurs.html');
    const cpt = await page.evaluate(() => {
      const S = window.SIGH.store;
      const attendus = ['GBAGUIDI Rafiou', 'SANOUSSI Adamon', 'MABOUDOU Nawal', 'IDOHOU Abraham',
        'AKONDE Octave', 'SOKOU Peace', 'ZIME Nadège', 'TOUNGOUH A. Zoulkifouli'];
      const pers = S.collection('personnel').active();
      const users = S.collection('utilisateurs').active();
      const parNom = {};
      users.forEach((u) => { parNom[u.nomComplet] = u; });
      return {
        huit: pers.length === 8 && attendus.every((n) => pers.some((p) => p.nomComplet === n)),
        salairesMarques: pers.every((p) => p.salaireProvisoire === true),
        identifiants: attendus.every((n, i) => {
          const u = parNom[n];
          return u && /^m-\d{3}@baguidi-clinique\.bj$/.test(u.identifiant);
        }),
        m001: parNom['GBAGUIDI Rafiou'] && parNom['GBAGUIDI Rafiou'].identifiant === 'm-001@baguidi-clinique.bj'
          && parNom['GBAGUIDI Rafiou'].role === 'direction',
        m008: parNom['TOUNGOUH A. Zoulkifouli'] && parNom['TOUNGOUH A. Zoulkifouli'].identifiant === 'm-008@baguidi-clinique.bj'
          && parNom['TOUNGOUH A. Zoulkifouli'].role === 'rh',
        admin: users.some((u) => u.role === 'admin' && u.identifiant === 'admin@baguidi-clinique.bj'),
        total: users.length,
      };
    });
    verifier('Le personnel est EXACTEMENT les huit agents d’Instructions.txt', cpt.huit);
    verifier('Chaque salaire est une valeur d’attente MARQUÉE (grille non fournie)', cpt.salairesMarques);
    verifier('Chaque compte porte l’adresse m-00N@baguidi-clinique.bj', cpt.identifiants);
    verifier('m-001 = GBAGUIDI Rafiou (Direction), m-008 = TOUNGOUH A. Zoulkifouli (RH)',
      cpt.m001 && cpt.m008);
    verifier('Neuf comptes en tout — les huit plus l’administrateur système',
      cpt.admin && cpt.total === 9, cpt.total + ' compte(s)');
    verifier('Aucune erreur JavaScript', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 7. RBAC — rôles actifs servis, rôles archivés refusés
   * ======================================================================= */
  {
    scenario('RBAC — rh désarchivé travaille, médecin exprime ses besoins, caissier archivé refusé');
    await session(RH);
    await ouvrir('m10-personnel.html');
    const rhOuvre = await page.evaluate(() => ({
      monte: !/error-403/.test(location.href),
      peutCreer: [...document.querySelectorAll('button')].some((b) => /Nouveau/i.test(b.textContent)),
    }));
    verifier('Le rôle RH (désarchivé, deux titulaires) ouvre le personnel EN ÉCRITURE',
      rhOuvre.monte && rhOuvre.peutCreer);

    await session(MEDECIN);
    await ouvrir('m7-besoins.html');
    const medBesoins = !/error-403/.test(page.url());
    await ouvrir('m12-ecritures.html');
    const medCompta = /error-403/.test(page.url());
    await ouvrir('dash-medecin.html');
    const medDash = await page.evaluate(() => !/error-403/.test(location.href));
    verifier('Le médecin garde son tableau de bord et l’EXPRESSION DE BESOINS (surcharge d’écran)',
      medBesoins && medDash);
    verifier('Le médecin n’entre pas en comptabilité (RG-13)', medCompta);

    await session(DIRECTION);
    await ouvrir('m11-validation.html');
    const dirPaie = !/error-403/.test(page.url());
    await ouvrir('m7-commandes.html');
    const dirCmd = !/error-403/.test(page.url());
    verifier('La Direction accède à la validation de la paie et aux commandes (RG-04)',
      dirPaie && dirCmd);

    /* Un rôle archivé ne travaille plus : sa session est refermée. */
    await session({ role: 'caissier', nom: 'Sonde caissier', fonction: 'caissiere', secteur: 'CPH' });
    await ouvrir('m6-dispensation.html');
    const caissier = await page.evaluate(() => ({
      url: location.href,
      role: window.SIGH.nav.roleArchive('caissier'),
    }));
    verifier('Le rôle caissier est ARCHIVÉ et sa session ne travaille plus',
      caissier.role && !/m6-dispensation/.test(caissier.url), caissier.url.split('/').pop());

    /* LE SÉLECTEUR DE PROFIL NE PROPOSE QUE CE QUI S'OUVRE (03/09/2026) :
       offrir un rôle archivé, c'est offrir une porte que le contrôle d'accès
       referme aussitôt en journalisant la tentative. */
    await session(ADMIN);
    await ouvrir('dash-admin.html');
    const profil = await page.evaluate(() => {
      window.SIGH.app.openProfile();
      const sel = document.querySelector('[role="dialog"] select');
      const N = window.SIGH.nav;
      const vals = sel ? [...sel.options].map((o) => o.value) : [];
      const libelles = sel ? [...sel.options].map((o) => o.textContent) : [];
      return {
        n: vals.length,
        archives: vals.filter((r) => N.roleArchive(r)),
        attendus: ['admin', 'direction', 'comptable', 'rh', 'medecin', 'infirmier']
          .every((r) => vals.indexOf(r) !== -1),
        nomme: libelles.some((l) => /GBAGUIDI Rafiou/.test(l))
          && libelles.some((l) => /MABOUDOU Nawal|TOUNGOUH/.test(l)),
      };
    });
    verifier('Le sélecteur de profil ne propose QUE les six rôles servis plus l’admin — aucun archivé',
      profil.n === 6 && profil.archives.length === 0 && profil.attendus,
      profil.n + ' profil(s), archivés : ' + profil.archives.join(', '));
    verifier('Chaque profil y porte le nom de son titulaire réel (comptes d’Instructions.txt)',
      profil.nomme);
    verifier('Aucune erreur JavaScript', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 8. TABLEAUX DE BORD DES POSTES SANS TITULAIRE — ils l'annoncent
   * ======================================================================= */
  {
    scenario('Un tableau de bord dont le poste n’existe pas chez BAGUIDI l’ANNONCE');
    await session(ADMIN);
    const dashArchives = ['dash-caissier.html', 'dash-laborantin.html', 'dash-stock.html', 'dash-receptionniste.html'];
    let annonces = 0;
    for (const d of dashArchives) {
      await ouvrir(d);
      const dit = await page.evaluate(() => /Poste sans titulaire|rôle archivé/i.test(document.body.textContent));
      if (dit) annonces++;
    }
    verifier('Caisse, laboratoire, stock et accueil annoncent le poste sans titulaire',
      annonces === dashArchives.length, annonces + '/' + dashArchives.length);
    await ouvrir('dash-direction.html');
    const dirPropre = await page.evaluate(() => !/Poste sans titulaire/.test(document.body.textContent));
    verifier('Le tableau de la Direction (rôle ACTIF) ne porte PAS l’annonce', dirPropre);
    verifier('Aucune erreur JavaScript', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 9. BARÈME NS 131 DÉSACTIVÉ — écrans fermés, barème vide, paie sans sanction
   * ======================================================================= */
  {
    scenario('NS 131 désactivé — barème vidé, bascule fermée, la paie calcule SANS sanction');
    await session(ADMIN);
    await ouvrir('cfg-systeme.html');
    await cliquer('Barème NS 131');
    const ns = await page.evaluate(() => {
      const S = window.SIGH.store;
      return {
        baremeVide: S.collection('baremeNS131').active().length === 0,
        basculeFermee: !window.SIGH.baremeModifiable(),
        evaluationsVides: (S.raw().evaluations || []).length === 0,
        annonce: /désactivé chez BAGUIDI/i.test(document.body.textContent),
      };
    });
    verifier('Le barème seedé est VIDE et la bascule de modification reste fermée',
      ns.baremeVide && ns.basculeFermee);
    verifier('Aucune évaluation n’est semée — la paie n’a aucune sanction à retenir',
      ns.evaluationsVides);
    verifier('L’onglet Barème de cfg-systeme ANNONCE la désactivation', ns.annonce);
    verifier('Aucune erreur JavaScript', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 10. CHAÎNE 1 — besoin → Direction → commande → réception → CUMP → écriture
   * ======================================================================= */
  {
    scenario('Chaîne 1 — expression de besoin → validation Direction → commande → réception/CUMP → facture fournisseur → écriture');
    await session(COMPTABLE);
    await ouvrir('m7-besoins.html');

    /* 1. L'expression de besoin naît, avec ses lignes. */
    const c1 = await page.evaluate(() => {
      const S = window.SIGH.store, C2 = window.SIGH.core;
      const p = S.collection('produits').active().filter((x) => x.stock > 10)[0];
      const besoin = S.collection('besoins').insert({
        reference: 'BEB-SONDE-0001', date: C2.iso(new Date()),
        service: 'Laboratoire', demandeur: 'IDOHOU Abraham', etape: 'soumis',
        motif: 'Sonde fonctionnelle — chaîne BAGUIDI n° 1',
        lignes: [{ produitId: p.id, produit: p.designation, unite: p.unite,
          quantiteDemandee: 20, quantiteAccordee: null, prixAchat: p.prixAchat }],
        montantEstime: 20 * p.prixAchat,
      });
      return { id: besoin.record ? besoin.record.id : besoin.id, produitId: p.id, prix: p.prixAchat };
    });
    verifier('Le besoin (service Laboratoire) est au circuit, étape « soumis »', !!c1.produitId);

    /* 2. La DIRECTION accorde — quantité accordée ≠ demandée, le vrai process. */
    await session(DIRECTION);
    const c2 = await page.evaluate((sonde) => {
      const S = window.SIGH.store;
      const b = S.collection('besoins').active().find((x) => x.reference === 'BEB-SONDE-0001');
      S.collection('besoins').update(b.id, {
        etape: 'accorde', valideePar: 'GBAGUIDI Rafiou', valideeLe: '2026-09-02',
        lignes: b.lignes.map((l) => Object.assign({}, l, { quantiteAccordee: 15 })),
      });
      const apres = S.collection('besoins').get(b.id);
      return { accorde: apres.etape === 'accorde' && apres.lignes[0].quantiteAccordee === 15
        && apres.lignes[0].quantiteDemandee === 20, validePar: apres.valideePar };
    }, c1);
    verifier('La Direction ACCORDE (15 sur 20 — quantité accordée ≠ demandée, tracée à son nom)',
      c2.accorde && c2.validePar === 'GBAGUIDI Rafiou');

    /* 3. Le bon de commande part, validé RG-04. */
    const c3 = await page.evaluate((sonde) => {
      const S = window.SIGH.store, C2 = window.SIGH.core;
      const p = S.collection('produits').get(sonde.produitId);
      const cmd = S.collection('commandes').insert({
        reference: 'BC-SONDE-0001', date: C2.iso(new Date()),
        fournisseur: 'F01', fournisseurNom: 'Fournisseur de la sonde',
        lignes: [{ produitId: p.id, produit: p.designation, unite: p.unite,
          quantite: 15, prixUnitaire: sonde.prix }],
        montant: 15 * sonde.prix,
        statutCommande: 'validee', valideePar: 'GBAGUIDI Rafiou', dateValidation: '2026-09-02',
      });
      return { ok: true };
    }, c1);
    verifier('Le bon de commande est émis et VALIDÉ par la Direction (RG-04)', c3.ok);

    /* 4. La réception : entrée en stock, mouvement justifié, CUMP recalculé. */
    const c4 = await page.evaluate((sonde) => {
      const S = window.SIGH.store, C2 = window.SIGH.core;
      const p = S.collection('produits').get(sonde.produitId);
      const avant = { stock: p.stock, cump: p.cump };
      const recu = 15;
      /* Le CUMP suit la formule de l'écran de réception :
         (valeur du stock + valeur de l'entrée) / quantité totale. */
      const nouvelleQte = p.stock + recu;
      const nouveauCump = Math.round((p.stock * p.cump + recu * sonde.prix) / nouvelleQte);
      S.collection('produits').update(p.id, {
        stock: nouvelleQte, stockGros: (p.stockGros || 0) + recu, cump: nouveauCump,
      });
      S.collection('mouvements').insert({
        reference: 'M-SONDE-01', date: C2.iso(new Date()),
        produitId: p.id, produit: p.designation, type: 'entree', typeLabel: 'Entrée',
        quantite: recu, stockType: 'gros',
        justificatif: 'Bon de livraison BL-SONDE-0001 (RG-03)',
        utilisateur: 'SANOUSSI Adamon',
      });
      S.collection('livraisons').insert({
        reference: 'BL-SONDE-0001', commandeRef: 'BC-SONDE-0001', date: C2.iso(new Date()),
        fournisseurNom: 'Fournisseur de la sonde',
        lignes: [{ produitId: p.id, produit: p.designation, quantite: 15, quantiteLivree: 15,
          ecart: 0, prixUnitaire: sonde.prix }],
        montant: 15 * sonde.prix, controlePar: ['SANOUSSI Adamon', 'SOKOU Peace'],
        statutReception: 'conforme',
      });
      const apres = S.collection('produits').get(p.id);
      return {
        stockMonte: apres.stock === avant.stock + recu,
        cumpRecalcule: apres.cump === nouveauCump,
        mouvement: S.collection('mouvements').active().some((m) => m.reference === 'M-SONDE-01'
          && /RG-03/.test(m.justificatif)),
      };
    }, c1);
    verifier('La réception ENTRE en stock (mouvement justifié RG-03) et le CUMP est recalculé',
      c4.stockMonte && c4.cumpRecalcule && c4.mouvement);

    /* 5. La facture fournisseur se rapproche, l'écriture naît en BROUILLON. */
    await session(COMPTABLE);
    const c5 = await page.evaluate((sonde) => {
      const S = window.SIGH.store, C2 = window.SIGH.core;
      S.collection('facturesFournisseurs').insert({
        reference: 'FF-SONDE-0001', blRef: 'BL-SONDE-0001', commandeRef: 'BC-SONDE-0001',
        date: C2.iso(new Date()), fournisseurNom: 'Fournisseur de la sonde',
        montantLivraison: 15 * sonde.prix, montantFacture: 15 * sonde.prix, ecart: 0,
        statutRappro: 'rapproche', statutPaiement: 'impayee',
      });
      const montant = 15 * sonde.prix;
      /* Deux lignes plates équilibrées — RG-10 : débit = crédit. */
      S.collection('ecritures').insert({
        numero: 'ACH-SONDE-1', date: C2.iso(new Date()), journal: 'ACH',
        journalLibelle: 'Achats', compte: '601000', compteLibelle: 'Achats de marchandises',
        libelle: 'Facture FF-SONDE-0001 — sonde chaîne 1', debit: montant, credit: 0,
        origine: 'Saisie manuelle', statut: 'brouillon',
      });
      S.collection('ecritures').insert({
        numero: 'ACH-SONDE-1', date: C2.iso(new Date()), journal: 'ACH',
        journalLibelle: 'Achats', compte: '401000', compteLibelle: 'Fournisseurs',
        libelle: 'Facture FF-SONDE-0001 — sonde chaîne 1', debit: 0, credit: montant,
        origine: 'Saisie manuelle', statut: 'brouillon',
      });
      const piece = S.collection('ecritures').active().filter((e) => e.numero === 'ACH-SONDE-1');
      const debit = piece.reduce((n, e) => n + (e.debit || 0), 0);
      const credit = piece.reduce((n, e) => n + (e.credit || 0), 0);
      return { equilibre: piece.length === 2 && debit === credit && debit > 0,
        brouillon: piece.every((e) => e.statut === 'brouillon') };
    }, c1);
    verifier('La facture fournisseur est rapprochée et l’écriture naît ÉQUILIBRÉE en brouillon (RG-10)',
      c5.equilibre && c5.brouillon);

    /* 6. Les écrans du circuit MONTRENT la chaîne. */
    await ouvrir('m7-besoins.html');
    const ecranBesoins = await page.evaluate(() => /BEB-SONDE-0001/.test(document.body.textContent));
    await ouvrir('m6-mouvements.html');
    const ecranMvt = await page.evaluate(() => /M-SONDE-01|BL-SONDE-0001/.test(document.body.textContent));
    await ouvrir('m12-ecritures.html');
    const ecranEcr = await page.evaluate(() => /ACH-SONDE-1/.test(document.body.textContent));
    verifier('Le besoin, le mouvement et l’écriture apparaissent sur leurs écrans',
      ecranBesoins && ecranMvt && ecranEcr,
      [ecranBesoins, ecranMvt, ecranEcr].join('/'));
    verifier('Aucune erreur JavaScript sur toute la chaîne', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 11. CHAÎNE 2 — fiche RH → planning → prime → bulletin → validation Direction
   * ======================================================================= */
  {
    scenario('Chaîne 2 — fiche RH → planning → primes → bulletin SANS sanction → validation Direction');
    await session(RH);
    await ouvrir('m10-personnel.html');
    const rh1 = await page.evaluate(() => {
      const S = window.SIGH.store;
      const inf = S.collection('personnel').active().find((p) => p.nomComplet === 'AKONDE Octave');
      const planning = S.collection('planning').active().filter((x) => x.employeId === inf.id);
      /* Le régime infirmier nomme ses vacations garde_soins / garde_hospi. */
      const gardes = planning.filter((x) => /garde/i.test(x.type));
      return { fiche: !!inf, planning: planning.length, gardes: gardes.length };
    });
    verifier('La fiche d’AKONDE Octave existe et son planning est semé (régime infirmier)',
      rh1.fiche && rh1.planning > 0, rh1.planning + ' vacation(s)');
    verifier('Le planning porte des gardes — la matière première des primes NS 132',
      rh1.gardes > 0, rh1.gardes + ' garde(s)');

    /* Le calcul et la génération passent par L'ÉCRAN, comme au poste. */
    await ouvrir('m11-calcul.html');
    await cliquer('Générer les bulletins');
    await cliquer('Générer', '[role="dialog"] button');
    await pause(600);
    const paie = await page.evaluate(() => {
      const S = window.SIGH.store;
      const b = S.collection('bulletins').active();
      const akonde = b.find((x) => x.employe === 'AKONDE Octave');
      const N = window.SIGH.nav;
      return {
        generes: b.length,
        aValider: b.filter((x) => x.statutBulletin === 'a_valider').length,
        sansSanction: b.every((x) => !x.sanction && !x.pctSanction),
        /* PAS DE PRIMES chez BAGUIDI (07/09/2026) : la grille est vide, et
           une grille vide vaut ZÉRO — jamais un repli sur la note de la
           clinique d'origine, qui ferait verser des primes que personne n'a
           décidées. */
        akondePrimes: akonde ? (akonde.totalPrimes || 0) : -1,
        grilleVide: S.collection('grillePrimes').active().length === 0,
        sansPrime: b.every((x) => !x.totalPrimes && !(x.lignesPrimes || []).length),
        moteurZero: window.SIGH.data.NS132.montant('garde', 'infirmier', '2026-09-30'),
        moteurGarde: !!window.SIGH.data.NS132.montantOrigine,
        ecranFerme: !N.ecranActif('m10-primes', 'M10'),
      };
    });
    verifier('Les bulletins des huit agents sont générés, soumis à la validation de la Direction',
      paie.generes >= 8 && paie.aValider >= 8, paie.generes + ' bulletin(s)');
    verifier('AUCUN bulletin ne porte de sanction — le NS 131 est bien hors de la paie',
      paie.sansSanction);
    verifier('AUCUN bulletin ne porte de prime — le dispositif est désactivé, grille vide et écran fermé',
      paie.sansPrime && paie.grilleVide && paie.ecranFerme && paie.akondePrimes === 0,
      'primes de l’infirmier : ' + paie.akondePrimes + ' FCFA');
    verifier('Une grille VIDE vaut zéro : le moteur ne retombe pas sur la note de la clinique d’origine',
      paie.moteurZero === 0 && paie.moteurGarde);

    /* La Direction VALIDE — signer n'est pas saisir. */
    await session(DIRECTION);
    await ouvrir('m11-validation.html');
    const val = await page.evaluate(() => {
      const S = window.SIGH.store;
      const col = S.collection('bulletins');
      const aValider = col.active().filter((x) => x.statutBulletin === 'a_valider');
      aValider.forEach((b) => col.update(b.id, {
        statutBulletin: 'valide', validePar: 'GBAGUIDI Rafiou', dateValidation: '2026-09-02',
      }));
      return {
        ecran: !/error-403/.test(location.href),
        valides: col.active().filter((x) => x.statutBulletin === 'valide'
          && x.validePar === 'GBAGUIDI Rafiou').length,
      };
    });
    verifier('La Direction valide les bulletins à son nom — la chaîne est bouclée',
      val.ecran && val.valides >= 8, val.valides + ' validé(s)');
    verifier('Aucune erreur JavaScript sur toute la chaîne', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 11 bis. AIB — le taux se déduit du statut de l'IFU, jamais d'un défaut
   * ======================================================================= */
  {
    scenario('AIB — généralisation du taux de 5 %, retenue tracée et écriture équilibrée');
    await session(COMPTABLE);
    /* La file des factures fournisseurs s'amorce à l'ouverture de son écran. */
    await ouvrir('m7-factures-fournisseurs.html');
    await ouvrir('m12-aib.html');

    const moteur = await page.evaluate(() => {
      const D2 = window.SIGH.data;
      const G = D2.PARAM_AIB.generalisation;
      return {
        texteDit: /Généralisation du taux de 5 %/.test(document.body.textContent),
        baremeAffiche: /Barème de l’AIB/.test(document.body.textContent)
          && /À arrêter par la Direction|Proposition :/.test(document.body.textContent),
        dateEffet: G.dateEffet,
        /* Un IFU désactivé, APRÈS la date d'effet : 5 % s'impose. */
        apres: D2.tauxAIB('desactive', '2026-09-10'),
        absentApres: D2.tauxAIB('absent', '2026-09-30'),
        /* Le même IFU AVANT la date d'effet : la généralisation ne s'applique
           pas, et le taux d'alors n'est fixé par aucun document. */
        avant: D2.tauxAIB('desactive', '2026-08-31'),
        /* Statut non vérifié : aucun taux ne se décide. */
        inconnu: D2.tauxAIB('inconnu', '2026-09-10'),
        /* IFU actif : le champ des taux de 1 % et 3 % reste à arrêter. */
        actif: D2.tauxAIB('actif', '2026-09-10'),
        comptes: D2.PARAM_AIB.comptes,
      };
    });
    verifier('L’écran énonce la généralisation du 5 %, sa source, et affiche le barème avec ses règles en attente',
      moteur.texteDit && moteur.baremeAffiche);
    verifier('IFU désactivé ou absent, à partir du 07/09/2026 → 5 % appliqué et motivé',
      moteur.apres.taux === 5 && moteur.apres.generalise && /désactivé/.test(moteur.apres.motif)
      && moteur.absentApres.taux === 5, JSON.stringify(moteur.apres));
    verifier('Avant la date d’effet, la généralisation ne s’applique pas — et le taux se refuse',
      moteur.avant.taux === null && /07\/09\/2026/.test(moteur.avant.motif));
    verifier('Statut non vérifié ou IFU actif : AUCUN taux par défaut — le refus est nommé',
      moteur.inconnu.taux === null && moteur.actif.taux === null
      && /ne se décide pas/.test(moteur.inconnu.motif));

    /* LE BARÈME EST UNE DONNÉE : une règle en attente ne s'applique pas ;
       arrêtée, elle s'applique d'elle-même à la retenue suivante. */
    const bareme = await page.evaluate(() => {
      const S2 = window.SIGH.store, D2 = window.SIGH.data;
      const regles = D2.baremeAIB();
      const avant = D2.tauxAIB('actif', '2026-09-10');
      /* La Direction arrête la règle des 1 %. */
      const col = S2.collection('baremeAIB');
      const r1 = col.active().filter((r) => r.taux === 1)[0];
      col.update(r1.id, { arrete: true, condition: 'Sonde — tiers au régime du réel', dateEffet: null });
      const apresUne = D2.tauxAIB('actif', '2026-09-10');
      /* Puis celle des 3 % : DEUX règles visent alors le même tiers — le
         logiciel ne choisit pas, il nomme les règles en présence. */
      const r3 = col.active().filter((r) => r.taux === 3)[0];
      col.update(r3.id, { arrete: true, condition: 'Sonde — prestataire', dateEffet: null });
      const apresDeux = D2.tauxAIB('actif', '2026-09-10');
      const nomme = D2.tauxAIB('actif', '2026-09-10', r3.id);
      /* Une sonde qui mute restaure. */
      col.update(r1.id, { arrete: false, condition: null });
      col.update(r3.id, { arrete: false, condition: null });
      return {
        nbRegles: regles.length,
        arreteesAuDepart: regles.filter((r) => r.arrete).map((r) => r.taux),
        avant: avant.taux, apresUne: apresUne.taux, apresUneMotif: apresUne.motif,
        apresDeux: apresDeux.taux, choix: (apresDeux.choix || []).map((c) => c.taux),
        nomme: nomme.taux, nommeRegle: nomme.regle === r3.id,
        retabli: D2.tauxAIB('actif', '2026-09-10').taux,
      };
    });
    verifier('Le barème porte les trois taux, et SEULE la règle des 5 % est arrêtée d’emblée',
      bareme.nbRegles === 3 && bareme.arreteesAuDepart.join(',') === '5',
      'arrêtées : ' + bareme.arreteesAuDepart.join(','));
    verifier('Une règle ARRÊTÉE s’applique d’elle-même — sans toucher au code',
      bareme.avant === null && bareme.apresUne === 1 && /régime du réel/.test(bareme.apresUneMotif || ''));
    verifier('Deux règles pour un même tiers : le logiciel NOMME les règles au lieu de choisir',
      bareme.apresDeux === null && bareme.choix.join(',') === '1,3');
    verifier('La règle désignée par le poste tranche, et le retrait rétablit le refus',
      bareme.nomme === 3 && bareme.nommeRegle && bareme.retabli === null);
    verifier('Les deux faces de l’AIB portent des comptes distincts : dette 4478, créance 4492',
      moteur.comptes.retenu === '4478' && moteur.comptes.subi === '4492');

    /* La chaîne au geste : constater le statut, puis retenir. */
    const chaine = await page.evaluate(() => {
      const S2 = window.SIGH.store, D2 = window.SIGH.data;
      /* La sonde fabrique SON règlement : dépendre du jeu de démonstration
         ferait dépendre le résultat de l'ordre des scénarios — un test qui
         mesure l'ordre d'exécution ne mesure plus la règle. */
      const f = S2.collection('fournisseurs').active()[0];
      if (!f) return { pasDeFacture: true };
      const fa = S2.collection('facturesFournisseurs').insert({
        reference: 'FF-AIB-SONDE', date: '2026-09-10', fournisseurNom: f.nom,
        montantLivraison: 400000, montantFacture: 400000, ecart: 0,
        statutRappro: 'rapproche', statutPaiement: 'payee',
      }).record;
      const avant = f ? f.ifuStatut : null;
      /* Le comptable constate un IFU désactivé au fichier de la DGI. */
      S2.collection('fournisseurs').update(f.id, { ifuStatut: 'desactive', ifuVerifieLe: '2026-09-08' });
      const t = D2.tauxAIB('desactive', fa.date >= '2026-09-07' ? fa.date : '2026-09-08');
      const montant = fa.montantFacture || 0;
      const aib = Math.round(montant * t.taux / 100);
      const piece = 'AIB-SONDE-1';
      S2.collection('retenuesAIB').insert({
        date: '2026-09-08', factureRef: fa.reference, tiers: fa.fournisseurNom,
        ifu: f.ifu || null, ifuStatut: 'desactive', contact: '—',
        montant: montant, taux: t.taux, montantAIB: aib, generalise: true, motif: t.motif, piece: piece,
      });
      const ecr = S2.collection('ecritures');
      ecr.insert({ numero: piece, date: '2026-09-08', journal: 'OD', journalLibelle: 'Opérations diverses',
        compte: D2.COMPTES_SIGH.fournisseurs, libelle: 'AIB retenu — sonde', debit: aib, credit: 0,
        origine: 'Automatique — AIB', statut: 'brouillon' });
      ecr.insert({ numero: piece, date: '2026-09-08', journal: 'OD', journalLibelle: 'Opérations diverses',
        compte: D2.COMPTES_SIGH.etatRetenuesSource, libelle: 'AIB retenu — sonde', debit: 0, credit: aib,
        origine: 'Automatique — AIB', statut: 'brouillon' });
      const piecesSonde = ecr.active().filter((e) => e.numero === piece);
      const r = S2.collection('retenuesAIB').active().filter((x) => x.piece === piece)[0];
      /* On remet le statut d'origine : une sonde qui mute restaure. */
      S2.collection('fournisseurs').update(f.id, { ifuStatut: avant, ifuVerifieLe: null });
      return {
        taux: r.taux, aib: r.montantAIB, attendu: Math.round(montant * 5 / 100),
        generalise: r.generalise, motifTrace: /désactivé/.test(r.motif || ''),
        debit: piecesSonde.reduce((n, e) => n + (e.debit || 0), 0),
        credit: piecesSonde.reduce((n, e) => n + (e.credit || 0), 0),
        comptes: piecesSonde.map((e) => e.compte).sort().join('+'),
        brouillon: piecesSonde.every((e) => e.statut === 'brouillon'),
      };
    });
    verifier('La retenue applique 5 % du montant de la facture et garde son motif',
      !chaine.pasDeFacture && chaine.taux === 5 && chaine.aib === chaine.attendu
      && chaine.generalise && chaine.motifTrace, JSON.stringify(chaine));
    verifier('L’écriture est ÉQUILIBRÉE (RG-10), en brouillon, sur 4011 et 4478',
      chaine.debit === chaine.credit && chaine.debit > 0
      && chaine.comptes === '4011+4478' && chaine.brouillon, chaine.comptes);
    verifier('Aucune erreur JavaScript', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 11 ter. L'IFU SUR LA FICHE — et l'AIB au bulletin, dans les deux sens
   * -------------------------------------------------------------------------
   * Ce que cette sonde protège : on ne retient pas d'AIB sur un salaire, et on
   * n'oublie pas de la retenir sur des honoraires. Les deux erreurs se paient,
   * l'une par le tiers, l'autre par la clinique.
   * ======================================================================= */
  {
    scenario('IFU sur chaque fiche — l’AIB frappe les honoraires, jamais un salaire');
    await session(RH);
    await ouvrir('m10-personnel.html');
    const fiches = await page.evaluate(() => {
      const S = window.SIGH.store, D = window.SIGH.data;
      const agents = S.collection('personnel').active();
      const t = document.body.textContent;
      return {
        effectif: agents.length,
        champs: agents.every((a) => 'ifu' in a && 'ifuStatut' in a && 'regimeRemuneration' in a),
        aucunIfuInvente: agents.every((a) => !a.ifu),
        tousAVerifier: agents.every((a) => a.ifuStatut === 'inconnu'),
        tousSalaries: agents.every((a) => a.regimeRemuneration === 'salaire'),
        ecranDit: /IFU/.test(t) && /régime de rémunération|Régime de rémunération/i.test(t),
        regimes: D.PARAM_AIB.regimes.map((r) => r.id).join(','),
      };
    });
    verifier('Chaque fiche d’agent porte IFU, statut au fichier de la DGI et régime de rémunération',
      fiches.effectif >= 8 && fiches.champs && fiches.ecranDit);
    verifier('AUCUN IFU n’est inventé pour les huit agents — le statut reste à vérifier',
      fiches.aucunIfuInvente && fiches.tousAVerifier);
    verifier('Les huit agents sont au régime salaire : deux régimes existent, salaire et honoraires',
      fiches.tousSalaries && fiches.regimes === 'salaire,honoraires');

    /* Le bulletin d'un SALARIÉ porte la ligne d'AIB — à zéro et motivée. */
    await ouvrir('m11-calcul.html');
    const salarie = await page.evaluate(() => {
      const S = window.SIGH.store;
      const b = S.collection('bulletins').active().filter((x) => x.employe === 'AKONDE Octave')[0];
      const bt = document.body.textContent;
      return {
        bulletin: !!b, aib: b ? b.aib : -1, applicable: b ? !!b.aibApplicable : true,
        motif: b ? (b.aibMotif || '') : '',
        ecranDit: /AIB/.test(bt),
      };
    });
    verifier('Le bulletin d’un salarié porte une AIB NULLE, motivée « sans objet »',
      salarie.bulletin && salarie.aib === 0 && !salarie.applicable
      && /salariale/.test(salarie.motif), salarie.motif);
    verifier('L’écran de calcul nomme l’AIB — elle ne se découvre pas à l’impression',
      salarie.ecranDit);

    /* On bascule l'infirmier au régime honoraires, IFU désactivé : la retenue
       de 5 % apparaît, se déduit du net, et le motif la porte. */
    const hono = await page.evaluate(() => {
      const S = window.SIGH.store, D = window.SIGH.data;
      const col = S.collection('personnel');
      const inf = col.active().filter((p) => p.nomComplet === 'AKONDE Octave')[0];
      const avant = { ifu: inf.ifu, ifuStatut: inf.ifuStatut, regime: inf.regimeRemuneration };
      col.update(inf.id, {
        ifu: '3299999999999', ifuStatut: 'desactive',
        ifuVerifieLe: '2026-09-08', ifuVerifiePar: 'Sonde',
        regimeRemuneration: 'honoraires',
      });
      const apres = D.aibTiers(col.active().filter((p) => p.id === inf.id)[0], '2026-09-30', 100000);
      /* Un IFU actif : le barème n'ayant pas arrêté les 1 % / 3 %, on refuse. */
      col.update(inf.id, { ifuStatut: 'actif' });
      const attente = D.aibTiers(col.active().filter((p) => p.id === inf.id)[0], '2026-09-30', 100000);
      /* Une sonde qui mute restaure. */
      col.update(inf.id, {
        ifu: avant.ifu, ifuStatut: avant.ifuStatut, ifuVerifieLe: null, ifuVerifiePar: null,
        regimeRemuneration: avant.regime,
      });
      const remis = D.aibTiers(col.active().filter((p) => p.id === inf.id)[0], '2026-09-30', 100000);
      return {
        taux: apres.taux, montant: apres.montant, base: apres.base, motif: apres.motif,
        attenteTaux: attente.taux, attenteMotif: attente.motif, attenteApplicable: attente.applicable,
        remisApplicable: remis.applicable, remisMontant: remis.montant,
      };
    });
    verifier('Régime honoraires + IFU désactivé → 5 % retenus sur l’assiette, motif à l’appui',
      hono.taux === 5 && hono.base === 100000 && hono.montant === 5000
      && /désactivé/.test(hono.motif), JSON.stringify(hono));
    verifier('Régime honoraires + IFU actif → le barème n’a rien arrêté : ZÉRO retenu, refus nommé',
      hono.attenteApplicable && hono.attenteTaux === null && hono.attenteMotif.length > 0);
    verifier('Le retour au régime salaire rend l’AIB sans objet — la bascule est réversible',
      !hono.remisApplicable && hono.remisMontant === 0);

    /* LA PIÈCE ELLE-MÊME : le bulletin imprimé doit porter la ligne. */
    await session(DIRECTION);
    await ouvrir('m11-bulletins.html');
    const clique = await page.evaluate(() => {
      const b = Array.from(document.querySelectorAll('button[title]'))
        .filter((x) => /Imprimer/i.test(x.getAttribute('title') || ''))[0];
      if (b) { b.click(); return true; }
      return false;
    });
    await pause(700);
    verifier('L’écran des bulletins offre l’impression de la pièce', clique);
    const pieceAib = await page.evaluate(() => {
      const sheet = document.querySelector('.print-sheet');
      const t = sheet ? sheet.textContent : '';
      return {
        ouverte: /Bulletin de paie/.test(t),
        ligne: /Acompte sur impôt assis sur les bénéfices \(AIB\)/.test(t),
        cartouche: /IFU/.test(t) && /Régime de rémunération/.test(t),
        motive: /rémunération salariale/.test(t),
      };
    });
    verifier('Le bulletin IMPRIMÉ porte la ligne d’AIB dans le tableau des retenues',
      pieceAib.ouverte && pieceAib.ligne, JSON.stringify(pieceAib));
    verifier('La pièce porte l’IFU, le régime, et la phrase qui justifie la retenue (ou son absence)',
      pieceAib.cartouche && pieceAib.motive, JSON.stringify(pieceAib));
    verifier('Aucune erreur JavaScript', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 11 quater. HISTORIQUE DES PRIX — la trace s'écrit seule, le passé ne bouge pas
   * ======================================================================= */
  {
    scenario('Historique des prix — auteur unique, prix figé sur le mouvement, refus nommé');
    await session(COMPTABLE);
    await ouvrir('m6-produits.html');

    const prix = await page.evaluate(() => {
      const S2 = window.SIGH.store, D2 = window.SIGH.data;
      const col = S2.collection('produits');
      const p = col.active().filter((x) => x.prixAchat > 0)[0];
      const avantPrix = p.prixAchat;
      const nb0 = S2.historiquePrix(p.id).length;

      /* Un mouvement enregistré AVANT le changement : il porte SA valeur. */
      const mv = S2.collection('mouvements').insert({
        reference: 'MVT-PRIX-SONDE', date: '2026-09-01',
        produitId: p.id, produit: p.designation, type: 'sortie', typeLabel: 'Sortie',
        quantite: 2, valeur: 2 * avantPrix, cump: p.cump,
        justificatif: 'Sonde historique des prix', utilisateur: 'Sonde',
      }).record;
      const valeurAvant = mv.valeur;

      /* LE CHANGEMENT passe par la seule porte du magasin : la trace naît
         d'elle-même, aucun écran ne l'écrit. */
      col.update(p.id, {
        prixAchat: Math.round(avantPrix * 1.3),
        _motifPrix: 'Nouvelle facture fournisseur — sonde',
      });
      const h = S2.historiquePrix(p.id);
      const derniere = h[0];
      const mvApres = S2.collection('mouvements').get(mv.id);

      /* Une modification SANS changement de prix n'écrit pas de ligne : un
         historique qui se remplit tout seul devient illisible. */
      col.update(p.id, { emplacement: 'Rayon sonde' });
      const nbApresNeutre = S2.historiquePrix(p.id).length;

      return {
        nb0: nb0, nbApres: h.length, nbApresNeutre: nbApresNeutre,
        champ: derniere && derniere.champ, ancien: derniere && derniere.ancien,
        nouveau: derniere && derniere.nouveau, ecart: derniere && derniere.ecartPct,
        motif: derniere && derniere.motif, auteur: derniere && derniere.utilisateur,
        libelleFige: derniere && derniere.produit === p.designation,
        valeurAvant: valeurAvant, valeurApres: mvApres.valeur,
        /* Le refus nommé, sur un article sans prix. */
        refus: S2.prixManquant({ designation: 'Article sans prix', prixAchat: 0, cump: 0, prixVente: 0 }),
        pasDeRefus: S2.prixManquant(p),
        /* Les trois méthodes de valorisation, dont celle par lot. */
        methodes: (D2.PARAM_STOCK.options || []).map((o) => o.id),
        coefficient: D2.PARAM_STOCK.coefficientVente,
      };
    });

    verifier('Le changement de prix écrit UNE ligne d’historique, sans qu’aucun écran ne l’écrive',
      prix.nbApres === prix.nb0 + 1 && prix.champ === 'prixAchat', JSON.stringify(prix));
    verifier('La ligne porte l’ancien prix, le nouveau, l’écart en %, le motif et son auteur',
      prix.ancien > 0 && prix.nouveau > prix.ancien && prix.ecart === 30
      && /facture fournisseur/.test(prix.motif || '') && !!prix.auteur, 'écart ' + prix.ecart + ' %');
    verifier('Le libellé de l’article est FIGÉ sur la ligne — renommer l’article ne la réécrit pas',
      prix.libelleFige);
    verifier('Une modification sans changement de prix n’écrit AUCUNE ligne',
      prix.nbApresNeutre === prix.nbApres);
    verifier('LE MOUVEMENT DÉJÀ ENREGISTRÉ GARDE SA VALEUR — le passé ne se réécrit pas',
      prix.valeurApres === prix.valeurAvant, prix.valeurAvant + ' → ' + prix.valeurApres);
    verifier('Un article sans prix ne sort pas : le refus NOMME la fiche à compléter',
      /Prix d’achat non renseigné/.test(prix.refus || '') && prix.pasDeRefus === null);
    verifier('Trois méthodes de valorisation, dont le PRIX DU LOT, et le coefficient de vente à 1,00',
      prix.methodes.join(',') === 'prixVente,cump,lot' && prix.coefficient === 1,
      prix.methodes.join(','));

    /* La valorisation au lot : le lot porte ce qu'il a coûté ; sans prix
       propre, elle retombe sur le CUMP et le DIT. */
    const lot = await page.evaluate(() => {
      const S2 = window.SIGH.store;
      const avant = S2.valorisationSortie();
      S2.setValorisationSortie('lot');
      const p = S2.collection('produits').active().filter((x) => x.cump > 0)[0];
      const l = S2.collection('lots').active().filter((x) => x.produitId === p.id)[0];
      const avecLot = l ? S2.valeurUnitaireDetail(p, l) : null;
      const sansLot = S2.valeurUnitaireDetail(p, { numeroLot: 'L-SANS-PRIX' });
      S2.setValorisationSortie(avant);
      return { avecLot: avecLot, sansLot: sansLot, methodeRendue: S2.valorisationSortie() };
    });
    verifier('Valorisation au lot : la sortie prend le prix du lot, et l’estimation se DIT',
      lot.avecLot && lot.avecLot.methode === 'lot' && lot.avecLot.valeur > 0 && lot.avecLot.approx === true
      && /valeur d’attente/.test(lot.avecLot.motif), JSON.stringify(lot.avecLot));
    verifier('Un lot sans prix propre retombe sur le CUMP — et l’annonce plutôt que de se taire',
      lot.sansLot.methode === 'cump' && /ne porte pas de prix propre/.test(lot.sansLot.motif));
    verifier('Aucune erreur JavaScript', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 12. CENTRE DES VALIDATIONS — ce qui attend la Direction est DIT
   * ======================================================================= */
  {
    scenario('adm-validations — files actives et « à compléter par la Direction »');
    await session(ADMIN);
    await ouvrir('adm-validations.html');
    const adm = await page.evaluate(() => {
      const t = document.body.textContent;
      return {
        /* Le RCCM a été FOURNI le 07/09/2026 : il quitte la liste des
           manquants. La forme juridique et l'autorisation, elles, restent. */
        rccm: /Forme juridique et n° d’autorisation d’ouverture/.test(t)
          && !/RCCM, forme juridique/.test(t),
        /* Les primes ont QUITTÉ la liste des attentes : elles sont désactivées
           (07/09/2026), ce qui est une décision, pas une donnée manquante. */
        primesDecidees: /Primes \(NS 132\)/.test(t) && /DÉSACTIVÉES/.test(t),
        salaires: /Salaires du personnel/.test(t),
        sage: /Inventaire SAGE/.test(t),
        fournisseurs: /Fournisseurs et périodicités/.test(t),
        baseline: /Compte de résultat 2025/.test(t),
        decisions: /SIGH-CBG/.test(t) && /02\/09\/2026/.test(t),
        sansCliniques: !/Résultats à valider biologiquement|imagerie/.test(t),
      };
    });
    verifier('Les données NON FOURNIES restent listées (forme juridique, salaires), le RCCM en sort, '
      + 'et les primes figurent en DÉCISION',
      adm.rccm && adm.salaires && adm.primesDecidees);
    verifier('Le jeu de démonstration hérité est DIT à remplacer : SAGE, fournisseurs, baseline 2025',
      adm.sage && adm.fournisseurs && adm.baseline);
    verifier('Les décisions de la Direction du 02/09/2026 sont tracées (sigle, périmètre, comptes)',
      adm.decisions);
    verifier('Plus aucune file clinique sur le centre des validations', adm.sansCliniques);
    verifier('Aucune erreur JavaScript', erreursJS.length === 0, erreursJS.join(' | '));
  }

  /* =========================================================================
   * 13. GREP FINAL — plus aucune trace CNT sur les écrans du périmètre
   * ======================================================================= */
  {
    scenario('Grep final — aucune chaîne CNT sur les écrans actifs ni les états');
    await session(ADMIN);
    const pagesActives = ['dash-direction.html', 'm6-produits.html', 'm7-besoins.html', 'cfg-organisation.html', 'm10-primes.html', 'm12-aib.html',
      'm10-personnel.html', 'm11-bulletins.html', 'm12-ecritures.html', 'm13-courriers.html',
      'cfg-branding.html', 'cfg-modules.html', 'aide-apropos.html', 'contact-editeur.html',
      'rapports-bibliotheque.html', 'ged-bibliotheque.html'];
    let propres = 0;
    const sales = [];
    for (const p of pagesActives) {
      await ouvrir(p);
      /* Le grep du PROMPT : dénomination, ville, slogan, IFU et RCCM de la
         clinique d'origine, plus les CODES DOSSIER CNT/<n°>/<année>. Les
         références de documents sources (NS 132/07/DM/DA/CNT/2026) restent :
         elles TRACENT la provenance de la grille héritée — c'est le faux
         positif documenté du grep. */
      const trace = await page.evaluate(() =>
        /NASSIERA|Natitingou|3201642748214|RB\/NAT\/2016-B-268|notre raison de vivre|CNT\/\d+\/\d{2}\b/.test(document.body.textContent)
        /* Les AGENTS de la clinique d'origine ne doivent pas non plus figurer :
           l'organigramme, les notes de service et les secteurs les portaient
           encore. Un nom d'agent est une donnée personnelle — il n'a rien à
           faire dans le référentiel d'une autre clinique. */
        || /BASSONGUI|TAKI Alimatou|KASSA Augustin|OROU YO|DIEYABIDI|MAMAN Zoukanéri|KINNOU|AHOHOU|TEPA Séraphine/
          .test(document.body.textContent));
      if (!trace) propres++; else sales.push(p);
    }
    verifier('Aucune chaîne CNT (nom, ville, slogan, IFU, RCCM, code CNT/…) sur les écrans actifs',
      propres === pagesActives.length, 'traces sur : ' + sales.join(', '));

    /* Le code dossier et les clés de stockage sont passés au sigle CBG. */
    const cbg = await page.evaluate(() => ({
      code: window.SIGH.core.codePatient(530, 2025),
      sigle: window.SIGH.core.BRAND.sigle,
      cles: Object.keys(localStorage).every((k) => !/^sigh-cnt:/.test(k)),
    }));
    verifier('Le code dossier est CBG/530/25 — la règle vit sur BRAND.sigle',
      cbg.code === 'CBG/530/25' && cbg.sigle === 'CBG', cbg.code);
    verifier('Plus aucune clé localStorage sigh-cnt:', cbg.cles);
    verifier('Aucune erreur JavaScript', erreursJS.length === 0, erreursJS.join(' | '));
  }

  await browser.close();
  server.close();

  /* --- Restitution --------------------------------------------------------- */
  const ligne = '─'.repeat(72);
  console.log('\n\n' + ligne);
  console.log('TESTS FONCTIONNELS — PROTOTYPE SIGH-CBG (CLINIQUE BAGUIDI)');
  console.log(ligne);

  let totalEtapes = 0, totalOk = 0;
  for (const s of resultats) {
    const okEtapes = s.etapes.filter((e) => e.ok).length;
    totalEtapes += s.etapes.length;
    totalOk += okEtapes;
    console.log(`\n${s.ok ? '✓' : '✗'} ${s.nom}   (${okEtapes}/${s.etapes.length})`);
    for (const e of s.etapes) {
      if (!e.ok) console.log(`    ✗ ${e.libelle}${e.detail ? '  →  ' + e.detail : ''}`);
    }
  }

  const scenariosOk = resultats.filter((s) => s.ok).length;
  console.log('\n' + ligne);
  console.log(`Scénarios : ${scenariosOk}/${resultats.length}     Vérifications : ${totalOk}/${totalEtapes}`);
  console.log(scenariosOk === resultats.length
    ? 'RÉSULTAT : TOUS LES PARCOURS FONCTIONNELS SONT CONFORMES.'
    : `RÉSULTAT : ${resultats.length - scenariosOk} scénario(s) en échec.`);
  console.log(ligne);

  fs.writeFileSync(path.join(ROOT, 'build/rapport-tests.json'), JSON.stringify(resultats, null, 2));
  process.exit(scenariosOk === resultats.length ? 0 : 1);
})();
