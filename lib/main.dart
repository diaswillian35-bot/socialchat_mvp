import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_localizations/flutter_localizations.dart';


import 'firebase_options.dart';
import 'services/locale_controller.dart';


// ✅ seu root real
import 'pages/auth_gate.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();


  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );


  await LocaleController.instance.load();


  runApp(const MyApp());
}


class MyApp extends StatelessWidget {
  const MyApp({super.key});


  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LocaleController.instance,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,


          // ✅ SnackBar global (todas as páginas)
          theme: ThemeData(
            snackBarTheme: SnackBarThemeData(
              backgroundColor: const Color(0xFF313A5F), // azul Remdy
              contentTextStyle: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
              behavior: SnackBarBehavior.floating,
              elevation: 6,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),


          // ✅ idioma do app (muda na hora)
          locale: LocaleController.instance.locale,
          supportedLocales: LocaleController.supportedLocales,


          // ✅ IMPORTANTE: isso resolve o erro "No MaterialLocalizations found"
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],


          home: const AuthGate(), // <-- mantém seu root real
        );
      },
    );
  }
}
