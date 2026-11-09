/// LES QUATORZE SPÉCIALITÉS DE LA CLINIQUE BAGUIDI « L'AS DU CŒUR » (PRD P0-12) — la donnée qui sème la collection `specialites`.
///
/// UNE SEULE MÉCANIQUE PILOTÉE PAR DES DONNÉES : une spécialité est une FICHE, pas un module. Ajouter une quinzième spécialité, c'est ajouter une fiche
/// (code, libellé, modèle de consultation) depuis l'écran « Spécialités » : le ruban, le hub, le formulaire de consultation, l'agenda, la file et les
/// statistiques en NAISSENT, sans une ligne de code.
///
/// Le MODÈLE de consultation est lui aussi une donnée : des sections de questions (texte, texte long, nombre, choix, oui/non, date), les appareils de
/// l'examen clinique repris du dossier de consultation générique (IPPOA : inspection, palpation, percussion, auscultation) et, au besoin, les
/// antécédents. Le formulaire de saisie naît du modèle, comme le questionnaire d'enquête.
///
/// Gynécologie, chirurgie et imagerie ont DÉJÀ leurs écrans (maternité M4, bloc M3, imagerie M2) : leur fiche y RENVOIE (`renvoi`), rien n'est dupliqué.
/// La médecine du travail est la seule spécialité qui ajoute des écrans propres (visites, entreprises clientes, conventions).
///
/// Le contenu est arrêté par la Direction de la clinique (consigne du 09/11/2026) : aucune fiche n'est marquée « à valider ». Aucune donnée d'identité
/// réelle ne figure ici : les praticiens rattachés se désignent depuis l'écran, par leur fiche du personnel.
library;

typedef FicheSpec = Map<String, Object?>;

/// La provenance écrite sur chaque fiche semée.
const specSource = 'Spécialité de la Clinique Baguidi — modèle de consultation arrêté par la Direction (09/11/2026)';

/// Un champ de modèle. `type` : `texte` · `longtexte` · `nombre` · `choix` · `oui_non` · `date`.
Map<String, Object?> _q(String code, String libelle, String type,
        {List<String> options = const [], String? unite, bool requis = false, bool plein = false, num? min, num? max, String? aide}) =>
    {
      'code': code,
      'libelle': libelle,
      'type': type,
      if (options.isNotEmpty) 'options': options,
      if (unite != null) 'unite': unite,
      if (requis) 'requis': true,
      if (plein) 'plein': true,
      if (min != null) 'min': min,
      if (max != null) 'max': max,
      if (aide != null) 'aide': aide,
    };

Map<String, Object?> _s(String titre, List<Map<String, Object?>> champs) => {'titre': titre, 'champs': champs};

Map<String, Object?> _modele(List<Map<String, Object?>> sections, {List<String> appareils = const [], bool antecedents = true}) =>
    {'version': 1, 'sections': sections, 'appareils': appareils, 'antecedents': antecedents};

Map<String, Object?> _spec(
  int ordre,
  String code,
  String libelle,
  String icone,
  String description,
  Map<String, Object?> modele, {
  List<String> actes = const [],
  String? acteConsultation = 'CH01',
  List<Map<String, String>> renvoi = const [],
}) =>
    {
      'id': 'SPE${ordre.toString().padLeft(2, '0')}',
      'code': code,
      'libelle': libelle,
      'icone': icone,
      'ordre': ordre,
      'description': description,
      'statut': 'actif',
      'praticiens': <String>[],
      'actes': actes,
      if (acteConsultation != null) 'acteConsultation': acteConsultation,
      if (renvoi.isNotEmpty) 'renvoi': renvoi,
      'modele': modele,
      'source': specSource,
    };

const _oui = ['Oui', 'Non'];

/// Les quatorze fiches de base, dans l'ordre d'affichage de la clinique. Fonction (et non constante) : chaque appel rend des fiches NEUVES, que l'appelant
/// peut modifier sans toucher à la référence.
List<FicheSpec> specFichesDeBase() => [
      _spec(
          1,
          'medecine-travail',
          'Médecine du travail',
          'hard-hat',
          'Cœur de métier de la clinique : visites d’embauche, périodiques et de reprise, fiche d’aptitude, entreprises clientes et leurs salariés, conventions de visites.',
          _modele([
            _s('Poste de travail', [
              _q('entreprise', 'Entreprise', 'texte'),
              _q('poste', 'Poste occupé', 'texte', requis: true),
              _q('anciennete', 'Ancienneté au poste', 'nombre', unite: 'ans', min: 0, max: 60),
              _q('risques', 'Risque principal du poste', 'choix',
                  options: ['Bruit', 'Poussières', 'Produits chimiques', 'Manutention', 'Travail sur écran', 'Conduite', 'Aucun risque particulier']),
              _q('port_epi', 'Équipements de protection portés', 'oui_non', options: _oui),
            ]),
            _s('Appréciation', [
              _q('aptitude', 'Avis sur l’aptitude', 'choix',
                  options: ['Apte', 'Apte avec aménagement de poste', 'Inapte temporaire', 'Inapte définitif'], requis: true),
              _q('restrictions', 'Restrictions ou aménagements', 'longtexte', plein: true),
            ]),
          ], appareils: ['cardio_vasculaire', 'pleuro_pulmonaire', 'locomoteur', 'orl']),
          actes: ['MT01', 'MT02', 'MT03', 'MT04', 'MT05'],
          acteConsultation: null,
          renvoi: [
            {'ecran': 'm2-mdt-visites', 'libelle': 'Visites de médecine du travail'},
            {'ecran': 'm2-mdt-entreprises', 'libelle': 'Entreprises clientes et salariés'},
            {'ecran': 'm2-mdt-conventions', 'libelle': 'Conventions de visites'},
          ]),
      _spec(
          2,
          'sante-publique',
          'Santé publique',
          'shield-plus',
          'Prévention et santé communautaire : vaccination, dépistage, éducation sanitaire, hygiène et nutrition.',
          _modele([
            _s('Action de santé publique', [
              _q('theme', 'Thème', 'choix',
                  options: ['Vaccination', 'Dépistage', 'Éducation sanitaire', 'Hygiène et assainissement', 'Nutrition', 'Santé de la mère et de l’enfant', 'Autre'],
                  requis: true),
              _q('population', 'Population concernée', 'texte'),
              _q('depistage', 'Dépistage réalisé', 'oui_non', options: _oui),
              _q('vaccin', 'Vaccin administré', 'texte'),
              _q('conseils', 'Conseils donnés', 'longtexte', plein: true),
            ]),
          ], antecedents: false),
          acteConsultation: null),
      _spec(
          3,
          'gynecologie',
          'Gynécologie',
          'baby',
          'Santé de la femme : consultation gynécologique, contraception, suivi. La grossesse, l’accouchement et le planning familial se tiennent au module Maternité.',
          _modele([
            _s('Histoire gynécologique', [
              _q('ddr', 'Date des dernières règles', 'date'),
              _q('cycle', 'Cycles', 'choix', options: ['Réguliers', 'Irréguliers', 'Aménorrhée', 'Ménopause']),
              _q('contraception', 'Contraception', 'choix', options: ['Aucune', 'Pilule', 'Injectable', 'Implant', 'DIU', 'Préservatif', 'Autre']),
              _q('gestite', 'Gestité', 'nombre', min: 0, max: 30),
              _q('parite', 'Parité', 'nombre', min: 0, max: 30),
              _q('grossesse', 'Grossesse en cours', 'oui_non', options: _oui),
              _q('frottis', 'Frottis à jour', 'oui_non', options: _oui),
            ]),
          ], appareils: ['gyneco_obstetrique', 'genito_urinaire']),
          actes: ['GY-SAA', 'CH06', 'IM01', 'IM02'],
          renvoi: [
            {'ecran': 'm4-dossier-obstetrical', 'libelle': 'Dossier obstétrical'},
            {'ecran': 'm4-maternite', 'libelle': 'Suivi de maternité'},
            {'ecran': 'm4-planification', 'libelle': 'Planification familiale'},
            {'ecran': 'dash-maternite', 'libelle': 'Tableau de bord de la maternité'},
          ]),
      _spec(
          4,
          'chirurgie',
          'Chirurgie',
          'scissors',
          'Consultation chirurgicale et suite opératoire. Le bloc, les comptes rendus opératoires et d’anesthésie se tiennent au module Hospitalisation.',
          _modele([
            _s('Consultation chirurgicale', [
              _q('lesion', 'Lésion ou motif chirurgical', 'texte', requis: true, plein: true),
              _q('evolution', 'Évolution', 'texte'),
              _q('indication', 'Indication opératoire', 'choix', options: ['Oui', 'Non', 'À rediscuter']),
              _q('bilan_preop', 'Bilan préopératoire demandé', 'oui_non', options: _oui),
              _q('pansement', 'Pansement ou soin local', 'texte'),
            ]),
          ], appareils: ['hepato_gastro_digestif', 'locomoteur', 'peau_phaneres']),
          actes: ['CH01', 'CH03', 'CH04', 'CH05', 'CH07', 'CH08', 'CH09', 'CH10', 'CH11', 'CH12'],
          renvoi: [
            {'ecran': 'm3-cpa', 'libelle': 'Consultation pré-anesthésique'},
            {'ecran': 'm3-bloc-cro', 'libelle': 'Compte rendu opératoire'},
            {'ecran': 'm3-cr-anesthesie', 'libelle': 'Compte rendu d’anesthésie'},
            {'ecran': 'dash-chirurgien', 'libelle': 'Tableau de bord du chirurgien'},
          ]),
      _spec(
          5,
          'urologie',
          'Urologie',
          'droplets',
          'Voies urinaires et appareil génital de l’homme : troubles mictionnels, lithiase, prostate.',
          _modele([
            _s('Motif urologique', [
              _q('troubles', 'Troubles mictionnels', 'choix', options: ['Aucun', 'Dysurie', 'Pollakiurie', 'Hématurie', 'Rétention', 'Incontinence']),
              _q('lombalgie', 'Douleur lombaire', 'oui_non', options: _oui),
              _q('jet', 'Jet urinaire', 'choix', options: ['Normal', 'Faible', 'Interrompu', 'Goutte à goutte']),
              _q('psa', 'PSA', 'nombre', unite: 'ng/ml', min: 0, max: 1000),
            ]),
          ], appareils: ['genito_urinaire', 'hepato_gastro_digestif']),
          actes: ['IM05', 'CH07']),
      _spec(
          6,
          'rhumatologie',
          'Rhumatologie',
          'bone',
          'Articulations, os et rachis : douleurs inflammatoires ou mécaniques, infiltrations.',
          _modele([
            _s('Douleur et fonction', [
              _q('articulations', 'Articulations atteintes', 'texte', plein: true),
              _q('eva', 'Douleur (échelle de 0 à 10)', 'nombre', min: 0, max: 10, requis: true),
              _q('raideur', 'Raideur matinale', 'nombre', unite: 'min', min: 0, max: 1440),
              _q('type_douleur', 'Type de douleur', 'choix', options: ['Mécanique', 'Inflammatoire', 'Mixte']),
              _q('gene', 'Gêne fonctionnelle', 'longtexte', plein: true),
            ]),
          ], appareils: ['locomoteur']),
          actes: ['CH11', 'CH12']),
      _spec(
          7,
          'ophtalmologie',
          'Ophtalmologie',
          'eye',
          'Vision et segment antérieur : acuité visuelle, tension oculaire, fond d’œil.',
          _modele([
            _s('Examen de la vision', [
              _q('motif', 'Motif', 'choix', options: ['Baisse d’acuité visuelle', 'Rougeur', 'Douleur oculaire', 'Larmoiement', 'Contrôle']),
              _q('av_od', 'Acuité visuelle œil droit', 'texte'),
              _q('av_og', 'Acuité visuelle œil gauche', 'texte'),
              _q('tension_od', 'Tension oculaire œil droit', 'nombre', unite: 'mmHg', min: 0, max: 80),
              _q('tension_og', 'Tension oculaire œil gauche', 'nombre', unite: 'mmHg', min: 0, max: 80),
              _q('correction', 'Correction optique portée', 'oui_non', options: _oui),
              _q('fond_oeil', 'Fond d’œil', 'longtexte', plein: true),
            ]),
          ]),
          acteConsultation: 'CH01'),
      _spec(
          8,
          'orthophonie',
          'Orthophonie',
          'message-circle',
          'Langage, voix, parole et déglutition : bilan et séances de rééducation.',
          _modele([
            _s('Bilan et rééducation', [
              _q('motif', 'Motif', 'choix', options: ['Retard de langage', 'Bégaiement', 'Dyslexie', 'Aphasie', 'Trouble de la voix', 'Trouble de la déglutition']),
              _q('langue', 'Langue de rééducation', 'texte'),
              _q('bilan', 'Bilan', 'longtexte', plein: true),
              _q('objectif', 'Objectif de rééducation', 'texte', plein: true),
              _q('seance', 'Séance numéro', 'nombre', min: 0, max: 200),
              _q('seances_prevues', 'Séances prévues', 'nombre', min: 0, max: 200),
            ]),
          ], appareils: ['orl', 'neurologie']),
          acteConsultation: 'CH01'),
      _spec(
          9,
          'endocrinologie',
          'Endocrinologie',
          'activity',
          'Diabète, thyroïde et métabolisme : glycémie, poids, traitement.',
          _modele([
            _s('Suivi métabolique', [
              _q('type_diabete', 'Pathologie suivie', 'choix', options: ['Diabète de type 1', 'Diabète de type 2', 'Dysthyroïdie', 'Obésité', 'Autre']),
              _q('glycemie', 'Glycémie à jeun', 'nombre', unite: 'g/l', min: 0, max: 20),
              _q('hba1c', 'Hémoglobine glyquée', 'nombre', unite: '%', min: 0, max: 20),
              _q('poids', 'Poids', 'nombre', unite: 'kg', min: 0, max: 400),
              _q('taille', 'Taille', 'nombre', unite: 'cm', min: 0, max: 260),
              _q('tsh', 'TSH', 'nombre', unite: 'mUI/l', min: 0, max: 500),
              _q('traitement', 'Traitement en cours', 'longtexte', plein: true),
            ]),
          ], appareils: ['cardio_vasculaire', 'hepato_gastro_digestif']),
          acteConsultation: 'CH01'),
      _spec(
          10,
          'pediatrie',
          'Pédiatrie',
          'baby',
          'Santé de l’enfant : croissance, vaccination, pathologies courantes. Le dossier du nouveau-né se tient au module Maternité.',
          _modele([
            _s('Croissance', [
              _q('poids', 'Poids', 'nombre', unite: 'kg', min: 0, max: 150, requis: true),
              _q('taille', 'Taille', 'nombre', unite: 'cm', min: 0, max: 220),
              _q('pc', 'Périmètre crânien', 'nombre', unite: 'cm', min: 0, max: 70),
              _q('temperature', 'Température', 'nombre', unite: '°C', min: 30, max: 45),
            ]),
            _s('Nutrition et vaccination', [
              _q('alimentation', 'Alimentation', 'choix', options: ['Allaitement exclusif', 'Allaitement et diversification', 'Alimentation diversifiée', 'Lait artificiel']),
              _q('vaccins', 'Statut vaccinal', 'choix', options: ['À jour', 'Incomplet', 'Inconnu']),
              _q('developpement', 'Développement psychomoteur', 'texte', plein: true),
            ]),
          ], appareils: ['pleuro_pulmonaire', 'orl', 'hepato_gastro_digestif', 'peau_phaneres']),
          acteConsultation: 'CH01'),
      _spec(
          11,
          'neurologie',
          'Neurologie',
          'brain',
          'Système nerveux : céphalées, crises convulsives, déficits, conscience.',
          _modele([
            _s('Histoire neurologique', [
              _q('cephalees', 'Céphalées', 'oui_non', options: _oui),
              _q('crises', 'Crises convulsives', 'oui_non', options: _oui),
              _q('deficit', 'Déficit moteur ou sensitif', 'texte', plein: true),
              _q('glasgow', 'Score de Glasgow', 'nombre', min: 3, max: 15),
              _q('eeg', 'Électroencéphalogramme demandé', 'oui_non', options: _oui),
            ]),
          ], appareils: ['neurologie']),
          acteConsultation: 'CH01'),
      _spec(
          12,
          'cardiologie',
          'Cardiologie',
          'heart-pulse',
          'Cœur et vaisseaux : tension, électrocardiogramme, mesure ambulatoire de la pression artérielle.',
          _modele([
            _s('Constantes et symptômes', [
              _q('tension', 'Tension artérielle', 'texte', aide: 'Format 14/9.'),
              _q('fc', 'Fréquence cardiaque', 'nombre', unite: 'bpm', min: 0, max: 300),
              _q('dyspnee', 'Dyspnée', 'choix', options: ['Aucune', 'À l’effort', 'Au repos']),
              _q('douleur_thoracique', 'Douleur thoracique', 'oui_non', options: _oui),
              _q('ecg', 'Électrocardiogramme réalisé', 'oui_non', options: _oui),
              _q('ecg_resultat', 'Résultat de l’électrocardiogramme', 'longtexte', plein: true),
            ]),
          ], appareils: ['cardio_vasculaire', 'pleuro_pulmonaire']),
          actes: ['MG03', 'MG04'],
          acteConsultation: 'CH01'),
      _spec(
          13,
          'kinesitherapie',
          'Kinésithérapie',
          'dumbbell',
          'Rééducation fonctionnelle : massage, mobilisation, renforcement, électrothérapie.',
          _modele([
            _s('Séance de rééducation', [
              _q('region', 'Région traitée', 'texte', requis: true),
              _q('technique', 'Technique', 'choix', options: ['Massage', 'Mobilisation', 'Renforcement musculaire', 'Électrothérapie', 'Rééducation à la marche']),
              _q('eva_avant', 'Douleur avant la séance (0 à 10)', 'nombre', min: 0, max: 10),
              _q('eva_apres', 'Douleur après la séance (0 à 10)', 'nombre', min: 0, max: 10),
              _q('seance', 'Séance numéro', 'nombre', min: 0, max: 200),
              _q('seances_prevues', 'Séances prévues', 'nombre', min: 0, max: 200),
            ]),
          ], appareils: ['locomoteur'], antecedents: false),
          acteConsultation: 'CH01'),
      _spec(
          14,
          'imagerie',
          'Imagerie',
          'scan-line',
          'Échographie, radiographie, mammographie, scanner et IRM. Les demandes, comptes rendus et clichés se tiennent au module Consultations.',
          _modele([
            _s('Orientation vers l’imagerie', [
              _q('examen', 'Examen d’imagerie envisagé', 'texte', requis: true, plein: true),
              _q('indication', 'Indication clinique', 'longtexte', plein: true),
              _q('prescripteur', 'Prescripteur', 'texte'),
            ]),
          ], antecedents: false),
          actes: ['IM01', 'IM02', 'IM03', 'IM04', 'IM05', 'IM06'],
          acteConsultation: null,
          renvoi: [
            {'ecran': 'm2-dashboard-imagerie', 'libelle': 'Poste d’imagerie médicale'},
            {'ecran': 'm2-imagerie-demandes', 'libelle': 'Demandes d’imagerie médicale'},
            {'ecran': 'm2-imagerie', 'libelle': 'Tableau Échographie'},
            {'ecran': 'm2-echographie-galerie', 'libelle': 'Galerie des clichés'},
          ]),
    ];
