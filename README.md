# SalesGO — Agent mobil ilova (Flutter)

Bitta APK, rolga qarab ishlaydi: **agent** (GPS/tashrif/zakaz/foto), **dostavka** (yetkazish),
**inkassator** (pul yig'ish), **supervayzer** (ko'rsatkichlar).
Backend allaqachon tayyor: `https://salesgo.uz`.

## APK avtomatik yig'iladi (GitHub Actions)

Fayllar `main` shoxiga qo'shilishi bilan **Actions** bo'limida build boshlanadi (~5-8 daqiqa).
Tugagach APK'ni oling:
- **Releases** bo'limidan `app-release.apk`, yoki
- **Actions → oxirgi run → Artifacts → salesgo-agent-apk**

APK'ni telefonga o'rnating (Sozlamalar → "Noma'lum manbalarga ruxsat").

## Kirish (test)
- Kompaniya kodi: `demo`
- Agent: `vali` / `12345` (yoki sardor/jasur/aziz)
- Dostavka: `akmal` / `12345`
- Inkassator: `sher` / `12345`
- Supervayzer: `super` / `12345`

## Muhim
- `Api.base` = `https://salesgo.uz` (lib/api.dart). O'zgarsa shu yerni yangilang.
- GPS ilova ochiq turganda har 60s yuboriladi. To'liq fon rejimi keyingi bosqichda.
- Oflayn kesh keyingi bosqichda (hozir onlayn).
