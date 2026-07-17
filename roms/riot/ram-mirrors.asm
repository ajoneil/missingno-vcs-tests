; ram-mirrors — the RIOT's 128 bytes of RAM answer at many different addresses.
;
; The 6507 CPU has only 13 address lines (A0-A12), and the console picks which
; chip answers a bus access using just three of them:
;
;   A12=1               -> cartridge ROM
;   A12=0, A7=0         -> TIA
;   A12=0, A7=1, A9=0   -> RIOT RAM        <- this test
;   A12=0, A7=1, A9=1   -> RIOT I/O + timer
;
; Once RAM is selected, only A0-A6 pick the byte. A8, A10 and A11 are wired to
; nothing, so flipping them changes the address but not the byte: $0080, $0180,
; $0480 and $0880 are one physical RAM cell, not four. (The $0180 alias is what
; makes the stack work at all — pushes to $0180-$01FF land in this same RAM.)
;
; The test writes a byte through one alias and reads it back through another;
; if the emulator treats the aliases as separate cells, the read won't match.
;
;   CODE $01 = wrote $80, read $0180: not the same cell (A8 not ignored)
;        $02 = wrote $0180, read $80: not the same cell (A8, other direction)
;        $03 = wrote $0480, read $80: not the same cell (A10 not ignored)
;        $04 = wrote $0880, read $80: not the same cell (A11 not ignored)
;
; Self-test: verdict in RESULT ($80); region-independent.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

        org $F000

Reset:
        CLEAN_START
        TEST_BEGIN

        lda #$3C                        ; ram[$00] = $3C   (write via $0080)
        sta $80
        ASSERT_EQ $0180, $3C, $01       ; assert read($0180) == $3C  (A8 alias)

        lda #$C3                        ; ram[$00] = $C3   (write via the alias)
        sta $0180
        ASSERT_EQ $80, $C3, $02         ; assert read($0080) == $C3

        ; NB: $80 doubles as the suite's RESULT byte, so the values written
        ; here must avoid the $A5/$5A PASS/FAIL magic (a headless runner
        ; would read a premature verdict).
        lda #$33                        ; ram[$00] = $33   (write via $0480)
        sta $0480
        ASSERT_EQ $80, $33, $03         ; assert read($0080) == $33  (A10 alias)

        lda #$CC                        ; ram[$00] = $CC   (write via $0880)
        sta $0880
        ASSERT_EQ $80, $CC, $04         ; assert read($0080) == $CC  (A11 alias)

        PASS_TEST

        include "result_screen.asm"

        org $FFFC
        .word Reset
        .word Reset
