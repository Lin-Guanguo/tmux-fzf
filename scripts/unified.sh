#!/usr/bin/env bash
# Unified Command Palette - flat search for all tmux commands
# Usage: bind-key P run-shell -b "path/to/unified.sh"

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/.envs"

# Get current context
current_session=$(tmux display-message -p '#{session_name}')
current_window=$(tmux display-message -p '#S:#I')
current_pane=$(tmux display-message -p '#S:#{window_index}.#{pane_index}')

generate_candidates() {
    # Sorting strategy: far items at top, close items at bottom (near fzf input)
    # Order: Global -> Other sessions -> Current session other windows -> Current window other panes -> Current -> No-target

    # ========== [1] Global commands (top, rarely used) ==========
    echo "[G] display-panes  # show pane numbers"
    echo "[G] clock-mode  # show clock"

    # ========== [2] Other sessions (far) ==========
    tmux list-sessions -F '#{session_name}|#{session_windows}|#{session_attached}' 2>/dev/null | while IFS='|' read -r name wins attached; do
        [[ "$name" == "$current_session" ]] && continue
        local mark=""
        [[ "$attached" == "1" ]] && mark="*"
        echo "[S] switch $name  # $mark ($wins win)"
        echo "[S] kill $name  # $mark"
        echo "[S] detach $name  # $mark"
        echo "[S] rename $name  # $mark -> input new name"
    done

    # ========== [3] Windows in other sessions ==========
    tmux list-windows -a -F '#{session_name}:#{window_index}|#{window_name}|#{session_name}' 2>/dev/null | while IFS='|' read -r target wname sess; do
        [[ "$sess" == "$current_session" ]] && continue
        echo "[W] switch $target  # $wname"
        echo "[W] kill $target  # $wname"
        echo "[W] respawn $target  # $wname restart"
        echo "[W] rename $target  # $wname -> input new name"
        echo "[W] swap $target  # $wname -> select another"
    done

    # ========== [4] Panes in other sessions ==========
    tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}|#{pane_current_command}|#{session_name}' 2>/dev/null | while IFS='|' read -r target pcmd sess; do
        [[ "$sess" == "$current_session" ]] && continue
        echo "[P] switch $target  # $pcmd"
        echo "[P] kill $target  # $pcmd"
        echo "[P] zoom $target  # $pcmd"
        echo "[P] break $target  # $pcmd -> new window"
        echo "[P] respawn $target  # $pcmd restart"
        echo "[P] clear-history $target  # $pcmd clear scrollback"
        echo "[P] swap $target  # $pcmd -> select another"
        echo "[P] join $target  # $pcmd -> move here"
    done

    # ========== [5] Current session - other windows ==========
    tmux list-windows -F '#{session_name}:#{window_index}|#{window_name}|#{window_active}' 2>/dev/null | while IFS='|' read -r target wname active; do
        [[ "$target" == "$current_window" ]] && continue
        echo "[W] switch $target  # $wname"
        echo "[W] kill $target  # $wname"
        echo "[W] respawn $target  # $wname restart"
        echo "[W] rename $target  # $wname -> input new name"
        echo "[W] swap $target  # $wname -> select another"
    done

    # ========== [6] Current session - panes in other windows ==========
    tmux list-panes -s -F '#{session_name}:#{window_index}.#{pane_index}|#{pane_current_command}|#{window_index}' 2>/dev/null | while IFS='|' read -r target pcmd widx; do
        local cur_widx=$(echo "$current_window" | sed 's/.*://')
        [[ "$widx" == "$cur_widx" ]] && continue
        echo "[P] switch $target  # $pcmd"
        echo "[P] kill $target  # $pcmd"
        echo "[P] zoom $target  # $pcmd"
        echo "[P] break $target  # $pcmd -> new window"
        echo "[P] respawn $target  # $pcmd restart"
        echo "[P] clear-history $target  # $pcmd clear scrollback"
        echo "[P] swap $target  # $pcmd -> select another"
        echo "[P] join $target  # $pcmd -> move here"
    done

    # ========== [7] Current window - other panes ==========
    tmux list-panes -F '#{session_name}:#{window_index}.#{pane_index}|#{pane_current_command}|#{pane_active}' 2>/dev/null | while IFS='|' read -r target pcmd active; do
        [[ "$target" == "$current_pane" ]] && continue
        local mark=""
        echo "[P] switch $target  # $pcmd"
        echo "[P] kill $target  # $pcmd"
        echo "[P] zoom $target  # $pcmd"
        echo "[P] break $target  # $pcmd -> new window"
        echo "[P] respawn $target  # $pcmd restart"
        echo "[P] clear-history $target  # $pcmd clear scrollback"
        echo "[P] swap $target  # $pcmd -> select another"
        echo "[P] join $target  # $pcmd -> move here"
    done

    # ========== [8] Current session operations ==========
    echo "[S] rename [current]  # -> input new name"
    echo "[S] kill $current_session  # current session"
    echo "[S] detach $current_session  # current session"

    # ========== [9] Current window operations ==========
    echo "[W] kill [current]"
    echo "[W] respawn [current]  # restart current window"
    echo "[W] rename [current]  # -> input new name"
    echo "[W] swap [current]  # -> select another"

    # ========== [10] Current pane operations (bottom, closest) ==========
    echo "[P] zoom [current]"
    echo "[P] kill [current]"
    echo "[P] break [current]  # -> new window"
    echo "[P] swap [current]  # -> select another"
    echo "[P] respawn [current]  # restart current pane"
    echo "[P] clear-history [current]  # clear scrollback"

    # ========== [11] No-target commands (most accessible) ==========
    echo "[S] new  # create new session"
    echo "[W] new  # create new window"
    echo "[W] split-h  # split horizontal"
    echo "[W] split-v  # split vertical"
    echo "[W] link  # -> select source window"
    echo "[W] move  # -> select source window"
    echo "[W] rotate  # rotate panes in current window"
    echo "[W] next-layout  # cycle through layouts"
    echo "[W] last-window  # switch to last window"
    echo "[P] layout  # -> select layout"
    echo "[P] resize  # -> select direction & size"
    echo "[P] last-pane  # switch to last pane"
    echo "[P] copy-mode  # enter copy mode"
}

# Create preview script
preview_script=$(cat << 'PREVIEW_SCRIPT'
#!/usr/bin/env bash
line="$1"
# Extract target (word after action)
target=$(echo "$line" | sed 's/^\[[^]]*\] [^ ]* //' | sed 's/  #.*//' | awk '{print $1}')
if [[ -n "$target" && "$target" != "#" ]]; then
    if [[ "$target" == "[current]" ]]; then
        tmux capture-pane -ep 2>/dev/null
    elif [[ "$target" == *"."* ]]; then
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
    echo "Command: $line"
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
selected=$(generate_candidates | eval "$TMUX_FZF_BIN $TMUX_FZF_OPTIONS $preview_opts")

# Cleanup
rm -f "$preview_file"

# Exit if nothing selected
[[ -z "$selected" ]] && exit 0

# Parse selection: [type] action target  # comment
type=$(echo "$selected" | grep -oE '^\[[^]]+\]')
rest=$(echo "$selected" | sed 's/^\[[^]]*\] //' | sed 's/  #.*//')
action=$(echo "$rest" | awk '{print $1}')
target=$(echo "$rest" | awk '{print $2}')

# Dispatch based on type and action
case "$type" in
    "[S]")
        case "$action" in
            switch)
                tmux switch-client -t "$target"
                ;;
            kill)
                tmux kill-session -t "$target"
                ;;
            detach)
                tmux detach -s "$target"
                ;;
            rename)
                # Call original script with action and target
                "$CURRENT_DIR/session.sh" rename "$target"
                ;;
            new)
                "$CURRENT_DIR/session.sh" new
                ;;
        esac
        ;;
    "[W]")
        case "$action" in
            switch)
                # Switch to session first, then window
                session=$(echo "$target" | sed 's/:.*//')
                tmux switch-client -t "$session"
                tmux select-window -t "$target"
                ;;
            kill)
                if [[ "$target" == "[current]" ]]; then
                    tmux kill-window
                else
                    tmux unlink-window -k -t "$target"
                fi
                ;;
            rename)
                "$CURRENT_DIR/window.sh" rename "$target"
                ;;
            swap)
                "$CURRENT_DIR/window.sh" swap "$target"
                ;;
            new)
                tmux new-window
                ;;
            split-h)
                tmux split-window -h
                ;;
            split-v)
                tmux split-window -v
                ;;
            link)
                "$CURRENT_DIR/window.sh" link
                ;;
            move)
                "$CURRENT_DIR/window.sh" move
                ;;
            respawn)
                if [[ "$target" == "[current]" ]]; then
                    tmux respawn-window -k
                else
                    tmux respawn-window -k -t "$target"
                fi
                ;;
            rotate)
                tmux rotate-window
                ;;
            next-layout)
                tmux next-layout
                ;;
            last-window)
                tmux last-window
                ;;
        esac
        ;;
    "[P]")
        case "$action" in
            switch)
                session=$(echo "$target" | sed -E 's/:.*//g')
                window=$(echo "$target" | sed -E 's/\..*//g')
                tmux switch-client -t "$session"
                tmux select-window -t "$window"
                tmux select-pane -t "$target"
                ;;
            kill)
                if [[ "$target" == "[current]" ]]; then
                    tmux kill-pane
                else
                    tmux kill-pane -t "$target"
                fi
                ;;
            zoom)
                if [[ "$target" == "[current]" ]]; then
                    tmux resize-pane -Z
                else
                    tmux resize-pane -Z -t "$target"
                fi
                ;;
            break)
                "$CURRENT_DIR/pane.sh" break "$target"
                ;;
            swap)
                "$CURRENT_DIR/pane.sh" swap "$target"
                ;;
            join)
                "$CURRENT_DIR/pane.sh" join "$target"
                ;;
            layout)
                "$CURRENT_DIR/pane.sh" layout
                ;;
            resize)
                "$CURRENT_DIR/pane.sh" resize
                ;;
            respawn)
                if [[ "$target" == "[current]" ]]; then
                    tmux respawn-pane -k
                else
                    tmux respawn-pane -k -t "$target"
                fi
                ;;
            clear-history)
                if [[ "$target" == "[current]" ]]; then
                    tmux clear-history
                else
                    tmux clear-history -t "$target"
                fi
                ;;
            last-pane)
                tmux last-pane
                ;;
            copy-mode)
                tmux copy-mode
                ;;
        esac
        ;;
    "[G]")
        case "$action" in
            display-panes)
                tmux display-panes
                ;;
            clock-mode)
                tmux clock-mode
                ;;
        esac
        ;;
esac
