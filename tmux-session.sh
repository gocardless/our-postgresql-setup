#!/bin/bash

set -eu

ARG=$1

function setup-session() {
    tmux split-window
    tmux split-window
    tmux select-layout even-horizontal
    tmux select-window -t pg:0
    sleep 3 # pause for a bit or the keys below may be sent before the user shell inits
    tmux send-keys -t pg:0.0 C-m "vagrant up pg01 && vagrant ssh pg01" C-m
    tmux send-keys -t pg:0.1 C-m "vagrant up pg02 && vagrant ssh pg02" C-m
    tmux send-keys -t pg:0.2 C-m "vagrant up pg03 && vagrant ssh pg03" C-m
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
