#!/bin/bash

sudo apt update && sudo apt upgrade -y && sudo apt install -y software-properties-common linux-headers-$(uname -r) dkms iproute2 iptables iptables-persistent && sudo apt autoremove -y

### ########################################
# Установим докер
### ########################################
curl -sSL https://get.docker.com | sh
sudo usermod -aG docker $(whoami)

### ########################################
# 1. Установка модуля ядра AmneziaWG на хост Ubuntu 22 из PPA
### ########################################
sudo add-apt-repository ppa:amnezia/ppa -y
sudo apt-get install -y amneziawg-dkms amneziawg-tools

# Проверка и принудительная загрузка модуля AmneziaWG в память хоста
if modinfo amneziawg &>/dev/null; then
  echo "== Загрузка и настройка модуля ядра amneziawg =="
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

docker stop amnezia-web-ui 2>/dev/null || true
docker rm amnezia-web-ui 2>/dev/null || true
docker pull alexishw/amneziawg-web-ui:master

### ########################################
# 3. Параметры запуска
### ########################################
clear
echo ""
echo -n " [#] Введите пароль WEB панели: "
read WEB_PASSWORD
echo ""
echo -n " [#] Введите имя пользователя WEB панели (по умолчанию admin): "
read WEB_USER
WEB_USER=${WEB_USER:-admin}

# Получение внешнего IP сервера
wg_host=$(wget -q -O - http://icanhazip.com)

# Порты
WEB_PORT=8080
WG_PORT=51820

### ########################################
# 4. Запуск контейнера с AmneziaWG Web UI
### ########################################
echo "== Запуск контейнера alexishw/amneziawg-web-ui:master =="

docker run -d \
  --name=amnezia-web-ui \
  --cap-add=NET_ADMIN \
  --cap-add=SYS_MODULE \
  --sysctl net.ipv4.ip_forward=1 \
  --sysctl net.ipv4.conf.all.src_valid_mark=1 \
  --device /dev/net/tun \
  --restart unless-stopped \
  -p $WG_PORT:51820/udp \
  -p $WEB_PORT:8080/tcp \
  -e NGINX_PORT=8080 \
  -e NGINX_USER="$WEB_USER" \
  -e NGINX_PASSWORD="$WEB_PASSWORD" \
  -e AUTO_START_SERVERS=true \
  -e DEFAULT_MTU=1420 \
  -e DEFAULT_SUBNET="10.8.0.0/24" \
  -e DEFAULT_DNS="9.9.9.9,1.1.1.1" \
  -e DEFAULT_ALLOWED_IPS="0.0.0.0/1,128.0.0.0/1,::/1,8000::/1" \
  -v amnezia-data:/etc/amnezia \
  alexishw/amneziawg-web-ui:master

echo ""
echo "== Проверка запущенных контейнеров =="
docker ps
