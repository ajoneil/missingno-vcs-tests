; dpc-probes — three DPC behaviours that live only on real silicon.
;
; The DPC ("Display Processor Chip", Pitfall II) is a 24-pin custom NMOS part with
; no clock pin and no R/W line: every function is decoded from the address alone.
; That physical fact implies documented edges no game exercises and no
; implementation models. This ROM asserts them as specified — untested on
; hardware, and only original silicon can settle them (a flashcart
; reimplementation cannot).
;
; The three probes:
;
;   $1800-$187F register mirror. The 24-pin chip does not decode A11, so the
;   register file answers again at $1800-$187F (a mirror is a second address range
;   that reaches the same registers). A read of $F808 (the A11 mirror of the DF0
;   data window $F008) should return DF0's display byte and decrement DF0. A model
;   that treats $F808 as plain program ROM returns the file byte there; this ROM
;   plants a distinct sentinel ($DB) at that offset so the failure byte names
;   itself.
;
;   No-R/W-line decode (register direction is A6 alone). With no
;   R/W strobe, a CPU write to the read window $F008 (A6=0) still fires the
;   read-side decoders, so on silicon the fetcher decrements. (The store also
;   drives the bus against the cart — bus contention — but the only observable
;   asserted here is the pointer state afterwards, never the store's data.) A model
;   whose write handler covers $1040-$107F only ignores a write to $1008, so the
;   pointer does not move.
;
;   Write-window read side effect (same A6 decode). A read of the
;   write window $F048 fires the write-side decoders while nothing drives the bus
;   (open bus — a floating bus with no defined value), so on silicon an undefined
;   floating byte is latched into DF0's Bottom register. The patent gives no
;   deterministic value and implementations split: some latch the driven bus byte
;   into Bottom, others leave Bottom unchanged. All agree the write-window read
;   moves no fetcher pointer, and that is all cell $04 asserts; the Bottom
;   behaviour is untested on hardware.
;
; The fetcher mechanism is explained in dpc-fetch.
;
;   CODE $01 = plumbing: a plain masked-window read (DF0) did not return the
;              expected display byte
;        $02 = $1800 mirror: $F808 did not return DF0 display data (silicon-implied)
;        $03 = no-R/W decode: a write to $F008 did not decrement DF0 (silicon)
;        $04 = write-window read ($F048) moved DF0's fetcher pointer (the
;              Bottom-latch side effect is not asserted — see above)
;
; Self-test: verdict in RESULT ($80); region-independent.
; mapper: DPC

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

HOTSPOT0 = $FFF8
HOTSPOT1 = $FFF9

; Music and draw-line are never enabled and $F000-$F003 is never read, so only
; the probed edges can move a reading.
DATA     = $F008             ; read DFx data, unmasked; decrements the pointer
MASKED   = $F010             ; read DFx data AND flag; also decrements
TOP      = $F040             ; write DFx Top   (start count; clears the flag)
BOTTOM   = $F048             ; write DFx Bottom (end count)
CLOW     = $F050             ; write DFx counter low
CHIGH    = $F058             ; write DFx counter high
MIRROR   = $F808             ; A11 mirror of DATA+0 ($F008): DF0 data on silicon

SENTINEL = $DB               ; planted at file $0808 so the mirror failure names itself

V1       = $90
V2       = $91

ENTRY    = $F080

        MAC ENTRYSTUB
        bit HOTSPOT0
        jmp Main
        ENDM

; ---------------------------------------------------------------- bank 0 (home)
        SEG BANK0
        ORG $0000
        RORG $F000
        ds 128                 ; DPC register window: no code/vectors
        ENTRYSTUB              ; ENTRY ($F080)
Main:
        CLEAN_START
        TEST_BEGIN

        ; A self-test stops at its first failing cell, so the cells run $01, $04,
        ; $02, $03: the two every model agrees on ($01 plumbing, $04 write-window
        ; read) come first, then the two silicon-only probes ($02 mirror, $03
        ; no-R/W decode). A model lacking the mirror therefore stops at $02 and
        ; never reaches $03, which stands for hardware and for any future model
        ; that adds the mirror but not the R/W-less decode.

        ; --- cell 01: a plain masked-window read behaves normally.
        ; DF0 Top = counter-low so the flag is set on the first read; Bottom out
        ; of the way. The read returns f($0C8) = $C4. Proves the ROM's plumbing
        ; before the silicon probes.
        lda #$C8
        sta TOP+0           ; Top = $C8 (clears flag)
        lda #$00
        sta BOTTOM+0        ; Bottom = $00 (out of the way)
        lda #$C8
        sta CLOW+0
        lda #$00
        sta CHIGH+0         ; DF0 c = $0C8, low == Top
        lda MASKED+0        ; masked: flag set (low==Top) -> f($0C8)=$C4; ptr -> $C7
        sta V1
        ASSERT_EQ V1, $C4, $01

        ; --- cell 04: a read of the write window does not move DF0's fetcher
        ; pointer. Position DF0 at $155, read $F008 (f($155)=$40, pointer -> $154),
        ; read the write window $F048 (its value is undefined and is not asserted),
        ; then read $F008 again: the read returns f($154)=$41, so the write-window
        ; read decremented nothing. Whether that read also latches a bus byte into
        ; DF0's Bottom is the split the header describes; Bottom is not asserted here.
        lda #$55
        sta CLOW+0
        lda #$01
        sta CHIGH+0         ; DF0 c = $155
        lda DATA+0          ; f($155)=$40, DF0 ptr -> $154
        sta V1
        lda BOTTOM+0        ; read the write window $F048 (value undefined -> not
                            ; asserted; does not move the pointer)
        lda DATA+0          ; f($154)=$41 (pointer untouched by $F048)
        sta V2
        ASSERT_EQ V1, $40, $04   ; first read primes the pointer
        ASSERT_EQ V2, $41, $04   ; write-window read did not decrement DF0

        ; --- cell 02 (silicon probe): the $1800-$187F register mirror.
        lda #$55
        sta CLOW+0
        lda #$01
        sta CHIGH+0         ; DF0 c = $155
        lda MIRROR          ; $F808 = A11 mirror of $F008. Silicon: DF0 data
                            ; f($155)=$40 (and decrement). A model that decodes
                            ; A11 as program ROM: file byte $0808 = sentinel $DB.
        sta V1
        ASSERT_EQ V1, $40, $02   ; silicon-implied side; the mirror-absent case observes $DB

        ; --- cell 03 (silicon probe): no-R/W-line decode. A write to the read
        ; window $F008 fires the read decoders -> DF0 decrements on silicon.
        lda #$55
        sta CLOW+0
        lda #$01
        sta CHIGH+0         ; DF0 c = $155
        lda DATA+0          ; read: f($155)=$40, DF0 ptr -> $154 (agreed; primes)
        sta V1
        sta DATA+0          ; write the read window (data irrelevant). Silicon: the
                            ; read decoders fire -> DF0 ptr $154 -> $153. A model
                            ; that ignores the store leaves ptr at $154.
        lda DATA+0          ; read: silicon f($153)=$46; ignored-store case f($154)=$41
        sta V2
        ASSERT_EQ V2, $46, $03   ; silicon side; the ignored-store case observes f($154)=$41

        PASS_TEST

        include "frame.asm"
        include "result_screen.asm"

        ; The DF0 data-window mirror sentinel, at file offset $0808 (CPU $F808),
        ; in the zero-filled gap above the code. A model that lacks the A11 mirror
        ; returns this byte for the cell-02 read, so the observed byte is diagnostic.
        ORG $0808
        RORG $F808
        .byte SENTINEL

        ORG $0FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY

; ---------------------------------------------------------------- bank 1 (data)
        SEG BANK1
        ORG $1000
        RORG $F000
        ds 128
        ENTRYSTUB
        ORG $1FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY

; ------------------------------------------------- 2K display ROM + 256B pad
; File offset o carries f($7FF - o) so a fetcher at counter c returns f(c); the
; 2K block + 256B pad set the 10496-byte DPC size. Laid out as in dpc-fetch.
        SEG DISPLAY
        ORG $2000
DPCDATA:
        REPEAT 2048
            .byte ((($7FF - (. - DPCDATA)) ^ (($7FF - (. - DPCDATA)) >> 4)) & $FF)
        REPEND
        ORG $2800
        ds 256, $00
