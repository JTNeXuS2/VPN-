#!/bin/sh

: ' установка и настройка PPTP в две команды (Ubuntu 20-22, для 24 требует доработки)
wget junger.zzux.com/vpn/pptp.sh
sh pptp.sh

ip link set dev ppp0 mtu 1500
sudo ifconfig ppp0 mtu 1500
'
: ' 

https://vps.today/index.php?ram=1&cpu=1&traffic=1000

доступность проерка для настройки zapret
curl -Is https://www.manyvids.com | head -1
sh /etc/rc.local
/etc/init.d/iptables restart
/etc/init.d/networking restart


ZAPRET https://gitee.com/dominicusin/zapret

dig -p 53 @77.88.8.88 manyvids.com
sudo apt install gcc g++ make git libnetfilter-queue-dev zlib1g-dev iptables
git clone --depth=1 https://github.com/bol-van/zapret
cd zapret
make
sudo cp /home/zapret/binaries/my/ip2net /usr/local/bin/ip2net
sudo cp /home/zapret/binaries/my/mdig /usr/local/bin/mdig
sudo cp /home/zapret/binaries/my/nfqws /usr/local/bin/nfqws
sudo cp /home/zapret/binaries/my/tpws /usr/local/bin/tpws
rm -rd /home/zapret
sh install_easy.sh
cd /opt/zapret
sh blockcheck.sh
sh install_easy.sh

или
Перехватить пакет с SYN,ACK не представляет никакой сложности средствами iptables.
Однако, возможности редактирования пакетов в iptables сильно ограничены.
Просто так поменять window size стандартными модулями нельзя.
Для этого мы воспользуемся средством NFQUEUE. Это средство позволяет
передавать пакеты на обработку процессам, работающим в user mode.
Процесс, приняв пакет, может его изменить, что нам и нужно.
iptables -t raw -I PREROUTING -p tcp --sport 80 --tcp-flags SYN,ACK SYN,ACK -j NFQUEUE --queue-num 200 --queue-bypass

или
Если DPI не обходится через разделение запроса на сегменты, то иногда срабатывает изменение
"Host:" на "host:". В этом случае нам может не понадобится замена window size, поэтому цепочка
PREROUTING нам не нужна. Вместо нее вешаемся на исходящие пакеты в цепочке POSTROUTING :
iptables -t mangle -I POSTROUTING -p tcp --dport 80 -m set --match-set zapret dst -j NFQUEUE --queue-num 200 --queue-bypass

или
В этом случае так же возможны дополнительные моменты. DPI может ловить только первый http запрос, игнорируя
последующие запросы в keep-alive сессии. Тогда можем уменьшить нагрузку на проц, отказавшись от процессинга ненужных пакетов.
iptables -t mangle -I POSTROUTING -p tcp --dport 80 -m connbytes --connbytes-dir=original --connbytes-mode=packets --connbytes 1:5 -m set --match-set zapret dst -j NFQUEUE --queue-num 200 --queue-bypass

'


sudo apt update && apt upgrade -y && apt autoremove -y
apt-get -y install iptables

modprobe ip_nat_pptp
modprobe pptp
modprobe gre

if [ `id -u` -ne 0 ] 
then
  echo "Need root, try with sudo"
  exit 0
fi

network_interface=$(ip -o -4 route show to default | awk '{print $5}')

apt-get update
apt-get -y install pptpd || {
  echo "Could not install pptpd" 
  #exit 1
  cat >> /etc/apt/sources.list << END

deb http://old-releases.ubuntu.com/ubuntu/ natty main restricted universe multiverse
deb http://old-releases.ubuntu.com/ubuntu/ natty-updates main restricted universe multiverse
deb http://old-releases.ubuntu.com/ubuntu/ natty-security main restricted universe multiverse
deb http://old-releases.ubuntu.com/ubuntu/ natty-backports main restricted universe multiverse

END
  sudo apt-get update
  apt-get -y install pptpd
}

#ubuntu has exit 0 at the end of the file.
sed -i '/^exit 0/d' /etc/rc.local

cat >> /etc/rc.local << END
echo 1 > /proc/sys/net/ipv4/ip_forward
iptables -I INPUT -p tcp --dport 22 -j ACCEPT
iptables -I INPUT -p tcp --dport 1723 -j ACCEPT
iptables -I INPUT  --protocol 47 -j ACCEPT
iptables -t nat -A POSTROUTING -s 10.10.0.0/24 -d 0.0.0.0/0 -o $network_interface -j MASQUERADE
iptables -I FORWARD -s 10.10.0.0/24 -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -j TCPMSS --set-mss 1356
iptables -I FORWARD -s 10.10.0.0/24 -p tcp -j ACCEPT
iptables -I FORWARD -s 10.10.0.0/24 -p udp -j ACCEPT

iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
END
sh /etc/rc.local

cat >> /etc/systemd/system/pptp.service << END
[Unit]
Description=Start VPN service 
Wants=network-online.target
After=network.target network-online.target multi-user.target

[Service]
Type=oneshot
ExecStart=pptpd restart
# Restart=on-failure

[Install]
WantedBy=multi-user.target
END

sudo systemctl daemon-reload
#sudo systemctl enable pptp.service

clear
echo ""
echo " +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+ "
echo " | PPTP VPN Setup Script By Aung Thu Myint | "
echo " +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+ "
echo ""
echo -n " [#] ВВедите логин PPTP VPN : "
read NAME
echo ""
echo -n " [#] ВВедите пароль PPTP VPN : "
read PASS
echo ""
NAME=$NAME
PASS=$PASS

cat >/etc/ppp/chap-secrets <<END
$NAME pptpd $PASS *
END
cat >/etc/pptpd.conf <<END
option /etc/ppp/options.pptpd
logwtmp
localip 10.10.0.1
remoteip 10.10.0.10-100
END
cat >/etc/ppp/options.pptpd <<END
name pptpd
refuse-pap
refuse-chap
refuse-mschap
require-mschap-v2
require-mppe-128
ms-dns 8.8.8.8
ms-dns 8.8.4.4
proxyarp
lock
nobsdcomp 
novj
novjccomp
nologfd
END

apt-get -y install wget || {
  echo "Could not install wget, required to retrieve your IP address." 
  exit 1
}

IP=`wget -q -O - http://api.ipify.org`

if [ "x$IP" = "x" ]
then
  echo ""
  echo " [!] COULD NOT DETECT SERVER EXTERNAL IP ADDRESS [!]"
  echo ""
else
  echo ""
  echo " +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+ "
  echo " | PPTP VPN Setup Script By Aung Thu Myint | "
  echo " +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+ "
  echo ""
  echo " [#] External IP Address  : $IP "
  echo ""
fi
echo   " [#] PPTP VPN Логин    : $NAME"
echo ""
echo   " [#] PPTP VPN Пароль    : $PASS "
echo ""
echo ""
echo   " +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+"
echo ""
sleep 3

echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

sudo systemctl enable pptpd
service pptpd restart

exit 0
