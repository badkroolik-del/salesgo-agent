# SalesGO SFA — Google Play'ga joylash yo'riqnomasi

Ilova: **SalesGO SFA** · paket: `uz.salesgo.agent` · versiya 2.0.0 (build 20) · targetSdk 36 (Android 16) · minSdk 23 (Android 6)

## 1. Yig'ish (GitHub)
1. Shu papkadagi hamma fayllarni GitHub repoga yuklang (eski `lib/`, `pubspec.yaml`, `.github/` ni almashtiring).
   `assets/`, `tools/`, `store/` papkalari ham kerak.
2. **Upload kalit (bir marta):** Actions → «Generate upload key (bir marta)» → Run workflow.
   Tugagach artifact `upload-key-MAXFIY` ni yuklab oling (1 kun saqlanadi):
   - `SECRETS.txt` dagi 4 qiymatni repo → Settings → Secrets and variables → Actions → New repository secret ga qo'shing:
     `ANDROID_KEYSTORE_B64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.
   - `upload.jks` faylini **2 joyda xavfsiz saqlang** (flesh + bulut). Yo'qolsa — Play'da kalitni tiklash kerak bo'ladi.
3. Har `main` ga yuklashda build avtomatik ishlaydi:
   - `salesgo-sfa-aab-google-play` → **`app-release.aab`** — Google Play'ga shu yuklanadi;
   - `salesgo-sfa-apk` → `app-release.apk` — telefonga to'g'ridan-to'g'ri o'rnatish (sinov) uchun.
   > Eslatma: Play'dan o'rnatilgan va to'g'ridan-to'g'ri o'rnatilgan APK imzosi har xil bo'ladi — bitta telefonda biridan
   > ikkinchisiga o'tishda avval eskisini o'chirish kerak. Eski (v1.x) ilova `com.example.salesgo_agent` paketida edi —
   > yangisi alohida o'rnatiladi (Play `com.example` paketini qabul qilmaydi, shuning uchun nom o'zgardi).

## 2. Play Console
1. play.google.com/console → akkaunt (bir martalik $25). Tashkilot akkaunti tavsiya etiladi (D-U-N-S kerak bo'lishi mumkin).
2. **Create app:** nomi `SalesGO SFA`, til — Русский (+ O'zbekcha), App, Free.
3. **Internal testing** → Create release → `app-release.aab` ni yuklang → **Play App Signing** ni qabul qiling.
4. Yangi shaxsiy akkauntlar uchun Google talabi: production'dan oldin **closed testing'da 12 ta tester 14 kun** (tashkilot akkauntida shart emas).

## 3. Store listing (tayyor matnlar)
**Qisqa tavsif (RU, ≤80):** Мобильная SFA для торговой команды: визиты, заказы, доставка, инкассация и GPS-маршрут.
**Qisqa tavsif (UZ):** Savdo jamoasi uchun SFA: tashrif, zakaz, yetkazish, inkassatsiya va GPS marshrut.

**To'liq tavsif (RU):**
SalesGO SFA — рабочее приложение для сотрудников дистрибьюторских компаний, подключённых к системе SalesGO.
• Агенты: маршрут на день, визиты с фотоотчётом, заказы (в том числе без интернета), акции, долги клиентов, акт сверки.
• Экспедиторы: доставка заказов с фото товара и накладной, приём оплаты, причины недоставки.
• Инкассаторы: сбор оплат по долгам с квитанцией.
• Супервайзеры: совместные визиты, аудит точки, оценка работы агента.
• GPS-трек рабочего маршрута (в рабочее время, с уведомлением) — для подтверждения визитов и доставки.
Вход только по логину, выданному вашей компанией.

**Grafika:** `store/icon_512.png` (ikonka), `store/feature_1024x500.png` (banner). Skrinshotlar — telefondan kamida 2 ta (kirish, bosh sahifa, vizit, yetkazish).
**Maxfiylik siyosati:** https://salesgo.uz/privacy.html (mobil ilova bo'limi qo'shilgan — avval saytga yuklang!)

## 4. App content (majburiy anketalar)
- **App access:** «All or some functionality is restricted» → tekshiruvchi uchun: Kompaniya kodi `demo`, login `vali`, parol `demo123`
  (kirish sahifasida «Demo» tugmalari: Agent / Dostavka / Inkassator / Supervayzer). Izoh: «Joylashuv ruxsati so'ralganda "Har doim ruxsat berish"ni tanlang».
- **Ads:** No. **Target audience:** 18+. **Content rating:** anketani to'ldiring (Utility/Productivity, zo'ravonlik yo'q).
- **News / Health / Financial features:** yo'q. **Government app:** yo'q.

### Data safety (javoblar)
| Ma'lumot | Yig'iladi | Uzatiladi | Maqsad | Majburiy |
|---|---|---|---|---|
| Aniq joylashuv (Precise location) | Ha | Yo'q (uchinchi shaxsga) | App functionality | Ha (ish uchun) |
| Taxminiy joylashuv | Ha | Yo'q | App functionality | Ha |
| Ism, telefon (Personal info) | Ha | Yo'q | Account management, App functionality | Ha |
| Foto (Photos) | Ha | Yo'q | App functionality | Ixtiyoriy/kompaniya talabi |
| App activity (ilovadagi amallar) | Ha | Yo'q | App functionality, Analytics | Ha |
| Device ID / qurilma ma'lumoti | Ha (model, versiya) | Yo'q | App functionality | Ha |
- Data encrypted in transit: **Ha (HTTPS)**. Data deletion: **Ha** — kompaniya administratori yoki support orqali.

### Permissions declaration — ACCESS_BACKGROUND_LOCATION
**Asosiy funksiya:** «Tracking the work route of field sales staff (agents, delivery drivers, collectors) during working hours to confirm client visits and deliveries for their employer.»
**Nega fonda kerak:** «Field employees work with the phone locked in their pocket and switch between apps (camera, maps, calls). The route must be recorded continuously during the working day, so location is collected by a foreground service with a persistent notification, only within company-defined working hours, and only after the in-app prominent disclosure and consent.»
**Video (majburiy, ~30 s, YouTube unlisted):** 1) login → 2) «Использование геолокации в фоне» oynasi → «Согласен» → 3) tizim so'rovida «Разрешать всегда» → 4) bildirishnoma «SalesGO — маршрут записывается» → 5) ilova yopiladi, panelda trek davom etayotgani.

### Foreground service declaration — FOREGROUND_SERVICE_LOCATION
Tur: **Location** · «Continuous GPS route recording of a field employee's working day (user-visible notification, stops at logout or outside working hours).» Video — yuqoridagi bilan bir xil.

## 5. Nima uchun Play talablariga mos
- targetSdk 36; release imzo — upload key + Play App Signing; format — AAB.
- Joylashuv ruxsatidan oldin ilova ichida **prominent disclosure** (nima, nega, fonda, kimga) + rozilik; rad etilsa ilova ishlayveradi, trek yozilmaydi.
- «Har doim» ruxsati alohida bosqichda, foydalanuvchi o'zi tanlaydi; bildirishnomalar (Android 13+) so'raladi.
- Foreground-servis turi `location`, doimiy bildirishnoma; ish vaqtidan tashqarida nuqta yozilmaydi; logout'da to'xtaydi.
- `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` ishlatilmaydi (Play cheklagan) — foydalanuvchi sozlamalarni o'zi ochadi.
- Ortiqcha ruxsatlar yo'q (SMS, kontaktlar, fayllar, QUERY_ALL_PACKAGES — yo'q). Maxfiylik siyosati URL.

## 6. «Ilova yopilsa ham ishlashi» haqida halol eslatma
Servis ro'yxatdan surib tashlanganda, ekran o'chganda va telefon qayta yoqilganda ishlaydi. Faqat foydalanuvchi o'zi
**Sozlamalar → Ilova → To'xtatish (Force stop)** qilsa yoki ruxsatni olib qo'ysa to'xtaydi (Android buni hech bir ilovaga ruxsat bermaydi).
Xiaomi/Redmi, Huawei, Tecno, Infinix telefonlarda «Avtozapusk» va «Batareya: cheklovsiz» yoqilishi kerak — ilova bunga yo'naltiradi.
Panelda «Мобильное приложение → Устройства и синхронизация» da kim oxirgi marta qachon ma'lumot yuborgani ko'rinadi.

## 7. Server tomoni (ilova kutadigan API)
- `POST /api/gps` — `{points:[{lat,lng,acc,speed,spd,bat,ts,kind}]}` (paket bilan, eski format bilan mos)
- `GET /api/mobile/config/me` — paneldagi rol + xodim konfiguratsiyasi (bo'lmasa ilova yumshoq standartda ishlaydi)
- `POST /api/mobile/devices/ping` — `{app,build,device,battery,pending_gps,gps}`
- `POST /api/visits/checkin` — `kind` (agent/delivery/collector/supervisor), `order_id` qo'shimcha maydonlari
- `POST /api/orders/{id}/status?status=delivered|failed&comment=` · `POST /api/payments` — `method`, `order_id`
