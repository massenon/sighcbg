// LES TABLEAUX CLINIQUES DU JEU : ce que la clinique voit à Parakou (paludisme, hypertension, infections respiratoires et urinaires, plaies, douleurs
// lombaires…), avec le motif de venue, l'histoire, l'examen par appareil, la pathologie codée (référentiel de morbidité du socle), les analyses et
// l'imagerie qu'un médecin prescrirait. Aucun patient réel : ce sont des tableaux types.

/// Un tableau clinique.
class Scenario {
  const Scenario(
    this.code,
    this.pathologie,
    this.diagnostic,
    this.motif,
    this.histoire, {
    this.resume = '',
    this.traitement = '',
    this.analyses = const [],
    this.appareils = const {},
    this.soins = const [],
    this.fievre = false,
    this.hta = false,
    this.sexe,
    this.ageMin = 0,
    this.ageMax = 120,
  });

  final String code;

  /// Code du référentiel de morbidité (`pathologies`).
  final String pathologie;
  final String diagnostic;
  final String motif;
  final String histoire;
  final String resume;
  final String traitement;

  /// Codes du catalogue des analyses (`L24`…), dans l'ordre où le médecin les coche.
  final List<String> analyses;

  /// L'examen par appareil : code d'appareil → [inspection, palpation, percussion, auscultation] (« RAS » là où rien n'est noté).
  final Map<String, List<String>> appareils;

  /// Codes d'actes de soins (catalogue tarifaire) prescrits à la salle de soins.
  final List<String> soins;
  final bool fievre;
  final bool hta;
  final String? sexe;
  final int ageMin;
  final int ageMax;
}

const Map<String, Scenario> scenarios = {
  'S1': Scenario('S1', 'PAL-S', 'Paludisme simple', 'Fièvre, frissons et céphalées depuis trois jours',
      'Fièvre vespérale avec frissons et courbatures depuis trois jours, céphalées frontales, anorexie. Pas de voyage récent, automédication par paracétamol.',
      resume: 'Syndrome fébrile palustre sans signe de gravité.',
      traitement: 'Antipaludéen oral, antipyrétique, hydratation.',
      analyses: ['L16', 'L24'],
      fievre: true,
      soins: ['PVV', 'PSP'],
      appareils: {
        'hepato_gastro_digestif': ['Abdomen plat', 'Sensibilité épigastrique légère, pas de splénomégalie', 'RAS', 'Bruits hydro-aériques normaux'],
        'pleuro_pulmonaire': ['RAS', 'RAS', 'RAS', 'Murmure vésiculaire bien perçu'],
      }),
  'S2': Scenario('S2', 'HTA', 'Hypertension artérielle essentielle', 'Céphalées occipitales et vertiges',
      'Céphalées occipitales matinales et vertiges depuis une semaine, sans douleur thoracique. Pas de traitement antihypertenseur régulier.',
      resume: 'HTA symptomatique, bilan de retentissement demandé.',
      traitement: 'Inhibiteur calcique, règles hygiéno-diététiques, contrôle à 15 jours.',
      analyses: ['L09', 'L14', 'L07'],
      hta: true,
      appareils: {
        'cardio_vasculaire': ['RAS', 'Pouls périphériques bien perçus', 'RAS', 'B2 claqué au foyer aortique, pas de souffle'],
        'neurologie': ['Conscient, orienté', 'Pas de raideur méningée', 'Réflexes ostéo-tendineux présents', 'RAS'],
      }),
  'S3': Scenario('S3', 'BRON', 'Bronchite aiguë', 'Toux grasse et fièvre modérée',
      'Toux productive depuis cinq jours, fièvre modérée, gêne thoracique à la toux, pas de dyspnée de repos.',
      resume: 'Bronchite aiguë, radiographie pour éliminer une pneumopathie.',
      traitement: 'Antibiotique, mucolytique, aérosol.',
      analyses: ['L24', 'L10'],
      fievre: true,
      soins: ['AERO'],
      appareils: {
        'pleuro_pulmonaire': ['Polypnée discrète', 'Vibrations vocales conservées', 'Sonorité normale', 'Râles bronchiques diffus, sibilants'],
      }),
  'S4': Scenario('S4', 'GEA', 'Gastro-entérite aiguë', 'Diarrhée et vomissements depuis 48 heures',
      'Diarrhée liquide, six à huit selles par jour, vomissements alimentaires, douleurs abdominales diffuses, soif intense.',
      resume: 'Gastro-entérite avec déshydratation légère.',
      traitement: 'Réhydratation, antispasmodique, soins intraveineux.',
      analyses: ['L16', 'L24'],
      soins: ['SIV', 'PSP'],
      appareils: {
        'hepato_gastro_digestif': ['Abdomen souple, plis cutanés persistants', 'Sensibilité diffuse sans défense', 'Tympanisme modéré', 'Bruits hydro-aériques augmentés'],
      }),
  'S5': Scenario('S5', 'UGD', 'Ulcère gastro-duodénal', 'Brûlures épigastriques postprandiales',
      'Brûlures épigastriques à distance des repas, calmées par l’alimentation, évolution de plusieurs semaines, pas de méléna.',
      resume: 'Syndrome ulcéreux typique, échographie abdominale demandée.',
      traitement: 'Inhibiteur de la pompe à protons, pansement gastrique.',
      analyses: ['L24', 'L19'],
      appareils: {
        'hepato_gastro_digestif': ['RAS', 'Sensibilité épigastrique sans défense', 'RAS', 'RAS'],
      }),
  'S6': Scenario('S6', 'IUB', 'Infection urinaire basse', 'Brûlures mictionnelles et pollakiurie',
      'Brûlures en urinant, envies fréquentes, urines troubles depuis quatre jours, pas de fièvre.',
      resume: 'Cystite aiguë non compliquée.',
      traitement: 'Antibiotique adapté à l’antibiogramme, hydratation.',
      analyses: ['L05', 'L12'],
      appareils: {
        'genito_urinaire': ['RAS', 'Fosses lombaires libres, sensibilité sus-pubienne', 'Pas de globe vésical', 'RAS'],
      }),
  'S7': Scenario('S7', 'DIA2', 'Diabète de type 2', 'Soif intense, polyurie et amaigrissement',
      'Polyurie, polydipsie et perte de poids de quatre kilos en deux mois. Antécédents familiaux de diabète.',
      resume: 'Diabète de type 2 déséquilibré à confirmer, bilan métabolique.',
      traitement: 'Règles diététiques, antidiabétique oral, éducation thérapeutique.',
      analyses: ['L14', 'L09', 'L44'],
      appareils: {
        'peau_phaneres': ['Pas de plaie du pied', 'Pas de mal perforant', 'RAS', 'RAS'],
      },
      ageMin: 30),
  'S8': Scenario('S8', 'LOMB', 'Lombalgie', 'Douleurs lombaires irradiant vers la fesse',
      'Douleur lombaire basse après un effort de port de charge, irradiation fessière gauche, soulagée par le repos.',
      resume: 'Lombalgie commune, imagerie du rachis demandée.',
      traitement: 'Antalgique, anti-inflammatoire, repos relatif.',
      analyses: ['L47'],
      soins: ['SIM'],
      appareils: {
        'locomoteur': ['Attitude antalgique', 'Contracture paravertébrale, douleur à la pression de L4-L5', 'Percussion des épineuses douloureuse', 'RAS'],
      },
      ageMin: 20),
  'S9': Scenario('S9', 'PLAI', 'Plaie et abcès', 'Plaie de la jambe après chute',
      'Plaie contuse de la jambe gauche survenue il y a deux heures, saignement contrôlé par compression, vaccination antitétanique non à jour.',
      resume: 'Plaie contuse nécessitant suture et pansements.',
      traitement: 'Suture, pansements, antibiothérapie, sérovaccination antitétanique.',
      soins: ['SUT', 'PAN'],
      appareils: {
        'peau_phaneres': ['Plaie contuse de 4 cm face antérieure de la jambe gauche', 'Pas de crépitation osseuse', 'RAS', 'RAS'],
        'locomoteur': ['Mobilité conservée', 'RAS', 'RAS', 'RAS'],
      }),
  'S10': Scenario('S10', 'ANEM', 'Anémie ferriprive', 'Pâleur, fatigue et essoufflement',
      'Asthénie progressive, pâleur, essoufflement à l’effort, règles abondantes ou alimentation pauvre en fer.',
      resume: 'Anémie clinique, numération demandée.',
      traitement: 'Fer par voie orale, conseils alimentaires, déparasitage.',
      analyses: ['L24', 'L18', 'L38'],
      appareils: {
        'cardio_vasculaire': ['Pâleur conjonctivale marquée', 'RAS', 'RAS', 'Souffle systolique fonctionnel'],
      }),
  'S11': Scenario('S11', 'PROS', 'Pathologie prostatique', 'Gêne mictionnelle et levers nocturnes',
      'Jet urinaire faible, levers nocturnes répétés depuis six mois, sensation de vidange incomplète.',
      resume: 'Syndrome obstructif bas, bilan prostatique.',
      traitement: 'Alpha-bloquant, contrôle après échographie.',
      analyses: ['L29', 'L09'],
      sexe: 'M',
      ageMin: 45,
      appareils: {
        'genito_urinaire': ['RAS', 'Fosses lombaires libres', 'Pas de globe vésical', 'RAS'],
      }),
  'S12': Scenario('S12', 'FIBR', 'Fibrome utérin', 'Douleurs pelviennes et règles abondantes',
      'Douleurs pelviennes sourdes, ménorragies depuis plusieurs cycles, pesanteur pelvienne.',
      resume: 'Suspicion de fibrome utérin, échographie pelvienne demandée.',
      traitement: 'Antalgique, hémostatique, fer, contrôle après imagerie.',
      analyses: ['L24'],
      sexe: 'F',
      ageMin: 25,
      ageMax: 55,
      appareils: {
        'gyneco_obstetrique': ['Seins sans particularité', 'Utérus augmenté de volume, indolore', 'Globe vésical absent', 'RAS'],
      }),
  'S13': Scenario('S13', 'ARTH', 'Arthrose', 'Gonalgies chroniques',
      'Douleurs des genoux à la marche et à la montée des escaliers, raideur matinale brève, évolution de plusieurs mois.',
      resume: 'Gonarthrose probable, imagerie articulaire demandée.',
      traitement: 'Antalgique, anti-inflammatoire local, kinésithérapie.',
      analyses: ['L47', 'L10'],
      ageMin: 40,
      appareils: {
        'locomoteur': ['Genu varum, pas d’épanchement', 'Douleur interligne fémoro-tibial interne', 'RAS', 'Crépitations à la mobilisation'],
      }),
  'S14': Scenario('S14', 'ANGI', 'Angine', 'Mal de gorge fébrile',
      'Odynophagie intense, fièvre à 38,5 degrés, absence de toux.',
      resume: 'Angine érythémato-pultacée.',
      traitement: 'Antibiotique, antalgique, gargarismes.',
      fievre: true,
      appareils: {
        'orl': ['Amygdales hypertrophiées avec enduit blanchâtre', 'Adénopathies cervicales sensibles', 'RAS', 'RAS'],
      }),
  'S15': Scenario('S15', 'CONS', 'Nodule du sein à explorer', 'Nodule du sein perçu à l’autopalpation',
      'Nodule du sein perçu depuis un mois, indolore, sans écoulement mamelonnaire. Antécédents familiaux non précisés.',
      resume: 'Nodule mammaire à caractériser.',
      traitement: 'Imagerie mammaire, contrôle avec les résultats.',
      sexe: 'F',
      ageMin: 35,
      appareils: {
        'gyneco_obstetrique': ['Nodule du quadrant supéro-externe gauche', 'Nodule ferme de 2 cm, mobile, indolore', 'RAS', 'RAS'],
      }),
  'S16': Scenario('S16', 'AVP', 'Traumatisme crânien léger', 'Céphalées persistantes après une chute',
      'Chute de moto il y a cinq jours avec perte de connaissance brève, céphalées persistantes, nausées matinales.',
      resume: 'Traumatisme crânien léger, imagerie cérébrale demandée.',
      traitement: 'Antalgique, surveillance, repos.',
      appareils: {
        'neurologie': ['Conscient, Glasgow 15', 'Pas de raideur méningée', 'Réflexes ostéo-tendineux normaux', 'RAS'],
      }),
  'S17': Scenario('S17', 'CONS', 'Douleur abdominale à explorer', 'Douleurs abdominales persistantes',
      'Douleurs abdominales diffuses depuis trois semaines avec ballonnements, amaigrissement discret.',
      resume: 'Douleur abdominale chronique, imagerie demandée.',
      traitement: 'Antispasmodique, contrôle avec l’imagerie.',
      analyses: ['L24', 'L41'],
      appareils: {
        'hepato_gastro_digestif': ['Abdomen distendu', 'Sensibilité diffuse sans défense', 'Tympanisme', 'Bruits hydro-aériques présents'],
      }),
  'S18': Scenario('S18', 'PNEU', 'Pneumopathie', 'Toux chronique et douleurs thoraciques',
      'Toux sèche persistante depuis un mois, douleur thoracique à l’inspiration, sueurs nocturnes.',
      resume: 'Toux chronique, scanner thoracique demandé.',
      traitement: 'Antibiothérapie d’épreuve, contrôle avec imagerie.',
      analyses: ['L24', 'L47'],
      fievre: true,
      appareils: {
        'pleuro_pulmonaire': ['RAS', 'Vibrations vocales augmentées à droite', 'Matité de la base droite', 'Crépitants de la base droite'],
      }),
  'S19': Scenario('S19', 'LOMB', 'Lombalgie rebelle', 'Lombalgie rebelle avec sciatique',
      'Lombosciatique persistante malgré trois semaines de traitement, paresthésies du pied.',
      resume: 'Lombosciatique rebelle, IRM du rachis demandée.',
      traitement: 'Antalgiques de palier II, repos, contrôle.',
      analyses: ['L47'],
      ageMin: 25,
      appareils: {
        'locomoteur': ['Attitude antalgique', 'Signe de Lasègue positif à 40 degrés', 'RAS', 'RAS'],
        'neurologie': ['RAS', 'Hypoesthésie du bord externe du pied', 'Réflexe achilléen diminué', 'RAS'],
      }),
  'S20': Scenario('S20', 'FRAC', 'Traumatisme du poignet', 'Douleur du poignet après chute',
      'Chute sur la main droite, douleur et gonflement du poignet, impotence fonctionnelle partielle.',
      resume: 'Traumatisme du poignet, radiographie demandée.',
      traitement: 'Immobilisation, antalgique, contrôle radiologique.',
      appareils: {
        'locomoteur': ['Tuméfaction du poignet droit', 'Douleur à la pression de la tabatière anatomique', 'RAS', 'RAS'],
      }),
  'S22': Scenario('S22', 'HTA', 'Hypertension artérielle suivie en cardiologie', 'Contrôle tensionnel et bilan cardiaque',
      'Hypertendu connu, traité depuis deux ans, essoufflement à l’effort depuis un mois.',
      resume: 'HTA avec dyspnée d’effort, électrocardiogramme demandé.',
      traitement: 'Adaptation du traitement antihypertenseur, régime pauvre en sel.',
      analyses: ['L09', 'L07'],
      hta: true,
      ageMin: 35,
      appareils: {
        'cardio_vasculaire': ['RAS', 'Choc de pointe dévié', 'Limites cardiaques élargies', 'Bruits du cœur réguliers, souffle systolique 2/6'],
      }),
  'S23': Scenario('S23', 'PAL-S', 'Fièvre de l’enfant, paludisme simple', 'Fièvre chez l’enfant depuis deux jours',
      'Fièvre depuis deux jours, refus de s’alimenter, pleurs, pas de convulsion.',
      resume: 'Fièvre palustre de l’enfant sans signe de gravité.',
      traitement: 'Antipaludéen pédiatrique, antipyrétique, surveillance.',
      analyses: ['L16', 'L24'],
      fievre: true,
      ageMax: 14,
      appareils: {
        'pleuro_pulmonaire': ['RAS', 'RAS', 'RAS', 'Murmure vésiculaire bien perçu'],
        'orl': ['Tympans normaux, pharynx rouge', 'RAS', 'RAS', 'RAS'],
      }),
  'S24': Scenario('S24', 'CONS', 'Baisse de l’acuité visuelle', 'Baisse de la vision de près',
      'Gêne en lecture de près depuis plusieurs mois, céphalées en fin de journée.',
      resume: 'Presbytie probable.',
      traitement: 'Correction optique, contrôle annuel.',
      ageMin: 38,
      appareils: {
        'neurologie': ['Pupilles égales et réactives, motricité oculaire normale', 'RAS', 'RAS', 'RAS'],
      }),
  'S25': Scenario('S25', 'CONS', 'Rééducation fonctionnelle', 'Séances de rééducation après traumatisme',
      'Rééducation du genou après une entorse, douleur résiduelle à la flexion.',
      resume: 'Rééducation fonctionnelle en cours.',
      traitement: 'Séances de kinésithérapie, renforcement musculaire.',
      appareils: {
        'locomoteur': ['Genou sans épanchement', 'Douleur résiduelle à la flexion', 'RAS', 'RAS'],
      }),
  'S26': Scenario('S26', 'CONS', 'Céphalées chroniques', 'Céphalées chroniques et photophobie',
      'Céphalées pulsatiles unilatérales récurrentes avec photophobie, plusieurs crises par mois.',
      resume: 'Céphalées de type migraineux.',
      traitement: 'Traitement de crise, traitement de fond à discuter.',
      appareils: {
        'neurologie': ['Conscient, orienté', 'Pas de raideur méningée', 'RAS', 'RAS'],
      }),
};
