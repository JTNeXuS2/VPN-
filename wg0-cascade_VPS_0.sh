#!/bin/sh

sudo apt update && apt upgrade -y && apt autoremove -y

### ########################################
# Установим докер
### ########################################
# echo удалить все контейнеры
# sudo docker rmi $(sudo docker images -q)
curl -sSL https://get.docker.com | sh
sudo usermod -aG docker $(whoami)
sudo apt install -y apache2-utils

### ########################################
# Установим/обновим Wireguard
### ########################################
docker stop wg-easy | echo == Stop wg-easy ==
docker rm wg-easy | echo == Remove wg-easy ==
docker pull ghcr.io/wg-easy/wg-easy | echo == Update wg-easy ==

### ########################################
# параметры запуска Wireguard
### ########################################
clear
echo ""
echo -n " [#] Введите пароль WEB панели: "
read PASS
echo ""
PASS=$PASS

wg_host=$(wget -q -O - http://api.ipify.org)
wg_webport=51821
wg_listen=51820
wg_PASSWORD=$PASS
wg_pass=$(htpasswd -nbB admin $wg_PASSWORD)
wg_pass=${wg_pass#*:}

### ########################################
# Настройка sysctl на самом хосте (ОБЯЗАТЕЛЬНО для host-режима)
### ########################################
echo "== Настройка параметров ядра хоста =="
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.ipv4.conf.all.src_valid_mark=1

### ########################################
# запуск WG0 в режиме HOST, паблик порты убраны из запуска
### ########################################
docker run --detach \
  --name wg-easy \
  --network host \
  --env WG_HOST=$wg_host \
  --env PASSWORD_HASH=$wg_pass \
  --env PORT=$wg_webport \
  --env WG_CONFIG_PORT=$wg_listen \
  --env WG_PORT=$wg_listen \
  --env WG_ALLOWED_IPS="0.0.0.0/0, ::/0" \
  --env WG_DEFAULT_DNS="9.9.9.9,1.1.1.1,8.8.8.8" \
  --env WG_MTU=1280 \
  --env WG_PERSISTENT_KEEPALIVE=25 \
  --volume ~/.wg-easy:/etc/wireguard \
  --cap-add NET_ADMIN \
  --cap-add SYS_MODULE \
  --restart unless-stopped \
  ghcr.io/wg-easy/wg-easy

clear
docker ps
echo ""
echo ""
echo "== WEB адрес WG == http://$wg_host:$wg_webport"
echo "== Web Password == $PASS"
echo "== Web PASSWORD_HASH == $wg_pass"

### ########################################
# разрешим трафик
### ########################################
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
sudo iptables -A FORWARD -i wg0 -j ACCEPT
sudo iptables -A FORWARD -o wg0 -j ACCEPT

### ########################################
# сохраним sysctl 
### ########################################
sudo mkdir -p /etc/sysctl.d
cat <<EOF | sudo tee /etc/sysctl.d/99-wireguard-forward.conf
net.ipv4.ip_forward=1
net.ipv4.conf.all.src_valid_mark=1
EOF

exit 0
