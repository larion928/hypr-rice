# ~/.config/fish/config.fish
# Перенесено из ~/.zshrc при переходе на fish

# --- PATH (аналог export PATH из .zshrc / .zprofile) ---
# fish_add_path сам не добавляет дубликаты и правит $PATH универсально
fish_add_path -g $HOME/.local/bin
fish_add_path -g $HOME/.cargo/bin

# --- Алиасы (то, что было простыми alias в .zshrc) ---
alias zapret-config='$HOME/zapret-configs/install.sh'
alias zapret-utils='$HOME/zapret-configs/utils-zapret.sh'
alias mcaselector='/usr/lib/jvm/java-21-openjdk/bin/java --module-path /usr/lib/jvm/java-21-openjdk/lib --add-modules ALL-MODULE-PATH -jar mcaselector-2.7.jar'

# NeoHtop — системный монитор (запуск релизного бинарника)
alias neohtop='~/neohtop/src-tauri/target/release/NeoHtop'

# neohtop-dev определён как функция ниже (в нём несколько команд + env),
# потому что синтаксис && из zsh в fish не работает — см. ~/.config/fish/functions/
