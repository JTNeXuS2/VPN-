#!/bin/bash

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
# 1. Установка модуля ядра AmneziaWG на хост Ubuntu 22 из PPA
### ########################################
echo "== Подготовка системы Ubuntu 22.04 == "
sudo apt-get update
sudo apt-get install -y software-properties-common linux-headers-$(uname -r) dkms iproute2 iptables iptables-persistent

# Добавление репозитория Amnezia и установка модуля ядра
sudo add-apt-repository ppa:amnezia/ppa -y
sudo apt-get update
sudo apt-get install -y amneziawg-dkms amneziawg-tools

# Проверка и принудительная загрузка модуля AmneziaWG в память хоста
if modinfo amneziawg &>/dev/null; then
  echo "== Загрузка и настройка модуля ядра amneziawg == "
  sudo modprobe amneziawg
  
  # Прописываем в автозагрузку, если модуля там еще нет
  if ! grep -q "^amneziawg$" /etc/modules; then
    echo "amneziawg" | sudo tee -a /etc/modules
  fi
  echo "[+] Модуль ядра amneziawg успешно инициализирован."
else
  echo "[-] Ошибка: Модуль amneziawg не собрался. Проверьте вывод команды 'dkms status'"
  exit 1
fi

### ########################################
# 2. Очистка старых контейнеров и обновление
### ########################################
echo "== Очистка старых контейнеров =="

docker stop wg-easy amnezia-wg-easy 2>/dev/null || true
docker rm wg-easy amnezia-wg-easy 2>/dev/null || true
docker pull ghcr.io/spcfox/amnezia-wg-easy:latest


### ########################################
# 3. Параметры запуска
### ########################################
clear
echo ""
echo -n " [#] Введите пароль WEB панели: "
read PASS
echo ""

# Получение внешнего IP сервера
wg_host=$(wget -q -O - http://icanhazip.com)
wg_webport=51821
wg_listen=51820

echo "== Генерация случайных параметров обфускации AmneziaWG =="
AWG_JMIN=40
AWG_JMAX=110
AWG_S1=$((RANDOM % 90 + 10))
AWG_S2=$((RANDOM % 90 + 10))
AWG_H1=$((RANDOM % 1500000000 + 1000000000))
AWG_H2=$((RANDOM % 1500000000 + 1000000000))
AWG_H3=$((RANDOM % 1500000000 + 1000000000))
AWG_H4=$((RANDOM % 1500000000 + 1000000000))

echo "== Параметры обфускации: =="
echo "Jmin: $AWG_JMIN, Jmax: $AWG_JMAX"
echo "S1: $AWG_S1, S2: $AWG_S2"
echo "H1-H4: $AWG_H1, $AWG_H2, $AWG_H3, $AWG_H4"

### ########################################
# 4. Запуск контейнера с AmneziaWG
### ########################################
echo "== Запуск контейнера ghcr.io/spcfox/amnezia-wg-easy:latest =="

# Создаем директорию для конфигов
mkdir -p ~/.amnezia-wg-easy

docker run -d \
  --name=amnezia-wg-easy \
  -e LANGUAGE=en \
  -e WG_HOST="$wg_host" \
  -e PASSWORD="$PASS" \
  -e PORT="$wg_webport" \
  -e WG_PORT="$wg_listen" \
  -e WG_ALLOWED_IPS="0.0.0.0/1,128.0.0.0/1,::/1,8000::/1" \
  -e WG_DEFAULT_DNS="9.9.9.9,1.1.1.1,8.8.8.8" \
  -e WG_MTU=1420 \
  -e WG_PERSISTENT_KEEPALIVE=25 \
  -e JMIN="$AWG_JMIN" \
  -e JMAX="$AWG_JMAX" \
  -e S1="$AWG_S1" \
  -e S2="$AWG_S2" \
  -e H1="$AWG_H1" \
  -e H2="$AWG_H2" \
  -e H3="$AWG_H3" \
  -e H4="$AWG_H4" \
  -v "$HOME/.amnezia-wg-easy:/etc/wireguard" \
  -p 51820:51820/udp \
  -p 51821:51821/tcp \
  --cap-add=NET_ADMIN \
  --cap-add=SYS_MODULE \
  --sysctl="net.ipv4.conf.all.src_valid_mark=1" \
  --sysctl="net.ipv4.ip_forward=1" \
  --device=/dev/net/tun:/dev/net/tun \
  --restart unless-stopped \
  ghcr.io/spcfox/amnezia-wg-easy:latest

echo ""
echo "== Проверка запущенных контейнеров =="
docker ps

# Проверка логов, если контейнер не запустился
if ! docker ps | grep -q amnezia-wg-easy; then
  echo ""
  echo "[-] Контейнер не запустился. Проверка логов:"
  docker logs amnezia-wg-easy --tail 50
fi

echo ""
echo "========================================================="
echo " УСТАНОВКА ЗАВЕРШЕНА УСПЕШНО!"
echo "========================================================="
echo "WEB адрес: http://$wg_host:$wg_webport"
echo "Пароль: $PASS"
echo "Конфиги хранятся в: ~/.amnezia-wg-easy"
echo "========================================================="
echo ""
