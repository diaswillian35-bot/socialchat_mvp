import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';


import 'pages/login_page.dart';
import 'widget/remdy_app.dart';


void main() {
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


      home: const LoginPage(),
    );
  }
}
