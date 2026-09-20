# ncd -- jump to a previously visited directory matching a fragment.
# Repeat the same command to rotate through the other matches.
#
# Source this file from your ~/.bashrc:
#     . $HOME/bin/bashrc.inc

ncd() {
    local target
    target=$("$HOME/bin/ncd.pl" "$@")
    [ -n "$target" ] && cd "$target"
}

# ncs [n] -- rotate among the n last directories (default 2, i.e. `cd -`).
ncs() {
    local target
    target=$("$HOME/bin/ncd.pl" -SWAPLAST "$@")
    [ -n "$target" ] && cd "$target"
}
