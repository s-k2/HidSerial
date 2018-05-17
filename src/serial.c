#include <avr/io.h>

#include "serial.h"

volatile unsigned char uartBits = 0; // the next bits that have to be send

// DEBUG
#define SERIAL_BIT_TIME 100
inline void serial_send_1()
{
	PORTA |= (1 << PA6);
	_delay_us(SERIAL_BIT_TIME);
}

inline void serial_send_0()
{
	PORTA &= ~(1 << PA6);
	_delay_us(SERIAL_BIT_TIME);
}

void serial_send(char ch)
{
	serial_send_1(); // stop-bit
	serial_send_0(); // start-bit

	register char i;
	for(i = 0; i < 8; i++) {
		if(ch & 1)
			serial_send_1();
		else
			serial_send_0();
		ch >>= 1;
	}

	serial_send_1(); // stop-bit
}
// DEBUG

inline void trainBitTime(void)
{
	uchar overflowCounter = 0;

DDRA |= (1 << PA6);
PORTA |= (1 << PA6);
	
	// set the default values
	SERIAL_BIT_TIME_REG = SERIAL_DEFAULT_BIT_TIME;
	SERIAL_UNTIL_LSB_REG = SERIAL_DEFAULT_UNTIL_LSB;
	
	TCCR0B = SEND_PRESCALER;
	
	// set our TX-pin as input with pull-up
	OC0A_DDR &= ~(1 << OC0A_BIT);
	OC0A_PORT |= (1 << OC0A_BIT);
	
	// if the value is already high, wait until it gets low again
	while(OC0A_PIN & (1 << OC0A_BIT)) {
		if(TIFR0 & (1 << TOV0)) { // if an overflow happend...
			TIFR0 |= (1 << TOV0); // ...clear the overflow flag
			if(++overflowCounter == 10) // and leave the training if it was to long
				return;
		}
	}
	
	// wait for it to become high
	while(!(OC0A_PIN & (1 << OC0A_BIT))) {
		if(TIFR0 & (1 << TOV0)) { // if an overflow happend...
			TIFR0 |= (1 << TOV0); // ...clear the overflow flag
			if(++overflowCounter == 30) // and leave the training if it was to long
				return;
		}
	}
	
	// reset timer to determine the length of this bit
	TCNT0 = 0;
	
	// and wait until the pin becomes low again
	while(OC0A_PIN & (1 << OC0A_BIT)) {
		if(TIFR0 & (1 << TOV0)) { // if an overflow happend...
			TIFR0 |= (1 << TOV0); // ...clear the overflow flag and leave (one bit may never lead to an overflow)
			return;
		}
	}
	
	// the timer value is now the bit-time
	register uchar bitTime = TCNT0;
	// TODO: check if it is valid???
	
	SERIAL_BIT_TIME_REG = bitTime;
	SERIAL_UNTIL_LSB_REG = bitTime + (bitTime / 2);
	

	serial_send(SERIAL_BIT_TIME_REG);
}

inline void sendInit(void)
{
	// save the time of one bit as output compare value
	OCR0A = SERIAL_BIT_TIME_REG;

	// enable the timer
	TCCR0B = SEND_PRESCALER;

	// setup output pin
	OC0A_DDR |= (1 << OC0A_BIT);
	OC0A_PORT |= (1 << OC0A_BIT);
}

inline void sendByte(unsigned char value)
{
	// save the next bits and append the stop bit as last bit
	uartBits = (value >> 1) | 0x80;

	// send start bit, we must unset OC0A pin's value first
	TCCR0A = (1 << COM0A1) | (1 << WGM01);
	TCCR0B = SEND_PRESCALER | (1 << FOC0A);

	// reset timer
	TCNT0 = 0;
	// enable output-compare interrupt A, but clear it's flag
	TIFR0 = (1 << OCF0A);
	TIMSK0 = (1 << OCIE0A);

	// put first-data bit in COM0A0
	// The timer will change the pin's state for us just in time
	// regardless of any interrupts running at this moment
	if(value & 1) // set the pin on timeout...
		TCCR0A = (1 << COM0A1) | (1 << COM0A0) | (1 << WGM01);
	else // ...or clear it
		TCCR0A = (1 << COM0A1) | (1 << WGM01);
}

/* TIMER0_COMPA_vect is written in assembly... it prepares the next data-bit 
   (or stop-bit) and disables itself if a full byte (including stop-bit) has 
   been sent)! 
   Remember that it does not yet change the pin's value, because it just sets
   the pin-change mode (COM0A0) for the next timeout! */

/* --------------------------------------------------------------------------- */

volatile unsigned char recvBits;

/* TIMER1_CAPT_vect is written in assembler...
   it gets activated on the start-bit, calculates when the first data-bit can
   be read (using the value of ICR1), deactivates itself and activates the
   output-compare-match */
   
/* TIMER1_COMPA_vect is also written in assembly...
   it reads the port's value every RECV_BIT_TIME ticks and appends it to the 
   current byte, until a full byte has read... if its done, it saves the byte
   into the buffer an re-enables TIMER1_CAPT_vect */
   
inline void recvInit(void)
{
	// make the rx-pin an input with enabled pull-up resistor
	ICP1_DDR &= ~(1 << ICP1_BIT);
	ICP1_PORT |= (1 << ICP1_BIT);

	TCCR1A = 0;
	// activate input noise canceler (input capture is set on falling edge),
	// clear on compare and use the right prescaler
	TCCR1B = (1 << ICNC1) | (1 << WGM12) | RECV_PRESCALER;

	// enable input change interrupt but make sure it is not fired
	TIFR1 = (1 << ICF1);
	TIMSK1 = (1 << ICIE1);

	// reset the timer
	TCNT1 = 0;

	// the pin-change interrupt expects OCR1A to be RECV_UNTIL_LSB
	OCR1A = SERIAL_UNTIL_LSB_REG;
}
