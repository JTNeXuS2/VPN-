#!/bin/sh

'
### ########################################
# Установим wg-easy и запустим в 2 команды (ctrl+c - ctrl+v)
### ########################################
wget -O wg-easy-setup.sh junger.zzux.com/vpn/wg-easy-setup.sh
sh wg-easy-setup.sh
'

sudo apt update && apt upgrade -y && apt autoremove -y

### ########################################
# Установим докер
### ########################################
# echo удалить все контейнеры
# sudo docker rmi $(sudo docker images -q)
curl -sSL https://get.docker.com | sh
sudo usermod -aG docker $(whoami)
sudo apt install apache2-utils

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
# запуск
### ########################################
docker run --detach \
  --name wg-easy \
  --env WG_HOST=$wg_host \
  --env PASSWORD_HASH=$wg_pass \
  --env PORT=$wg_webport \
  --env WG_CONFIG_PORT=$wg_listen \
  --env WG_PORT=$wg_listen \
  --env WG_ALLOWED_IPS="0.0.0.0/1, 128.0.0.0/1, ::/1, 8000::/1" \
  --volume ~/.wg-easy:/etc/wireguard \
  --publish $wg_listen:$wg_listen/udp \
  --publish $wg_webport:$wg_webport/tcp \
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
echo "== Web Password == $PASS"
echo "== Web PASSWORD_HASH == $wg_pass"

exit 0
