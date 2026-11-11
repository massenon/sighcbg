'use strict';
/* Garde-fous de la matrice engendrée : chaque ligne encode une DÉCISION de la Direction écrite dans CLAUDE.md.
 * Si ce test échoue après une régénération (`node prototype_html/build/extraire.js rbac`), soit la maquette a
 * changé — et la décision doit être revue —, soit l'extraction est cassée. Ne jamais « corriger » le test seul. */
const test = require('node:test');
const assert = require('node:assert/strict');
const rbac = require('../data/rbac.json');
const manifeste = require('../../referentiels/data/manifeste.json');
const droit = (role, ecran) => (rbac.parRole[role] || {})[ecran] || null;
const ecransConnus = new Set(manifeste.ecrans.map((e) => e.id));

test('chaque écran cité existe au manifeste', () => {
  for (const [role, ecrans] of Object.entries(rbac.parRole)) for (const id of Object.keys(ecrans)) assert.ok(ecransConnus.has(id), `${role} → ${id}`);
});
test('chaque rôle de la matrice est déclaré', () => {
  const ids = new Set(rbac.roles.map((r) => r.id));
  for (const role of Object.keys(rbac.parRole)) assert.ok(ids.has(role), role);
});
test('Pharmacie et RH sont archivés (RG-14) : aucun écran, jamais supprimés', () => {
  for (const r of ['pharmacien', 'rh']) { assert.ok(rbac.roles.find((x) => x.id === r).archive, r); assert.equal(Object.keys(rbac.parRole[r]).length, 0, r); }
});
test('caissier : ni stock en gros, ni dépenses ; avoir en lecture seule ; caisse en écriture sans annulation', () => {
  assert.equal(droit('caissier', 'm6-stock-gros'), null);
  assert.equal(droit('caissier', 'm12-depenses'), null);
  assert.deepEqual(droit('caissier', 'm8-facture-avoir'), [1, 0, 0]);
  assert.deepEqual(droit('caissier', 'm8-caisse'), [1, 1, 0]);
});
test('biologiste (id laborantin) : pas de bon de livraison', () => { assert.equal(droit('laborantin', 'm7-livraisons'), null); });
test('échographiste : exécute l\'imagerie sans prescrire, aucun accès financier', () => {
  assert.equal(droit('echographiste', 'm2-imagerie')[1], 1);
  assert.equal(droit('echographiste', 'm2-ordonnances'), null);
  for (const [id] of Object.entries(rbac.parRole.echographiste)) assert.ok(!/^m(8|9|12)-/.test(id) && !id.startsWith('mecef-'), id);
});
test('assistant de direction : pas de résultats de laboratoire, mais l\'inventaire des réactifs', () => {
  assert.equal(droit('assistant_comptable', 'm5-resultats'), null);
  assert.ok(droit('assistant_comptable', 'm5-reactifs'));
});
test('la Direction signe la paie (surcharge d\'écran), signer n\'est pas saisir', () => { assert.equal(droit('direction', 'm11-validation')[1], 1); });
test('A2 : le comptable génère les bulletins, il ne valide pas la paie (lecture seule de m11-validation)', () => {
  assert.deepEqual(droit('comptable', 'm11-validation'), [1, 0, 0]);
  assert.equal(droit('comptable', 'm11-calcul')[1], 1, 'il garde la génération');
});
test('écran universel : exprimer un besoin est ouvert à tout rôle actif, mais jamais annulable par le passant', () => {
  for (const r of rbac.roles.filter((x) => !x.archive)) { const d = droit(r.id, 'm7-besoins'); assert.ok(d && d[0] === 1 && d[1] === 1, r.id); }
  for (const r of ['medecin', 'caissier', 'reception']) assert.equal(droit(r, 'm7-besoins')[2], 0, r);
});
test('une page de saisie hérite des droits du registre qu\'elle alimente (servant)', () => {
  for (const e of manifeste.ecrans.filter((x) => x.servant)) {
    for (const role of Object.keys(rbac.parRole)) {
      const page = droit(role, e.id); const registre = droit(role, e.servant);
      assert.equal(!!page, !!registre, `${role} : ${e.id} ≠ ${e.servant}`);
    }
  }
});
test('spécialités (P0-12) : le répertoire et les visites de médecine du travail sont cliniques — fermés à l\'accueil et au technicien d\'échographie', () => {
  for (const r of ['reception', 'echographiste']) for (const e of ['m2-specialites', 'm2-mdt-visites']) assert.equal(droit(r, e), null, `${r} → ${e}`);
  assert.deepEqual(droit('infirmier', 'm2-specialites'), [1, 0, 0], 'l\'infirmier lit le répertoire sans le modifier');
  assert.deepEqual(droit('medecin', 'm2-mdt-visites'), [1, 1, 1]);
});
test('spécialités : les entreprises et conventions se lisent à l\'accueil, aucun rôle sans le module M2 n\'y entre', () => {
  assert.ok(droit('reception', 'm2-mdt-entreprises') && droit('reception', 'm2-mdt-conventions'));
  for (const r of ['caissier', 'comptable', 'stock', 'laborantin', 'rh', 'pharmacien', 'da'])
    for (const e of ['m2-specialites', 'm2-mdt-visites', 'm2-mdt-entreprises', 'm2-mdt-conventions']) assert.equal(droit(r, e), null, `${r} → ${e}`);
});

/* --- Trois rôles créés par la Direction de Baguidi le 10/11/2026 : un rôle propre à chaque responsable de l'organisation (RR, RM, RA). --- */
const rolesEnModule = (role, mod) => Object.keys(rbac.parRole[role]).filter((id) => (manifeste.ecrans.find((e) => e.id === id) || {}).module === mod);
// Les écrans UNIVERSELS (« Mon espace », « Propositions de planning » : un agent exprime son besoin, propose son planning et lit sa paie) sont ouverts à tout poste : ils ne
// donnent pas accès au module qui les porte, ce que ces tests mesurent.
const modulesDe = (role) => new Set(Object.keys(rbac.parRole[role]).filter((id) => !(manifeste.ecrans.find((e) => e.id === id) || {}).universel).map((id) => (manifeste.ecrans.find((e) => e.id === id) || {}).module));
test('les trois rôles du 10/11/2026 sont déclarés, actifs, avec leur tableau de bord pour accueil', () => {
  const attendu = { responsable_radiologie: 'dash-responsable-radiologie', sage_femme: 'dash-sage-femme', responsable_assurance: 'dash-responsable-assurance' };
  for (const [role, home] of Object.entries(attendu)) {
    const r = rbac.roles.find((x) => x.id === role);
    assert.ok(r && !r.archive, role);
    assert.equal(r.home, home);
    assert.ok(droit(role, home), `${role} voit son accueil`);
  }
});
test('Responsable Radiologie : exécute l\'imagerie sans prescrire, comme l\'échographiste ; aucun accès financier', () => {
  const echo = Object.keys(rbac.parRole.echographiste).filter((id) => id !== 'dash-echographiste');
  const rr = Object.keys(rbac.parRole.responsable_radiologie).filter((id) => id !== 'dash-responsable-radiologie');
  assert.deepEqual(rr, echo);
  for (const id of rr) assert.deepEqual(droit('responsable_radiologie', id), droit('echographiste', id), id);
  assert.equal(droit('responsable_radiologie', 'm2-imagerie-demandes')[1], 1);
  assert.equal(droit('responsable_radiologie', 'm2-ordonnances'), null);
  assert.deepEqual(droit('responsable_radiologie', 'cfg-imagerie-catalogue'), [1, 0, 0]);
  for (const mod of ['M8', 'M9', 'MECEF', 'M12', 'M10', 'M11']) assert.equal(modulesDe('responsable_radiologie').has(mod), false, mod);
});
test('Responsable Maternité (sage-femme) : M4 en écriture, M1 et M2 en lecture, constantes saisies, ni finance ni imagerie', () => {
  assert.equal(rolesEnModule('sage_femme', 'M4').length, 15);
  for (const id of rolesEnModule('sage_femme', 'M4')) assert.equal(droit('sage_femme', id)[1], 1, id);
  assert.deepEqual(droit('sage_femme', 'm1-patients'), [1, 0, 0]);
  assert.equal(droit('sage_femme', 'm1-constantes')[1], 1);
  assert.deepEqual(droit('sage_femme', 'm2-consultations'), [1, 0, 0]);
  assert.ok(droit('sage_femme', 'm5-resultats') && droit('sage_femme', 'm5-demandes-maternite'));
  for (const id of ['m5-demandes', 'm2-imagerie', 'm2-imagerie-demandes', 'm5-banque-sang']) assert.equal(droit('sage_femme', id), null, id);
  for (const mod of ['M3', 'M6', 'M8', 'M9', 'MECEF', 'M10', 'M11', 'M12', 'M13', 'M14', 'CFG']) assert.equal(modulesDe('sage_femme').has(mod), false, mod);
});
test('Responsable Assurance : M9 en écriture, M8 en lecture, répertoire sans dossier médical, rien en comptabilité ni clinique', () => {
  assert.equal(rolesEnModule('responsable_assurance', 'M9').length, 10);
  for (const id of rolesEnModule('responsable_assurance', 'M9')) assert.equal(droit('responsable_assurance', id)[1], 1, id);
  for (const id of rolesEnModule('responsable_assurance', 'M8')) assert.equal(droit('responsable_assurance', id)[1], 0, id);
  assert.deepEqual(droit('responsable_assurance', 'm1-patients'), [1, 0, 0]);
  for (const id of ['m1-dossier-medical', 'm1-antecedents', 'm1-constantes', 'm1-pieces', 'm8-caisse', 'm12-ecritures', 'm5-resultats', 'm2-consultations']) assert.equal(droit('responsable_assurance', id), null, id);
  for (const mod of ['M2', 'M3', 'M4', 'M5', 'M6', 'M10', 'M11', 'M12', 'MECEF', 'M13', 'M14', 'CFG']) assert.equal(modulesDe('responsable_assurance').has(mod), false, mod);
});
test('droit d\'archiver : chaque nouveau rôle suit le rôle existant le plus proche, sans l\'élargir (Direction, 11/11/2026)', () => {
  const ecrans = (role) => Object.keys(rbac.parRole[role]).filter((id) => !id.startsWith('dash-'));
  for (const id of ecrans('responsable_radiologie')) assert.equal(droit('responsable_radiologie', id)[2], droit('echographiste', id)[2], `radiologie/échographiste ${id}`);
  for (const id of rolesEnModule('sage_femme', 'M4')) assert.equal(droit('sage_femme', id)[2], droit('infirmier', id)[2], `sage-femme/infirmier ${id}`);
  for (const id of rolesEnModule('responsable_assurance', 'M9')) {
    assert.equal(droit('responsable_assurance', id)[2], 0, `M9 sans archivage ${id}`);
    assert.deepEqual(droit('responsable_assurance', id), droit('comptable', id), `comme le comptable ${id}`);
  }
  for (const id of rolesEnModule('responsable_assurance', 'M8')) assert.deepEqual(droit('responsable_assurance', id), [1, 0, 0], `M8 en lecture seule ${id}`);
  for (const mod of ['M9']) assert.equal(rbac.matriceModules.responsable_assurance[mod].annuler, false);
});
test('un tableau de bord de rôle n\'est ouvert qu\'à son rôle et aux profils qui lisent tout', () => {
  for (const [role, dash] of [['responsable_radiologie', 'dash-responsable-radiologie'], ['sage_femme', 'dash-sage-femme'], ['responsable_assurance', 'dash-responsable-assurance']]) {
    for (const r of rbac.roles) assert.equal(!!droit(r.id, dash), r.id === role || ['admin', 'da', 'direction'].includes(r.id), `${dash} sous ${r.id}`);
  }
});
