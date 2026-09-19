import 'package:flutter/material.dart';
import 'api.dart';
import 'theme.dart';
import 'ui.dart';
import 'maps.dart';
import 'main.dart';

Future<void> _openMap(BuildContext context) async {
  try {
    final d = await Api.get('/api/clients?limit=500');
    if (context.mounted) {
      Navigator.push(context,
          fadeRoute(ClientsMapScreen(clients: (d['items'] ?? []) as List)));
    }
  } catch (_) {}
}

Widget _header(BuildContext context, String title, String subtitle,
    {bool map = true}) {
  return GradientHeader(
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AnimatedWordmark(size: 20, base: Colors.white),
              const SizedBox(height: 10),
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800)),
              Text(subtitle,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.85), fontSize: 13)),
            ],
          ),
        ),
        if (map)
          IconButton(
            onPressed: () => _openMap(context),
            icon: const Icon(Icons.map, color: Colors.white),
          ),
        IconButton(
          onPressed: () async {
            await Api.logout();
            if (context.mounted) {
              Navigator.pushReplacement(
                  context, fadeRoute(const LoginScreen()));
            }
          },
          icon: const Icon(Icons.logout, color: Colors.white),
        ),
      ],
    ),
  );
}

void _snack(BuildContext c, String s) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(s)));

// ============ DOSTAVKA / EKSPEDITOR ============
class DeliveryHome extends StatefulWidget {
  const DeliveryHome({super.key});
  @override
  State<DeliveryHome> createState() => _DeliveryHomeState();
}

class _DeliveryHomeState extends State<DeliveryHome> {
  List orders = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final d = await Api.get('/api/orders?status=collected&limit=200');
      orders = d['items'] ?? [];
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  Future<void> _deliver(int id) async {
    try {
      await Api.post('/api/orders/$id/status?status=delivered', {});
      _load();
    } catch (e) {
      if (mounted) _snack(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = orders.fold<num>(0, (a, o) => a + asNum(o['total']));
    return Scaffold(
      body: Column(
        children: [
          _header(context, tr('Yetkazish', 'Доставка'),
              '${orders.length} ${tr('ta zakaz kutmoqda', 'заказ(ов) ожидает')}'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(children: [
              Expanded(
                  child: StatCard(
                      icon: Icons.local_shipping,
                      label: tr('Yetkaziladigan', 'К доставке'),
                      value: orders.length,
                      color: info)),
              const SizedBox(width: 12),
              Expanded(
                  child: StatCard(
                      icon: Icons.payments,
                      label: tr('Summa', 'Сумма'),
                      value: total,
                      isMoney: true,
                      color: brand)),
            ]),
          ),
          Expanded(
            child: loading
                ? const ListShimmer()
                : orders.isEmpty
                    ? EmptyState(
                        icon: Icons.local_shipping_outlined,
                        text: tr('Yetkazadigan zakaz yo‘q', 'Нет заказов для доставки'))
                    : RefreshIndicator(
                        color: brand,
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: orders.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final o = orders[i];
                            return Panel(
                              padding: const EdgeInsets.all(12),
                              child: Row(children: [
                                Avatar('${o['client_name'] ?? '?'}'),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('${o['client_name'] ?? tr('Mijoz', 'Клиент')}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: ink)),
                                      const SizedBox(height: 2),
                                      Text(
                                          '#${o['id']} · ${money(asNum(o['total']))}',
                                          style: const TextStyle(
                                              color: muted, fontSize: 12.5)),
                                    ],
                                  ),
                                ),
                                FilledButton(
                                    onPressed: () => _deliver(o['id']),
                                    child: Text(tr('Yetkazdim', 'Доставил'))),
                              ]),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

// ============ INKASSATOR ============
class CollectorHome extends StatefulWidget {
  const CollectorHome({super.key});
  @override
  State<CollectorHome> createState() => _CollectorHomeState();
}

class _CollectorHomeState extends State<CollectorHome> {
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
      final d = await Api.get('/api/balances');
      items =
          (d['items'] ?? []).where((x) => asNum(x['balance']) > 0).toList();
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  Future<void> _pay(Map c) async {
    final ctrl = TextEditingController(text: '${asNum(c['balance']).round()}');
    final okr = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('${c['name']}'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: tr('Summa', 'Сумма')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('Bekor', 'Отмена'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('Qabul', 'Принять'))),
        ],
      ),
    );
    if (okr != true) return;
    try {
      await Api.post('/api/payments', {
        'client_id': c['id'],
        'amount': double.tryParse(ctrl.text) ?? 0,
        'type': 'payment',
      });
      _load();
    } catch (e) {
      if (mounted) _snack(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = items.fold<num>(0, (a, c) => a + asNum(c['balance']));
    return Scaffold(
      body: Column(
        children: [
          _header(context, tr('Inkassator', 'Инкассатор'),
              '${items.length} ${tr('ta qarzdor', 'должник(ов)')}'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(children: [
              Expanded(
                  child: StatCard(
                      icon: Icons.people,
                      label: tr('Qarzdorlar', 'Должники'),
                      value: items.length,
                      color: warn)),
              const SizedBox(width: 12),
              Expanded(
                  child: StatCard(
                      icon: Icons.account_balance_wallet,
                      label: tr('Umumiy qarz', 'Общий долг'),
                      value: total,
                      isMoney: true,
                      color: danger)),
            ]),
          ),
          Expanded(
            child: loading
                ? const ListShimmer()
                : items.isEmpty
                    ? EmptyState(
                        icon: Icons.check_circle_outline,
                        text: tr('Qarzdor yo‘q', 'Должников нет'))
                    : RefreshIndicator(
                        color: brand,
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final c = items[i];
                            return Panel(
                              padding: const EdgeInsets.all(12),
                              child: Row(children: [
                                Avatar('${c['name'] ?? '?'}'),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('${c['name'] ?? ''}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: ink)),
                                      const SizedBox(height: 2),
                                      Text(
                                          '${tr('Qarz', 'Долг')}: ${money(asNum(c['balance']))}',
                                          style: const TextStyle(
                                              color: danger,
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                                FilledButton(
                                    onPressed: () => _pay(c),
                                    child: Text(tr('To‘lov', 'Оплата'))),
                              ]),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

// ============ SUPERVAYZER / ADMIN ============
class SupervisorHome extends StatefulWidget {
  const SupervisorHome({super.key});
  @override
  State<SupervisorHome> createState() => _SupervisorHomeState();
}

class _SupervisorHomeState extends State<SupervisorHome> {
  Map? d;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      d = Map<String, dynamic>.from(
          await Api.get('/api/dashboard/supervisor'));
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  num _p(List keys) {
    dynamic cur = d;
    for (final k in keys) {
      if (cur is Map) {
        cur = cur[k];
      } else {
        return 0;
      }
    }
    return asNum(cur);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        color: brand,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            _header(context, tr('Boshqaruv', 'Управление'),
                '${Api.me?['name'] ?? ''}'),
            if (loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Column(children: [
                  Shimmer(height: 90),
                  SizedBox(height: 12),
                  Shimmer(height: 90),
                ]),
              )
            else
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                          child: StatCard(
                              icon: Icons.payments,
                              label: tr('Umumiy savdo', 'Общая продажа'),
                              value: _p(['sales', 'total']),
                              isMoney: true,
                              color: brand)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: StatCard(
                              icon: Icons.money,
                              label: tr('Naqd', 'Наличные'),
                              value: _p(['sales', 'cash']),
                              isMoney: true,
                              color: ok)),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                          child: StatCard(
                              icon: Icons.credit_card,
                              label: tr('O‘tkazma', 'Перевод'),
                              value: _p(['sales', 'transfer']),
                              isMoney: true,
                              color: info)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: StatCard(
                              icon: Icons.error_outline,
                              label: tr('Qarz', 'Долг'),
                              value: _p(['sales', 'debt']),
                              isMoney: true,
                              color: danger)),
                    ]),
                    SectionTitle(tr('Tashriflar', 'Визиты')),
                    Panel(
                      child: Column(children: [
                        _line(tr('Reja', 'План'),
                            _p(['funnel', 'visits_plan', 'plan'])),
                        const Divider(height: 20),
                        _line(tr('Fakt', 'Факт'),
                            _p(['funnel', 'visits_plan', 'fact'])),
                        const Divider(height: 20),
                        _line(tr('Muvaffaqiyatli %', 'Успешные %'),
                            _p(['funnel', 'successful', 'pct'])),
                      ]),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _line(String k, num v) => Row(children: [
        Text(k, style: const TextStyle(color: muted)),
        const Spacer(),
        Text(v.round().toString(),
            style: const TextStyle(
                fontWeight: FontWeight.w800, fontSize: 16, color: ink)),
      ]);
}
