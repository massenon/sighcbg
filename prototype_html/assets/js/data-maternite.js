/* =============================================================================
 * RÉFÉRENTIELS MATERNITÉ — RAPPORT OFFICIEL DU 27/08/2026
 * -----------------------------------------------------------------------------
 * Source unique : « Intégration des Nouvelles Variables Cliniques, Registres
 * Hospitaliers & Édition Automatisée du Dossier Patient » (suite/), formalisé
 * entre l'équipe obstétricale, le laboratoire et les soins curatifs, complété
 * par les formulaires nationaux scannés (dossier obstétrical, grille CPN,
 * partographie, registre des accouchements, fiche de surveillance intégrée).
 *
 * RIEN N'EST INVENTÉ : chaque liste porte sa référence au rapport. Ce qui
 * a dû être supplété (bornes d'affichage, libellés courts) est marqué
 * `aValider` — même discipline que les valeurs de référence du laboratoire.
 * ========================================================================== */
(function (global) {
  'use strict';
  var D = global.SIGH.data;

  /* --------------------------------------------------------------------------
   * LES 10 FONCTIONS SONU — Tableau A du rapport
   * --------------------------------------------------------------------------
   * SONUB = 7 fonctions de base ; SONUC = les 3 complètes en sus. La
   * distinction est STRUCTURELLE : les rapports nationaux classent les
   * structures selon qu'elles posent 7 ou 10 fonctions.
   * ------------------------------------------------------------------------ */
  var SONU = {
    reference: 'Rapport maternité 27/08/2026 — Tableau A (directives OMS / SNIS / SONU)',
    fonctions: [
      [1, 'SONUB', 'Antibiotiques parentéraux', 'Ampicilline, gentamycine, métronidazole — infections maternelles et néonatales'],
      [2, 'SONUB', 'Anticonvulsivants parentéraux', 'Sulfate de magnésium (MgSO4) — éclampsie et pré-éclampsie sévère'],
      [3, 'SONUB', 'Oxytociques parentéraux', 'Ocytocine, GATPA — prévention et traitement de l’hémorragie du post-partum'],
      [4, 'SONUB', 'Délivrance artificielle et révision utérine', 'Extraction manuelle du placenta, vérification de la cavité utérine'],
      [5, 'SONUB', 'AMIU / curetage / curage', 'Aspiration Manuelle Intra-Utérine — avortement incomplet, rétention trophoblastique'],
      [6, 'SONUB', 'Ventouse obstétricale', 'Accouchement instrumental — assistance mécanique à l’expulsion fœtale'],
      [7, 'SONUB', 'Réanimation du nouveau-né', 'Désobstruction, ventilation au ballon et masque, réanimation cardio-pulmonaire néonatale'],
      [8, 'SONUC', 'Transfusion sanguine d’urgence', 'Choc hémorragique sévère obstétrical — fonction SONUC'],
      [9, 'SONUC', 'PEC éclampsie compliquée / chirurgie obstétricale', 'Soins intensifs, laparotomie d’urgence — rupture utérine, hémorragie réfractaire'],
      [10, 'SONUC', 'Césarienne d’urgence', 'Extraction fœtale d’urgence par voie haute au bloc — fonction SONUC'],
    ].map(function (f) {
      return { num: f[0], type: f[1], label: f[2], description: f[3], code: 'SONU' + f[0] };
    }),
  };
  function fonctionSONU(num) {
    return SONU.fonctions.filter(function (f) { return f.num === Number(num); })[0] || null;
  }

  /* --------------------------------------------------------------------------
   * LES 15 MÉTHODES CONTRACEPTIVES — Tableau B du rapport (registre PF)
   * --------------------------------------------------------------------------
   * Liste EXCLUSIVE (choix unique) et codification A/N : « A » = Nouvelle
   * Acceptante, « N » = Ancienne Acceptante (renouvellement ou changement).
   * La codification du rapport surprend (A pour nouvelle) : elle est reprise
   * TELLE QUELLE — c'est celle des registres papier nationaux.
   * ------------------------------------------------------------------------ */
  var METHODES_PF = [
    ['diu', 'DIU (cuivre / hormonal)', 'Longue durée', 'Stérilet de longue durée (5 à 10 ans)'],
    ['diu_pp', 'DIU PP Immédiat', 'Longue durée', 'Insertion dans les 10 min à 48 h après l’accouchement'],
    ['noristerat', 'Noristérat', 'Courte durée', 'Injection hormonale tous les 2 mois'],
    ['depo_im', 'Depo IM (Dépo-Provera)', 'Courte durée', 'Injectable intramusculaire tous les 3 mois'],
    ['dmpa_sc', 'DMPA-SC Sayana Press', 'Courte durée', 'Auto-injection ou injection CS sous-cutanée de 3 mois'],
    ['co', 'CO (Contraceptifs Oraux)', 'Courte durée', 'Pilule œstro-progestative quotidienne'],
    ['jadelle', 'Jadelle (2 bâtonnets)', 'Longue durée', 'Implant efficace 5 ans'],
    ['implanon', 'Implanon / Nexplanon (1 bâtonnet)', 'Longue durée', 'Implant efficace 3 ans'],
    ['jadelle_pp', 'Jadelle PP Immédiat', 'Longue durée', 'Pose en post-partum immédiat, en salle de maternité'],
    ['implanon_pp', 'Implanon PP Immédiat', 'Longue durée', 'Pose en post-partum immédiat'],
    ['pilule', 'Pilule microprogestative', 'Courte durée', 'Compatible avec l’allaitement maternel'],
    ['ligature', 'Ligature des trompes', 'Définitive', 'Contraception chirurgicale volontaire féminine'],
    ['vasectomie', 'Vasectomie', 'Définitive', 'Stérilisation masculine volontaire ambulatoire'],
    ['collier', 'Collier du cycle / MAMA', 'Naturelle / barrière', 'Méthodes naturelles, allaitement maternel et aménorrhée'],
    ['preservatif', 'Préservatifs masculins / féminins', 'Naturelle / barrière', 'Méthode barrière et double protection VIH/IST'],
  ].map(function (m) {
    return { code: m[0], label: m[1], categorie: m[2], specification: m[3] };
  });
  function methodePF(code) {
    return METHODES_PF.filter(function (m) { return m.code === code; })[0] || null;
  }
  var STATUTS_ACCEPTANTE = [
    { code: 'A', label: 'A — Nouvelle acceptante' },
    { code: 'N', label: 'N — Ancienne acceptante (renouvellement / changement)' },
  ];

  /* --------------------------------------------------------------------------
   * CPN — suivi de grossesse (Module B + tableau 8 du rapport)
   * ------------------------------------------------------------------------ */
  var DOSES_SP = ['SP1', 'SP2', 'SP3', 'SP4', 'SP5'];
  var TYPES_CPON = [
    { code: 'cpon1', label: 'CPoN 1', fenetre: '6 h – 24 h (J0-J1)' },
    { code: 'cpon2', label: 'CPoN 2', fenetre: 'J6 – J14' },
    { code: 'cpon3', label: 'CPoN 3', fenetre: '6ᵉ semaine' },
  ];

  /* --------------------------------------------------------------------------
   * NOUVEAU-NÉ — bornes du Module C
   * --------------------------------------------------------------------------
   * PC 32,0–38,0 cm ; PT 30,0–36,0 cm ; alerte si Apgar à 5 min < 7/10.
   * Ce sont les bornes ÉCRITES du rapport, pas des valeurs de manuel.
   * ------------------------------------------------------------------------ */
  var BORNES_NOUVEAU_NE = {
    pc: { min: 32, max: 38, unite: 'cm', libelle: 'Périmètre crânien' },
    pt: { min: 30, max: 36, unite: 'cm', libelle: 'Périmètre thoracique' },
    apgarSeuil5min: 7,
    source: 'Rapport maternité 27/08/2026 — Module C et §5.4 (alertes de sécurité clinique)',
  };
  /* Facteur de risque CPN : âge < 18 ans ou > 35 ans (§5.4 du rapport). */
  var AGES_RISQUE_CPN = { min: 18, max: 35 };

  var SOINS_ESSENTIELS_NN = ['Vitamine K1', 'Collyre tétracycline', 'Chlorhexidine 7,1 % (cordon)'];

  /* --------------------------------------------------------------------------
   * SOINS CURATIFS & URGENCES MATERNITÉ — Module E (Case 27 restructurée)
   * ------------------------------------------------------------------------ */
  var URGENCES_MATERNITE = [
    { code: 'referee', label: 'Femme en travail référée d’urgence' },
    { code: 'referee_admise', label: 'Référée d’urgence ET admise à l’hôpital de référence' },
    { code: 'referee_pec', label: 'Référée d’urgence ET prise en charge par l’hôpital de référence' },
  ];
  var TRANCHES_AGE_CURATIF = ['< 1 mois', '1–11 mois', '1–4 ans', '5–9 ans', '10–14 ans',
    '15–19 ans', '20–24 ans', '25 ans et +'];

  /* --------------------------------------------------------------------------
   * RÉFÉRENCE / CONTRE-RÉFÉRENCE — Module G (compléments)
   * ------------------------------------------------------------------------ */
  var TRANSPORTS_REFERENCE = ['Ambulance', 'Taxi', 'Moto', 'Barque', 'À pied', 'Autre'];
  var EVOLUTIONS_MALADIE = ['Guéri', 'Évadé', 'Décédé', 'Sortie contre avis médical', 'Référé'];

  /* --------------------------------------------------------------------------
   * PTME — registre quadripartite (Module I)
   * ------------------------------------------------------------------------ */
  var PTME = {
    reference: 'Rapport maternité 27/08/2026 — Module I et tableau 6 (protocoles PTME)',
    prophylaxiesNN: [
      { code: 1, label: 'NVP' }, { code: 2, label: 'AZT' },
      { code: 3, label: 'AZT + NVP' }, { code: 4, label: 'Aucune' },
    ],
    allaitements: ['Exclusif', 'Artificiel', 'Mixte'],
    dureesARV: ['< 8 semaines', '≥ 8 semaines'],
    suivisEnfant: ['PCR naissance', 'PCR-1 (6 semaines)', 'PCR-2 (9 mois)', 'Sérologie VIH (18 mois)'],
  };

  /* --------------------------------------------------------------------------
   * ACCOUCHEMENT — types et actes associés (cible Instructions + registre)
   * ------------------------------------------------------------------------ */
  var TYPES_ACCOUCHEMENT = ['Eutocique', 'Dystocique', 'Dirigé', 'Gemellaire', 'Trimellaire', 'Césarienne'];
  var ACTES_ACCOUCHEMENT = ['Épisiotomie', 'Délivrance artificielle', 'Révision utérine',
    'AMIU', 'Ventouse obstétricale', 'GATPA'];

  /* --------------------------------------------------------------------------
   * PARTOGRAMME — le modèle de la PARTOGRAPHIE nationale scannée
   * --------------------------------------------------------------------------
   * La ligne d'ALERTE part de 4 cm et progresse de 1 cm/h ; la ligne d'ACTION
   * lui est parallèle, décalée de 4 heures. Codes actions 1-7 du formulaire.
   * ------------------------------------------------------------------------ */
  var PARTOGRAMME = {
    alerteDepart: 4, alerteParHeure: 1, actionDecalageHeures: 4,
    liquides: [
      { code: 'I', label: 'I — Poche des eaux intacte' },
      { code: 'C', label: 'C — Liquide clair' },
      { code: 'M', label: 'M — Méconial (purée de pois)' },
      { code: 'S', label: 'S — Sanglant / hématique' },
      { code: 'V', label: 'V — « Jus de viande »' },
      { code: 'J', label: 'J — Jaunâtre' },
    ],
    actions: ['Rupture artificielle de la PDE', 'Antispasmodique', 'Ocytocine', 'Épisiotomie',
      'Ventouse / Forceps', 'Référence', 'Césarienne / Laparotomie'],
    source: 'PARTOGRAPHIE — formulaire national scanné (suite/, p. 6)',
  };

  /* --------------------------------------------------------------------------
   * ÉDITION AUTOMATISÉE & INDICATEURS (Modules J et §5.3)
   * ------------------------------------------------------------------------ */
  var INDICATEURS_DHIS2 = [
    { code: 'pf_acceptation', label: 'Taux d’acceptation PF (nouvelles acceptantes)' },
    { code: 'gar', label: 'Proportion de grossesses à risque (GAR)' },
    { code: 'sp3', label: 'Couverture SP3' },
    { code: 'sp5', label: 'Couverture SP5' },
    { code: 'milda', label: 'Couverture MILDA' },
    { code: 'transferts', label: 'Parturientes transférées admises et prises en charge' },
  ];

  /* --- Exposition ---------------------------------------------------------- */
  D.SONU = SONU;
  D.fonctionSONU = fonctionSONU;
  D.METHODES_PF = METHODES_PF;
  D.methodePF = methodePF;
  D.STATUTS_ACCEPTANTE = STATUTS_ACCEPTANTE;
  D.DOSES_SP = DOSES_SP;
  D.TYPES_CPON = TYPES_CPON;
  D.BORNES_NOUVEAU_NE = BORNES_NOUVEAU_NE;
  D.AGES_RISQUE_CPN = AGES_RISQUE_CPN;
  D.SOINS_ESSENTIELS_NN = SOINS_ESSENTIELS_NN;
  D.URGENCES_MATERNITE = URGENCES_MATERNITE;
  D.TRANCHES_AGE_CURATIF = TRANCHES_AGE_CURATIF;
  D.TRANSPORTS_REFERENCE = TRANSPORTS_REFERENCE;
  D.EVOLUTIONS_MALADIE = EVOLUTIONS_MALADIE;
  D.PTME = PTME;
  D.TYPES_ACCOUCHEMENT = TYPES_ACCOUCHEMENT;
  D.ACTES_ACCOUCHEMENT = ACTES_ACCOUCHEMENT;
  D.PARTOGRAMME = PARTOGRAMME;
  D.INDICATEURS_DHIS2 = INDICATEURS_DHIS2;
})(window);
