import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'theme.dart';
import 'ui.dart';

const _tashkent = LatLng(41.311081, 69.240562);

TileLayer _osm() => TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'uz.salesgo.agent',
    );

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
      final pos = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.best));
      final ll = LatLng(pos.latitude, pos.longitude);
      setState(() => picked = ll);
      _mc.move(ll, 16);
    } catch (_) {
      if (mounted) snack(context, tr('GPS aniqlanmadi', 'GPS не определён'));
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

/// Mijozlarni xaritada ko'rish.
class ClientsMapScreen extends StatelessWidget {
  final List clients;
  const ClientsMapScreen({super.key, required this.clients});
  @override
  Widget build(BuildContext context) {
    final pts = clients
        .where((c) => c['lat'] != null && c['lng'] != null)
        .toList();
    final center = pts.isNotEmpty
        ? LatLng(asNum(pts.first['lat']).toDouble(),
            asNum(pts.first['lng']).toDouble())
        : _tashkent;
    return Scaffold(
      body: Stack(children: [
        FlutterMap(
          options: MapOptions(initialCenter: center, initialZoom: 12),
          children: [
            _osm(),
            MarkerLayer(
              markers: pts.map((c) {
                return Marker(
                  point: LatLng(asNum(c['lat']).toDouble(),
                      asNum(c['lng']).toDouble()),
                  width: 44,
                  height: 44,
                  child: GestureDetector(
                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('${c['name'] ?? ''}'))),
                    child: Icon(Icons.location_on,
                        color: asNum(c['balance']) > 0 ? danger : brand,
                        size: 40),
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
                child: Text('${tr('Xaritada', 'На карте')}: ${pts.length}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: ink)),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
