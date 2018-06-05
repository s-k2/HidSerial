## General Flags
PROJECT = HidSerial
MCU = attiny44a
TARGET = bin/HidSerial.elf
CC = avr-gcc

## Options common to compile, link and assembly rules
COMMON = -mmcu=$(MCU) 

## Compile options common for all C compilation units.
CFLAGS = $(COMMON)
#CFLAGS += -Wall -gdwarf-2 -std=gnu99 -DF_CPU=16000000UL -Os -funsigned-char -funsigned-bitfields -fpack-struct -fshort-enums
CFLAGS += -MD -MP -MT bin/$(*F).o -MF bin/dep/$(@F).d 
CFLAGS += -Wall -Os
CFLAGS += -DF_CPU=16000000

## Assembly specific flags
ASMFLAGS = $(COMMON)
ASMFLAGS += $(CFLAGS)
#ASMFLAGS += -x assembler-with-cpp -Wa,-gdwarf2

## Linker flags
LDFLAGS = $(COMMON)
LDFLAGS += 

## Intel Hex file production flags
HEX_FLASH_FLAGS = -R .eeprom -R .fuse -R .lock -R .signature

HEX_EEPROM_FLAGS = -j .eeprom
HEX_EEPROM_FLAGS += --set-section-flags=.eeprom="alloc,load"
HEX_EEPROM_FLAGS += --change-section-lma .eeprom=0 --no-change-warnings

## Objects that must be built in order to link
OBJECTS = bin/main.o bin/serialasm.o bin/usbdrvasm.o

## Objects explicitly added by the user
LINKONLYOBJECTS = 
INCLUDES =  -Isrc/usbdrv

## Build
all: $(TARGET) bin/HidSerial.hex bin/HidSerial.eep bin/HidSerial.lss

bin/main.o: src/main.c
	$(CC) $(INCLUDES) $(CFLAGS) -c -o $@ $<

bin/usbdrvasm.o: src/usbdrv/usbdrvasm.S
	$(CC) $(INCLUDES) $(ASMFLAGS) -c -o $@ $<

bin/serialasm.o: src/serialasm.S
	$(CC) $(INCLUDES) $(ASMFLAGS) -c -o $@ $<

##Link
$(TARGET): $(OBJECTS)
	 $(CC) $(LDFLAGS) $(OBJECTS) $(LINKONLYOBJECTS) $(LIBDIRS) $(LIBS) -o $(TARGET)

bin/%.hex: $(TARGET)
	avr-objcopy -O ihex $(HEX_FLASH_FLAGS)  $< $@

bin/%.eep: $(TARGET)
	-avr-objcopy $(HEX_EEPROM_FLAGS) -O ihex $< $@ || exit 0

bin/%.lss: $(TARGET)
	avr-objdump -h -S $< > $@

## Clean target
.PHONY: clean
clean:
	-rm -rf $(OBJECTS) bin/HidSerial.elf bin/dep/* bin/HidSerial.hex bin/HidSerial.eep bin/HidSerial.lss bin/HidSerial.map


## Other dependencies
-include $(shell mkdir bin/dep) $(wildcard bin/dep/*)
