// LA RESTAURATION DE LA CLÉ DE LA CLINIQUE SUR UN POSTE NEUF : les RÈGLES PURES (Direction de Baguidi, 17/11/2026, décision 12).
//
// Sans la clé de la clinique, les sauvegardes, les exports portables et le relais sont irrécupérables (ADR-0008). La clé se range sous scellé, hors de la mère ; sur un poste
// neuf, on la remet depuis cette copie. Deux règles ne se négocient pas :
//  * l'EMPREINTE de la clé est contrôlée AVANT qu'elle soit acceptée : on saisit l'empreinte notée sur le scellé (ou lue au manifeste d'un export / d'une sauvegarde), et une clé
//    qui ne la reproduit pas est refusée en le disant. On ne « devine » jamais une clé et on n'écrase jamais une clé en service par une autre sans l'avoir demandé ;
//  * la clé ne s'AFFICHE JAMAIS et ne se JOURNALISE jamais : seule son empreinte courte paraît (écran, journal, manifeste).
library;

import 'dart:convert';

import '../mere/mrb_regles.dart' show mrbEmpreinteCourte;
import '../documents/doc_sha256.dart' show docSha256;
import 'sauvegarde_horssite.dart' show RefusSauvegarde;

/// Longueur d'une clé de clinique (AES-256).
const int cleLongueur = 32;

/// Empreinte COMPLÈTE (SHA-256 hexadécimal) d'une clé : c'est la valeur que la mère publie (`mrbEmpreinteCourte` n'en affiche que huit caractères).
String cleEmpreinte(List<int> cle) => docSha256(cle);

/// Empreinte courte portée aux manifestes (16 caractères) : de quoi distinguer « mauvaise clé » de « fichier altéré », pas de quoi retrouver la clé.
String cleEmpreinteManifeste(List<int> cle) => cleEmpreinte(cle).substring(0, 16);

/// L'empreinte affichable (8 caractères majuscules) d'une clé.
String cleEmpreinteAffichee(List<int> cle) => mrbEmpreinteCourte(cleEmpreinte(cle)) ?? '';

/// Lit la clé telle qu'elle est écrite sur la copie sous scellé : 64 hexadécimaux (espaces et tirets de groupage tolérés) ou 44 caractères Base64 (32 octets). `null` : illisible.
List<int>? cleLireTexte(String texte) {
  final brut = texte.trim();
  final hex = brut.replaceAll(RegExp(r'[\s\-:]'), '');
  if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(hex)) return [for (var i = 0; i < 64; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];
  try {
    final b = base64.decode(brut.replaceAll(RegExp(r'\s'), ''));
    if (b.length == cleLongueur) return b;
  } catch (_) {}
  return null;
}

/// L'empreinte attendue, nettoyée : de 8 à 64 hexadécimaux. `null` : illisible.
String? cleEmpreinteAttendue(String saisie) {
  final h = saisie.replaceAll(RegExp(r'[\s\-:]'), '').toLowerCase();
  return RegExp(r'^[0-9a-f]{8,64}$').hasMatch(h) ? h : null;
}

RefusSauvegarde _r(String code, String motif, String geste) => RefusSauvegarde(code, motif, geste);

/// CONTRÔLE avant acceptation : [octets] est la clé lue, [empreinteAttendue] celle du scellé. Refus NOMMÉ ou `null`. [empreinteEnService] : l'empreinte (complète) de la clé déjà en
/// service sur ce poste ; une clé DIFFÉRENTE n'est remplacée que si [remplacer] est vrai.
RefusSauvegarde? cleControlerRestauration(
    {required List<int>? octets, required String empreinteAttendue, String? empreinteEnService, bool remplacer = false}) {
  if (octets == null) {
    return _r('CLE_ILLISIBLE', 'la clé saisie n’est ni 64 caractères hexadécimaux ni une clé Base64 de 32 octets', 'Recopier la clé de la copie sous scellé, caractère par caractère.');
  }
  if (octets.length != cleLongueur) return _r('CLE_ILLISIBLE', 'la clé doit faire ${cleLongueur * 8} bits', 'Recopier la clé de la copie sous scellé.');
  final attendue = cleEmpreinteAttendue(empreinteAttendue);
  if (empreinteAttendue.trim().isEmpty) {
    return _r('EMPREINTE_ABSENTE', 'l’empreinte de la clé est obligatoire : elle seule prouve que la clé saisie est la bonne', 'Saisir l’empreinte notée sur le scellé (au moins 8 caractères).');
  }
  if (attendue == null) return _r('EMPREINTE_ILLISIBLE', 'l’empreinte saisie n’est pas une suite de 8 à 64 caractères hexadécimaux', 'Recopier l’empreinte notée sur le scellé.');
  final calculee = cleEmpreinte(octets);
  if (!calculee.startsWith(attendue)) {
    return _r('EMPREINTE_DIFFERENTE', 'la clé saisie ne reproduit pas l’empreinte attendue : ce n’est pas la clé de la clinique, ou elle est mal recopiée', 'Reprendre la copie sous scellé. Aucune clé n’a été acceptée.');
  }
  if (empreinteEnService != null && empreinteEnService.isNotEmpty && empreinteEnService != calculee && !remplacer) {
    return _r('CLE_EN_SERVICE_DIFFERENTE', 'une AUTRE clé de clinique est déjà en service sur ce poste : la remplacer rendrait illisible ce qu’elle a chiffré', 'Confirmer explicitement le remplacement (poste neuf uniquement).');
  }
  return null;
}
