
#include <mach/machine/asm.h>

#include <i386/i386/i386asm.h>

#include <i386/i386/proc_reg.h>

	/*
	 * This section will be put first into .text.  See also	i386/ldscript.
	 */
	.code32
	.section .text.start,"ax"
	
	/* We should never be entered this way.  */
	.globl	start,_start
start:
_start:
	jmp	boot_entry

	/* MultiBoot header - see multiboot.h.  */
#define	MULTIBOOT_MAGIC		0x1BADB002
#ifdef __ELF__
#define MULTIBOOT_FLAGS		0x00000003
#else  /* __ELF__ */
#define MULTIBOOT_FLAGS		0x00010003
#endif /* __ELF__ */
	P2ALIGN(2)
boot_hdr:
	.long	MULTIBOOT_MAGIC
	.long	MULTIBOOT_FLAGS
		/*
		 * The next item here is the checksum.
		 * XX this works OK until we need at least the 30th bit.
		 */
	.long	- (MULTIBOOT_MAGIC+MULTIBOOT_FLAGS)
#ifndef __ELF__	/* a.out kludge */
	.long	boot_hdr	/* header_addr */
	.long	_start		/* load_addr */
	.long	_edata		/* load_end_addr */
	.long	_end		/* bss_end_addr */
	.long	boot_entry	/* entry */
#endif /* __ELF__ */

boot_entry:
	/* use segmentation to offset ourself. */
	lgdt	boot_gdt_descr - KERNELBASE
	ljmp	$8,$0f
0:
	movw	$0,%ax
	movw	%ax,%ds
	movw	%ax,%es
	movw	%ax,%fs
	movw	%ax,%gs
	movw	$16,%ax
	movw	%ax,%ds
	movw	%ax,%es
	movw	%ax,%ss

	/* Switch to our own interrupt stack.  */
	movl	$_intstack+INTSTACK_SIZE,%esp

	/* Reset EFLAGS to a known state.  */
	pushl	$0
	popf

/*
 *  Prepare for entering in 64 bit mode
 */

#define P4_BASE					0x1000
#define P3_BASE					0x2000
#define P2_BASE					0x3000
#define BOOT_INIT_PGT_SIZE		0x2000
#define NUM_P3_ENTRIES 4
#define NUM_P2_ENTRIES (NUM_P3_ENTRIES * 512)

 	/* TODO add checks to ensure that processor support 64 bits */
	
	/* Disable paging */
	mov		%cr0, %eax
	xorl	$CR0_PG, %eax
	mov		%eax, %cr0

	/* Enable PAE mode */
	mov		%cr4, %eax
	orl		$CR4_PAE, %eax
	mov		%eax, %cr4

	/* Initialize page tables to 0 */
	mov		%cr3, %edi
	xor		%eax, %eax
	movl	$(BOOT_INIT_PGT_SIZE / 4), %ecx
	rep		stosl

	/* Build Level 4 */
	movl	$P4_BASE, %edi
	movl	$(P3_BASE | 0x3) , 0(%edi)

	/* Build Level 3 */
	movl	$P3_BASE, %edi
	movl	$(P2_BASE | 0x3), %eax
	movl	NUM_P3_ENTRIES, %ecx
1:	movl	%eax, 0(%edi)
	addl	%edx, 4(%edi)
	addl	$0x00001000, %eax
	addl	$8, %edi
	decl	%ecx
	jnz		1b

	/* Build Level 2 */
	movl	$P2_BASE, %edi
	movl	$0x00000183, %eax
	movl	$2048, %ecx
1:	movl	%eax, 0(%edi)
	addl	%edx, 4(%edi)
	addl	$0x00200000, %eax
	addl	$8, %edi
	decl	%ecx
	jnz		1b

	/* Enable the boot page tables */
	movl	$P4_BASE, %eax
	mov		%eax, %cr3

	/* Enable Long mode in EFER (Extended Feature Enable Register) */
	movl	$EFER_MSR, %ecx
	rdmsr
	btsl	$EFER_LME, %eax
	wrmsr

	/* Enter paged protected Mode, activating Long Mode */
	mov		%cr0, %eax /* Enable Paging and Protected mode */
	orl		$(CR0_PG | CR0_PE), %eax /* Enable Paging and Protected mode */
	mov		%eax, %cr0

	/* Starting kernel */
	jmp _start64

	.code64

	.global _start64
	.type _start64, @function
_start64:

	/* Clear uninitialized data.  */
	/*lea     _edata,%edi
	lea     _end,%ecx
	subl    %edi,%ecx
	xorl    %eax,%eax
	rep
	stosb*/

	/* Push the boot_info pointer to be the second argument.  */
	movq	%rbx,%r8

	/* Fix ifunc entries */
	movq    $__rela_iplt_start,%rsi
	movq    $__rela_iplt_end,%rdi
iplt_cont:
	cmpq    %rdi,%rsi
	jae     iplt_done
	movq    (%rsi),%rbx	/* r_offset */
	movb    4(%rsi),%al	/* info */
	cmpb    $42,%al		/* IRELATIVE */
	jnz     iplt_next
	call    *(%ebx)		/* call ifunc */
	movq    %rax,(%rbx)	/* fixed address */
iplt_next:
	addq    $8,%rsi
	jmp     iplt_cont
iplt_done:

	movq	%r8,%rdi
	/* Jump into C code.  */
	call	EXT(c_boot_entry)

	.comm	_intstack,INTSTACK_SIZE

.align 16
	.word 0
boot_gdt_descr:
	.word 3*8+7
	.long boot_gdt - KERNELBASE
.align 16
boot_gdt:
	/* 0 */
	.quad 0
	/* boot CS = 8 */
	.word 0xffff
	.word (-KERNELBASE) & 0xffff
	.byte ((-KERNELBASE) >> 16) & 0xff
	.byte 0x9a
	.byte 0xcf
	.byte ((-KERNELBASE) >> 24) & 0xff
	/* boot DS = 8 */
	.word 0xffff
	.word (-KERNELBASE) & 0xffff
	.byte ((-KERNELBASE) >> 16) & 0xff
	.byte 0x92
	.byte 0xcf
	.byte ((-KERNELBASE) >> 24) & 0xff

