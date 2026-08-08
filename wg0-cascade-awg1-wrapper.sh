#!/bin/sh
'# запустить
chmod +x /root/awg/wg0-cascade-awg1-wrapper.sh
bash /root/awg/wg0-cascade-awg1-wrapper.sh
'

set -euo pipefail

# 1. Сначала запускаем оригинальный скрипт каскада, который скачивает базы и настраивает awg0
echo "=== Запуск оригинального скрипта каскада ==="
bash /root/awg/awg-routing.sh

echo "=== Настройка правил для подсети wg0 ==="
# 2. Очищаем старые ошибочные ip rule и таблицы маршрутизации, если они остались
ip rule del from 10.8.0.0/24 table 200 2>/dev/null || true
ip rule del from 10.8.0.0/24 table 100 2>/dev/null || true
ip route del default table 200 2>/dev/null || true

# 3. Настройка разделения трафика для wg0 (10.8.0.0/24) через iptables mangle
# Если трафик идет на RU IP — пропускаем напрямую в интернет (RETURN)
iptables -t mangle -C PREROUTING -i wg0 -s 10.8.0.0/24 -m set --match-set ru dst -j RETURN 2>/dev/null \
  || iptables -t mangle -I PREROUTING 1 -i wg0 -s 10.8.0.0/24 -m set --match-set ru dst -j RETURN

# Если трафик идет на любые другие IP — маркируем меткой 0x1 (уйдет в таблицу каскада 100)
iptables -t mangle -C PREROUTING -i wg0 -s 10.8.0.0/24 -j MARK --set-mark 0x1 2>/dev/null \
  || iptables -t mangle -A PREROUTING -i wg0 -s 10.8.0.0/24 -j MARK --set-mark 0x1

# 4. NAT/Маскарадинг для wg0 при уходе в заграничный туннель awg1
iptables -t nat -C POSTROUTING -s 10.8.0.0/24 -o awg1 -j MASQUERADE 2>/dev/null \
  || iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o awg1 -j MASQUERADE

# 5. Разрешаем FORWARD между wg0 и awg1 (включая Docker)
iptables -I FORWARD 1 -i wg0 -o awg1 -j ACCEPT
iptables -I FORWARD 2 -i awg1 -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT

# 6. Оптимизация MTU / MSS для предотвращения зависания сайтов на интерфейсе wg0
iptables -t mangle -C FORWARD -p tcp --tcp-flags SYN,RST SYN -o awg1 -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null \
  || iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -o awg1 -j TCPMSS --clamp-mss-to-pmtu

iptables -t mangle -C FORWARD -i wg0 -o awg1 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1240 2>/dev/null \
  || iptables -t mangle -A FORWARD -i wg0 -o awg1 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1240

iptables -t mangle -C FORWARD -i awg1 -o wg0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1240 2>/dev/null \
  || iptables -t mangle -A FORWARD -i awg1 -o wg0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1240

# 7. Системные параметры ядра Linux
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv4.conf.awg1.rp_filter=2
sysctl -w net.ipv4.conf.wg0.rp_filter=2
ip route flush cache

echo "=== Настройка завершена. Трафик wg0 успешно разделен! ==="
