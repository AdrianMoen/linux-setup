#!/bin/bash

which gnome-control-center

gnome_status=$?

# Change this later to a script that takes input for which settings we want to open -> ie. bluetooth, display, etc.
if [ "$gnome_status" -eq 0 ]; then
    alias settings='gnome-control-center'
fi
