import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'models/user_model.dart';
import 'screens/auth/login_page.dart';
import 'screens/home/app_shell.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'services/sos_background_handler.dart';
import 'services/sos_launch_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Data-only FCM SOS messages wake the killed app and run this handler,
  // which presents the full-screen alarm even when the app is closed.
  FirebaseMessaging.onBackgroundMessage(sosBackgroundMessageHandler);
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await NotificationService.instance.init();
  await SosLaunchService.instance.initialize();
  runApp(const MediCareApp());
}

class MediCareApp extends StatelessWidget {
  const MediCareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MediCare',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<UserModel?>(
      stream: AuthService().user,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData && snapshot.data != null) {
          return AppShell(user: snapshot.data!);
        }
        return const LoginPage();
      },
    );
  }
}
