import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';


import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';


import 'widget/remdy_app.dart';
import 'pages/main_shell_page.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );


  runApp(const RemdyApp(child: MyApp()));
}


class MyApp extends StatelessWidget {
  const MyApp({super.key});


  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,


      locale: RemdyApp.localeOf(context),
      supportedLocales: const [
        Locale('pt'),
        Locale('en'),
        Locale('es'),
        Locale('fr'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],


      home: const MainShell(initialIndex: 0), // ou LoginPage()
    );
  }
}
