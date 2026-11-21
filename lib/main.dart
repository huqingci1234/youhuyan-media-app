import 'package:material_ui/material_ui.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const YouhuyanApp());
}

class YouhuyanApp extends StatelessWidget {
  const YouhuyanApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF5267D8);
    return MaterialApp(
      title: '尤湖沿影视',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xFF10131D),
        useMaterial3: true,
        cardTheme: CardThemeData(
          color: const Color(0xFF1B2030),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
