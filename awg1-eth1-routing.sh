#!/bin/bash

: '
# 1. Остановить все процессы
pkill -f "awg1-eth1-routing.sh" 2>/dev/null
systemctl stop awg1-eth1-routing.service 2>/dev/null

# 2. Удалить файлы блокировки
rm -f /var/lock/awg-routing.lock
rm -f /var/run/awg-monitor.pid
rm -f /var/run/awg-routing-status
rm -f /var/run/awg-routing-metrics

# 4. Сделать исполняемым
chmod +x /root/awg1-eth1-routing.sh

# 5. Создать сервисный файл
cat > /etc/systemd/system/awg1-eth1-routing.service << '\''EOF'\''
[Unit]
Description=AmneziaWG and Eth1 Routing with Monitoring
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/root/awg1-eth1-routing.sh start
ExecStop=/root/awg1-eth1-routing.sh stop
ExecReload=/root/awg1-eth1-routing.sh restart
Restart=on-failure
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
EOF

# 6. Перезагрузить systemd и запустить
systemctl stop awg1-eth1-routing.service
systemctl daemon-reload
systemctl enable awg1-eth1-routing.service
systemctl start awg1-eth1-routing.service

# 7. Проверить статус
systemctl status awg-quick@awg1
systemctl status awg1-eth1-routing.service

# 8. Посмотреть логи
tail -f /var/log/awg-routing.log
'

# ============================================
# КОНФИГУРАЦИЯ
# ============================================
LOCK_FILE="/var/lock/awg-routing.lock"
MONITOR_PID_FILE="/var/run/awg-monitor.pid"
LOG_FILE="/var/log/awg-routing.log"
STATUS_FILE="/var/run/awg-routing-status"
METRICS_FILE="/var/run/awg-routing-metrics"

# Параметры мониторинга
CHECK_INTERVAL=30
PING_TARGETS="8.8.8.8 1.1.1.1 9.9.9.9"
PING_COUNT=2
PING_TIMEOUT=2
FAILURE_THRESHOLD=3
RECOVERY_THRESHOLD=2

# Таймауты для запуска
AWG_START_TIMEOUT=5
AWG_START_RETRIES=3

SSH_PORT=${SSH_PORT:-22}
DEBUG=${DEBUG:-false}

# ============================================
# ФУНКЦИИ ЛОГИРОВАНИЯ
# ============================================
log() {
    local level="${2:-INFO}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    case "$level" in
        "ACTION")  level_pad="[ACTION] " ;;
        "MONITOR") level_pad="[MONITOR]" ;;
        "WARN")    level_pad="[WARN]   " ;;
        "ERROR")   level_pad="[ERROR]  " ;;
        "OK")      level_pad="[OK]     " ;;
        "DEBUG")   level_pad="[DEBUG]  " ;;
        *)         level_pad="[INFO]   " ;;
    esac
    printf "%s %s - %s\n" "$timestamp" "$level_pad" "$1" | tee -a "$LOG_FILE"
}

log_debug() {
    if [ "$DEBUG" = "true" ]; then
        log "$1" "DEBUG"
    fi
}

# ============================================
# ФУНКЦИИ ПОЛУЧЕНИЯ ИНФОРМАЦИИ
# ============================================
get_eth1_ip() {
    ip -4 addr show eth1 2>/dev/null | grep inet | awk '{print $2}' | cut -d/ -f1 | head -1
}

get_default_gw() {
    ip route 2>/dev/null | grep default | awk '{print $3}' | head -1
}

get_awg1_ip() {
    ip -4 addr show awg1 2>/dev/null | grep inet | awk '{print $2}' | cut -d/ -f1 | head -1
}

get_awg1_peer_count() {
    awg show awg1 2>/dev/null | grep -c "peer:" 2>/dev/null || echo "0"
}

# ============================================
# ФУНКЦИИ ПРОВЕРКИ СТАТУСА
# ============================================
check_awg_status() {
    systemctl is-active --quiet awg-quick@awg1 2>/dev/null
    return $?
}

check_awg_interface() {
    ip link show awg1 >/dev/null 2>&1
    return $?
}

check_awg_routing() {
    if ! check_awg_interface; then
        log_debug "Интерфейс awg1 не существует"
        return 1
    fi
    
    local awg_ip=$(get_awg1_ip)
    if [ -z "$awg_ip" ]; then
        log_debug "awg1 не имеет IP адреса"
        return 1
    fi
    
    if ! ip route show table 200 2>/dev/null | grep -q "default dev awg1"; then
        log_debug "Маршрут по умолчанию через awg1 отсутствует в таблице 200"
        return 1
    fi
    
    if ! ip rule show 2>/dev/null | grep -q "from 192.168.0.0/24 lookup 200"; then
        log_debug "Правило для подсети 192.168.0.0/24 отсутствует"
        return 1
    fi
    
    local success=0
    for target in $PING_TARGETS; do
        if ping -I awg1 -c $PING_COUNT -W $PING_TIMEOUT "$target" >/dev/null 2>&1; then
            success=1
            log_debug "Ping через awg1 до $target успешен"
            break
        else
            log_debug "Ping через awg1 до $target не удался"
        fi
    done
    
    if [ $success -eq 1 ]; then
        return 0
    else
        log_debug "Все попытки ping через awg1 не удались"
        return 1
    fi
}

# ============================================
# ФУНКЦИЯ ПРОВЕРКИ ГОТОВНОСТИ ТУННЕЛЯ (без ping)
# ============================================
check_awg_ready() {
    # Проверяем только наличие интерфейса и IP
    if ! check_awg_interface; then
        return 1
    fi
    
    local awg_ip=$(get_awg1_ip)
    if [ -z "$awg_ip" ]; then
        return 1
    fi
    
    return 0
}

# ============================================
# ФУНКЦИЯ ЗАПУСКА AWG1 С ТАЙМАУТОМ
# ============================================
start_awg1_with_timeout() {
    log "Запуск awg1..." "ACTION"
    
    # 1. Права на конфиг
    chmod 600 /etc/amnezia/amneziawg/awg1.conf 2>/dev/null
    
    # 2. Очистка
    #systemctl stop awg-quick@awg1 2>/dev/null
    #awg-quick down awg1 2>/dev/null
    
    # 3. Первая попытка с использованием встроенного таймаута systemd
    log "Попытка запуска через systemd (таймаут ${AWG_START_TIMEOUT}с)..." "INFO"
    systemctl start awg-quick@awg1 --wait --timeout="${AWG_START_TIMEOUT}s" 2>/dev/null
    
    sleep 2
    if check_awg_status; then
        log "awg1 успешно запущен" "OK"
        return 0
    fi
    
    # 4. Если systemd не справился, пробуем агрессивный перезапуск
    log "Первая попытка не удалась. Сбрасываем зависшие процессы и пробуем снова..." "WARN"
    
    systemctl kill -s KILL awg-quick@awg1 2>/dev/null
    awg-quick down awg1 2>/dev/null
    systemctl stop awg-quick@awg1 2>/dev/null
    
    # Вторая попытка запуска
    systemctl start awg-quick@awg1 --wait --timeout="${AWG_START_TIMEOUT}s" 2>/dev/null
    
    sleep 2
    if check_awg_status; then
        log "awg1 успешно запущен со второй попытки" "OK"
        return 0
    fi
    
    log "ОШИБКА: Не удалось запустить awg1" "ERROR"
    return 1
}

# ============================================
# ФУНКЦИИ УПРАВЛЕНИЯ МАРШРУТИЗАЦИЕЙ
# ============================================
enable_routing() {
    log "=== ВКЛЮЧЕНИЕ МАРШРУТИЗАЦИИ ===" "ACTION"
    
    local ETH1_IP=$(get_eth1_ip)
    local DEFAULT_GW=$(get_default_gw)
    local AWG1_IP=$(get_awg1_ip)
    
    if [ -z "$ETH1_IP" ] || [ -z "$DEFAULT_GW" ]; then
        log "ОШИБКА: Не удалось получить IP eth1 или шлюз" "ERROR"
        return 1
    fi
    
    if [ -z "$AWG1_IP" ]; then
        log "ОШИБКА: awg1 не имеет IP адреса" "ERROR"
        return 1
    fi
    
    log "IP eth1: $ETH1_IP"
    log "Шлюз по умолчанию: $DEFAULT_GW"
    log "IP awg1: $AWG1_IP"
    
    ip link set dev eth1 mtu 1280 2>/dev/null
    log "MTU eth1 установлен в 1280"
    
    ip rule del from 192.168.0.0/24 table 200 2>/dev/null
    ip rule del from $ETH1_IP table main 2>/dev/null
    ip rule del from $ETH1_IP table main priority 999 2>/dev/null
    ip rule del from $ETH1_IP table main priority 500 2>/dev/null
    ip route flush table 200 2>/dev/null
    log "Старые правила очищены"
    
    ip route add default dev awg1 table 200 2>/dev/null
    if [ $? -eq 0 ]; then
        log "Таблица 200 настроена с маршрутом через awg1"
    else
        log "Предупреждение: Не удалось добавить маршрут в таблицу 200" "WARN"
    fi
    
    ip rule add from $ETH1_IP table main priority 999 2>/dev/null
    log "Правило для локального IP добавлено"
    
    ip rule add from 192.168.0.0/24 table 200 priority 1000 2>/dev/null
    log "Правило для подсети 192.168.0.0/24 добавлено"
    
    ip route add default via $DEFAULT_GW dev eth1 table main 2>/dev/null
    log "Основной маршрут через шлюз сохранен"
    
    iptables -t nat -D POSTROUTING -o awg1 -j MASQUERADE 2>/dev/null
    iptables -D FORWARD -i eth1 -o awg1 -j ACCEPT 2>/dev/null
    iptables -D FORWARD -i awg1 -o eth1 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null
    iptables -t mangle -D FORWARD -p tcp --tcp-flags SYN,RST SYN -o awg1 -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null
    iptables -t mangle -D FORWARD -i eth1 -o awg1 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1240 2>/dev/null
    iptables -t mangle -D FORWARD -i awg1 -o eth1 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1240 2>/dev/null
    
    iptables -t nat -A POSTROUTING -o awg1 -j MASQUERADE 2>/dev/null
    iptables -A FORWARD -i eth1 -o awg1 -j ACCEPT 2>/dev/null
    iptables -A FORWARD -i awg1 -o eth1 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null
    iptables -I FORWARD 1 -i eth1 -o awg1 -j ACCEPT 2>/dev/null
    iptables -I FORWARD 2 -i awg1 -o eth1 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null
    iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -o awg1 -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null
    iptables -t mangle -A FORWARD -i eth1 -o awg1 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1240 2>/dev/null
    iptables -t mangle -A FORWARD -i awg1 -o eth1 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1240 2>/dev/null
    log "Правила iptables настроены"
    
    sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
    sysctl -w net.ipv4.conf.awg1.rp_filter=2 >/dev/null 2>&1
    sysctl -w net.ipv4.conf.eth1.rp_filter=0 >/dev/null 2>&1
    sysctl -w net.ipv4.conf.all.rp_filter=0 >/dev/null 2>&1
    ip route flush cache >/dev/null 2>&1
    log "Параметры ядра применены"
    
    echo "enabled" > "$STATUS_FILE"
    echo "enabled_at=$(date +%s)" >> "$STATUS_FILE"
    log "Маршрутизация успешно включена"
    return 0
}

disable_routing() {
    log "=== ОТКЛЮЧЕНИЕ МАРШРУТИЗАЦИИ ===" "ACTION"
    
    local ETH1_IP=$(get_eth1_ip)
    
    ip rule del from 192.168.0.0/24 table 200 2>/dev/null
    ip rule del from $ETH1_IP table main 2>/dev/null
    ip rule del from $ETH1_IP table main priority 999 2>/dev/null
    ip rule del from $ETH1_IP table main priority 500 2>/dev/null
    ip route flush table 200 2>/dev/null
    
    iptables -t nat -D POSTROUTING -o awg1 -j MASQUERADE 2>/dev/null
    iptables -D FORWARD -i eth1 -o awg1 -j ACCEPT 2>/dev/null
    iptables -D FORWARD -i awg1 -o eth1 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null
    iptables -t mangle -D FORWARD -p tcp --tcp-flags SYN,RST SYN -o awg1 -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null
    iptables -t mangle -D FORWARD -i eth1 -o awg1 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1240 2>/dev/null
    iptables -t mangle -D FORWARD -i awg1 -o eth1 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1240 2>/dev/null
    
    echo "disabled" > "$STATUS_FILE"
    echo "disabled_at=$(date +%s)" >> "$STATUS_FILE"
    log "Маршрутизация отключена"
    return 0
}

# ============================================
# ФУНКЦИИ МОНИТОРИНГА
# ============================================
monitor_loop() {
    log "=== ЗАПУСК МОНИТОРИНГА (интервал: ${CHECK_INTERVAL}с) ===" "MONITOR"
    
    echo $$ > "$MONITOR_PID_FILE"
    
    local routing_enabled=false
    local failure_count=0
    local success_count=0
    local first_check=true
    
    while true; do
        sleep $CHECK_INTERVAL
        
        if ! check_awg_status; then
            log "ВНИМАНИЕ: awg1 неактивен" "WARN"
            if [ "$routing_enabled" = true ]; then
                disable_routing
                routing_enabled=false
                failure_count=0
                success_count=0
            fi
            continue
        fi
        
        if check_awg_routing; then
            success_count=$((success_count + 1))
            failure_count=0
            
            if [ "$routing_enabled" = false ]; then
                if [ $success_count -ge $RECOVERY_THRESHOLD ]; then
                    log "Маршрут awg1 восстановлен (проверок: $success_count), включаем маршрутизацию..." "MONITOR"
                    if enable_routing; then
                        routing_enabled=true
                        success_count=0
                        log "Маршрутизация успешно включена после восстановления" "OK"
                    else
                        log "ОШИБКА: Не удалось включить маршрутизацию" "ERROR"
                    fi
                else
                    log_debug "Маршрут доступен, но ждем $RECOVERY_THRESHOLD успешных проверок ($success_count/$RECOVERY_THRESHOLD)"
                fi
            else
                if [ "$first_check" = true ]; then
                    log "Маршрут awg1 работает стабильно" "OK"
                    first_check=false
                fi
                echo "last_check_ok=$(date +%s)" > "$METRICS_FILE"
                echo "peer_count=$(get_awg1_peer_count)" >> "$METRICS_FILE"
            fi
        else
            failure_count=$((failure_count + 1))
            success_count=0
            
            if [ "$routing_enabled" = true ]; then
                if [ $failure_count -ge $FAILURE_THRESHOLD ]; then
                    log "Маршрут awg1 недоступен (неудачных проверок: $failure_count), отключаем маршрутизацию..." "MONITOR"
                    disable_routing
                    routing_enabled=false
                    failure_count=0
                else
                    log_debug "Маршрут недоступен, но ждем $FAILURE_THRESHOLD неудачных проверок ($failure_count/$FAILURE_THRESHOLD)"
                fi
            else
                if [ "$first_check" = true ]; then
                    log "Маршрут awg1 недоступен при первом запуске мониторинга" "WARN"
                    first_check=false
                fi
            fi
        fi
    done
}

# ============================================
# ФУНКЦИИ УПРАВЛЕНИЯ МОНИТОРОМ
# ============================================
start_monitor() {
    if [ -f "$MONITOR_PID_FILE" ]; then
        local old_pid=$(cat "$MONITOR_PID_FILE" 2>/dev/null)
        if kill -0 $old_pid 2>/dev/null; then
            log "Монитор уже запущен (PID: $old_pid)" "MONITOR"
            return 0
        fi
        rm -f "$MONITOR_PID_FILE"
    fi
    
    monitor_loop &
    local pid=$!
    echo $pid > "$MONITOR_PID_FILE"
    log "Монитор запущен (PID: $pid)" "MONITOR"
    return 0
}

stop_monitor() {
    if [ -f "$MONITOR_PID_FILE" ]; then
        local pid=$(cat "$MONITOR_PID_FILE" 2>/dev/null)
        if kill -0 $pid 2>/dev/null; then
            kill $pid 2>/dev/null
            sleep 1
            if kill -0 $pid 2>/dev/null; then
                kill -9 $pid 2>/dev/null
            fi
            log "Монитор остановлен (PID: $pid)" "MONITOR"
        fi
        rm -f "$MONITOR_PID_FILE"
    fi
}

# ============================================
# ОСНОВНАЯ ФУНКЦИЯ
# ============================================
main() {
    if [ -f "$LOCK_FILE" ]; then
        local lock_pid=$(cat "$LOCK_FILE" 2>/dev/null)
        if kill -0 $lock_pid 2>/dev/null; then
            log "Скрипт уже запущен (PID: $lock_pid), выходим" "WARN"
            exit 1
        else
            rm -f "$LOCK_FILE"
        fi
    fi
    
    echo $$ > "$LOCK_FILE"
    
    cleanup() {
        rm -f "$LOCK_FILE"
    }
    trap cleanup EXIT INT TERM
    
    case "${1:-start}" in
        start)
            log "=== ЗАПУСК СИСТЕМЫ МАРШРУТИЗАЦИИ ===" "ACTION"
            
            # Проверяем, запущен ли awg1
            if ! check_awg_status; then
                # Пробуем запустить с таймаутом
                if ! start_awg1_with_timeout; then
                    log "Не удалось запустить awg1, продолжаем в режиме ожидания" "WARN"
                fi
            else
                log "awg1 уже запущен" "OK"
            fi
            
            # ИЗМЕНЕНИЕ: проверяем готовность туннеля (только интерфейс и IP, без ping)
            # И ВКЛЮЧАЕМ МАРШРУТИЗАЦИЮ СРАЗУ, если интерфейс есть и IP получен
            if check_awg_ready; then
                log "Туннель awg1 готов, ВКЛЮЧАЕМ маршрутизацию..." "ACTION"
                enable_routing
            else
                log "Туннель awg1 НЕ ГОТОВ (нет интерфейса или IP), маршрутизация будет включена монитором позже" "WARN"
                echo "disabled" > "$STATUS_FILE"
            fi
            
            # Запускаем монитор в любом случае
            start_monitor
            
            log "=== СИСТЕМА ЗАПУЩЕНА ===" "OK"
            exit 0
            ;;
            
        stop)
            log "=== ОСТАНОВКА СИСТЕМЫ ===" "ACTION"
            stop_monitor
            disable_routing
            rm -f "$STATUS_FILE" "$METRICS_FILE" 2>/dev/null
            log "=== СИСТЕМА ОСТАНОВЛЕНА ===" "OK"
            exit 0
            ;;
            
        restart)
            $0 stop
            sleep 2
            $0 start
            ;;
            
        status)
            if [ -f "$STATUS_FILE" ]; then
                echo "=== СТАТУС СИСТЕМЫ ==="
                cat "$STATUS_FILE"
                echo ""
                echo "Правила маршрутизации:"
                ip rule show | grep -E "(from 192.168.0.0/24|from.*eth1)" 2>/dev/null || echo "  Нет специальных правил"
                echo ""
                echo "Таблица 200:"
                ip route show table 200 2>/dev/null || echo "  Таблица пуста"
                
                if [ -f "$MONITOR_PID_FILE" ]; then
                    local pid=$(cat "$MONITOR_PID_FILE" 2>/dev/null)
                    if kill -0 $pid 2>/dev/null; then
                        echo ""
                        echo "Монитор: Активен (PID: $pid)"
                    else
                        echo ""
                        echo "Монитор: Неактивен"
                    fi
                fi
            else
                echo "Статус не определен"
            fi
            ;;
            
        enable)
            log "Принудительное включение маршрутизации" "ACTION"
            enable_routing
            start_monitor
            ;;
            
        disable)
            log "Принудительное отключение маршрутизации" "ACTION"
            stop_monitor
            disable_routing
            ;;
            
        monitor)
            start_monitor
            while true; do
                sleep 60
            done
            ;;
            
        test)
            log "Тестирование маршрутизации..." "ACTION"
            if check_awg_routing; then
                log "✅ Маршрут awg1 доступен" "OK"
            else
                log "❌ Маршрут awg1 недоступен" "ERROR"
            fi
            ;;
            
        *)
            echo "Использование: $0 {start|stop|restart|status|enable|disable|monitor|test}"
            echo ""
            echo "  start    - Запуск всей системы с мониторингом"
            echo "  stop     - Остановка системы и мониторинга"
            echo "  restart  - Перезапуск системы"
            echo "  status   - Показать текущий статус"
            echo "  enable   - Принудительно включить маршрутизацию"
            echo "  disable  - Принудительно отключить маршрутизацию"
            echo "  monitor  - Запустить только монитор"
            echo "  test     - Проверить доступность маршрута"
            exit 1
            ;;
    esac
}

main "$@"
