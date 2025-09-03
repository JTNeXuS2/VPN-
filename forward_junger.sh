#!/bin/bash

# Установите задачу cron для выполнения скрипта каждые 5 минут
'
wget -O forward_junger.sh junger.zzux.com/vpn/forward_junger.sh
sh forward_junger.sh

sudo chmod +x forward_junger.sh
(echo "*/5 * * * * /root/forward_junger.sh"; crontab -l) | crontab -
(echo "@reboot rm /root/old_ip.txt"; crontab -l) | crontab -
'
clear
echo "================================================"
# Инициализируем переменную OLD_IP
OLD_IP=""
# Получите IP-адрес
IP=$(dig +short junger.zzux.com)
OLD_IP=$(cat old_ip.txt)
echo "Current IP address: $IP"
echo "Old IP address: $OLD_IP"
echo "================================================"

# Проверка, если IP-адрес не пустой
if [ -n "$IP" ]; then
    # Если новый IP равен старому, ничего не делаем
    if [ "$IP" = "$OLD_IP" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - $IP : Nothing Update"
		exit 0
    else
        # Удалите старые правила
        echo "DELETE OLD RULES"
        sudo iptables -t nat -D PREROUTING -p udp --dport 60000:61000 -j DNAT --to-destination $OLD_IP 2>/dev/null
        sudo iptables -D FORWARD -p udp -d $OLD_IP --dport 60000:61000 -j ACCEPT 2>/dev/null
        sudo iptables -t nat -D PREROUTING -p tcp --dport 60000:61000 -j DNAT --to-destination $OLD_IP 2>/dev/null
        sudo iptables -D FORWARD -p tcp -d $OLD_IP --dport 60000:61000 -j ACCEPT 2>/dev/null

        # Добавьте новые правила
        echo "ADD NEW RULES"
        sudo iptables -t nat -A PREROUTING -p udp --dport 60000:61000 -j DNAT --to-destination $IP
        sudo iptables -A FORWARD -p udp -d $IP --dport 60000:61000 -j ACCEPT
        sudo iptables -t nat -A PREROUTING -p tcp --dport 60000:61000 -j DNAT --to-destination $IP
        sudo iptables -A FORWARD -p tcp -d $IP --dport 60000:61000 -j ACCEPT

		# Обработка переменных для удаления переносов строк и сжатия пробелов
		IP_CLEAN=$(echo "$IP" | tr -d '\n' | tr -s ' ')
		OLD_IP_CLEAN=$(echo "$OLD_IP" | tr -d '\n' | tr -s ' ')

        # Сохраним текущий IP для дальнейшего использования
        echo "$IP" > old_ip.txt
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Current: $IP_CLEAN - OldIP: $OLD_IP_CLEAN" >> forward_junger.log
    fi
else
    echo "Не удалось разрешить доменное имя."
fi

exit 0
