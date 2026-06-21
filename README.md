# intex28698
This is alternative firmware for Intex pool lamp model 28698. This firmware has added new features compared to the original firmware. 

* When powered off and on it starts at previous lighting mode. It stores currenct lamp modes in the mcu flash memory.
* Light sensor can be added to the pin8 (P2.0). If no light sensor is present then pin 8 need to be connected to VDD (PIN 16)

To flash it first you need to check if your outer lamp has SN8F5702 mcu (16 pins package). I'm not sure if all lamps have the same hardware, so flash at your own risk. For flashing you need to download flashing tool from this repository https://github.com/silicagel777/SN8Flash, also connection schematics and tutorial are available there.

For example, the command for flashing

`./sn8flash --port /dev/ttyUSB0 --reset-less write --file ./intex.hex`

If you have reset less connection version then it requires severel tries to start flashing, usually up to 5 times.

If you want to modify assembler file and compile hex file then you need also the sda8051 assembler which is part of SDCC package and packihx tool. To build and create hex file
`
sdas8051  -o ./intex.asm
sdld -i ./intex.rel
packihx ./intex.ihx > intex.hex
`
To make the lamp turn automatically on at night, you need to connect a light sensor to the pin 8 (P2.0). You can use one of the ready modules or solder it yourself. The only requirement is the output should be high in the dark and low at light. The module and light element must be placed inside the lamp and water tightness must be observed.
