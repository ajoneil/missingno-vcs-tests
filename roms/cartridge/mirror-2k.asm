; mirror-2k — a 2K cartridge shows its image twice in the 4K window, because
; address line A11 is left unwired.
;
; The cart answers whenever address line A12 is high: a 4K window the CPU sees at
; $F000-$FFFF. A 4K cart wires all twelve address lines A0-A11 and fills the
; window once. A 2K cart holds half as much, so it wires only A0-A10 and leaves
; A11 unconnected: it cannot tell A11=0 from A11=1 and answers to both. The one
; 2K image therefore appears twice (a mirror):
;
;   $F000-$F7FF  image, seen with A11=0
;   $F800-$FFFF  the same image, seen with A11=1
;
; The two halves are not copies; they are the same chip seen through two
; addresses. The byte at 2K-offset n is reachable as $F000+n and as $F800+n
; alike, for instruction fetches as much as data reads — code runs the same from
; either half. The 6507 fetches its reset vector from $FFFC/$FFFD (in the upper
; half); the address stored there ($F800, the program start) works only because
; the lower half mirrors it.
;
;   CODE $01 = signature read through the lower image ($F700) was wrong
;        $02 = signature read through the upper image ($FF00) was wrong
;        $03 = subroutine did not run when entered via its upper address
;        $04 = subroutine did not run when entered via its lower alias ($800 below)
;        $05 = reset vector low byte ($FFFC) did not hold the entry point
;        $06 = reset vector high byte ($FFFD) did not hold the entry point
;
; Self-test: verdict in RESULT ($80); region-independent.
; mapper: 2K

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

SIGVAL      = $A5              ; the one signature byte, read through both images
ALIAS_MAGIC = $C3             ; AliasProbe stamps this to prove it ran

        IFCONST BROKEN_NO_MIRROR
WRONGSIG    = $5A             ; the un-mirrored lower image carries a DIFFERENT byte
MAINOFF     = $0800          ; ...so the program moves up to make room for that image
        ELSE
MAINOFF     = $0000
        ENDIF

MARK   = $90                  ; AliasProbe's landing pad
LOSIG  = $91                  ; signature read via the lower image
HISIG  = $92                  ; signature read via the upper image
UPMARK = $93                  ; MARK after entering AliasProbe by its upper address
LOMARK = $94                  ; MARK after entering AliasProbe by its lower alias
VECLO  = $95                  ; reset vector low byte, read back from $FFFC
VECHI  = $96                  ; reset vector high byte, read back from $FFFD

        IFCONST BROKEN_NO_MIRROR
; A NON-mirrored 4K image: an independent lower half whose signature differs, so
; a genuinely-mirrored read cannot see it. This half exists only in the broken
; build — a real 2K cart has no separate lower image at all, just the one that
; answers to both A11 states. Building this proves CODE $01 fires when A11 is
; (wrongly) decoded.
        SEG LOWERHALF
        ORG $0000
        RORG $F000
        .byte 0                 ; anchor the file's low end (CPU $F000)
        ORG $0700
        RORG $F700
        .byte WRONGSIG          ; CPU $F700: the lower image's own, different signature
        ENDIF

; ---------------------------------------------------------------- the 2K image
        SEG MAIN
        ORG MAINOFF
        RORG $F800
ENTRY:
Main:
        CLEAN_START
        TEST_BEGIN

        ; --- the images must agree before we trust code fetched through either.
        ; (Check this first: on a non-mirrored image the lower-alias call below
        ; would fetch a different — possibly unrunnable — routine.)
        lda $F700               ; signature through the lower image
        sta LOSIG
        lda $FF00               ; ...and through the upper image (same 2K byte)
        sta HISIG
        ASSERT_EQ LOSIG,  SIGVAL,      $01
        ASSERT_EQ HISIG,  SIGVAL,      $02

        lda #0                  ; enter AliasProbe by its natural (upper) address
        sta MARK
        jsr AliasProbe
        lda MARK
        sta UPMARK

        lda #0                  ; ...and by its lower alias, $800 below — same bytes,
        sta MARK                ;   fetched through the lower image
        jsr AliasProbe-$800
        lda MARK
        sta LOMARK
        ASSERT_EQ UPMARK, ALIAS_MAGIC, $03
        ASSERT_EQ LOMARK, ALIAS_MAGIC, $04

        lda $FFFC               ; the reset vector the 6507 booted through
        sta VECLO
        lda $FFFD
        sta VECHI
        ASSERT_EQ VECLO,  <ENTRY,      $05
        ASSERT_EQ VECHI,  >ENTRY,      $06

        PASS_TEST

        include "frame.asm"
        include "result_screen.asm"

; A subroutine reached two ways: `jsr AliasProbe` fetches its bytes through the
; upper image, `jsr AliasProbe-$800` through the lower. Both must run it.
AliasProbe:
        lda #ALIAS_MAGIC
        sta MARK
        rts

        ORG MAINOFF+$0700
        RORG $FF00
        .byte SIGVAL            ; the lone signature byte, at 2K-offset $700

        ORG MAINOFF+$07FC
        RORG $FFFC
        .word ENTRY             ; reset -> the program start (upper image)
        .word ENTRY             ; IRQ/BRK
