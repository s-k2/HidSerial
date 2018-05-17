#include <avr/io.h>

#ifndef SERIAL_H
#define SERIAL_H

#if F_CPU != 16000000
#error "You must manually adjust the prescalers for clock-rates != 16 MHz"
#endif

#define SEND_PRESCALER ((1 << CS01) | 1 << (CS00)) // prescaler: clk / 64
#define RECV_PRESCALER ((1 << CS11) | 1 << (CS10)) // prescaler: clk / 64

// the registers will be initialized in initRecv()
#define SERIAL_BIT_TIME_REG GPIOR0
// this is the time starting from the falling edge of the start-bit until we
// can read the first data-bit
#define SERIAL_UNTIL_LSB_REG GPIOR1

#define SERIAL_DEFAULT_BIT_TIME 104 // = 2400 baud with 16Mhz clock and 64 prescaler
#define SERIAL_DEFAULT_UNTIL_LSB (SERIAL_DEFAULT_BIT_TIME * 15 / 10)

// the interrupt is active until the stop bit is sent completly
#define SEND_BUSY() (TIMSK0)
#define RECV_BUSY() (TIMSK1 & (1 << OCIE1A))

#ifndef __ASSEMBLER__
extern volatile unsigned char uartBits; // the next bits that have to be send
extern volatile unsigned char recvBits;
#else
.extern uartBits
.extern recvBits
#endif /* __ASSEMBLER__ */

#endif /* SERIAL_H */