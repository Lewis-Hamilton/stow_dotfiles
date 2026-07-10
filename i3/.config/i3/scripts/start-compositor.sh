#!/usr/bin/env bash

if command -v nvidia-smi &> /dev/null && nvidia-smi &> /dev/null; then
    echo "NVIDIA GPU detected. Skipping picom for better gaming performance."
    
else
    echo "Non-NVIDIA system detected. Launching picom..."
    picom -b
fi