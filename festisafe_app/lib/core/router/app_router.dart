import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../presentation/screens/welcome_screen.dart';
import '../../presentation/screens/login_screen.dart';
import '../../presentation/screens/register_screen.dart';
import '../../presentation/screens/home_screen.dart';
import '../../presentation/screens/profile_screen.dart';
import '../../presentation/screens/events_screen.dart';
import '../../presentation/screens/event_detail_screen.dart';
import '../../presentation/screens/group_screen.dart';
import '../../presentation/screens/map_screen.dart';
import '../../presentation/screens/compass_screen.dart';
import '../../presentation/screens/organizer_dashboard_screen.dart';
import '../../presentation/screens/qr_screen.dart';
import '../../presentation/screens/participants_screen.dart';
import '../../presentation/screens/join_screen.dart';
import '../../presentation/screens/event_groups_screen.dart';
import '../../presentation/screens/admin_screen.dart';
import '../../presentation/screens/forgot_password_screen.dart';
import '../../presentation/screens/password_reset_screen.dart';
import '../../presentation/screens/chat_screen.dart';
import '../../presentation/screens/onboarding_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthRouterNotifier(ref);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: notifier,
    // Deep link scheme: festisafe://
    redirect: (context, state) {
      final authState = ref.read(authProvider);
      final isAuth = authState is AuthAuthenticated || authState is AuthGuest;
      final isLoading = authState is AuthLoading || authState is AuthInitial;
      final publicRoutes = ['/', '/login', '/register', '/reset-password', '/change-password', '/onboarding'];
      // /join/:code es accesible sin auth (redirige a login con returnTo)
      final isPublic = publicRoutes.contains(state.matchedLocation) ||
          state.matchedLocation.startsWith('/join/');

      if (isLoading) return null;
      if (!isAuth && !isPublic) return '/';
      if (isAuth && (state.matchedLocation == '/' ||
          state.matchedLocation == '/login' ||
          state.matchedLocation == '/register')) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: '/', builder: (_, __) => const WelcomeScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
      GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
      GoRoute(path: '/events', builder: (_, __) => const EventsScreen()),
      GoRoute(
        path: '/events/:eventId',
        builder: (_, state) => EventDetailScreen(eventId: state.pathParameters['eventId']!),
      ),
      GoRoute(
        path: '/groups/:groupId',
        builder: (_, state) => GroupScreen(groupId: state.pathParameters['groupId']!),
      ),
      GoRoute(
        path: '/map/:eventId',
        builder: (_, state) => MapScreen(eventId: state.pathParameters['eventId']!),
        routes: [
          GoRoute(
            path: 'chat',
            builder: (_, state) => ChatScreen(eventId: state.pathParameters['eventId']!),
          ),
        ],
      ),
      GoRoute(
        path: '/compass/:userId',
        builder: (_, state) => CompassScreen(targetUserId: state.pathParameters['userId']!),
      ),
      GoRoute(
        path: '/organizer/:eventId',
        redirect: (context, state) {
          final auth = ref.read(authProvider);
          if (auth is AuthAuthenticated && auth.user.isOrganizer) return null;
          return '/home';
        },
        builder: (_, state) =>
            OrganizerDashboardScreen(eventId: state.pathParameters['eventId']!),
      ),
      GoRoute(
        path: '/qr/:eventId',
        redirect: (context, state) {
          final auth = ref.read(authProvider);
          if (auth is AuthAuthenticated && auth.user.isOrganizer) return null;
          return '/home';
        },
        builder: (_, state) => QrScreen(eventId: state.pathParameters['eventId']!),
      ),
      // Pantalla de participantes con toggle grupo/todos
      GoRoute(
        path: '/participants/:eventId',
        builder: (_, state) => ParticipantsScreen(
          eventId: state.pathParameters['eventId']!,
        ),
      ),
      // Deep link: festisafe://join/CODIGO → /join/CODIGO
      GoRoute(
        path: '/join/:code',
        builder: (_, state) => JoinScreen(code: state.pathParameters['code']!),
      ),
      // Grupos disponibles del evento — solicitar unirse
      GoRoute(
        path: '/event-groups/:eventId',
        builder: (_, state) => EventGroupsScreen(
          eventId: state.pathParameters['eventId']!,
        ),
      ),
      // Panel de administración — solo admins
      GoRoute(
        path: '/admin',
        redirect: (context, state) {
          final auth = ref.read(authProvider);
          if (auth is AuthAuthenticated && auth.user.role == 'admin') return null;
          return '/home';
        },
        builder: (_, __) => const AdminScreen(),
      ),
      // Recuperación de contraseña
      GoRoute(
        path: '/forgot-password',
        builder: (_, __) => const ForgotPasswordScreen(),
      ),
      // Restablecer contraseña con token (deep link: festisafe://reset-password?token=...)
      GoRoute(
        path: '/reset-password',
        builder: (_, state) => PasswordResetScreen(
          mode: PasswordResetMode.resetWithToken,
          token: state.uri.queryParameters['token'],
        ),
      ),
      // Cambio obligatorio de contraseña (email pasado como query param)
      GoRoute(
        path: '/change-password',
        builder: (_, state) => PasswordResetScreen(
          mode: PasswordResetMode.changeObligatory,
          email: state.uri.queryParameters['email'],
        ),
      ),
    ],
    errorBuilder: (_, state) => Scaffold(
      body: Center(child: Text('Página no encontrada: ${state.error}')),
    ),
  );
});

class _AuthRouterNotifier extends ChangeNotifier {
  _AuthRouterNotifier(Ref ref) {
    ref.listen<AuthState>(authProvider, (_, __) => notifyListeners());
  }
}
