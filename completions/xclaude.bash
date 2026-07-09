# Bash completions for xclaude and all backend launchers.
# Source this file in your ~/.bashrc:
#   source /path/to/xxclaude/completions/xclaude.bash

# ---- xclaude ----
_xclaude_complete() {
  local cur prev words cword
  _init_completion || return
  COMPREPLY=()
  case $cword in
    1) COMPREPLY=($(compgen -W "ls menu list pick help fast long effort update --help" -- "$cur")) ;;
    *) COMPREPLY=($(compgen -W "fast flash long effort low medium high xhigh max update --help" -- "$cur")) ;;
  esac
}
complete -F _xclaude_complete xclaude

# ---- Common flags for all launchers ----
_launcher_common_flags="fast flash long effort update --help"

# ---- dsclaude ----
_dsclaude_complete() {
  local cur prev words cword
  _init_completion || return
  COMPREPLY=($(compgen -W "fast flash long effort think reasoner update --help" -- "$cur"))
}
complete -F _dsclaude_complete dsclaude

# ---- mmclaude ----
_mmclaude_complete() {
  local cur; _init_completion || return
  COMPREPLY=($(compgen -W "$_launcher_common_flags" -- "$cur"))
}
complete -F _mmclaude_complete mmclaude

# ---- qwclaude ----
_qwclaude_complete() {
  local cur; _init_completion || return
  COMPREPLY=($(compgen -W "max pro plus fast flash long effort coding token intl cn update --help" -- "$cur"))
}
complete -F _qwclaude_complete qwclaude

# ---- glmclaude ----
_glmclaude_complete() {
  local cur; _init_completion || return
  COMPREPLY=($(compgen -W "$_launcher_common_flags" -- "$cur"))
}
complete -F _glmclaude_complete glmclaude

# ---- kmclaude ----
_kmclaude_complete() {
  local cur; _init_completion || return
  COMPREPLY=($(compgen -W "$_launcher_common_flags" -- "$cur"))
}
complete -F _kmclaude_complete kmclaude

# ---- arkclaude ----
_arkclaude_complete() {
  local cur; _init_completion || return
  COMPREPLY=($(compgen -W "max pro plus fast flash lite kimi kimi-pro kimi-k2 deepseek deepseek-flash glm minimax long effort update --help" -- "$cur"))
}
complete -F _arkclaude_complete arkclaude

# ---- lcclaude ----
_lcclaude_complete() {
  local cur; _init_completion || return
  COMPREPLY=($(compgen -W "fast flash think long effort update --help" -- "$cur"))
}
complete -F _lcclaude_complete lcclaude

# ---- mxclaude ----
_mxclaude_complete() {
  local cur; _init_completion || return
  COMPREPLY=($(compgen -W "$_launcher_common_flags" -- "$cur"))
}
complete -F _mxclaude_complete mxclaude

# ---- hyclaude ----
_hyclaude_complete() {
  local cur; _init_completion || return
  COMPREPLY=($(compgen -W "max pro code fast flash lite kimi kimi-pro kimi-k2 deepseek deepseek-flash glm minimax qwen long effort update --help" -- "$cur"))
}
complete -F _hyclaude_complete hyclaude

# ---- sfclaude ----
_sfclaude_complete() {
  local cur; _init_completion || return
  COMPREPLY=($(compgen -W "max pro fast flash lite kimi glm minimax qwen yi r1 long effort update --help" -- "$cur"))
}
complete -F _sfclaude_complete sfclaude
