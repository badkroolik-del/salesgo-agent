import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'theme.dart';
import 'ui.dart';
import 'mobile_cfg.dart';

/// ================= FONDA GPS TREK =================
/// Android foreground-servis (turi: location) — ilova yopilsa (ro'yxatdan surib tashlansa) ham ishlaydi,
/// telefon qayta yoqilganda o'zi ishga tushadi. Nuqtalar telefonda navbatda saqlanadi va internet
/// bo'lganda paket bilan yuboriladi (POST /api/gps). Google Play talabi: ruxsat so'rashdan oldin
/// «prominent disclosure» oynasi (LocationConsentScreen) va doimiy bildirishnoma.
enum TrackState { unknown, off, noConsent, noPermission, noBackground, gpsDisabled, on }

const _kConsent = 'loc_consent_v1';
const _kQueue = 'q_gps';
const _kQueueUid = 'q_gps_uid';
const _kLast = 'gps_last';
const privacyUrl = 'https://salesgo.uz/privacy.html';

class Tracker {
  static final state = ValueNotifier<TrackState>(TrackState.unknown);
  static final last = ValueNotifier<String?>(null);
  static bool _configured = false;
  static bool _asked = false;

  static bool get fieldRole {
    final r = Api.me?['role'];
    return r == 'agent' || r == 'delivery' || r == 'collector' || r == 'supervisor';
  }

  static Future<void> configure() async {
    // Web (brauzerdagi sinov versiyasi): fon servisi yo'q
    if (_configured || kIsWeb) return;
    _configured = true;
    try {
      await FlutterBackgroundService().configure(
        androidConfiguration: AndroidConfiguration(
          onStart: trackerMain,
          autoStart: false,
          autoStartOnBoot: true,
          isForegroundMode: true,
          initialNotificationTitle: 'SalesGO',
          initialNotificationContent: 'Marshrut yozilmoqda · Маршрут записывается',
          foregroundServiceNotificationId: 7301,
          foregroundServiceTypes: [AndroidForegroundType.location],
        ),
        iosConfiguration: IosConfiguration(autoStart: false, onForeground: trackerMain),
      );
    } catch (_) {}
  }

  static Future<bool> consented() async =>
      (await SharedPreferences.getInstance()).getBool(_kConsent) ?? false;

  static Future<void> setConsent(bool v) async =>
      (await SharedPreferences.getInstance()).setBool(_kConsent, v);

  static Future<TrackState> check() async {
    if (kIsWeb) return TrackState.unknown;
    try {
      if (!await consented()) return TrackState.noConsent;
      if (!(await Permission.locationWhenInUse.status).isGranted) return TrackState.noPermission;
      if (!(await Permission.locationAlways.status).isGranted) return TrackState.noBackground;
      if (!await Geolocator.isLocationServiceEnabled()) return TrackState.gpsDisabled;
      return (await FlutterBackgroundService().isRunning()) ? TrackState.on : TrackState.off;
    } catch (_) {
      return TrackState.off;
    }
  }

  static Future<void> refresh() async {
    state.value = await check();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.reload();
      last.value = sp.getString(_kLast);
    } catch (_) {}
  }

  /// Kirgandan keyin: rozilik → ruxsatlar → servis. Har sessiyada bir marta avtomatik.
  static Future<void> ensure(BuildContext context, {bool force = false}) async {
    if (!fieldRole || kIsWeb) return;
    if (_asked && !force) {
      await refresh();
      return;
    }
    _asked = true;
    await configure();
    // Boshqa xodim kirgan bo'lsa — eski navbatni tozalash (nuqtalar boshqa odamga yozilmasin)
    try {
      final sp = await SharedPreferences.getInstance();
      final uid = '${Api.me?['id'] ?? ''}';
      if ((sp.getString(_kQueueUid) ?? uid) != uid) await sp.remove(_kQueue);
      await sp.setString(_kQueueUid, uid);
    } catch (_) {}
    var st = await check();
    if (st == TrackState.noConsent) {
      if (!context.mounted) return;
      final okc = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
              fullscreenDialog: true, builder: (_) => const LocationConsentScreen()));
      if (okc != true) {
        state.value = TrackState.noConsent;
        return;
      }
      st = await check();
    }
    if (st == TrackState.noPermission || st == TrackState.noBackground || st == TrackState.gpsDisabled) {
      if (!context.mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const TrackerSetupScreen()));
      st = await check();
    }
    if (st == TrackState.off || st == TrackState.on) await start();
    await refresh();
  }

  static Future<void> start() async {
    if (kIsWeb) return;
    try {
      final s = FlutterBackgroundService();
      if (!await s.isRunning()) await s.startService();
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 500));
  }

  /// Chiqishda: servis navbatni yuborib to'xtaydi.
  static Future<void> stop() async {
    if (kIsWeb) return;
    try {
      FlutterBackgroundService().invoke('stop');
    } catch (_) {}
    state.value = TrackState.off;
  }

  /// Panel konfiguratsiyasi yangilanganda servisga xabar.
  static void pushConfig() {
    if (kIsWeb) return;
    try {
      FlutterBackgroundService().invoke('cfg');
    } catch (_) {}
  }

  static Future<int> pending() async {
    final sp = await SharedPreferences.getInstance();
    await sp.reload();
    return (sp.getStringList(_kQueue) ?? []).length;
  }
}

/// ============ Fon izolyatsiyasi (servis ichida ishlaydi) ============
@pragma('vm:entry-point')
Future<void> trackerMain(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  final sp = await SharedPreferences.getInstance();
  StreamSubscription<Position>? sub;
  Timer? flushT, pingT;
  Position? lastKept;
  Map<String, dynamic> cfg = {};
  String lang = 'uz';
  bool busy = false;
  final battery = Battery();

  String t(String uz, String ru) => lang == 'ru' ? ru : uz;
  num cn(String k, num d) => cfg[k] is num ? cfg[k] as num : (num.tryParse('${cfg[k]}') ?? d);
  String cs(String k, String d) => cfg[k] == null ? d : '${cfg[k]}';
  int mins(String hhmm) {
    final p = hhmm.split(':');
    return (int.tryParse(p[0]) ?? 0) * 60 + (p.length > 1 ? (int.tryParse(p[1]) ?? 0) : 0);
  }

  bool inWork() {
    final n = DateTime.now();
    final m = n.hour * 60 + n.minute;
    final a = mins(cs('work_from', '07:00')), b = mins(cs('work_to', '21:00'));
    return a <= b ? (m >= a && m <= b) : (m >= a || m <= b);
  }

  void note(String c) {
    try {
      (service as dynamic).setForegroundNotificationInfo(
          title: t('SalesGO — marshrut yozilmoqda', 'SalesGO — маршрут записывается'), content: c);
    } catch (_) {}
  }

  Future<void> loadCfg() async {
    await sp.reload();
    lang = sp.getString('lang') ?? 'uz';
    try {
      cfg = Map<String, dynamic>.from(jsonDecode(sp.getString('mobile_cfg') ?? '{}'));
    } catch (_) {
      cfg = {};
    }
  }

  Future<void> flush() async {
    if (busy) return;
    busy = true;
    try {
      await sp.reload();
      final token = sp.getString('token');
      if (token == null) return;
      var q = sp.getStringList(_kQueue) ?? [];
      while (q.isNotEmpty) {
        final n = q.length > 200 ? 200 : q.length;
        final batch = q.sublist(0, n).map((e) => jsonDecode(e)).toList();
        final r = await http
            .post(Uri.parse('${Api.base}/api/gps'),
                headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
                body: jsonEncode({'points': batch}))
            .timeout(const Duration(seconds: 25));
        if (r.statusCode == 401) {
          await sub?.cancel();
          service.stopSelf();
          return;
        }
        if (r.statusCode >= 300) break;
        await sp.reload();
        q = sp.getStringList(_kQueue) ?? [];
        q = q.length >= n ? q.sublist(n) : <String>[];
        await sp.setStringList(_kQueue, q);
      }
    } catch (_) {
      // internet yo'q — nuqtalar navbatda qoladi
    } finally {
      busy = false;
    }
  }

  Future<void> ping() async {
    try {
      await sp.reload();
      final token = sp.getString('token');
      if (token == null) return;
      final pi = await PackageInfo.fromPlatform();
      String dev = '';
      try {
        final a = await DeviceInfoPlugin().androidInfo;
        dev = '${a.manufacturer} ${a.model} · Android ${a.version.release}';
      } catch (_) {}
      int? bat;
      try {
        bat = await battery.batteryLevel;
      } catch (_) {}
      await http
          .post(Uri.parse('${Api.base}/api/mobile/devices/ping'),
              headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
              body: jsonEncode({
                'app': pi.version,
                'build': pi.buildNumber,
                'device': dev,
                'battery': bat,
                'pending_gps': (sp.getStringList(_kQueue) ?? []).length,
                'gps': true,
              }))
          .timeout(const Duration(seconds: 20));
    } catch (_) {}
  }

  Future<void> addPoint(Position p) async {
    if (!inWork()) {
      note(t('Ish vaqtidan tashqari — trek yozilmaydi', 'Вне рабочего времени — трек не пишется'));
      return;
    }
    final maxAcc = cn('gps_acc', 100).toDouble();
    if (p.accuracy > (maxAcc < 30 ? 30 : maxAcc)) return; // noaniq nuqta
    final prev = lastKept;
    if (prev != null) {
      final d = Geolocator.distanceBetween(prev.latitude, prev.longitude, p.latitude, p.longitude);
      final dt = p.timestamp.difference(prev.timestamp).inSeconds.abs();
      if (dt > 0 && d / dt > 55) return; // >200 km/soat — GPS sakrashi
    }
    lastKept = p;
    int? bat;
    try {
      bat = await battery.batteryLevel;
    } catch (_) {}
    final ts = DateTime.now();
    final pt = {
      'lat': double.parse(p.latitude.toStringAsFixed(6)),
      'lng': double.parse(p.longitude.toStringAsFixed(6)),
      'acc': p.accuracy.round(),
      'speed': p.speed,
      'spd': (p.speed * 3.6).round(),
      'bat': bat,
      'ts': ts.toIso8601String().substring(0, 19),
      'kind': 'route',
    };
    await sp.reload();
    final q = sp.getStringList(_kQueue) ?? [];
    q.add(jsonEncode(pt));
    if (q.length > 6000) q.removeRange(0, q.length - 6000);
    await sp.setStringList(_kQueue, q);
    final hm = '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';
    await sp.setString(_kLast, hm);
    note('${t('Oxirgi nuqta', 'Последняя точка')} $hm · ${t('navbatda', 'в очереди')} ${q.length}');
    if (q.length >= 30) unawaited(flush());
  }

  Future<void> startStream() async {
    await sub?.cancel();
    final settings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: cn('track_dist', 30).toInt(),
      intervalDuration: Duration(seconds: cn('track_int', 20).toInt().clamp(5, 600)),
    );
    sub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (p) => addPoint(p),
      onError: (_) => note(t('GPS o‘chiq yoki ruxsat yo‘q', 'GPS выключен или нет разрешения')),
    );
  }

  service.on('stop').listen((_) async {
    await sub?.cancel();
    flushT?.cancel();
    pingT?.cancel();
    await flush();
    service.stopSelf();
  });
  service.on('cfg').listen((_) async {
    await loadCfg();
    await startStream();
  });
  service.on('flush').listen((_) => flush());

  await loadCfg();
  if (sp.getString('token') == null) {
    service.stopSelf();
    return;
  }
  note(t('Trek yoqildi', 'Трек включён'));
  await startStream();
  flushT = Timer.periodic(const Duration(seconds: 60), (_) => flush());
  pingT = Timer.periodic(const Duration(minutes: 15), (_) => ping());
  unawaited(flush());
  unawaited(ping());
}

/// ============ Google Play: joylashuvdan foydalanish haqida ochiq tushuntirish ============
class LocationConsentScreen extends StatelessWidget {
  const LocationConsentScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final from = MobileCfg.workFrom, to = MobileCfg.workTo;
    Widget item(IconData ic, String txt) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: brand.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
                child: Icon(ic, color: brand, size: 20)),
            const SizedBox(width: 12),
            Expanded(child: Text(txt, style: const TextStyle(fontSize: 15, height: 1.4, color: ink))),
          ]),
        );
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(22, 22, 22, 10), children: [
              const Center(child: BrandLogo(height: 34)),
              const SizedBox(height: 26),
              Text(tr('Joylashuvdan fonda foydalanish', 'Использование геолокации в фоне'),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: ink)),
              const SizedBox(height: 16),
              item(Icons.route,
                  tr('SalesGO marshrutingiz va mijozlarga tashriflarni yozib borish uchun joylashuv ma’lumotlarini to‘playdi — ilova yopiq bo‘lsa yoki ishlatilmayotgan bo‘lsa ham.',
                      'SalesGO собирает данные о местоположении, чтобы записывать ваш маршрут и визиты к клиентам — даже когда приложение закрыто или не используется.')),
              item(Icons.schedule,
                  tr('Ma’lumot faqat ish vaqtida ($from–$to) yig‘iladi va faqat ish beruvchi kompaniyangizga yuboriladi. Uchinchi shaxslarga sotilmaydi va berilmaydi.',
                      'Данные собираются только в рабочее время ($from–$to) и передаются только вашей компании-работодателю. Мы не продаём и не передаём их третьим лицам.')),
              item(Icons.notifications_active_outlined,
                  tr('Yozish davomida bildirishnomalar panelida «SalesGO — marshrut yozilmoqda» ko‘rinib turadi. Akkauntdan chiqsangiz yozish to‘xtaydi.',
                      'Во время записи в панели уведомлений видно «SalesGO — маршрут записывается». При выходе из аккаунта запись останавливается.')),
              item(Icons.battery_charging_full,
                  tr('Batareyani tejash uchun nuqta faqat harakatlanganda yoki belgilangan oraliqda olinadi.',
                      'Для экономии батареи точка берётся только при движении или с заданным интервалом.')),
              TextButton.icon(
                onPressed: () => launchUrl(Uri.parse(privacyUrl), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.privacy_tip_outlined),
                label: Text(tr('Maxfiylik siyosati', 'Политика конфиденциальности')),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
            child: Column(children: [
              GradientButton(
                text: tr('Roziman, davom etish', 'Согласен и продолжить'),
                icon: Icons.check,
                onTap: () async {
                  await Tracker.setConsent(true);
                  if (context.mounted) Navigator.pop(context, true);
                },
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(tr('Hozir emas', 'Не сейчас'), style: const TextStyle(color: muted)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// ============ Ruxsatlarni bosqichma-bosqich sozlash ============
class TrackerSetupScreen extends StatefulWidget {
  const TrackerSetupScreen({super.key});
  @override
  State<TrackerSetupScreen> createState() => _TrackerSetupScreenState();
}

class _TrackerSetupScreenState extends State<TrackerSetupScreen> with WidgetsBindingObserver {
  bool loc = false, always = false, notif = false, gps = false, battery = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      loc = (await Permission.locationWhenInUse.status).isGranted;
      always = (await Permission.locationAlways.status).isGranted;
      notif = (await Permission.notification.status).isGranted;
      gps = await Geolocator.isLocationServiceEnabled();
      battery = (await Permission.ignoreBatteryOptimizations.status).isGranted;
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Widget _step(int n, bool done, String title, String sub, String btn, VoidCallback? onTap, {bool optional = false}) {
    return Panel(
      padding: const EdgeInsets.all(14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: done ? ok : (optional ? warn : brand), shape: BoxShape.circle),
          child: done
              ? const Icon(Icons.check, color: Colors.white, size: 18)
              : Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: ink)),
            const SizedBox(height: 3),
            Text(sub, style: const TextStyle(color: muted, fontSize: 14, height: 1.35)),
            if (!done && onTap != null) ...[
              const SizedBox(height: 8),
              FilledButton(onPressed: onTap, child: Text(btn)),
            ],
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = loc && always && gps;
    return Scaffold(
      appBar: AppBar(title: Text(tr('GPS ni sozlash', 'Настройка GPS'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(
            tr('Marshrut ilova yopiq bo‘lsa ham yozilishi uchun quyidagi ruxsatlar kerak.',
                'Чтобы маршрут записывался даже при закрытом приложении, нужны эти разрешения.'),
            style: const TextStyle(color: muted, fontSize: 14.5)),
        const SizedBox(height: 14),
        _step(1, loc, tr('Joylashuvga ruxsat', 'Доступ к геолокации'),
            tr('«Ilovadan foydalanganda» ni tanlang', 'Выберите «При использовании приложения»'), tr('Ruxsat berish', 'Разрешить'),
            () async {
          await Permission.locationWhenInUse.request();
          _refresh();
        }),
        const SizedBox(height: 10),
        _step(2, always, tr('«Har doim ruxsat berish»', '«Разрешать всегда»'),
            tr('Ochilgan oynada «Har doim ruxsat berish»ni tanlang — shunda ilova yopiq bo‘lsa ham trek yoziladi.',
                'В открывшемся окне выберите «Разрешать всегда» — тогда трек пишется и при закрытом приложении.'),
            tr('Sozlash', 'Настроить'), loc
                ? () async {
                    final r = await Permission.locationAlways.request();
                    if (!r.isGranted) await openAppSettings();
                    _refresh();
                  }
                : null),
        const SizedBox(height: 10),
        _step(3, notif, tr('Bildirishnomalar', 'Уведомления'),
            tr('Trek yozilayotganini ko‘rsatuvchi bildirishnoma uchun.', 'Для уведомления о том, что идёт запись маршрута.'),
            tr('Ruxsat berish', 'Разрешить'), () async {
          await Permission.notification.request();
          _refresh();
        }),
        const SizedBox(height: 10),
        _step(4, gps, tr('Telefonda GPS yoqilgan', 'GPS на телефоне включён'),
            tr('Joylashuv (GPS) xizmatini yoqing.', 'Включите службу геолокации (GPS).'), tr('Yoqish', 'Включить'), () async {
          await Geolocator.openLocationSettings();
          _refresh();
        }),
        const SizedBox(height: 10),
        _step(
            5,
            battery,
            tr('Batareya: cheklovsiz', 'Батарея: без ограничений'),
            tr('Ilova sozlamalari → Batareya → «Cheklovsiz». Xiaomi/Redmi, Huawei, Tecno da yana «Avtozapusk»ni yoqing — aks holda telefon ilovani yopib qo‘yishi mumkin.',
                'Настройки приложения → Батарея → «Без ограничений». На Xiaomi/Redmi, Huawei, Tecno включите также «Автозапуск» — иначе телефон может закрывать приложение.'),
            tr('Sozlamalarni ochish', 'Открыть настройки'), () async {
          await openAppSettings();
          _refresh();
        }, optional: true),
        const SizedBox(height: 20),
        GradientButton(
          text: ready ? tr('Tayyor — trekni yoqish', 'Готово — включить трек') : tr('Keyinroq', 'Позже'),
          icon: ready ? Icons.gps_fixed : Icons.schedule,
          onTap: () async {
            if (ready) await Tracker.start();
            await Tracker.refresh();
            if (context.mounted) Navigator.pop(context);
          },
        ),
      ]),
    );
  }
}

/// ============ Holat banneri (bosh sahifada) ============
class TrackerBanner extends StatelessWidget {
  const TrackerBanner({super.key});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TrackState>(
      valueListenable: Tracker.state,
      builder: (_, st, __) {
        if (st == TrackState.on || st == TrackState.unknown || !Tracker.fieldRole) return const SizedBox.shrink();
        final txt = st == TrackState.noConsent
            ? tr('Trek o‘chiq — rozilik berilmagan', 'Трек выключен — нет согласия')
            : st == TrackState.noPermission || st == TrackState.noBackground
                ? tr('Trek o‘chiq — «Har doim» ruxsati kerak', 'Трек выключен — нужно разрешение «Всегда»')
                : st == TrackState.gpsDisabled
                    ? tr('Telefonda GPS o‘chiq', 'На телефоне выключен GPS')
                    : tr('Trek o‘chiq', 'Трек выключен');
        return Material(
          color: danger.withOpacity(0.08),
          child: InkWell(
            onTap: () => Tracker.ensure(context, force: true),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(children: [
                  const Icon(Icons.gps_off, color: danger, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(txt, style: const TextStyle(color: danger, fontWeight: FontWeight.w700, fontSize: 14))),
                  Text(tr('Sozlash', 'Настроить'), style: const TextStyle(color: brand, fontWeight: FontWeight.w800, fontSize: 14)),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}
