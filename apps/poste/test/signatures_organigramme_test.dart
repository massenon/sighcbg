import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/impression/piece.dart';

/// LES SIGNATAIRES D'UNE PIÈCE SE LISENT À L'ORGANIGRAMME ET AU PERSONNEL (lot « noms et signataires » de l'inventaire des valeurs en dur, 17/11/2026) : l'INTITULÉ vient du poste
/// de l'organigramme (collection `postes`), le NOM du titulaire courant au dossier du personnel ; l'intitulé écrit à l'appelant n'est que le repli. L'organigramme ne porte que le
/// titulaire ACTUEL : un nom ENREGISTRÉ sur la pièce ([Signature.nomFige]) ne se remplace jamais, même vide.
PieceA4 piece(List<Signature> s) => PieceA4(titre: 'État', reference: 'R-1', utilisateur: 'U', edite: DateTime(2030, 1, 5), signatures: s);

const postes = <Map<String, Object?>>[
  {'poste': 'Responsable Comptable', 'statut': 'actif'},
  {'poste': 'Chargé de l’Administration et des Ressources Humaines', 'statut': 'actif'},
  {'poste': 'Directeur Médical', 'statut': 'archive'},
];
const personnel = <Map<String, Object?>>[
  {'nomComplet': 'ESSAI Alpha', 'poste': 'Responsable Comptable', 'fonction': 'comptable', 'statut': 'actif'},
];

void main() {
  test('l’intitulé d’une signature à qualité est celui du poste de l’organigramme, le nom celui du titulaire du personnel', () {
    final p = piece(const [Signature('Le Comptable', qualite: PaiQualite.comptable)]).avecSignatures(personnel, postes: postes);
    expect(p.signatures.single.role, 'Responsable Comptable');
    expect(p.signatures.single.nom, 'ESSAI Alpha');
  });

  test('sans poste lisible à l’organigramme, l’intitulé écrit à l’appelant reste le repli ; un poste archivé ne signe pas', () {
    final p = piece(const [Signature('La Directrice Administrative', qualite: PaiQualite.daf), Signature('Le Directeur Médical', qualite: PaiQualite.directeurMedical)])
        .avecSignatures(personnel, postes: postes);
    expect(p.signatures[0].role, 'La Directrice Administrative', reason: 'aucun poste de directeur administratif à l’organigramme : le repli');
    expect(p.signatures[1].role, 'Le Directeur Médical', reason: 'le poste de directeur médical est archivé : il n’est pas lu');
    expect(p.signatures[1].nom, isNull, reason: 'aucun titulaire : la ligne reste sans nom, jamais devinée');
  });

  test('sans organigramme (collection vide), la pièce garde ses intitulés écrits et le nom vient du personnel', () {
    final p = piece(const [Signature('Le Comptable', qualite: PaiQualite.comptable)]).avecSignatures(personnel);
    expect(p.signatures.single.role, 'Le Comptable');
    expect(p.signatures.single.nom, 'ESSAI Alpha');
  });

  test('un nom ENREGISTRÉ sur la pièce ne devient jamais le titulaire courant, même vide ; l’intitulé, lui, se lit à l’organigramme', () {
    final p = piece(const [
      Signature('Le Comptable', nom: '', nomFige: true, qualite: PaiQualite.comptable),
      Signature('Le Comptable', nom: 'ESSAI Bravo', nomFige: true, qualite: PaiQualite.comptable),
    ]).avecSignatures(personnel, postes: postes);
    expect(p.signatures[0].nom, '', reason: 'le signataire d’époque est inconnu : la ligne reste vide, à signer à la main');
    expect(p.signatures[1].nom, 'ESSAI Bravo');
    expect(p.signatures[0].role, 'Responsable Comptable');
  });

  test('une signature sans qualité n’est jamais touchée ; une pièce sans qualité est rendue telle quelle', () {
    final sans = piece(const [Signature('Le Patient')]);
    expect(identical(sans.avecSignatures(personnel, postes: postes), sans), isTrue);
    final mixte = piece(const [Signature('Le Patient'), Signature('Le Comptable', qualite: PaiQualite.comptable)]).avecSignatures(personnel, postes: postes);
    expect(mixte.signatures[0].role, 'Le Patient');
    expect(mixte.signatures[1].role, 'Responsable Comptable');
  });
}
