import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'api.dart';
import 'theme.dart';
import 'ui.dart';
import 'sync.dart';
import 'mobile_cfg.dart';

/// ================= DALA XODIMI VIZITI (ekspeditor / inkassator / supervayzer) =================
/// Agent vizitidagidek: check-in (GPS, masofa, radius), foto-hisobot, asosiy amal, davomiylik, check-out.
/// Majburiyatlar paneldagi «Мобильное приложение» sozlamalaridan olinadi (MobileCfg).
class FieldVisitScreen extends StatefulWidget {
  final String role; // delivery | collector | supervisor
  final Map client;
  final Map? order;
  final num? debt;
  const FieldVisitScreen({super.key, required this.role, required this.client, this.order, this.debt});
  @override
  State<FieldVisitScreen> createState() => _FieldVisitScreenState();
}

class _FieldVisitScreenState extends State<FieldVisitScreen> {
  int? visitId;
  bool busy = true, tooFar = false;
  double? distance;
  Position? pos;
  final DateTime started = DateTime.now();
  final Map<String, int> photos = {};
  String? result; // order (bajarildi) | no_order
  String? reason;
  String method = 'cash';
  final amount = TextEditingController();
  final comment = TextEditingController();
  final Map<String, bool> audit = {};
  int rating = 0;
  Timer? tick;

  String get role => widget.role;
  bool get isDlv => role == 'delivery';
  bool get isCol => role == 'collector';
  bool get isSv => role == 'supervisor';

  static const _dlvReasons = [
    ['Mijoz yopiq', 'Клиент закрыт'],
    ['Pul yo‘q', 'Нет денег для оплаты'],
    ['Tovardan voz kechdi', 'Отказ от товара'],
    ['Omborida joy yo‘q', 'Нет места на складе клиента'],
    ['Boshqa', 'Другое'],
  ];
  static const _colReasons = [
    ['Mijoz yopiq', 'Клиент закрыт'],
    ['Pul yo‘q', 'Нет денег'],
    ['Qarz bilan rozi emas', 'Не согласен с долгом'],
    ['Keyinroq to‘laydi', 'Оплатит позже'],
    ['Boshqa', 'Другое'],
  ];
  static const _audit = {
    'sku': ['Tovar bor (SKU)', 'Наличие товара (SKU)'],
    'facing': ['Facing', 'Фейсинг'],
    'merch': ['Vykladka', 'Мерчендайзинг'],
    'price': ['Javondagi narx', 'Цены на полке'],
    'stock': ['Qoldiq', 'Остатки'],
    'competitor': ['Raqobatchilar', 'Конкуренты'],
  };

  /// Rolga mos foto turlari: [kalit, uz, ru, majburiy]
  List<List> get photoKinds {
    if (isDlv) {
      return [
        ['goods', 'Mijozdagi tovar', 'Товар у клиента', MobileCfg.b('dlv_photo')],
        ['doc', 'Imzoli nakladnoy', 'Накладная с подписью', MobileCfg.b('dlv_doc_photo')],
        if (MobileCfg.b('receipt_photo')) ['receipt', 'Kvitansiya', 'Квитанция', false],
      ];
    }
    if (isCol) return [['receipt', 'To‘lov kvitansiyasi', 'Квитанция об оплате', MobileCfg.b('col_receipt')]];
    return [
      ['before', 'Javon oldin', 'Полка до', MobileCfg.b('sv_photo')],
      ['after', 'Javon keyin', 'Полка после', false],
      ['audit', 'Audit', 'Аудит', false],
    ];
  }

  bool get radiusReq => isDlv ? MobileCfg.b('dlv_radius_req') : isCol ? MobileCfg.b('col_radius_req') : false;
  num get radius => isDlv ? MobileCfg.n('dlv_radius', 150) : isCol ? MobileCfg.n('col_radius', 200) : MobileCfg.n('sv_radius', 200);
  int get minMin => isDlv ? MobileCfg.n('dlv_min', 0).toInt() : 0;
  bool get reasonReq => isDlv ? MobileCfg.b('dlv_reason', true) : true;
  List get methods {
    final l = MobileCfg.l('pay_methods', const ['cash']);
    return l.isEmpty ? const ['cash'] : l;
  }

  @override
  void initState() {
    super.initState();
    if (isDlv && widget.order != null) amount.text = '${asNum(widget.order!['total']).round()}';
    if (isCol && widget.debt != null) amount.text = '${widget.debt!.round()}';
    if (isSv) {
      for (final k in MobileCfg.l('aud', const ['sku', 'facing', 'merch'])) {
        if (_audit.containsKey('$k')) audit['$k'] = true;
      }
    }
    method = '${methods.first}';
    tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    _checkin();
  }

  @override
  void dispose() {
    tick?.cancel();
    amount.dispose();
    comment.dispose();
    super.dispose();
  }

  Future<void> _checkin() async {
    setState(() => busy = true);
    try {
      try {
        pos = await Geolocator.getCurrentPosition();
      } catch (_) {}
      num? lat = widget.client['lat'] == null ? null : asNum(widget.client['lat']);
      num? lng = widget.client['lng'] == null ? null : asNum(widget.client['lng']);
      if (lat == null && widget.client['id'] != null) {
        try {
          final c = await Api.get('/api/clients/${widget.client['id']}');
          final m = (c is Map && c['client'] is Map) ? c['client'] : c;
          if (m is Map && m['lat'] != null) {
            lat = asNum(m['lat']);
            lng = asNum(m['lng']);
          }
        } catch (_) {}
      }
      if (pos != null && lat != null && lng != null && lat != 0) {
        distance = Geolocator.distanceBetween(pos!.latitude, pos!.longitude, lat.toDouble(), lng.toDouble());
      }
      tooFar = radiusReq && distance != null && distance! > radius;
      if (tooFar) return;
      final id = await SyncStore.sendOrQueueVisit({
        'client_id': widget.client['id'],
        'lat': pos?.latitude,
        'lng': pos?.longitude,
        'gps_ok': pos != null,
        'kind': role,
        if (widget.order != null) 'order_id': widget.order!['id'],
        'client_uuid': DateTime.now().millisecondsSinceEpoch.toString(),
      });
      visitId = id ?? -1;
    } catch (e) {
      if (mounted) _snack('$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _snack(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  Future<void> _photo(String kind) async {
    final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: MobileCfg.n('photo_q', 70).toInt().clamp(30, 100), maxWidth: MobileCfg.n('photo_w', 1200).toDouble(), requestFullMetadata: false);
    if (x == null) return;
    final okSent = await SyncStore.sendOrQueuePhoto(visitId: (visitId != null && visitId! > 0) ? visitId : null, path: x.path, type: kind);
    if (!mounted) return;
    setState(() => photos[kind] = (photos[kind] ?? 0) + 1);
    _snack(okSent ? tr('Foto yuklandi', 'Фото загружено') : tr('Foto navbatga saqlandi', 'Фото в очереди'));
  }

  Future<void> _finish() async {
    final mins = DateTime.now().difference(started).inSeconds / 60.0;
    if (result == null) return _snack(tr('Natijani tanlang', 'Выберите результат'));
    for (final k in photoKinds) {
      if (k[3] == true && (photos[k[0]] ?? 0) == 0) return _snack('${tr('Foto kerak', 'Нужно фото')}: ${tr(k[1], k[2])}');
    }
    if (MobileCfg.photoMin > 0 && photos.values.fold<int>(0, (a, b) => a + b) < MobileCfg.photoMin) {
      return _snack(tr('Kamida ${MobileCfg.photoMin} ta foto kerak', 'Нужно минимум ${MobileCfg.photoMin} фото'));
    }
    if (minMin > 0 && mins < minMin) return _snack(tr('Nuqtada kamida $minMin daqiqa bo‘ling', 'Будьте на точке не меньше $minMin мин'));
    if (result == 'no_order' && !isSv && reasonReq && reason == null) return _snack(tr('Sababini tanlang', 'Выберите причину'));
    final amt = num.tryParse(amount.text.replaceAll(' ', '')) ?? 0;
    final payNow = (isCol && result == 'order') || (isDlv && result == 'order' && MobileCfg.b('allow_pay') && amt > 0);
    if (isCol && result == 'order' && amt <= 0) return _snack(tr('Summani kiriting', 'Введите сумму'));
    setState(() => busy = true);
    try {
      if (isDlv && widget.order != null) {
        final st = result == 'order' ? 'delivered' : 'failed';
        final cm = Uri.encodeComponent(reason ?? comment.text.trim());
        await Api.post('/api/orders/${widget.order!['id']}/status?status=$st&comment=$cm', {});
      }
      if (payNow) {
        await Api.post('/api/payments', {
          'client_id': widget.client['id'],
          'amount': amt,
          'type': 'payment',
          'method': method,
          if (widget.order != null) 'order_id': widget.order!['id'],
        });
      }
      if (visitId != null && visitId! > 0) {
        final parts = <String>[];
        if (reason != null) parts.add(reason!);
        if (isSv) {
          if (audit.isNotEmpty) {
            parts.add('Аудит: ${audit.entries.map((e) => '${_audit[e.key]![1]} ${e.value ? 'OK' : 'проблема'}').join(', ')}');
          }
          if (rating > 0) parts.add('Оценка агента: $rating/5');
        }
        if (comment.text.trim().isNotEmpty) parts.add(comment.text.trim());
        final cm = Uri.encodeComponent(parts.join(' · '));
        await Api.post('/api/visits/$visitId/checkout?result=${result == 'order' ? 'order' : 'no_order'}&comment=$cm', {});
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) _snack('$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _chip(String label, bool sel, VoidCallback onTap, {Color c = brand}) => ChoiceChip(
        label: Text(label),
        selected: sel,
        onSelected: (_) => onTap(),
        selectedColor: c,
        labelStyle: TextStyle(color: sel ? Colors.white : ink, fontWeight: FontWeight.w700),
      );

  @override
  Widget build(BuildContext context) {
    final mins = DateTime.now().difference(started).inMinutes;
    final title = isDlv ? tr('Yetkazish', 'Доставка') : isCol ? tr('Inkassatsiya', 'Инкассация') : tr('Birgalikdagi tashrif', 'Совместный визит');
    final okLbl = isDlv ? tr('Yetkazildi', 'Доставлено') : isCol ? tr('To‘ladi', 'Оплатил') : tr('Zakaz bor', 'С заказом');
    final noLbl = isDlv ? tr('Yetkazilmadi', 'Не доставлено') : isCol ? tr('To‘lamadi', 'Не оплатил') : tr('Zakazsiz', 'Без заказа');
    final reasons = isDlv ? _dlvReasons : _colReasons;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: busy && visitId == null && !tooFar
          ? const Center(child: CircularProgressIndicator(color: brand))
          : ListView(padding: const EdgeInsets.all(16), children: [
              Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${widget.client['name'] ?? widget.client['client_name'] ?? ''}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: ink)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    Pill('${tr('Vaqt', 'Время')}: $mins ${tr('daq', 'мин')}', color: info),
                    Pill(distance == null ? tr('GPS: masofa noma’lum', 'GPS: расстояние неизвестно') : '${tr('Masofa', 'Расстояние')}: ${distance!.round()} m',
                        color: distance != null && distance! <= radius ? ok : warn),
                    if (widget.order != null) Pill('#${widget.order!['id']} · ${money(asNum(widget.order!['total']))}', color: brand),
                    if (widget.debt != null) Pill('${tr('Qarz', 'Долг')}: ${money(widget.debt!)}', color: danger),
                  ]),
                ]),
              ),
              if (tooFar) ...[
                const SizedBox(height: 12),
                Panel(
                  color: const Color(0xFFFDECEC),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr('Nuqtadan uzoqdasiz', 'Вы далеко от точки'), style: const TextStyle(color: danger, fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 6),
                    Text(tr('Tashrifni faqat ${radius.round()} m ichida boshlash mumkin.', 'Начать можно только в радиусе ${radius.round()} м.'),
                        style: const TextStyle(color: ink)),
                    const SizedBox(height: 10),
                    FilledButton.icon(onPressed: _checkin, icon: const Icon(Icons.refresh), label: Text(tr('Qayta tekshirish', 'Проверить снова'))),
                  ]),
                ),
              ] else ...[
                SectionTitle(tr('Foto-hisobot', 'Фотоотчёт')),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  for (final k in photoKinds)
                    OutlinedButton.icon(
                      onPressed: () => _photo('${k[0]}'),
                      icon: Icon((photos[k[0]] ?? 0) > 0 ? Icons.check_circle : Icons.photo_camera, color: (photos[k[0]] ?? 0) > 0 ? ok : brand),
                      label: Text('${tr(k[1], k[2])}${k[3] == true ? ' *' : ''}${(photos[k[0]] ?? 0) > 0 ? ' (${photos[k[0]]})' : ''}'),
                    ),
                ]),
                SectionTitle(tr('Natija', 'Результат')),
                Wrap(spacing: 10, children: [
                  _chip(okLbl, result == 'order', () => setState(() {
                        result = 'order';
                        reason = null;
                      }), c: ok),
                  _chip(noLbl, result == 'no_order', () => setState(() => result = 'no_order'), c: danger),
                ]),
                if (result == 'no_order' && !isSv) ...[
                  const SizedBox(height: 12),
                  Text(tr('Sababi', 'Причина'), style: const TextStyle(color: muted, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    for (final r in reasons) _chip(tr(r[0], r[1]), reason == tr(r[0], r[1]), () => setState(() => reason = tr(r[0], r[1])), c: danger),
                  ]),
                ],
                if ((isCol && result == 'order') || (isDlv && result == 'order' && MobileCfg.b('allow_pay'))) ...[
                  SectionTitle(isCol ? tr('Olingan pul', 'Получено денег') : tr('To‘lov (bo‘lsa)', 'Оплата (если есть)')),
                  TextField(
                    controller: amount,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: tr('Summa', 'Сумма'), prefixIcon: const Icon(Icons.payments_outlined)),
                  ),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, children: [
                    for (final m in methods)
                      _chip(m == 'cash' ? tr('Naqd', 'Наличные') : m == 'card' ? tr('Karta', 'Карта') : tr('O‘tkazma', 'Перечисление'), method == m, () => setState(() => method = '$m')),
                  ]),
                ],
                if (isSv && audit.isNotEmpty) ...[
                  SectionTitle(tr('Audit', 'Аудит точки')),
                  Panel(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Column(children: [
                      for (final k in audit.keys)
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(tr(_audit[k]![0], _audit[k]![1])),
                          subtitle: Text(audit[k]! ? 'OK' : tr('Muammo bor', 'Есть проблема'), style: TextStyle(color: audit[k]! ? ok : danger)),
                          value: audit[k]!,
                          activeColor: ok,
                          onChanged: (v) => setState(() => audit[k] = v),
                        ),
                    ]),
                  ),
                ],
                if (isSv && MobileCfg.b('sv_rate', true)) ...[
                  SectionTitle(tr('Agent ishiga baho', 'Оценка работы агента')),
                  Row(children: [
                    for (int i = 1; i <= 5; i++)
                      IconButton(onPressed: () => setState(() => rating = i), icon: Icon(i <= rating ? Icons.star : Icons.star_border, color: warn, size: 32)),
                  ]),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: comment,
                  maxLines: 2,
                  decoration: InputDecoration(labelText: tr('Izoh', 'Комментарий'), prefixIcon: const Icon(Icons.comment_outlined)),
                ),
                const SizedBox(height: 20),
                GradientButton(text: tr('Yakunlash', 'Завершить'), icon: Icons.check, busy: busy, onTap: _finish),
              ],
            ]),
    );
  }
}
