import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'theme.dart';
import 'ui.dart';

const _tashkent = LatLng(41.311081, 69.240562);

TileLayer _osm() => TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'uz.salesgo.agent',
    );

Future<void> openRoute(double lat, double lng) async {
  final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
}

class _ZoomButtons extends StatelessWidget {
  final MapController mc;
  const _ZoomButtons({required this.mc});
  void _z(double d) {
    final c = mc.camera;
    mc.move(c.center, (c.zoom + d).clamp(3.0, 18.0));
  }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      FloatingActionButton.small(
        heroTag: 'zin',
        backgroundColor: Colors.white,
        foregroundColor: ink,
        onPressed: () => _z(1),
        child: const Icon(Icons.add),
      ),
      const SizedBox(height: 8),
      FloatingActionButton.small(
        heroTag: 'zout',
        backgroundColor: Colors.white,
        foregroundColor: ink,
        onPressed: () => _z(-1),
        child: const Icon(Icons.remove),
      ),
    ]);
  }
}

/// Lokatsiyani xaritada tanlash (GPS bilan aniqlash). LatLng qaytaradi.
class LocationPickerScreen extends StatefulWidget {
  final LatLng? initial;
  const LocationPickerScreen({super.key, this.initial});
  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final _mc = MapController();
  late LatLng picked;
  bool locating = false;

  @override
  void initState() {
    super.initState();
    picked = widget.initial ?? _tashkent;
    if (widget.initial == null) _myLocation();
  }

  Future<void> _myLocation() async {
    setState(() => locating = true);
    try {
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      final pos = await Geolocator.getCurrentPosition();
      final ll = LatLng(pos.latitude, pos.longitude);
      setState(() => picked = ll);
      _mc.move(ll, 16);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(tr('GPS aniqlanmadi', 'GPS не определён'))));
      }
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mc,
            options: MapOptions(
              initialCenter: picked,
              initialZoom: 15,
              onTap: (_, ll) => setState(() => picked = ll),
            ),
            children: [
              _osm(),
              MarkerLayer(markers: [
                Marker(
                  point: picked,
                  width: 46,
                  height: 46,
                  child: const Icon(Icons.location_on, color: danger, size: 46),
                ),
              ]),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                CircleAvatar(
                  backgroundColor: Colors.white,
                  child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back, color: ink)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: softShadow),
                    child: Text(
                      tr('Nuqtani belgilash uchun xaritaga bosing',
                          'Нажмите на карту, чтобы отметить точку'),
                      style: const TextStyle(fontSize: 12.5, color: muted),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          Positioned(
            right: 14,
            bottom: 150,
            child: _ZoomButtons(mc: _mc),
          ),
          Positioned(
            right: 14,
            bottom: 96,
            child: FloatingActionButton(
              heroTag: 'myloc',
              backgroundColor: Colors.white,
              foregroundColor: brand,
              onPressed: locating ? null : _myLocation,
              child: locating
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: GradientButton(
              text: tr('Shu joyni tanlash', 'Выбрать это место'),
              icon: Icons.check,
              onTap: () => Navigator.pop(context, picked),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mijozlarni xaritada ko'rish. Marker AKB bo'yicha rangli.
class ClientsMapScreen extends StatefulWidget {
  final List clients;
  final void Function(Map)? onOpen;
  const ClientsMapScreen({super.key, required this.clients, this.onOpen});
  @override
  State<ClientsMapScreen> createState() => _ClientsMapScreenState();
}

class _ClientsMapScreenState extends State<ClientsMapScreen> {
  final _mc = MapController();

  void _tap(Map c) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(18),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Avatar('${c['name'] ?? '?'}'),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${c['name'] ?? ''}',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                  Text('${c['address'] ?? '-'}',
                      style: const TextStyle(color: muted, fontSize: 12.5)),
                ],
              ),
            ),
            if (asNum(c['balance']) > 0)
              Pill(shortMoney(asNum(c['balance'])), color: danger),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            if (widget.onOpen != null)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onOpen!(c);
                  },
                  icon: const Icon(Icons.info_outline),
                  label: Text(tr('Karta', 'Карточка')),
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12)),
                ),
              ),
            if (widget.onOpen != null) const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: c['lat'] == null
                    ? null
                    : () {
                        Navigator.pop(context);
                        openRoute(asNum(c['lat']).toDouble(),
                            asNum(c['lng']).toDouble());
                      },
                icon: const Icon(Icons.directions),
                label: Text(tr('Marshrut', 'Маршрут')),
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pts =
        widget.clients.where((c) => c['lat'] != null && c['lng'] != null).toList();
    final center = pts.isNotEmpty
        ? LatLng(asNum(pts.first['lat']).toDouble(),
            asNum(pts.first['lng']).toDouble())
        : _tashkent;
    return Scaffold(
      body: Stack(children: [
        FlutterMap(
          mapController: _mc,
          options: MapOptions(initialCenter: center, initialZoom: 12),
          children: [
            _osm(),
            MarkerLayer(
              markers: pts.map((c) {
                final akb = asNum(c['orders_month']) > 0;
                return Marker(
                  point: LatLng(asNum(c['lat']).toDouble(),
                      asNum(c['lng']).toDouble()),
                  width: 44,
                  height: 44,
                  child: GestureDetector(
                    onTap: () => _tap(c),
                    child: Icon(Icons.location_on,
                        color: akb ? brand : danger, size: 40),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              CircleAvatar(
                backgroundColor: Colors.white,
                child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, color: ink)),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: softShadow),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.location_on, color: brand, size: 16),
                  const SizedBox(width: 3),
                  const Text('AKB', style: TextStyle(fontSize: 11, color: muted)),
                  const SizedBox(width: 8),
                  const Icon(Icons.location_on, color: danger, size: 16),
                  const SizedBox(width: 3),
                  const Text('OKB', style: TextStyle(fontSize: 11, color: muted)),
                  const SizedBox(width: 8),
                  Text('· ${pts.length}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, color: ink)),
                ]),
              ),
            ]),
          ),
        ),
        Positioned(right: 14, bottom: 30, child: _ZoomButtons(mc: _mc)),
      ]),
    );
  }
}
