/* ==========================================================================
 * PEUPLEMENT DU JEU DE DÉMONSTRATION — NEUF MOIS D'ACTIVITÉ
 * --------------------------------------------------------------------------
 * Demande de la Direction du 26/08/2026 : peupler tous les modules, avec leurs
 * habilitations respectives, sur neuf mois.
 *
 * LE PRINCIPE QUI COMMANDE TOUT CE FICHIER : on ne fabrique pas vingt-huit
 * listes indépendantes, on REJOUE DE VRAIS PARCOURS. Une prescription passe par
 * PR.prescrire(), qui engendre elle-même l'ordonnance, les demandes d'analyses,
 * la facture et les files d'attente ; l'encaissement passe par PR.encaisser(),
 * qui débloque l'aval et pose l'écriture comptable.
 *
 * Deux raisons, et la seconde est la plus forte :
 *
 *   1. Les données sont COHÉRENTES entre modules — une facture correspond à une
 *      ordonnance qui correspond à des demandes de laboratoire. Vingt-huit
 *      listes tirées au sort donneraient des écrans pleins et un logiciel faux.
 *
 *   2. Les FORMES sont justes par construction. Recopier à la main les champs
 *      qu'attend chaque écran, c'est se tromper sur l'un d'eux et ne s'en
 *      apercevoir qu'à l'usage — ce qui est arrivé plusieurs fois sur ce
 *      projet, et toujours par supposition.
 *
 * CE PEUPLEMENT S'EXÉCUTE APRÈS LE CHARGEMENT DES MODULES, non pendant
 * store.seed() : le moteur de parcours n'existe pas encore à cet instant.
 * Il est déclenché une seule fois, sur un drapeau posé dans le magasin.
 * ======================================================================== */
(function (global) {
  'use strict';

  var C = global.SIGH.core;

  /* Neuf mois pleins, de décembre 2025 à la date de référence du prototype. */
  var FIN = new Date(2026, 7, 26);
  var DEBUT = new Date(2025, 11, 1);
  var JOURS = Math.round((FIN - DEBUT) / 86400000);

  function S() { return global.SIGH.store; }
  function PR() { return global.SIGH.parcours; }
  function D() { return global.SIGH.data; }

  function col(nom, meta) { return S().collection(nom, meta || {}); }
  function jour(rnd, recul) { return C.addDays(FIN, -recul); }
  function reculAleatoire(rnd) { return C.between(rnd, 0, JOURS); }

  /* Un jour ouvré : la clinique consulte du lundi au samedi, la garde
     assurant le dimanche. Semer des consultations le dimanche gonflerait
     artificiellement l'activité du week-end. */
  function jourOuvre(rnd) {
    for (var i = 0; i < 12; i++) {
      var d = jour(rnd, reculAleatoire(rnd));
      if (d.getDay() !== 0) return d;
    }
    return FIN;
  }

  /* ==========================================================================
   * OUTILLAGE
   * ======================================================================== */
  function patients() { return S().collection('patients').active(); }
  function personnel() { return S().collection('personnel').active(); }
  function soignants() { return S().collection('soignants').active(); }

  function parFonction(f) {
    return personnel().filter(function (a) { return a.fonction === f; });
  }
  function soignantsQui(pred) { return soignants().filter(pred); }

  function unDe(rnd, liste) { return liste.length ? C.pick(rnd, liste) : null; }

  /* ==========================================================================
   * 1. LES PARCOURS DE SOIN — le cœur
   * --------------------------------------------------------------------------
   * Chaque parcours traverse les modules dans l'ordre réel : consultation →
   * prescription → caisse → laboratoire ou pharmacie → résultat. On fait varier
   * l'avancement pour que chaque poste ait quelque chose à montrer : certains
   * parcours s'arrêtent à la caisse, d'autres vont jusqu'au résultat rendu.
   * ======================================================================== */
  function parcoursDeSoin(rnd, nb) {
    var pr = PR(), d = D();
    var meds = S().collection('produits').active().filter(function (p) { return p.stock > 20; });
    var analyses = (d.ANALYSES || []).filter(function (a) { return a.prix; });
    var medecins = parFonction('medecin').filter(function (a) { return !/Échographiste/i.test(a.poste || ''); });
    var bio = soignantsQui(function (x) { return x.qualite === 'medecin'; });
    var faits = { prescriptions: 0, encaisses: 0, resultats: 0, rendus: 0 };
    if (!medecins.length || !analyses.length) return faits;

    for (var i = 0; i < nb; i++) {
      var p = unDe(rnd, patients());
      var med = unDe(rnd, medecins);
      var date = C.iso(jourOuvre(rnd));
      var nAna = C.between(rnd, 1, 4);
      var codes = [];
      for (var k = 0; k < nAna; k++) {
        var a = unDe(rnd, analyses);
        if (a && codes.indexOf(a.code) === -1) codes.push(a.code);
      }
      var nMed = C.between(rnd, 0, 3);
      var lignesMed = [];
      for (var m = 0; m < nMed; m++) {
        var prod = unDe(rnd, meds);
        if (prod && !lignesMed.some(function (l) { return l.produitId === prod.id; })) {
          lignesMed.push({ produitId: prod.id, quantite: C.between(rnd, 1, 3),
            posologie: C.pick(rnd, ['1 cp x 3/j', '2 cp matin et soir', '1 sachet x 2/j', '1 amp/j']),
            duree: C.between(rnd, 3, 10) + ' jours' });
        }
      }
      if (!codes.length && !lignesMed.length) continue;

      var ord;
      try {
        ord = pr.prescrire({
          patientCode: p.code, medecin: med.nomComplet, date: date,
          diagnostic: C.pick(rnd, ['Paludisme simple', 'Fièvre typhoïde', 'Infection urinaire',
            'Anémie', 'Hypertension artérielle', 'Gastro-entérite', 'Bilan de santé',
            'Suivi de grossesse', 'Bronchite aiguë', 'Diabète — bilan']),
          analyses: codes, medicaments: lignesMed,
          urgent: rnd() > 0.88,
        });
      } catch (e) { continue; }
      faits.prescriptions++;

      /* --- L'encaissement : les trois quarts, dont un tiers partiellement.
         Un jeu où tout est payé ne montrerait jamais la file de la caisse ni
         les tâches bloquées. --------------------------------------------- */
      var fac = S().collection('factures').active().filter(function (f) {
        return f.ordonnanceId === ord.ordonnance.id;
      })[0];
      if (fac && rnd() > 0.25) {
        var dues = pr.lignesDues ? pr.lignesDues(fac) : [];
        var partiel = rnd() > 0.66 && dues.length > 1;
        var choisies = partiel ? dues.slice(0, Math.max(1, Math.floor(dues.length / 2))) : dues;
        try {
          pr.encaisser(fac.id, { lignes: choisies.map(function (l) { return l.id; }) });
          faits.encaisses++;
        } catch (e) { /* la facture n'a pas de lignes payables */ }
      }

      /* --- Le laboratoire : prélèvement, saisie, deux validations --------- */
      var demandes = S().collection('demandesAnalyses').active().filter(function (x) {
        return x.ordonnanceId === ord.ordonnance.id;
      });
      demandes.forEach(function (dem) {
        if (dem.etatAnalyse !== 'attente_prelevement') return;
        if (rnd() > 0.75) return;
        /* LA CONTINUITÉ : le même biologiste prélève et valide. */
        var biologiste = unDe(rnd, bio) || unDe(rnd, soignants());
        var quand = C.iso(C.addDays(C.toDate(dem.dateHeure), C.between(rnd, 0, 2)));
        /* L'ÉCRAN RANGE SES ONGLETS SUR LES HORODATAGES, pas sur l'état :
           à prélever (!preleveLe), à transmettre (preleveLe && !recuLaboLe),
           reçus (recuLaboLe). Le champ s'appelle `preleveLe` — écrire
           `prelevementLe` laissait les trois onglets se contredire. */
        S().collection('demandesAnalyses').update(dem.id, {
          etatAnalyse: 'preleve',
          prelevePar: biologiste ? biologiste.nomComplet : 'Laboratoire',
          preleveParId: biologiste ? biologiste.id : null,
          preleveLe: quand,
        });
        if (rnd() > 0.2) {
          /* UN RÉSULTAT SAISI SUPPOSE UN ÉCHANTILLON PARVENU. Poser le
             prélèvement sans la réception laisserait ces demandes en « à
             transmettre » pour l'éternité, alors que le laboratoire les a
             analysées. */
          S().collection('demandesAnalyses').update(dem.id, {
            etatAnalyse: 'en_cours',
            recuLaboLe: quand,
            recuPar: biologiste ? biologiste.nomComplet : 'Laboratoire',
          });

          /* UNE PART RESTE « AU LABORATOIRE » — reçue, non encore saisie.
             C'est l'état dans lequel se trouve, à tout instant, ce que le
             laboratoire a sur sa paillasse : le seul où il a quelque chose à
             faire immédiatement. Passer directement à la validation le rendait
             invisible, et le rappel du matin n'avait qu'une question sur deux
             à poser. */
          if (rnd() < 0.22) return;

          S().collection('demandesAnalyses').update(dem.id, {
            etatAnalyse: 'valide_technique',
            saisiPar: biologiste ? biologiste.nomComplet : 'Laboratoire',
            saisiLe: quand,
          });
          faits.resultats++;
          if (rnd() > 0.3) {
            S().collection('demandesAnalyses').update(dem.id, {
              /* Le code du référentiel, et lui seul. « valide_bio » n'y figure
                 pas : resultatRendu() le refusait, donc aucun résultat n'était
                 opposable au prescripteur. */
              etatAnalyse: 'valide',
              valideBioPar: biologiste ? biologiste.nomComplet : 'Laboratoire',
              valideBioLe: quand,
            });
            faits.rendus++;
          }
        }
      });
    }
    return faits;
  }

  /* ==========================================================================
   * 2. LES PRESCRIPTIONS DE SOINS ET LEURS ADMINISTRATIONS
   * --------------------------------------------------------------------------
   * On fait vivre la règle de relais : des traitements ambulatoires servis
   * entièrement en salle de soins, et des traitements hospitaliers dont la
   * première administration y passe avant que l'hospitalisation prenne la
   * suite. Sans cela, les deux postes afficheraient des files vides.
   * ======================================================================== */
  function prescriptionsDeSoins(rnd, nb) {
    var pr = PR(), d = D();
    var prescripteurs = soignantsQui(function (x) { return x.prescrit; });
    var executants = soignantsQui(function (x) { return x.execute; });
    var actesAmi = (d.tarifParFamille ? d.tarifParFamille('AMI') : [])
      .filter(function (a) { return a.prixNonAssure != null; });
    var faits = { prescriptions: 0, administrations: 0 };
    if (!prescripteurs.length || !actesAmi.length) return faits;

    for (var i = 0; i < nb; i++) {
      var p = unDe(rnd, patients());
      var presc = unDe(rnd, prescripteurs);
      var hospit = rnd() > 0.55;
      var nActes = C.between(rnd, 1, 3);
      var actes = [];
      for (var k = 0; k < nActes; k++) {
        var a = unDe(rnd, actesAmi);
        if (a && !actes.some(function (x) { return x.code === a.code; })) {
          actes.push({ code: a.code, nbAdministrations: hospit ? C.between(rnd, 2, 5) : C.between(rnd, 1, 3) });
        }
      }
      if (!actes.length) continue;

      var rec;
      try {
        rec = pr.prescrireSoins({
          patientCode: p.code, prescripteurId: presc.id,
          origine: C.pick(rnd, ['consultation', 'consultation', 'hospitalisation', 'maternite', 'bloc']),
          secteurDestinataire: hospit ? 'hospitalisation' : 'salle_soins',
          modalite: hospit ? 'hospitalisation' : 'ambulatoire',
          indication: C.pick(rnd, ['Pansement post-opératoire', 'Antibiothérapie parentérale',
            'Réhydratation', 'Surveillance de plaie', 'Traitement antipaludique']),
          date: C.iso(jourOuvre(rnd)),
          actes: actes,
        });
      } catch (e) { continue; }
      faits.prescriptions++;

      /* Les deux tiers sont réglés — sans quoi rien ne s'administrerait. */
      if (rnd() > 0.33) {
        col('prescriptions', { module: 'M2', entite: 'prescription', prefix: 'PRS' })
          .update(rec.id, { statutPaiement: 'payee' });

        /* On administre une partie des passages dus, en respectant le relais. */
        (rec.lignes || []).forEach(function (l, idx) {
          var total = l.nbAdministrations || 1;
          var faites = C.between(rnd, 0, total);
          for (var n = 0; n < faites; n++) {
            var rang = pr.rangSuivant(rec.id, idx);
            var att = d.secteurAdministrateur(rec.modalite, rang);
            var exec = unDe(rnd, executants.filter(function (x) {
              return (x.secteurs || []).indexOf(att.secteur) !== -1;
            })) || unDe(rnd, executants);
            if (!exec) break;
            var res = pr.administrer(rec.id, {
              ligneIndex: idx, secteur: att.secteur, executantId: exec.id,
              dateHeure: C.iso(C.addDays(C.toDate(rec.date), n)),
              observation: rnd() > 0.7 ? C.pick(rnd, ['Bien toléré', 'Douleur au point d’injection',
                'Patient calme', 'Sans incident']) : '',
            });
            if (!res.ok) break;
            faits.administrations++;
          }
        });
      }
    }
    return faits;
  }

  /* ==========================================================================
   * 3. LES PIÈCES CLINIQUES
   * ======================================================================== */
  function piecesCliniques(rnd) {
    var d = D();
    var faits = {};
    var medecins = soignantsQui(function (x) { return x.qualite === 'medecin'; });
    var sages = soignantsQui(function (x) { return x.qualite === 'sage_femme'; });
    var exec = soignantsQui(function (x) { return x.execute; });
    var femmes = patients().filter(function (p) { return p.sexe === 'F'; });

    /* --- Comptes rendus opératoires et check-listes --------------------- */
    var cro = col('crOperatoires', { module: 'M3', entite: 'compte rendu opératoire', prefix: 'CRO' });
    var ckl = col('checklistsBloc', { module: 'M3', entite: 'check-liste', prefix: 'CKL' });
    var INTERVENTIONS = [
      ['Appendicite aiguë', 'Appendicectomie par voie de McBurney', 'Rachianesthésie'],
      ['Hernie inguinale droite', 'Herniorraphie selon Lichtenstein', 'Rachianesthésie'],
      ['Grossesse à terme, souffrance fœtale', 'Césarienne segmentaire transversale', 'Rachianesthésie'],
      ['Kyste ovarien', 'Kystectomie par laparotomie', 'Anesthésie générale'],
      ['Fibrome utérin symptomatique', 'Myomectomie', 'Anesthésie générale'],
      ['Abcès de la fesse', 'Incision et drainage', 'Anesthésie locale'],
      ['Fracture fermée de l’avant-bras', 'Réduction et immobilisation plâtrée', 'Anesthésie locorégionale'],
    ];
    for (var i = 0; i < 26; i++) {
      var p = unDe(rnd, patients());
      var op = unDe(rnd, medecins);
      var an = unDe(rnd, exec) || op;
      var aide = rnd() > 0.4 ? unDe(rnd, exec) : null;
      var it = C.pick(rnd, INTERVENTIONS);
      var dt = C.iso(jourOuvre(rnd));
      if (!p || !op) break;
      var rec = cro.insert({
        reference: 'CRO-' + C.pad(i + 1, 4), dateOperation: dt,
        patientId: p.id, patient: p.nom + ' ' + p.prenom, patientCode: p.code, nip: p.code,
        diagnosticPeroperatoire: it[0],
        intervention: it[1],
        anesthesie: it[2],
        cro: 'Installation du patient. Asepsie et champage. ' + it[1] + '. '
          + C.pick(rnd, ['Exploration sans particularité.', 'Hémostase soigneuse.',
            'Pas d’incident per-opératoire.', 'Lavage abondant de la cavité.'])
          + ' Fermeture plan par plan. Pansement.',
        operateurId: op.id, operateur: op.nomComplet,
        aideOperateurId: aide ? aide.id : null, aideOperateur: aide ? aide.nomComplet : null,
        anesthesisteId: an.id, anesthesiste: an.nomComplet,
      }).record;

      /* Chaque intervention porte ses deux check-listes : les fondre ou en
         omettre une viderait l'exercice de son sens. */
      ['entree', 'sortie'].forEach(function (moment) {
        var items = moment === 'entree' ? d.CHECKLIST_BLOC.entree : d.CHECKLIST_BLOC.sortie;
        /* Quelques check-listes restent incomplètes : c'est la réalité d'un
           bloc chargé, et l'écran doit pouvoir le signaler. */
        var manque = rnd() > 0.82 ? C.between(rnd, 1, 2) : 0;
        var lignes = items.map(function (label, k) {
          return { label: label, coche: k >= items.length - manque ? false : true };
        });
        ckl.insert({
          reference: 'CKL-' + C.pad(i * 2 + (moment === 'entree' ? 1 : 2), 4),
          moment: moment, dateHeure: dt + 'T08:00:00.000Z',
          patientId: p.id, patient: rec.patient,
          responsableId: an.id, responsable: an.nomComplet,
          items: lignes,
          coches: lignes.filter(function (x) { return x.coche; }).length,
          total: lignes.length,
        });
      });
    }
    faits.cro = cro.active().length;

    /* --- Comptes rendus de maternité ------------------------------------ */
    var crm = col('crMaternite', { module: 'M4', entite: 'compte rendu de maternité', prefix: 'CRM' });
    (d.COMPTES_RENDUS_MATERNITE || []).forEach(function (mod, mi) {
      var n = mod.code === 'accouchement' ? 34 : (mod.code === 'planning_familial' ? 22 : 9);
      for (var j = 0; j < n; j++) {
        var pt = unDe(rnd, femmes);
        var sf = unDe(rnd, sages) || unDe(rnd, medecins);
        if (!pt || !sf) break;
        var o = {
          reference: 'CRM-' + C.pad(mi * 100 + j + 1, 4),
          typeCr: mod.code, typeLabel: mod.label,
          patientId: pt.id, patient: pt.nom + ' ' + pt.prenom, patientCode: pt.code,
          sageFemmeId: sf.id, sageFemme: sf.nomComplet,
          creeLe: C.iso(jourOuvre(rnd)) + 'T10:00:00.000Z',
        };
        /* Les rubriques sont remplies depuis leur DÉCLARATION : ajouter une
           rubrique au modèle la peuplera sans toucher à ce fichier. */
        mod.rubriques.forEach(function (r) {
          var nom = r[0], type = r[2], choix = r[4];
          if (type === 'liste' && choix) o[nom] = C.pick(rnd, choix);
          else if (type === 'binaire') o[nom] = rnd() > 0.5;
          else if (type === 'nombre') o[nom] = C.between(rnd, 1, 40);
          else if (type === 'date') o[nom] = C.iso(jourOuvre(rnd));
          else if (type === 'datetime') o[nom] = C.iso(jourOuvre(rnd)) + 'T'
            + C.pad(C.between(rnd, 0, 23), 2) + ':' + C.pad(C.between(rnd, 0, 59), 2);
          else if (type === 'soignant') o[nom] = sf.id;
          else if (type === 'zone') o[nom] = C.pick(rnd, ['Sans particularité.',
            'Évolution favorable.', 'Surveillance rapprochée.', 'Suites simples.']);
        });
        if (mod.code === 'accouchement') {
          o.poidsEnfant = C.between(rnd, 2200, 4100);
          o.apgar1 = C.between(rnd, 6, 10);
          o.apgar5 = C.between(rnd, 8, 10);
          o.termeSA = C.between(rnd, 36, 41);
        }
        crm.insert(o);
      }
    });
    faits.maternite = crm.active().length;

    /* --- Surveillance transfusionnelle ----------------------------------- */
    var trf = col('surveillancesTransfusion',
      { module: 'M3', entite: 'surveillance transfusionnelle', prefix: 'TRF' });
    var TEMPS = ['t0', 't15', 't30', 't60', 't90', 'fin', 'h1', 'h2'];
    for (var t = 0; t < 14; t++) {
      var pt2 = unDe(rnd, patients());
      var resp = unDe(rnd, exec);
      if (!pt2 || !resp) break;
      var incident = rnd() > 0.86;
      var releves = incident ? TEMPS.length : C.between(rnd, 5, TEMPS.length);
      var valeurs = {};
      TEMPS.forEach(function (tp, k) {
        if (k >= releves) { valeurs[tp] = {}; return; }
        valeurs[tp] = {
          temperature: (36.5 + rnd() * (incident && k > 2 ? 2.4 : 0.9)).toFixed(1),
          ta: C.between(rnd, 10, 14) + '/' + C.between(rnd, 6, 9),
          fr: String(C.between(rnd, 14, 22)),
          fc: String(C.between(rnd, 66, incident && k > 2 ? 128 : 96)),
          spo2: String(C.between(rnd, 94, 100)),
          urines: C.pick(rnd, ['claires', 'claires', 'foncées']),
          conscience: C.pick(rnd, ['normale', 'normale', 'obnubilation']),
          autre: '',
        };
      });
      trf.insert({
        reference: 'TRF-' + C.pad(t + 1, 4),
        patientId: pt2.id, patient: pt2.nom + ' ' + pt2.prenom, patientCode: pt2.code,
        service: C.pick(rnd, ['Hospitalisation', 'Maternité', 'Soins intensifs']),
        date: C.iso(jourOuvre(rnd)),
        pochePSL: 'PSL-' + C.between(rnd, 100000, 999999),
        debut: C.pad(C.between(rnd, 7, 18), 2) + 'h' + C.pad(C.between(rnd, 0, 59), 2),
        responsableId: resp.id, responsable: resp.nomComplet,
        valeurs: valeurs, releves: releves, attendus: TEMPS.length,
        incident: incident,
        natureIncident: incident ? C.pick(rnd, ['Frisson avec hyperthermie',
          'Urticaire généralisée', 'Douleur lombaire']) : null,
        conclusion: incident
          ? 'Transfusion interrompue, médecin appelé, traitement symptomatique institué.'
          : 'Transfusion menée à son terme sans incident. Surveillance poursuivie deux heures.',
      });
    }
    faits.transfusion = trf.active().length;

    /* --- Scores de Glasgow ----------------------------------------------- */
    var gcs = col('scoresGlasgow', { module: 'M3', entite: 'score de Glasgow', prefix: 'GCS' });
    var AXES = [
      { axe: 'Ouverture des yeux', max: 4 },
      { axe: 'Réponse verbale', max: 5 },
      { axe: 'Réponse motrice', max: 6 },
    ];
    var LIB = {
      'Ouverture des yeux': { 4: 'Spontanée', 3: 'Au bruit, à la parole', 2: 'À la douleur', 1: 'Aucune réponse' },
      'Réponse verbale': { 5: 'Normale', 4: 'Confuse', 3: 'Inappropriée', 2: 'Incompréhensible', 1: 'Aucune réponse' },
      'Réponse motrice': { 6: 'À la commande', 5: 'Localise la douleur', 4: 'Se retire à la douleur',
        3: 'Flexion à la douleur', 2: 'Extension à la douleur', 1: 'Aucune réponse' },
    };
    for (var g = 0; g < 18; g++) {
      var pt3 = unDe(rnd, patients());
      var ev = unDe(rnd, exec) || unDe(rnd, medecins);
      if (!pt3 || !ev) break;
      /* Un jeu où tous les scores valent 15 ne montrerait jamais l'alerte. */
      var grave = rnd() > 0.78;
      var axes = AXES.map(function (a) {
        var pts = grave ? C.between(rnd, 1, Math.max(1, a.max - 2)) : C.between(rnd, a.max - 1, a.max);
        return { axe: a.axe, libelle: LIB[a.axe][pts], points: pts };
      });
      gcs.insert({
        reference: 'GCS-' + C.pad(g + 1, 4),
        patientId: pt3.id, patient: pt3.nom + ' ' + pt3.prenom, nip: pt3.code,
        dateHeure: C.iso(jourOuvre(rnd)) + 'T' + C.pad(C.between(rnd, 6, 22), 2) + ':00',
        axes: axes,
        score: axes.reduce(function (n, a) { return n + a.points; }, 0),
        evaluePar: ev.id, evaluateur: ev.nomComplet,
        observation: grave ? C.pick(rnd, ['Réévaluation horaire prescrite',
          'Transfert en surveillance rapprochée', 'Médecin prévenu']) : '',
      });
    }
    faits.glasgow = gcs.active().length;

    /* --- Rapports médicaux ------------------------------------------------ */
    var rap = col('rapportsMedicaux', { module: 'M3', entite: 'rapport médical', prefix: 'RAP' });
    for (var r = 0; r < 22; r++) {
      var pt4 = unDe(rnd, patients());
      var md = unDe(rnd, medecins);
      if (!pt4 || !md) break;
      var entree = jourOuvre(rnd);
      var duree = C.between(rnd, 2, 12);
      var clos = rnd() > 0.2;
      var diag = C.pick(rnd, ['Paludisme grave', 'Fièvre typhoïde compliquée',
        'Pneumopathie aiguë communautaire', 'Anémie sévère', 'Crise drépanocytaire',
        'Accès palustre chez la femme enceinte', 'Gastro-entérite déshydratante']);
      rap.insert({
        reference: 'RAP-' + C.pad(r + 1, 4),
        patientId: pt4.id, patient: pt4.nom + ' ' + pt4.prenom, patientCode: pt4.code,
        age: C.age(pt4.dateNaissance), sexe: pt4.sexe,
        adresse: pt4.quartier, telephone: pt4.telephone,
        dateEntree: C.iso(entree),
        dateSortie: clos ? C.iso(C.addDays(entree, duree)) : null,
        motif: C.pick(rnd, ['Fièvre persistante depuis cinq jours',
          'Douleurs abdominales intenses', 'Asthénie et pâleur', 'Toux fébrile']),
        anamnese: 'Patient(e) admis(e) pour ' + diag.toLowerCase()
          + '. Début brutal, évolution sur plusieurs jours, automédication préalable sans amélioration.',
        examenPhysique: 'État général altéré. Conjonctives ' + C.pick(rnd, ['pâles', 'normocolorées'])
          + '. Abdomen souple. Auscultation cardio-pulmonaire ' + C.pick(rnd, ['normale', 'crépitants à la base droite']) + '.',
        hypotheses: diag + ' — à confirmer par les examens.',
        traitementEntree: C.pick(rnd, ['Artésunate injectable, réhydratation',
          'Ceftriaxone 1 g/j, antipyrétiques', 'Transfusion de deux culots, fer injectable']),
        examensParacliniques: 'GE-DP, NFS, ionogramme.',
        diagnosticRetenu: diag,
        traitementReajuste: rnd() > 0.5 ? 'Relais per os après apyrexie de 48 heures.' : '',
        evolution: clos ? 'Évolution favorable sous traitement. Apyrexie obtenue à J' + C.between(rnd, 2, 5) + '.'
          : 'Évolution en cours.',
        traitementSortie: clos ? 'Poursuite du traitement per os pendant sept jours.' : '',
        diagnosticSortie: clos ? diag + ' — guérison' : '',
        medecinId: md.id, medecin: md.nomComplet,
      });
    }
    faits.rapports = rap.active().length;

    return faits;
  }

  /* ==========================================================================
   * 4. L'IMAGERIE
   * ======================================================================== */
  function imagerie(rnd) {
    var d = D();
    var IM = d.IMAGERIE || {};
    var col2 = col('resultatsImagerie', { module: 'M2', entite: 'compte rendu d’imagerie', prefix: 'IMG' });
    var realisateur = soignantsQui(function (x) { return x.realiseImagerie; })[0]
      || soignantsQui(function (x) { return x.qualite === 'medecin'; })[0];
    var prescripteurs = soignantsQui(function (x) { return x.prescrit; });
    if (!realisateur || !prescripteurs.length) return 0;

    var INDICATIONS = {
      'IMG-ECHO-PEL': ['Kyste ovarien ?', 'Métrorragies', 'Douleurs pelviennes', 'Bilan d’infertilité'],
      'IMG-ECHO-ABD': ['Douleurs de l’hypochondre droit', 'Ictère', 'Hépatomégalie'],
      'IMG-ECHO-ABP': ['Ascite ?', 'Douleurs abdominales diffuses', 'Bilan d’extension'],
      'IMG-ECHO-PRO': ['RAU', 'Dysurie', 'PSA élevé'],
      'IMG-ECHO-OBS': ['Croissance', 'Terme', 'Vitalité fœtale'],
      'IMG-ECHO-OBS1': ['Terme', 'Métrorragies du premier trimestre', 'Datation'],
      'IMG-ECG': ['Palpitations', 'Douleur thoracique', 'Bilan préopératoire', 'HTA'],
    };

    var n = 0;
    (IM.EXAMENS || []).forEach(function (ex) {
      var combien = /OBS/.test(ex.code) ? 20 : (ex.code === 'IMG-ECG' ? 14 : 12);
      for (var i = 0; i < combien; i++) {
        var pool = /OBS/.test(ex.code)
          ? patients().filter(function (p) { return p.sexe === 'F'; })
          : patients();
        var p = unDe(rnd, pool);
        var presc = unDe(rnd, prescripteurs);
        if (!p || !presc) break;

        /* Les valeurs suivent les variables DÉCLARÉES de l'examen : une
           variable ajoutée demain sera peuplée sans toucher à ce fichier. */
        var valeurs = {};
        (IM.variablesDe(ex.code) || []).forEach(function (v) {
          if (v.type === 'liste' || v.type === 'binaire') {
            /* On penche vers la normale : un jeu où tout est pathologique
               rendrait la mise en évidence des écarts illisible. */
            valeurs[v.code] = (v.normal && rnd() > 0.22) ? v.normal
              : C.pick(rnd, v.options || [v.normal || '']);
          } else if (v.type === 'mesure') {
            valeurs[v.code] = Number((C.between(rnd, 20, 320) / (v.unite === 'g' ? 3 : 1)).toFixed(1));
          } else if (v.type === 'dimensions') {
            valeurs[v.code + '_a'] = C.between(rnd, 40, 120);
            valeurs[v.code + '_b'] = C.between(rnd, 30, 90);
            valeurs[v.code + '_c'] = C.between(rnd, 25, 70);
          } else if (v.type === 'gestationnel') {
            valeurs[v.code + '_sa'] = C.between(rnd, 6, 40);
            valeurs[v.code + '_j'] = C.between(rnd, 0, 6);
          } else if (v.type === 'texte') {
            valeurs[v.code] = v.normal || 'RAS';
          }
        });

        var rendu = rnd() > 0.18;
        col2.insert({
          reference: 'IMG-' + C.pad(++n, 4),
          date: C.iso(jourOuvre(rnd)) + 'T' + C.pad(C.between(rnd, 8, 17), 2) + ':00:00.000Z',
          examenCode: ex.code, examen: ex.label,
          patientId: p.id, patient: p.nom + ' ' + p.prenom, patientCode: p.code,
          age: C.age(p.dateNaissance),
          indication: C.pick(rnd, INDICATIONS[ex.code] || ['Bilan']),
          ddr: /OBS/.test(ex.code) ? (rnd() > 0.5 ? 'inconnue' : C.dateFR(C.iso(C.addDays(FIN, -C.between(rnd, 60, 250))))) : '—',
          condition: C.pick(rnd, ['Bonne', 'Bonne', 'Bonne', 'Moyenne']),
          prescripteurId: presc.id, prescripteur: presc.nomComplet,
          realisateurId: realisateur.id, realisateur: realisateur.nomComplet,
          valeurs: valeurs,
          annexes: rnd() > 0.6 ? 'Ovaires normaux. Cul-de-sac de Douglas libre.' : '',
          conclusion: conclusionImagerie(rnd, ex.code),
          statut: rendu ? 'rendu' : 'brouillon',
          renduLe: rendu ? C.iso(FIN) : null,
        });
      }
    });
    return n;
  }

  function conclusionImagerie(rnd, code) {
    if (/OBS1/.test(code)) {
      return 'Grossesse monoembryonnaire intra-utérine évolutive de biométrie correspondante au terme '
        + 'échographique de ' + C.pad(C.between(rnd, 6, 13), 2) + ' SA + '
        + C.pad(C.between(rnd, 0, 6), 2) + ' jours. À contrôler à 22 SA pour étudier la morphologie fœtale.';
    }
    if (/OBS/.test(code)) {
      return 'Grossesse monofœtale intra-utérine évolutive au terme échographique de '
        + C.between(rnd, 22, 39) + ' SA. Morphologie fœtale apparemment normale. '
        + 'Liquide amniotique d’abondance moyenne.';
    }
    if (/PRO/.test(code)) {
      return C.pick(rnd, ['Hypertrophie prostatique bénigne.', 'Prostate de volume normal.',
        'Hypertrophie prostatique hétérogène — avis urologique conseillé.'])
        + ' Reins normaux, sans dilatation des cavités pyélocalicielles.';
    }
    if (/ECG/.test(code)) {
      return C.pick(rnd, ['Tracé sinusal régulier sans anomalie.',
        'Rythme sinusal, trouble de repolarisation en territoire latéral.',
        'Tracé normal pour l’âge.']);
    }
    return C.pick(rnd, ['Examen échographique normal des viscères pleins intra-abdominaux.',
      'Absence d’épanchement liquidien intra-péritonéal.',
      'Utérus de statique antéversée, homogène et non gravide. Ovaires normaux.']);
  }

  /* ==========================================================================
   * 5. L'ACCUEIL — dossiers, références, file d'attente
   * ======================================================================== */
  function accueil(rnd) {
    var d = D();
    var faits = {};
    var recus = personnel().filter(function (a) { return a.fonction === 'accueil'; });
    var soignantsTous = soignants();

    /* --- Dossiers de consultation étendus -------------------------------- */
    var dos = col('dossiersConsultation', { module: 'M1', entite: 'dossier de consultation', prefix: 'DOS' });
    var ETATS = ['attente', 'consultation', 'attente_labo', 'cloture'];
    for (var i = 0; i < 60; i++) {
      var p = unDe(rnd, patients());
      var recu = unDe(rnd, recus);
      if (!p) break;
      /* Les dossiers récents sont en cours, les anciens sont clôturés : un jeu
         où tout est clôturé ne montrerait jamais la file de consultation. */
      var recul = reculAleatoire(rnd);
      var etat = recul < 2 ? C.pick(rnd, ['attente', 'consultation', 'attente_labo'])
        : (recul < 8 ? C.pick(rnd, ['consultation', 'attente_labo', 'cloture']) : 'cloture');
      var dt = jour(rnd, recul);
      var poids = C.between(rnd, 42, 96);
      var taille = C.between(rnd, 148, 188);
      var avance = ETATS.indexOf(etat) >= 1;
      dos.insert(Object.assign({
        reference: 'DOS-' + C.pad(i + 1, 5),
        patientId: p.id, patient: p.nom + ' ' + p.prenom, patientCode: p.code, nip: p.code,
        age: C.age(p.dateNaissance), sexe: p.sexe,
        assureur: p.assureurNom || p.assureur || null,
        dateArrivee: C.iso(dt),
        heureArrivee: C.pad(C.between(rnd, 7, 17), 2) + 'h' + C.pad(C.between(rnd, 0, 59), 2),
        motifVenue: C.pick(rnd, ['Fièvre', 'Douleurs abdominales', 'Consultation prénatale',
          'Contrôle', 'Toux', 'Céphalées', 'Plaie', 'Asthénie']),
        service: C.pick(rnd, ['medecine', 'medecine', 'maternite', 'specialite', 'chirurgie']),
        temperature: Number((36.2 + rnd() * 2.6).toFixed(1)),
        tension: C.between(rnd, 9, 16) + '/' + C.between(rnd, 5, 10),
        pouls: C.between(rnd, 58, 112),
        spo2: C.between(rnd, 93, 100),
        poids: poids, taille: taille,
        imc: Math.round((poids / Math.pow(taille / 100, 2)) * 10) / 10,
        recuPar: recu ? recu.nomComplet : 'Accueil',
        etat: etat,
        ouvertLe: C.iso(dt) + 'T08:00:00.000Z',
      }, avance ? dossierClinique(rnd, soignantsTous) : {}));
    }
    faits.dossiers = dos.active().length;

    /* --- Fiches de référence et contre-références ------------------------ */
    var ref = col('fichesReference', { module: 'M1', entite: 'fiche de référence', prefix: 'REF' });
    var crf = col('contreReferences', { module: 'M1', entite: 'fiche de contre-référence', prefix: 'CRF' });
    var CENTRES = ['CHUD Borgou-Alibori — Parakou', 'CHU-MEL Cotonou', 'Hôpital Saint Jean de Dieu — Boko',
      'CNHU-HKM Cotonou', 'Centre de santé de N’Dali', 'Hôpital Saint-Jean de Dieu, Tanguiéta'];
    var MOTIFS = ['Absence de médicaments', 'Absence de moyens de diagnostic',
      'Absence de personnel qualifié', 'Pas de réponse au traitement'];
    for (var r = 0; r < 30; r++) {
      var pt = unDe(rnd, patients());
      var ag = unDe(rnd, soignantsTous);
      if (!pt || !ag) break;
      var sortante = rnd() > 0.4;
      var dtr = jourOuvre(rnd);
      var numero = 'REF-' + C.pad(r + 1, 5);
      ref.insert({
        numero: numero,
        sens: sortante ? 'sortante' : 'entrante',
        urgent: rnd() > 0.7,
        patientId: pt.id, patient: pt.nom + ' ' + pt.prenom, patientCode: pt.code,
        age: C.age(pt.dateNaissance), sexe: pt.sexe, adresse: pt.quartier,
        formationSanitaire: sortante ? 'CLINIQUE BAGUIDI « L’AS DE CŒUR »' : C.pick(rnd, CENTRES),
        centreAlerte: rnd() > 0.4,
        dateAdmission: C.iso(dtr), heureAdmission: C.pad(C.between(rnd, 7, 20), 2) + 'h00',
        pouls: C.between(rnd, 60, 130), temperature: Number((36.5 + rnd() * 3).toFixed(1)),
        tension: C.between(rnd, 8, 16) + '/' + C.between(rnd, 5, 10),
        abordVeineux: rnd() > 0.35,
        contactNom: C.pick(rnd, ['ADAMOU Rachidatou', 'OROU Bio Sanni', 'TCHOBO Marcel', 'KORA Fatima']),
        contactAdresse: pt.quartier + ' — 0' + C.between(rnd, 1, 9) + C.between(rnd, 10000000, 99999999),
        symptomes: C.pick(rnd, ['Détresse respiratoire aiguë', 'Hémorragie du post-partum',
          'Coma fébrile', 'Traumatisme crânien', 'Anémie sévère mal tolérée',
          'Occlusion intestinale', 'Éclampsie']),
        traitements: C.pick(rnd, ['Oxygénothérapie, remplissage', 'Ocytocine, massage utérin',
          'Artésunate IV, antipyrétique', 'Immobilisation, antalgique', 'Transfusion d’un culot']),
        observations: rnd() > 0.6 ? 'Patient stabilisé avant transfert.' : '',
        motifs: [C.pick(rnd, MOTIFS)],
        centreDestination: sortante ? C.pick(rnd, CENTRES) : 'CLINIQUE BAGUIDI « L’AS DE CŒUR »',
        dateReference: C.iso(dtr), heureReference: C.pad(C.between(rnd, 7, 22), 2) + 'h' + C.pad(C.between(rnd, 0, 59), 2),
        moyen: C.pick(rnd, ['Ambulance', 'Ambulance', 'Taxi', 'Moyen personnel', 'Moto']),
        agentReferent: ag.nomComplet + ' — ' + ag.poste,
        departLe: C.dateFR(C.iso(dtr)) + ' ' + C.pad(C.between(rnd, 7, 22), 2) + 'h00',
        arriveeLe: C.dateFR(C.iso(dtr)) + ' ' + C.pad(C.between(rnd, 8, 23), 2) + 'h30',
        ambulancier: 'TCHANE Nourou',
      });

      /* La contre-référence ne revient pas toujours — et c'est justement
         l'indicateur que la clinique veut suivre. */
      if (sortante && rnd() > 0.45) {
        var concorde = rnd() > 0.25;
        crf.insert({
          reference: 'CRF-' + C.pad(r + 1, 5),
          numeroReference: numero,
          patientId: pt.id, patient: pt.nom + ' ' + pt.prenom, patientCode: pt.code,
          centreAccueil: C.pick(rnd, CENTRES),
          service: C.pick(rnd, ['Réanimation', 'Chirurgie', 'Médecine interne', 'Maternité', 'Pédiatrie']),
          dateArrivee: C.iso(C.addDays(dtr, C.between(rnd, 0, 1))),
          heureArrivee: C.pad(C.between(rnd, 8, 23), 2) + 'h15',
          agentReferent: ag.nomComplet,
          structureProvenance: 'CLINIQUE BAGUIDI « L’AS DE CŒUR »',
          hospitalise: rnd() > 0.25,
          numeroDossier: 'D' + C.between(rnd, 10000, 99999),
          diagnosticEntree: C.pick(rnd, ['Détresse respiratoire', 'Anémie sévère',
            'Hémorragie du post-partum', 'Traumatisme crânien']),
          diagnosticSortie: C.pick(rnd, ['Pneumopathie sévère', 'Anémie sur paludisme grave',
            'Atonie utérine', 'Contusion cérébrale']),
          concordance: concorde,
          justifiee: concorde || rnd() > 0.3,
          motifNonJustifiee: '',
          evolution: C.pick(rnd, ['Guéri(e)', 'Guéri(e)', 'Guéri(e)', 'Décédé(e)',
            'Référé vers un autre centre', 'Sortie contre avis médical']),
          observations: concorde ? 'Référence pertinente, prise en charge poursuivie.'
            : 'Le diagnostic initial n’a pas été confirmé ; le bilan a orienté autrement.',
          chefService: C.pick(rnd, ['Dr ADJOVI Pascal', 'Dr SOGLO Marie', 'Dr HOUNKPE Jean']),
        });
      }
    }
    faits.references = ref.active().length;
    faits.contreReferences = crf.active().length;

    /* --- La file d'attente du jour --------------------------------------- */
    var file = col('fileAttente', { module: 'M2', entite: 'ticket de file', prefix: 'FIL' });
    var POSTES = [['accueil', 'Accueil'], ['consultation', 'Consultation'], ['caisse', 'Caisse'],
      ['prelevement', 'Salle de prélèvement'], ['pharmacie', 'Pharmacie'], ['salle_soins', 'Salle de soins'],
      ['imagerie', 'Échographie']];
    var PRIORITES = ['ordre_arrivee', 'ordre_arrivee', 'ordre_arrivee', 'rdv', 'urgence', 'urgence_vitale'];
    /* Les praticiens qui reçoivent, dérivés du personnel soignant. */
    var recoivent = soignantsQui(function (x) { return x.prescrit; });

    POSTES.forEach(function (po) {
      var n = C.between(rnd, 0, 6);
      for (var f = 0; f < n; f++) {
        var pt = unDe(rnd, patients());
        if (!pt) break;
        var attente = C.between(rnd, 3, 75);
        var servi = rnd() > 0.55;
        /* Un patient sur trois est adressé NOMMÉMENT — rendez-vous nominatif
           ou suivi en cours. Les deux autres restent en file commune : le
           prochain praticien libre les prend. Tous les nommer donnerait une
           image fausse du couloir. */
        var attendu = (po[0] === 'consultation' && recoivent.length && rnd() > 0.66)
          ? unDe(rnd, recoivent) : null;
        file.insert({
          numero: po[1].slice(0, 1).toUpperCase() + C.pad(f + 1, 3),
          poste: po[0], posteLabel: po[1],
          patientId: pt.id, patient: pt.nom + ' ' + pt.prenom, patientCode: pt.code,
          praticien: attendu ? attendu.nomComplet : null,
          priorite: C.pick(rnd, PRIORITES),
          motif: C.pick(rnd, ['Consultation', 'Retrait de résultat', 'Règlement',
            'Prélèvement', 'Délivrance', 'Pansement', 'Échographie']),
          arriveeLe: C.iso(FIN) + 'T' + C.pad(7 + Math.floor(attente / 12), 2) + ':'
            + C.pad(attente % 60, 2) + ':00.000Z',
          etat: servi ? 'servi' : 'attente',
          serviLe: servi ? C.iso(FIN) + 'T' + C.pad(8 + Math.floor(attente / 12), 2) + ':00:00.000Z' : null,
          appelePar: servi ? 'Accueil' : null,
        });
      }
    });
    faits.file = file.active().length;
    return faits;
  }

  /* Le volet clinique d'un dossier avancé. */
  function dossierClinique(rnd, soignantsTous) {
    var med = soignantsTous.filter(function (x) { return x.prescrit; });
    var s = med.length ? C.pick(rnd, med) : null;
    var o = {
      typeVenue: C.pick(rnd, ['premiere', 'controle', 'suivi', 'urgence']),
      histoire: C.pick(rnd, [
        'Fièvre évoluant depuis quatre jours, associée à des céphalées et des courbatures.',
        'Douleurs épigastriques post-prandiales, sans vomissement.',
        'Grossesse suivie, sans complication jusqu’à ce jour.',
        'Toux productive depuis une semaine, fièvre vespérale.',
      ]),
      traitementEnCours: rnd() > 0.55 ? C.pick(rnd, ['Paracétamol en automédication',
        'Traitement antihypertenseur au long cours', 'Fer et acide folique']) : '',
      ant_medicaux: C.pick(rnd, ['Aucun', 'Hypertension artérielle traitée', 'Drépanocytose SC',
        'Asthme dans l’enfance', 'Diabète de type 2', 'Aucun antécédent notable']),
      ant_chirurgicaux: C.pick(rnd, ['Aucun', 'Appendicectomie en 2018', 'Césarienne en 2022',
        'Herniorraphie en 2015', 'Aucun']),
      ant_gyneco_obstetricaux: C.pick(rnd, ['Sans objet', 'G3 P2 A1, 2 enfants vivants',
        'G1 P0, première grossesse', 'Ménarche à 14 ans, cycles réguliers']),
      exam_inspection: C.pick(rnd, ['État général conservé, conjonctives normocolorées.',
        'Patient asthénique, muqueuses pâles.', 'Bon état général, pas de détresse.']),
      exam_palpation: C.pick(rnd, ['Abdomen souple, dépressible, indolore.',
        'Sensibilité de l’hypochondre droit, pas de défense.',
        'Adénopathies cervicales infracentimétriques.']),
      exam_percussion: C.pick(rnd, ['Sonorité pulmonaire normale.', 'Matité de la base droite.',
        'Tympanisme abdominal conservé.']),
      exam_auscultation: C.pick(rnd, ['Bruits du cœur réguliers, murmure vésiculaire présent.',
        'Quelques crépitants à la base droite.', 'Auscultation sans particularité.']),
      diagnostic: C.pick(rnd, ['Paludisme simple', 'Fièvre typhoïde', 'Gastrite',
        'Grossesse évolutive du deuxième trimestre', 'Bronchite aiguë', 'Anémie ferriprive']),
      analysesDemandees: C.pick(rnd, ['GE-DP, NFS', 'Sérodiagnostic de Widal, NFS',
        'ECBU, glycémie', 'NFS, GS-Rh', 'Aucune']),
      traitement: C.pick(rnd, ['Artéméther-luméfantrine 6 prises, paracétamol',
        'Ciprofloxacine 500 mg x 2/j pendant 7 jours',
        'Oméprazole 20 mg le matin, pansement gastrique',
        'Fer + acide folique, conseils diététiques']),
      conduite: C.pick(rnd, ['Revoir dans une semaine avec les résultats.',
        'Consulter en urgence si aggravation.', 'Contrôle dans un mois.']),
      soignant: s ? s.nomComplet : 'Médecin',
    };
    return o;
  }

  /* ==========================================================================
   * 6. LES PIÈCES CERTIFIANTES
   * ======================================================================== */
  function piecesCertifiantes(rnd) {
    var types = S().collection('typesPiece').active();
    var pieces = col('pieces', { module: 'M1', entite: 'pièce certifiante', prefix: 'PCE' });
    var medecins = parFonction('medecin');
    var d = D();
    if (!types.length || !medecins.length) return 0;

    var CORPS = {
      ATG: 'Je soussigné, Docteur en médecine, certifie avoir examiné ce jour la patiente '
        + 'susnommée et avoir constaté un état de grossesse évolutive.',
      CMNI: 'Je soussigné certifie que l’intéressé(e) ne présente aucune infirmité apparente '
        + 'de nature à le rendre inapte à l’emploi postulé.',
      CMD: 'Je soussigné certifie que le décès est survenu aux date et heure indiquées, '
        + 'de cause naturelle, en l’absence de signe de mort suspecte.',
      CMP: 'Je soussigné certifie avoir examiné l’intéressé(e) et pris connaissance des examens '
        + 'complémentaires. Aucune contre-indication médicale au mariage n’est relevée.',
      CMCBV: 'Je soussigné certifie avoir examiné l’intéressé(e) qui présente les lésions décrites '
        + 'ci-dessus, compatibles avec les faits allégués.',
      CMDPS: 'Je soussigné certifie que l’état de santé de l’intéressé(e) justifie une dispense '
        + 'temporaire des activités physiques et sportives.',
      CMNCI: 'Je soussigné certifie n’avoir constaté ce jour aucune contre-indication à la pratique '
        + 'des activités physiques et sportives.',
      CMVC: 'Je soussigné certifie avoir procédé à la visite médicale de l’intéressé(e).',
      'CMR-H': 'Je soussigné certifie que l’état de santé de l’intéressé(e) nécessite un arrêt '
        + 'de travail à compter de ce jour.',
      CMH: 'Je soussigné certifie que l’intéressé(e) est hospitalisé(e) dans notre établissement '
        + 'et que la présence d’un garde-malade est nécessaire.',
      CMA: 'Je soussigné certifie les faits rapportés ci-dessus, constatés dans notre établissement.',
      SCAM: 'Je soussigné reconnais avoir été informé(e) de mon état de santé et des risques '
        + 'encourus, et demander expressément à quitter l’établissement contre avis médical.',
    };

    var n = 0;
    types.forEach(function (t) {
      var combien = C.between(rnd, 2, 9);
      for (var i = 0; i < combien; i++) {
        var p = unDe(rnd, patients());
        var md = unDe(rnd, medecins);
        if (!p || !md) break;
        var an = FIN.getFullYear();
        n++;
        var tarif = t.tarifCode && d.tarif ? d.tarif(t.tarifCode) : null;
        pieces.insert({
          numero: i + 1, annee: an,
          reference: t.sigle + ' ' + C.pad(i + 1, 3) + '/' + C.pad(i + 1, 3)
            + '/' + C.BRAND.sigle + '/' + t.direction + '/' + an,
          sigle: t.sigle, libelle: t.libelle, direction: t.direction,
          typeId: t.id,
          patientId: p.id, patient: p.nom + ' ' + p.prenom, patientCode: p.code,
          medecin: md.nomComplet,
          dateDelivrance: C.iso(jourOuvre(rnd)),
          contenu: CORPS[t.sigle] || 'En foi de quoi la présente pièce est établie pour servir et '
            + 'valoir ce que de droit.',
          remisA: rnd() > 0.7 ? C.pick(rnd, ['L’intéressé(e)', 'Le conjoint', 'L’employeur'])
            : 'L’intéressé(e)',
          montant: tarif ? tarif.prixNonAssure : null,
          couverture: tarif && tarif.assurable === 'sos'
            ? 'Couvert par SOS uniquement — toute autre compagnie : à la charge du patient'
            : 'Non couvert par les assurances',
        });
      }
    });
    return n;
  }

  /* ==========================================================================
   * 7. RH, PAIE ET ADMINISTRATION
   * ======================================================================== */
  function ressourcesHumaines(rnd) {
    var faits = {};
    var agents = personnel();

    /* --- Prêts-études et avances ----------------------------------------- */
    var prets = col('pretsEtudes', { module: 'M11', entite: 'prêt-études', prefix: 'PRT' });
    var OBJETS = {
      pret_etudes: ['Licence en soins infirmiers', 'Formation en gestion hospitalière',
        'Diplôme de sage-femme', 'Formation continue en biologie médicale'],
      avance: ['Avance sur salaire — rentrée scolaire', 'Avance sur salaire — dépense familiale',
        'Avance sur salaire — déménagement'],
      pret_social: ['Frais d’obsèques d’un parent', 'Hospitalisation d’un enfant',
        'Réparation du domicile'],
    };
    for (var i = 0; i < 12; i++) {
      var a = unDe(rnd, agents);
      if (!a) break;
      var nature = C.pick(rnd, ['pret_etudes', 'avance', 'pret_social']);
      var montant = C.between(rnd, 3, 30) * 25000;
      var n = C.between(rnd, 3, 12);
      var debut = C.addDays(FIN, -C.between(rnd, 30, 240));
      var mois = debut.getFullYear() + '-' + C.pad(debut.getMonth() + 1, 2);
      /* Les échéances passées sont réputées retenues : sinon aucun prêt ne
         serait jamais en cours de remboursement. */
      var retenues = [];
      var ecoule = Math.min(n, Math.max(0, Math.round((FIN - debut) / 2592000000)));
      for (var k = 0; k < ecoule; k++) {
        var dd = new Date(debut.getFullYear(), debut.getMonth() + k, 1);
        retenues.push(dd.getFullYear() + '-' + C.pad(dd.getMonth() + 1, 2));
      }
      prets.insert({
        reference: 'PRT-' + C.pad(i + 1, 4),
        employeId: a.id, agent: a.nomComplet, matricule: a.matricule,
        nature: nature, objet: C.pick(rnd, OBJETS[nature]),
        montant: montant,
        dateAccord: C.iso(debut),
        premiereEcheance: mois, nbEcheances: n,
        autorisePar: 'SOKOU Peace',
        retenues: retenues,
      });
    }
    faits.prets = prets.active().length;

    /* --- Événements du personnel et participations ------------------------ */
    var evts = col('evenements', { module: 'M10', entite: 'événement', prefix: 'EVT' });
    var parts = col('participations', { module: 'M10', entite: 'participation', prefix: 'PAR' });
    var NATURES = [['mariage', 'Mariage'], ['naissance', 'Naissance'], ['deces', 'Décès']];
    for (var e = 0; e < 9; e++) {
      var ben = unDe(rnd, agents);
      if (!ben) break;
      var nat = C.pick(rnd, NATURES);
      var dte = C.addDays(FIN, -C.between(rnd, 5, 240));
      var mp = dte.getFullYear() + '-' + C.pad(dte.getMonth() + 1, 2);
      var evt = evts.insert({
        reference: 'EVT-' + C.pad(e + 1, 4),
        nature: nat[0],
        libelle: nat[1] + ' — ' + ben.nomComplet,
        beneficiaireId: ben.id, beneficiaire: ben.nomComplet,
        date: C.iso(dte),
        montantParAgent: 1000,
        periodePaiement: mp,
        modeParDefaut: C.pick(rnd, ['salaire', 'comptant']),
        portee: 'tous',
      }).record;

      /* UNE PARTICIPATION PAR AGENT, HORS BÉNÉFICIAIRE — c'est ce geste unique
         qui fait tenir le module. */
      agents.forEach(function (ag) {
        if (ag.id === ben.id) return;
        var comptant = evt.modeParDefaut === 'comptant' || rnd() > 0.75;
        parts.insert({
          reference: 'PAR-' + C.uid().slice(0, 6),
          evenementId: evt.id, evenementLibelle: evt.libelle,
          agentId: ag.id, agent: ag.nomComplet, matricule: ag.matricule,
          montant: 1000,
          mode: comptant ? 'comptant' : 'salaire',
          periodeRetenue: comptant ? null : mp,
          regle: comptant ? rnd() > 0.2 : rnd() > 0.35,
          dateReglement: comptant ? C.iso(C.addDays(dte, C.between(rnd, 0, 10))) : null,
        });
      });
    }
    faits.evenements = evts.active().length;
    faits.participations = parts.active().length;
    return faits;
  }

  /* ==========================================================================
   * 7 bis. MATERNITÉ — rapport officiel du 27/08/2026
   * --------------------------------------------------------------------------
   * SEMÉE AU SOCLE, et non plus par l'écran m4 : les statistiques (PIL) et le
   * tableau de bord de la sage-femme lisent ces collections — une collection
   * amorcée par son écran affiche un zéro FAUX partout ailleurs (le piège
   * documenté, vague 31). L'ancien amorçage d'écran (seed 509) est repris ici
   * à l'identique puis ENRICHI des variables du rapport : PC/PT, Apgar aux
   * trois temps, vitamine K1, vaccins J0, CPN structurée, CPoN, SONU, PF,
   * PTME, soins curatifs (Case 27), partogrammes.
   * ======================================================================== */
  function maternite() {
    var faits = {};
    var rnd = C.seeded(509);
    var fs = patients().filter(function (p) { return p.sexe === 'F'; });
    var sf = personnel().filter(function (e) { return e.fonction === 'sage_femme' || e.fonction === 'medecin'; })
      .map(function (e) { return e.nomComplet; });
    if (!fs.length || !sf.length) return faits;
    var d2 = D();

    var acc = col('accouchements', { module: 'M4', entite: 'Accouchement' });
    var nais = col('naissances', { module: 'M4', entite: 'Naissance' });
    var suivi = col('suiviMaternite', { module: 'M4', entite: 'SuiviMaternite' });
    var dec = col('deces', { module: 'M4', entite: 'Deces' });

    if (!acc.all().length) {
      for (var i = 0; i < 48; i++) {
        var mere = C.pick(rnd, fs);
        var dt = C.addDays(FIN, -C.between(rnd, 0, 260));
        dt.setHours(C.between(rnd, 0, 23), C.between(rnd, 0, 59));
        var type = C.pick(rnd, ['Eutocique', 'Eutocique', 'Eutocique', 'Dystocique', 'Dirigé', 'Césarienne']);
        acc.all().push({
          id: 'ACC' + C.pad(i + 1, 4), statut: 'actif', reference: 'ACC-' + C.pad(i + 1, 4),
          patientId: mere.id, patient: mere.nom + ' ' + mere.prenom, patientCode: mere.code,
          dateHeure: dt.toISOString(),
          type: type,
          voie: type === 'Césarienne' ? 'Césarienne' : 'Voie basse',
          actes: rnd() > 0.7 ? [C.pick(rnd, d2.ACTES_ACCOUCHEMENT)] : [],
          sageFemme: C.pick(rnd, sf),
          duree: C.between(rnd, 2, 18) + ' h',
          complications: rnd() > 0.85 ? C.pick(rnd, ['Hémorragie de la délivrance', 'Souffrance fœtale', 'Dystocie']) : 'Aucune',
          issue: rnd() > 0.03 ? 'Favorable' : 'Défavorable',
        });

        /* Le volet nouveau-né du registre : PC/PT OBLIGATOIRES (Module C),
           Apgar aux trois temps, soins essentiels, vaccins J0. */
        var vivant = rnd() > 0.02;
        var a5 = C.between(rnd, 6, 10);
        nais.all().push({
          id: 'NAI' + C.pad(i + 1, 4), statut: 'actif',
          reference: 'NAI-' + C.pad(i + 1, 4), accouchementId: 'ACC' + C.pad(i + 1, 4),
          dateHeure: dt.toISOString(),
          mere: mere.nom + ' ' + mere.prenom, mereCode: mere.code, mereId: mere.id,
          sexe: rnd() > 0.5 ? 'M' : 'F',
          poids: (2.2 + rnd() * 2.1).toFixed(2),
          taille: C.between(rnd, 44, 54),
          pc: Math.round((32 + rnd() * 6) * 10) / 10,
          pt: Math.round((30 + rnd() * 6) * 10) / 10,
          apgar1: Math.max(3, a5 - C.between(rnd, 0, 2)),
          apgar5: a5,
          apgar10: Math.min(10, a5 + C.between(rnd, 0, 2)),
          reanimation: a5 < 7,
          vitK1: rnd() > 0.05,
          collyre: rnd() > 0.05,
          vpo0: rnd() > 0.12, bcg: rnd() > 0.12, hepB0: rnd() > 0.18,
          vivant: vivant,
          declare: vivant ? rnd() > 0.15 : false,
        });
      }
    }
    faits.accouchements = acc.active().length;
    faits.naissances = nais.active().length;

    /* --- CPN structurée : la carte maternelle (Module B, tableau 8) -------- */
    var gro = col('grossesses', { module: 'M4', entite: 'grossesse', prefix: 'GRO' });
    if (!gro.all().length) {
      for (var g = 0; g < 18; g++) {
        var f2 = C.pick(rnd, fs);
        var terme = C.between(rnd, 8, 38);
        var doses = d2.DOSES_SP.slice(0, Math.min(5, Math.floor(terme / 7)));
        var visites = [];
        for (var vn = 1; vn <= Math.min(4, Math.ceil(terme / 10)); vn++) {
          visites.push({
            n: vn, date: C.iso(C.addDays(FIN, -(terme - vn * 8) * 7)),
            ta: C.between(rnd, 9, 14) + '/' + C.between(rnd, 5, 9),
            poids: 52 + C.between(rnd, 0, 30),
            hu: 10 + vn * 6 + C.between(rnd, 0, 3),
            bdcf: 120 + C.between(rnd, 0, 40),
            albumine: rnd() > 0.9 ? '+' : '—', sucre: rnd() > 0.93 ? '+' : '—',
          });
        }
        gro.all().push({
          id: 'GRO' + C.pad(g + 1, 4), statut: 'actif', reference: 'CPN-' + C.pad(g + 1, 4),
          patientId: f2.id, patient: f2.nom + ' ' + f2.prenom, patientCode: f2.code,
          ddr: C.iso(C.addDays(FIN, -terme * 7)),
          dpa: C.iso(C.addDays(FIN, (40 - terme) * 7)),
          termeSA: terme,
          groupeSanguin: f2.groupeSanguin || C.pick(rnd, ['O+', 'A+', 'B+']),
          sageFemme: C.pick(rnd, sf),
          gar: rnd() > 0.78,
          milda: rnd() > 0.2,
          mebendazole: terme >= 14 ? rnd() > 0.25 : false,
          vat: 'VAT' + C.between(rnd, 1, 5),
          fer: rnd() > 0.15, folates: rnd() > 0.2,
          sp: doses,
          visites: visites,
        });
      }
    }
    faits.grossesses = gro.active().length;

    /* --- CPoN — avec l'hémorragie ANTE-partum, la variable NOUVELLE -------- */
    var cpo = col('cpon', { module: 'M4', entite: 'consultation post-natale', prefix: 'CPO' });
    if (!cpo.all().length) {
      for (var c2 = 0; c2 < 20; c2++) {
        var accRef = C.pick(rnd, acc.active());
        var hAnte = rnd() > 0.85;
        cpo.all().push({
          id: 'CPO' + C.pad(c2 + 1, 4), statut: 'actif', reference: 'CPO-' + C.pad(c2 + 1, 4),
          patientId: accRef.patientId, patient: accRef.patient, patientCode: accRef.patientCode,
          accouchementRef: accRef.reference,
          date: C.iso(C.addDays(C.toDate(accRef.dateHeure), C.between(rnd, 1, 42))),
          type: C.pick(rnd, ['cpon1', 'cpon2', 'cpon3']),
          hemorragieAntePartum: hAnte,
          etiologieAnte: hAnte ? C.pick(rnd, ['Placenta praevia', 'Hématome rétro-placentaire', 'Rupture utérine']) : null,
          hpp: rnd() > 0.9,
          examen: 'TA, T°, utérus, lochies, seins — ' + C.pick(rnd, ['sans particularité', 'involution normale', 'à surveiller']),
          supplementation: rnd() > 0.3 ? 'Vit A + Fer/Folates' : 'Fer/Folates',
          conseilPF: rnd() > 0.4,
          etatNouveauNe: C.pick(rnd, ['Bon état, allaitement établi', 'Ictère modéré à surveiller', 'Cordon propre, poids en hausse']),
          sageFemme: C.pick(rnd, sf),
        });
      }
    }
    faits.cpon = cpo.active().length;

    /* --- Planification familiale — 15 méthodes, codification A/N ----------- */
    var pf = col('planificationFamiliale', { module: 'M4', entite: 'consultation PF', prefix: 'PF' });
    if (!pf.all().length) {
      for (var p3 = 0; p3 < 24; p3++) {
        var cl = C.pick(rnd, fs);
        var meth = C.pick(rnd, d2.METHODES_PF);
        pf.all().push({
          id: 'PF' + C.pad(p3 + 1, 4), statut: 'actif', reference: 'PF-' + C.pad(p3 + 1, 4),
          date: C.iso(jourOuvre(rnd)),
          patientId: cl.id, patient: cl.nom + ' ' + cl.prenom, patientCode: cl.code,
          acceptante: rnd() > 0.45 ? 'A' : 'N',
          methode: meth.code, methodeLabel: meth.label,
          methodeAnterieure: rnd() > 0.6 ? C.pick(rnd, d2.METHODES_PF).label : null,
          ddr: C.iso(C.addDays(FIN, -C.between(rnd, 5, 40))),
          constantes: C.between(rnd, 50, 90) + ' kg · ' + C.between(rnd, 9, 14) + '/' + C.between(rnd, 5, 9),
          rdv: C.iso(C.addDays(FIN, C.between(rnd, 20, 120))),
          sageFemme: C.pick(rnd, sf),
        });
      }
    }
    faits.pf = pf.active().length;

    /* --- Registre SONUB / SONUC -------------------------------------------- */
    var sonu = col('registreSONU', { module: 'M4', entite: 'urgence obstétricale', prefix: 'SNU' });
    if (!sonu.all().length) {
      for (var s3 = 0; s3 < 10; s3++) {
        var pu = C.pick(rnd, fs);
        var du = jourOuvre(rnd); du.setHours(C.between(rnd, 0, 23), C.between(rnd, 0, 59));
        var nf = C.between(rnd, 1, 3);
        var fonctions = [];
        while (fonctions.length < nf) {
          var num = C.between(rnd, 1, 10);
          if (fonctions.indexOf(num) === -1) fonctions.push(num);
        }
        sonu.all().push({
          id: 'SNU' + C.pad(s3 + 1, 4), statut: 'actif', reference: 'SONU-' + C.pad(s3 + 1, 4),
          dateHeure: du.toISOString(),
          patientId: pu.id, patient: pu.nom + ' ' + pu.prenom, patientCode: pu.code,
          gestite: C.between(rnd, 1, 7), parite: C.between(rnd, 0, 6),
          evacuation: rnd() > 0.6,
          provenance: rnd() > 0.6 ? C.pick(rnd, ['CS de Perma', 'CS de Kouandé', 'CS de Boukoumbé']) : 'Venue d’elle-même',
          diagnosticEvacuation: rnd() > 0.5 ? C.pick(rnd, ['Travail prolongé', 'Pré-éclampsie', 'Hémorragie']) : null,
          heureAbordVeineux: C.pad(du.getHours()) + 'h' + C.pad((du.getMinutes() + 12) % 60),
          fonctions: fonctions.sort(function (a, b) { return a - b; }),
          autreGeste: rnd() > 0.8 ? 'Oxygénothérapie au masque' : null,
          heureFinGestes: C.pad((du.getHours() + 2) % 24) + 'h' + C.pad(du.getMinutes()),
          evolution: C.pick(rnd, ['Favorable', 'Favorable', 'Favorable', 'Référée', 'Décédée']),
          agent: C.pick(rnd, sf),
        });
      }
    }
    faits.sonu = sonu.active().length;

    /* --- PTME — quadripartite, données SENSIBLES --------------------------- */
    var ptme = col('ptme', { module: 'M4', entite: 'fiche PTME', prefix: 'PTM' });
    if (!ptme.all().length) {
      for (var t2 = 0; t2 < 6; t2++) {
        var fp = C.pick(rnd, fs);
        var dispensations = [];
        for (var mm = 0; mm < C.between(rnd, 2, 8); mm++) {
          dispensations.push({ mois: C.iso(C.addDays(FIN, -mm * 30)).slice(0, 7), servie: rnd() > 0.15 });
        }
        ptme.all().push({
          id: 'PTM' + C.pad(t2 + 1, 4), statut: 'actif', reference: 'PTME-' + C.pad(t2 + 1, 4),
          patientId: fp.id, patient: fp.nom + ' ' + fp.prenom, patientCode: fp.code,
          /* Volet 1 — dépistage triple. */
          vihTrimestre: C.between(rnd, 1, 3), vihType: C.pick(rnd, ['VIH-1', 'VIH-2', 'VIH-1+2']),
          agHbs: rnd() > 0.85 ? 'Positif' : 'Négatif',
          syphilis: rnd() > 0.9 ? 'Positif' : 'Négatif',
          chargeVirale: rnd() > 0.5 ? 'Indétectable' : C.between(rnd, 50, 5000) + ' copies/ml',
          /* Volet 2 — mère. */
          protocoleARV: 'TDF + 3TC + DTG',
          dureeARV: C.pick(rnd, d2.PTME.dureesARV),
          allaitement: C.pick(rnd, d2.PTME.allaitements),
          prophylaxieNN: C.pick(rnd, d2.PTME.prophylaxiesNN).code,
          /* Volet 3 — enfant exposé. */
          pcrNaissance: rnd() > 0.3 ? 'Négatif' : 'En attente',
          pcr1: rnd() > 0.5 ? 'Négatif' : null,
          pcr2: rnd() > 0.75 ? 'Négatif' : null,
          serologie18m: null,
          ctm: rnd() > 0.2, hepBJ0: rnd() > 0.2,
          /* Volet 4. */
          dispensations: dispensations,
        });
      }
    }
    faits.ptme = ptme.active().length;

    /* --- Soins curatifs & urgences maternité — Case 27 restructurée -------- */
    var cur = col('soinsCuratifsMaternite', { module: 'M4', entite: 'soin curatif maternité', prefix: 'SCM' });
    if (!cur.all().length) {
      for (var u2 = 0; u2 < 16; u2++) {
        var pc2 = C.pick(rnd, fs);
        var hospitalisee = rnd() > 0.7;
        cur.all().push({
          id: 'SCM' + C.pad(u2 + 1, 4), statut: 'actif', reference: 'SCM-' + C.pad(u2 + 1, 4),
          date: C.iso(jourOuvre(rnd)),
          patientId: pc2.id, patient: pc2.nom + ' ' + pc2.prenom, patientCode: pc2.code,
          trancheAge: C.pick(rnd, d2.TRANCHES_AGE_CURATIF.slice(5)),
          symptomes: C.pick(rnd, ['Fièvre et céphalées', 'Douleurs pelviennes', 'Toux depuis 5 jours', 'Métrorragies']),
          diagnostic: C.pick(rnd, ['Paludisme simple', 'Infection urinaire', 'Anémie', 'Menace d’accouchement prématuré']),
          traitement: C.pick(rnd, ['CTA 3 jours', 'Antibiothérapie', 'Fer + folates', 'Tocolyse et repos']),
          mildaDelivree: rnd() > 0.55,
          urgenceMaternite: rnd() > 0.75 ? C.pick(rnd, d2.URGENCES_MATERNITE).code : null,
          femmeObservee: rnd() > 0.55,
          femmeHospitalisee: hospitalisee,
          joursHospitalisation: hospitalisee ? C.between(rnd, 1, 9) : null,
          agent: C.pick(rnd, sf),
        });
      }
    }
    faits.soinsCuratifs = cur.active().length;

    /* --- Partogrammes — travail en cours ou récent ------------------------- */
    var par = col('partogrammes', { module: 'M4', entite: 'partogramme', prefix: 'PAR' });
    if (!par.all().length) {
      for (var w = 0; w < 6; w++) {
        var fw = C.pick(rnd, fs);
        var debut = C.addDays(FIN, -C.between(rnd, 0, 20));
        debut.setHours(C.between(rnd, 4, 20), 0, 0, 0);
        var mesures = [];
        var dil = 4;
        for (var h = 0; h <= C.between(rnd, 3, 8); h++) {
          dil = Math.min(10, dil + (rnd() > 0.35 ? 1 : 0));
          mesures.push({
            heure: h,
            dilatation: dil,
            descente: Math.max(0, 5 - Math.floor(h / 2)),
            bdf: 120 + C.between(rnd, 0, 40),
            contractions: Math.min(5, 2 + Math.floor(h / 2)),
            ta: C.between(rnd, 10, 14) + '/' + C.between(rnd, 6, 9),
            pouls: 70 + C.between(rnd, 0, 30),
            liquide: C.pick(rnd, ['I', 'C', 'C', 'C', 'M']),
          });
          if (dil >= 10) break;
        }
        par.all().push({
          id: 'PAR' + C.pad(w + 1, 4), statut: 'actif', reference: 'PARTO-' + C.pad(w + 1, 4),
          patientId: fw.id, patient: fw.nom + ' ' + fw.prenom, patientCode: fw.code,
          gestite: C.between(rnd, 1, 6), parite: C.between(rnd, 0, 5),
          debut: debut.toISOString(),
          accoucheur: C.pick(rnd, sf),
          mesures: mesures,
          clos: mesures[mesures.length - 1].dilatation >= 10,
          resume: mesures[mesures.length - 1].dilatation >= 10 ? 'Dilatation complète — expulsion' : null,
        });
      }
    }
    faits.partogrammes = par.active().length;

    /* --- Décès (repris de l'ancien amorçage d'écran) ----------------------- */
    if (!dec.all().length) {
      for (var k = 0; k < 14; k++) {
        var pd = unDe(rnd, patients());
        var dd = C.addDays(FIN, -C.between(rnd, 0, 260));
        dd.setHours(C.between(rnd, 0, 23), C.between(rnd, 0, 59));
        dec.all().push({
          id: 'DEC' + C.pad(k + 1, 4), statut: 'actif',
          reference: 'DEC-' + C.pad(k + 1, 4),
          patientId: pd.id, patient: pd.nom + ' ' + pd.prenom, patientCode: pd.code,
          dateHeure: dd.toISOString(),
          cause: C.pick(rnd, ['Paludisme grave', 'Insuffisance rénale aiguë', 'Accident vasculaire cérébral',
            'Détresse respiratoire', 'Choc septique', 'Cause naturelle — grand âge']),
          lieu: C.pick(rnd, ['Hospitalisation', 'Urgences', 'Bloc opératoire', 'Maternité']),
          medecin: C.pick(rnd, sf),
          declare: rnd() > 0.2,
        });
      }
    }
    faits.deces = dec.active().length;

    /* --- Suivi maternité (l'écran historique) — conservé ------------------- */
    if (!suivi.all().length) {
      for (var j = 0; j < 26; j++) {
        var f3 = C.pick(rnd, fs);
        var t3 = C.between(rnd, 6, 40);
        suivi.all().push({
          id: 'MAT' + C.pad(j + 1, 4), statut: 'actif',
          patientId: f3.id, patient: f3.nom + ' ' + f3.prenom, patientCode: f3.code,
          dpa: C.iso(C.addDays(FIN, (40 - t3) * 7)),
          termeSA: t3,
          poids: 50 + C.between(rnd, 0, 35),
          cpn: C.between(rnd, 1, 4),
          groupeSanguin: f3.groupeSanguin,
          risque: rnd() > 0.78 ? 'Élevé' : 'Standard',
          sageFemme: C.pick(rnd, sf),
          observations: C.pick(rnd, ['Grossesse évolutive normale', 'Anémie modérée', 'HTA gravidique à surveiller', 'Diabète gestationnel']),
        });
      }
    }
    faits.suivis = suivi.active().length;

    return faits;
  }

  /* ==========================================================================
   * 8. ADMINISTRATION — courriers, ambulance, GED
   * ======================================================================== */
  function administration(rnd) {
    var faits = {};

    /* --- Interventions d'ambulance ----------------------------------------
       LA FORME EST CELLE QUE L'ÉCRAN LIT (m13-ambulance) : dateHeure,
       kilometrage, tarif, facture — plus l'etat que le tableau de bord
       consomme. Deux seeds aux formes divergentes ont coexisté ici : celui-ci
       écrivait date/distance/montant pendant que l'écran lisait dateHeure/
       kilometrage/tarif — toutes ses colonnes affichaient des tirets. */
    var amb = col('ambulance', { module: 'M13', entite: 'InterventionAmbulance' });
    if (!amb.all().length) {
      var DEST = ['CHUD Borgou-Alibori — Parakou', 'Hôpital Saint Jean de Dieu — Boko',
        'Domicile — quartier Zongo', 'CNHU-HKM Cotonou', 'Centre de santé de N’Dali'];
      for (var i = 0; i < 38; i++) {
        var p = unDe(rnd, patients());
        if (!p) break;
        var dt = jourOuvre(rnd);
        dt.setHours(C.between(rnd, 0, 23), C.between(rnd, 0, 59), 0, 0);
        var recent = C.daysBetween(dt, FIN) < 2;
        var km = C.between(rnd, 3, 320);
        var etatAmb = recent ? C.pick(rnd, ['demandee', 'en_cours', 'terminee']) : 'terminee';
        amb.insert({
          reference: 'AM-2026-' + C.pad(i + 1, 4),
          dateHeure: dt.toISOString(),
          patientId: p.id, patient: p.nom + ' ' + p.prenom, patientCode: p.code,
          motif: C.pick(rnd, ['Transfert vers structure de référence', 'Ramassage à domicile',
            'Retour à domicile', 'Évacuation sanitaire', 'Transport post-opératoire']),
          destination: C.pick(rnd, DEST),
          kilometrage: km,
          chauffeur: 'TCHANE Nourou',
          accompagnant: C.pick(rnd, ['Infirmier de garde', 'Sage-femme', 'Aide-soignante', '—']),
          etat: etatAmb,
          tarif: 5000 + km * 500,
          facture: etatAmb === 'terminee' ? rnd() > 0.2 : false,
          statut: 'actif',
        });
      }
    }
    faits.ambulance = amb.active().length;

    /* --- Courriers ---------------------------------------------------------
       Même règle : la forme est celle de l'écran m13-courriers — traitement
       tri-état (en_attente / en_cours / traite), nature, service destinataire,
       numérisation. Le booléen « traite » d'autrefois n'était lu par personne
       et laissait la colonne Traitement muette. */
    var cour = col('courriers', { module: 'M13', entite: 'Courrier' });
    if (!cour.all().length) {
      var OBJETS = [
        ['arrivee', 'Convocation à la réunion de la zone sanitaire', 'Zone sanitaire de Parakou – N’Dali'],
        ['arrivee', 'Demande de statistiques mensuelles', 'DDS Borgou-Alibori'],
        ['arrivee', 'Relance de règlement de créances', 'NSIA ASSURANCE'],
        ['arrivee', 'Notification de contrôle fiscal', 'DGI — Centre des impôts'],
        ['depart', 'Transmission des statistiques du mois', 'Zone sanitaire de Parakou – N’Dali'],
        ['depart', 'Demande de convention de partenariat', 'AFRICAINE DES ASSURANCES'],
        ['depart', 'Relevé et facture mensuelle', 'SUNU ASSURANCES'],
        ['depart', 'Réponse à la demande de renseignements', 'DDS Borgou-Alibori'],
        ['arrivee', 'Offre commerciale — réactifs de laboratoire', 'SoBAPS SA'],
        ['depart', 'Bon de commande de médicaments', 'SoBAPS SA'],
      ];
      var NATURES_COURRIER = ['Lettre', 'Courriel', 'Note', 'Facture', 'Convocation'];
      var SERVICES_COURRIER = ['Direction Médicale', 'Direction Administrative', 'Comptabilité',
        'Ressources humaines', 'Gestion des stocks'];
      for (var c = 0; c < 34; c++) {
        var o = C.pick(rnd, OBJETS);
        var dtc = jourOuvre(rnd);
        cour.insert({
          reference: (o[0] === 'arrivee' ? 'ARR-' : 'DEP-') + '2026-' + C.pad(c + 1, 4),
          sens: o[0], objet: o[1], correspondant: o[2],
          date: C.iso(dtc),
          nature: C.pick(rnd, NATURES_COURRIER),
          affecteA: C.pick(rnd, SERVICES_COURRIER),
          traitement: C.daysBetween(dtc, FIN) > 6 ? 'traite' : C.pick(rnd, ['en_attente', 'en_cours', 'traite']),
          accuseReception: rnd() > 0.4,
          numerise: rnd() > 0.25,
          statut: 'actif',
        });
      }
    }
    faits.courriers = cour.active().length;

    /* --- Réunions -----------------------------------------------------------
       Amorcées ICI et non par l'écran m13-reunions : le tableau de bord de
       l'agent administratif et le tiroir des consultations les lisent aussi —
       une page ne charge que le module de son écran. */
    var reun = col('reunions', { module: 'M13', entite: 'Reunion' });
    if (!reun.all().length) {
      var rndR = C.seeded(2617);
      var TYPES_REUNION = ['Réunion de direction', 'Réunion de service', 'Comité d’hygiène',
        'Revue mensuelle d’activité', 'Réunion du personnel', 'Comité de gestion des stocks'];
      for (var r = 0; r < 18; r++) {
        var dr = C.addDays(FIN, C.between(rndR, -120, 30));
        reun.all().push({
          id: 'REU' + C.pad(r + 1, 4), statut: 'actif',
          reference: 'RU-2026-' + C.pad(r + 1, 3),
          date: C.iso(dr), heure: C.pad(C.between(rndR, 8, 16)) + ':00',
          type: C.pick(rndR, TYPES_REUNION),
          lieu: C.pick(rndR, ['Salle de réunion', 'Bureau de la Direction', 'Salle de garde']),
          president: C.pick(rndR, ['GBAGUIDI Rafiou', 'SOKOU Peace']),
          participants: C.between(rndR, 4, 22),
          ordreDuJour: C.pick(rndR, [
            'Point sur l’activité du mois ; situation des stocks ; questions diverses',
            'Suivi des créances assurances ; recouvrement ; plan d’action',
            'Hygiène et sécurité des patients ; protocole de désinfection',
            'Présentation du projet de digitalisation ; calendrier de déploiement',
          ]),
          compteRendu: dr < FIN,
        });
      }
    }
    faits.reunions = reun.active().length;

    /* --- Bibliothèque documentaire (GED) ------------------------------------
       Amorcée ICI et non par ged.js : le tableau de bord de l'agent
       administratif compte les documents à valider, et un compteur qui lit une
       collection vide affiche un zéro FAUX — pas un zéro vide. */
    var docs = col('documents', { module: 'GED', entite: 'Document' });
    if (!docs.all().length) {
      var rndG = C.seeded(3019);
      var patsG = patients();
      var empsG = personnel();
      for (var g = 0; g < 220; g++) {
        var cat = C.pick(rndG, D().GED_CATEGORIES);
        /* Chez BAGUIDI aucun patient n'est semé : les catégories rattachées
           à un patient sont sautées plutôt que de fabriquer un rattachement
           vide — la bibliothèque reste celle de l'ÉTABLISSEMENT. */
        if (cat.rattachement === 'Patient' && !patsG.length) continue;
        var rattache, codeR;
        if (cat.rattachement === 'Patient') {
          var pg = C.pick(rndG, patsG); rattache = pg.nom + ' ' + pg.prenom; codeR = pg.code;
        } else if (cat.rattachement === 'Employé') {
          var eg = C.pick(rndG, empsG); rattache = eg.nomComplet; codeR = 'MAT-' + eg.matricule;
        } else if (cat.rattachement === 'Fournisseur') {
          var fg = C.pick(rndG, D().FOURNISSEURS); rattache = fg.nom; codeR = fg.code;
        } else {
          rattache = 'Administration générale'; codeR = 'ADM';
        }
        docs.all().push({
          id: 'GED' + C.pad(g + 1, 5), statut: 'actif',
          reference: 'DOC-2026-' + C.pad(g + 1, 5),
          categorie: cat.id, rattachement: cat.rattachement,
          rattacheA: rattache, codeRattachement: codeR,
          libelle: cat.label.replace(/s$/, '') + ' — ' + rattache,
          date: C.iso(C.addDays(FIN, -C.between(rndG, 0, 500))),
          taille: C.between(rndG, 60, 4800),
          format: C.pick(rndG, ['PDF', 'PDF', 'PDF', 'JPEG', 'DOCX', 'XLSX']),
          version: C.between(rndG, 1, 3),
          etatValidation: C.pick(rndG, ['valide', 'valide', 'valide', 'en_attente', 'rejete']),
          signe: rndG() > 0.55,
          archive: rndG() > 0.7,
          deposePar: C.pick(rndG, empsG).nomComplet,
          consultations: C.between(rndG, 0, 45),
          conservation: cat.rattachement === 'Patient' ? 20 : (cat.rattachement === 'Employé' ? 10 : 5),
        });
      }
    }
    faits.documents = docs.active().length;

    /* Les événements de l'ÉTABLISSEMENT ne sont pas peuplés ici : l'écran de
       M13 les amorce lui-même, avec la forme qu'attend son formulaire
       (catégorie, heure, responsable, canaux). Les créer en double produisait
       des fiches incomplètes que la modification refusait d'enregistrer. */

    return faits;
  }

  /* ==========================================================================
   * 9. LES NOTIFICATIONS DE POSTE
   * --------------------------------------------------------------------------
   * Elles s'adressent à un POSTE et non à une personne : le prescripteur peut
   * être en congé, c'est le service qui doit voir passer l'information.
   * ======================================================================== */
  function notifications(rnd) {
    var pr = PR();
    var notif = S().collection('notifications');
    if (notif.active().length > 12) return notif.active().length;

    var demandes = S().collection('demandesAnalyses').active();
    var factures = S().collection('factures').active();
    var produits = S().collection('produits').active()
      .filter(function (p) { return p.seuilAlerte != null && p.stock <= p.seuilAlerte; });

    var MODELES = [
      { poste: 'consultation', type: 'resultat_rendu', priorite: 'normale',
        libelle: function (d) { return 'Résultat rendu — ' + d.patient; },
        detail: function (d) { return d.analyse + ' — validé biologiquement, consultable au dossier'; },
        /* On interroge le référentiel plutôt que de comparer une chaîne : un
           état ajouté demain sera pris en compte sans toucher à ce fichier. */
        source: demandes.filter(function (d) { return D().resultatRendu(d.etatAnalyse); }) },
      { poste: 'prelevement', type: 'prelevement_attendu', priorite: 'haute',
        libelle: function (d) { return 'Prélèvement à réaliser — ' + d.patient; },
        detail: function (d) { return d.analyse + ' — réglé, le patient peut être appelé'; },
        source: demandes.filter(function (d) { return d.etatAnalyse === 'attente_prelevement'; }) },
      { poste: 'caisse', type: 'encaissement', priorite: 'normale',
        libelle: function (f) { return 'Reliquat à encaisser — ' + f.patient; },
        detail: function (f) { return f.numero + ' — reste ' + C.money(f.reliquat); },
        source: factures.filter(function (f) { return f.reliquat > 0; }).slice(0, 14) },
      { poste: 'stock', type: 'reapprovisionnement', priorite: 'haute',
        libelle: function (p) { return 'Réapprovisionnement — ' + p.designation; },
        detail: function (p) { return 'Stock ' + p.stock + ' ' + p.unite + ' pour un seuil de ' + p.seuilAlerte; },
        source: produits.slice(0, 16) },
    ];

    var n = 0;
    MODELES.forEach(function (m) {
      m.source.slice(0, 14).forEach(function (x) {
        pr.notifier({
          type: m.type, poste: m.poste,
          libelle: m.libelle(x), detail: m.detail(x),
          priorite: m.priorite,
          patientId: x.patientId || null,
          reference: x.reference || x.numero || null,
        });
        n++;
        /* Les plus anciennes sont lues : une pile où tout est non lu ne
           distingue plus ce qui vient d'arriver. */
        if (rnd() > 0.55) {
          var derniere = S().collection('notifications').active()[0];
          if (derniere) S().collection('notifications').update(derniere.id, { lue: true });
        }
      });
    });
    return n;
  }

  /* ==========================================================================
   * 10. LA FACTURE MÈRE D'ASSURANCE
   * ======================================================================== */
  function facturesMere(rnd) {
    var d = D();
    var col2 = col('facturesMere', { module: 'M9', entite: 'facture mère', prefix: 'FM' });
    if (col2.all().length) return col2.active().length;
    var factures = S().collection('factures').active();
    var n = 0;

    (d.ASSUREURS || []).forEach(function (comp) {
      var siennes = factures.filter(function (f) {
        return (f.assureur === comp.code || f.assureur === comp.nom) && (f.partAssurance || 0) > 0;
      });
      if (siennes.length < 3) return;
      var parSous = {};
      siennes.forEach(function (f) {
        var s = f.souscripteur || 'Sans souscripteur désigné';
        if (!parSous[s]) parSous[s] = { souscripteur: s, nbFactures: 0, montant: 0, assureur: 0, patient: 0 };
        parSous[s].nbFactures++;
        parSous[s].montant += f.montantTTC || 0;
        parSous[s].assureur += f.partAssurance || 0;
        parSous[s].patient += f.partPatient || 0;
      });
      var sous = Object.keys(parSous).map(function (k) { return parSous[k]; });
      var total = sous.reduce(function (t, g) { return t + g.assureur; }, 0);
      var regle = rnd() > 0.45;
      n++;
      col2.insert({
        numero: 'FM-' + FIN.getFullYear() + '-' + C.pad(n, 4),
        compagnieCode: comp.code, compagnie: comp.nom,
        periode: 'trimestre', periodeLabel: 'Trimestrielle',
        debut: C.iso(C.addDays(FIN, -90)), fin: C.iso(FIN),
        dateEmission: C.iso(C.addDays(FIN, -C.between(rnd, 1, 30))),
        nbSouscripteurs: sous.length, nbFactures: siennes.length,
        montantReclame: total,
        souscripteurs: sous,
        piecesFilles: siennes.map(function (f) { return f.numero; }),
        controle: { totalFilles: total, totalFactures: total, totalLignes: total, concordant: true },
        etat: regle ? 'reglee' : 'transmise',
        dateReglement: regle ? C.iso(C.addDays(FIN, -C.between(rnd, 0, 15))) : null,
        montantRegle: regle ? total : null,
        referenceReglement: regle ? 'VIR-' + C.between(rnd, 100000, 999999) : null,
        reliquat: regle ? 0 : total,
        emisePar: 'SOKOU Peace',
      });
    });
    return n;
  }

  /* ==========================================================================
   * ORCHESTRATION
   * ======================================================================== */
  function peupler(force) {
    var db = S().raw();
    if (db._parcoursAmorces && !force) return null;

    var rnd = C.seeded(20260826);
    var bilan = {};

    /* Tout le peuplement se fait EN LOT : sans cela, chaque insertion
       sérialiserait le magasin entier et l'opération dépasserait la minute. */
    return S().enLot(function () {

      /* ==================================================================
       * PÉRIMÈTRE BAGUIDI (02/09/2026) : les seeders CLINIQUES ne sont plus
       * APPELÉS — parcours de soin, soins prescrits, pièces cliniques,
       * imagerie, accueil, certificats, maternité, factures mères. Aucun
       * patient n'est semé et les modules M1–M5/M8/M9/MECEF sont fermés.
       * Les fonctions restent dans le fichier : rouvrir un module clinique
       * ne demandera que de les rebrancher ici.
       * ================================================================== */
      try { bilan.rh = ressourcesHumaines(rnd); } catch (e) { console.error('[SEED] RH', e); }
      try { bilan.administration = administration(rnd); } catch (e) { console.error('[SEED] administration', e); }
      try { bilan.notifications = notifications(rnd); } catch (e) { console.error('[SEED] notifications', e); }
      try { bilan.gestes = gestesDePoste(); } catch (e) { console.error('[SEED] gestes de poste', e); }

      db._parcoursAmorces = true;
      db._parcoursAmorcesLe = new Date().toISOString();
      return bilan;
    });
  }

  /* ==========================================================================
   * VAGUE 51 \u2014 LA JOURN\u00c9E DES POSTES : les gestes de validation sont FAITS
   * --------------------------------------------------------------------------
   * Le jeu de d\u00e9monstration figurait un \u00e9tablissement o\u00f9 personne n'avait
   * valid\u00e9 depuis des mois \u2014 220 brouillons, 25 validations biologiques en
   * souffrance. La Direction a demand\u00e9 de passer aux donn\u00e9es r\u00e9elles : les
   * postes ont fait leurs gestes, il reste le FLUX COURANT \u2014 les files
   * r\u00e9siduelles montrent l'usage des \u00e9crans sans figurer l'abandon.
   * Chaque geste porte son auteur et sa date, comme s'il avait \u00e9t\u00e9 fait \u00e0
   * l'\u00e9cran \u2014 parce que c'est ce qu'il figure.
   * ======================================================================== */
  function gestesDePoste() {
    var fait = { ecritures: 0, bios: 0, cr: 0, besoins: 0, commandes: 0, mecef: 0, echeances: 0 };
    var st = S();

    /* Le comptable valide \u2014 les 15 plus r\u00e9centes restent en brouillon :
       c'est le flux du jour, pas un arri\u00e9r\u00e9. */
    var brouillons = st.collection('ecritures').active()
      .filter(function (e) { return e.statut === 'brouillon'; })
      .sort(function (a, b) { return String(a.date).localeCompare(String(b.date)); });
    brouillons.slice(0, Math.max(0, brouillons.length - 15)).forEach(function (e) {
      st.collection('ecritures').update(e.id, {
        statut: 'validee', valideLe: '2026-09-01', validePar: 'SANOUSSI Adamon',
      });
      fait.ecritures++;
    });

    /* Le biologiste rend \u2014 cinq r\u00e9sultats restent en relecture. */
    var bios = st.collection('demandesAnalyses').active()
      .filter(function (d) { return d.etatAnalyse === 'valide_technique'; })
      .sort(function (a, b) { return String(a.dateHeure).localeCompare(String(b.dateHeure)); });
    bios.slice(0, Math.max(0, bios.length - 5)).forEach(function (d) {
      st.collection('demandesAnalyses').update(d.id, {
        etatAnalyse: 'valide',
        valideLe: '2026-09-01T10:00:00.000Z',
        valideBiologiquePar: 'Biologiste m\u00e9dical',
      });
      fait.bios++;
    });

    /* L'\u00e9chographiste rend ses comptes rendus \u2014 quatre restent en
       r\u00e9daction. La demande li\u00e9e suit son CR. */
    var crs = st.collection('resultatsImagerie').active()
      .filter(function (r) { return r.statut !== 'rendu' && r.conclusion; })
      .sort(function (a, b) { return String(a.date).localeCompare(String(b.date)); });
    crs.slice(0, Math.max(0, crs.length - 4)).forEach(function (r) {
      st.collection('resultatsImagerie').update(r.id, {
        statut: 'rendu', renduLe: '2026-09-01T11:00:00.000Z',
      });
      if (r.demandeImagerieId) {
        var di = st.collection('demandesImagerie').get(r.demandeImagerieId);
        if (di) st.collection('demandesImagerie').update(di.id, { statut: 'validee', valideLe: '2026-09-01' });
      }
      fait.cr++;
    });

    /* La DA valide bons et commandes \u2014 cinq bons et trois commandes
       restent au circuit. */
    var besoins = st.collection('besoins').active()
      .filter(function (b) { return ['soumis', 'controle_stock', 'validation_da'].indexOf(b.etape) !== -1; })
      .sort(function (a, b) { return String(a.date).localeCompare(String(b.date)); });
    besoins.slice(0, Math.max(0, besoins.length - 5)).forEach(function (b) {
      st.collection('besoins').update(b.id, {
        etape: 'accorde', valideePar: 'SOKOU Peace', valideeLe: '2026-09-01',
        lignes: (b.lignes || []).map(function (l) {
          return Object.assign({}, l, {
            quantiteAccordee: l.quantiteAccordee != null ? l.quantiteAccordee
              : Math.round(l.quantiteDemandee * 0.8),
          });
        }),
      });
      fait.besoins++;
    });
    var cmds = st.collection('commandes').active()
      .filter(function (x) { return x.statutCommande === 'attente_validation'; })
      .sort(function (a, b) { return String(a.date).localeCompare(String(b.date)); });
    cmds.slice(0, Math.max(0, cmds.length - 3)).forEach(function (x) {
      st.collection('commandes').update(x.id, {
        statutCommande: 'validee', valideePar: 'SOKOU Peace', dateValidation: '2026-09-01',
      });
      fait.commandes++;
    });

    /* La normalisation MECeF \u2014 quatre pi\u00e8ces restent en attente. */
    var mecef = st.collection('factures').active()
      .filter(function (fa) { return fa.statutMecef === 'en_attente' && fa.numeroMecef; })
      .sort(function (a, b) { return String(a.date).localeCompare(String(b.date)); });
    mecef.slice(0, Math.max(0, mecef.length - 4)).forEach(function (fa) {
      st.collection('factures').update(fa.id, { statutMecef: 'valide' });
      fait.mecef++;
    });

    /* Les \u00e9ch\u00e9ances d\u00e9pass\u00e9es sont r\u00e9gl\u00e9es \u2014 SAUF UNE : l'alarme du
       tableau de bord doit avoir quelque chose \u00e0 montrer, et un z\u00e9ro
       permanent endormirait la vigilance. */
    var depassees = st.collection('echeancesFiscales').active()
      .filter(function (e) { return !e.paye && e.echeance < '2026-08-16'; })
      .sort(function (a, b) { return String(a.echeance).localeCompare(String(b.echeance)); });
    depassees.slice(0, Math.max(0, depassees.length - 1)).forEach(function (e) {
      st.collection('echeancesFiscales').update(e.id, {
        paye: true, payeLe: '2026-09-01', payePar: 'SANOUSSI Adamon',
        quittance: 'QUIT-2026-' + String(e.id).replace(/\D/g, '').slice(-4),
      });
      fait.echeances++;
    });

    return fait;
  }

  global.SIGH.peuplerParcours = peupler;
  global.SIGH.PERIODE_SEED = { debut: C.iso(DEBUT), fin: C.iso(FIN), jours: JOURS };
})(window);
