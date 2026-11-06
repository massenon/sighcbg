/* AUDIT DES ACTIONS PAR PROFIL — « VÉRIFIER TT LES ACTIONS DISABLE OU ABLE ».
 *
 * La question posée est simple et le contrôle habituel ne la pose jamais :
 * sur chaque écran, un profil qui n'a PAS le droit de modifier voit-il quand
 * même un bouton « Modifier » ? Un profil qui n'a pas le droit d'annuler
 * voit-il un bouton « Archiver » ?
 *
 * `npm run check` n'y répond pas : il ouvre les pages sous un seul profil et
 * ne lit pas les boutons. Cet audit ouvre CHAQUE écran sous CHAQUE profil qui
 * y a accès, relève les commandes d'écriture affichées, et les confronte aux
 * droits que le moteur RBAC accorde.
 *
 * DEUX FAUTES SYMÉTRIQUES, ET LA SECONDE EST LA PLUS GRAVE :
 *   - PROMETTRE : afficher « Modifier » à qui ne peut pas modifier. Le
 *     bouton mène à un refus, ou pire, à une modification qui ne s'enregistre
 *     pas.
 *   - CACHER : ne rien afficher à qui a le droit. L'agent croit le logiciel
 *     incomplet et ressaisit ailleurs.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const http = require('http');
const puppeteer = require('puppeteer');
const ROOT = path.resolve(__dirname, '..');
const PORT = 8161;
function findBrowser() {
  const c = [process.env.CHROME_PATH, 'C:/Program Files/Google/Chrome/Application/chrome.exe',
    'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
    'C:/Program Files/Microsoft/Edge/Application/msedge.exe'].filter(Boolean);
  for (const x of c) if (fs.existsSync(x)) return x;
  return null;
}
const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json', '.woff2': 'font/woff2',
  '.jpeg': 'image/jpeg', '.jpg': 'image/jpeg', '.png': 'image/png', '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon' };
function serve() {
  return new Promise((r) => {
    const s = http.createServer((req, res) => {
      const rel = decodeURIComponent(req.url.split('?')[0]).replace(/^\/+/, '') || 'index.html';
      const f = path.join(ROOT, rel);
      if (!f.startsWith(ROOT) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) {
        res.writeHead(404); res.end('404'); return;
      }
      res.writeHead(200, { 'Content-Type': MIME[path.extname(f)] || 'application/octet-stream' });
      fs.createReadStream(f).pipe(res);
    });
    s.listen(PORT, () => r(s));
  });
}

/* Les profils sondés, avec la fonction métier réelle de chacun. */
const PROFILS = [
  ['reception', 'accueil'], ['medecin', 'medecin'], ['infirmier', 'infirmier'],
  ['laborantin', 'tsl'], ['caissier', 'caissiere'], ['stock', 'stock'],
  ['comptable', 'comptable'], ['da', 'direction'], ['dm', 'medecin'],
  ['aide_soignant', 'aide_soignant'], ['echographiste', 'medecin'],
  ['surveillant', 'infirmier'], ['assistant_comptable', 'comptable'],
  ['biomedical', 'stock'], ['agentadmin', 'entretien'], ['ambulancier', 'chauffeur'],
];

/* Ce qu'on considère comme une commande d'ÉCRITURE. */
/* « ÉDITER » N'EST PAS UNE ÉCRITURE — c'est une IMPRESSION. Relevé sur les
   vingt-quatre libellés du prototype : « Éditer l'état », « Éditer l'arrêté de
   caisse », « Éditer le bordereau », « Éditer la quittance »… tous produisent
   un document, aucun ne modifie une donnée. Le verbe d'écriture, ici, est
   « Modifier ». Compter le premier comme une écriture faisait signaler trois
   promesses là où il n'y en avait qu'une — et un audit qui crie au loup finit
   ignoré. */
const ECRITURE = /^(nouve|nouvel|créer|ajouter|enregistrer|saisir|modifier|valider|encaisser|prescrire|admettre|délivrer|transférer|déclarer|poser|émettre|inscrire|prélever|administrer)/i;
const ANNULATION = /^(archiver|supprimer|annuler|restaurer|clôturer)/i;

(async () => {
  const server = await serve();
  const browser = await puppeteer.launch({ executablePath: findBrowser(), headless: true,
    args: ['--no-sandbox', '--disable-dev-shm-usage', '--disable-gpu'] });
  const page = await browser.newPage();
  await page.setViewport({ width: 1600, height: 1100 });
  const erreurs = [];
  page.on('pageerror', (e) => erreurs.push(String(e.message)));

  /* L'inventaire des écrans et de leur module, lu au manifeste. */
  await page.goto('http://127.0.0.1:' + PORT + '/pages/dash-admin.html', { waitUntil: 'networkidle2' });
  const ecrans = await page.evaluate(() => {
    const N = window.SIGH.nav;
    const out = [];
    (N.NAV || []).forEach((dom) => (dom.modules || []).forEach((mod) => {
      (mod.items || []).forEach((it) => out.push({ id: it.id, module: mod.code, label: it.label }));
    }));
    return out;
  });
  console.log('Écrans au manifeste : ' + ecrans.length);

  const promesses = [];   /* bouton affiché sans le droit */
  const cachees = [];     /* droit accordé, aucune commande */
  let sondes = 0;

  for (const [role, fonction] of PROFILS) {
    await page.evaluate((r, f) => localStorage.setItem('sigh-cbg:session', JSON.stringify({
      role: r, nom: 'Audit ' + r, nomComplet: 'Audit ' + r, identifiant: 'audit', fonction: f,
    })), role, fonction);

    /* Les écrans que ce profil peut ouvrir, et ses droits sur chacun. */
    const accessibles = await page.evaluate((r) => {
      const N = window.SIGH.nav;
      const out = [];
      (N.NAV || []).forEach((dom) => (dom.modules || []).forEach((mod) => {
        (mod.items || []).forEach((it) => {
          /* ON NOMME LE MODULE. `can()` ne consulte la surcharge que si
             l'appelant le lui donne, et l'item du manifeste ne le porte pas :
             l'audit sondait donc des écrans que le profil ne peut PAS ouvrir,
             tombait sur la page 403 — qui n'affiche évidemment aucune
             commande — et les comptait comme « écrans en lecture qui ne le
             disent pas ». Même défaut que sur les cartes de hub et les accès
             rapides, une troisième fois. */
          const entree = Object.assign({}, it, {
            module: mod.code,
            roles: it.roles || mod.roles,
          });
          if (!N.can(r, entree)) return;
          const d = N.droitsEcran ? N.droitsEcran(r, it.id, mod.code) : N.droits(r, mod.code);
          out.push({ id: it.id, module: mod.code, editer: !!d.editer, annuler: !!d.annuler });
        });
      }));
      return out;
    }, role);

    for (const e of accessibles) {
      await page.goto('http://127.0.0.1:' + PORT + '/pages/' + e.id + '.html', { waitUntil: 'networkidle2' });
      await new Promise((r) => setTimeout(r, 130));
      sondes++;
      const vu = await page.evaluate((ecrit, annul) => {
        const re = new RegExp(ecrit, 'i'), ra = new RegExp(annul, 'i');
        /* Les commandes du CONTENU de la page — on exclut le ruban, la barre
           supérieure et les accès rapides, qui ne sont pas des actions de
           l'écran. */
        const zone = document.querySelector('#page-content, main, [data-page-content]') || document.body;
        const cmd = [...zone.querySelectorAll('button, a.btn')]
          .filter((b) => b.offsetParent !== null && !b.closest('#app-topbar, #app-ribbon, #page-actions'))
          .map((b) => ({
            texte: (b.textContent || '').trim(),
            titre: b.getAttribute('title') || '',
            inerte: b.getAttribute('aria-disabled') === 'true' || b.disabled
              || /opacity-50/.test(b.className || ''),
          }))
          .filter((b) => b.texte || b.titre);
        const nom = (b) => (b.texte || b.titre).trim();
        return {
          ecriture: cmd.filter((b) => re.test(nom(b)) && !b.inerte).map(nom),
          annulation: cmd.filter((b) => ra.test(nom(b)) && !b.inerte).map(nom),
          lectureSeule: /lecture seule|ne modifie pas|sans les saisir|consulte .* sans/i
            .test(zone.textContent || ''),
        };
      }, ECRITURE.source, ANNULATION.source);

      /* UN TABLEAU DE BORD NE MODIFIE RIEN : ses boutons sont des raccourcis
         de navigation vers un écran où le profil a, lui, le droit d'écrire.
         Les compter comme des promesses ferait signaler un défaut là où il
         n'y en a pas — et un audit qui crie au loup finit ignoré. */
      /* ET UN ÉCRAN D'ANALYSE NON PLUS : statistiques, points, baseline,
         grand livre, balance. Ils sont en lecture PAR NATURE, non par
         habilitation — y attendre un bandeau « lecture seule » ferait
         signaler un défaut là où il n'y en a pas. C'est la même liste que
         celle d'`ecranModifiable()` dans app.js : le jour où l'une change,
         l'autre doit suivre. */
      var navigation = /^(dash-|rapports-)/.test(e.id)
        || /-(stats|stats-[a-z]+|point-[a-z]+|baseline|analytique|grand-livre|balance)$/.test(e.id);
      if (!navigation && !e.editer && vu.ecriture.length) {
        promesses.push({ role, ecran: e.id, type: 'écriture', boutons: [...new Set(vu.ecriture)].slice(0, 3) });
      }
      if (!navigation && !e.annuler && vu.annulation.length) {
        promesses.push({ role, ecran: e.id, type: 'annulation', boutons: [...new Set(vu.annulation)].slice(0, 3) });
      }
      if (!navigation && !e.editer && !vu.ecriture.length && !vu.lectureSeule) {
        cachees.push({ role, ecran: e.id });
      }
    }
    process.stdout.write('  ' + role + ' : ' + accessibles.length + ' écran(s)\n');
  }

  console.log('\n' + '─'.repeat(72));
  console.log('AUDIT DES ACTIONS PAR PROFIL');
  console.log('─'.repeat(72));
  console.log('Sondages : ' + sondes + ' (écran × profil)');
  console.log('\nPROMESSES — un bouton actif sans le droit correspondant : ' + promesses.length);
  promesses.slice(0, 40).forEach((p) => {
    console.log('  ✗ ' + p.role.padEnd(20) + p.ecran.padEnd(28) + p.type + ' : ' + p.boutons.join(', '));
  });
  if (promesses.length > 40) console.log('  … ' + (promesses.length - 40) + ' autre(s)');

  console.log('\nÉCRANS EN LECTURE QUI NE LE DISENT PAS : ' + cachees.length);
  /* ON NOMME LE PROFIL. Un signalement qui dit « 1 profil » oblige à le
     chercher, et ce qu'on ne peut pas reproduire d'un coup, on ne le corrige
     pas. */
  const parEcran = {};
  cachees.forEach((c) => { (parEcran[c.ecran] = parEcran[c.ecran] || []).push(c.role); });
  Object.keys(parEcran).sort((a, b) => parEcran[b].length - parEcran[a].length).slice(0, 25)
    .forEach((k) => console.log('  · ' + k.padEnd(30) + parEcran[k].join(', ')));

  console.log('\nErreurs JS : ' + erreurs.length);
  erreurs.slice(0, 5).forEach((e) => console.log('   ' + e));
  console.log('─'.repeat(72));

  await browser.close();
  server.close();
})();
