/* =============================================================================
 * SIGH-CBG — Magasin de données
 * -----------------------------------------------------------------------------
 * Persistance localStorage + CRUD complet.
 *  - RG-14 : suppression LOGIQUE uniquement (statut « archivé »), jamais physique.
 *  - RG-12 : toute création / modification / archivage / restauration est
 *            journalisée (utilisateur, date/heure, entité, ancienne → nouvelle).
 *  - Toute mutation retourne un jeton d'ANNULATION (undo) exploité par les toasts.
 * Les jeux de démonstration sont générés par un PRNG à graine fixe : les données
 * sont donc identiques d'une session à l'autre (tests reproductibles).
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core, D = global.SIGH.data, L = global.SIGH.labo;
  var KEY = 'sigh-cbg:v1';
  /* ==========================================================================
   * LA VERSION DU SCHÉMA — UNE SEULE FOIS, ICI
   * --------------------------------------------------------------------------
   * Elle est écrite par la semence ET vérifiée par load(). Les deux valeurs
   * ont longtemps été des littéraux distincts : incrémenter la semence sans
   * toucher au test faisait rejeter le magasin enregistré À CHAQUE
   * CHARGEMENT DE PAGE. Rien ne plantait — le prototype ré-amorçait, en
   * silence, et tout ce qu'on venait de saisir disparaissait à la navigation
   * suivante. Une constante partagée rend la dérive impossible.
   * ======================================================================== */
  var VERSION = 64;
  var db = null;
  var listeners = {};

  /* --- Stockage tolérant ---------------------------------------------------
   * Ouvert par double-clic (protocole file://), Chrome refuse l'accès à
   * localStorage selon la configuration. On bascule alors silencieusement sur
   * un stockage en mémoire : le prototype reste pleinement fonctionnel, seules
   * les données ne survivent pas au rechargement.
   * ---------------------------------------------------------------------- */
  var mem = {};
  var persistant = (function () {
    try {
      var t = '__sigh_test__';
      global.localStorage.setItem(t, '1');
      global.localStorage.removeItem(t);
      return true;
    } catch (e) { return false; }
  })();

  var storage = {
    disponible: persistant,
    get: function (k) {
      try { return persistant ? global.localStorage.getItem(k) : (mem[k] != null ? mem[k] : null); }
      catch (e) { return mem[k] != null ? mem[k] : null; }
    },
    set: function (k, v) {
      try { if (persistant) { global.localStorage.setItem(k, v); return true; } } catch (e) {
        /* QUOTA DÉPASSÉ. Le repli en mémoire garde la page fonctionnelle, mais
           les données seront PERDUES au changement d'écran. Se taire ferait
           chercher le défaut dans les écrans pendant des heures. */
        if (!storage.quotaSignale) {
          storage.quotaSignale = true;
          storage.quotaMessage = 'Le stockage local du navigateur est saturé ('
            + Math.round(String(v).length / 1024) + ' Ko à écrire). Les données restent en mémoire '
            + 'et seront perdues au changement d’écran. Réinitialiser le jeu de démonstration depuis '
            + '« Paramètres système » libère la place.';
          if (global.console && global.console.error) global.console.error('[SIGH] ' + storage.quotaMessage);
          /* Une écriture refusée s'ANNONCE : la console ne suffit pas, personne
             ne l'a ouverte au guichet. ui.js n'est pas encore chargé quand le
             magasin s'initialise — d'où la consultation paresseuse. */
          var Ui = global.SIGH && global.SIGH.ui;
          if (Ui && Ui.alerter) {
            try { Ui.alerter(storage.quotaMessage, { type: 'danger', duration: 0 }); } catch (e2) { /* visuel seul */ }
          }
        }
      }
      mem[k] = v; return false;
    },
    remove: function (k) {
      try { if (persistant) global.localStorage.removeItem(k); } catch (e) { /* sans effet */ }
      delete mem[k];
    },
  };

  /* --- Utilisateur courant (session) -------------------------------------- */
  function session() {
    try { return JSON.parse(storage.get('sigh-cbg:session')) || null; } catch (e) { return null; }
  }
  /* --------------------------------------------------------------------------
   * MÉTHODE DE VALORISATION DES SORTIES DE STOCK
   * --------------------------------------------------------------------------
   * Prix de vente ou CUMP — c'est un PARAMÈTRE, comme l'annotation manuscrite
   * le demandait. Il vit ici et non dans l'écran de configuration : une
   * bascule d'exploitation lue par le moteur de stock, les états de la
   * Direction et les points du gestionnaire ne peut pas dépendre d'un module
   * que ces pages ne chargent pas.
   * ----------------------------------------------------------------------- */
  var CLE_VALORISATION = 'sigh-cbg:valorisation-sortie';

  function valorisationSortie() {
    return storage.get(CLE_VALORISATION)
      || (global.SIGH.data && global.SIGH.data.PARAM_STOCK
        && global.SIGH.data.PARAM_STOCK.valorisationSortie) || 'prixVente';
  }
  function setValorisationSortie(id) {
    storage.set(CLE_VALORISATION, id);
    /* Le référentiel suit, pour que tout code qui le lit encore directement
       voie la même chose. Deux vérités sur une même bascule, c'est le défaut
       qu'on corrige ici. */
    if (global.SIGH.data && global.SIGH.data.PARAM_STOCK) {
      global.SIGH.data.PARAM_STOCK.valorisationSortie = id;
    }
  }
  /** Valeur unitaire d'un article selon la méthode en vigueur. */
  /**
   * La valeur unitaire d'une sortie, selon la méthode en vigueur.
   *
   * MÉTHODE « lot » : le lot sorti est valorisé à CE QU'IL A COÛTÉ. C'est la
   * plus exacte quand les lots sont suivis un à un — ce qu'impose déjà la
   * traçabilité des médicaments. Un lot sans prix propre retombe sur le CUMP,
   * et l'appelant peut le DIRE (`valeurUnitaireDetail`) : une valeur
   * approximative annoncée vaut mieux qu'une valeur fausse qu'on croit exacte.
   */
  function valeurUnitaire(produit, lot) {
    return valeurUnitaireDetail(produit, lot).valeur;
  }

  function valeurUnitaireDetail(produit, lot) {
    if (!produit) return { valeur: 0, methode: null, approx: false, motif: 'Article inconnu.' };
    var m = valorisationSortie();
    if (m === 'lot') {
      if (lot && lot.prixAchat) {
        return {
          valeur: Math.round(lot.prixAchat), methode: 'lot', approx: !!lot.prixEstime,
          motif: lot.prixEstime
            ? 'Prix du lot ' + (lot.numeroLot || '') + ' — valeur d’attente, à confirmer par la facture fournisseur.'
            : 'Prix réel du lot ' + (lot.numeroLot || '') + '.',
        };
      }
      return {
        valeur: Math.round(produit.cump || produit.prixAchat || 0), methode: 'cump', approx: true,
        motif: 'Ce lot ne porte pas de prix propre : valorisation au CUMP.',
      };
    }
    if (m === 'cump') {
      return { valeur: Math.round(produit.cump || produit.prixAchat || 0), methode: 'cump', approx: false,
        motif: 'Coût unitaire moyen pondéré.' };
    }
    return { valeur: Math.round(produit.prixVente || produit.prixAchat || 0), methode: 'prixVente', approx: false,
      motif: 'Prix de vente de l’article.' };
  }

  /**
   * UN ARTICLE SANS PRIX NE SORT PAS. Un prix d'achat jamais saisi vaut zéro,
   * et un article à zéro se dispense gratuitement sans que personne ne s'en
   * aperçoive. Mieux vaut refuser en nommant la fiche à compléter.
   */
  function prixManquant(produit) {
    if (!produit) return 'Article inconnu.';
    if (produit.prixAchat || produit.prixVente || produit.cump) return null;
    return 'Prix d’achat non renseigné pour « ' + (produit.designation || produit.id)
      + ' » — à compléter sur la fiche de l’article avant toute sortie de stock.';
  }

  /* ==========================================================================
   * L'HISTORIQUE DES PRIX — une TRACE, jamais une source
   * --------------------------------------------------------------------------
   * Le prix courant vit sur l'article ; l'historique dit d'où il vient. Il
   * s'écrit tout seul, à la modification, et ne se modifie plus ensuite : une
   * ligne d'historique qu'on peut retoucher ne prouve plus rien.
   *
   * ATTENTION À CE QU'IL N'EST PAS : il ne sert JAMAIS à valoriser une sortie
   * passée. Un mouvement porte SES valeurs, copiées au moment où il est
   * enregistré — sans quoi réimprimer un état de janvier après un changement
   * de prix en mars afficherait le prix de mars.
   * ======================================================================== */
  var CHAMPS_PRIX = [
    { champ: 'prixAchat', label: 'Prix d’achat' },
    { champ: 'prixVente', label: 'Prix de vente' },
    { champ: 'cump', label: 'CUMP' },
  ];

  function tracerPrix(rec, avant, patch) {
    if (!patch) return;
    var db2 = db;
    if (!db2) return;
    if (!db2.historiquePrix) db2.historiquePrix = [];
    CHAMPS_PRIX.forEach(function (c) {
      if (!Object.prototype.hasOwnProperty.call(patch, c.champ)) return;
      var ancien = avant[c.champ] == null ? null : Number(avant[c.champ]);
      var nouveau = rec[c.champ] == null ? null : Number(rec[c.champ]);
      if (ancien === nouveau) return;
      db2.historiquePrix.push({
        id: 'HPX' + C.pad(db2.historiquePrix.length + 1, 5), statut: 'actif',
        produitId: rec.id,
        /* Le LIBELLÉ est figé lui aussi : si l'article est renommé demain, la
           ligne d'historique doit rester lisible telle qu'elle a été écrite. */
        produit: rec.designation || avant.designation || rec.id,
        champ: c.champ, champLabel: c.label,
        ancien: ancien, nouveau: nouveau,
        ecartPct: (ancien && nouveau != null) ? Math.round(((nouveau - ancien) / ancien) * 1000) / 10 : null,
        motif: patch._motifPrix || null,
        sourceId: patch._sourcePrix || null,
        utilisateur: currentUser(),
        date: new Date().toISOString(),
      });
    });
  }

  /** L'historique d'un article, du plus récent au plus ancien. */
  function historiquePrix(produitId) {
    return ((db && db.historiquePrix) || []).filter(function (h) {
      return !produitId || h.produitId === produitId;
    }).slice().sort(function (a, b) { return String(b.date).localeCompare(String(a.date)); });
  }

  /* Les jeux enregistrés avant la fusion portent encore « Administration ».
     On les rattache au chargement plutôt que d'attendre une réinitialisation :
     un graphique faux pendant une semaine, c'est une semaine de décisions
     prises sur un effectif coupé en deux. */
  /* Les jeux enregistrés portent l'ancien code : sans reprise, le laboratoire
     resterait muet jusqu'à la prochaine réinitialisation. */
  function normaliserEtatsResultat(base) {
    if (!base || !base.demandesAnalyses) return;
    base.demandesAnalyses.forEach(function (d) {
      if (d.etatAnalyse === 'valide_bio' || d.etatAnalyse === 'rendu') d.etatAnalyse = 'valide';

      /* DEUX NOMS POUR LA MÊME DATE. L'écran de la salle de prélèvement range
         ses onglets sur `preleveLe` ; d'anciens jeux portent
         `prelevementLe`. Sans reprise, l'onglet « À transmettre » resterait
         vide alors que des échantillons sont prélevés. */
      if (!d.preleveLe && d.prelevementLe) d.preleveLe = d.prelevementLe;

      /* UN RÉSULTAT SAISI SUPPOSE UN ÉCHANTILLON PARVENU. Sans cette
         déduction, cent dix-huit demandes analysées resteraient éternellement
         « à transmettre ». */
      var avance = ['en_cours', 'saisi', 'valide_technique', 'valide', 'rectifie'];
      if (avance.indexOf(d.etatAnalyse) >= 0) {
        if (!d.preleveLe) d.preleveLe = d.saisiLe || d.dateHeure || null;
        if (!d.recuLaboLe) d.recuLaboLe = d.saisiLe || d.preleveLe || null;
      }
    });
  }

  function fusionnerServiceDirection(base) {
    if (!base) return;
    (base.personnel || []).forEach(function (a) {
      if (a.service === 'Administration') a.service = 'Direction';
    });
    /* Le centre de coût est amorcé en collection : il reste figé dans les jeux
       déjà enregistrés tant qu'on ne le reprend pas ici. Les imputations qui
       le désignaient suivent, sans quoi elles pointeraient vers un centre
       disparu. */
    if (base.centresCouts) {
      base.centresCouts = base.centresCouts.filter(function (c) { return c.id !== 'administration'; });
    }
    ['ecritures', 'depenses', 'budgets'].forEach(function (nom) {
      (base[nom] || []).forEach(function (e) {
        if (e.centreCout === 'administration') e.centreCout = 'direction';
      });
    });
  }

  function setSession(s) {
    if (s) storage.set('sigh-cbg:session', JSON.stringify(s));
    else storage.remove('sigh-cbg:session');
  }
  function currentUser() {
    var s = session();
    return (s && s.nom) || 'Utilisateur non identifié';
  }

  /* ==========================================================================
   * GÉNÉRATION DES JEUX DE DÉMONSTRATION
   * ======================================================================== */
  var PRENOMS_M = ['Abdoul', 'Ganiou', 'Florent', 'Rodrigue', 'Augustin', 'Hervé', 'Edmond', 'Nourou',
    'Séko', 'Yahouza', 'Idrissou', 'Boukari', 'Sabi', 'Orou', 'Moussa', 'Salifou', 'Tamou', 'Djibril',
    'Kassim', 'Bio', 'Yacoubou', 'Souleymane', 'Zakari', 'Alassane'];
  var PRENOMS_F = ['Alimatou', 'Aïssatou', 'Séraphine', 'Rabiatou', 'Zoukanéri', 'Fatouma', 'Adissa',
    'Bibata', 'Salamatou', 'Ramatou', 'Bertine', 'Colette', 'Justine', 'Hélène', 'Marguerite',
    'Chantal', 'Nadège', 'Sylvie', 'Rachida', 'Kadidjatou', 'Awaou', 'Foussena'];
  var NOMS = ['BASSONGUI', 'TAKI', 'KASSA', 'GBEDJI', 'YENI', 'AHOHOU', 'KINNOU', 'GARBA', 'TEPA',
    'DIEYABIDI', 'OURTCHA', 'ISSA', 'OROU YO', 'MAMAN', 'TCHANE', 'SANNI', 'DAOUDA', 'KORA',
    'N’TCHA', 'TIGRI', 'YARO', 'SAMBIENI', 'TCHOUKOUROU', 'BOUKARI', 'ADAM', 'SEIDOU', 'BAKO',
    'PARAISO', 'DOSSOU', 'HOUNKPATIN', 'AGOSSOU', 'ZIME', 'SOULE', 'WOROU', 'BANI'];
  var QUARTIERS = ['Tchirimina', 'Yimporima', 'Kantaborifa', 'Peporiyakou', 'Santa', 'Ourbouga',
    'Bérécingou', 'Perma', 'Kouandé', 'Boukoumbé', 'Toucountouna', 'Kotopounga'];
  var MOTIFS = ['Fièvre persistante', 'Céphalées', 'Douleurs abdominales', 'Suivi de grossesse',
    'Paludisme suspecté', 'Toux chronique', 'Hypertension artérielle', 'Contrôle post-opératoire',
    'Plaie infectée', 'Vomissements', 'Asthénie', 'Diarrhée aiguë', 'Consultation prénatale',
    'Traumatisme', 'Infection urinaire', 'Contrôle diabète'];
  var DIAGNOSTICS = ['Paludisme simple', 'Paludisme grave', 'Fièvre typhoïde', 'Gastro-entérite',
    'Infection respiratoire aiguë', 'HTA essentielle', 'Anémie ferriprive', 'Infection urinaire basse',
    'Grossesse évolutive', 'Diabète de type 2', 'Bronchite aiguë', 'Dermatose infectieuse'];

  /* Antécédents, allergies et actes de soins : référentiels cliniques tenus
     dans data.js, administrables par la clinique. */
  var ANTECEDENTS = D.ANTECEDENTS, ALLERGIES = D.ALLERGIES, ACTES_SOINS = D.ACTES_SOINS;

  var MEDICAMENTS = [
    ['Artéméther-Luméfantrine 20/120mg', 'Comprimé', 'medicament', 1200, 40],
    ['Artésunate injectable 60mg', 'Flacon', 'medicament', 2500, 20],
    ['Paracétamol 500mg', 'Comprimé', 'medicament', 25, 500],
    ['Paracétamol injectable 1g', 'Flacon', 'medicament', 850, 60],
    ['Amoxicilline 500mg', 'Gélule', 'medicament', 60, 400],
    ['Amoxicilline + Ac. clavulanique 1g', 'Comprimé', 'medicament', 350, 150],
    ['Ciprofloxacine 500mg', 'Comprimé', 'medicament', 120, 200],
    ['Ceftriaxone 1g injectable', 'Flacon', 'medicament', 1500, 80],
    ['Métronidazole 500mg', 'Comprimé', 'medicament', 45, 300],
    ['Ibuprofène 400mg', 'Comprimé', 'medicament', 35, 250],
    ['Diclofénac 75mg injectable', 'Ampoule', 'medicament', 200, 100],
    ['Oméprazole 20mg', 'Gélule', 'medicament', 90, 180],
    ['Sérum glucosé 5% 500ml', 'Poche', 'medicament', 750, 120],
    ['Sérum salé isotonique 0,9% 500ml', 'Poche', 'medicament', 700, 150],
    ['Ringer lactate 500ml', 'Poche', 'medicament', 800, 90],
    ['Fer + Acide folique', 'Comprimé', 'medicament', 30, 400],
    ['Ocytocine 5UI', 'Ampoule', 'medicament', 350, 80],
    ['Méthyldopa 250mg', 'Comprimé', 'medicament', 80, 150],
    ['Amlodipine 5mg', 'Comprimé', 'medicament', 55, 200],
    ['Metformine 850mg', 'Comprimé', 'medicament', 45, 250],
    ['Insuline rapide 100UI/ml', 'Flacon', 'medicament', 4500, 15],
    ['Dexaméthasone 4mg', 'Ampoule', 'medicament', 250, 100],
    ['Salbutamol spray', 'Flacon', 'medicament', 2200, 25],
    ['Vitamine C 500mg', 'Comprimé', 'medicament', 20, 300],
    ['Albendazole 400mg', 'Comprimé', 'medicament', 150, 200],
  ];
  var CONSOMMABLES = [
    ['Gants d’examen latex (boîte 100)', 'Boîte', 'conso_medical', 4500, 40],
    ['Gants stériles chirurgicaux', 'Paire', 'conso_medical', 350, 200],
    ['Seringue 5ml', 'Unité', 'conso_medical', 60, 800],
    ['Seringue 10ml', 'Unité', 'conso_medical', 80, 600],
    ['Cathéter IV G18', 'Unité', 'conso_medical', 250, 300],
    ['Cathéter IV G22', 'Unité', 'conso_medical', 250, 300],
    ['Compresses stériles', 'Sachet', 'conso_medical', 150, 400],
    ['Bande de gaze 10cm', 'Rouleau', 'conso_medical', 300, 200],
    ['Sparadrap', 'Rouleau', 'conso_medical', 500, 100],
    ['Alcool 70° 500ml', 'Flacon', 'conso_medical', 900, 60],
    ['Bétadine dermique 125ml', 'Flacon', 'conso_medical', 2200, 40],
    ['Fil de suture résorbable', 'Unité', 'conso_medical', 1200, 80],
    ['Sonde urinaire Foley', 'Unité', 'conso_medical', 850, 50],
    ['Perfuseur', 'Unité', 'conso_medical', 200, 400],
    ['Masque chirurgical (boîte 50)', 'Boîte', 'conso_medical', 2500, 30],
  ];
  var REACTIFS = [
    ['Réactif Glycémie (kit 100 tests)', 'Kit', 'reactif', 18000, 8],
    ['Réactif Créatinine (kit 100 tests)', 'Kit', 'reactif', 22000, 6],
    ['Réactif Transaminases ASAT/ALAT', 'Kit', 'reactif', 25000, 6],
    ['Réactif Cholestérol total', 'Kit', 'reactif', 20000, 5],
    ['Test rapide Paludisme (TDR)', 'Boîte 25', 'reactif', 12000, 15],
    ['Test rapide VIH 1/2', 'Boîte 25', 'reactif', 15000, 12],
    ['Test rapide Hépatite B (AgHBs)', 'Boîte 25', 'reactif', 14000, 10],
    ['Sérum test Anti-A / Anti-B / Anti-D', 'Coffret', 'reactif', 16000, 6],
    ['Réactif Widal', 'Kit', 'reactif', 19000, 5],
    ['Lames porte-objet (boîte 50)', 'Boîte', 'conso_labo', 3500, 20],
    ['Tubes EDTA 5ml', 'Unité', 'conso_labo', 90, 500],
    ['Tubes secs 5ml', 'Unité', 'conso_labo', 85, 500],
    ['Pipettes Pasteur', 'Unité', 'conso_labo', 45, 400],
    ['Bandelettes urinaires (boîte 100)', 'Boîte', 'conso_labo', 8500, 12],
    ['Huile à immersion', 'Flacon', 'conso_labo', 4200, 8],
  ];
  var DIVERS = [
    ['Ramette papier A4', 'Ramette', 'fourniture', 3500, 30],
    ['Registre grand format', 'Unité', 'fourniture', 2500, 20],
    ['Cartouche encre imprimante', 'Unité', 'fourniture', 18000, 6],
    ['Eau de javel 1L', 'Bidon', 'entretien', 800, 40],
    ['Savon liquide antiseptique 5L', 'Bidon', 'entretien', 6500, 12],
    ['Balai et raclette', 'Unité', 'entretien', 2000, 10],
    ['Tensiomètre électronique', 'Unité', 'petit_materiel', 35000, 4],
    ['Thermomètre infrarouge', 'Unité', 'petit_materiel', 18000, 6],
    ['Stéthoscope', 'Unité', 'petit_materiel', 22000, 5],
    ['Oxymètre de pouls', 'Unité', 'petit_materiel', 15000, 6],
  ];

  /* ==========================================================================
   * JEUX DE DROITS DES RÔLES CRÉÉS
   * --------------------------------------------------------------------------
   * Un rôle créé part de zéro : la surcharge FERME chaque module nommément,
   * puis en rouvre quelques-uns. Sans cette fermeture explicite, les modules
   * portant `roles: '*'` au manifeste — M1 et RAP — resteraient ouverts à un
   * rôle qu'on vient d'inventer.
   * ======================================================================== */
  var MODULES_TOUS = ["DASH","M1","M2","M3","M4","M5","M6","M7","M8","M9","MECEF","M10","M11","M12","M13","GED","RAP","M14","CFG"];

  /* ==========================================================================
   * LE MODULE DES TABLEAUX DE BORD NE SE DÉCLARE JAMAIS AU NIVEAU DU MODULE.
   * --------------------------------------------------------------------------
   * DASH porte `roles: ALL` au manifeste et ce sont les listes de CHAQUE écran
   * qui filtrent. Les deux façons de le déclarer sont donc fautives, et de
   * manière symétrique :
   *
   *   `DASH: VOIR`  → une surcharge ACCORDE : le rôle récupère les VINGT
   *                   tableaux de bord d'un coup. Mesuré sur les quatre rôles
   *                   créés : l'aide-soignante lisait les tableaux de la
   *                   comptabilité et des ressources humaines, et le
   *                   technicien d'échographie ceux de la caisse et de la
   *                   comptabilité — alors que « aucun accès financier » est
   *                   la condition même que la Direction a posée pour ce
   *                   poste.
   *   `DASH: fermé` → le rôle perdrait AUSSI son propre tableau, donc sa page
   *                   d'accueil.
   *
   * On ne le déclare donc pas : le manifeste décide, écran par écran, et
   * chaque rôle voit exactement le sien.
   *
   * La création d'un rôle en cours d'exploitation est un autre cas : là, tout
   * est fermé DASH compris, parce qu'un rôle inventé n'a pas de tableau à lui.
   * ======================================================================== */
  function fermerTout(ouverts) {
    var out = {};
    MODULES_TOUS.forEach(function (m) {
      if (m === 'DASH') return;
      out[m] = ouverts[m] || { voir: false, editer: false, annuler: false };
    });
    return out;
  }
  var VOIR = { voir: true, editer: false, annuler: false };
  var EDITER = { voir: true, editer: true, annuler: false };
  var TOUT = { voir: true, editer: true, annuler: true };

  /* L'aide-soignante participe aux soins : elle voit le patient et
     l'hospitalisation, elle ne voit AUCUN résultat d'analyse — c'est la règle
     métier posée par la Direction pour cette fonction. */
  var droitsAideSoignant = fermerTout({
    M1: VOIR, M2: VOIR, M3: EDITER, M4: VOIR,
  });

  /* Le technicien d'échographie : dossier en LECTURE, imagerie en CRÉATION,
     AUCUN accès financier — ni caisse, ni assurances, ni comptabilité. C'est
     la condition posée par la Direction, et elle est structurante : un
     manipulateur qui verrait la caisse pourrait faire dépendre l'examen du
     paiement, ce qui n'est pas son rôle. */
  /* M2 EN LECTURE, et l'imagerie seule en écriture par surcharge d'écran.
     « M2: EDITER » lui ouvrait aussi les ordonnances, la salle de soins et la
     file d'attente : un technicien d'échographie qui rédige une ordonnance,
     ce n'est pas une habilitation trop large, c'est un exercice illégal. */
  var droitsEchographiste = fermerTout({
    M1: VOIR, M2: VOIR, M5: VOIR, RAP: VOIR,
  });

  /* Le surveillant : agendas, retards, présences, absences, planning et
     gardes. Ce sont exactement les missions 1 et 5 de la description de poste
     de l'Infirmier Général. Aucun accès financier ni comptable. */
  var droitsSurveillant = fermerTout({
    M1: VOIR, M2: VOIR, M3: VOIR, M4: VOIR, M10: EDITER, RAP: VOIR,
  });

  /* L'ingénieur biomédical entretient les automates et le parc technique. Il
     VOIT le laboratoire pour connaître les analyses en cours sur les appareils
     dont il a la charge, mais ne rend AUCUN résultat : la validation biologique
     engage la responsabilité du biologiste, pas celle du technicien qui a
     étalonné la machine. Il tient la maintenance (M13) et voit le stock des
     réactifs et consommables. */
  var droitsBiomedical = fermerTout({
    M5: VOIR, M6: VOIR, M7: VOIR, M13: EDITER, RAP: VOIR,
  });

  /* L'assistant comptable, d'après ses 30 activités : livres de compte,
     rapprochements, recouvrement des créances chez les particuliers ET les
     compagnies, obligations fiscales, point journalier de la caisse,
     inventaire des médicaments d'urgence et des réactifs de laboratoire. */
  var droitsAssistantComptable = fermerTout({
    M8: VOIR, M9: EDITER, MECEF: VOIR, M12: TOUT,
    M11: VOIR, M6: VOIR, M5: VOIR, M7: VOIR, RAP: VOIR,
  });

  /* ==========================================================================
   * LES TROIS RÔLES DE LA PHASE 2 — arbitrage et cible du 31/08/2026
   * --------------------------------------------------------------------------
   * Le CHIRURGIEN : même base que le médecin, PLUS le bloc, MOINS la
   * maternité — la matrice cible ferme M4 nommément pour ce profil. D interdit
   * partout (pas d'annulation) : un compte rendu opératoire ne se retire pas.
   *
   * L'ANESTHÉSISTE : le péri-opératoire — patients en lecture, hospitalisation
   * et bloc en écriture, résultats de laboratoire en lecture. Ni maternité, ni
   * consultations générales : il n'ouvre pas de dossier de médecine, il
   * sécurise une intervention. Ses écrans propres (CPA, feuille d'anesthésie)
   * arrivent en phase 6 et hériteront de M3.
   *
   * L'ASSISTANT COMPTABLE (16ᵉ rôle, créé par arbitrage — distinct de
   * l'Assistant de Direction) : saisie financière SANS pouvoir d'annulation —
   * dépenses, écritures, réceptions fournisseurs — et AUCUN accès clinique.
   * La clôture annuelle lui est fermée nommément : elle engage l'exercice, et
   * la cible la réserve au Comptable principal et à la DAF.
   * ======================================================================== */
  var droitsChirurgien = fermerTout({
    M1: EDITER, M2: EDITER, M3: EDITER, M5: VOIR, RAP: VOIR,
  });
  var droitsAnesthesiste = fermerTout({
    M1: VOIR, M3: EDITER, M5: VOIR, RAP: VOIR,
  });
  var droitsAideComptable = fermerTout({
    M7: EDITER, M8: VOIR, M9: EDITER, MECEF: VOIR, M12: EDITER, RAP: VOIR,
  });

  function genPersonnel(rnd) {
    var out = [], mat = 1;
    function add(nom, fonctionId, service, salaire, sexe, poste) {
      var parts = nom ? nom.split('|') : null;
      var nomF = parts ? parts[0] : C.pick(rnd, NOMS);
      var prenom = parts ? parts[1] : (sexe === 'F' ? C.pick(rnd, PRENOMS_F) : C.pick(rnd, PRENOMS_M));
      var ech = 'E' + C.between(rnd, 1, 5) + '-' + C.between(rnd, 1, 3);
      var embauche = new Date(2016 + C.between(rnd, 0, 9), C.between(rnd, 0, 11), C.between(rnd, 1, 28));
      out.push({
        id: 'EMP' + C.pad(mat), matricule: String(mat++),
        nom: nomF, prenom: prenom, nomComplet: nomF + ' ' + prenom,
        sexe: sexe, fonction: fonctionId, poste: poste || '', service: service,
        categorie: ech, salaireBase: salaire,
        dateEmbauche: C.iso(embauche),
        cnss: '2' + C.between(rnd, 100000, 999999) + C.between(rnd, 10, 99),
        telephone: '0' + C.between(rnd, 1, 9) + C.between(rnd, 10000000, 99999999),
        situation: C.pick(rnd, ['Célibataire', 'Marié(e)', 'Marié(e)', 'Veuf(ve)']),
        /* IDENTIFICATION FISCALE — AUCUN IFU N'EST INVENTÉ. Les huit agents
           sont sous contrat de travail : leur rémunération supporte l'ITS et
           non l'AIB, d'où le régime `salaire`. Si la Direction rémunère l'un
           d'eux À L'ACTE, elle bascule son régime sur `honoraires` et renseigne
           son IFU : le bulletin porte alors la retenue d'AIB. */
        ifu: null, ifuStatut: 'inconnu', ifuVerifieLe: null, ifuVerifiePar: null,
        regimeRemuneration: 'salaire',
        statut: 'actif',
      });
    }
    /* ======================================================================
     * LE PERSONNEL BAGUIDI — les HUIT agents d'Instructions.txt, EXACTEMENT
     * (décision écrite de la Direction du 02/09/2026). Aucun autre agent ne
     * s'invente : l'effectif réel complet n'a pas été fourni.
     *
     * Les SALAIRES sont des VALEURS D'ATTENTE de démonstration (aucune grille
     * salariale BAGUIDI n'a été fournie) — marqués `salaireProvisoire`, à
     * remplacer par la Direction. Sexe, situation, CNSS, téléphone et date
     * d'embauche sont du jeu de démonstration, à compléter sur les fiches.
     * ==================================================================== */
    function marquer() {
      var a = out[out.length - 1];
      a.salaireProvisoire = true;
      a.motifSalaire = 'Valeur d’attente de démonstration — grille salariale BAGUIDI à fournir par la Direction.';
      a.aValider = true;
    }
    /* L'ORDRE est celui d'Instructions.txt : le matricule N correspond au
       compte m-00N@baguidi-clinique.bj. */
    add('GBAGUIDI|Rafiou', 'direction', 'Direction', 400000, 'M', 'Directeur Général'); marquer();
    add('SANOUSSI|Adamon', 'comptable', 'Comptabilité', 180000, 'M', 'Comptable'); marquer();
    add('MABOUDOU|Nawal', 'rh', 'Ressources humaines', 150000, 'F', 'Responsable RH'); marquer();
    add('IDOHOU|Abraham', 'medecin', 'Médecine générale', 280000, 'M', 'Médecin'); marquer();
    add('AKONDE|Octave', 'infirmier', 'Soins infirmiers', 95000, 'M', 'Infirmier'); marquer();
    add('SOKOU|Peace', 'direction', 'Direction', 300000, 'F', 'Direction'); marquer();
    add('ZIME|Nadège', 'comptable', 'Comptabilité', 175000, 'F', 'Comptable'); marquer();
    add('TOUNGOUH|A. Zoulkifouli', 'rh', 'Ressources humaines', 145000, 'M', 'Responsable RH'); marquer();
    return out;
  }

  /* ==========================================================================
   * LES COMPTES QUI OUVRENT UNE SESSION
   * --------------------------------------------------------------------------
   * Les HUIT comptes d'Instructions.txt (Direction, 02/09/2026) — exactement,
   * aucun autre ne s'invente — plus le compte d'administration système, dont
   * le poste EST l'accès complet. L'identifiant est l'adresse
   * m-00N@baguidi-clinique.bj de la liste, où N est le matricule de l'agent.
   *
   * AMORÇAGE AU SOCLE, et non par l'écran M14 : la barre supérieure nomme le
   * titulaire de chaque profil sur TOUTES les pages, donc plus d'un écran lit
   * cette collection. Amorcée par son écran, elle restait vide partout
   * ailleurs — le piège documenté du prototype.
   * ======================================================================== */
  function genUtilisateurs(rnd, personnel) {
    var mapping = {
      'GBAGUIDI Rafiou': 'direction',
      'SANOUSSI Adamon': 'comptable',
      'MABOUDOU Nawal': 'rh',
      'IDOHOU Abraham': 'medecin',
      'AKONDE Octave': 'infirmier',
      'SOKOU Peace': 'direction',
      'ZIME Nadège': 'comptable',
      'TOUNGOUH A. Zoulkifouli': 'rh',
    };
    var out = [{
      id: 'USR000', statut: 'actif', identifiant: 'admin@baguidi-clinique.bj',
      nomComplet: 'Administrateur système', role: 'admin', service: 'Administration',
      poste: 'Administrateur système', actif: true, mfa: true,
      dernierAcces: C.iso(new Date(2026, 7, 16)), echecs: 0, creeLe: '2026-09-02',
    }];
    personnel.forEach(function (e, i) {
      var role = mapping[e.nomComplet]
        || ({ medecin: 'medecin', infirmier: 'infirmier', rh: 'rh',
          comptable: 'comptable', direction: 'direction' }[e.fonction]) || 'direction';
      out.push({
        id: 'USR' + C.pad(i + 1, 3), statut: 'actif',
        identifiant: 'm-' + C.pad(e.matricule, 3) + '@baguidi-clinique.bj',
        nomComplet: e.nomComplet, employeId: e.id, matricule: e.matricule,
        role: role, service: e.service, poste: e.poste,
        actif: true,
        mfa: ['direction', 'admin'].indexOf(role) !== -1,
        dernierAcces: C.iso(C.addDays(new Date(2026, 7, 16), -C.between(rnd, 0, 45))),
        echecs: C.between(rnd, 0, 2),
        creeLe: e.dateEmbauche,
      });
    });
    return out;
  }

  function genPatients(rnd, n) {
    var out = [];
    for (var i = 1; i <= n; i++) {
      var sexe = rnd() > 0.45 ? 'F' : 'M';
      var annee = rnd() > 0.25 ? 26 : 25;
      var anneeComplete = 2000 + Number(String(annee).slice(-2));
      var age = C.between(rnd, 1, 82);
      var naiss = new Date(2026 - age, C.between(rnd, 0, 11), C.between(rnd, 1, 28));
      var assure = rnd() > 0.62;
      var comp = assure ? C.pick(rnd, D.ASSUREURS) : null;
      out.push({
        id: 'PAT' + C.pad(i, 4),
        /* Le format est porté par C.codePatient() et NULLE PART AILLEURS.
           Le reconstruire ici en faisait une seconde règle, qui a divergé dès
           que la Direction a demandé « <sigle>/[n° d'ordre]/[année] ». */
        code: C.codePatient(i, anneeComplete),
        nom: C.pick(rnd, NOMS),
        prenom: sexe === 'F' ? C.pick(rnd, PRENOMS_F) : C.pick(rnd, PRENOMS_M),
        sexe: sexe,
        dateNaissance: C.iso(naiss),
        age: age,
        telephone: '0' + C.between(rnd, 1, 9) + C.between(rnd, 10000000, 99999999),
        quartier: C.pick(rnd, QUARTIERS),
        adresse: C.pick(rnd, QUARTIERS) + ', Parakou',
        personneAPrevenir: C.pick(rnd, NOMS) + ' ' + C.pick(rnd, PRENOMS_M),
        groupeSanguin: C.pick(rnd, D.GROUPES_SANGUINS),
        assureur: comp ? comp.code : null,
        assureurNom: comp ? comp.nom : null,
        numeroPolice: comp ? comp.code + '-' + C.between(rnd, 100000, 999999) : null,
        /* Rattachement au souscripteur : c'est le contrat de l'employeur, pas la
           compagnie, qui porte la grille de garanties (relevés par souscripteur). */
        souscripteurId: null,
        categorieAssurance: comp ? C.pick(rnd, ['particulier', 'personnel', 'entreprise', 'entreprise']) : null,
        /* Conservé pour l'historique des factures déjà émises ; la répartition
           se calcule désormais garantie par garantie. */
        tauxPriseEnCharge: comp ? C.pick(rnd, [70, 80, 80, 90, 100]) : 0,
        carteExpiration: comp ? C.iso(new Date(2026, C.between(rnd, 0, 11), C.between(rnd, 1, 28))) : null,
        dateCreation: C.iso(new Date(2000 + annee, C.between(rnd, 0, 7), C.between(rnd, 1, 28))),
        antecedents: C.pick(rnd, ANTECEDENTS),
        antecedentsAutres: rnd() > 0.8 ? C.pick(rnd, ANTECEDENTS) : '',
        allergies: C.pick(rnd, ALLERGIES),
        traitementEnCours: rnd() > 0.7 ? C.pick(rnd, ['Antihypertenseur', 'Antidiabétique oral', 'Antirétroviral', 'Insuline']) : '',
        statut: 'actif',
      });
    }
    return out;
  }

  /* --------------------------------------------------------------------------
   * Le référentiel produits est issu de la REPRISE de l'inventaire « Grand
   * Stock » SAGE 100 arrêté au 15/07/2026 : références, désignations,
   * quantités et coûts unitaires moyens pondérés sont ceux du document.
   * Seuls la ventilation gros/détail, l'emplacement et le seuil d'alerte sont
   * proposés par le système et restent à valider par la clinique.
   * ----------------------------------------------------------------------- */
  function genProduits(rnd) {
    var SG = global.SIGH.sage;
    /* La médiane des coûts unitaires VALORISÉS de chaque catégorie — le
       « montant juste » de l'arbitrage : plausible, dérivé du document, et
       recalculé si l'inventaire change. Une catégorie sans aucun coût
       valorisé retombe sur la médiane générale. */
    var parCategorie = {};
    SG.INVENTAIRE_SAGE.forEach(function (a) {
      var v = Math.round(a.cump);
      if (v > 0) (parCategorie[a.categorie] = parCategorie[a.categorie] || []).push(v);
    });
    var toutes = [];
    Object.keys(parCategorie).forEach(function (k) {
      parCategorie[k].sort(function (x, y) { return x - y; });
      toutes = toutes.concat(parCategorie[k]);
    });
    toutes.sort(function (x, y) { return x - y; });
    function medianeCategorie(cat) {
      var vals = parCategorie[cat] && parCategorie[cat].length ? parCategorie[cat] : toutes;
      return vals.length ? vals[Math.floor(vals.length / 2)] : 500;
    }
    return SG.INVENTAIRE_SAGE.map(function (a, i) {
      /* Le magasin central conserve l'essentiel ; la pharmacie de détail est
         approvisionnée par transferts successifs. */
      var qDetail = Math.min(a.quantite, Math.round(a.quantite * (0.15 + rnd() * 0.25)));
      var qGros = a.quantite - qDetail;
      /* Le CMUP exact sert à la valorisation (quantité × cump = P.R. global du
         document) ; la facturation, elle, s'exprime en francs entiers. */
      var prix = Math.round(a.cump);
      /* ARBITRAGE DU 01/09/2026 — plus aucun article à montant NUL : une
         référence non valorisée par SAGE reçoit une VALEUR D'ATTENTE, la
         MÉDIANE de sa catégorie (calculée, jamais écrite en dur — le jour où
         l'inventaire change, la médiane suit). Marquée provisoire, tracée
         dans `valorisationsSage` : la surcouche, jamais la réécriture du
         document — INVENTAIRE_SAGE reste ce qu'il est. */
      var provisoire = !(prix > 0);
      if (provisoire) prix = medianeCategorie(a.categorie);
      return Object.assign(provisoire ? {
        valorisationProvisoire: true,
        sourceValorisation: 'Décision de la Direction du 01/09/2026 — médiane de la catégorie, à confirmer',
      } : {}, {
        id: 'PRD' + C.pad(i + 1, 4),
        code: a.code,
        designation: a.designation,
        unite: SG.uniteDe(a.designation),
        categorie: a.categorie,
        prixAchat: prix,
        /* RG-02 : les médicaments sont facturés au prix d'achat, sans marge. */
        prixVente: prix,
        cump: provisoire ? prix : a.cump,
        /* Seuils proposés (20 % du stock repris, plancher 5), CONFIRMÉS par
           la clinique le 01/09/2026 (vague 51) — révisables référence par
           référence à l'écran des réactifs et du stock. */
        seuilAlerte: SG.seuilPropose(a.quantite),
        seuilConfirmeLe: '2026-09-01',
        stockGros: qGros, stockDetail: qDetail,
        stock: a.quantite,
        emplacement: 'Rayon ' + String.fromCharCode(65 + (i % 6)) + ' — Casier ' + ((i % 8) + 1),
        fournisseur: C.pick(rnd, D.FOURNISSEURS).code,
        /* Traçabilité de la reprise (draf1 §10). */
        source: SG.LOT_IMPORT.source,
        lotImport: SG.LOT_IMPORT.reference,
        dateImport: SG.LOT_IMPORT.dateArrete,
        quantiteImportee: a.quantite,
        valoriseSage: a.valorise,
        seuilAValider: false,
        statut: 'actif',
      });
    });
  }

  function genLots(rnd, produits) {
    var out = [], today = new Date(2026, 7, 16);
    produits.forEach(function (p, i) {
      if (p.categorie === 'fourniture' || p.categorie === 'petit_materiel' || p.categorie === 'immobilisation') return;
      var nb = C.between(rnd, 1, 3);
      for (var k = 0; k < nb; k++) {
        var jours = C.between(rnd, -40, 640);
        out.push({
          id: 'LOT' + C.pad(out.length + 1, 4),
          produitId: p.id, produit: p.designation,
          numeroLot: 'L' + (2025 + (k % 2)) + '-' + C.pad(C.between(rnd, 1, 999), 3),
          /* LE PRIX DU LOT est ce qui permet de valoriser une sortie à ce que
             la boîte a réellement coûté. Aucun document ne donne le prix
             d'entrée lot par lot : celui-ci part du prix d'achat courant de
             l'article et se DIT estimé — il tombera à la première réception
             saisie, qui, elle, connaît son prix. */
          prixAchat: p.prixAchat || null,
          prixEstime: true,
          datePeremption: C.iso(C.addDays(today, jours)),
          quantiteRestante: C.between(rnd, 0, Math.max(1, Math.round(p.stock / nb))),
          emplacement: p.emplacement,
          statut: jours < 0 ? 'perime' : (jours < 90 ? 'alerte' : 'actif'),
        });
      }
    });
    return out;
  }

  function genConsultations(rnd, patients, personnel) {
    var medecins = personnel.filter(function (e) { return e.fonction === 'medecin'; });
    var out = [], today = new Date(2026, 7, 16);
    for (var i = 0; i < 260; i++) {
      var p = C.pick(rnd, patients), m = C.pick(rnd, medecins);
      var d = C.addDays(today, -C.between(rnd, 0, 120));
      d.setHours(C.between(rnd, 8, 18), C.pick(rnd, [0, 15, 30, 45]));
      out.push({
        id: 'CONS' + C.pad(i + 1, 4),
        reference: 'C' + C.pad(i + 1, 5),
        patientId: p.id, patient: p.nom + ' ' + p.prenom, patientCode: p.code,
        medecinId: m.id, medecin: m.nomComplet,
        date: d.toISOString(),
        motif: C.pick(rnd, MOTIFS),
        diagnostic: C.pick(rnd, DIAGNOSTICS),
        type: C.pick(rnd, ['Consultation', 'Consultation', 'Consultation', 'Contrôle', 'Urgence', 'Domicile']),
        tarif: C.pick(rnd, [3000, 3000, 5000, 5000, 10000]),
        statut: C.pick(rnd, ['terminee', 'terminee', 'terminee', 'en_cours', 'planifiee']),
      });
    }
    return C.sortBy(out, 'date', 'desc');
  }

  function genAdmissions(rnd, patients, personnel) {
    var lits = [];
    D.CHAMBRES.forEach(function (ch) { ch.lits.forEach(function (l) { lits.push({ chambre: ch, lit: l }); }); });
    var infirmiers = personnel.filter(function (e) { return e.fonction === 'infirmier' || e.fonction === 'sage_femme'; });
    var out = [], today = new Date(2026, 7, 16), occupes = {};
    for (var i = 0; i < 90; i++) {
      var p = C.pick(rnd, patients), inf = C.pick(rnd, infirmiers);
      var entree = C.addDays(today, -C.between(rnd, 0, 150));
      var duree = C.between(rnd, 1, 12);
      var enCours = i < 14;
      var slot = lits[i % lits.length];
      if (enCours && occupes[slot.lit.code]) enCours = false;
      if (enCours) occupes[slot.lit.code] = true;
      out.push({
        id: 'ADM' + C.pad(i + 1, 4),
        reference: 'H' + C.pad(i + 1, 5),
        patientId: p.id, patient: p.nom + ' ' + p.prenom, patientCode: p.code,
        chambre: slot.chambre.code, lit: slot.lit.label, typeChambre: slot.chambre.type,
        dateEntree: enCours ? C.iso(C.addDays(today, -C.between(rnd, 0, 9))) : C.iso(entree),
        dateSortie: enCours ? null : C.iso(C.addDays(entree, duree)),
        diagnosticEntree: C.pick(rnd, DIAGNOSTICS),
        symptomes: C.pick(rnd, MOTIFS),
        priseEnCharge: rnd() > 0.3 ? 'plus_8h' : 'moins_8h',
        infirmierId: inf.id, infirmier: inf.nomComplet,
        statut: enCours ? 'en_cours' : 'sortie',
      });
    }
    return out;
  }

  /* ==========================================================================
   * FACTURES — ENGENDRÉES À PARTIR DE LEURS LIGNES
   * --------------------------------------------------------------------------
   * Le montant est la SOMME des lignes, jamais un nombre tiré à part : une
   * facture dont le total ne correspond pas à son détail est un piège, et c'est
   * exactement ce que produisait la version précédente. Le reçu n'avait alors
   * rien à détailler, et un règlement partiel n'avait aucune ligne à
   * sélectionner — d'où le défaut signalé par la Direction le 25/08/2026.
   *
   * Chaque ligne porte son statut de paiement propre. C'est lui qui permet à la
   * caisse de dire « ces trois examens-là sont réglés, ces deux-là ne le sont
   * pas » — et au laboratoire de ne recevoir que les premiers.
   * ======================================================================== */
  /* ==========================================================================
   * ÉCHÉANCES FISCALES
   * --------------------------------------------------------------------------
   * Chaque obligation mensuelle donne douze échéances, chaque obligation
   * annuelle en donne une. Une échéance tombant un samedi ou un dimanche est
   * REPORTÉE au jour ouvrable suivant, jamais avancée — l'administration
   * n'ouvre pas le week-end, et anticiper ferait payer avant d'y être tenu.
   * ======================================================================== */
  function genEcheances() {
    var AUJ2 = new Date(2026, 7, 16);
    function jourOuvrableSuivant(d) {
      var x = new Date(d.getTime());
      while (x.getDay() === 0 || x.getDay() === 6) x = C.addDays(x, 1);
      return x;
    }
    var annee = AUJ2.getFullYear();
    var out = [], n = 0;
    (D.CALENDRIER_FISCAL || []).forEach(function (o) {
      var dates = [];
      if (o.periodicite === 'mensuelle') {
        for (var m = 0; m < 12; m++) dates.push(new Date(annee, m, o.jour));
      } else {
        dates.push(new Date(annee, o.mois, Math.min(o.jour, 28)));
      }
      dates.forEach(function (d) {
        n++;
        var echue = jourOuvrableSuivant(d);
        var passee = echue < AUJ2;
        out.push({
          id: 'ECH' + C.pad(n, 4), statut: 'actif',
          code: o.code, libelle: o.libelle, famille: o.famille,
          periodicite: o.periodicite, part: o.part, declaration: o.declaration, note: o.note,
          exercice: annee,
          periode: o.periodicite === 'mensuelle'
            ? C.MOIS[Math.max(0, d.getMonth() - 1)] + ' ' + annee : String(annee),
          echeance: C.iso(echue),
          reportee: C.iso(echue) !== C.iso(d),
          /* Les échéances passées sont réputées honorées, SAUF les plus
             récentes — sans quoi l'écran de suivi et le tableau de bord du
             comptable n'auraient jamais rien à montrer. */
          paye: passee && C.daysBetween(echue, AUJ2) > 25,
          datePaiement: null, montant: null, reference: null, valideePar: null,
        });
      });
    });
    out.forEach(function (e) {
      if (e.paye) {
        e.datePaiement = e.echeance;
        e.valideePar = 'SANOUSSI Adamon';
        e.reference = 'QUIT-' + e.code + '-' + e.exercice;
      }
    });
    return out;
  }

  /* Une remise se JUSTIFIE. Un rabais sans motif au dossier est exactement ce
     qu'un contrôle interne cherche : la colonne « motif » n'est pas
     décorative. */
  var MOTIFS_REMISE = [
    { code: 'famille_agent', label: 'Famille d’un agent', taux: 50 },
    { code: 'indigent', label: 'Cas social — décision de la Direction', taux: 100 },
    { code: 'fidelite', label: 'Client de longue date', taux: 10 },
    { code: 'geste', label: 'Geste commercial — Direction', taux: 20 },
    { code: 'convention', label: 'Convention d’établissement', taux: 15 },
  ];

  function genFactures(rnd, patients, consultations, produits) {
    var out = [], today = new Date(2026, 7, 16);

    /* Le catalogue réel sert de source : facturer des libellés inventés
       rendrait les statistiques par prestation inexploitables. */
    var analyses = (D.ANALYSES || []).filter(function (a) { return a.prix; });
    var actes = (D.ACTES || []).filter(function (a) { return a.prix; });
    var meds = (produits || []).filter(function (x) { return x.prixAchat > 0; });

    /* Les natures de facture et ce qu'elles portent. */
    var NATURES = [
      { type: 'Consultation', lignes: function () {
        var a = C.pick(rnd, actes.filter(function (x) { return /consultation/i.test(x.libelle); }) );
        return a ? [{ categorie: 'consultation', designation: a.libelle, quantite: 1, prixUnitaire: a.prix }] : [];
      } },
      { type: 'Laboratoire', lignes: function () {
        var n = C.between(rnd, 1, 5), l = [];
        for (var k = 0; k < n; k++) {
          var a = C.pick(rnd, analyses);
          if (a && !l.some(function (x) { return x.designation === a.designation; })) {
            l.push({ categorie: 'analyse', designation: a.designation, quantite: 1, prixUnitaire: a.prix });
          }
        }
        return l;
      } },
      { type: 'Pharmacie', lignes: function () {
        var n = C.between(rnd, 1, 4), l = [];
        for (var k = 0; k < n; k++) {
          var m2 = C.pick(rnd, meds);
          if (m2 && !l.some(function (x) { return x.designation === m2.designation; })) {
            /* RG-02 — le médicament se facture au prix d'achat, sans marge. */
            l.push({ categorie: 'medicament', designation: m2.designation,
              quantite: C.between(rnd, 1, 3), prixUnitaire: m2.prixAchat, produitId: m2.id });
          }
        }
        return l;
      } },
      { type: 'Soins', lignes: function () {
        var n = C.between(rnd, 1, 3), l = [];
        for (var k = 0; k < n; k++) {
          var a = C.pick(rnd, actes);
          if (a && !l.some(function (x) { return x.designation === a.libelle; })) {
            l.push({ categorie: 'acte', designation: a.libelle, quantite: 1,
              prixUnitaire: a.prix, acteCode: a.code });
          }
        }
        return l;
      } },
      { type: 'Hospitalisation', lignes: function () {
        var jours = C.between(rnd, 1, 7);
        var l = [{ categorie: 'hospitalisation', designation: 'Journée d’hospitalisation',
          quantite: jours, prixUnitaire: 5000 }];
        var a = C.pick(rnd, actes);
        if (a) l.push({ categorie: 'acte', designation: a.libelle, quantite: 1, prixUnitaire: a.prix, acteCode: a.code });
        return l;
      } },
    ];

    /* Densité réduite le 26/08/2026 : c'est l'ÉTENDUE de neuf mois qui porte
       les statistiques, pas le nombre de lignes. À 320 pièces le magasin
       frôlait le quota du navigateur, et une écriture de plus aurait été
       silencieusement perdue. */
    for (var i = 0; i < 230; i++) {
      var pat = C.pick(rnd, patients);
      var d = C.addDays(today, -C.between(rnd, 0, 150));
      var nature = C.pick(rnd, NATURES);
      var brutes = nature.lignes();
      /* Une nature qui ne produit rien ne fabrique pas de facture vide : mieux
         vaut 315 factures justes que 320 dont cinq sont creuses. */
      if (!brutes.length) continue;

      var taux = pat.assureur ? (pat.tauxPriseEnCharge || 0) : 0;

      /* L'AGENT DE LA CLINIQUE est pris en charge à 100 % par l'établissement.
         Ce n'est PAS une assurance : aucun tiers ne rembourse, aucune créance
         ne naît. La part correspondante a donc son propre compartiment. */
      var estAgent = !!pat.personnelId;

      /* Une pièce sur huit porte une remise, avec son motif. Jamais sur un
         agent — il est déjà pris en charge en totalité, et cumuler les deux
         n'aurait aucun sens. */
      var remise = (!estAgent && rnd() > 0.87) ? C.pick(rnd, MOTIFS_REMISE) : null;

      var lignes = brutes.map(function (l, k) {
        var brut = l.quantite * l.prixUnitaire;

        /* RG-02 — le médicament se facture au prix d'achat, sans marge : une
           remise le vendrait à perte. Les remises ne portent donc que sur les
           prestations. */
        var remisable = remise && l.categorie !== 'medicament';
        var montantRemise = remisable ? Math.round(brut * remise.taux / 100) : 0;
        var net = brut - montantRemise;

        var partAssureur = estAgent ? 0 : Math.round(net * taux / 100);
        var partPersonnel = estAgent ? net : 0;

        return {
          id: 'L' + C.pad(k + 1, 3),
          categorie: l.categorie, designation: l.designation,
          quantite: l.quantite, prixUnitaire: l.prixUnitaire,
          /* Le prix unitaire NET est la colonne « P.U NET » des pièces réelles :
             il se lit sans refaire la division. */
          prixUnitaireNet: l.quantite ? Math.round(net / l.quantite) : net,
          montantBrut: brut,
          remise: montantRemise,
          tauxRemise: remisable ? remise.taux : 0,
          motifRemise: remisable ? remise.label : null,
          montant: net,
          partAssureur: partAssureur,
          partPersonnel: partPersonnel,
          partPatient: net - partAssureur - partPersonnel,
          produitId: l.produitId || null, acteCode: l.acteCode || null,
          demandeId: null,
          statutPaiement: 'du', montantRegle: 0, payeLe: null, payePar: null,
        };
      });

      /* LE TOTAL EST LA SOMME DES LIGNES. Le tirer à part était le défaut. */
      var montantBrut = lignes.reduce(function (n, l) { return n + l.montantBrut; }, 0);
      var totalRemise = lignes.reduce(function (n, l) { return n + l.remise; }, 0);
      var montantTTC = lignes.reduce(function (n, l) { return n + l.montant; }, 0);
      var partAssurance = lignes.reduce(function (n, l) { return n + l.partAssureur; }, 0);
      var partPersonnel = lignes.reduce(function (n, l) { return n + l.partPersonnel; }, 0);
      var partPatient = montantTTC - partAssurance - partPersonnel;

      /* Le règlement porte sur des LIGNES ENTIÈRES : un demi-examen ne se
         prélève pas. On règle donc les premières lignes, dans l'ordre de la
         pièce, jusqu'à épuisement de ce que le patient a versé. */
      var solde = rnd() > 0.22;
      var aRegler = solde ? lignes.length : C.between(rnd, 0, lignes.length - 1);
      var paye = 0;
      lignes.forEach(function (l, k) {
        if (k < aRegler) {
          l.statutPaiement = 'paye';
          l.montantRegle = l.partPatient;
          l.payeLe = C.iso(d);
          l.payePar = 'Caisse';
          paye += l.partPatient;
        }
      });

      out.push({
        id: 'FAC' + C.pad(i + 1, 4),
        numero: 'FN-2026-' + C.pad(i + 1, 5),
        numeroMecef: rnd() > 0.12 ? 'MECEF' + C.between(rnd, 1000000, 9999999) : null,
        patientId: pat.id, patient: pat.nom + ' ' + pat.prenom, patientCode: pat.code,
        date: C.iso(d), type: nature.type,
        lignes: lignes,
        montantHT: montantTTC, montantTTC: montantTTC,
        /* Le brut et la remise restent lisibles à l'en-tête : c'est ce que
           le point de vente totalise, et le recalculer ligne à ligne à chaque
           état ferait diverger deux façons de compter la même chose. */
        montantBrut: montantBrut, totalRemise: totalRemise,
        motifRemise: remise ? remise.label : null,
        tauxRemise: remise ? remise.taux : 0,
        /* La prise en charge de l'établissement pour ses propres agents.
           Distincte de l'assurance : elle ne crée aucune créance. */
        partPersonnel: partPersonnel,
        priseEnChargePersonnel: estAgent,
        personnelId: pat.personnelId || null,
        assureur: pat.assureur, tauxPriseEnCharge: taux,
        /* Le SOUSCRIPTEUR est le niveau intermédiaire de la prise en charge —
           compagnie → souscripteur → assuré — et c'est lui que la facture mère
           consolide. Sans lui, toutes les pièces tombaient dans « Sans
           souscripteur désigné ». */
        souscripteur: pat.souscripteur || pat.souscripteurNom || null,
        partAssurance: partAssurance, partPatient: partPatient,
        montantPaye: paye, reliquat: partPatient - paye,
        /* Exigence écrite du cahier de charge : la base MECeF ne porte QUE la
           part réglée par le patient — ni la part assureur, ni les remises. */
        baseMecef: paye,
        modePaiement: C.pick(rnd, D.MODES_PAIEMENT.slice(0, 4)).id,
        statutPaiement: paye >= partPatient ? 'soldee' : (paye > 0 ? 'partielle' : 'impayee'),
        statutMecef: rnd() > 0.12 ? 'valide' : C.pick(rnd, ['en_attente', 'rejete']),
        statut: 'actif',
      });
    }
    return C.sortBy(out, 'date', 'desc');
  }

  function genMouvements(rnd, produits) {
    var out = [], today = new Date(2026, 7, 16);
    for (var i = 0; i < 400; i++) {
      var p = C.pick(rnd, produits);
      var t = C.pick(rnd, D.TYPES_MOUVEMENT);
      out.push({
        id: 'MVT' + C.pad(i + 1, 5),
        reference: 'M' + C.pad(i + 1, 6),
        date: C.iso(C.addDays(today, -C.between(rnd, 0, 90))),
        produitId: p.id, produit: p.designation,
        type: t.id, typeLabel: t.label,
        quantite: C.between(rnd, 1, 60),
        stockType: C.pick(rnd, D.TYPES_STOCK).id,
        /* RG-03 : tout mouvement porte un justificatif. */
        justificatif: C.pick(rnd, ['Facture FN-2026-00' + C.between(rnd, 100, 999), 'BL-26LNA000' + C.between(rnd, 10, 99),
          'Bon de transfert T-' + C.between(rnd, 100, 999), 'Constat de perte P-' + C.between(rnd, 10, 99),
          'Retour péremption R-' + C.between(rnd, 10, 99)]),
        utilisateur: C.pick(rnd, ['SANOUSSI Adamon', 'AKONDE Octave', 'ZIME Nadège']),
        statut: 'actif',
      });
    }
    return C.sortBy(out, 'date', 'desc');
  }

  /* Vingt-cinq jours pointés par agent. Le taux de présence se calcule sur les
     jours RENSEIGNÉS et non sur le calendrier : un service dont on n'a pointé
     que dix jours ne doit pas paraître absent les vingt autres. */
  function genPresences(rnd, personnel) {
    var out = [], today = new Date(2026, 7, 16);
    (personnel || []).forEach(function (e) {
      for (var j = 0; j < 25; j++) {
        var d = C.addDays(today, -j);
        var r = rnd();
        var etat = r > 0.94 ? 'absent' : (r > 0.86 ? 'retard' : 'present');
        out.push({
          id: 'PRS' + C.uid(), statut: 'actif',
          date: C.iso(d), employeId: e.id, employe: e.nomComplet,
          matricule: e.matricule, service: e.service,
          etat: etat,
          heureArrivee: etat === 'absent' ? null
            : (etat === 'retard' ? '08:' + C.pad(C.between(rnd, 20, 55)) : '07:' + C.pad(C.between(rnd, 40, 59))),
          heureDepart: etat === 'absent' ? null
            : '1' + C.between(rnd, 6, 8) + ':' + C.pad(C.between(rnd, 0, 59)),
          motif: etat === 'absent'
            ? C.pick(rnd, ['Maladie', 'Congé', 'Absence non justifiée', 'Autorisation']) : null,
        });
      }
    });
    return out;
  }

  function genEcritures(rnd) {
    var out = [], today = new Date(2026, 7, 16);
    /* UNE ÉCRITURE SE PASSE SUR UNE FEUILLE. Le plan SYSCOHADA révisé porte
       ses comptes de regroupement (classes, comptes principaux, divisionnaires)
       : ils TOTALISENT, ils ne s'imputent pas. Le jeu de démonstration ne tire
       donc que parmi les comptes imputables de charges et de produits — un
       journal qui porterait « 6 COMPTES DE CHARGES » ne se lirait pas. */
    var comptes = D.PLAN_COMPTABLE.filter(function (c) {
      return c.imputable && (c.classe === 6 || c.classe === 7);
    });
    for (var i = 0; i < 260; i++) {
      var j = C.pick(rnd, D.JOURNAUX);
      var c = C.pick(rnd, comptes);
      var montant = C.between(rnd, 5, 800) * 1000;
      out.push({
        id: 'ECR' + C.pad(i + 1, 5),
        numero: j.code + '-2026-' + C.pad(i + 1, 5),
        date: C.iso(C.addDays(today, -C.between(rnd, 0, 220))),
        journal: j.code, journalLibelle: j.libelle,
        compte: c.num, compteLibelle: c.libelle,
        libelle: C.pick(rnd, ['Achat médicaments SoBAPS', 'Règlement fournisseur',
          'Salaires du mois', 'Cotisations CNSS', 'Achat réactifs', 'Facture SBEE',
          'Facture d’eau', 'Fournitures administratives',
          'Frais bancaires', 'Dotation amortissement']),
        debit: rnd() > 0.5 ? montant : 0,
        credit: rnd() > 0.5 ? 0 : montant,
        centreCout: C.pick(rnd, D.CENTRES_COUT).id,
        origine: C.pick(rnd, ['Automatique — Caisse', 'Automatique — Achats', 'Automatique — Paie', 'Saisie manuelle']),
        statut: C.pick(rnd, ['validee', 'validee', 'validee', 'brouillon']),
      });
    }
    out.forEach(function (e) { if (!e.debit && !e.credit) e.debit = 10000; });
    return C.sortBy(out, 'date', 'desc');
  }

  /* --------------------------------------------------------------------------
   * Le planning reproduit les rotations réelles relevées sur les plannings de
   * la clinique : chaque catégorie a son propre régime (types de vacation,
   * durée du repos, longueur du cycle), défini dans REGLES_PLANNING.
   * Les agents d'une même catégorie sont décalés les uns par rapport aux
   * autres, de sorte qu'un poste soit couvert chaque jour.
   * ----------------------------------------------------------------------- */
  function genPlanning(rnd, personnel) {
    var out = [], today = new Date(2026, 7, 16);
    var concernes = personnel.filter(function (e) { return !!D.regleDe(e.fonction); });
    var parFonction = C.groupBy(concernes, 'fonction');

    Object.keys(parFonction).forEach(function (fonction) {
      var regle = D.regleDe(fonction);
      var agents = parFonction[fonction];
      var cycle = Math.max(regle.cycle, regle.vacations.length + (regle.repos ? 1 : 0));

      agents.forEach(function (e, rang) {
        for (var d = -20; d <= 20; d++) {
          var jour = C.addDays(today, d);
          /* Position de l'agent dans le cycle, décalée par son rang. */
          var pos = (((d + rang) % cycle) + cycle) % cycle;
          var type;
          if (pos < regle.vacations.length) {
            type = regle.vacations[pos];
          } else {
            type = regle.repos || 'repos24';
          }
          /* Les secrétaires n'assurent pas de permanence le dimanche. */
          if (type === 'permanence' && fonction !== 'entretien' && jour.getDay() === 0) {
            type = regle.repos || 'repos24';
          }
          out.push({
            id: 'PLN' + out.length,
            date: C.iso(jour), employeId: e.id, employe: e.nomComplet,
            fonction: e.fonction, service: e.service, type: type,
            regime: regle.libelle,
            statut: 'validee',
          });
        }
      });
    });
    return out;
  }

  /* Feuille de soins : actes réalisés au chevet des patients hospitalisés. */
  /* ==========================================================================
   * RELEVÉS DE CONSTANTES AU LIT DU PATIENT
   * --------------------------------------------------------------------------
   * Trois fois par jour, aux heures de la feuille papier : 08 h, 14 h et 20 h —
   * matin, midi, soir, les trois colonnes que porte le document.
   *
   * La diurèse est relevée en MILLILITRES au lit du patient, alors que
   * l'échelle de la feuille de température est graduée en litres. La conversion
   * se fait à l'affichage : convertir ici perdrait la précision de la mesure.
   * ======================================================================== */
  function genReleves(rnd, admissions) {
    var out = [];
    var ref = new Date(2026, 7, 16);
    /* Une admission en cours est celle qui n'a pas de date de sortie. Le
       champ statut vaut 'en_cours', pas 'actif' — les confondre ne filtrait
       rien du tout, et la fiche de surveillance restait vide sur un patient
       hospitalisé depuis six jours. */
    admissions.filter(function (a) { return !a.dateSortie; })
      .forEach(function (a) {
        var debut = C.toDate(a.dateEntree);
        var jours = Math.min(Math.max(1, Math.round((ref - debut) / 86400000)), 7);
        for (var j = jours; j >= 0; j--) {
          ['08:00', '14:00', '20:00'].forEach(function (h) {
            out.push({
              id: 'REL' + C.uid(), statut: 'actif',
              admissionId: a.id, date: C.iso(C.addDays(ref, -j)), heure: h,
              temperature: Number((36.4 + rnd() * 2.2).toFixed(1)),
              tension: C.between(rnd, 10, 15) + '/' + C.between(rnd, 6, 9),
              fc: C.between(rnd, 62, 108), spo2: C.between(rnd, 92, 100),
              fr: C.between(rnd, 14, 24), diurese: C.between(rnd, 600, 2200),
              poids: C.between(rnd, 45, 92), taille: C.between(rnd, 150, 188),
              traitement: C.pick(rnd, ['Perfusion RL 500ml', 'Paracétamol 1g IV',
                'Ceftriaxone 1g', 'Artésunate 60mg', 'Surveillance simple']),
              saisiPar: a.infirmier,
            });
          });
        }
      });
    return out;
  }

  function genSoins(rnd, admissions, produits) {
    var out = [], n = 0;
    var consommables = produits.filter(function (p) { return p.categorie === 'medicament' || p.categorie === 'consommable'; });
    admissions.filter(function (a) { return a.statut !== 'archive'; }).forEach(function (a) {
      var nb = C.between(rnd, 2, 6);
      for (var i = 0; i < nb; i++) {
        var jours = C.between(rnd, 0, 6);
        var d = C.addDays(new Date(2026, 7, 16), -jours);
        var prod = rnd() > 0.35 ? C.pick(rnd, consommables) : null;
        out.push({
          id: 'SOIN' + C.pad(++n, 4),
          date: C.iso(d),
          heure: C.pad(C.between(rnd, 6, 22)) + ':' + C.pick(rnd, ['00', '15', '30', '45']),
          admissionId: a.id,
          patientId: a.patientId,
          patient: a.patient,
          patientCode: a.patientCode,
          lit: a.lit,
          acte: C.pick(rnd, ACTES_SOINS),
          produit: prod ? prod.designation : '',
          quantite: prod ? C.between(rnd, 1, 3) : 0,
          soignant: a.infirmier,
          observations: '',
          etat: C.pick(rnd, ['realise', 'realise', 'realise', 'planifie']),
          statut: 'actif',
        });
      }
    });
    return out;
  }

  function genAudit(rnd, personnel) {
    var out = [], today = new Date(2026, 7, 16);
    var actions = [
      ['Connexion', 'M14', 'Session'], ['Création', 'M1', 'Patient'], ['Modification', 'M1', 'Patient'],
      ['Validation', 'M7', 'BonCommande'], ['Impression', 'M8', 'Facture'], ['Archivage', 'M6', 'Produit'],
      ['Création', 'M8', 'Facture'], ['Modification', 'M6', 'Stock'], ['Consultation', 'M10', 'BulletinPaie'],
      ['Échec de connexion', 'M14', 'Session'], ['Restauration', 'M1', 'Patient'], ['Validation', 'M11', 'Paie'],
    ];
    for (var i = 0; i < 220; i++) {
      var a = C.pick(rnd, actions), e = C.pick(rnd, personnel);
      var d = C.addDays(today, -C.between(rnd, 0, 30));
      d.setHours(C.between(rnd, 7, 21), C.between(rnd, 0, 59));
      out.push({
        id: 'LOG' + C.pad(i + 1, 5),
        dateHeure: d.toISOString(),
        utilisateur: e.nomComplet,
        action: a[0], module: a[1], entite: a[2],
        reference: a[2].toUpperCase().slice(0, 3) + C.pad(C.between(rnd, 1, 999), 4),
        poste: 'POSTE-' + C.pick(rnd, ['ACCUEIL', 'CAISSE', 'PHARMA', 'LABO', 'COMPTA', 'DIR']),
        succes: a[0].indexOf('Échec') === -1,
      });
    }
    return C.sortBy(out, 'dateHeure', 'desc');
  }

  /* ==========================================================================
   * AMORÇAGE
   * ======================================================================== */
  function seed() {
    var rnd = C.seeded(20260716);
    var personnel = genPersonnel(rnd);
    /* ======================================================================
     * PURGE DU JEU CLINIQUE — dérivation BAGUIDI (Instructions.txt,
     * 02/09/2026) : AUCUN patient, AUCUNE consultation, admission ou facture
     * de soins n'est semé — les modules cliniques sont fermés et leur jeu de
     * démonstration n'a pas lieu d'être. Les GÉNÉRATEURS restent dans le
     * fichier : rouvrir un module clinique un jour ne demandera que de les
     * rebrancher ici, rien n'est supprimé.
     * ==================================================================== */
    var patients = [];
    var souscripteurs = genSouscripteurs(rnd);
    var produits = genProduits(rnd);
    var consultations = [];
    var admissions = [];

    return {
      /* 39 — phase 1 : catalogue des actes au socle, réunions et GED semées
         par data-seed, formes canoniques courriers/ambulance, compression.
         40 — phase 2 : rôles chirurgien, anesthésiste et aide_comptable
         (Assistant Comptable, 16ᵉ), fermetures caissier m6-transferts/
         mouvements/lots.
         41 — phase 3a : tarifs publics ouverts en lecture à la réception
         (cfg-tarifs, cfg-catalogue, cfg-certificats).
         42 — phase 3b : fusion Rendez-vous & visites — une venue peut porter
         `nonPatient` et `visiteurNom` (individu non enregistré, affaire
         privée), sans consommer de code CNT (RG-01).
         43 — phase 4 (rapport maternité du 27/08/2026) : sept collections
         nouvelles (grossesses, partogrammes, cpon, planificationFamiliale,
         registreSONU, ptme, soinsCuratifsMaternite), naissances enrichies
         (PC/PT, Apgar 1-5-10, vitamine K1, réanimation, vaccins J0), M4 semé
         AU SOCLE (les stats et tableaux de bord le lisent), acte SAA au
         catalogue.
         44 — phase 5 : `avoirs` au socle (une pièce, deux vues M8/MECeF, avec
         lignes annulées et contre-passation), une dépense porte des LIGNES
         (arbitrage — le total est leur somme), `pvReceptions` (M7), et
         M8.annuler fermé au caissier (l'avoir est le canal de correction).
         45 — phase 6 : le code d'analyse unique NNNNN-AAAA sur les demandes
         (fabrique unique PR.codeAnalyse, série annuelle) et la collection
         `plagesReactif` (bornes par lot de réactif, versionnées par date).
         46 — phase 7 : les collections `cpa` (consultation pré-anesthésique)
         et `crAnesthesie` (compte rendu d'anesthésie), et la demande
         d'analyse peut porter l'origine 'service' (fiche m3-demande-examen).
         47 — phase 8 : l'imagerie éclatée — `demandesImagerie` (états du
         labo : demandée → payée → exécutée → validée), `clichesImagerie`
         (galerie), `examensImagerie` et `variablesImagerie` au socle
         (administrables par cfg-imagerie-catalogue), la ligne payable porte
         `demandeImagerieId`.
         48 — phase 10 : les collections `enquetes` (modèles de
         questionnaires — le formulaire naît du modèle) et
         `reponsesEnquetes`.
         49 — arbitrage du 01/09/2026 : plus aucun montant NUL — GY-SAA
         reçoit un tarif d'attente aligné sur l'AMIU, les 34 références
         SAGE non valorisées reçoivent la MÉDIANE de leur catégorie
         (marquées `valorisationProvisoire`, tracées dans la surcouche
         `valorisationsSage` désormais semée au socle).
         50 — vague 49 : les validations du ressort de la DIRECTION sont
         levées — tarifs d'attente ARRÊTÉS (`tarifArreteLe`, la semence
         garde son marquage), valorisations confirmées, groupes d'articles
         confirmés, questionnaire validé. Les marquages qui attendent un
         professionnel nommé (variables labo, pathologies, check-listes)
         restent.
         51 — vague 51 : les validations écrites des PROFESSIONNELS sont
         arrivées (variables labo par le biologiste, pathologies par les
         médecins — `valideLe`/`validePar`, la semence garde son marquage),
         seuils d'alerte confirmés, et la « journée des postes » du seed
         (brouillons validés, résultats rendus, files résiduelles).
         52 — vague 53 : les CINQ fiches RBAC qui manquaient (dm, direction,
         comptable, agentadmin, ambulancier — un rôle sans fiche avait tous
         les droits), fermetures caissier (stock-gros, dashboard stock,
         dépenses), M1 fermé au magasinier, bon de livraison fermé au
         biologiste.
         53 — dérivation BAGUIDI, vague identité (02/09/2026) : C.BRAND porte
         l'identité CLINIQUE BAGUIDI « L'AS DE CŒUR » (SIGH-CBG), le préfixe
         des clés de stockage passe de sigh-cnt: à sigh-cbg:, le code dossier
         et les numérotations de pièces lisent C.BRAND.sigle (CBG).
         54 — dérivation BAGUIDI, vague périmètre (02/09/2026) : fermeture AU
         MODULE de M1, M2, M3, M4, M5, M8, M9 et MECEF dans `modulesActifs`
         (fiches MOD-CBG-*), écrans d'évaluation NS 131 fermés au canal des
         écrans, barème NS 131 seedé VIDÉ.
         55 — dérivation BAGUIDI, vague seeders (02/09/2026) : le personnel
         devient les HUIT agents d'Instructions.txt (salaires d'attente
         `salaireProvisoire`), comptes m-00N@baguidi-clinique.bj, PURGE du jeu
         clinique (aucun patient, consultation, admission, facture de soins ;
         seeders cliniques débranchés de data-seed), grille NS 132 `aValider`,
         fiches de poste CNT non semées.
         56 — dérivation BAGUIDI, vague RBAC (02/09/2026) : rôle rh DÉSARCHIVÉ
         (deux titulaires, fiche RBAC05 réécrite), da ARCHIVÉ (transfert à la
         Direction), quinze rôles sans titulaire ARCHIVÉS (motifArchivage),
         Direction porteuse des validations RG-04 (m7-besoins/m7-commandes en
         surcharge d'écran), comptable en écriture M6/M7 (aucun magasinier
         nommé — décision à confirmer), médecin/infirmier gardent tableau de
         bord + m7-besoins, statistiques cliniques PIL fermées aux écrans.
         57 — décision du 03/09/2026 : les deux OFFICINES (pharmacie interne
         urgences, pharmacie externe voie orale) fermées au canal des écrans
         (fiche MOD-CBG-OFFICINE) — la dispensation suppose une ordonnance
         réglée en caisse ; le stock reste entier. La collection `utilisateurs`
         (les huit comptes + l'admin) passe AU SOCLE : le modal de profil de la
         barre supérieure la lit sur toutes les pages, elle ne peut plus être
         amorcée par le seul écran M14.
         58 — décision du 04/09/2026 : le REGISTRE des délivrances
         (`m6-dispensation`) rejoint les officines dans la fiche
         MOD-CBG-OFFICINE — sans ordonnance encaissée en amont, il n'a aucun
         geste à enregistrer.
         59 — décision du 06/09/2026 : le PLAN COMPTABLE SYSCOHADA RÉVISÉ
         remplace celui de la clinique d'origine — la collection `comptes`
         porte les 1 332 comptes officiels (code, niveau, parent, imputable),
         et les écritures passent sur les codes à quatre chiffres.
         60 — décision du 07/09/2026 : les SIX secteurs de la clinique (groupes
         de prestation et centres de coûts alignés), et l'AIB — collection
         `retenuesAIB`, statut de l'IFU sur chaque fournisseur (`ifuStatut`,
         jamais semé : il se vérifie et se date).
         61 — L'HISTORIQUE DES PRIX (07/09/2026) : collection `historiquePrix`,
         écrite par le SEUL entonnoir `update()` du magasin ; les lots portent
         leur prix d'entrée (`prixAchat`, `prixEstime`) pour la valorisation
         au lot ; les articles portent leur `coefficientVente` (1,00).
         62 — décision du 07/09/2026 : PAS DE PRIMES chez BAGUIDI — la grille
         `grillePrimes` est VIDE, l'écran m10-primes est fermé
         (MOD-CBG-PRIMES), et une grille vide vaut ZÉRO prime au bulletin,
         jamais un repli sur la note de la clinique d'origine. Le moteur reste
         entier pour la réouverture.
         63 — le BARÈME DE L'AIB devient une donnée administrable
         (collection `baremeAIB`) : la Direction arrête le champ d'application
         de chaque taux, et le moteur s'y conforme à la retenue suivante.
         Seule la règle des 5 % est arrêtée d'emblée — les taux de 1 % et 3 %
         attendent leur condition, et ne s'appliquent pas d'ici là.
         64 — L'IFU SUR CHAQUE FICHE DE RÉMUNÉRATION (07/09/2026) : agents du
         `personnel` comme `prestataires` externes portent `ifu`, `ifuStatut`,
         `ifuVerifieLe`/`ifuVerifiePar` et leur `regimeRemuneration`
         (salaire ou honoraires). C'est le RÉGIME qui décide : un salaire
         supporte l'ITS, des honoraires supportent l'AIB. Le bulletin de paie
         porte désormais la ligne d'AIB dans les deux cas — motivée à zéro pour
         un salarié — et les bulletins enregistrent `aib`, `aibTaux`,
         `aibBase`, `aibMotif`. Aucun IFU n'est semé : il se vérifie et se date. */
      _version: VERSION,
      _seededAt: new Date().toISOString(),
      personnel: personnel,
      /* Les comptes de session — lus par M14 ET par le modal de profil de la
         barre supérieure, donc amorcés ICI (règle de placement du dépôt). */
      utilisateurs: genUtilisateurs(rnd, personnel),
      patients: patients,
      produits: produits,
      /* La SURCOUCHE de valorisation (vague 33) porte la trace de l'arbitrage
         du 01/09/2026 : une fiche par référence que SAGE ne valorisait pas,
         datée, sourcée, marquée à valider. Le document reste ce qu'il est. */
      valorisationsSage: produits.filter(function (p) { return p.valorisationProvisoire; })
        .map(function (p, i) {
          return {
            id: 'VSG' + C.pad(i + 1, 3), statut: 'actif',
            code: p.code, designation: p.designation,
            prixRevient: p.prixAchat,
            date: '2026-09-01', auteur: 'Direction',
            source: p.sourceValorisation + ' ; confirmée par la Direction le 01/09/2026',
            observation: 'Médiane de la catégorie, confirmée par la Direction — révisable à la première facture fournisseur.',
            aValider: false,
          };
        }),
      lots: genLots(rnd, produits),
      /* L'historique des prix naît VIDE et ne s'écrit qu'au fil des
         modifications : le semer reviendrait à inventer des changements qui
         n'ont pas eu lieu. */
      historiquePrix: [],
      consultations: consultations,
      admissions: admissions,
      /* Jeu clinique NON SEMÉ chez BAGUIDI (modules fermés). */
      soins: [],
      /* Relevés de constantes au lit du patient. Lus par la feuille de
         température, par la fiche de surveillance ET par le dossier patient :
         amorcés ICI, jamais par un écran — sinon celui qu'on ouvre en premier
         décide si les autres voient quelque chose. */
      releves: [],
      factures: [],
      mouvements: genMouvements(rnd, produits),
      ecritures: genEcritures(rnd),
      planning: genPlanning(rnd, personnel),
      audit: genAudit(rnd, personnel),
      analyses: D.ANALYSES.map(function (a) { return Object.assign({}, a); }),
      /* Catalogue des actes — lu par la consultation, l'hospitalisation, la
         facturation, la recherche globale ET le moteur de parcours : amorcé ICI.
         L'amorcer depuis l'écran de configuration laissait la prescription sans
         options sur tout poste qui n'avait jamais ouvert cfg-tarifs, et le
         moteur tarifait depuis D.ACTES pendant que les écrans lisaient la
         collection — deux vérités. D.ACTES n'est que la semence. */
      actes: D.ACTES.map(function (a, i) {
        var rec = Object.assign({ id: 'ACT' + C.pad(i + 1, 3) }, a);
        /* VALIDATION DE LA DIRECTION DU 01/09/2026 : les tarifs d'ATTENTE
           sont ARRÊTÉS — plus aucun « provisoire » au catalogue vivant. La
           SEMENCE (D.ACTES) garde son marquage : elle documente ce qui
           venait d'un document et ce qui n'en venait pas ; c'est l'arrêté
           qui rend le tarif opposable, et il est daté. */
        if (rec.tarifProvisoire) {
          rec.tarifProvisoire = false;
          rec.tarifArreteLe = '2026-09-01';
          rec.source = (rec.source ? rec.source + ' ; ' : '')
            + 'tarif arrêté par la Direction le 01/09/2026';
        }
        return rec;
      }).concat(D.TYPES_CHAMBRE.map(function (t, i) {
        return {
          id: 'ACH' + C.pad(i + 1, 3), statut: 'actif',
          code: 'HO' + C.pad(i + 1, 2),
          libelle: 'Journée d’hospitalisation — chambre ' + t.label,
          secteur: 'Hospitalisation', prix: t.tarif,
          source: 'CDCT — types de chambre et tarifs journaliers',
        };
      })).concat([(function () {
        /* DEMANDE ÉCRITE du rapport maternité (Module A) : « Ajout de l'acte
           Avortement / Soins Après Avortement (SAA) dans la nomenclature ».
           Aucun document ne le tarife ; l'ARBITRAGE DU 01/09/2026 (« plus
           aucun montant nul ») lui donne un TARIF D'ATTENTE aligné sur
           l'AMIU — la SAA se pratique par aspiration manuelle intra-utérine,
           c'est le même geste. Marqué provisoire : une valeur d'attente ne
           se présente jamais comme un tarif validé. */
        var amiu = (D.CATALOGUE || []).filter(function (e) { return e.code === 'AMIU'; })[0] || {};
        return {
          id: 'ACT-SAA', statut: 'actif', code: 'GY-SAA',
          libelle: 'Avortement — Soins Après Avortement (SAA)',
          secteur: 'Gynéco-obstétrique',
          prix: amiu.prixNonAssure != null ? amiu.prixNonAssure : null,
          prixNonAssure: amiu.prixNonAssure != null ? amiu.prixNonAssure : null,
          prixAssure: amiu.prixAssure != null ? amiu.prixAssure : null,
          assurable: amiu.assurable,
          tarifProvisoire: false, tarifArreteLe: '2026-09-01',
          motifPrix: 'Tarif aligné sur l’AMIU (la SAA se pratique par AMIU), arrêté par la Direction le 01/09/2026.',
          source: 'Rapport maternité 27/08/2026 — Module A ; tarif arrêté par la Direction le 01/09/2026',
        };
      })()]),
      /* Amorcées par leur écran : parcours de prescription. */
      ordonnances: [],
      /* FACTURES D'AVOIR — une seule pièce, deux vues : la gestion (M8,
         contre-passation comptable, lignes annulées, remboursement) et le
         registre fiscal (MECeF). Lue par les deux modules ET par la
         comptabilité : amorcée ICI. */
      avoirs: [],
      /* PV de réception (M7) — consommables et réactifs, deux écrans d'un
         même module. Vide au socle pour la corbeille. */
      pvReceptions: [],
      taches: [],
      assureurs: D.ASSUREURS.map(function (a, i) {
        return Object.assign({ id: 'ASS' + C.pad(i + 1), statut: 'actif', convention: 'Signée', assures: 0 }, a);
      }),
      /* Le STATUT DE L'IFU au fichier de la DGI commande le taux d'AIB retenu
         au tiers. Il n'est semé pour AUCUN fournisseur : c'est un constat que
         la clinique relève et date, et supposer qu'un IFU est actif — ou qu'il
         ne l'est pas — reviendrait à décider d'un prélèvement sur un tiers.
         Tant qu'il n'est pas vérifié, aucune retenue ne s'enregistre. */
      fournisseurs: D.FOURNISSEURS.map(function (f) {
        return Object.assign({ statut: 'actif', ifuStatut: 'inconnu', ifuVerifieLe: null }, f);
      }),
      retenuesAIB: [],
      /* LE BARÈME D'AIB EST UNE DONNÉE, administrable : la Direction arrête le
         champ d'application de chaque taux, et le moteur s'y conforme à la
         ligne suivante. Seule la règle des 5 % est ARRÊTÉE — c'est la seule
         qui repose sur un écrit ; les deux autres sont offertes avec leur
         condition PROPOSÉE, et ne s'appliquent pas tant qu'elle n'est pas
         validée. */
      baremeAIB: (D.PARAM_AIB.bareme || []).map(function (r, i) {
        return Object.assign({ id: 'BAIB' + C.pad(i + 1, 2), statut: 'actif' }, r);
      }),
      /* Référentiels lus depuis plusieurs modules : amorcés ici, pas par un écran. */
      naturesFacture: D.NATURES_FACTURE.map(function (n) { return Object.assign({}, n); }),
      souscripteurs: souscripteurs,
      /* Lus par la configuration ET par le moteur d'habilitations : amorcés ici. */
      secteurs: D.NS145.secteurs.map(function (x) { return Object.assign({}, x); }),
      /* Grilles de garanties : vides tant qu'une convention n'est pas saisie. */
      garanties: [],
      centresCouts: D.CENTRES_COUTS.map(function (c) { return Object.assign({}, c); }),

      /* ====================================================================
       * COMPTES DE TRÉSORERIE — d'où l'argent sort
       * --------------------------------------------------------------------
       * Amorcés ICI et non par l'écran des rapprochements : la saisie des
       * dépenses lit la même liste, et une page ne charge que le module de son
       * écran. Les trois banques sont celles que le plan comptable de la
       * clinique nomme (631810 BOA, 631820 Orabank, 631830 Coris Bank).
       *
       * LA CAISSE EN FAIT PARTIE : une dépense de trésorerie sort le plus
       * souvent en espèces. L'omettre obligerait à imputer un décaissement de
       * caisse sur une banque, et le rapprochement bancaire s'en trouverait
       * faussé.
       * ================================================================== */
      banques: [
        { id: 'BQ00', statut: 'actif', banque: 'Caisse', intitule: 'Caisse de la clinique',
          numeroCompte: null, compteComptable: '5711', devise: 'FCFA', statutCompte: 'actif',
          nature: 'caisse',
          source: 'Compte 571 — caisse. Les décaissements en espèces sortent d’ici.' },
        { id: 'BQ01', statut: 'actif', banque: 'BOA', intitule: 'Compte courant BOA',
          numeroCompte: '001 40218 001', compteComptable: '5211', devise: 'FCFA', statutCompte: 'actif',
          nature: 'banque',
          source: 'Plan comptable de la clinique — compte 631810 « Frais bancaire BOA ».' },
        { id: 'BQ02', statut: 'actif', banque: 'Orabank', intitule: 'Compte courant Orabank',
          numeroCompte: '002 51907 001', compteComptable: '5212', devise: 'FCFA', statutCompte: 'actif',
          nature: 'banque',
          source: 'Plan comptable de la clinique — compte 631820 « Frais bancaire Orabank ».' },
        { id: 'BQ03', statut: 'actif', banque: 'Coris Bank', intitule: 'Compte courant Coris Bank',
          numeroCompte: '003 33184 001', compteComptable: '5211', devise: 'FCFA', statutCompte: 'actif',
          nature: 'banque',
          source: 'Plan comptable de la clinique — compte 631830 « Frais bancaire Coris bank ».' },
      ],

      /* Les dépenses de trésorerie directes — voir m12-depenses. */
      depenses: [],

      /* ======================================================================
       * CATALOGUE TARIFAIRE — DEUX PRIX PAR ACTE
       * ----------------------------------------------------------------------
       * Les six grilles officielles portent chacune deux colonnes, « PRIX NON
       * ASSURE » et « PRIX ASSURE », le second étant presque toujours le plus
       * élevé. C'est le modèle économique de la clinique, pas une coquille :
       * le tarif conventionné opposable à une compagnie n'est pas le tarif de
       * guichet.
       *
       * Amorcé ICI parce que six modules le lisent — prescription, laboratoire,
       * pharmacie, facturation, assurances, comptabilité. Le poser dans un
       * écran le rendrait vide partout ailleurs.
       * ==================================================================== */
      catalogueTarifs: (D.CATALOGUE || []).map(function (t, i) {
        return Object.assign({ id: 'TAR' + C.pad(i + 1, 3) }, t);
      }),

      /* ======================================================================
       * EN-TÊTE UNIQUE — ARBITRAGE DU 31/08/2026
       * ----------------------------------------------------------------------
       * Le référentiel des variantes d'en-tête est RETIRÉ (arbitrage hérité
       * de la clinique d'origine, conservé chez BAGUIDI) : toutes les pièces
       * portent l'unique identité légale de C.BRAND — IFU 3201001996110 du
       * 26/11/2010 ; RCCM et autorisation restent à compléter par la
       * Direction et les écrans le disent.
       * ==================================================================== */

      /* ======================================================================
       * TYPES DE PIÈCES CERTIFIANTES
       * ----------------------------------------------------------------------
       * Quatorze gabarits officiels, chacun avec son sigle de référence, sa
       * direction émettrice et son en-tête. La numérotation suit
       * « <SIGLE> n°/n°/<sigle clinique>/<direction>/<année> » — le sigle de
       * la clinique est LU SUR C.BRAND.sigle (CBG), jamais écrit en dur.
       *
       * DEUX COLLISIONS DE SIGLES existent dans les documents sources : CMA
       * désigne l'accouchement ET l'aptitude, CMD le décès ET le genre de mort.
       * Elles sont CONSERVÉES telles quelles et signalées : renuméroter
       * d'office romprait la correspondance avec les registres papier tenus
       * depuis des années.
       * ==================================================================== */
      typesPiece: [
        ['ATG', 'Attestation de grossesse', 'DG/DE', 'CERT-ATG'],
        ['CMNI', 'Certificat médical de non-infirmité', 'DG/DE', null],
        ['CMA', 'Certificat médical d’accouchement', 'DG/DE', null,
          { collision: 'Le sigle CMA désigne aussi le certificat médical d’aptitude.' }],
        ['CMA', 'Certificat médical d’aptitude', 'DG/DE', 'CERT-APT',
          { collision: 'Le sigle CMA désigne aussi le certificat médical d’accouchement.' }],
        ['CMH', 'Certificat médical d’hospitalisation (garde-malade)', 'DG/DE', null],
        ['CMD', 'Certificat médical de décès', 'DA', 'CERT-DEC',
          { collision: 'Le sigle CMD désigne aussi le certificat de genre de mort.' }],
        ['CMD', 'Certificat médical de genre de mort', 'DA', null,
          { collision: 'Le sigle CMD désigne aussi le certificat médical de décès.' }],
        ['CMP', 'Certificat médical prénuptial', 'CN', null,
          { examens: ['LAB-GSRH', 'LAB-HEPB', 'LAB-HEPC', 'LAB-TPHA', 'LAB-HIV', 'LAB-EPHB'] }],
        ['CMCBV', 'Certificat médical de coups et blessures volontaires', 'CN', 'CERT-CBV'],
        ['CMDPS', 'Certificat médical de dispense aux activités physiques et sportives', 'DG/DE', 'CERT-DPS'],
        ['CMNCI', 'Certificat médical de non contre-indication aux activités physiques et sportives', 'DM/DA', null],
        ['CMVC', 'Certificat médical de visite et de contre-visite', 'DG/DE', 'CERT-VC'],
        ['CMR-H', 'Certificat médical d’arrêt de travail et/ou d’hospitalisation', 'DG/DA', null],
        ['SCAM', 'Sortie contre avis médical', 'CN', null],
      ].map(function (t, i) {
        var o = t[4] || {};
        return {
          id: 'TPC' + C.pad(i + 1, 2), sigle: t[0], libelle: t[1],
          direction: t[2], tarifCode: t[3],
          collision: o.collision || null,
          /* Le prénuptial ne se saisit pas : il se remplit depuis les
             résultats VALIDÉS BIOLOGIQUEMENT du patient. Un examen non validé
             ne peut pas y être coché. */
          examens: o.examens || null,
          statut: 'actif',
        };
      }),

      /* Pièces émises : le registre des certificats délivrés. */
      pieces: [],

      /* ======================================================================
       * SOIGNANTS — QUI PRESCRIT, QUI EXÉCUTE
       * ----------------------------------------------------------------------
       * Dérivés du personnel : une seconde liste de noms divergerait du dossier
       * RH au premier recrutement. La fiche ne porte que ce que le dossier RH
       * ne dit pas — les deux droits, et les secteurs d'exercice.
       *
       * DEUX DROITS DISTINCTS SUR UNE MÊME FICHE, parce que la sage-femme les
       * cumule : elle prescrit ET elle exécute. Deux listes séparées auraient
       * obligé à l'inscrire deux fois.
       *
       * Deux agents sont soignants sans être ni l'un ni l'autre : le
       * Surveillant Général supervise, l'Échographiste réalise. Les compter
       * comme prescripteurs aurait fait mentir les effectifs de la Direction.
       * ==================================================================== */
      soignants: personnel.filter(function (a) {
        return ['medecin', 'sage_femme', 'infirmier'].indexOf(a.fonction) !== -1;
      }).map(function (a, i) {
        var superviseur = /Surveillant/i.test(a.poste || '');
        var echographiste = /Échographiste|Echographiste/i.test(a.poste || '');
        var q = a.fonction;
        return {
          id: 'SOI' + C.pad(i + 1, 2),
          personnelId: a.id, nomComplet: a.nomComplet, poste: a.poste,
          qualite: q,
          /* Le médecin et la sage-femme prescrivent ; l'infirmier non. Le
             superviseur et l'échographiste sont retirés des deux listes. */
          prescrit: (q === 'medecin' || q === 'sage_femme') && !superviseur && !echographiste,
          execute: (q === 'infirmier' || q === 'sage_femme') && !superviseur,
          /* Le superviseur n'exécute pas : il contrôle. C'est l'IG de la
             description de poste du 26/10/2023. */
          supervise: superviseur,
          realiseImagerie: echographiste,
          secteurs: q === 'sage_femme' ? ['maternite', 'salle_soins']
            : q === 'infirmier' ? ['salle_soins', 'hospitalisation']
              : ['salle_soins', 'hospitalisation', 'maternite'],
          statut: 'actif',
          source: 'Dérivé de l’organigramme ; effectifs confirmés par la Direction le 24/08/2026',
        };
      }),

      /* ======================================================================
       * PRESCRIPTIONS — DEUX TYPES, QUATRE ORIGINES
       * ----------------------------------------------------------------------
       * Le prototype ne connaissait que l'ordonnance issue de la consultation.
       * La clinique prescrit depuis quatre endroits (consultation,
       * hospitalisation, bloc, maternité) et distingue deux objets :
       * l'ORDONNANCE (des médicaments à délivrer, qui sortent du stock) et les
       * SOINS (des actes à exécuter, qui ne sortent pas du stock).
       *
       * Amorcée vide : elle se remplit par le parcours, jamais par une saisie
       * de démonstration qui n'aurait traversé aucun module.
       * ==================================================================== */
      prescriptions: [],

      /* Administrations : une ligne par passage, avec son rang. C'est le rang
         qui décide du secteur (voir D.secteurAdministrateur) — la première
         administration d'un traitement hospitalier revient à la salle de
         soins, les suivantes à l'hospitalisation. */
      administrations: [],

      /* ======================================================================
       * BLOC OPÉRATOIRE
       * ----------------------------------------------------------------------
       * Le compte rendu opératoire est une pièce de preuve : c'est elle qu'on
       * ressort quand une suite opératoire est contestée. Elle porte ses trois
       * intervenants nommés — opérateur, aide-opérateur, anesthésiste.
       *
       * Les deux check-listes sont SÉPARÉES, à deux moments distincts. Les
       * fondre ferait cocher après l'intervention ce qui devait l'être avant,
       * ce qui vide l'exercice de son sens.
       * ==================================================================== */
      crOperatoires: [],
      checklistsBloc: [],

      /* ======================================================================
       * CALENDRIER FISCAL — DÉROULÉ SUR L'EXERCICE
       * ----------------------------------------------------------------------
       * Amorcé ICI et non par son écran : trois modules le lisent désormais —
       * M12 (le suivi), CFG (la référence documentaire) et les TABLEAUX DE BORD
       * de la Direction et du comptable.
       *
       * Un tableau de bord qui affiche « 0 échéance dépassée » faute d'avoir la
       * collection chargée ne montre pas un vide : il affirme une FAUSSETÉ, et
       * dit à la Direction qu'il n'y a rien à payer. C'est plus dangereux qu'un
       * tableau de bord absent.
       * ==================================================================== */
      echeancesFiscales: genEcheances(),

      /* Comptes rendus de maternité : accouchement, planning familial, AMIU.
         Trois pièces aux rubriques propres — un gabarit unique aurait fait
         remplir des champs sans objet. */
      crMaternite: [],

      /* ======================================================================
       * IMAGERIE
       * ----------------------------------------------------------------------
       * Les comptes rendus d'échographie et d'ECG. Lus par M1 (dossier du
       * patient), M2 (l'écran qui les produit) et RAP (statistiques) : amorcés
       * ici et non par l'écran.
       * ==================================================================== */
      resultatsImagerie: [],

      /* ======================================================================
       * RÉFÉRENCE ET CONTRE-RÉFÉRENCE
       * ----------------------------------------------------------------------
       * Deux collections et non une : la contre-référence est écrite par un
       * AUTRE établissement, souvent des semaines plus tard, et elle peut ne
       * jamais arriver. La fondre dans la fiche de référence obligerait à
       * distinguer « pas encore revenue » de « champs non remplis », ce qui est
       * précisément l'indicateur que la clinique veut suivre.
       *
       * Le lien se fait par le NUMÉRO de la fiche de référence, comme sur le
       * papier — c'est le seul identifiant que les deux établissements
       * partagent.
       * ==================================================================== */
      fichesReference: [],
      contreReferences: [],

      /* ======================================================================
       * FICHES CLINIQUES D'HOSPITALISATION
       * ==================================================================== */
      surveillancesTransfusion: [],
      scoresGlasgow: [],
      rapportsMedicaux: [],

      /* ======================================================================
       * FILE D'ATTENTE
       * ----------------------------------------------------------------------
       * FIFO tempéré par la PRIORITÉ DE TRIAGE : l'ordre d'arrivée gouverne,
       * sauf urgence. Un FIFO strict ferait attendre une urgence vitale
       * derrière douze consultations de routine ; une priorité sans FIFO
       * ferait passer indéfiniment les mêmes.
       * ==================================================================== */
      fileAttente: [],

      /* ======================================================================
       * RH — FICHES DE POSTE ET PRÊTS-ÉTUDES
       * ==================================================================== */
      fichesPoste: [],
      pretsEtudes: [],

      /* ======================================================================
       * RAPPELS ET MESSAGES
       * ----------------------------------------------------------------------
       * Le MESSAGE est un gabarit administrable, le RAPPEL est son envoi. Les
       * confondre obligerait à ressaisir le texte à chaque anniversaire.
       * ==================================================================== */
      /* ==================================================================
       * FACTURES MÈRES D'ASSURANCE
       * ------------------------------------------------------------------
       * Une facture mère consolide TOUS les souscripteurs d'une compagnie sur
       * une période. Ses filles sont les factures par souscripteur. Lue par M9
       * (qui l'émet) et M12 (qui la comptabilise) : amorcée ici.
       * ================================================================== */
      facturesMere: [],

      /* Répertoire des ambulances — tenu par l'accueil, lu par M13 et par le
         tableau de bord de l'accueil. */
      ambulances: [],

      /* Dossiers de consultation étendus : zones Accueil et Consultation. */
      dossiersConsultation: [],

      modelesMessage: [],
      rappels: [],
      /* ====================================================================
       * PAS DE PRIMES CHEZ BAGUIDI — décision de la Direction du 07/09/2026
       * --------------------------------------------------------------------
       * La grille est VIDE, comme le barème NS 131 : aucune note de service de
       * primes n'a été fournie, et la clinique n'en verse pas pour l'instant.
       * Le MOTEUR reste entier — grille datée, versionnement, calcul au
       * bulletin — pour que la réouverture ne demande qu'une décision écrite
       * et la saisie d'une grille, jamais du code.
       *
       * Corollaire tenu dans D.NS132.montant() : une grille vide vaut ZÉRO
       * prime, et non un repli sur la grille de la clinique d'origine — sans
       * quoi la paie verserait des primes que personne n'a décidées.
       * ================================================================== */
      grillePrimes: [],
      historiquePrimes: [],
      /* Activité des modules. La clinique ne pratique NI la banque de sang NI
         la transfusion : les deux écrans sont fermés d'emblée, et rouvrables. */
      /* --- Décisions RBAC de la Direction --------------------------------
         Le laborantin consulte le répertoire des patients — il en a besoin
         pour rattacher un prélèvement — mais n'y modifie RIEN, et n'accède
         pas au dossier médical. Ce n'est pas une méfiance : le dossier
         médical, les antécédents et les documents numérisés relèvent du
         soignant, pas du laboratoire.

         Ces décisions vivent ici et non dans le manifeste : ce sont des choix
         d'organisation, que la clinique doit pouvoir défaire depuis
         « Rôles & permissions » sans qu'on touche au code. */
      rbac: [
        /* ====================================================================
         * RÈGLE DES FICHES CI-DESSOUS : ON NE DÉCLARE JAMAIS `voir` AU NIVEAU
         * DU MODULE.
         * --------------------------------------------------------------------
         * `surchargeExplicite()` ne consulte QUE `voir` : une entrée de module
         * qui l'omet borne l'écriture sans rien accorder, et la visibilité
         * reste celle du manifeste, écran par écran.
         *
         * Le déclarer à `true` OUVRE tous les écrans du module — y compris
         * ceux dont la liste `roles` excluait le rôle. C'est ainsi que le
         * caissier avait récupéré `m1-externe`, alors que « la caisse ne crée
         * jamais la demande » est un garde-fou de contrôle interne.
         *
         * `voir: false` reste possible : c'est une FERMETURE délibérée, et le
         * seul cas où déclarer `voir` a un sens ici.
         * ================================================================== */

        /* ====================================================================
         * LE CAISSIER-DISPENSATEUR
         * --------------------------------------------------------------------
         * Il encaisse et il délivre. La pharmacie lui est rattachée depuis la
         * fermeture du compte Pharmacien — mais la pharmacie, c'est le STOCK
         * DÉTAIL et la dispensation, PAS le magasin central.
         *
         * Le GROS relève du Gestionnaire de Stock : lui laisser le stock gros
         * et les transferts reviendrait à ce que le même agent commande,
         * receptionne, transfère et vende — c'est-à-dire à supprimer toute
         * séparation des tâches sur la chaîne d'approvisionnement.
         *
         * Il ne touche RIEN de clinique (RG-13) : il voit l'identité du
         * patient pour encaisser, jamais son dossier.
         * ================================================================== */
        {
          id: 'RBAC12', role: 'caissier', libelleOrigine: 'Caissier', statut: 'archive',
          archiveLe: '2026-09-02', motifArchivage: 'Poste sans titulaire chez BAGUIDI (Instructions.txt, 02/09/2026) — rôle archivé, jamais supprimé (RG-14). Réactivable sur décision écrite de la Direction.',
          libelle: 'Caissier — Dispensaire (Pharmacie)', libelleCourt: 'Caisse-Pharma',
          droits: {
            /* SEULS les modules que le manifeste lui ouvre — DASH, M1, M8,
               M9, MECEF, RAP. En ajouter un ici ne bornerait pas ses droits :
               cela LUI OUVRIRAIT le module, puisqu'une surcharge accorde
               autant qu'elle restreint. La pharmacie (M6) et la comptabilité
               (M12) lui viennent du manifeste par ailleurs. */
            M1: { editer: false, annuler: false },
            /* ARBITRAGE SOLDÉ (phase 5) : la facture d'avoir est LIVRÉE
               (m8-facture-avoir), le canal de correction existe — l'annulation
               de pièces est donc FERMÉE au caissier, comme la matrice cible
               l'exige. Une erreur de caisse se corrige par un AVOIR, émis par
               le Comptable ou la DAF, jamais par la disparition de la pièce. */
            M8: { editer: true, annuler: false },
            M9: { editer: true, annuler: false },
            MECEF: { editer: true, annuler: false },
          },
          droitsEcrans: {
            /* SES DEUX TABLEAUX : la caisse et la pharmacie. Il tient les
               deux activités — c'est un seul poste, Caissière-Dispensatrice. */
            'dash-caissier': { voir: true, editer: true, annuler: true },
            'dash-pharmacien': { voir: true, editer: true, annuler: true },

            /* Le patient s'identifie au guichet ; son dossier ne s'y ouvre pas. */
            'm1-patients': { voir: true, editer: false, annuler: false },
            'm1-patient-profil': { voir: true, editer: false, annuler: false },
            'm1-dossier-medical': { voir: false },
            'm1-antecedents': { voir: false },
            'm1-dossier-etendu': { voir: false },
            'm1-pieces': { voir: false },
            'm1-constantes': { voir: false },
            'm1-reference': { voir: false },
            'm1-contre-reference': { voir: false },
            'm1-documents': { voir: false },
            'm1-numerisation': { voir: false },

            /* LE MAGASIN N'EST PAS LA PHARMACIE. Le gros relève du
               Gestionnaire de Stock : laisser au dispensateur le magasin ET
               les transferts reviendrait à ce que le même agent commande,
               réceptionne, transfère et vende. Décision du 02/09/2026 : la
               LECTURE même du magasin lui est retirée, ainsi que le tableau
               de bord stock — son poste est la pharmacie de détail. */
            'm6-stock-gros': { voir: false },
            'm6-dashboard': { voir: false },
            /* FERMÉS NOMMÉMENT — matrice cible des Instructions, phase 2 :
               « Interdiction d'accéder aux transferts Gros → Détail et aux
               mouvements de stock FEFO ». La lecture même est retirée : la
               chaîne d'approvisionnement ne se surveille pas depuis la
               caisse. */
            'm6-transferts': { voir: false, editer: false, annuler: false },
            'm6-mouvements': { voir: false, editer: false, annuler: false },
            'm6-lots': { voir: false, editer: false, annuler: false },
            'm6-inventaire': { voir: true, editer: false, annuler: false },
            'm6-reprise': { voir: false },

            /* L'AVOIR se consulte au guichet — le patient revient avec sa
               pièce — mais son ÉMISSION appartient au Comptable et à la DAF
               (matrice cible) : contre-passer une recette n'est pas un geste
               de caisse. */
            'm8-facture-avoir': { voir: true, editer: false, annuler: false },
            /* La configuration fiscale engage la clinique devant la DGI. */
            'mecef-config': { voir: false },
            /* Décision du 02/09/2026 — elle REMPLACE la doctrine antérieure
               (« une dépense se saisit au fil de l'eau, y compris à la
               caisse ») : les dépenses journalières sont un geste COMPTABLE,
               fermé à la caisse. Une dépense née au guichet remonte au
               comptable par pièce justificative, pas par saisie. */
            'm12-depenses': { voir: false },
          },
          definiLe: '2026-08-27', definiPar: 'Direction',
          motif: 'Encaisse et délivre. La pharmacie de DÉTAIL lui est rattachée ; le magasin central '
            + 'et les transferts restent au Gestionnaire de Stock — séparation des tâches. Aucun accès '
            + 'clinique (RG-13).',
        },

        /* ====================================================================
         * LE MÉDECIN — il soigne, il ne tient ni la caisse ni le stock
         * ================================================================== */
        {
          id: 'RBAC13', role: 'medecin', libelleOrigine: 'Médecin', statut: 'actif',
          droits: {
            M1: { editer: true, annuler: false },
            M2: { editer: true, annuler: true },
            M3: { editer: true, annuler: true },
            M4: { editer: true, annuler: false },
            M5: { editer: true, annuler: false },
            M6: { editer: false, annuler: false },
          },
          droitsEcrans: {
            /* Il prescrit le médicament, il ne tient pas le stock. */
            'm6-stock-gros': { voir: false },
            'm6-stock-detail': { voir: false },
            'm6-transferts': { voir: false },
            'm6-inventaire': { voir: false },
            'm6-reprise': { voir: false },
            'm6-point-ventes': { voir: false },
            'm6-point-stock': { voir: false },
            /* Le catalogue et les valeurs de référence du laboratoire sont
               tenus par le biologiste : le médecin les LIT. */
            'm5-catalogue': { voir: true, editer: false, annuler: false },
            'm5-unites': { voir: false },
            'm5-valeurs-reference': { voir: true, editer: false, annuler: false },
            'm5-reactifs': { voir: false },
            /* BAGUIDI (02/09/2026) : les modules cliniques sont fermés — le
               médecin garde son tableau de bord et l'EXPRESSION DE BESOINS
               de son service, qui passe par M7 (une surcharge ACCORDE). */
            'm7-besoins': { voir: true, editer: true, annuler: false },
          },
          definiLe: '2026-08-27', definiPar: 'Direction',
          motif: 'Consultations, prescriptions, hospitalisation et lecture des résultats. Il prescrit '
            + 'le médicament, il ne tient pas le stock ; il lit le catalogue d’analyses, il ne le tient pas. '
            + 'Chez BAGUIDI (modules cliniques fermés) : tableau de bord et expression de besoins.',
        },

        /* ====================================================================
         * L'INFIRMIER / SAGE-FEMME — il exécute, il ne prescrit pas au stock
         * ================================================================== */
        {
          id: 'RBAC14', role: 'infirmier', libelleOrigine: 'Infirmier / Sage-femme', statut: 'actif',
          droits: {
            M1: { editer: true, annuler: false },
            M2: { editer: true, annuler: false },
            M3: { editer: true, annuler: true },
            M4: { editer: true, annuler: true },
            /* M5 et M6 ne lui sont pas ouverts par le manifeste : les
               mentionner les lui OUVRIRAIT. Les écrans du laboratoire dont il
               a besoin — demandes, résultats, prélèvement — lui sont donnés
               nommément par leur propre liste `roles`. */
          },
          droitsEcrans: {
            /* Les certificats engagent le médecin : l'infirmier les lit. */
            'm1-pieces': { voir: true, editer: false, annuler: false },
            'm1-numerisation': { voir: false },
            /* BAGUIDI (02/09/2026) : modules cliniques fermés — l'infirmier
               garde son tableau de bord et l'expression de besoins (M7). */
            'm7-besoins': { voir: true, editer: true, annuler: false },
          },
          definiLe: '2026-08-27', definiPar: 'Direction',
          motif: 'Exécute les soins, tient l’hospitalisation et la maternité. Les certificats engagent '
            + 'le médecin : il les lit sans les délivrer. Chez BAGUIDI (modules cliniques fermés) : '
            + 'tableau de bord et expression de besoins.',
        },

        /* ====================================================================
         * LE GESTIONNAIRE DE STOCK — le magasin, pas le dossier ni la caisse
         * ================================================================== */
        {
          id: 'RBAC15', role: 'stock', libelleOrigine: 'Gestionnaire de Stock', statut: 'archive',
          archiveLe: '2026-09-02', motifArchivage: 'Poste sans titulaire chez BAGUIDI (Instructions.txt, 02/09/2026) — rôle archivé, jamais supprimé (RG-14). Réactivable sur décision écrite de la Direction.',
          droits: {
            M6: { editer: true, annuler: true },
            M7: { editer: true, annuler: true },
            M8: { editer: false, annuler: false },
            /* Décision du 02/09/2026 : AUCUN accès au dossier patient — M1
               est ouvert « à tous » au manifeste (roles: '*'), la fermeture
               se pose donc au MODULE : un écran M1 ajouté demain restera
               fermé au magasinier, qui gère des références, pas des
               personnes (RG-13). Le domaine des soins (M2-M5) ne lui est
               pas ouvert par le manifeste — rien à mentionner. */
            M1: { voir: false },
            /* M5 ne lui est pas ouvert par le manifeste ; l'écran des réactifs
               lui vient de sa propre liste `roles`. */
          },
          droitsEcrans: {
            /* Il suit les ventes, il n'encaisse pas. */
            'm8-caisse': { voir: true, editer: false, annuler: false },
            'm8-facturation': { voir: false },
            'm8-paiements': { voir: false },
          },
          definiLe: '2026-08-27', definiPar: 'Direction',
          motif: 'Magasin, achats, réceptions et réactifs. Il SUIT les ventes — ce sont ses sorties — '
            + 'mais il n’encaisse pas : séparation des tâches. Aucun accès au dossier patient ni aux '
            + 'soins (décision du 02/09/2026).',
        },

        /* ====================================================================
         * LA RÉCEPTION — RG-13, aucun accès clinique ni financier
         * ================================================================== */
        {
          id: 'RBAC16', role: 'reception', libelleOrigine: 'Réception / Accueil', statut: 'archive',
          archiveLe: '2026-09-02', motifArchivage: 'Poste sans titulaire chez BAGUIDI (Instructions.txt, 02/09/2026) — rôle archivé, jamais supprimé (RG-14). Réactivable sur décision écrite de la Direction.',
          droits: {
            M1: { editer: true, annuler: false },
            M2: { editer: true, annuler: false },
            M3: { editer: false, annuler: false },
            M13: { editer: false, annuler: false },
          },
          droitsEcrans: {
            /* ZONE 1 — identification, coordonnées, couverture, constantes.
               La zone clinique ne lui est pas ouverte (RG-13), et chacune de
               ses consultations du dossier est journalisée. */
            'm1-dossier-medical': { voir: false },
            'm1-antecedents': { voir: false },
            'm1-dossier-etendu': { voir: true, editer: true, annuler: false },
            'm2-consultation-fiche': { voir: false },
            'm2-prescriptions': { voir: false },
            'm2-ordonnances': { voir: false },
            'm2-salle-soins': { voir: false },
            'm2-imagerie': { voir: false },
            'm2-pathologies': { voir: false },
            /* La sortie d'hospitalisation passe par elle. */
            'm3-sorties': { voir: true, editer: true, annuler: false },
            'm3-visites-patients': { voir: true, editer: true, annuler: false },
            /* LE REGISTRE DU COURRIER EST TENU À L'ACCUEIL — matrice cible
               des Instructions (C, R, U). Le reste de M13 ne s'ouvre pas. */
            'm13-courriers': { voir: true, editer: true, annuler: false },
            /* TARIFS PUBLICS À L'ACCUEIL (phase 3) : l'accueil renseigne le
               patient sur les prix — LECTURE seule, le référentiel se tient en
               configuration. Une surcharge d'écran ACCORDE sans ouvrir le
               module CFG. */
            'cfg-tarifs': { voir: true, editer: false, annuler: false },
            'cfg-catalogue': { voir: true, editer: false, annuler: false },
            'cfg-certificats': { voir: true, editer: false, annuler: false },
          },
          definiLe: '2026-08-27', definiPar: 'Direction',
          motif: 'Zone 1 du dossier — identification, coordonnées, couverture, constantes. La zone '
            + 'clinique ne lui est pas ouverte (RG-13) et chaque consultation du dossier est journalisée. '
            + 'Les tarifs publics lui sont ouverts en lecture (phase 3) : renseigner un prix au guichet.',
        },

        {
          id: 'RBAC01', role: 'laborantin', libelleOrigine: 'Laborantin', statut: 'archive',
          archiveLe: '2026-09-02', motifArchivage: 'Poste sans titulaire chez BAGUIDI (Instructions.txt, 02/09/2026) — rôle archivé, jamais supprimé (RG-14). Réactivable sur décision écrite de la Direction.',
          droits: {
            /* Le module reste ouvert — sinon le laborantin perdrait aussi le
               répertoire, dont il a besoin. C'est l'écran qui décide. */
            M1: { voir: true, editer: false, annuler: false },
          },
          droitsEcrans: {
            /* CE QU'IL LUI FAUT : identifier le patient, et ouvrir la demande
               d'un patient externe qui se présente avec une ordonnance. */
            'm1-patients': { voir: true, editer: false, annuler: false },
            'm1-patient-profil': { voir: true, editer: false, annuler: false },
            'm1-externe': { voir: true, editer: true, annuler: false },

            /* CE QUI EST CLINIQUE — RG-13. */
            'm1-dossier-medical': { voir: false },
            'm1-antecedents': { voir: false },
            'm1-dossier-etendu': { voir: false },
            'm1-pieces': { voir: false },

            /* CE QUI EST LE GESTE D'UN AUTRE POSTE. Les constantes sont
               relevées à l'accueil ; la référence et la contre-référence sont
               des décisions d'évacuation, prises par le clinicien. Le
               laboratoire n'a rien à y faire, ni à les lire. */
            'm1-constantes': { voir: false },
            'm1-reference': { voir: false },
            'm1-contre-reference': { voir: false },

            /* La numérisation et la bibliothèque du dossier. */
            'm1-documents': { voir: false },
            'm1-numerisation': { voir: false },

            /* IL UTILISE LES AUTOMATES, IL NE LES ENTRETIENT PAS. Le parc
               technique lui était ouvert par héritage du module M13 ; c'est
               l'administration qui le tient. */
            'm13-maintenance': { voir: false },

            /* Décision du 02/09/2026 : le BON DE LIVRAISON est le geste du
               MAGASINIER — ni le créer, ni le modifier, ni même l'imprimer
               depuis le laboratoire. L'écran lui est fermé ; il garde les
               bons de commande (suivre l'arrivée de SES réactifs) et les PV
               de réception des réactifs, où il constate. */
            'm7-livraisons': { voir: false },
          },
          /* UNE SEULE FICHE PAR RÔLE : le renommage décidé par la Direction
             le 24/08/2026 est porté ICI et non dans une seconde fiche. Deux
             fiches rendraient la matrice imprévisible — selon l'ordre de
             lecture, c'est l'une ou l'autre qui l'emporterait, et un archivage
             posé par la première serait annulé par le statut de la seconde. */
          libelle: 'Biologiste médical', libelleCourt: 'Biologiste',
          definiLe: '2026-08-24', definiPar: 'Direction',
          motif: 'Le laboratoire consulte l’identité du patient, il ne tient pas son dossier médical. '
            + 'Rôle renommé « Biologiste médical » sur décision de la Direction du 24/08/2026.',
        },

        /* ====================================================================
         * LE COMPTE PHARMACIE EST FERMÉ — LA PHARMACIE PASSE AU CAISSIER
         * --------------------------------------------------------------------
         * « Supprimer » se traduit par ARCHIVER (RG-14) : les comptes cessent
         * d'ouvrir une session, la tentative est journalisée, et les mouvements
         * de stock que ce rôle a signés restent attribuables. Les effacer
         * rendrait anonymes des sorties de stock justifiées.
         *
         * L'archivage va AVEC son transfert : fermer la pharmacie sans l'ouvrir
         * au caissier laisserait le poste sans personne.
         * ================================================================== */
        {
          id: 'RBAC03', role: 'pharmacien', libelleOrigine: 'Pharmacien',
          /* C'est le STATUT de la fiche qui ferme le compte : roleArchive() le
             lit là, et nulle part ailleurs. */
          statut: 'archive',
          definiLe: '2026-08-24', definiPar: 'Direction',
          motif: 'Compte fermé sur décision de la Direction. Ses droits — module M6 en totalité, '
            + 'annulation comprise — sont transférés au compte Caissier (fiche RBAC04). Rien n’est '
            + 'supprimé : la réouverture rendrait le compte en l’état (RG-14).',
          transfereA: 'caissier',
        },
        {
          id: 'RBAC04', role: 'caissier', libelleOrigine: 'Caissier', statut: 'archive',
          archiveLe: '2026-09-02', motifArchivage: 'Poste sans titulaire chez BAGUIDI (Instructions.txt, 02/09/2026) — rôle archivé, jamais supprimé (RG-14). Réactivable sur décision écrite de la Direction.',
          droits: {
            /* LA PHARMACIE EST TRANSFÉRÉE EN ENTIER, droit d'annulation
               compris. Un archivage va toujours avec son transfert : le
               pharmacien pouvait annuler un mouvement, le caissier qui reprend
               sa fonction doit le pouvoir aussi. Transférer à moitié, c'est
               fermer le métier. */
            M6: { voir: true, editer: true, annuler: true },
          },
          definiLe: '2026-08-24', definiPar: 'Direction',
          motif: 'La pharmacie — stock détail, pharmacie d’urgence et mouvements — est rattachée au '
            + 'compte Caissier, avec l’intégralité des droits du compte Pharmacien fermé.',
        },

        /* ====================================================================
         * LE RÔLE RH EST DÉSARCHIVÉ — deux titulaires chez BAGUIDI
         * --------------------------------------------------------------------
         * Chez la clinique d'origine le compte RH avait été fermé et transféré
         * à la DAF ; chez BAGUIDI il a DEUX titulaires (MABOUDOU Nawal,
         * TOUNGOUH A. Zoulkifouli — Instructions.txt, 02/09/2026). Le rôle
         * reprend ses droits : M10 en écriture, M11 en saisie — la VALIDATION
         * de la paie reste le geste de la Direction (m11-validation).
         * ================================================================== */
        {
          id: 'RBAC05', role: 'rh', libelleOrigine: 'Responsable RH',
          statut: 'actif',
          droits: {
            M10: { voir: true, editer: true, annuler: true },
            M11: { voir: true, editer: true, annuler: false },
            GED: { editer: false, annuler: false },
            RAP: { editer: false, annuler: false },
          },
          droitsEcrans: {
            /* La validation de la paie est le geste de la DIRECTION. */
            'm11-validation': { voir: true, editer: false, annuler: false },
            /* L'expression de besoins de son service passe par M7. */
            'm7-besoins': { voir: true, editer: true, annuler: false },
          },
          definiLe: '2026-09-02', definiPar: 'Direction',
          motif: 'Rôle DÉSARCHIVÉ le 02/09/2026 : deux titulaires chez BAGUIDI. Fiches du personnel, '
            + 'plannings, congés et calcul de paie ; la validation de la paie reste à la Direction.',
        },
        /* La Directrice Administrative n'existe pas chez BAGUIDI : le rôle est
           ARCHIVÉ (RG-14), ses attributions reviennent à la Direction (RG-04,
           validations) et au rôle RH (personnel, paie). */
        {
          id: 'RBAC06', role: 'da', libelleOrigine: 'Directrice Administrative',
          statut: 'archive',
          libelle: 'Directrice de l’Administration et des Finances (DAF)', libelleCourt: 'DAF',
          definiLe: '2026-09-02', definiPar: 'Direction',
          motif: 'Poste sans titulaire chez BAGUIDI (Instructions.txt, 02/09/2026). Les validations '
            + 'institutionnelles (RG-04) reviennent à la Direction, le personnel et la paie au rôle '
            + 'RH désarchivé. Rien n’est supprimé : la réouverture rendrait le rôle en l’état.',
          transfereA: 'direction',
        },

        /* ====================================================================
         * QUATRE COMPTES CRÉÉS
         * --------------------------------------------------------------------
         * Chacun part de ZÉRO — aucun module n'est ouvert tant qu'on ne l'écrit
         * pas. M1 et RAP portent `roles: '*'` au manifeste, mais « tous les
         * rôles » a été écrit pour ceux qui existaient alors, pas pour ceux
         * qu'on inventerait : la surcharge ferme donc chaque module nommément
         * avant d'en rouvrir quelques-uns.
         * ================================================================== */
        {
          id: 'RBAC07', role: 'aide_soignant', statut: 'archive', nouveau: true,
          archiveLe: '2026-09-02', motifArchivage: 'Poste sans titulaire chez BAGUIDI (Instructions.txt, 02/09/2026) — rôle archivé, jamais supprimé (RG-14). Réactivable sur décision écrite de la Direction.',
          libelle: 'Aide-soignante', libelleCourt: 'Aide-soign.', couleur: 'success',
          accueil: 'dash-aide-soignant',
          droits: droitsAideSoignant,
          droitsEcrans: {
            /* Aucun résultat d'analyse : la règle métier le dit déjà, l'écran
               le confirme. */
            'm1-dossier-medical': { voir: false },
          },
          definiLe: '2026-08-24', definiPar: 'Direction',
          motif: 'Compte demandé par la Direction — AKONDE Octave, Aide-soignante chef de service.',
        },
        {
          id: 'RBAC08', role: 'echographiste', statut: 'archive', nouveau: true,
          archiveLe: '2026-09-02', motifArchivage: 'Poste sans titulaire chez BAGUIDI (Instructions.txt, 02/09/2026) — rôle archivé, jamais supprimé (RG-14). Réactivable sur décision écrite de la Direction.',
          libelle: 'Technicien d’échographie', libelleCourt: 'Échographie', couleur: 'info',
          accueil: 'dash-echographiste',
          droits: droitsEchographiste,
          droitsEcrans: {
            /* Le dossier patient informatisé en LECTURE SEULE : il consulte
               l'indication, il ne tient pas le dossier. */
            'm1-dossier-medical': { voir: true, editer: false, annuler: false },
            'm1-antecedents': { voir: true, editer: false, annuler: false },
            'm1-patients': { voir: true, editer: false, annuler: false },
            'm1-patient-profil': { voir: true, editer: false, annuler: false },
            /* Il ne modifie pas les prescriptions d'un autre service. */
            'm2-prescriptions': { voir: true, editer: false, annuler: false },
            'm2-consultations': { voir: true, editer: false, annuler: false },
            /* SON écran : le seul de M2 qu'il écrit. Un écran l'emporte sur
               son module, et une surcharge ACCORDE autant qu'elle restreint. */
            'm2-imagerie': { voir: true, editer: true, annuler: true },
            /* Phase 8 — l'imagerie éclatée : son poste de travail. Le module
               M2 ne le liste pas ; ce sont ces surcharges qui ACCORDENT.
               Sur le registre des demandes, il ÉCRIT — exécuter la demande
               et saisir le CR, c'est son métier — mais il n'en OUVRE pas :
               prescrire serait un exercice illégal, et l'écran ferme la
               commande de création à son rôle, nommément. */
            'm2-dashboard-imagerie': { voir: true, editer: true, annuler: false },
            'm2-imagerie-demandes': { voir: true, editer: true, annuler: false },
            'm2-echographie-galerie': { voir: true, editer: true, annuler: true },
            /* Les statistiques de SON activité : PIL lui est fermé au module
               (aucun accès financier), l'écran s'accorde nommément. */
            'm2-stats-echographie': { voir: true, editer: false, annuler: false },

            /* Les écrans de M1 ajoutés depuis, rouverts par héritage du
               module : l'échographiste lit l'indication, il ne tient ni le
               dossier clinique, ni les pièces médico-légales, ni les fiches
               d'évacuation. */
            'm1-dossier-etendu': { voir: false },
            'm1-pieces': { voir: false },
            'm1-constantes': { voir: false },
            'm1-reference': { voir: false },
            'm1-contre-reference': { voir: false },
            'm1-documents': { voir: false },
            'm1-numerisation': { voir: false },
            'm13-maintenance': { voir: false },
            /* Ce qu'il ne doit pas toucher, nommément — un module en lecture
               le couvrirait déjà, mais l'écrire ici le rend vérifiable dans la
               matrice sans avoir à raisonner sur le module. */
            'm2-ordonnances': { voir: false, editer: false, annuler: false },
            'm2-salle-soins': { voir: false, editer: false, annuler: false },
            'm2-pathologies': { voir: false, editer: false, annuler: false },
          },
          definiLe: '2026-08-24', definiPar: 'Direction',
          motif: 'Accès en lecture au dossier et aux consultations ; SEUL l’écran d’imagerie lui est '
            + 'ouvert en écriture. Aucun accès financier : un manipulateur qui verrait la caisse pourrait '
            + 'faire dépendre l’examen du paiement.',
        },
        {
          id: 'RBAC09', role: 'surveillant', statut: 'archive', nouveau: true,
          archiveLe: '2026-09-02', motifArchivage: 'Poste sans titulaire chez BAGUIDI (Instructions.txt, 02/09/2026) — rôle archivé, jamais supprimé (RG-14). Réactivable sur décision écrite de la Direction.',
          libelle: 'Surveillant', libelleCourt: 'Surveillant', couleur: 'navy',
          accueil: 'dash-surveillant',
          droits: droitsSurveillant,
          definiLe: '2026-08-24', definiPar: 'Direction',
          motif: 'Agendas, retards, présences, absences, planning et gardes. Correspond à l’Infirmier Général, '
            + 'dont la description de poste du 26/10/2023 porte déjà ces missions.',
        },
        {
          /* ASSISTANT DE DIRECTION, non « assistant comptable » : la Direction a
             rectifié l'intitulé le 25/08/2026. C'est le poste que décrit la
             seconde description de poste — celle qui s'intitule « Directrice
             Administrative » mais dont le corps décrit son adjoint. Ses droits
             restent ceux de ses 30 activités, qui sont bien comptables. */
          id: 'RBAC10', role: 'assistant_comptable', statut: 'archive', nouveau: true,
          archiveLe: '2026-09-02', motifArchivage: 'Poste sans titulaire chez BAGUIDI (Instructions.txt, 02/09/2026) — rôle archivé, jamais supprimé (RG-14). Réactivable sur décision écrite de la Direction.',
          libelle: 'Assistant de Direction', libelleCourt: 'Assist. Dir.', couleur: 'warning',
          accueil: 'dash-assistant-comptable',
          droits: droitsAssistantComptable,
          definiLe: '2026-08-24', definiPar: 'Direction',
          motif: 'Rattaché à la Direction. Droits repris de la description de poste : livres de compte, '
            + 'rapprochements bancaires, recouvrement des créances, obligations fiscales, point journalier '
            + 'de la caisse, inventaire des médicaments d’urgence et des réactifs.',
        },

        /* ====================================================================
         * LES TROIS RÔLES DE LA PHASE 2 — décidés le 31/08/2026
         * ================================================================== */
        {
          id: 'RBAC17', role: 'chirurgien', statut: 'archive', nouveau: true,
          archiveLe: '2026-09-02', motifArchivage: 'Poste sans titulaire chez BAGUIDI (Instructions.txt, 02/09/2026) — rôle archivé, jamais supprimé (RG-14). Réactivable sur décision écrite de la Direction.',
          libelle: 'Chirurgien', libelleCourt: 'Chirurgien', couleur: 'danger',
          accueil: 'dash-chirurgien',
          droits: droitsChirurgien,
          droitsEcrans: {
            'dash-chirurgien': { voir: true, editer: true, annuler: false },
            /* Même discipline que le médecin sur le stock et le laboratoire :
               il prescrit, il ne tient ni l'un ni l'autre. */
            'm5-catalogue': { voir: true, editer: false, annuler: false },
            'm5-unites': { voir: false },
            'm5-valeurs-reference': { voir: true, editer: false, annuler: false },
            'm5-reactifs': { voir: false },
            /* L'imagerie s'écrit par l'échographiste ; le chirurgien la LIT. */
            'm2-imagerie': { voir: true, editer: false, annuler: false },
          },
          definiLe: '2026-08-31', definiPar: 'Direction',
          motif: 'Base médecin + bloc opératoire (CRO, check-listes, transfusion, surveillance), '
            + 'MATERNITÉ FERMÉE — matrice cible des Instructions. Aucune suppression : un compte '
            + 'rendu opératoire est la pièce qu’on ressort quand une suite est contestée.',
        },
        {
          id: 'RBAC18', role: 'anesthesiste', statut: 'archive', nouveau: true,
          archiveLe: '2026-09-02', motifArchivage: 'Poste sans titulaire chez BAGUIDI (Instructions.txt, 02/09/2026) — rôle archivé, jamais supprimé (RG-14). Réactivable sur décision écrite de la Direction.',
          libelle: 'Anesthésiste — Réanimateur', libelleCourt: 'Anesthésiste', couleur: 'info',
          accueil: 'dash-anesthesiste',
          droits: droitsAnesthesiste,
          droitsEcrans: {
            'dash-anesthesiste': { voir: true, editer: true, annuler: false },
            /* Les constantes se saisissent — c'est son matériau de travail. */
            'm1-constantes': { voir: true, editer: true, annuler: false },
            'm5-catalogue': { voir: true, editer: false, annuler: false },
            'm5-unites': { voir: false },
            'm5-reactifs': { voir: false },
          },
          definiLe: '2026-08-31', definiPar: 'Direction',
          motif: 'Péri-opératoire : check-listes du bloc, Glasgow, transfusion, surveillance, soins. '
            + 'Résultats de laboratoire en lecture. Ni maternité, ni caisse, ni consultations '
            + 'générales. La CPA et la feuille d’anesthésie (phase 6) hériteront de M3.',
        },
        {
          /* LE 16ᵉ RÔLE — créé par l'arbitrage du 31/08/2026, DISTINCT de
             l'Assistant de Direction (rôle technique `assistant_comptable`,
             conservé tel quel : renommer un identifiant technique romprait
             listes, surcharges et comptes — la doctrine posée pour
             « laborantin »). L'identifiant technique est `aide_comptable` ;
             le LIBELLÉ, celui que l'agent lit, est « Assistant Comptable ». */
          id: 'RBAC19', role: 'aide_comptable', statut: 'archive', nouveau: true,
          archiveLe: '2026-09-02', motifArchivage: 'Poste sans titulaire chez BAGUIDI (Instructions.txt, 02/09/2026) — rôle archivé, jamais supprimé (RG-14). Réactivable sur décision écrite de la Direction.',
          libelle: 'Assistant Comptable', libelleCourt: 'Assist. Compta', couleur: 'warning',
          accueil: 'dash-aide-comptable',
          droits: droitsAideComptable,
          droitsEcrans: {
            'dash-aide-comptable': { voir: true, editer: true, annuler: false },
            /* LA CLÔTURE ENGAGE L'EXERCICE : réservée au Comptable principal
               et à la DAF — fermée nommément, matrice cible des Instructions. */
            'm12-cloture': { voir: false, editer: false, annuler: false },
            /* Il saisit dépenses et écritures ; les états de synthèse et le
               paramétrage restent en lecture par le module. */
            'm12-depenses': { voir: true, editer: true, annuler: false },
            'm12-ecritures': { voir: true, editer: true, annuler: false },
          },
          definiLe: '2026-08-31', definiPar: 'Direction',
          motif: 'Saisie financière sans pouvoir d’annulation : dépenses courantes, écritures, '
            + 'réceptions fournisseurs, suivi des créances. Aucun accès clinique (RG-13), '
            + 'clôture annuelle fermée. D = interdit sur toute la matrice — l’annulation '
            + 'appartient au Comptable principal et à la DAF.',
        },
        /* ====================================================================
         * VAGUE 53 (02/09/2026) — LES CINQ FICHES QUI MANQUAIENT
         * --------------------------------------------------------------------
         * Un rôle sans fiche a TOUS les droits sur ce que le manifeste lui
         * ouvre — l'inventaire montrait le comptable en édition/annulation
         * sur le dossier médical. Chaque fiche ne mentionne QUE les modules
         * que le manifeste ouvre au rôle (les mentionner ACCORDE) ; seul
         * l'administrateur système reste sans fiche — son poste EST
         * l'accès complet, et c'est assumé.
         * ================================================================== */
        {
          id: 'RBAC20', role: 'dm', libelleOrigine: 'Directeur Médical', statut: 'archive',
          archiveLe: '2026-09-02', motifArchivage: 'Poste sans titulaire chez BAGUIDI (Instructions.txt, 02/09/2026) — rôle archivé, jamais supprimé (RG-14). Réactivable sur décision écrite de la Direction.',
          droits: {
            M1: { editer: true, annuler: false },
            M2: { editer: true, annuler: true },
            M3: { editer: true, annuler: true },
            M4: { editer: true, annuler: false },
            M5: { editer: true, annuler: false },
            /* Il DIRIGE le médical : le stock et la caisse se lisent, ils ne
               se tiennent pas depuis son bureau (accès caisse en lecture —
               décision du 26/08/2026). */
            M6: { editer: false, annuler: false },
            M8: { editer: false, annuler: false },
            M13: { editer: true, annuler: false },
            RAP: { editer: true, annuler: false },
            /* PIL ne se déclare pas : le pilotage est fait de STATISTIQUES,
               qui n'ont rien à modifier — le déclarer en lecture créerait un
               état « lecture seule » sans objet, que l'audit relèverait. */
          },
          droitsEcrans: {
            'm6-stock-gros': { voir: false },
            'm6-transferts': { voir: false },
            'm6-reprise': { voir: false },
          },
          definiLe: '2026-09-02', definiPar: 'Direction',
          motif: 'Direction médicale : écrit le clinique (M1-M5), lit le stock et la caisse, ne les '
            + 'tient pas. L’annulation clinique reste possible en consultation et hospitalisation.',
        },
        {
          id: 'RBAC21', role: 'direction', libelleOrigine: 'Direction / Gérance', statut: 'actif',
          droits: {
            /* La Direction DÉCIDE et LIT ; elle ne saisit ni actes, ni
               caisse, ni stock, ni paie — ses gestes propres sont
               l'institutionnel : administration, sécurité, configuration,
               documentaire, et la validation de la paie (écran nommé). */
            M1: { editer: false, annuler: false },
            M2: { editer: false, annuler: false },
            M3: { editer: false, annuler: false },
            M4: { editer: false, annuler: false },
            M5: { editer: false, annuler: false },
            M6: { editer: false, annuler: false },
            M7: { editer: false, annuler: false },
            M8: { editer: false, annuler: false },
            M9: { editer: false, annuler: false },
            M10: { editer: false, annuler: false },
            M11: { editer: false, annuler: false },
            M12: { editer: false, annuler: false },
            MECEF: { editer: false, annuler: false },
            M13: { editer: true, annuler: true },
            M14: { editer: true, annuler: true },
            CFG: { editer: true, annuler: false },
            GED: { editer: true, annuler: false },
            RAP: { editer: true, annuler: false },
            /* PIL ne se déclare pas : le pilotage est fait de STATISTIQUES,
               qui n'ont rien à modifier — le déclarer en lecture créerait un
               état « lecture seule » sans objet, que l'audit relèverait. */
          },
          droitsEcrans: {
            /* LA VALIDATION DE LA PAIE EST SON GESTE — l'écran s'accorde
               nommément, le module M11 restant en lecture. */
            'm11-validation': { voir: true, editer: true, annuler: false },
            /* BAGUIDI : la Directrice Administrative n'existe pas — la
               VALIDATION RG-04 des bons et commandes revient à la DIRECTION.
               Écran par écran : signer n'est pas tenir le stock. */
            'm7-besoins': { voir: true, editer: true, annuler: false },
            'm7-commandes': { voir: true, editer: true, annuler: false },
          },
          definiLe: '2026-09-02', definiPar: 'Direction',
          motif: 'La Direction lit tout et décide : administration, sécurité, configuration, '
            + 'documentaire, validation de la paie et validation RG-04 des bons et commandes '
            + '(la DA n’existe pas chez BAGUIDI). Elle ne saisit ni actes ni caisse — signer '
            + 'n’est pas saisir.',
        },
        {
          id: 'RBAC22', role: 'comptable', libelleOrigine: 'Comptable', statut: 'actif',
          droits: {
            M12: { editer: true, annuler: true },
            /* L'avoir est SON canal de correction (phase 5). */
            M8: { editer: true, annuler: true },
            M9: { editer: true, annuler: false },
            MECEF: { editer: true, annuler: false },
            M11: { editer: true, annuler: false },
            /* BAGUIDI (02/09/2026) : AUCUN gestionnaire de stock n'est nommé
               — la liste des huit comptes fait foi et un rôle de plus ne
               s'ajoute que sur décision écrite. En attendant cette décision,
               la TENUE du stock et des achats revient au COMPTABLE (les
               validations RG-04 restant à la Direction : la séparation des
               tâches passe par la signature, faute d'un second poste). */
            M7: { editer: true, annuler: false },
            M6: { editer: true, annuler: false },
            M13: { editer: false, annuler: false },
            GED: { editer: true, annuler: false },
            RAP: { editer: true, annuler: false },
            /* PIL ne se déclare pas : le pilotage est fait de STATISTIQUES,
               qui n'ont rien à modifier — le déclarer en lecture créerait un
               état « lecture seule » sans objet, que l'audit relèverait. */
            M1: { editer: false, annuler: false },
          },
          droitsEcrans: {
            /* Identifier un patient pour une pièce, jamais lire son dossier. */
            'm1-patients': { voir: true, editer: false, annuler: false },
            'm1-patient-profil': { voir: true, editer: false, annuler: false },
            'm1-dossier-medical': { voir: false },
            'm1-antecedents': { voir: false },
            'm1-dossier-etendu': { voir: false },
            'm1-constantes': { voir: false },
            'm1-reference': { voir: false },
            'm1-contre-reference': { voir: false },
            'm1-documents': { voir: false },
            'm1-numerisation': { voir: false },
            'm1-pieces': { voir: false },
            /* La facture fournisseur est une pièce COMPTABLE. */
            'm7-factures-fournisseurs': { voir: true, editer: true, annuler: false },
            /* La configuration fiscale engage la clinique devant la DGI :
               elle se décide, elle ne se retouche pas au fil des saisies. */
            'mecef-config': { voir: true, editer: false, annuler: false },
          },
          definiLe: '2026-09-02', definiPar: 'Direction',
          motif: 'La comptabilité, la caisse (avoirs compris), les créances, la paie et le fiscal. '
            + 'Les achats et le stock se lisent ; la facture fournisseur s’y saisit car c’est une '
            + 'pièce comptable. Aucun accès clinique (RG-13).',
        },
        {
          id: 'RBAC23', role: 'agentadmin', libelleOrigine: 'Agent Administratif', statut: 'archive',
          archiveLe: '2026-09-02', motifArchivage: 'Poste sans titulaire chez BAGUIDI (Instructions.txt, 02/09/2026) — rôle archivé, jamais supprimé (RG-14). Réactivable sur décision écrite de la Direction.',
          droits: {
            M13: { editer: true, annuler: true },
            GED: { editer: true, annuler: false },
            RAP: { editer: true, annuler: false },
            M1: { editer: false, annuler: false },
          },
          droitsEcrans: {
            'm1-patients': { voir: true, editer: false, annuler: false },
            'm1-patient-profil': { voir: true, editer: false, annuler: false },
            'm1-dossier-medical': { voir: false },
            'm1-antecedents': { voir: false },
            'm1-dossier-etendu': { voir: false },
            'm1-constantes': { voir: false },
            'm1-reference': { voir: false },
            'm1-contre-reference': { voir: false },
            'm1-documents': { voir: false },
            'm1-numerisation': { voir: false },
            'm1-pieces': { voir: false },
            'm1-certificats-externes': { voir: false },
          },
          definiLe: '2026-09-02', definiPar: 'Direction',
          motif: 'Courriers, réunions, événements, ambulance, documentaire et états — le secrétariat '
            + 'de l’établissement. Il identifie un patient pour un courrier, il ne lit pas son '
            + 'dossier (RG-13).',
        },
        {
          id: 'RBAC24', role: 'ambulancier', libelleOrigine: 'Ambulancier', statut: 'archive',
          archiveLe: '2026-09-02', motifArchivage: 'Poste sans titulaire chez BAGUIDI (Instructions.txt, 02/09/2026) — rôle archivé, jamais supprimé (RG-14). Réactivable sur décision écrite de la Direction.',
          droits: {
            M13: { editer: true, annuler: false },
            RAP: { editer: false, annuler: false },
            M1: { editer: false, annuler: false },
          },
          droitsEcrans: {
            /* SON poste : les interventions et le répertoire d'urgence. Le
               reste de M13 est le secrétariat — fermé NOMMÉMENT, pour que la
               matrice se vérifie sans raisonner sur le module. */
            'm13-ambulance': { voir: true, editer: true, annuler: false },
            'm13-repertoire-ambulances': { voir: true, editer: false, annuler: false },
            'm13-courriers': { voir: false },
            'm13-reunions': { voir: false },
            'm13-evenements': { voir: false },
            'm13-plan-annuel': { voir: false },
            'm13-notes-service': { voir: false },
            'm13-maintenance': { voir: false },
            'adm-validations': { voir: false },
            'adm-enquetes': { voir: false },
            'adm-satisfaction': { voir: false },
            /* Identifier le patient transporté, rien de plus. */
            'm1-patients': { voir: true, editer: false, annuler: false },
            'm1-patient-profil': { voir: false },
            'm1-dossier-medical': { voir: false },
            'm1-antecedents': { voir: false },
            'm1-dossier-etendu': { voir: false },
            'm1-constantes': { voir: false },
            'm1-reference': { voir: false },
            'm1-contre-reference': { voir: false },
            'm1-documents': { voir: false },
            'm1-numerisation': { voir: false },
            'm1-pieces': { voir: false },
            'm1-certificats-externes': { voir: false },
            'm1-externe': { voir: false },
            'm1-assures': { voir: false },
          },
          definiLe: '2026-09-02', definiPar: 'Direction',
          motif: 'Les interventions d’ambulance et le répertoire d’urgence — rien du secrétariat, '
            + 'rien du dossier au-delà de l’identité du patient transporté.',
        },
        {
          /* ARCHIVÉ : le poste n'existe pas. Le rôle est conservé — un rôle
             s'archive, il ne se supprime jamais (RG-14), et des fiches de
             maintenance portent sa signature — mais il n'ouvre plus de
             session. Ses droits sur le parc technique passent à l'agent
             administratif : un archivage va toujours avec son transfert. */
          id: 'RBAC11', role: 'biomedical', statut: 'archive', nouveau: true,
          transfereA: 'agentadmin',
          libelle: 'Ingénieur biomédical', libelleCourt: 'Ing. biomed.', couleur: 'info',
          accueil: 'dash-biomedical',
          droits: droitsBiomedical,
          droitsEcrans: {
            /* Il voit les demandes et l'activité des automates, jamais les
               RÉSULTATS : un résultat n'est opposable qu'après validation
               biologique, et cette validation n'est pas la sienne. */
            'm5-resultats': { voir: false },
          },
          definiLe: '2026-08-25', definiPar: 'Direction',
          motif: 'Rôle créé le 25/08/2026 puis laissé SANS TITULAIRE le 26/08 : la Direction a '
            + 'confirmé que KINNOU A. Ganiou reste au laboratoire comme biologiste médical chef de '
            + 'service. Le rôle subsiste — la clinique pourra le pourvoir — mais personne ne le porte.',
          sansTitulaire: true,
        },
      ],
      /* Emplacements de rangement — rayons et casiers. Amorcés depuis ce que
         les produits portent déjà : le référentiel ne part pas de zéro, il
         régularise l'existant. Lu par le référentiel produits ET par
         l'étiquetage, donc amorcé ici. */
      emplacements: (function () {
        var vus = {}, out = [];
        produits.forEach(function (p) {
          var e = (p.emplacement || '').trim();
          if (!e || vus[e]) return;
          vus[e] = true;
          out.push({
            id: 'EMP' + C.pad(out.length + 1, 3),
            code: e, libelle: e,
            zone: /frigo|froid|2.*8/i.test(e) ? 'Chaîne du froid' : 'Rayonnage sec',
            temperature: /frigo|froid|2.*8/i.test(e) ? '2 à 8 °C' : 'Ambiante',
            capacite: null, statut: 'actif',
            source: 'Repris des emplacements saisis sur les fiches produits',
          });
        });
        return out;
      })(),
      /* Barème d'évaluation NS 131 — VIDÉ chez BAGUIDI : le barème venait de
         la note de service NS 131 de la clinique d'origine, et aucune note
         d'évaluation BAGUIDI n'a été fournie. Les écrans d'évaluation sont
         fermés par `modulesActifs` (fiche MOD-CBG-NS131), la bascule
         `baremeModifiable` reste fermée, et la paie calcule SANS rubrique de
         sanction (lignes conditionnelles à null, filtrées au bulletin).
         La semence D.NS131 reste dans data.js : elle documente ce que le
         prototype d'origine portait — rien n'est supprimé. */
      baremeNS131: [],
      historiqueBareme: [],
      /* Notifications de poste — amorcées vides, alimentées par le parcours. */
      notifications: [],
      modulesActifs: [
        /* ================================================================
         * DEUX POSTES QUI N'EXISTENT PAS — fermés le 27/08/2026
         * ----------------------------------------------------------------
         * L'INGÉNIEUR BIOMÉDICAL n'existe pas à la clinique : le rôle avait
         * été créé sur une lecture erronée de la liste des comptes, et la
         * Direction a rectifié — KINNOU A. Ganiou est biologiste médical.
         * Le PARC TECHNIQUE reste ouvert : c'est un besoin réel, tenu par
         * l'administration.
         *
         * LE PHARMACIEN est un compte archivé depuis le 24/08/2026 : la
         * pharmacie est tenue par la Caissière-Dispensatrice. Son tableau de
         * bord n'a plus de titulaire.
         *
         * Rien n'est supprimé : rouvrir l'activité rend les écrans en l'état.
         * ============================================================== */
        { id: 'ACT-BIOMED', statut: 'actif', actif: false,
          libelle: 'Poste d’ingénieur biomédical',
          ecrans: ['dash-biomedical'],
          motif: 'Poste inexistant à la clinique. Le rôle avait été créé sur une lecture erronée de '
            + 'la liste des comptes ; la Direction a rectifié le 27/08/2026 — l’agent concerné est '
            + 'biologiste médical. Le parc technique reste ouvert, tenu par l’administration.',
          fermeLe: '2026-08-27', fermePar: 'Direction' },

        {
          id: 'MOD01', code: 'M5-BANQUE', libelle: 'Banque de sang', module: 'M5',
          ecrans: ['m5-banque-sang'], actif: false,
          motif: 'La clinique ne pratique pas la banque de sang.',
          fermeLe: '2026-08-21', fermePar: 'Direction',
        },
        {
          id: 'MOD02', code: 'M5-DONNEURS', libelle: 'Donneurs & transfusions', module: 'M5',
          ecrans: ['m5-donneurs'], actif: false,
          motif: 'La clinique ne pratique pas la transfusion.',
          fermeLe: '2026-08-21', fermePar: 'Direction',
        },

        /* ================================================================
         * PÉRIMÈTRE BAGUIDI — décision de la Direction du 02/09/2026
         * ----------------------------------------------------------------
         * Le prototype SIGH-CBG n'exploite pour l'instant que les stocks
         * (M6), les achats et expressions de besoins (M7 — y compris les
         * demandes de besoins du laboratoire et des services), les RH (M10),
         * la paie (M11), la comptabilité (M12), l'administration (M13), le
         * pilotage, les tableaux de bord et la configuration.
         *
         * Les modules CLINIQUES sont fermés AU MODULE (une fiche sans liste
         * d'écrans ferme le module entier — mécanisme de la vague 50) :
         * rien n'est supprimé, la réactivation depuis cfg-modules rend tout
         * en l'état. Cette liste découle d'Instructions.txt et ne se
         * rediscute que sur une nouvelle décision écrite de la Direction.
         * ============================================================== */
        { id: 'MOD-CBG-M1', module: 'M1', libelle: 'Patients & Dossier médical', actif: false,
          motif: 'Hors périmètre BAGUIDI pour l’instant (Instructions.txt, Direction 02/09/2026).',
          fermeLe: '2026-09-02', fermePar: 'Direction' },
        { id: 'MOD-CBG-M2', module: 'M2', libelle: 'RDV, Visites & Consultations', actif: false,
          motif: 'Hors périmètre BAGUIDI pour l’instant (Instructions.txt, Direction 02/09/2026).',
          fermeLe: '2026-09-02', fermePar: 'Direction' },
        { id: 'MOD-CBG-M3', module: 'M3', libelle: 'Hospitalisation', actif: false,
          motif: 'Hors périmètre BAGUIDI pour l’instant (Instructions.txt, Direction 02/09/2026).',
          fermeLe: '2026-09-02', fermePar: 'Direction' },
        { id: 'MOD-CBG-M4', module: 'M4', libelle: 'Maternité, Naissances & Décès', actif: false,
          motif: 'Hors périmètre BAGUIDI pour l’instant (Instructions.txt, Direction 02/09/2026).',
          fermeLe: '2026-09-02', fermePar: 'Direction' },
        { id: 'MOD-CBG-M5', module: 'M5', libelle: 'Laboratoire clinique', actif: false,
          motif: 'Le laboratoire clinique est hors périmètre : les BESOINS du laboratoire passent '
            + 'par les expressions de besoins M7 (Instructions.txt, Direction 02/09/2026).',
          fermeLe: '2026-09-02', fermePar: 'Direction' },
        { id: 'MOD-CBG-M8', module: 'M8', libelle: 'Facturation & Caisse', actif: false,
          motif: 'Hors périmètre BAGUIDI pour l’instant (Instructions.txt, Direction 02/09/2026).',
          fermeLe: '2026-09-02', fermePar: 'Direction' },
        { id: 'MOD-CBG-M9', module: 'M9', libelle: 'Assurances & Créances', actif: false,
          motif: 'Hors périmètre BAGUIDI pour l’instant (Instructions.txt, Direction 02/09/2026).',
          fermeLe: '2026-09-02', fermePar: 'Direction' },
        { id: 'MOD-CBG-MECEF', module: 'MECEF', libelle: 'MECeF — Facture normalisée', actif: false,
          motif: 'Hors périmètre BAGUIDI pour l’instant — pas de caisse, donc pas de facture '
            + 'normalisée (Instructions.txt, Direction 02/09/2026).',
          fermeLe: '2026-09-02', fermePar: 'Direction' },

        /* LA DISPENSATION AU PATIENT EST FERMÉE (Direction, 03-04/09/2026).
           Les deux officines — pharmacie interne (urgences, produits qui
           partent vers la salle de soins) et pharmacie externe (voie orale
           que le patient emporte) — délivrent SUR ORDONNANCE, après passage
           en caisse : leur amont (M2 ordonnances, M8 caisse) est fermé, une
           officine sans prescription ni encaissement ne servirait à rien.
           Le REGISTRE des délivrances (`m6-dispensation`) suit le 04/09 : il
           n'enregistre aucun geste propre — toute délivrance y naît d'une
           ordonnance encaissée (RG-03, justificatif = n° d'ordonnance) — donc
           sans amont il ne montrerait qu'une liste vide.
           Le STOCK reste entier — magasin, transferts, lots FEFO, alertes,
           inventaires, pertes, valorisation : c'est le cœur du périmètre
           BAGUIDI. Fermeture par le canal des ÉCRANS, jamais du module. */
        { id: 'MOD-CBG-OFFICINE', code: 'M6-OFFICINE', module: 'M6',
          libelle: 'Officines et registre des délivrances',
          ecrans: ['m6-pharmacie-interne', 'm6-pharmacie-externe', 'm6-dispensation'], actif: false,
          motif: 'La dispensation naît d’une ordonnance réglée en caisse ; les modules cliniques et '
            + 'la caisse sont hors périmètre BAGUIDI. Le stock, lui, reste ouvert en entier. '
            + 'Décision de la Direction des 03 et 04/09/2026 — réactivable avec son amont.',
          fermeLe: '2026-09-03', fermePar: 'Direction' },

        /* Les STATISTIQUES d'activités cliniques (rangées PIL) suivent leur
           activité : fermées par le canal des écrans tant que le clinique
           l'est — un écran de statistiques qui ne compterait que des zéros
           n'informe personne. La statistique des examens de laboratoire
           reste DANS ce lot : seuls les BESOINS du labo passent par M7. */
        { id: 'MOD-CBG-STATS', code: 'PIL-CLINIQUE', libelle: 'Statistiques des activités cliniques',
          ecrans: ['m4-stats-maternite', 'm2-stats-echographie', 'm5-stats-examens',
            'm2-stats-consultations', 'm3-stats-bloc', 'm5-reactifs-stats'],
          actif: false,
          motif: 'Statistiques d’activités cliniques hors périmètre BAGUIDI (Instructions.txt, '
            + 'Direction 02/09/2026) — rouvertes avec leur activité.',
          fermeLe: '2026-09-02', fermePar: 'Direction' },

        /* LES PRIMES SONT DÉSACTIVÉES (Direction, 07/09/2026) : l'écran de la
           grille est fermé au canal des écrans, la grille seedée est VIDE et
           les bulletins se calculent sans prime. Le moteur reste en place —
           rouvrir le dispositif ne demandera qu'une décision écrite et la
           saisie de la grille. */
        { id: 'MOD-CBG-PRIMES', code: 'M10-PRIMES', module: 'M10',
          libelle: 'Primes (NS 132)',
          ecrans: ['m10-primes'], actif: false,
          motif: 'Aucune note de service de primes BAGUIDI n’a été fournie et la clinique n’en verse '
            + 'pas pour l’instant — décision de la Direction du 07/09/2026. Le moteur est conservé : '
            + 'la réouverture rend l’écran en l’état.',
          fermeLe: '2026-09-07', fermePar: 'Direction' },

        /* Barème d'évaluation NS 131 : DÉSACTIVÉ chez BAGUIDI — les écrans
           d'évaluation et de sanctions sont fermés par le CANAL DES ÉCRANS
           (le reste de M10 travaille), la bascule baremeModifiable reste
           fermée et le barème seedé est VIDÉ. La paie M11 calcule SANS
           rubrique de sanction — les lignes conditionnelles à null sont
           filtrées, la sonde du test fonctionnel le vérifie. */
        { id: 'MOD-CBG-NS131', code: 'M10-NS131', module: 'M10',
          libelle: 'Évaluations & sanctions (barème NS 131)',
          ecrans: ['m10-evaluations', 'm10-sanctions'], actif: false,
          motif: 'Le barème d’évaluation NS 131 est propre à la clinique d’origine du prototype. '
            + 'Aucune note de service d’évaluation BAGUIDI n’a été fournie — désactivé sur '
            + 'décision de la Direction du 02/09/2026.',
          fermeLe: '2026-09-02', fermePar: 'Direction' },
      ],
      /* --- Paramétrage du laboratoire ---------------------------------------
         Trois collections lues par plusieurs écrans, donc amorcées ici :
         le catalogue du bulletin, les unités et les variables de résultat.
         Le biologiste doit pouvoir les corriger — « en fonction des réactifs
         les valeurs peuvent changer » — d'où leur passage par le magasin. */
      /* Pathologies — lues par la consultation, le dossier patient et les
         statistiques de morbidité, donc amorcées ici. */
      /* VALIDATIONS ÉCRITES DU 01/09/2026 (vague 51) — les professionnels
         nommés ont tranché : les pathologies par les médecins (tableau de
         morbidité), les bornes suppléées par le biologiste médical. La
         SEMENCE (D.PATHOLOGIES, L.VARIABLES) garde son marquage : elle
         documente ce qui venait d'un document et ce qui a été suppléé. */
      pathologies: D.PATHOLOGIES.map(function (x) {
        var rec = Object.assign({}, x);
        if (rec.aValider) {
          rec.aValider = false;
          rec.valideLe = '2026-09-01';
          rec.validePar = 'Médecins — tableau de morbidité';
        }
        return rec;
      }),
      examensLabo: L.EXAMENS.map(function (e) { return Object.assign({}, e); }),
      unitesLabo: L.UNITES.map(function (u, i) {
        return Object.assign({ id: 'UNI' + C.pad(i + 1, 2), statut: 'actif' }, u);
      }),
      variablesLabo: L.VARIABLES.map(function (v) {
        var rec = Object.assign({}, v);
        if (rec.aValider) {
          rec.aValider = false;
          rec.valideLe = '2026-09-01';
          rec.validePar = 'Biologiste médical';
          rec.source = 'Valeur usuelle, validée par le biologiste médical le 01/09/2026';
        }
        return rec;
      }),
      /* --- Paramétrage de l'IMAGERIE (phase 8) ------------------------------
         Le catalogue et les variables quittent le code pour le magasin — la
         doctrine du laboratoire, appliquée à l'imagerie : l'échographiste
         doit pouvoir corriger ses listes sans toucher au code. Lu par les
         écrans M2 ET par cfg-imagerie-catalogue (module CFG), donc au socle.
         D.IMAGERIE n'est que la semence. */
      examensImagerie: ((D.IMAGERIE && D.IMAGERIE.EXAMENS) || []).map(function (e, i) {
        return Object.assign({ id: 'EXI' + C.pad(i + 1, 2), statut: 'actif' }, e);
      }),
      variablesImagerie: ((D.IMAGERIE && D.IMAGERIE.VARIABLES) || []).map(function (v, i) {
        return Object.assign({ id: 'VIM' + C.pad(i + 1, 3), statut: 'actif', actif: true }, v);
      }),
      /* Les demandes d'imagerie (mêmes états que le labo : demandée → payée →
         exécutée → validée) et la galerie de clichés — remplies par le
         parcours et par le poste, jamais pré-inventées. */
      demandesImagerie: [],
      clichesImagerie: [],
      /* Événements du personnel et participations — amorcés par leur écran
         (un seul les crée), mais LUS par la paie : la collection doit exister.  */
      evenements: [],
      /* Les événements de l'ÉTABLISSEMENT — distincts de ceux du PERSONNEL.
         Les deux partageaient une seule collection, ce que le peuplement a
         révélé en mêlant les mariages d'agents aux journées portes ouvertes. */
      evenementsEtablissement: [],
      participations: [],
      /* Régimes de travail par catégorie — lus par le planning ET par les
         statistiques de garde, donc amorcés ici et non par un écran. */
      /* Le registre des présences — amorcé ICI et non par son écran : trois
         écrans le lisent (registre, statistiques, tableau du Surveillant), et
         une page ne charge que le module de son écran. */
      presences: genPresences(rnd, personnel),

      regimesTravail: D.REGLES_PLANNING.map(function (r, i) {
        return Object.assign({ id: 'REG' + C.pad(i + 1, 2), statut: 'actif' }, r, {
          fonctions: r.fonctions.slice(), vacations: r.vacations.slice(),
        });
      }),
      comptes: D.PLAN_COMPTABLE.map(function (c, i) {
        return Object.assign({ id: 'CPT' + C.pad(i + 1, 3), statut: 'actif' }, c);
      }),
    };
  }

  /* --------------------------------------------------------------------------
   * PERSONNEL SOIGNÉ SUR PLACE
   * --------------------------------------------------------------------------
   * La clinique prend ses agents en charge à 100 %. Encore faut-il savoir, au
   * guichet, que le patient est un agent : c'est ce que porte `personnelId`.
   *
   * Le rattachement ne se devine pas d'un nom — deux personnes peuvent le
   * partager, et un agent peut être enregistré sous un nom d'usage. On crée
   * donc un DOSSIER PATIENT explicite pour une partie du personnel, portant
   * son matricule. C'est ce que fait l'accueil dans la réalité.
   * ----------------------------------------------------------------------- */
  function rattacherPersonnelPatients(rnd, patients, personnel) {
    var eligibles = personnel.slice(0, 18);
    eligibles.forEach(function (e, i) {
      var morceaux = String(e.nomComplet).split(' ');
      var nom = morceaux[0];
      var prenom = morceaux.slice(1).join(' ') || nom;
      patients.push({
        id: 'PAT-AG' + C.pad(i + 1, 3),
        code: C.BRAND.sigle + '/' + (900 + i) + '/25',
        nom: nom, prenom: prenom,
        sexe: e.sexe || (i % 2 ? 'F' : 'M'),
        dateNaissance: e.dateNaissance || '1988-01-01',
        telephone: e.telephone || null,
        adresse: 'Parakou',
        statut: 'actif',
        /* Le lien qui vaut prise en charge. */
        personnelId: e.id, matricule: e.matricule, fonctionAgent: e.fonction,
        assure: false, souscripteurId: null,
        priseEnChargePersonnel: true,
        dateCreation: C.iso(C.addDays(new Date(2026, 7, 16), -C.between(rnd, 200, 900))),
      });
    });
  }

  /* --------------------------------------------------------------------------
   * SOUSCRIPTEURS — le niveau intermédiaire que les pièces réelles imposent
   * --------------------------------------------------------------------------
   * Le relevé mensuel de la clinique et la facture récapitulative sont organisés
   * « par souscripteur, avec n° de police », sous une même compagnie : PIB Bénin
   * et GIZ Bénin sous Africaine des Assurances, par exemple. C'est le contrat de
   * l'employeur — et non la compagnie — qui porte la grille de garanties.
   * ----------------------------------------------------------------------- */
  var EMPLOYEURS = [
    ['PIB Bénin', 'entreprise'], ['GIZ Bénin', 'entreprise'], ['SBEE', 'entreprise'],
    ['SONEB', 'entreprise'], ['Mairie de Parakou', 'entreprise'],
    ['CNSS Borgou', 'entreprise'], ['Université de Parakou', 'entreprise'],
    ['Souscripteurs particuliers', 'particulier'],
    ['Personnel de la clinique', 'personnel'],
  ];

  function genSouscripteurs(rnd) {
    var out = [];
    EMPLOYEURS.forEach(function (e, i) {
      var comp = D.ASSUREURS[i % D.ASSUREURS.length];
      out.push({
        id: 'SOU' + C.pad(i + 1, 3), statut: 'actif',
        nom: e[0], categorie: e[1],
        assureur: comp.code, assureurNom: comp.nom,
        police: comp.code + '/' + (2024 + (i % 3)) + '/' + C.pad(100 + i, 4),
        effectif: e[1] === 'particulier' ? null : C.between(rnd, 12, 240),
        contact: e[1] === 'entreprise' ? 'Chef Service Santé au Travail' : null,
        dateDebut: C.iso(new Date(2024 + (i % 3), C.between(rnd, 0, 11), 1)),
        dateFin: null,
        /* Aucune grille n'est présumée : tant que la convention n'est pas
           saisie, la facturation reste intégralement à la charge du patient
           et le dit. Les barèmes des compagnies restent à collecter. */
        grilleSaisie: false,
        actesExclus: [], produitsExclus: [], accordPrealable: [],
        source: 'Relevé des prestations et facture mensuelle par souscripteur',
      });
    });
    return out;
  }

  /* Un assuré appartient à un souscripteur de sa compagnie. */
  function rattacherSouscripteurs(rnd, patients, souscripteurs) {
    patients.forEach(function (p) {
      if (!p.assureur) return;
      var possibles = souscripteurs.filter(function (s) { return s.assureur === p.assureur; });
      var s = possibles.length ? C.pick(rnd, possibles) : C.pick(rnd, souscripteurs);
      p.souscripteurId = s.id;
      p.souscripteur = s.nom;
      p.numeroPolice = s.police;
      p.categorieAssurance = s.categorie;
    });
  }

  /* ==========================================================================
   * PERSISTANCE
   * ======================================================================== */
  /* --- Compression du magasin ----------------------------------------------
     ~4 Mo de JSON approchaient le quota localStorage (10 Mo en UTF-16) : la
     vague maternité l'aurait franchi en silence. lz-string (vendoré, comme
     Chart.js) ramène le magasin sous le mégaoctet. Le préfixe U+0002 distingue
     une valeur compressée d'un JSON hérité — les deux se relisent, et un poste
     dont la page n'aurait pas chargé lz-string retombe sur le JSON nu. */
  var MARQUE_LZ = '\u0002';
  function serialiser(objet) {
    var json = JSON.stringify(objet);
    if (global.LZString && global.LZString.compressToUTF16) {
      try { return MARQUE_LZ + global.LZString.compressToUTF16(json); } catch (e) { /* repli JSON */ }
    }
    return json;
  }
  function deserialiser(raw) {
    if (raw == null) return null;
    if (raw.charAt(0) === MARQUE_LZ) {
      if (!(global.LZString && global.LZString.decompressFromUTF16)) return null;
      raw = global.LZString.decompressFromUTF16(raw.slice(1));
    }
    return JSON.parse(raw);
  }

  function load() {
    if (db) return db;
    try {
      var raw = storage.get(KEY);
      if (raw) {
        db = deserialiser(raw);
        if (db && db._version === VERSION) {
          fusionnerServiceDirection(db);
          normaliserEtatsResultat(db);
          return db;
        }
      }
    } catch (e) { /* données corrompues : on ré-amorce */ }
    db = seed();
    save();
    return db;
  }
  /* ==========================================================================
   * SAUVEGARDE, ET SAUVEGARDE DIFFÉRÉE
   * --------------------------------------------------------------------------
   * save() sérialise le magasin entier. Sur un geste isolé c'est imperceptible ;
   * sur un traitement en lot de plusieurs milliers d'écritures, le coût devient
   * quadratique — la base grossit et on la resérialise à chaque ligne.
   *
   * enLot() suspend les écritures le temps du traitement et n'en fait qu'une à
   * la fin. Le mode se referme dans un `finally` : une exception au milieu
   * d'un lot ne doit pas laisser le magasin durablement sans sauvegarde.
   * ======================================================================== */
  /* LA COMPRESSION EST UNE SOUPAPE, PAS UN RÉGIME PERMANENT. Mesure faite :
     compresser 4 Mo coûte ~2,4 s de fil principal — payé à chaque écriture,
     cela gelait l'interface et faisait dépasser six secondes aux pages qui
     amorcent en rafale. Le magasin s'écrit donc en JSON nu (rapide) tant que
     le quota tient ; le jour où une écriture est REFUSÉE, il bascule en
     compressé (437 Ko au lieu de 4 Mo), réécrit, et l'annonce. */
  var _lot = 0, _minuterie = null, _compresser = false;
  function ecrire() {
    if (_minuterie) { clearTimeout(_minuterie); _minuterie = null; }
    if (!db) return;
    var ok = storage.set(KEY, _compresser ? serialiser(db) : JSON.stringify(db));
    if (!ok && !_compresser && storage.disponible && global.LZString) {
      _compresser = true;
      storage.quotaSignale = false; /* si même compressé ça déborde, le redire */
      ok = storage.set(KEY, serialiser(db));
      if (ok && global.console && global.console.warn) {
        global.console.warn('[SIGH] Quota localStorage atteint : le magasin est désormais '
          + 'écrit compressé (lz-string).');
      }
    }
  }
  function save() {
    if (_lot > 0) return;
    /* Écriture DIFFÉRÉE : les amorçages d'écran enchaînent des dizaines
       d'insertions qui appellent chacune save() — sérialiser le magasin à
       chaque fois est quadratique. Une rafale n'écrit qu'une fois, 300 ms
       après le dernier geste ; db reste la vérité en mémoire, et pagehide
       vide le tampon avant de quitter la page. */
    if (!_minuterie) _minuterie = setTimeout(ecrire, 300);
  }

  function enLot(fn) {
    _lot++;
    try {
      return fn();
    } finally {
      _lot--;
      if (_lot === 0) ecrire();
    }
  }

  if (global.addEventListener) {
    global.addEventListener('pagehide', function () { if (_minuterie) ecrire(); });
  }
  function reset() { storage.remove(KEY); db = null; return load(); }

  /* --- Journal d'audit (RG-12) -------------------------------------------- */
  function log(action, module, entite, reference, avant, apres) {
    load();
    db.audit.unshift({
      id: 'LOG' + Date.now().toString(36),
      dateHeure: new Date().toISOString(),
      utilisateur: currentUser(),
      action: action, module: module, entite: entite, reference: reference,
      /* Extraits volontairement courts : le journal doit dire CE QUI a changé,
         pas rejouer l'enregistrement entier. Deux cent quarante caractères par
         ligne pesaient 430 Ko sur huit cents entrées. */
      ancienneValeur: avant ? JSON.stringify(avant).slice(0, 140) : null,
      nouvelleValeur: apres ? JSON.stringify(apres).slice(0, 140) : null,
      poste: 'POSTE-LOCAL', succes: true,
    });
    if (db.audit.length > 400) db.audit.length = 400;
  }

  /* --- Abonnements -------------------------------------------------------- */
  function on(name, fn) { (listeners[name] = listeners[name] || []).push(fn); }
  function emit(name) { (listeners[name] || []).forEach(function (fn) { try { fn(); } catch (e) { console.error(e); } }); }

  /* ==========================================================================
   * API COLLECTION
   * ======================================================================== */
  function collection(name, meta) {
    load();
    if (!db[name]) db[name] = [];
    var M = meta || {};
    var api = {
      name: name,
      /** Tous les enregistrements, archivés compris. */
      all: function () { return db[name]; },
      /** Enregistrements non archivés (vue par défaut des tableaux). */
      active: function () { return db[name].filter(function (r) { return r.statut !== 'archive'; }); },
      archived: function () { return db[name].filter(function (r) { return r.statut === 'archive'; }); },
      get: function (id) {
        for (var i = 0; i < db[name].length; i++) if (db[name][i].id === id) return db[name][i];
        return null;
      },
      count: function () { return api.active().length; },

      insert: function (obj) {
        var rec = Object.assign({
          id: (M.prefix || name.slice(0, 3).toUpperCase()) + C.uid(),
          statut: 'actif',
        }, obj);
        rec._creePar = currentUser();
        rec._creeLe = new Date().toISOString();
        db[name].unshift(rec);
        log('Création', M.module || '—', M.entite || name, rec.id, null, rec);
        save(); emit(name);
        return { record: rec, undo: function () { api._remove(rec.id); save(); emit(name); } };
      },

      update: function (id, patch) {
        var rec = api.get(id); if (!rec) return null;
        var avant = Object.assign({}, rec);
        Object.assign(rec, patch);
        rec._modifiePar = currentUser();
        rec._modifieLe = new Date().toISOString();
        log('Modification', M.module || '—', M.entite || name, id, avant, rec);
        /* L'HISTORIQUE DES PRIX A UN SEUL AUTEUR : ici. Toute modification
           d'un article passe par cette porte, quel que soit l'écran qui la
           demande — laisser plusieurs endroits écrire la trace, c'est
           s'assurer qu'un chemin l'oubliera un jour, et l'historique
           deviendrait faux sans que rien ne le signale. */
        if (name === 'produits') tracerPrix(rec, avant, patch);
        save(); emit(name);
        return {
          record: rec,
          undo: function () { Object.assign(rec, avant); save(); emit(name); },
        };
      },

      /** RG-14 — archivage logique, jamais de suppression physique. */
      archive: function (id, motif) {
        var rec = api.get(id); if (!rec) return null;
        var avant = rec.statut;
        rec.statut = 'archive';
        rec._archivePar = currentUser();
        rec._archiveLe = new Date().toISOString();
        rec._motifArchivage = motif || null;
        log('Archivage', M.module || '—', M.entite || name, id, { statut: avant }, { statut: 'archive' });
        save(); emit(name);
        return {
          record: rec,
          undo: function () {
            rec.statut = avant; delete rec._archivePar; delete rec._archiveLe; delete rec._motifArchivage;
            log('Restauration', M.module || '—', M.entite || name, id, { statut: 'archive' }, { statut: avant });
            save(); emit(name);
          },
        };
      },

      restore: function (id) {
        var rec = api.get(id); if (!rec) return null;
        rec.statut = 'actif'; delete rec._archivePar; delete rec._archiveLe;
        log('Restauration', M.module || '—', M.entite || name, id, { statut: 'archive' }, { statut: 'actif' });
        save(); emit(name);
        return { record: rec };
      },

      duplicate: function (id) {
        var rec = api.get(id); if (!rec) return null;
        var copie = Object.assign({}, rec);
        delete copie.id; delete copie._creeLe; delete copie._creePar;
        if (copie.reference) copie.reference = copie.reference + '-COPIE';
        if (copie.numero) copie.numero = copie.numero + '-COPIE';
        return api.insert(copie);
      },

      /** Suppression physique — réservée à l'annulation d'une création. */
      _remove: function (id) {
        var i = db[name].findIndex(function (r) { return r.id === id; });
        if (i >= 0) db[name].splice(i, 1);
      },
    };
    return api;
  }

  /* ==========================================================================
   * CORBEILLE — RG-14
   * --------------------------------------------------------------------------
   * L'archivage remplace la suppression dans tous les modules. Encore faut-il
   * pouvoir retrouver ce qui a été archivé sans savoir de quel écran cela
   * venait : cette vue balaie toutes les collections et rend chaque fiche
   * restaurable depuis un seul endroit.
   * ======================================================================== */

  /* Libellé lisible de chaque collection : « module | entité ». Une collection
     absente de cette table reste listée sous son nom technique. */
  var LIBELLES = {
    patients: 'M1|Patients', documentsPatient: 'M1|Documents numérisés du patient',
    documents: 'GED|Bibliothèque documentaire',
    consultations: 'M2|Consultations et rendez-vous', support: 'M2|Registre des appels',
    admissions: 'M3|Admissions', soins: 'M3|Soins', observations: 'M3|Mises en observation', sortiesAvisMedical: 'M3|Sorties contre avis médical',
    suiviMaternite: 'M4|Suivi maternité', accouchements: 'M4|Accouchements',
    naissances: 'M4|Naissances', deces: 'M4|Décès',
    grossesses: 'M4|Suivi CPN & carte maternelle', partogrammes: 'M4|Partogrammes',
    cpon: 'M4|Consultations post-natales', planificationFamiliale: 'M4|Planification familiale',
    registreSONU: 'M4|Registre SONUB / SONUC', ptme: 'M4|Registre PTME',
    soinsCuratifsMaternite: 'M4|Soins curatifs & urgences maternité',
    demandesAnalyses: 'M5|Demandes d’analyses', analyses: 'M5|Catalogue des analyses',
    plagesReactif: 'M5|Plages de référence par lot de réactif',
    actes: 'CFG|Catalogue des actes', ordonnances: 'M2|Ordonnances', taches: 'CFG|Files d’attente',
    certificats: 'CFG|Certificats médicaux', naturesFacture: 'CFG|Natures de facture', centresCouts: 'M12|Centres de coûts',
    banques: 'M12|Comptes de trésorerie', depenses: 'M12|Dépenses de trésorerie', souscripteurs: 'M9|Souscripteurs', garanties: 'M9|Garanties de prise en charge',
    avoirs: 'M8|Factures d’avoir', pvReceptions: 'M7|PV de réception',
    secteurs: 'CFG|Secteurs de la clinique', postes: 'CFG|Postes de l’organigramme',
    ressources: 'CFG|Ressources graphiques',
    poches: 'M5|Banque de sang', donneurs: 'M5|Donneurs',
    produits: 'M6|Produits et médicaments', lots: 'M6|Lots', mouvements: 'M6|Mouvements de stock',
    transferts: 'M6|Transferts', inventaires: 'M6|Inventaires', dispensations: 'M6|Dispensations',
    besoins: 'M7|Bons de besoins', commandes: 'M7|Commandes', livraisons: 'M7|Livraisons',
    fournisseurs: 'M7|Fournisseurs', facturesFournisseurs: 'M7|Factures fournisseurs',
    factures: 'M8|Factures', remboursements: 'M8|Remboursements', avoirs: 'M8|Avoirs',
    assureurs: 'M9|Compagnies d’assurance', releves: 'M9|Relevés', relances: 'M9|Relances',
    personnel: 'M10|Personnel', contrats: 'M10|Contrats', planning: 'M10|Planning',
    presences: 'M10|Présences', conges: 'M10|Congés', evaluations: 'M10|Évaluations',
    prestataires: 'M10|Prestataires', assurancesPersonnel: 'M10|Assurances du personnel', missions: 'M10|Ordres de mission',
    bulletins: 'M11|Bulletins de paie', heuresSup: 'M11|Heures supplémentaires', avances: 'M11|Avances',
    comptes: 'M12|Plan comptable', ecritures: 'M12|Écritures', budgets: 'M12|Budgets',
    immobilisations: 'M12|Immobilisations', rapprochements: 'M12|Rapprochements bancaires',
    echeancesFiscales: 'M12|Échéances fiscales',
    regimesTravail: 'M10|Régimes de travail par catégorie',
    modulesActifs: 'CFG|Activité des modules', notifications: 'M14|Notifications',
    retenuesAIB: 'M12|Retenues d’AIB', historiquePrix: 'M6|Historique des prix',
    baremeAIB: 'M12|Barème de l’AIB',
    emplacements: 'M6|Emplacements de rangement',
    baremeNS131: 'M10|Barème d’évaluation NS 131', historiqueBareme: 'M10|Versions antérieures du barème',
    rbac2: 'M14|Surcharges RBAC',
    pathologies: 'M2|Référentiel des pathologies',
    examensLabo: 'M5|Catalogue des examens', unitesLabo: 'M5|Unités de mesure',
    variablesLabo: 'M5|Variables et valeurs de référence',
    evenements: 'M10|Événements du personnel', participations: 'M10|Participations aux événements',
    grillePrimes: 'M10|Grille des primes NS 132', historiquePrimes: 'M10|Versions antérieures de la grille des primes',
    rbac: 'M14|Rôles et permissions', tentativesConnexion: 'M14|Tentatives de connexion refusées',
    courriers: 'M13|Courriers', reunions: 'M13|Réunions',
    /* Une clé déclarée deux fois dans un littéral écrase la première EN
       SILENCE : « evenements » désignait ici les événements de M13 et effaçait
       l'intitulé de ceux du personnel. Les deux collections sont désormais
       distinctes, et leurs intitulés aussi. */
    evenementsEtablissement: 'M13|Événements de l’établissement',
    planAnnuel: 'M13|Plan annuel', ambulance: 'M13|Ambulance',
    releves: 'M3|Relevés de constantes au lit du patient',
    resultatsImagerie: 'M2|Comptes rendus d’imagerie',
    demandesImagerie: 'M2|Demandes d’imagerie',
    enquetes: 'M13|Modèles d’enquête',
    reponsesEnquetes: 'M13|Réponses d’enquête',
    clichesImagerie: 'M2|Clichés d’échographie',
    examensImagerie: 'CFG|Catalogue des examens d’imagerie',
    variablesImagerie: 'CFG|Variables des comptes rendus d’imagerie',
    fichesReference: 'M1|Fiches de référence',
    contreReferences: 'M1|Fiches de contre-référence',
    surveillancesTransfusion: 'M3|Surveillances transfusionnelles',
    scoresGlasgow: 'M3|Scores de Glasgow',
    rapportsMedicaux: 'M3|Rapports médicaux',
    fileAttente: 'M2|File d’attente',
    fichesPoste: 'M10|Fiches de poste',
    pretsEtudes: 'M11|Prêts-études et avances',
    facturesMere: 'M9|Factures mères d’assurance',
    ambulances: 'M13|Répertoire des ambulances',
    materiel: 'M13|Parc technique',
    valorisationsSage: 'M6|Valorisations de la reprise SAGE',
    dossiersConsultation: 'M1|Dossiers de consultation',
    modelesMessage: 'CFG|Modèles de message',
    rappels: 'CFG|Rappels',
    soignants: 'M14|Prescripteurs et exécutants de soins',
    prescriptions: 'M2|Prescriptions',
    administrations: 'M3|Administrations de traitement',
    crOperatoires: 'M3|Comptes rendus opératoires',
    checklistsBloc: 'M3|Check-listes du bloc',
    cpa: 'M3|Consultations pré-anesthésiques',
    crAnesthesie: 'M3|Comptes rendus d’anesthésie',
    crMaternite: 'M4|Comptes rendus de maternité',
    catalogueTarifs: 'CFG|Catalogue tarifaire',
    typesPiece: 'CFG|Types de pièces certifiantes',
    pieces: 'M1|Pièces certifiantes délivrées',
    utilisateurs: 'M14|Utilisateurs', audit: 'M14|Journal d’audit',
  };

  function libelleCollection(nom) {
    var t = (LIBELLES[nom] || '—|' + nom).split('|');
    return { module: t[0], entite: t[1] };
  }

  /** Toutes les fiches archivées, tous modules confondus. */
  function corbeille() {
    load();
    var out = [];
    Object.keys(db).forEach(function (k) {
      if (k.charAt(0) === '_' || !Array.isArray(db[k])) return;
      var lib = libelleCollection(k);
      db[k].forEach(function (r) {
        if (!r || r.statut !== 'archive') return;
        out.push({
          id: k + ':' + r.id, refId: r.id, collection: k,
          module: lib.module, entite: lib.entite,
          libelle: r.nom ? (r.nom + ' ' + (r.prenom || '')).trim()
            : (r.libelle || r.designation || r.reference || r.numero || r.intitule || r.code || r.id),
          archiveLe: r._archiveLe || null,
          archivePar: r._archivePar || '—',
          motif: r._motifArchivage || null,
        });
      });
    });
    return out.sort(function (a, b) { return String(b.archiveLe || '').localeCompare(String(a.archiveLe || '')); });
  }

  /* ==========================================================================
   * BASCULES D'EXPLOITATION
   * --------------------------------------------------------------------------
   * Elles vivent dans le SOCLE et non dans un module : chaque page ne charge
   * que le module de son écran, si bien qu'une bascule déclarée dans
   * configuration.js serait invisible partout ailleurs — c'est exactement ce
   * qui est arrivé à celle du barème.
   *
   * Autorisation de modifier le barème NS 131 : condition posée par la
   * Direction — « on doit autoriser le CRUD depuis paramètres de setting ».
   * Un barème de sanctions ne se retouche pas au détour d'un écran
   * d'évaluation. Fermée, la modification est ABSENTE et non grisée.
   * ======================================================================== */
  global.SIGH.baremeModifiable = function () {
    return storage.get('sigh-cbg:bareme-modifiable') === '1';
  };

  /**
   * Journalise un ACCÈS — une consultation, une recherche — sans passer par
   * collection().insert(), qui journaliserait à son tour et doublerait l'entrée.
   *
   * RG-12 impose de tracer les actions ; la Direction a demandé de tracer aussi
   * les CONSULTATIONS de dossier patient. Un journal qui se double lui-même
   * devient illisible au moment précis où l'on en a besoin.
   */
  function journaliserAcces(o) {
    load();
    var rec = {
      id: 'LOG' + C.uid(),
      dateHeure: new Date().toISOString(),
      utilisateur: o.utilisateur || currentUser(),
      role: o.role || null,
      action: o.action || 'Consultation',
      module: o.module || 'M14',
      entite: o.entite || 'Dossier patient',
      reference: o.reference || null,
      cible: o.cible || null,
      patientId: o.patientId || null,
      ecran: o.ecran || null,
      motif: o.motif || null,
      trouve: o.trouve !== false,
      ancienneValeur: null, nouvelleValeur: null,
      poste: 'POSTE-LOCAL', succes: true,
    };
    db.audit.unshift(rec);
    if (db.audit.length > 400) db.audit.length = 400;
    save();
    return rec;
  }

  global.SIGH.store = {
    enLot: enLot,
    journaliserAcces: journaliserAcces,
    load: load, save: save, reset: reset, collection: collection,
    log: log, on: on, emit: emit,
    session: session, setSession: setSession, currentUser: currentUser,
    valorisationSortie: valorisationSortie, setValorisationSortie: setValorisationSortie,
    valeurUnitaire: valeurUnitaire, valeurUnitaireDetail: valeurUnitaireDetail,
    prixManquant: prixManquant, historiquePrix: historiquePrix,
    storage: storage,
    corbeille: corbeille, libelleCollection: libelleCollection,
    raw: function () { return load(); },
  };
})(window);
