/* chimera memisl.ld, but with the host (CVA6) stack at the top of the memory island.  The boot ROM
   leaves sp at 0x4800fff8, inside this ELF's data once it exceeds 64 KiB (crt0 keeps the boot-ROM
   stack unless __stack_pointer$ is nonzero). */
INCLUDE memisl.ld
__stack_pointer$ = __stack_start - 64;
