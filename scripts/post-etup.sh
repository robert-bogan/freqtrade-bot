#!/bin/bash

# Ensure correct permissions and ownership
CONFIG_PATH="/freqtrade/user_data/config.json"

if [ -f "$CONFIG_PATH" ]; then
  chmod 600 "$CONFIG_PATH"
  chown 0:0 "$CONFIG_PATH"  # UID 0 = root
  echo "✔ Set permissions on config.json"
else
  echo "✘ config.json not found at $CONFIG_PATH"
fi
