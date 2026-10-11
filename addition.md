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
