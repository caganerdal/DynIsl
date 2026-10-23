# Uyanık Tut (gelişmiş) – tasarım

## Amaç
Kullanıcının asıl ihtiyacı: kapak kapalıyken de Mac'in çalışmaya devam etmesi. Bunun yanında Uyanık Tut'un daha ayrıntılı kontrol edilebilmesi ve Sistem Paneli'nde kendi sayfasının olması.

## Hedefler
- Kapak kapalıyken uyanık kalma (harici ekran olmadan da).
- Esnek süreler ve koşullar.
- Sistem Paneli'nde ayrıntılı sayfa; ada ve menü çubuğu hızlı kontrol olarak kalır.

## Hedef olmayanlar
- Mac App Store uyumluluğu (DynIsl zaten değil).
- Ağ üzerinden uyandırma, zamanlanmış açılma.

## Anti-hedef
- Çantada kapak kapalı unutulan Mac'in ısınması ya da pilinin bitmesi. Güvenlik önlemleri şart.

## Yaklaşım (kullanıcı seçti: A)
- **A (seçilen):** İlk kullanımda macOS yönetici penceresiyle bir kez izin; `/etc/sudoers.d/dynisl` dosyasına yalnızca `/usr/bin/pmset -a disablesleep 0` ve `... 1` komutlarını şifresiz çalıştırma izni eklenir (`visudo -cf` ile doğrulanır). Sonra `sudo -n` ile çalıştırılır. Ayarlar'dan izin kaldırılabilir.
- B: Her seferinde şifre. Reddedildi: kullanımı zahmetli.
- C: SMAppService ayrıcalıklı yardımcı. Reddedildi: çok daha büyük iş, Developer ID imzası gerekiyor (gerçek ad kararı bekliyor).

## Davranış
**Modlar**
- Uyanık tut: ekran ve sistem uykusu engellenir (mevcut, IOPM assertion).
- Ekranın kapanmasına izin ver (seçenek, benim önerim): yalnızca sistem uykusu engellenir.
- Kapak kapalıyken de (seçenek): ek olarak `pmset disablesleep 1`.

**Süreler** (benim önerim): Süresiz, 15 dk, 30 dk, 1/2/4/8 sa, "Şu saate kadar" (saat seçici), "Seçilen uygulama açık kaldıkça".

**Güvenlik** (zorunlu)
- Pildeyken pil eşik değerinin altına düşünce kendiliğinden kapanır (varsayılan %20, ayarlanabilir).
- Süre bitince, kullanıcı kapatınca ve uygulama kapanırken `disablesleep 0`.
- Çökme kurtarma: `disablesleep 1` uygulandığında UserDefaults'a işaret yazılır; açılışta işaret varsa ve aktif değilse `disablesleep 0` çalıştırılır.
- Kapak modu açıkken pildeyse adada uyarı rengi.

## Arayüz
- **Sistem Paneli › Bağlantı ve Güç › Uyanık Tut** (yeni sayfa): durum kartı (aktif/pasif, kalan süre halkası, mod), süre düğmeleri, saat seçici, uygulama seçici, "Ekran kapanabilir" ve "Kapak kapalıyken de" anahtarları, kapak modu izni (kur/kaldır, durum), pil eşiği.
- **Ada › Sistem sekmesi:** mevcut düğme kalır; kalan süre ve kapak modu simgesi eklenir.
- **Menü çubuğu:** yeni süreler ve "Kapak kapalıyken de" seçeneği.
- Açılış/kapanış/otomatik kapanma bildirimleri adada.

## Kurucuya bırakılanlar
- Sayfanın görsel düzeni mevcut panel kartlarıyla uyumlu olacak.
- Metinler Türkçe yazılıp `localize.sh` ile İngilizceye çevrilecek.
