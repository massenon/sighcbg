// Lots A1 et A2 du laboratoire : antériorités rendues, variation, bornes d'époque, seuils de variation brutale (états, versions, droit, alerte non bloquante).
// Fonctions pures : les collections sont construites ici, sans magasin.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef F = Map<String, Object?>;

final auj = DateTime(2026, 11, 13, 12);

final examens = <F>[
  {'code': 'NFS', 'designation': 'NFS complète (hémogramme)'},
];

F variable(String code, String type, {num? min, num? max, bool accomp = false, String unite = 'g_l'}) => {
      'id': 'VAR-NFS-$code',
      'examen': 'NFS',
      'examenLibelle': 'NFS complète (hémogramme)',
      'code': code,
      'libelle': 'Libellé $code',
      'type': type,
      'unite': unite,
      if (min != null) 'min': min,
      if (max != null) 'max': max,
      'ordre': 1,
      'actif': true,
      'accompagnement': accomp,
      'statut': 'actif',
    };

final variables = <F>[
  variable('GB', 'numerique', min: 4, max: 8),
  variable('HB', 'numerique', min: 11, max: 14),
  variable('PLQ', 'numerique'),
  variable('CRPQ', 'binaire'),
  variable('LOT', 'lot', accomp: true),
  variable('COM', 'texte'),
];
final unites = <F>[
  {'id': 'g_l', 'symbole': 'G/l'}
];

F demande(String id, String date, {String etat = 'valide', Map<String, Object?>? valeurs, String patient = 'P1', String secteur = 'MÉDECINE GÉNÉRALE', String? valideLe}) => {
      'id': id,
      'reference': 'LAB-$id',
      'codeAnalyse': '$id-2026',
      'patientId': patient,
      'patient': 'TEST $patient',
      'analyse': 'NFS complète',
      'examenCode': 'NFS',
      'dateHeure': '${date}T09:00:00.000Z',
      'etatAnalyse': etat,
      'secteurDemandeur': secteur,
      if (etat == 'valide' || etat == 'rectifie') 'valideLe': valideLe ?? '${date}T15:00:00.000Z',
      'valeurs': valeurs ?? {'GB': 5, 'HB': 12},
    };

JeuLabo jeu(List<F> demandes, {List<F> plages = const [], List<F> seuils = const [], SessionLabo? session, int nombre = 3}) => JeuLabo(
    demandes: demandes, examens: examens, variables: variables, plages: plages, unites: unites, seuils: seuils, session: session ?? biologiste, aujourdhui: auj, nombre: nombre);

const biologiste = SessionLabo(role: 'laborantin', fonction: 'biologiste');

void main() {
  group('réglage du nombre d’antériorités', () {
    test('défaut 3 ; réglé ; hors bornes ou illisible : 3', () {
      expect(nbAnterioritesReglees(const []), 3);
      expect(nbAnterioritesReglees([{'id': 'nbAnterioritesLabo', 'valeur': 2}]), 2);
      expect(nbAnterioritesReglees([{'id': 'nbAnterioritesLabo', 'valeur': '5'}]), 5);
      for (final mauvais in [0, -1, 13, 'abc', null, 2.5 * 100]) {
        expect(nbAnterioritesReglees([{'id': 'nbAnterioritesLabo', 'valeur': mauvais}]), 3, reason: '$mauvais');
      }
      expect(nbAnterioritesReglees([{'id': 'autre', 'valeur': 9}]), 3);
    });
  });

  group('antériorités : seules les mesures RENDUES comptent', () {
    final d = [
      demande('D1', '2026-01-10', valeurs: {'GB': 5}),
      demande('D2', '2026-02-10', etat: 'saisi', valeurs: {'GB': 9}),
      demande('D3', '2026-03-10', etat: 'valide_technique', valeurs: {'GB': 9}),
      demande('D4', '2026-04-10', etat: 'rectifie', valeurs: {'GB': 6}),
      demande('D5', '2026-05-10', valeurs: {'GB': 7}),
    ];
    test('une saisie ou une validation technique n’entre jamais dans une antériorité ; une rectifiée y entre', () {
      final a = anterieuresDe(d[4], jeu(d));
      expect(a.mesures.map((x) => x['id']), ['D1', 'D4']);
      expect(mesuresRendues('P1', 'NFS', jeu(d)).visibles.map((x) => x['id']), ['D1', 'D4', 'D5']);
    });
    test('une mesure non rendue lit tout de même ses antériorités rendues, dans l’ordre chronologique', () {
      final a = anterieuresDe(d[2], jeu(d));
      expect(a.mesures.map((x) => x['id']), ['D1']);
    });
    test('un autre patient ou un autre examen n’entre pas', () {
      final autres = [...d, demande('X1', '2026-04-20', patient: 'P2'), {...demande('X2', '2026-04-21'), 'examenCode': 'GLY', 'analyse': 'Glycémie'}];
      expect(anterieuresDe(d[4], jeu(autres)).mesures.map((x) => x['id']), ['D1', 'D4']);
    });
  });

  group('antériorités : au plus trois (réglable), de la plus ancienne à la plus récente', () {
    final d = [for (var i = 1; i <= 6; i++) demande('R$i', '2026-0$i-10', valeurs: {'GB': 4 + i, if (i == 1) 'HB': 13})];
    test('trois par défaut : les trois plus récentes avant la mesure comparée', () {
      final a = anterieuresDe(d[5], jeu(d));
      expect(a.mesures.map((x) => x['id']), ['R3', 'R4', 'R5']);
      expect(a.toutes.length, 5);
    });
    test('le réglage change le nombre', () {
      expect(anterieuresDe(d[5], jeu(d, nombre: 2)).mesures.map((x) => x['id']), ['R4', 'R5']);
      expect(anterieuresDe(d[5], jeu(d, nombre: 5)).mesures.length, 5);
    });
    test('la mesure comparée est choisie : ses antériorités s’en déduisent', () {
      expect(anterieuresDe(d[3], jeu(d)).mesures.map((x) => x['id']), ['R1', 'R2', 'R3']);
      expect(anterieuresDe(d[0], jeu(d)).mesures, isEmpty);
    });
    test('colonnes : les antériorités puis la mesure comparée en dernier', () {
      final m = modeleComparatif('NFS', d[5], jeu(d));
      expect(m.colonnes.map((x) => x['id']), ['R3', 'R4', 'R5', 'R6']);
    });
    test('la valeur précédente d’une variable se cherche au-delà des colonnes affichées', () {
      // HB n'a été mesurée qu'en R1 ; R6 n'en porte pas : pas de variation. Avec HB en R6, la précédente est R1 (hors des trois colonnes).
      final avecHb = [...d.take(5), demande('R6', '2026-06-10', valeurs: {'GB': 10, 'HB': 12})];
      final m = modeleComparatif('NFS', avecHb[5], jeu(avecHb));
      final hb = m.lignes.firstWhere((l) => l.variable['code'] == 'HB');
      expect(hb.precedente!['id'], 'R1');
      expect(hb.variation!.sens, 'baisse');
      expect(texteVariation(hb.variation, hb.suffixe), '↓ -1 G/l (-7.7 %)');
      // La précédente n'est pas la colonne voisine : le modèle le sait (l'écran le dit).
      expect(m.colonnes.map((x) => x['id']), isNot(contains('R1')));
    });
  });

  group('bornes de l’époque', () {
    final plages = <F>[
      {'id': 'P1', 'variableId': 'VAR-NFS-GB', 'lot': 'LOT-B', 'dateDebut': '2026-03-01', 'min': 5, 'max': 7},
    ];
    final d = [
      demande('E1', '2026-02-10', valeurs: {'GB': 4.5}), // bornes de la variable 4-8 : normal
      demande('E2', '2026-04-10', valeurs: {'GB': 4.5}), // bornes du lot 5-7 : bas
    ];
    test('chaque colonne se juge aux bornes de SON époque', () {
      final m = modeleComparatif('NFS', d[1], jeu(d, plages: plages));
      final gb = m.lignes.firstWhere((l) => l.variable['code'] == 'GB');
      expect(gb.cellules[0].ecart, isNull, reason: 'avant le lot : 4-8');
      expect(gb.cellules[0].reference, '4 - 8');
      expect(gb.cellules[1].ecart, 'bas', reason: 'après le lot : 5-7');
      expect(gb.cellules[1].reference, '5 - 7 — lot LOT-B');
    });
    test('une colonne ne se juge jamais aux bornes de la mesure comparée', () {
      final m = modeleComparatif('NFS', d[1], jeu(d, plages: plages));
      final gb = m.lignes.firstWhere((l) => l.variable['code'] == 'GB');
      expect(gb.cellules[0].ecart, isNot(gb.cellules[1].ecart));
    });
  });

  group('variation', () {
    final gb = variables[0];
    test('numérique : sens, écart signé, pourcentage', () {
      final h = variationEntre(gb, 5, 6.5)!;
      expect(h.sens, 'hausse');
      expect(h.ecart, 1.5);
      expect(h.pourcent, 30);
      expect(texteVariation(h, ' G/l'), '↑ +1.5 G/l (+30.0 %)');
      final b = variationEntre(gb, 8, 6)!;
      expect(texteVariation(b, ' G/l'), '↓ -2 G/l (-25.0 %)');
      final e = variationEntre(gb, 5, 5)!;
      expect(e.sens, 'egal');
      expect(texteVariation(e), '= 0 (0.0 %)');
    });
    test('valeur précédente nulle : jamais un pourcentage inventé, et on le dit', () {
      final v = variationEntre(gb, 0, 3)!;
      expect(v.divisionParZero, isTrue);
      expect(v.pourcent, isNull);
      expect(texteVariation(v, ' G/l'), '↑ +3 G/l (écart relatif non calculable : valeur précédente nulle)');
    });
    test('qualitative : texte, jamais de pourcentage', () {
      final q = variationEntre(variables[3], 'Négatif', 'Positif')!;
      expect(q.mode, 'texte');
      expect(q.pourcent, isNull);
      expect(texteVariation(q), 'Négatif puis Positif');
      expect(texteVariation(variationEntre(variables[3], 'Négatif', ' négatif ')), 'Inchangé (négatif)');
    });
    test('titres, commentaires, réactif, lot : rien à comparer', () {
      expect(variationEntre(variables[4], 'A', 'B'), isNull);
      expect(variationEntre(variables[5], 'a', 'b'), isNull);
      expect(variationEntre({...variables[0], 'type': 'reactif'}, 'a', 'b'), isNull);
      expect(variationEntre({...variables[0], 'type': 'titre'}, 'a', 'b')!.mode, 'texte'); // un titre est qualitatif : comparé en texte
    });
    test('une valeur d’une variable numérique qui n’est pas un nombre se compare en texte', () {
      final v = variationEntre(gb, '<0,5', '2')!;
      expect(v.mode, 'texte');
    });
    test('une valeur absente d’un côté : aucune variation', () {
      expect(variationEntre(gb, null, 5), isNull);
      expect(variationEntre(gb, 5, ''), isNull);
    });
  });

  group('périmètre RBAC métier des antériorités', () {
    final d = [
      demande('S1', '2026-01-10', secteur: 'MATERNITÉ'),
      demande('S2', '2026-02-10', secteur: 'MÉDECINE GÉNÉRALE'),
      demande('S3', '2026-03-10', secteur: 'MATERNITÉ'),
      demande('S4', '2026-04-10', secteur: 'MATERNITÉ'),
    ];
    const sageFemme = SessionLabo(role: 'sage_femme', fonction: 'sage_femme', secteur: 'MAT');
    test('une sage-femme ne lit pas une antériorité d’un autre secteur : elle est comptée, motivée, jamais montrée', () {
      final a = anterieuresDe(d[3], jeu(d, session: sageFemme));
      expect(a.mesures.map((x) => x['id']), ['S1', 'S3']);
      expect(a.masquees, 1);
      expect(a.motif, contains('hors de son périmètre'));
      final m = modeleComparatif('NFS', d[3], jeu(d, session: sageFemme));
      expect(m.colonnes.map((x) => x['id']), ['S1', 'S3', 'S4']);
    });
    test('le biologiste voit tout', () {
      final a = anterieuresDe(d[3], jeu(d, session: biologiste));
      expect(a.mesures.map((x) => x['id']), ['S1', 'S2', 'S3']);
      expect(a.masquees, 0);
    });
    test('une infirmière ne compare rien', () {
      const inf = SessionLabo(role: 'infirmier', fonction: 'infirmier');
      expect(mesuresRendues('P1', 'NFS', jeu(d, session: inf)).visibles, isEmpty);
    });
    test('la variation et la fiche imprimée n’utilisent jamais une antériorité interdite', () {
      final v = variables[0];
      final sf = jeu(d, session: sageFemme);
      // S3 (maternité) a pour précédente visible S1 et non S2 (médecine générale, interdite à la sage-femme).
      expect(derniereValeurAnterieure(d[2], 'GB', sf)!.demande['id'], 'S1');
      expect(texteAnterioriteImprimee(v, d[2], sf), '5 G/l (10/01/2026)');
    });
  });

  group('colonne « Antériorités » imprimée', () {
    final d = [
      demande('I1', '2026-01-10', valeurs: {'GB': 5}),
      demande('I2', '2026-05-10', valeurs: {'GB': 6, 'HB': 12}),
    ];
    test('mesure et date de l’antériorité la plus récente ; jamais un blanc', () {
      final j = jeu(d);
      expect(texteAnterioriteImprimee(variables[0], d[1], j), '5 G/l (10/01/2026)');
      expect(texteAnterioriteImprimee(variables[1], d[1], j), 'Aucune antériorité');
      expect(texteAnterioriteImprimee(variables[4], d[1], j), 'Sans objet');
      expect(texteAnterioriteImprimee(variables[0], d[0], j), 'Aucune antériorité');
    });
  });

  group('seuils : enregistrer, valider, versions, droit', () {
    final gb = variables[0];
    final qual = variables[3];

    // Un magasin de fortune : applique un verdict à la liste, comme le poste.
    List<F> appliquer(List<F> base, VerdictSeuil v) {
      expect(v.ok, isTrue, reason: v.refus?.motif);
      if (v.creation) return [...base, {'id': 'SEU${base.length + 1}', ...v.fiche!}];
      if (v.archivage) return [for (final f in base) if (f['id'] == v.id) {...f, 'statut': 'archive'} else f];
      return [for (final f in base) if (f['id'] == v.id) {...f, ...v.patch!} else f];
    }

    List<F> actifs(List<F> l) => [for (final f in l) if (f['statut'] != 'archive') f];

    VerdictSeuil enreg(List<F> base, {Object? abs, Object? rel, bool retrait = false, String date = '2026-11-13', bool droit = true, F? variable}) => enregistrerSeuil(
        variable: variable ?? gb,
        variableId: '${(variable ?? gb)['id']}',
        seuilsActifs: actifs(base),
        droitEditer: droit,
        profil: 'Profil',
        ecartAbsolu: abs,
        ecartRelatif: rel,
        retrait: retrait,
        dateEffet: date,
        acteur: 'Dr B',
        role: 'laborantin',
        maintenant: auj);

    VerdictSeuil valide(List<F> base, {bool droit = true, bool fonction = true, String? motif = 'Recommandation du réactif'}) => validerSeuil(
        variableId: '${gb['id']}', seuilsActifs: actifs(base), droitValider: droit, fonctionHabilitee: fonction, profil: 'Profil', motif: motif, acteur: 'Dr B', libelleRole: 'Biologiste médical', maintenant: auj);

    test('aucun seuil par défaut : rien n’est configuré, aucune alerte', () {
      expect(etatSeuil('${gb['id']}', const [], aujourdhui: auj).etat, 'aucun');
      expect(seuilEnVigueur('${gb['id']}', null, const [], aujourdhui: auj), isNull);
      final v = variationEntre(gb, 5, 50);
      expect(alerteVariation(gb, v, '2026-11-13', const [], aujourdhui: auj), isNull);
    });

    test('refus nommés à l’enregistrement', () {
      expect(enreg(const [], abs: 1, droit: false).refus!.code, 'DROIT_REFUSE');
      expect(enreg(const [], abs: 1, variable: qual).refus!.code, 'VARIABLE_NON_NUMERIQUE');
      expect(enreg(const [], abs: 1, variable: variables[4]).refus!.code, 'VARIABLE_NON_NUMERIQUE');
      expect(enreg(const []).refus!.code, 'SEUIL_VIDE');
      expect(enreg(const [], abs: 0).refus!.code, 'SEUIL_INVALIDE');
      expect(enreg(const [], rel: -5).refus!.code, 'SEUIL_INVALIDE');
      expect(enreg(const [], abs: 1, date: '2026-11-12').refus!.code, 'DATE_EFFET_PASSEE');
      expect(enreg(const [], retrait: true).refus!.code, 'RIEN_A_RETIRER');
      expect(enreg(const [], abs: 1, retrait: true).refus!.code, 'RETRAIT_AVEC_VALEURS');
      expect(enregistrerSeuil(variable: null, variableId: 'X', seuilsActifs: const [], droitEditer: true, profil: 'P', ecartAbsolu: 1, acteur: 'a', role: 'r', maintenant: auj).refus!.code, 'VARIABLE_INTROUVABLE');
    });

    test('ENREGISTRER garde l’état Enregistré, sans effet : aucune alerte, même pour un seuil écrasant', () {
      final base = appliquer(const [], enreg(const [], abs: 0.5));
      final e = etatSeuil('${gb['id']}', base, aujourdhui: auj);
      expect(e.etat, 'enregistre');
      expect(e.brouillon!['version'], 1);
      expect(e.enVigueur, isNull);
      final a = alerteVariation(gb, variationEntre(gb, 5, 50), '2026-11-13', base, aujourdhui: auj);
      expect(a, isNull, reason: 'un seuil Enregistré est sans effet');
    });

    test('une seconde saisie remplace le brouillon, elle n’ajoute pas de version', () {
      var base = appliquer(const [], enreg(const [], abs: 0.5));
      final v2 = enreg(base, abs: 2, rel: 10);
      expect(v2.creation, isFalse);
      base = appliquer(base, v2);
      expect(base.length, 1);
      expect(base.single['ecartAbsolu'], 2);
      expect(base.single['ecartRelatif'], 10);
    });

    test('VALIDER : réservé par la matrice, la fonction, le motif et l’existence d’un brouillon — le moteur refuse ce que l’écran n’offre pas', () {
      final base = appliquer(const [], enreg(const [], abs: 1));
      expect(valide(base, droit: false).refus!.code, 'VALIDATION_RESERVEE');
      expect(valide(base, fonction: false).refus!.code, 'FONCTION_NON_HABILITEE');
      expect(valide(base, motif: '  ').refus!.code, 'MOTIF_OBLIGATOIRE');
      expect(valide(base, motif: null).refus!.code, 'MOTIF_OBLIGATOIRE');
      expect(valide(const []).refus!.code, 'SEUIL_NON_ENREGISTRE');
      // Rien n'a été validé par ces refus.
      expect(etatSeuil('${gb['id']}', base, aujourdhui: auj).etat, 'enregistre');
    });

    test('VALIDER fait passer de Enregistré à Validé : auteur, rôle, date et motif sont portés par la version', () {
      var base = appliquer(const [], enreg(const [], abs: 1, rel: 20));
      final v = valide(base);
      expect(v.patch!['etat'], 'valide');
      expect(v.patch!['validePar'], 'Dr B');
      expect(v.patch!['valideRole'], 'Biologiste médical');
      expect(v.patch!['motifValidation'], 'Recommandation du réactif');
      expect(v.patch!['valideLe'], isNotNull);
      base = appliquer(base, v);
      final e = etatSeuil('${gb['id']}', base, aujourdhui: auj);
      expect(e.etat, 'valide');
      expect(texteSeuil(e.enVigueur!, ' G/l'), '1 G/l ou 20 %');
    });

    test('un seuil validé à date d’effet future n’est pas encore en vigueur', () {
      var base = appliquer(const [], enreg(const [], abs: 1, date: '2026-12-01'));
      base = appliquer(base, valide(base));
      expect(seuilEnVigueur('${gb['id']}', '2026-11-30', base, aujourdhui: auj), isNull);
      expect(seuilEnVigueur('${gb['id']}', '2026-12-01', base, aujourdhui: auj), isNotNull);
      expect(etatSeuil('${gb['id']}', base, aujourdhui: auj).aVenir, isNotNull);
    });

    test('VERSIONS IMMUABLES : modifier un seuil validé AJOUTE une version, la validée reste en force', () {
      var base = appliquer(const [], enreg(const [], abs: 1));
      base = appliquer(base, valide(base));
      final v = enreg(base, abs: 3, date: '2026-11-20');
      expect(v.creation, isTrue);
      expect(v.fiche!['version'], 2);
      base = appliquer(base, v);
      final e = etatSeuil('${gb['id']}', base, aujourdhui: auj);
      expect(e.etat, 'enregistre_sur_valide');
      expect(e.enVigueur!['version'], 1);
      expect(e.enVigueur!['ecartAbsolu'], 1);
      expect(e.versions.length, 2);
      // La garde du magasin : la version validée ne se réécrit ni ne s'archive, d'où qu'arrive l'écriture.
      final validee = base.first;
      expect(gardeSeuil('modifier', {...validee, 'ecartAbsolu': 99}, validee), contains('IMMUABLE'));
      expect(gardeSeuil('archiver', validee, validee), contains('ne s’archive pas'));
      expect(gardeSeuil('inserer', validee, validee), contains('existe déjà'));
      // Le brouillon, lui, se remplace et s'abandonne.
      expect(gardeSeuil('modifier', {...base.last, 'ecartAbsolu': 4}, base.last), isNull);
      expect(gardeSeuil('archiver', base.last, base.last), isNull);
      // Il ne devient « validé » qu'avec ses traces.
      expect(gardeSeuil('modifier', {...base.last, 'etat': 'valide'}, base.last), contains('auteur, sa date et son motif'));
    });

    test('date d’effet antérieure à une version validée : refusée', () {
      var base = appliquer(const [], enreg(const [], abs: 1, date: '2026-12-10'));
      base = appliquer(base, valide(base));
      expect(enreg(base, abs: 2, date: '2026-12-01').refus!.code, 'DATE_EFFET_ANTERIEURE');
    });

    test('à la validation, une date d’effet devenue passée est refusée en disant quoi faire', () {
      final base = [
        {'id': 'S', 'variableId': '${gb['id']}', 'variableCode': 'GB', 'version': 1, 'etat': 'enregistre', 'ecartAbsolu': 1, 'dateEffet': '2026-11-01', 'statut': 'actif'}
      ];
      final r = valide(base).refus!;
      expect(r.code, 'DATE_EFFET_PASSEE');
      expect(r.geste, contains('Enregistrer de nouveau'));
    });

    test('retirer l’alerte est une version aussi : enregistrée puis validée', () {
      var base = appliquer(const [], enreg(const [], abs: 1));
      base = appliquer(base, valide(base));
      final r = enreg(base, retrait: true, date: '2026-11-14');
      expect(r.creation, isTrue);
      base = appliquer(base, r);
      expect(etatSeuil('${gb['id']}', base, aujourdhui: auj).enVigueur!['version'], 1, reason: 'le retrait n’agit qu’une fois validé');
      base = appliquer(base, valide(base));
      expect(seuilEnVigueur('${gb['id']}', '2026-11-14', base, aujourdhui: auj)!['retrait'], isTrue);
      expect(alerteVariation(gb, variationEntre(gb, 5, 50), '2026-11-14', base, aujourdhui: auj), isNull);
      expect(etatSeuil('${gb['id']}', base, aujourdhui: DateTime(2026, 11, 20)).retire, isTrue);
    });

    test('abandonner un brouillon l’archive, la version validée reste', () {
      var base = appliquer(const [], enreg(const [], abs: 1));
      base = appliquer(base, valide(base));
      base = appliquer(base, enreg(base, abs: 5, date: '2026-11-20'));
      final ab = abandonnerSeuil(variableId: '${gb['id']}', seuilsActifs: actifs(base), droitEditer: true, profil: 'P');
      expect(ab.archivage, isTrue);
      base = appliquer(base, ab);
      expect(etatSeuil('${gb['id']}', actifs(base), aujourdhui: auj).etat, 'valide');
      expect(abandonnerSeuil(variableId: '${gb['id']}', seuilsActifs: actifs(base), droitEditer: true, profil: 'P').refus!.code, 'SEUIL_NON_ENREGISTRE');
      expect(abandonnerSeuil(variableId: '${gb['id']}', seuilsActifs: actifs(base), droitEditer: false, profil: 'P').refus!.code, 'DROIT_REFUSE');
    });

    test('la fonction du technicien de laboratoire (intérim) est exclue ; une fonction non déclarée laisse la matrice décider', () {
      expect(fonctionPeutValiderSeuil(const SessionLabo(role: 'laborantin', fonction: 'biologiste')), isTrue);
      expect(fonctionPeutValiderSeuil(const SessionLabo(role: 'laborantin', fonction: 'tsl')), isFalse);
      expect(fonctionPeutValiderSeuil(const SessionLabo(role: 'direction', fonction: 'direction')), isFalse);
      expect(fonctionPeutValiderSeuil(const SessionLabo(role: 'laborantin')), isTrue);
      expect(fonctionPeutValiderSeuil(const SessionLabo(role: 'laborantin', fonction: 'inconnue')), isTrue);
      expect(fonctionPeutValiderSeuil(null), isTrue);
    });

    List<F> seuilValide(Map<String, Object?> champs) => [
          {
            'id': 'SEU1',
            'variableId': '${gb['id']}',
            'variableCode': 'GB',
            'version': 1,
            'etat': 'valide',
            'dateEffet': '2026-01-01',
            'retrait': false,
            'statut': 'actif',
            'valideLe': '2026-01-01T08:00:00Z',
            'validePar': 'Dr B',
            ...champs,
          }
        ];

    test('alerte : absolu, relatif, « l’un ou l’autre »', () {
      final abs = seuilValide({'ecartAbsolu': 2});
      expect(alerteVariation(gb, variationEntre(gb, 5, 7), '2026-11-13', abs, aujourdhui: auj)!.alerte, isTrue);
      expect(alerteVariation(gb, variationEntre(gb, 5, 6.9), '2026-11-13', abs, aujourdhui: auj)!.alerte, isFalse);
      final rel = seuilValide({'ecartRelatif': 20});
      expect(alerteVariation(gb, variationEntre(gb, 5, 4), '2026-11-13', rel, aujourdhui: auj)!.alerte, isTrue, reason: 'une baisse de 20 % alerte aussi');
      expect(alerteVariation(gb, variationEntre(gb, 5, 5.5), '2026-11-13', rel, aujourdhui: auj)!.alerte, isFalse);
      final les2 = seuilValide({'ecartAbsolu': 10, 'ecartRelatif': 20});
      final a = alerteVariation(gb, variationEntre(gb, 5, 7), '2026-11-13', les2, aujourdhui: auj)!;
      expect(a.alerte, isTrue);
      expect(a.raisons.map((r) => r.type), ['relatif'], reason: '40 % ≥ 20 %, 2 < 10 : seul le relatif est atteint');
    });

    test('seuil relatif sur valeur précédente nulle : non évalué, et le dit ; le seuil absolu, lui, s’évalue', () {
      final rel = seuilValide({'ecartRelatif': 20});
      final a = alerteVariation(gb, variationEntre(gb, 0, 9), '2026-11-13', rel, aujourdhui: auj)!;
      expect(a.alerte, isFalse);
      expect(a.nonEvaluable, isTrue);
      final deux = seuilValide({'ecartRelatif': 20, 'ecartAbsolu': 5});
      expect(alerteVariation(gb, variationEntre(gb, 0, 9), '2026-11-13', deux, aujourdhui: auj)!.alerte, isTrue);
    });

    test('décision du 13/11/2026 : valeur précédente proche de zéro, le pourcentage n’est pas calculé et seul l’absolu juge', () {
      final v = variationEntre(gb, 1e-12, 3)!;
      expect(v.divisionParZero, isTrue);
      expect(v.pourcent, isNull);
      expect(texteVariation(v, ' G/l'), contains('valeur précédente proche de zéro'));
      final rel = seuilValide({'ecartRelatif': 20});
      final ar = alerteVariation(gb, v, '2026-11-13', rel, aujourdhui: auj)!;
      expect(ar.alerte, isFalse, reason: 'jamais un pourcentage énorme sur une quasi-zéro');
      expect(ar.nonEvaluable, isTrue);
      final deux = alerteVariation(gb, v, '2026-11-13', seuilValide({'ecartRelatif': 20, 'ecartAbsolu': 2}), aujourdhui: auj)!;
      expect(deux.alerte, isTrue);
      expect(deux.raisons.map((r) => r.type), ['absolu']);
      expect(deux.nonEvaluable, isTrue, reason: 'le relatif non évalué se dit même quand l’absolu juge');
      // Une valeur réellement mesurée, même petite, se divise.
      expect(variationEntre(gb, 0.01, 3)!.pourcent, isNotNull);
    });

    test('décision du 13/11/2026 : valider est un geste réservé à la matrice, l’accès complet de l’administrateur ne le satisfait pas', () {
      final base = appliquer(const [], enreg(const [], abs: 1));
      VerdictSeuil v(String role) => validerSeuil(
          variableId: '${gb['id']}', seuilsActifs: actifs(base), droitValider: true, fonctionHabilitee: true, profil: 'P', role: role, motif: 'm', acteur: 'a', libelleRole: 'L', maintenant: auj);
      expect(v('admin').refus!.code, 'VALIDATION_HORS_MATRICE');
      expect(v('laborantin').ok, isTrue);
      expect(accesCompletSuffit('seuil.valider', 'admin'), isFalse);
      expect(accesCompletSuffit('seuil.valider', 'laborantin'), isTrue);
      expect(accesCompletSuffit('autre.geste', 'admin'), isTrue, reason: 'rien d’autre ne change pour l’administrateur');
      // L'administrateur enregistre toujours (éditer).
      expect(enreg(const [], abs: 1).ok, isTrue);
    });

    test('pas d’alerte sur une variable qualitative', () {
      expect(alerteVariation(qual, variationEntre(qual, 'Négatif', 'Positif'), '2026-11-13', seuilValide({'ecartAbsolu': 1}), aujourdhui: auj), isNull);
    });

    test('une mesure se juge au seuil en vigueur à la date de sa VALIDATION biologique, non à celle d’aujourd’hui', () {
      // v1 (abs 1) depuis le 01/01 ; v2 (abs 100) depuis le 01/11.
      final seuils = [
        ...seuilValide({'ecartAbsolu': 1}),
        ...[
          {...seuilValide({'ecartAbsolu': 100}).single, 'id': 'SEU2', 'version': 2, 'dateEffet': '2026-11-01'}
        ]
      ];
      final prec = demande('A1', '2026-05-01', valeurs: {'GB': 5});
      final avantV2 = demande('A2', '2026-09-01', valeurs: {'GB': 7}, valideLe: '2026-09-02T10:00:00Z');
      final apresV2 = demande('A3', '2026-11-05', valeurs: {'GB': 7}, valideLe: '2026-11-06T10:00:00Z');
      final tout = [prec, avantV2];
      expect(alertesDe(avantV2, jeu(tout, seuils: seuils)).length, 1, reason: 'validée sous v1 (1) : écart 2 ≥ 1');
      final tout2 = [prec, avantV2, apresV2];
      // apresV2 est jugée sous v2 : son écart à la précédente (7 -> 7 = 0) n'alerte pas ; avantV2 garde son alerte (v1) bien que v2 soit en vigueur aujourd'hui.
      expect(alertesDe(avantV2, jeu(tout2, seuils: seuils)).length, 1);
      expect(alertesDe(apresV2, jeu(tout2, seuils: seuils)), isEmpty);
      final grosse = demande('A4', '2026-11-07', valeurs: {'GB': 50}, valideLe: '2026-11-08T10:00:00Z');
      expect(alertesDe(grosse, jeu([...tout2, grosse], seuils: seuils)).length, 0, reason: 'écart 43 < 100 sous v2');
    });

    test('une mesure non rendue se juge au seuil d’aujourd’hui (le résultat qu’on s’apprête à signer)', () {
      final seuils = seuilValide({'ecartAbsolu': 1});
      final prec = demande('B1', '2026-05-01', valeurs: {'GB': 5});
      final aSigner = demande('B2', '2026-11-12', etat: 'valide_technique', valeurs: {'GB': 9});
      final al = alertesDe(aSigner, jeu([prec, aSigner], seuils: seuils));
      expect(al.length, 1);
      expect(al.single.variable['code'], 'GB');
      expect(texteVariation(al.single.variation, al.single.suffixe), '↑ +4 G/l (+80.0 %)');
      expect(texteAlerte(al.single.alerte, al.single.suffixe), 'Variation brutale : seuil de 1 G/l atteint (seuil validé, version 1 du 01/01/2026)');
    });

    test('L’ALERTE NE BLOQUE JAMAIS : la validation biologique passe, avec ou sans alerte, et ne crée aucune notification d’alerte', () {
      final seuils = seuilValide({'ecartAbsolu': 1});
      final prec = demande('C1', '2026-05-01', valeurs: {'GB': 5});
      final aSigner = {...demande('C2', '2026-11-12', etat: 'valide_technique', valeurs: {'GB': 9}), 'valideTechniquePar': 'TSL'};
      expect(alertesDe(aSigner, jeu([prec, aSigner], seuils: seuils)), isNotEmpty);
      final g = validerBiologique(aSigner, session: biologiste, utilisateur: 'Dr B', maintenant: auj);
      expect(g.patch['etatAnalyse'], 'valide');
      // La seule notification est celle du résultat disponible : rien sur la variation, aucune donnée médicale ajoutée.
      expect(g.notification!['type'], 'resultat_disponible');
      expect('${g.notification}', isNot(contains('variation')));
      expect('${g.notification}', isNot(contains('9')));
    });

    test('aucune fenêtre de temps : une variation sur plusieurs mois alerte comme sur deux jours', () {
      final seuils = seuilValide({'ecartAbsolu': 1});
      final loin = demande('F1', '2024-01-01', valeurs: {'GB': 5});
      final pres = demande('F2', '2026-11-12', valeurs: {'GB': 9});
      expect(alertesDe(pres, jeu([loin, pres], seuils: seuils)).length, 1);
    });

    test('les constantes d’hospitalisation ne portent aucune alerte de variation : aucune règle documentée', () {
      // Le moteur ne lit que des variables d'EXAMEN (catalogue du laboratoire) : une constante n'a ni code d'examen ni variable.
      final constante = {'id': 'REL1', 'patientId': 'P1', 'temperature': 39, 'etatAnalyse': 'valide', 'valeurs': {'temperature': 39}, 'dateHeure': '2026-11-12T10:00:00Z'};
      expect(alertesDe(constante, jeu([constante], seuils: seuilValide({'ecartAbsolu': 1}))), isEmpty);
    });
  });
}
