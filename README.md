# SalesGO SFA — mobil ilova (Flutter) v2.0

Bitta ilova, rolga qarab ishlaydi: **agent** (marshrut, tashrif, zakaz, foto), **dostavka** (yetkazish, foto, to'lov),
**inkassator** (qarz yig'ish, kvitansiya), **supervayzer** (birgalikdagi tashrif, audit).
Backend: `https://salesgo.uz` (`lib/api.dart` → `Api.base`).

Yangi v2.0 da:
- firma ranglari (navy #02255B + yashil #21A94D) va asl SalesGO logosi, ilova nomi **SalesGO SFA**;
- **fonda GPS**: ilova yopilsa ham, ekran o'chsa ham, telefon qayta yoqilsa ham ishlaydi (foreground-servis + bildirishnoma);
  internet bo'lmasa nuqtalar navbatda saqlanadi va keyin yuboriladi;
- ruxsatlar ketma-ket so'raladi (rozilik oynasi → joylashuv → «Har doim» → bildirishnoma → batareya);
- paneldagi «Мобильное приложение» sozlamalari (majburiyatlar: radius, foto, min vaqt, ish soatlari) ilovaga sinxron keladi;
- dostavka/inkassator/supervayzer uchun tashrif ekrani (check-in, foto, natija, to'lov);
- Google Play talablariga mos (targetSdk 36, AAB, upload key) — batafsil: **PLAY_MARKET.md**.

## Yig'ish (GitHub Actions, bepul)
1. Repoga shu papkadagi **hamma narsani** yuklang: `lib/`, `assets/`, `store/`, `tools/`, `.github/`, `pubspec.yaml`,
   `README.md`, `PLAY_MARKET.md`. Eski fayllarni ustidan yozing.
   > `.github` papkasi yashirin — saytga sudrab tashlaganda tushib qolmasligini tekshiring.
2. **Bir marta:** Actions → «Generate upload key (bir marta)» → Run workflow → artifact `upload-key-MAXFIY` ni yuklab oling,
   `SECRETS.txt` dagi 4 qiymatni Settings → Secrets and variables → Actions ga qo'shing. `upload.jks` ni xavfsiz saqlang.
   (Kalit qo'shilmasa ham APK yig'iladi, lekin Play uchun AAB chiqmaydi.)
3. Har yuklashda build avtomatik (~8-12 daqiqa). Natija:
   - **Releases** → `app-release.apk` (telefonga o'rnatish);
   - **Actions → oxirgi run → Artifacts** → `salesgo-sfa-apk` va `salesgo-sfa-aab-google-play` (AAB faqat shu yerda —
     ochiq Releases'ga qo'yilmaydi).
4. APK'ni telefonga o'rnating. Eski v1.x ilova boshqa paket nomida — yangisi alohida o'rnatiladi, eskisini o'chiring.

## Brauzerda ko'rish (APK o'rnatmasdan)
**https://badkroolik-del.github.io/salesgo-agent/** — har yuklashda avtomatik yangilanadi (Actions → `web` bo'limi).
Kirish sahifasida 4 ta demo tugma: **Agent · Dostavka · Inkassator · Supervayzer** — bosing va o'sha rolning ekranlarini ko'ring.
Brauzerda fon GPS servisi yo'q (u faqat telefondagi APK'da ishlaydi), qolgan hamma narsa bir xil.

## Kirish (test)
- Kompaniya kodi: `demo`; loginlar: `vali` (agent), `akmal` (dostavka), `sher` (inkassator), `super` (supervayzer)

## GPS haqida
- Faqat foydalanuvchi o'zi **Force stop** qilsa yoki ruxsatni olib qo'ysa to'xtaydi — buni Android hech bir ilovaga chetlab o'tishga ruxsat bermaydi.
- Xiaomi/Redmi, Huawei, Tecno, Infinix: «Avtozapusk» yoqilsin va batareya «Cheklovsiz» qilinsin (ilova sozlamaga yo'naltiradi).
- Ish vaqtidan tashqari nuqta yozilmaydi (panel sozlamasi), logout'da servis to'xtaydi.
