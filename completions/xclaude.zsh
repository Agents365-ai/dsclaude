#compdef xclaude dsclaude mmclaude qwclaude glmclaude kmclaude arkclaude lcclaude mxclaude hyclaude sfclaude

# Zsh completions for xxclaude launchers.
# Source this file in your ~/.zshrc:
#   fpath=(/path/to/xxclaude/completions $fpath)
#   autoload -Uz compinit && compinit

local -a common_flags
common_flags=('fast:use flash/lite tier as main model'
             'flash:use flash/lite tier'
             'long:request max context window (1M)'
             'effort:set reasoning effort level'
             'update:git pull latest version'
             '--help:show help')

local -a effort_levels
effort_levels=('low:minimal reasoning'
               'medium:moderate reasoning'
               'high:thorough reasoning'
               'xhigh:very thorough reasoning'
               'max:maximum reasoning depth')

# ---- xclaude ----
_xclaude() {
  local -a subcmds
  subcmds=('ls:list all backends and key status'
           'menu:interactive backend picker'
           'help:show help')
  _arguments -C \
    '1: :_alternative "sub:subcommand:((ls\:list\ all\ backends menu\:interactive\ picker help\:show\ help))" "flag:flag:((fast long effort))"' \
    '*::args:_default'
}
compdef _xclaude xclaude

# ---- dsclaude ----
compdef '_arguments "1: :((fast\:flash\ tier long\:1M\ context effort\:effort\ level think\:deep\ reasoning reasoner\:backward-compat\ alias -r\:backward-compat\ alias update\:git\ pull\ latest))"' dsclaude

# ---- mmclaude ----
compdef '_arguments "1: :((fast long effort update))"' mmclaude

# ---- qwclaude ----
compdef '_arguments "1: :((max pro plus fast flash long effort coding token intl cn update))"' qwclaude

# ---- glmclaude ----
compdef '_arguments "1: :((fast long effort update))"' glmclaude

# ---- kmclaude ----
compdef '_arguments "1: :((fast long effort update))"' kmclaude

# ---- arkclaude ----
compdef '_arguments "1: :((max pro plus fast flash lite kimi kimi-pro kimi-k2 deepseek deepseek-flash glm minimax long effort update))"' arkclaude

# ---- lcclaude ----
compdef '_arguments "1: :((fast flash think long effort update))"' lcclaude

# ---- mxclaude ----
compdef '_arguments "1: :((fast long effort update))"' mxclaude

# ---- hyclaude ----
compdef '_arguments "1: :((max pro code fast flash lite kimi kimi-pro kimi-k2 deepseek deepseek-flash glm minimax qwen long effort update))"' hyclaude

# ---- sfclaude ----
compdef '_arguments "1: :((max pro fast flash lite kimi glm minimax qwen yi r1 long effort update))"' sfclaude
