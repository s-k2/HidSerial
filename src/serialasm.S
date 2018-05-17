#include <avr/io.h>
#include <avr/interrupt.h>

#include "serial.h"

// shared with main.c
#define INVALID_BUFFER_INDEX 0xFF
#define FROM_UART_SIZE 0x20 // may never exceed 0x80
#define FROM_UART_WRAP_MASK (FROM_UART_SIZE - 1) // used to wrap to zero at maximum

.global TIM0_COMPA_vect
TIM0_COMPA_vect:
		;; prolgue: we use just one register and the status flag
		push r24
		in r24, _SFR_IO_ADDR(SREG)
		push r24
		;; [ 5 clocks ]

		;; if uartBits == 0 we set the pin for the stop-bit recently and wait
		;; until the full stop-bit is sent
		lds r24, uartBits

		cpi r24, 0
		brne prepareNextBit
		;; [ 5 + 5 = 10 clocks, if stop-bit was not sent ]
		;; [ 5 + 4 = 9 clocks, if stop-bit startet already ]

		;; If the stop-bit was recently sent, but not yet completed, we need
		;; some inidcator that prevents us from directly sending the next bit!
		;; Immediatelly after the stop-bit was sent, we only disable bit-setting.
		;; Then the output-compare happens again when the full stop-bit is sent.
		;; Only at this moment we deactivate the interrupt.
		;; Thus the interrupt-flag can be used as indicator when the port is
		;; ready to send the next byte.
		in r24, _SFR_IO_ADDR(TCCR0A) ; load the current value of TCCR0A
		cpi r24, (1 << WGM01)	; if the full stop-bit was sent, r24 would have
								; a value where bit-setting is unset
		brne deactivateBitSettingOnly
								; don't deactivate the interrupt if stop bit has
								; not been sent completly
		;; [ 5 + 4 + 4 = 13 clocks, if stop-bit started recently ]
		;; [ 5 + 4 + 3 = 12 clocks, if stop-bit was completly sent ]

		;; deactivate output-compare-match interrupt
		clr r24					; unset all interrupts of this timer...
		out _SFR_IO_ADDR(TIMSK0), r24 ; ...and out it to TIMSK0

		;; [ 5 + 4 + 3 + 2 = 15 clocks, if stop-bit was completly sent ]

		;; it does not hurt if we dactivate bit-setting a second time, when
		;; the interrupt was disabled... But it saves us 2 bytes of flash ;)

deactivateBitSettingOnly:	
		ldi r24, (1 << WGM01)	; unset all bit-setting-related flags
		out _SFR_IO_ADDR(TCCR0A), r24 ; and out it to the config-register

		rjmp sendBitEpilogue	; leave the interrupt handler
		;; [ 5 + 4 + 4 + 4 = 17 clocks, if stop-bit started recently ]
		;; [ 5 + 4 + 3 + 2 + 4 = 19 clocks, if stop-bit was completly sent ]

		
		;; if the stop-bit has not started yet, prepare the next bit...
prepareNextBit:
		clc			   			; clear the carry flag, else we would rotate
								; in a set bit, instead of an unset one
		ror r24					; shift uartBits right, carry-flag contains lsb
		sts uartBits, r24		; save the shiftet value to memory

		ldi r24, (1 << COM0A1) | (1 << WGM01)
								; load the value of the config byte that clears
								; the pin's value on next timeout

		brcc outConfigByte		; if we need to send a zero bit, we don't 
								; need to change r24 here...
		ori r24, (1 << COM0A0)	; ...else logical or with the set-pin-flag

outConfigByte:
		out _SFR_IO_ADDR(TCCR0A), r24 ; out the config byte
		;; [ 5 + 5 + 8 = 18 clocks, if stop was not sent, whatever bit was sent]

sendBitEpilogue:		
		;; restore the register and status flag
		pop r24
		out _SFR_IO_ADDR(SREG), r24
		pop r24
		reti
		;; [ 5 + 5 + 8 + 9 = 27 clocks, if stop-bit was not sent]
		;; [ 5 + 4 + 4 + 4 + 9 = 26 clocks, if stop-bit started recently ]
		;; [ 5 + 4 + 3 + 2 + 4 + 9 = 28 clocks, if stop-bit was completly sent ]
		
		
.global TIM1_CAPT_vect
TIM1_CAPT_vect:
		;; prologue: we need to save two registers and the status flag
		push r24
		in r24, _SFR_IO_ADDR(SREG)
		push r24
		push r25
		;; [ 7 clocks ]

		;; Calculate the time we have to wait for the first data-bit
		;; Take care that the the timer could have had an overflow since the
		;; pin-change happened
		in r25, _SFR_IO_ADDR(ICR1L)			; time when the start-bit was captured
		in r24, _SFR_IO_ADDR(TCNT1L)		; current time 
		
		sub r24, r25			; how many timer-clocks elapsed since then?
		brsh check_too_short	; if TCNT1L >= ICR1L do nothing...
		
		in r24, _SFR_IO_ADDR(SERIAL_UNTIL_LSB_REG)
		sub r24, r25
		in r25, _SFR_IO_ADDR(TCNT1L)
		add r24, r25
		
		;; [ 7 + 5 = 12 clocks (if current time didn't wrap around since ICP) ]
		;; [ 7 + 8 = 15 clocks (if current time wrapped around since ICP) ]

		;; and take care that there is more than one timer-clock until the
		;; compare-match (else no overflow-interrupt would be raised)
check_too_short:
		in r25, _SFR_IO_ADDR(SERIAL_UNTIL_LSB_REG)
		subi r25, 3				; subtract two from the value where we overflow
		cp r25, r24 			; compare the maximum of allowed ticks with the
								; number of ticks that have passed since the start-bit
		brsh set_timer			; if there are just 2 counter-clocks
		subi r24, 2				; wait 2 clocks longer
		
		;; [ 7 + 5 + 5 = 17 clocks (if current time didn't wrap around since ICP) ]
		;; [ 7 + 8 + 5 = 20 clocks (if current time wrapped around since ICP) ]
		
		;; r24 contains the new initial value of the timer which will lead to
		;; an overflow in the middle of the LSB
set_timer:
		out _SFR_IO_ADDR(TCNT1L), r24 	; set the new timer value
		;; [ 7 + 5 + 5 + 1 = 18 clocks (if current time didn't wrap around since ICP) ]
		;; [ 7 + 8 + 5 + 1= 21 clocks (if current time wrapped around since ICP) ]

		;; now enable the compare-match-interrupt A, but clear it's flag if it
		;; already happened
		ldi r24, 2				; both flags are on bit 1
		out _SFR_IO_ADDR(TIMSK1), r24			; enable the interrupt
		out _SFR_IO_ADDR(TIFR1), r24			; and clear it's flag
		;; [ 7 + 5 + 5 + 1 + 3 = 21 clocks (if current time didn't wrap around since ICP) ]
		;; [ 7 + 8 + 5 + 1 + 3 = 24 clocks (if current time wrapped around since ICP) ]

		;; set the recvBits to 0x80 to be able to detect the first and the last
		;; bit in each interrupt compare match
		ldi r24, 0x80
		sts recvBits, r24
		;; [ 7 + 5 + 5 + 1 + 3 + 3 = 24 clocks (if current time didn't wrap around since ICP) ]
		;; [ 7 + 8 + 5 + 1 + 3 + 3 = 27 clocks (if current time wrapped around since ICP) ]

		sei						; as we would exceed the 33 clocks-limit due to 
								; the epilogue we allow interrupts here to not
								; disturb the USB-things

		;; epilogue: restore the two registers and all flags
		pop r25
		pop r24
		out _SFR_IO_ADDR(SREG), r24
		pop r24
		reti
		;; [ 11 clocks epilogue ]
		
		
.global TIM1_COMPA_vect
TIM1_COMPA_vect:	
		;; prologue: we need to save two registers and the status flag
		push r24
		in r24, _SFR_IO_ADDR(SREG)
		push r24
		push r25
		;; [7 clocks]

		;; we read the pin's value (= data-bit) as soon as possible
		in r25, _SFR_IO_ADDR(ICP1_PIN)
		bst r25, ICP1_BIT				; store data in T-flag for later use
		;; [7 + 2 = 9 clocks]

		;; check if this is the first data-bit! If so, we need to adjust
		;; OCR1A for the next data bits...
		;; To do this check, we compare recvBits with 0x80! This value is only
		;; possible for the first data-bit. For all subsequent bits we receive
		;; it is different. And it will never be mistaken with an received
		;; byte with a value of 0x80, because recvBits never contains the full
		;; received byte!
		lds r24, recvBits
		cpi r24, 0x80		
		brne appendBit	; else append the bit and test if it's the last one
		;; [7 + 2 + 4 = 13 clocks, if first bit]
		;; [7 + 2 + 5 = 14 clocks, if not first bit]

		;; if we're reading the LSB we must update our overflow value as it's
		;; still the longer time for LSB instead of one bit's time
		in r25, _SFR_IO_ADDR(SERIAL_BIT_TIME_REG)
		out _SFR_IO_ADDR(OCR1AL), r25			
		;; [7 + 2 + 4 + 2 = 15 clocks, if first bit]

appendBit:		
		ror r24					; store lsb in carry-register, it doesn't matter
		                        ; what value will be stored in the msb of r24
		bld r24, 7				; read the value of the current data-bit stored
								; in the T-flag
		brcs last_bit			; if the lsb was not set, just append the new bit
		sts recvBits, r24
		;; [7 + 2 + 4 + 2 + 5 = 20 clocks, if first bit, but not last]
		;; [7 + 2 + 5 + 5 = 19 clocks, if neither first, nor last bit]
		;; [7 + 2 + 5 + 4 = 18 clocks, if not first, but last bit]	

recvBitEpilogue:
		;; restore the two registers and all flags
		pop r25
		pop r24
		out _SFR_IO_ADDR(SREG), r24
		pop r24
		reti
		;; [7 + 2 + 4 + 2 + 5 + 11 = 31 clocks, if first bit, but not last]
		;; [7 + 2 + 5 + 5 + 11 = 30 clocks, if neither first, nor last bit]
		
last_bit:		
		;; enable the input capture-interrupt again and clear it's flag
		ldi r25, 0x20				; both flags are on bit 5
		out _SFR_IO_ADDR(TIMSK1), r25
		out _SFR_IO_ADDR(TIFR1), r25	; and clear it's flag

		in r25, _SFR_IO_ADDR(SERIAL_UNTIL_LSB_REG)
		out _SFR_IO_ADDR(OCR1AL), r25			; write the new timeout to OCR1AL  

		sei						; enable interrupts again...
		;; [7 + 2 + 5 + 4 + 6 = 24 clocks, if not first, but last bit]
		
		push r30				; save additional registers
		push r31
		push r26
		
		;; if fromUartNextFree == fromUartNextToUsb there is no more space in
		;; the buffer... so we just indicate the error and return
		lds r25, fromUartNextFree
		lds r26, fromUartNextToUsb
		cp r25, r26
		brne saveByteToBuffer 	; continue if there is space in the buffer left
				
		sbi _SFR_IO_ADDR(PORTA), 4	; ... else show an error (set PORTA.4)

		rjmp recvStoreBitEpilogue	; and return

saveByteToBuffer:
		;; write the read byte: fromUart[fromUartNextFree] = receivedChar
		;; please note that the calculation of the address needs to take in
		;; account an overflow from bit 7 to bit 8!
		mov r30, r25
      	ldi r31, 0
      	subi r30, lo8(-(fromUart))
		sbci r31, hi8(-(fromUart))
    	st Z, r24				; saved the new byte

		;; indicate that new data is available, if fromUartNextToUsb was invalid
		cpi r26, INVALID_BUFFER_INDEX ; TODO: use CPSE here???
		brne moveFreeIndex
		sts fromUartNextToUsb, r25 ; fromUartNextToUsb = fromUartNextFree

		;; increment fromUartNextFree and wrap around if needed
moveFreeIndex:
		inc r25
		andi r25, FROM_UART_WRAP_MASK
		sts fromUartNextFree, r25

recvStoreBitEpilogue:
		pop r26
		pop r31
		pop r30

		rjmp recvBitEpilogue			; clean-up
		