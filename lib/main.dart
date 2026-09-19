import 'package:flutter/material.dart';
import 'api.dart';
import 'agent.dart';
import 'roles.dart';

const brand = Color(0xFF12B981);

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
      theme: ThemeData(
        colorSchemeSeed: brand,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF1F5F9),
      ),
      home: Api.token == null ? const LoginScreen() : const Gate(),
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
              context, MaterialPageRoute(builder: (_) => const LoginScreen()));
        }
      } else {
        setState(() => err = '\$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (err != null) {
      return Scaffold(body: Center(child: Text('Xato: \$err')));
    }
    if (Api.me == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final role = Api.me!['role'];
    switch (role) {
      case 'agent':
        return const AgentHome();
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
  String? err;

  Future<void> _login() async {
    setState(() {
      busy = true;
      err = null;
    });
    try {
      await Api.login(comp.text.trim(), login.text.trim(), pass.text);
      if (mounted) {
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const Gate()));
      }
    } catch (e) {
      setState(() => err = '\$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [Color(0xFF062A1F), Color(0xFF0B3D2C), Color(0xFF083A49)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight)),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Sales',
                      style: TextStyle(
                          fontSize: 30, fontWeight: FontWeight.w900),
                      textAlign: TextAlign.center),
                  const Text('GO',
                      style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          color: brand)),
                  const SizedBox(height: 18),
                  _field(comp, 'Kompaniya kodi'),
                  _field(login, 'Login'),
                  _field(pass, 'Parol', obscure: true),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: busy ? null : _login,
                      style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Kirish',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  if (err != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(err!,
                          style: const TextStyle(color: Colors.red)),
                    ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, {bool obscure = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        obscureText: obscure,
        decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder()),
      ),
    );
  }
}
