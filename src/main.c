#include <avr/io.h>
#include <avr/interrupt.h>
#include <util/delay.h>

#include "usbdrv.c"
#include "serial.c"

// USB report descriptor
PROGMEM const char usbHidReportDescriptor[29] = {    
    0x06, 0x00, 0xff,              // USAGE_PAGE (Generic Desktop)
    0x09, 0x01,                    // USAGE (Vendor Usage 1)
    0xa1, 0x01,                    // COLLECTION (Application)
    0x15, 0x00,                    //   LOGICAL_MINIMUM (0)
    0x26, 0xff, 0x00,              //   LOGICAL_MAXIMUM (255)
    0x75, 0x08,                    //   REPORT_SIZE (8)
    0x95, 0x08,                    //   REPORT_COUNT (8)
    0x09, 0x00,                    //   USAGE (Undefined)
	0xB1, 0x00,	                   //   INPUT
    0x75, 0x08,                    //   REPORT_SIZE (8)
    0x95, 0x08,                    //   REPORT_COUNT (8)
    0x09, 0x00,                    //   USAGE (Undefined)
    0x91, 0x00,                    //   OUTPUT
    0xc0                           // END_COLLECTION
};

#define INVALID_BUFFER_INDEX 0xFF

#define FROM_UART_SIZE 0x20 // may never exceed 0x80
#define FROM_UART_WRAP_MASK (FROM_UART_SIZE - 1) // used to wrap to zero at maximum
volatile uchar fromUart[FROM_UART_SIZE]; // input buffer

volatile uchar fromUartNextToUsb = INVALID_BUFFER_INDEX; // where is the next valid byte that can be send to USB?
volatile uchar fromUartNextFree = 0; // where is the next free byte in the input buffer

#define TO_UART_SIZE 0x10 // may never exceed 0x80
#define TO_UART_WRAP_MASK (TO_UART_SIZE - 1) // used to wrap to zero at maximum
volatile uchar toUart[TO_UART_SIZE];

volatile uchar toUartNextSend = INVALID_BUFFER_INDEX; // where is the next valid byte that can be send to USB?
volatile uchar toUartNextFree = 0; // where is the next free byte in the output buffer

// The host sends a read-report to get new data from the UART and to get
// the number of free bytes in the output-buffer (query-data report)
uchar usbFunctionRead(uchar *data, uchar len)
{
    // this variable is the index in the usb-data array
    register uchar written = 1;
    
    // as long as data is available, write it - but at least 7 bytes
    while(fromUartNextToUsb != INVALID_BUFFER_INDEX && written < 8) {
        data[written] = fromUart[fromUartNextToUsb];
        
        register uchar newFromUartNextToUsb = 
			(fromUartNextToUsb + 1) & FROM_UART_WRAP_MASK;
        
        if(newFromUartNextToUsb == fromUartNextFree) {
            fromUartNextToUsb = INVALID_BUFFER_INDEX;
			written++;
            break;
        }
        fromUartNextToUsb = newFromUartNextToUsb;
        
        written++;
	}
	
	// calculate the number of free bytes in the output-buffer
	register uchar toUartFree;
	if(toUartNextSend == INVALID_BUFFER_INDEX) {
		toUartFree = TO_UART_SIZE;
	} else {
		if(toUartNextSend > toUartNextFree)
			toUartFree = toUartNextSend - toUartNextFree - 1;
		else
			toUartFree = toUartNextSend + TO_UART_SIZE - toUartNextFree - 1;
	}

	data[0] = (written - 1) | (toUartFree << 3);

    return(len);
}

// The write report is received by the host if it wants to send data to the
// UART (send-data report)
uchar   usbFunctionWrite(uchar *data, uchar len)
{
	register uchar i = len;
	register uchar newToUartNextFree = toUartNextFree;

	for(i = data[0]; i > 0; i--) {

		if(newToUartNextFree == toUartNextSend) {
			PORTA |= 0x10;
			break;
		}
		++data;
		toUart[newToUartNextFree] = *data;
		newToUartNextFree = (newToUartNextFree + 1) & TO_UART_WRAP_MASK;
	}
	if(toUartNextSend == INVALID_BUFFER_INDEX)
		toUartNextSend = toUartNextFree;
	toUartNextFree = newToUartNextFree;
	
    return 1; /* return 1 if this was the last chunk */
} 

USB_PUBLIC uchar usbFunctionSetup(uchar data[8])
{    
    usbRequest_t    *rq = (void *)data;
    if((rq->bmRequestType & USBRQ_TYPE_MASK) == USBRQ_TYPE_CLASS){    /* HID class request */
        if(rq->bRequest == USBRQ_HID_GET_REPORT){  /* wValue: ReportType (highbyte), ReportID (lowbyte) */
            /* since we have only one report type, we can ignore the report-ID */

            return USB_NO_MSG;  /* use usbFunctionRead() to obtain data */
        } else if(rq->bRequest == USBRQ_HID_SET_REPORT){
            /* since we have only one report type, we can ignore the report-ID */
            return USB_NO_MSG;  /* use usbFunctionWrite() to receive data from host */
        }
    }
    return(0);
}

inline void sendToUartIfPossible(void)
{
	if(SEND_BUSY() || toUartNextSend == INVALID_BUFFER_INDEX)
		return;

	sendByte(toUart[toUartNextSend]);
	register uchar newToUartNextSend = (toUartNextSend + 1) & TO_UART_WRAP_MASK;
	if(newToUartNextSend == toUartNextFree)
		toUartNextSend = INVALID_BUFFER_INDEX;
	else
		toUartNextSend = newToUartNextSend;
}

void main(void)
{
	// enable the error led
	DDRA = (1 << PA4);
	
	// it takes 75 seconds until the other chip has startet and is sending the
	// training-signals
    _delay_ms(75);
	
	// get the length of a bit
	trainBitTime();
	
    sei(); // enable interrupts

    usbInit();

	recvInit();
	sendInit();

    // disconnect, wait 500ms and connect again to have same id
    usbDeviceDisconnect();
    _delay_ms(500);
    usbDeviceConnect();

    while(1) {
        usbPoll();
		sendToUartIfPossible();
    }
}
