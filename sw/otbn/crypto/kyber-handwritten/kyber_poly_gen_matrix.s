/* Copyright "Towards ML-KEM & ML-DSA on OpenTitan" Authors */
/* Licensed under the Apache License, Version 2.0, see LICENSE for details. */
/* SPDX-License-Identifier: Apache-2.0 */

.text

.equ x0, zero
.equ x2, sp
.equ x3, fp

.equ x5, t0
.equ x6, t1
.equ x7, t2

.equ x8, s0
.equ x9, s1

.equ x10, a0
.equ x11, a1

.equ x12, a2
.equ x13, a3
.equ x14, a4
.equ x15, a5
.equ x16, a6
.equ x17, a7

.equ x18, s2
.equ x19, s3
.equ x20, s4
.equ x21, s5
.equ x22, s6
.equ x23, s7
.equ x24, s8
.equ x25, s9
.equ x26, s10
.equ x27, s11

.equ w31, bn0

/* Index of the Keccak command special register. */
#define KECCAK_CFG_REG 0x7d9
/* Config to start a SHAKE-128 operation. */
#define SHAKE128_CFG 0x2
/* Config to start a SHAKE-256 operation. */
#define SHAKE256_CFG 0xA
/* Config to start a SHA3_256 operation. */
#define SHA3_256_CFG 0x8
/* Config to start a SHA3_512 operation. */
#define SHA3_512_CFG 0x10

/* ═══════════════════════════════════════════════════════════════════════
 * Instruction encoding macros for custom vector instructions.
 *
 * These emit raw .word encodings since the assembler does not know
 * about bn.extv, bn.rejv, bn.merv. Encoding (custom7 opcode = 0x4F):
 *
 *   [6:0]   = opcode (0x4F = custom7)
 *   [11:7]  = wrd (destination WDR)
 *   [14:12] = funct3 (101=extv, 110=rejv, 100=merv)
 *   [19:15] = wrs (source WDR)
 *   [24:20] = grd/grs (GPR for count/offset)
 *   [27]    = type (0=.16H, 1=.8S)
 *
 * Usage:
 *   BN_EXTV_16H(wrd, wrs)           — extract 16×12-bit fields
 *   BN_REJV_16H(wrd, wrs, grd)      — compare & compact, count→GPR
 *   BN_MERV_16H(wrd, wrs, grs)      — merge at variable offset from GPR
 * ═══════════════════════════════════════════════════════════════════════ */

/* bn.extv.16H wrd, wrs */
#define BN_EXTV_16H(wrd, wrs) \
    .word (0x00000000 | ((wrs) << 15) | (0b101 << 12) | ((wrd) << 7) | 0x4F)

/* bn.rejv.16H wrd, wrs, grd */
#define BN_REJV_16H(wrd, wrs, grd) \
    .word (0x00000000 | ((grd) << 20) | ((wrs) << 15) | (0b110 << 12) | ((wrd) << 7) | 0x4F)

/* bn.merv.16H wrd, wrs, grs_offset */
#define BN_MERV_16H(wrd, wrs, grs) \
    .word (0x00000000 | ((grs) << 20) | ((wrs) << 15) | (0b100 << 12) | ((wrd) << 7) | 0x4F)


/*
 * Name:        poly_gen_matrix (vectorized)
 *
 * Description: Run rejection sampling on uniform random bytes to generate
 *              uniform random integers mod q, using vectorized instructions
 *              bn.extv, bn.rejv, bn.merv for the bulk of the work.
 *
 *              Consumes SHAKE-128 output in exactly the same byte order and
 *              quantity as the scalar baseline (30 bytes per inner_loop call,
 *              3 squeezes per main loop = 96 bytes), ensuring bit-exact
 *              polynomial output.
 *
 * Flags: Clobbers FG0, has no meaning beyond the scope of this subroutine.
 *
 * @param[in]  a0: pointer to seed (KYBER_SYMBYTES = 32)
 * @param[in]  a2: i||j (2 bytes)
 * @param[out] a1: dmem pointer to polynomial
 *
 * clobbered registers: a0-a6, t0-t2, s2-s7, w0-w3, w8, w10-w13, w16
 *
 * Register allocation:
 *   s5 (x21) = accumulator fill level (0..15), doubles as bn.merv offset
 *   s6 (x22) = bn.rejv accepted count output
 *   s2 (x18) = accumulator capacity (16)
 *   s4 (x20) = WDR index for bn.sid (13)
 *   a6 (x16) = flag comparison value (3) for scalar reject
 *   w8       = shake_reg (SHAKE output)
 *   w1       = extracted candidates (from bn.extv)
 *   w2       = accepted compacted (from bn.rejv)
 *   w13      = output accumulator
 *   w10      = coeff_mask (0xFFF)
 *   w11      = cand (scalar candidate)
 *   w12      = mod (q in lowest 16 bits)
 *   w16      = scratch for cross-squeeze candidates
 */

.globl poly_gen_matrix
poly_gen_matrix:
  /* 32 byte align the sp */
  andi a5, sp, 31
  beq  a5, zero, _aligned
  sub  sp, sp, a5
_aligned:
  /* save fp to stack, use 32 bytes to keep it 32-byte aligned */
  addi sp, sp, -32
  sw   fp, 0(sp)

  addi fp, sp, 0
    
  /* Adjust sp to accomodate local variables */
  addi sp, sp, -64

  /* Space for tmp buffer to hold a WDR */
  #define STACK_WDR2GPR -32
  /* Space for the nonce */
  #define STACK_NONCE -64

  /* Store nonce to memory */
  sw a2, STACK_NONCE(fp)
    
  /* Initialize a SHAKE128 operation. */
  addi  t0, zero, 34
  slli  t0, t0, 5
  addi  t0, t0, SHAKE128_CFG
  csrrw zero, KECCAK_CFG_REG, t0

  /* Send the message to the Keccak core. */
  bn.lid x0, 0(a0)             /* a0 still contains the input buffer */
  bn.wsrw 0x9, w0              /* Write to KECCAK_MSG_REG */
  addi a0, fp, STACK_NONCE     /* Set a0 to point to the nonce in memory */
  bn.lid x0, 0(a0)
  bn.wsrw 0x9, w0              /* Write to KECCAK_MSG_REG */

  /* t0 = end-of-output address (a1 + 512 for 256 x 16-bit coefficients) */
  addi t0, a1, 512

  /* Compare for flag bits (M=1, C=1 means cand < q) */
  li a6, 3 

  /* For masking coeff with 0xFFF */
  bn.xor bn0, bn0, bn0
  #define coeff_mask w10
  bn.addi coeff_mask, bn0, 1
  bn.rshi coeff_mask, coeff_mask, bn0 >> 244
  bn.subi coeff_mask, coeff_mask, 1

  #define cand w11

  #define mod w12
  li      s2, 12
  la      t1, modulus_bn
  bn.lid  s2, 0(t1)
  bn.rshi mod, bn0, mod >> 240 /* Only keep mod in lowest word */

  /* NOTE: We rely on the MOD WSR already being set by the test harness with
   * q=3329 in the lowest 16 bits. We must NOT overwrite MOD because the NTT
   * code that runs after us uses MOD for bn.addm (it contains R|Q packed). */

  #define accumulator w13
  li s4, 13
  li s2, 16 /* 1 WDR stores 16 coeffs */
  #define accumulator_count s5
  li s5, 0

  /* Clear accumulator */
  bn.xor accumulator, accumulator, accumulator

  /* Loop until 256 coefficients have been written to the output */
_rej_sample_loop:
  /* First squeeze */
  .equ w8, shake_reg
  bn.wsrr shake_reg, 0xA /* KECCAK_DIGEST */

  /* With one SHAKE squeeze, we get 32 bytes (256 bits) of data.
   *
   * Vectorized path: bn.extv consumes 16 × 12 = 192 bits (24 bytes)
   * Scalar remainder: 4 × 12 = 48 bits (6 bytes)
   * Total consumed: 240 bits = 30 bytes (same as baseline's LOOPI 20)
   * Remaining: 16 bits = 2 bytes (same as baseline)
   *
   * The 3-squeeze structure (30+30+30 + cross-squeeze stitching = 96 bytes)
   * is preserved for bit-exact output parity with the baseline.
   */

  jal        x1, _poly_uniform_inner_loop /* Process 30 bytes */
  beq        a1, t0, _end_rej_sample_loop /* Check if we have finished */

  /* ── Cross-squeeze stitching: 2 bytes from squeeze 1 + 1 byte from squeeze 2 ── */
  bn.rshi    cand, shake_reg, bn0 >> 16     /* Move remaining 2 bytes to the top of cand */
  bn.wsrr    shake_reg, 0xA                 /* Squeeze KECCAK_DIGEST */
  bn.rshi    cand, shake_reg, cand >> 240   /* Get one more byte from new shake data*/
  bn.rshi    shake_reg, bn0, shake_reg >> 8 /* Shift out used byte in shake_reg */

  /* Process the 2 cross-squeeze candidates (3 bytes → 2 × 12-bit candidates) */
  /* Candidate 1: lower 12 bits */
  bn.and     w16, coeff_mask, cand
  bn.cmp     w16, mod
  csrrs      a4, 0x7C0, zero       /* Read flags */
  andi       a4, a4, 3 /* Mask flags */
  bne        a4, a6, _skip_store2a /* Reject if cand >= q */
  jal        x1, _scalar_accumulate_w16
  beq        a1, t0, _end_rej_sample_loop
_skip_store2a:
  /* Candidate 2: next 12 bits */
  bn.rshi    cand, bn0, cand >> 12
  bn.and     cand, coeff_mask, cand
  bn.cmp     cand, mod
  csrrs      a4, 0x7C0, zero      /* Read flags */
  andi       a4, a4, 3 /* Mask flags */
  bne        a4, a6, _skip_store2
  jal        x1, _scalar_accumulate_cand
  beq        a1, t0, _end_rej_sample_loop
_skip_store2:
  jal        x1, _poly_uniform_inner_loop /* Process 30 bytes */
  beq        a1, t0, _end_rej_sample_loop /* Check if we have finished */

  /* ── Cross-squeeze stitching: 1 byte from squeeze 2 + 2 bytes from squeeze 3 ── */
  bn.rshi    cand, shake_reg, bn0 >> 8       /* move remaining 1 byte to the top of cand */
  bn.wsrr    shake_reg, 0xA                  /* Squeeze KECCAK_DIGEST */
  bn.rshi    cand, shake_reg, cand >> 248    /* Get 2 more bytes from new shake data */
  bn.rshi    shake_reg, bn0, shake_reg >> 16 /* Shift out used 2 bytes */

  /* Process the 2 cross-squeeze candidates */
  /* Candidate 1: lower 12 bits */
  bn.and     w16, coeff_mask, cand
  bn.cmp     w16, mod
  csrrs      a4, 0x7C0, zero       /* Read flags */
  andi       a4, a4, 3 /* Mask flags */
  bne        a4, a6, _skip_store4a /* Reject if cand >= q */
  jal        x1, _scalar_accumulate_w16
  beq        a1, t0, _end_rej_sample_loop
_skip_store4a:
  /* Candidate 2: next 12 bits */
  bn.rshi    cand, bn0, cand >> 12
  bn.and     cand, coeff_mask, cand
  bn.cmp     cand, mod
  csrrs      a4, 0x7C0, zero      /* Read flags */
  andi       a4, a4, 3 /* Mask flags */
  bne        a4, a6, _skip_store4
  jal        x1, _scalar_accumulate_cand
  beq        a1, t0, _end_rej_sample_loop
_skip_store4:
  jal        x1, _poly_uniform_inner_loop /* Process 30 bytes */
  beq        a1, t0, _end_rej_sample_loop /* Check if we have finished */

  /* No remainder! Start all over again. */
  beq        zero, zero, _rej_sample_loop
_end_rej_sample_loop:

  addi       sp, fp, 0 /* sp <- fp */
  lw         fp, 0(sp)   /* Pop ebp */
  addi       sp, sp, 32
  add        sp, sp, a5 /* Correct alignment offset (unalign) */

  ret


/* ═══════════════════════════════════════════════════════════════════════
 * _poly_uniform_inner_loop (vectorized)
 *
 * Process 30 bytes (240 bits) from shake_reg:
 *   Step 1: Vectorized — bn.extv consumes 192 bits → 16 candidates
 *   Step 2: Scalar    — process 4 more candidates from remaining 64 bits
 *
 * Total: 192 + 48 = 240 bits = 30 bytes consumed (identical to baseline)
 * Remaining in shake_reg after return: 16 bits = 2 bytes
 *
 * The accumulator is filled exclusively via bn.merv (LSB-first).
 * When it reaches 16 lanes, it is stored to DMEM and cleared.
 * ═══════════════════════════════════════════════════════════════════════ */
_poly_uniform_inner_loop:
  /* ── Step 1: Vectorized pipeline (16 candidates, 192 bits) ── */
  BN_EXTV_16H(1, 8)         /* w1 = bn.extv.16H(shake_reg): 16 × 12-bit → 16-bit lanes */
  BN_REJV_16H(2, 1, 22)     /* w2 = bn.rejv.16H(w1), s6 = accepted count */

  /* Check if vector results fit in accumulator: s5 + s6 <= 16 */
  add  t2, s5, s6            /* t2 = current fill + new accepted */
  li   t1, 16
  beq  s6, zero, _vec_done   /* No accepted values → skip merge entirely */

  /* Check for overflow: if t2 > 16, we need to split the merge */
  sub  t1, t1, s5            /* t1 = remaining capacity = 16 - s5 */

  /* We always merge — if overflow happens, the values past lane 15 are
   * silently clipped by the 256-bit register width. But we need to detect
   * this to store and handle the overflow portion. */

  /* First, check: does everything fit? t2 <= 16? */
  /* Since OTBN has no bge/blt, we compute: if (t2 - 16) would be > 0, overflow.
   * Equivalently: andi t2, t2, ~15 → if nonzero, overflow. But simpler:
   * we check if s6 <= t1 (remaining capacity). */

  /* Simple approach: always merge, always update s5, check if >= 16 after */
  BN_MERV_16H(13, 2, 21)    /* accumulator |= w2 << (s5 * 16) */
  add  s5, s5, s6            /* s5 = new fill level */

  /* Check if accumulator is full: s5 >= 16 */
  /* Test: is s5 >= 16? Since s5 is at most 16+15=31, we check bit 4 */
  andi s7, s5, 16
  beq  s7, zero, _vec_done   /* s5 < 16, not full yet */

  /* Accumulator full — store to DMEM */
  bn.sid s4, 0(a1++)         /* Store accumulator (w13) */
  beq  a1, t0, _vec_done     /* Check if done (will be caught by caller) */

  /* Handle overflow: s5 - 16 values were accepted but landed past bit 255.
   * These values are the LAST (s5-16) entries of w2, starting at index t1.
   * We need to recover them. Since bn.merv clips at 256 bits, we must
   * re-merge from the overflow portion of w2.
   *
   * Strategy: clear accumulator, shift w2 right by t1 lanes to bring
   * overflow values to lane 0, then merge at offset 0. */
  bn.xor accumulator, accumulator, accumulator   /* Clear accumulator */
  addi   s5, s5, -16         /* s5 = overflow count */
  beq    s5, zero, _vec_done /* No overflow values */

  /* Shift w2 right by t1 lanes (t1 = 16 - old_s5 = number that fit).
   * Each lane is 16 bits, so shift by t1*16 bits.
   * Since OTBN bn.rshi only does immediate shifts, we use a loop. */
  bn.xor w3, w3, w3          /* Use w3 as zero for shifting */
_vec_overflow_shift:
  bn.rshi w2, bn0, w2 >> 16  /* Shift w2 right by one lane (16 bits) */
  addi    t1, t1, -1
  bne     t1, zero, _vec_overflow_shift

  /* Now w2 has the overflow values at lanes 0..s5-1. Merge at offset 0. */
  li     t1, 0               /* offset = 0 */
  BN_MERV_16H(13, 2, 6)     /* accumulator |= w2 << (t1 * 16) = w2 << 0 */
                             /* Note: t1 = x6 */

_vec_done:
  /* ── Step 2: Scalar remainder (4 candidates from bits [255:192]) ── */
  /* After bn.extv consumed the low 192 bits, 64 bits remain in positions
   * [255:192] of shake_reg. Shift them down to low bits. */
  bn.rshi shake_reg, bn0, shake_reg >> 192  /* Move bits [255:192] to [63:0] */

  /* Process 4 scalar candidates from the remaining 64 bits */
  LOOPI 4, 13
    beq  a1, t0, _scalar_skip

    /* Extract low 12 bits as candidate */
    bn.and  cand, coeff_mask, shake_reg
    bn.cmp  cand, mod
    csrrs   a4, 0x7C0, zero    /* Read flags */
    andi    a4, a4, 3
    bne     a4, a6, _scalar_skip   /* Reject if cand >= q */

    /* Accepted: merge single value into accumulator using bn.merv.
     * cand has the value in bits [11:0]. bn.merv will place it at
     * lane s5 of the accumulator. */
    BN_MERV_16H(13, 11, 21)   /* accumulator |= cand << (s5 * 16) */
    addi    s5, s5, 1

    /* Check if accumulator is full */
    bne     s5, s2, _scalar_skip   /* s2 = 16 */
    bn.sid  s4, 0(a1++)            /* Store accumulator */
    li      s5, 0
    bn.xor  accumulator, accumulator, accumulator
_scalar_skip:
    bn.rshi shake_reg, bn0, shake_reg >> 12  /* Consume 12 bits */

  /* shake_reg now has 64 - 48 = 16 bits remaining = 2 bytes.
   * These are at bits [15:0] of shake_reg (after the 4 right-shifts of 12). */
  ret


/* ═══════════════════════════════════════════════════════════════════════
 * _scalar_accumulate_w16
 *
 * Accumulate the value in w16 (low 16 bits) into the accumulator using
 * bn.merv. Called from cross-squeeze stitching code.
 *
 * Uses x1 as return address (jal). Clobbers nothing beyond accumulator.
 * ═══════════════════════════════════════════════════════════════════════ */
_scalar_accumulate_w16:
  BN_MERV_16H(13, 16, 21)     /* accumulator |= w16 << (s5 * 16) */
  addi    s5, s5, 1
  bne     s5, s2, _sa_w16_done
  bn.sid  s4, 0(a1++)
  li      s5, 0
  bn.xor  accumulator, accumulator, accumulator
_sa_w16_done:
  ret


/* ═══════════════════════════════════════════════════════════════════════
 * _scalar_accumulate_cand
 *
 * Accumulate the value in cand/w11 (low 16 bits) into the accumulator
 * using bn.merv. Called from cross-squeeze stitching code.
 * ═══════════════════════════════════════════════════════════════════════ */
_scalar_accumulate_cand:
  BN_MERV_16H(13, 11, 21)     /* accumulator |= cand << (s5 * 16) */
  addi    s5, s5, 1
  bne     s5, s2, _sa_cand_done
  bn.sid  s4, 0(a1++)
  li      s5, 0
  bn.xor  accumulator, accumulator, accumulator
_sa_cand_done:
  ret
