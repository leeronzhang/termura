# termura-shell-integration
# OSC 133 shell integration hooks for Termura terminal.
# Sourced automatically from .zshrc / .bashrc after installation.

# ── zsh ──────────────────────────────────────────────────────────────────────
if [ -n "$ZSH_VERSION" ]; then
    _termura_exit=0

    precmd_termura() {
        printf '\033]133;D;%s\007' "${_termura_exit:-0}"
        printf '\033]133;A\007'
        # OSC 7: report working directory so the terminal can show it in the path bar.
        printf '\033]7;file://%s%s\007' "$HOST" "$PWD"
    }

    preexec_termura() {
        _termura_exit=$?
        printf '\033]133;B\007'
        printf '\033]133;C\007'
    }

    autoload -Uz add-zsh-hook
    add-zsh-hook precmd precmd_termura
    add-zsh-hook preexec preexec_termura

# ── bash ─────────────────────────────────────────────────────────────────────
elif [ -n "$BASH_VERSION" ]; then
    _termura_exit=0

    _termura_precmd() {
        printf '\033]133;D;%s\007' "${_termura_exit:-0}"
        printf '\033]133;A\007'
        # OSC 7: report working directory so the terminal can show it in the path bar.
        printf '\033]7;file://%s%s\007' "$HOSTNAME" "$PWD"
    }

    _termura_preexec() {
        _termura_exit=$?
        printf '\033]133;B\007'
        printf '\033]133;C\007'
    }

    PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND; }_termura_precmd"
    trap '_termura_preexec' DEBUG
fi
