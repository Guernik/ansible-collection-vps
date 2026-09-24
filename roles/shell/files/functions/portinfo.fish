function portinfo
    if test (count $argv) -eq 0
        echo "Usage: portinfo <port>"
        return 1
    end

    set -l port $argv[1]

    echo "── Socket info (ss) ──────────────────────────────────"
    sudo ss -tlnp | head -1
    sudo ss -tlnp | grep ":$port "

    echo ""
    echo "── Open files on port (lsof) ──────────────────────────"
    sudo lsof -i :$port

    # Extract PID from ss output for deeper inspection
    set -l pid (sudo ss -tlnp | grep ":$port " | string match -r 'pid=(\d+)' | head -2 | tail -1)

    if test -n "$pid"
        echo ""
        echo "── Process details (PID: $pid) ────────────────────────"
        ps -p $pid -o pid,ppid,user,%cpu,%mem,start,command --no-headers

        echo ""
        echo "── Process tree ─────────────────────────────────────"
        pstree -sp $pid

        echo ""
        echo "── Files opened by process ────────────────────────────"
        sudo lsof -p $pid | head -20
    end

    # Check if it's a docker-proxy process
    if sudo ss -tlnp | grep ":$port " | grep -q docker-proxy
        echo ""
        echo "── Docker container on port $port ──────────────────────"
        docker ps --filter "publish=$port" --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
    end
end
