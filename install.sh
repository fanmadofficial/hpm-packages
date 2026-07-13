#!/bin/bash

echo "Installing hpm"

mkdir -p ~/.mypm/{bin,packages,db,cache}


curl -sSL "https://raw.githubusercontent.com/fanmadofficial/hpm-packages/main/hpm.sh" -o ~/.hpm/bin/hpm
chmod +x ~/.hpm/bin/hpm


if ! grep -q ".hpm/bin" ~/.bashrc; then
    echo 'export PATH="$HOME/.hpm/bin:$PATH"' >> ~/.bashrc
fi

echo "Done! Run 'source ~/.bashrc' and 'hpm help'"
