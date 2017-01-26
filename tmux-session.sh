#!/bin/bash

set -eu

ARG=$1

function setup-session() {
    tmux split-window
    tmux split-window
    tmux select-layout even-horizontal
    # Handle tmux configs where windows aren't 0-indexed
    local tmux_first_window="$(tmux display-message -p '#I')"
    tmux select-window -t pg:"$tmux_first_window"
    sleep 3 # pause for a bit or the keys below may be sent before the user shell inits
    # Handle tmux configs where panes aren't 0-indexed
    local tmux_pane_1="$(tmux list-panes | cut -d':' -f1 | sed -n '1p')"
    local tmux_pane_2="$(tmux list-panes | cut -d':' -f1 | sed -n '2p')"
    local tmux_pane_3="$(tmux list-panes | cut -d':' -f1 | sed -n '3p')"
    tmux send-keys -t pg:"${tmux_first_window}"."${tmux_pane_1}" C-m "vagrant up pg01 && vagrant ssh pg01" C-m
    tmux send-keys -t pg:"${tmux_first_window}"."${tmux_pane_2}" C-m "vagrant up pg02 && vagrant ssh pg02" C-m
    tmux send-keys -t pg:"${tmux_first_window}"."${tmux_pane_3}" C-m "vagrant up pg03 && vagrant ssh pg03" C-m
    tmux attach-session -t pg
}

if [ "$ARG" == "start" ]; then
    (tmux new-session -d -s pg -n cluster && setup-session) || tmux attach -t pg
elif [ "$ARG" == "stop" ]; then
    echo "Stopping all VMs..."
    vagrant halt
    tmux kill-session -t pg
elif [ "$ARG" == "destroy" ]; then
    echo "Destroying all VMs..."
    vagrant destroy -f
    tmux kill-session -t pg
fi
