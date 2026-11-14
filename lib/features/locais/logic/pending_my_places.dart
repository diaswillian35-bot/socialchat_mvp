/// Destino pendente: depois do login, abrir Meus locais.
///
/// O [LoginPage] substitui a pilha por [SplashPage]; esta bandeira sobrevive
/// no isolado para o [AuthGate] retomar o destino.
class PendingMyPlaces {
  PendingMyPlaces._();

  static bool openAfterLogin = false;

  static bool take() {
    final pending = openAfterLogin;
    openAfterLogin = false;
    return pending;
  }
}
