# Личные команды-скрипты myconfig: всё исполняемое из ~/myconfig/shell/bin/
# становится командой на PATH (напр. pcap2flows). Кладёшь скрипт в bin/,
# chmod +x — и он команда, без per-tool алиаса. Путь выводим из
# SHELL_CONFIG_ROOT (=~/myconfig/shell), срезая /sh → портируется гитом.
export PATH="$SHELL_CONFIG_ROOT/bin:$PATH"
