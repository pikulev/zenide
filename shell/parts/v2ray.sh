# Для включения прокси
alias proxy_on="export http_proxy=http://127.0.0.1:8001; export https_proxy=http://127.0.0.1:8001; export all_proxy=socks5://127.0.0.1:1081"

# Для выключения прокси
alias proxy_off="unset http_proxy https_proxy all_proxy"