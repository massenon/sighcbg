// LES NOMS DU JEU CLINIQUE : patronymes du Borgou et prénoms usuels, écrits ici et tirés au sort. Aucun des noms réels de la clinique (BAGUIDI, SOKOU,
// SANOUSSI, ZIME, MABOUDOU, TOUNGOUH, IDOHOU, AKONDE) n'y figure, ni aucun nom de l'ancien jeu : `node tools/baguidi/controle-identite.mjs` le vérifie
// sur le jeu livré. Une combinaison nom + prénom ne sort qu'une fois.

/// Patronymes courants du Borgou et du Nord-Bénin (bariba, peulh, dendi, yoruba, fon).
const List<String> patronymes = [
  'YAROU', 'BIO', 'SERO', 'GANDO', 'MAMA',
  'ISSIFOU', 'KPERA', 'HOUNGBO', 'ZOSSOU', 'OSSENI', 'BAKARY', 
  'TIDJANI', 'BOURAIMA', 'SEYDOU', 'GOMINA', 'DARI', 'FASSASSI',
  'LAWANI', 'MOUSSA', 'BOKO', 'TOGBE', 'HOUESSOU', 'AMOUSSOU', 'GBENOU', 
  'NASSIROU', 'SOULEY', 'ROUFAI', 'TOKO', 'NIKKI', 'KPANOU', 'MORA', 
  'WABI', 'GUERA', 'BIO-GUERA', 'KEREKOU', 'IBRAHIM', 'TOUKOUROU', 'ALLADAYE',
  'FOLLY', 'SODJI', 'AHOUANDJINOU', 'GLELE', 'MEDEGAN', 'ODJO', 'ADEOTI', 'AKANNI', 'OLADELE', 'LAOUROU', 'DIAGNE', 'KANHOUN',
  'TCHIBOZO', 'DEGBE', 'ZINSOU', 'ASSOGBA', 'LOKOSSOU', 'ATCHADE', 'AHOLOU', 'SINSIN', 'BODJRENOU', 'MITO',
];

/// Prénoms féminins usuels.
const List<String> prenomsFeminins = [
  'Awa', 'Fatimath', 'Mariam', 'Rakiatou', 'Zouératou', 'Safiatou', 'Nafissatou', 'Aminatou', 'Gisèle', 'Estelle', 'Prisca', 'Flora',
  'Chantal', 'Bernadette', 'Léa', 'Sylvie', 'Rachida', 'Latifatou', 'Barikissou', 'Mounira', 'Hadjara', 'Salamatou', 'Ramatou',
  'Adjara', 'Carine', 'Judith', 'Pélagie', 'Rosine', 'Odile', 'Nadine', 'Perpétue', 'Clarisse', 'Francine', 'Henriette', 'Sylvanie',
  'Mariette', 'Reine', 'Ernestine', 'Flavienne', 'Ginette', 'Habiba', 'Kadidja', 'Maïmouna', 'Soumaïla', 'Tatiana', 'Vanessa',
];

/// Prénoms masculins usuels.
const List<String> prenomsMasculins = [
  'Moussa', 'Rachidi', 'Abdoulaye', 'Karimou', 'Yacoubou', 'Ibrahim', 'Baba', 'Habibou', 'Pascal', 'Judicaël', 'Romuald',
  'Cyrille', 'Euloge', 'Fidèle', 'Arnaud', 'Issiaka', 'Boni', 'Thierry', 'Gildas', 'Mathieu', 'Hervé', 'Aristide',
  'Césaire', 'Dieudonné', 'Édouard', 'Félix', 'Gaston', 'Hilaire', 'Innocent', 'Jérôme', 'Landry', 'Martial', 'Nestor', 'Olivier',
  'Parfait', 'Raoul', 'Séraphin', 'Théophile', 'Urbain', 'Valentin', 'Wilfried', 'Yannick', 'Zacharie', 'Ousmane', 'Oumarou', 'Soumaïla',
  'Tidjani', 'Djibril',
];

/// Les huit quartiers de Parakou du jeu.
const List<String> quartiers = ['Zongo', 'Banikanni', 'Albarika', 'Ladjifarani', 'Guéma', 'Dépôt', 'Titirou', 'Kpébié'];

/// Professions des salariés des entreprises clientes.
const List<String> professions = [
  'Ouvrier', 'Agent de production', 'Chauffeur', 'Magasinier', 'Comptable', 'Secrétaire', 'Opérateur de machine', 'Maçon', 'Imprimeur',
  'Technicien', 'Agent de sécurité', 'Mécanicien', 'Manutentionnaire', 'Conducteur d’engins', 'Agent commercial',
];
