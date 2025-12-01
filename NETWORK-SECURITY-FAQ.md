# 🛡️ Bezpieczeństwo sieci domowej - FAQ

## ❓ Czy moje urządzenia w domu są bezpieczne?

### 🏠 Twoja sieć: Orange + ConnectBox + UPnP włączony

#### ⚠️ **Ryzyko z UPnP:**
UPnP (Universal Plug and Play) pozwala urządzeniom automatycznie otwierać porty w routerze bez Twojej wiedzy.

**Kto używa UPnP w Twoim domu:**
- ✅ Konsola (PS5/Xbox) - gaming online
- ✅ Smart TV - streaming
- ⚠️ Potencjalnie każde urządzenie IoT
- ⚠️ Złośliwe oprogramowanie na PC/telefonie może otworzyć porty

---

## 🔍 Jak sprawdzić co jest otwarte?

### 1. **Sprawdź aktywne port forwarding w ConnectBox:**

Login: http://192.168.0.1 → Advanced Settings → Port Forwarding

**Szukaj:**
- Automatycznych reguł (od UPnP)
- Nieznanych portów/IP

**Bezpieczne (Twoje):**
```
192.168.0.100:80   ← Home Lab HTTP
192.168.0.100:443  ← Home Lab HTTPS
```

**Podejrzane (sprawdź!):**
```
Porty: 3389 (RDP), 22 (SSH), 445 (SMB), 23 (Telnet)
IP: Nieznane urządzenia
```

### 2. **Skanuj sieć - co jest podłączone:**

```bash
# Z serwera:
sudo nmap -sn 192.168.0.0/24

# Pokaże wszystkie urządzenia:
# - IP
# - MAC address
# - Producent (często można rozpoznać urządzenie)
```

**Sprawdź czy rozpoznajesz wszystkie urządzenia:**
- Router
- Serwer home lab
- Konsola
- Telefony/laptopy
- Smart TV
- IoT (żarówki, kamery, etc.)

### 3. **Sprawdź co jest widoczne z internetu:**

```bash
# Zewnętrzny scan (z telefonu 4G lub: https://www.shodan.io):
nmap -p 1-10000 <twoje-publiczne-IP>
```

**Powinno być otwarte TYLKO:**
- Port 80 (HTTP) → Home Lab
- Port 443 (HTTPS) → Home Lab

**Jeśli widzisz więcej portów = PROBLEM!**

---

## 🛡️ Jak zabezpieczyć sieć domową?

### ✅ **Minimalne bezpieczeństwo (MUSISZ):**

1. **Router:**
   - ✅ Zmień domyślne hasło admina ConnectBox
   - ✅ Firewall routera włączony
   - ✅ Aktualizuj firmware routera (sprawdź w ConnectBox)

2. **WiFi:**
   - ✅ WPA3 lub minimum WPA2-AES (NIE WPA/WEP!)
   - ✅ Silne hasło WiFi (min. 16 znaków)
   - ✅ Ukryj SSID (opcjonalnie)
   - ✅ Wyłącz WPS (łatwy do zhackowania)

3. **Urządzenia:**
   - ✅ Aktualizacje systemu (Windows/Mac/Linux)
   - ✅ Antywirus (Windows Defender wystarczy)
   - ✅ Hasła na wszystkich urządzeniach
   - ✅ Firewall włączony na PC/laptopach

4. **IoT (smart devices):**
   - ✅ Zmień domyślne hasła (kamery, smart TV, etc.)
   - ✅ Aktualizuj firmware
   - ⚠️ NIE kupuj tanich chińskich urządzeń (ryzyko backdoor)

### 🔥 **Zaawansowane bezpieczeństwo (ZALECANE):**

#### 1. **Segmentacja sieci (VLAN)**

Jeśli ConnectBox obsługuje (niektóre modele tak):

```
VLAN 1 (Trusted): Laptopy, telefony, serwer
VLAN 2 (IoT):     Smart TV, konsola, IoT
VLAN 3 (Guest):   WiFi dla gości
```

**Korzyści:**
- IoT nie ma dostępu do Twoich komputerów
- Malware na smart TV nie zainfekuje PC
- Konsola nie widzi serwera home lab

#### 2. **Pi-hole lub AdGuard (masz już!)**

AdGuard w Twoim home lab może blokować:
- ✅ Złośliwe domeny
- ✅ Trackery/reklamy
- ✅ Phishing
- ✅ Telemetria z IoT (szpiegujące domeny)

**Ustaw AdGuard jako DNS w ConnectBox:**
```
Primary DNS:   <IP-serwera-z-AdGuard>
Secondary DNS: 1.1.1.1 (Cloudflare backup)
```

#### 3. **Monitoring sieci**

Dodaj do home lab:
- **ntopng** - monitoring ruchu sieciowego
- **Suricata** - IDS/IPS (wykrywa ataki)

```bash
# Zobacz kto co robi w sieci:
# - Podejrzane połączenia
# - Nietypowy ruch
# - Próby skanowania portów
```

---

## 🎮 UPnP vs Gaming - Rozwiązanie

### Problem:
- UPnP potrzebny dla konsoli (NAT Type Open)
- UPnP = ryzyko bezpieczeństwa

### ✅ **Rozwiązanie: Połącz oba podejścia**

**W ConnectBox:**

1. **UPnP zostaw włączony** (dla konsoli)

2. **Dodaj ręczny port forwarding dla konsoli:**
   ```
   Konsola (PS5/Xbox):
   - IP: 192.168.0.50 (static DHCP)
   - Porty gaming:
     PS5:  TCP/UDP 3478-3480, 3658
     Xbox: TCP/UDP 3074
   ```

3. **Włącz UPnP TYLKO dla konsoli (jeśli router pozwala):**
   - Niektóre routery mają "UPnP Whitelist"
   - Dodaj MAC address konsoli
   - Reszta urządzeń bez UPnP

4. **Regularnie sprawdzaj port forwarding:**
   ```bash
   # Co tydzień:
   Login → ConnectBox → Port Forwarding
   # Usuń nieznane reguły!
   ```

---

## 🚨 Czerwone flagi (NATYCHMIAST SPRAWDŹ!)

- 🔴 Nieznane urządzenia w sieci
- 🔴 Otwarte porty które nie powinieneś mieć (3389, 445, 23, etc.)
- 🔴 Urządzenia IoT bez aktualizacji firmware od lat
- 🔴 Domyślne hasła na routerze/kamerach
- 🔴 Wolny internet (ktoś korzysta z WiFi?)
- 🔴 Dziwne połączenia w routerze (Advanced → Connected Devices)

---

## 📊 Twoje bezpieczeństwo - ocena

### Po wdrożeniu home lab:

```
Home Lab Server:     ████████░ 9/10
- ✅ Firewall
- ✅ SSL/TLS
- ✅ Basic Auth
- ✅ Secrets encrypted
- ⚠️ Tylko porty 80, 443 otwarte (musi być)

Router/Sieć:         █████░░░░ 5/10
- ✅ Hasło WiFi
- ⚠️ UPnP włączony (gaming)
- ❓ Firmware aktualny?
- ❓ Hasło admina zmienione?
- ❓ Segmentacja sieci?

Urządzenia domowe:   ❓❓❓❓❓ ??/10
- ❓ Smart TV - hasło zmienione?
- ❓ Konsola - aktualna?
- ❓ IoT - bezpieczne?
- ❓ PC/Laptopy - antywirus?
```

---

## ✅ Action Plan (co zrobić TERAZ)

### 1. **Natychmiast (10 min):**
```bash
# Sprawdź kto jest w sieci:
nmap -sn 192.168.0.0/24

# Login do ConnectBox:
# - Zmień hasło admina (jeśli domyślne)
# - Sprawdź Port Forwarding (usuń nieznane)
# - Sprawdź Connected Devices
```

### 2. **Dziś wieczorem (30 min):**
- [ ] Zmień hasła WiFi (jeśli słabe)
- [ ] Wyłącz WPS
- [ ] Sprawdź firmware routera (aktualizuj)
- [ ] Static IP dla konsoli
- [ ] Zmień hasła na smart TV/kamerach

### 3. **Ten weekend:**
- [ ] Skonfiguruj AdGuard jako DNS
- [ ] Scan zewnętrzny (shodan.io lub nmap z 4G)
- [ ] Rozważ segmentację VLAN

---

## 💡 Podsumowanie

**Czy jesteś bezpieczny?**
- ✅ Home Lab (serwer): TAK (9/10)
- ⚠️ Sieć domowa: ŚREDNIO (5-7/10)
  - UPnP = ryzyko, ale potrzebne dla gamingu
  - Zminimalizuj ryzyko: static IP dla konsoli, monitoring, AdGuard DNS

**Najważniejsze:**
1. Zmień domyślne hasła (router, IoT)
2. Aktualizuj wszystko
3. Monitoruj co jest otwarte w port forwarding
4. Używaj AdGuard jako DNS (blokuje złośliwe domeny)

**UPnP można zostawić, ale:**
- Regularnie sprawdzaj port forwarding
- Static IP + ręczne porty dla konsoli
- Rozważ VLAN w przyszłości

---

**Twoja sieć jest relatywnie bezpieczna, ale można lepiej!** 🛡️
