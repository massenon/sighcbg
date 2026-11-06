/* =============================================================================
 * PARCOURS — chaîne transactionnelle inter-modules
 * -----------------------------------------------------------------------------
 * draf1 §24-25 : le prototype ne se juge pas au nombre d'écrans mais à sa
 * capacité à faire traverser plusieurs modules à une même opération. Ce fichier
 * porte cette traversée, décrite par la Direction :
 *
 *   le médecin prescrit  →  le gestionnaire de stock est informé des médicaments
 *                        →  le laborantin est informé des analyses, la demande
 *                           est établie d'office (la saisie manuelle reste
 *                           possible pour les patients venus de l'extérieur)
 *                        →  la caisse est informée, le patient règle, la caisse
 *                           valide  →  les médicaments sont délivrés et le
 *                           prélèvement est autorisé.
 *
 * Il est chargé sur toutes les pages, juste après `store` : la chaîne doit
 * fonctionner depuis la consultation comme depuis la caisse ou la pharmacie,
 * alors que chaque page ne charge que le module de son écran.
 *
 * Règles de gestion appliquées ici :
 *   RG-02  médicaments facturés au prix d'achat, sans marge ;
 *   RG-03  toute sortie porte un justificatif, le stock ne devient jamais négatif ;
 *   RG-12  chaque étape est journalisée, aucune action anonyme ;
 *   RG-14  rien n'est supprimé, tout est archivé.
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core, S = global.SIGH.store, D = global.SIGH.data;

  /* --- Files d'attente : à qui l'information est adressée ------------------ */
  var TACHES = {
    encaissement: {
      role: 'caissier', module: 'M8', ecran: 'm8-caisse',
      titre: 'Encaisser la prescription', icon: 'coins',
    },
    dispensation: {
      role: 'pharmacien', module: 'M6', ecran: 'm6-dispensation',
      titre: 'Délivrer les médicaments', icon: 'pill',
    },
    prelevement: {
      role: 'laborantin', module: 'M5', ecran: 'm5-demandes',
      titre: 'Prélever et analyser', icon: 'flask-conical',
    },
    acte: {
      role: 'infirmier', module: 'M3', ecran: 'm3-soins',
      titre: 'Exécuter les actes prescrits', icon: 'stethoscope',
    },
  };

  function col(nom) { return S.collection(nom, META[nom] || {}); }
  var META = {
    ordonnances: { module: 'M2', entite: 'ordonnance', prefix: 'ORD' },
    taches: { module: 'M14', entite: 'tâche', prefix: 'TCH' },
    demandesAnalyses: { module: 'M5', entite: 'demande d’analyse', prefix: 'DEM' },
    factures: { module: 'M8', entite: 'facture', prefix: 'FAC' },
    mouvements: { module: 'M6', entite: 'mouvement de stock', prefix: 'MVT' },
    prescriptions: { module: 'M2', entite: 'prescription', prefix: 'PRS' },
    administrations: { module: 'M3', entite: 'administration de traitement', prefix: 'ADM' },
    soignants: { module: 'M14', entite: 'soignant', prefix: 'SOI' },
  };

  /* ==========================================================================
   * RÉFÉRENTIELS DE TRAVAIL
   * ======================================================================== */
  function patients() { return S.collection('patients').active(); }
  function produits() { return S.collection('produits').active(); }

  function patientParCode(code) {
    var t = patients().filter(function (p) { return p.code === code; });
    return t[0] || null;
  }
  function produitParId(id) {
    var t = produits().filter(function (p) { return p.id === id; });
    return t[0] || null;
  }
  function analyseParCode(code) {
    var t = D.ANALYSES.filter(function (a) { return a.code === code; });
    return t[0] || null;
  }
  function acteParCode(code) {
    /* Le catalogue des actes vit dans le MAGASIN (administrable depuis
       cfg-tarifs) ; D.ACTES n'en est que la semence. Lire la constante ici,
       c'était facturer un tarif que l'écran de configuration ne pouvait plus
       corriger. */
    var t = S.collection('actes').active().filter(function (a) { return a.code === code; });
    return t[0] || null;
  }

  /* ==========================================================================
   * 1. LE MÉDECIN PRESCRIT
   * --------------------------------------------------------------------------
   * Un seul geste engendre l'ordonnance, les demandes d'analyses, la facture et
   * les trois files d'attente. Rien n'est laissé à une ressaisie.
   * ======================================================================== */
  function prescrire(v) {
    var p = patientParCode(v.patientCode);
    if (!p) throw new Error('Patient introuvable : ' + v.patientCode);

    var date = v.date || new Date().toISOString();
    var numero = 'ORD-' + String(new Date(date).getFullYear()) + '-' + C.pad(col('ordonnances').all().length + 1, 5);

    /* --- Lignes ----------------------------------------------------------- */
    var medicaments = (v.medicaments || []).map(function (l) {
      var prod = produitParId(l.produitId) || {};
      /* RG-02 — prix d'achat, sans marge. */
      var pu = prod.prixAchat != null ? prod.prixAchat : 0;
      var q = Number(l.quantite) || 0;
      return {
        produitId: l.produitId, produit: prod.designation || l.produit || '—',
        unite: prod.unite || '', quantite: q,
        posologie: l.posologie || '', duree: l.duree || '',
        prix: pu, total: pu * q,
      };
    }).filter(function (l) { return l.quantite > 0; });

    var analyses = (v.analyses || []).map(function (code) {
      var a = analyseParCode(code) || {};
      return { code: code, designation: a.designation || code, categorie: a.categorie || '',
        echantillon: a.echantillon || '', delai: a.delai || '', prix: a.prix || 0 };
    });

    var actes = (v.actes || []).map(function (code) {
      var a = acteParCode(code) || {};
      return { code: code, libelle: a.libelle || code, secteur: a.secteur || '', prix: a.prix || 0,
        tarifValide: a.prix != null };
    });

    var mMed = C.sum(medicaments, 'total');
    var mAna = C.sum(analyses, 'prix');
    var mAct = C.sum(actes, function (a) { return a.prix || 0; });

    /* --- L'ordonnance ------------------------------------------------------ */
    var ord = col('ordonnances').insert({
      numero: numero, date: date,
      patientId: p.id, patientCode: p.code, patient: p.nom + ' ' + p.prenom,
      medecin: v.medecin, diagnostic: v.diagnostic || '', consultationId: v.consultationId || null,
      medicaments: medicaments, analyses: analyses, actes: actes,
      montantMedicaments: mMed, montantAnalyses: mAna, montantActes: mAct,
      montant: mMed + mAna + mAct,
      urgent: !!v.urgent,
      statutPaiement: 'impayee',
      statutDispensation: medicaments.length ? 'en_attente' : 'sans_objet',
      statutAnalyses: analyses.length ? 'en_attente' : 'sans_objet',
      statutActes: actes.length ? 'en_attente' : 'sans_objet',
    }).record;

    /* --- Le laboratoire : demandes établies d'office ----------------------- */
    var demandes = analyses.map(function (a) {
      return col('demandesAnalyses').insert({
        reference: C.nextRef('LAB-', 5),
        codeAnalyse: codeAnalyse(date),
        patientId: p.id, patientCode: p.code, patient: p.nom + ' ' + p.prenom,
        analyseCode: a.code, analyse: a.designation, categorie: a.categorie,
        echantillon: a.echantillon, delai: a.delai, prix: a.prix,
        dateHeure: date, prescripteur: v.medecin, laborantin: null,
        urgent: !!v.urgent, etatAnalyse: 'en_attente',
        /* Origine tracée : la demande automatique se distingue de la saisie
           manuelle du laboratoire, qui reste ouverte pour les patients
           adressés par l'extérieur. */
        origine: 'ordonnance', ordonnanceId: ord.id, ordonnanceNumero: numero,
        /* Le secteur prescripteur commande la visibilité du résultat : une
           sage-femme voit ceux de la maternité, pas ceux de la chirurgie. */
        secteurDemandeur: v.secteurDemandeur || (secteurCourant() ? secteurCourant().libelle : null),
        /* Le prélèvement n'est autorisé qu'une fois la caisse passée. */
        bloqueParPaiement: true,
      }).record;
    });

    /* --- La caisse : facture en attente de règlement ------------------------ */
    var taux = p.assureur ? (p.tauxPriseEnCharge || 0) : 0;
    var montant = mMed + mAna + mAct;
    var partAssurance = Math.round(montant * taux / 100);

    /* Les LIGNES PAYABLES. Chacune sait ce qu'elle couvre — une demande
       d'analyse, un produit, un acte — pour que le règlement de cette ligne
       débloque exactement ce qu'elle a payé, et rien d'autre. */
    var lignesFacture = construireLignes({
      medicaments: medicaments, analyses: analyses, actes: actes,
      demandes: demandes, taux: taux,
      /* L'agent de la clinique est pris en charge à 100 % par l'établissement.
         Le lien vient du dossier, il ne se saisit pas au guichet. */
      personnelId: p.personnelId || null,
    });

    /* LE TOTAL EST LA SOMME DES LIGNES, jamais un montant calculé à côté.
       C'est le défaut déjà corrigé sur les états imprimés : deux façons de
       compter la même chose divergent au premier correctif. */
    var totalLignes = C.sum(lignesFacture, 'montant');
    var totalAssureur = C.sum(lignesFacture, 'partAssureur');
    var totalPersonnel = C.sum(lignesFacture, 'partPersonnel');
    var totalRemise = C.sum(lignesFacture, 'remise');
    var duPatient = totalLignes - totalAssureur - totalPersonnel;

    var facture = col('factures').insert({
      lignes: lignesFacture,
      numero: 'FP-' + String(new Date(date).getFullYear()) + '-' + C.pad(col('factures').all().length + 1, 5),
      numeroMecef: null,
      patientId: p.id, patient: p.nom + ' ' + p.prenom, patientCode: p.code,
      date: C.iso(new Date(date)), type: 'Prescription',
      montantHT: totalLignes, montantTTC: totalLignes,
      montantBrut: C.sum(lignesFacture, 'montantBrut'), totalRemise: totalRemise,
      partPersonnel: totalPersonnel,
      priseEnChargePersonnel: !!p.personnelId, personnelId: p.personnelId || null,
      assureur: p.assureur || null, tauxPriseEnCharge: taux,
      partAssurance: totalAssureur, partPatient: duPatient,
      montantPaye: 0, reliquat: duPatient,
      modePaiement: null,
      statutPaiement: 'impayee', statutMecef: 'en_attente',
      ordonnanceId: ord.id, ordonnanceNumero: numero,
    }).record;

    col('ordonnances').update(ord.id, { factureId: facture.id, factureNumero: facture.numero });

    /* --- Les files d'attente ---------------------------------------------- */
    var taches = [];
    taches.push(creerTache('encaissement', ord, facture, {
      detail: resumeLignes(medicaments, analyses, actes), montant: montant, statut: 'en_attente',
    }));
    if (medicaments.length) {
      taches.push(creerTache('dispensation', ord, facture, {
        detail: medicaments.length + ' médicament(s) — ' + C.money(mMed, false),
        montant: mMed,
        /* Informé tout de suite, exécutable après encaissement. */
        statut: 'bloque',
      }));
    }
    if (analyses.length) {
      taches.push(creerTache('prelevement', ord, facture, {
        detail: analyses.length + ' analyse(s) — ' + analyses.map(function (a) { return a.designation; }).join(', '),
        montant: mAna, statut: 'bloque',
      }));
    }
    if (actes.length) {
      taches.push(creerTache('acte', ord, facture, {
        detail: actes.map(function (a) { return a.libelle; }).join(', '),
        montant: mAct, statut: 'bloque',
      }));
    }

    S.log('Prescription', 'M2', 'ordonnance', numero, null, {
      medicaments: medicaments.length, analyses: analyses.length, actes: actes.length, montant: montant,
    });

    /* L ordonnance entre au REGISTRE UNIFIÉ des prescriptions. Sans cela,
       « les prescriptions du jour » n en montreraient que la moitié : les soins
       y figureraient, les médicaments non. */
    if (medicaments.length) {
      try { inscrireOrdonnance(col('ordonnances').get(ord.id), v.origine || 'consultation'); }
      catch (e) { /* le registre est secondaire, il ne doit pas casser la prescription */ }
    }

    return { ordonnance: col('ordonnances').get(ord.id), demandes: demandes, facture: facture, taches: taches };
  }

  function resumeLignes(med, ana, act) {
    var t = [];
    if (med.length) t.push(med.length + ' médicament(s)');
    if (ana.length) t.push(ana.length + ' analyse(s)');
    if (act.length) t.push(act.length + ' acte(s)');
    return t.join(' · ') || 'Prescription sans ligne';
  }

  function creerTache(type, ord, facture, extra) {
    var def = TACHES[type];
    return col('taches').insert(Object.assign({
      type: type, role: def.role, module: def.module, ecran: def.ecran,
      titre: def.titre, icon: def.icon,
      reference: ord.numero, ordonnanceId: ord.id,
      factureId: facture ? facture.id : null, factureNumero: facture ? facture.numero : null,
      patient: ord.patient, patientCode: ord.patientCode,
      date: ord.date, urgent: !!ord.urgent,
      statut: 'en_attente', faitLe: null, faitPar: null,
    }, extra || {})).record;
  }

  /* ==========================================================================
   * 2. LA CAISSE ENCAISSE ET VALIDE
   * --------------------------------------------------------------------------
   * Le règlement débloque tout l'aval : sans lui, ni délivrance ni prélèvement.
   * ======================================================================== */
  /* ==========================================================================
   * LES DEUX VALIDATIONS D'UN RÉSULTAT
   * --------------------------------------------------------------------------
   * « Une première validation technique, puis une validation biologique. Dès
   * que nous faisons la validation biologique, le médecin a le résultat. »
   *
   * Entre les deux, le résultat existe mais reste invisible du prescripteur :
   * c'est la fenêtre de relecture. Elle n'a de sens que si personne ne lit
   * par-dessus l'épaule du laboratoire — d'où le verrou posé dans
   * peutVoirResultat().
   *
   * QUI VALIDE BIOLOGIQUEMENT : le biologiste médical. Le TSL le peut EN SON
   * ABSENCE, et l'intérim est alors tracé sur la pièce. Une clinique de trente
   * agents ne peut pas suspendre ses rendus pendant un congé ; masquer
   * l'intérim reviendrait à faire signer quelqu'un d'autre.
   * ======================================================================== */
  function validerTechnique(demandeId, opts) {
    opts = opts || {};
    var col_ = S.collection('demandesAnalyses');
    var d = col_.get(demandeId);
    if (!d) throw new Error('Demande introuvable.');
    if (!d.valeurs || !Object.keys(d.valeurs).length) {
      throw new Error('Aucun résultat saisi : il n’y a rien à valider.');
    }
    var res = col_.update(demandeId, {
      etatAnalyse: 'valide_technique',
      valideTechniqueLe: new Date().toISOString(),
      valideTechniquePar: opts.utilisateur || S.currentUser(),
    });
    S.log('Validation technique', 'M5', 'ResultatAnalyse', d.reference,
      { etat: d.etatAnalyse }, { etat: 'valide_technique' });
    return { demande: col_.get(demandeId), undo: res.undo };
  }

  /**
   * La validation biologique rend le résultat OPPOSABLE : le prescripteur le
   * voit, la clinique le remet au patient externe. C'est le point de
   * non-retour — au-delà, une correction devient une RECTIFICATION.
   */
  function validerBiologique(demandeId, opts) {
    opts = opts || {};
    var col_ = S.collection('demandesAnalyses');
    var d = col_.get(demandeId);
    if (!d) throw new Error('Demande introuvable.');
    if (d.etatAnalyse !== 'valide_technique') {
      throw new Error('La validation technique doit précéder la validation biologique.');
    }
    var cap = capacites(opts.session);
    if (!cap.validerBiologique) {
      throw new Error(cap.label + ' n’est pas habilité à porter la validation biologique.');
    }
    var interim = cap.validerBiologique === 'interim';

    var res = col_.update(demandeId, {
      etatAnalyse: 'valide',
      valideLe: new Date().toISOString(),
      valideBiologiquePar: opts.utilisateur || S.currentUser(),
      /* L'intérim est PORTÉ SUR LA PIÈCE : le compte rendu dira qui a signé
         et à quel titre. */
      validationInterim: interim,
      qualiteValidateur: interim
        ? cap.label + ' — par intérim du biologiste médical'
        : cap.label,
      version: d.version || 1,
    });
    S.log('Validation biologique', 'M5', 'ResultatAnalyse', d.reference,
      { etat: 'valide_technique' }, { etat: 'valide', interim: interim });

    /* Le prescripteur est informé que son résultat est disponible. */
    notifier({
      type: 'resultat_disponible', poste: 'prescripteur',
      destinataire: d.prescripteur,
      libelle: 'Résultat disponible — ' + d.analyse,
      detail: d.patient + ' (' + d.patientCode + ')',
      demandeId: demandeId, reference: d.reference,
      patientId: d.patientId,
    });

    return { demande: col_.get(demandeId), interim: interim, undo: res.undo };
  }

  /**
   * RECTIFIER un résultat déjà validé biologiquement.
   *
   * « Même si après on vient corriger, peut-être qu'il a déjà lu le premier,
   * et c'est pas cool. » — Exactement. La version précédente est CONSERVÉE,
   * la nouvelle est numérotée, et le prescripteur est notifié que ce qu'il a
   * lu a changé. Écraser en silence laisserait le médecin avec une valeur qui
   * n'existe plus nulle part.
   */
  function rectifierResultat(demandeId, valeurs, opts) {
    opts = opts || {};
    if (!opts.motif) throw new Error('Une rectification doit être motivée.');
    var col_ = S.collection('demandesAnalyses');
    var d = col_.get(demandeId);
    if (!d) throw new Error('Demande introuvable.');
    if (!D.resultatRendu(d.etatAnalyse)) {
      throw new Error('Ce résultat n’a pas été validé biologiquement : le corriger ne demande pas de rectification.');
    }

    var versions = (d.versions || []).slice();
    var numero = (d.version || 1);
    /* On fige la version sortante AVANT de la remplacer : c'est elle que le
       médecin a lue, et elle doit rester consultable. */
    versions.push({
      numero: numero,
      valeurs: Object.assign({}, d.valeurs),
      commentaireGeneral: d.commentaireGeneral || null,
      conclusion: d.conclusion || null,
      valideLe: d.valideLe,
      valideBiologiquePar: d.valideBiologiquePar,
      remplaceeLe: new Date().toISOString(),
      motifRemplacement: opts.motif,
    });

    var res = col_.update(demandeId, {
      valeurs: valeurs,
      versions: versions,
      version: numero + 1,
      etatAnalyse: 'rectifie',
      rectifieLe: new Date().toISOString(),
      rectifiePar: opts.utilisateur || S.currentUser(),
      motifRectification: opts.motif,
      commentaireGeneral: opts.commentaireGeneral != null ? opts.commentaireGeneral : d.commentaireGeneral,
    });

    S.log('Rectification de résultat', 'M5', 'ResultatAnalyse', d.reference,
      { version: numero, valeurs: d.valeurs }, { version: numero + 1, motif: opts.motif });

    /* LA NOTIFICATION EST LE CŒUR DU DISPOSITIF : sans elle, la rectification
       ne vaut pas mieux qu'un écrasement silencieux. */
    notifier({
      type: 'resultat_rectifie', poste: 'prescripteur',
      destinataire: d.prescripteur,
      priorite: 'haute',
      libelle: 'RÉSULTAT RECTIFIÉ — ' + d.analyse,
      detail: d.patient + ' (' + d.patientCode + ') — version ' + (numero + 1)
        + '. Motif : ' + opts.motif + '. Le résultat que vous avez consulté a changé.',
      demandeId: demandeId, reference: d.reference,
      patientId: d.patientId,
    });

    return { demande: col_.get(demandeId), version: numero + 1, undo: res.undo };
  }

  /* ==========================================================================
   * NOTIFICATIONS DE POSTE
   * --------------------------------------------------------------------------
   * Une notification s'adresse à un POSTE, pas à une personne : le
   * prescripteur peut être en congé, c'est le service qui doit voir passer
   * l'information. Elle vit dans sa propre collection pour survivre au
   * rechargement de la page.
   * ======================================================================== */
  function notifier(o) {
    return S.collection('notifications', { module: 'M14', entite: 'notification', prefix: 'NOT' }).insert({
      type: o.type, poste: o.poste || 'tous',
      destinataire: o.destinataire || null,
      libelle: o.libelle, detail: o.detail || null,
      priorite: o.priorite || 'normale',
      demandeId: o.demandeId || null, factureId: o.factureId || null,
      ordonnanceId: o.ordonnanceId || null, patientId: o.patientId || null,
      reference: o.reference || null,
      lue: false, creeLe: new Date().toISOString(),
    }).record;
  }

  /** Les notifications d'un poste, non lues d'abord. */
  function notifications(poste, opts) {
    opts = opts || {};
    var rows = S.collection('notifications', { module: 'M14', entite: 'notification', prefix: 'NOT' })
      .active()
      .filter(function (n) { return !poste || n.poste === poste || n.poste === 'tous'; });
    if (opts.nonLues) rows = rows.filter(function (n) { return !n.lue; });
    return rows.sort(function (a, b) { return String(b.creeLe).localeCompare(String(a.creeLe)); });
  }

  function marquerLue(id) {
    return S.collection('notifications', { module: 'M14', entite: 'notification', prefix: 'NOT' })
      .update(id, { lue: true, lueLe: new Date().toISOString(), luePar: S.currentUser() });
  }

  /* ==========================================================================
   * LE PATIENT EXTERNE
   * --------------------------------------------------------------------------
   * Il arrive avec une ordonnance d'un médecin extérieur. L'accueil TRANSCRIT
   * cette ordonnance — il ne prescrit pas — en cochant les examens dans le
   * catalogue, puis l'envoie à la caisse avec sa facture.
   *
   * Deux règles que ce circuit doit tenir :
   *   — les examens viennent du CATALOGUE, jamais d'un montant libre : sans
   *     lignes, la facture ne peut pas être réglée examen par examen ;
   *   — l'IDENTITÉ est obligatoire. Sans nom, âge, sexe et téléphone, le
   *     résultat ne peut être ni remis ni retrouvé — et c'est au patient
   *     externe qu'on le remet directement.
   * ======================================================================== */
  function ouvrirDemandeExterne(v) {
    /* L'identité est obligatoire — mais un patient DU RÉPERTOIRE (fiche du
       service, phase 7) la porte déjà : exiger sa ressaisie créerait deux
       vérités. La règle vaut pour l'externe dont on crée le dossier. */
    if (!v || (!v.patientId && (!v.nom || !v.prenom))) {
      throw new Error('Nom et prénoms du patient obligatoires.');
    }
    if (!v.analyses || !v.analyses.length) throw new Error('Cocher au moins un examen au catalogue.');

    var date = v.date || new Date().toISOString();

    /* Le patient externe reçoit un DOSSIER : sans lui, on ne peut ni lui
       remettre son résultat, ni le retrouver s'il revient. Il est marqué
       comme externe, ce qui le distingue de la file de consultation. */
    var patients = S.collection('patients', { module: 'M1', entite: 'Patient' });
    var existant = v.patientId ? patients.get(v.patientId) : null;
    if (v.patientId && !existant) throw new Error('Patient introuvable au répertoire.');
    var p = existant;
    if (!p) {
      var annee = String(new Date(date).getFullYear()).slice(-2);
      p = patients.insert({
        code: 'CNT' + (900 + patients.all().length) + '/' + annee,
        nom: String(v.nom).toUpperCase(), prenom: v.prenom,
        sexe: v.sexe || 'M', dateNaissance: v.dateNaissance || null,
        telephone: v.telephone || null, adresse: v.residence || null,
        quartier: v.residence || null,
        externe: true, origineDossier: 'Patient externe — accueil',
        prescripteurExterieur: v.prescripteur || null,
        assure: !!v.assureur, assureur: v.assureur || null,
        tauxPriseEnCharge: v.assureur ? (Number(v.taux) || 0) : 0,
      }).record;
    }

    /* Les examens, pris au catalogue. */
    var analyses = (v.analyses || []).map(function (code) {
      var a = analyseParCode(code) || {};
      return {
        code: code, designation: a.designation || code, categorie: a.categorie || '',
        echantillon: a.echantillon || '', delai: a.delai || '', prix: a.prix || 0,
      };
    });
    var montant = C.sum(analyses, 'prix');

    /* Les demandes, marquées EXTERNE : le résultat se remet au patient. */
    var demandes = analyses.map(function (a) {
      return S.collection('demandesAnalyses').insert({
        reference: C.nextRef('LAB-', 5),
        codeAnalyse: codeAnalyse(date),
        patientId: p.id, patientCode: p.code, patient: p.nom + ' ' + p.prenom,
        analyseCode: a.code, analyse: a.designation, categorie: a.categorie,
        echantillon: a.echantillon, delai: a.delai, prix: a.prix,
        dateHeure: date,
        prescripteur: v.prescripteur || 'Médecin extérieur',
        laborantin: null,
        urgent: v.urgence === 'bilan' || (v.urgence === 'examen' && v.examenUrgent === a.code),
        etatAnalyse: 'en_attente',
        /* Trois voies désormais : la transcription à l'accueil, la saisie du
           laboratoire, et — phase 7 — la fiche de demande d'examen d'un
           SERVICE (m3-demande-examen, le formulaire papier de reunions/).
           origineDemande 'externe' dit que le résultat se remet au patient ;
           'service' le renvoie au prescripteur, sous le RBAC métier. */
        origine: v.origineFiche || 'accueil-externe',
        origineDemande: v.origineDemande || 'externe',
        serviceDemandeur: v.serviceDemandeur || null,
        secteurDemandeur: v.secteurDemandeur || null,
        indication: v.indication || null,
        hospitalise: !!v.hospitalise,
        bloqueParPaiement: true,
      }).record;
    });

    /* La facture, avec ses lignes payables. */
    var taux = p.assureur ? (p.tauxPriseEnCharge || 0) : 0;
    var partAssurance = Math.round(montant * taux / 100);
    var lignes = construireLignes({
      analyses: analyses, demandes: demandes, taux: taux,
      personnelId: p.personnelId || null,
    });

    var facture = col('factures').insert({
      lignes: lignes,
      numero: 'FE-' + String(new Date(date).getFullYear()) + '-' + C.pad(col('factures').all().length + 1, 5),
      numeroMecef: null,
      patientId: p.id, patient: p.nom + ' ' + p.prenom, patientCode: p.code,
      date: C.iso(new Date(date)), type: 'Analyses — patient externe',
      /* Le total est la somme des lignes, comme sur la facture de
         prescription : deux façons de compter divergeraient. */
      montantHT: C.sum(lignes, 'montant'), montantTTC: C.sum(lignes, 'montant'),
      montantBrut: C.sum(lignes, 'montantBrut'), totalRemise: C.sum(lignes, 'remise'),
      partPersonnel: C.sum(lignes, 'partPersonnel'),
      priseEnChargePersonnel: !!p.personnelId, personnelId: p.personnelId || null,
      assureur: p.assureur || null, tauxPriseEnCharge: taux,
      partAssurance: C.sum(lignes, 'partAssureur'),
      partPatient: C.sum(lignes, 'partPatient'),
      montantPaye: 0, reliquat: C.sum(lignes, 'partPatient'),
      modePaiement: null,
      statutPaiement: 'impayee', statutMecef: 'en_attente',
      origineDemande: 'externe',
      prescripteurExterieur: v.prescripteur || null,
    }).record;

    demandes.forEach(function (d) {
      S.collection('demandesAnalyses').update(d.id, { factureId: facture.id, factureNumero: facture.numero });
    });

    /* La caisse est saisie, le prélèvement attend le règlement. */
    var taches = [];
    taches.push(col('taches').insert({
      type: 'encaissement', poste: 'caisse',
      libelle: 'Patient externe — ' + p.nom + ' ' + p.prenom,
      detail: C.num(analyses.length) + ' examen(s) — ' + C.money(montant, false),
      reference: facture.numero, factureId: facture.id,
      patientId: p.id, patient: p.nom + ' ' + p.prenom,
      montant: montant, statut: 'en_attente', creeLe: date,
    }).record);
    taches.push(col('taches').insert({
      type: 'prelevement', poste: 'laboratoire',
      libelle: 'Patient externe — ' + p.nom + ' ' + p.prenom,
      detail: C.num(analyses.length) + ' examen(s)',
      reference: facture.numero, factureId: facture.id,
      patientId: p.id, patient: p.nom + ' ' + p.prenom,
      statut: 'bloque', creeLe: date,
    }).record);

    S.log('Demande externe ouverte', 'M1', 'DemandeAnalyse', facture.numero, null,
      { patient: p.code, examens: analyses.length, montant: montant });

    return { patient: p, demandes: demandes, facture: facture, taches: taches, montant: montant };
  }

  /* ==========================================================================
   * LA DEMANDE D'IMAGERIE (phase 8, cible Instructions)
   * --------------------------------------------------------------------------
   * L'imagerie suit LES MÊMES ÉTATS que le laboratoire : demandée → payée →
   * exécutée → validée. La demande naît bloquée par le paiement ; c'est
   * l'encaissement de SA ligne qui la libère — la ligne payable porte
   * `demandeImagerieId`, comme la ligne d'analyse porte `demandeId`.
   * UNE fabrique pour toutes les voies (consultation, service, saisie du
   * poste) : deux fabriques divergeraient.
   * ======================================================================== */
  function ouvrirDemandeImagerie(v) {
    var p = v.patientId ? S.collection('patients').get(v.patientId)
      : patientParCode(v.patientCode);
    if (!p) throw new Error('Patient introuvable au répertoire.');
    if (!v.examens || !v.examens.length) throw new Error('Cocher au moins un examen d’imagerie.');

    var date = v.date || new Date().toISOString();
    var assure = carteValide(p, date);
    var col_ = S.collection('demandesImagerie', { module: 'M2', entite: 'demande d’imagerie', prefix: 'IME' });

    var demandes = v.examens.map(function (code) {
      var ex = ((D.IMAGERIE && D.IMAGERIE.EXAMENS) || []).filter(function (x) { return x.code === code; })[0];
      /* RG-09 : la validité de la carte À LA DATE décide du tarif. */
      var pr = D.tarifPrix ? D.tarifPrix((ex && ex.tarifCode) || code, assure) : { montant: null };
      return col_.insert({
        reference: C.nextRef('IME-', 5),
        dateHeure: date,
        patientId: p.id, patientCode: p.code, patient: p.nom + ' ' + p.prenom,
        examenCode: code, examen: ex ? ex.label : code,
        prescripteur: v.prescripteur || '—',
        indication: v.indication || '',
        urgent: !!v.urgent,
        secteurDemandeur: v.secteurDemandeur || (secteurCourant() ? secteurCourant().libelle : null),
        origine: v.origine || 'consultation',
        prix: pr.montant, motifTarif: pr.motif || null,
        statut: 'demandee',
        bloqueParPaiement: true,
      }).record;
    });

    var sansPrix = demandes.filter(function (d) { return d.prix == null; });
    if (sansPrix.length) {
      /* Un tiret n'est pas un zéro : une demande sans tarif validé ne se
         facture pas — elle est refusée EN NOMMANT l'examen. */
      demandes.forEach(function (d) { col_.archive(d.id); });
      throw new Error('Tarif non renseigné pour : '
        + sansPrix.map(function (d) { return d.examen; }).join(', ')
        + '. Le renseigner au référentiel tarifaire avant de facturer.');
    }

    var taux = p.assureur ? (p.tauxPriseEnCharge || 0) : 0;
    var lignes = construireLignes({
      taux: taux, personnelId: p.personnelId || null,
      autres: demandes.map(function (d) {
        return { categorie: 'imagerie', designation: d.examen,
          quantite: 1, prixUnitaire: d.prix, montant: d.prix,
          demandeImagerieId: d.id };
      }),
    });

    var facture = col('factures').insert({
      lignes: lignes,
      numero: 'FI-' + String(new Date(date).getFullYear()) + '-' + C.pad(col('factures').all().length + 1, 5),
      numeroMecef: null,
      patientId: p.id, patient: p.nom + ' ' + p.prenom, patientCode: p.code,
      date: C.iso(new Date(date)), type: 'Imagerie',
      montantHT: C.sum(lignes, 'montant'), montantTTC: C.sum(lignes, 'montant'),
      montantBrut: C.sum(lignes, 'montantBrut'), totalRemise: C.sum(lignes, 'remise'),
      partPersonnel: C.sum(lignes, 'partPersonnel'),
      priseEnChargePersonnel: !!p.personnelId, personnelId: p.personnelId || null,
      assureur: p.assureur || null, tauxPriseEnCharge: taux,
      partAssurance: C.sum(lignes, 'partAssureur'),
      partPatient: C.sum(lignes, 'partPatient'),
      montantPaye: 0, reliquat: C.sum(lignes, 'partPatient'),
      modePaiement: null,
      statutPaiement: 'impayee', statutMecef: 'en_attente',
    }).record;

    demandes.forEach(function (d) {
      col_.update(d.id, { factureId: facture.id, factureNumero: facture.numero });
    });

    var taches = [];
    taches.push(col('taches').insert({
      type: 'encaissement', poste: 'caisse',
      libelle: 'Imagerie — ' + p.nom + ' ' + p.prenom,
      detail: C.num(demandes.length) + ' examen(s) — ' + C.money(facture.montantTTC, false),
      reference: facture.numero, factureId: facture.id,
      patientId: p.id, patient: p.nom + ' ' + p.prenom,
      montant: facture.montantTTC, statut: 'en_attente', creeLe: date,
    }).record);
    taches.push(col('taches').insert({
      type: 'imagerie', poste: 'imagerie',
      libelle: 'Examen d’imagerie — ' + p.nom + ' ' + p.prenom,
      detail: demandes.map(function (d) { return d.examen; }).join(', '),
      reference: facture.numero, factureId: facture.id,
      patientId: p.id, patient: p.nom + ' ' + p.prenom,
      statut: 'bloque', creeLe: date,
    }).record);

    notifier({
      type: 'demande_imagerie', poste: 'imagerie',
      libelle: 'Nouvelle demande d’imagerie — ' + p.nom + ' ' + p.prenom,
      detail: demandes.map(function (d) { return d.examen; }).join(', ')
        + ' — exécutable après passage en caisse',
      priorite: v.urgent ? 'haute' : 'normale',
      patientId: p.id, reference: facture.numero,
    });

    S.log('Demande d’imagerie ouverte', 'M2', 'DemandeImagerie', facture.numero, null,
      { patient: p.code, examens: demandes.length, montant: facture.montantTTC });

    return { patient: p, demandes: demandes.map(function (d) { return col_.get(d.id); }), facture: facture, taches: taches };
  }

  /* ==========================================================================
   * LE CODE D'ANALYSE UNIQUE — NNNNN-AAAA (phase 6, cible Instructions)
   * --------------------------------------------------------------------------
   * Série ANNUELLE, comme les pièces certifiantes : le registre papier du
   * laboratoire repart à 1 chaque année. UNE SEULE fabrique pour toutes les
   * voies — ordonnance, transcription à l'accueil, saisie du laboratoire,
   * jeu de démonstration : deux fabriques divergeraient au premier correctif
   * (c'est le défaut déjà rencontré sur le code patient, qui vivait à deux
   * endroits). La référence LAB-NNNNN reste : elle identifie la DEMANDE dans
   * le logiciel, le code d'analyse identifie le DOSSIER au registre annuel.
   * ======================================================================== */
  function codeAnalyse(date) {
    var d = date ? new Date(date) : new Date();
    var annee = String(isNaN(d.getTime()) ? new Date().getFullYear() : d.getFullYear());
    var max = 0;
    S.collection('demandesAnalyses').all().forEach(function (x) {
      var m = /^(\d{5})-(\d{4})$/.exec(x.codeAnalyse || '');
      if (m && m[2] === annee && +m[1] > max) max = +m[1];
    });
    return C.pad(max + 1, 5) + '-' + annee;
  }

  /* ==========================================================================
   * LES LIGNES PAYABLES D'UNE FACTURE
   * --------------------------------------------------------------------------
   * Une ligne par prestation, et le lien vers ce qu'elle couvre. Sans ce lien,
   * régler « trois examens sur cinq » ne pourrait pas désigner LESQUELS trois
   * passent au laboratoire.
   *
   * Chaque ligne porte sa part patient et sa part assureur : c'est la part
   * PATIENT qui se règle à la caisse, la part assureur suit son propre
   * circuit de recouvrement.
   * ======================================================================== */
  function construireLignes(v) {
    var lignes = [];
    var taux = Number(v.taux) || 0;
    /* La prise en charge de l'établissement se DÉDUIT du dossier : un agent
       n'a pas à la réclamer au guichet, et la lui faire demander reviendrait à
       l'oublier le jour où il est pressé. Ce n'est pas une assurance — aucun
       tiers ne rembourse, aucune créance ne naît. */
    var estAgent = !!v.personnelId;
    var n = 0;

    function ajouter(o) {
      n++;
      var brut = Math.round(Number(o.montant) || 0);
      var remise = Math.round(Number(o.remise) || 0);
      /* RG-02 — pas de remise sur un médicament : il se facture au prix
         d'achat, une remise le vendrait à perte. */
      if (o.categorie === 'medicament') remise = 0;
      var montant = brut - remise;

      var partAssureur = estAgent ? 0 : Math.round(montant * taux / 100);
      var partPersonnel = estAgent ? montant : 0;

      lignes.push({
        id: 'L' + C.pad(n, 3),
        categorie: o.categorie, designation: o.designation,
        quantite: o.quantite != null ? o.quantite : 1,
        prixUnitaire: o.prixUnitaire != null ? o.prixUnitaire : brut,
        prixUnitaireNet: (o.quantite || 1) ? Math.round(montant / (o.quantite || 1)) : montant,
        montantBrut: brut,
        remise: remise,
        motifRemise: remise ? (o.motifRemise || 'Remise accordée') : null,
        montant: montant,
        partAssureur: partAssureur,
        partPersonnel: partPersonnel,
        partPatient: montant - partAssureur - partPersonnel,
        /* Le lien vers ce que la ligne couvre. */
        demandeId: o.demandeId || null,
        produitId: o.produitId || null,
        acteCode: o.acteCode || null,
        demandeImagerieId: o.demandeImagerieId || null,
        /* L'état de règlement, ligne par ligne. */
        statutPaiement: 'du',
        montantRegle: 0, payeLe: null, payePar: null,
      });
    }

    (v.medicaments || []).forEach(function (m) {
      ajouter({
        categorie: 'medicament', designation: m.produit,
        quantite: m.quantite, prixUnitaire: m.prix, montant: m.total,
        produitId: m.produitId,
      });
    });

    (v.analyses || []).forEach(function (a, i) {
      var dem = (v.demandes || [])[i];
      ajouter({
        categorie: 'analyse', designation: a.designation,
        quantite: 1, prixUnitaire: a.prix, montant: a.prix,
        demandeId: dem ? dem.id : null,
      });
    });

    (v.actes || []).forEach(function (a) {
      ajouter({
        categorie: 'acte', designation: a.libelle,
        quantite: 1, prixUnitaire: a.prix || 0, montant: a.prix || 0,
        acteCode: a.code,
      });
    });

    (v.autres || []).forEach(function (o) { ajouter(o); });
    return lignes;
  }

  /** Les lignes encore dues d'une facture, dans l'ordre de la pièce. */
  function lignesDues(facture) {
    return (facture.lignes || []).filter(function (l) { return l.statutPaiement !== 'paye'; });
  }

  /** Les lignes réglées d'une facture. */
  function lignesReglees(facture) {
    return (facture.lignes || []).filter(function (l) { return l.statutPaiement === 'paye'; });
  }

  /* ==========================================================================
   * LE COMPTABLE EST INFORMÉ
   * --------------------------------------------------------------------------
   * « La caisse valide → le comptable est informé. » Informer ne suffit pas :
   * un encaissement qui ne produit pas d'écriture oblige à ressaisir la
   * recette à la main, et c'est exactement ce que la clinique fait aujourd'hui
   * entre PERFECTO et la caisse.
   *
   * L'écriture est EQUILIBRÉE (RG-10) et double quand le patient est assuré :
   *   — débit  571 Caisse            de la part réglée par le patient ;
   *   — débit  411 Clients assurance de la part restant due par l'assureur ;
   *   — crédit 706 Prestations       du total facturé.
   *
   * Elle naît en BROUILLON : la validation comptable reste un geste humain.
   * ======================================================================== */
  var COMPTES_CAISSE = {
    caisse: { num: '5711', libelle: 'Caisse' },
    clientsAssurance: { num: '4111', libelle: 'Clients compagnie d’assurance' },
    prestations: { num: '7061', libelle: 'Services vendus — prestations de soins' },
  };

  function ecrireEncaissement(facture, montantRegle) {
    var lignes = [];
    var partAssureur = Number(facture.partAssureur) || 0;
    var total = montantRegle + partAssureur;
    if (total <= 0) return [];

    var numero = 'CAI-2026-' + String(facture.numero || facture.id).replace(/[^0-9]/g, '').slice(-5);
    var base = {
      numero: numero, date: C.iso(new Date()),
      journal: 'CAI', journalLibelle: 'Journal de caisse-dépenses',
      libelle: 'Encaissement facture ' + (facture.numero || facture.id)
        + ' — ' + (facture.patient || ''),
      pieceId: facture.id, pieceNumero: facture.numero,
      origine: 'Automatique — Caisse',
      statut: 'brouillon',
    };

    if (montantRegle > 0) {
      lignes.push(Object.assign({}, base, {
        compte: COMPTES_CAISSE.caisse.num, compteLibelle: COMPTES_CAISSE.caisse.libelle,
        debit: montantRegle, credit: 0,
      }));
    }
    if (partAssureur > 0) {
      lignes.push(Object.assign({}, base, {
        compte: COMPTES_CAISSE.clientsAssurance.num,
        compteLibelle: COMPTES_CAISSE.clientsAssurance.libelle,
        debit: partAssureur, credit: 0,
        libelle: base.libelle + ' — part ' + (facture.assureur || 'assureur'),
      }));
    }
    lignes.push(Object.assign({}, base, {
      compte: COMPTES_CAISSE.prestations.num, compteLibelle: COMPTES_CAISSE.prestations.libelle,
      debit: 0, credit: total,
    }));

    /* Contrôle RG-10 avant écriture : un déséquilibre ne doit pas entrer au
       journal, fût-il en brouillon. */
    var debit = lignes.reduce(function (n, l) { return n + l.debit; }, 0);
    var credit = lignes.reduce(function (n, l) { return n + l.credit; }, 0);
    if (debit !== credit) {
      S.log('Écriture d’encaissement refusée — déséquilibre', 'M12', 'Ecriture', numero,
        null, { debit: debit, credit: credit });
      return [];
    }

    var posees = lignes.map(function (l) { return col('ecritures').insert(l).record; });
    S.log('Écriture d’encaissement', 'M12', 'Ecriture', numero, null,
      { debit: debit, credit: credit, lignes: posees.length });
    return posees;
  }

  /* ==========================================================================
   * LE STOCK EST INFORMÉ
   * --------------------------------------------------------------------------
   * « Le stock est informé des stocks épuisés et de l'approvisionnement. »
   * Une délivrance qui fait passer un article sous son seuil doit le dire au
   * gestionnaire — au moment où elle a lieu, et non le jour de l'inventaire.
   *
   * Le seuil est celui que la clinique a fixé (il est absent du document
   * SAGE) : sans seuil, aucune alerte n'est possible, et l'article est
   * signalé comme tel plutôt que passé sous silence.
   * ======================================================================== */
  function alerterStock(produitIds, justificatif) {
    var alertes = [];
    (produitIds || []).forEach(function (id) {
      var prod = produitParId(id);
      if (!prod) return;
      var dispo = prod.stockDetail != null ? prod.stockDetail : prod.stock;
      var seuil = prod.seuilAlerte;
      var niveau = null;
      if (dispo <= 0) niveau = 'rupture';
      else if (seuil != null && seuil !== '' && dispo <= seuil) niveau = 'alerte';
      else if (seuil == null || seuil === '') niveau = 'sansSeuil';
      if (!niveau || niveau === 'sansSeuil') {
        if (niveau === 'sansSeuil') {
          alertes.push({ produit: prod, niveau: niveau, dispo: dispo, seuil: null });
        }
        return;
      }
      /* Une seule tâche ouverte par article : réalerter à chaque sortie
         noierait le gestionnaire sous les doublons. */
      var deja = taches().filter(function (t) {
        return t.type === 'reapprovisionnement' && t.produitId === id
          && t.statut !== 'termine';
      })[0];
      if (deja) {
        col('taches').update(deja.id, {
          stockRestant: dispo,
          libelle: (niveau === 'rupture' ? 'RUPTURE — ' : 'Sous le seuil — ') + prod.designation,
        });
      } else {
        col('taches').insert({
          type: 'reapprovisionnement', poste: 'stock',
          libelle: (niveau === 'rupture' ? 'RUPTURE — ' : 'Sous le seuil — ') + prod.designation,
          produitId: id, produitCode: prod.code,
          stockRestant: dispo, seuil: seuil,
          justificatif: justificatif || null,
          statut: 'en_attente', priorite: niveau === 'rupture' ? 'haute' : 'normale',
          creeLe: new Date().toISOString(),
        });
      }
      alertes.push({ produit: prod, niveau: niveau, dispo: dispo, seuil: seuil });
    });
    return alertes;
  }

  /**
   * encaisser(factureId, opts)
   *
   * opts.lignes   — identifiants des lignes réglées. C'est la forme JUSTE :
   *                 la caisse encaisse des prestations nommées.
   * opts.montant  — forme héritée. Le montant est alors ALLOUÉ aux lignes
   *                 encore dues, dans l'ordre de la pièce, jusqu'à épuisement.
   *                 Une ligne n'est réglée que si elle l'est entièrement :
   *                 un demi-examen ne se prélève pas.
   *
   * Dans les deux cas le résultat est le même — des lignes réglées, nommées,
   * et un déblocage qui ne porte que sur elles.
   */
  function encaisser(factureId, opts) {
    opts = opts || {};
    var fac = col('factures').get(factureId);
    if (!fac) throw new Error('Facture introuvable.');
    if (fac.statutPaiement === 'soldee') return { facture: fac, deja: true, lignesReglees: [] };

    var toutes = fac.lignes || [];
    var duTotal = fac.partPatient != null ? fac.partPatient : fac.montantTTC;

    /* --- Quelles lignes sont réglées par ce versement ? ------------------ */
    var reglees = [];
    var paye = 0;

    if (opts.lignes && opts.lignes.length) {
      var vises = {};
      opts.lignes.forEach(function (id) { vises[id] = true; });
      toutes.forEach(function (l) {
        if (l.statutPaiement === 'paye' || !vises[l.id]) return;
        reglees.push(l); paye += l.partPatient;
      });
    } else if (toutes.length) {
      /* Allocation d'un montant global : les lignes dues, dans l'ordre, tant
         que la somme versée les couvre ENTIÈREMENT. */
      var reste = opts.montant != null ? Number(opts.montant) : duTotal;
      toutes.forEach(function (l) {
        if (l.statutPaiement === 'paye') return;
        if (l.partPatient <= reste) { reglees.push(l); reste -= l.partPatient; paye += l.partPatient; }
      });
    } else {
      /* Facture sans lignes — pièce antérieure au modèle. On conserve le
         comportement par montant plutôt que de la rendre inencaissable. */
      paye = opts.montant != null ? Number(opts.montant) : duTotal;
    }

    /* --- Report sur la facture ------------------------------------------- */
    var lignesMaj = toutes.map(function (l) {
      if (reglees.indexOf(l) === -1) return l;
      return Object.assign({}, l, {
        statutPaiement: 'paye', montantRegle: l.partPatient,
        payeLe: new Date().toISOString(),
        payePar: opts.utilisateur || S.currentUser(),
      });
    });
    var totalPaye = (fac.montantPaye || 0) + paye;
    var restantDu = lignesMaj.length
      ? lignesMaj.filter(function (l) { return l.statutPaiement !== 'paye'; })
        .reduce(function (n, l) { return n + l.partPatient; }, 0)
      : Math.max(0, duTotal - totalPaye);
    var solde = restantDu <= 0;

    col('factures').update(factureId, {
      lignes: lignesMaj,
      montantPaye: totalPaye,
      reliquat: restantDu,
      modePaiement: opts.mode || 'especes',
      statutPaiement: solde ? 'soldee' : (totalPaye > 0 ? 'partielle' : 'impayee'),
      statutMecef: solde ? 'valide' : 'en_attente',
      /* Le point fiscal du dossier : seule la part réglée est normalisée. */
      baseMecef: totalPaye,
      dernierReglement: {
        date: new Date().toISOString(), montant: paye, mode: opts.mode || 'especes',
        lignes: reglees.map(function (l) { return l.id; }),
        encaissePar: opts.utilisateur || S.currentUser(),
      },
    });
    fac = col('factures').get(factureId);

    /* --- Le laboratoire : SEULES les analyses réglées passent ------------- */
    var demandesLiberees = [];
    reglees.forEach(function (l) {
      if (l.categorie !== 'analyse' || !l.demandeId) return;
      var d = S.collection('demandesAnalyses').get(l.demandeId);
      if (!d) return;
      S.collection('demandesAnalyses').update(l.demandeId, {
        bloqueParPaiement: false, statutPaiement: 'soldee',
        etatAnalyse: d.etatAnalyse === 'valide' ? 'valide' : 'attente_prelevement',
        regleLe: new Date().toISOString(),
      });
      demandesLiberees.push(d.reference || d.id);
    });

    /* --- L'imagerie suit la même règle : la séance réglée passe ----------- */
    reglees.forEach(function (l) {
      if (l.categorie !== 'imagerie' || !l.demandeImagerieId) return;
      var di = S.collection('demandesImagerie').get(l.demandeImagerieId);
      if (!di) return;
      S.collection('demandesImagerie').update(l.demandeImagerieId, {
        bloqueParPaiement: false,
        statut: di.statut === 'demandee' ? 'payee' : di.statut,
        regleLe: new Date().toISOString(),
      });
      demandesLiberees.push(di.reference || di.id);
    });

    var debloquees = [];
    if (fac.statutPaiement === 'soldee') {
      /* La tâche de caisse est faite ; celles d'aval s'ouvrent. */
      taches().filter(function (t) { return t.factureId === factureId; }).forEach(function (t) {
        if (t.type === 'encaissement') { terminer(t.id, opts.utilisateur); return; }
        if (t.statut === 'bloque') {
          col('taches').update(t.id, { statut: 'en_attente' });
          debloquees.push(t.type);
        }
      });
      /* Facture soldée : ce qui resterait bloqué faute de ligne — les pièces
         antérieures au modèle par lignes — est libéré ici. Les analyses déjà
         libérées ligne par ligne ne sont pas retouchées. */
      S.collection('demandesAnalyses').all().forEach(function (d) {
        if (!d.bloqueParPaiement) return;
        if (d.factureId === factureId || (fac.ordonnanceId && d.ordonnanceId === fac.ordonnanceId)) {
          S.collection('demandesAnalyses').update(d.id, {
            bloqueParPaiement: false,
            statutPaiement: 'soldee',
            etatAnalyse: d.etatAnalyse === 'valide' ? 'valide' : 'attente_prelevement',
            regleLe: new Date().toISOString(),
          });
          demandesLiberees.push(d.reference || d.id);
        }
      });
      S.collection('demandesImagerie').all().forEach(function (di) {
        if (!di.bloqueParPaiement || di.factureId !== factureId) return;
        S.collection('demandesImagerie').update(di.id, {
          bloqueParPaiement: false,
          statut: di.statut === 'demandee' ? 'payee' : di.statut,
          regleLe: new Date().toISOString(),
        });
        demandesLiberees.push(di.reference || di.id);
      });
      if (fac.ordonnanceId) col('ordonnances').update(fac.ordonnanceId, { statutPaiement: 'soldee' });
    }

    /* Le comptable est informé — par une écriture, pas par un message.
       Elle est posée à CHAQUE versement, y compris partiel : attendre le
       solde laisserait la caisse et la comptabilité divergentes entre-temps. */
    var ecritures = paye > 0 ? ecrireEncaissement(fac, paye) : [];

    S.log('Encaissement', 'M8', 'facture', fac.numero, { statutPaiement: 'impayee' },
      {
        statutPaiement: fac.statutPaiement, montantPaye: totalPaye,
        verse: paye, lignes: reglees.length, restantDu: restantDu,
      });

    return {
      facture: fac, debloquees: debloquees, ecritures: ecritures,
      lignesReglees: reglees, montantRegle: paye,
      restantDu: restantDu, demandesLiberees: demandesLiberees,
    };
  }

  /* ==========================================================================
   * 3. LA PHARMACIE DÉLIVRE
   * --------------------------------------------------------------------------
   * RG-03 : chaque sortie porte son justificatif — le numéro d'ordonnance — et
   * le stock ne peut pas passer sous zéro. Une ligne insuffisante bloque la
   * délivrance entière plutôt que de servir à moitié sans le dire.
   * ======================================================================== */
  function verifierStock(ordonnanceId) {
    var ord = col('ordonnances').get(ordonnanceId);
    if (!ord) throw new Error('Ordonnance introuvable.');
    return (ord.medicaments || []).map(function (l) {
      var prod = produitParId(l.produitId);
      var dispo = prod ? (prod.stockDetail != null ? prod.stockDetail : prod.stock) : 0;
      return { ligne: l, produit: prod, disponible: dispo, suffisant: prod && dispo >= l.quantite };
    });
  }

  /* Valorisation d'une sortie de stock — paramétrable (annotation manuscrite
     de la réunion du 30/12/2024). Le mouvement porte LES DEUX valeurs : sans
     cela, changer de méthode rendrait l'historique incomparable. */
  function valoriserSortie(produit, quantite) {
    var pv = (produit.prixVente != null ? produit.prixVente : produit.prixAchat) || 0;
    var cump = produit.cump != null ? produit.cump : pv;
    var methode = S.valorisationSortie();
    var retenu = methode === 'cump' ? cump : pv;
    return {
      methode: methode,
      valeur: Math.round(retenu * quantite),
      valeurPrixVente: Math.round(pv * quantite),
      valeurCump: Math.round(cump * quantite),
      ecart: Math.round((pv - cump) * quantite),
    };
  }

  /** Alerte le gestionnaire de stock après une sortie. Voir alerterStock(). */
  function delivrer(ordonnanceId, opts) {
    opts = opts || {};
    var ord = col('ordonnances').get(ordonnanceId);
    if (!ord) throw new Error('Ordonnance introuvable.');
    if (ord.statutPaiement !== 'soldee') throw new Error('Facture non réglée — la délivrance est bloquée.');
    if (ord.statutDispensation === 'servie') return { ordonnance: ord, deja: true };

    var etat = verifierStock(ordonnanceId);
    var manquants = etat.filter(function (e) { return !e.suffisant; });
    if (manquants.length) {
      /* RG-03 — jamais de stock négatif : on refuse et on dit lequel. */
      var e = new Error('Stock insuffisant : ' + manquants.map(function (m) {
        return m.ligne.produit + ' (' + m.disponible + ' pour ' + m.ligne.quantite + ' demandés)';
      }).join(', '));
      e.manquants = manquants;
      throw e;
    }

    var mouvements = etat.map(function (x) {
      var prod = x.produit;
      var reste = (prod.stockDetail != null ? prod.stockDetail : prod.stock) - x.ligne.quantite;
      S.collection('produits').update(prod.id, {
        stockDetail: prod.stockDetail != null ? reste : prod.stockDetail,
        stock: Math.max(0, (prod.stock || 0) - x.ligne.quantite),
      });
      var val = valoriserSortie(prod, x.ligne.quantite);
      return col('mouvements').insert({
        reference: C.nextRef('M', 6),
        date: new Date().toISOString(),
        produitId: prod.id, produit: prod.designation,
        type: 'sortie', typeLabel: 'Sortie',
        quantite: x.ligne.quantite,
        stockType: 'detail',
        justificatif: 'Ordonnance ' + ord.numero,
        ordonnanceId: ord.id,
        /* Valorisation : méthode retenue et les deux valeurs, pour comparaison. */
        valorisation: val.methode, valeur: val.valeur,
        valeurPrixVente: val.valeurPrixVente, valeurCump: val.valeurCump,
        utilisateur: opts.utilisateur || S.currentUser(),
      }).record;
    });

    col('ordonnances').update(ordonnanceId, {
      statutDispensation: 'servie',
      dispenseLe: new Date().toISOString(),
      dispensePar: opts.utilisateur || S.currentUser(),
    });
    taches().filter(function (t) { return t.ordonnanceId === ordonnanceId && t.type === 'dispensation'; })
      .forEach(function (t) { terminer(t.id, opts.utilisateur); });

    S.log('Dispensation', 'M6', 'ordonnance', ord.numero, { statutDispensation: 'en_attente' },
      { statutDispensation: 'servie', lignes: mouvements.length });

    /* Le gestionnaire de stock est informé au moment où la sortie a lieu, et
       non le jour de l’inventaire : c’est la sortie qui fait passer sous le
       seuil, c’est elle qui doit le dire. */
    var alertes = alerterStock(etat.map(function (x) { return x.produit ? x.produit.id : null; })
      .filter(Boolean), ord.numero);

    return { ordonnance: col('ordonnances').get(ordonnanceId), mouvements: mouvements, alertes: alertes };
  }

  /* ==========================================================================
   * 4. FILES D'ATTENTE
   * ======================================================================== */
  function taches() { return col('taches').active(); }

  /** Ce qui attend un poste de travail : d'abord l'urgent, puis le plus ancien. */
  function aFaire(role, type) {
    return taches().filter(function (t) {
      if (t.statut === 'fait') return false;
      if (role && t.role !== role) return false;
      if (type && t.type !== type) return false;
      return true;
    }).sort(function (a, b) {
      if (!!b.urgent !== !!a.urgent) return b.urgent ? 1 : -1;
      return String(a.date).localeCompare(String(b.date));
    });
  }

  function terminer(tacheId, utilisateur) {
    return col('taches').update(tacheId, {
      statut: 'fait', faitLe: new Date().toISOString(), faitPar: utilisateur || S.currentUser(),
    });
  }

  /** Compteurs d'attente, pour les badges des tableaux de bord. */
  function compteurs(role) {
    var out = { total: 0 };
    aFaire(role).forEach(function (t) {
      out[t.type] = (out[t.type] || 0) + 1;
      if (t.statut === 'en_attente') out.total++;
    });
    return out;
  }

  /** Toutes les pièces attachées à une ordonnance — vue de bout en bout. */
  function dossier(ordonnanceId) {
    var ord = col('ordonnances').get(ordonnanceId);
    if (!ord) return null;
    return {
      ordonnance: ord,
      facture: ord.factureId ? col('factures').get(ord.factureId) : null,
      demandes: S.collection('demandesAnalyses').all().filter(function (d) { return d.ordonnanceId === ordonnanceId; }),
      mouvements: S.collection('mouvements').all().filter(function (m) { return m.ordonnanceId === ordonnanceId; }),
      taches: taches().filter(function (t) { return t.ordonnanceId === ordonnanceId; }),
    };
  }

  /* ==========================================================================
   * PRISE EN CHARGE — répartition ligne par ligne
   * --------------------------------------------------------------------------
   * Le cahier de charge du 30/12/2024 l'exige : « appliquer des pourcentages
   * par article et par prestation », le taux variant « d'une assurance à
   * l'autre et, pour un même assuré, selon la nature de l'article ». Un taux
   * unique par patient ne peut pas exprimer cela.
   *
   * La répartition suit donc quatre questions, dans cet ordre :
   *   1. la carte est-elle valide à la date de facturation ?      (RG-09)
   *   2. la ligne est-elle exclue par la convention ?
   *   3. exige-t-elle un accord préalable, et l'a-t-on ?
   *   4. quelle garantie couvre sa catégorie, à quel taux, sous quel plafond ?
   *
   * Chaque ligne repart avec son MOTIF : une part patient à 100 % doit toujours
   * pouvoir s'expliquer au guichet.
   * ======================================================================== */
  function souscripteurDe(patient) {
    if (!patient || !patient.souscripteurId) return null;
    return S.collection('souscripteurs').get(patient.souscripteurId);
  }

  /** Garanties applicables : celles du souscripteur, sinon celles de la compagnie. */
  function garantiesDe(patient) {
    var sous = souscripteurDe(patient);
    if (!sous) return [];
    var toutes = S.collection('garanties').active();
    var propres = toutes.filter(function (g) { return g.souscripteurId === sous.id; });
    if (propres.length) return propres;
    return toutes.filter(function (g) { return !g.souscripteurId && g.assureur === sous.assureur; });
  }

  function carteValide(patient, date) {
    if (!patient || !patient.assureur) return false;
    if (!patient.carteExpiration) return false;
    return C.toDate(patient.carteExpiration).getTime() >= C.toDate(date || new Date()).getTime();
  }

  /* Nombre de mots significatifs partagés par deux libellés : « consultation
     généraliste » colle à « Consultation généraliste » (2) et non à
     « Consultation spécialiste ou professeur » (1). */
  function mots(t) {
    var s = String(t || '').toLowerCase();
    if (s.normalize) s = s.normalize('NFD').replace(/[̀-ͯ]/g, '');
    return s.split(/[^a-z0-9]+/);
  }
  function proximite(a, b) {
    var ma = mots(a).filter(function (m) { return m.length > 3; });
    var mb = mots(b).filter(function (m) { return m.length > 3; });
    var n = 0;
    ma.forEach(function (m) { if (mb.indexOf(m) >= 0) n++; });
    return n;
  }

  function contient(liste, texte) {
    if (!liste || !liste.length || !texte) return null;
    var t = String(texte).toLowerCase();
    for (var i = 0; i < liste.length; i++) {
      var e = String(liste[i]).toLowerCase();
      if (t.indexOf(e) >= 0 || e.indexOf(t) >= 0) return liste[i];
    }
    return null;
  }

  /**
   * repartir(patient, lignes, opts) — lignes : [{libelle, categorie, montant, accordObtenu}]
   * Retourne chaque ligne enrichie de partAssureur, partPatient et motif,
   * plus les totaux de la facture.
   */
  function repartir(patient, lignes, opts) {
    opts = opts || {};
    var date = opts.date || new Date().toISOString();
    var sous = souscripteurDe(patient);
    var grille = garantiesDe(patient);
    var valide = carteValide(patient, date);

    var detail = (lignes || []).map(function (l) {
      var montant = Number(l.montant) || 0;
      var base = {
        libelle: l.libelle, categorie: l.categorie || 'autre', montant: montant,
        partAssureur: 0, partPatient: montant, taux: 0, plafond: null, garantie: null,
      };

      if (!patient || !patient.assureur) {
        return Object.assign(base, { motif: 'Patient non assuré' });
      }
      if (!valide) {
        /* RG-09 — carte invalide à la date de facturation : facturation intégrale. */
        return Object.assign(base, { motif: 'Carte non valide à la date de facturation (RG-09)' });
      }
      if (!sous) {
        return Object.assign(base, { motif: 'Assuré non rattaché à un souscripteur' });
      }
      if (!grille.length) {
        return Object.assign(base, { motif: 'Convention non saisie pour ' + sous.nom });
      }

      var exclu = contient(sous.actesExclus, l.libelle) || contient(sous.produitsExclus, l.libelle);
      if (exclu) {
        return Object.assign(base, { motif: 'Exclu de la convention : ' + exclu, exclu: true });
      }

      var accord = contient(sous.accordPrealable, l.libelle);
      if (accord && !l.accordObtenu) {
        return Object.assign(base, {
          motif: 'Accord préalable requis et non obtenu : ' + accord,
          accordRequis: accord,
        });
      }

      /* Une catégorie porte souvent plusieurs garanties — le barème distingue
         la consultation généraliste de la consultation spécialiste, plafonnées
         à 5 000 et 10 000 FCFA. Prendre la première venue appliquerait le mauvais
         plafond : on retient celle dont le libellé colle le mieux à la ligne. */
      var candidates = grille.filter(function (x) { return x.categorie === base.categorie; });
      if (!candidates.length) {
        return Object.assign(base, { motif: 'Aucune garantie pour la catégorie « ' + base.categorie + ' »' });
      }
      var g = candidates[0], meilleur = -1;
      candidates.forEach(function (x) {
        var s = proximite(x.libelle, l.libelle);
        if (s > meilleur) { meilleur = s; g = x; }
      });

      var couvert = Math.round(montant * (g.taux || 0) / 100);
      var motif = 'Garantie ' + g.libelle + ' — ' + g.taux + ' %';
      if (g.plafond != null && couvert > g.plafond) {
        couvert = g.plafond;
        motif += ', plafonnée à ' + C.money(g.plafond, false)
          + (g.unitePlafond ? ' ' + libelleUnite(g.unitePlafond) : '');
      }
      return Object.assign(base, {
        partAssureur: couvert, partPatient: montant - couvert,
        taux: g.taux, plafond: g.plafond, garantie: g.libelle, motif: motif,
      });
    });

    return {
      lignes: detail,
      souscripteur: sous, carteValide: valide, grilleSaisie: grille.length > 0,
      total: C.sum(detail, 'montant'),
      partAssureur: C.sum(detail, 'partAssureur'),
      partPatient: C.sum(detail, 'partPatient'),
    };
  }

  function libelleUnite(id) {
    var u = D.UNITES_PLAFOND.filter(function (x) { return x.id === id; })[0];
    return u ? u.label : id;
  }

  /** Catégorie de garantie d'une ligne, déduite de sa nature. */
  function categoriser(ligne) {
    if (ligne.analyseCode || ligne.type === 'analyse') return 'analyse';
    if (ligne.produitId || ligne.type === 'medicament') {
      return /vitamin|fortifiant/i.test(ligne.libelle || ligne.produit || '') ? 'vitamine' : 'medicament';
    }
    var acte = (ligne.code && acteParCode(ligne.code)) || null;
    var secteur = acte ? acte.secteur : (ligne.secteur || '');
    if (/Imagerie/i.test(secteur)) return 'imagerie';
    if (/Maternité/i.test(secteur)) return 'maternite';
    if (/Chirurgie/i.test(secteur)) return 'chirurgie';
    if (/Hospitalisation/i.test(secteur)) return 'hospitalisation';
    if (/Médecine générale/i.test(secteur)) return /[Cc]ertificat/.test(ligne.libelle || '') ? 'certificat' : 'consultation';
    if (/Soins/i.test(secteur)) return 'soin';
    return 'autre';
  }

  /* ==========================================================================
   * HABILITATIONS MÉTIER — ce que l'agent peut VOIR, pas seulement ouvrir
   * --------------------------------------------------------------------------
   * Le manifeste `nav.js` décide des écrans par rôle. Il ne suffit pas : deux
   * agents peuvent ouvrir le même écran et ne devoir y voir ni les mêmes
   * lignes ni les mêmes colonnes. La Direction l'a dit sans ambiguïté — le
   * médecin voit tous les résultats, la sage-femme ceux de la maternité,
   * l'infirmier aucun, l'aide-soignant pas davantage.
   *
   * Trois axes, et non un seul :
   *   RÔLE       → les écrans          (nav.js)
   *   FONCTION   → les capacités       (D.CAPACITES)
   *   SECTEUR    → le périmètre        (collection `secteurs`, NS 145)
   * ======================================================================== */

  /** Fonction déduite d'une session — le rôle sert de repli. */
  var ROLE_VERS_FONCTION = {
    medecin: 'medecin', dm: 'medecin', direction: 'direction', da: 'direction',
    infirmier: 'infirmier', pharmacien: 'dispensatrice', laborantin: 'tsl',
    caissier: 'caissiere', reception: 'accueil', stock: 'stock',
    comptable: 'comptable', rh: 'direction', admin: 'direction',
    agentadmin: 'entretien', ambulancier: 'chauffeur',
  };

  function capacites(session) {
    var s = session || S.session() || {};
    var demandee = s.fonction || null;
    var duRole = ROLE_VERS_FONCTION[s.role] || null;

    /* UNE FONCTION INCONNUE NE FERME PAS L'ÉCRAN EN SILENCE. Elle retombe sur
       la fonction déduite du RÔLE — donnée sûre, venue du manifeste et non
       d'une saisie — et la substitution est signalée. Retomber sur « accueil »,
       le profil le plus restrictif, faisait qu'un agent parfaitement habilité
       ouvrait son poste, ne voyait rien, et lisait qu'il n'avait pas accès. */
    var inconnue = !!(demandee && !D.CAPACITES[demandee]);
    var f = (demandee && D.CAPACITES[demandee]) ? demandee : (duRole || 'accueil');

    return Object.assign({
      fonction: f,
      fonctionInconnue: inconnue ? demandee : null,
    }, D.CAPACITES[f] || D.CAPACITES.accueil);
  }

  /** Secteur d'affectation de l'agent connecté (NS 145). */
  function secteurCourant(session) {
    var s = session || S.session() || {};
    if (!s.secteur) return null;
    var t = S.collection('secteurs').active().filter(function (x) {
      return x.code === s.secteur || x.id === s.secteur;
    });
    return t[0] || null;
  }

  /**
   * peutVoirResultat(demande, session) — décide, et dit pourquoi.
   * Retourne { autorise, motif }. Le motif est destiné à l'écran : un refus
   * muet laisse croire à une donnée manquante plutôt qu'à une restriction.
   */
  function peutVoirResultat(demande, session) {
    var cap = capacites(session);

    /* LE PREMIER VERROU, avant toute question d'habilitation : un résultat
       non validé biologiquement n'existe pas pour le prescripteur. C'est
       toute la raison d'être des deux validations — entre la saisie et la
       validation biologique, le laboratoire relit, et personne d'autre ne
       lit par-dessus son épaule. Le laboratoire, lui, voit son propre
       travail en cours, sans quoi il ne pourrait pas le relire. */
    var duLabo = cap.voirResultats === 'produits' || cap.validerTechnique;
    if (demande && demande.etatAnalyse && !duLabo
      && !D.resultatRendu(demande.etatAnalyse)) {
      return {
        autorise: false,
        motif: 'Résultat non encore validé biologiquement — '
          + D.etatResultat(demande.etatAnalyse).label.toLowerCase()
          + '. Le laboratoire le relit avant de le rendre.',
        enAttenteValidation: true,
      };
    }

    if (cap.voirResultats === 'tous') {
      return { autorise: true, motif: cap.label + ' — accès à tous les résultats' };
    }
    if (cap.voirResultats === 'aucun') {
      return { autorise: false, motif: cap.label + ' — les résultats d’analyses ne lui sont pas accessibles' };
    }
    if (cap.voirResultats === 'produits') {
      /* Le laboratoire voit ce qu'il produit, et le remet aux patients externes. */
      return { autorise: true, motif: 'Laboratoire — résultat produit par le service' };
    }
    if (cap.voirResultats === 'secteur') {
      var sect = secteurCourant(session);
      var demandeur = demande && (demande.secteurDemandeur || demande.secteur);
      var mien = (sect && sect.libelle) || (cap.secteurs || [])[0] || '';
      var ok = demandeur && mien && String(demandeur).toUpperCase().indexOf(String(mien).toUpperCase()) >= 0;
      return {
        autorise: !!ok,
        motif: ok
          ? cap.label + ' — résultat demandé par son secteur (' + demandeur + ')'
          : cap.label + ' — résultat demandé par ' + (demandeur || 'un autre secteur') + ', hors de son périmètre',
      };
    }
    return { autorise: false, motif: 'Périmètre non défini' };
  }

  function peutPrescrire(nature, session) {
    var cap = capacites(session);
    return (cap.prescrire || []).indexOf(nature) >= 0;
  }

  function peutExecuterSoin(session) { return !!capacites(session).executerSoins; }

  /** Filtre une liste de demandes/résultats selon l'habilitation. */
  function filtrerResultats(liste, session) {
    return (liste || []).filter(function (d) { return peutVoirResultat(d, session).autorise; });
  }

  /* ==========================================================================
   * PRISE EN CHARGE DU PERSONNEL
   * --------------------------------------------------------------------------
   * La clinique soigne ses agents à 100 %. Ce n'est PAS une assurance au sens
   * de M9 : aucun tiers ne rembourse, aucune créance ne naît, et la prestation
   * ne constitue ni une recette ni une charge à comptabiliser — c'est un
   * avantage consenti par l'employeur, dont on veut connaître le VOLUME.
   *
   * D'où trois règles que le reste du logiciel doit respecter :
   *   — la part patient est nulle, mais il n'y a pas de part assureur ;
   *   — la ligne ne remonte pas aux recettes ni au relevé assureur ;
   *   — la valeur reste calculée, pour que la Direction sache ce que
   *     l'avantage représente.
   * ======================================================================== */

  /** Le dossier personnel derrière un patient, ou null. */
  function agentDe(patient) {
    if (!patient) return null;
    var id = patient.personnelId || (typeof patient === 'string' ? null : null);
    if (!id) return null;
    return S.collection('personnel').all().filter(function (e) { return e.id === id; })[0] || null;
  }

  /** Le patient est-il un agent de la clinique ? */
  function estPersonnel(patient) {
    return !!(patient && patient.personnelId);
  }

  /**
   * Prise en charge d'une ligne pour un agent : 100 %, sans tiers payeur.
   * Renvoie le même contrat que PR.repartir pour que la facturation n'ait
   * pas à distinguer deux formes de résultat.
   */
  function prendreEnChargePersonnel(patient, lignes) {
    var agent = agentDe(patient);
    return (lignes || []).map(function (l) {
      var base = Number(l.montant) || 0;
      return {
        ligne: l, base: base,
        partAssureur: 0,
        partPatient: 0,
        priseEnChargePersonnel: base,
        taux: 100,
        agent: agent ? agent.nomComplet : (patient && patient.nom),
        matricule: agent ? agent.matricule : (patient && patient.matricule),
        motif: 'Prise en charge du personnel — 100 %, sans contrepartie d’un tiers payeur. '
          + 'Ni recette ni créance : avantage consenti par l’employeur.',
        horsRecettes: true,
      };
    });
  }

  /* ==========================================================================
   * PRESCRIPTION DE SOINS
   * --------------------------------------------------------------------------
   * La clinique distingue deux prescriptions : celle de l'ORDONNANCE, qui
   * porte des médicaments, et celle des SOINS, qui porte des actes. Les
   * confondre rendait invisible tout le travail infirmier — sept infirmiers et
   * trois sages-femmes exécutent des actes que rien ne traçait.
   *
   * Un soin est ADRESSÉ à un secteur : salle de soins, hospitalisation ou
   * maternité. Sans destinataire, il n'apparaîtrait sur aucun poste et ne
   * serait jamais exécuté.
   *
   * Il est facturé au catalogue AMI — donc au bon prix selon que le patient
   * est assuré ou non (voir D.tarifPrix).
   * ======================================================================== */
  function prescrireSoins(v) {
    var p = patientParCode(v.patientCode);
    if (!p) throw new Error('Patient introuvable : ' + v.patientCode);

    var soignant = (col('soignants').active().filter(function (x) {
      return x.id === v.prescripteurId;
    })[0]) || null;
    /* Un infirmier ne prescrit pas. Le contrôle est ici, au moteur : le poser
       dans l'écran laisserait passer toute prescription venue d'ailleurs. */
    if (soignant && !soignant.prescrit) {
      throw new Error(soignant.nomComplet + ' (' + soignant.poste + ') n’est pas habilité à prescrire.');
    }

    var date = v.date || new Date().toISOString();
    /* RG-09 : c’est la validité de la carte À LA DATE qui décide du tarif,
       et non le fait que le patient possède une carte. Une carte expirée
       facture au tarif non assuré, et la ligne le dit. */
    var assure = carteValide(p, date);

    var lignes = (v.actes || []).map(function (a) {
      var code = typeof a === 'string' ? a : a.code;
      var t = D.tarif ? D.tarif(code) : null;
      var pr = D.tarifPrix ? D.tarifPrix(code, assure) : { montant: null, motif: null };
      return {
        acteCode: code,
        libelle: t ? t.libelle : code,
        famille: t ? t.famille : null,
        quantite: Number((typeof a === 'object' && a.quantite) || 1),
        frequence: (typeof a === 'object' && a.frequence) || '',
        duree: (typeof a === 'object' && a.duree) || '',
        /* Le nombre d'administrations attendues : c'est lui qui fait vivre le
           relais. Une seule administration ne quitte jamais la salle de soins. */
        nbAdministrations: Number((typeof a === 'object' && a.nbAdministrations) || 1),
        prix: pr.montant,
        tarif: pr.tarif || null,
        motifTarif: pr.motif || null,
        prixAValider: pr.montant == null,
      };
    });

    var modalite = v.modalite || 'ambulatoire';
    var pres = col('prescriptions').insert({
      reference: C.nextRef('PRS-', 5),
      type: 'soins',
      origine: v.origine || 'consultation',
      date: date,
      patientId: p.id, patientCode: p.code, patient: p.nom + ' ' + p.prenom,
      prescripteurId: v.prescripteurId || null,
      prescripteur: soignant ? soignant.nomComplet : (v.prescripteur || '—'),
      secteurDestinataire: v.secteurDestinataire || 'salle_soins',
      modalite: modalite,
      /* Le secteur qui recevra la PREMIÈRE administration, annoncé d'avance :
         l'écran le dit au prescripteur au moment où il prescrit. */
      premierAdministrateur: D.secteurAdministrateur(modalite, 1).secteur,
      admissionId: v.admissionId || null,
      indication: v.indication || '',
      lignes: lignes,
      montant: lignes.reduce(function (t, l) { return t + (l.prix || 0) * l.quantite; }, 0),
      assure: assure,
      statut: 'en_cours',
      statutPaiement: 'impayee',
    }).record;

    /* La notification s'adresse à un POSTE et non à une personne : l'infirmier
       de garde change, le secteur reste. */
    notifier({
      type: 'prescription_soins',
      poste: v.secteurDestinataire || 'salle_soins',
      libelle: 'Nouvelle prescription de soins — ' + pres.patient,
      detail: pres.reference + ' — ' + lignes.length + ' acte(s) — ' + pres.prescripteur,
      priorite: v.urgent ? 'haute' : 'normale',
      patientId: p.id, reference: pres.reference,
    });

    return pres;
  }

  /* --------------------------------------------------------------------------
   * L'ORDONNANCE ENTRE AU MÊME REGISTRE
   * ------------------------------------------------------------------------
   * Pour que le registre des prescriptions dise la vérité, l'ordonnance doit y
   * figurer aussi. Sans cela, « les prescriptions du jour » n'en montreraient
   * que la moitié.
   * ---------------------------------------------------------------------- */
  function inscrireOrdonnance(ord, origine) {
    return col('prescriptions').insert({
      reference: ord.numero,
      type: 'ordonnance',
      origine: origine || 'consultation',
      date: ord.date,
      patientId: ord.patientId, patientCode: ord.patientCode, patient: ord.patient,
      prescripteurId: ord.prescripteurId || null,
      prescripteur: ord.medecin,
      secteurDestinataire: 'pharmacie',
      modalite: ord.modalite || 'ambulatoire',
      premierAdministrateur: D.secteurAdministrateur(ord.modalite || 'ambulatoire', 1).secteur,
      ordonnanceId: ord.id,
      lignes: (ord.medicaments || []).map(function (m) {
        return {
          produitId: m.produitId, libelle: m.produit, quantite: m.quantite,
          posologie: m.posologie, duree: m.duree, prix: m.prix,
          nbAdministrations: Number(m.nbAdministrations || 1),
        };
      }),
      montant: ord.montantMedicaments || 0,
      statut: 'en_cours',
      statutPaiement: ord.statutPaiement || 'impayee',
    }).record;
  }

  /* ==========================================================================
   * ADMINISTRATION D'UN TRAITEMENT — LA RÈGLE DE RELAIS
   * --------------------------------------------------------------------------
   * Le rang décide du secteur, pas l'inverse. Un poste qui tente d'administrer
   * ce qui ne lui revient pas est refusé EN LE NOMMANT : « cette administration
   * revient à la salle de soins ». Un refus muet ferait croire à une panne.
   * ======================================================================== */
  function rangSuivant(prescriptionId, ligneIndex) {
    return col('administrations').active().filter(function (a) {
      return a.prescriptionId === prescriptionId && a.ligneIndex === ligneIndex;
    }).length + 1;
  }

  function administrer(prescriptionId, opts) {
    opts = opts || {};
    var pres = col('prescriptions').get(prescriptionId);
    if (!pres) throw new Error('Prescription introuvable.');

    var ligneIndex = Number(opts.ligneIndex || 0);
    var ligne = (pres.lignes || [])[ligneIndex];
    if (!ligne) throw new Error('Ligne de prescription introuvable.');

    /* Une prescription non réglée ne s'administre pas : c'est la même règle
       que pour la délivrance et le laboratoire. */
    if (pres.statutPaiement !== 'payee' && !opts.forcer) {
      return { ok: false, motif: 'Prescription non réglée — l’administration reste bloquée jusqu’à l’encaissement.' };
    }

    var rang = rangSuivant(prescriptionId, ligneIndex);
    var attendu = D.secteurAdministrateur(pres.modalite, rang);

    if (opts.secteur && opts.secteur !== attendu.secteur) {
      return {
        ok: false, rang: rang, secteurAttendu: attendu.secteur,
        motif: attendu.motif,
      };
    }

    var exec = (col('soignants').active().filter(function (x) {
      return x.id === opts.executantId;
    })[0]) || null;
    /* Le médecin prescrit, il n'exécute pas les soins ; l'infirmier et la
       sage-femme exécutent. Le contrôle vit au moteur. */
    if (exec && !exec.execute) {
      return {
        ok: false, rang: rang,
        motif: exec.nomComplet + ' (' + exec.poste + ') n’exécute pas les soins.',
      };
    }

    var rec = col('administrations').insert({
      reference: C.nextRef('ADM-', 5),
      prescriptionId: prescriptionId, prescriptionRef: pres.reference,
      ligneIndex: ligneIndex, libelle: ligne.libelle,
      patientId: pres.patientId, patientCode: pres.patientCode, patient: pres.patient,
      dateHeure: opts.dateHeure || new Date().toISOString(),
      rang: rang, total: ligne.nbAdministrations || 1,
      secteur: attendu.secteur, motifSecteur: attendu.motif,
      executantId: opts.executantId || null,
      executant: exec ? exec.nomComplet : (opts.executant || '—'),
      observation: opts.observation || '',
      modalite: pres.modalite,
    }).record;

    /* La prescription se termine quand toutes ses lignes sont servies. */
    var reste = (pres.lignes || []).some(function (l, i) {
      return rangSuivant(prescriptionId, i) <= (l.nbAdministrations || 1);
    });
    if (!reste) col('prescriptions').update(prescriptionId, { statut: 'termine' });

    return { ok: true, administration: rec, rang: rang, secteur: attendu.secteur };
  }

  /* --------------------------------------------------------------------------
   * CE QUI REVIENT À UN POSTE, MAINTENANT
   * ------------------------------------------------------------------------
   * Trois écrans posent la même question — la salle de soins, l'hospitalisation
   * et la maternité. Y répondre une fois évite trois filtres divergents.
   * ---------------------------------------------------------------------- */
  function soinsDuSecteur(secteur) {
    return col('prescriptions').active().filter(function (pres) {
      return pres.statut === 'en_cours';
    }).map(function (pres) {
      var lignes = (pres.lignes || []).map(function (l, i) {
        var rang = rangSuivant(pres.id, i);
        var att = D.secteurAdministrateur(pres.modalite, rang);
        return {
          index: i, ligne: l, rang: rang,
          total: l.nbAdministrations || 1,
          secteur: att.secteur, motif: att.motif,
          du: rang <= (l.nbAdministrations || 1) && att.secteur === secteur,
          bloque: pres.statutPaiement !== 'payee',
        };
      }).filter(function (x) { return x.du; });
      return lignes.length ? { prescription: pres, lignes: lignes } : null;
    }).filter(Boolean);
  }

  /* ==========================================================================
   * CLOISONNEMENT DE L'ACCUEIL
   * --------------------------------------------------------------------------
   * L'accueil a besoin de l'identité, des coordonnées, de la couverture
   * d'assurance et des constantes qu'il relève lui-même. Il n'a aucun besoin
   * du diagnostic, des antécédents, des résultats d'analyse ni du traitement —
   * et RG-13 le lui interdit.
   *
   * DEUX PRINCIPES :
   *   1. Une restriction S'ANNONCE. Un filtre muet fait croire à une donnée
   *      manquante ; l'écran dit qui il est, ce qu'il ne voit pas et pourquoi.
   *   2. TOUTE recherche de dossier par l'accueil est JOURNALISÉE. C'est une
   *      demande expresse de la Direction : le dossier d'un voisin, d'un
   *      notable ou d'un employé se consulte trop facilement quand rien ne
   *      trace qui a regardé quoi.
   * ======================================================================== */
  var CHAMPS_ADMINISTRATIFS = ['code', 'nip', 'nom', 'prenom', 'sexe', 'dateNaissance', 'age',
    'telephone', 'quartier', 'adresse', 'profession', 'ethnie', 'personneContact',
    'assureur', 'assureurNom', 'numeroCarte', 'carteExpiration', 'tauxPriseEnCharge',
    'souscripteur', 'creeLe', 'heureArrivee', 'statut'];

  var CHAMPS_CLINIQUES = ['diagnostic', 'antecedents', 'allergies', 'traitement',
    'groupeSanguin', 'gsRh', 'te', 'hb', 'observations', 'motifConsultation'];

  /** L'accueil voit-il ce champ ? RG-13. */
  function accueilVoitChamp(nom) {
    return CHAMPS_ADMINISTRATIFS.indexOf(nom) !== -1;
  }

  /**
   * Le dossier tel que l'accueil a le droit de le voir. Renvoie la fiche
   * expurgée ET le motif — parce qu'une restriction s'annonce.
   */
  function dossierPourAccueil(patient) {
    if (!patient) return { fiche: null, motif: 'Dossier introuvable.' };
    var out = {};
    Object.keys(patient).forEach(function (k) {
      if (accueilVoitChamp(k) || k === 'id') out[k] = patient[k];
    });
    var masques = Object.keys(patient).filter(function (k) {
      return CHAMPS_CLINIQUES.indexOf(k) !== -1;
    });
    return {
      fiche: out,
      masques: masques,
      motif: 'RG-13 — l’accueil accède aux données administratives et à la couverture d’assurance. '
        + 'Les données cliniques (diagnostic, antécédents, résultats, traitement) lui sont fermées.',
    };
  }

  /**
   * Journalise une recherche de dossier. Demande expresse de la Direction :
   * le dossier d'un voisin ou d'un notable se consulte trop facilement quand
   * rien ne trace qui a regardé quoi.
   *
   * On journalise la CONSULTATION, pas seulement la modification : c'est le
   * regard qui pose problème ici, pas l'écriture.
   */
  function journaliserRecherche(patient, opts) {
    opts = opts || {};
    var s = S.session() || {};
    /* On passe par le mécanisme du magasin et NON par collection().insert() :
       insert() journalise à son tour, et une recherche produisait deux
       entrées — la sienne, plus une entrée fantôme décrivant son écriture. */
    return S.journaliserAcces({
      utilisateur: s.nom || S.currentUser(),
      role: s.role || null,
      action: opts.action || 'Consultation de dossier',
      module: 'M1', entite: 'Dossier patient',
      reference: patient ? patient.code : (opts.terme || null),
      cible: patient ? (patient.code + ' — ' + patient.nom + ' ' + patient.prenom) : (opts.terme || '—'),
      patientId: patient ? patient.id : null,
      ecran: opts.ecran || null,
      motif: opts.motif || null,
      /* Une recherche infructueuse se journalise aussi : chercher le dossier
         de quelqu'un qui n'est pas patient est en soi une information. */
      trouve: !!patient,
    });
  }

  /* ==========================================================================
   * CONTINUITÉ DU PRÉLÈVEMENT ET DE LA VALIDATION
   * --------------------------------------------------------------------------
   * Celui qui a fait le prélèvement est celui qui valide. Règle de PREUVE et
   * non d'organisation : le validateur atteste d'un échantillon, et s'il ne l'a
   * pas vu arriver il atteste de ce qu'un collègue lui a dit.
   *
   * La clinique compte DEUX biologistes médicaux ; la règle a donc un effet
   * réel — elle interdit que l'un valide le prélèvement de l'autre.
   * ======================================================================== */
  function continuiteRespectee(demande, agent) {
    if (!demande) return { ok: false, motif: 'Demande introuvable.' };
    var preleveur = demande.preleveParId || demande.prelevePar || null;
    /* Un prélèvement non encore fait ne peut pas être validé : c'est déjà la
       règle du circuit, on ne la redouble pas ici. */
    if (!preleveur) {
      return { ok: true, motif: 'Aucun prélèvement enregistré — la continuité ne s’applique pas encore.' };
    }
    var memeAgent = preleveur === (agent && (agent.id || agent))
      || preleveur === (agent && agent.nomComplet);
    if (memeAgent) return { ok: true, motif: null };
    return {
      ok: false,
      preleveur: demande.prelevePar || preleveur,
      motif: 'Le prélèvement a été fait par ' + (demande.prelevePar || preleveur)
        + '. C’est à lui de valider : un validateur qui n’a pas vu arriver l’échantillon '
        + 'atteste de ce qu’un collègue lui a dit, et la signature perd sa valeur.',
    };
  }

  global.SIGH.parcours = {
    continuiteRespectee: continuiteRespectee,
    accueilVoitChamp: accueilVoitChamp,
    dossierPourAccueil: dossierPourAccueil,
    journaliserRecherche: journaliserRecherche,
    CHAMPS_CLINIQUES: CHAMPS_CLINIQUES,
    prescrireSoins: prescrireSoins, inscrireOrdonnance: inscrireOrdonnance,
    administrer: administrer, soinsDuSecteur: soinsDuSecteur,
    rangSuivant: rangSuivant,
    ecrireEncaissement: ecrireEncaissement, alerterStock: alerterStock,
    construireLignes: construireLignes, lignesDues: lignesDues, lignesReglees: lignesReglees,
    ouvrirDemandeExterne: ouvrirDemandeExterne,
    ouvrirDemandeImagerie: ouvrirDemandeImagerie,
    codeAnalyse: codeAnalyse,
    validerTechnique: validerTechnique, validerBiologique: validerBiologique,
    rectifierResultat: rectifierResultat,
    notifier: notifier, notifications: notifications, marquerLue: marquerLue,
    estPersonnel: estPersonnel, agentDe: agentDe,
    prendreEnChargePersonnel: prendreEnChargePersonnel,
    capacites: capacites, secteurCourant: secteurCourant, valoriserSortie: valoriserSortie,
    peutVoirResultat: peutVoirResultat, peutPrescrire: peutPrescrire,
    peutExecuterSoin: peutExecuterSoin, filtrerResultats: filtrerResultats,
    repartir: repartir, garantiesDe: garantiesDe, souscripteurDe: souscripteurDe,
    carteValide: carteValide, categoriser: categoriser, libelleUnite: libelleUnite,
    TACHES: TACHES,
    prescrire: prescrire, encaisser: encaisser, delivrer: delivrer,
    verifierStock: verifierStock,
    taches: taches, aFaire: aFaire, terminer: terminer, compteurs: compteurs,
    dossier: dossier,
  };
})(window);
