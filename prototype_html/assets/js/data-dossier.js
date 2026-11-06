/* ==========================================================================
 * LE DOSSIER PATIENT ÉTENDU — DEUX ZONES, DEUX RESPONSABILITÉS
 * --------------------------------------------------------------------------
 * Structure dictée par la Direction le 25/08/2026.
 *
 * LA COUPURE EN DEUX ZONES N'EST PAS UNE COMMODITÉ D'AFFICHAGE : c'est une
 * frontière de responsabilité.
 *
 *   ZONE 1 — ACCUEIL : identification, coordonnées, couverture, constantes.
 *     L'accueil remplit, et il ne voit rien d'autre (RG-13).
 *   ZONE 2 — CONSULTATION : historique, antécédents, examen physique,
 *     décisions. Le soignant remplit ; l'accueil n'y accède pas.
 *
 * Mêler les deux ferait qu'un secrétaire médical lirait un diagnostic en
 * cherchant un numéro de téléphone.
 *
 * LES ANTÉCÉDENTS SONT EN TROIS CATÉGORIES STRICTES, et la Direction a insisté
 * sur « strictes » : un antécédent chirurgical rangé dans les médicaux se perd
 * au moment où le chirurgien en a besoin — c'est-à-dire avant d'ouvrir.
 *
 * L'EXAMEN PHYSIQUE SUIT LES QUATRE TEMPS CLASSIQUES — inspection, palpation,
 * percussion, auscultation — dans cet ordre. Un champ unique « examen » laisse
 * l'interne écrire trois lignes et oublier la percussion ; quatre champs
 * rappellent ce qui n'a pas été fait.
 * ======================================================================== */
(function (global) {
  'use strict';

  var D = global.SIGH.data;

  /* --------------------------------------------------------------------------
   * LES TROIS CATÉGORIES D'ANTÉCÉDENTS
   * ------------------------------------------------------------------------ */
  var CATEGORIES_ANTECEDENT = [
    {
      code: 'medicaux', label: 'Antécédents médicaux', icone: 'stethoscope',
      note: 'Maladies chroniques, affections traitées, allergies, traitements au long cours.',
      exemples: ['Hypertension artérielle', 'Diabète', 'Drépanocytose', 'Asthme',
        'Épilepsie', 'Tuberculose traitée', 'Hépatite B', 'Insuffisance rénale',
        'Ulcère gastro-duodénal', 'Allergie médicamenteuse'],
    },
    {
      code: 'chirurgicaux', label: 'Antécédents chirurgicaux', icone: 'scissors',
      note: 'Toute intervention subie, avec sa date et son indication. C’est la première '
        + 'chose que le chirurgien cherche avant d’ouvrir.',
      exemples: ['Appendicectomie', 'Césarienne', 'Herniorraphie', 'Cholécystectomie',
        'Hystérectomie', 'Ostéosynthèse', 'Amygdalectomie', 'Laparotomie exploratrice'],
    },
    {
      code: 'gyneco_obstetricaux', label: 'Antécédents gynéco-obstétricaux', icone: 'baby',
      note: 'Gestité, parité, avortements, enfants vivants, contraception, ménarche, DDR.',
      exemples: ['Gestité', 'Parité', 'Avortements', 'Enfants vivants',
        'Contraception en cours', 'Âge des premières règles', 'Date des dernières règles',
        'Accouchement dystocique antérieur'],
    },
  ];

  /* --------------------------------------------------------------------------
   * L'EXAMEN PHYSIQUE — QUATRE TEMPS, DANS L'ORDRE
   * ------------------------------------------------------------------------ */
  var TEMPS_EXAMEN = [
    { code: 'inspection', label: 'Inspection', ordre: 1,
      note: 'Ce que l’on voit : état général, coloration, morphologie, cicatrices, déformations.' },
    { code: 'palpation', label: 'Palpation', ordre: 2,
      note: 'Ce que l’on sent : masses, défense, douleur provoquée, adénopathies, organomégalie.' },
    { code: 'percussion', label: 'Percussion', ordre: 3,
      note: 'Ce que l’on entend en percutant : matité, tympanisme, sonorité.' },
    { code: 'auscultation', label: 'Auscultation', ordre: 4,
      note: 'Ce que l’on entend au stéthoscope : bruits du cœur, murmure vésiculaire, râles, souffles.' },
  ];

  /* --------------------------------------------------------------------------
   * LE CYCLE DE VIE DU DOSSIER DE CONSULTATION
   * ------------------------------------------------------------------------
   * Quatre états, dictés par la Direction. L'ordre importe : un dossier ne
   * saute pas de l'attente à la clôture — s'il le pouvait, on clôturerait des
   * consultations qui n'ont jamais eu lieu.
   *
   * « EN ATTENTE LABO » n'est pas un état de garage : c'est celui où le
   * clinicien a prescrit et attend, et c'est lui qui permet de compter les
   * dossiers suspendus à un résultat.
   * ---------------------------------------------------------------------- */
  var ETATS_DOSSIER = [
    { code: 'attente', label: 'EN ATTENTE', couleur: 'neutral', ordre: 1,
      note: 'Le patient est enregistré et attend d’être reçu.',
      suivants: ['consultation'] },
    { code: 'consultation', label: 'EN CONSULTATION', couleur: 'info', ordre: 2,
      note: 'Le soignant a pris le patient en charge.',
      suivants: ['attente_labo', 'cloture'] },
    { code: 'attente_labo', label: 'EN ATTENTE LABO', couleur: 'warning', ordre: 3,
      note: 'Des examens ont été prescrits ; la décision attend leurs résultats.',
      suivants: ['consultation', 'cloture'] },
    { code: 'cloture', label: 'CLÔTURÉ', couleur: 'success', ordre: 4,
      note: 'La consultation est terminée et le dossier arrêté.',
      suivants: [] },
  ];

  function etatDossier(code) {
    return ETATS_DOSSIER.filter(function (e) { return e.code === code; })[0] || ETATS_DOSSIER[0];
  }

  /* Une transition est-elle permise ? Refuser les sauts n'est pas une rigidité
     d'école : clôturer un dossier resté « en attente » signerait une
     consultation qui n'a pas eu lieu. */
  function transitionPermise(de, vers) {
    var e = etatDossier(de);
    return e.suivants.indexOf(vers) !== -1;
  }

  /* --------------------------------------------------------------------------
   * CE QUE LE CHIRURGIEN SEUL PEUT ÉCRIRE
   * ------------------------------------------------------------------------
   * Condition posée par la Direction : « Actes Chirurgicaux & Bloc = chirurgien
   * seulement ». Le généraliste tient tout le reste du dossier.
   *
   * La règle porte sur l'ÉCRITURE, pas sur la lecture : le généraliste doit
   * pouvoir lire ce que le chirurgien a écrit — c'est son patient aussi.
   * ---------------------------------------------------------------------- */
  var RUBRIQUES_CHIRURGICALES = ['actesChirurgicaux', 'indicationOperatoire', 'blocPrevu', 'risqueOperatoire'];

  function peutEcrireRubrique(rubrique, capacite) {
    if (RUBRIQUES_CHIRURGICALES.indexOf(rubrique) === -1) return { ok: true };
    if (capacite === 'chirurgien') return { ok: true };
    return {
      ok: false,
      motif: 'Les actes chirurgicaux et la programmation du bloc ne sont renseignés que par le '
        + 'chirurgien. Un généraliste peut les LIRE — c’est son patient aussi — mais non les écrire.',
    };
  }

  D.CATEGORIES_ANTECEDENT = CATEGORIES_ANTECEDENT;
  D.TEMPS_EXAMEN = TEMPS_EXAMEN;
  D.ETATS_DOSSIER = ETATS_DOSSIER;
  D.etatDossier = etatDossier;
  D.transitionPermise = transitionPermise;
  D.RUBRIQUES_CHIRURGICALES = RUBRIQUES_CHIRURGICALES;
  D.peutEcrireRubrique = peutEcrireRubrique;

  /* --------------------------------------------------------------------------
   * LE CHIRURGIEN REJOINT LE RÉFÉRENTIEL DES CAPACITÉS
   * ------------------------------------------------------------------------
   * Il n'y figurait pas : le prototype ne connaissait que « médecin ». Or la
   * Direction distingue explicitement ce que le généraliste et le chirurgien
   * peuvent écrire au dossier.
   * ---------------------------------------------------------------------- */
  if (D.CAPACITES && !D.CAPACITES.chirurgien) {
    D.CAPACITES.chirurgien = {
      label: 'Chirurgien', voirResultats: 'tous', voirEchographie: 'tous',
      prescrire: ['analyse', 'medicament', 'acte', 'hospitalisation', 'echographie', 'chirurgie'],
      executerSoins: false, remettreResultats: false,
      ecritRubriquesChirurgicales: true,
      note: 'Seul à renseigner les actes chirurgicaux et la programmation du bloc. '
        + 'Consulte le mardi et le jeudi (chirurgien-gynécologue).',
    };
  }
  if (D.CAPACITES && D.CAPACITES.medecin) {
    D.CAPACITES.medecin.ecritRubriquesChirurgicales = false;
  }
})(window);
