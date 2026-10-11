## DPI тестер. DNS, домены и т.п. https://github.com/Runnin4ik/dpi-detector
### старт в докер с вебкой
```
docker run -d --name dpi-detector-web -p 7681:7681 --restart unless-stopped ghcr.io/runnin4ik/dpi-detector:web
```
### удалить
```
docker rm -f dpi-detector-web
```

## YandexSpeedTestCLI https://github.com/begugla0/yandexspeedtestcli
### Запуск одной командой
```
curl -fsSL https://raw.githubusercontent.com/begugla0/yandexspeedtestcli/main/yaspeed.py | python3 -
```

## sni-pinger https://github.com/begugla0/sni-pinger

## Прочее
```
IP region
bash <(wget -qO- https://ipregion.vrnt.xyz)

Censorcheck для проверки геоблока
bash <(wget -qO- https://github.com/vernette/censorcheck/raw/master/censorcheck.sh) --mode geoblock

Censorcheck для серверов РФ
bash <(wget -qO- https://github.com/vernette/censorcheck/raw/master/censorcheck.sh) --mode dpi

Тест до российских iPerf3 серверов
bash <(wget -qO- https://github.com/itdoginfo/russian-iperf3-servers/raw/main/speedtest.sh)

YABS
curl -sL yabs.sh | bash -s -- -4

Проверка IP сервера на блокировки зарубежными сервисами
bash <(curl -Ls IP.Check.Place) -l en

Параметры сервера и проверка скорости к зарубежным провайдерам
wget -qO- bench.sh | bash

IPQuality
bash <(curl -Ls https://Check.Place) -EI

Тест на процессор, можно понять примерно какой процент cpu выделили
sysbench cpu run --threads=1
```
