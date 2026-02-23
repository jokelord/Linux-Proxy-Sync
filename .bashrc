# =========================================================
# Ubuntu 24.04 (GNOME) 终端代理同步脚本 - 最终版
# 特性：防 DNS 污染 (socks5h) + 健壮校验 + 自动同步
# =========================================================

function update_proxy() {
    # 1. 依赖检查：非 GNOME 环境静默跳过
    if ! command -v gsettings &> /dev/null; then
        return 0
    fi

    # 2. 清理环境变量函数
    clean_proxy() {
        unset http_proxy HTTP_PROXY https_proxy HTTPS_PROXY ftp_proxy rsync_proxy all_proxy ALL_PROXY no_proxy NO_PROXY
    }

    # 3. 读取代理模式
    local mode
    mode=$(gsettings get org.gnome.system.proxy mode 2>/dev/null | tr -d "'")

    # 如果不是手动模式，清理代理并退出
    if [ "$mode" != "manual" ]; then
        clean_proxy
        return 0
    fi

    # 4. 读取 HTTP 和 SOCKS 配置
    local http_host http_port socks_host socks_port
    http_host=$(gsettings get org.gnome.system.proxy.http host 2>/dev/null | tr -d "'")
    http_port=$(gsettings get org.gnome.system.proxy.http port 2>/dev/null)
    socks_host=$(gsettings get org.gnome.system.proxy.socks host 2>/dev/null | tr -d "'")
    socks_port=$(gsettings get org.gnome.system.proxy.socks port 2>/dev/null)

    # 5. 端口校验辅助函数 (正则匹配数字且大于 0)
    is_valid_port() {
        [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -gt 0 ]
    }

    # 6. 如果 HTTP 和 SOCKS 都无效，则清理代理
    if ! is_valid_port "$http_port" && ! is_valid_port "$socks_port"; then
        clean_proxy
        return 0
    fi

    # 7. 构建 no_proxy (系统设置 + 强制内网段)
    local ignore_hosts
    # 处理 GNOME 数组格式 ['a', 'b'] -> a,b
    ignore_hosts=$(gsettings get org.gnome.system.proxy ignore-hosts 2>/dev/null | tr -d "[]'" | tr -s ' ' | sed 's/ *, */,/g')
    
    local hard_no_proxy="localhost,127.0.0.1,127.0.0.0/8,::1,*.local,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
    # 优雅拼接：如果 ignore_hosts 存在则加逗号，否则为空
    local final_no_proxy="${ignore_hosts:+$ignore_hosts,}$hard_no_proxy"

    # 8. 导出 HTTP 相关代理 (仅当 HTTP 配置有效时)
    if is_valid_port "$http_port" && [ -n "$http_host" ]; then
        local http_url="http://${http_host}:${http_port}/"
        export http_proxy="$http_url"
        export HTTP_PROXY="$http_url"
        export https_proxy="$http_url"
        export HTTPS_PROXY="$http_url"
        export ftp_proxy="$http_url"
        export rsync_proxy="$http_url"
    fi

    # 9. 导出 ALL_PROXY (优先 SOCKS5h，防止 DNS 污染)
    if is_valid_port "$socks_port" && [ -n "$socks_host" ]; then
        # 注意：使用 socks5h:// 让代理服务器解析域名，避免本地 DNS 污染
        export all_proxy="socks5h://${socks_host}:${socks_port}"
        export ALL_PROXY="socks5h://${socks_host}:${socks_port}"
    elif is_valid_port "$http_port" && [ -n "$http_host" ]; then
        # 降级方案：如果没有 SOCKS，则 all_proxy 也走 HTTP
        export all_proxy="http://${http_host}:${http_port}/"
        export ALL_PROXY="http://${http_host}:${http_port}/"
    fi

    # 10. 导出 no_proxy
    export no_proxy="$final_no_proxy"
    export NO_PROXY="$final_no_proxy"

    # 11. 提示信息
    echo -e "\033[32m[Proxy] 已同步系统代理 (HTTP: ${http_port:-无} | SOCKS: ${socks_port:-无}) \033[0m"
}

# =========================================================
# 执行逻辑
# =========================================================

# 仅在交互式 Shell 中自动执行
if [[ $- == *i* ]]; then
    update_proxy
fi
