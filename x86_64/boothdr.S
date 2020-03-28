
#include <mach/machine/asm.h>

#include <i386/i386/i386asm.h>

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

/*
 *  Prepare for entering in 64 bit mode
 */
#define MSR_EFER			0xc0000080 /* extended feature register */
#define _EFER_LME			8  /* Long mode enable */
	
	/* Disable paging */
	movl	%cr0, %eax
	orl		$CR0_PG, %eax
	movl	%eax, %cr0

	/* Enable PAE mode */
	movl	%cr4, %eax
	orl		$CR4_PAE, %eax
	movl	%eax, %cr4

	/* Enable the boot page tables */
	/* TODO FIXME use a real address */
	movl	$10000, %eax
	movl	%eax, %cr3

	/* Enable Long mode in EFER (Extended Feature Enable Register) */
	movl	$MSR_EFER, %ecx
	rdmsr
	btsl	$_EFER_LME, %eax
	wrmsr

	/* Enter paged protected Mode, activating Long Mode */
	movl	%cr0, %eax /* Enable Paging and Protected mode */
	orl 	$(CR0_PG | CR0_PE), %eax /* Enable Paging and Protected mode */
	movl	%eax, %cr0

	/* Starting kernel */
	jmp _start64

	.code64

	.global _start64
	.type _start64, @function
_start64:
	/* Setup data segments. */
	/*xorl	%eax, %eax
	movl	%eax, %ds
	movl	%eax, %es
	movl	%eax, %ss
	movl	%eax, %fs
	movl	%eax, %gs*/

	/* use segmentation to offset ourself. */
	lgdt	boot_gdt_descr - KERNELBASE
	jmp		0
0:

	/* Switch to our own interrupt stack.  */
	movq	$_intstack+INTSTACK_SIZE,%rax
	andq	$(~15),%rax
	movq	%rax,%rsp

	/* Reset EFLAGS to a known state.  */
	pushq	$0
	popf

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

