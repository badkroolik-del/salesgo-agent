import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'api.dart';
import 'theme.dart';
import 'ui.dart';
import 'maps.dart';
import 'main.dart';
import 'sync.dart';
import 'share_util.dart';

String _today() => DateTime.now().toIso8601String().substring(0, 10);

void snack(BuildContext c, String s) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(s)));

// ================= SHELL (pastki navigatsiya + avto GPS) =================
class AgentShell extends StatefulWidget {
  const AgentShell({super.key});
  @override
  State<AgentShell> createState() => _AgentShellState();
}

class _AgentShellState extends State<AgentShell> {
  int idx = 0;
  Timer? gpsTimer;
  bool gpsOn = false;

  @override
  void initState() {
    super.initState();
    _startGps();
  }

  @override
  void dispose() {
    gpsTimer?.cancel();
    super.dispose();
  }

  Future<void> _startGps() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      if (p == LocationPermission.denied ||
          p == LocationPermission.deniedForever) return;
      setState(() => gpsOn = true);
      _sendGps();
      gpsTimer =
          Timer.periodic(const Duration(seconds: 60), (_) => _sendGps());
    } catch (_) {}
  }

  Future<void> _sendGps() async {
    try {
      final pos = await Geolocator.getCurrentPosition();
      await Api.post('/api/gps', {
        'points': [
          {
            'lat': pos.latitude,
            'lng': pos.longitude,
            'speed': pos.speed,
            'ts': DateTime.now().toIso8601String().substring(0, 19),
          }
        ]
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      DashboardTab(gpsOn: gpsOn, onGoto: (i) => setState(() => idx = i)),
      const ClientsTab(),
      const OrdersTab(),
      const AgentReportsTab(),
      const ProfileTab(),
    ];
    return Scaffold(
      body: IndexedStack(index: idx, children: tabs),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
            gradient: navGradient, boxShadow: softShadow),
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            backgroundColor: Colors.transparent,
            elevation: 0,
            indicatorColor: Colors.white.withOpacity(0.24),
            labelTextStyle: MaterialStateProperty.all(const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
            iconTheme: MaterialStateProperty.resolveWith((s) => IconThemeData(
                color: s.contains(MaterialState.selected)
                    ? Colors.white
                    : Colors.white.withOpacity(0.7))),
          ),
          child: NavigationBar(
            backgroundColor: Colors.transparent,
            selectedIndex: idx,
            onDestinationSelected: (i) => setState(() => idx = i),
            destinations: [
              NavigationDestination(
                  icon: const Icon(Icons.dashboard_outlined),
                  selectedIcon: const Icon(Icons.dashboard),
                  label: tr('Bosh', 'Главная')),
              NavigationDestination(
                  icon: const Icon(Icons.storefront_outlined),
                  selectedIcon: const Icon(Icons.storefront),
                  label: tr('Mijozlar', 'Клиенты')),
              NavigationDestination(
                  icon: const Icon(Icons.receipt_long_outlined),
                  selectedIcon: const Icon(Icons.receipt_long),
                  label: tr('Zakazlar', 'Заказы')),
              NavigationDestination(
                  icon: const Icon(Icons.insert_chart_outlined),
                  selectedIcon: const Icon(Icons.insert_chart),
                  label: tr('Hisobot', 'Отчёт')),
              NavigationDestination(
                  icon: const Icon(Icons.person_outline),
                  selectedIcon: const Icon(Icons.person),
                  label: tr('Profil', 'Профиль')),
            ],
          ),
        ),
      ),
    );
  }
}

// ================= DASHBOARD =================
class DashboardTab extends StatefulWidget {
  final bool gpsOn;
  final void Function(int) onGoto;
  const DashboardTab({super.key, required this.gpsOn, required this.onGoto});
  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  bool loading = true;
  bool refreshing = false;
  num salesToday = 0, ordersToday = 0, routeToday = 0, debtors = 0;
  num visitsToday = 0;
  List drafts = [];
  List debtorList = [];
  List route = [];
  Set doneIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final o = await Api.get('/api/orders?d1=${_today()}&d2=${_today()}');
      final rt = await Api.get('/api/my-route');
      final c = await Api.get('/api/clients?limit=500');
      final items = (o['items'] ?? []) as List;
      final cl = (c['items'] ?? []) as List;
      salesToday = asNum(o['sum']);
      ordersToday = asNum(o['count'] ?? items.length);
      route = (rt['items'] ?? []) as List;
      routeToday = route.length;
      // bugungi marshrutdagi qarzdor do'konlar (hammasi emas)
      final routeIds = route.map((e) => e['id']).toSet();
      debtorList = cl
          .where((x) =>
              asNum(x['balance']) > 0 && routeIds.contains(x['id']))
          .toList()
        ..sort((a, b) => asNum(b['balance']).compareTo(asNum(a['balance'])));
      debtors = debtorList.length;
      doneIds = items.map((e) => e['client_id']).toSet();
      try {
        final k = await Api.get('/api/my-kpi');
        visitsToday = asNum(k['visits_today']);
      } catch (_) {}
      try {
        final dr = await Api.get('/api/orders?status=draft&limit=50');
        drafts = (dr['items'] ?? []) as List;
      } catch (_) {
        drafts = [];
      }
      _sortRoute(null);
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  void _sortRoute(Position? pos) {
    double dist(x) {
      if (pos == null || x['lat'] == null) return 1e12;
      return Geolocator.distanceBetween(pos.latitude, pos.longitude,
          asNum(x['lat']).toDouble(), asNum(x['lng']).toDouble());
    }

    route.sort((a, b) {
      final da = doneIds.contains(a['id']) ? 1 : 0;
      final db2 = doneIds.contains(b['id']) ? 1 : 0;
      if (da != db2) return da - db2; // qilinmagalar tepada, qilinganlar pastda
      if (pos != null) return dist(a).compareTo(dist(b));
      return '${a['name']}'.compareTo('${b['name']}');
    });
  }

  Future<void> _refresh() async {
    setState(() => refreshing = true);
    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition();
    } catch (_) {}
    await _load();
    _sortRoute(pos);
    if (mounted) setState(() => refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final name = '${Api.me?['name'] ?? 'Agent'}';
    return RefreshIndicator(
      color: brand,
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          GradientHeader(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const AnimatedWordmark(size: 20, base: Colors.white),
                    const Spacer(),
                    IconButton(
                      tooltip: tr('Aksiyalar', 'Акции'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.push(
                          context, fadeRoute(const PromosScreen())),
                      icon: const Icon(Icons.local_offer_outlined,
                          color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(20)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(widget.gpsOn ? Icons.gps_fixed : Icons.gps_off,
                            color: Colors.white, size: 15),
                        const SizedBox(width: 5),
                        Text(widget.gpsOn ? 'GPS' : tr('GPS o‘chiq', 'GPS выкл'),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text('${greeting()},',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.85), fontSize: 14)),
                Text(name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('${weekdayName(todayWeekday())} · ${tr('bugungi marshrut', 'сегодняшний маршрут')}: $routeToday',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                      child: StatCard(
                          compact: true,
                          icon: Icons.payments,
                          label: tr('Savdo', 'Продажа'),
                          value: salesToday,
                          isMoney: true,
                          color: brand)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: StatCard(
                          compact: true,
                          icon: Icons.receipt_long,
                          label: tr('Zakazlar', 'Заказы'),
                          value: ordersToday,
                          color: info)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: StatCard(
                          compact: true,
                          icon: Icons.route,
                          label: tr('Do‘konlar', 'Точки'),
                          value: routeToday,
                          color: accent)),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: StatCard(
                          compact: true,
                          icon: Icons.place,
                          label: tr('Vizitlar', 'Визиты'),
                          value: visitsToday,
                          color: violet)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: StatCard(
                          compact: true,
                          icon: Icons.error_outline,
                          label: tr('Qarzdor', 'Должники'),
                          value: debtors,
                          color: danger,
                          onTap: () => Navigator.push(
                              context,
                              fadeRoute(DebtorsScreen(clients: debtorList))))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: StatCard(
                          compact: true,
                          icon: Icons.drafts_outlined,
                          label: tr('Chernovik', 'Черновики'),
                          value: drafts.length,
                          color: warn,
                          onTap: () async {
                            await Navigator.push(context,
                                fadeRoute(const ChernovikScreen()));
                            _load();
                          })),
                ]),
                const SizedBox(height: 16),
                // KATTA sinxron tugmasi — bosilsa server bilan sinxron
                _BigSyncButton(onDone: _load),
                const SizedBox(height: 8),
                Center(
                  child: TextButton.icon(
                    onPressed: () async {
                      await Navigator.push(context,
                          fadeRoute(const OfflineQueueScreen()));
                      _load();
                    },
                    icon: const Icon(Icons.checklist_rtl,
                        size: 18, color: brand),
                    label: Text(
                        tr('Navbat (yuborilmagan zakazlar)',
                            'Очередь (неотправленные)'),
                        style: const TextStyle(
                            color: brand, fontWeight: FontWeight.w700)),
                  ),
                ),
                SectionTitle(tr('Bugungi marshrut', 'Маршрут на сегодня')),
                if (loading)
                  const Column(children: [
                    Shimmer(height: 64),
                    SizedBox(height: 10),
                    Shimmer(height: 64),
                  ])
                else if (route.isEmpty)
                  Panel(
                      child: EmptyState(
                          text: tr('Bugun do‘kon yo‘q', 'Точек на сегодня нет')))
                else
                  ...route.map((c) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _RouteTile(
                          c,
                          done: doneIds.contains(c['id']),
                          onTap: () async {
                            await Navigator.push(context,
                                fadeRoute(ClientCardScreen(client: c)));
                            _load();
                          },
                        ),
                      )),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============ OFLAYN NAVBAT (yuborilmagan zakazlar, 1/2 ptichka) ============
class OfflineQueueScreen extends StatefulWidget {
  const OfflineQueueScreen({super.key});
  @override
  State<OfflineQueueScreen> createState() => _OfflineQueueScreenState();
}

class _OfflineQueueScreenState extends State<OfflineQueueScreen> {
  List<Map<String, dynamic>> items = [];
  bool loading = true;
  bool syncing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    items = await SyncStore.listOrders();
    if (mounted) setState(() => loading = false);
  }

  Future<void> _sync() async {
    if (syncing) return;
    setState(() => syncing = true);
    Map<String, int> res = {};
    try {
      res = await SyncStore.flush(null);
    } catch (_) {}
    await _load();
    if (!mounted) return;
    setState(() => syncing = false);
    final left = res['left'] ?? items.length;
    snack(
        context,
        left == 0
            ? tr('Hammasi yuborildi ✓✓', 'Всё отправлено ✓✓')
            : tr('Qisman yuborildi, $left qoldi',
                'Отправлено частично, осталось $left'));
  }

  Future<void> _edit(Map<String, dynamic> o) async {
    String pay = '${o['pay_type'] ?? 'cash'}';
    final comment = TextEditingController(text: '${o['comment'] ?? ''}');
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        Widget chip(String label, String val) {
          final sel = pay == val;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(label),
              selected: sel,
              onSelected: (_) => setS(() => pay = val),
              selectedColor: brand,
              labelStyle: TextStyle(
                  color: sel ? Colors.white : ink,
                  fontWeight: FontWeight.w600),
            ),
          );
        }

        return Padding(
          padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${o['client_name'] ?? tr('Zakaz', 'Заказ')}',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('${money(asNum(o['total']))} · ${(o['items'] as List?)?.length ?? 0} ${tr('tovar', 'товар')}',
                  style: const TextStyle(color: muted)),
              const SizedBox(height: 14),
              Text(tr('To‘lov turi', 'Вид оплаты'),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(children: [
                chip(tr('Naqd', 'Наличные'), 'cash'),
                chip(tr('O‘tkazma', 'Перевод'), 'transfer'),
                chip(tr('Qarz', 'Долг'), 'debt'),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: comment,
                decoration: InputDecoration(
                  labelText: tr('Izoh', 'Комментарий'),
                  prefixIcon: const Icon(Icons.comment_outlined),
                ),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await SyncStore.removeOrder('${o['client_uuid']}');
                      await _load();
                    },
                    icon: const Icon(Icons.delete_outline, color: danger),
                    label: Text(tr('O‘chirish', 'Удалить'),
                        style: const TextStyle(color: danger)),
                    style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: danger),
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: GradientButton(
                    text: tr('Saqlash', 'Сохранить'),
                    icon: Icons.check,
                    onTap: () async {
                      final nb = Map<String, dynamic>.from(o);
                      nb['pay_type'] = pay;
                      nb['comment'] = comment.text.trim();
                      Navigator.pop(ctx);
                      await SyncStore.updateOrder('${o['client_uuid']}', nb);
                      await _load();
                    },
                  ),
                ),
              ]),
            ],
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(children: [
        GradientHeader(
          child: Row(children: [
            IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back, color: Colors.white)),
            Expanded(
              child: Text(tr('Yuborilmagan navbat', 'Очередь отправки'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
        Expanded(
          child: loading
              ? const ListShimmer()
              : (items.isEmpty
                  ? EmptyState(
                      icon: Icons.cloud_done_outlined,
                      text: tr('Navbat bo‘sh — hammasi yuborilgan ✓✓',
                          'Очередь пуста — всё отправлено ✓✓'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final o = items[i];
                        final cnt = (o['items'] as List?)?.length ?? 0;
                        return Panel(
                          padding: const EdgeInsets.all(14),
                          onTap: () => _edit(o),
                          child: Row(children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                  color: warn.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(12)),
                              child: const Icon(Icons.schedule, color: warn),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      '${o['client_name'] ?? tr('Mijoz', 'Клиент')}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: ink)),
                                  const SizedBox(height: 2),
                                  Text(
                                      '${money(asNum(o['total']))} · $cnt ${tr('tovar', 'товар')} · ${payLabel('${o['pay_type']}')}',
                                      style: const TextStyle(
                                          color: muted, fontSize: 12.5)),
                                ],
                              ),
                            ),
                            // 1 ptichka = lokal saqlangan, hali yuborilmagan
                            Column(children: [
                              const Icon(Icons.check,
                                  color: muted, size: 18),
                              Text(tr('saqlandi', 'сохранён'),
                                  style: const TextStyle(
                                      color: muted, fontSize: 10)),
                            ]),
                          ]),
                        );
                      },
                    )),
        ),
      ]),
      bottomNavigationBar: items.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: GradientButton(
                  text: syncing
                      ? tr('Yuborilmoqda…', 'Отправка…')
                      : tr('Sinxron qilish (✓✓)', 'Синхронизировать (✓✓)'),
                  icon: Icons.cloud_upload,
                  busy: syncing,
                  onTap: _sync,
                ),
              ),
            ),
    );
  }
}

// KATTA sinxron tugmasi: uzun bosilganda navbatdagi zakaz/rasmlarni serverga
// yuboradi va jarayonni (nechta zakaz / nechta rasm) ko'rsatadi.
class _BigSyncButton extends StatefulWidget {
  final Future<void> Function() onDone;
  const _BigSyncButton({required this.onDone});
  @override
  State<_BigSyncButton> createState() => _BigSyncButtonState();
}

class _BigSyncButtonState extends State<_BigSyncButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));
  bool syncing = false;
  int done = 0, total = 0, sentO = 0, sentP = 0, pending = 0, po = 0, pp = 0;

  @override
  void initState() {
    super.initState();
    _refreshPending();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _refreshPending() async {
    final o = await SyncStore.pendingOrders();
    final p = await SyncStore.pendingPhotos();
    if (mounted) {
      setState(() {
        po = o;
        pp = p;
        pending = o + p;
      });
    }
  }

  Future<void> _startSync() async {
    if (syncing) return;
    setState(() {
      syncing = true;
      done = 0;
      total = 0;
      sentO = 0;
      sentP = 0;
    });
    _c.repeat();
    Map<String, int> res = {'orders': 0, 'photos': 0};
    try {
      res = await SyncStore.flush((d, t, o, p) {
        if (mounted) {
          setState(() {
            done = d;
            total = t;
            sentO = o;
            sentP = p;
          });
        }
      });
    } catch (_) {}
    _c.stop();
    _c.value = 0;
    await _refreshPending();
    await widget.onDone();
    if (!mounted) return;
    setState(() => syncing = false);
    final o = res['orders'] ?? 0, ph = res['photos'] ?? 0;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.cloud_done, color: ok, size: 42),
        title: Text(tr('Sinxron tugadi', 'Синхронизация завершена'),
            textAlign: TextAlign.center),
        content: Text(
          (o == 0 && ph == 0)
              ? tr('Hammasi allaqachon sinxron ✓',
                  'Всё уже синхронизировано ✓')
              : '${tr('Zakazlar', 'Заказы')}: $o\n${tr('Rasmlar', 'Фото')}: $ph',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        actions: [
          Center(
            child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK')),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _startSync,
      child: Container(
        height: 64,
        width: double.infinity,
        decoration: BoxDecoration(
            gradient: brandGradient,
            borderRadius: BorderRadius.circular(18),
            boxShadow: softShadow),
        child: syncing
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    RotationTransition(
                        turns: _c,
                        child: const Icon(Icons.sync,
                            color: Colors.white, size: 22)),
                    const SizedBox(width: 10),
                    Text(
                        total == 0
                            ? tr('Sinxronlanmoqda…', 'Синхронизация…')
                            : '$done/$total',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 16)),
                  ]),
                  const SizedBox(height: 2),
                  Text(
                      '${tr('Zakaz', 'Заказы')}: $sentO   ·   ${tr('Rasm', 'Фото')}: $sentP',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_upload, color: Colors.white, size: 26),
                  const SizedBox(width: 12),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(tr('Sinxronlash', 'Синхронизация'),
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 16.5)),
                      if (pending > 0)
                        Text(
                            '${tr('Zakaz', 'Заказы')}: $po · ${tr('Rasm', 'Фото')}: $pp',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

class _RouteTile extends StatelessWidget {
  final Map c;
  final bool done;
  final VoidCallback onTap;
  const _RouteTile(this.c, {required this.done, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final bal = asNum(c['balance']);
    return Panel(
      padding: const EdgeInsets.all(12),
      color: done ? const Color(0xFFF6FBF8) : Colors.white,
      onTap: onTap,
      child: Row(children: [
        Avatar('${c['name'] ?? '?'}', size: 42),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${c['name'] ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: done ? muted : ink,
                      decoration:
                          done ? TextDecoration.lineThrough : null)),
              const SizedBox(height: 2),
              Text('${c['address'] ?? c['territory_name'] ?? '-'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: muted, fontSize: 12.5)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        done
            ? Pill(tr('Bajarildi', 'Готово'), color: ok, icon: Icons.check)
            : (bal > 0
                ? Pill(shortMoney(bal), color: danger, icon: Icons.trending_up)
                : const Icon(Icons.chevron_right, color: muted)),
      ]),
    );
  }
}

class DebtorsScreen extends StatefulWidget {
  final List? clients; // berilgan bo'lsa (bugungi marshrut qarzdorlari)
  const DebtorsScreen({super.key, this.clients});
  @override
  State<DebtorsScreen> createState() => _DebtorsScreenState();
}

class _DebtorsScreenState extends State<DebtorsScreen> {
  List items = [];
  bool loading = true;
  @override
  void initState() {
    super.initState();
    if (widget.clients != null) {
      items = widget.clients!;
      loading = false;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final d = await Api.get('/api/clients?limit=500');
      items = ((d['items'] ?? []) as List)
          .where((c) => asNum(c['balance']) > 0)
          .toList()
        ..sort((a, b) => asNum(b['balance']).compareTo(asNum(a['balance'])));
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final total = items.fold<num>(0, (a, c) => a + asNum(c['balance']));
    return Scaffold(
      body: Column(children: [
        GradientHeader(
          padding: const EdgeInsets.fromLTRB(8, 4, 18, 20),
          child: Row(children: [
            IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back, color: Colors.white)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('Qarzdorlar', 'Должники'),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800)),
                  Text('${items.length} · ${money(total)}',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.9), fontSize: 13)),
                ],
              ),
            ),
          ]),
        ),
        Expanded(
          child: loading
              ? const ListShimmer()
              : items.isEmpty
                  ? EmptyState(
                      icon: Icons.check_circle_outline,
                      text: tr('Qarzdor yo‘q', 'Должников нет'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final c = items[i];
                        return Panel(
                          padding: const EdgeInsets.all(12),
                          onTap: () => Navigator.push(context,
                              fadeRoute(ClientCardScreen(client: c))),
                          child: Row(children: [
                            Avatar('${c['name'] ?? '?'}'),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${c['name'] ?? ''}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: ink)),
                                  Text('${c['address'] ?? '-'}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: muted, fontSize: 12.5)),
                                ],
                              ),
                            ),
                            Text(money(asNum(c['balance'])),
                                style: const TextStyle(
                                    color: danger,
                                    fontWeight: FontWeight.w800)),
                          ]),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}

String payLabel(String p) {
  switch (p) {
    case 'cash':
      return tr('Naqd', 'Наличные');
    case 'transfer':
      return tr('O‘tkazma', 'Перевод');
    case 'debt':
      return tr('Qarz', 'Долг');
    default:
      return p;
  }
}

String statusLabel(String s) {
  switch (s) {
    case 'new':
      return tr('Yangi', 'Новый');
    case 'collected':
      return tr('Yig‘ilgan', 'Собран');
    case 'shipped':
      return tr('Yo‘lda', 'В пути');
    case 'delivered':
      return tr('Yetkazildi', 'Доставлен');
    case 'canceled':
      return tr('Bekor', 'Отменён');
    case 'returned':
      return tr('Vozvrat', 'Возврат');
    default:
      return s;
  }
}

Color statusColor(String s) {
  switch (s) {
    case 'delivered':
      return ok;
    case 'canceled':
      return danger;
    case 'returned':
      return violet;
    case 'shipped':
      return info;
    case 'collected':
      return warn;
    default:
      return muted;
  }
}

class OrderTile extends StatelessWidget {
  final Map o;
  final VoidCallback? onTap;
  final bool history; // mijoz tarixida: sana + receipt ikon (client_name yo'q)
  const OrderTile(this.o, {super.key, this.onTap, this.history = false});
  @override
  Widget build(BuildContext context) {
    final status = '${o['status'] ?? 'new'}';
    final dateRaw = '${o['created_at'] ?? o['delivery_date'] ?? ''}';
    final date = dateRaw.length >= 10 ? dateRaw.substring(0, 10) : dateRaw;
    final title =
        history ? (date.isNotEmpty ? date : '#${o['id']}') : '${o['client_name'] ?? tr('Mijoz', 'Клиент')}';
    return Panel(
      padding: const EdgeInsets.all(12),
      onTap: onTap,
      child: Row(
        children: [
          history
              ? Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: statusColor(status).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.receipt_long,
                      color: statusColor(status), size: 20),
                )
              : Avatar('${o['client_name'] ?? '?'}', size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: ink)),
                const SizedBox(height: 2),
                Text(
                    history
                        ? '#${o['id']} · ${payLabel('${o['pay_type']}')}'
                        : '#${o['id']} · ${payLabel('${o['pay_type']}')}',
                    style: const TextStyle(color: muted, fontSize: 12)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(money(asNum(o['total'])),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: ink)),
              const SizedBox(height: 4),
              Pill(statusLabel(status), color: statusColor(status)),
            ],
          ),
        ],
      ),
    );
  }
}

// ================= MIJOZLAR (bugungi marshrut + kun filtr) =================
class ClientsTab extends StatefulWidget {
  const ClientsTab({super.key});
  @override
  State<ClientsTab> createState() => _ClientsTabState();
}

class _ClientsTabState extends State<ClientsTab> {
  List all = [];
  bool loading = true;
  String q = '';
  String filter = 'all'; // all/debt/akb
  int day = 0; // 0 = hammasi, 1..7 = weekday

  @override
  void initState() {
    super.initState();
    day = todayWeekday();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final d = day == 0
          ? await Api.get('/api/clients?limit=500')
          : await Api.get('/api/my-route?weekday=$day');
      all = d['items'] ?? [];
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  List get filtered {
    return all.where((c) {
      final name = '${c['name'] ?? ''}'.toLowerCase();
      if (q.isNotEmpty && !name.contains(q.toLowerCase())) return false;
      if (filter == 'debt' && asNum(c['balance']) <= 0) return false;
      if (filter == 'akb' && asNum(c['orders_month']) <= 0) return false;
      if (filter == 'okb' && asNum(c['orders_month']) > 0) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final list = filtered;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: brand,
        foregroundColor: Colors.white,
        onPressed: () async {
          final ok = await Navigator.push<bool>(
              context, fadeRoute(const ClientFormScreen()));
          if (ok == true) _load();
        },
        icon: const Icon(Icons.add_business),
        label: Text(tr('Do‘kon', 'Точка')),
      ),
      body: Column(
        children: [
          GradientHeader(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(tr('Mijozlar', 'Клиенты'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800)),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.push(
                          context,
                          fadeRoute(ClientsMapScreen(
                              clients: all,
                              onOpen: (c) => Navigator.push(context,
                                  fadeRoute(ClientCardScreen(client: c)))))),
                      icon: const Icon(Icons.map, color: Colors.white),
                      tooltip: tr('Xarita', 'Карта'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TextField(
                  onChanged: (v) => setState(() => q = v),
                  decoration: InputDecoration(
                    hintText: tr('Do‘kon qidirish', 'Поиск точки'),
                    prefixIcon: const Icon(Icons.search),
                    fillColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              children: [
                _dayChip(tr('Hammasi', 'Все'), 0),
                for (int w = 1; w <= 7; w++) _dayChip(weekdayShort(w), w),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 2),
            child: Row(children: [
              _fChip(tr('Barchasi', 'Все'), 'all'),
              _fChip(tr('Qarzli', 'Должники'), 'debt'),
              _fChip('AKB', 'akb'),
              _fChip('OKB', 'okb'),
              const Spacer(),
              Text('${list.length}',
                  style: const TextStyle(
                      color: muted, fontWeight: FontWeight.w700)),
            ]),
          ),
          Expanded(
            child: loading
                ? const ListShimmer()
                : list.isEmpty
                    ? EmptyState(
                        icon: Icons.storefront_outlined,
                        text: tr('Do‘kon topilmadi', 'Точки не найдены'))
                    : RefreshIndicator(
                        color: brand,
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                          itemCount: list.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) => _clientTile(list[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _dayChip(String label, int val) {
    final sel = day == val;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: sel,
        onSelected: (_) {
          setState(() => day = val);
          _load();
        },
        selectedColor: brand,
        labelStyle: TextStyle(
            color: sel ? Colors.white : ink,
            fontWeight: FontWeight.w700,
            fontSize: 13),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: line)),
      ),
    );
  }

  Widget _fChip(String label, String val) {
    final sel = filter == val;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: sel,
        visualDensity: VisualDensity.compact,
        onSelected: (_) => setState(() => filter = val),
        selectedColor: brand.withOpacity(0.15),
        labelStyle: TextStyle(
            color: sel ? brandDark : muted,
            fontWeight: FontWeight.w600,
            fontSize: 12.5),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: sel ? brand : line)),
      ),
    );
  }

  Widget _clientTile(Map c) {
    final bal = asNum(c['balance']);
    return Panel(
      padding: const EdgeInsets.all(12),
      onTap: () async {
        final r = await Navigator.push(
            context, fadeRoute(ClientCardScreen(client: c)));
        if (r == true) _load();
      },
      child: Row(
        children: [
          Avatar('${c['name'] ?? '?'}'),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${c['name'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: ink, fontSize: 15)),
                const SizedBox(height: 3),
                Row(children: [
                  const Icon(Icons.place_outlined, size: 13, color: muted),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(
                        '${c['address'] ?? c['territory_name'] ?? '-'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: muted, fontSize: 12.5)),
                  ),
                ]),
              ],
            ),
          ),
          if (asNum(c['orders_month']) > 0) ...[
            const SizedBox(width: 6),
            const Icon(Icons.verified, color: ok, size: 18),
          ],
          if (bal > 0) ...[
            const SizedBox(width: 8),
            Pill(shortMoney(bal), color: danger, icon: Icons.trending_up),
          ],
        ],
      ),
    );
  }
}

// ================= MIJOZ KARTASI =================
class ClientCardScreen extends StatefulWidget {
  final Map client;
  const ClientCardScreen({super.key, required this.client});
  @override
  State<ClientCardScreen> createState() => _ClientCardScreenState();
}

class _ClientCardScreenState extends State<ClientCardScreen> {
  Map card = {};
  List weekdays = [];
  List orders = [];
  List equipment = [];
  bool loading = true;
  bool photoBusy = false;

  int get _id => widget.client['id'] as int;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Api.get('/api/clients/$_id/card');
      card = Map<String, dynamic>.from(d);
      weekdays = card['weekdays'] ?? [];
    } catch (_) {}
    try {
      final o = await Api.get('/api/clients/$_id/orders');
      orders = (o is List) ? o : ((o['items'] ?? []) as List);
    } catch (_) {
      orders = [];
    }
    try {
      final e = await Api.get('/api/clients/$_id/equipment');
      equipment = (e is List) ? e : ((e['items'] ?? []) as List);
    } catch (_) {
      equipment = [];
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _editPhoto() async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const Icon(Icons.camera_alt, color: brand),
              title: Text(tr('Kamera', 'Камера')),
              onTap: () => Navigator.pop(context, ImageSource.camera)),
          ListTile(
              leading: const Icon(Icons.photo_library, color: brand),
              title: Text(tr('Galereya', 'Галерея')),
              onTap: () => Navigator.pop(context, ImageSource.gallery)),
        ]),
      ),
    );
    if (src == null) return;
    final x = await ImagePicker().pickImage(source: src, imageQuality: 60);
    if (x == null) return;
    setState(() => photoBusy = true);
    try {
      final url = await Api.uploadPhoto(File(x.path));
      final c = _client;
      await Api.post('/api/clients/$_id', {
        'name': '${c['name'] ?? ''}',
        'territory_id': c['territory_id'],
        'category_id': c['category_id'],
        'inn': c['inn'],
        'address': c['address'],
        'orientir': c['orientir'],
        'lat': c['lat'] == null ? null : asNum(c['lat']).toDouble(),
        'lng': c['lng'] == null ? null : asNum(c['lng']).toDouble(),
        'phone': c['phone'],
        'photo': url,
        'is_akb': asNum(c['is_akb']) == 1,
        'weekdays': weekdays.map((w) => asNum(w).toInt()).toList(),
      }, put: true);
      if (mounted) snack(context, tr('Rasm yangilandi', 'Фото обновлено'));
      await _load();
    } catch (e) {
      if (mounted) snack(context, '$e');
    } finally {
      if (mounted) setState(() => photoBusy = false);
    }
  }

  // Rasmni to'liq ochish + "Изменить"
  Future<void> _openPhoto(String url) async {
    final has = url.isNotEmpty && url != 'null';
    final edit = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 0,
            actions: [
              TextButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.camera_alt, color: Colors.white),
                label: Text(tr('Изменить', 'Изменить'),
                    style: const TextStyle(color: Colors.white)),
              ),
            ],
          ),
          body: Center(
            child: has
                ? InteractiveViewer(
                    child: Image.network('${Api.base}$url',
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                            Icons.broken_image,
                            color: Colors.white54,
                            size: 60)))
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.image_outlined,
                          color: Colors.white54, size: 70),
                      const SizedBox(height: 12),
                      Text(tr('Rasm yo‘q — qo‘shish uchun «Изменить»',
                          'Нет фото — нажмите «Изменить»'),
                          style: const TextStyle(color: Colors.white70)),
                    ],
                  ),
          ),
        ),
      ),
    );
    if (edit == true) _editPhoto();
  }

  void _infoSheet(Map c) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tr('Do‘kon ma‘lumotlari', 'Информация о точке'),
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          _row(Icons.phone, tr('Telefon', 'Телефон'), '${c['phone'] ?? '-'}'),
          const Divider(height: 20),
          _row(Icons.place, tr('Manzil', 'Адрес'),
              '${c['address'] ?? c['territory_name'] ?? '-'}'),
          const Divider(height: 20),
          _row(Icons.near_me, tr('Orientir', 'Ориентир'),
              '${c['orientir'] ?? '-'}'),
          const Divider(height: 20),
          _row(Icons.badge, 'INN', '${c['inn'] ?? '-'}'),
          const Divider(height: 20),
          _row(Icons.category, tr('Kategoriya', 'Категория'),
              '${c['category_name'] ?? '-'}'),
          const Divider(height: 20),
          _row(Icons.map, tr('Koordinata', 'Координаты'),
              c['lat'] != null ? '${c['lat']}, ${c['lng']}' : '-'),
        ]),
      ),
    );
  }

  Future<void> _aktSverka(num bal) async {
    Navigator.push(context,
        fadeRoute(ReconcileScreen(clientId: _id, name: '${_client['name']}', balance: bal)));
  }

  Future<void> _addEquipment() async {
    // admin katalogi
    List catalog = [];
    try {
      final d = await Api.get('/api/equipment-catalog');
      catalog = (d is List) ? d : ((d['items'] ?? []) as List);
    } catch (_) {}
    if (!mounted) return;
    Map? selected;
    final noteC = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        return Padding(
          padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr('Oborudovaniya biriktirish', 'Прикрепить оборудование'),
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(tr('Ro‘yxatdan tanlang (admin qo‘shgan)',
                  'Выберите из списка (добавлено админом)'),
                  style: const TextStyle(color: muted, fontSize: 12.5)),
              const SizedBox(height: 12),
              if (catalog.isEmpty)
                Text(tr('Katalog bo‘sh — admin qo‘shishi kerak',
                    'Каталог пуст — админ должен добавить'),
                    style: const TextStyle(color: danger))
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: ListView(
                    shrinkWrap: true,
                    children: catalog.map<Widget>((e) {
                      final sel = selected != null && selected!['id'] == e['id'];
                      return ListTile(
                        dense: true,
                        leading: Icon(
                            '${e['type']}' == 'fridge'
                                ? Icons.kitchen
                                : ('${e['type']}' == 'stand'
                                    ? Icons.view_column
                                    : Icons.shelves),
                            color: sel ? brand : muted),
                        title: Text('${e['name']}'),
                        trailing: sel
                            ? const Icon(Icons.check_circle, color: brand)
                            : null,
                        onTap: () => setS(() => selected = e),
                      );
                    }).toList(),
                  ),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: noteC,
                decoration: InputDecoration(
                    labelText: tr('Izoh / raqami', 'Заметка / номер'),
                    prefixIcon: const Icon(Icons.notes)),
              ),
              const SizedBox(height: 16),
              GradientButton(
                text: tr('Saqlash', 'Сохранить'),
                icon: Icons.check,
                onTap: selected == null
                    ? null
                    : () => Navigator.pop(ctx, true),
              ),
            ],
          ),
        );
      }),
    );
    if (ok != true || selected == null) return;
    try {
      await Api.post('/api/equipment', {
        'client_id': _id,
        'type': '${selected!['type'] ?? 'other'}',
        'name': '${selected!['name'] ?? ''}',
        'note': noteC.text.trim(),
        'status': 'active',
      });
      await _load();
    } catch (e) {
      if (mounted) snack(context, '$e');
    }
  }

  Future<void> _delEquipment(int id) async {
    try {
      await Api.delete('/api/equipment/$id');
    } catch (e) {
      if (mounted) snack(context, '$e');
    }
    await _load();
  }

  String _eqLabel(String t) {
    switch (t) {
      case 'polka':
        return tr('Polka', 'Полка');
      case 'fridge':
        return tr('Xolodilnik', 'Холодильник');
      case 'stand':
        return tr('Stend', 'Стенд');
      default:
        return t;
    }
  }

  Map get _client => (card['client'] ?? widget.client) as Map;

  @override
  Widget build(BuildContext context) {
    final c = card['client'] ?? widget.client;
    final bal = asNum(card['balance'] ?? c['balance']);
    final photo = c['photo'];
    final stat = card['stat'] ?? {};
    return Scaffold(
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: GradientButton(
            text: tr('Tashrif boshlash', 'Начать визит'),
            icon: Icons.login,
            onTap: () =>
                Navigator.push(context, fadeRoute(VisitScreen(client: c))),
          ),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          GradientHeader(
            padding: const EdgeInsets.fromLTRB(8, 4, 10, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back, color: Colors.white)),
                  Expanded(
                    child: Text(tr('Mijoz kartasi', 'Карта клиента'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                      onPressed: () async {
                        final ok = await Navigator.push<bool>(context,
                            fadeRoute(ClientFormScreen(client: c, weekdays: weekdays)));
                        if (ok == true) {
                          _load();
                        }
                      },
                      icon: const Icon(Icons.edit, color: Colors.white)),
                ]),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(children: [
                    GestureDetector(
                      onTap: () => _openPhoto('$photo'),
                      child: (photo != null && '$photo'.isNotEmpty)
                          ? ClipOval(
                              child: Image.network('${Api.base}$photo',
                                  width: 54,
                                  height: 54,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      Avatar('${c['name'] ?? '?'}', size: 54)))
                          : Avatar('${c['name'] ?? '?'}', size: 54),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${c['name'] ?? ''}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          Text('${c['category_name'] ?? tr('Mijoz', 'Клиент')}',
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.85),
                                  fontSize: 13)),
                        ],
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                      child: StatCard(
                          icon: Icons.account_balance_wallet,
                          label: bal > 0 ? tr('Qarz', 'Долг') : tr('Balans', 'Баланс'),
                          value: bal,
                          isMoney: true,
                          color: bal > 0 ? danger : ok,
                          onTap: () => _aktSverka(bal))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: StatCard(
                          icon: Icons.receipt_long,
                          label: tr('Zakazlar', 'Заказы'),
                          value: asNum(stat['orders']),
                          color: info,
                          onTap: () => Navigator.push(
                              context,
                              fadeRoute(ClientOrdersScreen(
                                  clientId: _id, name: '${c['name']}'))))),
                ]),
                // Amallar: ma'lumot (i) + akt-sverka (do'kon nomi ostida)
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _infoSheet(c),
                      icon: const Icon(Icons.info_outline),
                      label: Text(tr('Ma‘lumot', 'Инфо')),
                      style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _aktSverka(bal),
                      icon: const Icon(Icons.receipt_long),
                      label: Text(tr('Akt-sverka', 'Акт-сверка')),
                      style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12)),
                    ),
                  ),
                ]),
                // Do'kon istoriyasi (oxirgi zakazlar)
                SectionTitle(tr('Do‘kon tarixi', 'История точки'),
                    trailing: orders.length > 3
                        ? TextButton(
                            onPressed: () => Navigator.push(
                                context,
                                fadeRoute(ClientOrdersScreen(
                                    clientId: _id, name: '${c['name']}'))),
                            child: Text(tr('Barchasi', 'Все')))
                        : null),
                if (loading)
                  const Shimmer(height: 64)
                else if (orders.isEmpty)
                  Panel(child: EmptyState(text: tr('Zakaz yo‘q', 'Заказов нет')))
                else
                  ...orders.take(3).map((o) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: OrderTile(o,
                            history: true,
                            onTap: () => Navigator.push(
                                context,
                                fadeRoute(NakladnoyScreen(
                                    orderId: o['id'] as int,
                                    clientName: '${c['name']}')))),
                      )),
                // Oborudovaniya (polka/xolodilnik)
                SectionTitle(tr('Oborudovaniya', 'Оборудование'),
                    trailing: TextButton.icon(
                        onPressed: _addEquipment,
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(tr('Qo‘shish', 'Добавить')))),
                if (equipment.isEmpty)
                  Panel(
                      child: EmptyState(
                          icon: Icons.kitchen_outlined,
                          text: tr('Biriktirilmagan', 'Не прикреплено')))
                else
                  ...equipment.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Panel(
                          padding: const EdgeInsets.all(12),
                          child: Row(children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                  color: info.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(12)),
                              child: Icon(
                                  '${e['type']}' == 'fridge'
                                      ? Icons.kitchen
                                      : ('${e['type']}' == 'stand'
                                          ? Icons.view_column
                                          : Icons.shelves),
                                  color: info),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      '${_eqLabel('${e['type']}')}${(e['name'] ?? '').toString().isNotEmpty ? ' · ${e['name']}' : ''}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: ink)),
                                  if ('${e['note'] ?? ''}'.isNotEmpty)
                                    Text('${e['note']}',
                                        style: const TextStyle(
                                            color: muted, fontSize: 12.5)),
                                ],
                              ),
                            ),
                            IconButton(
                                onPressed: () => _delEquipment(e['id'] as int),
                                icon: const Icon(Icons.delete_outline,
                                    color: danger)),
                          ]),
                        ),
                      )),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(IconData ic, String k, String v) {
    return Row(children: [
      Icon(ic, size: 18, color: muted),
      const SizedBox(width: 10),
      Text(k, style: const TextStyle(color: muted, fontSize: 13)),
      const Spacer(),
      Flexible(
        child: Text(v,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w600, color: ink)),
      ),
    ]);
  }

  Widget _photoPh() => Container(
        height: 140,
        width: double.infinity,
        decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: line)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_a_photo_outlined, color: muted, size: 34),
            const SizedBox(height: 8),
            Text(tr('Rasm qo‘shish', 'Добавить фото'),
                style: const TextStyle(color: muted, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

// ================= DO'KON ZAKAZLAR TARIXI =================
class ClientOrdersScreen extends StatefulWidget {
  final int clientId;
  final String name;
  const ClientOrdersScreen(
      {super.key, required this.clientId, required this.name});
  @override
  State<ClientOrdersScreen> createState() => _ClientOrdersScreenState();
}

class _ClientOrdersScreenState extends State<ClientOrdersScreen> {
  List items = [];
  bool loading = true;
  DateTimeRange? range;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final o = await Api.get('/api/clients/${widget.clientId}/orders');
      items = (o is List) ? o : ((o['items'] ?? []) as List);
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  List get filtered {
    if (range == null) return items;
    return items.where((o) {
      final s = '${o['created_at'] ?? ''}';
      if (s.length < 10) return true;
      final d = DateTime.tryParse(s.substring(0, 10));
      if (d == null) return true;
      return !d.isBefore(range!.start) &&
          !d.isAfter(range!.end.add(const Duration(days: 1)));
    }).toList();
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: range,
    );
    if (r != null) setState(() => range = r);
  }

  @override
  Widget build(BuildContext context) {
    final list = filtered;
    return Scaffold(
      body: Column(children: [
        GradientHeader(
          padding: const EdgeInsets.fromLTRB(8, 4, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, color: Colors.white)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Zakazlar tarixi', 'История заказов'),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800)),
                      Text(widget.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 13)),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickRange,
                    icon: const Icon(Icons.date_range, color: Colors.white, size: 18),
                    label: Text(
                        range == null
                            ? tr('Sana bo‘yicha filtr', 'Фильтр по дате')
                            : '${range!.start.toIso8601String().substring(0, 10)} — ${range!.end.toIso8601String().substring(0, 10)}',
                        style: const TextStyle(color: Colors.white)),
                    style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.white.withOpacity(0.6))),
                  ),
                ),
                if (range != null)
                  IconButton(
                      onPressed: () => setState(() => range = null),
                      icon: const Icon(Icons.close, color: Colors.white)),
              ]),
            ],
          ),
        ),
        Expanded(
          child: loading
              ? const ListShimmer()
              : list.isEmpty
                  ? EmptyState(text: tr('Zakaz yo‘q', 'Заказов нет'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => OrderTile(list[i],
                          history: true,
                          onTap: () => Navigator.push(
                              context,
                              fadeRoute(NakladnoyScreen(
                                  orderId: list[i]['id'] as int,
                                  clientName: widget.name)))),
                    ),
        ),
      ]),
    );
  }
}

// ================= NAKLADNOY (zakaz hujjati) =================
class NakladnoyScreen extends StatefulWidget {
  final int orderId;
  final String clientName;
  const NakladnoyScreen(
      {super.key, required this.orderId, required this.clientName});
  @override
  State<NakladnoyScreen> createState() => _NakladnoyScreenState();
}

class _NakladnoyScreenState extends State<NakladnoyScreen> {
  Map order = {};
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final o = await Api.get('/api/orders/${widget.orderId}');
      order = Map<String, dynamic>.from(o);
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  List get _items => (order['items'] ?? []) as List;

  List<List<dynamic>> _csvRows() {
    final rows = <List<dynamic>>[
      ['Nakladnoy #${order['id']}'],
      [tr('Mijoz', 'Клиент'), widget.clientName],
      [tr('Sana', 'Дата'), '${order['created_at'] ?? ''}'],
      [],
      ['#', tr('Mahsulot', 'Товар'), tr('Soni', 'Кол-во'),
        tr('Narx', 'Цена'), tr('Summa', 'Сумма')],
    ];
    int i = 1;
    for (final it in _items) {
      rows.add([
        i++,
        '${it['product_name'] ?? ''}',
        asNum(it['qty']),
        asNum(it['price']),
        asNum(it['line_sum'] ?? asNum(it['qty']) * asNum(it['price'])),
      ]);
    }
    rows.add([]);
    rows.add(['', '', '', tr('Jami', 'Итого'), asNum(order['total'])]);
    return rows;
  }

  Future<void> _share() async {
    try {
      await shareCsv('nakladnoy_${order['id']}.csv', _csvRows(),
          subject: 'Nakladnoy #${order['id']}',
          text: '${widget.clientName} · ${money(asNum(order['total']))}');
    } catch (e) {
      if (mounted) snack(context, '$e');
    }
  }

  Future<void> _finalize(String action) async {
    try {
      await Api.post(
          '/api/orders/${widget.orderId}/finalize?action=$action', {});
      if (mounted) {
        snack(
            context,
            action == 'confirm'
                ? tr('Zakaz yakunlandi', 'Заказ оформлен')
                : tr('Chernovik bekor qilindi', 'Черновик отменён'));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) snack(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = '${order['status'] ?? ''}';
    final isDraft = st == 'draft';
    return Scaffold(
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: isDraft
              ? Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: loading ? null : () => _finalize('cancel'),
                      icon: const Icon(Icons.close, color: danger),
                      label: Text(tr('Bekor', 'Отменить'),
                          style: const TextStyle(color: danger)),
                      style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: danger),
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: GradientButton(
                      text: tr('Zakazni yakunlash', 'Оформить заказ'),
                      icon: Icons.check,
                      onTap: loading ? null : () => _finalize('confirm'),
                    ),
                  ),
                ])
              : Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: loading ? null : _share,
                      icon: const Icon(Icons.ios_share),
                      label: Text(tr('Ulashish', 'Поделиться')),
                      style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GradientButton(
                      text: 'Excel',
                      icon: Icons.table_view,
                      onTap: loading ? null : _share,
                    ),
                  ),
                ]),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          GradientHeader(
            padding: const EdgeInsets.fromLTRB(8, 4, 18, 20),
            child: Row(children: [
              IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back, color: Colors.white)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${tr('Nakladnoy', 'Накладная')} #${widget.orderId}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800)),
                    Text(widget.clientName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.9), fontSize: 13)),
                  ],
                ),
              ),
              if (st.isNotEmpty)
                Pill(statusLabel(st), color: Colors.white),
            ]),
          ),
          if (loading)
            const Padding(padding: EdgeInsets.all(16), child: ListShimmer())
          else
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Panel(
                    child: Column(children: [
                      for (final it in _items) ...[
                        Row(children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${it['product_name'] ?? ''}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: ink)),
                                Text(
                                    '${asNum(it['qty']).toStringAsFixed(0)} × ${money(asNum(it['price']))}',
                                    style: const TextStyle(
                                        color: muted, fontSize: 12.5)),
                              ],
                            ),
                          ),
                          Text(
                              money(asNum(it['line_sum'] ??
                                  asNum(it['qty']) * asNum(it['price']))),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, color: ink)),
                        ]),
                        if (it != _items.last) const Divider(height: 20),
                      ],
                    ]),
                  ),
                  const SizedBox(height: 14),
                  Panel(
                    color: brand.withOpacity(0.06),
                    child: Row(children: [
                      Text(tr('Jami', 'Итого'),
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 16)),
                      const Spacer(),
                      Text(money(asNum(order['total'])),
                          style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              color: brand)),
                    ]),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ================= CHERNOVIK (draft) ZAKAZLAR =================
class ChernovikScreen extends StatefulWidget {
  const ChernovikScreen({super.key});
  @override
  State<ChernovikScreen> createState() => _ChernovikScreenState();
}

class _ChernovikScreenState extends State<ChernovikScreen> {
  List items = [];
  bool loading = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final d = await Api.get('/api/orders?status=draft&limit=200');
      items = (d['items'] ?? []) as List;
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(children: [
        GradientHeader(
          padding: const EdgeInsets.fromLTRB(8, 4, 18, 20),
          child: Row(children: [
            IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back, color: Colors.white)),
            Expanded(
              child: Text(tr('Chernovik zakazlar', 'Черновики заказов'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
        Expanded(
          child: loading
              ? const ListShimmer()
              : items.isEmpty
                  ? EmptyState(
                      icon: Icons.drafts_outlined,
                      text: tr('Chernovik yo‘q', 'Черновиков нет'))
                  : RefreshIndicator(
                      color: brand,
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => OrderTile(items[i], onTap: () async {
                          await Navigator.push(
                              context,
                              fadeRoute(NakladnoyScreen(
                                  orderId: items[i]['id'] as int,
                                  clientName:
                                      '${items[i]['client_name'] ?? ''}')));
                          _load();
                        }),
                      ),
                    ),
        ),
      ]),
    );
  }
}

// ================= AKT-SVERKA =================
class ReconcileScreen extends StatefulWidget {
  final int clientId;
  final String name;
  final num balance;
  const ReconcileScreen(
      {super.key,
      required this.clientId,
      required this.name,
      required this.balance});
  @override
  State<ReconcileScreen> createState() => _ReconcileScreenState();
}

class _ReconcileScreenState extends State<ReconcileScreen> {
  Map data = {};
  List rows = [];
  bool loading = true;
  DateTimeRange? range;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Api.get('/api/clients/${widget.clientId}/reconcile');
      if (d is Map) {
        data = Map<String, dynamic>.from(d);
        rows = (data['rows'] ?? data['items'] ?? data['entries'] ?? []) as List;
      } else if (d is List) {
        rows = d;
      }
    } catch (_) {
      // fallback: zakazlar ro'yxati
      try {
        final o = await Api.get('/api/clients/${widget.clientId}/orders');
        rows = (o is List) ? o : ((o['items'] ?? []) as List);
      } catch (_) {}
    }
    if (mounted) setState(() => loading = false);
  }

  List get filteredRows {
    if (range == null) return rows;
    return rows.where((r) {
      final s = '${r['ts'] ?? r['created_at'] ?? r['date'] ?? ''}';
      if (s.length < 10) return true;
      final d = DateTime.tryParse(s.substring(0, 10));
      if (d == null) return true;
      return !d.isBefore(range!.start) &&
          !d.isAfter(range!.end.add(const Duration(days: 1)));
    }).toList();
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: range,
    );
    if (r != null) setState(() => range = r);
  }

  Future<void> _share() async {
    final list = filteredRows;
    final csv = <List<dynamic>>[
      ['${tr('Akt-sverka', 'Акт-сверка')}: ${widget.name}'],
      if (range != null)
        [tr('Davr', 'Период'),
          '${range!.start.toIso8601String().substring(0, 10)} — ${range!.end.toIso8601String().substring(0, 10)}'],
      [],
      [tr('Sana', 'Дата'), tr('Turi', 'Тип'), tr('Summa', 'Сумма'),
        tr('Qoldiq', 'Остаток')],
    ];
    for (final r in list) {
      final type = '${r['type'] ?? r['status'] ?? ''}';
      csv.add([
        '${r['ts'] ?? r['created_at'] ?? ''}',
        type == 'debt'
            ? tr('Qarz', 'Долг')
            : type == 'payment'
                ? tr('To‘lov', 'Оплата')
                : type,
        asNum(r['total'] ?? r['amount'] ?? 0),
        r['balance'] ?? '',
      ]);
    }
    csv.add([]);
    csv.add(['', tr('Qoldiq', 'Остаток'), asNum(data['balance'] ?? widget.balance)]);
    try {
      await shareCsv('akt_sverka_${widget.clientId}.csv', csv,
          subject: '${tr('Akt-sverka', 'Акт-сверка')} — ${widget.name}');
    } catch (e) {
      if (mounted) snack(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bal = asNum(data['balance'] ?? widget.balance);
    final list = filteredRows;
    return Scaffold(
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: loading ? null : _share,
                icon: const Icon(Icons.ios_share),
                label: Text(tr('Ulashish', 'Поделиться')),
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GradientButton(
                text: 'Excel',
                icon: Icons.table_view,
                onTap: loading ? null : _share,
              ),
            ),
          ]),
        ),
      ),
      body: Column(children: [
        GradientHeader(
          padding: const EdgeInsets.fromLTRB(8, 4, 18, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, color: Colors.white)),
                Expanded(
                  child: Text(tr('Akt-sverka', 'Акт-сверка'),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800)),
                ),
              ]),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.name,
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 14)),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(14)),
                      child: Row(children: [
                        Text(
                            bal > 0
                                ? tr('Joriy qarz', 'Текущий долг')
                                : tr('Balans', 'Баланс'),
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.85),
                                fontSize: 13)),
                        const Spacer(),
                        Text(money(bal),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 18)),
                      ]),
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickRange,
                          icon: const Icon(Icons.date_range,
                              color: Colors.white, size: 18),
                          label: Text(
                              range == null
                                  ? tr('Sana bo‘yicha', 'По дате')
                                  : '${range!.start.toIso8601String().substring(0, 10)} — ${range!.end.toIso8601String().substring(0, 10)}',
                              style: const TextStyle(color: Colors.white)),
                          style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                  color: Colors.white.withOpacity(0.6))),
                        ),
                      ),
                      if (range != null)
                        IconButton(
                            onPressed: () => setState(() => range = null),
                            icon: const Icon(Icons.close, color: Colors.white)),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: loading
              ? const ListShimmer()
              : list.isEmpty
                  ? EmptyState(text: tr('Harakat yo‘q', 'Нет операций'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final r = list[i] as Map;
                        final amount =
                            asNum(r['total'] ?? r['amount'] ?? 0);
                        final date =
                            '${r['ts'] ?? r['created_at'] ?? r['date'] ?? ''}';
                        final type = '${r['type'] ?? r['status'] ?? ''}';
                        final isPay = type == 'payment' || amount < 0;
                        final label = type == 'debt'
                            ? tr('Qarz (zakaz)', 'Долг (заказ)')
                            : type == 'payment'
                                ? tr('To‘lov', 'Оплата')
                                : (r['id'] != null ? '#${r['id']}' : type);
                        return Panel(
                          padding: const EdgeInsets.all(12),
                          child: Row(children: [
                            Icon(isPay ? Icons.south_west : Icons.north_east,
                                color: isPay ? ok : danger, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(label,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: ink)),
                                  if (date.isNotEmpty)
                                    Text(
                                        date.length >= 16
                                            ? date.substring(0, 16)
                                            : date,
                                        style: const TextStyle(
                                            color: muted, fontSize: 12)),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(money(amount.abs()),
                                    style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: isPay ? ok : ink)),
                                if (r['balance'] != null)
                                  Text('= ${money(asNum(r['balance']))}',
                                      style: const TextStyle(
                                          color: muted, fontSize: 11.5)),
                              ],
                            ),
                          ]),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}

// ================= DO'KON QO'SHISH / TAHRIRLASH =================
class ClientFormScreen extends StatefulWidget {
  final Map? client;
  final List? weekdays;
  const ClientFormScreen({super.key, this.client, this.weekdays});
  @override
  State<ClientFormScreen> createState() => _ClientFormScreenState();
}

class _ClientFormScreenState extends State<ClientFormScreen> {
  final name = TextEditingController();
  final phone = TextEditingController();
  final inn = TextEditingController();
  final address = TextEditingController();
  final orientir = TextEditingController();
  final Set<int> days = {};
  bool akb = false;
  double? lat, lng;
  int? territoryId, categoryId;
  List territories = [], categories = [];
  bool busy = false;
  String? photoUrl;
  bool photoBusy = false;

  bool get isEdit => widget.client != null;

  @override
  void initState() {
    super.initState();
    final c = widget.client;
    if (c != null) {
      name.text = '${c['name'] ?? ''}';
      phone.text = '${c['phone'] ?? ''}';
      inn.text = '${c['inn'] ?? ''}';
      address.text = '${c['address'] ?? ''}';
      orientir.text = '${c['orientir'] ?? ''}';
      photoUrl = (c['photo'] != null && '${c['photo']}'.isNotEmpty)
          ? '${c['photo']}'
          : null;
      akb = asNum(c['is_akb']) == 1;
      if (c['lat'] != null) lat = asNum(c['lat']).toDouble();
      if (c['lng'] != null) lng = asNum(c['lng']).toDouble();
      territoryId = c['territory_id'];
      categoryId = c['category_id'];
      for (final w in (widget.weekdays ?? [])) {
        days.add(asNum(w).toInt());
      }
    }
    _loadRefs();
  }

  Future<void> _loadRefs() async {
    try {
      territories = await Api.get('/api/territories');
      categories = await Api.get('/api/client-categories');
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _pickLocation() async {
    final init = (lat != null && lng != null) ? LatLng(lat!, lng!) : null;
    final r = await Navigator.push<LatLng>(
        context, fadeRoute(LocationPickerScreen(initial: init)));
    if (r != null) {
      setState(() {
        lat = r.latitude;
        lng = r.longitude;
      });
    }
  }

  Future<void> _pickPhoto() async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const Icon(Icons.camera_alt, color: brand),
              title: Text(tr('Kamera', 'Камера')),
              onTap: () => Navigator.pop(context, ImageSource.camera)),
          ListTile(
              leading: const Icon(Icons.photo_library, color: brand),
              title: Text(tr('Galereya', 'Галерея')),
              onTap: () => Navigator.pop(context, ImageSource.gallery)),
        ]),
      ),
    );
    if (src == null) return;
    final x = await ImagePicker().pickImage(source: src, imageQuality: 60);
    if (x == null) return;
    setState(() => photoBusy = true);
    try {
      final url = await Api.uploadPhoto(File(x.path));
      setState(() => photoUrl = url);
    } catch (e) {
      if (mounted) snack(context, '$e');
    } finally {
      if (mounted) setState(() => photoBusy = false);
    }
  }

  Future<void> _save() async {
    if (name.text.trim().isEmpty) {
      snack(context, tr('Nomini kiriting', 'Введите название'));
      return;
    }
    setState(() => busy = true);
    final body = {
      'name': name.text.trim(),
      'phone': phone.text.trim(),
      'inn': inn.text.trim(),
      'address': address.text.trim(),
      'orientir': orientir.text.trim(),
      'lat': lat,
      'lng': lng,
      'territory_id': territoryId,
      'category_id': categoryId,
      'is_akb': akb,
      'photo': photoUrl,
      'weekdays': days.toList(),
    };
    try {
      if (isEdit) {
        await Api.post('/api/clients/${widget.client!['id']}', body, put: true);
      } else {
        await Api.post('/api/clients', body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) snack(context, '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          GradientHeader(
            padding: const EdgeInsets.fromLTRB(8, 4, 18, 20),
            child: Row(children: [
              IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back, color: Colors.white)),
              Text(
                  isEdit
                      ? tr('Mijozni tahrirlash', 'Редактировать клиента')
                      : tr('Yangi do‘kon', 'Новая точка'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _tf(name, tr('Do‘kon nomi', 'Название точки'), Icons.storefront),
                const SizedBox(height: 12),
                _tf(phone, tr('Telefon', 'Телефон'), Icons.phone,
                    kb: TextInputType.phone),
                const SizedBox(height: 12),
                _tf(inn, 'INN', Icons.badge, kb: TextInputType.number),
                const SizedBox(height: 12),
                _tf(address, tr('Manzil', 'Адрес'), Icons.place),
                const SizedBox(height: 12),
                _tf(orientir, tr('Orientir', 'Ориентир'), Icons.near_me),
                const SizedBox(height: 16),
                Text(tr('Tashrif kunlari', 'Дни визитов'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: ink)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (int w = 1; w <= 7; w++)
                      FilterChip(
                        label: Text(weekdayShort(w)),
                        selected: days.contains(w),
                        onSelected: (v) => setState(() {
                          v ? days.add(w) : days.remove(w);
                        }),
                        selectedColor: brand,
                        checkmarkColor: Colors.white,
                        labelStyle: TextStyle(
                            color: days.contains(w) ? Colors.white : ink,
                            fontWeight: FontWeight.w600),
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: const BorderSide(color: line)),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _dropdown(tr('Hudud', 'Территория'), territories, territoryId,
                    (v) => setState(() => territoryId = v)),
                const SizedBox(height: 12),
                _dropdown(tr('Kategoriya', 'Категория'), categories, categoryId,
                    (v) => setState(() => categoryId = v)),
                const SizedBox(height: 16),
                Panel(
                  onTap: _pickLocation,
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: brand.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.map, color: brand),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr('Lokatsiya', 'Локация'),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, color: ink)),
                          Text(
                              lat != null
                                  ? '${lat!.toStringAsFixed(5)}, ${lng!.toStringAsFixed(5)}'
                                  : tr('Xaritada belgilang (GPS)',
                                      'Отметьте на карте (GPS)'),
                              style: const TextStyle(
                                  color: muted, fontSize: 12.5)),
                        ],
                      ),
                    ),
                    Icon(lat != null ? Icons.check_circle : Icons.chevron_right,
                        color: lat != null ? ok : muted),
                  ]),
                ),
                const SizedBox(height: 12),
                Panel(
                  onTap: photoBusy ? null : _pickPhoto,
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: brand.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12)),
                      child: photoBusy
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : (photoUrl != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network('${Api.base}$photoUrl',
                                      width: 40, height: 40, fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          const Icon(Icons.storefront,
                                              color: brand)))
                              : const Icon(Icons.add_a_photo, color: brand)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr('Do‘kon rasmi', 'Фото точки'),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, color: ink)),
                          Text(
                              photoUrl != null
                                  ? tr('Rasm tanlangan', 'Фото выбрано')
                                  : tr('Rasm qo‘shish (ixtiyoriy)',
                                      'Добавить фото'),
                              style:
                                  const TextStyle(color: muted, fontSize: 12.5)),
                        ],
                      ),
                    ),
                    Icon(photoUrl != null ? Icons.check_circle : Icons.chevron_right,
                        color: photoUrl != null ? ok : muted),
                  ]),
                ),
                const SizedBox(height: 16),
                GradientButton(
                  text: tr('Saqlash', 'Сохранить'),
                  icon: Icons.check,
                  busy: busy,
                  onTap: _save,
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tf(TextEditingController c, String label, IconData ic,
      {TextInputType? kb}) {
    return TextField(
      controller: c,
      keyboardType: kb,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(ic)),
    );
  }

  Widget _dropdown(String label, List items, int? value,
      void Function(int?) onCh) {
    return DropdownButtonFormField<int>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        DropdownMenuItem<int>(value: null, child: Text(tr('Tanlanmagan', 'Не выбрано'))),
        ...items.map((t) => DropdownMenuItem<int>(
            value: t['id'] as int, child: Text('${t['name']}'))),
      ],
      onChanged: onCh,
    );
  }
}

// ================= ZAKAZLAR =================
class OrdersTab extends StatefulWidget {
  const OrdersTab({super.key});
  @override
  State<OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<OrdersTab> {
  List all = [];
  bool loading = true;
  bool loadingMore = false;
  bool hasMore = true;
  int offset = 0;
  static const _page = 40;
  String status = '';
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!hasMore || loadingMore || loading) return;
    if (_scroll.position.pixels >=
        _scroll.position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  String _path() {
    final st = status.isEmpty ? '' : '&status=$status';
    return '/api/orders?limit=$_page&offset=$offset$st';
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      offset = 0;
      hasMore = true;
    });
    try {
      final d = await Api.get(_path());
      final items = (d['items'] ?? []) as List;
      all = items;
      offset = items.length;
      hasMore = items.length >= _page;
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  Future<void> _loadMore() async {
    setState(() => loadingMore = true);
    try {
      final d = await Api.get(_path());
      final items = (d['items'] ?? []) as List;
      all = [...all, ...items];
      offset += items.length;
      hasMore = items.length >= _page;
    } catch (_) {}
    if (mounted) setState(() => loadingMore = false);
  }

  void _openOrder(Map o) {
    Navigator.push(
        context,
        fadeRoute(NakladnoyScreen(
            orderId: o['id'] as int,
            clientName: '${o['client_name'] ?? ''}')));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GradientHeader(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('Zakazlar', 'Заказы'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _sc(tr('Hammasi', 'Все'), ''),
                  _sc(tr('Yangi', 'Новые'), 'new'),
                  _sc(tr('Yetkazildi', 'Доставлен'), 'delivered'),
                  _sc(tr('Vozvrat', 'Возврат'), 'returned'),
                  _sc(tr('Otmen', 'Отмена'), 'canceled'),
                ]),
              ),
            ],
          ),
        ),
        Expanded(
          child: loading
              ? const ListShimmer()
              : all.isEmpty
                  ? EmptyState(
                      icon: Icons.receipt_long_outlined,
                      text: tr('Zakaz yo‘q', 'Заказов нет'))
                  : RefreshIndicator(
                      color: brand,
                      onRefresh: _load,
                      child: ListView.separated(
                        controller: _scroll,
                        padding: const EdgeInsets.all(16),
                        itemCount: all.length + (hasMore ? 1 : 0),
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          if (i >= all.length) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(
                                  child: SizedBox(
                                      height: 24,
                                      width: 24,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: brand))),
                            );
                          }
                          return OrderTile(all[i],
                              onTap: () => _openOrder(all[i]));
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _sc(String label, String val) {
    final sel = status == val;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: sel,
        onSelected: (_) {
          setState(() => status = val);
          _load();
        },
        selectedColor: brand,
        labelStyle: TextStyle(
            color: sel ? Colors.white : brandDark,
            fontWeight: FontWeight.w700,
            fontSize: 13),
        backgroundColor: Colors.white,
        side: BorderSide(color: sel ? brand : line),
      ),
    );
  }
}

// ================= HISOBOT =================
class AgentReportsTab extends StatefulWidget {
  const AgentReportsTab({super.key});
  @override
  State<AgentReportsTab> createState() => _AgentReportsTabState();
}

class _AgentReportsTabState extends State<AgentReportsTab> {
  bool loading = true;
  num sum = 0, count = 0;
  Map<String, num> byPay = {'cash': 0, 'transfer': 0, 'debt': 0};
  List recent = [];
  Map kpi = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final first = '${DateTime.now().toIso8601String().substring(0, 8)}01';
      final d = await Api.get('/api/orders?d1=$first&d2=${_today()}&limit=500');
      final items = (d['items'] ?? []) as List;
      sum = asNum(d['sum']);
      count = asNum(d['count'] ?? items.length);
      byPay = {'cash': 0, 'transfer': 0, 'debt': 0};
      for (final o in items) {
        final p = '${o['pay_type']}';
        byPay[p] = (byPay[p] ?? 0) + asNum(o['total']);
      }
      recent = items.take(8).toList();
      try {
        kpi = Map<String, dynamic>.from(await Api.get('/api/my-kpi'));
      } catch (_) {}
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final avg = count > 0 ? sum / count : 0;
    final total = byPay.values.fold<num>(0, (a, b) => a + b);
    return RefreshIndicator(
      color: brand,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          GradientHeader(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Bu oy — faoliyat', 'Этот месяц — активность'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Umumiy savdo', 'Общая продажа'),
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.85),
                              fontSize: 13)),
                      const SizedBox(height: 4),
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: sum.toDouble()),
                        duration: const Duration(milliseconds: 900),
                        builder: (_, v, __) => Text(money(v),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                      child: StatCard(
                          icon: Icons.verified,
                          label: 'AKB',
                          value: asNum(kpi['akb']),
                          color: ok)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: StatCard(
                          icon: Icons.store_mall_directory_outlined,
                          label: 'OKB',
                          value: asNum(kpi['okb']),
                          color: warn)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: StatCard(
                          icon: Icons.place,
                          label: tr('Tashrif', 'Визиты'),
                          value: asNum(kpi['visits']),
                          color: info)),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: StatCard(
                          icon: Icons.receipt_long,
                          label: tr('Zakazlar', 'Заказы'),
                          value: count,
                          color: info)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: StatCard(
                          icon: Icons.calculate,
                          label: tr('O‘rtacha chek', 'Средний чек'),
                          value: avg,
                          isMoney: true,
                          color: accent)),
                ]),
                _kpiSection(),
                SectionTitle(tr('To‘lov turlari', 'Виды оплаты')),
                Panel(
                  child: Column(children: [
                    _payRow(tr('Naqd', 'Наличные'), byPay['cash'] ?? 0, total, ok),
                    const SizedBox(height: 14),
                    _payRow(tr('O‘tkazma', 'Перевод'), byPay['transfer'] ?? 0, total, info),
                    const SizedBox(height: 14),
                    _payRow(tr('Qarz', 'Долг'), byPay['debt'] ?? 0, total, danger),
                  ]),
                ),
                SectionTitle(tr('So‘nggi zakazlar', 'Последние заказы')),
                if (loading)
                  const Shimmer(height: 64)
                else if (recent.isEmpty)
                  Panel(child: EmptyState(text: tr('Zakaz yo‘q', 'Заказов нет')))
                else
                  ...recent.map((o) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: OrderTile(o,
                            onTap: () => Navigator.push(
                                context,
                                fadeRoute(NakladnoyScreen(
                                    orderId: o['id'] as int,
                                    clientName:
                                        '${o['client_name'] ?? ''}')))),
                      )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpiSection() {
    final ts = asNum(kpi['target_sum']);
    final ta = asNum(kpi['target_akb']);
    final tv = asNum(kpi['target_visit']);
    if (ts <= 0 && ta <= 0 && tv <= 0) return const SizedBox.shrink();
    final rows = <Widget>[];
    void add(Widget w) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 14));
      rows.add(w);
    }

    if (ts > 0) {
      add(_kpiRow(tr('Savdo', 'Продажа'), asNum(kpi['sales']), ts, brand,
          money: true));
    }
    if (ta > 0) add(_kpiRow('AKB', asNum(kpi['akb']), ta, ok));
    if (tv > 0) {
      add(_kpiRow(tr('Tashrif', 'Визиты'), asNum(kpi['visits']), tv, info));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(tr('Reja bajarilishi (KPI)', 'Выполнение плана (KPI)')),
        Panel(child: Column(children: rows)),
      ],
    );
  }

  Widget _kpiRow(String label, num fact, num target, Color color,
      {bool money = false}) {
    final frac =
        target > 0 ? (fact / target).clamp(0.0, 1.0).toDouble() : 0.0;
    final pct = target > 0 ? (fact * 100 / target).round() : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          const Spacer(),
          Text(
              '${money ? shortMoney(fact) : fact.round()} / ${money ? shortMoney(target) : target.round()}   ·   $pct%',
              style: TextStyle(fontWeight: FontWeight.w800, color: color)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: frac),
            duration: const Duration(milliseconds: 800),
            builder: (_, v, __) => LinearProgressIndicator(
              value: v,
              minHeight: 9,
              backgroundColor: const Color(0xFFEFF2F6),
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _payRow(String label, num val, num total, Color color) {
    final frac = total > 0 ? (val / total).clamp(0.0, 1.0).toDouble() : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(money(val),
              style: TextStyle(fontWeight: FontWeight.w800, color: color)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: frac),
            duration: const Duration(milliseconds: 700),
            builder: (_, v, __) => LinearProgressIndicator(
              value: v,
              minHeight: 8,
              backgroundColor: const Color(0xFFEFF2F6),
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

// ================= PROFIL =================
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});
  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  bool uploading = false;

  Future<void> _pickPhoto() async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const Icon(Icons.camera_alt, color: brand),
              title: Text(tr('Kamera', 'Камера')),
              onTap: () => Navigator.pop(context, ImageSource.camera)),
          ListTile(
              leading: const Icon(Icons.photo_library, color: brand),
              title: Text(tr('Galereya', 'Галерея')),
              onTap: () => Navigator.pop(context, ImageSource.gallery)),
        ]),
      ),
    );
    if (src == null) return;
    final x = await ImagePicker().pickImage(source: src, imageQuality: 60);
    if (x == null) return;
    setState(() => uploading = true);
    try {
      final url = await Api.uploadPhoto(File(x.path));
      await Api.post('/auth/me/photo', {'photo': url});
      Api.me?['photo'] = url;
      if (mounted) snack(context, tr('Rasm yangilandi', 'Фото обновлено'));
    } catch (e) {
      if (mounted) snack(context, '$e');
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = Api.me ?? {};
    final role = '${me['role'] ?? '-'}';
    final photo = me['photo'];
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        GradientHeader(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 26),
          child: Column(
            children: [
              Stack(children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle),
                  child: (photo != null && '$photo'.isNotEmpty)
                      ? ClipOval(
                          child: Image.network('${Api.base}$photo',
                              width: 76,
                              height: 76,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  Avatar('${me['name'] ?? '?'}', size: 76)),
                        )
                      : Avatar('${me['name'] ?? '?'}', size: 76),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: GestureDetector(
                    onTap: uploading ? null : _pickPhoto,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                          color: brand, shape: BoxShape.circle),
                      child: uploading
                          ? const SizedBox(
                              height: 14,
                              width: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.camera_alt,
                              color: Colors.white, size: 16),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              Text('${me['name'] ?? '-'}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Pill(roleLabel(role), color: Colors.white, icon: Icons.badge),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Panel(
                child: Column(children: [
                  _row(Icons.person, tr('Login', 'Логин'),
                      '${me['login'] ?? me['name'] ?? '-'}'),
                  const Divider(height: 20),
                  _row(Icons.badge_outlined, tr('Rol', 'Роль'), roleLabel(role)),
                  const Divider(height: 20),
                  _row(Icons.business, tr('Kompaniya', 'Компания'),
                      '${me['company_name'] ?? '-'}'),
                ]),
              ),
              const SizedBox(height: 16),
              Panel(
                child: Row(children: [
                  const Icon(Icons.language, color: brand),
                  const SizedBox(width: 12),
                  Text(tr('Til', 'Язык'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  _langBtn('uz', 'UZ'),
                  const SizedBox(width: 8),
                  _langBtn('ru', 'RU'),
                ]),
              ),
              const SizedBox(height: 20),
              GradientButton(
                text: tr('Chiqish', 'Выход'),
                icon: Icons.logout,
                gradient: const LinearGradient(colors: [danger, accent2]),
                onTap: () async {
                  await Api.logout();
                  if (context.mounted) {
                    Navigator.pushReplacement(
                        context, fadeRoute(const LoginScreen()));
                  }
                },
              ),
              const SizedBox(height: 14),
              const Text('SalesGO v1.6',
                  style: TextStyle(color: muted, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _langBtn(String code, String label) {
    final sel = lang == code;
    return GestureDetector(
      onTap: () => setLang(code),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
            color: sel ? brand : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: sel ? brand : line)),
        child: Text(label,
            style: TextStyle(
                color: sel ? Colors.white : muted,
                fontWeight: FontWeight.w800)),
      ),
    );
  }

  Widget _row(IconData ic, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: brand.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(ic, size: 18, color: brand),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(k,
                    style: const TextStyle(color: muted, fontSize: 12)),
                const SizedBox(height: 1),
                Text(v,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: ink,
                        fontSize: 14.5)),
              ],
            ),
          ),
        ]),
      );
}

String roleLabel(String r) {
  switch (r) {
    case 'agent':
      return tr('Savdo agenti', 'Торговый агент');
    case 'delivery':
      return tr('Ekspeditor', 'Экспедитор');
    case 'collector':
      return tr('Inkassator', 'Инкассатор');
    case 'supervisor':
      return tr('Supervayzer', 'Супервайзер');
    case 'admin':
      return tr('Administrator', 'Администратор');
    case 'operator':
      return 'Operator';
    case 'cashier':
      return tr('Kassir', 'Кассир');
    default:
      return r;
  }
}

// ================= TASHRIF =================
class VisitScreen extends StatefulWidget {
  final Map client;
  const VisitScreen({super.key, required this.client});
  @override
  State<VisitScreen> createState() => _VisitScreenState();
}

class _VisitScreenState extends State<VisitScreen> {
  int? visitId;
  bool busy = false;
  bool checkinFailed = false;
  String result = 'no_order';
  double? distance;
  int beforeCount = 0, afterCount = 0;
  List equipment = [];
  final comment = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Vizit ochilishi bilan avtomatik check-in (alohida "boshlash" oynasi yo'q)
    _checkin();
    _loadEquipment();
  }

  Future<void> _loadEquipment() async {
    try {
      final e = await Api.get('/api/clients/${widget.client['id']}/equipment');
      equipment = (e is List) ? e : ((e['items'] ?? []) as List);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  void dispose() {
    comment.dispose();
    super.dispose();
  }

  Future<void> _checkin() async {
    setState(() {
      busy = true;
      checkinFailed = false;
    });
    try {
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition();
      } catch (_) {}
      if (pos != null && widget.client['lat'] != null) {
        distance = Geolocator.distanceBetween(
            pos.latitude,
            pos.longitude,
            asNum(widget.client['lat']).toDouble(),
            asNum(widget.client['lng']).toDouble());
      }
      final d = await Api.post('/api/visits/checkin', {
        'client_id': widget.client['id'],
        'lat': pos?.latitude,
        'lng': pos?.longitude,
        'gps_ok': pos != null,
        'client_uuid': DateTime.now().millisecondsSinceEpoch.toString(),
      });
      setState(() => visitId = d['id']);
    } catch (e) {
      if (mounted) {
        setState(() => checkinFailed = true);
        snack(context, '$e');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// Faqat KAMERA (galereya yo'q). Rasm olgach ilova ichida tasdiq oynasi:
  /// "Изменить" (qayta olish) yoki "Готово" (tasdiqlash). Tasdiqlansa yo'lni
  /// qaytaradi, aks holda null.
  Future<String?> _capturePhoto() async {
    while (true) {
      final x = await ImagePicker().pickImage(
          source: ImageSource.camera,
          imageQuality: 60,
          requestFullMetadata: false);
      if (x == null) return null;
      if (!mounted) return null;
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(18)),
                child: Image.file(File(x.path),
                    height: 340, width: double.infinity, fit: BoxFit.cover),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context, false),
                      icon: const Icon(Icons.refresh),
                      label: Text(tr('Изменить', 'Изменить')),
                      style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(context, true),
                      style: FilledButton.styleFrom(
                          backgroundColor: brand,
                          padding: const EdgeInsets.symmetric(vertical: 12)),
                      icon: const Icon(Icons.check),
                      label: Text(tr('Готово', 'Готово')),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      );
      if (ok == true) return x.path;
      // aks holda: qayta rasimga olish (davom etadi)
    }
  }

  Future<void> _addPhoto(String type) async {
    final path = await _capturePhoto();
    if (path == null) return;
    final okSent =
        await SyncStore.sendOrQueuePhoto(visitId: visitId, path: path, type: type);
    if (mounted) {
      setState(() {
        if (type == 'before') {
          beforeCount++;
        } else {
          afterCount++;
        }
      });
      snack(
          context,
          okSent
              ? tr('Foto yuklandi', 'Фото загружено')
              : tr('Foto navbatga saqlandi (sinxron qiling)',
                  'Фото в очереди (синхронизируйте)'));
    }
  }

  Future<void> _checkout() async {
    try {
      final cm = Uri.encodeComponent(comment.text.trim());
      await Api.post(
          '/api/visits/$visitId/checkout?result=$result&comment=$cm', {});
      if (!mounted) return;
      final rl = result == 'order'
          ? tr('Zakaz bilan', 'С заказом')
          : result == 'closed'
              ? tr('Yopiq', 'Закрыто')
              : tr('Zakazsiz', 'Без заказа');
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: ok, size: 42),
          title: Text(tr('Vizit yakunlandi', 'Визит завершён'),
              textAlign: TextAlign.center),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${tr('Natija', 'Результат')}: $rl',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                  '${tr('Foto', 'Фото')}: ${beforeCount + afterCount}  ·  До: $beforeCount / После: $afterCount',
                  style: const TextStyle(color: muted, fontSize: 12.5)),
            ],
          ),
          actions: [
            Center(
              child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK')),
            )
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) snack(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          GradientHeader(
            padding: const EdgeInsets.fromLTRB(8, 4, 18, 22),
            child: Row(children: [
              IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back, color: Colors.white)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${widget.client['name'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800)),
                    Text(tr('Tashrif', 'Визит'),
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                            fontSize: 13)),
                  ],
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: visitId == null
                ? Column(children: [
                    const SizedBox(height: 40),
                    if (checkinFailed) ...[
                      const Icon(Icons.wifi_off, size: 52, color: warn),
                      const SizedBox(height: 16),
                      Text(tr('Tashrif boshlanmadi', 'Визит не начался'),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(
                          tr('Internetni tekshiring va qayta urinib ko‘ring',
                              'Проверьте интернет и повторите'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: muted)),
                      const SizedBox(height: 24),
                      GradientButton(
                        text: tr('Qayta urinish', 'Повторить'),
                        icon: Icons.refresh,
                        busy: busy,
                        onTap: _checkin,
                      ),
                    ] else ...[
                      const SizedBox(height: 8),
                      const CircularProgressIndicator(color: brand),
                      const SizedBox(height: 20),
                      Text(tr('Tashrif boshlanmoqda…', 'Визит начинается…'),
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(
                          tr('GPS joylashuvingiz qayd etilmoqda',
                              'GPS-местоположение фиксируется'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: muted)),
                    ],
                  ])
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Panel(
                        color: ok.withOpacity(0.08),
                        child: Row(children: [
                          const Icon(Icons.check_circle, color: ok),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Text(tr('Tashrif boshlandi', 'Визит начат'),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700))),
                          if (distance != null)
                            Pill('${distance!.round()} m',
                                color: distance! <= 300 ? ok : warn,
                                icon: Icons.place),
                        ]),
                      ),
                      const SizedBox(height: 16),
                      _action(
                        icon: Icons.shopping_cart,
                        color: brand,
                        title: tr('Zakaz olish', 'Оформить заказ'),
                        sub: tr('Mahsulot tanlab savat yaratish',
                            'Выбрать товары в корзину'),
                        onTap: () async {
                          final okr = await Navigator.push<bool>(
                              context,
                              fadeRoute(OrderScreen(
                                  client: widget.client, visitId: visitId!)));
                          if (okr == true) setState(() => result = 'order');
                        },
                      ),
                      const SizedBox(height: 18),
                      Row(children: [
                        Text(tr('Foto-otchyot', 'Фото-отчёт'),
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, color: ink)),
                        const SizedBox(width: 6),
                        const Icon(Icons.photo_camera, size: 15, color: muted),
                        const SizedBox(width: 3),
                        Text(tr('(faqat kamera)', '(только камера)'),
                            style: const TextStyle(color: muted, fontSize: 11.5)),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                            child: _photoBtn(tr('Foto: До', 'Фото: До'),
                                Icons.photo_camera_back, beforeCount,
                                () => _addPhoto('before'))),
                        const SizedBox(width: 12),
                        Expanded(
                            child: _photoBtn(tr('Foto: После', 'Фото: После'),
                                Icons.photo_camera_front, afterCount,
                                () => _addPhoto('after'))),
                      ]),
                      if (equipment.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(children: [
                            const Icon(Icons.info_outline,
                                size: 15, color: warn),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                  tr('Oborudovaniya (${equipment.length}) rasmini ham До/После oling',
                                      'Сделайте фото До/После оборудования (${equipment.length})'),
                                  style: const TextStyle(
                                      color: muted, fontSize: 12)),
                            ),
                          ]),
                        ),
                      const SizedBox(height: 20),
                      Text(tr('Tashrif natijasi', 'Результат визита'),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, color: ink)),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, children: [
                        _res(tr('Zakaz', 'Заказ'), 'order'),
                        _res(tr('Zakazsiz', 'Без заказа'), 'no_order'),
                        _res(tr('Yopiq', 'Закрыто'), 'closed'),
                      ]),
                      const SizedBox(height: 16),
                      TextField(
                        controller: comment,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: tr('Izoh (ixtiyoriy)', 'Комментарий'),
                          prefixIcon: const Icon(Icons.comment_outlined),
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 24),
                      GradientButton(
                        text: tr('Tashrifni yakunlash', 'Завершить визит'),
                        icon: Icons.logout,
                        gradient:
                            const LinearGradient(colors: [danger, accent2]),
                        onTap: _checkout,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _res(String label, String val) {
    final sel = result == val;
    return ChoiceChip(
      label: Text(label),
      selected: sel,
      onSelected: (_) => setState(() => result = val),
      selectedColor: brand,
      labelStyle: TextStyle(
          color: sel ? Colors.white : ink, fontWeight: FontWeight.w600),
    );
  }

  Widget _photoBtn(String label, IconData icon, int count, VoidCallback onTap) {
    final done = count > 0;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
            color: done ? ok.withOpacity(0.10) : info.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: done ? ok : line)),
        child: Column(children: [
          Icon(icon, color: done ? ok : info, size: 26),
          const SizedBox(height: 6),
          Text(label,
              style: const TextStyle(fontWeight: FontWeight.w700, color: ink)),
          if (done)
            Text('$count ${tr('ta', 'шт')}',
                style: const TextStyle(
                    color: ok, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  Widget _action(
      {required IconData icon,
      required Color color,
      required String title,
      required String sub,
      required VoidCallback onTap}) {
    return Panel(
      onTap: onTap,
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14)),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style:
                      const TextStyle(fontWeight: FontWeight.w700, color: ink)),
              const SizedBox(height: 2),
              Text(sub, style: const TextStyle(color: muted, fontSize: 12.5)),
            ],
          ),
        ),
        const Icon(Icons.chevron_right, color: muted),
      ]),
    );
  }
}

// ================= AKSIYALAR (server bilan sinxron) =================
class PromosScreen extends StatefulWidget {
  const PromosScreen({super.key});
  @override
  State<PromosScreen> createState() => _PromosScreenState();
}

class _PromosScreenState extends State<PromosScreen> {
  List items = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Api.get('/api/promos');
      items = d['items'] ?? [];
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  String _kindLabel(String k) => k == 'price'
      ? tr('Maxsus narx', 'Спец. цена')
      : (k == 'gift' ? tr('Sovg‘a', 'Подарок') : tr('Chegirma', 'Скидка'));

  String _value(Map p) {
    switch ('${p['kind']}') {
      case 'price':
        return money(asNum(p['special_price']));
      case 'gift':
        return '${asNum(p['min_qty']).round()}+${asNum(p['gift_qty']).round()}'
            '${p['gift_name'] != null ? ' · ${p['gift_name']}' : ''}';
      default:
        return '−${asNum(p['discount_pct']).round()}%';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(children: [
        GradientHeader(
          child: Row(children: [
            IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back, color: Colors.white)),
            Text(tr('Aksiyalar', 'Акции'),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800)),
          ]),
        ),
        Expanded(
          child: loading
              ? const ListShimmer()
              : (items.isEmpty
                  ? EmptyState(
                      icon: Icons.local_offer_outlined,
                      text: tr('Faol aksiya yo‘q', 'Нет активных акций'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final p = items[i] as Map;
                        return Panel(
                          padding: const EdgeInsets.all(14),
                          child: Row(children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                  color: accent.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(12)),
                              child: const Icon(Icons.local_offer,
                                  color: accent),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${p['name'] ?? ''}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: ink)),
                                  const SizedBox(height: 3),
                                  Text(
                                      '${_kindLabel('${p['kind']}')} · ${p['product_name'] ?? tr('Barcha mahsulot', 'Все товары')}',
                                      style: const TextStyle(
                                          color: muted, fontSize: 12.5)),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                  color: accent,
                                  borderRadius: BorderRadius.circular(10)),
                              child: Text(_value(p),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12.5)),
                            ),
                          ]),
                        );
                      },
                    )),
        ),
      ]),
    );
  }
}

// ================= ZAKAZ (savat + blok/dona + rasm) =================
class OrderScreen extends StatefulWidget {
  final Map client;
  final int visitId;
  const OrderScreen({super.key, required this.client, required this.visitId});
  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  List products = [];
  final Map<int, Map> cart = {}; // id -> {product, qty(dona)}
  bool loading = true;
  String q = '';
  String cat = '';
  final _orderComment = TextEditingController();
  DateTime? _deliveryDate;
  // Aksiyalar (server bilan sinxron)
  final Map<int, Map> promoByProduct = {}; // product_id -> promo
  Map? promoAll; // barcha mahsulotga foizli aksiya

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _orderComment.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await Api.get('/api/products?limit=500');
      products = d['items'] ?? [];
    } catch (_) {}
    try {
      final pr = await Api.get('/api/promos');
      for (final x in (pr['items'] ?? [])) {
        if (x['product_id'] != null) {
          promoByProduct[x['product_id'] as int] = x;
        } else if ('${x['kind']}' == 'percent') {
          promoAll = x; // barcha mahsulotga chegirma
        }
      }
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  // Mahsulotga tegishli aksiya (avval maxsus, keyin umumiy foiz)
  Map? _promoFor(int id) => promoByProduct[id] ?? promoAll;

  // Aksiyani hisobga olgan birlik narx
  num _effPrice(Map p) {
    final base = asNum(p['price']);
    final pr = _promoFor(p['id'] as int);
    if (pr == null) return base;
    if ('${pr['kind']}' == 'percent') {
      return base * (1 - asNum(pr['discount_pct']) / 100);
    }
    if ('${pr['kind']}' == 'price' && pr['special_price'] != null) {
      return asNum(pr['special_price']);
    }
    return base; // gift -> narx o'zgarmaydi
  }

  // Qisqa aksiya yozuvi (badge uchun), aks holda null
  String? _promoLabel(Map p) {
    final pr = _promoFor(p['id'] as int);
    if (pr == null) return null;
    switch ('${pr['kind']}') {
      case 'percent':
        return '−${asNum(pr['discount_pct']).round()}%';
      case 'price':
        return tr('Aksiya', 'Акция');
      case 'gift':
        return '${asNum(pr['min_qty']).round()}+${asNum(pr['gift_qty']).round()}';
    }
    return null;
  }

  // Savatdagi sovg'alarni hisoblaydi: gift_product_id -> bepul dona
  Map<int, int> _gifts() {
    final g = <int, int>{};
    for (final e in cart.values) {
      final p = e['product'] as Map;
      final pr = promoByProduct[p['id']];
      if (pr != null && '${pr['kind']}' == 'gift') {
        final mq = asNum(pr['min_qty']).toInt();
        final gq = asNum(pr['gift_qty']).toInt();
        final gid = pr['gift_product_id'];
        if (mq > 0 && gq > 0 && gid != null) {
          final free = (asNum(e['qty']).toInt() ~/ mq) * gq;
          if (free > 0) g[gid as int] = (g[gid] ?? 0) + free;
        }
      }
    }
    return g;
  }

  String _prodName(int id) {
    final p = products.firstWhere((x) => x['id'] == id, orElse: () => null);
    return p == null ? '#$id' : '${p['name']}';
  }

  List<String> get cats {
    final s = <String>{};
    for (final p in products) {
      final c = '${p['category_name'] ?? ''}';
      if (c.isNotEmpty) s.add(c);
    }
    return s.toList();
  }

  List get filtered => products.where((p) {
        final name = '${p['name'] ?? ''}'.toLowerCase();
        if (q.isNotEmpty && !name.contains(q.toLowerCase())) return false;
        if (cat.isNotEmpty && '${p['category_name']}' != cat) return false;
        return true;
      }).toList();

  num get total => cart.values
      .fold<num>(0, (s, e) => s + _effPrice(e['product'] as Map) * asNum(e['qty']));
  int get itemsCount => cart.length;

  void _openProduct(Map p) {
    final id = p['id'] as int;
    final box = asNum(p['box_qty']).toInt();
    final unit = '${p['unit'] ?? 'dona'}';
    final price = asNum(p['price']);
    int blok = 0, dona = (cart[id]?['qty'] ?? 0) as int;
    // agar savatda bo'lsa, blok/dona ga ajratamiz
    if (box > 1 && dona > 0) {
      blok = dona ~/ box;
      dona = dona % box;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        int totalDona() => (box > 1 ? blok * box : 0) + dona;
        return Padding(
          padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                _prodImage(p, 60),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${p['name'] ?? ''}',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text('${money(price)} / $unit',
                          style: const TextStyle(
                              color: brand, fontWeight: FontWeight.w700)),
                      if (box > 1)
                        Text('1 ${tr('blok', 'блок')} = $box $unit',
                            style: const TextStyle(color: muted, fontSize: 12)),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 18),
              if (box > 1)
                _counter(tr('Blok', 'Блок'), blok,
                    (v) => setS(() => blok = v < 0 ? 0 : v)),
              if (box > 1) const SizedBox(height: 10),
              _counter(unit, dona, (v) => setS(() => dona = v < 0 ? 0 : v)),
              const SizedBox(height: 16),
              Row(children: [
                Text(tr('Jami', 'Итого'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
                const Spacer(),
                Text('${totalDona()} $unit · ${money(price * totalDona())}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, color: brand, fontSize: 15)),
              ]),
              const SizedBox(height: 14),
              GradientButton(
                text: tr('Savatga qo‘shish', 'В корзину'),
                icon: Icons.add_shopping_cart,
                onTap: () {
                  final tq = totalDona();
                  setState(() {
                    if (tq <= 0) {
                      cart.remove(id);
                    } else {
                      cart[id] = {'product': p, 'qty': tq};
                    }
                  });
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _counter(String label, int val, void Function(int) onCh) {
    return Row(children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      const Spacer(),
      IconButton(
          onPressed: () => onCh(val - 1),
          icon: const Icon(Icons.remove_circle_outline, color: danger)),
      InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _askQty(val, onCh),
        child: Container(
          width: 54,
          padding: const EdgeInsets.symmetric(vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
              border: Border.all(color: line),
              borderRadius: BorderRadius.circular(8)),
          child: Text('$val',
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        ),
      ),
      IconButton(
          onPressed: () => onCh(val + 1),
          icon: const Icon(Icons.add_circle, color: brand)),
    ]);
  }

  Future<void> _askQty(int cur, void Function(int) onCh) async {
    final c = TextEditingController(text: cur > 0 ? '$cur' : '');
    final r = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Sonini kiriting', 'Введите количество')),
        content: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(hintText: '0'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('Bekor', 'Отмена'))),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: brand),
              onPressed: () =>
                  Navigator.pop(ctx, int.tryParse(c.text.trim()) ?? cur),
              child: Text(tr('OK', 'OK'))),
        ],
      ),
    );
    if (r != null) onCh(r < 0 ? 0 : r);
  }

  Widget _prodImage(Map p, double size) {
    final img = p['image'];
    if (img != null && '$img'.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network('${Api.base}$img',
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _imgPlaceholder(size)),
      );
    }
    return _imgPlaceholder(size);
  }

  Widget _imgPlaceholder(double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            color: brand.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.inventory_2_outlined, color: brand),
      );

  @override
  Widget build(BuildContext context) {
    final list = filtered;
    return Scaffold(
      body: Column(
        children: [
          GradientHeader(
            padding: const EdgeInsets.fromLTRB(8, 4, 18, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon:
                          const Icon(Icons.arrow_back, color: Colors.white)),
                  Expanded(
                    child: Text('${widget.client['name'] ?? tr('Zakaz', 'Заказ')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    tooltip: tr('Aksiyalar', 'Акции'),
                    onPressed: () => Navigator.push(
                        context, fadeRoute(const PromosScreen())),
                    icon: const Icon(Icons.local_offer, color: Colors.white),
                  ),
                ]),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: TextField(
                    onChanged: (v) => setState(() => q = v),
                    decoration: InputDecoration(
                      hintText: tr('Mahsulot qidirish', 'Поиск товара'),
                      prefixIcon: const Icon(Icons.search),
                      fillColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (cats.isNotEmpty)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                children: [
                  _cc(tr('Hammasi', 'Все'), ''),
                  ...cats.map((c) => _cc(c, c)),
                ],
              ),
            ),
          Expanded(
            child: loading
                ? const ListShimmer()
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _prodTile(list[i]),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: cart.isEmpty
          ? null
          : SafeArea(
              child: Container(
                margin: const EdgeInsets.all(12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                    gradient: brandGradient,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: softShadow),
                child: Row(children: [
                  Stack(clipBehavior: Clip.none, children: [
                    const Icon(Icons.shopping_cart, color: Colors.white),
                    Positioned(
                      right: -8,
                      top: -8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                            color: accent2, shape: BoxShape.circle),
                        child: Text('$itemsCount',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ]),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(money(total),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 16)),
                  ),
                  FilledButton(
                    onPressed: _openCart,
                    style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: brandDark),
                    child: Text(tr('Rasmiylashtirish', 'Оформить'),
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ]),
              ),
            ),
    );
  }

  Widget _cc(String label, String val) {
    final sel = cat == val;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: sel,
        onSelected: (_) => setState(() => cat = val),
        selectedColor: brand,
        labelStyle: TextStyle(
            color: sel ? Colors.white : ink, fontWeight: FontWeight.w600),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: line)),
      ),
    );
  }

  Widget _prodTile(Map p) {
    final id = p['id'] as int;
    final qty = (cart[id]?['qty'] ?? 0) as int;
    final stock = asNum(p['stock']);
    final promoLabel = _promoLabel(p);
    final base = asNum(p['price']);
    final eff = _effPrice(p);
    final discounted = eff < base - 0.5;
    return Panel(
      padding: const EdgeInsets.all(12),
      onTap: () => _openProduct(p),
      child: Row(children: [
        _prodImage(p, 46),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(
                  child: Text('${p['name'] ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, color: ink)),
                ),
                if (promoLabel != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(6)),
                    child: Text(promoLabel,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800)),
                  ),
                ],
              ]),
              const SizedBox(height: 3),
              Row(children: [
                if (discounted) ...[
                  Text(money(base),
                      style: const TextStyle(
                          color: muted,
                          fontSize: 11.5,
                          decoration: TextDecoration.lineThrough)),
                  const SizedBox(width: 6),
                ],
                Text(money(eff),
                    style: TextStyle(
                        color: discounted ? accent : brand,
                        fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Text('· ${stock.round()} ${p['unit'] ?? 'dona'}',
                    style: const TextStyle(color: muted, fontSize: 12)),
              ]),
            ],
          ),
        ),
        qty > 0
            ? Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: brand,
                    borderRadius: BorderRadius.circular(20)),
                child: Text('$qty',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800)),
              )
            : const Icon(Icons.add_circle, color: brand, size: 30),
      ]),
    );
  }

  void _openCart() {
    String pay = 'cash';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          return Padding(
            padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                        color: line, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 14),
                Text(tr('Savat', 'Корзина'),
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: ListView(
                    shrinkWrap: true,
                    children: cart.values.map((e) {
                      final p = e['product'];
                      final qd = e['qty'] as int;
                      final id = p['id'] as int;
                      final price = _effPrice(p as Map);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${p['name']}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                Text('${money(price * qd)}',
                                    style: const TextStyle(
                                        color: brand,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                          IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                setState(() {
                                  final nv = qd - 1;
                                  if (nv <= 0) {
                                    cart.remove(id);
                                  } else {
                                    cart[id]!['qty'] = nv;
                                  }
                                });
                                if (cart.isEmpty) {
                                  Navigator.pop(ctx);
                                } else {
                                  setSheet(() {});
                                }
                              },
                              icon: const Icon(Icons.remove_circle_outline,
                                  color: danger, size: 22)),
                          SizedBox(
                              width: 28,
                              child: Text('$qd',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800))),
                          IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                setState(() => cart[id]!['qty'] = qd + 1);
                                setSheet(() {});
                              },
                              icon: const Icon(Icons.add_circle,
                                  color: brand, size: 22)),
                          IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                setState(() => cart.remove(id));
                                if (cart.isEmpty) {
                                  Navigator.pop(ctx);
                                } else {
                                  setSheet(() {});
                                }
                              },
                              icon: const Icon(Icons.delete_outline,
                                  color: muted, size: 20)),
                        ]),
                      );
                    }).toList(),
                  ),
                ),
                // Sovg'alar (aksiya bo'yicha bepul)
                ..._gifts().entries.map((g) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(children: [
                        const Icon(Icons.card_giftcard,
                            color: accent, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(
                                '${tr('Sovg‘a', 'Подарок')}: ${_prodName(g.key)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: accent,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12.5))),
                        Text('×${g.value}  ${tr('bepul', 'бесплатно')}',
                            style: const TextStyle(
                                color: accent,
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5)),
                      ]),
                    )),
                const Divider(),
                Row(children: [
                  Text(tr('Jami', 'Итого'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  const Spacer(),
                  Text(money(total),
                      style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                          color: brand)),
                ]),
                const SizedBox(height: 12),
                Text(tr('To‘lov turi', 'Вид оплаты'),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Row(children: [
                  _payChip(tr('Naqd', 'Наличные'), 'cash', pay,
                      (v) => setSheet(() => pay = v)),
                  _payChip(tr('O‘tkazma', 'Перевод'), 'transfer', pay,
                      (v) => setSheet(() => pay = v)),
                  _payChip(tr('Qarz', 'Долг'), 'debt', pay,
                      (v) => setSheet(() => pay = v)),
                ]),
                const SizedBox(height: 12),
                // Yetkazish kuni (kalendar)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    final now = DateTime.now();
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: _deliveryDate ??
                          now.add(const Duration(days: 1)),
                      firstDate: now,
                      lastDate: now.add(const Duration(days: 60)),
                    );
                    if (d != null) setSheet(() => _deliveryDate = d);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                        border: Border.all(color: line),
                        borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      const Icon(Icons.event, color: brand, size: 20),
                      const SizedBox(width: 10),
                      Text(tr('Yetkazish kuni', 'Дата доставки'),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Text(
                          _deliveryDate == null
                              ? tr('Tanlash', 'Выбрать')
                              : _deliveryDate!
                                  .toIso8601String()
                                  .substring(0, 10),
                          style: TextStyle(
                              color:
                                  _deliveryDate == null ? muted : brandDark,
                              fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _orderComment,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: tr('Izoh (ixtiyoriy)', 'Комментарий'),
                    prefixIcon: const Icon(Icons.comment_outlined),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _submit(pay, draft: true),
                      icon: const Icon(Icons.drafts_outlined),
                      label: Text(tr('Chernovik', 'Черновик')),
                      style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: GradientButton(
                      text: tr('Zakazni saqlash', 'Сохранить заказ'),
                      icon: Icons.check,
                      onTap: () => _submit(pay, draft: false),
                    ),
                  ),
                ]),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _payChip(String label, String val, String cur,
      void Function(String) onSel) {
    final sel = cur == val;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: sel,
        onSelected: (_) => onSel(val),
        selectedColor: brand,
        labelStyle: TextStyle(
            color: sel ? Colors.white : ink, fontWeight: FontWeight.w600),
      ),
    );
  }

  Future<void> _submit(String pay, {bool draft = false}) async {
    final body = <String, dynamic>{
      'client_id': widget.client['id'],
      'visit_id': widget.visitId,
      'pay_type': pay,
      'status': draft ? 'draft' : 'new',
      'comment': _orderComment.text.trim(),
      'delivery_date': _deliveryDate?.toIso8601String().substring(0, 10),
      'client_uuid': DateTime.now().millisecondsSinceEpoch.toString(),
      // Lokal ko'rsatish uchun (server e'tiborsiz qoldiradi):
      'client_name': widget.client['name'],
      'total': total,
      'items': [
        ...cart.values.map((e) => {
              'product_id': e['product']['id'],
              'qty': e['qty'],
              'price': _effPrice(e['product'] as Map), // aksiya narxi
            }),
        // Sovg'a qatorlari (bepul)
        ..._gifts().entries.map((g) => {
              'product_id': g.key,
              'qty': g.value,
              'price': 0,
            }),
      ],
    };
    final sent = await SyncStore.sendOrQueueOrder(body);
    if (mounted) {
      Navigator.pop(context); // sheet
      snack(
          context,
          sent
              ? (draft
                  ? tr('Chernovik saqlandi', 'Черновик сохранён')
                  : tr('Zakaz saqlandi', 'Заказ сохранён'))
              : tr('Zakaz navbatga saqlandi (sinxron qiling)',
                  'Заказ в очереди (синхронизируйте)'));
      Navigator.pop(context, true); // order screen
    }
  }
}
