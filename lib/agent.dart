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
      bottomNavigationBar: NavigationBar(
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
  num salesToday = 0, ordersToday = 0, routeToday = 0, debtors = 0;
  List recent = [];

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
      routeToday = ((rt['items'] ?? []) as List).length;
      debtors = cl.where((x) => asNum(x['balance']) > 0).length;
      recent = items.take(6).toList();
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final name = '${Api.me?['name'] ?? 'Agent'}';
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
                Row(
                  children: [
                    const AnimatedLogo(size: 40),
                    const SizedBox(width: 8),
                    const Wordmark(size: 20, base: Colors.white),
                    const Spacer(),
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
                          icon: Icons.payments,
                          label: tr('Bugungi savdo', 'Продажа сегодня'),
                          value: salesToday,
                          isMoney: true,
                          color: brand)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: StatCard(
                          icon: Icons.receipt_long,
                          label: tr('Zakazlar', 'Заказы'),
                          value: ordersToday,
                          color: info)),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: StatCard(
                          icon: Icons.route,
                          label: tr('Bugun do‘konlar', 'Точки сегодня'),
                          value: routeToday,
                          color: accent)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: StatCard(
                          icon: Icons.error_outline,
                          label: tr('Qarzdorlar', 'Должники'),
                          value: debtors,
                          color: danger)),
                ]),
                SectionTitle(tr('Tezkor amallar', 'Быстрые действия')),
                Row(children: [
                  _Quick(
                      icon: Icons.route,
                      label: tr('Marshrut', 'Маршрут'),
                      color: brand,
                      onTap: () => widget.onGoto(1)),
                  _Quick(
                      icon: Icons.receipt_long,
                      label: tr('Zakazlar', 'Заказы'),
                      color: info,
                      onTap: () => widget.onGoto(2)),
                  _Quick(
                      icon: Icons.insert_chart,
                      label: tr('Hisobot', 'Отчёт'),
                      color: accent,
                      onTap: () => widget.onGoto(3)),
                  _Quick(
                      icon: Icons.refresh,
                      label: tr('Yangilash', 'Обновить'),
                      color: violet,
                      onTap: _load),
                ]),
                SectionTitle(tr('So‘nggi zakazlar', 'Последние заказы'),
                    trailing: TextButton(
                        onPressed: () => widget.onGoto(2),
                        child: Text(tr('Barchasi', 'Все')))),
                if (loading)
                  const Column(children: [
                    Shimmer(height: 64),
                    SizedBox(height: 10),
                    Shimmer(height: 64),
                  ])
                else if (recent.isEmpty)
                  Panel(child: EmptyState(text: tr('Bugun zakaz yo‘q', 'Сегодня заказов нет')))
                else
                  ...recent.map((o) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: OrderTile(o),
                      )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Quick extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _Quick(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16)),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 6),
              Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600, color: ink)),
            ],
          ),
        ),
      ),
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
  const OrderTile(this.o, {super.key, this.onTap});
  @override
  Widget build(BuildContext context) {
    final status = '${o['status'] ?? 'new'}';
    return Panel(
      padding: const EdgeInsets.all(12),
      onTap: onTap,
      child: Row(
        children: [
          Avatar('${o['client_name'] ?? '?'}', size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${o['client_name'] ?? tr('Mijoz', 'Клиент')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: ink)),
                const SizedBox(height: 2),
                Text('#${o['id']} · ${payLabel('${o['pay_type']}')}',
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
      if (filter == 'akb' && asNum(c['is_akb']) != 1) return false;
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
                      onPressed: () => Navigator.push(context,
                          fadeRoute(ClientsMapScreen(clients: all))),
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
          const SizedBox(width: 8),
          bal > 0
              ? Pill(shortMoney(bal), color: danger, icon: Icons.trending_up)
              : Pill(tr('Toza', 'Чисто'), color: ok, icon: Icons.check),
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
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Api.get('/api/clients/${widget.client['id']}/card');
      card = Map<String, dynamic>.from(d);
      weekdays = card['weekdays'] ?? [];
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = card['client'] ?? widget.client;
    final bal = asNum(card['balance'] ?? c['balance']);
    final photo = c['photo'];
    final stat = card['stat'] ?? {};
    return Scaffold(
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
                    Avatar('${c['name'] ?? '?'}', size: 54),
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
                          color: bal > 0 ? danger : ok)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: StatCard(
                          icon: Icons.receipt_long,
                          label: tr('Zakazlar', 'Заказы'),
                          value: asNum(stat['orders']),
                          color: info)),
                ]),
                if (weekdays.isNotEmpty) ...[
                  SectionTitle(tr('Tashrif kunlari', 'Дни визитов')),
                  Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: weekdays
                          .map<Widget>((w) => Pill(weekdayName(asNum(w).toInt()),
                              color: brand, icon: Icons.event))
                          .toList()),
                ],
                SectionTitle(tr('Ma‘lumot', 'Информация')),
                Panel(
                  child: Column(children: [
                    _row(Icons.phone, tr('Telefon', 'Телефон'), '${c['phone'] ?? '-'}'),
                    const Divider(height: 20),
                    _row(Icons.place, tr('Manzil', 'Адрес'),
                        '${c['address'] ?? c['territory_name'] ?? '-'}'),
                    const Divider(height: 20),
                    _row(Icons.badge, 'INN', '${c['inn'] ?? '-'}'),
                    const Divider(height: 20),
                    _row(Icons.map, tr('Koordinata', 'Координаты'),
                        c['lat'] != null ? '${c['lat']}, ${c['lng']}' : '-'),
                  ]),
                ),
                if (photo != null && '$photo'.isNotEmpty) ...[
                  SectionTitle(tr('Do‘kon rasmi', 'Фото точки')),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network('${Api.base}$photo',
                        height: 180,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                            height: 120,
                            color: const Color(0xFFF1F5F9),
                            child: const Center(
                                child: Icon(Icons.image_not_supported,
                                    color: muted)))),
                  ),
                ],
                const SizedBox(height: 20),
                GradientButton(
                  text: tr('Tashrif boshlash', 'Начать визит'),
                  icon: Icons.login,
                  onTap: () => Navigator.push(
                      context, fadeRoute(VisitScreen(client: c))),
                ),
                const SizedBox(height: 10),
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
  final Set<int> days = {};
  bool akb = false;
  double? lat, lng;
  int? territoryId, categoryId;
  List territories = [], categories = [];
  bool busy = false;

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
      'lat': lat,
      'lng': lng,
      'territory_id': territoryId,
      'category_id': categoryId,
      'is_akb': akb,
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
                SwitchListTile(
                  value: akb,
                  onChanged: (v) => setState(() => akb = v),
                  activeColor: brand,
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('AKB (faol baza)', 'АКБ (активная база)'),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 12),
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
  String status = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final path = status.isEmpty
          ? '/api/orders?limit=200'
          : '/api/orders?status=$status&limit=200';
      final d = await Api.get(path);
      all = d['items'] ?? [];
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  Future<void> _setStatus(Map o, String st) async {
    try {
      await Api.post('/api/orders/${o['id']}/status?status=$st', {});
      if (mounted) Navigator.pop(context);
      _load();
    } catch (e) {
      if (mounted) snack(context, '$e');
    }
  }

  void _openOrder(Map o) {
    final st = '${o['status'] ?? 'new'}';
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Text('#${o['id']}',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
              const Spacer(),
              Pill(statusLabel(st), color: statusColor(st)),
            ]),
            const SizedBox(height: 6),
            Text('${o['client_name'] ?? ''}',
                style: const TextStyle(color: muted)),
            const SizedBox(height: 4),
            Text(money(asNum(o['total'])),
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w900, color: brand)),
            const SizedBox(height: 18),
            if (st != 'canceled' && st != 'returned') ...[
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _setStatus(o, 'returned'),
                    icon: const Icon(Icons.assignment_return, color: violet),
                    label: Text(tr('Vozvrat', 'Возврат'),
                        style: const TextStyle(color: violet)),
                    style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: violet),
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _setStatus(o, 'canceled'),
                    icon: const Icon(Icons.cancel, color: danger),
                    label: Text(tr('Otmen', 'Отмена'),
                        style: const TextStyle(color: danger)),
                    style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: danger),
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                  ),
                ),
              ]),
            ] else
              Text(tr('Bu zakaz yopilgan', 'Этот заказ закрыт'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: muted)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
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
                        padding: const EdgeInsets.all(16),
                        itemCount: all.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (_, i) =>
                            OrderTile(all[i], onTap: () => _openOrder(all[i])),
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
        selectedColor: Colors.white,
        labelStyle: TextStyle(
            color: sel ? brandDark : Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 13),
        backgroundColor: Colors.white.withOpacity(0.18),
        side: BorderSide(color: Colors.white.withOpacity(0.4)),
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
                        child: OrderTile(o),
                      )),
              ],
            ),
          ),
        ],
      ),
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
              const Text('SalesGO v1.2',
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

  Widget _row(IconData ic, String k, String v) => Row(children: [
        Icon(ic, size: 18, color: muted),
        const SizedBox(width: 10),
        Text(k, style: const TextStyle(color: muted, fontSize: 13)),
        const Spacer(),
        Flexible(
            child: Text(v,
                textAlign: TextAlign.right,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, color: ink))),
      ]);
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
  String result = 'no_order';
  double? distance;

  Future<void> _checkin() async {
    setState(() => busy = true);
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
      if (mounted) snack(context, '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _photo() async {
    // Kamera rasmi ilova keshiga tushadi, telefon galereyasiga saqlanmaydi.
    final x = await ImagePicker().pickImage(
        source: ImageSource.camera, imageQuality: 60, requestFullMetadata: false);
    if (x == null) return;
    try {
      final url = await Api.uploadPhoto(File(x.path));
      await Api.post('/api/photos',
          {'visit_id': visitId, 'type': 'shelf', 'file_path': url});
      if (mounted) snack(context, tr('Foto yuklandi', 'Фото загружено'));
    } catch (e) {
      if (mounted) snack(context, '$e');
    }
  }

  Future<void> _checkout() async {
    try {
      await Api.post('/api/visits/$visitId/checkout?result=$result', {});
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
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                          color: brand.withOpacity(0.08),
                          shape: BoxShape.circle),
                      child:
                          const Icon(Icons.storefront, size: 56, color: brand),
                    ),
                    const SizedBox(height: 20),
                    Text(tr('Do‘konga yetib keldingizmi?', 'Вы прибыли в точку?'),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(tr('GPS joylashuvingiz qayd etiladi',
                        'Ваше GPS-местоположение будет записано'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: muted)),
                    const SizedBox(height: 24),
                    GradientButton(
                      text: tr('Tashrifni boshlash', 'Начать визит'),
                      icon: Icons.login,
                      busy: busy,
                      onTap: _checkin,
                    ),
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
                      const SizedBox(height: 12),
                      _action(
                        icon: Icons.camera_alt,
                        color: info,
                        title: tr('Javon rasmi', 'Фото полки'),
                        sub: tr('Merchandising uchun foto', 'Фото для мерчендайзинга'),
                        onTap: _photo,
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Api.get('/api/products?limit=500');
      products = d['items'] ?? [];
    } catch (_) {}
    if (mounted) setState(() => loading = false);
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
      .fold<num>(0, (s, e) => s + asNum(e['product']['price']) * asNum(e['qty']));
  int get itemsCount => cart.length;

  void _openProduct(Map p) {
    final id = p['id'] as int;
    final box = asNum(p['box_qty']).toInt();
    final unit = '${p['unit'] ?? 'dona'}';
    final price = asNum(p['price']);
    int blok = 0, dona = (cart[id]?['qty'] ?? 0) as int;
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
      SizedBox(
        width: 40,
        child: Text('$val',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontWeight: FontWeight.w900, fontSize: 18)),
      ),
      IconButton(
          onPressed: () => onCh(val + 1),
          icon: const Icon(Icons.add_circle, color: brand)),
    ]);
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
              Text('${p['name'] ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: ink)),
              const SizedBox(height: 3),
              Row(children: [
                Text(money(asNum(p['price'])),
                    style: const TextStyle(
                        color: brand, fontWeight: FontWeight.w700)),
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
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: ListView(
                    shrinkWrap: true,
                    children: cart.values.map((e) {
                      final p = e['product'];
                      final qd = e['qty'] as int;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(children: [
                          Expanded(
                              child: Text('${p['name']}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600))),
                          Text('$qd ${p['unit'] ?? ''} × ${money(asNum(p['price']))}',
                              style: const TextStyle(color: muted, fontSize: 12.5)),
                        ]),
                      );
                    }).toList(),
                  ),
                ),
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
                const SizedBox(height: 16),
                GradientButton(
                  text: tr('Zakazni saqlash', 'Сохранить заказ'),
                  icon: Icons.check,
                  onTap: () => _submit(pay),
                ),
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

  Future<void> _submit(String pay) async {
    try {
      await Api.post('/api/orders', {
        'client_id': widget.client['id'],
        'visit_id': widget.visitId,
        'pay_type': pay,
        'client_uuid': DateTime.now().millisecondsSinceEpoch.toString(),
        'items': cart.values
            .map((e) => {
                  'product_id': e['product']['id'],
                  'qty': e['qty'],
                  'price': e['product']['price'],
                })
            .toList(),
      });
      if (mounted) {
        Navigator.pop(context);
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) snack(context, '$e');
    }
  }
}
