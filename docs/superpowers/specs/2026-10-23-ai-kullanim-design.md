# AI Kullanımı — tasarım

## Amaç
Abonelikle kullanılan AI servislerinde (Claude, ChatGPT, Gemini) "limitimin ne kadarı doldu, ne zaman açılır, bugün ne kadar kullandım" sorusunu adadan tek bakışta cevaplamak. Kullanıcı şu an yalnızca Claude (Pro/Max, Claude Code) kullanıyor; ChatGPT ve Gemini yer olarak hazır duracak.

## Hedefler
- Claude: 5 saatlik ve 7 günlük limit doluluğu (%), sıfırlanma saati.
- Claude Code: bugün / 7 gün token kullanımı, proje dökümü (yerel kayıtlardan).
- ChatGPT: Codex CLI kullanılıyorsa onun kayıtlarındaki limit doluluğu; yoksa "bağlı değil".
- Gemini: "resmî veri kaynağı yok" kartı.
- Ada: AI sekmesi + limit yükselince adada uyarı.
- Sistem Paneli: "AI Kullanımı" sayfası (ayrıntılar, bağlantı kurulumu).

## Hedef dışı
- Web oturumu/çerez kazıma, belgelenmemiş iç servisler (Yol B reddedildi).
- API anahtarlı kullanım ve dolar maliyeti.
- claude.ai sohbetlerinin token sayımı (yerel kaydı yok).

## Yaklaşım (seçilen: A + C)
- **A — resmî kaynaklar.** Claude Code durum çubuğu komutu stdin'e `rate_limits.five_hour/seven_day.{used_percentage,resets_at}` veriyor (Pro/Max, ilk yanıttan sonra). DynIsl bu komut olur: `island claude-status`.
- **C — derin Claude.** `~/.claude/projects/**/*.jsonl` içindeki `message.usage` alanlarından günlük/proje token dökümü.
- Reddedilen B: web oturumlarından okuma — kırılgan, kurallara aykırı olabilir.

## Nasıl çalışır
1. **Bağlantı.** Sayfadaki "Claude Code'a bağla" düğmesi `~/.claude/settings.json`'a `"statusLine": {"type":"command","command":"<island> claude-status"}` ekler; diğer anahtarlara dokunmaz, önce yedek alır. Zaten başka bir `statusLine` varsa üzerine yazmaz, nasıl birleştirileceğini anlatır. "Bağlantıyı kaldır" yalnızca kendi eklediğini siler.
2. **`island claude-status`.** stdin JSON'unu okur; `rate_limits`, `model`, `cwd` alanlarını `~/Library/Application Support/DynamicIsland/ai-usage.json`'a atomik yazar (0600) ve dağıtık bildirim (mevcut token'lı kanal) atar. stdout'a kısa satır basar: `5s %23 · hafta %41` (rate_limits yoksa model adı). Hızlı olmalı (<50 ms), ağ yok.
3. **Uygulama tarafı `AIUsageStore`.** Dosyayı ve bildirimi dinler; `resets_at` geçmiş pencereyi %0 sayar ve "sıfırlandı" gösterir; son güncelleme zamanını tutar ("12 dk önce").
4. **Token dökümü.** `ClaudeLogScanner` jsonl dosyalarını arka planda, dosya başına okunan bayt konumunu hatırlayarak artımlı tarar; aynı mesaj tekrarını `message.id + requestId` ile eler; gün × proje × (girdi, çıktı, önbellek okuma/yazma) toplar. Son 30 gün tutulur. Tarama: açılışta, ada AI sekmesi açılınca ve en sık 60 sn'de bir.
5. **ChatGPT.** `~/.codex/sessions/**/*.jsonl` varsa son `token_count` olayındaki `rate_limits.primary/secondary` (used_percent, pencere, sıfırlanma) okunur. Biçim yerelde doğrulanamadı; ayrıştırıcı toleranslı, alan yoksa "bağlı değil".

## Ada
- **AI sekmesi (yeni IslandTab `.ai`, ikon `sparkle`).** Üstte Claude: iki halka (5 saat, hafta) + "x sa y dk sonra açılır"; altında "Bugün 1,2 M token · en çok: DynIsl". ChatGPT ve Gemini birer ince satır.
- **Uyarı.** 5 saatlik pencere %80 ve %95'i ilk geçtiğinde, haftalık %90'da adada bildirim; pencere sıfırlanınca "Claude limitin açıldı". Her eşik pencere başına bir kez.
- Sekme Ayarlar'daki görünür sekmeler listesine eklenir (varsayılan açık).

## Sistem Paneli — "AI Kullanımı" sayfası
- Claude kartı: halkalar, sıfırlanma saatleri, son güncelleme, bağlantı durumu ve düğmesi.
- Claude Code kartı: son 7 gün token çubuk grafiği, proje listesi (bugün / 7 gün), model dağılımı.
- ChatGPT ve Gemini kartları: durum ve kısa açıklama.
- Uyarı eşikleri açma/kapama.

## Kısıtlar
- macOS 14, mevcut SwiftPM yapısı, kod içinde yorum yok, tüm yeni metinler TR kaynak + EN çeviri.
- Gizlilik: sohbet içeriği okunmaz/saklanmaz; jsonl'den yalnızca usage, model, zaman damgası, cwd alınır.
- Durum çubuğu verisi yalnızca Claude Code çalışırken gelir; ekranda tazelik her zaman belirtilir.

## Builder'a bırakılanlar
- Halka/grafik görsel ayrıntıları mevcut Theme/Card bileşenleriyle.
- Tarama aralığı ve dosya konum önbelleğinin saklanma biçimi.
