#!/bin/bash

sdas8051  -o ./intex.asm && sdld -i ./intex.rel && packihx ./intex.ihx > intex.hex && ./sn8flash --port /dev/ttyUSB0 --reset-less write --file ./intex.hex