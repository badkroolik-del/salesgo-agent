import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'api.dart';
import 'theme.dart';
import 'ui.dart';
import 'main.dart';

String _today() => DateTime.now().toIso8601String().substring(0, 10);

void snack(BuildContext c, String s) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(s)));

// ================= SHELL (pastki navigatsiya) =================
class AgentShell extends StatefulWidget {
  const AgentShell({super.key});
  @override
  State<AgentShell> createState() => _AgentShellState();
}

class _AgentShellState extends State<AgentShell> {
  int idx = 0;
  bool working = false;
  Timer? gpsTimer;

  @override
  void dispose() {
    gpsTimer?.cancel();
    super.dispose();
  }

  Future<bool> _ensureLoc() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    return p == LocationPermission.always ||
        p == LocationPermission.whileInUse;
  }

  Future<void> toggleWork() async {
    if (!working) {
      if (!await _ensureLoc()) {
        if (mounted) snack(context, 'GPS ruxsatini yoqing');
        return;
      }
      setState(() => working = true);
      _sendGps();
      gpsTimer =
          Timer.periodic(const Duration(seconds: 60), (_) => _sendGps());
    } else {
      gpsTimer?.cancel();
      setState(() => working = false);
    }
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
      DashboardTab(
          working: working, onToggle: toggleWork, onGoto: (i) => setState(() => idx = i)),
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
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Bosh'),
          NavigationDestination(
              icon: Icon(Icons.storefront_outlined),
              selectedIcon: Icon(Icons.storefront),
              label: 'Mijozlar'),
          NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'Zakazlar'),
          NavigationDestination(
              icon: Icon(Icons.insert_chart_outlined),
              selectedIcon: Icon(Icons.insert_chart),
              label: 'Hisobot'),
          NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profil'),
        ],
      ),
    );
  }
}

// ================= DASHBOARD =================
class DashboardTab extends StatefulWidget {
  final bool working;
  final Future<void> Function() onToggle;
  final void Function(int) onGoto;
  const DashboardTab(
      {super.key,
      required this.working,
      required this.onToggle,
      required this.onGoto});
  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  bool loading = true;
  num salesToday = 0, ordersToday = 0, clientsTotal = 0, debtors = 0;
  List recent = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final o = await Api.get('/api/orders?d1=${_today()}&d2=${_today()}');
      final c = await Api.get('/api/clients?limit=500');
      final items = (o['items'] ?? []) as List;
      final cl = (c['items'] ?? []) as List;
      salesToday = asNum(o['sum']);
      ordersToday = asNum(o['count'] ?? items.length);
      clientsTotal = cl.length;
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
                    const Wordmark(size: 22, base: Colors.white),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          shape: BoxShape.circle),
                      child: const Icon(Icons.notifications_none,
                          color: Colors.white, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('${greeting()},',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.85), fontSize: 14)),
                Text(name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 16),
                _WorkBar(working: widget.working, onToggle: widget.onToggle),
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
                          label: 'Bugungi savdo',
                          value: salesToday,
                          isMoney: true,
                          color: brand)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: StatCard(
                          icon: Icons.receipt_long,
                          label: 'Zakazlar',
                          value: ordersToday,
                          color: info)),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: StatCard(
                          icon: Icons.storefront,
                          label: 'Mijozlar',
                          value: clientsTotal,
                          color: accent)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: StatCard(
                          icon: Icons.error_outline,
                          label: 'Qarzdorlar',
                          value: debtors,
                          color: danger)),
                ]),
                const SectionTitle('Tezkor amallar'),
                Row(children: [
                  _Quick(
                      icon: Icons.storefront,
                      label: 'Mijozlar',
                      color: brand,
                      onTap: () => widget.onGoto(1)),
                  _Quick(
                      icon: Icons.receipt_long,
                      label: 'Zakazlar',
                      color: info,
                      onTap: () => widget.onGoto(2)),
                  _Quick(
                      icon: Icons.insert_chart,
                      label: 'Hisobot',
                      color: accent,
                      onTap: () => widget.onGoto(3)),
                  _Quick(
                      icon: Icons.refresh,
                      label: 'Yangilash',
                      color: violet,
                      onTap: _load),
                ]),
                SectionTitle('So‘nggi zakazlar',
                    trailing: TextButton(
                        onPressed: () => widget.onGoto(2),
                        child: const Text('Barchasi'))),
                if (loading)
                  const Column(children: [
                    Shimmer(height: 64),
                    SizedBox(height: 10),
                    Shimmer(height: 64),
                  ])
                else if (recent.isEmpty)
                  const Panel(child: EmptyState(text: 'Bugun zakaz yo‘q'))
                else
                  ...recent.map((o) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _OrderTile(o),
                      )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkBar extends StatelessWidget {
  final bool working;
  final Future<void> Function() onToggle;
  const _WorkBar({required this.working, required this.onToggle});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.16),
          borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Icon(working ? Icons.gps_fixed : Icons.gps_off,
              color: Colors.white, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(working ? 'Ish rejimida' : 'Ish boshlanmagan',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15)),
                Text(working ? 'GPS yoniq · har 60 s' : 'Kunni boshlash uchun bosing',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.85), fontSize: 12)),
              ],
            ),
          ),
          FilledButton(
            onPressed: () => onToggle(),
            style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: working ? danger : brandDark),
            child: Text(working ? 'Tugat' : 'Boshla',
                style: const TextStyle(fontWeight: FontWeight.w800)),
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
                  style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: ink)),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  final Map o;
  const _OrderTile(this.o);
  @override
  Widget build(BuildContext context) {
    final status = '${o['status'] ?? 'new'}';
    return Panel(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Avatar('${o['client_name'] ?? '?'}', size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${o['client_name'] ?? 'Mijoz'}',
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
              Pill(statusLabel(status),
                  color: statusColor(status)),
            ],
          ),
        ],
      ),
    );
  }
}

String payLabel(String p) {
  switch (p) {
    case 'cash':
      return 'Naqd';
    case 'transfer':
      return 'O‘tkazma';
    case 'debt':
      return 'Qarz';
    default:
      return p;
  }
}

String statusLabel(String s) {
  switch (s) {
    case 'new':
      return 'Yangi';
    case 'collected':
      return 'Yig‘ilgan';
    case 'shipped':
      return 'Yo‘lda';
    case 'delivered':
      return 'Yetkazildi';
    case 'canceled':
      return 'Bekor';
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
    case 'shipped':
      return info;
    case 'collected':
      return warn;
    default:
      return muted;
  }
}

// ================= MIJOZLAR =================
class ClientsTab extends StatefulWidget {
  const ClientsTab({super.key});
  @override
  State<ClientsTab> createState() => _ClientsTabState();
}

class _ClientsTabState extends State<ClientsTab> {
  List all = [];
  bool loading = true;
  String q = '';
  String filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final d = await Api.get('/api/clients?limit=500');
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
    return Column(
      children: [
        GradientHeader(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Mijozlar',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Text('${all.length} ta',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.85))),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                onChanged: (v) => setState(() => q = v),
                decoration: const InputDecoration(
                  hintText: 'Do‘kon nomi bo‘yicha qidirish',
                  prefixIcon: Icon(Icons.search),
                  fillColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(children: [
            _chip('Hammasi', 'all'),
            _chip('Qarzli', 'debt'),
            _chip('AKB', 'akb'),
          ]),
        ),
        Expanded(
          child: loading
              ? const ListShimmer()
              : list.isEmpty
                  ? const EmptyState(
                      icon: Icons.storefront_outlined,
                      text: 'Mijoz topilmadi')
                  : RefreshIndicator(
                      color: brand,
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: list.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (_, i) => _clientTile(list[i]),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _chip(String label, String val) {
    final sel = filter == val;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        label: Text(label),
        selected: sel,
        onSelected: (_) => setState(() => filter = val),
        selectedColor: brand,
        labelStyle: TextStyle(
            color: sel ? Colors.white : ink,
            fontWeight: FontWeight.w600,
            fontSize: 13),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: line)),
      ),
    );
  }

  Widget _clientTile(Map c) {
    final bal = asNum(c['balance']);
    return Panel(
      padding: const EdgeInsets.all(12),
      onTap: () =>
          Navigator.push(context, fadeRoute(ClientCardScreen(client: c))),
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
              : const Pill('Toza', color: ok, icon: Icons.check),
        ],
      ),
    );
  }
}

// ================= MIJOZ KARTASI =================
class ClientCardScreen extends StatelessWidget {
  final Map client;
  const ClientCardScreen({super.key, required this.client});
  @override
  Widget build(BuildContext context) {
    final bal = asNum(client['balance']);
    final photo = client['photo'];
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          GradientHeader(
            padding: const EdgeInsets.fromLTRB(8, 4, 18, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back, color: Colors.white)),
                  const Text('Mijoz kartasi',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(children: [
                    Avatar('${client['name'] ?? '?'}', size: 54),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${client['name'] ?? ''}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          Text('${client['category_name'] ?? 'Mijoz'}',
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
                StatCard(
                    icon: Icons.account_balance_wallet,
                    label: bal > 0 ? 'Qarz balansi' : 'Balans (toza)',
                    value: bal,
                    isMoney: true,
                    color: bal > 0 ? danger : ok),
                const SectionTitle('Ma‘lumot'),
                Panel(
                  child: Column(children: [
                    _row(Icons.phone, 'Telefon', '${client['phone'] ?? '-'}'),
                    const Divider(height: 20),
                    _row(Icons.place, 'Manzil',
                        '${client['address'] ?? client['territory_name'] ?? '-'}'),
                    const Divider(height: 20),
                    _row(Icons.badge, 'INN', '${client['inn'] ?? '-'}'),
                    const Divider(height: 20),
                    _row(Icons.map, 'Koordinata',
                        client['lat'] != null
                            ? '${client['lat']}, ${client['lng']}'
                            : '-'),
                  ]),
                ),
                if (photo != null && '$photo'.isNotEmpty) ...[
                  const SectionTitle('Do‘kon rasmi'),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network(
                      '${Api.base}$photo',
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        height: 120,
                        color: const Color(0xFFF1F5F9),
                        child: const Center(
                            child: Icon(Icons.image_not_supported,
                                color: muted)),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                GradientButton(
                  text: 'Tashrif boshlash',
                  icon: Icons.login,
                  onTap: () => Navigator.push(
                      context, fadeRoute(VisitScreen(client: client))),
                ),
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GradientHeader(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Zakazlar',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _sc('Hammasi', ''),
                  _sc('Yangi', 'new'),
                  _sc('Yig‘ilgan', 'collected'),
                  _sc('Yo‘lda', 'shipped'),
                  _sc('Yetkazildi', 'delivered'),
                ]),
              ),
            ],
          ),
        ),
        Expanded(
          child: loading
              ? const ListShimmer()
              : all.isEmpty
                  ? const EmptyState(
                      icon: Icons.receipt_long_outlined,
                      text: 'Zakaz yo‘q')
                  : RefreshIndicator(
                      color: brand,
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: all.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (_, i) => _OrderTile(all[i]),
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
      final first =
          '${DateTime.now().toIso8601String().substring(0, 8)}01';
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
          const GradientHeader(
            child: Text('Bu oy — faoliyat',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800)),
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
                          label: 'Savdo',
                          value: sum,
                          isMoney: true,
                          color: brand)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: StatCard(
                          icon: Icons.receipt_long,
                          label: 'Zakazlar',
                          value: count,
                          color: info)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: StatCard(
                          icon: Icons.calculate,
                          label: 'O‘rtacha chek',
                          value: avg,
                          isMoney: true,
                          color: accent)),
                ]),
                const SectionTitle('To‘lov turlari bo‘yicha'),
                Panel(
                  child: Column(children: [
                    _payRow('Naqd', byPay['cash'] ?? 0, total, ok),
                    const SizedBox(height: 14),
                    _payRow('O‘tkazma', byPay['transfer'] ?? 0, total, info),
                    const SizedBox(height: 14),
                    _payRow('Qarz', byPay['debt'] ?? 0, total, danger),
                  ]),
                ),
                const SectionTitle('So‘nggi zakazlar'),
                if (loading)
                  const Shimmer(height: 64)
                else if (recent.isEmpty)
                  const Panel(child: EmptyState(text: 'Zakaz yo‘q'))
                else
                  ...recent.map((o) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _OrderTile(o),
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
class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});
  @override
  Widget build(BuildContext context) {
    final me = Api.me ?? {};
    final role = '${me['role'] ?? '-'}';
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        GradientHeader(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 26),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle),
                child: Avatar('${me['name'] ?? '?'}', size: 76),
              ),
              const SizedBox(height: 12),
              Text('${me['name'] ?? 'Foydalanuvchi'}',
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
                  _row(Icons.person, 'Login', '${me['login'] ?? me['name'] ?? '-'}'),
                  const Divider(height: 20),
                  _row(Icons.badge_outlined, 'Rol', roleLabel(role)),
                  const Divider(height: 20),
                  _row(Icons.business, 'Kompaniya',
                      '${me['company_name'] ?? '-'}'),
                ]),
              ),
              const SizedBox(height: 20),
              GradientButton(
                text: 'Chiqish',
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
              const SizedBox(height: 16),
              const Text('SalesGO v1.1',
                  style: TextStyle(color: muted, fontSize: 12)),
            ],
          ),
        ),
      ],
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
      return 'Savdo agenti';
    case 'delivery':
      return 'Ekspeditor';
    case 'collector':
      return 'Inkassator';
    case 'supervisor':
      return 'Supervayzer';
    case 'admin':
      return 'Administrator';
    case 'operator':
      return 'Operator';
    case 'cashier':
      return 'Kassir';
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
    final x = await ImagePicker()
        .pickImage(source: ImageSource.camera, imageQuality: 60);
    if (x == null) return;
    try {
      final url = await Api.uploadPhoto(File(x.path));
      await Api.post('/api/photos',
          {'visit_id': visitId, 'type': 'shelf', 'file_path': url});
      if (mounted) snack(context, 'Foto yuklandi');
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
                    Text('Tashrif',
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
                      child: const Icon(Icons.storefront,
                          size: 56, color: brand),
                    ),
                    const SizedBox(height: 20),
                    const Text('Do‘konga yetib keldingizmi?',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    const Text('GPS joylashuvingiz qayd etiladi',
                        style: TextStyle(color: muted)),
                    const SizedBox(height: 24),
                    GradientButton(
                      text: 'Tashrifni boshlash',
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
                          const Expanded(
                              child: Text('Tashrif boshlandi',
                                  style: TextStyle(
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
                        title: 'Zakaz olish',
                        sub: 'Mahsulot tanlab savat yaratish',
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
                        title: 'Javon rasmi',
                        sub: 'Merchandising uchun foto',
                        onTap: _photo,
                      ),
                      const SizedBox(height: 20),
                      const Text('Tashrif natijasi',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, color: ink)),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, children: [
                        _res('Zakaz', 'order'),
                        _res('Zakazsiz', 'no_order'),
                        _res('Yopiq', 'closed'),
                      ]),
                      const SizedBox(height: 24),
                      GradientButton(
                        text: 'Tashrifni yakunlash',
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

// ================= ZAKAZ (savat) =================
class OrderScreen extends StatefulWidget {
  final Map client;
  final int visitId;
  const OrderScreen({super.key, required this.client, required this.visitId});
  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  List products = [];
  final Map<int, Map> cart = {};
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
  int get items => cart.values.fold<int>(0, (s, e) => s + (e['qty'] as int));

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
                    child: Text('${widget.client['name'] ?? 'Zakaz'}',
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
                    decoration: const InputDecoration(
                      hintText: 'Mahsulot qidirish',
                      prefixIcon: Icon(Icons.search),
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
                  _cc('Hammasi', ''),
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                        child: Text('$items',
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
                    child: const Text('Rasmiylashtirish',
                        style: TextStyle(fontWeight: FontWeight.w800)),
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
      child: Row(children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
              color: brand.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.inventory_2_outlined, color: brand),
        ),
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
                Text('· ${stock.round()} dona',
                    style: const TextStyle(color: muted, fontSize: 12)),
              ]),
            ],
          ),
        ),
        _stepper(id, p, qty),
      ]),
    );
  }

  Widget _stepper(int id, Map p, int qty) {
    if (qty == 0) {
      return IconButton(
        onPressed: () => setState(() => cart[id] = {'product': p, 'qty': 1}),
        icon: const Icon(Icons.add_circle, color: brand, size: 30),
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
        onPressed: () => setState(() {
          final q = qty - 1;
          if (q <= 0) {
            cart.remove(id);
          } else {
            cart[id] = {'product': p, 'qty': q};
          }
        }),
        icon: const Icon(Icons.remove_circle_outline, color: danger),
      ),
      Text('$qty',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      IconButton(
        onPressed: () => setState(() => cart[id] = {'product': p, 'qty': qty + 1}),
        icon: const Icon(Icons.add_circle, color: brand),
      ),
    ]);
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
                        color: line,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Savat',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: ListView(
                    shrinkWrap: true,
                    children: cart.values.map((e) {
                      final p = e['product'];
                      final q = e['qty'] as int;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(children: [
                          Expanded(
                            child: Text('${p['name']}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                          ),
                          Text('$q × ${money(asNum(p['price']))}',
                              style: const TextStyle(color: muted)),
                        ]),
                      );
                    }).toList(),
                  ),
                ),
                const Divider(),
                Row(children: [
                  const Text('Jami',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  const Spacer(),
                  Text(money(total),
                      style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                          color: brand)),
                ]),
                const SizedBox(height: 12),
                const Text('To‘lov turi',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Row(children: [
                  _payChip('Naqd', 'cash', pay, (v) => setSheet(() => pay = v)),
                  _payChip('O‘tkazma', 'transfer', pay,
                      (v) => setSheet(() => pay = v)),
                  _payChip('Qarz', 'debt', pay, (v) => setSheet(() => pay = v)),
                ]),
                const SizedBox(height: 16),
                GradientButton(
                  text: 'Zakazni saqlash',
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
        Navigator.pop(context); // sheet
        Navigator.pop(context, true); // order screen
      }
    } catch (e) {
      if (mounted) snack(context, '$e');
    }
  }
}
