/* ==========================================================================
 * IMAGERIE — LE MODÈLE DE COMPTE RENDU
 * --------------------------------------------------------------------------
 * Fondé sur SIX pièces réelles de newinfos/ :
 *   - cinq comptes rendus édités par la clinique (pelvienne, vésico-prostatique,
 *     abdomino-pelvienne, obstétricale, obstétricale du 1er trimestre) ;
 *   - le BROUILLON MANUSCRIT de l'échographiste, qui est la pièce décisive :
 *     il énumère lui-même, de sa main, les listes de choix qu'il veut voir
 *     pré-insérées.
 *
 * CE QUE LE BROUILLON DICTE, ET QU'IL NE FAUT PAS DÉFAIRE :
 *
 *   - des LISTES DE CHOIX partout où la valeur est catégorielle : nombre de
 *     sacs (01/02/03/autre), aspect (tonique/hypotonique), localisation
 *     (intra-utérine/extra-utérine/autre), réaction trophoblastique
 *     (décollement ou non), activité cardiaque (active/inactive) ;
 *
 *   - l'âge gestationnel est un COUPLE « n SA + n jours », pas un texte : le
 *     saisir librement autoriserait « 7 mois », qui ne se compare à rien ;
 *
 *   - MAIS « Annexes » et « Conclusion » restent en TEXTE LIBRE. Le brouillon
 *     porte, en toutes lettres, « à remplir par moi-même ». Fermer ces deux
 *     rubriques dans un formulaire à cases irait contre une demande écrite.
 *
 * Le pied de chaque compte rendu réel porte « Réalisé par : AHOHOU Rodrigue »
 * avec ses téléphones : l'échographiste est un intervenant NOMMÉ sur la pièce,
 * au même titre que le prescripteur.
 * ======================================================================== */
(function (global) {
  'use strict';

  var D = global.SIGH.data;

  /* --------------------------------------------------------------------------
   * TYPES DE VARIABLE
   * ------------------------------------------------------------------------ */
  var TYPES = [
    { code: 'liste', label: 'Liste de choix' },
    { code: 'binaire', label: 'Deux valeurs' },
    { code: 'mesure', label: 'Mesure chiffrée' },
    { code: 'dimensions', label: 'Trois dimensions (mm)' },
    { code: 'gestationnel', label: 'Âge gestationnel (SA + jours)' },
    { code: 'texte', label: 'Texte libre' },
    { code: 'zone', label: 'Texte libre — plusieurs lignes' },
  ];

  /* --------------------------------------------------------------------------
   * LES SEPT EXAMENS DU CATALOGUE
   * ------------------------------------------------------------------------
   * Codes alignés sur ceux du catalogue tarifaire : un examen d'imagerie est
   * un acte facturable, et l'un ne doit pas exister sans l'autre.
   * ---------------------------------------------------------------------- */
  var EXAMENS = [
    { code: 'IMG-ECHO-PEL', label: 'Échographie pelvienne', icone: 'scan-line', voie: 'sus-pubienne' },
    { code: 'IMG-ECHO-ABD', label: 'Échographie abdominale', icone: 'scan-line', voie: 'transpariétale' },
    { code: 'IMG-ECHO-ABP', label: 'Échographie abdomino-pelvienne', icone: 'scan-line', voie: 'transpariétale' },
    { code: 'IMG-ECHO-PRO', label: 'Échographie vésico-prostatique', icone: 'scan-line', voie: 'sus-pubienne' },
    { code: 'IMG-ECHO-OBS', label: 'Échographie obstétricale', icone: 'baby', voie: 'sus-pubienne' },
    { code: 'IMG-ECHO-OBS1', label: 'Échographie obstétricale du 1er trimestre', icone: 'baby', voie: 'sus-pubienne',
      tarifCode: 'IMG-ECHO-OBS' },
    { code: 'IMG-ECG', label: 'Électrocardiogramme (ECG)', icone: 'activity', voie: null },
  ];

  /* --------------------------------------------------------------------------
   * VARIABLES PAR EXAMEN
   * ------------------------------------------------------------------------
   * [code, libellé, type, options|unité, { rubrique, normal }]
   * ---------------------------------------------------------------------- */
  var V = {};

  /* --- Échographie pelvienne (compte rendu ABALO/AGNILO) ------------------- */
  V['IMG-ECHO-PEL'] = [
    ['VESSIE', 'Vessie', 'liste', ['bien remplie', 'insuffisamment remplie', 'vide'], { rubrique: 'Résultat', normal: 'bien remplie' }],
    ['UT_STAT', 'Statique utérine', 'liste', ['antéversée, antéfléchie', 'rétroversée', 'médiane', 'latérodéviée'], { rubrique: 'Utérus' }],
    ['UT_VAC', 'Vacuité utérine', 'binaire', ['vide', 'gravide'], { rubrique: 'Utérus', normal: 'vide' }],
    ['UT_DIM', 'Dimensions utérines', 'dimensions', 'mm', { rubrique: 'Utérus' }],
    ['UT_ECHO', 'Échostructure', 'liste', ['homogène', 'hétérogène'], { rubrique: 'Utérus', normal: 'homogène' }],
    ['UT_CONT', 'Contours', 'liste', ['réguliers', 'irréguliers'], { rubrique: 'Utérus', normal: 'réguliers' }],
    ['ENDO', 'Épaisseur de l’endomètre', 'mesure', 'mm', { rubrique: 'Utérus' }],
    ['OVAIRES', 'Ovaires', 'liste', ['normaux', 'ovaire droit anormal', 'ovaire gauche anormal', 'les deux anormaux'], { rubrique: 'Annexes', normal: 'normaux' }],
    ['DOUGLAS', 'Cul-de-sac de Douglas', 'liste', ['libre', 'épanchement de faible abondance', 'épanchement de moyenne abondance', 'épanchement de grande abondance'], { rubrique: 'Annexes', normal: 'libre' }],
  ];

  /* --- Échographie vésico-prostatique (compte rendu NOUKOURE OROU) --------- */
  V['IMG-ECHO-PRO'] = [
    ['PR_LARG', 'Prostate — largeur', 'mesure', 'mm', { rubrique: 'Prostate' }],
    ['PR_HAUT', 'Prostate — hauteur', 'mesure', 'mm', { rubrique: 'Prostate' }],
    ['PR_EP', 'Prostate — épaisseur', 'mesure', 'mm', { rubrique: 'Prostate' }],
    ['PR_VOL', 'Volume prostatique', 'mesure', 'g', { rubrique: 'Prostate' }],
    ['PR_ECHO', 'Échostructure prostatique', 'liste', ['homogène', 'hétérogène'], { rubrique: 'Prostate', normal: 'homogène' }],
    ['PR_NOD', 'Plus grand nodule', 'mesure', 'mm', { rubrique: 'Prostate' }],
    ['PR_CONT', 'Contours prostatiques', 'liste', ['réguliers', 'irréguliers'], { rubrique: 'Prostate', normal: 'réguliers' }],
    ['RD', 'Rein droit — axe bipolaire', 'mesure', 'mm', { rubrique: 'Reins' }],
    ['RG', 'Rein gauche — axe bipolaire', 'mesure', 'mm', { rubrique: 'Reins' }],
    ['R_DIL', 'Dilatation des voies excrétrices', 'binaire', ['absente', 'présente'], { rubrique: 'Reins', normal: 'absente' }],
    ['R_DIFF', 'Différenciation cortico-médullaire', 'binaire', ['conservée', 'altérée'], { rubrique: 'Reins', normal: 'conservée' }],
    ['R_LITH', 'Formation lithiasique', 'binaire', ['absente', 'présente'], { rubrique: 'Reins', normal: 'absente' }],
    ['VE_REPL', 'Vessie — réplétion', 'liste', ['bonne réplétion', 'réplétion insuffisante'], { rubrique: 'Vessie', normal: 'bonne réplétion' }],
    ['VE_PAROI', 'Vessie — épaisseur de paroi', 'mesure', 'mm', { rubrique: 'Vessie' }],
    ['VE_CONT', 'Vessie — contours de paroi', 'liste', ['réguliers', 'irréguliers'], { rubrique: 'Vessie', normal: 'réguliers' }],
    ['VE_CONT2', 'Vessie — contenu', 'liste', ['transsonore homogène', 'anéchogène homogène', 'échogène'], { rubrique: 'Vessie', normal: 'transsonore homogène' }],
    ['VE_MASSE', 'Masse intravésicale', 'binaire', ['absente', 'visible'], { rubrique: 'Vessie', normal: 'absente' }],
    ['RPM', 'Résidu post-mictionnel', 'mesure', 'ml', { rubrique: 'Vessie' }],
  ];

  /* --- Échographie abdomino-pelvienne (compte rendu ABDOU-RAHAMANE) -------- */
  V['IMG-ECHO-ABP'] = [
    ['FOIE', 'Foie — taille', 'mesure', 'mm', { rubrique: 'Foie et voies biliaires' }],
    ['FOIE_C', 'Foie — contours', 'liste', ['réguliers', 'irréguliers'], { rubrique: 'Foie et voies biliaires', normal: 'réguliers' }],
    ['FOIE_E', 'Foie — échostructure', 'liste', ['homogène', 'hétérogène'], { rubrique: 'Foie et voies biliaires', normal: 'homogène' }],
    ['VPORTE', 'Veine porte — calibre', 'mesure', 'mm', { rubrique: 'Foie et voies biliaires' }],
    ['VB_PAROI', 'Vésicule biliaire — paroi', 'mesure', 'mm', { rubrique: 'Foie et voies biliaires' }],
    ['VB_CONT', 'Vésicule biliaire — contenu', 'liste', ['transsonore alithiasique', 'lithiasique', 'sludge'], { rubrique: 'Foie et voies biliaires', normal: 'transsonore alithiasique' }],
    ['VB_VOIES', 'Voies biliaires intra et extra-hépatiques', 'binaire', ['sans anomalie', 'dilatées'], { rubrique: 'Foie et voies biliaires', normal: 'sans anomalie' }],
    ['VSH', 'Veines sus-hépatiques et veine cave inférieure', 'binaire', ['perméables, calibre normal', 'anormales'], { rubrique: 'Foie et voies biliaires', normal: 'perméables, calibre normal' }],
    ['RD2', 'Rein droit — axe bipolaire', 'mesure', 'mm', { rubrique: 'Reins' }],
    ['RG2', 'Rein gauche — axe bipolaire', 'mesure', 'mm', { rubrique: 'Reins' }],
    ['R_DIL2', 'Dilatation des voies excrétrices', 'binaire', ['absente', 'présente'], { rubrique: 'Reins', normal: 'absente' }],
    ['RATE', 'Rate — hauteur', 'mesure', 'mm', { rubrique: 'Rate et pancréas' }],
    ['PANC', 'Pancréas', 'liste', ['taille normale, contours réguliers, échostructure homogène', 'anormal'], { rubrique: 'Rate et pancréas', normal: 'taille normale, contours réguliers, échostructure homogène' }],
    ['VE_ABP', 'Vessie', 'liste', ['bonne réplétion, contenu anéchogène, paroi non épaissie', 'paroi épaissie', 'contenu échogène'], { rubrique: 'Appareil urinaire bas', normal: 'bonne réplétion, contenu anéchogène, paroi non épaissie' }],
    ['PR_ABP', 'Prostate — dimensions', 'dimensions', 'mm', { rubrique: 'Appareil urinaire bas' }],
    ['PR_VOL2', 'Volume prostatique', 'mesure', 'g', { rubrique: 'Appareil urinaire bas' }],
    ['RPM2', 'Résidu post-mictionnel', 'mesure', 'ml', { rubrique: 'Appareil urinaire bas' }],
    ['MASSE', 'Syndrome de masse ou adénopathie profonde', 'binaire', ['absent', 'présent'], { rubrique: 'Épanchements et masses', normal: 'absent' }],
    ['EPANCH', 'Épanchement liquidien intra-péritonéal', 'binaire', ['absent', 'présent'], { rubrique: 'Épanchements et masses', normal: 'absent' }],
  ];

  /* L'abdominale seule reprend les rubriques hautes de l'abdomino-pelvienne. */
  V['IMG-ECHO-ABD'] = V['IMG-ECHO-ABP'].filter(function (v) {
    return (v[4] || {}).rubrique !== 'Appareil urinaire bas';
  });

  /* --- Obstétricale du 1er trimestre — LE BROUILLON MANUSCRIT -------------- */
  V['IMG-ECHO-OBS1'] = [
    ['SG_NB', 'Sac gestationnel — nombre', 'liste', ['01', '02', '03', 'autre'], { rubrique: 'Sac gestationnel' }],
    ['SG_ASP', 'Sac gestationnel — aspect', 'binaire', ['tonique', 'hypotonique'], { rubrique: 'Sac gestationnel', normal: 'tonique' }],
    ['SG_LOC', 'Localisation', 'liste', ['intra-utérine', 'extra-utérine', 'autre'], { rubrique: 'Sac gestationnel', normal: 'intra-utérine' }],
    ['SG_DIM', 'Dimension du sac', 'mesure', 'mm', { rubrique: 'Sac gestationnel' }],
    ['SG_AG', 'Âge gestationnel', 'gestationnel', null, { rubrique: 'Sac gestationnel' }],
    ['SG_TROPH', 'Réaction trophoblastique', 'liste', ['bonne, pas de décollement ce jour', 'décollement'], { rubrique: 'Sac gestationnel', normal: 'bonne, pas de décollement ce jour' }],
    ['EM_NB', 'Embryon — nombre', 'liste', ['01', '02', '03', 'autre'], { rubrique: 'Embryon' }],
    ['EM_CARD', 'Activité cardiaque', 'binaire', ['active ce jour', 'inactive'], { rubrique: 'Embryon', normal: 'active ce jour' }],
    ['EM_BPM', 'Rythme cardiaque', 'mesure', 'bpm', { rubrique: 'Embryon' }],
    ['EM_LCC', 'LCC — longueur cranio-caudale', 'mesure', 'mm', { rubrique: 'Embryon' }],
    ['EM_AG', 'Âge gestationnel correspondant', 'gestationnel', null, { rubrique: 'Embryon' }],
    ['OB1_TYPE', 'Type de grossesse', 'liste', ['monoembryonnaire', 'gémellaire', 'triple'], { rubrique: 'Conclusion', normal: 'monoembryonnaire' }],
    ['OB1_SIEGE', 'Siège', 'liste', ['intra-utérine', 'extra-utérine'], { rubrique: 'Conclusion', normal: 'intra-utérine' }],
    ['OB1_EVOL', 'Évolutivité', 'binaire', ['évolutive', 'non évolutive'], { rubrique: 'Conclusion', normal: 'évolutive' }],
    ['OB1_CTRL', 'Contrôle programmé', 'texte', null, { rubrique: 'Conclusion' }],
  ];

  /* --- Obstétricale (compte rendu ABALO Bernadette) ------------------------ */
  V['IMG-ECHO-OBS'] = [
    ['F_NB', 'Fœtus — nombre', 'liste', ['01', '02', '03'], { rubrique: 'Fœtus' }],
    ['F_PRES', 'Présentation', 'liste', ['céphalique dos à gauche', 'céphalique dos à droite', 'siège', 'transverse'], { rubrique: 'Fœtus' }],
    ['F_BPM', 'Activité cardiaque', 'mesure', 'bats/min', { rubrique: 'Fœtus' }],
    ['F_MAF', 'MAF — mouvements actifs fœtaux', 'binaire', ['présents', 'absents'], { rubrique: 'Fœtus', normal: 'présents' }],
    ['F_MR', 'MR — mouvements respiratoires', 'binaire', ['présents', 'absents'], { rubrique: 'Fœtus', normal: 'présents' }],
    ['BIP', 'BIP — diamètre bipariétal', 'mesure', 'mm', { rubrique: 'Biométrie' }],
    ['HC', 'HC — périmètre céphalique', 'mesure', 'mm', { rubrique: 'Biométrie' }],
    ['AC', 'AC — périmètre abdominal', 'mesure', 'mm', { rubrique: 'Biométrie' }],
    ['FL', 'FL — longueur fémorale', 'mesure', 'mm', { rubrique: 'Biométrie' }],
    ['AG', 'Âge gestationnel', 'gestationnel', null, { rubrique: 'Biométrie' }],
    ['PLAC_POS', 'Placenta — position', 'liste', ['antérieur loin du col', 'postérieur loin du col', 'bas inséré', 'recouvrant'], { rubrique: 'Annexes fœtales', normal: 'antérieur loin du col' }],
    ['PLAC_GR', 'Placenta — grade', 'liste', ['grade 0', 'grade I', 'grade II', 'grade III'], { rubrique: 'Annexes fœtales' }],
    ['LA_ABOND', 'Liquide amniotique — abondance', 'liste', ['moyenne', 'diminuée', 'augmentée'], { rubrique: 'Annexes fœtales', normal: 'moyenne' }],
    ['LA_IA', 'Index amniotique', 'mesure', 'mm', { rubrique: 'Annexes fœtales' }],
    ['LA_ASP', 'Liquide amniotique — aspect', 'liste', ['normal', 'anormal'], { rubrique: 'Annexes fœtales', normal: 'normal' }],
    ['M_THOR', 'Thorax', 'liste', ['vu', 'non vu'], { rubrique: 'Morphologie', normal: 'vu' }],
    ['M_COEUR', 'Cœur', 'liste', ['actif (04 cavités)', 'anomalie'], { rubrique: 'Morphologie', normal: 'actif (04 cavités)' }],
    ['M_RACHIS', 'Colonne vertébrale', 'liste', ['vue et suivie', 'non vue'], { rubrique: 'Morphologie', normal: 'vue et suivie' }],
    ['M_CERV', 'Cerveau', 'liste', ['vu', 'non vu'], { rubrique: 'Morphologie', normal: 'vu' }],
    ['M_PAROI', 'Paroi abdominale', 'liste', ['fermée', 'anomalie'], { rubrique: 'Morphologie', normal: 'fermée' }],
    ['M_ESTOM', 'Estomac', 'liste', ['vu', 'non vu'], { rubrique: 'Morphologie', normal: 'vu' }],
    ['M_REINS', 'Reins', 'liste', ['vus', 'non vus'], { rubrique: 'Morphologie', normal: 'vus' }],
    ['M_VESSIE', 'Vessie', 'liste', ['vue', 'non vue'], { rubrique: 'Morphologie', normal: 'vue' }],
    ['M_SEXE', 'Sexe', 'liste', ['Masculin', 'Féminin', 'non déterminé'], { rubrique: 'Morphologie' }],
    ['M_AUTRES', 'Autres', 'texte', null, { rubrique: 'Morphologie', normal: 'RAS' }],
    ['POIDS', 'Poids fœtal estimé', 'mesure', 'g', { rubrique: 'Synthèse' }],
    ['MANNING', 'Score de MANNING', 'liste', ['10/10', '8/10', '6/10', '4/10', '2/10', '0/10'], { rubrique: 'Synthèse', normal: '10/10' }],
    ['DPA', 'Date probable d’accouchement', 'texte', null, { rubrique: 'Synthèse' }],
    ['PATHO', 'Aspects pathologiques', 'texte', null, { rubrique: 'Synthèse', normal: 'RAS' }],
  ];

  /* --- ECG ----------------------------------------------------------------- */
  V['IMG-ECG'] = [
    ['RYTHME', 'Rythme', 'liste', ['sinusal régulier', 'sinusal irrégulier', 'fibrillation auriculaire', 'autre'], { rubrique: 'Tracé', normal: 'sinusal régulier' }],
    ['FC', 'Fréquence cardiaque', 'mesure', 'bpm', { rubrique: 'Tracé' }],
    ['PR', 'Espace PR', 'mesure', 'ms', { rubrique: 'Tracé' }],
    ['QRS', 'Durée du QRS', 'mesure', 'ms', { rubrique: 'Tracé' }],
    ['QT', 'Intervalle QT corrigé', 'mesure', 'ms', { rubrique: 'Tracé' }],
    ['AXE', 'Axe électrique', 'liste', ['normal', 'dévié à gauche', 'dévié à droite'], { rubrique: 'Tracé', normal: 'normal' }],
    ['REPOL', 'Repolarisation', 'liste', ['normale', 'trouble de repolarisation'], { rubrique: 'Tracé', normal: 'normale' }],
    ['HYPER', 'Signes d’hypertrophie', 'binaire', ['absents', 'présents'], { rubrique: 'Tracé', normal: 'absents' }],
    ['ISCH', 'Signes d’ischémie', 'binaire', ['absents', 'présents'], { rubrique: 'Tracé', normal: 'absents' }],
  ];

  /* --------------------------------------------------------------------------
   * MISE EN FORME
   * ---------------------------------------------------------------------- */
  var VARIABLES = [];
  Object.keys(V).forEach(function (code) {
    V[code].forEach(function (v, i) {
      var o = v[4] || {};
      VARIABLES.push({
        examen: code, code: v[0], libelle: v[1], type: v[2],
        options: Array.isArray(v[3]) ? v[3] : null,
        unite: Array.isArray(v[3]) ? null : v[3],
        rubrique: o.rubrique || 'Résultat',
        normal: o.normal || null,
        ordre: i + 1,
      });
    });
  });

  /* --------------------------------------------------------------------------
   * LES DEUX RUBRIQUES QUI RESTENT LIBRES
   * ------------------------------------------------------------------------
   * Demande textuelle de l'échographiste, portée sur son brouillon : « Annexes
   * — à remplir par moi-même », puis « Conclusion ». Les fermer dans un
   * formulaire à cases irait contre une instruction écrite de sa main.
   * ---------------------------------------------------------------------- */
  var RUBRIQUES_LIBRES = [
    { code: 'annexes', label: 'Annexes', note: 'Rédigée par l’échographiste — demande portée sur son brouillon.' },
    { code: 'conclusion', label: 'Conclusion', note: 'Rédigée par l’échographiste. Reprise telle quelle sur le compte rendu.', requis: true },
  ];

  function variablesDe(codeExamen) {
    return VARIABLES.filter(function (v) { return v.examen === codeExamen; })
      .sort(function (a, b) { return a.ordre - b.ordre; });
  }

  function rubriquesDe(codeExamen) {
    var vus = {}, out = [];
    variablesDe(codeExamen).forEach(function (v) {
      if (vus[v.rubrique]) return;
      vus[v.rubrique] = true; out.push(v.rubrique);
    });
    return out;
  }

  function examen(code) {
    return EXAMENS.filter(function (x) { return x.code === code; })[0] || null;
  }

  /* Une valeur s'écarte-t-elle de la normale déclarée ? Le compte rendu réel
     met en gras ce qui sort de la norme — c'est cette mise en évidence que le
     clinicien lit en premier. */
  function ecart(variable, valeur) {
    if (!variable || !variable.normal || valeur == null || valeur === '') return false;
    return String(valeur) !== String(variable.normal);
  }

  D.IMAGERIE = {
    TYPES: TYPES,
    EXAMENS: EXAMENS,
    VARIABLES: VARIABLES,
    RUBRIQUES_LIBRES: RUBRIQUES_LIBRES,
    variablesDe: variablesDe,
    rubriquesDe: rubriquesDe,
    examen: examen,
    ecart: ecart,
  };
})(window);
