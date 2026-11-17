// LE SECRET D'ADMINISTRATION DE LA MÈRE (E4701, décision de la Direction du 17/11/2026) : un poste de PRODUCTION ne démarre jamais en mère sur un secret absent ou faible.
//
// Le secret est une valeur de COMPILATION (`--dart-define=SIGH_ADMIN=...`), jamais écrite dans le dépôt. Le repli [secretAdminRepli] n'existe que pour le développement et les
// tests : en mode release ([kReleaseMode]), un secret vide ou faible est REFUSÉ en le nommant, comme le refus de schéma plus récent. Fonctions pures : testables sans lancer de release.
import 'package:flutter/foundation.dart' show kReleaseMode;

/// Le repli de développement (jamais accepté en release).
const String secretAdminRepli = 'admin-local';

/// La longueur minimale d'un secret de production (même seuil que `build_windows.bat`).
const int secretAdminLongueurMin = 16;

/// Le secret est-il faible ? Vide, égal au repli de développement, ou plus court que [secretAdminLongueurMin].
bool secretAdminFaible(String brut) {
  final s = brut.trim();
  return s.isEmpty || s == secretAdminRepli || s.length < secretAdminLongueurMin;
}

/// Refus NOMMÉ : la mère d'un poste de production ne démarre pas sans secret d'administration solide.
class SecretAdminRefuse implements Exception {
  const SecretAdminRefuse();
  String get code => 'SECRET_ADMIN_FAIBLE';
  String get motif =>
      'Ce poste est une version de production construite sans secret d’administration solide (variable SIGH_ADMIN absente, égale à la valeur de développement ou de moins de $secretAdminLongueurMin caractères) : le mode mère ne démarre pas.';
  String get geste =>
      'Reconstruire le poste avec SIGH_ADMIN défini (au moins $secretAdminLongueurMin caractères, voir docs/guides/LANCER-EN-LOCAL.md). Rien n’a été modifié.';
  @override
  String toString() => '$code : $motif';
}

/// UNE SEULE lecture du secret : la valeur compilée, ou le repli de développement quand elle est vide.
String secretAdminEffectif(String brut) => brut.trim().isEmpty ? secretAdminRepli : brut.trim();

/// La garde : en [release], refuse un secret faible ([SecretAdminRefuse]) ; en développement et en test, ne refuse jamais. [release] vaut [kReleaseMode] par défaut.
void verifierSecretAdmin(String brut, {bool release = kReleaseMode}) {
  if (release && secretAdminFaible(brut)) throw const SecretAdminRefuse();
}
