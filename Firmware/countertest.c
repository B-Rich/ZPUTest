#include "minisoc_hardware.h"

#define COUNTER *(volatile unsigned int *)(0xFFFFFF80)
#define SWITCHES *(volatile unsigned int *)(0xFFFFFF84)

void putserial(char *msg)
{
	while(*msg)
	{
		while(!(HW_PER(PER_UART)&(1<<PER_UART_TXREADY)))
			;
		HW_PER(PER_UART)=*msg++;
	}
}

int main(int argc,char *argv)
{
	int c=0;
	long p=0;
	HW_PER(PER_UART_CLKDIV)=1000000/1152;
	putserial("Hello world!\n");
	while(1)
	{
		int d=-65535;
		while(d++)
			HW_PER(PER_HEX)=d;
		HW_VGA(FRAMEBUFFERPTR)=p;
		p+=1280;
	}
	return(0);
}

