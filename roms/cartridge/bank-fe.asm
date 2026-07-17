; bank-fe — the Activision FE board (Robot Tank, Decathlon, 8K) is the subtlest
; bankswitcher: it has no hotspot (an address the board watches for a bank
; switch) and watches no opcodes. A plain address comparator wired to one data
; line picks the bank.
;
; The 6507 gives the cartridge a 4K window at $F000-$FFFF (any access with A12
; high). The FE board's two 4K banks both answer that same window — there is no
; second address range. What picks between them is a latch (a one-bit store),
; driven by the address $01FE and data line D5:
;
;   1. Any bus access — read or write — to address $01FE arms the latch. The
;      cart decodes all 13 address lines, so $01FE arms even though A12 is low
;      there and the access is really to RIOT RAM (the stack page $0180-$01FF
;      mirrors the 128-byte RAM, so $01FE is zero-page $FE).
;   2. On the very next bus cycle the latch captures data-bus bit D5: D5=1
;      selects bank 0, D5=0 selects bank 1. That is the whole design.
;
; Every high address byte $F0-$FF has D5=1 and every $D0-$DF has D5=0 — hence
; the nicknames "$Fxxx bank" and "$Dxxx bank", though both live at $F000-$FFFF.
;
; Why JSR and RTS switch banks, with the stack at the top of RAM (SP=$FF):
;   - JSR pushes the return high byte to $01FF, then the low byte to $01FE (this
;     push arms the latch); its sixth cycle fetches the target's high address
;     byte, and that byte's D5 picks the bank.
;   - RTS pulls the low byte from $01FE (arm) then the high byte from $01FF; the
;     return address's high byte D5 picks the bank.
; So a JSR into the "$Dxxx" alias pages in bank 1, and the matching RTS (return
; address a "$Fxxx" byte) pages bank 0 back. The cart has no idea JSR or RTS ran.
;
; Two models of this board have circulated: an opcode-watching cart and the
; address-comparator latch. This test pins the comparator model, and proves:
;   - Any $01FE access arms — no JSR needed. `lda $01FE` then an instruction
;     whose opcode byte has D5=0 (e.g. $85 = sta zp) pages in bank 1. The
;     opcode-watching model would not switch here.
;   - Whether a JSR/RTS switches depends on the stack depth, not the opcode.
;     With SP far from $FE the pushes and pulls never touch $01FE, so JSR/RTS
;     cause no switch at all. The opcode-watching model would still switch.
;
;   CODE $01 = JSR $D000 (SP=$FF) did not page in bank 1 (target read != $D1)
;        $02 = the RTS did not page bank 0 back in (signature after return != $F0)
;        $03 = data-read arm (`lda $01FE` then a D5=0 store opcode) did not switch
;        $04 = arm + a D5=1 opcode (`lda $01FE` then `nop`) did not return home
;        $05 = deep-stack JSR (SP well clear of $FE) wrongly switched banks
;        $06 = deep-stack RTS wrongly switched banks
;        $07 = latch-delay probe: arm then `sta $25` (opcode $85 has D5=0 at the
;              +1 cycle, operand $25 has D5=1 at +2) did not page bank 1 — the
;              latch selects on the +1-cycle opcode byte
;
; How much of the armed byte the latch reads is contested: D5 alone, or
; a literal three-bit D7-D5 latch, which also requires D7=D6=1 and would
; leave an armed %100 byte selecting neither bank. The two readings diverge only
; for an armed byte outside $Cx-$Fx, which cell $03 builds deliberately. Cells
; $03/$07 assert the D5-only reading and the +1-cycle latch timing. Untested on
; hardware.
;
; Self-test: verdict in RESULT ($80); region-independent.
; mapper: FE

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

SIG     = $FC00                 ; per-bank signature (mid-window, clear of $01FE)
ENTRY   = $F006                 ; reset target: shared entry stub (offset $006)
PROBE   = $F014                 ; shared switch-probe routine (offset $014)

; scratch/result cells (harness owns $80-$89; tests use $90+)
SIG_T   = $90                   ; signature captured inside the JSR-$D000 target
SIG03   = $91                   ; signature after the data-read-arm switch
SIG04   = $92                   ; signature after arm + D5=1 opcode (back home)
SIG07   = $93                   ; signature after the latch-delay probe
J01     = $94                   ; SIG_T copied out after the SP=$FF JSR
R02     = $95                   ; signature after the RTS returned home
D05     = $96                   ; SIG_T copied out after the deep-stack JSR
R06     = $97                   ; signature after the deep-stack RTS
SAVESP  = $98                   ; saved stack pointer around the deep-stack cell

; The shared stub — emitted byte-identical into both banks so execution can
; cross a bank switch and keep fetching valid code at the same address.
;   offset $000  TARGET  : the JSR-$D000 target. Reads whichever bank's signature
;                          into SIG_T, then RTS. In bank 1 it reads $D1, in bank 0
;                          (deep-stack / off-board) it reads $F0.
;   offset $006  ENTRY   : reset entry (both banks' vectors point here). Power-on
;                          bank is undefined, so it arms-for-bank-0 twice (some
;                          models ignore the first $01FE access after reset) then
;                          jumps to Main in bank 0.
;   offset $014  PROBE   : the non-JSR switch cells $03/$04/$07. Each `lda $01FE`
;                          arms; the following opcode's D5 selects the bank, and
;                          execution continues in that bank through the identical
;                          stub to read its signature.
        MAC STUB
        ; --- TARGET ($F000, reached as $D000) ---
        lda SIG                 ; AD 00 FC : this bank's signature
        sta SIG_T               ; 85 90
        rts                     ; 60       : return high byte is $Fx -> pages bank 0
        ; --- ENTRY ($F006) ---
        lda $01FE               ; AD FE 01 : arm (first; some models ignore it)
        nop                     ; EA       : D5=1 -> bank 0
        lda $01FE               ; AD FE 01 : arm (honoured by every model)
        nop                     ; EA       : D5=1 -> bank 0
        bit $1FF8               ; 2C F8 1F : inert on FE (a plain window read, not
                                ;   $01FE). It exists only for an off-board run:
                                ;   $1FF8 is the F8 bank-0 hotspot, so a non-FE
                                ;   board still pages in bank 0, reaches Main, and
                                ;   fails cleanly at CODE $01 rather than derailing
                                ;   into bank-1 filler.
        jmp Main                ; 4C .. .. : run the test (Main lives in bank 0)
        ; --- PROBE ($F014) ---
        lda $01FE               ; arm
        sta $85                 ; 85 85 : opcode D5=0 (operand $85 D5=0 too) -> bank 1
        lda SIG                 ; now bank 1 -> $D1
        sta SIG03
        lda $01FE               ; arm
        nop                     ; EA : D5=1 -> bank 0
        lda SIG                 ; now bank 0 -> $F0
        sta SIG04
        lda $01FE               ; arm
        sta $25                 ; 85 25 : opcode $85 (D5=0) at +1, operand $25 (D5=1)
        lda SIG                 ;         at +2 -> the +1 latch model selects bank 1
        sta SIG07
        lda $01FE               ; arm
        nop                     ; EA : D5=1 -> force bank 0 before the RTS home
        rts
        ENDM

; ---------------------------------------------------------------- bank 0 (home)
        SEG BANK0
        ORG $0000
        RORG $F000
        STUB
Main:
        ; FE-safe start-up. The stock CLEAN_START clears RAM with a 256-byte push
        ; loop that sweeps the whole stack page $0100-$01FF; on this board its
        ; write to $01FE would arm the latch and the following `bne` opcode ($D0,
        ; D5=0) would page in bank 1 mid-loop and derail into bank-1 filler. So we
        ; clear RAM through zero-page stores, which never touch the $01xx page.
        sei
        cld
        ldx #$FF
        txs                     ; SP=$FF (transfer only; no bus access to $01FE)
        lda #0
        ldx #$80
.clr:   sta $00,x               ; 95 00 : clear RAM $80-$FF (zero page, not $01xx)
        inx
        bne .clr
        TEST_BEGIN

        ; --- cells $01/$02: JSR $D000 with SP=$FF switches to bank 1 and back ---
        jsr $D000               ; 20 00 D0 : arm + ADH $D0 (D5=0) -> bank 1; the
        dec $C5                 ; C6 C5    : target records SIG_T=$D1, RTS home.
                                ;   20 00 D0 C6 C5 is the FE detector fingerprint;
                                ;   dec of unused scratch $C5 is harmless.
        lda SIG_T               ; what the target saw inside bank 1
        sta J01
        lda SIG                 ; back home in bank 0
        sta R02

        ; --- cells $03/$04/$07: non-JSR arms (the switch does not need a JSR) ---
        jsr PROBE               ; 20 14 F0 : arms but ADH $F0 (D5=1) -> stays bank 0;
                                ;   PROBE performs the switches internally.

        ; --- cells $05/$06: with the stack far from $FE, JSR/RTS never touch
        ;     $01FE, so they cause no switch (the opcode-watching model would) ---
        tsx
        stx SAVESP
        ldx #$B8                ; a mid-RAM stack: pushes land at $01B8/$01B7, both
        txs                     ;   RAM-backed and clear of $01FE and the scratch
        jsr $D000               ;   cells. No $01FE access -> no arm -> no switch.
        lda SIG_T               ; the target ran in bank 0 -> $F0
        sta D05
        lda SIG                 ; still bank 0 after the RTS -> $F0
        sta R06
        ldx SAVESP
        txs                     ; restore SP=$FF

        ; --- assertions ---
        ASSERT_EQ J01,   $D1, $01       ; JSR paged bank 1
        ASSERT_EQ R02,   $F0, $02       ; RTS paged bank 0 back
        ASSERT_EQ SIG03, $D1, $03       ; data-read arm switched
        ASSERT_EQ SIG04, $F0, $04       ; arm + D5=1 opcode returned home
        ASSERT_EQ D05,   $F0, $05       ; deep-stack JSR did not switch
        ASSERT_EQ R06,   $F0, $06       ; deep-stack RTS did not switch
        ASSERT_EQ SIG07, $D1, $07       ; latch selects on the +1 opcode byte

        PASS_TEST

        include "frame.asm"
        include "result_screen.asm"

        ORG $0C00
        RORG $FC00
        .byte $F0                       ; bank 0 signature
        ORG $0FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY

; ---------------------------------------------------------------- bank 1 (data)
        SEG BANK1
        ORG $1000
        RORG $F000
        STUB                            ; identical stub; execution crosses into it
        ORG $1C00
        RORG $FC00
        .byte $D1                       ; bank 1 signature (differs)
        ORG $1FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY
