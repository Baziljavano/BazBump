#!/bin/sh

# Download luvit if it's not already there
if [ ! -f ./luvit ]; then
  curl -L https://github.com/luvit/luvit/releases/download/2.18.1/luvit -o luvit
  chmod +x luvit
fi

# Start your bot
./luvit bot.lua
