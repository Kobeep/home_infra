# 🚀 Home Lab - Deployment

## 📋 Wymagania początkowe

- [ ] Domena **kobecloud.pl** (home.pl)
- [ ] Serwer z k3d (IP: `83.25.45.232`)
- [ ] Router ConnectBox (Orange)
- [ ] SSH dostęp do serwera

---

## 🔧 KROK 1: Router ConnectBox (10 min)

### Login: http://192.168.0.1

1. **Static IP dla serwera:**
   - Advanced Settings → DHCP Settings
   - Znajdź serwer po MAC → Reserve IP
   - Przypisz: `192.168.0.100`

2. **Port Forwarding:**
   ```
   Service: Home Lab HTTP  | TCP | Port 80  → 192.168.0.100:80
   Service: Home Lab HTTPS | TCP | Port 443 → 192.168.0.100:443
   ```

3. **Bezpieczeństwo:**
   - Zmień hasło admina
   - ⚠️ **UPnP zostaw włączony** (konsola/gaming)
   - ℹ️ UPnP działa dla konsoli, ale port forwarding to stałe reguły dla serwera

---

## 🔒 KROK 2: Firewall na serwerze (5 min)

```bash
ssh server
cd /path/to/home_infra/gitops/scripts
./setup-firewall.sh
```

**Weryfikacja:**
```bash
sudo iptables -L -n -v | grep -E "22|80|443"
```

Powinno pokazać: ACCEPT dla portów 22, 80, 443

---

## 🌐 KROK 3: DNS w home.pl (5 min)

### Login: https://panel.home.pl

Dodaj **7 rekordów A** → `83.25.45.232`:

```
dashy.kobecloud.pl
argocd.kobecloud.pl
grafana.kobecloud.pl
home-assistant.kobecloud.pl
adguard.kobecloud.pl
grocy.kobecloud.pl
openwebui.kobecloud.pl
```

⏱️ **Poczekaj 5-15 min** na propagację DNS

**Weryfikacja:**
```bash
dig dashy.kobecloud.pl +short
# Powinno zwrócić: 83.25.45.232
```

---

## 🚀 KROK 4: Deploy aplikacji (10 min)

```bash
ssh server
cd /path/to/home_infra/gitops/scripts
./deploy-all.sh
```

Skrypt automatycznie:
- ✅ Zainstaluje SOPS + age (jeśli brak)
- ✅ Stworzy i zaszyfruje secrets
- ✅ Zainstaluje cert-manager
- ✅ Skonfiguruje Let's Encrypt
- ✅ Wdroży SSL + Basic Auth
- ✅ Zcommituje zmiany do git

---

## ⏳ KROK 5: Poczekaj na SSL (10-15 min)

Cert-manager automatycznie wystawi certyfikaty dla wszystkich domen.

**Sprawdź status:**
```bash
kubectl get certificate -A
```

Poczekaj aż wszystkie mają status: `True` w kolumnie READY

---

## ✅ KROK 6: Test

Otwórz w przeglądarce:
- https://dashy.kobecloud.pl

**Login:** (wpisz hasło z Basic Auth)

Powinno działać:
- ✅ HTTPS (zielona kłódka)
- ✅ Basic Auth (login/hasło)
- ✅ Dashboard z linkami
- ✅ Przekierowania do innych aplikacji

---

## 🔄 Jeśli IP się zmieni

1. **Sprawdź nowe IP:**
   ```bash
   curl ifconfig.me
   ```

2. **Zaktualizuj DNS w home.pl:**
   - Login → Domeny → kobecloud.pl → DNS
   - Edytuj wszystkie rekordy A na nowe IP

3. **Poczekaj 5-15 min**

4. **SSL odnowi się automatycznie** (cert-manager)

---

## 🆘 Troubleshooting

### Problem: Nie mogę się połączyć
```bash
# 1. Sprawdź port forwarding w ConnectBox
# 2. Sprawdź firewall:
sudo iptables -L -n | grep -E "80|443"
# 3. Sprawdź DNS:
dig dashy.kobecloud.pl +short
```

### Problem: SSL nie działa
```bash
# Sprawdź certyfikaty:
kubectl get certificate -A
kubectl describe certificate dashy-tls -n dashy

# Logi cert-manager:
kubectl logs -n cert-manager deployment/cert-manager --tail=50
```

### Problem: Basic Auth nie działa
```bash
# Sprawdź secret:
kubectl get secret basic-auth -n dashy
```

---

## 📊 Status bezpieczeństwa po deployment

```
✅ Firewall:        SSH/HTTP/HTTPS only
✅ Basic Auth:      Login + hasło
✅ SSL/TLS:         Let's Encrypt
✅ Secrets:         SOPS encrypted
✅ Rate Limiting:   10 req/s

Bezpieczeństwo: 9/10 ████████░
```

---

**To wszystko! Cały deployment: ~40 minut** 🎉
