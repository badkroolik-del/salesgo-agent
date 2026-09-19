import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'api.dart';
import 'main.dart';

String money(num n) => '${n.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ')} so\'m';

class AgentHome extends StatefulWidget {
  const AgentHome({super.key});
  @override
  State<AgentHome> createState() => _AgentHomeState();
}

class _AgentHomeState extends State<AgentHome> {
  bool working = false;
  Timer? gpsTimer;
  List clients = [];
  bool loading = true;
  Position? last;

  @override
  void initState() {
    super.initState();
    _loadClients();
  }

  @override
  void dispose() {
    gpsTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadClients() async {
    try {
      final d = await Api.get('/api/clients?limit=200');
      setState(() {
        clients = d['items'] ?? [];
        loading = false;
      });
    } catch (e) {
      setState(() => loading = false);
    }
  }

  Future<bool> _ensureLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    return p == LocationPermission.always || p == LocationPermission.whileInUse;
  }

  Future<void> _toggleWork() async {
    if (!working) {
      if (!await _ensureLocation()) {
        _snack('GPS ruxsati kerak');
        return;
      }
      setState(() => working = true);
      _sendGps();
      gpsTimer = Timer.periodic(const Duration(seconds: 60), (_) => _sendGps());
    } else {
      gpsTimer?.cancel();
      setState(() => working = false);
    }
  }

  Future<void> _sendGps() async {
    try {
      final pos = await Geolocator.getCurrentPosition();
      last = pos;
      await Api.post('/api/gps', {
        'points': [
          {
            'lat': pos.latitude,
            'lng': pos.longitude,
            'speed': pos.speed,
            'ts': DateTime.now().toIso8601String().substring(0, 19)
          }
        ]
      });
    } catch (_) {}
  }

  void _snack(String s) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(s)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('SalesGO · ${Api.me?['name'] ?? ''}'),
        backgroundColor: brand,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
              onPressed: () async {
                await Api.logout();
                if (mounted) {
                  Navigator.pushReplacement(context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()));
                }
              },
              icon: const Icon(Icons.logout))
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: working ? const Color(0xFFDCFCE7) : Colors.white,
            child: Row(
              children: [
                Icon(working ? Icons.gps_fixed : Icons.gps_off,
                    color: working ? brand : Colors.grey),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(working ? 'Ish davom etmoqda · GPS yoniq' : 'Ish boshlanmagan',
                        style: const TextStyle(fontWeight: FontWeight.bold))),
                FilledButton(
                  onPressed: _toggleWork,
                  style: FilledButton.styleFrom(
                      backgroundColor: working ? Colors.red : brand),
                  child: Text(working ? 'Ish tugat' : 'Ish boshla'),
                ),
              ],
            ),
          ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: clients.length,
                    itemBuilder: (_, i) {
                      final c = clients[i];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        child: ListTile(
                          title: Text(c['name'] ?? ''),
                          subtitle: Text(
                              '${c['territory_name'] ?? '-'} · ${c['phone'] ?? ''}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: working
                              ? () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => VisitScreen(client: c)))
                              : () => _snack('Avval "Ish boshla"'),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

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

  Future<void> _checkin() async {
    setState(() => busy = true);
    try {
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition();
      } catch (_) {}
      final d = await Api.post('/api/visits/checkin', {
        'client_id': widget.client['id'],
        'lat': pos?.latitude,
        'lng': pos?.longitude,
        'gps_ok': pos != null,
        'client_uuid': DateTime.now().millisecondsSinceEpoch.toString(),
      });
      setState(() => visitId = d['id']);
    } catch (e) {
      _snack('$e');
    } finally {
      setState(() => busy = false);
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
      _snack('Foto yuklandi');
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _checkout() async {
    try {
      await Api.post('/api/visits/$visitId/checkout?result=$result', {});
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _snack('$e');
    }
  }

  void _snack(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.client['name'] ?? ''),
          backgroundColor: brand,
          foregroundColor: Colors.white),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: visitId == null
            ? Center(
                child: FilledButton.icon(
                  onPressed: busy ? null : _checkin,
                  icon: const Icon(Icons.login),
                  label: const Text('Tashrifni boshlash (check-in)'),
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 16)),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: () async {
                      final ok = await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => OrderScreen(
                                  client: widget.client, visitId: visitId!)));
                      if (ok == true) setState(() => result = 'order');
                    },
                    icon: const Icon(Icons.shopping_cart),
                    label: const Text('Zakaz olish'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                      onPressed: _photo,
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Foto (javon)')),
                  const SizedBox(height: 12),
                  Text('Natija: $result',
                      style: const TextStyle(color: Colors.grey)),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _checkout,
                    style: FilledButton.styleFrom(backgroundColor: Colors.red),
                    icon: const Icon(Icons.logout),
                    label: const Text('Tashrifni yakunlash (check-out)'),
                  ),
                ],
              ),
      ),
    );
  }
}

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
  String pay = 'cash';
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await Api.get('/api/products?limit=500');
    setState(() {
      products = d['items'] ?? [];
      loading = false;
    });
  }

  num get total => cart.values
      .fold(0, (s, e) => s + (e['product']['price'] as num) * (e['qty'] as num));

  Future<void> _submit() async {
    if (cart.isEmpty) return;
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
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text('Zakaz'),
          backgroundColor: brand,
          foregroundColor: Colors.white),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: products.length,
              itemBuilder: (_, i) {
                final p = products[i];
                final id = p['id'] as int;
                final qty = cart[id]?['qty'] ?? 0;
                return ListTile(
                  title: Text(p['name'] ?? ''),
                  subtitle: Text(money(p['price'] ?? 0)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                        onPressed: qty > 0
                            ? () => setState(() {
                                  final q = qty - 1;
                                  if (q <= 0) {
                                    cart.remove(id);
                                  } else {
                                    cart[id] = {'product': p, 'qty': q};
                                  }
                                })
                            : null,
                        icon: const Icon(Icons.remove_circle_outline)),
                    Text('$qty', style: const TextStyle(fontWeight: FontWeight.bold)),
                    IconButton(
                        onPressed: () => setState(
                            () => cart[id] = {'product': p, 'qty': qty + 1}),
                        icon: const Icon(Icons.add_circle, color: brand)),
                  ]),
                );
              },
            ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(12),
        color: Colors.white,
        child: Row(children: [
          DropdownButton<String>(
            value: pay,
            items: const [
              DropdownMenuItem(value: 'cash', child: Text('Naqd')),
              DropdownMenuItem(value: 'transfer', child: Text('O\'tkazma')),
              DropdownMenuItem(value: 'debt', child: Text('Qarz')),
            ],
            onChanged: (v) => setState(() => pay = v!),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Text(money(total),
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 16))),
          FilledButton(onPressed: _submit, child: const Text('Saqlash')),
        ]),
      ),
    );
  }
}
