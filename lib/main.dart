import 'dart:async';
import 'package:flutter/material.dart';
import 'api.dart';
import 'theme.dart';
import 'ui.dart';
import 'agent.dart';
import 'roles.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.loadToken();
  await loadLang();
  runApp(const SalesGoApp());
}

bool _bootedOnce = false;

class SalesGoApp extends StatelessWidget {
  const SalesGoApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: langVN,
      builder: (_, l, __) => MaterialApp(
        key: ValueKey('app_$l'),
        title: 'SalesGO',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const Root(),
      ),
    );
  }
}

/// Ildiz: birinchi ochilishda splash, keyin login yoki role-home.
class Root extends StatefulWidget {
  const Root({super.key});
  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  late bool showSplash = !_bootedOnce;
  @override
  void initState() {
    super.initState();
    if (!_bootedOnce) {
      Timer(const Duration(milliseconds: 1800), () {
        _bootedOnce = true;
        if (mounted) setState(() => showSplash = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (showSplash) return const _Splash();
    return Api.token == null ? const LoginScreen() : const Gate();
  }
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: brandGradient),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AnimatedWordmark(size: 46, base: Colors.white),
              const SizedBox(height: 12),
              Text(tr('Savdo — harakatda', 'Продажи — в движении'),
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.3)),
              const SizedBox(height: 30),
              SizedBox(
                height: 26,
                width: 26,
                child: CircularProgressIndicator(
                    strokeWidth: 2.4, color: Colors.white.withOpacity(0.9)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// me'ni yuklab rolga qarab ekran qaytaradi (navigatsiyasiz — til uchun).
class Gate extends StatefulWidget {
  const Gate({super.key});
  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> {
  String? err;
  @override
  void initState() {
    super.initState();
    if (Api.me == null) _load();
  }

  Future<void> _load() async {
    try {
      Api.me = Map<String, dynamic>.from(await Api.get('/auth/me'));
      if (mounted) setState(() {});
    } catch (e) {
      if (e == 'auth') {
        await Api.logout();
        if (mounted) setState(() {});
      } else {
        if (mounted) setState(() => err = '$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (Api.token == null) return const LoginScreen();
    if (err != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 48, color: muted),
                const SizedBox(height: 12),
                Text('${tr('Ulanishda xato', 'Ошибка подключения')}:\n$err',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: muted)),
                const SizedBox(height: 16),
                FilledButton(
                    onPressed: () {
                      setState(() => err = null);
                      _load();
                    },
                    child: Text(tr('Qayta urinish', 'Повторить'))),
              ],
            ),
          ),
        ),
      );
    }
    if (Api.me == null) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator(color: brand)));
    }
    switch (Api.me!['role']) {
      case 'agent':
        return const AgentShell();
      case 'delivery':
        return const DeliveryHome();
      case 'collector':
        return const CollectorHome();
      default:
        return const SupervisorHome();
    }
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final comp = TextEditingController(text: 'demo');
  final login = TextEditingController();
  final pass = TextEditingController();
  bool busy = false;
  bool hide = true;
  String? err;

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      err = null;
    });
    try {
      await Api.login(comp.text.trim(), login.text.trim(), pass.text);
      Api.me = null;
      if (mounted) {
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const Gate()));
      }
    } catch (e) {
      setState(() => err = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _lang(String code, String label) {
    final sel = lang == code;
    return GestureDetector(
      onTap: () => setLang(code),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
            color: sel ? brand : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: sel ? brand : line)),
        child: Text(label,
            style: TextStyle(
                color: sel ? Colors.white : muted,
                fontWeight: FontWeight.w800)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: brandGradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  const AnimatedWordmark(size: 40, base: Colors.white),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: softShadow,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(tr('Tizimga kirish', 'Вход в систему'),
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: ink)),
                        const SizedBox(height: 4),
                        Text(
                            tr('Hisobingiz bilan davom eting',
                                'Продолжите с вашим аккаунтом'),
                            style: const TextStyle(color: muted, fontSize: 13)),
                        const SizedBox(height: 18),
                        TextField(
                          controller: comp,
                          decoration: InputDecoration(
                            labelText: tr('Kompaniya kodi', 'Код компании'),
                            prefixIcon: const Icon(Icons.business_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: login,
                          decoration: InputDecoration(
                            labelText: tr('Login', 'Логин'),
                            prefixIcon: const Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: pass,
                          obscureText: hide,
                          onSubmitted: (_) => busy ? null : _login(),
                          decoration: InputDecoration(
                            labelText: tr('Parol', 'Пароль'),
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(hide
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              onPressed: () => setState(() => hide = !hide),
                            ),
                          ),
                        ),
                        if (err != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                                color: danger.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(10)),
                            child: Row(children: [
                              const Icon(Icons.error_outline,
                                  color: danger, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(err!,
                                      style: const TextStyle(
                                          color: danger, fontSize: 13))),
                            ]),
                          ),
                        ],
                        const SizedBox(height: 18),
                        GradientButton(
                          text: tr('Kirish', 'Войти'),
                          icon: Icons.login,
                          busy: busy,
                          onTap: _login,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _lang('uz', 'UZ'),
                            const SizedBox(width: 8),
                            _lang('ru', 'RU'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                      tr('SalesGO · savdo agentlari uchun',
                          'SalesGO · для торговых агентов'),
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.8), fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
