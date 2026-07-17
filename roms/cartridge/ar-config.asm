; ar-config — Starpath Supercharger (AR) control register: bank layout and write enable.
;
; The Supercharger is a RAM cartridge: 6K of RAM (three 2K banks) plus a 2K BIOS
; ROM. It has no write line at the cartridge edge, so the CPU's read/write signal
; never reaches the cart. Everything the cart does is driven by reads of
; addresses in the $F000-$FFFF window; reads do all the work.
;
; Two things are read-driven. The control register comes first:
;   - a read of any address in $F000-$F0FF saves that read's low byte as a
;     pending value;
;   - a later read of $FFF8 (a hotspot: an address the board watches) copies the
;     pending value into the control register.
; So `LDA $F0nn ; BIT $FFF8` sets the control register to nn. Its bits:
;       bit 7-5   write-pulse delay (unused here)
;       bit 4-2   bank configuration (which RAM bank shows in each 2K window)
;       bit 1     RAM write enable (1 = writes armed, see ar-write)
;       bit 0     ROM power (0 = BIOS on and readable, 1 = ROM off)
;
; The 4K window splits into a low window ($F000-$F7FF) and a high window
; ($F800-$FFFF). The low window is always a RAM bank; only the high window can
; show the BIOS. ROM never appears in the low window.
;
; The eight bank layouts, indexed by control bits 4-2:
;       bits 4-2   $F000-$F7FF   $F800-$FFFF
;       000        RAM bank 2    ROM (BIOS)
;       001        RAM bank 0    ROM (BIOS)
;       010        RAM bank 2    RAM bank 0
;       011        RAM bank 0    RAM bank 2
;       100        RAM bank 2    ROM (BIOS)
;       101        RAM bank 1    ROM (BIOS)
;       110        RAM bank 2    RAM bank 1
;       111        RAM bank 1    RAM bank 2
;   (Bank numbers are the page-table index 0-2; some documentation labels them
;   1-3. Banks 0 and 1 are never both mapped.)
;
;   CODE $01 = the loaded program is not running from RAM (baked sentinel wrong)
;        $02 = a per-bank marker written via the +5 write protocol (see ar-write)
;              did not read back from its bank
;        $03 = config walk: the marker seen in a window did not match the bank
;              the table maps into that window
;        $04 = with write enable off, the write sequence changed RAM anyway
;        $05 = the low window did not show a RAM marker (ROM leaked into the low
;              window, or a BIOS-high config exposed a marker up top)
;
; Self-test: verdict in RESULT ($80); region-independent.
; mapper: AR

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

MARKER0 = $3A                   ; distinct per-bank marker bytes (written at runtime)
MARKER1 = $5C
MARKER2 = $71

MARK    = $F700                 ; per-bank marker cell in the low window
UMARK   = $FF00                 ; the same cell seen through the high window
HOTSPOT = $FFF8                 ; control-register commit ($1FF8 mirror)

WPTR    = $8E                   ; zero-page pointer for the +5 indirect write ($8E/$8F)
LOOPI   = $95                   ; config-walk loop index
TMPEXP  = $96                   ; stashed "expected" byte across a register shuffle

; SET_CFG value: latch a control byte then commit it. The latch is a read of
; $F000+value (its low byte becomes the pending value); BIT $FFF8 commits.
        MAC SET_CFG
        ldy #{1}
        lda $F000,y             ; read $F0{value} -> latch {value}
        bit HOTSPOT             ; read $FFF8 -> commit to the control register
        ENDM

; The image is loaded byte-identically into all three RAM banks, so a config
; switch that pages a different bank into the low window leaves execution running
; on an identical copy. All code and the result screen sit at $F100 or higher, so
; the only $F0xx reads are the deliberate control-register loads.
        SEG BANK
        ORG   $0000
        RORG  $F000
        ds    256, $FF          ; $F000-$F0FF: control-register latch page (never read/run)

Start:                          ; $F100 — BIOS jumps here once the tape is loaded
        CLEAN_START
        TEST_BEGIN

; --- cell $01: we are executing the loaded image out of Supercharger RAM ------
        ASSERT_EQ SENT, $C3, $01

; --- cell $02: write a distinct marker into each 2K RAM bank ------------------
; The write protocol has no write line: read $F0nn to latch nn, then the value
; lands at whatever cart address is accessed exactly 5 bus transitions later.
; `LDA $F0nn ; LDA (WPTR),Y` places that 5th access on MARK.
        lda   #<MARK
        sta   WPTR
        lda   #>MARK
        sta   WPTR+1

        SET_CFG $06             ; bankmode 001, write enable: bank 0 -> low window
        ldy   #0
        lda   $F000+MARKER0     ; latch $3A
        lda   (WPTR),y          ; +5 transitions -> writes $3A into bank 0 @ $F700

        SET_CFG $16             ; bankmode 101, write enable: bank 1 -> low window
        ldy   #0
        lda   $F000+MARKER1     ; latch $5C
        lda   (WPTR),y          ; -> bank 1 @ $F700

        SET_CFG $02             ; bankmode 000, write enable: bank 2 -> low window
        ldy   #0
        lda   $F000+MARKER2     ; latch $71
        lda   (WPTR),y          ; -> bank 2 @ $F700

        SET_CFG $04             ; bankmode 001, write off: bank 0 low
        lda   MARK
        ldx   #MARKER0
        ldy   #$02
        jsr   assert_eq
        SET_CFG $14             ; bankmode 101, write off: bank 1 low
        lda   MARK
        ldx   #MARKER1
        ldy   #$02
        jsr   assert_eq
        SET_CFG $00             ; bankmode 000, write off: bank 2 low
        lda   MARK
        ldx   #MARKER2
        ldy   #$02
        jsr   assert_eq

; --- cell $03: walk all eight configurations ---------------------------------
; For each config: commit it, then confirm the marker visible in the low window
; is the bank the table maps there, and the high window shows either the mapped
; bank's marker (RAM up top) or a non-marker (BIOS up top — we do not assert its
; content bytes, which differ between BIOSes; only that it is not our marker).
        lda   #0
        sta   LOOPI
.walk:
        ldx   LOOPI
        ldy   walk_cfg,x
        lda   $F000,y           ; latch this config
        bit   HOTSPOT           ; commit
        ; low window marker == the bank mapped low
        ldx   LOOPI
        lda   walk_low,x
        sta   TMPEXP
        lda   MARK
        ldx   TMPEXP
        ldy   #$03
        jsr   assert_eq
        ; high window: marker byte, or $00 flag meaning "BIOS => not a marker"
        ldx   LOOPI
        lda   walk_up,x
        beq   .walk_bios
        sta   TMPEXP
        lda   UMARK
        ldx   TMPEXP
        ldy   #$03
        jsr   assert_eq
        jmp   .walk_next
.walk_bios:
        lda   UMARK
        ldy   #$03
        jsr   assert_not_marker
.walk_next:
        inc   LOOPI
        lda   LOOPI
        cmp   #8
        bne   .walk

; --- cell $04: with write enable off the write sequence must not touch RAM ----
        SET_CFG $00             ; bankmode 000, write off: bank 2 low
        lda   #<MARK
        sta   WPTR
        lda   #>MARK
        sta   WPTR+1
        ldy   #0
        lda   $F0E5             ; latch $E5, run the +5 sequence...
        lda   (WPTR),y          ; ...but write enable is off -> no write
        lda   MARK              ; bank 2 marker must be unchanged ($71, not $E5)
        ldx   #MARKER2
        ldy   #$04
        jsr   assert_eq

; --- cell $05: ROM never maps into the low window ----------------------------
        SET_CFG $04             ; bankmode 001: low = bank 0 (RAM), high = ROM
        lda   MARK              ; low window is RAM -> a real marker, never ROM
        ldx   #MARKER0
        ldy   #$05
        jsr   assert_eq
        lda   UMARK             ; high window here is the BIOS -> not our marker
        ldy   #$05
        jsr   assert_not_marker

        SET_CFG $04             ; settle a clean, write-disabled map for the screen
        PASS_TEST

; --- data + helper (placed after the code; reached only as data / via jsr) ----
SENT:   .byte $C3               ; cell-$01 sentinel: proves the page loaded

; config-walk tables, indexed 0..7 (see the config table in the header)
walk_cfg: .byte $00,$04,$08,$0C,$10,$14,$18,$1C   ; control byte = bankmode<<2, write off
walk_low: .byte MARKER2,MARKER0,MARKER2,MARKER0,MARKER2,MARKER1,MARKER2,MARKER1
walk_up:  .byte $00,$00,MARKER0,MARKER2,$00,$00,MARKER1,MARKER2   ; $00 => BIOS (not a marker)

; assert_not_marker: A = observed high-window byte, Y = fail code. Fails if the
; byte equals any of our three markers (i.e. RAM leaked where BIOS was expected).
assert_not_marker:
        sta   OBSERVED
        sty   CODE
        cmp   #MARKER0
        beq   .anm_bad
        cmp   #MARKER1
        beq   .anm_bad
        cmp   #MARKER2
        beq   .anm_bad
        rts
.anm_bad:
        lda   #$FF
        sta   EXPECTED          ; "expected: not a marker"
        jmp   fail_result

        include "frame.asm"
        include "result_screen.asm"

; per-bank marker cell (baked $00; overwritten at runtime by cell $02) and pad
        ORG   $0700
        RORG  $F700
        .byte $00
        ORG   $07FF
        RORG  $F7FF
        .byte $FF               ; pad the bank image out to a full 2K
