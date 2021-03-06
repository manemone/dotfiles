source ~/.zplug/init.zsh

zplug 'zplug/zplug', hook-build:'zplug --self-manage'

# Theme
zplug "mafredri/zsh-async", from:github
zplug "sindresorhus/pure", use:pure.zsh, from:github, as:theme

# Syntax highlighting
zplug "zsh-users/zsh-syntax-highlighting"

# Searching for command history
zplug "zsh-users/zsh-history-substring-search"

# Completion
zplug "zsh-users/zsh-autosuggestions"
zplug "zsh-users/zsh-completions"
zplug "chrissicool/zsh-256color"

# Install plugins if there are plugins that have not been installed
if ! zplug check --verbose; then
  printf "Install? [y/N]: "
  if read -q; then
    echo; zplug install
  fi
fi

# Then, source plugins and add commands to $PATH
zplug load

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=1000
HISTFILESIZE=2000

# some more ls aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# rbenv
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init -)"

# postgresql
export PGDATA=/usr/local/var/postgres

# one-liner httpd
alias webrick="ruby -rwebrick -e 'WEBrick::HTTPServer.new(:DocumentRoot => \"./\", :Port => 8000).start'"

# use brew-installed libraries primarily
export PATH=/usr/local/bin:$PATH

# shortened command "bundle exec"
alias be="bundle exec"
alias bx="bundle exec"

# Rust
export PATH="$HOME/.cargo/bin:$PATH"

# pyenv
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init --path)"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"

# NeoVim
alias vim="nvim"
alias vi="nvim"
export EDITOR=nvim

# n (node.js version manager)
export N_PREFIX="$HOME/.n"
export PATH="$PATH:$N_PREFIX/bin"

# Google Cloud SDK
if [ ! -f "$(brew --prefix)/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.zsh.inc" ]; then
  source "$(brew --prefix)/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.zsh.inc"
fi
if [ ! -f "$(brew --prefix)/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.zsh.inc" ]; then
  source "$(brew --prefix)/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.zsh.inc"
fi
