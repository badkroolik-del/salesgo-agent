import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'theme.dart';
import 'ui.dart';
import 'agent.dart';
import 'roles.dart';
import 'tracker.dart';
import 'mobile_cfg.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.loadToken();
  await loadLang();
  await MobileCfg.load();
  await Tracker.configure();
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
        title: 'SalesGO SFA',
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
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 3),
            const Center(child: BrandLogo(height: 78, full: true)),
            const Spacer(flex: 2),
            const SizedBox(
                height: 26, width: 26,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: brandGreen)),
            const SizedBox(height: 18),
            Text(tr('Savdo — harakatda', 'Продажи — в движении'),
                style: const TextStyle(color: muted, fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 28),
          ],
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
  bool _started = false;
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

  /// Paneldan ilova sozlamalari (majburiyatlar) + fonda GPS (rozilik → ruxsatlar → servis).
  Future<void> _afterLogin() async {
    final changed = await MobileCfg.refresh();
    if (changed) Tracker.pushConfig();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Tracker.ensure(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (Api.token == null) return const LoginScreen();
    if (Api.me != null && !_started) {
      _started = true;
      _afterLogin();
    }
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

  /// Demo kirish: kompaniya `demo`, parol serverdagi demo parolidan biri.
  Future<void> _demo(String who) async {
    comp.text = 'demo';
    login.text = who;
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      err = null;
    });
    Object? last;
    for (final p in const ['demo123', '12345']) {
      try {
        await Api.login('demo', who, p);
        pass.text = p;
        Api.me = null;
        if (mounted) {
          Navigator.pushReplacement(
              context, MaterialPageRoute(builder: (_) => const Gate()));
        }
        return;
      } catch (e) {
        last = e;
      }
    }
    if (mounted) {
      setState(() {
        err = '$last';
        busy = false;
      });
    }
  }

  Widget _demoBtn(String who, IconData icon, String uz, String ru) => Expanded(
        child: OutlinedButton.icon(
          onPressed: busy ? null : () => _demo(who),
          icon: Icon(icon, color: brand, size: 20),
          label: Text(tr(uz, ru),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: brand, fontWeight: FontWeight.w700, fontSize: 14)),
          style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              side: const BorderSide(color: line),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        ),
      );

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
      backgroundColor: const Color(0xFFF4F7FB),
      body: Container(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  const BrandLogo(height: 58, full: true),
                  const SizedBox(height: 26),
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
                        const SizedBox(height: 10),
                        // Demo: har bir rolni o'rnatmasdan ko'rish (web versiya va Play tekshiruvchilari uchun)
                        Text(tr('Demo (sinov) kirish', 'Демо (тест) вход'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: muted, fontWeight: FontWeight.w700, fontSize: 14)),
                        const SizedBox(height: 8),
                        Row(children: [
                          _demoBtn('vali', Icons.person_pin_circle_outlined, 'Agent', 'Агент'),
                          const SizedBox(width: 8),
                          _demoBtn('akmal', Icons.local_shipping_outlined, 'Dostavka', 'Доставка'),
                        ]),
                        const SizedBox(height: 8),
                        Row(children: [
                          _demoBtn('sher', Icons.account_balance_wallet_outlined, 'Inkassator', 'Инкассатор'),
                          const SizedBox(width: 8),
                          _demoBtn('super', Icons.supervisor_account_outlined, 'Supervayzer', 'Супервайзер'),
                        ]),
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
                      tr('SalesGO SFA · savdo jamoasi uchun',
                          'SalesGO SFA · для торговой команды'),
                      style: const TextStyle(color: muted, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextButton(
                      onPressed: () => launchUrl(Uri.parse(privacyUrl),
                          mode: LaunchMode.externalApplication),
                      child: Text(tr('Maxfiylik siyosati', 'Политика конфиденциальности'),
                          style: const TextStyle(color: brand, fontSize: 13))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
