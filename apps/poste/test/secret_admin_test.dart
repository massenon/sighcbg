// Le secret d'administration de la mère (E4701) : en production, absent ou faible = refus nommé ; en développement et en test, le repli reste.
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/secret_admin.dart';

void main() {
  const solide = 'un-secret-de-production-solide-0123';

  test('faible : vide, espaces, repli de développement, moins de 16 caractères', () {
    for (final f in ['', '   ', secretAdminRepli, ' $secretAdminRepli ', 'court', 'a' * (secretAdminLongueurMin - 1)]) {
      expect(secretAdminFaible(f), isTrue, reason: '« $f »');
    }
    expect(secretAdminFaible('a' * secretAdminLongueurMin), isFalse);
    expect(secretAdminFaible(solide), isFalse);
  });

  test('release : un secret faible REFUSE, avec un code, un motif et un geste nommés', () {
    for (final f in ['', secretAdminRepli, 'court']) {
      expect(() => verifierSecretAdmin(f, release: true),
          throwsA(isA<SecretAdminRefuse>().having((e) => e.code, 'code', 'SECRET_ADMIN_FAIBLE').having((e) => e.motif, 'motif', contains('SIGH_ADMIN')).having((e) => e.geste, 'geste', contains('Reconstruire'))));
    }
  });

  test('release : un secret solide passe', () => verifierSecretAdmin(solide, release: true));

  test('développement et test : jamais de refus, le repli est servi', () {
    verifierSecretAdmin('', release: false);
    verifierSecretAdmin(secretAdminRepli, release: false);
    expect(secretAdminEffectif(''), secretAdminRepli);
    expect(secretAdminEffectif(solide), solide);
  });

  test('la suite de test ne tourne pas en release : la garde par défaut ne refuse pas', () => verifierSecretAdmin(''));

  test('le refus n’expose jamais la valeur du secret', () {
    try {
      verifierSecretAdmin('petit-secret', release: true);
    } on SecretAdminRefuse catch (e) {
      expect('$e'.contains('petit-secret'), isFalse);
    }
  });
}
