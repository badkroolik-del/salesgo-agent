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
  runApp(const SalesGoApp());
}

class SalesGoApp extends StatelessWidget {
  const SalesGoApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SalesGO',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 1900), () {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        fadeRoute(Api.token == null ? const LoginScreen() : const Gate()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: brandGradient),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AnimatedLogo(size: 128),
              const SizedBox(height: 22),
              const Wordmark(size: 34, base: Colors.white),
              const SizedBox(height: 8),
              Text('Savdo — harakatda',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.3)),
              const SizedBox(height: 30),
              SizedBox(
                height: 26,
                width: 26,
                child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white.withOpacity(0.9)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Login'dan keyin rolni aniqlab mos ekranga yo'naltiradi.
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
    _load();
  }

  Future<void> _load() async {
    try {
      Api.me = Map<String, dynamic>.from(await Api.get('/auth/me'));
      setState(() {});
    } catch (e) {
      if (e == 'auth') {
        await Api.logout();
        if (mounted) {
          Navigator.pushReplacement(
              context, fadeRoute(const LoginScreen()));
        }
      } else {
        setState(() => err = '$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                Text('Ulanishda xato:\n$err',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: muted)),
                const SizedBox(height: 16),
                FilledButton(
                    onPressed: () {
                      setState(() => err = null);
                      _load();
                    },
                    child: const Text('Qayta urinish')),
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
      if (mounted) {
        Navigator.pushReplacement(context, fadeRoute(const Gate()));
      }
    } catch (e) {
      setState(() => err = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
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
                  const SizedBox(height: 10),
                  const AnimatedLogo(size: 92),
                  const SizedBox(height: 14),
                  const Wordmark(size: 30, base: Colors.white),
                  const SizedBox(height: 22),
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
                        const Text('Tizimga kirish',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: ink)),
                        const SizedBox(height: 4),
                        const Text('Hisobingiz bilan davom eting',
                            style: TextStyle(color: muted, fontSize: 13)),
                        const SizedBox(height: 18),
                        TextField(
                          controller: comp,
                          decoration: const InputDecoration(
                            labelText: 'Kompaniya kodi',
                            prefixIcon: Icon(Icons.business_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: login,
                          decoration: const InputDecoration(
                            labelText: 'Login',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: pass,
                          obscureText: hide,
                          onSubmitted: (_) => busy ? null : _login(),
                          decoration: InputDecoration(
                            labelText: 'Parol',
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
                          text: 'Kirish',
                          icon: Icons.login,
                          busy: busy,
                          onTap: _login,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('SalesGO · savdo agentlari uchun',
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
