
/* Memory Definitions */

MEMORY
{
  BOOT (rx) : ORIGIN = 0x04000000, LENGTH = 0x00000008 /* Boot section contains just the initial jump */
  TRAP (rx) : ORIGIN = 0x04000008, LENGTH = 0x00000000 /* Dummy region to ensure we don't have any Initialized writable data */
  CODE (rx) : ORIGIN = 0x04000008, LENGTH = 0x00000ff8 /* Up to the end of the first 4K */
  SDRAM (rw)  : ORIGIN = 0x007ff000, LENGTH = 0x00001000 /* 4k at top end of DE1's SDRAM */
  STACK (rw) : ORIGIN = 0x04000000, LENGTH = 0x00000400 /* 1024 bytes */
}


/* Section Definitions */

SECTIONS
{
  /* first section is .fixed_vectors which is used for startup code */
  . = 0x0000000;
  .fixed_vectors :
  {
    *(.fixed_vectors)
  }>BOOT

  /* Remaining code sections */
  .text :
  {
	. = ALIGN(4);
    *(.text)                   /* remaining code */
  } >CODE

  /* .rodata section which is used for read-only data (constants) */
  .rodata :
  {
    *(.rodata*)
  . = ALIGN(4);
  } >CODE
  _romend = . ;

  /* .data section which is used for initialized data.
     Since we don't want any writable data within the ROM
     itself, we put this stuff in a "trap" section. */
  .data :
  {
    _data = . ;
    *(.data)
    SORT(CONSTRUCTORS)
    . = ALIGN(4);
  } >TRAP

  /* .bss section which is used for uninitialized data */
  .bss :
  {
    __bss_start = . ;
    __bss_start__ = . ;
    *(.bss)
    *(COMMON)
    . = ALIGN(4);
  } >SDRAM
  __bss_end__ = . ;
}
