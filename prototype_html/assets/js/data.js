/* =============================================================================
 * SIGH-CBG — Référentiels
 * -----------------------------------------------------------------------------
 * PRINCIPE (draf1 §1-2, §22) : « ne pas inventer la clinique ».
 * Chaque référentiel porte sa `source` — le document de cadrage dont il provient.
 * Les règles métier (NS 131, NS 132) sont VERSIONNÉES avec date d'effet, afin
 * qu'une note de service ultérieure n'écrase pas l'historique (draf1 §5-6, §23).
 *
 * Légende `source` :
 *   DOC   = transcrit d'un document réel fourni par la clinique
 *   CDCT  = Cahier des Charges Technique
 *   DEMO  = jeu de démonstration (à remplacer par la reprise de données, CDCT §24)
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core;

  /* ==========================================================================
   * 1. ORGANIGRAMME — source : Instructions.txt (Direction, 02/09/2026)
   * Pilote la structure organisationnelle ET le RBAC (draf1 §4).
   * ======================================================================== */
  /* L'ORGANIGRAMME BAGUIDI — les HUIT agents d'Instructions.txt, exactement.
     Celui de la clinique d'origine (44 agents nommés) a été retiré le
     07/09/2026 : il paraissait encore à l'écran « Organisation &
     organigramme ». L'effectif réel complet de BAGUIDI n'a pas été fourni ;
     aucun poste ne s'invente, et les services qui n'ont pas de titulaire
     nommé n'apparaissent pas. */
  var ORGANIGRAMME = {
    source: 'Instructions.txt — les huit comptes arrêtés par la Direction le 02/09/2026',
    effectifTotal: 8,
    aCompleter: true,
    noteEffectif: 'Effectif limité aux huit agents dont la Direction a fourni le nom. '
      + 'L’organigramme complet reste à communiquer.',
    racine: {
      poste: 'Directeur Général', effectif: 1, titulaire: 'GBAGUIDI Rafiou', role: 'direction',
      enfants: [
        { poste: 'Direction', effectif: 1, titulaire: 'SOKOU Peace', role: 'direction' },
        {
          poste: 'Comptabilité', effectif: 2, titulaire: 'SANOUSSI Adamon', chef: true, role: 'comptable',
          enfants: [{ poste: 'Comptable', effectif: 1, titulaire: 'ZIME Nadège', role: 'comptable' }],
        },
        {
          poste: 'Ressources humaines', effectif: 2, titulaire: 'MABOUDOU Nawal', chef: true, role: 'rh',
          enfants: [{ poste: 'Responsable RH', effectif: 1, titulaire: 'TOUNGOUH A. Zoulkifouli', role: 'rh' }],
        },
        { poste: 'Médecine générale', effectif: 1, titulaire: 'IDOHOU Abraham', role: 'medecin' },
        { poste: 'Soins infirmiers', effectif: 1, titulaire: 'AKONDE Octave', role: 'infirmier' },
      ],
    },
  };

  /* Fonctions = colonnes de la grille des primes NS 132 */
  var FONCTIONS = [
    { id: 'aide_soignant', label: 'Aide-soignant(e)', categorie: 'Paramédical' },
    { id: 'caissiere', label: 'Caissière', categorie: 'Administratif' },
    { id: 'accueil', label: 'Accueil / Secrétaire médical', categorie: 'Administratif' },
    { id: 'infirmier', label: 'Infirmier(ère)', categorie: 'Paramédical' },
    { id: 'sage_femme', label: 'Sage-femme', categorie: 'Paramédical' },
    { id: 'tsl', label: 'TSL (Technicien Supérieur de Laboratoire)', categorie: 'Technique' },
    /* Ajoutée le 25/08/2026 : la Direction a nommé un Ingénieur Biomédical,
       qui entretient les automates sans rendre de résultats. Le confondre avec
       un technicien de laboratoire lui ouvrirait la validation biologique. */
    { id: 'biomedical', label: 'Ingénieur biomédical', categorie: 'Technique' },
    { id: 'medecin', label: 'Médecin', categorie: 'Médical' },
    { id: 'direction', label: 'Direction', categorie: 'Direction' },
    { id: 'comptable', label: 'Comptable', categorie: 'Administratif' },
    { id: 'stock', label: 'Gestionnaire de stock', categorie: 'Logistique' },
    { id: 'dispensatrice', label: 'Dispensatrice', categorie: 'Pharmacie' },
    { id: 'securite', label: 'Agent de sécurité', categorie: 'Support' },
    { id: 'entretien', label: 'Agent d’entretien', categorie: 'Support' },
    { id: 'chauffeur', label: 'Chauffeur coursier', categorie: 'Support' },
  ];

  /* ==========================================================================
   * 2. NS 132/07/DM/DA/CNT/2026 — GRILLE DES PRIMES DIVERSES
   * source : docs/notes_de_services.jpeg — signée le 13/07/2026
   * Moteur des primes (draf1 §6). Montants en FCFA.
   * `mode` : 'occurrence' = varie selon le nombre d'actes/gardes
   *          'fixe'       = montant mensuel forfaitaire
   * ======================================================================== */
  var NS132 = {
    reference: 'NS n° 132/07/DM/DA/CNT/2026',
    objet: 'Primes diverses',
    version: 1,
    dateSignature: '2026-07-13',
    dateEffet: '2026-07-13',
    statut: 'ACTIVE',
    signataire: null,
    noteSignataire: 'Note de service héritée du prototype d’origine — signataire BAGUIDI à désigner.',
    recuPar: 'KASSA A. B. Augustin — reçu le 13/07/2026',
    source: 'DOC — Note de service NS 132/07/DM/DA/CNT/2026',
    mention: 'Abroge toute disposition antérieure contraire.',
    primes: [
      { id: 'permanence', label: 'Permanence', mode: 'occurrence',
        montants: { aide_soignant: 600, caissiere: 600, accueil: 700, infirmier: 800, sage_femme: 800, tsl: 800 } },
      { id: 'garde', label: 'Garde', mode: 'occurrence',
        montants: { aide_soignant: 900, caissiere: 900, accueil: 900, infirmier: 1500, sage_femme: 1500, tsl: 1500 } },
      { id: 'aide_bloc', label: 'Aide bloc', mode: 'occurrence',
        montants: { aide_soignant: 500, caissiere: 500, accueil: 500, infirmier: 500, sage_femme: 500 } },
      { id: 'bloc_fixe', label: 'Prime de bloc fixe', mode: 'fixe',
        montants: { aide_soignant: 10000, infirmier: 10000 } },
      { id: 'hydrotubation', label: 'Hydrotubation', mode: 'occurrence',
        montants: { infirmier: 1300 } },
      { id: 'accouchement', label: 'Accouchement', mode: 'occurrence',
        montants: { sage_femme: 1000 } },
      { id: 'caisse', label: 'Caisse', mode: 'fixe',
        montants: { caissiere: 10000 } },
      { id: 'urgence', label: 'Urgence', mode: 'occurrence',
        montants: { tsl: 2500 } },
      { id: 'incineration', label: 'Incinération', mode: 'fixe',
        montants: { aide_soignant: 5000 } },
      { id: 'accueil', label: 'Accueil', mode: 'fixe',
        montants: { accueil: 7000 } },
      { id: 'circoncision', label: 'Circoncision', mode: 'occurrence',
        montants: { sage_femme: 1000 } },
    ],
    /**
     * Montant applicable à une fonction pour une prime donnée, à une DATE.
     *
     * La grille vit désormais dans le magasin (collection `grillePrimes`) :
     * la Direction peut la modifier sans toucher au code. Le tableau statique
     * ci-dessus reste le barème d'origine, et sert de repli tant que le
     * magasin n'est pas chargé — c'est le cas au tout premier amorçage.
     *
     * Le troisième argument est ce qui distingue ce moteur d'une simple table :
     * une prime modifiée le 20 août ne doit pas changer la prime de juillet,
     * déjà calculée et souvent déjà payée. Les versions antérieures sont
     * conservées dans `historiquePrimes` et retrouvées par leur date d'effet.
     */
    montant: function (primeId, fonctionId, date) {
      var st = global.SIGH && global.SIGH.store;
      if (!st) return NS132.montantOrigine(primeId, fonctionId);
      var grille, courant;
      try {
        grille = st.collection('grillePrimes').active();
        courant = grille.filter(function (x) { return x.primeId === primeId; })[0];
      } catch (e) { return NS132.montantOrigine(primeId, fonctionId); }
      /* LA GRILLE DU MAGASIN FAIT FOI dès qu'elle est joignable. Une grille
         VIDE n'est pas une grille absente : c'est une clinique qui ne verse
         pas de prime — chez BAGUIDI, décision de la Direction du 07/09/2026.
         Retomber alors sur la grille d'origine ferait payer des primes que
         personne n'a décidées, et le dispositif « désactivé » n'en serait pas
         un. La grille de la note d'origine ne sert plus qu'à un poste dont le
         magasin est injoignable. */
      if (!grille.length) return 0;
      if (!courant) return 0;

      /* Sans date, ou si la version courante était déjà en vigueur : la grille
         du jour s'applique. */
      if (!date || !courant.dateEffet || String(date) >= String(courant.dateEffet)) {
        return (courant.montants || {})[fonctionId] || 0;
      }

      /* Sinon on remonte l'historique jusqu'à la version en vigueur ce jour-là. */
      var versions = [];
      try {
        versions = st.collection('historiquePrimes').active()
          .filter(function (x) { return x.primeId === primeId; });
      } catch (e) { versions = []; }
      var enVigueur = versions
        .filter(function (v) {
          return (!v.dateEffet || String(date) >= String(v.dateEffet))
            && (!v.dateFin || String(date) <= String(v.dateFin));
        })
        .sort(function (a, b) { return String(b.dateEffet).localeCompare(String(a.dateEffet)); })[0];
      if (enVigueur) return (enVigueur.montants || {})[fonctionId] || 0;
      return NS132.montantOrigine(primeId, fonctionId);
    },

    /** Le barème d'origine de la note, indépendant du magasin. */
    montantOrigine: function (primeId, fonctionId) {
      var p = null;
      for (var i = 0; i < NS132.primes.length; i++) if (NS132.primes[i].id === primeId) p = NS132.primes[i];
      return (p && p.montants[fonctionId]) || 0;
    },
  };

  /* ==========================================================================
   * 2 bis. FRAIS DE PARTICIPATION AUX ÉVÉNEMENTS DU PERSONNEL
   * --------------------------------------------------------------------------
   * Quand un événement touche un agent — mariage, naissance, décès dans sa
   * famille — le personnel se cotise. La contribution est de 1 000 FCFA par
   * agent, montant STANDARD et non figé : la Direction peut le porter plus
   * haut pour un événement particulier, et le montant retenu reste attaché à
   * l'événement, jamais au paramètre global. Changer le standard demain ne
   * doit pas réécrire ce que chacun a versé hier.
   *
   * Deux modes de règlement, au choix de l'agent :
   *   — IMPUTATION SUR SALAIRE : la contribution figure au bulletin du mois
   *     de retenue, comme une retenue ordinaire ;
   *   — PAIEMENT AU COMPTANT : l'agent verse à la caisse, et l'historique du
   *     versement est conservé (date, reçu, encaisseur).
   *
   * Ces sommes ne sont ni une recette de la clinique ni une charge : elles
   * transitent. La clinique collecte pour le compte du collectif.
   * ======================================================================== */
  var PARAM_EVENEMENTS = {
    montantStandard: 1000,
    source: 'Usage de la clinique — participation du personnel aux événements',
    natures: [
      { id: 'mariage', label: 'Mariage', icon: 'heart', tone: 'success' },
      { id: 'naissance', label: 'Naissance', icon: 'baby', tone: 'info' },
      { id: 'deces', label: 'Décès', icon: 'flower', tone: 'neutral' },
      { id: 'bapteme', label: 'Baptême', icon: 'church', tone: 'info' },
      { id: 'retraite', label: 'Départ à la retraite', icon: 'party-popper', tone: 'warning' },
      { id: 'maladie', label: 'Soutien maladie', icon: 'heart-pulse', tone: 'danger' },
      { id: 'autre', label: 'Autre événement', icon: 'calendar-heart', tone: 'navy' },
    ],
    modes: [
      { id: 'salaire', label: 'Imputation sur salaire', hint: 'Retenue portée au bulletin du mois choisi' },
      { id: 'comptant', label: 'Paiement au comptant', hint: 'Versement à la caisse, avec reçu' },
    ],
    /** Le libellé d'une nature, ou son identifiant à défaut. */
    nature: function (id) {
      var n = PARAM_EVENEMENTS.natures.filter(function (x) { return x.id === id; })[0];
      return n ? n.label : id;
    },
  };

  /* ==========================================================================
   * 2 quater. LES ÉTATS D'UN RÉSULTAT D'ANALYSE
   * --------------------------------------------------------------------------
   * Deux verrous, demandés par le biologiste. Ce qui les sépare n'est pas une
   * formalité : entre les deux, le résultat existe mais le prescripteur ne le
   * voit pas. C'est la fenêtre pendant laquelle le laboratoire relit.
   * ======================================================================== */
  var ETATS_RESULTAT = [
    { id: 'en_attente', label: 'En attente', tone: 'neutral', ordre: 1,
      aide: 'Demande enregistrée, prélèvement non effectué.' },
    { id: 'attente_prelevement', label: 'Réglé — à prélever', tone: 'warning', ordre: 2,
      aide: 'La caisse a encaissé : le prélèvement peut avoir lieu.' },
    { id: 'preleve', label: 'Prélevé', tone: 'info', ordre: 3,
      aide: 'Échantillon prélevé, à acheminer au laboratoire.' },
    { id: 'en_cours', label: 'Au laboratoire', tone: 'info', ordre: 4,
      aide: 'Échantillon reçu, analyse en cours.' },
    { id: 'saisi', label: 'Saisi, non validé', tone: 'warning', ordre: 5,
      aide: 'Résultat porté mais non validé : ni le laboratoire ni le prescripteur ne s’y fient encore.' },
    { id: 'valide_technique', label: 'Validation technique', tone: 'navy', ordre: 6,
      aide: 'Le technicien a validé sa saisie. Le prescripteur NE VOIT PAS ENCORE le résultat : '
        + 'c’est la fenêtre pendant laquelle le laboratoire relit.' },
    { id: 'valide', label: 'Validé biologiquement', tone: 'success', ordre: 7,
      aide: 'Validation biologique portée : le résultat est visible du prescripteur et fait foi.' },
    { id: 'rectifie', label: 'Rectifié', tone: 'danger', ordre: 8,
      aide: 'Une version rectificative a été émise après validation biologique. '
        + 'Le prescripteur est notifié que ce qu’il a lu a changé.' },
  ];

  /** L'état par son identifiant. */
  function etatResultat(id) {
    return ETATS_RESULTAT.filter(function (x) { return x.id === id; })[0]
      || { id: id, label: id || '—', tone: 'neutral', ordre: 0 };
  }

  /** Un résultat est-il opposable au prescripteur ? */
  function resultatRendu(etat) {
    return etat === 'valide' || etat === 'rectifie';
  }

  /* ==========================================================================
   * 2 ter. PATHOLOGIES — référentiel de morbidité
   * --------------------------------------------------------------------------
   * Le diagnostic est une PHRASE que le médecin rédige ; la pathologie est un
   * CODE que la clinique compte. Les confondre rend toute statistique de
   * morbidité impossible — « paludisme simple », « accès palustre » et « palu »
   * ne se regroupent pas d'eux-mêmes.
   *
   * Les deux coexistent donc sur la consultation : la pathologie pour compter,
   * le diagnostic rédigé pour dire ce que ce cas-là avait de particulier.
   *
   * Le classement suit les grands chapitres de la CIM-10 sans en reprendre la
   * codification : la clinique ne code pas en CIM, et lui imposer une
   * nomenclature qu'elle n'emploie pas ferait saisir n'importe quoi. La liste
   * est ADMINISTRABLE — c'est le tableau de morbidité de la clinique qui doit
   * la faire évoluer, pas une mise à jour du logiciel.
   * ======================================================================== */
  var CHAPITRES_PATHOLOGIE = [
    { id: 'infectieuses', label: 'Maladies infectieuses et parasitaires', tone: 'danger' },
    { id: 'respiratoire', label: 'Appareil respiratoire', tone: 'info' },
    { id: 'digestif', label: 'Appareil digestif', tone: 'warning' },
    { id: 'cardiovasculaire', label: 'Appareil circulatoire', tone: 'danger' },
    { id: 'genito', label: 'Appareil génito-urinaire', tone: 'navy' },
    { id: 'grossesse', label: 'Grossesse, accouchement et puerpéralité', tone: 'success' },
    { id: 'metabolique', label: 'Endocrinien, nutritionnel et métabolique', tone: 'warning' },
    { id: 'sang', label: 'Sang et organes hématopoïétiques', tone: 'danger' },
    { id: 'peau', label: 'Peau et tissu cellulaire sous-cutané', tone: 'neutral' },
    { id: 'osteo', label: 'Système ostéo-articulaire', tone: 'neutral' },
    { id: 'traumatismes', label: 'Traumatismes et empoisonnements', tone: 'danger' },
    { id: 'autres', label: 'Autres motifs de recours', tone: 'neutral' },
  ];

  var PATHOLOGIES = [
    /* [code, libellé, chapitre, notifiable] */
    ['PAL-S', 'Paludisme simple', 'infectieuses', true],
    ['PAL-G', 'Paludisme grave', 'infectieuses', true],
    ['TYPH', 'Fièvre typhoïde', 'infectieuses', true],
    ['MENI', 'Méningite', 'infectieuses', true],
    ['TUBE', 'Tuberculose', 'infectieuses', true],
    ['VIH', 'Infection à VIH', 'infectieuses', true],
    ['HEPB', 'Hépatite virale B', 'infectieuses', true],
    ['HEPC', 'Hépatite virale C', 'infectieuses', true],
    ['ROUG', 'Rougeole', 'infectieuses', true],
    ['CHOL', 'Choléra', 'infectieuses', true],
    ['SCHI', 'Bilharziose', 'infectieuses', false],
    ['AMIB', 'Amibiase', 'infectieuses', false],
    ['HELM', 'Helminthiase intestinale', 'infectieuses', false],

    ['IRA', 'Infection respiratoire aiguë', 'respiratoire', false],
    ['BRON', 'Bronchite aiguë', 'respiratoire', false],
    ['PNEU', 'Pneumopathie', 'respiratoire', false],
    ['ASTH', 'Asthme', 'respiratoire', false],
    ['ANGI', 'Angine', 'respiratoire', false],

    ['GEA', 'Gastro-entérite aiguë', 'digestif', false],
    ['UGD', 'Ulcère gastro-duodénal', 'digestif', false],
    ['APPE', 'Appendicite', 'digestif', false],
    ['HERN', 'Hernie', 'digestif', false],
    ['HEMO', 'Hémorroïdes', 'digestif', false],

    ['HTA', 'Hypertension artérielle essentielle', 'cardiovasculaire', false],
    ['INSC', 'Insuffisance cardiaque', 'cardiovasculaire', false],
    ['AVC', 'Accident vasculaire cérébral', 'cardiovasculaire', false],

    ['IUB', 'Infection urinaire basse', 'genito', false],
    ['PYEL', 'Pyélonéphrite', 'genito', false],
    ['IST', 'Infection sexuellement transmissible', 'genito', true],
    ['PROS', 'Pathologie prostatique', 'genito', false],
    ['FIBR', 'Fibrome utérin', 'genito', false],

    ['GROS', 'Grossesse évolutive', 'grossesse', false],
    ['HTAG', 'Hypertension gravidique', 'grossesse', false],
    ['ECLA', 'Pré-éclampsie et éclampsie', 'grossesse', true],
    ['MAP', 'Menace d’accouchement prématuré', 'grossesse', false],
    ['AVOR', 'Avortement', 'grossesse', false],
    ['HPP', 'Hémorragie du post-partum', 'grossesse', true],

    ['DIA2', 'Diabète de type 2', 'metabolique', false],
    ['DIA1', 'Diabète de type 1', 'metabolique', false],
    ['MALN', 'Malnutrition', 'metabolique', true],
    ['DYSL', 'Dyslipidémie', 'metabolique', false],

    ['ANEM', 'Anémie ferriprive', 'sang', false],
    ['DREP', 'Drépanocytose', 'sang', false],

    ['DERM', 'Dermatose infectieuse', 'peau', false],
    ['PLAI', 'Plaie et abcès', 'peau', false],

    ['LOMB', 'Lombalgie', 'osteo', false],
    ['ARTH', 'Arthrose', 'osteo', false],

    ['AVP', 'Accident de la voie publique', 'traumatismes', false],
    ['FRAC', 'Fracture', 'traumatismes', false],
    ['BRUL', 'Brûlure', 'traumatismes', false],
    ['INTO', 'Intoxication', 'traumatismes', true],

    ['CONS', 'Consultation de contrôle', 'autres', false],
    ['CPN', 'Consultation prénatale', 'autres', false],
    ['VACC', 'Vaccination', 'autres', false],
    ['CERT', 'Certificat médical', 'autres', false],
  ].map(function (x, i) {
    return {
      id: 'PATH' + (i + 1 < 10 ? '0' : '') + (i + 1),
      code: x[0], libelle: x[1], chapitre: x[2],
      /* Une pathologie « notifiable » relève de la déclaration obligatoire aux
         autorités sanitaires. Le marquer permet à la clinique de repérer les
         cas à déclarer sans relire tout le registre. */
      notifiable: !!x[3],
      statut: 'actif',
      aValider: true,
      source: 'Liste de morbidité proposée — à arrêter par le Directeur Médical',
    };
  });

  /* ==========================================================================
   * 3. NS 131/07/DM/DA/CNT/2026 — BARÈME D'ÉVALUATION & SANCTIONS
   * source : docs/fiche_crtitere_evaluation_advanced.jpeg — signée le 13/07/2026
   * Moteur d'évaluation + sanctions (draf1 §5). Retenues en % du SALAIRE BRUT.
   * ======================================================================== */
  var NS131 = {
    reference: 'NS 131/07/DM/DA/CNT/2026',
    objet: 'Modification de l’évaluation du rendement entrant dans le compte de la rémunération salariale',
    version: 1,
    dateSignature: '2026-07-13',
    dateEffet: '2026-07-13',
    statut: 'ACTIVE',
    signataire: null,
    noteSignataire: 'Note de service héritée du prototype d’origine — signataire BAGUIDI à désigner.',
    ampliation: 'Intéressés 41 — Archive 01',
    source: 'DOC — Note de service NS 131/07/DM/DA/CNT/2026',
    mention: 'Abroge toute disposition antérieure contraire.',
    niveaux: [
      { id: 'bonne', label: 'Bonne', aide: 'Aucune sanction' },
      { id: 'moyenne', label: 'Moyenne', aide: '1er niveau de faute — 1 à 2 manquements' },
      { id: 'faible', label: 'Faible à mauvaise', aide: '2e niveau de faute — 3 manquements et plus' },
    ],
    criteres: [
      {
        num: '01', id: 'ponctualite', label: 'Ponctualité et assiduité',
        criteres: ['Retard', 'Sortie non autorisée', 'Absence au poste',
          'Assemblée de bavardage', 'Dormir aux heures de travail', 'Usage de portable'],
        sanctions: { bonne: 0, moyenne: 6, faible: 10 },
      },
      {
        num: '02', id: 'execution', label: 'Exécution des tâches',
        criteres: ['Tâches non exécutées', 'Tâches mal exécutées'],
        sanctions: { bonne: 0, moyenne: 10, faible: 15 },
      },
      {
        num: '03', id: 'attitude', label: 'Attitude envers les patients',
        criteres: ['Parler mal au malade', 'Dispute avec malade',
          'Insulter ou critiquer le malade', 'Renvoi de malade'],
        sanctions: { bonne: 0, moyenne: 6, faible: 10 },
      },
      {
        num: '04', id: 'hierarchie', label: 'Respect de la hiérarchie',
        criteres: ['Manque de courtoisie', 'Indiscrétion', 'Manque d’intégrité'],
        sanctions: { bonne: 0, moyenne: 6, faible: 10 },
      },
    ],
    /** Total du prélèvement (% du brut) pour une évaluation {critereId: niveauId}. */
    prelevement: function (evaluation) {
      return NS131.criteres.reduce(function (total, c) {
        return total + (c.sanctions[evaluation[c.id]] || 0);
      }, 0);
    },
  };

  /* ==========================================================================
   * 4. COMPAGNIES D'ASSURANCE PARTENAIRES (13)
   * source : docs/liste_assurances_partenaires.jpeg
   * ======================================================================== */
  var ASSUREURS = [
    { n: 1, code: 'AFR', nom: 'AFRICAINE DES ASSURANCES', tel: ['0195262340', '0195965236'], email: 'directiongenerale@african-assur.com' },
    { n: 2, code: 'NSIA', nom: 'NSIA ASSURANCE', tel: ['0153212091', '0196043695', '0196929656'], email: 'nsiabenin@groupensia.com' },
    { n: 3, code: 'OLEA', nom: 'OLEA ASSURANCE', tel: ['0169406666'], email: 'jb.allyn@olea.africa' },
    { n: 4, code: 'SANLAM', nom: 'SANLAM ASSURANCE', tel: ['0197511275', '0197059564'], email: 'prestation.sante@bj.sanlamallianz.com' },
    { n: 5, code: 'TRANSVIE', nom: 'TRANSVIE ASSURANCE', tel: ['0160225555', '0197804140'], email: 'a.kponou@trasvie.bj' },
    { n: 6, code: 'SUNU', nom: 'SUNU ASSURANCE', tel: ['0152197878'], email: 'benin.iard@sunu-group.com' },
    { n: 7, code: 'DAYO', nom: 'DAYO ASSURANCE', tel: ['0161115844', '0169083881', '0152529898'], email: 'administration@dayo.africa' },
    { n: 8, code: 'SOS', nom: 'SOS ASSURANCE', tel: ['0196265551', '0161392410'], email: 'infos@sos-benin.org' },
    { n: 9, code: 'GAB', nom: 'GAB ASSURANCE', tel: ['0196100720', '0169550000'], email: 'info@gabassurance.com' },
    { n: 10, code: 'BECOTRA', nom: 'BECOTRA ASSURANCE', tel: ['0159112138'], email: 'contact@becotrac.com' },
    { n: 11, code: 'NOBILA', nom: 'NOBILA ASSURANCE', tel: ['0161655800', '0164218181'], email: 'contact@nobilaassurances.com' },
    { n: 12, code: 'ASCOMA', nom: 'ASCOMA ASSURANCE', tel: ['0197084698', '0160647171'], email: 'benin@ascoma.com' },
    { n: 13, code: 'ASK', nom: 'ASK ASSURANCE BENIN', tel: ['0197331477', '0121303130', '0137449149'], email: 'sariatou.adedjouma@bj.askgs.africa' },
  ];
  ASSUREURS.source = 'DOC — Liste et contact des assurances partenaires';

  /* ==========================================================================
   * BARÈME DE PRISE EN CHARGE — modèle de grille
   * --------------------------------------------------------------------------
   * source : « Conditions d'utilisation de la prise en charge (barème de
   * remboursement) », établi à Cotonou le 18/06/2026.
   *
   * ATTENTION — ce barème est celui d'UN régime employeur, pas celui de la
   * clinique ni d'une compagnie en particulier. Il donne la STRUCTURE exacte
   * qu'attend le cahier de charge du 30/12/2024 : « le taux varie d'une
   * assurance à l'autre et, pour un même assuré, selon la nature de l'article
   * — soins et analyses 90 %, vitamines 60 %, consultations 100 % ».
   *
   * Il sert donc de MODÈLE proposé à la saisie d'une nouvelle convention, et
   * non de grille appliquée d'office : les barèmes des treize compagnies
   * restent à collecter (question Q2 du backlog).
   * ======================================================================== */
  var BAREME_REFERENCE = {
    reference: 'Conditions d’utilisation de la prise en charge — barème de remboursement',
    lieu: 'Cotonou', date: '2026-06-18',
    contact: 'Chef Service Santé au Travail',
    source: 'DOC — Conditions d’utilisation de la prise en charge (18/06/2026)',
    /* [code, garantie, catégorie de prestation, taux Bénin, plafond, unité de plafond] */
    garanties: [
      ['G01', 'Consultation généraliste', 'consultation', 80, 5000, 'acte'],
      ['G02', 'Consultation spécialiste ou professeur', 'consultation', 80, 10000, 'acte'],
      ['G03', 'Hospitalisation — frais de chambre', 'hospitalisation', 80, 15000, 'jour'],
      ['G04', 'Frais pharmaceutiques', 'medicament', 80, null, null],
      ['G05', 'Vitamines et fortifiants', 'vitamine', 60, null, null],
      ['G06', 'Honoraires chirurgicaux', 'chirurgie', 80, null, null],
      ['G07', 'Séjour de la mère accompagnant un enfant de moins de 5 ans', 'hospitalisation', 80, 7500, 'jour'],
      ['G08', 'Analyses et travaux de laboratoire', 'analyse', 80, null, null],
      ['G09', 'Radiographie, échographie, scanner, IRM', 'imagerie', 80, null, null],
      ['G10', 'Ambulance', 'ambulance', 80, 20000, 'acte'],
      ['G11', 'Kinésithérapie', 'kinesitherapie', 80, 50000, 'an'],
      ['G12', 'Dentaire', 'dentaire', 80, null, null],
      ['G13', 'Prothèse dentaire (enfant de moins de 15 ans)', 'dentaire', 65, 70000, 'personne_an'],
      ['G14', 'Optique', 'optique', 80, 120000, 'personne_2ans'],
      ['G15', 'Vaccins (DT, fièvre jaune, coqueluche, polio, ROUVAX)', 'vaccin', 55, 50000, 'personne_an'],
      ['G16', 'Consultation pré et post-natale', 'maternite', 80, null, null],
      ['G17', 'Accouchement normal', 'maternite', 80, 150000, 'acte'],
      ['G18', 'Accouchement par voie chirurgicale', 'maternite', 80, 250000, 'acte'],
      ['G19', 'Accouchement gémellaire', 'maternite', 80, 300000, 'acte'],
      ['G20', 'Accouchement hors clinique privée', 'maternite', 80, 175000, 'acte'],
    ].map(function (g) {
      return {
        code: g[0], libelle: g[1], categorie: g[2],
        taux: g[3], plafond: g[4], unitePlafond: g[5],
        /* Le document donne trois zones ; la clinique n'exerçant qu'au Bénin,
           seule celle-ci est retenue tant que la Direction n'a pas tranché. */
        zone: 'Bénin',
      };
    }),
    actesExclus: [
      'Visites prénuptiales', 'Avortements et fausses couches chez les enfants',
      'Soins et analyses de reproduction', 'Soins esthétiques et de confort',
      'Soins traditionnels', 'Traitement des malformations',
      'Check-up et bilan de santé', 'Pédicure et manucure', 'Massages',
      'Rééducation hors accident', 'Kinésithérapie sans accord préalable',
      'Examens non prescrits', 'Prothèses dentaires', 'Détartrages',
    ],
    produitsExclus: [
      'Médicaments non prescrits', 'Contraceptifs et hormones sauf prescription',
      'Laxatifs', 'Coton', 'Compresses', 'Bandes', 'Sparadraps', 'Antiseptiques',
      'Dentifrices', 'Savons', 'Vaccins', 'Compléments alimentaires',
      'Appareils d’orthopédie', 'Produits d’esthétique', 'Aphrodisiaques',
      'Thermomètre', 'Seringue', 'Vessie de glace', 'Bassin de lit',
      'Irrigateur', 'Sonde', 'Ventouse', 'Gants',
    ],
    accordPrealable: [
      'Scanner', 'Laser', 'IRM', 'Fibroscopie', 'MAPA', 'Échocardiaque',
      'Échodoppler', 'Aérosolthérapie', 'Optique', 'Coloscopie',
      'Hystérosalpingographie', 'EEG', 'EMG',
      'Traitement de plus de 45 jours', 'Traitements antiviraux',
    ],
  };

  /** Catégories de prestation sur lesquelles se règlent les taux de couverture. */
  var CATEGORIES_GARANTIE = [
    { id: 'consultation', label: 'Consultations' },
    { id: 'analyse', label: 'Analyses de laboratoire' },
    { id: 'medicament', label: 'Médicaments et frais pharmaceutiques' },
    { id: 'vitamine', label: 'Vitamines et fortifiants' },
    { id: 'soin', label: 'Soins et actes infirmiers' },
    { id: 'chirurgie', label: 'Chirurgie' },
    { id: 'maternite', label: 'Maternité et accouchements' },
    { id: 'hospitalisation', label: 'Hospitalisation' },
    { id: 'imagerie', label: 'Imagerie et échographie' },
    { id: 'ambulance', label: 'Ambulance' },
    { id: 'dentaire', label: 'Dentaire' },
    { id: 'optique', label: 'Optique' },
    { id: 'vaccin', label: 'Vaccins' },
    { id: 'kinesitherapie', label: 'Kinésithérapie' },
    { id: 'certificat', label: 'Certificats médicaux' },
    { id: 'autre', label: 'Autres prestations' },
  ];

  /** Unités de plafond rencontrées dans le barème. */
  var UNITES_PLAFOND = [
    { id: 'acte', label: 'par acte' },
    { id: 'jour', label: 'par jour' },
    { id: 'an', label: 'par an' },
    { id: 'personne_an', label: 'par personne et par an' },
    { id: 'personne_2ans', label: 'par personne, tous les deux ans' },
  ];

  /* ==========================================================================
   * 5. CATALOGUE DES ANALYSES DE LABORATOIRE (48)
   * source : docs/liste_des_analyses_de_labo.jpeg (+ suite)
   * NB : le document fourni ne porte QUE les désignations ; la colonne tarif est
   * vierge. Les prix ci-dessous sont des valeurs d'attente à confirmer par la
   * clinique avant recette (cf. cfg-tarifs, référentiel tarifaire versionné).
   * ======================================================================== */
  var ANALYSES = [
    ['AKOP', 'Parasitologie', 2000, 'Selles', '24 h'],
    ['ASLO', 'Sérologie', 4000, 'Sang', '24 h'],
    ['AZOTEMIE (UREMIE)', 'Biochimie', 2500, 'Sang', '4 h'],
    ['BILIRUBINE TOTALE ET CONJUGUEE (DIRECTE)', 'Biochimie', 3500, 'Sang', '4 h'],
    ['BU', 'Biochimie', 1000, 'Urine', '1 h'],
    ['CALCEMIE', 'Biochimie', 3000, 'Sang', '4 h'],
    ['CHOLESTEROL TOTAL', 'Biochimie', 3000, 'Sang', '4 h'],
    ['CHOLESTEROL HDL', 'Biochimie', 3000, 'Sang', '4 h'],
    ['CREATININE', 'Biochimie', 2500, 'Sang', '4 h'],
    ['CRP', 'Immunologie', 4000, 'Sang', '4 h'],
    ['D-DIMERE', 'Hémostase', 12000, 'Sang', '24 h'],
    ['ECBU', 'Bactériologie', 5000, 'Urine', '48 h'],
    ['ELECTROPHORESE DE L’HEMOGLOBINE', 'Hématologie', 8000, 'Sang', '72 h'],
    ['GLYCEMIE', 'Biochimie', 1500, 'Sang', '2 h'],
    ['GLYCEMIE CAPILLAIRE', 'Biochimie', 1000, 'Capillaire', 'Immédiat'],
    ['GE-DP / FROTTIS SANGUIN', 'Parasitologie', 1500, 'Sang', '2 h'],
    ['GROUPE SANGUIN-RHESUS', 'Immuno-hématologie', 2000, 'Sang', '2 h'],
    ['HEMOGLOBINE CAPILLAIRE', 'Hématologie', 1000, 'Capillaire', 'Immédiat'],
    ['HEPATITE B', 'Sérologie', 3500, 'Sang', '4 h'],
    ['HEPATITE C', 'Sérologie', 4500, 'Sang', '4 h'],
    ['HIV', 'Sérologie', 2500, 'Sang', '4 h'],
    ['IONOGRAMME SANGUIN', 'Biochimie', 8000, 'Sang', '6 h'],
    ['MAGNESEMIE', 'Biochimie', 3500, 'Sang', '4 h'],
    ['NFS COMPLETE (HEMOGRAMME)', 'Hématologie', 4000, 'Sang', '4 h'],
    ['PRELEVEMENT URETRAL (PU)', 'Bactériologie', 5000, 'Prélèvement', '48 h'],
    ['PRELEVEMENT VAGINAL (PV)', 'Bactériologie', 5000, 'Prélèvement', '48 h'],
    ['PROLACTINE', 'Hormonologie', 10000, 'Sang', '72 h'],
    ['PROTIDEMIE', 'Biochimie', 2500, 'Sang', '4 h'],
    ['PSA TOTAL', 'Hormonologie', 12000, 'Sang', '72 h'],
    ['PSA LIBRE', 'Hormonologie', 12000, 'Sang', '72 h'],
    ['SERODIAGNOSTIC WIDAL (SDW)', 'Sérologie', 3000, 'Sang', '24 h'],
    ['SPERMOGRAMME', 'Andrologie', 8000, 'Sperme', '24 h'],
    ['SPERMOGRAMME SOS', 'Andrologie', 10000, 'Sperme', '24 h'],
    ['SPERMOGRAMME GRAS SAVOY / ECBK', 'Andrologie', 12000, 'Sperme', '48 h'],
    ['TBG SERIQUE (SANGUIN)', 'Hormonologie', 12000, 'Sang', '72 h'],
    ['TEMPS DE COAGULATION (TC)', 'Hémostase', 1500, 'Sang', '2 h'],
    ['TEMPS DE CEPHALINE ACTIVEE OU KAOLIN (TCA ou TCK)', 'Hémostase', 5000, 'Sang', '6 h'],
    ['TEST D’EMMEL', 'Hématologie', 2000, 'Sang', '4 h'],
    ['TP + INR', 'Hémostase', 5000, 'Sang', '6 h'],
    ['TPHA', 'Sérologie', 3000, 'Sang', '24 h'],
    ['TRANSAMINASE TGO / ASAT', 'Biochimie', 3000, 'Sang', '4 h'],
    ['TRANSAMINASE TGP / ALAT', 'Biochimie', 3000, 'Sang', '4 h'],
    ['TRANSAMINASE GGT', 'Biochimie', 3000, 'Sang', '4 h'],
    ['TRIGLYCERIDE', 'Biochimie', 3000, 'Sang', '4 h'],
    ['TEMPS DE SAIGNEMENT', 'Hémostase', 1500, 'Sang', '2 h'],
    ['URICEMIE (ACIDE URIQUE)', 'Biochimie', 3000, 'Sang', '4 h'],
    ['VITESSE DE SEDIMENTATION (VS)', 'Hématologie', 2000, 'Sang', '4 h'],
    ['VDRL', 'Sérologie', 2500, 'Sang', '24 h'],
  ].map(function (a, i) {
    return {
      id: 'ANA' + C.pad(i + 1), n: i + 1, code: 'L' + C.pad(i + 1),
      designation: a[0], categorie: a[1], prix: a[2], echantillon: a[3], delai: a[4],
      statut: 'Actif', tarifProvisoire: true,
    };
  });
  ANALYSES.source = 'DOC — Tarifs des analyses de laboratoire (48 désignations)';

  /* ==========================================================================
   * 6. CATÉGORIES DE PRODUITS — CDCT §10.1 (gestion différenciée)
   * ======================================================================== */
  var CATEGORIES_PRODUIT = [
    { id: 'medicament', label: 'Médicaments', cump: false, marge: false },
    { id: 'reactif', label: 'Réactifs de laboratoire', cump: true, marge: false },
    { id: 'conso_labo', label: 'Consommables de laboratoire', cump: true, marge: false },
    { id: 'conso_medical', label: 'Consommables médicaux', cump: true, marge: false },
    { id: 'fourniture', label: 'Fournitures administratives', cump: false, marge: false },
    { id: 'entretien', label: 'Produits d’entretien', cump: false, marge: false },
    { id: 'petit_materiel', label: 'Petit matériel médical', cump: false, marge: false },
    { id: 'immobilisation', label: 'Immobilisations', cump: false, marge: false },
  ];

  var TYPES_STOCK = [
    { id: 'gros', label: 'Stock gros (magasin central)' },
    { id: 'detail', label: 'Stock détail (pharmacie d’urgence)' },
    { id: 'labo', label: 'Stock laboratoire' },
  ];

  var TYPES_MOUVEMENT = [
    { id: 'entree', label: 'Entrée', sens: 1, badge: 'success' },
    { id: 'sortie', label: 'Sortie', sens: -1, badge: 'navy' },
    { id: 'transfert', label: 'Transfert', sens: 0, badge: 'info' },
    { id: 'perte', label: 'Perte', sens: -1, badge: 'danger' },
    { id: 'casse', label: 'Casse / bris', sens: -1, badge: 'danger' },
    { id: 'peremption', label: 'Péremption', sens: -1, badge: 'warning' },
    { id: 'inventaire', label: 'Régularisation inventaire', sens: 0, badge: 'neutral' },
  ];

  /* ==========================================================================
   * 7. FOURNISSEURS — source : facture SoBAPS, CDCT §10.1 (retours CAME/SoBAPS)
   * ======================================================================== */
  /* --------------------------------------------------------------------------
   * Paramètres fiscaux relevés sur la facture normalisée SoBAPS n° 26FNA00026
   * du 10/07/2026, certifiée MECeF.
   * ----------------------------------------------------------------------- */
  var PARAM_FISCAL = {
    source: 'DOC — Facture de vente SoBAPS n° 26FNA00026 (certifiée MECeF)',
    /* Sur la facture de référence, la TVA est portée à 0 : les produits de
       santé y sont exonérés, et le TTC vaut le HT augmenté du seul AIB.
       Le régime est donc paramétrable et signalé comme à confirmer, plutôt que
       d'appliquer 18 % par défaut à des opérations qui en sont exemptées. */
    tva: { taux: 18, libelle: 'TVA 18 %' },
    regimeTva: 'exonere',
    regimesTva: [
      { id: 'exonere', label: 'Exonéré — produits et actes de santé', taux: 0 },
      { id: 'normal', label: 'Taux normal 18 %', taux: 18 },
    ],
    tvaAConfirmer: true,
    mentionExoneration: 'Opérations exonérées de TVA — produits et actes de santé.',
    /* Acompte sur Impôt assis sur les Bénéfices, prélevé à la source. */
    aib: { taux: 1, libelle: 'AIB 1 %', code: 'AIB2', mention: 'Acompte sur impôt assis sur les bénéfices' },
    mentionMontant: 'Arrêté la présente facture à la somme de',
    /* Format du code de certification relevé : six groupes de quatre caractères. */
    formatCodeMecef: 'XXXX-XXXX-XXXX-XXXX-XXXX-XXXX',
    exemple: {
      facture: '26FNA00026',
      proforma: '26BNA00031',
      bonLivraison: '26LNA00026',
      codeMecef: 'GT32-Z4DN-SBSS-JXSP-ULDC-5URR',
      totalHT: 182725,
      aib: 1827,
      totalTTC: 184552,
    },
    /* Convention de numérotation observée : [AA][type][agence][séquence].
       B = bon / pro-forma, L = bordereau de livraison, F = facture. */
    numerotation: {
      modele: '[AA][B|L|F][agence][séquence 5 chiffres]',
      types: { B: 'Bon de commande / pro-forma', L: 'Bordereau de livraison', F: 'Facture de vente' },
    },
  };

  /* ==========================================================================
   * ACOMPTE SUR IMPÔT ASSIS SUR LES BÉNÉFICES (AIB)
   * --------------------------------------------------------------------------
   * L'AIB est un ACOMPTE prélevé à la source : il ne s'ajoute pas à l'impôt,
   * il s'impute dessus. Deux faces, à ne jamais confondre :
   *
   *   — L'AIB QUE LA CLINIQUE RETIENT à ses fournisseurs et prestataires. Elle
   *     le doit à l'État : c'est une DETTE (compte 4478, État — autres impôts
   *     et contributions), reversée à l'échéance mensuelle du 10.
   *   — L'AIB QUE LA CLINIQUE SUBIT sur ses propres factures. C'est une
   *     CRÉANCE sur l'État (compte 4492, avances et acomptes versés sur
   *     impôts), imputée sur l'impôt sur les bénéfices de l'exercice.
   *
   * Les ranger ensemble ferait d'une dette une créance — l'erreur se verrait
   * au bilan, pas au moment de la saisie.
   *
   * LA SEULE RÈGLE ÉCRITE dont nous disposons est la généralisation du taux de
   * 5 %, communiquée par la Direction le 07/09/2026 ; elle est reproduite
   * mot pour mot ci-dessous. Les taux de 1 % (relevé sur la facture
   * normalisée SoBAPS de référence) et de 3 % (relevé sur l'annexe AIB du
   * journal de la clinique) EXISTENT dans les pièces, mais aucun document ne
   * fixe leur champ d'application : ils restent marqués à valider, et l'écran
   * le dit. Un taux de retenue inventé, c'est une somme prélevée à tort sur un
   * tiers — la faute ne se rattrape pas d'une écriture.
   * ======================================================================== */
  var PARAM_AIB = {
    libelle: 'Acompte sur Impôt assis sur les Bénéfices (AIB)',
    comptes: { retenu: '4478', subi: '4492', imputation: '891' },
    echeance: 'Le 10 du mois suivant, après déclaration préalable (calendrier fiscal, ligne AIB).',
    generalisation: {
      taux: 5,
      dateEffet: '2026-09-07',
      texte: 'Généralisation du taux de 5 % : à partir du 7 septembre 2026, la Direction Générale '
        + 'des Impôts applique automatiquement un prélèvement d’AIB de 5 % sur les factures '
        + 'normalisées émises par les personnes morales, entreprises individuelles et professions '
        + 'libérales dont l’Identifiant Fiscal Unique (IFU) est désactivé ou qui sont absentes du '
        + 'fichier actif.',
      source: 'Direction Générale des Impôts — communiqué transmis par la Direction le 07/09/2026',
      statutsVises: ['desactive', 'absent'],
    },
    /* ======================================================================
     * CE QUI DÉCIDE SI L'AIB EST DUE : LE RÉGIME DE LA RÉMUNÉRATION
     * ----------------------------------------------------------------------
     * L'AIB est un acompte sur l'impôt assis sur les BÉNÉFICES : elle frappe
     * un revenu FACTURÉ (honoraires, vacation, acte réglé sur facture), jamais
     * un salaire. Un salaire supporte l'ITS, la CNSS et le VPS — pas l'AIB.
     *
     * C'est pourquoi le régime se porte sur la FICHE du tiers, agent interne
     * comme prestataire externe, et non sur le type de collection : la clinique
     * rémunère certains agents à l'acte en plus de leur contrat, et c'est cette
     * part-là qui supporte l'acompte. Retenir l'AIB sur un salaire serait
     * prélever à tort ; ne pas la retenir sur des honoraires serait exposer la
     * clinique au rappel. Le bulletin porte la ligne DANS LES DEUX CAS — à zéro
     * et motivée pour un salarié — parce qu'un bulletin doit dire de quoi
     * l'agent est redevable, pas seulement ce qu'il paie.
     * ==================================================================== */
    regimes: [
      { id: 'salaire', label: 'Salaire (contrat de travail)', aib: false,
        detail: 'Supporte l’ITS, la CNSS et le VPS. L’AIB ne frappe pas un salaire.' },
      { id: 'honoraires', label: 'Honoraires / acte facturé', aib: true,
        detail: 'Revenu facturé : l’AIB s’y applique selon le statut de l’IFU et le barème.' },
    ],
    /* Les statuts que peut prendre l'IFU d'un tiers au fichier de la DGI. */
    statutsIfu: [
      { id: 'actif', label: 'IFU actif', detail: 'Présent au fichier actif de la DGI.' },
      { id: 'desactive', label: 'IFU désactivé', detail: 'Visé par la généralisation du taux de 5 %.' },
      { id: 'absent', label: 'Absent du fichier actif', detail: 'Visé par la généralisation du taux de 5 %.' },
      { id: 'inconnu', label: 'Statut à vérifier', detail: 'Non vérifié auprès de la DGI — le taux ne se décide pas.' },
    ],
    /* ======================================================================
     * LE BARÈME — trois taux, dont un seul est arrêté
     * ----------------------------------------------------------------------
     * Le barème est une DONNÉE, pas du code : la Direction arrête le champ
     * d'application de chaque taux depuis l'écran, et le moteur s'y conforme
     * à la ligne suivante. C'est ce qui permet de livrer la généralisation du
     * 5 % — la seule règle écrite dont nous disposions — sans attendre les
     * deux autres, et sans les inventer.
     *
     * Une règle `arrete: false` NE S'APPLIQUE PAS : elle est offerte à la
     * Direction, qui la complète et la valide. Tant qu'elle ne l'a pas fait,
     * le moteur refuse en le disant. Un taux de retenue appliqué « pour voir »
     * est une somme prélevée à tort sur un tiers.
     * ==================================================================== */
    bareme: [
      {
        id: 'aib5-generalise', taux: 5, arrete: true,
        dateEffet: '2026-09-07',
        statutsIfu: ['desactive', 'absent'],
        condition: 'IFU désactivé ou absent du fichier actif de la DGI.',
        source: 'Direction Générale des Impôts — communiqué du 07/09/2026',
      },
      {
        id: 'aib1', taux: 1, arrete: false,
        dateEffet: null,
        statutsIfu: ['actif'],
        condition: null,
        conditionProposee: 'Tiers au régime du réel, IFU actif — à confirmer.',
        source: 'Taux relevé sur la facture normalisée SoBAPS n° 26FNA00026, certifiée MECeF',
        motifAttente: 'Le taux de 1 % figure sur une pièce réelle, mais aucun document remis ne dit '
          + 'À QUI il s’applique. La Direction arrête la condition, puis le taux s’applique seul.',
      },
      {
        id: 'aib3', taux: 3, arrete: false,
        dateEffet: null,
        statutsIfu: ['actif'],
        condition: null,
        conditionProposee: 'Prestataire ou profession libérale, IFU actif — à confirmer.',
        source: 'Taux relevé sur l’annexe AIB du journal de la clinique (janvier 2026)',
        motifAttente: 'Le taux de 3 % figure sur l’annexe de la clinique, appliqué à certains '
          + 'prestataires. Le critère qui les distingue des tiers à 1 % n’est écrit nulle part.',
      },
    ],
    tauxParDefaut: null,
    noteTauxParDefaut: 'Aucun taux par défaut n’est appliqué hors généralisation : le champ '
      + 'd’application des taux de 1 % et 3 % n’est fixé par aucun document remis. Il s’arrête à '
      + 'l’écran « Acompte sur impôt (AIB) », onglet Barème — et le moteur le suit aussitôt.',
  };

  /** Le barème en vigueur : celui du magasin s'il existe, la semence sinon. */
  function baremeAIB() {
    var st = global.SIGH && global.SIGH.store;
    if (!st) return PARAM_AIB.bareme;
    try {
      var col = st.collection('baremeAIB').active();
      return col.length ? col : PARAM_AIB.bareme;
    } catch (e) { return PARAM_AIB.bareme; }
  }

  /**
   * Le taux d'AIB applicable à un tiers, à une date donnée.
   *
   * Renvoie toujours un MOTIF : une retenue qu'on ne sait pas expliquer au
   * fournisseur est une retenue qu'on ne fera pas. Quand le taux ne peut pas
   * être déterminé, `taux` vaut null et l'écran refuse en le disant — il ne
   * retombe pas sur une valeur commode.
   */
  function tauxAIB(statutIfu, date, regleId) {
    var jour = String(date || '').slice(0, 10);
    var statut = statutIfu || 'inconnu';
    if (statut === 'inconnu') {
      return {
        taux: null, generalise: false, statut: statut,
        motif: 'Statut de l’IFU non vérifié auprès de la DGI — le taux ne se décide pas sans lui.',
      };
    }

    var bareme = baremeAIB();
    /* Les règles qui VISENT ce statut, arrêtées, et en vigueur à cette date.
       Une règle sans date d'effet s'applique dès qu'elle est arrêtée : c'est
       le cas d'un barème que la clinique fixe elle-même. */
    var candidates = bareme.filter(function (r) {
      if (!r.arrete) return false;
      if ((r.statutsIfu || []).indexOf(statut) === -1) return false;
      if (r.dateEffet && (!jour || jour < r.dateEffet)) return false;
      return true;
    });
    /* Si la Direction a nommé la règle à appliquer, elle prime : deux règles
       peuvent viser le même statut (1 % et 3 % sur un IFU actif), et c'est
       elle qui tranche, jamais l'ordre du tableau. */
    if (regleId) {
      var nommee = candidates.filter(function (r) { return r.id === regleId; })[0];
      if (nommee) {
        return {
          taux: nommee.taux, generalise: !!nommee.dateEffet, statut: statut, regle: nommee.id,
          motif: 'Taux de ' + nommee.taux + ' % — ' + (nommee.condition || 'condition arrêtée par la Direction') + '.',
        };
      }
    }
    if (candidates.length === 1) {
      var r0 = candidates[0];
      return {
        taux: r0.taux, generalise: !!r0.dateEffet, statut: statut, regle: r0.id,
        motif: 'Taux de ' + r0.taux + ' % — ' + (r0.condition || 'condition arrêtée par la Direction') + '.',
      };
    }
    if (candidates.length > 1) {
      /* PLUSIEURS RÈGLES VISENT CE TIERS : le logiciel ne choisit pas à la
         place de la clinique — il NOMME les règles en présence. */
      return {
        taux: null, generalise: false, statut: statut,
        choix: candidates.map(function (r) { return { id: r.id, taux: r.taux, condition: r.condition }; }),
        motif: 'Deux règles visent ce tiers (' + candidates.map(function (r) { return r.taux + ' %'; }).join(' ou ')
          + ') : la retenue attend que le poste désigne laquelle s’applique.',
      };
    }

    /* Aucune règle arrêtée : on dit POURQUOI, en nommant celles qui attendent. */
    var enAttente = bareme.filter(function (r) {
      return !r.arrete && (r.statutsIfu || []).indexOf(statut) !== -1;
    });
    var g = PARAM_AIB.generalisation;
    if (g.statutsVises.indexOf(statut) !== -1 && jour && jour < g.dateEffet) {
      return {
        taux: null, generalise: false, statut: statut,
        motif: 'IFU non actif, mais la généralisation ne prend effet que le 07/09/2026 : le taux '
          + 'applicable avant cette date reste à arrêter par la Direction.',
      };
    }
    return {
      taux: null, generalise: false, statut: statut,
      enAttente: enAttente.map(function (r) { return r.taux; }),
      motif: enAttente.length
        ? 'Aucune règle arrêtée pour un IFU actif : les taux de '
          + enAttente.map(function (r) { return r.taux + ' %'; }).join(' et ')
          + ' figurent dans les pièces de la clinique, mais leur champ d’application n’est fixé par '
          + 'aucun document — à arrêter au barème.'
        : 'Aucune règle du barème ne vise ce tiers — à compléter par la Direction.',
    };
  }

  /**
   * L'AIB due sur la rémunération d'un tiers — agent interne ou prestataire
   * externe : une seule règle, lue par la paie, par les prestataires et par la
   * comptabilité, donc elle vit ici et nulle part ailleurs.
   *
   * `profil` porte `regimeRemuneration`, `ifu`, `ifuStatut` et, si la Direction
   * a désigné la règle du barème à appliquer, `regleAIB`.
   *
   * Renvoie TOUJOURS une ligne exploitable : `applicable` dit si l'acompte a
   * lieu d'être, `montant` ce qu'on retient (zéro tant que le taux n'est pas
   * déterminé), et `motif` la phrase qu'on écrira sur le bulletin. Un montant
   * nul motivé vaut mieux qu'une retenue inventée : la première se corrige,
   * la seconde a déjà quitté la poche du tiers.
   */
  function aibTiers(profil, date, base) {
    var p = profil || {};
    var regime = p.regimeRemuneration || 'salaire';
    var assiette = Math.max(0, Math.round(base || 0));
    if (regime !== 'honoraires') {
      return {
        applicable: false, regime: regime, taux: 0, base: 0, montant: 0,
        statut: p.ifuStatut || 'inconnu', ifu: p.ifu || null,
        motif: 'Sans objet — rémunération salariale : elle supporte l’ITS, jamais l’AIB, '
          + 'qui ne frappe que les revenus facturés.',
      };
    }
    var t = tauxAIB(p.ifuStatut, date, p.regleAIB);
    if (t.taux == null) {
      return {
        applicable: true, regime: regime, taux: null, base: assiette, montant: 0,
        statut: t.statut, ifu: p.ifu || null, choix: t.choix, enAttente: t.enAttente,
        retenu: false, motif: t.motif,
      };
    }
    return {
      applicable: true, regime: regime, taux: t.taux, base: assiette,
      montant: Math.round(assiette * t.taux / 100),
      statut: t.statut, ifu: p.ifu || null, regle: t.regle, generalise: t.generalise,
      retenu: true, motif: t.motif,
    };
  }

  var FOURNISSEURS = [
    {
      id: 'F001', code: 'SOBAPS', nom: 'SoBAPS SA — Société Béninoise pour l’Approvisionnement en Produits de Santé',
      type: 'Grossiste pharmaceutique', ville: 'Parakou', habilite: true,
      tel: '(229) 01 91 48 42 42 / 01 99 43 04 04', delai: 5,
      adresse: 'BP 201 Parakou — Agence Régionale Parakou',
      ifu: '3202112446712',
      banque: 'BANK OF AFRICA', compte: '007393360019', guichet: '01030', codeBanque: 'B5061', cleRib: '94',
      codeClient: '1106035',
      certification: 'ISO 9001:2015 · ISO 14001:2015 · ISO 45001:2018',
      source: 'DOC — Facture de vente n° 26FNA00026',
    },
    { id: 'F002', code: 'CAME', nom: 'CAME — Centrale d’Achat des Médicaments Essentiels', type: 'Centrale d’achat', ville: 'Cotonou', habilite: true, tel: '21 33 00 00', delai: 7 },
    { id: 'F003', code: 'UBIPHARM', nom: 'UBIPHARM Bénin', type: 'Grossiste pharmaceutique', ville: 'Cotonou', habilite: false, tel: '21 31 00 00', delai: 6 },
    { id: 'F004', code: 'LABOTECH', nom: 'LABOTECH Réactifs', type: 'Réactifs & consommables labo', ville: 'Cotonou', habilite: false, tel: '21 35 00 00', delai: 10 },
    { id: 'F005', code: 'MEDIPLUS', nom: 'MEDIPLUS Équipements', type: 'Matériel médical', ville: 'Parakou', habilite: false, tel: '23 61 00 00', delai: 14 },
    { id: 'F006', code: 'NATIFOURN', nom: 'NATI Fournitures', type: 'Fournitures & entretien', ville: 'Natitingou', habilite: false, tel: '23 82 00 00', delai: 2 },
  ];

  /* ==========================================================================
   * 8. PLAN COMPTABLE SYSCOHADA RÉVISÉ
   * --------------------------------------------------------------------------
   * LE PLAN DE LA CLINIQUE D'ORIGINE EST RETIRÉ (Direction, 06/09/2026). Le
   * référentiel est désormais le PLAN COMPTABLE SYSCOHADA RÉVISÉ au complet —
   * 1 332 comptes, dont 1 049 imputables — vendoré depuis le CSV officiel par
   * build/gen-plan-comptable.js.
   *
   * Les codes sont ceux du plan, à QUATRE CHIFFRES : c'est la numérotation que
   * le service comptable de BAGUIDI emploie déjà dans son journal (4011 pour
   * un fournisseur, 5711 pour la caisse, 2458 pour une moto). Le prototype
   * portait auparavant des numéros à six chiffres, hérités : ils ont été
   * convertis, compte par compte, vers leur code officiel.
   * ======================================================================== */
  function journalDeCompte(num) {
    var p = String(num);
    if (/^6318/.test(p)) return 'BQ';
    if (/^66|^664/.test(p)) return 'SAL';
    if (/^6(0|1|2|3|4|5)/.test(p)) return 'ACH';
    if (/^67|^68|^69|^8/.test(p)) return 'OD';
    if (/^7/.test(p)) return 'VTE';
    if (/^52/.test(p)) return 'BQ';
    if (/^57/.test(p)) return 'CAI';
    if (/^2/.test(p)) return 'IMM';
    return 'OD';
  }

  var PLAN_COMPTABLE = ((global.SIGH.planComptable && global.SIGH.planComptable.COMPTES) || [])
    .map(function (c) {
      return {
        /* `num` reste le nom du champ lu partout dans le logiciel ; sa VALEUR
           est désormais le code SYSCOHADA. */
        num: c.code, code: c.code, libelle: c.libelle,
        classe: c.classe, niveau: c.niveau, parent: c.parent,
        imputable: c.imputable,
        journal: journalDeCompte(c.code),
        source: 'SYSCOHADA révisé',
      };
    });

  /* ==========================================================================
   * LES COMPTES DES SCHÉMAS D'ÉCRITURE — nommés, jamais écrits en dur
   * --------------------------------------------------------------------------
   * Chaque écriture automatique du logiciel (achat, réception, paie, dépense,
   * retenue d'AIB…) désigne son compte PAR SON NOM. Le jour où la Direction
   * change un rattachement, il se corrige ICI et nulle part ailleurs — c'est
   * la règle « une règle vit à un seul endroit », déjà payée sur le code
   * patient et sur la méthode de valorisation.
   *
   * Chaque code est celui du plan SYSCOHADA révisé, avec son libellé officiel
   * en commentaire : aucune correspondance n'est devinée.
   * ======================================================================== */
  var COMPTES_SIGH = {
    fournisseurs: '4011',            /* Fournisseurs */
    clients: '4111',                 /* Clients */
    personnelRemunerations: '422',   /* Personnel, rémunérations dues */
    personnelAcomptes: '4212',       /* Personnel, acomptes */
    securiteSociale: '431',          /* Sécurité sociale (CNSS) */
    tvaFactureeServices: '4432',     /* T.V.A. facturée sur prestations de services */
    etatImpotsSalaires: '4472',      /* Impôts sur salaires (ITS) */
    etatRetenuesSource: '4478',      /* Autres impôts et contributions — AIB retenu aux tiers */
    etatAcomptesImpots: '4492',      /* État, avances et acomptes versés sur impôts — AIB subi */
    banque: '5211',                  /* Banque X — à nommer par la Direction */
    caisse: '5711',                  /* Caisse en monnaie nationale */
    achatsMarchandises: '6011',      /* Achats de marchandises — dans la Région */
    matieresConsommables: '6041',    /* Matières consommables */
    produitsEntretien: '6043',       /* Produits d'entretien */
    fournituresBureau: '6047',       /* Fournitures de bureau */
    eau: '6051',                     /* Fournitures non stockables — Eau */
    electricite: '6052',             /* Fournitures non stockables — Électricité */
    petitMateriel: '6056',           /* Achats de petit matériel et outillage */
    transportPlis: '616',            /* Transport de plis */
    assurances: '6251',              /* Assurances multirisques */
    fraisBancaires: '6318',          /* Autres frais bancaires */
    personnelExterieur: '6371',      /* Personnel intérimaire */
    patente: '6412',                 /* Patentes, licences et taxes annexes */
    taxeSalaires: '6413',            /* Taxes sur appointements et salaires (VPS) */
    pertesCreances: '6511',          /* Pertes sur créances — Clients */
    salaires: '6611',                /* Appointements, salaires et commissions */
    chargesSociales: '6641',         /* Charges sociales sur rémunération du personnel national */
    interetsEmprunts: '6712',        /* Intérêts des emprunts auprès des établissements de crédit */
    ventesMarchandises: '7011',      /* Ventes de marchandises — dans la Région */
    servicesVendus: '7061',          /* Services vendus — dans la Région */
    impotsSurBenefices: '891',       /* Impôts sur les bénéfices de l'exercice */
  };

  /** Le libellé officiel d'un compte, par son code. */
  function libelleCompte(code) {
    var c = PLAN_COMPTABLE.filter(function (x) { return x.num === String(code); })[0];
    return c ? c.libelle : null;
  }

  var JOURNAUX = [
    { code: 'ACH', libelle: 'Journal des achats', contrepartie: '4011' },
    { code: 'VTE', libelle: 'Journal des ventes', contrepartie: '4111' },
    { code: 'CAI', libelle: 'Journal de caisse-dépenses', contrepartie: '5711' },
    { code: 'BQ', libelle: 'Journal de banque', contrepartie: '5211' },
    { code: 'SAL', libelle: 'Journal des salaires', contrepartie: '422' },
    { code: 'IMM', libelle: 'Journal des immobilisations', contrepartie: '2411' },
    { code: 'OD', libelle: 'Journal des opérations diverses', contrepartie: null },
  ];

  /** Centres de coûts — comptabilité analytique (CDCT §10.11).
   *  LES MÊMES SECTEURS QUE LES GROUPES DE PRESTATION, dans le même ordre et
   *  sous les mêmes libellés (Direction, 07/09/2026), plus la DIRECTION, qui
   *  porte les charges transverses et n'a pas de recette propre. Nommer un
   *  centre autrement que son groupe rendrait le rapprochement illisible :
   *  c'est la même activité vue par ses recettes puis par ses charges. */
  var CENTRES_COUT = [
    { id: 'laboratoire', label: 'Laboratoire' },
    { id: 'pharmacie', label: 'Pharmacie' },
    { id: 'consultation', label: 'Consultation' },
    { id: 'echographie', label: 'Échographie' },
    { id: 'maternite', label: 'Maternité' },
    { id: 'hospitalisation', label: 'Hospitalisation et soins' },
    /* Un seul centre pour la Direction. Les deux libellés d'autrefois
       désignaient le même service ; la ventilation en sortait scindée. */
    { id: 'direction', label: 'Direction' },
  ];

  /* ==========================================================================
   * 9. PAIE — cotisations sociales et fiscales (CDCT §10.10)
   * ======================================================================== */
  var PARAM_PAIE = {
    cnss: { patronale: 16.4, ouvriere: 3.6, plafond: null, source: 'CDCT §10.10' },
    vps: { taux: 4, base: 'Salaire brut', source: 'CDCT §10.10' },
    its: {
      bareme: [
        { de: 0, a: 60000, taux: 0 },
        { de: 60001, a: 150000, taux: 10 },
        { de: 150001, a: 250000, taux: 15 },
        { de: 250001, a: 500000, taux: 19 },
        { de: 500001, a: null, taux: 30 },
      ],
      source: 'Barème ITS Bénin — à confirmer par le service comptable',
    },
    /* Redevance ORTB — règle précisée par la Direction le 20/08/2026.
       DEUX REDEVANCES DISTINCTES, qui se CUMULENT — et non deux tranches
       exclusives d'un même barème :
         ORTB Radio : 1 000 F, TOUS LES SALARIÉS SANS EXCEPTION, en MARS ;
         ORTB Télé  : 3 000 F, salaire brut SUPÉRIEUR à 60 000 F, en JUIN.
       Un agent au-dessus du seuil acquitte donc 4 000 F sur l'exercice
       (1 000 radio + 3 000 télé) ; en dessous, 1 000 F au titre de la radio.
       Les traiter comme des tranches exclusives dispenserait à tort de la
       radio les salaires élevés — c'est l'erreur que cette note prévient.
       Prélèvement ANNUEL, pas mensuel. */
    ortb: {
      libelle: 'Redevance ORTB',
      source: 'Direction — précision du 20/08/2026',
      seuilTele: 60000,
      redevances: [
        {
          id: 'radio', code: 'ORTB-RADIO', categorie: 'Radio',
          libelle: 'Redevance ORTB / Radio',
          montant: 1000, mois: 2, moisLabel: 'mars',
          seuilMin: null, seuilMax: null,
          assiette: 'Tous les salariés, sans exception',
        },
        {
          id: 'tele', code: 'ORTB-TELE', categorie: 'Télé',
          libelle: 'Redevance ORTB / Télé',
          montant: 3000, mois: 5, moisLabel: 'juin',
          seuilMin: 60001, seuilMax: null,
          assiette: 'Salaire brut supérieur à 60 000 FCFA',
        },
      ],
      cumulMaximum: 4000,
    },
  };

  /* ==========================================================================
   * 10. HOSPITALISATION — chambres et lits (CDCT §10.4, nomenclature A1 LIT1)
   * ======================================================================== */
  var TYPES_CHAMBRE = [
    { id: 'standard', label: 'Standard', tarif: 5000 },
    { id: 'vip', label: 'VIP', tarif: 15000 },
    { id: 'vvip', label: 'VVIP', tarif: 25000 },
  ];

  var CHAMBRES = (function () {
    var out = [], plan = [
      { code: 'A1', type: 'standard', lits: 2, aile: 'Aile A — Médecine' },
      { code: 'A2', type: 'standard', lits: 2, aile: 'Aile A — Médecine' },
      { code: 'A3', type: 'standard', lits: 2, aile: 'Aile A — Médecine' },
      { code: 'A4', type: 'standard', lits: 2, aile: 'Aile A — Médecine' },
      { code: 'B1', type: 'standard', lits: 2, aile: 'Aile B — Maternité' },
      { code: 'B2', type: 'standard', lits: 2, aile: 'Aile B — Maternité' },
      { code: 'B3', type: 'standard', lits: 2, aile: 'Aile B — Maternité' },
      { code: 'C1', type: 'vip', lits: 1, aile: 'Aile C — VIP' },
      { code: 'C2', type: 'vip', lits: 1, aile: 'Aile C — VIP' },
      { code: 'C3', type: 'vip', lits: 1, aile: 'Aile C — VIP' },
      { code: 'D1', type: 'vvip', lits: 1, aile: 'Aile D — VVIP' },
      { code: 'D2', type: 'vvip', lits: 1, aile: 'Aile D — VVIP' },
    ];
    plan.forEach(function (ch) {
      var lits = [];
      for (var i = 1; i <= ch.lits; i++) lits.push({ code: ch.code + '_LIT' + i, label: ch.code + ' LIT' + i, statut: 'libre' });
      out.push({ id: ch.code, code: ch.code, type: ch.type, aile: ch.aile, lits: lits });
    });
    return out;
  })();

  /* ==========================================================================
   * 11. DIVERS — modes de paiement, motifs, planning
   * ======================================================================== */
  var MODES_PAIEMENT = [
    { id: 'especes', label: 'Espèces', icon: 'banknote', compte: '5711' },
    { id: 'tpe', label: 'TPE (carte bancaire)', icon: 'credit-card', compte: '5211' },
    { id: 'mtn', label: 'MTN Mobile Money', icon: 'smartphone', compte: '5211' },
    { id: 'moov', label: 'Moov Money', icon: 'smartphone', compte: '5211' },
    { id: 'assurance', label: 'Prise en charge assurance', icon: 'shield-check', compte: '4111' },
  ];

  /* --------------------------------------------------------------------------
   * Types de vacation — transcrits des plannings réels de la clinique
   * (médecins, infirmiers, sages-femmes, aides-soignants, secrétaires,
   * agents d'entretien et agents de sécurité).
   * ----------------------------------------------------------------------- */
  var TYPES_PLANNING = [
    { id: 'garde', label: 'Garde 24h', court: 'G', debut: '08:00', fin: '08:00', couleur: 'danger', duree: 24 },
    { id: 'garde_hospi', label: 'Garde hospitalisation', court: 'GH', debut: '08:00', fin: '08:00', couleur: 'danger', duree: 24 },
    { id: 'garde_soins', label: 'Garde soins', court: 'GS', debut: '08:00', fin: '18:30', couleur: 'warning', duree: 10.5 },
    { id: 'permanence', label: 'Permanence', court: 'P', debut: '08:00', fin: '18:00', couleur: 'info', duree: 10 },
    { id: 'soiree', label: 'Soirée', court: 'S', debut: '18:00', fin: '08:00', couleur: 'navy', duree: 14 },
    { id: 'entretien_general', label: 'Entretien général de la journée', court: 'EGJ', debut: '08:00', fin: '18:00', couleur: 'info', duree: 10 },
    { id: 'repos24', label: 'Repos 24h', court: 'R', couleur: 'neutral', duree: 0 },
    { id: 'repos48', label: 'Repos 48h', court: 'R48', couleur: 'neutral', duree: 0 },
    { id: 'conge', label: 'Congé', court: 'C', couleur: 'success', duree: 0 },
    { id: 'absence', label: 'Absence', court: 'A', couleur: 'warning', duree: 0 },
    { id: 'remplacement', label: 'Remplacement', court: 'Rp', couleur: 'navy', duree: 0 },
    { id: 'incineration', label: 'Incinération des déchets', court: 'INC', debut: '16:00', fin: '18:00', couleur: 'warning', duree: 2 },
  ];

  /* --------------------------------------------------------------------------
   * Régime de travail par catégorie de personnel, relevé sur les plannings.
   * `cycle` décrit la rotation observée ; `repos` la durée de repos appliquée.
   * ----------------------------------------------------------------------- */
  var REGLES_PLANNING = [
    {
      fonctions: ['medecin'], libelle: 'Médecins',
      vacations: ['garde'], repos: 'repos48', cycle: 2,
      source: 'Planning de travail des médecins',
      mention: 'Garde de 24 h (08h→08h), suivie d’un repos de 48 h.',
    },
    {
      fonctions: ['infirmier'], libelle: 'Infirmiers',
      vacations: ['garde_soins', 'garde_hospi'], repos: 'repos48', cycle: 3,
      joursTravaillesMois: 20,
      source: 'Planning de travail des infirmiers',
      mention: 'Deux postes distincts : garde soins de 08h à 18h30 et garde hospitalisation de 08h à 08h. '
        + 'Vingt jours travaillés par mois et par agent.',
    },
    {
      fonctions: ['sage_femme'], libelle: 'Sages-femmes',
      vacations: ['garde'], repos: 'repos24', cycle: 2,
      source: 'Planning de travail des sages-femmes',
      mention: 'Garde de 24 h en alternance quotidienne, suivie d’un repos de 24 h.',
    },
    {
      fonctions: ['aide_soignant'], libelle: 'Aides-soignants',
      vacations: ['garde'], repos: 'repos48', cycle: 3,
      source: 'Planning de travail des aides-soignants',
      mention: 'Rotation à trois : un agent de garde, deux au repos.',
    },
    {
      fonctions: ['accueil', 'caissiere'], libelle: 'Secrétaires médicaux et caisse',
      vacations: ['garde', 'permanence'], repos: 'repos24', cycle: 3,
      source: 'Planning de travail des secrétaires',
      mention: 'Garde de 24 h et permanence de 08h à 18h ; pas de permanence le dimanche.',
    },
    {
      fonctions: ['entretien'], libelle: 'Agents d’entretien',
      vacations: ['permanence', 'entretien_general'], repos: null, cycle: 3,
      source: 'Planning des agents d’entretien',
      mention: 'Rotation « P » (permanence) et « EGJ » (entretien général de la journée).',
    },
    {
      fonctions: ['securite'], libelle: 'Agents de sécurité',
      vacations: ['garde', 'soiree'], repos: 'repos24', cycle: 3,
      source: 'Planning des agents de sécurité',
      mention: 'Rotation « G » (garde 24 h), « S » (soirée de 18h à 8h) et « R » (repos).',
    },
    {
      /* L'incinération des déchets hospitaliers est un poste à part : elle ne
         relève pas d'une garde mais d'une intervention rémunérée au forfait
         mensuel, dont le montant vient de la NS 132. Le rattacher au régime
         des aides-soignants aurait dissous l'honoraire dans la garde. */
      fonctions: ['aide_soignant', 'entretien'], libelle: 'Incinération des déchets de l’hôpital',
      vacations: ['incineration'], repos: null, cycle: 7,
      honoraire: 5000, honoraireMode: 'fixe', honorairePeriodicite: 'mensuelle',
      source: 'NS n° 132/07/DM/DA/CNT/2026 — prime d’incinération',
      mention: 'Incinération des déchets hospitaliers, poste hebdomadaire rémunéré '
        + '5 000 FCFA par mois au titre de la prime d’incinération (NS 132).',
    },
  ];

  function regleDe(fonction) {
    for (var i = 0; i < REGLES_PLANNING.length; i++) {
      if (REGLES_PLANNING[i].fonctions.indexOf(fonction) !== -1) return REGLES_PLANNING[i];
    }
    return null;
  }

  /* Un seul intitulé pour le service : « Direction ». Le porter en double —
     Administration ici, Direction là — coupait l'effectif en deux dans les
     graphiques et donnait deux barres pour un seul service. */
  var SERVICES = [
    'Médecine générale', 'Maternité', 'Chirurgie', 'Laboratoire', 'Pharmacie',
    'Imagerie / Échographie', 'Soins infirmiers', 'Accueil', 'Direction', 'Comptabilité',
  ];

  var GROUPES_SANGUINS = ['O+', 'O-', 'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-'];

  /* --- Référentiels cliniques du dossier patient ---------------------------
   * Listes proposées à la saisie des antécédents et des allergies. Elles sont
   * administrables : la clinique arrêtera sa propre nomenclature.
   * ---------------------------------------------------------------------- */
  var ANTECEDENTS = [
    'Hypertension artérielle', 'Diabète de type 2', 'Asthme', 'Drépanocytose',
    'Ulcère gastrique', 'Épilepsie', 'Césarienne antérieure', 'Tuberculose traitée',
    'Insuffisance rénale', 'Hépatite B', 'Aucun antécédent notable',
  ];
  var ANTECEDENTS_RISQUE = ['Drépanocytose', 'Insuffisance rénale', 'Épilepsie', 'Tuberculose traitée', 'Hépatite B'];
  var ALLERGIES = [
    'Pénicilline', 'Sulfamides', 'Aspirine', 'Arachide', 'Iode',
    'Anti-inflammatoires non stéroïdiens', 'Aucune allergie connue',
  ];
  var ACTES_SOINS = [
    'Injection intraveineuse', 'Injection intramusculaire', 'Pose de perfusion',
    'Réfection de pansement', 'Sondage urinaire', 'Prise de constantes', 'Aérosol',
    'Soins de nursing', 'Transfusion sanguine',
    /* Demandée par la Direction : elle manquait à la liste des rubriques. */
    'Mise en observation',
  ];

  /** Unités d'observation — surveillance de courte durée, distincte de l'hospitalisation. */
  var UNITES_OBSERVATION = [
    { id: 'urgences', label: 'Salle d’observation — urgences', places: 4 },
    { id: 'medecine', label: 'Salle d’observation — médecine générale', places: 3 },
    { id: 'maternite', label: 'Salle d’observation — maternité', places: 2 },
    { id: 'pediatrie', label: 'Salle d’observation — pédiatrie', places: 2 },
  ];

  /** Orientation prise à l'issue de l'observation (décision informatisée). */
  var ORIENTATIONS_OBSERVATION = [
    { id: 'domicile', label: 'Sortie définitive — retour à domicile', tone: 'success' },
    { id: 'hospitalisation', label: 'Hospitalisation complète', tone: 'warning' },
    { id: 'transfert', label: 'Transfert vers un autre établissement', tone: 'danger' },
    { id: 'bloc', label: 'Passage au bloc opératoire', tone: 'danger' },
  ];

  /** Durée de référence : 24 h en médecine générale (au-delà, alerte). */
  var DUREE_OBSERVATION_REFERENCE = 24;

  /* ==========================================================================
   * NS 145/08/DA/CNT/2026 — RÉPARTITION DES SECTEURS ET RESPONSABLES
   * --------------------------------------------------------------------------
   * Note de service de la Directrice Administrative, signée le 06/08/2026,
   * effet au 07/08/2026 : « la nouvelle répartition des différents secteurs de
   * la Clinique ainsi que la désignation des responsables respectifs ».
   *
   * C'est la maille réelle des habilitations — plus fine que les rôles — et la
   * base de l'évaluation de l'activité de chaque service.
   * ======================================================================== */
  var NS145 = {
    reference: 'NS 145/08/DA/CNT/2026',
    objet: 'Répartition des secteurs de la clinique et désignation des responsables',
    version: 1,
    dateSignature: '2026-08-06',
    dateEffet: '2026-08-07',
    statut: 'ACTIVE',
    signataire: null,
    noteSignataire: 'Note de service héritée du prototype d’origine — signataire BAGUIDI à désigner.',
    source: 'DOC — Note de service NS 145/08/DA/CNT/2026',
    /* LES TITULAIRES NE SONT PAS REPRIS (07/09/2026) : ceux de la note
       d'origine ne sont pas les agents de BAGUIDI, et nommer quelqu'un à
       leur place serait inventer une désignation. La RÉPARTITION des
       secteurs reste — c'est elle qui porte le filtre des données. */
    secteurs: [
      ['ACC', 'ACCUEIL', null, null, 'Secrétaire médical', 'reception'],
      ['ADM', 'ADMINISTRATION', null, null, 'Comptable', 'comptable'],
      ['MGE', 'MÉDECINE GÉNÉRALE', null, null, 'Médecin généraliste', 'medecin'],
      ['CHI', 'CHIRURGIE', null, null, 'Chirurgien généraliste', 'medecin'],
      ['MAT', 'MATERNITÉ', null, null, 'Sage-femme', 'infirmier'],
      ['ECH', 'ÉCHOGRAPHIE', null, null, 'Échographiste', 'medecin'],
      ['LAB', 'LABORATOIRE', null, null, 'Biologiste médical', 'laborantin'],
      ['HOS', 'HOSPI', null, null, 'Infirmier(ère)', 'infirmier'],
      ['SOI', 'SALLE DE SOINS', null, null, 'Infirmier(ère)', 'infirmier'],
      ['BLO', 'BLOC OPÉRATOIRE', null, null, 'Infirmier(ère)', 'infirmier'],
      ['SUR', 'SURVEILLANCE', null, null, 'Infirmier général', 'infirmier'],
      ['CPH', 'CAISSE / PHARMACIE', null, null, 'Dispensatrice', 'pharmacien'],
      ['SEC', 'SÉCURITÉ', null, null, 'Gardien', 'agentadmin'],
      ['ENT', 'ENTRETIEN', null, null, 'Ménagère', 'agentadmin'],
    ].map(function (s, i) {
      return {
        id: 'SEC' + C.pad(i + 1, 2), statut: 'actif', ordre: i + 1,
        code: s[0], libelle: s[1], responsable: s[2], adjoint: s[3],
        qualification: s[4], role: s[5],
        source: 'NS 145/08/DA/CNT/2026 du 06/08/2026',
      };
    }),
  };

  /* ==========================================================================
   * CAPACITÉS MÉTIER — le RBAC que la Direction a dicté
   * --------------------------------------------------------------------------
   * Le rôle décide des ÉCRANS ; la fonction et le secteur décident des DONNÉES.
   * Les règles ci-dessous sont la transcription littérale de la réunion :
   *
   *   « les médecins doivent avoir accès à tous les résultats des analyses,
   *     tous » ;
   *   « les sages-femmes […] il faut qu'elles aient accès aux résultats de la
   *     maternité. Mais est-ce qu'elles doivent avoir accès aux analyses
   *     prescrites pour le compte de la chirurgie ? Non » ;
   *   « ce sont les infirmiers qui font les soins. Ce n'est pas les
   *     aides-soignants » ;
   *   « pour les infirmiers, non. Pour les aides-soignants, non. Pour les
   *     agents de l'accueil, non » (résultats d'échographie) ;
   *   « ceux qui viennent de l'extérieur, le laboratoire doit pouvoir leur
   *     donner leur résultat ».
   *
   * `voirResultats` : 'tous' | 'secteur' | 'produits' | 'aucun'
   *   — 'secteur'  : uniquement ce qui a été demandé par son propre secteur ;
   *   — 'produits' : ce que l'agent produit lui-même (laboratoire).
   * ======================================================================== */
  var CAPACITES = {
    medecin: {
      label: 'Médecin', voirResultats: 'tous', voirEchographie: 'tous',
      prescrire: ['analyse', 'medicament', 'acte', 'hospitalisation', 'echographie'],
      executerSoins: false, remettreResultats: false,
      note: 'Accès à tous les résultats, quel que soit le prescripteur.',
    },
    sage_femme: {
      label: 'Sage-femme', voirResultats: 'secteur', voirEchographie: 'secteur',
      prescrire: ['analyse', 'medicament', 'acte', 'echographie'],
      executerSoins: true, remettreResultats: false,
      secteurs: ['MATERNITE'],
      note: 'Résultats de la maternité seulement — pas ceux demandés par la chirurgie.',
    },
    infirmier: {
      label: 'Infirmier(ère)', voirResultats: 'aucun', voirEchographie: 'aucun',
      prescrire: [], executerSoins: true, remettreResultats: false,
      note: 'Exécute les soins prescrits ; ne consulte pas les résultats d’analyses.',
    },
    aide_soignant: {
      label: 'Aide-soignant(e)', voirResultats: 'aucun', voirEchographie: 'aucun',
      prescrire: [], executerSoins: false, remettreResultats: false,
      note: 'N’exécute pas les soins prescrits et ne consulte aucun résultat.',
    },
    tsl: {
      label: 'Technicien de laboratoire', voirResultats: 'produits', voirEchographie: 'aucun',
      prescrire: [], executerSoins: false, remettreResultats: true,
      /* Le TSL saisit et valide TECHNIQUEMENT. Il peut porter la validation
         biologique en l'absence du biologiste, mais l'intérim est tracé sur
         la pièce — une clinique de trente agents ne peut pas suspendre ses
         rendus pendant un congé, et masquer l'intérim reviendrait à faire
         signer quelqu'un d'autre. */
      validerTechnique: true, validerBiologique: 'interim',
      note: 'Produit les résultats, les valide techniquement et les remet aux patients externes. '
        + 'Peut porter la validation biologique par intérim, qui est alors tracée comme telle.',
    },
    /* DEUX BIOLOGISTES MÉDICAUX — décision de la Direction du 26/08/2026.
       Ce sont les deux agents que l'organigramme appelle « laborantins » : le
       terme est renommé, la fonction ne change pas. KINNOU A. Ganiou reste au
       laboratoire, chef de service.

       RÈGLE DE PREUVE ATTACHÉE : celui qui a fait le prélèvement est celui qui
       valide. Un prélèvement fait par l'un et validé par l'autre romprait la
       chaîne — le validateur attesterait d'un échantillon qu'il n'a pas vu
       arriver. La validation porte donc le nom du biologiste CONNECTÉ, et le
       journal d'audit trace son compte. */
    biologiste: {
      label: 'Biologiste médical', voirResultats: 'tous', voirEchographie: 'aucun',
      effectif: 2,
      continuitePrelevement: true,
      prescrire: ['analyse'], executerSoins: false, remettreResultats: true,
      validerTechnique: true, validerBiologique: true,
      note: 'Détient la validation biologique : c’est elle qui rend le résultat visible du prescripteur.',
    },
    accueil: {
      label: 'Accueil / Secrétaire médical', voirResultats: 'aucun', voirEchographie: 'aucun',
      prescrire: [], executerSoins: false, remettreResultats: false,
      note: 'Aucun accès aux résultats ni aux prescriptions.',
    },
    caissiere: {
      label: 'Caissière', voirResultats: 'aucun', voirEchographie: 'aucun',
      prescrire: [], executerSoins: false, remettreResultats: false,
      note: 'Voit la liste des prestations à encaisser, jamais leur contenu clinique.',
    },
    dispensatrice: {
      label: 'Dispensatrice', voirResultats: 'aucun', voirEchographie: 'aucun',
      prescrire: [], executerSoins: false, remettreResultats: false,
      note: 'Voit les médicaments prescrits, non les résultats d’analyses.',
    },
    direction: {
      label: 'Direction', voirResultats: 'tous', voirEchographie: 'tous',
      prescrire: [], executerSoins: false, remettreResultats: false,
      note: 'Accès de supervision, sans droit de prescription.',
    },
    stock: { label: 'Gestionnaire de stock', voirResultats: 'aucun', voirEchographie: 'aucun', prescrire: [], executerSoins: false, remettreResultats: false },
    comptable: { label: 'Comptable', voirResultats: 'aucun', voirEchographie: 'aucun', prescrire: [], executerSoins: false, remettreResultats: false },
    /* Fonction RH — deux titulaires chez BAGUIDI (MABOUDOU Nawal, TOUNGOUH
       A. Zoulkifouli). Aucun accès clinique : RG-13. */
    rh: { label: 'Responsable RH', voirResultats: 'aucun', voirEchographie: 'aucun', prescrire: [], executerSoins: false, remettreResultats: false },
    securite: { label: 'Agent de sécurité', voirResultats: 'aucun', voirEchographie: 'aucun', prescrire: [], executerSoins: false, remettreResultats: false },
    entretien: { label: 'Agent d’entretien', voirResultats: 'aucun', voirEchographie: 'aucun', prescrire: [], executerSoins: false, remettreResultats: false },
    chauffeur: { label: 'Chauffeur coursier', voirResultats: 'aucun', voirEchographie: 'aucun', prescrire: [], executerSoins: false, remettreResultats: false },
  };

  /** Ce qui se prescrit, et depuis quel écran. */
  var NATURES_PRESCRIPTION = [
    { id: 'analyse', label: 'Analyses de laboratoire' },
    { id: 'medicament', label: 'Médicaments' },
    { id: 'acte', label: 'Actes et soins' },
    { id: 'echographie', label: 'Échographies' },
    { id: 'hospitalisation', label: 'Catégories d’hospitalisation' },
  ];

  /* ==========================================================================
   * CATALOGUE DES ACTES PAR SECTEUR
   * --------------------------------------------------------------------------
   * Source : « RÉPARTITION DES ACTIVITÉS PERMETTANT L'ÉVALUATION DES DIFFÉRENTS
   * SECTEURS DE LA CLINIQUE » (document CNT, deux pages) — il donne, secteur par
   * secteur, ce que chaque service exécute réellement. C'est ce catalogue que le
   * médecin parcourt pour prescrire, et sur lequel s'évalue l'efficacité de
   * chaque service.
   *
   * `prix: null` n'est pas un oubli : les grilles tarifaires des documents de
   * cadrage ont leurs colonnes de prix vierges. Seuls les tarifs lus sur des
   * pièces réellement émises sont renseignés — les autres restent à valider par
   * la Direction et sont signalés comme tels dans l'application.
   * ======================================================================== */
  /* Tarifs d'attente, à valider — voir le commentaire de ACTES ci-dessous. */
  var TARIFS_ATTENTE = {
  MG02: 8000,
  MG03: 10000,
  MG04: 25000,
  MG05: 15000,
  MG06: 2000,
  CH02: 15000,
  CH03: 150000,
  CH04: 5000,
  CH05: 25000,
  CH06: 25000,
  CH07: 60000,
  CH08: 20000,
  CH09: 20000,
  CH10: 12000,
  CH11: 15000,
  CH12: 15000,
  MA01: 3000,
  MA02: 35000,
  MA03: 12000,
  MA04: 3000,
  MA05: 5000,
  MA06: 5000,
  MA07: 3000,
  MA08: 3000,
  MA09: 3000,
  MA10: 25000,
  MA11: 20000,
  MA12: 15000,
  MA13: 20000,
  MA14: 10000,
  MA15: 5000,
  MA16: 8000,
  MA17: 10000,
  MA18: 1000,
  IM01: 8000,
  IM02: 8000,
  IM03: 8000,
  IM04: 10000,
  IM05: 10000,
  IM06: 8000,
  SO03: 800,
  SO04: 800,
  SO06: 3000,
  SO07: 3000,
  SO08: 5000,
  SO09: 2000,
  SO10: 15000,
  SO11: 5000,
  SO12: 5000,
  SO13: 2500,
  SO14: 8000,
  SO15: 5000,
  SO16: 10000,
  SO17: 3000,
  SO18: 2000,
  SO19: 10000,
  SO20: 8000,
  SO21: 5000,
  SO22: 10000,
  SO23: 1000,
  SO24: 1000,
  SO25: 10000,
  SO26: 5000,
  SO27: 5000
};

  var ACTES = [
    /* --- Médecine générale ------------------------------------------------ */
    ['MG01', 'Consultation généraliste', 'Médecine générale', 5000, 'Relevé des prestations, juillet 2026'],
    ['MG02', 'Consultation généraliste à domicile', 'Médecine générale', null, null],
    ['MG03', 'Électrocardiogramme (ECG)', 'Médecine générale', null, null],
    ['MG04', 'MAPA — mesure ambulatoire de la pression artérielle', 'Médecine générale', null, null],
    ['MG05', 'Ponction lombaire', 'Médecine générale', null, null],
    ['MG06', 'Certificat médical', 'Médecine générale', null, null],
    /* --- Chirurgie -------------------------------------------------------- */
    ['CH01', 'Consultation spécialiste', 'Chirurgie', 10000, 'Relevé des prestations, juillet 2026'],
    ['CH02', 'Consultation spécialiste à domicile', 'Chirurgie', null, null],
    ['CH03', 'Opération', 'Chirurgie', null, null],
    ['CH04', 'Pansement chirurgical', 'Chirurgie', null, null],
    ['CH05', 'Petite chirurgie', 'Chirurgie', null, null],
    ['CH06', 'Hydrotubation', 'Chirurgie', null, null],
    ['CH07', 'Cystostomie', 'Chirurgie', null, null],
    ['CH08', 'Ponction pleurale', 'Chirurgie', null, null],
    ['CH09', 'Plâtre', 'Chirurgie', null, null],
    ['CH10', 'Attelle plâtrée', 'Chirurgie', null, null],
    ['CH11', 'Infiltration de kyste synovial', 'Chirurgie', null, null],
    ['CH12', 'Infiltration de genou', 'Chirurgie', null, null],
    /* --- Maternité -------------------------------------------------------- */
    ['MA01', 'Consultation prénatale', 'Maternité', null, null],
    ['MA02', 'Accouchement', 'Maternité', null, null],
    ['MA03', 'Protocole ACE-MISO', 'Maternité', null, null],
    ['MA04', 'Pose de planning familial — Sayana Press', 'Maternité', null, null],
    ['MA05', 'Pose de planning familial — Implanon ou Jadelle', 'Maternité', null, null],
    ['MA06', 'Pose de planning familial — DIU', 'Maternité', null, null],
    ['MA07', 'Pose de planning familial — Noristérat', 'Maternité', null, null],
    ['MA08', 'Retrait de planning familial — Implanon ou Jadelle', 'Maternité', null, null],
    ['MA09', 'Retrait de planning familial — DIU', 'Maternité', null, null],
    ['MA10', 'AMIU — aspiration manuelle intra-utérine', 'Maternité', null, null],
    ['MA11', 'Révision utérine', 'Maternité', null, null],
    ['MA12', 'Expulsion de fœtus', 'Maternité', null, null],
    ['MA13', 'Délivrance artificielle', 'Maternité', null, null],
    ['MA14', 'Épisiotomie', 'Maternité', null, null],
    ['MA15', 'Surveillance de travail d’accouchement', 'Maternité', null, null],
    ['MA16', 'Suture de déchirure', 'Maternité', null, null],
    ['MA17', 'Surveillance de tocolyse', 'Maternité', null, null],
    ['MA18', 'BU — bandelette urinaire', 'Maternité', null, null],
    /* --- Imagerie médicale ------------------------------------------------ */
    ['IM01', 'Échographie pelvienne', 'Imagerie médicale', null, null],
    ['IM02', 'Échographie obstétricale', 'Imagerie médicale', null, null],
    ['IM03', 'Échographie abdominale', 'Imagerie médicale', null, null],
    ['IM04', 'Échographie abdomino-pelvienne', 'Imagerie médicale', null, null],
    ['IM05', 'Échographie prostatique', 'Imagerie médicale', null, null],
    ['IM06', 'Autre échographie', 'Imagerie médicale', null, null],
    /* --- Soins, pansement et hospitalisation ------------------------------ */
    ['SO01', 'Prise de voie veineuse (PVV)', 'Soins et observation', 1200, 'Facture normalisée 21034'],
    ['SO02', 'Soins intraveineux (SIV)', 'Soins et observation', 1000, 'Facture normalisée 21034 — 800 F sur la facture 19727, écart à trancher'],
    ['SO03', 'Soins intramusculaires (SIM)', 'Soins et observation', null, null],
    ['SO04', 'Soins sous-cutanés (SC)', 'Soins et observation', null, null],
    ['SO05', 'Pose et surveillance de perfusion (PSP)', 'Soins et observation', 1500, 'Facture normalisée 21034'],
    ['SO06', 'Sondage naso-gastrique', 'Soins et observation', null, null],
    ['SO07', 'Sondage vésical', 'Soins et observation', null, null],
    ['SO08', 'Suture', 'Soins et observation', null, null],
    ['SO09', 'Pansement', 'Soins et observation', null, null],
    ['SO10', 'Ponction drainage d’ascite', 'Soins et observation', null, null],
    ['SO11', 'Ablation de frein de langue', 'Soins et observation', null, null],
    ['SO12', 'Oxygénothérapie', 'Soins et observation', null, null],
    ['SO13', 'Aérosolthérapie', 'Soins et observation', null, null],
    ['SO14', 'Hospitalisation', 'Soins et observation', null, null],
    ['SO15', 'Mise en observation', 'Soins et observation', null, null],
    ['SO16', 'Mise à plat d’abcès', 'Soins et observation', null, null],
    ['SO17', 'Lavage vésical', 'Soins et observation', null, null],
    ['SO18', 'Lavage d’oreille', 'Soins et observation', null, null],
    ['SO19', 'Ponction sus-pubienne', 'Soins et observation', null, null],
    ['SO20', 'Panaris', 'Soins et observation', null, null],
    ['SO21', 'Extraction de corps étranger', 'Soins et observation', null, null],
    ['SO22', 'Infiltration chéloïde', 'Soins et observation', null, null],
    ['SO23', 'Glycémie rapide', 'Soins et observation', null, null],
    ['SO24', 'Taux d’hémoglobine rapide', 'Soins et observation', null, null],
    ['SO25', 'Soins à domicile', 'Soins et observation', null, null],
    ['SO26', 'Surveillance de prématuré', 'Soins et observation', null, null],
    ['SO27', 'Pousse-seringue', 'Soins et observation', null, null],
  ].map(function (a) {
    /* Décision de la Direction (20/08/2026) : renseigner un tarif d'attente sur
       tout acte que les documents ne tarifent pas, afin que la facturation soit
       exerçable en démonstration. Ces valeurs restent explicitement PROVISOIRES —
       elles se corrigent depuis le référentiel tarifaire, écran par écran. */
    var attente = TARIFS_ATTENTE[a[0]] || null;
    return {
      code: a[0], libelle: a[1], secteur: a[2],
      prix: a[3] != null ? a[3] : attente,
      tarifProvisoire: a[3] == null && attente != null,
      source: a[4] || (attente != null ? 'Valeur d'+String.fromCharCode(8217)+'attente — à valider par la Direction' : null),
      statut: 'actif',
    };
  });

  /* ==========================================================================
   * NATURES DE FACTURE ET CENTRES DE COÛTS
   * --------------------------------------------------------------------------
   * Deux listes que l'écran de facturation et la saisie comptable portaient en
   * dur — la première ignorait la Maternité et la Mise en observation, pourtant
   * facturées tous les jours. Elles deviennent des référentiels amorcés par le
   * magasin, donc disponibles depuis n'importe quel écran, et administrables.
   * ======================================================================== */
  var NATURES_FACTURE = [
    ['CONS', 'Consultation généraliste', 'Médecine générale'],
    ['CSPE', 'Consultation spécialiste', 'Chirurgie'],
    ['CCPN', 'Consultation prénatale (CPN)', 'Maternité'],
    ['MATE', 'Maternité', 'Maternité'],
    ['OBSE', 'Mise en observation', 'Soins et observation'],
    ['HOSP', 'Hospitalisation', 'Soins et observation'],
    ['LABO', 'Laboratoire', 'Laboratoire'],
    ['PHAR', 'Pharmacie', 'Pharmacie'],
    ['SOIN', 'Soins', 'Soins et observation'],
    ['ECHO', 'Échographie', 'Imagerie médicale'],
    ['CHIR', 'Chirurgie', 'Chirurgie'],
    ['DOMI', 'Soins à domicile', 'Soins et observation'],
    ['CERT', 'Certificat médical', 'Médecine générale'],
    ['AMBU', 'Ambulance', 'Accueil'],
  ].map(function (n, i) {
    return {
      id: 'NAT' + C.pad(i + 1, 2), statut: 'actif', ordre: i + 1,
      code: n[0], libelle: n[1], secteur: n[2],
      source: 'Émission de facture — demande de la Direction du 19/08/2026',
    };
  });

  /** Les huit secteurs porteurs d'activité facturable (le document en liste 8). */
  var SECTEURS_ACTIVITE = ['Médecine générale', 'Chirurgie', 'Maternité', 'Imagerie médicale',
    'Laboratoire', 'Accueil', 'Soins et observation', 'Pharmacie'];


  /** Axes analytiques : un centre par secteur porteur d'activité, plus les supports. */
  var CENTRES_COUTS = SECTEURS_ACTIVITE.map(function (s, i) {
    return {
      id: 'CC' + C.pad(i + 1, 2), statut: 'actif', code: 'CC' + C.pad(i + 1, 2),
      libelle: s, type: 'exploitation', responsable: null,
      source: 'Secteurs d’activité de la clinique (NS 145)',
    };
  }).concat([
    { id: 'CC90', statut: 'actif', code: 'CC90', libelle: 'Administration générale', type: 'support', responsable: null, source: 'Organigramme' },
    { id: 'CC91', statut: 'actif', code: 'CC91', libelle: 'Entretien et sécurité', type: 'support', responsable: null, source: 'Organigramme' },
    { id: 'CC92', statut: 'actif', code: 'CC92', libelle: 'Ambulance et transport', type: 'support', responsable: null, source: 'Organigramme' },
  ]);


  /* ==========================================================================
   * CALENDRIER FISCAL ET SOCIAL
   * --------------------------------------------------------------------------
   * Transcription des précisions données par le comptable en réunion. Les dates
   * sont des ÉCHÉANCES LÉGALES : quand elles tombent un week-end, le jour
   * ouvrable suivant fait foi.
   *
   * L'impôt sur les sociétés se paie par anticipation : quatre acomptes assis
   * sur l'impôt de l'année précédente, divisé en quatre. Le solde se liquide au
   * 30 avril de l'année suivante, en même temps que le dépôt des états
   * financiers.
   * ======================================================================== */
  /* [code, libellé, périodicité, jour, mois (0-11), part %, déclaration préalable, note] */
  var CALENDRIER_FISCAL = [
    ['ITS', 'Impôt sur les traitements salariaux', 'mensuelle', 10, null, 100,
      'Déclaration mensuelle avant paiement',
      'Le 10 du mois suivant le mois d’exercice. Reporté au jour ouvrable suivant si l’échéance tombe un week-end.'],
    ['AIB', 'Acompte sur impôt assis sur les bénéfices', 'mensuelle', 10, null, 100,
      'Déclaration mensuelle avant paiement',
      'Le 10 de chaque mois, après la déclaration préalable.'],
    ['VPS', 'Versement patronal sur salaires', 'mensuelle', 10, null, 100,
      'Déclaration mensuelle avant paiement',
      'Le 10 du mois suivant le mois d’exercice.'],
    ['CNSS', 'Cotisations sociales CNSS', 'mensuelle', 10, null, 100,
      'Déclaration mensuelle avant paiement',
      'Le 10 du mois suivant. Part patronale 16,4 %, part ouvrière 3,6 %.'],

    ['IS-1', 'Impôt sur les sociétés — 1er acompte', 'annuelle', 10, 2, 25, null,
      'Premier des quatre acomptes trimestriels, assis sur l’impôt de l’exercice précédent divisé par quatre. '
      + 'Le 10 mars — confirmé par la Direction le 25/08/2026.'],
    ['IS-2', 'Impôt sur les sociétés — 2e acompte', 'annuelle', 10, 5, 25, null, 'Deuxième acompte trimestriel.'],
    ['IS-3', 'Impôt sur les sociétés — 3e acompte', 'annuelle', 10, 8, 25, null, 'Troisième acompte trimestriel.'],
    ['IS-4', 'Impôt sur les sociétés — 4e acompte', 'annuelle', 10, 11, 25, null, 'Quatrième acompte trimestriel.'],
    ['IS-SOLDE', 'Liquidation du solde de l’impôt sur les sociétés', 'annuelle', 30, 3, null, null,
      'Le 30 avril de chaque année, PRÉALABLEMENT au dépôt des états financiers. Ajuste à la hausse ou à la '
      + 'baisse les acomptes versés l’exercice précédent — confirmé par la Direction le 25/08/2026.'],
    ['ETATS-FIN', 'Dépôt des états financiers', 'annuelle', 30, 3, null, null,
      'Le 30 avril de l’année suivant l’exercice clos, après la liquidation du solde.'],

    ['PATENTE-DECL', 'Patente — déclaration prévisionnelle', 'annuelle', 31, 0, null, null,
      'Date limite de la déclaration prévisionnelle de la patente.'],
    ['PATENTE-1', 'Patente — 1er acompte', 'annuelle', 10, 1, 50, 'Déclaration prévisionnelle au 31 janvier',
      'Première moitié. La patente se paie une fois par an, avec possibilité de régler en deux tranches.'],
    ['PATENTE-2', 'Patente — solde', 'annuelle', 30, 3, 50, null, 'Seconde moitié, au 30 avril.'],

    ['CCIB-DECL', 'CCIB — déclaration prévisionnelle', 'annuelle', 28, 1, null, null,
      'La déclaration prévisionnelle s’effectue à la FIN DU MOIS, avant le premier acompte — '
      + 'confirmé par la Direction le 25/08/2026.'],
    ['CCIB-1', 'CCIB — 1re tranche', 'annuelle', 10, 2, 50, 'Déclaration prévisionnelle en fin de mois',
      'Contribution annuelle de 300 000 FCFA, réglée en deux tranches égales de 150 000 FCFA. '
      + 'Premier acompte le 10 mars (50 %) — confirmé par la Direction le 25/08/2026.'],
    ['CCIB-2', 'CCIB — 2e tranche', 'annuelle', 10, 5, 50, null, 'Seconde tranche de 150 000 FCFA, le 10 juin (50 %) — confirmé par la Direction le 25/08/2026.'],

    ['TVM', 'Taxe sur véhicules à moteur', 'annuelle', 30, 3, 100, null,
      'Une fois par an, au plus tard le 30 avril.'],

    ['ORTB-RADIO', 'Redevance ORTB / Radio', 'annuelle', 30, 2, 100, null,
      'Prélevée sur TOUS les salariés sans exception — 1 000 FCFA par agent, au mois de mars.'],
    ['ORTB-TELE', 'Redevance ORTB / Télé', 'annuelle', 30, 5, 100, null,
      'Prélevée en SUS de la radio sur les salaires supérieurs à 60 000 FCFA — 3 000 FCFA par agent, au mois de juin.'],
  ].map(function (e, i) {
    return {
      id: 'FIS' + C.pad(i + 1, 2), code: e[0], libelle: e[1],
      periodicite: e[2], jour: e[3], mois: e[4],
      part: e[5], declaration: e[6], note: e[7],
      famille: e[0].split('-')[0],
      statut: 'actif',
      source: 'Précisions du comptable — réunion du 19/08/2026',
    };
  });

  /** Montants connus, à confirmer par le cabinet comptable. */
  var MONTANTS_FISCAUX = {
    ccib: { total: 300000, tranches: 2, note: 'Deux tranches de 150 000 F' },
    ortbRadio: 1000, ortbTele: 3000, ortbCumul: 4000,
  };


  /* ==========================================================================
   * VALORISATION DES SORTIES DE STOCK
   * --------------------------------------------------------------------------
   * Annotation manuscrite de la réunion du 30/12/2024 : « Paramétrer pour que
   * les produits sortent au Prix de Vente et non au CUMP ». Le mot compte —
   * la Direction demande un PARAMÈTRE, pas une règle figée.
   *
   * Ce que cela change aujourd'hui : rien, ou presque. RG-02 impose que les
   * médicaments soient facturés au prix d'achat, sans marge ; le prix de vente
   * égale donc le prix d'achat, lui-même arrondi du CUMP. Sur les 184 articles
   * de l'inventaire SAGE, l'écart entre les deux valorisations est de
   * 1 015 FCFA au total — un effet d'arrondi, pas une différence de méthode.
   *
   * Ce que cela changera : le jour où une marge sera appliquée à un article
   * hors médicament — le cahier de charge le permet, sur validation tracée de
   * la Direction — les deux valorisations divergeront réellement. Le paramètre
   * décide alors si la marge est reconnue à la sortie de stock (prix de vente)
   * ou seulement à la facturation (CUMP).
   * ======================================================================== */
  var PARAM_STOCK = {
    valorisationSortie: 'prixVente',
    options: [
      {
        id: 'prixVente', label: 'Prix de vente',
        note: 'Valeur de sortie = prix de vente de l’article. Demandé par la Direction ; '
          + 'la marge éventuelle est reconnue dès la sortie de stock.',
      },
      {
        id: 'cump', label: 'Coût unitaire moyen pondéré (CUMP)',
        note: 'Valeur de sortie = coût moyen d’acquisition. Méthode comptable classique ; '
          + 'la marge n’apparaît qu’à la facturation.',
      },
      {
        id: 'lot', label: 'Prix du lot sorti (FEFO)',
        note: 'Valeur de sortie = ce que le lot a RÉELLEMENT coûté. La plus exacte quand les lots '
          + 'sont suivis un à un — ce qu’impose déjà la traçabilité des médicaments. Le lot qui n’a '
          + 'pas de prix propre retombe sur le CUMP, et la sortie le dit : mieux vaut une valeur '
          + 'annoncée approximative qu’une valeur fausse qu’on croit exacte.',
      },
    ],
    source: 'Annotation manuscrite — réunion du 30/12/2024 ; méthode par lot ajoutée le 07/09/2026',
    ecartConstate: 1015,
    note: 'Tant que RG-02 s’applique (médicaments au prix d’achat, sans marge), les trois méthodes '
      + 'donnent des résultats voisins ; elles divergeront le jour où une marge sera appliquée.',
    /* Le COEFFICIENT DE VENTE existe dès aujourd'hui, et vaut 1,00 : la
       clinique vend au prix d'achat (RG-02). Le prévoir maintenant coûte une
       colonne ; l'ajouter plus tard obligerait à reprendre chaque ligne
       historique pour savoir à quel coefficient elle avait été valorisée. */
    coefficientVente: 1,
    noteCoefficient: 'Coefficient appliqué au prix d’achat pour obtenir le prix de vente. Il vaut '
      + '1,00 : RG-02 interdit la marge sur le médicament. Il existe pour que la clinique puisse un '
      + 'jour couvrir ses coûts de pharmacie sans reprendre l’historique.',
  };

  /* ==========================================================================
   * GROUPES ET FAMILLES D'ARTICLES
   * --------------------------------------------------------------------------
   * Les FAMILLES existent dans le document source : l'inventaire SAGE « Grand
   * Stock » classe ses 184 articles en sept catégories. Les GROUPES, eux, ne
   * figurent dans aucun document — ils sont ici une lecture à deux niveaux de
   * cette classification, proposée à la Direction et non déduite d'une source.
   * D'où le drapeau aConfirmer, que les écrans affichent.
   * ======================================================================== */
  var FAMILLES_ARTICLES = [
    { id: 'medicament', label: 'Médicaments', groupe: 'pharmacie' },
    { id: 'conso_medical', label: 'Consommables médicaux', groupe: 'pharmacie' },
    { id: 'reactif', label: 'Réactifs de laboratoire', groupe: 'laboratoire' },
    { id: 'conso_labo', label: 'Consommables de laboratoire', groupe: 'laboratoire' },
    { id: 'petit_materiel', label: 'Petit matériel médical', groupe: 'equipement' },
    { id: 'entretien', label: 'Produits d’entretien', groupe: 'logistique' },
    { id: 'fourniture', label: 'Fournitures de bureau', groupe: 'logistique' },
  ];

  /* --------------------------------------------------------------------------
   * GROUPES DE PRESTATION — pour les points de vente
   * --------------------------------------------------------------------------
   * « Le point pour un groupe d'articles choisis : groupe de soins, groupe
   * d'analyse. » Les lignes de facture portent leur categorie ; le groupe les
   * coiffe. « Soins » n'est pas une catégorie, c'est une famille de catégories
   * — la consultation et l'acte s'y rangent ensemble parce que c'est ainsi que
   * la clinique compte son activité de soins.
   *
   * L'hospitalisation reste à part : c'est une durée facturée, pas un acte, et
   * la fondre dans les soins rendrait le prix de journée incomparable d'un mois
   * à l'autre.
   * ----------------------------------------------------------------------- */
  /* --------------------------------------------------------------------------
   * CATÉGORIES DE DÉPENSES — la lecture de GESTION
   * --------------------------------------------------------------------------
   * À ne pas confondre avec le compte de charge SYSCOHADA, qui est la lecture
   * COMPTABLE. Le même achat de gants est « 604100 Matières consommables »
   * pour le comptable et « Consommables médicaux » pour la Directrice. Fondre
   * les deux obligerait l'un à lire la langue de l'autre.
   *
   * Les comptes proposés par défaut viennent du plan comptable réel de la
   * clinique : ce sont les comptes qu'elle mouvemente déjà.
   * ----------------------------------------------------------------------- */
  /* --------------------------------------------------------------------------
   * SOLDES INTERMÉDIAIRES DE GESTION — la cascade SYSCOHADA
   * --------------------------------------------------------------------------
   * Le compte de résultat ne s'écrit pas d'un bloc : il se construit par
   * soldes successifs, chacun répondant à une question et retranchant au
   * précédent. C'est cette cascade qui dit D'OÙ vient le résultat, et pas
   * seulement combien il vaut.
   *
   * Le rattachement se fait par PRÉFIXE DE COMPTE : c'est la seule règle
   * stable, et elle survit à l'ajout d'un compte au plan.
   * ----------------------------------------------------------------------- */
  var RUBRIQUES_RESULTAT = [
    { id: 'ventes_march', label: 'Ventes de marchandises', sens: 'produit',
      prefixes: ['7011'], sig: 'marge',
      note: 'Médicaments et consommables revendus. RG-02 les facture au prix d’achat : '
        + 'la marge commerciale doit être nulle ou quasi nulle.' },
    { id: 'achats_march', label: 'Achats de marchandises', sens: 'charge',
      prefixes: ['601', '6032'], sig: 'marge' },
    { id: 'production', label: 'Prestations de services', sens: 'produit',
      prefixes: ['7061', '702', '704', '707'], sig: 'valeurAjoutee',
      note: 'Consultations, analyses, actes, hospitalisation : le cœur de l’activité.' },
    { id: 'consommations', label: 'Consommations intermédiaires', sens: 'charge',
      prefixes: ['602', '604', '605', '608', '61', '62', '63'], sig: 'valeurAjoutee',
      note: 'Réactifs, eau, électricité, entretien, honoraires, frais bancaires — '
        + 'tout ce que la clinique achète pour travailler.' },
    { id: 'impots', label: 'Impôts et taxes', sens: 'charge',
      prefixes: ['64'], sig: 'ebe' },
    { id: 'personnel', label: 'Charges de personnel', sens: 'charge',
      prefixes: ['66'], sig: 'ebe',
      note: 'Salaires bruts et charges sociales patronales.' },
    { id: 'dotations', label: 'Dotations aux amortissements', sens: 'charge',
      prefixes: ['68'], sig: 'exploitation' },
    { id: 'autres_charges', label: 'Autres charges d’exploitation', sens: 'charge',
      prefixes: ['65'], sig: 'exploitation' },
    { id: 'produits_fin', label: 'Produits financiers', sens: 'produit',
      prefixes: ['77'], sig: 'financier' },
    { id: 'charges_fin', label: 'Charges financières', sens: 'charge',
      prefixes: ['67'], sig: 'financier',
      note: 'Intérêts d’emprunt. Ils sont ICI et non dans l’exploitation : les y mettre '
        + 'ferait juger l’activité sur des choix de financement.' },
    { id: 'impot_societes', label: 'Impôt sur le résultat', sens: 'charge',
      prefixes: ['89'], sig: 'net' },
  ];

  /* --------------------------------------------------------------------------
   * NATURE FIXE OU VARIABLE — un JUGEMENT, pas une donnée
   * --------------------------------------------------------------------------
   * Aucun plan comptable ne porte cette distinction : elle relève de l'analyse
   * de gestion. La proposition ci-dessous est celle qu'un comptable ferait
   * pour une clinique, et l'écran la présente COMME UNE PROPOSITION, modifiable
   * compte par compte. La cacher donnerait un seuil de rentabilité qui a l'air
   * d'un fait alors qu'il dépend d'un choix.
   * ----------------------------------------------------------------------- */
  var NATURE_CHARGE = {
    /* Variables : elles suivent l'activité. Une consultation de plus, c'est
       des gants de plus. */
    '601': 'variable', '602': 'variable', '603': 'variable', '604': 'variable',
    '608': 'variable', '612': 'variable',
    /* Fixes : elles tombent qu'on travaille ou non. */
    '605': 'fixe', '616': 'fixe', '618': 'fixe', '622': 'fixe', '624': 'fixe',
    '625': 'fixe', '627': 'fixe', '628': 'fixe', '631': 'fixe', '632': 'fixe',
    '634': 'fixe', '635': 'fixe', '637': 'fixe', '638': 'fixe',
    '64': 'fixe', '65': 'fixe', '66': 'fixe', '67': 'fixe', '68': 'fixe',
  };
  NATURE_CHARGE.aValider = true;
  NATURE_CHARGE.note = 'Répartition PROPOSÉE par défaut. Elle relève de l’analyse de gestion, '
    + 'non du plan comptable, et se corrige compte par compte.';

  /** La rubrique d'un compte, par préfixe — la seule règle qui survive à
      l'ajout d'un compte au plan. */
  function rubriqueDuCompte(num) {
    var n = String(num || '');
    var trouvee = null, longueur = -1;
    RUBRIQUES_RESULTAT.forEach(function (r) {
      r.prefixes.forEach(function (p) {
        if (n.indexOf(p) === 0 && p.length > longueur) { trouvee = r; longueur = p.length; }
      });
    });
    return trouvee;
  }

  /** Fixe ou variable — le préfixe le plus long l'emporte. */
  function natureCharge(num) {
    var n = String(num || '');
    var val = null, longueur = -1;
    Object.keys(NATURE_CHARGE).forEach(function (p) {
      if (typeof NATURE_CHARGE[p] !== 'string') return;
      if (n.indexOf(p) === 0 && p.length > longueur) { val = NATURE_CHARGE[p]; longueur = p.length; }
    });
    return val || 'fixe';
  }

  var CATEGORIES_DEPENSE = [
    { id: 'medical', label: 'Consommables et produits médicaux', icone: 'pill',
      comptes: ['6011', '6041', '6056'] },
    { id: 'fonctionnement', label: 'Fonctionnement courant', icone: 'building-2',
      comptes: ['6043', '6047', '6051', '6052', '6054'] },
    { id: 'logistique', label: 'Logistique et transport', icone: 'truck',
      comptes: ['6042', '612', '616', '6181', '6183'] },
    { id: 'entretien', label: 'Entretien, réparations et maintenance', icone: 'wrench',
      comptes: ['6044', '6044', '6044', '6241', '6242', '6243'] },
    { id: 'personnel', label: 'Personnel et prestations externes', icone: 'users-round',
      comptes: ['6371', '6324', '6327', '6384'] },
    { id: 'fiscal', label: 'Impôts, taxes et frais bancaires', icone: 'landmark',
      comptes: ['6318', '6318', '6318', '6412', '6462', '6468'] },
    { id: 'divers', label: 'Charges diverses', icone: 'circle-ellipsis',
      comptes: ['6383', '638', '6582', '6588'] },
  ];

  /** Catégories documentaires de la GED (CDCT §10.12). Vivent ici et non dans
      ged.js : le peuplement du socle et l'écran GED lisent la même liste. */
  var GED_CATEGORIES = [
    { id: 'ordonnance', label: 'Ordonnances', rattachement: 'Patient', icon: 'file-text' },
    { id: 'resultat', label: 'Résultats de laboratoire', rattachement: 'Patient', icon: 'flask-conical' },
    { id: 'rapport', label: 'Rapports médicaux', rattachement: 'Patient', icon: 'stethoscope' },
    { id: 'facture_patient', label: 'Factures patients', rattachement: 'Patient', icon: 'receipt' },
    { id: 'bon_commande', label: 'Bons de commande', rattachement: 'Fournisseur', icon: 'truck' },
    { id: 'bon_livraison', label: 'Bons de livraison', rattachement: 'Fournisseur', icon: 'package-check' },
    { id: 'facture_fournisseur', label: 'Factures fournisseurs', rattachement: 'Fournisseur', icon: 'file-text' },
    { id: 'contrat', label: 'Contrats RH', rattachement: 'Employé', icon: 'file-signature' },
    { id: 'bulletin', label: 'Bulletins de paie', rattachement: 'Employé', icon: 'banknote' },
    { id: 'courrier', label: 'Courriers administratifs', rattachement: 'Administration', icon: 'mail' },
  ];

  /* ==========================================================================
   * LES SIX GROUPES DE PRESTATION — arrêtés par la Direction le 07/09/2026
   * --------------------------------------------------------------------------
   * Ce sont les SECTEURS de la clinique, dans l'ordre qu'elle emploie. Ils
   * commandent partout la même lecture : recettes par groupe, bénéfice brut
   * par groupe, rapprochement avec les centres de coûts, origine de
   * prescription du tableau croisé. AUCUN SECTEUR NE MANQUE — c'est la
   * condition posée : une prestation dont le groupe serait absent
   * disparaîtrait de toutes les analyses à la fois.
   *
   * `categories` rattache les lignes de facture au groupe. Une catégorie ne
   * peut appartenir qu'à UN groupe, sinon la même recette se compterait deux
   * fois ; l'échographie et la maternité, qui n'ont pas de catégorie de ligne
   * propre, se reconnaissent au SECTEUR de la prestation (`secteur`).
   * ======================================================================== */
  var GROUPES_PRESTATION = [
    { id: 'laboratoire', label: 'Laboratoire', categories: ['analyse'], secteurs: ['LAB'], icone: 'flask-conical' },
    { id: 'pharmacie', label: 'Pharmacie', categories: ['medicament'], secteurs: ['CPH', 'PHA'], icone: 'pill' },
    { id: 'consultation', label: 'Consultation', categories: ['consultation'], secteurs: ['MGE', 'CONS'], icone: 'stethoscope' },
    { id: 'echographie', label: 'Échographie', categories: ['imagerie'], secteurs: ['IMG', 'ECHO'], icone: 'scan-line' },
    { id: 'maternite', label: 'Maternité', categories: ['maternite'], secteurs: ['MAT'], icone: 'baby' },
    { id: 'hospitalisation', label: 'Hospitalisation et soins', categories: ['hospitalisation', 'acte'], secteurs: ['HOS', 'SUR'], icone: 'bed-double' },
  ];

  var CATEGORIES_LIGNE = [
    { id: 'consultation', label: 'Consultation' },
    { id: 'acte', label: 'Acte / soin' },
    { id: 'analyse', label: 'Analyse' },
    { id: 'medicament', label: 'Médicament' },
    { id: 'imagerie', label: 'Échographie / imagerie' },
    { id: 'maternite', label: 'Maternité' },
    { id: 'hospitalisation', label: 'Hospitalisation' },
  ];

  function groupePrestation(categorie) {
    return GROUPES_PRESTATION.filter(function (g) {
      return g.categories.indexOf(categorie) >= 0;
    })[0] || null;
  }

  /**
   * Le SECTEUR d'une valeur quelconque — identifiant de groupe, code de
   * secteur (NS 145), libellé de service ou d'unité — ramené aux SIX secteurs
   * de la clinique. C'est la fonction que consultent les axes d'analyse : une
   * seule liste, une seule façon de nommer, partout.
   */
  function secteurPrestation(valeur) {
    var k = String(valeur == null ? '' : valeur).toLowerCase();
    if (!k || k === '—') return '—';
    var direct = GROUPES_PRESTATION.filter(function (g) {
      return g.id === k || (g.secteurs || []).some(function (s) { return s.toLowerCase() === k; });
    })[0];
    if (direct) return direct.label;
    if (/labo/.test(k)) return 'Laboratoire';
    if (/pharma|dispens|officine/.test(k)) return 'Pharmacie';
    if (/consult|m[ée]decine|g[ée]n[ée]rale|accueil/.test(k)) return 'Consultation';
    if (/[ée]chograph|imagerie|radio/.test(k)) return 'Échographie';
    if (/maternit|obst[ée]|accouch/.test(k)) return 'Maternité';
    if (/hospit|soins|chirurgie|observation|bloc|urgence/.test(k)) return 'Hospitalisation et soins';
    return String(valeur);
  }
  function libelleCategorieLigne(id) {
    var c = CATEGORIES_LIGNE.filter(function (x) { return x.id === id; })[0];
    return c ? c.label : (id || 'Autre');
  }

  var GROUPES_ARTICLES = [
    { id: 'pharmacie', label: 'Pharmacie et consommables de soins' },
    { id: 'laboratoire', label: 'Laboratoire' },
    { id: 'equipement', label: 'Équipement et petit matériel' },
    { id: 'logistique', label: 'Logistique et fonctionnement' },
  ];
  /* CONFIRMÉS par la Direction le 01/09/2026 (vague 49 — passage des
     validations en attente) : les quatre groupes cessent d'être une
     proposition. La note d'origine reste ci-dessus : elle documente qu'ils
     ne venaient d'aucun document avant cette décision. */
  GROUPES_ARTICLES.aConfirmer = false;
  GROUPES_ARTICLES.confirmesLe = '2026-09-01';
  GROUPES_ARTICLES.confirmesPar = 'Direction';
  GROUPES_ARTICLES.source = 'Regroupement proposé à partir des sept catégories de l’inventaire SAGE — à valider par la Direction';

  function familleDe(categorie) {
    return FAMILLES_ARTICLES.filter(function (f) { return f.id === categorie; })[0] || null;
  }
  function groupeDe(categorie) {
    var f = familleDe(categorie);
    if (!f) return null;
    return GROUPES_ARTICLES.filter(function (g) { return g.id === f.groupe; })[0] || null;
  }

  /** Catalogue des états imprimables — CDCT §21 + draf1 « Bibliothèque des États ». */
  var CATALOGUE_ETATS = [
    { domaine: 'Patients / Soins', etats: ['Carte patient', 'Fiche patient', 'Historique médical', 'Parcours de soins', 'Compte rendu de consultation', 'Ordonnance', 'Certificat médical', 'Bon d’examen'] },
    { domaine: 'Hospitalisation', etats: ['Bon d’admission', 'Feuille de température', 'Feuille de soins', 'Bon de sortie', 'Sortie contre avis médical', 'Rapport d’hospitalisation'] },
    { domaine: 'Maternité & Décès', etats: ['Fiche d’accouchement', 'Acte de naissance', 'Registre des naissances', 'Déclaration de décès', 'Registre des décès'] },
    { domaine: 'Laboratoire', etats: ['Résultat d’analyse', 'Rapport biologique', 'Bon de prélèvement', 'Registre des analyses', 'Bon de demande de sang'] },
    { domaine: 'Stock / Pharmacie', etats: ['Bon d’expression de besoins', 'Bon de commande', 'Bon de livraison', 'Bon de sortie de stock', 'État d’inventaire', 'État des produits périmés', 'État des alertes de stock', 'Étiquettes produits'] },
    { domaine: 'Facturation', etats: ['Facture normalisée MECeF', 'Facture pro-forma', 'Reçu de paiement', 'Avoir', 'État de caisse journalier', 'Historique des paiements'] },
    { domaine: 'Assurances', etats: ['Facture mensuelle par assureur', 'État des créances', 'Lettre de relance', 'État des prises en charge'] },
    { domaine: 'RH', etats: ['Contrat de travail', 'Fiche employé', 'Fiche d’évaluation (NS 131)', 'Planning de garde/permanence', 'État des présences', 'État des congés', 'Notification de sanction'] },
    { domaine: 'Paie', etats: ['Bulletin de paie', 'Fiche de solde mensuelle', 'Journal de paie', 'État des cotisations CNSS', 'État ITS', 'État VPS', 'État des primes'] },
    { domaine: 'Comptabilité', etats: ['Journaux comptables', 'Grand livre', 'Balance générale', 'Balance âgée', 'Tableau d’amortissement', 'État de rapprochement bancaire', 'Bilan', 'Compte de résultat', 'Tableau des flux de trésorerie'] },
    { domaine: 'Administration', etats: ['Registre des courriers', 'Compte rendu de réunion', 'Plan annuel de travail', 'Note de service'] },
    { domaine: 'Pilotage', etats: ['Tableau de bord financier', 'Tableau de bord stock', 'Tableau de bord RH', 'Tableau de bord d’activité', 'Rapport d’activité'] },
    { domaine: 'Sécurité', etats: ['Journal d’audit', 'Liste des comptes utilisateurs et rôles'] },
  ];

  /** Matrice « document collecté → rôle dans le logiciel » (draf1 §2). */
  var SOURCES_VERITE = [
    { document: 'Organigramme de la Clinique NASSIERA TOO', devient: 'Structure organisationnelle + RBAC', module: 'M14 / CFG', ecran: 'cfg-organisation', statut: 'Intégré' },
    { document: 'NS 131/07/DM/DA/CNT/2026', devient: 'Moteur d’évaluation et de sanctions', module: 'M10', ecran: 'm10-evaluations', statut: 'Intégré' },
    { document: 'NS 132/07/DM/DA/CNT/2026', devient: 'Moteur des primes', module: 'M10 / M11', ecran: 'm10-primes', statut: 'Intégré' },
    { document: 'Fiche d’évaluation et de solde (juillet 2026)', devient: 'Modèle d’état imprimable', module: 'M10 / RAP', ecran: 'm10-evaluations', statut: 'Intégré' },
    { document: 'Tarifs des analyses de laboratoire (48)', devient: 'Catalogue laboratoire', module: 'M5', ecran: 'm5-catalogue', statut: 'Intégré — tarifs à confirmer' },
    { document: 'Tarifs des médicaments et accessoires (144)', devient: 'Catalogue tarifaire pharmacie', module: 'M6', ecran: 'cfg-tarifs', statut: 'Intégré — tarifs à confirmer' },
    { document: 'Inventaire « Grand Stock » (SAGE 100)', devient: 'Stock initial — 175 articles repris', module: 'M6', ecran: 'm6-reprise', statut: 'Intégré' },
    { document: 'Facture fournisseur SoBAPS (BL 26LNA00026)', devient: 'Modèle du workflow achat', module: 'M7', ecran: 'm7-receptions', statut: 'Intégré' },
    { document: 'Bon d’expression de besoins (modèle vierge)', devient: 'Workflow de demande interne', module: 'M7', ecran: 'm7-besoins', statut: 'Intégré' },
    { document: 'Classeur comptable SYSCOHADA', devient: 'Plan comptable + journaux', module: 'M12', ecran: 'm12-plan-comptable', statut: 'Intégré — partiel' },
    { document: 'Compte de résultat mensuel 2025', devient: 'Baseline financière de comparaison', module: 'M12 / M14', ecran: 'm12-etats-financiers', statut: 'À importer' },
    { document: 'Planning de travail des médecins', devient: 'Moteur de planning (garde 24h)', module: 'M10', ecran: 'm10-planning', statut: 'Intégré' },
    { document: 'Planning agents d’entretien et sécurité', devient: 'Moteur de planning RH', module: 'M10', ecran: 'm10-securite-entretien', statut: 'Intégré' },
    { document: 'Liste des 13 compagnies d’assurance', devient: 'Référentiel assureurs', module: 'M9', ecran: 'm9-compagnies', statut: 'Intégré' },
    { document: 'Photographies du site et entête officielle', devient: 'Brand Configuration Center', module: 'CFG', ecran: 'cfg-branding', statut: 'Intégré' },
  ];

  global.SIGH.data = {
    ORGANIGRAMME: ORGANIGRAMME, FONCTIONS: FONCTIONS,
    PARAM_EVENEMENTS: PARAM_EVENEMENTS,
    PATHOLOGIES: PATHOLOGIES, CHAPITRES_PATHOLOGIE: CHAPITRES_PATHOLOGIE,
    ETATS_RESULTAT: ETATS_RESULTAT, etatResultat: etatResultat, resultatRendu: resultatRendu,
    NS131: NS131, NS132: NS132,
    ASSUREURS: ASSUREURS, ANALYSES: ANALYSES,
    CATEGORIES_PRODUIT: CATEGORIES_PRODUIT, TYPES_STOCK: TYPES_STOCK, TYPES_MOUVEMENT: TYPES_MOUVEMENT,
    FOURNISSEURS: FOURNISSEURS, PLAN_COMPTABLE: PLAN_COMPTABLE, JOURNAUX: JOURNAUX, CENTRES_COUT: CENTRES_COUT,
    COMPTES_SIGH: COMPTES_SIGH, libelleCompte: libelleCompte,
    PARAM_FISCAL: PARAM_FISCAL, PARAM_AIB: PARAM_AIB, tauxAIB: tauxAIB, baremeAIB: baremeAIB,
    aibTiers: aibTiers,
    PARAM_PAIE: PARAM_PAIE, TYPES_CHAMBRE: TYPES_CHAMBRE, CHAMBRES: CHAMBRES,
    MODES_PAIEMENT: MODES_PAIEMENT, TYPES_PLANNING: TYPES_PLANNING, SERVICES: SERVICES,
    REGLES_PLANNING: REGLES_PLANNING, regleDe: regleDe,
    GROUPES_SANGUINS: GROUPES_SANGUINS, CATALOGUE_ETATS: CATALOGUE_ETATS, SOURCES_VERITE: SOURCES_VERITE,
    ANTECEDENTS: ANTECEDENTS, ANTECEDENTS_RISQUE: ANTECEDENTS_RISQUE,
    ALLERGIES: ALLERGIES, ACTES_SOINS: ACTES_SOINS,
    UNITES_OBSERVATION: UNITES_OBSERVATION, ORIENTATIONS_OBSERVATION: ORIENTATIONS_OBSERVATION,
    DUREE_OBSERVATION_REFERENCE: DUREE_OBSERVATION_REFERENCE,
    ACTES: ACTES, SECTEURS_ACTIVITE: SECTEURS_ACTIVITE, NS145: NS145,
    NATURES_FACTURE: NATURES_FACTURE, CENTRES_COUTS: CENTRES_COUTS,
    PARAM_STOCK: PARAM_STOCK, FAMILLES_ARTICLES: FAMILLES_ARTICLES, GROUPES_ARTICLES: GROUPES_ARTICLES,
    familleDe: familleDe, groupeDe: groupeDe,
    RUBRIQUES_RESULTAT: RUBRIQUES_RESULTAT, NATURE_CHARGE: NATURE_CHARGE,
    rubriqueDuCompte: rubriqueDuCompte, natureCharge: natureCharge,
    CATEGORIES_DEPENSE: CATEGORIES_DEPENSE, GED_CATEGORIES: GED_CATEGORIES,
    GROUPES_PRESTATION: GROUPES_PRESTATION, CATEGORIES_LIGNE: CATEGORIES_LIGNE,
    groupePrestation: groupePrestation, libelleCategorieLigne: libelleCategorieLigne,
    secteurPrestation: secteurPrestation,
    CALENDRIER_FISCAL: CALENDRIER_FISCAL, MONTANTS_FISCAUX: MONTANTS_FISCAUX,
    CAPACITES: CAPACITES, NATURES_PRESCRIPTION: NATURES_PRESCRIPTION,
    BAREME_REFERENCE: BAREME_REFERENCE, CATEGORIES_GARANTIE: CATEGORIES_GARANTIE, UNITES_PLAFOND: UNITES_PLAFOND,
  };
})(window);
