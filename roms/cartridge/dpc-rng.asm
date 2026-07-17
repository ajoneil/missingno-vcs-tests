; dpc-rng — the DPC's random-number generator, an 8-bit LFSR.
;
; The DPC ("Display Processor Chip", Pitfall II) carries an 8-bit linear-feedback
; shift register (LFSR) that games read for pseudo-random values. The whole stream
; follows from the shift law, so this ROM carries its own software model of the
; LFSR and judges the chip against it — no captured reference stream.
;
; The law (US Patent 4,644,495): the 8-bit register shifts left, and the new
; bit 0 is the XNOR of the old bits 3, 4, 5 and 7. In one line:
;
;       step(r) = ((r<<1) & $FF) | (~((r>>3)^(r>>4)^(r>>5)^(r>>7)) & 1)
;
; Facts that pin the model down:
;   - step($00) = $01 — an all-zero register is legal and self-starts.
;   - the orbit has period 255 and covers every value except $FF.
;   - step($FF) = $FF — the all-ones state is an absorbing lock-up.
; The value is read from the RNG value register at $F000.
;
; The clocking is where readings diverge. The chip has no clock pin; the
; LFSR advances on address-decoded events, and the references disagree on which
; events clock it — the patent on every $1xxx chip-select (even opcode fetches),
; others on every cart access, on register-window accesses only, or on reads of
; $1000-$1003 only. So the number of steps between two of our reads — the "stride"
; k — is a per-implementation quantity, and which clocking the die uses is
; untested on hardware.
;
; This ROM therefore never asserts an absolute RNG value. It asserts the sequence
; law — each read is exactly step^k of the previous, for one measured stride k —
; and reports k together with the post-reset offset j. Those two numbers are the
; clocking fingerprint, and they, not the verdict, carry the divergence.
;
;   CODE $01 = software LFSR model wrong — the in-ROM step() disagrees with the
;              baked vectors step($00)=$01, step($3C)=$78, step($AA)=$54. Pure
;              CPU, no chip read: this proves the reference before it judges.
;        $02 = stride not found — no k in 0..32 reaches read v2 from read v1
;              (wrong taps, shift direction, or length).
;        $03 = stride not constant — v3 != step^k(v2).
;        $04 = stride not constant — v4 != step^k(v3).
;        $05 = lock-up — one of v1..v4 is the absorbing $FF.
;        $06 = reset out of orbit — after a $F070 reset the read is not step^j of
;              $00 for any j in 0..32 (a wrong reset value or wrong LFSR).
;        $07 = reset not repeatable — a second identical reset+read differs.
;
; Self-test: verdict in RESULT ($80); region-independent.
; mapper: DPC

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

HOTSPOT0 = $FFF8
HOTSPOT1 = $FFF9

RNG      = $F000             ; read RNG value (the $1000 mirror); only $F000 used
RNGRESET = $F070             ; write here resets the LFSR (references reset to 0, one to 1)

V1       = $90               ; four back-to-back RNG reads
V2       = $91
V3       = $92
V4       = $93
STRIDE   = $94               ; measured k (LFSR steps between consecutive reads)
RESETOFF = $95               ; measured j (steps from $00 to the post-reset read)
VR       = $96               ; post-reset read
VR2      = $97               ; second post-reset read (repeatability)
EXPV     = $98               ; scratch: computed step^k expectation
FOUND    = $99               ; search result flag (1 found / 0 exhausted)
STEPIN   = $9A               ; step() input latch
STEPT    = $9B               ; step() fold/feedback scratch
RUN      = $9C               ; search working value
SSTART   = $9D               ; search start value
STGT     = $9E               ; search target value

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

        ; --- cell 01: prove the in-ROM LFSR model against baked vectors.
        ; Pure CPU (no chip read), so the reference is validated before it is
        ; used to judge anything. step($00)=$01 is the self-start; the other two
        ; are precomputed. A wrong feedback polarity (XOR) breaks step($00).
        lda #$00
        jsr Step
        sta V1
        ASSERT_EQ V1, $01, $01
        lda #$3C
        jsr Step
        sta V1
        ASSERT_EQ V1, $78, $01
        lda #$AA
        jsr Step
        sta V1
        ASSERT_EQ V1, $54, $01

        ; --- capture four RNG reads with identical instruction bytes between
        ; each consecutive pair (lda abs / sta zp). The stride between reads is
        ; therefore the same constant k for every pair on a given implementation.
        lda RNG
        sta V1
        lda RNG
        sta V2
        lda RNG
        sta V3
        lda RNG
        sta V4

        ; --- cell 02: find the stride k with step^k(v1) == v2 (k in 0..32).
        ; Every plausible clocking's stride lands inside that bound, so a correct
        ; LFSR stays green whichever clocking it uses; only a wrong-taps /
        ; wrong-direction / wrong-length model fails to reach v2.
        lda V1
        sta SSTART
        lda V2
        sta STGT
        jsr Search
        sta STRIDE             ; measured k (valid when FOUND)
        ASSERT_EQ FOUND, $01, $02

        ; --- cell 03: stride constancy — v3 == step^k(v2).
        lda V2
        ldy STRIDE
        jsr StepK
        sta EXPV
        lda V3
        ldx EXPV
        ldy #$03
        jsr assert_eq

        ; --- cell 04: stride constancy again — v4 == step^k(v3).
        lda V3
        ldy STRIDE
        jsr StepK
        sta EXPV
        lda V4
        ldx EXPV
        ldy #$04
        jsr assert_eq

        ; --- cell 05: none of v1..v4 is the absorbing lock-up $FF (v < $FF).
        ASSERT_LT V1, $FF, $05
        ASSERT_LT V2, $FF, $05
        ASSERT_LT V3, $FF, $05
        ASSERT_LT V4, $FF, $05

        ; --- cell 06: reset, then read; the value must lie on the orbit from
        ; $00 within 32 steps. References reset to $00 or to $01 (== step($00)) —
        ; both are on the from-$00 orbit; the search's offset j absorbs the reset
        ; value and the clocks between the write and the read.
        lda #$00
        sta RNGRESET           ; reset the LFSR
        lda RNG                ; first post-reset read
        sta VR
        lda #$00
        sta SSTART             ; search from $00
        lda VR
        sta STGT
        jsr Search
        sta RESETOFF           ; measured j
        ASSERT_EQ FOUND, $01, $06

        ; --- cell 07: reset is repeatable — a second reset+read of identical
        ; instruction shape yields the same value (same reset, same inter-access
        ; clocking). The cell-06 search ran in between, but the reset wipes it.
        lda #$00
        sta RNGRESET
        lda RNG
        sta VR2
        lda VR2
        ldx VR
        ldy #$07
        jsr assert_eq

        ; Surface the fingerprint in the watched result bytes, so the record
        ; carries k and j even though PASS shows no on-screen readout.
        lda STRIDE
        sta OBSERVED
        lda RESETOFF
        sta EXPECTED
        PASS_TEST

; --- step(): A = r on entry, A = step(r) on exit. Preserves X and Y.
; feedback = XNOR(b3,b4,b5,b7): mask those bits, XOR-fold to a parity bit,
; invert (XNOR), then OR into (r<<1).
Step:
        sta STEPIN
        and #$B8               ; keep bits 7,5,4,3
        sta STEPT
        lsr
        lsr
        lsr
        lsr
        eor STEPT              ; x ^= x>>4
        sta STEPT
        lsr
        lsr
        eor STEPT              ; x ^= x>>2
        sta STEPT
        lsr
        eor STEPT              ; x ^= x>>1
        and #$01               ; parity of b3,b4,b5,b7 in bit 0
        eor #$01               ; XNOR feedback bit
        sta STEPT
        lda STEPIN
        asl                    ; (r<<1) & $FF, drop the shifted-out bit
        ora STEPT              ; OR in the feedback bit
        rts

; --- StepK(): A = step^Y(A). Y = count (0..). Preserves X.
StepK:
        cpy #0
        beq .skdone
.skl:
        jsr Step
        dey
        bne .skl
.skdone:
        rts

; --- Search(): find k in [0,32] with step^k(SSTART) == STGT.
; On exit FOUND=1 and A=k, or FOUND=0. Preserves nothing of note.
Search:
        lda SSTART
        sta RUN
        ldx #0
.sloop:
        lda RUN
        cmp STGT
        beq .sfound
        cpx #32
        beq .sexh
        lda RUN
        jsr Step
        sta RUN
        inx
        jmp .sloop
.sfound:
        lda #1
        sta FOUND
        txa                    ; A = k
        rts
.sexh:
        lda #0
        sta FOUND
        rts

        include "frame.asm"
        include "result_screen.asm"

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
; This ROM never reads the display data ports, but the 2K block plus the 256B
; pad are what make the image the 10496-byte size accepted as a DPC cart
; (detection is by size). Laid out identically to dpc-fetch.
        SEG DISPLAY
        ORG $2000
DPCDATA:
        REPEAT 2048
            .byte ((($7FF - (. - DPCDATA)) ^ (($7FF - (. - DPCDATA)) >> 4)) & $FF)
        REPEND
        ORG $2800
        ds 256, $00
