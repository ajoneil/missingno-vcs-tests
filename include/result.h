; result.h — self-check RESULT convention (shared by every self-test ROM).
;
; A test writes its verdict to a fixed block of 6532 RAM so a headless runner
; can read it, AND drops into a pass/fail result screen so the same ROM is
; legible on real hardware. See result_screen.asm.
;
; Reading a failure: CODE/OBSERVED/EXPECTED are HEXADECIMAL — every test header
; tabulates its FAIL codes in hex, so print the captured bytes in hex too
; (decimal turns code $10 into a misleading "16"). A self-test stops at its
; FIRST failing sub-check: a lone code says nothing about later checks. And the
; record does not identify the test — two tests can share expected constants
; and fail byte-identically — so the harness must track which ROM ran.
;
; RAM map (low, so tests use $90+ for scratch and the stack stays high):
RESULT   = $80          ; $00 running -> $A5 PASS / $5A FAIL
CODE     = $81          ; on FAIL: which sub-check (1..255); 0 on PASS
OBSERVED = $82          ; the value that mismatched
EXPECTED = $83          ; the value the test expected
RS_BGCOL = $85          ; result-screen background colour (scratch)
RS_P1    = $86          ; result-screen font pointer 1 ($86/$87)
RS_P2    = $88          ; result-screen font pointer 2 ($88/$89)

PASS_MAGIC = $A5
FAIL_MAGIC = $5A

; Call once at the top of the test, after CLEAN_START. Also clears carry —
; CLEAN_START zeroes RAM/A/X/Y and the D flag but leaves carry undefined, so
; without this the (undefined) power-on carry rides along until the first
; compare, which shows up as noise when diffing traces across emulators.
; After TEST_BEGIN the machine state is fully deterministic — a clean anchor.
    MAC TEST_BEGIN
        clc                     ; carry: undefined at power-on
        clv                     ; overflow: undefined at power-on
        lda #0
        sta RESULT
        sta CODE
        sta OBSERVED
        sta EXPECTED
harness_ready:                  ; deterministic-state anchor for trace diffs
    ENDM

; ASSERT_EQ observed_zpaddr, expected_imm, failcode_imm
;   loads the byte at {1}, checks it == {2}; on mismatch records
;   OBSERVED/EXPECTED/CODE and jumps to fail_result (never returns).
    MAC ASSERT_EQ
        lda {1}
        ldx #{2}
        ldy #{3}
        jsr assert_eq
    ENDM

; ASSERT_LT observed_zpaddr, limit_imm, failcode   -- assert [{1}] <  {2} (unsigned)
    MAC ASSERT_LT
        lda {1}
        ldx #{2}
        ldy #{3}
        jsr assert_lt
    ENDM

; ASSERT_GE observed_zpaddr, limit_imm, failcode   -- assert [{1}] >= {2} (unsigned)
    MAC ASSERT_GE
        lda {1}
        ldx #{2}
        ldy #{3}
        jsr assert_ge
    ENDM

; Declare success and show the pass screen.
    MAC PASS_TEST
        lda #0
        sta CODE                ; CODE = 0 on PASS (per convention)
        lda #PASS_MAGIC
        sta RESULT
        jmp pass_result
    ENDM
