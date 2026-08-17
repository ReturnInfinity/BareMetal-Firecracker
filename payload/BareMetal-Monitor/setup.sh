#!/usr/bin/env bash
set -eu

./clean.sh

mkdir src/api
cd src/api
if [ -x "$(command -v curl)" ]; then
	curl -fsS -o libBareMetal.asm https://raw.githubusercontent.com/ReturnInfinity/BareMetal/master/api/libBareMetal.asm
else
	wget -q https://raw.githubusercontent.com/ReturnInfinity/BareMetal/master/api/libBareMetal.asm
fi
cd ../..

mkdir bin

./build.sh
