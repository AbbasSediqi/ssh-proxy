cat << 'EOF' > setup-proxy.sh
#!/bin/bash

# --- 1. INITIAL SETUP ---
clear
echo "=========================================="
echo "      SSH PROXY PANEL INSTALLER          "
echo "=========================================="
read -p "Enter Foreign Server IP: " R_IP
read -p "Enter Tunnel Port (Default 1081): " R_PORT
R_PORT=${R_PORT:-1081}

# --- 2. CREATE THE MAIN SCRIPT ---
cat << 'INNER_EOF' > /usr/local/bin/ssh-proxy
#!/bin/bash
CONFIG_FILE="/etc/ssh-proxy-list.conf"
touch $CONFIG_FILE

list_indexed_ports() {
    local i=1
    while IFS=: read -r p ip; do
        echo "$i - Port: $p (Remote: $ip)"
        eval "port_$i=$p"
        i=$((i+1))
    done < $CONFIG_FILE
    return $((i-1))
}

show_menu() {
    clear
    echo "=========================================="
    echo "      SSH TUNNEL MANAGEMENT PANEL        "
    echo "=========================================="
    echo "1) Create New Tunnel"
    echo "2) List Active Tunnels & Status"
    echo "3) Stop & Delete a Tunnel"
    echo "4) Ping Test (Latency)"
    echo "5) Speed Test (Download Speed)"
    echo "6) View Tunnel Logs"
    echo "7) UNINSTALL EVERYTHING"
    echo "8) Exit"
    echo "------------------------------------------"
    read -p "Select option: " choice
    case $choice in
        1) create_tunnel ;;
        2) list_tunnels ;;
        3) delete_tunnel ;;
        4) ping_test ;;
        5) speed_test ;;
        6) view_logs ;;
        7) uninstall_panel ;;
        8) exit 0 ;;
        *) show_menu ;;
    esac
}

create_tunnel() {
    local IP=$1; local PORT=$2
    if [[ -z "$IP" ]]; then read -p "Remote IP: " IP; read -p "Port: " PORT; fi
    PORT=${PORT:-1081}
    SERVICE="ssh-proxy-${PORT}"
    if [ ! -f ~/.ssh/id_rsa ]; then ssh-keygen -t rsa -b 4096 -N "" -f ~/.ssh/id_rsa; fi
    ssh-copy-id -o StrictHostKeyChecking=no root@${IP}
    
    cat <<S_FILE > /etc/systemd/system/${SERVICE}.service
[Unit]
Description=SSH Tunnel ${PORT}
After=network.target
[Service]
User=root
ExecStart=/usr/bin/ssh -N -D 0.0.0.0:${PORT} -o ServerAliveInterval=15 -o StrictHostKeyChecking=accept-new root@${IP}
Restart=always
S_FILE

    systemctl daemon-reload && systemctl enable ${SERVICE} && systemctl restart ${SERVICE}
    if ! grep -q "^${PORT}:" $CONFIG_FILE; then echo "${PORT}:${IP}" >> $CONFIG_FILE; fi
    echo "Done!"; sleep 1; [[ -z "$1" ]] && show_menu
}

ping_test() {
    echo -e "\nSelect Port Index:"
    list_indexed_ports
    read -p "Index: " IDX
    eval "P=\$port_$IDX"
    if [[ -z "$P" ]]; then show_menu; fi
    echo "Testing latency to 1.1.1.1..."
    curl -4 -o /dev/null -s --connect-timeout 5 -w "Connect: %{time_connect}s | Total: %{time_total}s\n" --socks5-hostname 127.0.0.1:${P} http://1.1.1.1 || echo "Error: Offline"
    read -p "Press Enter..."; show_menu
}

speed_test() {
    echo -e "\nSelect Port Index:"
    list_indexed_ports
    read -p "Index: " IDX
    eval "P=\$port_$IDX"
    if [[ -z "$P" ]]; then show_menu; fi
    curl -4 -L --socks5-hostname 127.0.0.1:${P} -o /dev/null --connect-timeout 10 http://cachefly.cachefly.net/10mb.test
    read -p "Press Enter..."; show_menu
}

delete_tunnel() {
    echo -e "\nSelect Port Index to delete:"
    list_indexed_ports
    read -p "Index: " IDX
    eval "P=\$port_$IDX"
    if [[ -z "$P" ]]; then show_menu; fi
    systemctl stop ssh-proxy-${P} && systemctl disable ssh-proxy-${P}
    rm -f /etc/systemd/system/ssh-proxy-${P}.service
    sed -i "/^${P}:/d" $CONFIG_FILE
    echo "Deleted."; sleep 1; show_menu
}

view_logs() {
    echo -e "\nSelect Port Index:"
    list_indexed_ports
    read -p "Index: " IDX
    eval "P=\$port_$IDX"
    if [[ -z "$P" ]]; then show_menu; fi
    journalctl -u ssh-proxy-${P} -n 30
    read -p "Press Enter..."; show_menu
}

list_tunnels() {
    echo -e "\nPORT\tIP\tSTATUS"
    while IFS=: read -r p ip; do
        s=$(systemctl is-active ssh-proxy-${p})
        echo -e "${p}\t${ip}\t${s}"
    done < $CONFIG_FILE
    read -p "Press Enter..."; show_menu
}

uninstall_panel() {
    while IFS=: read -r p ip; do
        systemctl stop ssh-proxy-${p} && systemctl disable ssh-proxy-${p}
        rm -f /etc/systemd/system/ssh-proxy-${p}.service
    done < $CONFIG_FILE
    rm -f $CONFIG_FILE /usr/local/bin/ssh-proxy
    echo "Uninstalled."; exit 0
}

if [[ "$1" == "init" ]]; then create_tunnel $2 $3; else show_menu; fi
INNER_EOF

# --- 3. FINALIZING ---
chmod +x /usr/local/bin/ssh-proxy
/usr/local/bin/ssh-proxy init $R_IP $R_PORT
echo "Installation complete! Type 'ssh-proxy' to manage."
EOF

bash setup-proxy.sh