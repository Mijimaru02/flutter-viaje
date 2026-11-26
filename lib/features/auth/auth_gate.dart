import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../trips/trips_page.dart';
import 'auth_page.dart';
import 'password_recovery_page.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _passwordRecovery = false;

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;
    return StreamBuilder<AuthState>(
      stream: client.auth.onAuthStateChange,
      initialData: AuthState(
        AuthChangeEvent.initialSession,
        client.auth.currentSession,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data?.event == AuthChangeEvent.passwordRecovery) {
          _passwordRecovery = true;
        }
        if (client.auth.currentSession == null) {
          _passwordRecovery = false;
          return const AuthPage();
        }
        if (_passwordRecovery) {
          return PasswordRecoveryPage(
            onCompleted: () => setState(() => _passwordRecovery = false),
          );
        }
        return const TripsPage();
      },
    );
  }
}
