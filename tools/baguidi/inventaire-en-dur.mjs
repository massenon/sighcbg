#!/usr/bin/env node
// INVENTAIRE DES VALEURS EN DUR (demande de la Direction de Baguidi : « faire l'inventaire des modules qui sont encore EN DUR dans le code »).
//
// La règle du projet est « rien en dur » : une valeur métier vient d'un référentiel administrable, d'un paramètre de clinique versionné
// (packages/domaine/lib/src/parametres/definitions.dart), de la matrice des droits ou d'un geste réservé (gestes_reserves.dart), ou de l'identité de la clinique.
// Ce script BALAIE le code de production — les `lib` du poste, du domaine, du client de synchronisation et du mobile (.dart), et le relais Laravel
// (apps/web/app et apps/web/config, .php) — et classe chaque occurrence CANDIDATE par FAMILLE et par MODULE :
//   A  années et dates fixes            B  taux, pourcentages, montants FCFA     C  seuils et durées
//   D  listes de choix métier            E  préfixes et formats de numérotation    F  noms de rôles décisionnels (cliquet existant, relu)
//   G  libellés d'organisation, contacts H  règles de calcul figées (barèmes, tranches, grilles)
//
// Ce qui est EXCLU d'office (et compté à part, pour qu'on sache ce qu'on n'a pas regardé) : les commentaires ; les fichiers ENGENDRÉS « ne pas éditer »
// (référentiels statiques tirés de la maquette : comptés UNE fois par fichier, famille R) ; les constantes techniques (tailles, couleurs, durées
// d'animation en ms/s, index) ; les citations datées dans un texte (« décision du 16/11/2026 ») ; les longs libellés d'interface ; les SEMENCES
// déclarées (défaut d'un paramètre de definitions.dart, constante `…Defaut` qu'il référence, collection semée par une fonction `semer…`/`graine…`).
// Une constante semée qui est AUSSI lue directement ailleurs (au lieu du paramètre ou de la collection) est retenue : elle duplique la semence.
//
// Le tri est HEURISTIQUE : chaque candidat porte un statut (`defaut` = défaut réel, sinon le motif d'exclusion) et une gravité proposée. Les faux
// positifs VÉRIFIÉS À LA MAIN vivent dans la table `ECARTES` (famille, chemin, motif de ligne, raison) : ils restent dans le JSON au statut
// `ecarte-main`. Le taux de faux positifs résiduel se mesure par échantillon (option --echantillon) ; il est donné dans
// docs/architecture/INVENTAIRE-VALEURS-EN-DUR.md, avec le plan de lots et la proposition de cliquet (base : --par-fichier).
//
// Usage depuis la racine :
//   node tools/baguidi/inventaire-en-dur.mjs                       synthèse MODULE × FAMILLE (défauts retenus) sur la sortie standard
//   node tools/baguidi/inventaire-en-dur.mjs --json chemin.json     + l'inventaire complet (candidats, statuts, gravités) en JSON
//   node tools/baguidi/inventaire-en-dur.mjs --liste B [--module m11] la liste des défauts retenus d'une famille (fichier:ligne, valeur, contexte)
//   node tools/baguidi/inventaire-en-dur.mjs --echantillon 30 --famille C [--graine 7]   un tirage reproductible pour la vérification à la main
//   node tools/baguidi/inventaire-en-dur.mjs --par-fichier          les comptes de défauts par fichier (base du cliquet « valeurs en dur »)
//   node tools/baguidi/inventaire-en-dur.mjs --cliquet --famille=B,H [--plafonds chemin.json] [--proposer]
//        LE CLIQUET (lot 1, 16/11/2026) : relance le balayage et ÉCHOUE (code 1) si, dans une famille surveillée, un fichier DÉPASSE son plafond (une valeur en dur
//        est apparue), passe SOUS son plafond sans que la ligne de base soit abaissée (la place libérée ne doit pas resservir), ou si un fichier toléré n'a pas de
//        MOTIF. Un fichier absent de la ligne de base a un plafond de zéro. Ligne de base : `tools/baguidi/valeurs-en-dur.plafonds.json` (familles → fichier →
//        {plafond, motif}). `--proposer` imprime la ligne de base mesurée (à recopier en gardant les motifs), sans rien écrire.
//        Famille E (préfixes de numérotation) : plafond ZÉRO partout depuis le lot 2 (fabrique du référentiel de numérotation) ; `--injecter=<chemin fictif>:<fichier>` ajoute un source
//        au balayage comme s'il vivait au chemin fictif (sonde : le cliquet doit mordre).
//   node tools/baguidi/inventaire-en-dur.mjs --cliquet --famille=A   échoue si une année en dur qui décide apparaît hors de la liste fermée (annees-tolerees.json)
// Lecture seule : le script n'écrit que le fichier demandé par --json. Importable (node --test) : `analyser`, `cliquet`, `lireToleres`.
import { readFileSync, readdirSync, statSync, existsSync, writeFileSync } from 'node:fs';
import { join, relative } from 'node:path';
import { pathToFileURL } from 'node:url';

const RACINE = new URL('../../', import.meta.url).pathname.replace(/\/$/, '');
const RACINES = [
  { dir: 'apps/poste/lib', ext: '.dart' },
  { dir: 'packages/domaine/lib', ext: '.dart' },
  { dir: 'packages/sync_dart/lib', ext: '.dart' },
  { dir: 'apps/mobile/lib', ext: '.dart' },
  { dir: 'apps/web/app', ext: '.php' },
  { dir: 'apps/web/config', ext: '.php' },
];
const EXCLUS_CHEMIN = /(\/test\/|_test\.dart$|\.g\.dart$|\.freezed\.dart$|\/generated\/|\/l10n\/)/;

// ---------------------------------------------------------------------------------------------------------------------------------------------
// 1. LEXIQUE : commentaires retirés, chaînes repérées (Dart : '…', "…", '''…''', r'…', interpolation ${…} ; PHP : '…', "…", //, #, /* */).
// Rend `code` (le source, commentaires et contenus de chaînes remplacés par des espaces, sauts de ligne conservés) et `chaines` [{debut, fin, texte}].
// ---------------------------------------------------------------------------------------------------------------------------------------------
function lexer(src, php) {
  const n = src.length;
  const code = src.split('');
  const chaines = [];
  const blanc = (a, b) => { for (let k = a; k < b; k++) if (code[k] !== '\n') code[k] = ' '; };
  const pile = []; // contextes d'interpolation : {quote, triple, raw, debut, prof}
  let prof = 0; // profondeur d'accolades en mode code
  let i = 0;
  // Lit une chaîne qui commence à i (guillemet ouvrant) ; rend l'indice après la chaîne, ou s'interrompt sur une interpolation.
  function lireChaine(debutLit, quote, triple, raw, depuis) {
    let k = depuis;
    while (k < n) {
      if (!raw && src[k] === '\\') { k += 2; continue; }
      if (triple ? src.startsWith(quote.repeat(3), k) : src[k] === quote) {
        const fin = k + (triple ? 3 : 1);
        return { fin, interpo: false };
      }
      if (!triple && src[k] === '\n' && !php) return { fin: k, interpo: false }; // chaîne non fermée : on s'arrête à la ligne
      if (!php && !raw && src[k] === '$' && src[k + 1] === '{') return { fin: k + 2, interpo: true };
      k++;
    }
    return { fin: n, interpo: false };
  }
  let chaineCourante = null; // {debut, quote, triple, raw}
  function enChaine(depuis) {
    const c = chaineCourante;
    const r = lireChaine(c.debut, c.quote, c.triple, c.raw, depuis);
    if (r.interpo) {
      pile.push({ ...c, prof });
      prof = 0;
      chaineCourante = null;
      return r.fin;
    }
    // chaîne terminée
    chaines.push({ debut: c.debut, fin: r.fin, texte: src.slice(c.debut, r.fin) });
    chaineCourante = null;
    return r.fin;
  }
  while (i < n) {
    if (chaineCourante) { i = enChaine(i); continue; }
    const ch = src[i];
    // commentaires
    if (ch === '/' && src[i + 1] === '/') { const e = src.indexOf('\n', i); const f = e < 0 ? n : e; blanc(i, f); i = f; continue; }
    if (php && ch === '#' && src[i + 1] !== '[') { const e = src.indexOf('\n', i); const f = e < 0 ? n : e; blanc(i, f); i = f; continue; }
    if (ch === '/' && src[i + 1] === '*') { const e = src.indexOf('*/', i + 2); const f = e < 0 ? n : e + 2; blanc(i, f); i = f; continue; }
    // retour d'interpolation
    if (ch === '{') { prof++; i++; continue; }
    if (ch === '}') {
      if (prof === 0 && pile.length) { const c = pile.pop(); prof = c.prof; chaineCourante = { debut: c.debut, quote: c.quote, triple: c.triple, raw: c.raw }; i = enChaine(i + 1); continue; }
      prof = Math.max(0, prof - 1); i++; continue;
    }
    // chaînes
    let raw = false; let j = i;
    if (!php && (ch === 'r' || ch === 'R') && (src[i + 1] === "'" || src[i + 1] === '"') && !/[\w$]/.test(src[i - 1] || '')) { raw = true; j = i + 1; }
    const q = src[j];
    if (q === "'" || q === '"') {
      const triple = !php && src.startsWith(q.repeat(3), j);
      chaineCourante = { debut: i, quote: q, triple, raw: raw || (php && q === "'") };
      i = enChaine(j + (triple ? 3 : 1));
      continue;
    }
    i++;
  }
  // blanchir les contenus de chaînes (guillemets gardés) — les interpolations le sont aussi : leur contenu est relu comme texte de chaîne
  for (const c of chaines) blanc(c.debut + 1, c.fin - 1);
  return { code: code.join(''), chaines };
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// 2. MODULES : le module se déduit du chemin ; un MODULE FONCTIONNEL réunit le poste (écrans) et le domaine (règles) du même métier.
// ---------------------------------------------------------------------------------------------------------------------------------------------
const DOMAINE_VERS_MODULE = {
  patients: 'M1', consultation: 'M2', imagerie: 'M2', specialites: 'M2', hospitalisation: 'M3', maternite: 'M4', labo: 'M5', stock: 'M6', achats: 'M7',
  caisse: 'M8', tarifs: 'M8', assurances: 'M9', rh: 'M10', paie: 'M11', comptabilite: 'M12', administration: 'M13', qualite: 'M13',
  securite: 'M14', acces: 'M14', droits: 'M14', mecef: 'MECEF', configuration: 'CFG', parametres: 'CFG', referentiels: 'CFG', validation: 'CFG',
  pilotage: 'PIL', tableaux_de_bord: 'DASH', tableaux: 'DASH', graphiques: 'DASH', rapports: 'RAP', documents: 'GED', impression: 'IMP',
  mere: 'MERE', sync: 'SYNC', mobile: 'MOBILE', assistant: 'ASSISTANT', import: 'IMPORT', sauvegarde: 'SAUVEGARDE', navigation: 'SOCLE', format: 'SOCLE', design: 'SOCLE',
};
function zoneEtModule(p) {
  let m;
  if ((m = p.match(/^apps\/poste\/lib\/modules\/([^/]+)\//))) {
    const z = m[1];
    const mod = /^m\d+$/.test(z) ? z.toUpperCase() : { cfg: 'CFG', mere: 'MERE', dash: 'DASH', pil: 'PIL', rap: 'RAP', ged: 'GED', imp: 'IMP', mecef: 'MECEF', auth: 'M14', rls: 'M14' }[z] || z.toUpperCase();
    return { zone: `poste/modules/${z}`, module: mod };
  }
  if ((m = p.match(/^apps\/poste\/lib\/([^/]+)\//))) {
    const z = m[1];
    const mod = { mere: 'MERE', sync: 'SYNC', impression: 'IMP', documents: 'GED', import: 'IMPORT' }[z] || 'SOCLE';
    return { zone: `poste/${z}`, module: mod };
  }
  if (p.startsWith('apps/poste/lib/')) return { zone: 'poste', module: 'SOCLE' };
  if ((m = p.match(/^packages\/domaine\/lib\/src\/([^/]+)\//))) return { zone: `domaine/${m[1]}`, module: DOMAINE_VERS_MODULE[m[1]] || m[1].toUpperCase() };
  if (p.startsWith('packages/domaine/lib/')) return { zone: 'domaine', module: 'SOCLE' };
  if (p.startsWith('packages/sync_dart/')) return { zone: 'sync_dart', module: 'SYNC' };
  if (p.startsWith('apps/mobile/')) return { zone: 'mobile', module: 'MOBILE' };
  if (p.startsWith('apps/web/config/')) return { zone: 'web/config', module: 'RELAIS' };
  if (p.startsWith('apps/web/')) return { zone: 'web/app', module: 'RELAIS' };
  return { zone: '?', module: '?' };
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// 3. CONTEXTES de mots-clés (sur la ligne de code, chaînes blanchies, plus le nom déclaré).
// ---------------------------------------------------------------------------------------------------------------------------------------------
const MOTS_TECHNIQUES = /\b(width|height|padding|margin|fontSize|size|iconSize|EdgeInsets|SizedBox|Radius|radius|elevation|flex|Color|Colors|opacity|alpha|milliseconds|microseconds|seconds|pixel|px|dpi|PdfPageFormat|offset|Offset|substring|padLeft|padRight|take|skip|sublist|maxLines|minLines|maxLength|letterSpacing|strokeWidth|thickness|spacing|runSpacing|indent|blurRadius|spreadRadius|BoxConstraints|maxWidth|minWidth|maxHeight|minHeight|extent|itemExtent|cacheExtent|zoom|scale|angle|rotation|curve|PdfColor|textScale|columnWidths|FixedColumnWidth|FlexColumnWidth|Alignment|Point|Rect|Size|crossAxisCount|childAspectRatio|mainAxis|crossAxis|toStringAsFixed|toRadixString|codeUnit|codeUnitAt|charCode|byte|bytes|Uint8List|buffer|chunk|port|timeout|Timeout|retry|tentatives|backoff|hash|sha|crc|bits|mask|0x)\b/;
const MOTS_TAUX = /(taux|pourcent|pct|percent|cnss|vps|\bits\b|\baib\b|tva|remise|marge|ristourne|commission|interet|intérêt|penalit|pénalit|majoration|cotis|prelev|prélèv|retenue|abattement|ticketModerateur|ticket_moderateur|patronal|ouvri)/i;
const MOTS_MONTANT = /(montant|prix|tarif|fcfa|\bcfa\b|prime|salaire|brut|\bnet\b|redevance|honoraire|plafond|ccib|amende|frais|cout\b|coût|caution|forfait|indemn|avance|solde|budget|recette|depense|dépense|ticket|amount|price|money\(|valeur|cotisation|patente|ortb|radio|tele\b|télé)/i;
const MOTS_DUREE = /(jour|jours|days|inDays|heure|heures|hours|inHours|minute|minutes|inMinutes|delai|délai|seuil|limite|alerte|peremption|péremption|retention|rétention|\bage\b|âge|semaine|anciennet|echeance|échéance|preavis|préavis|expir|validit|quota|\bmax|\bmin|duree|durée|periode|période|mois\b|annees|années|terme|\bsa\b|semaines|retard|delaiJours|nbJours|horizon|fenetre|fenêtre|tolerance|tolérance)/i;
const MOTS_LISTE_METIER = /(statut|etat|état|categor|catégor|motif|type|mode|axe|nature|famille|groupe|option|choix|liste|niveau|raison|origine|canal|sexe|issue|voie|unite|unité|methode|méthode|classe|qualite|qualité|service|secteur|priorit|gravit|urgence|decision|décision|resultat|résultat|conclusion|orientation|provenance|destination|situation|regime|régime|traitement|paiement|reglement|règlement|garantie|couverture|exclusion|pathologie|diagnostic|presentation|présentation|position|etape|étape|circuit|valeurs|items|libelles|libellés|codes|natures|types|motifs|statuts|etats|modes)/i;
const MOTS_LISTE_TECHNIQUE = /(colonne|cols\b|champ|fields|cles\b|clés|keys|entete|entête|headers|ordre|extension|mime|icone|icône|icon|police|font|route|table\b|tables|collection|index|tri\b|sort|format|mois\b|moisLabel|jours?Semaine|weekdays|months|alphabet|lettres|chiffres|caracteres|caractères|separ|séparat|regex|motif?s?Regex|pattern|ecrans|écrans|ecranIds|modules\b|manifeste|onglets|tabs|rubriques|sections|ordreAffichage|sql|pragma|json|csv|xlsx|pdf|svg|png|jpg|langue|locale|stopwords|motsVides|diacrit|accents|synonymes|mots\b|vocabulaire)/i;
const MOIS_FR = /^(janvier|février|fevrier|mars|avril|mai|juin|juillet|août|aout|septembre|octobre|novembre|décembre|decembre|janv\.?|févr\.?|avr\.?|juil\.?|sept\.?|oct\.?|nov\.?|déc\.?|lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche|lun\.?|mar\.?|mer\.?|jeu\.?|ven\.?|sam\.?|dim\.?)$/i;
const MOTS_GRAVITE_HAUTE = /(paiement|reglement|règlement|caisse|factur|tarif|prix|montant|tva|fiscal|aib|cnss|its|vps|ortb|impot|impôt|taxe|comptab|ecriture|écriture|compte|journal|assur|garantie|couverture|plafond|prime|salaire|paie|bulletin|diagnostic|patholog|medic|médic|traitement|posolog|dose|resultat|résultat|analyse|labo|borne|apgar|terme|partogr|transfus|sang|allerg|droit|acces|accès|role|rôle|geste|habilit|stock|peremption|péremption|mecef|avoir)/i;

// ---------------------------------------------------------------------------------------------------------------------------------------------
// 4. LES SEMENCES DÉCLARÉES : défauts de definitions.dart, identifiants qu'il référence, constantes lues par une fonction de semis.
// ---------------------------------------------------------------------------------------------------------------------------------------------
const DEFINITIONS = 'packages/domaine/lib/src/parametres/definitions.dart';

// ---------------------------------------------------------------------------------------------------------------------------------------------
// 5. LE CLIQUET DES RÔLES (famille F) : le détecteur et la table de tolérances de roles_en_dur_global_test.dart, relus tels quels.
// ---------------------------------------------------------------------------------------------------------------------------------------------
function lireCliquetRoles() {
  const t = readFileSync(join(RACINE, 'packages/domaine/test/roles_en_dur_global_test.dart'), 'utf8');
  const tol = new Map();
  let section = '';
  for (const l of t.split('\n')) {
    const s = l.match(/^\s*\/\/ --- (.+)$/);
    if (s) { section = s[1].replace(/[.:]\s*$/, ''); continue; }
    const m = l.match(/^\s*'([^']+)': \(sites: (\d+), motif: '((?:[^'\\]|\\.)*)'/);
    if (m) {
      const chemin = m[1].startsWith('../../') ? m[1].slice(6) : m[1].startsWith('../') ? 'packages/' + m[1].slice(3) : 'packages/domaine/' + m[1];
      tol.set(chemin, { sites: +m[2], motif: m[3].replace(/\\'/g, "'"), section });
    }
  }
  const rbac = JSON.parse(readFileSync(join(RACINE, 'packages/rbac/data/rbac.json'), 'utf8'));
  return { tol, roles: rbac.roles.map((r) => String(r.id)) };
}
function rolesEnDur(source, roles) {
  const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const alt = roles.map(esc).join('|');
  const index = /(?<=[\w\)\]\?!])\[\s*'[^']*'\s*\]/g;
  const formes = [
    new RegExp(`[=!]=\\s*'(${alt})'`, 'g'),
    new RegExp(`'(${alt})'\\s*[=!]=`, 'g'),
    new RegExp(`\\.contains\\(\\s*'(${alt})'\\s*\\)`, 'g'),
    new RegExp(`(?<=[\\[{,])\\s*'(${alt})'(?=\\s*[,\\]}])`, 'g'),
    new RegExp(`\\brole\\w*\\s*:\\s*'(${alt})'`, 'g'),
    new RegExp(`^\\s*'(${alt})'\\s*,?\\s*[\\]}]?[,;)]*\\s*$`, 'g'),
  ];
  const out = [];
  source.split(/\r?\n/).forEach((brute, i) => {
    if (brute.trimStart().startsWith('//')) return;
    const l = brute.replace(index, '');
    const vus = new Set();
    for (const f of formes) {
      f.lastIndex = 0;
      for (const m of l.matchAll(f)) {
        const debut = m.index + m[0].indexOf(`'${m[1]}'`);
        if (!vus.has(debut)) { vus.add(debut); out.push({ ligne: i + 1, role: m[1], texte: brute.trim() }); }
      }
    }
  });
  return out;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// 5 bis. LES FAUX POSITIFS ÉCARTÉS À LA MAIN (vérification du 16/11/2026). Chaque ligne : famille, motif de chemin, motif de la ligne (ou null =
// tout le fichier pour cette famille), raison. Ils restent dans le JSON avec le statut `ecarte-main` : on sait ce qui a été écarté, et pourquoi.
// Une ligne de code qui change sort d'elle-même de cette liste (le motif ne correspond plus) : le cliquet la verra comme un candidat neuf.
// ---------------------------------------------------------------------------------------------------------------------------------------------
const ECARTES = [
  // A — années
  ['A', /m12\/cpc_baseline\.dart$/, /'(Baseline financière|Imprimer le compte|Compte de résultat — exercice|TOTAL|Total|Montant|Chiffre d’affaires( mensuel)? 2025'|Résultat 2025|\$\{_cap|baseline-2025|2025 \(réel\)|\('Exercice', '2025'\))/, 'citation du classeur 2025 (baseline documentaire, données de démonstration)'],
  ['A', /registre_m12\.dart$/, null, 'identifiant d’écran'],
  ['A', /m12\/cpc_baseline\.dart$/, /\('Exercice', '2025'\)/, 'citation du classeur 2025 (baseline documentaire)'],
  ['A', /m12\/cpc_baseline\.dart$/, /'(Comparaison 2025 \/ \$\{c\.aujourdhui\.year\}|Chiffre d’affaires 2025 et \$annee)'/, 'citation du classeur 2025 comparée à l’année EN COURS (lot 0, E3835)'],
  ['A', /m5\/cat_valeurs\.dart$/, null, 'date de la validation écrite du biologiste (métadonnée de source)'],
  ['A', /m7\/besoins_receptions\.dart$/, null, 'exemple documentaire cité (circuit de la pièce réelle)'],
  ['A', /assurances\/ass_regles\.dart$/, /static const date/, 'date du document source du barème (métadonnée)'],
  ['A', /configuration\/cfa_regles\.dart$/, /dateEffet/, 'date d’effet de la note de service source (métadonnée)'],
  ['A', /import\/port_memoire\.dart$/, null, 'port mémoire des essais (jour figé de test, non lu en production)'],
  ['A', /impression\/organigramme\.dart$/, null, 'graine documentée de la fiche de l’organigramme'],
  ['A', /tarifs\/tarifs_decisions\.dart$/, null, 'semence documentée (décision de la Direction datée)'],
  ['A', /mecef\/ecrans\.dart$/, /rangSerieFactures/, 'compté en E (préfixe FN-2026-)'],
  // B — taux et montants
  ['B', /m2\/sp_repertoire\.dart$/, /9999/, 'valeur de tri (sentinelle)'],
  ['B', /documents\/doc_ocr\.dart$/, null, 'plafond technique du texte OCR'],
  ['B', /mecef\/montants\.dart$/, null, 'conversion en millièmes (format MECeF)'],
  ['B', /indicateurs_?clinique\.(dart|php)$/i, /(PLAFOND|_plafondEntier)/, 'garde technique contre le débordement d’entier'],
  ['B', /paie\/pai_moteur\.dart$/, /paiSeuilTele = /, 'semence de la fiche ORTB-PARAMETRES (PaiParametresOrtb.semence, lue en base)'],
  ['B', /tarifs\/tarifs_decisions\.dart$/, null, 'semence documentée (prix fixé par une note datée, semé au catalogue)'],
  // C — seuils et durées
  ['C', /(kit\/graphiques|domaine\/lib\/src\/graphiques\/|tableaux\/xlsx|impression\/pdf|documents\/ocr_poste|core\/plages_codes|mere\/mrb_journal|sms_mere|tableaux\/export_tableau|doc_ocr\.dart)/, null, 'constante technique (rendu, format de fichier, file interne, journal plafonné)'],
  ['C', /apps\/web\//, /(limite|MAX|lot|longueur_max|tentatives_max|PAR_HEURE|mesurerBlocs|\$max|PERIODES|DELAIS_MS|\$y = |Certificat TLS|plancher|conservation_jours)/, 'borne technique du relais (pagination, lot, réessais, tracé) — les réglages du relais sont déjà en base ou en configuration'],
  ['C', /./, /ajouterJours\([^,]+,\s*-\d+\)|subtract\(const Duration\(days: 6\)\)|add\(const Duration\(days: 6\)\)|Duration\(days: 7\)\);$|agDebutTexte\(|\* 10\) \/ 10|\* 1000\) \/ 10|List<int>\.filled\(12|[im] [<>]=? 12|mois < 6|champ\(_periode!, 176\)|styleLabo\(10|delaiMaxJours|numeroMecefSimule|astTolerance|inMinutes >= 60|showDatePicker|<< 11|shHeureMax|nb: 8|b\.jours <= 62|maxH = 12|365 \/ f\.jours|jours > 25|total \* 0\.2|^\? 5$|_delai\(int jours\)|seance|Timer\.periodic|_pauseApresTentative|allouerPlage|q\['limite'\]|journal\(\{int limite|for \(final j in \{30, 60/, 'plage d’affichage, semaine calendaire, arrondi, format ou garde technique'],
  ['C', /(sync\/config_smtp|cfg\/cfg_smtp|sync\/service_smtp|sync_dart\/lib\/src\/smtp|sync\/file_courriels|sync\/etat_sync)/, null, 'délai réseau, réessais ou format d’affichage (technique)'],
  ['C', /assistant\/ast_(reconnaissance|executeurs)\.dart$/, /Duration\(days: [67]\)/, 'semaine calendaire'],
  ['C', /rh\/regime_individuel\.dart$/, /days: 6/, 'semaine calendaire'],
  ['C', /(parametres\/parametres_clinique|securite\/verrou_secours|sync_dart\/lib\/src\/indicateurs_clinique|tarifs\/tarifs\.dart|assistant\/ast_conversation)/, /(Max = |<= 730|> 730|Max\b.*= \d)/, 'borne de validation d’un réglage (la valeur reste au paramètre)'],
  ['C', /shell\/recherche_globale\.dart$/, null, 'nombre de résultats affichés (faux doublon de paramètre)'],
  ['C', /m5\/res_comparatif\.dart$/, null, 'texte d’affichage'],
  ['C', /m7\/besoins_(commandes|expression)\.dart$/, /referenceSuivante/, 'largeur du numéro (comptée en E)'],
  ['C', /PurgerAudit\.php$/, /error\(/, 'message du même contrôle (compté une fois)'],
  ['C', /mere\/mrc_regles\.dart$/, null, 'nombre d’anomalies listées (technique)'],
  ['C', /cfg\/cft_tarifs\.dart$/, /tarPiecesRecentes/, 'fenêtre d’affichage des pièces récentes'],
  // D — listes
  ['D', /./, /etiquettes\s*:/, 'étiquettes d’un graphique (libellés d’affichage)'],
  ['D', /(core\/donnees_navigation|documents\/service_fichiers|donnees\/tarifs_poste|kit\/importer|cfg\/cfg_smtp|m1\/externe\.dart:1[0-9][0-9]|m1\/fiche\.dart|rha_personnel|rhb_evaluations|rhc_badges_modeles|pai_pieces|pai_tableau_bord|cpb_immobilisations\.dart|adm_registres|adm_vues|ag_agenda|ag_commun|ag_registres|cs_consultations|cs_pathologies|cs_prescriptions|img_galerie|hos_soins|cat_reactifs|cat_valeurs|besoins_expression|m8\/facturation|m9\/conventions|pil_gestion|rls_commun|rls_ecrans|centre_notifications|pieces_mises_de_cote|caisse\/avoir|cpc_exercice|doc_regles|format_fr|res_anteriorites|res_plages|sang_regles\.dart|mrb_regles|mrc_regles|mere\/sms|pai_moteur\.dart|parametres\/parametres|pat_releves|pil_tableaux|qualite\/qual_enquetes|rap_regles|rhc_regles\.dart|sec_exploitation|emplacements|stock\/stock\.dart|tarifs_sans_prix|mobile\/lib\/ui\/tournee|VueIndicateurs|ast_executeurs|ast_texte|impression\/identite|acc_connexion|cft_tarifs|m8\/caisse|m8\/commun|cs_moteur|ass_regles\.dart|prise_en_charge|remboursement|comptabilite\/aib|labo\/cat_regles|res_saisie|rha_regles\.dart)/, /(valeursInitiales|valeursCreation|initiale?s?\s*:|ctl\s*=|transformer|faux|droite|gains|retenues|children|options|modele|reels|noms|smtpDefauts|valeur\s*:|_libelleOrigine|_categorieDeRubrique|_typesImage|_libellesVues|_liensNotif|rlsPages|rlsRegles|rlsControles|ecritures|clBase|anBase|_unites|_dizaines|typesQualitatifs|_typesChoix|typesAccompagnement|catTypesAccompagnement|libellesTypeVariable|mrbEssentiels|mrbVide|mrcCategoriesSage|smsVariables|paiComptes|parFamilles|patMoments|lib\s*=|note\s*:|options|rapMentionsPied|rapCatalogueEtats|rapPeriodesRapport|rhcZonesBadge|_postes|final m = |final d = |emp|typesPerte|tarCauses|_libelles|CARTES|cibles|astAbreviations|defauts|accRegleMotDePasse|assUnitesPlafond|_unitesPlafond|motifsMoteurAvoir|aibDefinitions|typeCons|decisions|_categories|categories|_libellesNature|final s = |final r = |final res = |final att = |final nt = |final m = |eligible|'r' :|r = \[)/, 'fiche construite, contrôleurs, en-têtes, icônes, énumération d’états ou vocabulaire structurel'],
  ['D', /(pat_patients|labo\/sang_regles)\.dart$/, /(Groupes|sangGroupes)/, 'groupes sanguins ABO/Rh (normatif)'],
  ['D', /(jeux_import\.dart|rha_regles\.dart)$/, /(Célibataire|rhaSituations|liste\s*:)/, 'état civil (énumération normative)'],
  ['D', /achats\/besoins\.dart$/, /etapesBesoin/, 'énumération d’étapes du circuit'],
  ['D', /m2\/cs_pathologies\.dart$/, null, 'fiche construite'],
  ['D', /comptabilite\/cpb_gestion\.dart$/, /cpbFamillesBilanImmo/, 'références de la liasse SYSCOHADA (normatif)'],
  ['D', /configuration\/cfa_regles\.dart$/, /cfaVariablesMessage/, 'variables de gabarit d’un message (structurel)'],
  ['D', /(m10\/rhc_badges_modeles|m2\/sp_repertoire|m1\/externe|m8\/facturation)\.dart$/, /(_zones|_typesQuestion|_urgences|_naturesLigne)/, 'énumération structurelle (zones du badge, types de question, niveaux d’urgence, natures de ligne lues par la logique)'],
  ['D', /m10\/rhb_presences\.dart$/, /const lib = /, 'libellés des états de présence (énumération structurelle)'],
  ['D', /cfg\/cft_tarifs\.dart$/, /_etatsPrix/, 'libellés des états calculés d’un prix (énumération structurelle)'],
  ['D', /(documents\/service_fichiers|sync\/pieces_mises_de_cote)\.dart$/, null, 'arguments de commande système ou fiche construite'],
  ['D', /securite\/sec_exploitation\.dart$/, null, 'journal d’exploitation SIMULÉ (tirage à graine de la maquette)'],
  ['D', /m5\/cat_(reactifs|valeurs)\.dart$/, /ctl/, 'contrôleurs de formulaire'],
  ['D', /m4\/mat_registres\.dart$/, /(transformer|valeursInitiales|\? \{|: \{)/, 'noms de champs / fiche construite'],
  ['D', /m1\/externe\.dart$/, /ctl\b/, 'contrôleurs de formulaire'],
  // E — préfixes
  ['E', /./, /'(PLG|ACT|TAR|ANA)-\$\{?(nom|p\[)|PAA-\$\{switch|ECH-\$\{|AN-PROV-|PAIE-\$\{l\.periode\}/, 'identifiant technique interne'],
  // G — libellés d'organisation
  ['G', /bloc_avis_medical|bloc_regles\.dart/, /Procureur/, 'mention légale (RG-07 : avis du Procureur)'],
  ['G', /shell\/coque\.dart$/, null, 'nom de domaine du ruban (manifeste)'],
  ['G', /rapports\/rap_regles\.dart$/, null, 'identifiant de section d’un modèle de rapport (toléré au cliquet des rôles)'],
  ['G', /stock\/points\.dart$/, null, 'faux positif (texte formaté)'],
  // H — barèmes
  ['H', /hospitalisation\/hos_regles\.dart$/, /hosEchelles|HosEchelle/, 'graduations d’affichage de la feuille de température'],
  ['H', /m12\/cpb_feuillets\.dart$/, null, 'étiquettes de graphique'],
  ['H', /paie\/pai_moteur\.dart$/, /paiRedevances/, 'semence de la fiche ORTB-PARAMETRES (PaiParametresOrtb.semence, lue en base)'],
  ['H', /rh\/rhb_regles\.dart$/, /rhbPrimesOrigine/, 'graine UNIQUE de la grille NS 132 (collection `grillePrimes`, semée au jeu livré et versionnée) : repli du moteur et ordre des lignes du bulletin ; la seconde copie `paiPrimesNs132` est retirée (lot 1)'],
  // F — rôles : les entrées descriptives de `_tachesDef` (motif du cliquet : « jamais lu pour décider »)
  ['F', /consultation\/cs_moteur\.dart$/, /\(role: '(caissier|pharmacien|laborantin|infirmier|echographiste)'/, 'champ descriptif `role` des tâches d’aval (toléré au cliquet : jamais lu pour décider)'],
];
function ecarterALaMain(c) {
  for (const [f, rf, rl, motif] of ECARTES) {
    if (f !== c.famille || !rf.test(c.fichier)) continue;
    if (rl && !rl.test(c.contexte) && !rl.test(String(c.valeur))) continue;
    return motif;
  }
  return null;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// 6. LE BALAYAGE.
// ---------------------------------------------------------------------------------------------------------------------------------------------
function fichiers() {
  const out = [];
  const marche = (d, ext) => {
    if (!existsSync(d)) return;
    for (const f of readdirSync(d).sort()) {
      const p = join(d, f);
      const st = statSync(p);
      if (st.isDirectory()) marche(p, ext);
      else if (p.endsWith(ext)) out.push(relative(RACINE, p));
    }
  };
  for (const r of RACINES) marche(join(RACINE, r.dir), r.ext);
  return out.filter((p) => !EXCLUS_CHEMIN.test(p));
}

// Un fichier de DONNÉES DE DÉMONSTRATION écrit dans lib (en-tête « DÉMONSTRATION », « données fictives ») : exclu, compté une fois.
const estDemo = (src) => /D[ÉE]MONSTRATION|données fictives/.test(src.split('\n').slice(0, 3).join('\n'));
const estEngendre = (src) => {
  const tete = src.split('\n').slice(0, 5).join('\n');
  return /ENGENDR[ÉE]/i.test(tete) && /(ne pas [ée]diter|NE PAS [ÉE]DITER|relancer le script)/i.test(tete);
};

// Unités du calendrier et de l'informatique : multiplier ou diviser par elles est une CONVERSION, pas une règle.
const UNITES = new Set([7, 12, 24, 60, 365, 366, 1000, 1024, 3600, 60000, 86400, 3600000, 86400000, 1048576]);
// Une fonction ou une constante dont le NOM dit qu'elle sème, amorce ou porte un jeu de démonstration.
const RE_SEMIS_NOM = /(amorc|semer|semence|graine|seed|demo|démo|demonstration|jeu|exemple|fictif|peupl|initial|origine|reference|Reference)/i;
const RE_DEMO_NOM = /(amorc|demo|démo|demonstration|fictif|peupl|jeuDe|exemple)/i;
// Un nom qui désigne une MÉTADONNÉE DE SOURCE (référence, date de signature ou d'effet d'un document) : la trace d'une semence, pas une règle.
const RE_META_SOURCE = /(Reference|reference|DateEffet|DateSignature|dateSignature|ArreteLe|DateSemence|dateSemence|Source|source|Document|Arrete|ValideLe)$/;
const SENTINELLES = /^(0000-00-00|0001-01-01|9999-12-31|1970-01-01|1900-01-01)/;

// Déclaration englobante d'une ligne : la plus proche ligne de niveau 0 (fonction, constante, classe), et, dans une classe, le membre de niveau 2.
function englobantes(lignesCode) {
  const res = new Array(lignesCode.length);
  let top = { genre: '', nom: '', ligne: 0 };
  let membre = null;
  const decl = (t) => {
    let m;
    if ((m = t.match(/^(?:static\s+)?(?:const|final|var|late\s+final|late)\s+(?:[\w<>,?\s\[\]().]+?\s+)?([A-Za-z_$]\w*)\s*=(?!=)/))) return { genre: 'const', nom: m[1] };
    if ((m = t.match(/^(?:abstract\s+|sealed\s+|final\s+)?(?:class|enum|mixin|extension)\s+(\w+)/))) return { genre: 'class', nom: m[1] };
    if ((m = t.match(/^(?:static\s+|external\s+|factory\s+)*(?:[\w<>,?\s\[\]().]+?\s+)?(?:get\s+)?([A-Za-z_$]\w*)\s*(?:<[^>]*>)?\s*\(/))) return { genre: 'fn', nom: m[1] };
    if ((m = t.match(/^(?:static\s+)?(?:[\w<>,?\s\[\]().]+?\s+)get\s+([A-Za-z_$]\w*)/))) return { genre: 'fn', nom: m[1] };
    return null;
  };
  for (let i = 0; i < lignesCode.length; i++) {
    const l = lignesCode[i];
    if (/^[A-Za-z_@]/.test(l)) {
      const d = decl(l.replace(/^@\w+(\([^)]*\))?\s*/, ''));
      if (d) { top = { ...d, ligne: i + 1 }; membre = null; }
    } else if (/^ {2}[A-Za-z_]/.test(l) && top.genre === 'class') {
      const d = decl(l.trim());
      if (d) membre = { ...d, ligne: i + 1 };
    } else if (/^ {4}(public|private|protected|const|function|static)\b/.test(l)) { // PHP : membres de classe
      const t = l.trim().replace(/^(public|private|protected|static|final|readonly)\s+/g, '').replace(/^(public|private|protected|static|final|readonly)\s+/g, '');
      const m = t.match(/^(?:const\s+(?:\w+\s+)?([A-Z_]\w*)|function\s+(\w+)|(?:\??\w+\s+)?\$(\w+))/);
      if (m) membre = { genre: m[1] ? 'const' : m[2] ? 'fn' : 'const', nom: m[1] || m[2] || m[3], ligne: i + 1 };
    }
    res[i] = { top, membre };
  }
  return res;
}

export function analyser() {
  const { tol, roles } = lireCliquetRoles();
  const liste = fichiers();
  const sources = new Map(liste.map((p) => [p, readFileSync(join(RACINE, p), 'utf8')]));
  // --injecter=<chemin fictif>:<fichier> (sonde du cliquet) : un source lu ailleurs, balayé comme s'il vivait au chemin fictif.
  for (const a of process.argv.slice(2).filter((x) => x.startsWith('--injecter='))) {
    const v = a.slice('--injecter='.length);
    const i = v.indexOf(':');
    if (i <= 0) throw new Error(`--injecter attend <chemin fictif>:<fichier>, reçu « ${v} »`);
    const fictif = v.slice(0, i);
    sources.set(fictif, readFileSync(v.slice(i + 1), 'utf8'));
    liste.push(fictif);
  }
  const COLLECTIONS = new Set(existsSync(join(RACINE, 'apps/poste/assets/donnees/jeu')) ? readdirSync(join(RACINE, 'apps/poste/assets/donnees/jeu')).map((f) => f.replace(/\.json$/, '')) : []);

  // --- Pré-lecture : lexique, déclarations englobantes, fichiers engendrés, fichiers qui se déclarent SEMENCE dans leur en-tête.
  const pre = new Map();
  for (const [p, src] of sources) {
    const php = p.endsWith('.php');
    const engendre = !php && (estEngendre(src) || estDemo(src));
    const lx = engendre ? { code: src, chaines: [] } : lexer(src, php);
    const lignesCode = lx.code.split('\n');
    const tete = src.split('\n').slice(0, 12).join('\n');
    const fichierSemence = /(qui s[èe]me|est s[ée]m[ée]e?|la graine|GRAINE|SEMENCE|semence du|sème la collection|amorce la collection)/.test(tete);
    pre.set(p, { php, engendre, ...lx, lignesCode, encl: englobantes(lignesCode), fichierSemence });
  }
  const DEFSRC = sources.get(DEFINITIONS) || '';
  const identsDefinitions = new Set([...DEFSRC.matchAll(/\b([a-z][A-Za-z0-9_]{3,})\b/g)].map((m) => m[1]));
  const enSemis = (p, i) => {
    const e = pre.get(p).encl[i];
    if (!e) return false;
    const noms = [e.top.nom, e.membre?.nom].filter(Boolean).join(' ');
    return /(amorc|semer|semence|graine|seed|Semis|semis|DeBase|deBase|Origine|origine)/i.test(noms);
  };
  // Constantes de niveau 0 ou membres statiques, et leurs lectures (fichier, ligne) hors de la déclaration.
  const constantes = new Map(); // nom → {fichier, ligne}
  for (const [p, x] of pre) {
    x.encl.forEach((e, i) => {
      if (e.top.genre === 'const' && e.top.ligne === i + 1) constantes.set(e.top.nom, { fichier: p, ligne: i + 1 });
      if (e.membre && e.membre.genre === 'const' && e.membre.ligne === i + 1 && /static|const/.test(x.lignesCode[i])) constantes.set(e.membre.nom, { fichier: p, ligne: i + 1 });
    });
  }
  const lectures = new Map(); // nom → [{fichier, ligne, semis, repli}]
  const RE_IDENT = /\b([a-zA-Z_][A-Za-z0-9_]{3,})\b/g;
  for (const [p, x] of pre) {
    if (x.engendre) continue;
    x.lignesCode.forEach((l, i) => {
      for (const m of l.matchAll(RE_IDENT)) {
        const d = constantes.get(m[1]);
        if (!d) continue;
        const e = x.encl[i];
        if (d.fichier === p && (e.top.nom === m[1] || e.membre?.nom === m[1])) continue; // dans sa propre déclaration
        let a = lectures.get(m[1]);
        if (!a) lectures.set(m[1], (a = []));
        a.push({ fichier: p, ligne: i + 1, semis: enSemis(p, i) || p === DEFINITIONS, repli: /\?\?\s*$|\?[^:?]*:\s*$/.test(l.slice(0, m.index)) || /parametres\//.test(p) });
      }
    });
  }
  // Une constante est SEMÉE si une fonction de semis ou definitions.dart la lit, ou si son nom le dit ; elle DUPLIQUE la semence si elle est
  // AUSSI lue directement ailleurs (hors semis, hors repli « ?? »).
  const etatConstante = (nom) => {
    if (!nom) return { semee: false, direct: 0 };
    const ls = lectures.get(nom) || [];
    const semee = identsDefinitions.has(nom) || ls.some((x) => x.semis) || /(Defaut|Default|Semence|Graine|Seed|Origine|Seme|Semee|DeBase)\w*$/.test(nom) || /^(semence|graine|seed|defaut)/i.test(nom);
    const direct = ls.filter((x) => !x.semis && !x.repli).length;
    return { semee, direct, lectures: ls.length };
  };

  const candidats = [];
  const engendres = [];
  const rolesF = [];
  const lignesF = new Set();

  for (const [p, src] of sources) {
    const x = pre.get(p);
    const { zone, module } = zoneEtModule(p);
    if (!x.php) for (const r of rolesEnDur(src, roles)) { rolesF.push({ fichier: p, ...r, zone, module }); lignesF.add(`${p}:${r.ligne}`); }
    if (x.engendre) { engendres.push({ fichier: p, zone, module, nature: estDemo(src) ? 'démonstration' : 'engendré', lignes: src.split('\n').length, entete: src.split('\n').slice(0, 2).join(' ').replace(/^[\/\s]+/, '').slice(0, 220) }); continue; }
  }

  for (const [p, src] of sources) {
    const x = pre.get(p);
    if (x.engendre) continue;
    const { php, code, chaines, lignesCode, encl, fichierSemence } = x;
    const { zone, module } = zoneEtModule(p);
    const lignesSrc = src.split('\n');
    const debutsLigne = [0];
    for (let k = 0; k < src.length; k++) if (src[k] === '\n') debutsLigne.push(k + 1);
    const ligneDe = (pos) => { let lo = 0, hi = debutsLigne.length - 1; while (lo < hi) { const mid = (lo + hi + 1) >> 1; if (debutsLigne[mid] <= pos) lo = mid; else hi = mid - 1; } return lo + 1; };
    const couverts = [];
    const dansCouvert = (pos) => couverts.some(([a, b]) => pos >= a && pos < b);
    const contexteLigne = (l) => (lignesSrc[l - 1] || '').trim().slice(0, 220);
    // Nom qui gouverne une ligne : déclaration locale (const x = / nom: ), sinon le membre ou la déclaration englobante.
    const nomLocal = (l) => {
      for (let k = l; k >= Math.max(1, l - 6); k--) {
        const t = lignesCode[k - 1] || '';
        const m = t.match(/(?:const|final|static|var|late|\$)\s+(?:[\w<>,?\s\[\]]+\s+)?([A-Za-z_]\w*)\s*=(?!=)/) || t.match(/\b([A-Za-z_]\w*)\s*:\s*(?:const\s*)?(?:<[^>]*>\s*)?[\[{(]/) || t.match(/'([A-Za-z_]\w*)'\s*=>\s*[\[{]/);
        if (m) return m[1];
        if (k < l && /[;{]\s*$/.test(t)) break;
      }
      return '';
    };
    const englobant = (l) => encl[l - 1] || { top: { nom: '' }, membre: null };
    const nomGouvernant = (l) => { const e = englobant(l); return (e.membre && e.membre.genre === 'const' ? e.membre.nom : '') || (e.top.genre === 'const' ? e.top.nom : '') || ''; };
    const fonction = (l) => { const e = englobant(l); return [e.top.genre === 'fn' ? e.top.nom : '', e.membre?.genre === 'fn' ? e.membre.nom : ''].filter(Boolean).join('.'); };
    // Statut commun : semence/démo, doublon de semence, métadonnée de source, ou défaut.
    const statutDe = (l, nom) => {
      const fn = fonction(l);
      if (fn && RE_DEMO_NOM.test(fn)) return { statut: 'demo', motif: `dans la fonction de démonstration/amorçage « ${fn} »` };
      if (fn && /(amorc|semer|graine|seed|semence|DeBase|deBase)/i.test(fn)) return { statut: 'semence', motif: `dans la fonction de semis « ${fn} »` };
      const g = nomGouvernant(l) || nom;
      if (g && RE_META_SOURCE.test(g)) return { statut: 'meta-source', motif: `métadonnée de source « ${g} »` };
      const ec = etatConstante(g);
      if (g && ec.semee) {
        if (ec.direct > 0) return { statut: 'defaut', motif: `semence « ${g} » AUSSI lue directement (${ec.direct} lecture(s) hors semis)`, doublon: true };
        return { statut: 'semence', motif: `constante semée « ${g} » (lue par le semis ou definitions.dart, ou en repli « ?? »)` };
      }
      if (fichierSemence) return { statut: 'semence', motif: 'fichier déclaré SEMENCE dans son en-tête' };
      return { statut: 'defaut', motif: '' };
    };
    const ajouter = (c) => candidats.push({ fichier: p, zone, module, ...c });

    // --- Collections littérales ---------------------------------------------------------------------------------------------------------
    const collections = [];
    for (let k = 0; k < code.length; k++) {
      const ch = code[k];
      if (ch !== '[' && ch !== '{') continue;
      let a = k - 1; while (a >= 0 && /\s/.test(code[a])) a--;
      const avant = code[a] || '';
      const motAvant = code.slice(Math.max(0, a - 7), a + 1);
      if (ch === '[' && /[\w)\]?!]/.test(avant) && !/(const|return|in|yield|await|else|=>)$/.test(motAvant)) continue;
      if (ch === '{' && php) continue;
      if (ch === '{' && !(/[=:(,\[{>?]/.test(avant) || /(const|return|=>)$/.test(motAvant))) continue;
      let d = 0, e = k;
      for (; e < code.length; e++) { const c2 = code[e]; if (c2 === '[' || c2 === '{' || c2 === '(') d++; else if (c2 === ']' || c2 === '}' || c2 === ')') { d--; if (d === 0) break; } }
      if (e >= code.length) continue;
      const elements = [];
      let dd = 0, deb = k + 1;
      for (let y = k + 1; y <= e; y++) {
        const c2 = code[y];
        if (c2 === '[' || c2 === '{' || c2 === '(') dd++;
        else if (c2 === ']' || c2 === '}' || c2 === ')') { if (dd === 0) { elements.push([deb, y]); break; } dd--; }
        else if (c2 === ',' && dd === 0) { elements.push([deb, y]); deb = y + 1; }
      }
      const elts = elements.map(([u, v]) => ({ u, v, t: code.slice(u, v).trim(), s: src.slice(u, v).trim() })).filter((z) => z.t.length);
      collections.push({ debut: k, fin: e + 1, elts });
    }
    const valeurChaine = (z) => { const m = z.s.replace(/^(const\s+)?(OptionChamp)?\(\s*/, '').match(/^r?(['"])((?:\\.|(?!\1).)*)\1/s); return m ? m[2] : z.s; };
    const NUM = /(?<![\w.$#])-?\d+(?:\.\d+)?(?![\w.])/g;
    const LIT = /^(r?['"]\s*['"]|-?\d+(\.\d+)?|true|false|null)$/;

    // H — barèmes, tranches, grilles chiffrées.
    const RE_NOM_BAREME = /(bareme|barème|tranche|grille|taux|tarif|prime|seuil|echelle|échelle|ns13|its\b|ortb|redevance|cotis|indice|coef|palier|plafond|honoraire|montant|forfait|penalit|sanction|amende)/i;
    for (const c of collections) {
      if (dansCouvert(c.debut)) continue;
      const corps = code.slice(c.debut, c.fin);
      const nombres = [...corps.matchAll(NUM)].map((m) => +m[0]).filter((v) => !(v >= 0 && v <= 2));
      if (nombres.length < 3) continue;
      const l = ligneDe(c.debut);
      const nom = nomLocal(l) || nomGouvernant(l);
      const ctor = c.elts.filter((z) => /^(const\s+)?[A-Z]\w*\s*\(/.test(z.t) && (z.t.match(NUM) || []).length >= 2).length;
      const metier = nombres.some((v) => v >= 100 || !Number.isInteger(v));
      const corpsSrc = src.slice(c.debut, c.fin);
      if (MOTS_TECHNIQUES.test(corps) || /0x[0-9a-f]|#[0-9a-f]{6}|graduation/i.test(corpsSrc)) continue;
      if (!((RE_NOM_BAREME.test(nom) && metier) || (ctor >= 3 && metier && RE_NOM_BAREME.test(nom + ' ' + corps.slice(0, 80))))) continue;
      couverts.push([c.debut, c.fin]);
      const st = statutDe(l, nom);
      ajouter({ famille: 'H', ligne: l, nom, valeur: `${nom || '(anonyme)'} : ${nombres.length} valeurs (${nombres.slice(0, 6).join(', ')}${nombres.length > 6 ? '…' : ''})`, contexte: contexteLigne(l), ...st, gravite: 'haute' });
    }

    // D — listes de choix. Une liste ouverte (motifs, catégories, services, modes de paiement…) est un défaut ; une énumération d'ÉTATS d'un circuit
    // (statuts, rangs, étapes) est STRUCTURELLE : la logique en dépend, elle ne se rend pas administrable sans code (seuls ses libellés le pourraient).
    const RE_LISTE_OUVERTE = /(mode|motif|categor|catégor|type(?!s?Variable)|nature|service|secteur|specialit|spécialit|moyen|garantie|exclu|produit|technique|pathologie|antecedent|antécédent|aptitude|option|choix|famille|groupe|origine|provenance|canal|filigrane|unite|unité|document|piece|pièce|prestation|examen|analyse|acte|soin|checklist|evenement|événement|raison|orientation|issue|voie|presentation|position|risque|allergie|vaccin|methode|méthode|banque|assureur|fournisseur|poste|fonction|qualite|qualité|niveau|priorit|urgence|zone|lieu|salle|chambre)/i;
    const RE_ETATS = /(statut|etat|état|rang|etape|étape|circuit|cycle|transition|aval|amont|suivant|precedent|ordre|phase|refus|code|erreur|cle|clé)/i;
    const pris = [];
    for (const c of collections) {
      if (dansCouvert(c.debut)) continue;
      if (p === DEFINITIONS) continue;
      // Une option de liste déroulante (`OptionChamp('code', 'Libellé')`) ou un n-uplet de chaînes (`('mtn', 'MTN Mobile Money', 'smartphone')`) compte comme une chaîne.
      const estOption = (z) => /^(const\s+)?(OptionChamp)?\(\s*r?['"]\s*['"]\s*(,\s*r?['"]\s*['"]\s*){0,3}(,\s*\w+\s*:[^,()]*)*,?\s*\)$/.test(z.t.replace(/\s+/g, ' '));
      const chs = c.elts.filter((z) => /^r?['"]\s*['"]$/.test(z.t.replace(/\s+/g, '')) || estOption(z));
      const paires = c.elts.filter((z) => { const m = z.t.replace(/\s+/g, ' ').match(/^r?['"]\s*['"]\s*:\s*(.*)$/); return m && LIT.test(m[1].replace(/\s+/g, '')); });
      const pairesChaine = paires.filter((z) => /:\s*r?['"]\s*['"]$/.test(z.t.replace(/\s+/g, ' ')));
      const nCh = chs.length + paires.length;
      if (nCh < 3 || nCh / c.elts.length < 0.6) continue;
      const l = ligneDe(c.debut);
      const nom = nomLocal(l) || nomGouvernant(l);
      const valeurs = [...chs, ...paires].map(valeurChaine);
      const libelles = pairesChaine.map((z) => { const m = z.s.match(/:\s*r?(['"])((?:\\.|(?!\1).)*)\1/s); return m ? m[2] : ''; }).filter(Boolean);
      const ctxt = (lignesCode[l - 1] || '') + ' ' + nom;
      const avantC = code.slice(Math.max(0, c.debut - 40), c.debut);
      const N = valeurs.length;
      const part = (f) => valeurs.filter(f).length / N;
      const codes = part((v) => /^[a-z0-9_]+$/.test(v) || /^[A-Z0-9_]+$/.test(v)) >= 0.7;
      const enregistrement = paires.length >= 2 && (paires.length - pairesChaine.length) / paires.length >= 0.4; // {'heure': 0, 'etat': 'x', 'vivant': true}
      let statut = 'defaut', motif = '';
      if (part((v) => MOIS_FR.test(v)) >= 0.6) { statut = 'technique'; motif = 'calendrier (mois, jours)'; }
      else if (part((v) => roles.includes(v)) >= 0.6) { statut = 'famille-F'; motif = 'liste de rôles : relève du cliquet des rôles'; }
      else if (part((v) => COLLECTIONS.has(v)) >= 0.5) { statut = 'technique'; motif = 'noms de collections'; }
      else if (part((v) => /^m\d+-|^cfg-|^dash-|^hub-|^pil-|^rap-|^mere-|^ged-|^imp-|^mecef-/.test(v)) >= 0.5) { statut = 'technique'; motif = 'identifiants d’écrans (manifeste)'; }
      else if (part((v) => /^[a-z]+[A-Z]\w*$/.test(v) || /^_\w+$/.test(v)) >= 0.5) { statut = 'technique'; motif = 'noms de champs'; }
      else if (part((v) => /^\d{2,8}$/.test(v)) >= 0.6) { statut = 'technique'; motif = 'numéros de comptes (plan SYSCOHADA, normatif)'; }
      else if (part((v) => /^[A-Z][A-Z0-9]*_[A-Z0-9_]+$/.test(v) || /^[A-Z]{1,3}\d{1,4}$/.test(v)) >= 0.6) { statut = 'technique'; motif = 'codes de refus, références de liasse ou identifiants internes'; }
      else if (part((v) => /^-{1,2}\w|^\\x|^%|^\.\w+$|^[\w-]+\/[\w.+-]+$|^\W+$/.test(v)) >= 0.5) { statut = 'technique'; motif = 'arguments, extensions, types MIME ou signatures'; }
      else if (part((v) => v.split(/\s+/).length > 8) >= 0.5) { statut = 'libelle'; motif = 'textes d’interface (phrases)'; }
      else if (enregistrement) { statut = 'technique'; motif = 'fiche construite (clés de champ, valeurs initiales)'; }
      else if (part((v) => v.includes('${') || v.trim() === '') >= 0.5) { statut = 'technique'; motif = 'chaînes composées (interpolations)'; }
      else if (paires.length >= 3 && part((v) => /^[a-z][a-zA-Z0-9_]*$/.test(v)) >= 0.8 && (libelles.length < paires.length * 0.6 || libelles.filter((x) => /^[A-ZÀ-Ý]|\s/.test(x)).length < libelles.length * 0.5)) { statut = 'technique'; motif = 'fiche construite (clés de champ)'; }
      else if (chs.length >= 3 && !paires.length && part((v) => /^[a-z][a-zA-Z0-9]*$/.test(v)) >= 0.8 && !/^\s*(static\s+)?(const|final)\b/.test(lignesCode[l - 1] || '') && /[(,:]\s*(const\s*)?$/.test(avantC)) { statut = 'technique'; motif = 'noms de champs passés en argument'; }
      else if (part((v) => roles.includes(v) || /^(medecin|sage_femme|infirmier|aide_soignant|tsl|caissiere|accueil|chirurgien|anesthesiste|biologiste|pharmacien|surveillant|echographiste|comptable|daf|dm)$/.test(v)) >= 0.7 && tol.has(p)) { statut = 'famille-F'; motif = 'liste de fonctions tolérée au cliquet des rôles (axe FONCTION)'; }
      else if (MOTS_LISTE_TECHNIQUE.test(nom)) { statut = 'technique'; motif = `nom technique « ${nom} »`; }
      else if (/(reconnaissance|vocabulaire|synonymes|diacritiques|recherche|ast_catalogue|accord\.dart)/.test(p)) { statut = 'technique'; motif = 'vocabulaire de recherche ou d’accord grammatical'; }
      else if (/(children|TableauAst|entetes|colonnes|header)\s*:?\s*[\[(]?\s*$/.test(avantC) || /\bin\s+(const\s+)?$/.test(avantC)) { statut = 'incertain'; motif = 'liste parcourue pour l’affichage (en-têtes, boucle)'; }
      else if (php && p.startsWith('apps/web/config/')) { statut = 'technique'; motif = 'configuration du relais (Laravel)'; }
      else if (/^(cartouche|kpis|children|conv|d|c|lignes|entetes|colonnes|en_?tetes)$/.test(nom)) { statut = 'libelle'; motif = `en-têtes ou cartouche d’une pièce imprimée (« ${nom} »)`; }
      else if (!nom && !/(options|choix|valeurs|items)\s*:/.test(lignesCode.slice(Math.max(0, l - 2), l).join(' '))) { statut = 'incertain'; motif = 'liste anonyme (en-têtes, textes, boucle d’affichage)'; }
      else if (part((v) => /^(valide|validee?|en_attente|en_cours|rejetee?|refusee?|brouillon|actif|archive|clos|cloture|annulee?|plus90|30a90|moins30|soumis|transmise?|livree?)$/.test(v)) >= 0.6) { statut = 'structurel'; motif = 'codes d’états (énumération structurelle)'; }
      else if (/FiltreTableau|RhbFiltre|filtre/i.test(lignesCode.slice(Math.max(0, l - 3), l).join(' ')) || part((v) => /^(tous|toutes|Tous|Toutes|)$/.test(v)) > 0) { statut = 'incertain'; motif = 'options d’un FILTRE d’écran (affichage)'; }
      else if (/(Demo|Exemple|Simulateur|Fictif)/.test(nom)) { statut = 'demo'; motif = `nom de démonstration « ${nom} »`; }
      else if (codes && !RE_LISTE_OUVERTE.test(nom) && (RE_ETATS.test(nom) || !libelles.length)) { statut = 'structurel'; motif = 'énumération d’états ou de codes dont la logique dépend'; }
      else if (!nom && !MOTS_LISTE_METIER.test(ctxt)) { statut = 'incertain'; motif = 'liste anonyme sans nom métier'; }
      if (statut === 'defaut') { const st = statutDe(l, nom); statut = st.statut; motif = st.motif; }
      couverts.push([c.debut, c.fin]);
      const sous = codes ? (libelles.length ? 'énumération codée (code → libellé)' : 'énumération codée') : 'liste de libellés';
      const cand = {
        famille: 'D', sous, ligne: l, nom, valeur: `${nom || '(anonyme)'} : [${valeurs.slice(0, 5).map((v) => v.slice(0, 30)).join(' | ')}${N > 5 ? ' …' : ''}] (${N})`,
        contexte: contexteLigne(l), statut, motif,
        gravite: MOTS_GRAVITE_HAUTE.test(nom + ' ' + valeurs.join(' ') + ' ' + libelles.join(' ')) ? 'haute' : codes && !RE_LISTE_OUVERTE.test(nom) ? 'basse' : 'moyenne',
        _debut: c.debut, _fin: c.fin,
      };
      pris.push(cand);
    }
    // Des fiches SŒURS (les lignes d'un même tableau de fiches) ne font qu'UN site : on les rassemble sur la ligne du tableau parent.
    const parentDe = (cand) => { let best = null; for (const c of collections) if (c.debut < cand._debut && c.fin > cand._fin && (!best || c.debut > best.debut)) best = c; return best; };
    const groupes = new Map();
    for (const cand of pris) { const par = parentDe(cand); const k = par && cand.statut === 'defaut' ? par.debut : `seul-${cand._debut}`; const g = groupes.get(k) || []; g.push(cand); groupes.set(k, g); }
    for (const [k, g] of groupes) {
      if (g.length >= 2 && typeof k === 'number') {
        const l = ligneDe(k);
        const nom = nomLocal(l) || nomGouvernant(l) || g[0].nom;
        const st = statutDe(l, nom);
        const corps = code.slice(k, g[g.length - 1]._fin);
        const chiffres = [...corps.matchAll(NUM)].map((m) => +m[0]).filter((v) => v >= 100 || !Number.isInteger(v));
        const bareme = chiffres.length >= 3 && /(taux|plafond|montant|prix|tarif|prime|seuil)/i.test(src.slice(k, g[g.length - 1]._fin));
        ajouter({ famille: bareme ? 'H' : 'D', sous: bareme ? 'grille en fiches' : 'tableau de fiches', ligne: l, nom, valeur: `${nom || '(anonyme)'} : ${g.length} fiches (${g[0].valeur.replace(/^[^:]*: /, '').slice(0, 80)})`, contexte: contexteLigne(l), ...st, gravite: bareme ? 'haute' : g.some((x) => x.gravite === 'haute') ? 'haute' : 'moyenne' });
      } else for (const cand of g) { delete cand._debut; delete cand._fin; ajouter(cand); }
    }

    // --- Nombres hors chaînes (A, B, C) ---------------------------------------------------------------------------------------------------
    lignesCode.forEach((lc, idx) => {
      const l = idx + 1;
      if (!/\d/.test(lc)) return;
      if (/^\s*(import|export|library|part|use|namespace)\b/.test(lc)) return;
      const nom = nomLocal(l);
      const ctx = lc + ' ' + nom;
      const debutL = debutsLigne[idx];
      const exemple = /\b(exemple|indicatif|hint|hintText|placeholder|aide)\s*:/.test(lc);
      for (const m of lc.matchAll(NUM)) {
        const pos = debutL + m.index;
        if (dansCouvert(pos)) continue;
        const brut = m[0];
        const v = +brut;
        const apres = lc.slice(m.index + brut.length, m.index + brut.length + 14);
        const avant = lc.slice(Math.max(0, m.index - 40), m.index);
        if (/[\w$]$/.test(avant)) continue;
        if (/\[\s*$/.test(avant) && /^\s*\]/.test(apres)) continue;
        const arith = /[*\/%]\s*$/.test(avant) || /^\s*[*\/~%]/.test(apres) || /<<|>>/.test(avant.slice(-4) + apres.slice(0, 4));
        const boucle = /\b\w+\s*<=?\s*$/.test(avant) && /\bfor\s*\(/.test(lc);
        const calendrier = /DateTime(\.utc)?\(/.test(lc) || /\b(mois|month|jour|day|heure|hour|minute)\s*[<>]=?\s*$/.test(avant) && [11, 12, 23, 24, 28, 29, 30, 31, 59, 60].includes(v) || /(semaine|hebdo|mensuel|trimest|semest|annuel|annee|année|quinzaine|'mois', 'Mois')/i.test(lignesSrc[idx]) && [7, 14, 15, 28, 30, 31, 90, 91, 92, 180, 182, 183, 365, 366].includes(v);
        const generateur = /\b(rnd|alea|aléa|_entre|entre)\s*[(,]/.test(lc) || /Random\(/.test(lc);
        const parametreTechnique = /\b(limite|limit|lignes|maxScale|minScale|take|nbMax|top|premiers|precision|décimales|decimales)\s*[:=]\s*$/.test(avant) || /\.(group|length|substring|padLeft|elementAt)\b/.test(lc) || /\blength\s*[<>=!]=?\s*$/.test(avant);
        const technique = MOTS_TECHNIQUES.test(lc) || /Duration\(\s*(milliseconds|microseconds|seconds)\s*:/.test(lc) || /\b(hauteur|largeur|trou|marge|horizontal|vertical|circular|Graphique\w*|colonnes|police|taille[A-Z]?\w*|rayon|epaisseur|épaisseur|_w[A-Z]\w*)\b/.test(lc) || /\b(refuser|abort|response|status|statusCode|json)\s*\(\s*$/.test(avant) || /return\s*\(\s*$/.test(avant);
        // A — année littérale
        if (Number.isInteger(v) && v >= 2024 && v <= 2030) {
          if (exemple) { ajouter({ famille: 'A', ligne: l, valeur: brut, nom, contexte: contexteLigne(l), statut: 'exemple', motif: 'exemple d’aide à la saisie', gravite: 'basse' }); continue; }
          const st = statutDe(l, nom);
          ajouter({ famille: 'A', ligne: l, valeur: brut, nom, contexte: contexteLigne(l), ...st, gravite: MOTS_GRAVITE_HAUTE.test(ctx + ' ' + p) ? 'haute' : 'moyenne' });
          continue;
        }
        if (v >= -2 && v <= 2 && Number.isInteger(v)) continue;
        if (exemple) continue;
        if (calendrier || generateur || parametreTechnique) continue;
        if (UNITES.has(Math.abs(v)) && (arith || boucle)) continue;
        if (boucle && v <= 12) continue;
        // B — taux
        const suivi100 = /^\s*\/\s*100(?![\d.])/.test(apres);
        const estTaux = (!Number.isInteger(v) && Math.abs(v) < 100 && MOTS_TAUX.test(ctx)) || (suivi100 && v !== 100 && MOTS_TAUX.test(ctx)) || (MOTS_TAUX.test(nom) && v < 100 && /=\s*$/.test(avant));
        if (estTaux && !technique) {
          ajouter({ famille: 'B', sous: 'taux', ligne: l, valeur: brut, nom, contexte: contexteLigne(l), ...statutDe(l, nom), gravite: 'haute' });
          continue;
        }
        if (v === 100 || v === 10000 && arith) continue;
        // B — montants (FCFA)
        if (Number.isInteger(v) && v >= 100 && MOTS_MONTANT.test(ctx) && !technique && !/(jour|heure|minute|delai|délai|duree|durée|limite|lignes|taille|longueur|nb[A-Z]|age|âge)/i.test(nom)) {
          ajouter({ famille: 'B', sous: 'montant', ligne: l, valeur: brut, nom, contexte: contexteLigne(l), ...statutDe(l, nom), gravite: 'haute' });
          continue;
        }
        // C — seuils et durées
        if (technique || !Number.isInteger(v) || Math.abs(v) < 3) continue;
        const duree = /Duration\(\s*(days|hours|minutes)\s*:/.test(lc) || /\.(inDays|inHours|inMinutes)\b/.test(lc);
        const borne = /\b(min|max|minimum|maximum)\s*:\s*$/.test(avant);
        if (duree || MOTS_DUREE.test(ctx) || borne) {
          const st = statutDe(l, nom);
          ajouter({ famille: 'C', sous: borne ? 'borne de saisie' : duree ? 'durée' : 'seuil', ligne: l, valeur: brut, nom, contexte: contexteLigne(l), ...st, gravite: MOTS_GRAVITE_HAUTE.test(ctx + ' ' + p) ? 'haute' : 'moyenne' });
        }
      }
    });

    // --- Chaînes (A, E, G) ---------------------------------------------------------------------------------------------------------------
    for (const c of chaines) {
      if (dansCouvert(c.debut)) continue;
      const m = c.texte.match(/^r?(['"]{1,3})([\s\S]*)\1$/);
      const t = m ? m[2] : c.texte.slice(1, -1);
      if (!t || !t.trim()) continue;
      const l = ligneDe(c.debut);
      const lc = lignesCode[l - 1] || '';
      const nom = nomLocal(l);
      const mots = t.trim().split(/\s+/).length;
      const avantCh = src.slice(Math.max(0, c.debut - 40), c.debut);
      const apresCh = src.slice(c.fin, c.fin + 25);
      const compare = /([=!]==?|\bcase)\s*$/.test(avantCh) || /^\s*[=!]==?/.test(apresCh) || /(\.contains|startsWith|endsWith|in_array)\(\s*$/.test(avantCh);
      const exemple = /\b(exemple|indicatif|hint|hintText|placeholder|aide)\s*:\s*$/.test(avantCh);
      const cle = (/^\s*:/.test(apresCh) && !/\?[^:]*$/.test(avantCh)) || /\[\s*$/.test(avantCh);
      // E — préfixes de numérotation
      const prefixe = /^[A-Z][A-Z0-9]{0,7}(?:-[A-Z0-9]{1,8})*[-\/]$/.test(t) || /^[A-Z][A-Z0-9]{0,7}(?:-[A-Z0-9]{1,8})*-\$/.test(t) || /^[A-Z][A-Z0-9]{1,7}(?:-20\d\d)?-(?:\$\{|\$\w)/.test(t);
      if (prefixe && !cle) {
        const annee = /20(2[4-9]|30)/.test(t);
        let statut = 'defaut', motif = 'préfixe de pièce visible';
        if (/^(A|B|AB|O)-$/.test(t)) { statut = 'technique'; motif = 'groupe sanguin'; }
        else if (/\$\{?(sha|hexAlea|maintenant\.millis|magasin\.horloge|_maintenant|utilisateurId|compte\[|cible|etape|id\b|v\.id|r\.id|rem\.id|etiquette|codeCnss|iso\(|profil\.)/.test(t) || /^(PROV|SEC|OCQ|OCR|FIC|DDR|VRF|VDP|MES|SAT|BK|POSTE|IMPORT|SIGH)-/.test(t)) { statut = 'technique'; motif = 'identifiant technique interne (ni pièce ni numéro lu par un agent)'; }
        else if (exemple) { statut = 'exemple'; motif = 'exemple d’aide à la saisie'; }
        else { const st = statutDe(l, nom); if (st.statut !== 'defaut') { statut = st.statut; motif = st.motif; } }
        ajouter({ famille: 'E', ligne: l, valeur: t.slice(0, 50), nom, contexte: contexteLigne(l), statut, motif, annee, gravite: annee ? 'haute' : 'moyenne' });
        continue;
      }
      // A — dates et années dans une chaîne
      const tt = t.trim();
      const iso = /^\d{4}-\d{2}-\d{2}(T[\d:.]+Z?)?$/.test(tt);
      const anneeSeule = /^(20(2[4-9]|30))$/.test(tt);
      const annee = /(?<![\d\w])20(2[4-9]|30)(?![\d])/.test(t) || /(?<=[a-z])20(2[4-9]|30)\b/.test(t);
      if (iso || anneeSeule || annee) {
        let statut = 'defaut', motif = '';
        if (SENTINELLES.test(tt)) { statut = 'technique'; motif = 'date sentinelle (bornes de tri)'; }
        else if (exemple) { statut = 'exemple'; motif = 'exemple d’aide à la saisie'; }
        else if (/\b(NS|N\.S\.)\s*(n°\s*)?\d+\/|\/CBG\/|\/CNT\//.test(t)) { statut = 'citation'; motif = 'référence d’un document (note de service)'; }
        else if (!iso && !anneeSeule && mots >= 4 && /\d{1,2}\/\d{1,2}\/20\d\d|\d{1,2}(er)? (janvier|février|mars|avril|mai|juin|juillet|août|septembre|octobre|novembre|décembre) 20\d\d|(décision|arbitrage|réunion|note|rapport|lot|vague|CDCT|depuis|arrêté|validée?|source)/i.test(t)) { statut = 'citation'; motif = 'citation datée dans un texte'; }
        else if (mots > 10) { statut = 'libelle'; motif = 'long libellé'; }
        else { const st = statutDe(l, nom); statut = st.statut; motif = st.motif; }
        ajouter({ famille: 'A', sous: iso ? 'date ISO' : anneeSeule ? 'année' : 'année dans un libellé', ligne: l, valeur: t.slice(0, 60), nom, contexte: contexteLigne(l), statut, motif, gravite: compare || iso || anneeSeule ? (MOTS_GRAVITE_HAUTE.test(lc + nom + p) ? 'haute' : 'moyenne') : 'basse' });
        continue;
      }
      // G — contacts et libellés d'organisation
      if (lignesF.has(`${p}:${l}`)) continue;
      const mail = /[\w.+-]+@[\w-]+\.[a-z]{2,}/i.test(t);
      const url = /https?:\/\/\S|www\.\S|\b[\w-]+\.(com|bj|org|net|fr|africa|io)\b/.test(t);
      const tel = /(\+?229[\s.]?)?(?<!\d)\d{2}([\s.]\d{2}){3,4}(?!\d)/.test(t) || /\+229\s?\d{8,10}/.test(t);
      const bp = /\bB\.?P\.?\s*\d+\b/.test(t);
      const FONCTIONS = /^(la |le |l['’]|les |au |du )?(direct(eur|rice)( g[ée]n[ée]ral(e)?| m[ée]dical| administrati(f|ve)( et financi(er|ère))?)?|daf|surveillant(e)?( g[ée]n[ée]ral(e)?)?|major|chef( de service)?|comptable|caissi[eè]re?(-dispensatrice)?|pharmacien(ne)?|biologiste( m[ée]dical)?|m[ée]decin( chef| traitant)?|infirmi(er|ère)( g[ée]n[ée]ral)?|sage-femme( major)?|gestionnaire( de stock)?|magasinier|assistant(e)?( de direction| comptable)?|r[ée]ceptionniste|secr[ée]taire|ambulancier|aide-soignant(e)?|technicien(ne)?( d['’][ée]chographie| de laboratoire)?|[ée]chographiste|chirurgien|anesth[ée]siste|promoteur|g[ée]rant|responsable (financier|logistique|administratif))$/i;
      const org = FONCTIONS.test(tt);
      const etab = /\b(CHU|CHD|CNHU|CHUD|Hôpital|Hopital|Centre de santé|Zone sanitaire|Polyclinique|Ministère|Ministere|DDS|Préfecture|Prefecture|Mairie|Tribunal|Commissariat|Gendarmerie|Sapeurs|SAMU|Procureur)\b/.test(t) && mots <= 8;
      const libelleService = /^[A-ZÉ][\wéèêàçôûî'’ -]{2,40}$/.test(tt) && /^(Service|Unité|Bloc|Salle|Pavillon|Guichet|Bureau|Magasin|Pharmacie|Laboratoire|Maternité|Consultation|Hospitalisation|Échographie|Imagerie|Urgences?|Pédiatrie|Chirurgie|Radiologie|Direction|Accueil|Réception|Caisse|Administration|Finance|Logistique)\b/.test(tt) && mots <= 4;
      const fonctionCode = /^(medecin|sage_femme|infirmier|comptable|chirurgien|anesthesiste|biologiste|pharmacien|surveillant|echographiste|aide_soignant|daf|dm)$/.test(tt);
      let sorte = '';
      if (mail) sorte = 'courriel'; else if (url) sorte = 'domaine'; else if (tel) sorte = 'téléphone'; else if (bp) sorte = 'adresse';
      else if (etab) sorte = 'établissement'; else if (org) sorte = 'poste/fonction (libellé)'; else if (libelleService && compare) sorte = 'service (libellé comparé)';
      else if (fonctionCode && compare) sorte = 'fonction (code comparé)';
      if (!sorte) continue;
      let statut = 'defaut', motif = '';
      const local = /localhost|127\.0\.0\.1|192\.168\.|example\.(com|org)|exemple\.|\.test\b|schemas\.|w3\.org|openxmlformats|xmlns|purl\.org|dart\.dev|flutter\.dev|pub\.dev|laravel\.com|github\.com|php\.net|mozilla|googleapis|apple\.com|microsoft\.com|amazonaws|your-account|^https?:\/\/(\$|\{)|^https?:\/\/$|^https:\/\/\$/i.test(t);
      if (local) { statut = 'technique'; motif = 'adresse technique, d’exemple ou de format'; }
      else if (exemple) { statut = 'exemple'; motif = 'exemple d’aide à la saisie'; }
      else if (mots > 8) { statut = 'libelle'; motif = 'phrase d’interface'; }
      else if (sorte === 'poste/fonction (libellé)' && !compare) { statut = 'libelle-court'; motif = 'libellé affiché (à vérifier : signataire, destinataire ?)'; }
      else { const st = statutDe(l, nom); statut = st.statut; motif = st.motif; }
      ajouter({ famille: 'G', sous: sorte, ligne: l, valeur: t.slice(0, 60), nom, contexte: contexteLigne(l), statut, motif, gravite: compare ? 'moyenne' : (mail || tel || url || bp) ? 'moyenne' : 'basse' });
    }
  }

  // --- F : confrontation au cliquet ------------------------------------------------------------------------------------------------------
  const parFichierF = new Map();
  for (const r of rolesF) { const a = parFichierF.get(r.fichier) || []; a.push(r); parFichierF.set(r.fichier, a); }
  const ecartsF = [];
  for (const [f, rs] of parFichierF) { const t = tol.get(f); const plafond = t ? t.sites : 0; if (rs.length !== plafond) ecartsF.push({ fichier: f, trouves: rs.length, toleres: plafond }); }
  for (const [f, t] of tol) if (!parFichierF.has(f) && t.sites > 0) ecartsF.push({ fichier: f, trouves: 0, toleres: t.sites });
  const DEFAUT_SECTIONS = /Chantier parallèle|À ARBITRER/i;
  for (const r of rolesF) {
    const t = tol.get(r.fichier);
    const section = t ? t.section : 'HORS TOLÉRANCE';
    const reel = !t || DEFAUT_SECTIONS.test(section);
    candidats.push({ famille: 'F', fichier: r.fichier, zone: r.zone, module: r.module, ligne: r.ligne, valeur: r.role, contexte: r.texte.slice(0, 220), statut: reel ? 'defaut' : 'tolere', motif: t ? `${section} — ${t.motif}` : 'hors de la table de tolérances', gravite: 'haute' });
  }
  for (const [p, src] of sources) {
    if (!p.endsWith('.php')) continue;
    const { zone, module } = zoneEtModule(p);
    src.split('\n').forEach((l, i) => {
      if (/^\s*(\/\/|\*|#)/.test(l)) return;
      const m = l.match(new RegExp(`[=!]==?\\s*['"](${roles.join('|')})['"]|in_array\\(\\s*['"](${roles.join('|')})['"]`));
      if (m) candidats.push({ famille: 'F', fichier: p, zone, module, ligne: i + 1, valeur: m[1] || m[2], contexte: l.trim().slice(0, 220), statut: 'a-verifier', motif: 'relais : identifiant comparé (rôle ou profil d’appareil ?)', gravite: 'haute' });
    });
  }

  // --- Doublons de semence : un défaut numérique de definitions.dart réécrit en littéral près des mots de sa clé.
  const defs = [...DEFSRC.matchAll(/cle:\s*'([\w.]+)'[\s\S]*?defaut:\s*(\d+)\b/g)].map((m) => ({ cle: m[1], valeur: +m[2] })).filter((d) => d.valeur > 2);
  const doublons = [];
  for (const d of defs) {
    const stems = d.cle.split('.').pop().replace(/([A-Z])/g, ' $1').toLowerCase().split(/\s+/).filter((w) => w.length >= 5 && !/^(jours|delai|limite|seuil|borne)$/.test(w));
    if (!stems.length) continue;
    for (const c of candidats) {
      if ((c.famille !== 'C' && c.famille !== 'B') || +c.valeur !== d.valeur || c.fichier === DEFINITIONS) continue;
      const ctx = (c.contexte + ' ' + (c.nom || '')).toLowerCase();
      if (stems.some((s) => ctx.includes(s.slice(0, 6)))) { c.doublonDe = d.cle; if (c.statut !== 'defaut' && c.statut !== 'demo') { c.statut = 'defaut'; c.motif = `réécrit le défaut du paramètre ${d.cle}`; } doublons.push({ cle: d.cle, fichier: c.fichier, ligne: c.ligne, statut: c.statut }); }
    }
  }

  // Les faux positifs vérifiés à la main.
  for (const c of candidats) { if (c.statut !== 'defaut') continue; const m = ecarterALaMain(c); if (m) { c.statut = 'ecarte-main'; c.motif = m; } }
  // Une occurrence = une ligne : plusieurs littéraux de la même famille sur la même ligne ne font qu'un site.
  const vus = new Set();
  for (const c of candidats) {
    const k = `${c.famille}|${c.fichier}|${c.ligne}|${c.statut}`;
    c.doublonLigne = vus.has(k);
    vus.add(k);
  }
  return { candidats: candidats.filter((c) => !c.doublonLigne), engendres, ecartsF, tolerances: [...tol.entries()].map(([f, t]) => ({ fichier: f, ...t })), doublons, nbFichiers: liste.length, nbLignes: [...sources.values()].reduce((s, y) => s + y.split('\n').length, 0) };
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// 7. SORTIES, ET LE CLIQUET.
//
// Le CLIQUET (lot 0, 16/11/2026 — E3840) : `--cliquet --famille=A`. Une ANNÉE littérale 2024-2030 qui DÉCIDE ne réapparaît pas dans `lib`.
// La liste des sites TOLÉRÉS est FERMÉE et motivée (`annees-tolerees.json` : fichier, valeur relevée, nombre de sites, motif). Le cliquet échoue
//   * quand un défaut de la famille n'est couvert par aucune tolérance (une année en dur est apparue) ;
//   * quand une tolérance couvre PLUS de sites qu'elle n'en déclare (la valeur s'est répandue) ;
//   * quand une tolérance couvre MOINS de sites qu'elle n'en déclare (le site a été corrigé : la liste doit être abaissée — le cliquet ne remonte jamais).
// Les sites se reconnaissent par le FICHIER et la VALEUR relevée, jamais par le numéro de ligne (qui bouge à chaque retouche).
// ---------------------------------------------------------------------------------------------------------------------------------------------
export const FICHIERS_TOLERES = { A: 'annees-tolerees.json' };
export function lireToleres(famille) {
  const nom = FICHIERS_TOLERES[famille];
  if (!nom) throw new Error(`aucune liste de tolérances pour la famille ${famille} (cliquet disponible : ${Object.keys(FICHIERS_TOLERES).join(', ')})`);
  const j = JSON.parse(readFileSync(new URL(nom, import.meta.url), 'utf8'));
  for (const t of j.toleres) if (!t.fichier || !t.valeur || !t.motif || !(t.sites >= 1)) throw new Error(`tolérance incomplète (fichier, valeur, sites ≥ 1 et motif obligatoires) : ${JSON.stringify(t)}`);
  return j.toleres;
}
/** Confronte les défauts d'une famille à sa liste fermée. Rend `{ nouveaux, depassements, perimes, couverts }` ; le cliquet passe quand les trois premiers sont vides. */
export function cliquet(candidats, toleres, famille) {
  const defs = candidats.filter((c) => c.statut === 'defaut' && c.famille === famille);
  const parTol = new Map(toleres.map((t) => [t, []]));
  const nouveaux = [];
  for (const c of defs) {
    const t = toleres.find((x) => x.fichier === c.fichier && x.valeur === String(c.valeur));
    if (t) parTol.get(t).push(c); else nouveaux.push(c);
  }
  const depassements = [], perimes = [];
  for (const [t, cs] of parTol) {
    if (cs.length > t.sites) depassements.push({ ...t, trouves: cs.length, lignes: cs.map((c) => c.ligne) });
    if (cs.length < t.sites) perimes.push({ ...t, trouves: cs.length });
  }
  return { nouveaux, depassements, perimes, couverts: defs.length - nouveaux.length };
}

function principal() {
const args = process.argv.slice(2);
const opt = (k) => { const eq = args.find((a) => a.startsWith(k + '=')); if (eq) return eq.slice(k.length + 1); const i = args.indexOf(k); return i >= 0 ? args[i + 1] : undefined; };
const res = analyser();
const FAMILLES = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'];
const defauts = res.candidats.filter((c) => c.statut === 'defaut');

// Deux cliquets cohabitent : la famille A (années) lit une LISTE FERMÉE de tolérances motivées (lot 0) ; les autres familles lisent des PLAFONDS par fichier
// (lot 2, plus bas). Celui-ci ne prend que les familles qui ont une liste de tolérances.
const familleCliquetA = (args.find((a) => a.startsWith('--famille=')) || '').slice('--famille='.length) || opt('--famille') || 'A';
if (args.includes('--cliquet') && FICHIERS_TOLERES[familleCliquetA]) {
  const famille = familleCliquetA;
  const r = cliquet(res.candidats, lireToleres(famille), famille);
  for (const c of r.nouveaux) console.log(`✗ NOUVELLE valeur en dur (famille ${famille}) : ${c.fichier}:${c.ligne}  « ${c.valeur} »  — ${c.contexte}`);
  for (const t of r.depassements) console.log(`✗ ${t.fichier} : « ${t.valeur} » relevé ${t.trouves} fois (lignes ${t.lignes.join(', ')}), ${t.sites} toléré(s) — la valeur s'est répandue`);
  for (const t of r.perimes) console.log(`✗ ${t.fichier} : « ${t.valeur} » relevé ${t.trouves} fois, ${t.sites} toléré(s) — site corrigé : abaisser la liste (${FICHIERS_TOLERES[famille]})`);
  const ko = r.nouveaux.length + r.depassements.length + r.perimes.length;
  console.log(ko ? `Cliquet famille ${famille} : ÉCHEC (${ko} écart(s)).` : `Cliquet famille ${famille} : 0 nouvelle valeur en dur ; ${r.couverts} site(s) toléré(s), tous motivés.`);
  process.exit(ko ? 1 : 0);
}

if (opt('--json')) writeFileSync(opt('--json'), JSON.stringify(res, null, 1));

if (args.includes('--liste')) {
  const f = opt('--liste');
  const mod = opt('--module');
  const statut = opt('--statut') || 'defaut';
  for (const c of res.candidats.filter((x) => x.famille === f && (statut === 'tous' || x.statut === statut) && (!mod || x.module.toLowerCase() === mod.toLowerCase() || x.zone.includes(mod))))
    console.log(`${c.fichier}:${c.ligne}\t${c.statut}\t${c.gravite}\t${c.sous || ''}\t${c.valeur}\t${c.doublonDe ? '[doublon de ' + c.doublonDe + '] ' : ''}${c.contexte}`);
  process.exit(0);
}
if (args.includes('--echantillon')) {
  const n = +opt('--echantillon');
  const f = opt('--famille');
  let g = +(opt('--graine') || 7);
  const alea = () => ((g = (g * 1103515245 + 12345) % 2147483648) / 2147483648);
  const pool = defauts.filter((c) => !f || c.famille === f);
  const tir = [];
  const pris = new Set();
  while (tir.length < Math.min(n, pool.length)) { const k = Math.floor(alea() * pool.length); if (!pris.has(k)) { pris.add(k); tir.push(pool[k]); } }
  for (const c of tir) console.log(`${c.famille}${c.sous ? '/' + c.sous : ''}\t${c.fichier}:${c.ligne}\t${c.valeur}\t${c.contexte}`);
  process.exit(0);
}
if (args.includes('--cliquet')) {
  // `--famille=B,H` ou `--famille B,H` : les familles surveillées (défaut : celles de la ligne de base).
  const brut = (args.find((a) => a.startsWith('--famille=')) || '').slice('--famille='.length) || opt('--famille') || '';
  const cheminPlafonds = opt('--plafonds') || join(RACINE, 'tools/baguidi/valeurs-en-dur.plafonds.json');
  let base = { familles: {} };
  if (existsSync(cheminPlafonds)) base = JSON.parse(readFileSync(cheminPlafonds, 'utf8'));
  else if (!args.includes('--proposer')) { console.error(`Cliquet : ligne de base absente (${cheminPlafonds}).`); process.exit(1); }
  const familles = (brut ? brut.split(',') : Object.keys(base.familles || {})).map((f) => f.trim().toUpperCase()).filter(Boolean);
  const inconnues = familles.filter((f) => !FAMILLES.includes(f));
  if (!familles.length || inconnues.length) { console.error(`Cliquet : familles à surveiller absentes ou inconnues (${inconnues.join(', ') || 'aucune'}) ; attendu par exemple --famille=B,H.`); process.exit(1); }
  const mesure = {};
  for (const f of familles) mesure[f] = {};
  for (const c of defauts) if (mesure[c.famille]) mesure[c.famille][c.fichier] = (mesure[c.famille][c.fichier] || 0) + 1;
  if (args.includes('--proposer')) {
    const out = { familles: {} };
    for (const f of familles) {
      out.familles[f] = {};
      for (const [fichier, n] of Object.entries(mesure[f]).sort()) out.familles[f][fichier] = { plafond: n, motif: base.familles?.[f]?.[fichier]?.motif || '' };
    }
    console.log(JSON.stringify(out, null, 2));
    process.exit(0);
  }
  const ecarts = [];
  for (const f of familles) {
    const tol = base.familles?.[f] || {};
    for (const [fichier, n] of Object.entries(mesure[f])) {
      const t = tol[fichier];
      const plafond = t ? t.plafond : 0;
      if (n > plafond) {
        const sites = defauts.filter((c) => c.famille === f && c.fichier === fichier).map((c) => `    ${c.fichier}:${c.ligne}  « ${String(c.valeur).slice(0, 60)} »`).join('\n');
        const consigne = f === 'E'
          ? 'Une référence de pièce se construit par la fabrique du référentiel de numérotation (numeroSuivant / numeroFormate / numeroDerive), jamais par un préfixe écrit dans le code.'
          : 'La lire dans un paramètre daté, un référentiel ou un barème ; sinon la tolérer avec un motif.';
        ecarts.push(`${f} ${fichier} : ${n} valeur(s) en dur pour un plafond de ${plafond} — une valeur en dur est APPARUE :\n${sites}\n    ${consigne}`);
      }
    }
    for (const [fichier, t] of Object.entries(tol)) {
      const n = mesure[f][fichier] || 0;
      if (n < t.plafond) ecarts.push(`${f} ${fichier} : ${n} valeur(s) en dur pour un plafond de ${t.plafond} — ABAISSER la ligne de base (le cliquet ne remonte jamais : la place libérée ne doit pas resservir).`);
      if (!String(t.motif || '').trim()) ecarts.push(`${f} ${fichier} : toléré SANS MOTIF — dire pourquoi la valeur reste en dur et quel lot la convertira.`);
    }
  }
  const total = (m) => Object.values(m).reduce((s, n) => s + n, 0);
  const resume = familles.map((f) => `${f} = ${total(mesure[f])}`).join(', ');
  if (ecarts.length) {
    console.error(`Cliquet « valeurs en dur » (${resume}) : ${ecarts.length} écart(s) avec ${relative(RACINE, cheminPlafonds) || cheminPlafonds}`);
    for (const e of ecarts) console.error(`  - ${e}`);
    process.exit(1);
  }
  console.log(`Cliquet « valeurs en dur » : familles ${familles.join(', ')} conformes à leurs plafonds (${resume}).`);
//        Famille E (préfixes de numérotation) : plafond ZÉRO partout depuis le lot 2 (fabrique du référentiel de numérotation) ; `--injecter=<chemin fictif>:<fichier>` ajoute un source
//        au balayage comme s'il vivait au chemin fictif (sonde : le cliquet doit mordre).
//   node tools/baguidi/inventaire-en-dur.mjs --cliquet --famille=A   échoue si une année en dur qui décide apparaît hors de la liste fermée (annees-tolerees.json)
// Lecture seule : le script n'écrit que le fichier demandé par --json. Importable (node --test) : `analyser`, `cliquet`, `lireToleres`.
  process.exit(0);
}
if (args.includes('--par-fichier')) {
  const m = new Map();
  for (const c of defauts) { const k = c.fichier; const o = m.get(k) || Object.fromEntries(FAMILLES.map((x) => [x, 0])); o[c.famille]++; m.set(k, o); }
  for (const [k, o] of [...m.entries()].sort((a, b) => Object.values(b[1]).reduce((s, x) => s + x, 0) - Object.values(a[1]).reduce((s, x) => s + x, 0)))
    console.log(`${k}\t${FAMILLES.map((x) => `${x}=${o[x]}`).join(' ')}`);
  process.exit(0);
}

// Synthèse
const modules = [...new Set(defauts.map((c) => c.module))];
const tab = new Map(modules.map((m) => [m, Object.fromEntries(FAMILLES.map((f) => [f, 0]))]));
for (const c of defauts) tab.get(c.module)[c.famille]++;
const total = (o) => FAMILLES.reduce((s, f) => s + o[f], 0);
const lignes = [...tab.entries()].sort((a, b) => total(b[1]) - total(a[1]));
console.log(`Inventaire des valeurs en dur — ${res.nbFichiers} fichiers, ${res.nbLignes} lignes balayées.`);
console.log(`Candidats : ${res.candidats.length} ; défauts réels (statut « defaut », après exclusions d’office et faux positifs écartés à la main) : ${defauts.length}.`);
const parStatut = {};
for (const c of res.candidats) { const k = `${c.famille}:${c.statut}`; parStatut[k] = (parStatut[k] || 0) + 1; }
console.log('Par famille et statut :', JSON.stringify(parStatut));
console.log(`Fichiers ENGENDRÉS (référentiels statiques, famille R, comptés une fois chacun) : ${res.engendres.length}`);
console.log(`Cliquet des rôles : ${res.ecartsF.length} écart(s) avec la table de tolérances${res.ecartsF.length ? ' : ' + JSON.stringify(res.ecartsF) : ''}.`);
console.log(`Doublons de semence (défaut de definitions.dart réécrit en littéral) : ${res.doublons.length}`);
console.log(['MODULE', ...FAMILLES, 'TOTAL'].join('\t'));
for (const [m, o] of lignes) console.log([m, ...FAMILLES.map((f) => o[f]), total(o)].join('\t'));
const tot = Object.fromEntries(FAMILLES.map((f) => [f, defauts.filter((c) => c.famille === f).length]));
console.log(['TOTAL', ...FAMILLES.map((f) => tot[f]), defauts.length].join('\t'));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) principal();
