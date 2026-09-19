import 'package:flutter/material.dart';
import 'api.dart';
import 'theme.dart';
import 'ui.dart';
import 'main.dart';

Widget _header(BuildContext context, String title, String subtitle) {
  return GradientHeader(
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Wordmark(size: 20, base: Colors.white),
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
          _header(context, 'Yetkazish', '${orders.length} ta zakaz kutmoqda'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(children: [
              Expanded(
                  child: StatCard(
                      icon: Icons.local_shipping,
                      label: 'Yetkaziladigan',
                      value: orders.length,
                      color: info)),
              const SizedBox(width: 12),
              Expanded(
                  child: StatCard(
                      icon: Icons.payments,
                      label: 'Summa',
                      value: total,
                      isMoney: true,
                      color: brand)),
            ]),
          ),
          Expanded(
            child: loading
                ? const ListShimmer()
                : orders.isEmpty
                    ? const EmptyState(
                        icon: Icons.local_shipping_outlined,
                        text: 'Yetkazadigan zakaz yo‘q')
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
                                      Text('${o['client_name'] ?? 'Mijoz'}',
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
                                    child: const Text('Yetkazdim')),
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
      items = (d['items'] ?? [])
          .where((x) => asNum(x['balance']) > 0)
          .toList();
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  Future<void> _pay(Map c) async {
    final ctrl = TextEditingController(text: '${asNum(c['balance']).round()}');
    final okr = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18)),
        title: Text('${c['name']}'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Summa'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Bekor')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Qabul')),
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
          _header(context, 'Inkassator', '${items.length} ta qarzdor'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(children: [
              Expanded(
                  child: StatCard(
                      icon: Icons.people,
                      label: 'Qarzdorlar',
                      value: items.length,
                      color: warn)),
              const SizedBox(width: 12),
              Expanded(
                  child: StatCard(
                      icon: Icons.account_balance_wallet,
                      label: 'Umumiy qarz',
                      value: total,
                      isMoney: true,
                      color: danger)),
            ]),
          ),
          Expanded(
            child: loading
                ? const ListShimmer()
                : items.isEmpty
                    ? const EmptyState(
                        icon: Icons.check_circle_outline,
                        text: 'Qarzdor yo‘q')
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
                                      Text('Qarz: ${money(asNum(c['balance']))}',
                                          style: const TextStyle(
                                              color: danger,
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                                FilledButton(
                                    onPressed: () => _pay(c),
                                    child: const Text('To‘lov')),
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
            _header(context, 'Boshqaruv', '${Api.me?['name'] ?? ''}'),
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
                              label: 'Umumiy savdo',
                              value: _p(['sales', 'total']),
                              isMoney: true,
                              color: brand)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: StatCard(
                              icon: Icons.money,
                              label: 'Naqd',
                              value: _p(['sales', 'cash']),
                              isMoney: true,
                              color: ok)),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                          child: StatCard(
                              icon: Icons.credit_card,
                              label: 'O‘tkazma',
                              value: _p(['sales', 'transfer']),
                              isMoney: true,
                              color: info)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: StatCard(
                              icon: Icons.error_outline,
                              label: 'Qarz',
                              value: _p(['sales', 'debt']),
                              isMoney: true,
                              color: danger)),
                    ]),
                    const SectionTitle('Tashriflar'),
                    Panel(
                      child: Column(children: [
                        _line('Reja', _p(['funnel', 'visits_plan', 'plan'])),
                        const Divider(height: 20),
                        _line('Fakt', _p(['funnel', 'visits_plan', 'fact'])),
                        const Divider(height: 20),
                        _line('Muvaffaqiyatli %',
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
