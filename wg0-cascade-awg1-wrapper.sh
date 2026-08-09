#!/bin/sh
# Ручная часть
'
# VPS_0 ставим скриптом AWG или WG обязательно интерфейс wg0 в режиме HOST - wg0-cascade_VPS_0.sh
# VPS_1 ставим скриптом ядро AWG + панель для удобства - amnezia-web-ui-setup.sh
# VPS_1 в веб панели создаем вручную клиента awg1.conf
# редактируем клиент-конфиг обязательно добавить (при проблемах понижаем MTU до 1280)
# [Interface]
# MTU = 1420 
# Table = off
# DNS можно убрать
# На VPS_0 помещаем в /etc/amnezia/amneziawg/awg1.conf
'

# VPS_0 Установка ядра AWG
'
###############################################
apt update && apt install -y curl ipset
sudo add-apt-repository ppa:amnezia/ppa -y
sudo apt install -y amneziawg dkms
sudo apt-get install -y amneziawg-dkms amneziawg-tools
sudo modprobe amneziawg
if ! grep -q "^amneziawg$" /etc/modules; then
  echo "amneziawg" | sudo tee -a /etc/modules
fi
###############################################
'

# запустить тунель между VPSками awg0 -> awg1
'
###############################################
systemctl stop awg-quick@awg1
chmod 600 /etc/amnezia/amneziawg/awg1.conf
systemctl start awg-quick@awg1
sudo awg show awg1
if [ ! -L /root/awg/awg1_link.conf ]; then
    ln -s /etc/amnezia/amneziawg/awg1.conf /root/awg/awg1_link.conf
fi
###############################################
'

'
###############################
# обязательно проверить/подправить /root/awg/awg-routing.sh
# согласно инструкции https://github.com/bivlked/amneziawg-installer/blob/main/CASCADE.md#step4
# CLIENT_SUBNET="172.16.17.0/24"          # подсеть клиентов VPS_0 WG0/AWG0 (см. Address в /etc/amnezia/amneziawg/awg0.conf)
# AWG1_ENDPOINT="CHANGE_ME"               # внешний IP сервера AWG1 (Endpoint из awg1.conf, без порта)
##
# после можно использовтаь wg0-cascade-awg1-wrapper.sh
'

# для автозапуска
'
# 1. Создаем Systemd службу для автозапуска правил после перезагрузки
cat << 'EOF' > /etc/systemd/system/wg0-cascade.service
[Unit]
Description=Run WG0 Cascade Wrapper after delay
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/bin/chmod +x /root/awg/wg0-cascade-awg1-wrapper.sh
ExecStart=/bin/bash /root/awg/wg0-cascade-awg1-wrapper.sh

[Install]
WantedBy=multi-user.target
EOF

# 2. Перезапускаем конфигурацию systemd и добавляем службу в автозапуск
systemctl daemon-reload
systemctl enable wg0-cascade.service

# 3. Выполняем первый запуск каскада прямо сейчас
if [ -f "/root/awg/wg0-cascade-awg1-wrapper.sh" ]; then
    chmod +x /root/awg/wg0-cascade-awg1-wrapper.sh
    bash /root/awg/wg0-cascade-awg1-wrapper.sh
    systemctl start wg0-cascade.service
else
    echo "ОШИБКА: Файл /root/awg/wg0-cascade-awg1-wrapper.sh не найден!"
fi
'

'# запустить
chmod +x /root/awg/wg0-cascade-awg1-wrapper.sh
bash /root/awg/wg0-cascade-awg1-wrapper.sh
'
clear
set -euo pipefail

###############################################
# запустить тунель между VPSками awg0 -> awg1
systemctl stop awg-quick@awg1
chmod 600 /etc/amnezia/amneziawg/awg1.conf
systemctl start awg-quick@awg1
sudo awg show awg1
if [ ! -L /root/awg/awg1_link.conf ]; then
    ln -s /etc/amnezia/amneziawg/awg1.conf /root/awg/awg1_link.conf
fi
###############################################


# 2. Очищаем старые ошибочные ip rule и таблицы маршрутизации
ip rule del from 10.8.0.0/24 table 200 2>/dev/null || true
ip rule del from 10.8.0.0/24 table 100 2>/dev/null || true
ip route del default table 200 2>/dev/null || true

# 1. Сначала запускаем оригинальный скрипт каскада, который скачивает базы и настраивает awg0
echo "=== Запуск оригинального скрипта каскада ==="
bash /root/awg/awg-routing.sh

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

# Включаем маскарадинг для трафика, уходящего в туннель awg1 (Ручной заворот)
iptables -t nat -A POSTROUTING -o awg1 -j MASQUERADE
iptables -A FORWARD -i wg0 -o awg1 -j ACCEPT
iptables -A FORWARD -i awg1 -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT

# 5. Разрешаем FORWARD между wg0 и awg1 (включая Docker)
iptables -I FORWARD 1 -i wg0 -o awg1 -j ACCEPT
iptables -I FORWARD 2 -i awg1 -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT

# Системные параметры ядра Linux
sysctl -w net.ipv4.ip_forward=1 >/dev/null
sysctl -w net.ipv4.conf.awg1.rp_filter=2 >/dev/null
sysctl -w net.ipv4.conf.wg0.rp_filter=2 >/dev/null
sysctl -w net.ipv4.conf.all.src_valid_mark=1 >/dev/null
ip route flush cache

echo "=== Настройка завершена. Трафик wg0 успешно разделен! ==="
