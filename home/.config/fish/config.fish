# The rice's scripts and cargo-installed tools.
fish_add_path -g $HOME/.local/bin
fish_add_path -g $HOME/.cargo/bin

# Your own aliases, PATH and variables. Not part of the rice: rice update leaves it alone.
test -f ~/.config/fish/user.fish; and source ~/.config/fish/user.fish
