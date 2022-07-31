#!/bin/bash

if [ "$OMD_UPDATE" = "" ]; then
    echo "script requires OMD_VERSION env variable"
    exit 1
fi
echo "updating to version $OMD_UPDATE..."

omd stop

# start update in tmux
if command -v tmux >/dev/null 2>&1; then
    session="omd_update"
    tmux new-session -d -s $session
    window=0
    tmux rename-window -t $session:$window 'omd_update'
    tmux send-keys -t $session:$window 'omd -V $OMD_UPDATE update' C-m

    # now wait till the omd update is finished and tail the output till then
    # end tmux on success
    bashpid=$(tmux list-panes -a -F "#{pane_pid} #{session_name}" | grep $session | awk '{ print $1 }')

    while kill -0 $bashpid; do
        tmux capture-pane -p -s $session
        sleep 5
    done

else
    omd -f -V $OMD_UPDATE update
fi

omd start