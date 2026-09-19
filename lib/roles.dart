import 'package:flutter/material.dart';
import 'api.dart';
import 'main.dart';
import 'agent.dart' show money;

AppBar _bar(BuildContext c, String title) => AppBar(
      title: Text('SalesGO · $title'),
      backgroundColor: brand,
      foregroundColor: Colors.white,
      actions: [
        IconButton(
          onPressed: () async {
            await Api.logout();
            if (c.mounted) {
              Navigator.pushReplacement(
                  c, MaterialPageRoute(builder: (_) => const LoginScreen()));
            }
          },
          icon: const Icon(Icons.logout),
        )
      ],
    );

/// DOSTAVKA / EKSPEDITOR — yetkazish ro'yxati
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
    final d = await Api.get('/api/orders?status=collected');
    setState(() {
      orders = d['items'] ?? [];
      loading = false;
    });
  }

  Future<void> _deliver(int id) async {
    try {
      await Api.post('/api/orders/$id/status?status=delivered', {});
      _load();
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _bar(context, 'Dostavka'),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : orders.isEmpty
              ? const Center(child: Text('Yetkazadigan zakaz yo\'q'))
              : ListView.builder(
                  itemCount: orders.length,
                  itemBuilder: (_, i) {
                    final o = orders[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      child: ListTile(
                        title: Text('#${o['id']} · ${o['client_name']}'),
                        subtitle: Text('${o['pay_type']} · ${money(o['total'] ?? 0)}'),
                        trailing: FilledButton(
                            onPressed: () => _deliver(o['id']),
                            child: const Text('Yetkazdim')),
                      ),
                    );
                  },
                ),
    );
  }
}

/// INKASSATOR — qarzdorlardan pul yig'ish
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
    final d = await Api.get('/api/balances');
    setState(() {
      items = (d['items'] ?? []).where((x) => (x['balance'] ?? 0) > 0).toList();
      loading = false;
    });
  }

  Future<void> _pay(Map c) async {
    final ctrl = TextEditingController(text: '${c['balance']}');
    final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
              title: Text(c['name']),
              content: TextField(
                  controller: ctrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Summa')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Bekor')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Qabul')),
              ],
            ));
    if (ok != true) return;
    try {
      await Api.post('/api/payments', {
        'client_id': c['id'],
        'amount': double.tryParse(ctrl.text) ?? 0,
        'type': 'payment'
      });
      _load();
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _bar(context, 'Inkassator'),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (_, i) {
                final c = items[i];
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  child: ListTile(
                    title: Text(c['name']),
                    subtitle: Text('Qarz: ${money(c['balance'])}',
                        style: const TextStyle(color: Colors.red)),
                    trailing: FilledButton(
                        onPressed: () => _pay(c),
                        child: const Text('To\'lov')),
                  ),
                );
              },
            ),
    );
  }
}

/// SUPERVAYZER / ADMIN — kunlik ko'rsatkichlar
class SupervisorHome extends StatefulWidget {
  const SupervisorHome({super.key});
  @override
  State<SupervisorHome> createState() => _SupervisorHomeState();
}

class _SupervisorHomeState extends State<SupervisorHome> {
  Map? d;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      d = Map<String, dynamic>.from(await Api.get('/api/dashboard/supervisor'));
      setState(() {});
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _bar(context, 'Boshqaruv'),
      body: d == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              _card('Umumiy savdo', money(d!['sales']['total'])),
              _card('Naqd', money(d!['sales']['cash'])),
              _card('Qarz', money(d!['sales']['debt'])),
              _card('Tashrif (fakt)',
                  '${d!['funnel']['visits_plan']['fact']}'),
              _card('Muvaffaqiyatli',
                  '${d!['funnel']['successful']['pct']}%'),
            ]),
    );
  }

  Widget _card(String t, String v) => Card(
        child: ListTile(
          title: Text(t, style: const TextStyle(color: Colors.grey)),
          trailing: Text(v,
              style:
                  const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        ),
      );
}
