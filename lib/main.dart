import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/splash_page.dart';
import 'theme/app_theme.dart';

/// 전역 RouteObserver — 페이지 라우트 변경 이벤트를 RouteAware 위젯에 전달.
/// inventory_list_page에서 NEW 뱃지 자동 해제용으로 구독.
/// 추가로 다른 페이지에서도 RouteAware mixin 통해 자유롭게 구독 가능.
final RouteObserver<ModalRoute<dynamic>> routeObserver =
    RouteObserver<ModalRoute<dynamic>>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Auth Demo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      // 페이지 push/pop 이벤트를 RouteAware 위젯들에 전파
      navigatorObservers: [routeObserver],
      home: const SplashPage(),
    );
  }
}
