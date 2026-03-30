/// Par de tokens JWT devuelto por la API tras autenticación.
class AuthTokens {
  final String accessToken;
  final String refreshToken;
  final bool isGuest;

  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    this.isGuest = false,
  });

  factory AuthTokens.fromJson(Map<String, dynamic> json) {
    return AuthTokens(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      isGuest: json['is_guest'] as bool? ?? false,
    );
  }
}
