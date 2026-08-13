#!/bin/bash

# Установите задачу cron для выполнения скрипта каждые 5 минут
: '
wget -O forward_junger.sh junger.zzux.com/vpn/forward_junger.sh
sh /root/forward_junger.sh

sudo chmod +x /root/forward_junger.sh
(echo "*/5 * * * * /root/forward_junger.sh"; crontab -l) | crontab -
(echo "@reboot rm /root/old_ip.txt"; crontab -l) | crontab -
'

clear
echo "================================================"
DOMAIN="junger.zzux.com"

# Задаем жесткие пути к файлам для работы через cron
LOG_FILE="/root/forward_junger.log"
OLD_IP_FILE="/root/old_ip.txt"

# Инициализируем переменную OLD_IP (если файл не существует, переменная останется пустой)
OLD_IP=""
if [ -f "$OLD_IP_FILE" ]; then
    OLD_IP=$(cat "$OLD_IP_FILE" | tr -d '\n' | tr -s ' ')
fi

# Получаем ТОЛЬКО IP-адрес. 
IP=$(dig +short +tries=2 +time=3 "$DOMAIN" | grep -E -m1 '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
if [ -z "$IP" ]; then
    IP=$(host -W 3 "$DOMAIN" | grep -E -o -m1 '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
fi

echo "Current IP address: $IP"
echo "Old IP address: $OLD_IP"
echo "================================================"

# Строгая проверка: IP-адрес не пустой И является валидным IPv4
if [ -n "$IP" ]; then
    
    # Если новый IP равен старому, ничего не делаем
    if [ "$IP" = "$OLD_IP" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - $IP : Nothing Update"
        exit 0
    else
        # Удалите старые правила
        if [ -n "$OLD_IP" ]; then
            echo "DELETE OLD RULES $OLD_IP"
            sudo iptables -t nat -D PREROUTING -p udp --dport 60000:61100 -j DNAT --to-destination "$OLD_IP" 2>/dev/null
            sudo iptables -D FORWARD -p udp -d "$OLD_IP" --dport 60000:61100 -j ACCEPT 2>/dev/null
            sudo iptables -t nat -D PREROUTING -p tcp --dport 60000:61100 -j DNAT --to-destination "$OLD_IP" 2>/dev/null
            sudo iptables -D FORWARD -p tcp -d "$OLD_IP" --dport 60000:61100 -j ACCEPT 2>/dev/null
        fi

        # Добавьте новые правила
        echo "ADD NEW RULES $IP"
        sudo iptables -t nat -A PREROUTING -p udp --dport 60000:61100 -j DNAT --to-destination "$IP"
        sudo iptables -A FORWARD -p udp -d "$IP" --dport 60000:61100 -j ACCEPT
        sudo iptables -t nat -A PREROUTING -p tcp --dport 60000:61100 -j DNAT --to-destination "$IP"
        sudo iptables -A FORWARD -p tcp -d "$IP" --dport 60000:61100 -j ACCEPT

        # Сохраним текущий IP для дальнейшего использования
        echo "$IP" > "$OLD_IP_FILE"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Current: $IP - OldIP: ${OLD_IP:-NONE}" >> "$LOG_FILE"
    fi
else
    # Пишем ошибку резолва в лог, чтобы видеть сбои сети, но не ломать правила iptables
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Failed to resolve domain. Network or DNS timeout." >> "$LOG_FILE"
    echo "Не удалось разрешить доменное имя."
fi

exit 0
