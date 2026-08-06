#!/bin/sh

### ########################################
# Скопировать клиентский конфиг wg0.conf его берем с сервера WG VPS_2
### ########################################
mkdir -p ~/.gluetun

### ########################################
# Очистка старых контейнеров
### ########################################
docker stop wg-easy gluetun | echo == Stop old containers ==
docker rm wg-easy gluetun | echo == Remove old containers ==
docker pull ghcr.io/wg-easy/wg-easy
docker pull qmcgaw/gluetun

### ########################################
# Параметры запуска Wireguard
### ########################################
clear
echo ""
echo -n " [#] Введите пароль WEB панели: "
read PASS
echo ""

#wg_host=$(wget -q -O - http://ipify.org)
wg_host=$(wget -q -O - https://api.ipify.org)

wg_webport=51821
wg_listen=51820
wg_PASSWORD=$PASS
wg_pass=$(htpasswd -nbB admin $wg_PASSWORD)
wg_pass=${wg_pass#*:}

### ########################################
# 1. ЗАПУСК GLUETUN (WireGuard-клиент для VPS_2)
### ########################################
# Он забирает на себя публикацию портов wg-easy наружу
docker run --detach \
  --name gluetun \
  --cap-add NET_ADMIN \
  --device /dev/net/tun:/dev/net/tun \
  --volume ~/.gluetun/wg0.conf:/gluetun/wireguard/wg0.conf:ro \
  --env VPN_SERVICE_PROVIDER=custom \
  --env VPN_TYPE=wireguard \
  --publish ${wg_listen}:${wg_listen}/udp \
  --publish ${wg_webport}:${wg_webport}/tcp \
  --restart unless-stopped \
  qmcgaw/gluetun

### ########################################
# 2. ЗАПУСК WG-EASY (Внутри сети Gluetun)
### ########################################
# Обратите внимание: порты (--publish) здесь не указываются,
# а вместо этого используется сетевой стек контейнера gluetun.
docker run --detach \
  --name wg-easy \
  --network container:gluetun \
  --env WG_HOST=$wg_host \
  --env PASSWORD_HASH=$wg_pass \
  --env PORT=$wg_webport \
  --env WG_CONFIG_PORT=$wg_listen \
  --env WG_PORT=$wg_listen \
  --env WG_ALLOWED_IPS="0.0.0.0/0, ::/0" \
  --env WG_DEFAULT_DNS="9.9.9.9,1.1.1.1,8.8.8.8" \
  --env WG_MTU=1360 \
  --env WG_PERSISTENT_KEEPALIVE=15 \
  --volume ~/.wg-easy:/etc/wireguard \
  --cap-add NET_ADMIN \
  --cap-add SYS_MODULE \
  --sysctl 'net.ipv4.conf.all.src_valid_mark=1' \
  --sysctl 'net.ipv4.ip_forward=1' \
  --restart unless-stopped \
  ghcr.io/wg-easy/wg-easy

clear
docker ps
echo ""
echo ""
echo "== WEB адрес WG == http://$wg_host:$wg_webport"
echo "Web Password == $PASS"
echo "Web PASSWORD_HASH == $wg_pass"
