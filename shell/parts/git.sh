cdg() {
    # Находим корень git репозитория
    local git_root
    git_root=$(git rev-parse --show-toplevel 2>/dev/null)
    
    # Проверяем, что мы находимся внутри git-репозитория
    if [ -n "$git_root" ]; then
        cd "$git_root" || return
    else
        echo "Не в git-репозитории"
    fi
}