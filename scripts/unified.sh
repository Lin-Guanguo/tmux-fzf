#!/usr/bin/env bash
# Unified Command Palette - flat search for all tmux commands
# Usage: bind-key P run-shell -b "path/to/unified.sh"

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/.envs"

# Get current context (single tmux call for performance)
read -r current_session current_window current_pane cur_ses_wins cur_win_name cur_pane_cmd cur_pane_idx <<< \
    "$(tmux display-message -p '#{session_name} #S:#I #S:#{window_index}.#{pane_index} #{session_windows} #{window_name} #{pane_current_command} #{pane_index}')"
cur_widx="${current_window##*:}"

# Format output: 25 char min width, longer commands just add one space
fmt() {
    local cmd="$1" desc="$2"
    if [[ -z "$desc" ]]; then
        printf "%s\n" "$cmd"
    elif [[ ${#cmd} -ge 25 ]]; then
        printf "%s  %s\n" "$cmd" "$desc"
    else
        printf "%-25s %s\n" "$cmd" "$desc"
    fi
}

# Emit all pane actions for a target (DRY helper)
# info format: process@window or process@window~ for current
emit_pane_actions() {
    local target="$1" info="$2"
    fmt "[P] select-pane -t $target" "$info"
    fmt "[P] kill-pane -t $target" "$info"
    fmt "[P] resize-pane -Z -t $target" "$info zoom"
    fmt "[P] break-pane -t $target" "$info"
    fmt "[P] respawn-pane -t $target" "$info"
    fmt "[P] clear-history -t $target" "$info"
    fmt "[P] swap-pane -s $target -t *" "$info select target"
    fmt "[P] join-pane -s $target" "$info to here"
}

generate_candidates() {
    # Sorting strategy: far items at top, close items at bottom (near fzf input)
    # Order: Global -> Other sessions -> Current session other windows -> Current window other panes -> Current -> No-target
    # Left side: actual tmux command, Right side: context info

    # ========== [1] Global commands (top, rarely used) ==========
    fmt "[G] display-panes" "show pane numbers"
    fmt "[G] clock-mode" "show clock"

    # ========== [2] Other sessions (far) ==========
    tmux list-sessions -F '#{session_name}|#{session_windows}|#{session_attached}' 2>/dev/null | while IFS='|' read -r name wins attached; do
        [[ "$name" == "$current_session" ]] && continue
        local info="$wins win"
        [[ "$attached" == "1" ]] && info="*attached $wins win"
        fmt "[S] switch-client -t $name" "$info"
        fmt "[S] kill-session -t $name" "$info"
        fmt "[S] detach-client -s $name" "$info"
        fmt "[S] rename-session -t $name *" "$info input new name"
    done

    # ========== [3] Windows in other sessions ==========
    tmux list-windows -a -F '#{session_name}:#{window_index}|#{window_name}|#{session_name}' 2>/dev/null | while IFS='|' read -r target wname sess; do
        [[ "$sess" == "$current_session" ]] && continue
        fmt "[W] select-window -t $target" "$wname"
        fmt "[W] kill-window -t $target" "$wname"
        fmt "[W] respawn-window -t $target" "$wname"
        fmt "[W] rename-window -t $target *" "$wname input new name"
        fmt "[W] swap-window -s $target -t *" "$wname select target"
    done

    # ========== [4] Panes in other sessions ==========
    tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}|#{pane_current_command}|#{session_name}|#{window_name}' 2>/dev/null | while IFS='|' read -r target pcmd sess wname; do
        [[ "$sess" == "$current_session" ]] && continue
        emit_pane_actions "$target" "$pcmd@$wname"
    done

    # ========== [5] Current session - other windows ==========
    tmux list-windows -F '#{session_name}:#{window_index}|#{window_name}|#{window_active}' 2>/dev/null | while IFS='|' read -r target wname active; do
        [[ "$target" == "$current_window" ]] && continue
        fmt "[W] select-window -t $target" "$wname"
        fmt "[W] kill-window -t $target" "$wname"
        fmt "[W] respawn-window -t $target" "$wname"
        fmt "[W] rename-window -t $target *" "$wname input new name"
        fmt "[W] swap-window -s $target -t *" "$wname select target"
    done

    # ========== [6] Current session - panes in other windows ==========
    tmux list-panes -s -F '#{session_name}:#{window_index}.#{pane_index}|#{pane_current_command}|#{window_index}|#{window_name}' 2>/dev/null | while IFS='|' read -r target pcmd widx wname; do
        [[ "$widx" == "$cur_widx" ]] && continue
        emit_pane_actions "$target" "$pcmd@$wname"
    done

    # ========== [7] Current window - other panes ==========
    tmux list-panes -F '#{session_name}:#{window_index}.#{pane_index}|#{pane_current_command}|#{pane_active}|#{window_name}' 2>/dev/null | while IFS='|' read -r target pcmd active wname; do
        [[ "$target" == "$current_pane" ]] && continue
        emit_pane_actions "$target" "$pcmd@$wname"
    done

    # ========== [8] Current session ==========
    local cur_ses_info="${cur_ses_wins} win~"
    fmt "[S] kill-session -t $current_session" "$cur_ses_info"
    fmt "[S] detach-client -s $current_session" "$cur_ses_info"
    fmt "[S] rename-session -t $current_session *" "$cur_ses_info input new name"

    # ========== [9] Current window ==========
    local cur_win_info="${cur_win_name}~"
    fmt "[W] kill-window -t $current_window" "$cur_win_info"
    fmt "[W] respawn-window -t $current_window" "$cur_win_info"
    fmt "[W] rename-window -t $current_window *" "$cur_win_info input new name"
    fmt "[W] swap-window -s $current_window -t *" "$cur_win_info select target"

    # ========== [10] Current pane (bottom, closest) ==========
    local cur_pane_info="${cur_pane_cmd}@${cur_win_name}~"
    fmt "[P] resize-pane -Z -t $current_pane" "$cur_pane_info zoom"
    fmt "[P] kill-pane -t $current_pane" "$cur_pane_info"
    fmt "[P] break-pane -t $current_pane" "$cur_pane_info"
    fmt "[P] swap-pane -s $current_pane -t *" "$cur_pane_info select target"
    fmt "[P] respawn-pane -t $current_pane" "$cur_pane_info"
    fmt "[P] clear-history -t $current_pane" "$cur_pane_info"

    # ========== [11] No-target commands (most accessible) ==========
    fmt "[S] new-session *" "input name"
    fmt "[W] new-window" ""
    fmt "[W] split-window -h" "horizontal"
    fmt "[W] split-window -v" "vertical"
    fmt "[W] link-window -s *" "select source window"
    fmt "[W] move-window -s *" "select source window"
    fmt "[W] rotate-window" ""
    fmt "[W] next-layout" ""
    fmt "[W] last-window" ""
    fmt "[P] select-layout *" "select layout"
    fmt "[P] resize-pane *" "select direction & size"
    fmt "[P] last-pane" ""
    fmt "[P] copy-mode" ""
}

# Create preview script
preview_script=$(cat << 'PREVIEW_SCRIPT'
#!/usr/bin/env bash
line="$1"
# Extract target from -t or -s flag
target=$(echo "$line" | grep -oE '(-t|-s) [^ ]+' | awk '{print $2}')
if [[ -n "$target" ]]; then
    if [[ "$target" == *"."* ]]; then
        # Pane target (session:window.pane)
        tmux capture-pane -ep -t "$target" 2>/dev/null
    elif [[ "$target" == *":"* ]]; then
        # Window target (session:window)
        tmux capture-pane -ep -t "$target" 2>/dev/null
    else
        # Session target
        tmux capture-pane -ep -t "$target:" 2>/dev/null
    fi
else
    # No target, show current pane or command info
    cmd=$(echo "$line" | sed 's/^\[[^]]*\] //' | sed 's/  .*//')
    echo "Command: $cmd"
fi
PREVIEW_SCRIPT
)

preview_file=$(mktemp "/tmp/tmux-fzf-unified-preview-XXXXXX.sh")
echo "$preview_script" > "$preview_file"
chmod +x "$preview_file"

# Set header
FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS --header='Tmux Command Palette  [S]ession [W]indow [P]ane [G]lobal'"

# Determine preview options
if [[ "$TMUX_FZF_PREVIEW" != "0" ]]; then
    preview_opts="--preview='$preview_file {}'"
else
    preview_opts=""
fi

# Run fzf and get selection
# --tac: reverse order so last output (current/no-target) appears at top (easiest to select)
# --no-sort: preserve our proximity-based ordering
selected=$(generate_candidates | eval "$TMUX_FZF_BIN $TMUX_FZF_OPTIONS --tac --no-sort $preview_opts")

# Cleanup
rm -f "$preview_file"

# Exit if nothing selected
[[ -z "$selected" ]] && exit 0

# Parse selection: [type] tmux-command [args]  description
cmd=$(echo "$selected" | sed 's/^\[[^]]*\] //' | sed 's/  .*//' | sed 's/ \*$//' | sed 's/ \* / /')
tmux_cmd=$(echo "$cmd" | awk '{print $1}')

# Extract target from -t flag (destination) and -s flag (source) if present
target=$(echo "$cmd" | grep -oE '\-t [^ ]+' | awk '{print $2}')
source=$(echo "$cmd" | grep -oE '\-s [^ ]+' | awk '{print $2}')

# Dispatch: most commands run directly, some need interactive scripts
case "$tmux_cmd" in
    # === Session commands ===
    switch-client|kill-session|detach-client)
        tmux $cmd
        ;;
    rename-session)
        "$CURRENT_DIR/session.sh" rename "$target"
        ;;
    new-session)
        "$CURRENT_DIR/session.sh" new
        ;;

    # === Window commands ===
    select-window)
        # Switch to session first, then window
        session=$(echo "$target" | sed 's/:.*//')
        tmux switch-client -t "$session"
        tmux select-window -t "$target"
        ;;
    kill-window)
        tmux unlink-window -k -t "$target"
        ;;
    respawn-window)
        tmux respawn-window -k -t "$target"
        ;;
    rename-window)
        "$CURRENT_DIR/window.sh" rename "$target"
        ;;
    swap-window)
        # -s source -t target; source is pre-selected, target needs selection
        "$CURRENT_DIR/window.sh" swap "$source"
        ;;
    link-window)
        "$CURRENT_DIR/window.sh" link
        ;;
    move-window)
        "$CURRENT_DIR/window.sh" move
        ;;
    new-window|split-window|rotate-window|next-layout|last-window)
        tmux $cmd
        ;;

    # === Pane commands ===
    select-pane)
        session=$(echo "$target" | sed -E 's/:.*//g')
        window=$(echo "$target" | sed -E 's/\..*//g')
        tmux switch-client -t "$session"
        tmux select-window -t "$window"
        tmux select-pane -t "$target"
        ;;
    kill-pane|clear-history)
        tmux $tmux_cmd -t "$target"
        ;;
    resize-pane)
        if echo "$cmd" | grep -q '\-Z'; then
            # zoom toggle
            tmux resize-pane -Z -t "$target"
        else
            # interactive resize
            "$CURRENT_DIR/pane.sh" resize
        fi
        ;;
    respawn-pane)
        tmux respawn-pane -k -t "$target"
        ;;
    break-pane)
        "$CURRENT_DIR/pane.sh" break "$target"
        ;;
    swap-pane)
        # -s source -t target; source is pre-selected, target needs selection
        "$CURRENT_DIR/pane.sh" swap "$source"
        ;;
    join-pane)
        # -s source; move source pane to current window
        "$CURRENT_DIR/pane.sh" join "$source"
        ;;
    select-layout)
        "$CURRENT_DIR/pane.sh" layout
        ;;
    last-pane|copy-mode)
        tmux $tmux_cmd
        ;;

    # === Global commands ===
    display-panes|clock-mode)
        tmux $tmux_cmd
        ;;
esac
