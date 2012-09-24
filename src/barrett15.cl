/*
This file is part of mfaktc (mfakto).
Copyright (C) 2009 - 2012  Oliver Weihe (o.weihe@t-online.de)
                           Bertram Franz (bertramf@gmx.net)

mfaktc (mfakto) is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

mfaktc (mfakto) is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
                                
You should have received a copy of the GNU General Public License
along with mfaktc (mfakto).  If not, see <http://www.gnu.org/licenses/>.

Version 0.13pre2
*/

/****************************************
 ****************************************
 * 15-bit-stuff for the 90/75-bit-barrett-kernel
 * included by main kernel file
 ****************************************
 ****************************************/

// 75-bit
#define EVAL_RES_d(comp) \
  if((a.d4.comp|a.d3.comp|a.d2.comp|a.d1.comp)==0 && a.d0.comp==1) \
  { \
      tid=ATOMIC_INC(RES[0]); \
      if(tid<10) \
      { \
        RES[tid*3 + 1]=f.d4.comp;  \
        RES[tid*3 + 2]=mad24(f.d3.comp,0x8000u, f.d2.comp); \
        RES[tid*3 + 3]=mad24(f.d1.comp,0x8000u, f.d0.comp); \
      } \
  }

// 90-bit
#define EVAL_RES_90(comp) \
  if((a.d5.comp|a.d4.comp|a.d3.comp|a.d2.comp|a.d1.comp)==0 && a.d0.comp==1) \
  { \
      tid=ATOMIC_INC(RES[0]); \
      if(tid<10) \
      { \
        RES[tid*3 + 1]=mad24(f.d5.comp,0x8000u, f.d4.comp); \
        RES[tid*3 + 2]=mad24(f.d3.comp,0x8000u, f.d2.comp); \
        RES[tid*3 + 3]=mad24(f.d1.comp,0x8000u, f.d0.comp); \
      } \
  }


/****************************************
 ****************************************
 * 15-bit based 75-bit barrett-kernels
 *
 ****************************************
 ****************************************/

int75_v sub_if_gte_75(const int75_v a, const int75_v b)
/* return (a>b)?a-b:a */
{
  int75_v tmp;
  /* do the subtraction and use tmp.d4 to decide if the result is valid (if a was > b) */

  tmp.d0 = (a.d0 - b.d0) & 0x7FFF;
  tmp.d1 = (a.d1 - b.d1 - AS_UINT_V((b.d0 > a.d0) ? 1 : 0));
  tmp.d2 = (a.d2 - b.d2 - AS_UINT_V((tmp.d1 > a.d1) ? 1 : 0));
  tmp.d3 = (a.d3 - b.d3 - AS_UINT_V((tmp.d2 > a.d2) ? 1 : 0));
  tmp.d4 = (a.d4 - b.d4 - AS_UINT_V((tmp.d3 > a.d3) ? 1 : 0));
  tmp.d1&= 0x7FFF;
  tmp.d2&= 0x7FFF;
  tmp.d3&= 0x7FFF;

  tmp.d0 = (tmp.d4 > a.d4) ? a.d0 : tmp.d0;
  tmp.d1 = (tmp.d4 > a.d4) ? a.d1 : tmp.d1;
  tmp.d2 = (tmp.d4 > a.d4) ? a.d2 : tmp.d2;
  tmp.d3 = (tmp.d4 > a.d4) ? a.d3 : tmp.d3;
  tmp.d4 = (tmp.d4 > a.d4) ? a.d4 : tmp.d4; //  & 0x7FFF not necessary as tmp.d4 is <= a.d4

  return tmp;
}

void inc_if_ge_75(int75_v * const res, const int75_v a, const int75_v b)
{ /* if (a >= b) res++ */
  __private uint_v ge,tmpa0,tmpa1,tmpb0,tmpb1;
  // PERF: faster to combine them to 30-bits before all this?
  // Yes, a tiny bit: 9 operations each, plus 2 vs. 4 conditional loads with dependencies.
  // PERF: further improvement by upsampling to long int? No, that is slower.
  tmpa0=mad24(a.d2, 32768u, a.d1);
  tmpa1=mad24(a.d4, 32768u, a.d3);
  tmpb0=mad24(b.d2, 32768u, b.d1);
  tmpb1=mad24(b.d4, 32768u, b.d3);
  ge = AS_UINT_V((tmpa1 == tmpb1) ? ((tmpa0 == tmpb0) ? (a.d0 >= b.d0)
                                                      : (tmpa0 > tmpb0))
                                  : (tmpa1 > tmpb1));
  /*
  ge = AS_UINT_V((a.d4 == b.d4) ? ((a.d3 == b.d3) ? ((a.d2 == b.d2) ? ((a.d1 == b.d1) ? (a.d0 >= b.d0)
                                                                                      : (a.d1 > b.d1))
                                                                    : (a.d2 > b.d2))
                                                  : (a.d3 > b.d3))
                                :(a.d4 > b.d4));

                                */
  res->d0 += AS_UINT_V(ge ? 1 : 0);
  res->d1 += res->d0 >> 15;
  res->d2 += res->d1 >> 15;
  res->d3 += res->d2 >> 15;
  res->d4 += res->d3 >> 15;
  res->d0 &= 0x7FFF;
  res->d1 &= 0x7FFF;
  res->d2 &= 0x7FFF;
  res->d3 &= 0x7FFF;
}

void mul_75(int75_v * const res, const int75_v a, const int75_v b)
/* res = a * b */
{
  res->d0 = mul24(a.d0, b.d0);

  res->d1 = mad24(a.d1, b.d0, res->d0 >> 15);
  res->d1 = mad24(a.d0, b.d1, res->d1);
  res->d0 &= 0x7FFF;

  res->d2 = mad24(a.d2, b.d0, res->d1 >> 15);
  res->d2 = mad24(a.d1, b.d1, res->d2);
  res->d2 = mad24(a.d0, b.d2, res->d2);
  res->d1 &= 0x7FFF;

  res->d3 = mad24(a.d3, b.d0, res->d2 >> 15);
  res->d3 = mad24(a.d2, b.d1, res->d3);
  res->d3 = mad24(a.d1, b.d2, res->d3);
  res->d3 = mad24(a.d0, b.d3, res->d3);
  res->d2 &= 0x7FFF;

  res->d4 = mad24(a.d4, b.d0, res->d3 >> 15);
  res->d4 = mad24(a.d3, b.d1, res->d4);
  res->d4 = mad24(a.d2, b.d2, res->d4);
  res->d4 = mad24(a.d1, b.d3, res->d4);
  res->d4 = mad24(a.d0, b.d4, res->d4);  // the 5th mad can overflow d4, but that's ok for this function.
  res->d3 &= 0x7FFF;
  res->d4 &= 0x7FFF;

}


void mul_75_150_no_low3(int150_v * const res, const int75_v a, const int75_v b)
/*
res ~= a * b
res.d0 to res.d2 are NOT computed. Carries to res.d3 are ignored,
too. So the digits res.d{3-9} might differ from mul_75_150().
 */
{
  // assume we have enough spare bits and can do all the carries at the very end:
  // 0x7FFF * 0x7FFF = 0x3FFF0001 = max result of mul24, up to 4 of these can be
  // added into 32-bit: 0x3FFF0001 * 4 = 0xFFFC0004, which even leaves room for
  // one (almost two) carry of 17 bit (32-bit >> 15)
  // this optimized mul 5x5 requires: 19 mul/mad24, 7 shift, 6 and, 1 add

  res->d3 = mul24(a.d3, b.d0);
  res->d3 = mad24(a.d2, b.d1, res->d3);
  res->d3 = mad24(a.d1, b.d2, res->d3);
  res->d3 = mad24(a.d0, b.d3, res->d3);

  res->d4 = mad24(a.d4, b.d0, res->d3 >> 15);
  // res->d3 &= 0x7FFF;  // d3 itself is not used, only its carry to d4 is required
  res->d4 = mad24(a.d3, b.d1, res->d4);
  res->d4 = mad24(a.d2, b.d2, res->d4);
  res->d4 = mad24(a.d1, b.d3, res->d4);
   // 5th mad24 can overflow d4, need to handle carry before: pull in the first d5 line
  res->d5 = mad24(a.d4, b.d1, res->d4 >> 15);
  res->d4 &= 0x7FFF;
  res->d4 = mad24(a.d0, b.d4, res->d4);  // 31-bit at most

  res->d5 = mad24(a.d3, b.d2, res->d4 >> 15) + res->d5;
  res->d5 = mad24(a.d2, b.d3, res->d5);
  res->d5 = mad24(a.d1, b.d4, res->d5);
  res->d4 &= 0x7FFF;
  // now we have in d5: 4x mad24() + 1x 17-bit carry + 1x 16-bit carry: still fits into 32 bits

  res->d6 = mad24(a.d2, b.d4, res->d5 >> 15);
  res->d6 = mad24(a.d3, b.d3, res->d6);
  res->d6 = mad24(a.d4, b.d2, res->d6);
  res->d5 &= 0x7FFF;

  res->d7 = mad24(a.d3, b.d4, res->d6 >> 15);
  res->d7 = mad24(a.d4, b.d3, res->d7);
  res->d6 &= 0x7FFF;

  res->d8 = mad24(a.d4, b.d4, res->d7 >> 15);
  res->d7 &= 0x7FFF;

  res->d9 = res->d8 >> 15;
  res->d8 &= 0x7FFF;
}


void mul_75_150(int150_v * const res, const int75_v a, const int75_v b)
/*
res = a * b
 */
{
  /* this is the complete implementation, no longer used, but was the basis for
     the _no_low3 and square functions */
  // assume we have enough spare bits and can do all the carries at the very end:
  // 0x7FFF * 0x7FFF = 0x3FFF0001 = max result of mul24, up to 4 of these can be
  // added into 32-bit: 0x3FFF0001 * 4 = 0xFFFC0004, which even leaves room for
  // one (almost two) carry of 17 bit (32-bit >> 15)
  // mul 5x5 requires: 25 mul/mad24, 10 shift, 10 and, 1 add

  res->d0 = mul24(a.d0, b.d0);

  res->d1 = mad24(a.d1, b.d0, res->d0 >> 15);
  res->d1 = mad24(a.d0, b.d1, res->d1);
  res->d0 &= 0x7FFF;

  res->d2 = mad24(a.d2, b.d0, res->d1 >> 15);
  res->d2 = mad24(a.d1, b.d1, res->d2);
  res->d2 = mad24(a.d0, b.d2, res->d2);
  res->d1 &= 0x7FFF;

  res->d3 = mad24(a.d3, b.d0, res->d2 >> 15);
  res->d3 = mad24(a.d2, b.d1, res->d3);
  res->d3 = mad24(a.d1, b.d2, res->d3);
  res->d3 = mad24(a.d0, b.d3, res->d3);
  res->d2 &= 0x7FFF;

  res->d4 = mad24(a.d4, b.d0, res->d3 >> 15);
  res->d3 &= 0x7FFF;
  res->d4 = mad24(a.d3, b.d1, res->d4);
  res->d4 = mad24(a.d2, b.d2, res->d4);
  res->d4 = mad24(a.d1, b.d3, res->d4);
   // 5th mad24 can overflow d4, need to handle carry before: pull in the first d5 line
  res->d5 = mad24(a.d4, b.d1, res->d4 >> 15);
  res->d4 &= 0x7FFF;
  res->d4 = mad24(a.d0, b.d4, res->d4);  // 31-bit at most

  res->d5 = mad24(a.d3, b.d2, res->d4 >> 15) + res->d5;
  res->d5 = mad24(a.d2, b.d3, res->d5);
  res->d5 = mad24(a.d1, b.d4, res->d5);
  res->d4 &= 0x7FFF;
  // now we have in d5: 4x mad24() + 1x 17-bit carry + 1x 16-bit carry: still fits into 32 bits

  res->d6 = mad24(a.d2, b.d4, res->d5 >> 15);
  res->d6 = mad24(a.d3, b.d3, res->d6);
  res->d6 = mad24(a.d4, b.d2, res->d6);
  res->d5 &= 0x7FFF;

  res->d7 = mad24(a.d3, b.d4, res->d6 >> 15);
  res->d7 = mad24(a.d4, b.d3, res->d7);
  res->d6 &= 0x7FFF;

  res->d8 = mad24(a.d4, b.d4, res->d7 >> 15);
  res->d7 &= 0x7FFF;

  res->d9 = res->d8 >> 15;
  res->d8 &= 0x7FFF;
}


void square_75_150(int150_v * const res, const int75_v a)
/* res = a^2 = d0^2 + 2d0d1 + d1^2 + 2d0d2 + 2(d1d2 + d0d3) + d2^2 +
               2(d0d4 + d1d3) + 2(d1d4 + d2d3) + d3^2 + 2d2d4 + 2d3d4 + d4^2
   */
{
  // assume we have enough spare bits and can do all the carries at the very end:
  // 0x7FFF * 0x7FFF = 0x3FFF0001 = max result of mul24, up to 4 of these can be
  // added into 32-bit: 0x3FFF0001 * 4 = 0xFFFC0004, which even leaves room for
  // one (almost two) carry of 17 bit (32-bit >> 15)
  // square 5x5 requires: 15 mul/mad24, 14 shift, 10 and, 1 add

  res->d0 = mul24(a.d0, a.d0);

  res->d1 = mad24(a.d1, a.d0 << 1, res->d0 >> 15);
  res->d0 &= 0x7FFF;

  res->d2 = mad24(a.d1, a.d1, res->d1 >> 15);
  res->d2 = mad24(a.d2, a.d0 << 1, res->d2);
  res->d1 &= 0x7FFF;

  res->d3 = mad24(a.d3, a.d0 << 1, res->d2 >> 15);
  res->d3 = mad24(a.d2, a.d1 << 1, res->d3);
  res->d2 &= 0x7FFF;

  res->d4 = mad24(a.d4, a.d0 << 1, res->d3 >> 15);
  res->d3 &= 0x7FFF;
  res->d4 = mad24(a.d3, a.d1 << 1, res->d4);
   // 5th mad24 can overflow d4, need to handle carry before: pull in the first d5 line
  res->d5 = mad24(a.d4, a.d1 << 1, res->d4 >> 15);
  res->d4 &= 0x7FFF;
  res->d4 = mad24(a.d2, a.d2, res->d4);  // 31-bit at most

  res->d5 = mad24(a.d3, a.d2 << 1, res->d4 >> 15) + res->d5;
  res->d4 &= 0x7FFF;
  // now we have in d5: 4x mad24() + 1x 17-bit carry + 1x 16-bit carry: still fits into 32 bits

  res->d6 = mad24(a.d4, a.d2 << 1, res->d5 >> 15);
  res->d6 = mad24(a.d3, a.d3, res->d6);
  res->d5 &= 0x7FFF;

  res->d7 = mad24(a.d4, a.d3 << 1, res->d6 >> 15);
  res->d6 &= 0x7FFF;

  res->d8 = mad24(a.d4, a.d4, res->d7 >> 15);
  res->d7 &= 0x7FFF;

  res->d9 = res->d8 >> 15;
  res->d8 &= 0x7FFF;
}


void shl_75(int75_v * const a)
/* shiftleft a one bit */
{
  a->d4 = mad24(a->d4, 2u, a->d3 >> 14); // keep the extra top bit
  a->d3 = mad24(a->d3, 2u, a->d2 >> 14) & 0x7FFF;
  a->d2 = mad24(a->d2, 2u, a->d1 >> 14) & 0x7FFF;
  a->d1 = mad24(a->d1, 2u, a->d0 >> 14) & 0x7FFF;
  a->d0 = (a->d0 << 1u) & 0x7FFF;
}
void shl_150(int150_v * const a)
/* shiftleft a one bit */
{
  a->d9 = mad24(a->d9, 2u, a->d8 >> 14); // keep the extra top bit
  a->d8 = mad24(a->d8, 2u, a->d7 >> 14) & 0x7FFF;
  a->d7 = mad24(a->d7, 2u, a->d6 >> 14) & 0x7FFF;
  a->d6 = mad24(a->d6, 2u, a->d5 >> 14) & 0x7FFF;
  a->d5 = mad24(a->d5, 2u, a->d4 >> 14) & 0x7FFF;
  a->d4 = mad24(a->d4, 2u, a->d3 >> 14) & 0x7FFF;
  a->d3 = mad24(a->d3, 2u, a->d2 >> 14) & 0x7FFF;
  a->d2 = mad24(a->d2, 2u, a->d1 >> 14) & 0x7FFF;
  a->d1 = mad24(a->d1, 2u, a->d0 >> 14) & 0x7FFF;
  a->d0 = (a->d0 << 1u) & 0x7FFF;
}


void div_150_75(int75_v * const res, const uint qhi, const int75_v n, const float_v nf
#if (TRACE_KERNEL > 1)
                  , const uint tid
#endif
#ifdef CHECKS_MODBASECASE
                  , __global uint * restrict modbasecase_debug
#endif
)/* res = q / n (integer division) */
{
  __private float_v qf;
  __private float   qf_1;   // for the first conversion which does not need vectors yet
  __private uint_v qi, qil, qih;
  __private int150_v nn, q;
  __private int75_v tmp75;

#if (TRACE_KERNEL > 1)
  if (tid==TRACE_TID) printf("div_150_75#0: q=%x:<135x0>, n=%x:%x:%x:%x:%x, nf=%#G\n",
        qhi, n.d4.s0, n.d3.s0, n.d2.s0, n.d1.s0, n.d0.s0, nf.s0);
#endif

/********** Step 1, Offset 2^60 (4*15 + 0) **********/
  qf_1= convert_float_rtz(qhi) * 32768.0f * 32768.0f * 32768.0f; // no vector yet

  qi=CONVERT_UINT_V(qf_1*nf);  // vectorize just here

  MODBASECASE_QI_ERROR(1<<15, 1, qi, 0);  // first step is smaller

  res->d4 = qi;
#if (TRACE_KERNEL > 1)
    if (tid==TRACE_TID) printf("div_150_75#1: qf=%#G, nf=%#G, *=%#G, qi=%d=0x%x, res=%x:..:..:..:..\n",
                                 qf_1, nf.s0, qf.s0*nf.s0, qi.s0, qi.s0, res->d4.s0);
#endif

  /*******************************************************/

// nn = n * qi
  nn.d4  = mul24(n.d0, qi);
#if (TRACE_KERNEL > 4)
  if (tid==TRACE_TID) printf("div_150_75#1.1: nn=..:..:..:..:..:%x:..:..:..:..\n",
        nn.d4.s0);
#endif

  nn.d5  = mad24(n.d1, qi, nn.d4 >> 15);
  nn.d4 &= 0x7FFF;
#if (TRACE_KERNEL > 4)
  if (tid==TRACE_TID) printf("div_150_75#1.2: nn=..:..:..:..:%x:%x:...\n",
        nn.d5.s0, nn.d4.s0);
#endif

  nn.d6  = mad24(n.d2, qi, nn.d5 >> 15);
  nn.d5 &= 0x7FFF;
#if (TRACE_KERNEL > 4)
  if (tid==TRACE_TID) printf("div_150_75#1.3: nn=..:..:..:%x:%x:%x:...\n",
        nn.d6.s0, nn.d5.s0, nn.d4.s0);
#endif

  nn.d7  = mad24(n.d3, qi, nn.d6 >> 15);
  nn.d6 &= 0x7FFF;
#if (TRACE_KERNEL > 3)
  if (tid==TRACE_TID) printf("div_150_75#1.4: nn=..:..:%x:%x:%x:%x:...\n",
        nn.d7.s0, nn.d6.s0, nn.d5.s0, nn.d4.s0);
#endif
  nn.d8  = mad24(n.d4, qi, nn.d7 >> 15);
  nn.d7 &= 0x7FFF;
#if (TRACE_KERNEL > 3)
  if (tid==TRACE_TID) printf("div_150_75#1.5: nn=..:%x:%x:%x:%x:%x:...\n",
        nn.d8.s0, nn.d7.s0, nn.d6.s0, nn.d5.s0, nn.d4.s0);
#endif

// now shift-left 3 bits
//#ifdef CHECKS_MODBASECASE
  nn.d9  = nn.d8 >> 15;  // PERF: not needed as it will be gone anyway after sub
  nn.d8 &= 0x7FFF;
//#endif
//  nn.d8  = mad24(nn.d8 & 0xFFF, 8u, nn.d7 >> 12);
//  nn.d7  = mad24(nn.d7 & 0xFFF, 8u, nn.d6 >> 12);
//  nn.d6  = mad24(nn.d6 & 0xFFF, 8u, nn.d5 >> 12);
 // nn.d5  = mad24(nn.d5 & 0xFFF, 8u, nn.d4 >> 12);
//  nn.d4  = mad24(nn.d4 & 0xFFF, 8u, nn.d3 >> 12);
//  nn.d3  = (nn.d3 & 0xFFF) << 3;
#if (TRACE_KERNEL > 2)
//  if (tid==TRACE_TID) printf("div_150_75#1.6: nn=%x:%x:%x:%x:%x:%x:%x:..:..:..\n",
//        nn.d9.s0, nn.d8.s0, nn.d7.s0, nn.d6.s0, nn.d5.s0, nn.d4.s0, nn.d3.s0);
#endif

//  q.d0-q.d8 are all zero
  q.d4 = -nn.d4;
  q.d5 = -nn.d5 - AS_UINT_V((q.d4 > 0x7FFF)?1:0);
  q.d6 = -nn.d6 - AS_UINT_V((q.d5 > 0x7FFF)?1:0);
  q.d7 = -nn.d7 - AS_UINT_V((q.d6 > 0x7FFF)?1:0);
  q.d8 = -nn.d8 - AS_UINT_V((q.d7 > 0x7FFF)?1:0); 
//#ifdef CHECKS_MODBASECASE
  q.d9 = qhi - nn.d9 - AS_UINT_V((q.d8 > 0x7FFF)?1:0); // PERF: not needed: should be zero anyway
//#endif
  q.d4 &= 0x7FFF;
  q.d5 &= 0x7FFF;
  q.d6 &= 0x7FFF;
  q.d7 &= 0x7FFF;
  q.d8 &= 0x7FFF;
#if (TRACE_KERNEL > 2)
  if (tid==TRACE_TID) printf("div_150_75#1.7: q=%x!%x:%x:%x:%x:%x:..:..:..:..\n",
        q.d9.s0, q.d8.s0, q.d7.s0, q.d6.s0, q.d5.s0, q.d4.s0);
#endif
  MODBASECASE_NONZERO_ERROR(q.d9, 1, 9, 1);

  /********** Step 2, Offset 2^40 (2*15 + 10) **********/

  qf= CONVERT_FLOAT_V(mad24(q.d8, 32768u, q.d7));
  qf= qf * 32768.0f * 32768.0f + CONVERT_FLOAT_V(mad24(q.d6, 32768u, q.d5));
  qf*= 32.0f;

  qi=CONVERT_UINT_V(qf*nf);

  MODBASECASE_QI_ERROR(1<<21, 2, qi, 2);

  res->d3 = (qi >> 5);
  res->d2 = (qi << 10) & 0x7FFF;
  qil = qi & 0x7FFF;
  qih = (qi >> 15) & 0x7FFF;
#if (TRACE_KERNEL > 1)
    if (tid==TRACE_TID) printf("div_150_75#2: qf=%#G, nf=%#G, *=%#G, qi=%d=0x%x, res=%x:%x:%x:..:..\n",
                                 qf.s0, nf.s0, qf.s0*nf.s0, qi.s0, qi.s0, res->d4.s0, res->d3.s0, res->d2.s0);
#endif

  /*******************************************************/

// nn = n * qi
  nn.d2  = mul24(n.d0, qil);
  nn.d3  = mad24(n.d0, qih, nn.d2 >> 15);
  nn.d2 &= 0x7FFF;
#if (TRACE_KERNEL > 4)
  if (tid==TRACE_TID) printf("div_150_75#2.1: nn=..:..:..:..:%x:%x:..:..\n",
        nn.d3.s0, nn.d2.s0);
#endif

  nn.d3  = mad24(n.d1, qil, nn.d3);
  nn.d4  = mad24(n.d1, qih, nn.d3 >> 15);
  nn.d3 &= 0x7FFF;
#if (TRACE_KERNEL > 4)
  if (tid==TRACE_TID) printf("div_150_75#2.2: nn=..:..:..:%x:%x:%x:..:..\n",
        nn.d4.s0, nn.d3.s0, nn.d2.s0);
#endif

  nn.d4  = mad24(n.d2, qil, nn.d4);
  nn.d5  = mad24(n.d2, qih, nn.d4 >> 15);
  nn.d4 &= 0x7FFF;
#if (TRACE_KERNEL > 4)
  if (tid==TRACE_TID) printf("div_150_75#2.3: nn=..:..:%x:%x:%x:%x:..:..\n",
        nn.d5.s0, nn.d4.s0, nn.d3.s0, nn.d2.s0);
#endif

  nn.d5  = mad24(n.d3, qil, nn.d5);
  nn.d6  = mad24(n.d3, qih, nn.d5 >> 15);
  nn.d5 &= 0x7FFF;
#if (TRACE_KERNEL > 3)
  if (tid==TRACE_TID) printf("div_150_75#2.4: nn=..:%x:%x:%x:%x:%x:..:..\n",
        nn.d6.s0, nn.d5.s0, nn.d4.s0, nn.d3.s0, nn.d2.s0);
#endif

  nn.d6  = mad24(n.d4, qil, nn.d6);
//#ifdef CHECKS_MODBASECASE
  nn.d7  = mad24(n.d4, qih, nn.d6 >> 15);
//#endif
  nn.d6 &= 0x7FFF;

#if (TRACE_KERNEL > 3)
  if (tid==TRACE_TID) printf("div_150_75#2.5: nn=..:%x:%x:%x:%x:%x:%x:..:..\n",
        nn.d7.s0, nn.d6.s0, nn.d5.s0, nn.d4.s0, nn.d3.s0, nn.d2.s0);
#endif

// now shift-left 10 bits
//#ifdef CHECKS_MODBASECASE
  nn.d8  = nn.d7 >> 5;  // PERF: not needed as it will be gone anyway after sub
//#endif
  nn.d7  = mad24(nn.d7 & 0x1F, 1024u, nn.d6 >> 5);  // PERF: not needed as it will be gone anyway after sub
  nn.d6  = mad24(nn.d6 & 0x1F, 1024u, nn.d5 >> 5);
  nn.d5  = mad24(nn.d5 & 0x1F, 1024u, nn.d4 >> 5);
  nn.d4  = mad24(nn.d4 & 0x1F, 1024u, nn.d3 >> 5);
  nn.d3  = mad24(nn.d3 & 0x1F, 1024u, nn.d2 >> 5);
  nn.d2  = (nn.d2 & 0x1F) << 10;
#if (TRACE_KERNEL > 3)
  if (tid==TRACE_TID) printf("div_150_75#2.6: nn=..:%x:%x:%x:%x:%x:%x:%x:..:..\n",
        nn.d8.s0, nn.d7.s0, nn.d6.s0, nn.d5.s0, nn.d4.s0, nn.d3.s0, nn.d2.s0);
#endif

//  q = q - nn
  q.d2 = -nn.d2;
  q.d3 = q.d3 - nn.d3 - AS_UINT_V((q.d2 > 0x7FFF)?1:0);
  q.d4 = q.d4 - nn.d4 - AS_UINT_V((q.d3 > 0x7FFF)?1:0);
  q.d5 = q.d5 - nn.d5 - AS_UINT_V((q.d4 > 0x7FFF)?1:0);
  q.d6 = q.d6 - nn.d6 - AS_UINT_V((q.d5 > 0x7FFF)?1:0);
  q.d7 = q.d7 - nn.d7 - AS_UINT_V((q.d6 > 0x7FFF)?1:0); // PERF: not needed: should be zero anyway
//#ifdef CHECKS_MODBASECASE
  q.d8 = q.d8 - nn.d8 - AS_UINT_V((q.d7 > 0x7FFF)?1:0); // PERF: not needed: should be zero anyway
//#endif
  q.d2 &= 0x7FFF;
  q.d3 &= 0x7FFF;
  q.d4 &= 0x7FFF;
  q.d5 &= 0x7FFF;
  q.d6 &= 0x7FFF;
  q.d7 &= 0x7FFF;
#if (TRACE_KERNEL > 2)
  if (tid==TRACE_TID) printf("div_150_75#2.7: q=..:%x:%x!%x:%x:%x:%x:%x:..:..\n",
        q.d8.s0, q.d7.s0, q.d6.s0, q.d5.s0, q.d4.s0, q.d3.s0, q.d2.s0);
#endif

  MODBASECASE_NONZERO_ERROR(q.d8, 2, 8, 3);

  /********** Step 3, Offset 2^20 (1*15 + 5) **********/

  qf= CONVERT_FLOAT_V(mad24(q.d7, 32768u, q.d6)); 
  qf= qf * 32768.0f * 32768.0f + CONVERT_FLOAT_V(mad24(q.d5, 32768u, q.d4));
  qf*= 32768.0f;

  qi=CONVERT_UINT_V(qf*nf);

  MODBASECASE_QI_ERROR(1<<25, 3, qi, 5);

  qih = (qi >> 15) & 0x7FFF;
  qil = qi & 0x7FFF;
  res->d2 += qih;
  res->d1  = qil;
#if (TRACE_KERNEL > 1)
    if (tid==TRACE_TID) printf("div_150_75#3: qf=%#G, nf=%#G, *=%#G, qi=%d=0x%x, res=%x:%x:%x:%x:..\n",
                                 qf.s0, nf.s0, qf.s0*nf.s0, qi.s0, qi.s0, res->d4.s0, res->d3.s0, res->d2.s0, res->d1.s0);
#endif

  /*******************************************************/

// nn = n * qi
  nn.d1  = mul24(n.d0, qil);
  nn.d2  = mad24(n.d0, qih, nn.d1 >> 15);
  nn.d1 &= 0x7FFF;
#if (TRACE_KERNEL > 4)
  if (tid==TRACE_TID) printf("div_150_75#3.1: nn=..:..:..:..:%x:%x:..\n",
        nn.d2.s0, nn.d1.s0);
#endif

  nn.d2  = mad24(n.d1, qil, nn.d2);
  nn.d3  = mad24(n.d1, qih, nn.d2 >> 15);
  nn.d2 &= 0x7FFF;
#if (TRACE_KERNEL > 4)
  if (tid==TRACE_TID) printf("div_150_75#3.2: nn=..:..:..:%x:%x:%x:..\n",
        nn.d3.s0, nn.d2.s0, nn.d1.s0);
#endif

  nn.d3  = mad24(n.d2, qil, nn.d3);
  nn.d4  = mad24(n.d2, qih, nn.d3 >> 15);
  nn.d3 &= 0x7FFF;
#if (TRACE_KERNEL > 4)
  if (tid==TRACE_TID) printf("div_150_75#3.3: nn=..:..:%x:%x:%x:%x:..\n",
        nn.d4.s0, nn.d3.s0, nn.d2.s0, nn.d1.s0);
#endif

  nn.d4  = mad24(n.d3, qil, nn.d4);
  nn.d5  = mad24(n.d3, qih, nn.d4 >> 15);
  nn.d4 &= 0x7FFF;
#if (TRACE_KERNEL > 3)
  if (tid==TRACE_TID) printf("div_150_75#3.4: nn=..:%x:%x:%x:%x:%x:..\n",
        nn.d5.s0, nn.d4.s0, nn.d3.s0, nn.d2.s0, nn.d1.s0);
#endif
  nn.d5  = mad24(n.d4, qil, nn.d5);
//#ifdef CHECKS_MODBASECASE
  nn.d6  = mad24(n.d4, qih, nn.d5 >> 15);
//#endif
  nn.d5 &= 0x7FFF;
#if (TRACE_KERNEL > 3)
  if (tid==TRACE_TID) printf("div_150_75#3.5: nn=..:%x:%x:%x:%x:%x:%x:..\n",
        nn.d6.s0, nn.d5.s0, nn.d4.s0, nn.d3.s0, nn.d2.s0, nn.d1.s0);
#endif
  nn.d7  = nn.d6 >> 15;  // PERF: not needed as it will be gone anyway after sub
  nn.d6 &= 0x7FFF;

// now shift-left 10 bits
//  nn.d7  = nn.d6 >> 5;  // PERF: not needed as it will be gone anyway after sub
//  nn.d6  = mad24(nn.d6 & 0x1F, 1024u, nn.d5 >> 5);  // PERF: not needed as it will be gone anyway after sub
//  nn.d5  = mad24(nn.d5 & 0x1F, 1024u, nn.d4 >> 5);
//  nn.d4  = mad24(nn.d4 & 0x1F, 1024u, nn.d3 >> 5);
//  nn.d3  = mad24(nn.d3 & 0x1F, 1024u, nn.d2 >> 5);
//  nn.d2  = mad24(nn.d2 & 0x1F, 1024u, nn.d1 >> 5);
//  nn.d1  = (nn.d1 & 0x1F) << 10;
#if (TRACE_KERNEL > 3)
  if (tid==TRACE_TID) printf("div_150_75#3.6: nn=..:..:%x:%x:%x:%x:%x:%x:..\n",
        nn.d6.s0, nn.d5.s0, nn.d4.s0, nn.d3.s0, nn.d2.s0, nn.d1.s0);
#endif

//  q = q - nn
  q.d1 = -nn.d1;
  q.d2 = q.d2 - nn.d2 - AS_UINT_V((q.d1 > 0x7FFF)?1:0);
  q.d3 = q.d3 - nn.d3 - AS_UINT_V((q.d2 > 0x7FFF)?1:0);
  q.d4 = q.d4 - nn.d4 - AS_UINT_V((q.d3 > 0x7FFF)?1:0);
  q.d5 = q.d5 - nn.d5 - AS_UINT_V((q.d4 > 0x7FFF)?1:0);
  q.d6 = q.d6 - nn.d6 - AS_UINT_V((q.d5 > 0x7FFF)?1:0);
//#ifdef CHECKS_MODBASECASE
  q.d7 = q.d7 - nn.d7 - AS_UINT_V((q.d6 > 0x7FFF)?1:0); // PERF: not needed: should be zero anyway
  q.d7 &= 0x7FFF;
//#endif
  q.d1 &= 0x7FFF;
  q.d2 &= 0x7FFF;
  q.d3 &= 0x7FFF;
  q.d4 &= 0x7FFF;
  q.d5 &= 0x7FFF;
  q.d6 &= 0x7FFF;
#if (TRACE_KERNEL > 2)
  if (tid==TRACE_TID) printf("div_150_75#3.7: q=..:%x:%x:%x!%x:%x:%x:%x:%x:..\n",
        q.d8.s0, q.d7.s0, q.d6.s0, q.d5.s0, q.d4.s0, q.d3.s0, q.d2.s0, q.d1.s0);
#endif

  MODBASECASE_NONZERO_ERROR(q.d7, 3, 6, 6);

  /********** Step 4, Offset 2^0 (0*15 + 0) **********/

  qf= CONVERT_FLOAT_V(mad24(q.d6, 32768u, q.d5));
  qf= qf * 32768.0f * 32768.0f + CONVERT_FLOAT_V(mad24(q.d4, 32768u, q.d3));
  qf*= 32768.0f;

  qi=CONVERT_UINT_V(qf*nf);

  MODBASECASE_QI_ERROR(1<<22, 4, qi, 7);

  qil = qi & 0x7FFF;
  qih = (qi >> 15) & 0x7FFF;
  res->d1 += qih;
  res->d0 = qil;

#if (TRACE_KERNEL > 1)
  if (tid==TRACE_TID) printf("div_150_75#4: qf=%#G, nf=%#G, *=%#G, qi=%d=0x%x, res=%x:%x:%x:%x:%x\n",
                                 qf.s0, nf.s0, qf.s0*nf.s0, qi.s0, qi.s0, res->d4.s0, res->d3.s0, res->d2.s0, res->d1.s0, res->d0.s0);
#endif

  // skip the last part - it will change the result by one at most - we can live with a result that is off by one
  // but need to handle outstanding carries instead
  res->d2 += res->d1 >> 15;
  res->d1 &= 0x7FFF;
  res->d3 += res->d2 >> 15;
  res->d2 &= 0x7FFF;
  res->d4 += res->d3 >> 15;
  res->d3 &= 0x7FFF;

  return;

  /*******************************************************/

// nn = n * qi
  nn.d0  = mul24(n.d0, qil);
  nn.d1  = mad24(n.d0, qih, nn.d0 >> 15);
  nn.d0 &= 0x7FFF;
#if (TRACE_KERNEL > 4)
  if (tid==TRACE_TID) printf("div_150_75#4.1: nn=..:..:..:..:%x:%x\n",
        nn.d1.s0, nn.d0.s0);
#endif

  nn.d1  = mad24(n.d1, qil, nn.d1);
  nn.d2  = mad24(n.d1, qih, nn.d1 >> 15);
  nn.d1 &= 0x7FFF;
#if (TRACE_KERNEL > 4)
  if (tid==TRACE_TID) printf("div_150_75#4.2: nn=..:..:..:%x:%x:%x\n",
        nn.d2.s0, nn.d1.s0, nn.d0.s0);
#endif

  nn.d2  = mad24(n.d2, qil, nn.d2);
  nn.d3  = mad24(n.d2, qih, nn.d2 >> 15);
  nn.d2 &= 0x7FFF;
#if (TRACE_KERNEL > 4)
  if (tid==TRACE_TID) printf("div_150_75#4.3: nn=..:..:%x:%x:%x:%x\n",
        nn.d3.s0, nn.d2.s0, nn.d1.s0, nn.d0.s0);
#endif

  nn.d3  = mad24(n.d3, qil, nn.d3);
  nn.d4  = mad24(n.d3, qih, nn.d3 >> 15);
  nn.d3 &= 0x7FFF;
#if (TRACE_KERNEL > 3)
  if (tid==TRACE_TID) printf("div_150_75#4.4: nn=..:%x:%x:%x:%x:%x\n",
        nn.d4.s0, nn.d3.s0, nn.d2.s0, nn.d1.s0, nn.d0.s0);
#endif
  nn.d4  = mad24(n.d4, qil, nn.d4);
#ifdef CHECKS_MODBASECASE
  nn.d5  = mad24(n.d4, qih, nn.d4 >> 15);
#endif
  nn.d4 &= 0x7FFF;
#if (TRACE_KERNEL > 3)
  if (tid==TRACE_TID) printf("div_150_75#4.5: nn=..:%x:%x:%x:%x:%x:%x\n",
        nn.d5.s0, nn.d4.s0, nn.d3.s0, nn.d2.s0, nn.d1.s0, nn.d0.s0);
#endif

// no shift-left required

//  q = q - nn
  q.d0 = q.d0 - nn.d0;
  q.d1 = q.d1 - nn.d1 - AS_UINT_V((q.d0 > 0x7FFF)?1:0);
  q.d2 = q.d2 - nn.d2 - AS_UINT_V((q.d1 > 0x7FFF)?1:0);
  q.d3 = q.d3 - nn.d3 - AS_UINT_V((q.d2 > 0x7FFF)?1:0);
  q.d4 = q.d4 - nn.d4 - AS_UINT_V((q.d3 > 0x7FFF)?1:0);
#ifdef CHECKS_MODBASECASE
  q.d5 = q.d5 - nn.d5 - AS_UINT_V((q.d4 > 0x7FFF)?1:0); // PERF: not needed: should be zero anyway
  q.d5 &= 0x7FFF;// PERF: not needed: should be zero anyway
#endif
  q.d0 &= 0x7FFF;
  q.d1 &= 0x7FFF;
  q.d2 &= 0x7FFF;
  q.d3 &= 0x7FFF;
  q.d4 &= 0x7FFF;
#if (TRACE_KERNEL > 2)
  if (tid==TRACE_TID) printf("div_150_75#4.7: q=..:%x:%x:%x:%x!%x:%x:%x:%x:%x\n",
        q.d8.s0, q.d7.s0, q.d6.s0, q.d5.s0, q.d4.s0, q.d3.s0, q.d2.s0, q.d1.s0, q.d0.s0);
#endif
 MODBASECASE_NONZERO_ERROR(q.d5, 3, 5, 8);

/********** Step 5, final compare **********/


//  res->d0=q.d0;
//  res->d1=q.d1;
//  res->d2=q.d2;

  tmp75.d0=q.d0;
  tmp75.d1=q.d1;
  tmp75.d2=q.d2;
  tmp75.d3=q.d3;
  tmp75.d4=q.d4;
  
/*
qi is allways a little bit too small, this is OK for all steps except the last
one. Sometimes the result is a little bit bigger than n
This function also handles outstanding carries in res.
*/
  inc_if_ge_75(res, tmp75, n);
}


void mod_simple_75(int75_v * const res, const int75_v q, const int75_v n, const float_v nf
#if (TRACE_KERNEL > 1)
                  , const uint tid
#endif
#ifdef CHECKS_MODBASECASE
                  , const int bit_max64, const uint limit, __global uint * restrict modbasecase_debug
#endif
)
/*
res = q mod n
used for refinement in barrett modular multiplication
assumes q < 6n (6n includes "optional mul 2")
*/
{
  __private float_v qf;
  __private uint_v qi;
  __private int75_v nn;

  qf = CONVERT_FLOAT_V(mad24(q.d4, 32768u, q.d3));
  qf = qf * 32768.0f;
  
  qi = CONVERT_UINT_V(qf*nf);

#ifdef CHECKS_MODBASECASE
/* both barrett based kernels are made for factor candidates above 2^64,
atleast the 79bit variant fails on factor candidates less than 2^64!
Lets ignore those errors...
Factor candidates below 2^64 can occur when TFing from 2^64 to 2^65, the
first candidate in each class can be smaller than 2^64.
This is NOT an issue because those exponents should be TFed to 2^64 with a
kernel which can handle those "small" candidates before starting TF from
2^64 to 2^65. So in worst case we have a false positive which is cought
easily by the primenetserver.
The same applies to factor candidates which are bigger than 2^bit_max for the
barrett92 kernel. If the factor candidate is bigger than 2^bit_max then
usually just the correction factor is bigger than expected. There are tons
of messages that qi is to high (better: higher than expected) e.g. when trial
factoring huge exponents from 2^64 to 2^65 with the barrett92 kernel (during
selftest). The factor candidates might be as high a 2^68 in some of these
cases! This is related to the _HUGE_ blocks that mfaktc processes at once.
To make it short: let's ignore warnings/errors from factor candidates which
are "out of range".
*/
  if(n.d4 != 0 && n.d4 < (1 << bit_max64))
  {
    MODBASECASE_QI_ERROR(limit, 100, qi, 12);
  }
#endif
#if (TRACE_KERNEL > 2)
  if (tid==TRACE_TID) printf("mod_simple_75: q=%x:%x:%x:%x:%x, n=%x:%x:%x:%x:%x, nf=%.7G, qf=%#G, qi=%x\n",
        q.d4.s0, q.d3.s0, q.d2.s0, q.d1.s0, q.d0.s0, n.d4.s0, n.d3.s0, n.d2.s0, n.d1.s0, n.d0.s0, nf.s0, qf.s0, qi.s0);
#endif

// nn = n * qi
  nn.d0  = mul24(n.d0, qi);
  nn.d1  = mad24(n.d1, qi, nn.d0 >> 15);
  nn.d2  = mad24(n.d2, qi, nn.d1 >> 15);
  nn.d3  = mad24(n.d3, qi, nn.d2 >> 15);
  nn.d4  = mad24(n.d4, qi, nn.d3 >> 15);
  nn.d0 &= 0x7FFF;
  nn.d1 &= 0x7FFF;
  nn.d2 &= 0x7FFF;
  nn.d3 &= 0x7FFF;
#if (TRACE_KERNEL > 3)
  if (tid==TRACE_TID) printf("mod_simple_75#5: nn=%x:%x:%x:%x:%x\n",
        nn.d4.s0, nn.d3.s0, nn.d2.s0, nn.d1.s0, nn.d0.s0);
#endif


  res->d0 = q.d0 - nn.d0;
  res->d1 = q.d1 - nn.d1 - AS_UINT_V((res->d0 > 0x7FFF)?1:0);
  res->d2 = q.d2 - nn.d2 - AS_UINT_V((res->d1 > 0x7FFF)?1:0);
  res->d3 = q.d3 - nn.d3 - AS_UINT_V((res->d2 > 0x7FFF)?1:0);
  res->d4 = q.d4 - nn.d4 - AS_UINT_V((res->d3 > 0x7FFF)?1:0);
  res->d0 &= 0x7FFF;
  res->d1 &= 0x7FFF;
  res->d2 &= 0x7FFF;
  res->d3 &= 0x7FFF;

#if (TRACE_KERNEL > 2)
  if (tid==TRACE_TID) printf("mod_simple_75#6: res=%x:%x:%x:%x:%x\n",
        res->d4.s0, res->d3.s0, res->d2.s0, res->d1.s0, res->d0.s0);
#endif

}

__kernel void cl_barrett15_73(__private uint exp, const int75_t k_base, const __global uint * restrict k_tab, const int shiftcount,
                           const uint8 b_in, __global uint * restrict RES, const int bit_max
#ifdef CHECKS_MODBASECASE
         , __global uint * restrict modbasecase_debug
#endif
         )
/*
shiftcount is used for precomputing without mod
a is precomputed on host ONCE.

*/
{
  __private int75_t exp75;
  __private int75_v a, u, f, k;
  __private int150_v b, tmp150;
  __private int75_v tmp75;
  __private float_v ff;
  __private uint tid, bit_max_75=76-bit_max, bit_max_60=bit_max-61; //bit_max is 60 .. 73
  __private uint tmp, bit_max75_mult = 1 << bit_max_75; /* used for bit shifting... */
  __private uint_v t;

  // b > 2^60, 8 fields of the uint8 for d4-db, da and db not used in this kernel (only for bit_max > 73)
  __private int150_t bb={0, 0, 0, 0, b_in.s0, b_in.s1, b_in.s2, b_in.s3, b_in.s4, b_in.s5};

	tid = mad24((uint)get_global_id(1), (uint)get_global_size(0), (uint)get_global_id(0)) * BARRETT_VECTOR_SIZE;

  // exp75.d4=0;exp75.d3=0;  // not used, PERF: we can skip d2 as well, if we limit exp to 2^29
  exp75.d2=exp>>29;exp75.d1=(exp>>14)&0x7FFF;exp75.d0=(exp<<1)&0x7FFF;	// exp75 = 2 * exp

#if (TRACE_KERNEL > 1)
  if (tid==TRACE_TID) printf("cl_barrett15_73: exp=%d, x2=%x:%x:%x, b=%x:%x:%x:%x:%x:%x:%x:%x:0:0, k_base=%x:%x:%x:%x:%x, bit_max=%d\n",
        exp, exp75.d2, exp75.d1, exp75.d0, bb.d9, bb.d8, bb.d7, bb.d6, bb.d5, bb.d4, bb.d3, bb.d2, k_base.d4, k_base.d3, k_base.d2, k_base.d1, k_base.d0, bit_max);
#endif

#if (BARRETT_VECTOR_SIZE == 1)
  t    = k_tab[tid];
#elif (BARRETT_VECTOR_SIZE == 2)
  t.x  = k_tab[tid];
  t.y  = k_tab[tid+1];
#elif (BARRETT_VECTOR_SIZE == 3)
  t.x  = k_tab[tid];
  t.y  = k_tab[tid+1];
  t.z  = k_tab[tid+2];
#elif (BARRETT_VECTOR_SIZE == 4)
  t.x  = k_tab[tid];
  t.y  = k_tab[tid+1];
  t.z  = k_tab[tid+2];
  t.w  = k_tab[tid+3];
#elif (BARRETT_VECTOR_SIZE == 8)
  t.s0 = k_tab[tid];
  t.s1 = k_tab[tid+1];
  t.s2 = k_tab[tid+2];
  t.s3 = k_tab[tid+3];
  t.s4 = k_tab[tid+4];
  t.s5 = k_tab[tid+5];
  t.s6 = k_tab[tid+6];
  t.s7 = k_tab[tid+7];
#elif (BARRETT_VECTOR_SIZE == 16)
  t.s0 = k_tab[tid];
  t.s1 = k_tab[tid+1];
  t.s2 = k_tab[tid+2];
  t.s3 = k_tab[tid+3];
  t.s4 = k_tab[tid+4];
  t.s5 = k_tab[tid+5];
  t.s6 = k_tab[tid+6];
  t.s7 = k_tab[tid+7];
  t.s8 = k_tab[tid+8];
  t.s9 = k_tab[tid+9];
  t.sa = k_tab[tid+10];
  t.sb = k_tab[tid+11];
  t.sc = k_tab[tid+12];
  t.sd = k_tab[tid+13];
  t.se = k_tab[tid+14];
  t.sf = k_tab[tid+15];
#endif
  a.d0 = t & 0x7FFF;
  a.d1 = t >> 15;  // t is 24 bits at most

  k.d0  = mad24(a.d0, 4620u, k_base.d0);
  k.d1  = mad24(a.d1, 4620u, k_base.d1) + (k.d0 >> 15);
  k.d0 &= 0x7FFF;
  k.d2  = (k.d1 >> 15) + k_base.d2;
  k.d1 &= 0x7FFF;
  k.d3  = (k.d2 >> 15) + k_base.d3;
  k.d2 &= 0x7FFF;
  k.d4  = (k.d3 >> 15) + k_base.d4;  // PERF: k.d4 = 0, normally. Can we limit k to 2^60?
  k.d3 &= 0x7FFF;
        
#if (TRACE_KERNEL > 3)
    if (tid==TRACE_TID) printf("cl_barrett15_73: k_tab[%d]=%x, k_base+k*4620=%x:%x:%x:%x:%x\n",
        tid, t.s0, k.d4.s0, k.d3.s0, k.d2.s0, k.d1.s0, k.d0.s0);
#endif
		// f = 2 * k * exp + 1
  f.d0 = mad24(k.d0, exp75.d0, 1u);

  f.d1 = mad24(k.d1, exp75.d0, f.d0 >> 15);
  f.d1 = mad24(k.d0, exp75.d1, f.d1);
  f.d0 &= 0x7FFF;

  f.d2 = mad24(k.d2, exp75.d0, f.d1 >> 15);
  f.d2 = mad24(k.d1, exp75.d1, f.d2);
  f.d2 = mad24(k.d0, exp75.d2, f.d2);  // PERF: if we limit exp at kernel compile time to 2^29, then we can skip exp75.d2 here and above.
  f.d1 &= 0x7FFF;

  f.d3 = mad24(k.d3, exp75.d0, f.d2 >> 15);
  f.d3 = mad24(k.d2, exp75.d1, f.d3);
  f.d3 = mad24(k.d1, exp75.d2, f.d3);
//  f.d3 = mad24(k.d0, exp75.d3, f.d3);    // exp75.d3 = 0
  f.d2 &= 0x7FFF;

  f.d4 = mad24(k.d4, exp75.d0, f.d3 >> 15);  // PERF: see above
  f.d4 = mad24(k.d3, exp75.d1, f.d4);
  f.d4 = mad24(k.d2, exp75.d2, f.d4);
  f.d3 &= 0x7FFF;

#if (TRACE_KERNEL > 1)
    if (tid==TRACE_TID) printf("cl_barrett15_73: k_tab[%d]=%x, k=%x:%x:%x:%x:%x, f=%x:%x:%x:%x:%x, shift=%d\n",
        tid, t.s0, k.d4.s0, k.d3.s0, k.d2.s0, k.d1.s0, k.d0.s0, f.d4.s0, f.d3.s0, f.d2.s0, f.d1.s0, f.d0.s0, shiftcount);
#endif
/*
ff = f as float, needed in mod_192_96() and div_192_96().
Precalculated here since it is the same for all steps in the following loop */
  ff= CONVERT_FLOAT_RTP_V(mad24(f.d4, 32768u, f.d3));
  ff= ff * 32768.0f + CONVERT_FLOAT_RTP_V(f.d2);   // these are at least 30 significant bits for 60-bit FC's

  ff= as_float(0x3f7ffffd) / ff;   // we rounded ff towards plus infinity, and round all other results towards zero. 
        
  tmp = 1 << (bit_max - 61);	// tmp150 = 2^(74 + bits in f)
  
  // tmp150.d0 .. d8 =0
  // PERF: as div is only used here, use all those zeros directly in there
  //       here, no vectorized data is necessary yet: the precalculated "b" value is the same for all
  //       tmp150.d9 contains the upper part (15 bits) of a 150-bit value. The lower 135 bits are all zero implicitely

  div_150_75(&u, tmp, f, ff
#if (TRACE_KERNEL > 1)
                  , tid
#endif
#ifdef CHECKS_MODBASECASE
                  ,modbasecase_debug
#endif
);						// u = floor(tmp150 / f)

#if (TRACE_KERNEL > 2)
    if (tid==TRACE_TID) printf("cl_barrett15_73: u=%x:%x:%x:%x:%x, ff=%G\n",
        u.d4.s0, u.d3.s0, u.d2.s0, u.d1.s0, u.d0.s0, ff.s0);
#endif
    //PERF: min limit of bb? skip lower eval's?
  a.d0 = mad24(bb.d5, bit_max75_mult, (bb.d4 >> bit_max_60))&0x7FFF;			// a = b / (2^bit_max)
  a.d1 = mad24(bb.d6, bit_max75_mult, (bb.d5 >> bit_max_60))&0x7FFF;			// a = b / (2^bit_max)
  a.d2 = mad24(bb.d7, bit_max75_mult, (bb.d6 >> bit_max_60))&0x7FFF;			// a = b / (2^bit_max)
  a.d3 = mad24(bb.d8, bit_max75_mult, (bb.d7 >> bit_max_60))&0x7FFF;			// a = b / (2^bit_max)
  a.d4 = mad24(bb.d9, bit_max75_mult, (bb.d8 >> bit_max_60));		        	// a = b / (2^bit_max)

  mul_75_150_no_low3(&tmp150, a, u);					// tmp150 = (b / (2^bit_max)) * u # at least close to ;)
#if (TRACE_KERNEL > 3)
    if (tid==TRACE_TID) printf("cl_barrett15_73: a=%x:%x:%x:%x:%x * u = %x:%x:%x:%x:%x:%x:...\n",
        a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0,
        tmp150.d9.s0, tmp150.d8.s0, tmp150.d7.s0, tmp150.d6.s0, tmp150.d5.s0, tmp150.d4.s0);
#endif

  a.d0 = tmp150.d5;			// a = ((b / (2^bit_max)) * u) / (2^bit_max)
  a.d1 = tmp150.d6;			// a = ((b / (2^bit_max)) * u) / (2^bit_max)
  a.d2 = tmp150.d7;			// a = ((b / (2^bit_max)) * u) / (2^bit_max)
  a.d3 = tmp150.d8;			// a = ((b / (2^bit_max)) * u) / (2^bit_max)
  a.d4 = tmp150.d9;		        	// a = ((b / (2^bit_max)) * u) / (2^bit_max)

  mul_75(&tmp75, a, f);							// tmp75 = (((b / (2^bit_max)) * u) / (2^bit_max)) * f

#if (TRACE_KERNEL > 3)
    if (tid==TRACE_TID) printf("cl_barrett15_73: a=%x:%x:%x:%x:%x * f = %x:%x:%x:%x:%x (tmp)\n",
        a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0, tmp75.d4.s0, tmp75.d3.s0, tmp75.d2.s0, tmp75.d1.s0, tmp75.d0.s0);
#endif
    // all those bb's are 0 due to preprocessing on the host, thus always require a borrow
  tmp75.d0 = (-tmp75.d0) & 0x7FFF;
  tmp75.d1 = (-tmp75.d1 - 1) & 0x7FFF;
  tmp75.d2 = (-tmp75.d2 - 1) & 0x7FFF;
  tmp75.d3 = (-tmp75.d3 - 1) & 0x7FFF;
  tmp75.d4 = (bb.d4-tmp75.d4 - 1) & 0x7FFF;

#if (TRACE_KERNEL > 3)
    if (tid==TRACE_TID) printf("cl_barrett15_73: b=%x:%x:%x:%x:%x - tmp = %x:%x:%x:%x:%x (tmp)\n",
        bb.d4, bb.d3, bb.d2, bb.d1, bb.d0, tmp75.d4.s0, tmp75.d3.s0, tmp75.d2.s0, tmp75.d1.s0, tmp75.d0.s0);
#endif
#ifndef CHECKS_MODBASECASE
  mod_simple_75(&a, tmp75, f, ff
#if (TRACE_KERNEL > 1)
                   , tid
#endif
               );					// adjustment, plain barrett returns N = AB mod M where N < 3M!
#else
  int limit = 6;
  if(bit_max_75 == 2) limit = 8;						// bit_max == 65, due to decreased accuracy of mul_96_192_no_low2() above we need a higher threshold
  if(bit_max_75 == 3) limit = 7;						// bit_max == 66, ...
  mod_simple_75(&a, tmp75, f, ff
#if (TRACE_KERNEL > 1)
                   , tid
#endif
                   , bit_max_75, limit, modbasecase_debug);
#endif
  
#if (TRACE_KERNEL > 2)
    if (tid==TRACE_TID) printf("cl_barrett15_73: tmp=%x:%x:%x:%x:%x mod f=%x:%x:%x:%x:%x = %x:%x:%x:%x:%x (a)\n",
        tmp75.d4.s0, tmp75.d3.s0, tmp75.d2.s0, tmp75.d1.s0, tmp75.d0.s0,
        f.d4.s0, f.d3.s0, f.d2.s0, f.d1.s0, f.d0.s0, a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0 );
#endif
  exp<<= 32 - shiftcount;
  while(exp)
  {
    square_75_150(&b, a);						// b = a^2

#if (TRACE_KERNEL > 2)
    if (tid==TRACE_TID) printf("loop: exp=%.8x, a=%x:%x:%x:%x:%x ^2 = %x:%x:%x:%x:%x:%x:%x:%x:%x:%x (b)\n",
        exp, a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0,
        b.d9.s0, b.d8.s0, b.d7.s0, b.d6.s0, b.d5.s0, b.d4.s0, b.d3.s0, b.d2.s0, b.d1.s0, b.d0.s0 );
#endif
#if (TRACE_KERNEL > 14)
    // verify squaring by dividing again.
    __private float_v f1 = CONVERT_FLOAT_RTP_V(mad24(a.d4, 32768, a.d3));
    f1= f1 * 32768.0f + CONVERT_FLOAT_RTP_V(a.d2);   // f.d1 needed?

    f1= as_float(0x3f7ffffd) / f1;   // we rounded f1 towards plus infinity, and round all other results towards zero. 
    div_150_75(&tmp75, b, a, f1, tid
#ifdef CHECKS_MODBASECASE
                  ,modbasecase_debug
#endif
              );
    if (tid==TRACE_TID) printf("vrfy: b = %x:%x:%x:%x:%x:%x:%x:%x:%x:%x / a=%x:%x:%x:%x:%x = %x:%x:%x:%x:%x\n",
        b.d9.s0, b.d8.s0, b.d7.s0, b.d6.s0, b.d5.s0, b.d4.s0, b.d3.s0, b.d2.s0, b.d1.s0, b.d0.s0,
        a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0, tmp75.d4.s0, tmp75.d3.s0, tmp75.d2.s0, tmp75.d1.s0, tmp75.d0.s0);
#endif
    a.d0 = mad24(b.d5, bit_max75_mult, (b.d4 >> bit_max_60))&0x7FFF;			// a = b / (2^bit_max)
    a.d1 = mad24(b.d6, bit_max75_mult, (b.d5 >> bit_max_60))&0x7FFF;			// a = b / (2^bit_max)
    a.d2 = mad24(b.d7, bit_max75_mult, (b.d6 >> bit_max_60))&0x7FFF;			// a = b / (2^bit_max)
    a.d3 = mad24(b.d8, bit_max75_mult, (b.d7 >> bit_max_60))&0x7FFF;			// a = b / (2^bit_max)
    a.d4 = mad24(b.d9, bit_max75_mult, (b.d8 >> bit_max_60));       			// a = b / (2^bit_max)

    mul_75_150_no_low3(&tmp150, a, u);					// tmp150 = (b / (2^bit_max)) * u # at least close to ;)

#if (TRACE_KERNEL > 3)
    if (tid==TRACE_TID) printf("loop: a=%x:%x:%x:%x:%x * u = %x:%x:%x:%x:%x:%x:...\n",
        a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0,
        tmp150.d9.s0, tmp150.d8.s0, tmp150.d7.s0, tmp150.d6.s0, tmp150.d5.s0, tmp150.d4.s0);
#endif
    a.d0 = tmp150.d5;			// a = ((b / (2^bit_max)) * u) / (2^bit_max)
    a.d1 = tmp150.d6;			// a = ((b / (2^bit_max)) * u) / (2^bit_max)
    a.d2 = tmp150.d7;			// a = ((b / (2^bit_max)) * u) / (2^bit_max)
    a.d3 = tmp150.d8;			// a = ((b / (2^bit_max)) * u) / (2^bit_max)
    a.d4 = tmp150.d9;		        	// a = ((b / (2^bit_max)) * u) / (2^bit_max)
    mul_75(&tmp75, a, f);						// tmp75 = (((b / (2^bit_max)) * u) / (2^bit_max)) * f

#if (TRACE_KERNEL > 3)
    if (tid==TRACE_TID) printf("loop: a=%x:%x:%x:%x:%x * f = %x:%x:%x:%x:%x (tmp)\n",
        a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0, tmp75.d4.s0, tmp75.d3.s0, tmp75.d2.s0, tmp75.d1.s0, tmp75.d0.s0);
#endif
    tmp75.d0 = (b.d0 - tmp75.d0) & 0x7FFF;
    tmp75.d1 = (b.d1 - tmp75.d1 - AS_UINT_V((tmp75.d0 > b.d0) ? 1 : 0 ));
    tmp75.d2 = (b.d2 - tmp75.d2 - AS_UINT_V((tmp75.d1 > 0x7FFF) ? 1 : 0 ));
    tmp75.d3 = (b.d3 - tmp75.d3 - AS_UINT_V((tmp75.d2 > 0x7FFF) ? 1 : 0 ));
    tmp75.d4 = (b.d4 - tmp75.d4 - AS_UINT_V((tmp75.d3 > 0x7FFF) ? 1 : 0 ));
    tmp75.d1 &= 0x7FFF;
    tmp75.d2 &= 0x7FFF;
    tmp75.d3 &= 0x7FFF;
    tmp75.d4 &= 0x7FFF;
    
#if (TRACE_KERNEL > 3)
    if (tid==TRACE_TID) printf("loop: b=%x:%x:%x:%x:%x - tmp = %x:%x:%x:%x:%x (tmp)\n",
        b.d4.s0, b.d3.s0, b.d2.s0, b.d1.s0, b.d0.s0, tmp75.d4.s0, tmp75.d3.s0, tmp75.d2.s0, tmp75.d1.s0, tmp75.d0.s0);
#endif
    if(exp&0x80000000)shl_75(&tmp75);					// "optional multiply by 2" in Prime 95 documentation

#ifndef CHECKS_MODBASECASE
    mod_simple_75(&a, tmp75, f, ff
#if (TRACE_KERNEL > 1)
                   , tid
#endif
                 );					// adjustment, plain barrett returns N = AB mod M where N < 3M!
#else
    int limit = 6;
    if(bit_max_75 == 2) limit = 8;					// bit_max == 65, due to decreased accuracy of mul_96_192_no_low2() above we need a higher threshold
    if(bit_max_75 == 3) limit = 7;					// bit_max == 66, ...
    mod_simple_75(&a, tmp75, f, ff
#if (TRACE_KERNEL > 1)
                   , tid
#endif
                   , bit_max_75, limit, modbasecase_debug);
#endif

    exp+=exp;
#if (TRACE_KERNEL > 1)
    if (tid==TRACE_TID) printf("loopend: exp=%x, tmp=%x:%x:%x:%x:%x mod f=%x:%x:%x:%x:%x = %x:%x:%x:%x:%x (a)\n",
        exp, tmp75.d4.s0, tmp75.d3.s0, tmp75.d2.s0, tmp75.d1.s0, tmp75.d0.s0,
        f.d4.s0, f.d3.s0, f.d2.s0, f.d1.s0, f.d0.s0, a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0 );
#endif
  }


#ifndef CHECKS_MODBASECASE
  a = sub_if_gte_75(a,f);	// final adjustment in case a >= f
#else
  tmp75 = sub_if_gte_75(a,f);
  a = sub_if_gte_75(tmp75,f);
  if( tmp75.d0 != a.d0 )  // f is odd, so it is sufficient to compare the last part
  {
    printf("EEEEEK, final a was >= f\n");
  }
#endif

#if (TRACE_KERNEL > 3)
  if (tid==TRACE_TID) printf("after sub: a = %x:%x:%x:%x:%x \n",
         a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0 );
#endif
  

/* finally check if we found a factor and write the factor to RES[] */
#if (BARRETT_VECTOR_SIZE == 1)
  if( ((a.d4|a.d3|a.d2|a.d1)==0 && a.d0==1) )
  {
/* in contrast to the other kernels this barrett based kernel is only allowed for factors above 2^60 so there is no need to check for f != 1 */  
    tid=ATOMIC_INC(RES[0]);
    if(tid<10)				/* limit to 10 factors per class */
    {
      RES[tid*3 + 1]=f.d4;
      RES[tid*3 + 2]=mad24(f.d3,0x8000u, f.d2);  // that's now 30 bits per int
      RES[tid*3 + 3]=mad24(f.d1,0x8000u, f.d0);  
    }
  }
#elif (BARRETT_VECTOR_SIZE == 2)
  EVAL_RES_d(x)
  EVAL_RES_d(y)
#elif (BARRETT_VECTOR_SIZE == 3)
  EVAL_RES_d(x)
  EVAL_RES_d(y)
  EVAL_RES_d(z)
#elif (BARRETT_VECTOR_SIZE == 4)
  EVAL_RES_d(x)
  EVAL_RES_d(y)
  EVAL_RES_d(z)
  EVAL_RES_d(w)
#elif (BARRETT_VECTOR_SIZE == 8)
  EVAL_RES_d(s0)
  EVAL_RES_d(s1)
  EVAL_RES_d(s2)
  EVAL_RES_d(s3)
  EVAL_RES_d(s4)
  EVAL_RES_d(s5)
  EVAL_RES_d(s6)
  EVAL_RES_d(s7)
#elif (BARRETT_VECTOR_SIZE == 16)
  EVAL_RES_d(s0)
  EVAL_RES_d(s1)
  EVAL_RES_d(s2)
  EVAL_RES_d(s3)
  EVAL_RES_d(s4)
  EVAL_RES_d(s5)
  EVAL_RES_d(s6)
  EVAL_RES_d(s7)
  EVAL_RES_d(s8)
  EVAL_RES_d(s9)
  EVAL_RES_d(sa)
  EVAL_RES_d(sb)
  EVAL_RES_d(sc)
  EVAL_RES_d(sd)
  EVAL_RES_d(se)
  EVAL_RES_d(sf)
#endif
 
}

__kernel void cl_barrett15_68(__private uint exp, const int75_t k_base, const __global uint * restrict k_tab, const int shiftcount,
                           const uint8 b_in, __global uint * restrict RES, const int bit_max
#ifdef CHECKS_MODBASECASE
         , __global uint * restrict modbasecase_debug
#endif
         )
/*
shiftcount is used for precomputing without mod
a is precomputed on host ONCE.

*/
{
  __private int75_t exp75;
  __private int75_v a, u, f, k;
  __private int150_v b, tmp150;
  __private int75_v tmp75;
  __private float_v ff;
  __private uint tid, bit_max_75=76-bit_max, bit_max_60=bit_max-61; //bit_max is 61 .. 74
  __private uint tmp, bit_max75_mult = 1 << bit_max_75; /* used for bit shifting... */
  __private uint_v t;

  // b > 2^60, 8 fields of the uint8 for d4-db, da and db not used in this kernel (only for bit_max > 73)
  __private int150_t bb={0, 0, 0, 0, b_in.s0, b_in.s1, b_in.s2, b_in.s3, b_in.s4, b_in.s5};

	tid = mad24((uint)get_global_id(1), (uint)get_global_size(0), (uint)get_global_id(0)) * BARRETT_VECTOR_SIZE;

  // exp75.d4=0;exp75.d3=0;  // not used, PERF: we can skip d2 as well, if we limit exp to 2^29
  exp75.d2=exp>>29;exp75.d1=(exp>>14)&0x7FFF;exp75.d0=(exp<<1)&0x7FFF;	// exp75 = 2 * exp

#if (TRACE_KERNEL > 1)
  if (tid==TRACE_TID) printf("cl_barrett15_68: exp=%d, x2=%x:%x:%x, b=%x:%x:%x:%x:%x:%x:%x:%x:0:0, k_base=%x:%x:%x:%x:%x, bit_max=%d\n",
        exp, exp75.d2, exp75.d1, exp75.d0, bb.d9, bb.d8, bb.d7, bb.d6, bb.d5, bb.d4, bb.d3, bb.d2, k_base.d4, k_base.d3, k_base.d2, k_base.d1, k_base.d0, bit_max);
#endif

#if (BARRETT_VECTOR_SIZE == 1)
  t    = k_tab[tid];
#elif (BARRETT_VECTOR_SIZE == 2)
  t.x  = k_tab[tid];
  t.y  = k_tab[tid+1];
#elif (BARRETT_VECTOR_SIZE == 3)
  t.x  = k_tab[tid];
  t.y  = k_tab[tid+1];
  t.z  = k_tab[tid+2];
#elif (BARRETT_VECTOR_SIZE == 4)
  t.x  = k_tab[tid];
  t.y  = k_tab[tid+1];
  t.z  = k_tab[tid+2];
  t.w  = k_tab[tid+3];
#elif (BARRETT_VECTOR_SIZE == 8)
  t.s0 = k_tab[tid];
  t.s1 = k_tab[tid+1];
  t.s2 = k_tab[tid+2];
  t.s3 = k_tab[tid+3];
  t.s4 = k_tab[tid+4];
  t.s5 = k_tab[tid+5];
  t.s6 = k_tab[tid+6];
  t.s7 = k_tab[tid+7];
#elif (BARRETT_VECTOR_SIZE == 16)
  t.s0 = k_tab[tid];
  t.s1 = k_tab[tid+1];
  t.s2 = k_tab[tid+2];
  t.s3 = k_tab[tid+3];
  t.s4 = k_tab[tid+4];
  t.s5 = k_tab[tid+5];
  t.s6 = k_tab[tid+6];
  t.s7 = k_tab[tid+7];
  t.s8 = k_tab[tid+8];
  t.s9 = k_tab[tid+9];
  t.sa = k_tab[tid+10];
  t.sb = k_tab[tid+11];
  t.sc = k_tab[tid+12];
  t.sd = k_tab[tid+13];
  t.se = k_tab[tid+14];
  t.sf = k_tab[tid+15];
#endif
  a.d0 = t & 0x7FFF;
  a.d1 = t >> 15;  // t is 24 bits at most

  k.d0  = mad24(a.d0, 4620u, k_base.d0);
  k.d1  = mad24(a.d1, 4620u, k_base.d1) + (k.d0 >> 15);
  k.d0 &= 0x7FFF;
  k.d2  = (k.d1 >> 15) + k_base.d2;
  k.d1 &= 0x7FFF;
  k.d3  = (k.d2 >> 15) + k_base.d3;
  k.d2 &= 0x7FFF;
  k.d4  = (k.d3 >> 15) + k_base.d4;  // PERF: k.d4 = 0, normally. Can we limit k to 2^60?
  k.d3 &= 0x7FFF;
        
#if (TRACE_KERNEL > 3)
    if (tid==TRACE_TID) printf("cl_barrett15_68: k_tab[%d]=%x, k_base+k*4620=%x:%x:%x:%x:%x\n",
        tid, t.s0, k.d4.s0, k.d3.s0, k.d2.s0, k.d1.s0, k.d0.s0);
#endif
		// f = 2 * k * exp + 1
  f.d0 = mad24(k.d0, exp75.d0, 1u);

  f.d1 = mad24(k.d1, exp75.d0, f.d0 >> 15);
  f.d1 = mad24(k.d0, exp75.d1, f.d1);
  f.d0 &= 0x7FFF;

  f.d2 = mad24(k.d2, exp75.d0, f.d1 >> 15);
  f.d2 = mad24(k.d1, exp75.d1, f.d2);
  f.d2 = mad24(k.d0, exp75.d2, f.d2);  // PERF: if we limit exp at kernel compile time to 2^29, then we can skip exp75.d2 here and above.
  f.d1 &= 0x7FFF;

  f.d3 = mad24(k.d3, exp75.d0, f.d2 >> 15);
  f.d3 = mad24(k.d2, exp75.d1, f.d3);
  f.d3 = mad24(k.d1, exp75.d2, f.d3);
//  f.d3 = mad24(k.d0, exp75.d3, f.d3);    // exp75.d3 = 0
  f.d2 &= 0x7FFF;

  f.d4 = mad24(k.d4, exp75.d0, f.d3 >> 15);  // PERF: see above
  f.d4 = mad24(k.d3, exp75.d1, f.d4);
  f.d4 = mad24(k.d2, exp75.d2, f.d4);
  f.d3 &= 0x7FFF;

#if (TRACE_KERNEL > 1)
    if (tid==TRACE_TID) printf("cl_barrett15_68: k_tab[%d]=%x, k=%x:%x:%x:%x:%x, f=%x:%x:%x:%x:%x, shift=%d\n",
        tid, t.s0, k.d4.s0, k.d3.s0, k.d2.s0, k.d1.s0, k.d0.s0, f.d4.s0, f.d3.s0, f.d2.s0, f.d1.s0, f.d0.s0, shiftcount);
#endif
/*
ff = f as float, needed in mod_192_96() and div_192_96().
Precalculated here since it is the same for all steps in the following loop */
  ff= CONVERT_FLOAT_RTP_V(mad24(f.d4, 32768u, f.d3));
  ff= ff * 32768.0f + CONVERT_FLOAT_RTP_V(f.d2);   // f.d1 needed?

  ff= as_float(0x3f7ffffd) / ff;   // we rounded ff towards plus infinity, and round all other results towards zero. 
        
  tmp = 1 << (bit_max - 61);	// tmp150 = 2^(74 + bits in f)
  
  // tmp150.d0 .. d8 =0
  // PERF: as div is only used here, use all those zeros directly in there
  //       here, no vectorized data is necessary yet: the precalculated "b" value is the same for all
  //       tmp150.d9 contains the upper part (15 bits) of a 150-bit value. The lower 135 bits are all zero implicitely

  div_150_75(&u, tmp, f, ff
#if (TRACE_KERNEL > 1)
                  , tid
#endif
#ifdef CHECKS_MODBASECASE
                  ,modbasecase_debug
#endif
);						// u = floor(tmp150 / f)

#if (TRACE_KERNEL > 2)
  if (tid==TRACE_TID) printf("cl_barrett15_68: u=%x:%x:%x:%x:%x, ff=%G\n",
        u.d4.s0, u.d3.s0, u.d2.s0, u.d1.s0, u.d0.s0, ff.s0);
#endif
    //PERF: min limit of bb? skip lower eval's?
  a.d0 = mad24(bb.d5, bit_max75_mult, (bb.d4 >> bit_max_60))&0x7FFF;			// a = b / (2^bit_max)
  a.d1 = mad24(bb.d6, bit_max75_mult, (bb.d5 >> bit_max_60))&0x7FFF;			// a = b / (2^bit_max)
  a.d2 = mad24(bb.d7, bit_max75_mult, (bb.d6 >> bit_max_60))&0x7FFF;			// a = b / (2^bit_max)
  a.d3 = mad24(bb.d8, bit_max75_mult, (bb.d7 >> bit_max_60))&0x7FFF;			// a = b / (2^bit_max)
  a.d4 = mad24(bb.d9, bit_max75_mult, (bb.d8 >> bit_max_60));		        	// a = b / (2^bit_max)

  mul_75_150_no_low3(&tmp150, a, u);					// tmp150 = (b / (2^bit_max)) * u # at least close to ;)
#if (TRACE_KERNEL > 3)
    if (tid==TRACE_TID) printf("cl_barrett15_68: a=%x:%x:%x:%x:%x * u = %x:%x:%x:%x:%x:%x...\n",
        a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0,
        tmp150.d9.s0, tmp150.d8.s0, tmp150.d7.s0, tmp150.d6.s0, tmp150.d5.s0, tmp150.d4.s0);
#endif

  a.d0 = tmp150.d5;			// a = ((b / (2^bit_max)) * u) / (2^bit_max)
  a.d1 = tmp150.d6;			// a = ((b / (2^bit_max)) * u) / (2^bit_max)
  a.d2 = tmp150.d7;			// a = ((b / (2^bit_max)) * u) / (2^bit_max)
  a.d3 = tmp150.d8;			// a = ((b / (2^bit_max)) * u) / (2^bit_max)
  a.d4 = tmp150.d9;		        	// a = ((b / (2^bit_max)) * u) / (2^bit_max)

  mul_75(&tmp75, a, f);							// tmp75 = (((b / (2^bit_max)) * u) / (2^bit_max)) * f

#if (TRACE_KERNEL > 3)
    if (tid==TRACE_TID) printf("cl_barrett15_68: a=%x:%x:%x:%x:%x * f = %x:%x:%x:%x:%x (tmp)\n",
        a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0, tmp75.d4.s0, tmp75.d3.s0, tmp75.d2.s0, tmp75.d1.s0, tmp75.d0.s0);
#endif
    // bb.d0-bb.d3 are 0 due to preprocessing on the host, thus always require a borrow
  a.d0 = (-tmp75.d0) & 0x7FFF;
  a.d1 = (-tmp75.d1 - 1) & 0x7FFF;
  a.d2 = (-tmp75.d2 - 1) & 0x7FFF;
  a.d3 = (-tmp75.d3 - 1) & 0x7FFF;
  a.d4 = (bb.d4-tmp75.d4 - 1) & 0x7FFF;

#if (TRACE_KERNEL > 3)
    if (tid==TRACE_TID) printf("cl_barrett15_68: b=%x:%x:%x:%x:%x - tmp = %x:%x:%x:%x:%x (a)\n",
        bb.d4, bb.d3, bb.d2, bb.d1, bb.d0, a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0);
#endif
  
  exp<<= 32 - shiftcount;
  while(exp)
  {
    square_75_150(&b, a);						// b = a^2

#if (TRACE_KERNEL > 2)
    if (tid==TRACE_TID) printf("loop: exp=%.8x, a=%x:%x:%x:%x:%x ^2 = %x:%x:%x:%x:%x:%x:%x:%x:%x:%x (b)\n",
        exp, a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0,
        b.d9.s0, b.d8.s0, b.d7.s0, b.d6.s0, b.d5.s0, b.d4.s0, b.d3.s0, b.d2.s0, b.d1.s0, b.d0.s0 );
#endif
    a.d0 = mad24(b.d5, bit_max75_mult, (b.d4 >> bit_max_60))&0x7FFF;			// a = b / (2^bit_max)
    a.d1 = mad24(b.d6, bit_max75_mult, (b.d5 >> bit_max_60))&0x7FFF;			// a = b / (2^bit_max)
    a.d2 = mad24(b.d7, bit_max75_mult, (b.d6 >> bit_max_60))&0x7FFF;			// a = b / (2^bit_max)
    a.d3 = mad24(b.d8, bit_max75_mult, (b.d7 >> bit_max_60))&0x7FFF;			// a = b / (2^bit_max)
    a.d4 = mad24(b.d9, bit_max75_mult, (b.d8 >> bit_max_60));       			// a = b / (2^bit_max)

    mul_75_150_no_low3(&tmp150, a, u);					// tmp150 = (b / (2^bit_max)) * u # at least close to ;)

#if (TRACE_KERNEL > 3)
    if (tid==TRACE_TID) printf("loop: a=%x:%x:%x:%x:%x * u = %x:%x:%x:%x:%x:%x...\n",
        a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0,
        tmp150.d9.s0, tmp150.d8.s0, tmp150.d7.s0, tmp150.d6.s0, tmp150.d5.s0, tmp150.d4.s0);
#endif
    a.d0 = tmp150.d5;			// a = ((b / (2^bit_max)) * u) / (2^bit_max)
    a.d1 = tmp150.d6;			// a = ((b / (2^bit_max)) * u) / (2^bit_max)
    a.d2 = tmp150.d7;			// a = ((b / (2^bit_max)) * u) / (2^bit_max)
    a.d3 = tmp150.d8;			// a = ((b / (2^bit_max)) * u) / (2^bit_max)
    a.d4 = tmp150.d9;		        	// a = ((b / (2^bit_max)) * u) / (2^bit_max)

    mul_75(&tmp75, a, f);						// tmp75 = (((b / (2^bit_max)) * u) / (2^bit_max)) * f

#if (TRACE_KERNEL > 3)
    if (tid==TRACE_TID) printf("loop: a=%x:%x:%x:%x:%x * f = %x:%x:%x:%x:%x (tmp)\n",
        a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0, tmp75.d4.s0, tmp75.d3.s0, tmp75.d2.s0, tmp75.d1.s0, tmp75.d0.s0);
#endif
    a.d0 = (b.d0 - tmp75.d0) & 0x7FFF;
    a.d1 = (b.d1 - tmp75.d1 - AS_UINT_V((a.d0 > b.d0) ? 1 : 0 ));
    a.d2 = (b.d2 - tmp75.d2 - AS_UINT_V((a.d1 > b.d1) ? 1 : 0 ));
    a.d3 = (b.d3 - tmp75.d3 - AS_UINT_V((a.d2 > b.d2) ? 1 : 0 ));
    a.d4 = (b.d4 - tmp75.d4 - AS_UINT_V((a.d3 > b.d3) ? 1 : 0 ));
    a.d1 &= 0x7FFF;
    a.d2 &= 0x7FFF;
    a.d3 &= 0x7FFF;
    a.d4 &= 0x7FFF;
    
#if (TRACE_KERNEL > 3)
    if (tid==TRACE_TID) printf("loop: b=%x:%x:%x:%x:%x - tmp = %x:%x:%x:%x:%x (a)\n",
        b.d4.s0, b.d3.s0, b.d2.s0, b.d1.s0, b.d0.s0, a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0);
#endif

    if(exp&0x80000000)shl_75(&a);					// "optional multiply by 2" in Prime 95 documentation

    exp+=exp;
#if (TRACE_KERNEL > 1)
    if (tid==TRACE_TID) printf("loopend: exp=%x, tmp=%x:%x:%x:%x:%x (shl) =%x:%x:%x:%x:%x = %x:%x:%x:%x:%x (a)\n",
        exp, a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0,
        f.d4.s0, f.d3.s0, f.d2.s0, f.d1.s0, f.d0.s0, a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0 );
#endif
  }

#ifndef CHECKS_MODBASECASE
    mod_simple_75(&tmp75, a, f, ff
#if (TRACE_KERNEL > 1)
                   , tid
#endif
                 );					// adjustment, plain barrett returns N = AB mod M where N < 3M!
#else
    int limit = 6;
    if(bit_max_75 == 2) limit = 8;					// bit_max == 65, due to decreased accuracy of mul_96_192_no_low2() above we need a higher threshold
    if(bit_max_75 == 3) limit = 7;					// bit_max == 66, ...
    mod_simple_75(&tmp75, a, f, ff
#if (TRACE_KERNEL > 1)
                   , tid
#endif
                   , bit_max_75, limit, modbasecase_debug);
#endif

#ifndef CHECKS_MODBASECASE
  a = sub_if_gte_75(tmp75,f);	// final adjustment in case a >= f
#else
  tmp75 = sub_if_gte_75(tmp75,f);
  a = sub_if_gte_75(tmp75,f);
  if( tmp75.d0 != a.d0 )  // f is odd, so it is sufficient to compare the last part
  {
    printf("EEEEEK, final a was >= f\n");
  }
#endif

#if (TRACE_KERNEL > 3)
  if (tid==TRACE_TID) printf("after sub: a = %x:%x:%x:%x:%x \n",
         a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0 );
#endif
  

/* finally check if we found a factor and write the factor to RES[] */
#if (BARRETT_VECTOR_SIZE == 1)
  if( ((a.d4|a.d3|a.d2|a.d1)==0 && a.d0==1) )
  {
/* in contrast to the other kernels this barrett based kernel is only allowed for factors above 2^60 so there is no need to check for f != 1 */  
    tid=ATOMIC_INC(RES[0]);
    if(tid<10)				/* limit to 10 factors per class */
    {
      RES[tid*3 + 1]=f.d4;
      RES[tid*3 + 2]=mad24(f.d3,0x8000u, f.d2);  // that's now 30 bits per int
      RES[tid*3 + 3]=mad24(f.d1,0x8000u, f.d0);  
    }
  }
#elif (BARRETT_VECTOR_SIZE == 2)
  EVAL_RES_d(x)
  EVAL_RES_d(y)
#elif (BARRETT_VECTOR_SIZE == 3)
  EVAL_RES_d(x)
  EVAL_RES_d(y)
  EVAL_RES_d(z)
#elif (BARRETT_VECTOR_SIZE == 4)
  EVAL_RES_d(x)
  EVAL_RES_d(y)
  EVAL_RES_d(z)
  EVAL_RES_d(w)
#elif (BARRETT_VECTOR_SIZE == 8)
  EVAL_RES_d(s0)
  EVAL_RES_d(s1)
  EVAL_RES_d(s2)
  EVAL_RES_d(s3)
  EVAL_RES_d(s4)
  EVAL_RES_d(s5)
  EVAL_RES_d(s6)
  EVAL_RES_d(s7)
#elif (BARRETT_VECTOR_SIZE == 16)
  EVAL_RES_d(s0)
  EVAL_RES_d(s1)
  EVAL_RES_d(s2)
  EVAL_RES_d(s3)
  EVAL_RES_d(s4)
  EVAL_RES_d(s5)
  EVAL_RES_d(s6)
  EVAL_RES_d(s7)
  EVAL_RES_d(s8)
  EVAL_RES_d(s9)
  EVAL_RES_d(sa)
  EVAL_RES_d(sb)
  EVAL_RES_d(sc)
  EVAL_RES_d(sd)
  EVAL_RES_d(se)
  EVAL_RES_d(sf)
#endif
 
}

/****************************************
 ****************************************
 * 15-bit based 90-bit barrett-kernels
 *
 ****************************************
 ****************************************/

int90_v sub_if_gte_90(const int90_v a, const int90_v b)
/* return (a>b)?a-b:a */
{
  int90_v tmp;
  /* do the subtraction and use tmp.d5 to decide if the result is valid (if a was > b) */

  tmp.d0 = (a.d0 - b.d0) & 0x7FFF;
  tmp.d1 = (a.d1 - b.d1 - AS_UINT_V((b.d0 > a.d0) ? 1 : 0));
  tmp.d2 = (a.d2 - b.d2 - AS_UINT_V((tmp.d1 > a.d1) ? 1 : 0));
  tmp.d3 = (a.d3 - b.d3 - AS_UINT_V((tmp.d2 > a.d2) ? 1 : 0));
  tmp.d4 = (a.d4 - b.d4 - AS_UINT_V((tmp.d3 > a.d3) ? 1 : 0));
  tmp.d5 = (a.d5 - b.d5 - AS_UINT_V((tmp.d4 > a.d4) ? 1 : 0));
  tmp.d1&= 0x7FFF;
  tmp.d2&= 0x7FFF;
  tmp.d3&= 0x7FFF;
  tmp.d4&= 0x7FFF;

  tmp.d0 = (tmp.d5 > a.d5) ? a.d0 : tmp.d0;
  tmp.d1 = (tmp.d5 > a.d5) ? a.d1 : tmp.d1;
  tmp.d2 = (tmp.d5 > a.d5) ? a.d2 : tmp.d2;
  tmp.d3 = (tmp.d5 > a.d5) ? a.d3 : tmp.d3;
  tmp.d4 = (tmp.d5 > a.d5) ? a.d4 : tmp.d4; 
  tmp.d5 = (tmp.d5 > a.d5) ? a.d5 : tmp.d5; //  & 0x7FFF not necessary as tmp.d5 is <= a.d5

  return tmp;
}

void inc_if_ge_90(int90_v * const res, const int90_v a, const int90_v b)
{ /* if (a >= b) res++ */
  __private uint_v ge,tmpa0,tmpa1,tmpa2,tmpb0,tmpb1,tmpb2;

  tmpa0=mad24(a.d1, 32768u, a.d0);  // combine 2 components into one for easier comparing
  tmpa1=mad24(a.d3, 32768u, a.d2);
  tmpa2=mad24(a.d5, 32768u, a.d4);
  tmpb0=mad24(b.d1, 32768u, b.d0);
  tmpb1=mad24(b.d3, 32768u, b.d2);
  tmpb2=mad24(b.d5, 32768u, b.d4);
  ge = AS_UINT_V(((tmpa2 == tmpb2) ? ((tmpa1 == tmpb1) ? (tmpa0 >= tmpb0)
                                                      : (tmpa1 > tmpb1))
                                  : (tmpa2 > tmpb2))? 1 : 0);

  res->d0 += ge;
  res->d1 += res->d0 >> 15;
  res->d2 += res->d1 >> 15;
  res->d3 += res->d2 >> 15;
  res->d4 += res->d3 >> 15;
  res->d5 += res->d4 >> 15;
  res->d0 &= 0x7FFF;
  res->d1 &= 0x7FFF;
  res->d2 &= 0x7FFF;
  res->d3 &= 0x7FFF;
  res->d4 &= 0x7FFF;
}

void mul_90(int90_v * const res, const int90_v a, const int90_v b)
/* res = a * b 
   21 mul/mad24, 6 >>, 7 &=, 1 +*/
{
  res->d0 = mul24(a.d0, b.d0);

  res->d1 = mad24(a.d1, b.d0, res->d0 >> 15);
  res->d1 = mad24(a.d0, b.d1, res->d1);
  res->d0 &= 0x7FFF;

  res->d2 = mad24(a.d2, b.d0, res->d1 >> 15);
  res->d2 = mad24(a.d1, b.d1, res->d2);
  res->d2 = mad24(a.d0, b.d2, res->d2);
  res->d1 &= 0x7FFF;

  res->d3 = mad24(a.d3, b.d0, res->d2 >> 15);
  res->d2 &= 0x7FFF;
  res->d3 = mad24(a.d2, b.d1, res->d3);
  res->d3 = mad24(a.d1, b.d2, res->d3);
  res->d3 = mad24(a.d0, b.d3, res->d3);

  res->d4 = mad24(a.d4, b.d0, res->d3 >> 15);
  res->d3 &= 0x7FFF;
  res->d4 = mad24(a.d3, b.d1, res->d4);
  res->d4 = mad24(a.d2, b.d2, res->d4);
  res->d4 = mad24(a.d1, b.d3, res->d4);
  res->d5 = mad24(a.d5, b.d0, res->d4 >> 15);  // the 5th mad can overflow d4, need to handle carry before
  res->d4 &= 0x7FFF;
  res->d4 = mad24(a.d0, b.d4, res->d4);

  res->d5 += mad24(a.d4, b.d1, res->d4 >> 15);
  res->d4 &= 0x7FFF;
  res->d5 = mad24(a.d3, b.d2, res->d5);
  res->d5 = mad24(a.d2, b.d3, res->d5);
  res->d5 = mad24(a.d1, b.d4, res->d5);  // the 5th mad can overflow d5, but that's ok for this function.
  res->d5 = mad24(a.d0, b.d5, res->d5);  // the 6th mad can overflow d5, but that's ok for this function.
  res->d5 &= 0x7FFF;

}


void mul_90_180_no_low3(int180_v * const res, const int90_v a, const int90_v b)
/*
res ~= a * b
res.d0 to res.d2 are NOT computed. Carries to res.d3 are ignored,
too. So the digits res.d{3-b} might differ from mul_90_180().
 */
{
  // assume we have enough spare bits and can do all the carries at the very end:
  // 0x7FFF * 0x7FFF = 0x3FFF0001 = max result of mul24, up to 4 of these can be
  // added into 32-bit: 0x3FFF0001 * 4 = 0xFFFC0004, which even leaves room for
  // one (almost two) carry of 17 bit (32-bit >> 15)
  // this optimized mul 5x5 requires: 19 mul/mad24, 7 shift, 6 and, 1 add

  res->d3 = mul24(a.d3, b.d0);
  res->d3 = mad24(a.d2, b.d1, res->d3);
  res->d3 = mad24(a.d1, b.d2, res->d3);
  res->d3 = mad24(a.d0, b.d3, res->d3);

  res->d4 = mad24(a.d4, b.d0, res->d3 >> 15);
  // res->d3 &= 0x7FFF;  // d3 itself is not used, only its carry to d4 is required
  res->d4 = mad24(a.d3, b.d1, res->d4);
  res->d4 = mad24(a.d2, b.d2, res->d4);
  res->d4 = mad24(a.d1, b.d3, res->d4);
   // 5th mad24 can overflow d4, need to handle carry before: pull in the first d5 line
  res->d5 = mad24(a.d5, b.d0, res->d4 >> 15);
  res->d4 &= 0x7FFF;
  res->d4 = mad24(a.d0, b.d4, res->d4);  // 31-bit at most

  res->d5 = mad24(a.d4, b.d1, res->d4 >> 15) + res->d5;
  res->d4 &= 0x7FFF;
  res->d5 = mad24(a.d3, b.d2, res->d5);
  // handle carry after 3 of 6 mad's for d5: pull in the first d6 line
  res->d6 = mad24(a.d1, b.d5, res->d5 >> 15);
  res->d5 &= 0x7FFF;

  res->d5 = mad24(a.d2, b.d3, res->d5);
  res->d5 = mad24(a.d1, b.d4, res->d5);
  res->d5 = mad24(a.d0, b.d5, res->d5);

  res->d6 = mad24(a.d2, b.d4, res->d5 >> 15) + res->d6;
  res->d5 &= 0x7FFF;
  res->d6 = mad24(a.d3, b.d3, res->d6);
   // handle carry after 3 of 5 mad's for d6: pull in the first d7 line
  res->d7 = mad24(a.d2, b.d5, res->d6 >> 15);
  res->d6 &= 0x7FFF;

  res->d6 = mad24(a.d4, b.d2, res->d6);
  res->d6 = mad24(a.d5, b.d1, res->d6);

  res->d7 = mad24(a.d3, b.d4, res->d6 >> 15) + res->d7;
  res->d7 = mad24(a.d4, b.d3, res->d7);
  res->d7 = mad24(a.d5, b.d2, res->d7);  // in d7 we have 4 mad's, and 2 carries (both not full 17 bits)
  res->d6 &= 0x7FFF;

  res->d8 = mad24(a.d5, b.d3, res->d7 >> 15);
  res->d8 = mad24(a.d4, b.d4, res->d8);
  res->d8 = mad24(a.d3, b.d5, res->d8);
  res->d7 &= 0x7FFF;

  res->d9 = mad24(a.d5, b.d4, res->d8 >> 15);
  res->d9 = mad24(a.d4, b.d5, res->d9);
  res->d8 &= 0x7FFF;

  res->da = mad24(a.d5, b.d5, res->d9 >> 15);
  res->d9 &= 0x7FFF;

  res->db = res->da >> 15;
  res->da &= 0x7FFF;
}


void mul_90_180(int180_v * const res, const int90_v a, const int90_v b)
/*
res = a * b
 */
{
  /* this is the complete implementation, no longer used, but was the basis for
     the _no_low3 and square functions */
  // assume we have enough spare bits and can do all the carries at the very end:
  // 0x7FFF * 0x7FFF = 0x3FFF0001 = max result of mul24, up to 4 of these can be
  // added into 32-bit: 0x3FFF0001 * 4 = 0xFFFC0004, which even leaves room for
  // one (almost two) carry of 17 bit (32-bit >> 15)
  // mul 6x6 requires: 36 mul/mad24, 14 shift, 14 and, 3 add

  res->d0 = mul24(a.d0, b.d0);

  res->d1 = mad24(a.d1, b.d0, res->d0 >> 15);
  res->d1 = mad24(a.d0, b.d1, res->d1);
  res->d0 &= 0x7FFF;

  res->d2 = mad24(a.d2, b.d0, res->d1 >> 15);
  res->d2 = mad24(a.d1, b.d1, res->d2);
  res->d2 = mad24(a.d0, b.d2, res->d2);
  res->d1 &= 0x7FFF;

  res->d3 = mad24(a.d3, b.d0, res->d2 >> 15);
  res->d3 = mad24(a.d2, b.d1, res->d3);
  res->d3 = mad24(a.d1, b.d2, res->d3);
  res->d3 = mad24(a.d0, b.d3, res->d3);
  res->d2 &= 0x7FFF;

  res->d4 = mad24(a.d4, b.d0, res->d3 >> 15);
  res->d3 &= 0x7FFF;
  res->d4 = mad24(a.d3, b.d1, res->d4);
  res->d4 = mad24(a.d2, b.d2, res->d4);
  res->d4 = mad24(a.d1, b.d3, res->d4);
   // 5th mad24 can overflow d4, need to handle carry before: pull in the first d5 line
  res->d5 = mad24(a.d5, b.d0, res->d4 >> 15);
  res->d4 &= 0x7FFF;
  res->d4 = mad24(a.d0, b.d4, res->d4);  // 31-bit at most

  res->d5 = mad24(a.d4, b.d1, res->d4 >> 15) + res->d5;
  res->d4 &= 0x7FFF;
  res->d5 = mad24(a.d3, b.d2, res->d5);
  // handle carry after 3 of 6 mad's for d5: pull in the first d6 line
  res->d6 = mad24(a.d1, b.d5, res->d5 >> 15);
  res->d5 &= 0x7FFF;

  res->d5 = mad24(a.d2, b.d3, res->d5);
  res->d5 = mad24(a.d1, b.d4, res->d5);
  res->d5 = mad24(a.d0, b.d5, res->d5);

  res->d6 = mad24(a.d2, b.d4, res->d5 >> 15) + res->d6;
  res->d5 &= 0x7FFF;
  res->d6 = mad24(a.d3, b.d3, res->d6);
   // handle carry after 3 of 5 mad's for d6: pull in the first d7 line
  res->d7 = mad24(a.d2, b.d5, res->d6 >> 15);
  res->d6 &= 0x7FFF;

  res->d6 = mad24(a.d4, b.d2, res->d6);
  res->d6 = mad24(a.d5, b.d1, res->d6);

  res->d7 = mad24(a.d3, b.d4, res->d6 >> 15) + res->d7;
  res->d7 = mad24(a.d4, b.d3, res->d7);
  res->d7 = mad24(a.d5, b.d2, res->d7);  // in d7 we have 4 mad's, and 2 carries (both not full 17 bits)
  res->d6 &= 0x7FFF;

  res->d8 = mad24(a.d5, b.d3, res->d7 >> 15);
  res->d8 = mad24(a.d4, b.d4, res->d8);
  res->d8 = mad24(a.d3, b.d5, res->d8);
  res->d7 &= 0x7FFF;

  res->d9 = mad24(a.d5, b.d4, res->d8 >> 15);
  res->d9 = mad24(a.d4, b.d5, res->d9);
  res->d8 &= 0x7FFF;

  res->da = mad24(a.d5, b.d5, res->d9 >> 15);
  res->d9 &= 0x7FFF;

  res->db = res->da >> 15;
  res->da &= 0x7FFF;
}


void square_90_180(int180_v * const res, const int90_v a)
/* res = a^2 = d0^2 + 2d0d1 + d1^2 + 2d0d2 + 2(d1d2 + d0d3) + d2^2 +
               2(d0d4 + d1d3) + 2(d1d4 + d2d3) + d3^2 + 2d2d4 + 2d3d4 + d4^2
   */
{
  // assume we have enough spare bits and can do all the carries at the very end:
  // 0x7FFF * 0x7FFF = 0x3FFF0001 = max result of mul24, up to 4 of these can be
  // added into 32-bit: 0x3FFF0001 * 4 = 0xFFFC0004, which even leaves room for
  // one (almost two) carry of 17 bit (32-bit >> 15)
  // square 5x5 requires: 15 mul/mad24, 14 shift, 10 and, 1 add

  res->d0 = mul24(a.d0, a.d0);

  res->d1 = mad24(a.d1, a.d0 << 1, res->d0 >> 15);
  res->d0 &= 0x7FFF;

  res->d2 = mad24(a.d1, a.d1, res->d1 >> 15);
  res->d2 = mad24(a.d2, a.d0 << 1, res->d2);
  res->d1 &= 0x7FFF;

  res->d3 = mad24(a.d3, a.d0 << 1, res->d2 >> 15);
  res->d3 = mad24(a.d2, a.d1 << 1, res->d3);
  res->d2 &= 0x7FFF;

  res->d4 = mad24(a.d4, a.d0 << 1, res->d3 >> 15);
  res->d3 &= 0x7FFF;
  res->d4 = mad24(a.d3, a.d1 << 1, res->d4);
   // 5th mad24 can overflow d4, need to handle carry before: pull in the first d5 line
  res->d5 = mad24(a.d4, a.d1 << 1, res->d4 >> 15);
  res->d4 &= 0x7FFF;
  res->d4 = mad24(a.d2, a.d2, res->d4);  // 31-bit at most

  res->d5 = mad24(a.d3, a.d2 << 1, res->d4 >> 15) + res->d5;
  res->d4 &= 0x7FFF;
  res->d6 = mad24(a.d5, a.d1 << 1, res->d5 >> 15); // d5 carry handling before overflowing
  res->d5 &= 0x7FFF;
  res->d5 = mad24(a.d5, a.d0 << 1, res->d5);

  res->d7 = mad24(a.d5, a.d2 << 1, res->d6 >> 15); // d6 carry handling before overflowing
  res->d6 &= 0x7FFF;
  res->d6 = mad24(a.d4, a.d2 << 1, res->d5 >> 15) + res->d6;
  res->d6 = mad24(a.d3, a.d3, res->d6);
  res->d5 &= 0x7FFF;

  res->d7 = mad24(a.d4, a.d3 << 1, res->d6 >> 15) + res->d7;
  res->d6 &= 0x7FFF;

  res->d8 = mad24(a.d4, a.d4, res->d7 >> 15);
  res->d8 = mad24(a.d5, a.d3 << 1, res->d8);
  res->d7 &= 0x7FFF;

  res->d9 = mad24(a.d5, a.d4 << 1, res->d8 >> 15);
  res->d8 &= 0x7FFF;

  res->da = mad24(a.d5, a.d5, res->d9 >> 15);
  res->d9 &= 0x7FFF;

  res->db = res->da >> 15;
  res->da &= 0x7FFF;
}


void shl_90(int90_v * const a)
/* shiftleft a one bit */
{
  a->d5 = mad24(a->d5, 2u, a->d4 >> 14); // keep the extra top bit
  a->d4 = mad24(a->d4, 2u, a->d3 >> 14) & 0x7FFF;
  a->d3 = mad24(a->d3, 2u, a->d2 >> 14) & 0x7FFF;
  a->d2 = mad24(a->d2, 2u, a->d1 >> 14) & 0x7FFF;
  a->d1 = mad24(a->d1, 2u, a->d0 >> 14) & 0x7FFF;
  a->d0 = (a->d0 << 1u) & 0x7FFF;
}

void shl_180(int180_v * const a)
/* shiftleft a one bit */
{
  a->db = mad24(a->db, 2u, a->da >> 14); // keep the extra top bit
  a->da = mad24(a->da, 2u, a->d9 >> 14) & 0x7FFF;
  a->d9 = mad24(a->d9, 2u, a->d8 >> 14) & 0x7FFF;
  a->d8 = mad24(a->d8, 2u, a->d7 >> 14) & 0x7FFF;
  a->d7 = mad24(a->d7, 2u, a->d6 >> 14) & 0x7FFF;
  a->d6 = mad24(a->d6, 2u, a->d5 >> 14) & 0x7FFF;
  a->d5 = mad24(a->d5, 2u, a->d4 >> 14) & 0x7FFF;
  a->d4 = mad24(a->d4, 2u, a->d3 >> 14) & 0x7FFF;
  a->d3 = mad24(a->d3, 2u, a->d2 >> 14) & 0x7FFF;
  a->d2 = mad24(a->d2, 2u, a->d1 >> 14) & 0x7FFF;
  a->d1 = mad24(a->d1, 2u, a->d0 >> 14) & 0x7FFF;
  a->d0 = (a->d0 << 1u) & 0x7FFF;
}

void div_180_90(int90_v * const res, const uint qhi, const int90_v n, const float_v nf
#if (TRACE_KERNEL > 1)
                  , const uint tid
#endif
#ifdef CHECKS_MODBASECASE
                  , __global uint * restrict modbasecase_debug
#endif
)/* res = q / n (integer division) 
    during function entry, qhi contains the upper 30 bits of an 180-bit-value. The remaining bits are zero implicitely.
    this is not a vector, as the first value is the same for all FCs*/
    // try with 4 * 23 bit reductions: should be sufficient for 90 bits (and 86 anyways)
{
  __private float_v qf;
  __private float   qf_1;   // for the first conversion which does not need vectors yet
  
  __private uint_v qi, qil, qih;
  __private int180_v nn, q;  // PERF: reduce register usage by always using nn.d0-nn.d6 instead of shifting ?
  __private int90_v tmp90;

#if (TRACE_KERNEL > 1)
  if (tid==TRACE_TID) printf("div_180_90#0: q=%x:<150x0>, n=%x:%x:%x:%x:%x:%x, nf=%#G\n",
        qhi, n.d5.s0, n.d4.s0, n.d3.s0, n.d2.s0, n.d1.s0, n.d0.s0, nf.s0);
#endif

/********** Step 1, Offset 2^67 (4*15 + 7) **********/
  qf_1 = convert_float_rtz(qhi) * 4294967296.0f; // no vector yet, saving a few conversions!
  qf_1 = qf_1 * 32768.0f * 64.0f;

  qi=CONVERT_UINT_V(qf_1*nf);  // vectorize just here

  MODBASECASE_QI_ERROR(1<<24, 1, qi, 0);  // qi here is about 23 bits

  res->d5 = (qi >> 8);
  res->d4 = (qi << 7) & 0x7FFF;
  qil = qi & 0x7FFF;
  qih = (qi >> 15);
#if (TRACE_KERNEL > 1)
    if (tid==TRACE_TID) printf("div_180_90#1: qf=%#G, nf=%#G, *=%#G, qi=%d=0x%x, res=%x:%x:..:..:..:..\n",
                                 qf_1, nf.s0, qf_1*nf.s0, qi.s0, qi.s0, res->d5.s0, res->d4.s0);
#endif

  /*******************************************************/

// nn = n * qi
  nn.d4  = mul24(n.d0, qil);
  nn.d5  = mad24(n.d0, qih, nn.d4 >> 15);
  nn.d4 &= 0x7FFF;
#if (TRACE_KERNEL > 4)
  if (tid==TRACE_TID) printf("div_180_90#1.1: nn=..:..:..:..:..:%x:%x:..:..:..\n",
        nn.d5.s0, nn.d4.s0);
#endif

  nn.d5  = mad24(n.d1, qil, nn.d5);
  nn.d6  = mad24(n.d1, qih, nn.d5 >> 15);
  nn.d5 &= 0x7FFF;
#if (TRACE_KERNEL > 4)
  if (tid==TRACE_TID) printf("div_180_90#1.2: nn=..:..:..:..:%x:%x:%x:...\n",
        nn.d6.s0, nn.d5.s0, nn.d4.s0);
#endif

  nn.d6  = mad24(n.d2, qil, nn.d6);
  nn.d7  = mad24(n.d2, qih, nn.d6 >> 15);
  nn.d6 &= 0x7FFF;
#if (TRACE_KERNEL > 4)
  if (tid==TRACE_TID) printf("div_180_90#1.3: nn=..:..:..:%x:%x:%x:%x:...\n",
        nn.d7.s0, nn.d6.s0, nn.d5.s0, nn.d4.s0);
#endif

  nn.d7  = mad24(n.d3, qil, nn.d7);
  nn.d8  = mad24(n.d3, qih, nn.d7 >> 15);
  nn.d7 &= 0x7FFF;
#if (TRACE_KERNEL > 3)
  if (tid==TRACE_TID) printf("div_180_90#1.4: nn=..:..:%x:%x:%x:%x:%x:...\n",
        nn.d8.s0, nn.d7.s0, nn.d6.s0, nn.d5.s0, nn.d4.s0);
#endif
  nn.d8  = mad24(n.d4, qil, nn.d8);
  nn.d9  = mad24(n.d4, qih, nn.d8 >> 15);
  nn.d8 &= 0x7FFF;
#if (TRACE_KERNEL > 3)
  if (tid==TRACE_TID) printf("div_180_90#1.5: nn=..:%x:%x:%x:%x:%x:%x:...\n",
        nn.d9.s0, nn.d8.s0, nn.d7.s0, nn.d6.s0, nn.d5.s0, nn.d4.s0);
#endif
  nn.d9  = mad24(n.d5, qil, nn.d9);
  nn.da  = mad24(n.d5, qih, nn.d9 >> 15);
  nn.d9 &= 0x7FFF;
#if (TRACE_KERNEL > 3)
  if (tid==TRACE_TID) printf("div_180_90#1.6: nn=..:%x:%x:%x:%x:%x:%x:%x:...\n",
        nn.da.s0, nn.d9.s0, nn.d8.s0, nn.d7.s0, nn.d6.s0, nn.d5.s0, nn.d4.s0);
#endif

// now shift-left 5 bits
//#ifdef CHECKS_MODBASECASE
  nn.db  = nn.da >> 8;  // PERF: not needed as it will be gone anyway after sub
//#endif
  nn.da  = mad24(nn.da & 0xFF, 128u, nn.d9 >> 8);
  nn.d9  = mad24(nn.d9 & 0xFF, 128u, nn.d8 >> 8);
  nn.d8  = mad24(nn.d8 & 0xFF, 128u, nn.d7 >> 8);
  nn.d7  = mad24(nn.d7 & 0xFF, 128u, nn.d6 >> 8);
  nn.d6  = mad24(nn.d6 & 0xFF, 128u, nn.d5 >> 8);
  nn.d5  = mad24(nn.d5 & 0xFF, 128u, nn.d4 >> 8);
  nn.d4  = (nn.d4 & 0x3FF) << 7;
#if (TRACE_KERNEL > 2)
  if (tid==TRACE_TID) printf("div_180_90#1.7: nn=%x:%x:%x:%x:%x:%x:%x:%x:..:..:..\n",
        nn.db.s0, nn.da.s0, nn.d9.s0, nn.d8.s0, nn.d7.s0, nn.d6.s0, nn.d5.s0, nn.d4.s0);
#endif

//  q = q - nn, but upon function entry, qhi contains all the bits for db:da. All bits below are zero.
  q.d4 = (-nn.d4) & 0x7FFF;
  q.d5 = (-nn.d5 - AS_UINT_V((nn.d4 > 0)?1:0));
  q.d6 = (-nn.d6 - AS_UINT_V((q.d5 > 0)?1:0));
  q.d7 = (-nn.d7 - AS_UINT_V((q.d6 > 0)?1:0));
  q.d8 = (-nn.d8 - AS_UINT_V((q.d7 > 0)?1:0));
  q.d9 = (-nn.d9 - AS_UINT_V((q.d8 > 0)?1:0));
  q.da = (qhi & 0x7FFF) - nn.da - AS_UINT_V((q.d9 > 0)?1:0); 
//#ifdef CHECKS_MODBASECASE
  q.db = (qhi >> 15)    - nn.db - AS_UINT_V((q.da > 0x7FFF)?1:0); // PERF: not needed: should be zero anyway
  q.db &= 0x7FFF;
//#endif
  q.d5 &= 0x7FFF;
  q.d6 &= 0x7FFF;
  q.d7 &= 0x7FFF;
  q.d8 &= 0x7FFF;
  q.d9 &= 0x7FFF;
  q.da &= 0x7FFF;
#if (TRACE_KERNEL > 2)
  if (tid==TRACE_TID) printf("div_180_90#1.8: q=%x:%x:%x:%x:%x:%x:%x:%x:..:..\n",
        q.db.s0, q.da.s0, q.d9.s0, q.d8.s0, q.d7.s0, q.d6.s0, q.d5.s0, q.d4.s0);
#endif
  MODBASECASE_NONZERO_ERROR(q.db, 1, 9, 1);

  /********** Step 2, Offset 2^45 (3*15 + 0) **********/

  qf= CONVERT_FLOAT_V(mad24(q.da, 32768u, q.d9));
  qf= qf * 32768.0f * 32768.0f + CONVERT_FLOAT_V(mad24(q.d8, 32768u, q.d7));
  qf*= 32768.0f * 32768.0f * 4.0f;

  qi=CONVERT_UINT_V(qf*nf);

  MODBASECASE_QI_ERROR(1<<23, 2, qi, 2); // here, we need 2^23 ...

  qih = (qi >> 15);
  qil = qi & 0x7FFF;
  res->d4 += (qi >> 17);
  res->d3  = (qi >>  2) &0x7FFF;
  res->d2  = (qi << 13) &0x7FFF;
#if (TRACE_KERNEL > 1)
    if (tid==TRACE_TID) printf("div_180_90#2: qf=%#G, nf=%#G, *=%#G, qi=%d=0x%x, res=%x:%x:%x:%x:..:..\n",
                                 qf.s0, nf.s0, qf.s0*nf.s0, qi.s0, qi.s0, res->d5.s0, res->d4.s0, res->d3.s0, res->d2.s0);
#endif

  /*******************************************************/

// nn = n * qi
  nn.d3  = mul24(n.d0, qil);
  nn.d4  = mad24(n.d0, qih, nn.d3 >> 15);
  nn.d3 &= 0x7FFF;
#if (TRACE_KERNEL > 4)
  if (tid==TRACE_TID) printf("div_180_90#2.1: nn=..:..:..:..:%x:%x:..:..:..\n",
        nn.d4.s0, nn.d3.s0);
#endif

  nn.d4  = mad24(n.d1, qil, nn.d4);
  nn.d5  = mad24(n.d1, qih, nn.d4 >> 15);
  nn.d4 &= 0x7FFF;
#if (TRACE_KERNEL > 4)
  if (tid==TRACE_TID) printf("div_180_90#2.2: nn=..:..:..:%x:%x:%x:..:..:..\n",
        nn.d5.s0, nn.d4.s0, nn.d3.s0);
#endif

  nn.d5  = mad24(n.d2, qil, nn.d5);
  nn.d6  = mad24(n.d2, qih, nn.d5 >> 15);
  nn.d5 &= 0x7FFF;
#if (TRACE_KERNEL > 4)
  if (tid==TRACE_TID) printf("div_180_90#2.3: nn=..:..:%x:%x:%x:%x:..:..:..\n",
        nn.d6.s0, nn.d5.s0, nn.d4.s0, nn.d3.s0);
#endif

  nn.d6  = mad24(n.d3, qil, nn.d6);
  nn.d7  = mad24(n.d3, qih, nn.d6 >> 15);
  nn.d6 &= 0x7FFF;
#if (TRACE_KERNEL > 3)
  if (tid==TRACE_TID) printf("div_180_90#2.4: nn=..:%x:%x:%x:%x:%x:..:..:..\n",
        nn.d7.s0, nn.d6.s0, nn.d5.s0, nn.d4.s0, nn.d3.s0);
#endif

  nn.d7  = mad24(n.d4, qil, nn.d7);
  nn.d8  = mad24(n.d4, qih, nn.d7 >> 15);
  nn.d7 &= 0x7FFF;
#if (TRACE_KERNEL > 3)
  if (tid==TRACE_TID) printf("div_180_90#2.5: nn=..:%x:%x:%x:%x:%x:%x:..:..:..\n",
        nn.d8.s0, nn.d7.s0, nn.d6.s0, nn.d5.s0, nn.d4.s0, nn.d3.s0);
#endif

  nn.d8  = mad24(n.d5, qil, nn.d8);
  nn.d9  = mad24(n.d5, qih, nn.d8 >> 15);
  nn.d8 &= 0x7FFF;
#if (TRACE_KERNEL > 3)
  if (tid==TRACE_TID) printf("div_180_90#2.6: nn=..:..:%x:%x:%x:%x:%x:%x:%x:..:..:..\n",
        nn.d9.s0, nn.d8.s0, nn.d7.s0, nn.d6.s0, nn.d5.s0, nn.d4.s0, nn.d3.s0);
#endif
//#ifdef CHECKS_MODBASECASE
  nn.da  = nn.d9 >> 15;
  nn.d9 &= 0x7FFF;
//#endif

#if (TRACE_KERNEL > 3)
  if (tid==TRACE_TID) printf("div_180_90#2.7: nn=..:%x:%x:%x:%x:%x:%x:%x:%x:..:..:..\n",
        nn.da.s0, nn.d9.s0, nn.d8.s0, nn.d7.s0, nn.d6.s0, nn.d5.s0, nn.d4.s0, nn.d3.s0);
#endif

  // shift-right 2 bits
  nn.d2 = (nn.d3 << 13) & 0x7FFF;
  nn.d3 = mad24(nn.d4 & 3, 8192u, nn.d3 >> 2);
  nn.d4 = mad24(nn.d5 & 3, 8192u, nn.d4 >> 2);
  nn.d5 = mad24(nn.d6 & 3, 8192u, nn.d5 >> 2);
  nn.d6 = mad24(nn.d7 & 3, 8192u, nn.d6 >> 2);
  nn.d7 = mad24(nn.d8 & 3, 8192u, nn.d7 >> 2);
  nn.d8 = mad24(nn.d9 & 3, 8192u, nn.d8 >> 2);
  nn.d9 = mad24(nn.da & 3, 8192u, nn.d9 >> 2);
  nn.da = nn.da >> 2;

#if (TRACE_KERNEL > 4)
  if (tid==TRACE_TID) printf("div_180_90#2.8: nn=..:%x:%x:%x:%x:%x:%x:%x:%x:%x:..:..\n",
        nn.da.s0, nn.d9.s0, nn.d8.s0, nn.d7.s0, nn.d6.s0, nn.d5.s0, nn.d4.s0, nn.d3.s0, nn.d2.s0);
#endif
  //  q = q - nn; q.d2 and q.d3 are still 0
  q.d2 = (-nn.d2) & 0x7FFF;
  q.d3 = (-nn.d3 - AS_UINT_V((nn.d2 > 0)?1:0));
  q.d4 = q.d4 - nn.d4 - AS_UINT_V((q.d3 > 0x7FFF)?1:0);
  q.d5 = q.d5 - nn.d5 - AS_UINT_V((q.d4 > 0x7FFF)?1:0);
  q.d6 = q.d6 - nn.d6 - AS_UINT_V((q.d5 > 0x7FFF)?1:0);
  q.d7 = q.d7 - nn.d7 - AS_UINT_V((q.d6 > 0x7FFF)?1:0);
  q.d8 = q.d8 - nn.d8 - AS_UINT_V((q.d7 > 0x7FFF)?1:0); // PERF: not needed: should be zero anyway
//#ifdef CHECKS_MODBASECASE
  q.d9 = q.d9 - nn.d9 - AS_UINT_V((q.d8 > 0x7FFF)?1:0); // PERF: not needed: should be zero anyway
  q.d9 &= 0x7FFF;
//#endif
  q.d3 &= 0x7FFF;
  q.d4 &= 0x7FFF;
  q.d5 &= 0x7FFF;
  q.d6 &= 0x7FFF;
  q.d7 &= 0x7FFF;
  q.d8 &= 0x7FFF;
#if (TRACE_KERNEL > 2)
  if (tid==TRACE_TID) printf("div_180_90#2.9: q=..:..:%x:%x:%x:%x:%x:%x:%x:..:..\n",
        q.d9.s0, q.d8.s0, q.d7.s0, q.d6.s0, q.d5.s0, q.d4.s0, q.d3.s0);
#endif

  MODBASECASE_NONZERO_ERROR(q.da, 2, 8, 3);
  MODBASECASE_NONZERO_ERROR(q.d9, 2, 7, 4);

  /********** Step 3, Offset 2^22 (1*15 + 7) **********/

  qf= CONVERT_FLOAT_V(mad24(q.d8, 32768u, q.d7)); 
  qf= qf * 32768.0f * 32768.0f + CONVERT_FLOAT_V(mad24(q.d6, 32768u, q.d5));
  qf*= 32768.0f * 256.0f;

  qi=CONVERT_UINT_V(qf*nf);

  MODBASECASE_QI_ERROR(1<<23, 3, qi, 5);

  qih = (qi >> 15);
  qil = qi & 0x7FFF;
  res->d2 += (qi >> 8);
  res->d1  = (qi << 7) & 0x7FFF;
#if (TRACE_KERNEL > 1)
    if (tid==TRACE_TID) printf("div_180_90#3: qf=%#G, nf=%#G, *=%#G, qi=%d=0x%x, res=%x:%x:%x:%x:%x:..\n",
                                 qf.s0, nf.s0, qf.s0*nf.s0, qi.s0, qi.s0, res->d5.s0, res->d4.s0, res->d3.s0, res->d2.s0, res->d1.s0);
#endif

  /*******************************************************/

// nn = n * qi
  nn.d1  = mul24(n.d0, qil);
  nn.d2  = mad24(n.d0, qih, nn.d1 >> 15);
  nn.d1 &= 0x7FFF;
#if (TRACE_KERNEL > 4)
  if (tid==TRACE_TID) printf("div_180_90#3.1: nn=..:..:..:..:%x:%x:..\n",
        nn.d2.s0, nn.d1.s0);
#endif

  nn.d2  = mad24(n.d1, qil, nn.d2);
  nn.d3  = mad24(n.d1, qih, nn.d2 >> 15);
  nn.d2 &= 0x7FFF;
#if (TRACE_KERNEL > 4)
  if (tid==TRACE_TID) printf("div_180_90#3.2: nn=..:..:..:%x:%x:%x:..\n",
        nn.d3.s0, nn.d2.s0, nn.d1.s0);
#endif

  nn.d3  = mad24(n.d2, qil, nn.d3);
  nn.d4  = mad24(n.d2, qih, nn.d3 >> 15);
  nn.d3 &= 0x7FFF;
#if (TRACE_KERNEL > 4)
  if (tid==TRACE_TID) printf("div_180_90#3.3: nn=..:..:%x:%x:%x:%x:..\n",
        nn.d4.s0, nn.d3.s0, nn.d2.s0, nn.d1.s0);
#endif

  nn.d4  = mad24(n.d3, qil, nn.d4);
  nn.d5  = mad24(n.d3, qih, nn.d4 >> 15);
  nn.d4 &= 0x7FFF;
#if (TRACE_KERNEL > 3)
  if (tid==TRACE_TID) printf("div_180_90#3.4: nn=..:%x:%x:%x:%x:%x:..\n",
        nn.d5.s0, nn.d4.s0, nn.d3.s0, nn.d2.s0, nn.d1.s0);
#endif

  nn.d5  = mad24(n.d4, qil, nn.d5);
  nn.d6  = mad24(n.d4, qih, nn.d5 >> 15);
  nn.d5 &= 0x7FFF;
#if (TRACE_KERNEL > 3)
  if (tid==TRACE_TID) printf("div_180_90#3.5: nn=..:%x:%x:%x:%x:%x:%x:..\n",
        nn.d6.s0, nn.d5.s0, nn.d4.s0, nn.d3.s0, nn.d2.s0, nn.d1.s0);
#endif

  nn.d6  = mad24(n.d5, qil, nn.d6);
  nn.d7  = mad24(n.d5, qih, nn.d6 >> 15);
  nn.d6 &= 0x7FFF;
#if (TRACE_KERNEL > 3)
  if (tid==TRACE_TID) printf("div_180_90#3.6: nn=..:%x:%x:%x:%x:%x:%x:%x:..\n",
        nn.d7.s0, nn.d6.s0, nn.d5.s0, nn.d4.s0, nn.d3.s0, nn.d2.s0, nn.d1.s0);
#endif

// nn.d7 also contains the nn.d8 bits, will be distributed by the shifting below

// now shift-left 7 bits
  nn.d8  = nn.d7 >> 8;  // PERF: not needed as it will be gone anyway after sub
  nn.d7  = mad24(nn.d7 & 0xFF, 128u, nn.d6 >> 8);  // PERF: not needed as it will be gone anyway after sub
  nn.d6  = mad24(nn.d6 & 0xFF, 128u, nn.d5 >> 8);
  nn.d5  = mad24(nn.d5 & 0xFF, 128u, nn.d4 >> 8);
  nn.d4  = mad24(nn.d4 & 0xFF, 128u, nn.d3 >> 8);
  nn.d3  = mad24(nn.d3 & 0xFF, 128u, nn.d2 >> 8);
  nn.d2  = mad24(nn.d2 & 0xFF, 128u, nn.d1 >> 8);
  nn.d1  = (nn.d1 & 0xFF) << 7;
#if (TRACE_KERNEL > 3)
  if (tid==TRACE_TID) printf("div_180_90#3.7: nn=..:..:%x:%x:%x:%x:%x:%x:%x:%x:..\n",
        nn.d8.s0, nn.d7.s0, nn.d6.s0, nn.d5.s0, nn.d4.s0, nn.d3.s0, nn.d2.s0, nn.d1.s0);
#endif

//  q = q - nn;  q.d1 is still 0
  q.d1 = (-nn.d1) & 0x7FFF;
  q.d2 = q.d2 - nn.d2 - AS_UINT_V((nn.d1 > 0)?1:0);
  q.d3 = q.d3 - nn.d3 - AS_UINT_V((q.d2 > 0x7FFF)?1:0);
  q.d4 = q.d4 - nn.d4 - AS_UINT_V((q.d3 > 0x7FFF)?1:0);
  q.d5 = q.d5 - nn.d5 - AS_UINT_V((q.d4 > 0x7FFF)?1:0);
  q.d6 = q.d6 - nn.d6 - AS_UINT_V((q.d5 > 0x7FFF)?1:0);
  q.d7 = q.d7 - nn.d7 - AS_UINT_V((q.d6 > 0x7FFF)?1:0);
//#ifdef CHECKS_MODBASECASE
  q.d8 = q.d8 - nn.d8 - AS_UINT_V((q.d7 > 0x7FFF)?1:0); // PERF: not needed: should be zero anyway
  q.d8 &= 0x7FFF;
//#endif
  q.d2 &= 0x7FFF;
  q.d3 &= 0x7FFF;
  q.d4 &= 0x7FFF;
  q.d5 &= 0x7FFF;
  q.d6 &= 0x7FFF;
  q.d7 &= 0x7FFF;
#if (TRACE_KERNEL > 2)
  if (tid==TRACE_TID) printf("div_180_90#3.8: q=..:%x:%x:%x:%x:%x:%x:%x:%x:..\n",
        q.d8.s0, q.d7.s0, q.d6.s0, q.d5.s0, q.d4.s0, q.d3.s0, q.d2.s0, q.d1.s0);
#endif

  MODBASECASE_NONZERO_ERROR(q.d8, 3, 6, 6);

  /********** Step 4, Offset 2^0 (0*15 + 0) **********/

  qf= CONVERT_FLOAT_V(mad24(q.d7, 32768u, q.d6));
  qf= qf * 32768.0f * 32768.0f + CONVERT_FLOAT_V(mad24(q.d5, 32768u, q.d4));
  qf*= 32768.0f * 32768.0f;

  qi=CONVERT_UINT_V(qf*nf);

  MODBASECASE_QI_ERROR(1<<23, 4, qi, 7);

  qil = qi & 0x7FFF;
  qih = (qi >> 15);
  res->d1 += qih;
  res->d0 = qil;

#if (TRACE_KERNEL > 1)
    if (tid==TRACE_TID) printf("div_180_90#4: qf=%#G, nf=%#G, *=%#G, qi=%d=0x%x, res=%x:%x:%x:%x:%x:%x\n",
                                 qf.s0, nf.s0, qf.s0*nf.s0, qi.s0, qi.s0, res->d5.s0, res->d4.s0, res->d3.s0, res->d2.s0, res->d1.s0, res->d0.s0);
#endif
  
  // skip the last part - it will change the result by one at most - we can live with a result that is off by one
  // but need to handle outstanding carries instead
  res->d2 += res->d1 >> 15;
  res->d1 &= 0x7FFF;
  res->d3 += res->d2 >> 15;
  res->d2 &= 0x7FFF;
  res->d4 += res->d3 >> 15;
  res->d3 &= 0x7FFF;
  res->d5 += res->d4 >> 15;
  res->d4 &= 0x7FFF;
  return;

  /*******************************************************/

// nn = n * qi
  nn.d0  = mul24(n.d0, qil);
  nn.d1  = mad24(n.d0, qih, nn.d0 >> 15);
  nn.d0 &= 0x7FFF;
#if (TRACE_KERNEL > 4)
  if (tid==TRACE_TID) printf("div_180_90#4.1: nn=..:..:..:..:%x:%x\n",
        nn.d1.s0, nn.d0.s0);
#endif

  nn.d1  = mad24(n.d1, qil, nn.d1);
  nn.d2  = mad24(n.d1, qih, nn.d1 >> 15);
  nn.d1 &= 0x7FFF;
#if (TRACE_KERNEL > 4)
  if (tid==TRACE_TID) printf("div_180_90#4.2: nn=..:..:..:%x:%x:%x\n",
        nn.d2.s0, nn.d1.s0, nn.d0.s0);
#endif

  nn.d2  = mad24(n.d2, qil, nn.d2);
  nn.d3  = mad24(n.d2, qih, nn.d2 >> 15);
  nn.d2 &= 0x7FFF;
#if (TRACE_KERNEL > 4)
  if (tid==TRACE_TID) printf("div_180_90#4.3: nn=..:..:%x:%x:%x:%x\n",
        nn.d3.s0, nn.d2.s0, nn.d1.s0, nn.d0.s0);
#endif

  nn.d3  = mad24(n.d3, qil, nn.d3);
  nn.d4  = mad24(n.d3, qih, nn.d3 >> 15);
  nn.d3 &= 0x7FFF;
#if (TRACE_KERNEL > 3)
  if (tid==TRACE_TID) printf("div_180_90#4.4: nn=..:%x:%x:%x:%x:%x\n",
        nn.d4.s0, nn.d3.s0, nn.d2.s0, nn.d1.s0, nn.d0.s0);
#endif

  nn.d4  = mad24(n.d4, qil, nn.d4);
  nn.d5  = mad24(n.d4, qih, nn.d4 >> 15);
  nn.d4 &= 0x7FFF;
#if (TRACE_KERNEL > 3)
  if (tid==TRACE_TID) printf("div_180_90#4.5: nn=..:%x:%x:%x:%x:%x:%x\n",
        nn.d5.s0, nn.d4.s0, nn.d3.s0, nn.d2.s0, nn.d1.s0, nn.d0.s0);
#endif

  nn.d5  = mad24(n.d5, qil, nn.d5);
//#ifdef CHECKS_MODBASECASE
  nn.d6  = mad24(n.d5, qih, nn.d5 >> 15);
//#endif
  nn.d5 &= 0x7FFF;
#if (TRACE_KERNEL > 3)
  if (tid==TRACE_TID) printf("div_180_90#4.6: nn=..:%x:%x:%x:%x:%x:%x:%x\n",
        nn.d6.s0, nn.d5.s0, nn.d4.s0, nn.d3.s0, nn.d2.s0, nn.d1.s0, nn.d0.s0);
#endif

  nn.d7  = nn.d6 >> 15;
  nn.d6 &= 0x7FFF;
#if (TRACE_KERNEL > 3)
  if (tid==TRACE_TID) printf("div_180_90#4.7: nn=..:%x:%x:%x:%x:%x:%x:%x:%x\n",
        nn.d7.s0, nn.d6.s0, nn.d5.s0, nn.d4.s0, nn.d3.s0, nn.d2.s0, nn.d1.s0, nn.d0.s0);
#endif

// no shift-left required

//  q = q - nn ; q.d0 still 0
  q.d0 = (-nn.d0) & 0x7FFF;
  q.d1 = q.d1 - nn.d1 - AS_UINT_V((nn.d0 > 0)?1:0);
  q.d2 = q.d2 - nn.d2 - AS_UINT_V((q.d1 > 0x7FFF)?1:0);
  q.d3 = q.d3 - nn.d3 - AS_UINT_V((q.d2 > 0x7FFF)?1:0);
  q.d4 = q.d4 - nn.d4 - AS_UINT_V((q.d3 > 0x7FFF)?1:0);
  q.d5 = q.d5 - nn.d5 - AS_UINT_V((q.d4 > 0x7FFF)?1:0);
//#ifdef CHECKS_MODBASECASE
  q.d6 = q.d6 - nn.d6 - AS_UINT_V((q.d5 > 0x7FFF)?1:0); // PERF: not needed: should be zero anyway
  q.d6 &= 0x7FFF;// PERF: not needed: should be zero anyway
//#endif
  q.d1 &= 0x7FFF;
  q.d2 &= 0x7FFF;
  q.d3 &= 0x7FFF;
  q.d4 &= 0x7FFF;
  q.d5 &= 0x7FFF;// PERF: not needed: should be zero anyway
#if (TRACE_KERNEL > 2)
  if (tid==TRACE_TID) printf("div_180_90#4.8: q=..:%x:%x:%x!%x:%x:%x:%x:%x:%x\n",
        q.d8.s0, q.d7.s0, q.d6.s0, q.d5.s0, q.d4.s0, q.d3.s0, q.d2.s0, q.d1.s0, q.d0.s0);
#endif
 MODBASECASE_NONZERO_ERROR(q.d5, 3, 5, 8);

/********** Step 5, final compare **********/


//  res->d0=q.d0;
//  res->d1=q.d1;
//  res->d2=q.d2;

  tmp90.d0=q.d0;
  tmp90.d1=q.d1;
  tmp90.d2=q.d2;
  tmp90.d3=q.d3;
  tmp90.d4=q.d4;
  tmp90.d5=q.d5;
  
/*
qi is allways a little bit too small, this is OK for all steps except the last
one. Sometimes the result is a little bit bigger than n

*/
  inc_if_ge_90(res, tmp90, n);
#if (TRACE_KERNEL > 1)
  if (tid==TRACE_TID) printf("div_180_90: final res=%x:%x:%x:%x:%x:%x\n",
        res->d5.s0, res->d4.s0, res->d3.s0, res->d2.s0, res->d1.s0, res->d0.s0);
#endif
}


void mod_simple_90(int90_v * const res, const int90_v q, const int90_v n, const float_v nf
#if (TRACE_KERNEL > 1)
                  , const uint tid
#endif
#ifdef CHECKS_MODBASECASE
                  , const int bit_max64, const uint limit, __global uint * restrict modbasecase_debug
#endif
)
/*
res = q mod n
used for refinement in barrett modular multiplication
assumes q < 12n (12n includes "optional mul 2")
*/
{
  __private float_v qf;
  __private uint_v qi;
  __private int90_v nn;

  qf = CONVERT_FLOAT_V(mad24(q.d5, 32768u, q.d4));  // q.d3 needed?
  qf = qf * 32768.0f * 32768.0f;
  
  qi = CONVERT_UINT_V(qf*nf);

#ifdef CHECKS_MODBASECASE
/* both barrett based kernels are made for factor candidates above 2^64,
atleast the 79bit variant fails on factor candidates less than 2^64!
Lets ignore those errors...
Factor candidates below 2^64 can occur when TFing from 2^64 to 2^65, the
first candidate in each class can be smaller than 2^64.
This is NOT an issue because those exponents should be TFed to 2^64 with a
kernel which can handle those "small" candidates before starting TF from
2^64 to 2^65. So in worst case we have a false positive which is cought
easily by the primenetserver.
The same applies to factor candidates which are bigger than 2^bit_max for the
barrett92 kernel. If the factor candidate is bigger than 2^bit_max then
usually just the correction factor is bigger than expected. There are tons
of messages that qi is to high (better: higher than expected) e.g. when trial
factoring huge exponents from 2^64 to 2^65 with the barrett92 kernel (during
selftest). The factor candidates might be as high a 2^68 in some of these
cases! This is related to the _HUGE_ blocks that mfaktc processes at once.
To make it short: let's ignore warnings/errors from factor candidates which
are "out of range".
*/
  if(n.d5 != 0 && n.d5 < (1 << bit_max64))
  {
    MODBASECASE_QI_ERROR(limit, 100, qi, 12);
  }
#endif
#if (TRACE_KERNEL > 2)
  if (tid==TRACE_TID) printf("mod_simple_90: q=%x:%x:%x:%x:%x:%x, n=%x:%x:%x:%x:%x:%x, nf=%.7G, qf=%#G, qi=%x\n",
        q.d5.s0, q.d4.s0, q.d3.s0, q.d2.s0, q.d1.s0, q.d0.s0, n.d5.s0, n.d4.s0, n.d3.s0, n.d2.s0, n.d1.s0, n.d0.s0, nf.s0, qf.s0, qi.s0);
#endif

// nn = n * qi
  nn.d0  = mul24(n.d0, qi);
  nn.d1  = mad24(n.d1, qi, nn.d0 >> 15);
  nn.d2  = mad24(n.d2, qi, nn.d1 >> 15);
  nn.d3  = mad24(n.d3, qi, nn.d2 >> 15);
  nn.d4  = mad24(n.d4, qi, nn.d3 >> 15);
  nn.d5  = mad24(n.d5, qi, nn.d4 >> 15);
  nn.d0 &= 0x7FFF;
  nn.d1 &= 0x7FFF;
  nn.d2 &= 0x7FFF;
  nn.d3 &= 0x7FFF;
  nn.d4 &= 0x7FFF;
#if (TRACE_KERNEL > 3)
  if (tid==TRACE_TID) printf("mod_simple_90#5: nn=%x:%x:%x:%x:%x:%x\n",
        nn.d5.s0, nn.d4.s0, nn.d3.s0, nn.d2.s0, nn.d1.s0, nn.d0.s0);
#endif


  res->d0 = q.d0 - nn.d0;
  res->d1 = q.d1 - nn.d1 - AS_UINT_V((res->d0 > 0x7FFF)?1:0);
  res->d2 = q.d2 - nn.d2 - AS_UINT_V((res->d1 > 0x7FFF)?1:0);
  res->d3 = q.d3 - nn.d3 - AS_UINT_V((res->d2 > 0x7FFF)?1:0);
  res->d4 = q.d4 - nn.d4 - AS_UINT_V((res->d3 > 0x7FFF)?1:0);
  res->d5 = q.d5 - nn.d5 - AS_UINT_V((res->d4 > 0x7FFF)?1:0);
  res->d0 &= 0x7FFF;
  res->d1 &= 0x7FFF;
  res->d2 &= 0x7FFF;
  res->d3 &= 0x7FFF;
  res->d4 &= 0x7FFF;

#if (TRACE_KERNEL > 2)
  if (tid==TRACE_TID) printf("mod_simple_90#6: res=%x:%x:%x:%x:%x:%x\n",
        res->d5.s0, res->d4.s0, res->d3.s0, res->d2.s0, res->d1.s0, res->d0.s0);
#endif

}

__kernel void cl_barrett15_88(__private uint exp, const int75_t k_base, const __global uint * restrict k_tab, const int shiftcount,
                           const uint8 b_in, __global uint * restrict RES, const int bit_max
#ifdef CHECKS_MODBASECASE
         , __global uint * restrict modbasecase_debug
#endif
         )
/*
shiftcount is used for precomputing without mod
a is precomputed on host ONCE.

*/
{
  __private int90_t exp90;
  __private int90_v a, u, f, k;
  __private int180_v b, tmp180;
  __private int90_v tmp90;
  __private float_v ff;
  __private uint tmp, tid, bit_max_bot, bit_max_mult;
  __private uint_v t;

  // implicitely assume b > 2^60 and use the 8 fields of the uint8 for d4-db
  __private int180_t bb={0, 0, 0, 0, b_in.s0, b_in.s1, b_in.s2, b_in.s3, b_in.s4, b_in.s5, b_in.s6, b_in.s7};

	tid = mad24((uint)get_global_id(1), (uint)get_global_size(0), (uint)get_global_id(0)) * BARRETT_VECTOR_SIZE;

  // exp90.d4=0;exp90.d3=0;  // not used, PERF: we can skip d2 as well, if we limit exp to 2^29
  exp90.d2=exp>>29;exp90.d1=(exp>>14)&0x7FFF;exp90.d0=(exp<<1)&0x7FFF;	// exp90 = 2 * exp

#if (TRACE_KERNEL > 1)
  if (tid==TRACE_TID) printf("cl_barrett15_88: exp=%d, x2=%x:%x:%x, b=%x:%x:%x:%x:%x:%x:%x:%x:0:0:0:0, k_base=%x:%x:%x:%x:%x, bit_max=%d\n",
        exp, exp90.d2, exp90.d1, exp90.d0, bb.db, bb.da, bb.d9, bb.d8, bb.d7, bb.d6, bb.d5, bb.d4, k_base.d4, k_base.d3, k_base.d2, k_base.d1, k_base.d0, bit_max);
#endif

#if (BARRETT_VECTOR_SIZE == 1)
  t    = k_tab[tid];
#elif (BARRETT_VECTOR_SIZE == 2)
  t.x  = k_tab[tid];
  t.y  = k_tab[tid+1];
#elif (BARRETT_VECTOR_SIZE == 3)
  t.x  = k_tab[tid];
  t.y  = k_tab[tid+1];
  t.z  = k_tab[tid+2];
#elif (BARRETT_VECTOR_SIZE == 4)
  t.x  = k_tab[tid];
  t.y  = k_tab[tid+1];
  t.z  = k_tab[tid+2];
  t.w  = k_tab[tid+3];
#elif (BARRETT_VECTOR_SIZE == 8)
  t.s0 = k_tab[tid];
  t.s1 = k_tab[tid+1];
  t.s2 = k_tab[tid+2];
  t.s3 = k_tab[tid+3];
  t.s4 = k_tab[tid+4];
  t.s5 = k_tab[tid+5];
  t.s6 = k_tab[tid+6];
  t.s7 = k_tab[tid+7];
#elif (BARRETT_VECTOR_SIZE == 16)
  t.s0 = k_tab[tid];
  t.s1 = k_tab[tid+1];
  t.s2 = k_tab[tid+2];
  t.s3 = k_tab[tid+3];
  t.s4 = k_tab[tid+4];
  t.s5 = k_tab[tid+5];
  t.s6 = k_tab[tid+6];
  t.s7 = k_tab[tid+7];
  t.s8 = k_tab[tid+8];
  t.s9 = k_tab[tid+9];
  t.sa = k_tab[tid+10];
  t.sb = k_tab[tid+11];
  t.sc = k_tab[tid+12];
  t.sd = k_tab[tid+13];
  t.se = k_tab[tid+14];
  t.sf = k_tab[tid+15];
#endif
  a.d0 = t & 0x7FFF;
  a.d1 = t >> 15;  // t is 24 bits at most

  k.d0  = mad24(a.d0, 4620u, k_base.d0);
  k.d1  = mad24(a.d1, 4620u, k_base.d1) + (k.d0 >> 15);
  k.d0 &= 0x7FFF;
  k.d2  = (k.d1 >> 15) + k_base.d2;
  k.d1 &= 0x7FFF;
  k.d3  = (k.d2 >> 15) + k_base.d3;
  k.d2 &= 0x7FFF;
  k.d4  = (k.d3 >> 15) + k_base.d4;  // PERF: k.d4 = 0, normally. Can we limit k to 2^60?
  k.d3 &= 0x7FFF;
        
#if (TRACE_KERNEL > 3)
    if (tid==TRACE_TID) printf("cl_barrett15_88: k_tab[%d]=%x, k_base+k*4620=%x:%x:%x:%x:%x\n",
        tid, t.s0, k.d4.s0, k.d3.s0, k.d2.s0, k.d1.s0, k.d0.s0);
#endif
		// f = 2 * k * exp + 1
  f.d0 = mad24(k.d0, exp90.d0, 1u);

  f.d1 = mad24(k.d1, exp90.d0, f.d0 >> 15);
  f.d1 = mad24(k.d0, exp90.d1, f.d1);
  f.d0 &= 0x7FFF;

  f.d2 = mad24(k.d2, exp90.d0, f.d1 >> 15);
  f.d2 = mad24(k.d1, exp90.d1, f.d2);
  f.d2 = mad24(k.d0, exp90.d2, f.d2);  // PERF: if we limit exp at kernel compile time to 2^29, then we can skip exp90.d2 here and above.
  f.d1 &= 0x7FFF;

  f.d3 = mad24(k.d3, exp90.d0, f.d2 >> 15);
  f.d3 = mad24(k.d2, exp90.d1, f.d3);
  f.d3 = mad24(k.d1, exp90.d2, f.d3);
//  f.d3 = mad24(k.d0, exp90.d3, f.d3);    // exp90.d3 = 0
  f.d2 &= 0x7FFF;

  f.d4 = mad24(k.d4, exp90.d0, f.d3 >> 15);  // PERF: see above
  f.d4 = mad24(k.d3, exp90.d1, f.d4);
  f.d4 = mad24(k.d2, exp90.d2, f.d4);
  f.d3 &= 0x7FFF;

//  f.d5 = mad24(k.d5, exp90.d0, f.d4 >> 15);  // k.d5 = 0
  f.d5 = mad24(k.d4, exp90.d1, f.d4 >> 15);
  f.d5 = mad24(k.d3, exp90.d2, f.d5);
  f.d4 &= 0x7FFF;

#if (TRACE_KERNEL > 1)
    if (tid==TRACE_TID) printf("cl_barrett15_88: k_tab[%d]=%x, k=%x:%x:%x:%x:%x, f=%x:%x:%x:%x:%x:%x, shift=%d\n",
        tid, t.s0, k.d4.s0, k.d3.s0, k.d2.s0, k.d1.s0, k.d0.s0, f.d5.s0, f.d4.s0, f.d3.s0, f.d2.s0, f.d1.s0, f.d0.s0, shiftcount);
#endif
/*
ff = f as float, needed in mod_192_96() and div_192_96().
Precalculated here since it is the same for all steps in the following loop */
  ff= CONVERT_FLOAT_RTP_V(mad24(f.d5, 32768u, f.d4));
  ff= ff * 32768.0f * 32768.0f+ CONVERT_FLOAT_RTP_V(mad24(f.d3, 32768u, f.d2));   // at factor size 60 bits, this gives 30 significant bits

  //ff= as_float(0x3f7ffffb) / ff;		// just a little bit below 1.0f so we always underestimate the quotient
  //ff= as_float(0x3f7ffffd) / ff;		// just a little bit below 1.0f so we always underestimate the quotient
  ff = as_float(0x3f7ffffd) / ff;   // we rounded ff towards plus infinity, and round all other results towards zero.

  // we need u=2^(2*bit_max)/f. As bit_max is between 60 and 90, use 2 uint's to store the upper 60 bits of 2^(2*bit_max)

  tmp = 1 << (bit_max - 61);	// tmp180 = 2^(89 + bits in f)
  
  // tmp180.d7 = 0; tmp180.d6 = 0; tmp180.d5 = 0; tmp180.d4 = 0; tmp180.d3 = 0; tmp180.d2 = 0; tmp180.d1 = 0; tmp180.d0 = 0;
  // PERF: as div is only used here, use all those zeros directly in there
  //       here, no vectorized data is necessary yet: the precalculated "b" value is the same for all
  //       tmp180.db contains the upper 2 parts (30 bits) of a 180-bit value. The lower 150 bits are all zero implicitely

  div_180_90(&u, tmp, f, ff
#if (TRACE_KERNEL > 1)
                  , tid
#endif
#ifdef CHECKS_MODBASECASE
                  ,modbasecase_debug
#endif
);						// u = floor(tmp180 / f)

#if (TRACE_KERNEL > 2)
  if (tid==TRACE_TID) printf("cl_barrett15_88: u=%x:%x:%x:%x:%x:%x, ff=%G\n",
        u.d5.s0, u.d4.s0, u.d3.s0, u.d2.s0, u.d1.s0, u.d0.s0, ff.s0);
#endif

  if (bit_max > 75)  // need to distiguish how far to shift; the same branch will be taken by all threads
  {
    //bit_max is 76 .. 89
    bit_max_bot  = bit_max-76;
    bit_max_mult = 1 << (91-bit_max);

    // a.d<n> = bb.d<n+5> >> bit_max_bot + bb.d<n+6> << top_bit_max

    //PERF: min limit of bb? bit_max > 75 ==> bb > 2^150 ==> d0..d9=0
    a.d0 = mad24(bb.d6, bit_max_mult, (bb.d5 >> bit_max_bot))&0x7FFF;			// a = floor(b / 2 ^ (bits_in_f - 1))
    a.d1 = mad24(bb.d7, bit_max_mult, (bb.d6 >> bit_max_bot))&0x7FFF;
    a.d2 = mad24(bb.d8, bit_max_mult, (bb.d7 >> bit_max_bot))&0x7FFF;
    a.d3 = mad24(bb.d9, bit_max_mult, (bb.d8 >> bit_max_bot))&0x7FFF;
    a.d4 = mad24(bb.da, bit_max_mult, (bb.d9 >> bit_max_bot))&0x7FFF;
    a.d5 = mad24(bb.db, bit_max_mult, (bb.da >> bit_max_bot));
  }
  else
  {
    //bit_max is 61 .. 75
    bit_max_bot  = bit_max-61;
    bit_max_mult = 1 << (76-bit_max);

    // a.d<n> = bb.d<n+4> >> bit_max_bot + bb.d<n+5> << top_bit_max

    //PERF: min limit of bb? bit_max >= 60 ==> bb >= 2^120 ==> d0..d7=0
    a.d0 = mad24(bb.d5, bit_max_mult, (bb.d4 >> bit_max_bot))&0x7FFF;			// a = b / (2^bit_max)
    a.d1 = mad24(bb.d6, bit_max_mult, (bb.d5 >> bit_max_bot))&0x7FFF;			// a = b / (2^bit_max)
    a.d2 = mad24(bb.d7, bit_max_mult, (bb.d6 >> bit_max_bot))&0x7FFF;			// a = b / (2^bit_max)
    a.d3 = mad24(bb.d8, bit_max_mult, (bb.d7 >> bit_max_bot))&0x7FFF;			// a = b / (2^bit_max)
    a.d4 = mad24(bb.d9, bit_max_mult, (bb.d8 >> bit_max_bot))&0x7FFF;		 	// a = b / (2^bit_max)
    a.d5 = mad24(bb.da, bit_max_mult, (bb.d9 >> bit_max_bot));		       	// a = b / (2^bit_max)
  }
      // PERF: could be no_low_5
  mul_90_180_no_low3(&tmp180, a, u); // tmp180 = (b / 2 ^ (bits_in_f - 1)) * (2 ^ (89 + bits_in_f) / f)   
#if (TRACE_KERNEL > 3)
  if (tid==TRACE_TID) printf("cl_barrett15_88: a=%x:%x:%x:%x:%x:%x * u = %x:%x:%x:%x:%x:%x:%x:%x:...\n",
        a.d5.s0, a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0,
        tmp180.db.s0, tmp180.da.s0, tmp180.d9.s0, tmp180.d8.s0, tmp180.d7.s0, tmp180.d6.s0, tmp180.d5.s0, tmp180.d4.s0);
#endif

  a.d0 = tmp180.d6;		             	// a = tmp180 / 2^90, which is b / f
  a.d1 = tmp180.d7;
  a.d2 = tmp180.d8;
  a.d3 = tmp180.d9;
  a.d4 = tmp180.da;
  a.d5 = tmp180.db;

  mul_90(&tmp90, a, f);							// tmp90 = quotient * f, we only compute the low 90-bits here

#if (TRACE_KERNEL > 3)
    if (tid==TRACE_TID) printf("cl_barrett15_88: a=%x:%x:%x:%x:%x:%x * f = %x:%x:%x:%x:%x:%x (tmp)\n",
        a.d5.s0, a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0,
        tmp90.d5.s0, tmp90.d4.s0, tmp90.d3.s0, tmp90.d2.s0, tmp90.d1.s0, tmp90.d0.s0);
#endif
    // bb.d0-bb.d3 are 0
  tmp90.d0 = (-tmp90.d0) & 0x7FFF;
  tmp90.d1 = (-tmp90.d1 - AS_UINT_V((tmp90.d0 > 0) ? 1 : 0 ));
  tmp90.d2 = (-tmp90.d2 - AS_UINT_V((tmp90.d1 > 0x7FFF) ? 1 : 0 ));
  tmp90.d3 = (-tmp90.d3 - AS_UINT_V((tmp90.d2 > 0x7FFF) ? 1 : 0 ));
  tmp90.d4 = (bb.d4-tmp90.d4 - AS_UINT_V((tmp90.d3 > 0x7FFF) ? 1 : 0 ));
  tmp90.d5 = (bb.d5-tmp90.d5 - AS_UINT_V((tmp90.d4 > 0x7FFF) ? 1 : 0 ));
  tmp90.d1 &= 0x7FFF;
  tmp90.d2 &= 0x7FFF;
  tmp90.d3 &= 0x7FFF;
  tmp90.d4 &= 0x7FFF;
  tmp90.d5 &= 0x7FFF;

#if (TRACE_KERNEL > 3)
  if (tid==TRACE_TID) printf("cl_barrett15_88: b=%x:%x:%x:%x:%x:%x - tmp = %x:%x:%x:%x:%x:%x (tmp)\n",
        bb.d5, bb.d4, bb.d3, bb.d2, bb.d1, bb.d0, tmp90.d5.s0, tmp90.d4.s0, tmp90.d3.s0, tmp90.d2.s0, tmp90.d1.s0, tmp90.d0.s0);
#endif
    ///
    ///// here it starts to become different between the 3 6x15bit kernels
    ///
#ifndef CHECKS_MODBASECASE
  mod_simple_90(&a, tmp90, f, ff
#if (TRACE_KERNEL > 1)
                   , tid
#endif
               );					// adjustment, plain barrett returns N = AB mod M where N < 3M!
#else
  int limit = 6;
  if(bit_max_90 == 2) limit = 8;						// bit_max == 65, due to decreased accuracy of mul_96_192_no_low2() above we need a higher threshold
  if(bit_max_90 == 3) limit = 7;						// bit_max == 66, ...
  mod_simple_90(&a, tmp90, f, ff
#if (TRACE_KERNEL > 1)
                   , tid
#endif
                   , bit_max_90, limit, modbasecase_debug);
#endif
  
#if (TRACE_KERNEL > 2)
    if (tid==TRACE_TID) printf("cl_barrett15_88: tmp=%x:%x:%x:%x:%x:%x mod f=%x:%x:%x:%x:%x:%x = %x:%x:%x:%x:%x:%x (a)\n",
        tmp90.d5.s0, tmp90.d4.s0, tmp90.d3.s0, tmp90.d2.s0, tmp90.d1.s0, tmp90.d0.s0,
        f.d5.s0, f.d4.s0, f.d3.s0, f.d2.s0, f.d1.s0, f.d0.s0, a.d5.s0, a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0 );
#endif
  exp<<= 32 - shiftcount;
  while(exp)
  {
    square_90_180(&b, a);						// b = a^2

#if (TRACE_KERNEL > 2)
    if (tid==TRACE_TID) printf("loop: exp=%.8x, a=%x:%x:%x:%x:%x:%x ^2 = %x:%x:%x:%x:%x:%x:%x:%x:%x:%x:%x:%x (b)\n",
        exp, a.d5.s0, a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0,
        b.db.s0, b.da.s0, b.d9.s0, b.d8.s0, b.d7.s0, b.d6.s0, b.d5.s0, b.d4.s0, b.d3.s0, b.d2.s0, b.d1.s0, b.d0.s0 );
#endif
    if (bit_max > 75)  // need to distiguish how far to shift
    {
      a.d0 = mad24(b.d6, bit_max_mult, (b.d5 >> bit_max_bot))&0x7FFF;			// a = b / (2^bit_max)
      a.d1 = mad24(b.d7, bit_max_mult, (b.d6 >> bit_max_bot))&0x7FFF;			// a = b / (2^bit_max)
      a.d2 = mad24(b.d8, bit_max_mult, (b.d7 >> bit_max_bot))&0x7FFF;			// a = b / (2^bit_max)
      a.d3 = mad24(b.d9, bit_max_mult, (b.d8 >> bit_max_bot))&0x7FFF;			// a = b / (2^bit_max)
      a.d4 = mad24(b.da, bit_max_mult, (b.d9 >> bit_max_bot))&0x7FFF;		 	// a = b / (2^bit_max)
      a.d5 = mad24(b.db, bit_max_mult, (b.da >> bit_max_bot));		       	// a = b / (2^bit_max)
    }
    else
    {
      a.d0 = mad24(b.d5, bit_max_mult, (b.d4 >> bit_max_bot))&0x7FFF;			// a = b / (2^bit_max)
      a.d1 = mad24(b.d6, bit_max_mult, (b.d5 >> bit_max_bot))&0x7FFF;			// a = b / (2^bit_max)
      a.d2 = mad24(b.d7, bit_max_mult, (b.d6 >> bit_max_bot))&0x7FFF;			// a = b / (2^bit_max)
      a.d3 = mad24(b.d8, bit_max_mult, (b.d7 >> bit_max_bot))&0x7FFF;			// a = b / (2^bit_max)
      a.d4 = mad24(b.d9, bit_max_mult, (b.d8 >> bit_max_bot))&0x7FFF;		 	// a = b / (2^bit_max)
      a.d5 = mad24(b.da, bit_max_mult, (b.d9 >> bit_max_bot));		       	// a = b / (2^bit_max)
    }
      // PERF: could be no_low_5
    mul_90_180_no_low3(&tmp180, a, u); // tmp180 = (b / 2 ^ (bits_in_f - 1)) * (2 ^ (89 + bits_in_f) / f)   
#if (TRACE_KERNEL > 3)
    if (tid==TRACE_TID) printf("loop: a=%x:%x:%x:%x:%x:%x * u = %x:%x:%x:%x:%x:%x:%x:%x:...\n",
        a.d5.s0, a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0,
        tmp180.db.s0, tmp180.da.s0, tmp180.d9.s0, tmp180.d8.s0, tmp180.d7.s0, tmp180.d6.s0, tmp180.d5.s0, tmp180.d4.s0);
#endif

    a.d0 = tmp180.d6;		             	// a = tmp180 / 2^90, which is b / f
    a.d1 = tmp180.d7;
    a.d2 = tmp180.d8;
    a.d3 = tmp180.d9;
    a.d4 = tmp180.da;
    a.d5 = tmp180.db;

    mul_90(&tmp90, a, f);							// tmp90 = quotient * f, we only compute the low 90-bits here

#if (TRACE_KERNEL > 3)
    if (tid==TRACE_TID) printf("loop: a=%x:%x:%x:%x:%x:%x * f = %x:%x:%x:%x:%x:%x (tmp)\n",
        a.d5.s0, a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0, tmp90.d5.s0, tmp90.d4.s0, tmp90.d3.s0, tmp90.d2.s0, tmp90.d1.s0, tmp90.d0.s0);
#endif
    tmp90.d0 = (b.d0 - tmp90.d0) & 0x7FFF;
    tmp90.d1 = (b.d1 - tmp90.d1 - AS_UINT_V((tmp90.d0 > b.d0) ? 1 : 0 ));
    tmp90.d2 = (b.d2 - tmp90.d2 - AS_UINT_V((tmp90.d1 > b.d1) ? 1 : 0 ));
    tmp90.d3 = (b.d3 - tmp90.d3 - AS_UINT_V((tmp90.d2 > b.d2) ? 1 : 0 ));
    tmp90.d4 = (b.d4 - tmp90.d4 - AS_UINT_V((tmp90.d3 > b.d3) ? 1 : 0 ));
    tmp90.d5 = (b.d5 - tmp90.d5 - AS_UINT_V((tmp90.d4 > b.d4) ? 1 : 0 ));
    tmp90.d1 &= 0x7FFF;
    tmp90.d2 &= 0x7FFF;
    tmp90.d3 &= 0x7FFF;
    tmp90.d4 &= 0x7FFF;
    tmp90.d5 &= 0x7FFF;
    
#if (TRACE_KERNEL > 3)
    if (tid==TRACE_TID) printf("loop: b=%x:%x:%x:%x:%x:%x - tmp = %x:%x:%x:%x:%x:%x (tmp)\n",
        b.d5.s0, b.d4.s0, b.d3.s0, b.d2.s0, b.d1.s0, b.d0.s0, tmp90.d5.s0, tmp90.d4.s0, tmp90.d3.s0, tmp90.d2.s0, tmp90.d1.s0, tmp90.d0.s0);
#endif
    if(exp&0x80000000)shl_90(&tmp90);			// "optional multiply by 2" in Prime 95 documentation, can be up to 91 bits (16 in tmp90.d5)

#ifndef CHECKS_MODBASECASE
    mod_simple_90(&a, tmp90, f, ff   // can handle 91 bits tmp90
#if (TRACE_KERNEL > 1)
                   , tid
#endif
                 );					// adjustment, plain barrett returns N = AB mod M where N < 3M!
#else
    int limit = 6;
    if(bit_max_90 == 2) limit = 8;					// bit_max == 65, due to decreased accuracy of mul_96_192_no_low2() above we need a higher threshold
    if(bit_max_90 == 3) limit = 7;					// bit_max == 66, ...
    mod_simple_90(&a, tmp90, f, ff
#if (TRACE_KERNEL > 1)
                   , tid
#endif
                   , bit_max_90, limit, modbasecase_debug);
#endif

    exp+=exp;
#if (TRACE_KERNEL > 1)
    if (tid==TRACE_TID) printf("loopend: exp=%x, tmp=%x:%x:%x:%x:%x:%x mod f=%x:%x:%x:%x:%x:%x = %x:%x:%x:%x:%x:%x (a)\n",
        exp, tmp90.d5.s0, tmp90.d4.s0, tmp90.d3.s0, tmp90.d2.s0, tmp90.d1.s0, tmp90.d0.s0,
        f.d5.s0, f.d4.s0, f.d3.s0, f.d2.s0, f.d1.s0, f.d0.s0, a.d5.s0, a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0 );
#endif
  }


#ifndef CHECKS_MODBASECASE
  a = sub_if_gte_90(a,f);	// final adjustment in case a >= f
#else
  tmp90 = sub_if_gte_90(a,f);
  a = sub_if_gte_90(tmp90,f);
  if( tmp90.d0 != a.d0 )  // f is odd, so it is sufficient to compare the last part
  {
    printf("EEEEEK, final a was >= f\n");
  }
#endif
  ///
  ////// starting from here, the 3 6x15bit kernels are the same again
  ///
#if (TRACE_KERNEL > 3)
  if (tid==TRACE_TID) printf("after sub: a = %x:%x:%x:%x:%x:%x \n",
         a.d5.s0, a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0 );
#endif
  

/* finally check if we found a factor and write the factor to RES[] */
#if (BARRETT_VECTOR_SIZE == 1)
  if( ((a.d5|a.d4|a.d3|a.d2|a.d1)==0 && a.d0==1) )
  {
/* in contrast to the other kernels this barrett based kernel is only allowed for factors above 2^60 so there is no need to check for f != 1 */  
    tid=ATOMIC_INC(RES[0]);
    if(tid<10)				/* limit to 10 factors per class */
    {
      RES[tid*3 + 1]=mad24(f.d5,0x8000u, f.d4);
      RES[tid*3 + 2]=mad24(f.d3,0x8000u, f.d2);  // that's now 30 bits per int
      RES[tid*3 + 3]=mad24(f.d1,0x8000u, f.d0);  
    }
  }
#elif (BARRETT_VECTOR_SIZE == 2)
  EVAL_RES_90(x)
  EVAL_RES_90(y)
#elif (BARRETT_VECTOR_SIZE == 3)
  EVAL_RES_90(x)
  EVAL_RES_90(y)
  EVAL_RES_90(z)
#elif (BARRETT_VECTOR_SIZE == 4)
  EVAL_RES_90(x)
  EVAL_RES_90(y)
  EVAL_RES_90(z)
  EVAL_RES_90(w)
#elif (BARRETT_VECTOR_SIZE == 8)
  EVAL_RES_90(s0)
  EVAL_RES_90(s1)
  EVAL_RES_90(s2)
  EVAL_RES_90(s3)
  EVAL_RES_90(s4)
  EVAL_RES_90(s5)
  EVAL_RES_90(s6)
  EVAL_RES_90(s7)
#elif (BARRETT_VECTOR_SIZE == 16)
  EVAL_RES_90(s0)
  EVAL_RES_90(s1)
  EVAL_RES_90(s2)
  EVAL_RES_90(s3)
  EVAL_RES_90(s4)
  EVAL_RES_90(s5)
  EVAL_RES_90(s6)
  EVAL_RES_90(s7)
  EVAL_RES_90(s8)
  EVAL_RES_90(s9)
  EVAL_RES_90(sa)
  EVAL_RES_90(sb)
  EVAL_RES_90(sc)
  EVAL_RES_90(sd)
  EVAL_RES_90(se)
  EVAL_RES_90(sf)
#endif
 
}

__kernel void cl_barrett15_83(__private uint exp, const int75_t k_base, const __global uint * restrict k_tab, const int shiftcount,
                           const uint8 b_in, __global uint * restrict RES, const int bit_max
#ifdef CHECKS_MODBASECASE
         , __global uint * restrict modbasecase_debug
#endif
         )
/*
shiftcount is used for precomputing without mod
a is precomputed on host ONCE.

*/
{
  __private int90_t exp90;
  __private int90_v a, u, f, k;
  __private int180_v b, tmp180;
  __private int90_v tmp90;
  __private float_v ff;
  __private uint tmp, tid, bit_max_bot, bit_max_mult;
  __private uint_v t;

  // implicitely assume b > 2^60 and use the 8 fields of the uint8 for d4-db
  __private int180_t bb={0, 0, 0, 0, b_in.s0, b_in.s1, b_in.s2, b_in.s3, b_in.s4, b_in.s5, b_in.s6, b_in.s7};

	tid = mad24((uint)get_global_id(1), (uint)get_global_size(0), (uint)get_global_id(0)) * BARRETT_VECTOR_SIZE;

  // exp90.d4=0;exp90.d3=0;  // not used, PERF: we can skip d2 as well, if we limit exp to 2^29
  exp90.d2=exp>>29;exp90.d1=(exp>>14)&0x7FFF;exp90.d0=(exp<<1)&0x7FFF;	// exp90 = 2 * exp

#if (TRACE_KERNEL > 1)
  if (tid==TRACE_TID) printf("cl_barrett15_83: exp=%d, x2=%x:%x:%x, b=%x:%x:%x:%x:%x:%x:%x:%x:0:0:0:0, k_base=%x:%x:%x:%x:%x, bit_max=%d\n",
        exp, exp90.d2, exp90.d1, exp90.d0, bb.db, bb.da, bb.d9, bb.d8, bb.d7, bb.d6, bb.d5, bb.d4, k_base.d4, k_base.d3, k_base.d2, k_base.d1, k_base.d0, bit_max);
#endif

#if (BARRETT_VECTOR_SIZE == 1)
  t    = k_tab[tid];
#elif (BARRETT_VECTOR_SIZE == 2)
  t.x  = k_tab[tid];
  t.y  = k_tab[tid+1];
#elif (BARRETT_VECTOR_SIZE == 3)
  t.x  = k_tab[tid];
  t.y  = k_tab[tid+1];
  t.z  = k_tab[tid+2];
#elif (BARRETT_VECTOR_SIZE == 4)
  t.x  = k_tab[tid];
  t.y  = k_tab[tid+1];
  t.z  = k_tab[tid+2];
  t.w  = k_tab[tid+3];
#elif (BARRETT_VECTOR_SIZE == 8)
  t.s0 = k_tab[tid];
  t.s1 = k_tab[tid+1];
  t.s2 = k_tab[tid+2];
  t.s3 = k_tab[tid+3];
  t.s4 = k_tab[tid+4];
  t.s5 = k_tab[tid+5];
  t.s6 = k_tab[tid+6];
  t.s7 = k_tab[tid+7];
#elif (BARRETT_VECTOR_SIZE == 16)
  t.s0 = k_tab[tid];
  t.s1 = k_tab[tid+1];
  t.s2 = k_tab[tid+2];
  t.s3 = k_tab[tid+3];
  t.s4 = k_tab[tid+4];
  t.s5 = k_tab[tid+5];
  t.s6 = k_tab[tid+6];
  t.s7 = k_tab[tid+7];
  t.s8 = k_tab[tid+8];
  t.s9 = k_tab[tid+9];
  t.sa = k_tab[tid+10];
  t.sb = k_tab[tid+11];
  t.sc = k_tab[tid+12];
  t.sd = k_tab[tid+13];
  t.se = k_tab[tid+14];
  t.sf = k_tab[tid+15];
#endif
  a.d0 = t & 0x7FFF;
  a.d1 = t >> 15;  // t is 24 bits at most

  k.d0  = mad24(a.d0, 4620u, k_base.d0);
  k.d1  = mad24(a.d1, 4620u, k_base.d1) + (k.d0 >> 15);
  k.d0 &= 0x7FFF;
  k.d2  = (k.d1 >> 15) + k_base.d2;
  k.d1 &= 0x7FFF;
  k.d3  = (k.d2 >> 15) + k_base.d3;
  k.d2 &= 0x7FFF;
  k.d4  = (k.d3 >> 15) + k_base.d4;  // PERF: k.d4 = 0, normally. Can we limit k to 2^60?
  k.d3 &= 0x7FFF;
        
#if (TRACE_KERNEL > 3)
    if (tid==TRACE_TID) printf("cl_barrett15_83: k_tab[%d]=%x, k_base+k*4620=%x:%x:%x:%x:%x\n",
        tid, t.s0, k.d4.s0, k.d3.s0, k.d2.s0, k.d1.s0, k.d0.s0);
#endif
		// f = 2 * k * exp + 1
  f.d0 = mad24(k.d0, exp90.d0, 1u);

  f.d1 = mad24(k.d1, exp90.d0, f.d0 >> 15);
  f.d1 = mad24(k.d0, exp90.d1, f.d1);
  f.d0 &= 0x7FFF;

  f.d2 = mad24(k.d2, exp90.d0, f.d1 >> 15);
  f.d2 = mad24(k.d1, exp90.d1, f.d2);
  f.d2 = mad24(k.d0, exp90.d2, f.d2);  // PERF: if we limit exp at kernel compile time to 2^29, then we can skip exp90.d2 here and above.
  f.d1 &= 0x7FFF;

  f.d3 = mad24(k.d3, exp90.d0, f.d2 >> 15);
  f.d3 = mad24(k.d2, exp90.d1, f.d3);
  f.d3 = mad24(k.d1, exp90.d2, f.d3);
//  f.d3 = mad24(k.d0, exp90.d3, f.d3);    // exp90.d3 = 0
  f.d2 &= 0x7FFF;

  f.d4 = mad24(k.d4, exp90.d0, f.d3 >> 15);  // PERF: see above
  f.d4 = mad24(k.d3, exp90.d1, f.d4);
  f.d4 = mad24(k.d2, exp90.d2, f.d4);
  f.d3 &= 0x7FFF;

//  f.d5 = mad24(k.d5, exp90.d0, f.d4 >> 15);  // k.d5 = 0
  f.d5 = mad24(k.d4, exp90.d1, f.d4 >> 15);
  f.d5 = mad24(k.d3, exp90.d2, f.d5);
  f.d4 &= 0x7FFF;

#if (TRACE_KERNEL > 1)
    if (tid==TRACE_TID) printf("cl_barrett15_83: k_tab[%d]=%x, k=%x:%x:%x:%x:%x, f=%x:%x:%x:%x:%x:%x, shift=%d\n",
        tid, t.s0, k.d4.s0, k.d3.s0, k.d2.s0, k.d1.s0, k.d0.s0, f.d5.s0, f.d4.s0, f.d3.s0, f.d2.s0, f.d1.s0, f.d0.s0, shiftcount);
#endif
/*
ff = f as float, needed in mod_192_96() and div_192_96().
Precalculated here since it is the same for all steps in the following loop */
  ff= CONVERT_FLOAT_RTP_V(mad24(f.d5, 32768u, f.d4));
  ff= ff * 32768.0f * 32768.0f+ CONVERT_FLOAT_RTP_V(mad24(f.d3, 32768u, f.d2));   // f.d1 needed?

  //ff= as_float(0x3f7ffffb) / ff;		// just a little bit below 1.0f so we always underestimate the quotient
  //ff= as_float(0x3f7ffffd) / ff;		// just a little bit below 1.0f so we always underestimate the quotient
  ff = as_float(0x3f7ffffd) / ff;   // we rounded ff towards plus infinity, and round all other results towards zero. 

  // we need u=2^(2*bit_max)/f. As bit_max is between 60 and 90, use 2 uint's to store the upper 60 bits of 2^(2*bit_max)

  tmp = 1 << (bit_max - 61);	// tmp180 = 2^(89 + bits in f)
  
  // tmp180.d7 = 0; tmp180.d6 = 0; tmp180.d5 = 0; tmp180.d4 = 0; tmp180.d3 = 0; tmp180.d2 = 0; tmp180.d1 = 0; tmp180.d0 = 0;
  // PERF: as div is only used here, use all those zeros directly in there
  //       here, no vectorized data is necessary yet: the precalculated "b" value is the same for all
  //       tmp180.db contains the upper 2 parts (30 bits) of a 180-bit value. The lower 150 bits are all zero implicitely

  div_180_90(&u, tmp, f, ff
#if (TRACE_KERNEL > 1)
                  , tid
#endif
#ifdef CHECKS_MODBASECASE
                  ,modbasecase_debug
#endif
);						// u = floor(tmp180 / f)

#if (TRACE_KERNEL > 2)
  if (tid==TRACE_TID) printf("cl_barrett15_83: u=%x:%x:%x:%x:%x:%x, ff=%G\n",
        u.d5.s0, u.d4.s0, u.d3.s0, u.d2.s0, u.d1.s0, u.d0.s0, ff.s0);
#endif

  if (bit_max > 75)  // need to distiguish how far to shift; the same branch will be taken by all threads
  {
    //bit_max is 76 .. 89
    bit_max_bot  = bit_max-76;
    bit_max_mult = 1 << (91-bit_max);

    // a.d<n> = bb.d<n+5> >> bit_max_bot + bb.d<n+6> << top_bit_max

    //PERF: min limit of bb? bit_max > 75 ==> bb > 2^150 ==> d0..d9=0
    a.d0 = mad24(bb.d6, bit_max_mult, (bb.d5 >> bit_max_bot))&0x7FFF;			// a = floor(b / 2 ^ (bits_in_f - 1))
    a.d1 = mad24(bb.d7, bit_max_mult, (bb.d6 >> bit_max_bot))&0x7FFF;
    a.d2 = mad24(bb.d8, bit_max_mult, (bb.d7 >> bit_max_bot))&0x7FFF;
    a.d3 = mad24(bb.d9, bit_max_mult, (bb.d8 >> bit_max_bot))&0x7FFF;
    a.d4 = mad24(bb.da, bit_max_mult, (bb.d9 >> bit_max_bot))&0x7FFF;
    a.d5 = mad24(bb.db, bit_max_mult, (bb.da >> bit_max_bot));
  }
  else
  {
    //bit_max is 61 .. 75
    bit_max_bot  = bit_max-61;
    bit_max_mult = 1 << (76-bit_max);

    // a.d<n> = bb.d<n+4> >> bit_max_bot + bb.d<n+5> << top_bit_max

    //PERF: min limit of bb? bit_max >= 60 ==> bb >= 2^120 ==> d0..d7=0
    a.d0 = mad24(bb.d5, bit_max_mult, (bb.d4 >> bit_max_bot))&0x7FFF;			// a = b / (2^bit_max)
    a.d1 = mad24(bb.d6, bit_max_mult, (bb.d5 >> bit_max_bot))&0x7FFF;			// a = b / (2^bit_max)
    a.d2 = mad24(bb.d7, bit_max_mult, (bb.d6 >> bit_max_bot))&0x7FFF;			// a = b / (2^bit_max)
    a.d3 = mad24(bb.d8, bit_max_mult, (bb.d7 >> bit_max_bot))&0x7FFF;			// a = b / (2^bit_max)
    a.d4 = mad24(bb.d9, bit_max_mult, (bb.d8 >> bit_max_bot))&0x7FFF;		 	// a = b / (2^bit_max)
    a.d5 = mad24(bb.da, bit_max_mult, (bb.d9 >> bit_max_bot));		       	// a = b / (2^bit_max)
  }
      // PERF: could be no_low_5
  mul_90_180_no_low3(&tmp180, a, u); // tmp180 = (b / 2 ^ (bits_in_f - 1)) * (2 ^ (89 + bits_in_f) / f)   
#if (TRACE_KERNEL > 3)
    if (tid==TRACE_TID) printf("cl_barrett15_83: a=%x:%x:%x:%x:%x:%x * u = %x:%x:%x:%x:%x:%x:%x:%x:...\n",
        a.d5.s0, a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0,
        tmp180.db.s0, tmp180.da.s0, tmp180.d9.s0, tmp180.d8.s0, tmp180.d7.s0, tmp180.d6.s0, tmp180.d5.s0, tmp180.d4.s0);
#endif

  a.d0 = tmp180.d6;		             	// a = tmp180 / 2^90, which is b / f
  a.d1 = tmp180.d7;
  a.d2 = tmp180.d8;
  a.d3 = tmp180.d9;
  a.d4 = tmp180.da;
  a.d5 = tmp180.db;

  mul_90(&tmp90, a, f);							// tmp90 = (((b / (2^bit_max)) * u) / (2^bit_max)) * f

#if (TRACE_KERNEL > 3)
    if (tid==TRACE_TID) printf("cl_barrett15_83: a=%x:%x:%x:%x:%x:%x * f = %x:%x:%x:%x:%x:%x (tmp)\n",
        a.d5.s0, a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0,
        tmp90.d5.s0, tmp90.d4.s0, tmp90.d3.s0, tmp90.d2.s0, tmp90.d1.s0, tmp90.d0.s0);
#endif
  // bb.d0-bb.d3 are 0
  a.d0 = (-tmp90.d0) & 0x7FFF;
  a.d1 = (-tmp90.d1 - AS_UINT_V((a.d0 > 0) ? 1 : 0 ));
  a.d2 = (-tmp90.d2 - AS_UINT_V((a.d1 > 0x7FFF) ? 1 : 0 ));
  a.d3 = (-tmp90.d3 - AS_UINT_V((a.d2 > 0x7FFF) ? 1 : 0 ));
  a.d4 = (bb.d4-tmp90.d4 - AS_UINT_V((a.d3 > 0x7FFF) ? 1 : 0 ));
  a.d5 = (bb.d5-tmp90.d5 - AS_UINT_V((a.d4 > 0x7FFF) ? 1 : 0 ));
  a.d1 &= 0x7FFF;
  a.d2 &= 0x7FFF;
  a.d3 &= 0x7FFF;
  a.d4 &= 0x7FFF;
  a.d5 &= 0x7FFF;

#if (TRACE_KERNEL > 3)
    if (tid==TRACE_TID) printf("cl_barrett15_83: b=%x:%x:%x:%x:%x:%x - tmp = %x:%x:%x:%x:%x:%x (a)\n",
        bb.d5, bb.d4, bb.d3, bb.d2, bb.d1, bb.d0, a.d5.s0, a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0);
#endif
    ///
    ///// here it starts to become different between the 3 6x15bit kernels
    ///
  exp<<= 32 - shiftcount;
  while(exp)
  {
    square_90_180(&b, a);						// b = a^2
#if (TRACE_KERNEL > 2)
    if (tid==TRACE_TID) printf("loop: exp=%.8x, a=%x:%x:%x:%x:%x:%x ^2 = %x:%x:%x:%x:%x:%x:%x:%x:%x:%x:%x:%x (b)\n",
        exp, a.d5.s0, a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0,
        b.db.s0, b.da.s0, b.d9.s0, b.d8.s0, b.d7.s0, b.d6.s0, b.d5.s0, b.d4.s0, b.d3.s0, b.d2.s0, b.d1.s0, b.d0.s0 );
#endif
    if(exp&0x80000000)
    {
      shl_180(&b);					// "optional multiply by 2" in Prime 95 documentation

#if (TRACE_KERNEL > 3)
      if (tid==TRACE_TID) printf("loop: shl: %x:%x:%x:%x:%x:%x:%x:%x:%x:%x:%x:%x (b)\n",
        b.db.s0, b.da.s0, b.d9.s0, b.d8.s0, b.d7.s0, b.d6.s0, b.d5.s0, b.d4.s0, b.d3.s0, b.d2.s0, b.d1.s0, b.d0.s0 );
#endif
    }

    if (bit_max > 75)  // need to distiguish how far to shift
    {
      a.d0 = mad24(b.d6, bit_max_mult, (b.d5 >> bit_max_bot))&0x7FFF;			// a = b / (2^bit_max)
      a.d1 = mad24(b.d7, bit_max_mult, (b.d6 >> bit_max_bot))&0x7FFF;			// a = b / (2^bit_max)
      a.d2 = mad24(b.d8, bit_max_mult, (b.d7 >> bit_max_bot))&0x7FFF;			// a = b / (2^bit_max)
      a.d3 = mad24(b.d9, bit_max_mult, (b.d8 >> bit_max_bot))&0x7FFF;			// a = b / (2^bit_max)
      a.d4 = mad24(b.da, bit_max_mult, (b.d9 >> bit_max_bot))&0x7FFF;		 	// a = b / (2^bit_max)
      a.d5 = mad24(b.db, bit_max_mult, (b.da >> bit_max_bot));		       	// a = b / (2^bit_max)
    }
    else
    {
      a.d0 = mad24(b.d5, bit_max_mult, (b.d4 >> bit_max_bot))&0x7FFF;			// a = b / (2^bit_max)
      a.d1 = mad24(b.d6, bit_max_mult, (b.d5 >> bit_max_bot))&0x7FFF;			// a = b / (2^bit_max)
      a.d2 = mad24(b.d7, bit_max_mult, (b.d6 >> bit_max_bot))&0x7FFF;			// a = b / (2^bit_max)
      a.d3 = mad24(b.d8, bit_max_mult, (b.d7 >> bit_max_bot))&0x7FFF;			// a = b / (2^bit_max)
      a.d4 = mad24(b.d9, bit_max_mult, (b.d8 >> bit_max_bot))&0x7FFF;		 	// a = b / (2^bit_max)
      a.d5 = mad24(b.da, bit_max_mult, (b.d9 >> bit_max_bot));		       	// a = b / (2^bit_max)
    }
      // PERF: could be no_low_5
    mul_90_180_no_low3(&tmp180, a, u); // tmp180 = (b / 2 ^ (bits_in_f - 1)) * (2 ^ (89 + bits_in_f) / f)   

#if (TRACE_KERNEL > 3)
    if (tid==TRACE_TID) printf("loop: a=%x:%x:%x:%x:%x:%x * u = %x:%x:%x:%x:%x:%x:%x:%x:...\n",
        a.d5.s0, a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0,
        tmp180.db.s0, tmp180.da.s0, tmp180.d9.s0, tmp180.d8.s0, tmp180.d7.s0, tmp180.d6.s0, tmp180.d5.s0, tmp180.d4.s0);
#endif
    a.d0 = tmp180.d6;		             	// a = tmp180 / 2^90, which is b / f
    a.d1 = tmp180.d7;
    a.d2 = tmp180.d8;
    a.d3 = tmp180.d9;
    a.d4 = tmp180.da;
    a.d5 = tmp180.db;

    mul_90(&tmp90, a, f);						// tmp90 = (((b / (2^bit_max)) * u) / (2^bit_max)) * f

#if (TRACE_KERNEL > 3)
    if (tid==TRACE_TID) printf("loop: a=%x:%x:%x:%x:%x:%x * f = %x:%x:%x:%x:%x:%x (tmp)\n",
        a.d5.s0, a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0, tmp90.d5.s0, tmp90.d4.s0, tmp90.d3.s0, tmp90.d2.s0, tmp90.d1.s0, tmp90.d0.s0);
#endif
    // PERF: faster to compare against 0x7fff instead of b.dx?
    a.d0 = (b.d0 - tmp90.d0) & 0x7FFF;
    a.d1 = (b.d1 - tmp90.d1 - AS_UINT_V((a.d0 > b.d0) ? 1 : 0 ));
    a.d2 = (b.d2 - tmp90.d2 - AS_UINT_V((a.d1 > b.d1) ? 1 : 0 ));
    a.d3 = (b.d3 - tmp90.d3 - AS_UINT_V((a.d2 > b.d2) ? 1 : 0 ));
    a.d4 = (b.d4 - tmp90.d4 - AS_UINT_V((a.d3 > b.d3) ? 1 : 0 ));
    a.d5 = (b.d5 - tmp90.d5 - AS_UINT_V((a.d4 > b.d4) ? 1 : 0 ));
    a.d1 &= 0x7FFF;
    a.d2 &= 0x7FFF;
    a.d3 &= 0x7FFF;
    a.d4 &= 0x7FFF;
    a.d5 &= 0x7FFF;
    
#if (TRACE_KERNEL > 3)
    if (tid==TRACE_TID) printf("loop: b=%x:%x:%x:%x:%x:%x - tmp = %x:%x:%x:%x:%x:%x (a)\n",
        b.d5.s0, b.d4.s0, b.d3.s0, b.d2.s0, b.d1.s0, b.d0.s0, a.d5.s0, a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0);
#endif

    exp+=exp;
  }

#ifndef CHECKS_MODBASECASE
    mod_simple_90(&tmp90, a, f, ff
#if (TRACE_KERNEL > 1)
                   , tid
#endif
                 );					// adjustment, plain barrett returns N = AB mod M where N < 3M!
#else
    int limit = 6;
    if(bit_max_90 == 2) limit = 8;					// bit_max == 65, due to decreased accuracy of mul_96_192_no_low2() above we need a higher threshold
    if(bit_max_90 == 3) limit = 7;					// bit_max == 66, ...
    mod_simple_90(&tmp90, a, f, ff
#if (TRACE_KERNEL > 1)
                   , tid
#endif
                   , bit_max_90, limit, modbasecase_debug);
#endif

#ifndef CHECKS_MODBASECASE
  a = sub_if_gte_90(tmp90,f);	// final adjustment in case a >= f
#else
  tmp90 = sub_if_gte_90(tmp90,f);
  a = sub_if_gte_90(tmp90,f);
  if( tmp90.d0 != a.d0 )  // f is odd, so it is sufficient to compare the last part
  {
    printf("EEEEEK, final a was >= f\n");
  }
#endif

#if (TRACE_KERNEL > 3)
  if (tid==TRACE_TID) printf("after sub: a = %x:%x:%x:%x:%x:%x \n",
         a.d5.s0, a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0 );
#endif
  

/* finally check if we found a factor and write the factor to RES[] */
#if (BARRETT_VECTOR_SIZE == 1)
  if( ((a.d5|a.d4|a.d3|a.d2|a.d1)==0 && a.d0==1) )
  {
/* in contrast to the other kernels this barrett based kernel is only allowed for factors above 2^60 so there is no need to check for f != 1 */  
    tid=ATOMIC_INC(RES[0]);
    if(tid<10)				/* limit to 10 factors per class */
    {
      RES[tid*3 + 1]=mad24(f.d5,0x8000u, f.d4);
      RES[tid*3 + 2]=mad24(f.d3,0x8000u, f.d2);  // that's now 30 bits per int
      RES[tid*3 + 3]=mad24(f.d1,0x8000u, f.d0);  
    }
  }
#elif (BARRETT_VECTOR_SIZE == 2)
  EVAL_RES_90(x)
  EVAL_RES_90(y)
#elif (BARRETT_VECTOR_SIZE == 3)
  EVAL_RES_90(x)
  EVAL_RES_90(y)
  EVAL_RES_90(z)
#elif (BARRETT_VECTOR_SIZE == 4)
  EVAL_RES_90(x)
  EVAL_RES_90(y)
  EVAL_RES_90(z)
  EVAL_RES_90(w)
#elif (BARRETT_VECTOR_SIZE == 8)
  EVAL_RES_90(s0)
  EVAL_RES_90(s1)
  EVAL_RES_90(s2)
  EVAL_RES_90(s3)
  EVAL_RES_90(s4)
  EVAL_RES_90(s5)
  EVAL_RES_90(s6)
  EVAL_RES_90(s7)
#elif (BARRETT_VECTOR_SIZE == 16)
  EVAL_RES_90(s0)
  EVAL_RES_90(s1)
  EVAL_RES_90(s2)
  EVAL_RES_90(s3)
  EVAL_RES_90(s4)
  EVAL_RES_90(s5)
  EVAL_RES_90(s6)
  EVAL_RES_90(s7)
  EVAL_RES_90(s8)
  EVAL_RES_90(s9)
  EVAL_RES_90(sa)
  EVAL_RES_90(sb)
  EVAL_RES_90(sc)
  EVAL_RES_90(sd)
  EVAL_RES_90(se)
  EVAL_RES_90(sf)
#endif
 
}


__kernel void cl_barrett15_82(__private uint exp, const int75_t k_base, const __global uint * restrict k_tab, const int shiftcount,
                           const uint8 b_in, __global uint * restrict RES, const int bit_max
#ifdef CHECKS_MODBASECASE
         , __global uint * restrict modbasecase_debug
#endif
         )
/*
shiftcount is used for precomputing without mod
a is precomputed on host ONCE.

*/
{
  __private int90_t exp90;
  __private int90_v a, u, f, k;
  __private int180_v b, tmp180;
  __private int90_v tmp90;
  __private float_v ff;
  __private uint tmp, tid, bit_max_bot, bit_max_mult;
  __private uint_v t;

  // implicitely assume b > 2^60 and use the 8 fields of the uint8 for d4-db
  __private int180_t bb={0, 0, 0, 0, b_in.s0, b_in.s1, b_in.s2, b_in.s3, b_in.s4, b_in.s5, b_in.s6, b_in.s7};

	tid = mad24((uint)get_global_id(1), (uint)get_global_size(0), (uint)get_global_id(0)) * BARRETT_VECTOR_SIZE;

  // exp90.d4=0;exp90.d3=0;  // not used, PERF: we can skip d2 as well, if we limit exp to 2^29
  exp90.d2=exp>>29;exp90.d1=(exp>>14)&0x7FFF;exp90.d0=(exp<<1)&0x7FFF;	// exp90 = 2 * exp

#if (TRACE_KERNEL > 1)
  if (tid==TRACE_TID) printf("cl_barrett15_82: exp=%d, x2=%x:%x:%x, b=%x:%x:%x:%x:%x:%x:%x:%x:0:0:0:0, k_base=%x:%x:%x:%x:%x, bit_max=%d\n",
        exp, exp90.d2, exp90.d1, exp90.d0, bb.db, bb.da, bb.d9, bb.d8, bb.d7, bb.d6, bb.d5, bb.d4, k_base.d4, k_base.d3, k_base.d2, k_base.d1, k_base.d0, bit_max);
#endif

#if (BARRETT_VECTOR_SIZE == 1)
  t    = k_tab[tid];
#elif (BARRETT_VECTOR_SIZE == 2)
  t.x  = k_tab[tid];
  t.y  = k_tab[tid+1];
#elif (BARRETT_VECTOR_SIZE == 3)
  t.x  = k_tab[tid];
  t.y  = k_tab[tid+1];
  t.z  = k_tab[tid+2];
#elif (BARRETT_VECTOR_SIZE == 4)
  t.x  = k_tab[tid];
  t.y  = k_tab[tid+1];
  t.z  = k_tab[tid+2];
  t.w  = k_tab[tid+3];
#elif (BARRETT_VECTOR_SIZE == 8)
  t.s0 = k_tab[tid];
  t.s1 = k_tab[tid+1];
  t.s2 = k_tab[tid+2];
  t.s3 = k_tab[tid+3];
  t.s4 = k_tab[tid+4];
  t.s5 = k_tab[tid+5];
  t.s6 = k_tab[tid+6];
  t.s7 = k_tab[tid+7];
#elif (BARRETT_VECTOR_SIZE == 16)
  t.s0 = k_tab[tid];
  t.s1 = k_tab[tid+1];
  t.s2 = k_tab[tid+2];
  t.s3 = k_tab[tid+3];
  t.s4 = k_tab[tid+4];
  t.s5 = k_tab[tid+5];
  t.s6 = k_tab[tid+6];
  t.s7 = k_tab[tid+7];
  t.s8 = k_tab[tid+8];
  t.s9 = k_tab[tid+9];
  t.sa = k_tab[tid+10];
  t.sb = k_tab[tid+11];
  t.sc = k_tab[tid+12];
  t.sd = k_tab[tid+13];
  t.se = k_tab[tid+14];
  t.sf = k_tab[tid+15];
#endif
  a.d0 = t & 0x7FFF;
  a.d1 = t >> 15;  // t is 24 bits at most

  k.d0  = mad24(a.d0, 4620u, k_base.d0);
  k.d1  = mad24(a.d1, 4620u, k_base.d1) + (k.d0 >> 15);
  k.d0 &= 0x7FFF;
  k.d2  = (k.d1 >> 15) + k_base.d2;
  k.d1 &= 0x7FFF;
  k.d3  = (k.d2 >> 15) + k_base.d3;
  k.d2 &= 0x7FFF;
  k.d4  = (k.d3 >> 15) + k_base.d4;  // PERF: k.d4 = 0, normally. Can we limit k to 2^60?
  k.d3 &= 0x7FFF;
        
#if (TRACE_KERNEL > 3)
    if (tid==TRACE_TID) printf("cl_barrett15_82: k_tab[%d]=%x, k_base+k*4620=%x:%x:%x:%x:%x\n",
        tid, t.s0, k.d4.s0, k.d3.s0, k.d2.s0, k.d1.s0, k.d0.s0);
#endif
		// f = 2 * k * exp + 1
  f.d0 = mad24(k.d0, exp90.d0, 1u);

  f.d1 = mad24(k.d1, exp90.d0, f.d0 >> 15);
  f.d1 = mad24(k.d0, exp90.d1, f.d1);
  f.d0 &= 0x7FFF;

  f.d2 = mad24(k.d2, exp90.d0, f.d1 >> 15);
  f.d2 = mad24(k.d1, exp90.d1, f.d2);
  f.d2 = mad24(k.d0, exp90.d2, f.d2);  // PERF: if we limit exp at kernel compile time to 2^29, then we can skip exp90.d2 here and above.
  f.d1 &= 0x7FFF;

  f.d3 = mad24(k.d3, exp90.d0, f.d2 >> 15);
  f.d3 = mad24(k.d2, exp90.d1, f.d3);
  f.d3 = mad24(k.d1, exp90.d2, f.d3);
//  f.d3 = mad24(k.d0, exp90.d3, f.d3);    // exp90.d3 = 0
  f.d2 &= 0x7FFF;

  f.d4 = mad24(k.d4, exp90.d0, f.d3 >> 15);  // PERF: see above
  f.d4 = mad24(k.d3, exp90.d1, f.d4);
  f.d4 = mad24(k.d2, exp90.d2, f.d4);
  f.d3 &= 0x7FFF;

//  f.d5 = mad24(k.d5, exp90.d0, f.d4 >> 15);  // k.d5 = 0
  f.d5 = mad24(k.d4, exp90.d1, f.d4 >> 15);
  f.d5 = mad24(k.d3, exp90.d2, f.d5);
  f.d4 &= 0x7FFF;

#if (TRACE_KERNEL > 1)
    if (tid==TRACE_TID) printf("cl_barrett15_82: k_tab[%d]=%x, k=%x:%x:%x:%x:%x, f=%x:%x:%x:%x:%x:%x, shift=%d\n",
        tid, t.s0, k.d4.s0, k.d3.s0, k.d2.s0, k.d1.s0, k.d0.s0, f.d5.s0, f.d4.s0, f.d3.s0, f.d2.s0, f.d1.s0, f.d0.s0, shiftcount);
#endif
/*
ff = f as float, needed in mod_192_96() and div_192_96().
Precalculated here since it is the same for all steps in the following loop */
  ff= CONVERT_FLOAT_RTP_V(mad24(f.d5, 32768u, f.d4));
  ff= ff * 32768.0f * 32768.0f+ CONVERT_FLOAT_RTP_V(mad24(f.d3, 32768u, f.d2));   // f.d1 needed?

  //ff= as_float(0x3f7ffffb) / ff;		// just a little bit below 1.0f so we always underestimate the quotient
  //ff= as_float(0x3f7ffffd) / ff;		// just a little bit below 1.0f so we always underestimate the quotient
  ff = as_float(0x3f7ffffd) / ff;   // we rounded ff towards plus infinity, and round all other results towards zero. 

  // we need u=2^(2*bit_max)/f. As bit_max is between 60 and 90, use 2 uint's to store the upper 60 bits of 2^(2*bit_max)

  tmp = 1 << (bit_max - 61);	// tmp180 = 2^(89 + bits in f)
  
  // tmp180.d7 = 0; tmp180.d6 = 0; tmp180.d5 = 0; tmp180.d4 = 0; tmp180.d3 = 0; tmp180.d2 = 0; tmp180.d1 = 0; tmp180.d0 = 0;
  // PERF: as div is only used here, use all those zeros directly in there
  //       here, no vectorized data is necessary yet: the precalculated "b" value is the same for all
  //       tmp180.db contains the upper 2 parts (30 bits) of a 180-bit value. The lower 150 bits are all zero implicitely

  div_180_90(&u, tmp, f, ff
#if (TRACE_KERNEL > 1)
                  , tid
#endif
#ifdef CHECKS_MODBASECASE
                  ,modbasecase_debug
#endif
);						// u = floor(tmp180 / f)

#if (TRACE_KERNEL > 2)
  if (tid==TRACE_TID) printf("cl_barrett15_82: u=%x:%x:%x:%x:%x:%x, ff=%G\n",
        u.d5.s0, u.d4.s0, u.d3.s0, u.d2.s0, u.d1.s0, u.d0.s0, ff.s0);
#endif

  if (bit_max > 75)  // need to distiguish how far to shift; the same branch will be taken by all threads
  {
    //bit_max is 76 .. 89
    bit_max_bot  = bit_max-76;
    bit_max_mult = 1 << (91-bit_max);

    // a.d<n> = bb.d<n+5> >> bit_max_bot + bb.d<n+6> << top_bit_max

    //PERF: min limit of bb? bit_max > 75 ==> bb > 2^150 ==> d0..d9=0
    a.d0 = mad24(bb.d6, bit_max_mult, (bb.d5 >> bit_max_bot))&0x7FFF;			// a = floor(b / 2 ^ (bits_in_f - 1))
    a.d1 = mad24(bb.d7, bit_max_mult, (bb.d6 >> bit_max_bot))&0x7FFF;
    a.d2 = mad24(bb.d8, bit_max_mult, (bb.d7 >> bit_max_bot))&0x7FFF;
    a.d3 = mad24(bb.d9, bit_max_mult, (bb.d8 >> bit_max_bot))&0x7FFF;
    a.d4 = mad24(bb.da, bit_max_mult, (bb.d9 >> bit_max_bot))&0x7FFF;
    a.d5 = mad24(bb.db, bit_max_mult, (bb.da >> bit_max_bot));
  }
  else
  {
    //bit_max is 61 .. 75
    bit_max_bot  = bit_max-61;
    bit_max_mult = 1 << (76-bit_max);

    // a.d<n> = bb.d<n+4> >> bit_max_bot + bb.d<n+5> << top_bit_max

    //PERF: min limit of bb? bit_max >= 60 ==> bb >= 2^120 ==> d0..d7=0
    a.d0 = mad24(bb.d5, bit_max_mult, (bb.d4 >> bit_max_bot))&0x7FFF;			// a = b / (2^bit_max)
    a.d1 = mad24(bb.d6, bit_max_mult, (bb.d5 >> bit_max_bot))&0x7FFF;			// a = b / (2^bit_max)
    a.d2 = mad24(bb.d7, bit_max_mult, (bb.d6 >> bit_max_bot))&0x7FFF;			// a = b / (2^bit_max)
    a.d3 = mad24(bb.d8, bit_max_mult, (bb.d7 >> bit_max_bot))&0x7FFF;			// a = b / (2^bit_max)
    a.d4 = mad24(bb.d9, bit_max_mult, (bb.d8 >> bit_max_bot))&0x7FFF;		 	// a = b / (2^bit_max)
    a.d5 = mad24(bb.da, bit_max_mult, (bb.d9 >> bit_max_bot));		       	// a = b / (2^bit_max)
  }
      // PERF: could be no_low_5
  mul_90_180_no_low3(&tmp180, a, u); // tmp180 = (b / 2 ^ (bits_in_f - 1)) * (2 ^ (89 + bits_in_f) / f)   

#if (TRACE_KERNEL > 3)
    if (tid==TRACE_TID) printf("cl_barrett15_82: a=%x:%x:%x:%x:%x:%x * u = %x:%x:%x:%x:%x:%x:%x:%x:...\n",
        a.d5.s0, a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0,
        tmp180.db.s0, tmp180.da.s0, tmp180.d9.s0, tmp180.d8.s0, tmp180.d7.s0, tmp180.d6.s0, tmp180.d5.s0, tmp180.d4.s0);
#endif
  a.d0 = tmp180.d6;		             	// a = tmp180 / 2^90, which is b / f
  a.d1 = tmp180.d7;
  a.d2 = tmp180.d8;
  a.d3 = tmp180.d9;
  a.d4 = tmp180.da;
  a.d5 = tmp180.db;

  mul_90(&tmp90, a, f);							// tmp90 = (((b / (2^bit_max)) * u) / (2^bit_max)) * f

#if (TRACE_KERNEL > 3)
    if (tid==TRACE_TID) printf("cl_barrett15_82: a=%x:%x:%x:%x:%x:%x * f = %x:%x:%x:%x:%x:%x (tmp)\n",
        a.d5.s0, a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0,
        tmp90.d5.s0, tmp90.d4.s0, tmp90.d3.s0, tmp90.d2.s0, tmp90.d1.s0, tmp90.d0.s0);
#endif
    // all those bb.d0-bb.d3 are 0
  a.d0 = (-tmp90.d0) & 0x7FFF;
  a.d1 = (-tmp90.d1 - AS_UINT_V((a.d0 > 0) ? 1 : 0 ));
  a.d2 = (-tmp90.d2 - AS_UINT_V((a.d1 > 0x7FFF) ? 1 : 0 ));
  a.d3 = (-tmp90.d3 - AS_UINT_V((a.d2 > 0x7FFF) ? 1 : 0 ));
  a.d4 = (bb.d4-tmp90.d4 - AS_UINT_V((a.d3 > 0x7FFF) ? 1 : 0 ));
  a.d5 = (bb.d5-tmp90.d5 - AS_UINT_V((a.d4 > 0x7FFF) ? 1 : 0 ));
  a.d1 &= 0x7FFF;
  a.d2 &= 0x7FFF;
  a.d3 &= 0x7FFF;
  a.d4 &= 0x7FFF;
  a.d5 &= 0x7FFF;

#if (TRACE_KERNEL > 3)
    if (tid==TRACE_TID) printf("cl_barrett15_82: b=%x:%x:%x:%x:%x:%x - tmp = %x:%x:%x:%x:%x:%x (a)\n",
        bb.d5, bb.d4, bb.d3, bb.d2, bb.d1, bb.d0, a.d5.s0, a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0);
#endif
    ///
    ///// here it starts to become different between the 3 6x15bit kernels
    ///

  exp<<= 32 - shiftcount;
  while(exp)
  {
    square_90_180(&b, a);						// b = a^2

#if (TRACE_KERNEL > 2)
    if (tid==TRACE_TID) printf("loop: exp=%.8x, a=%x:%x:%x:%x:%x:%x ^2 = %x:%x:%x:%x:%x:%x:%x:%x:%x:%x:%x:%x (b)\n",
        exp, a.d5.s0, a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0,
        b.db.s0, b.da.s0, b.d9.s0, b.d8.s0, b.d7.s0, b.d6.s0, b.d5.s0, b.d4.s0, b.d3.s0, b.d2.s0, b.d1.s0, b.d0.s0 );
#endif
    if (bit_max > 75)  // need to distiguish how far to shift
    {
      a.d0 = mad24(b.d6, bit_max_mult, (b.d5 >> bit_max_bot))&0x7FFF;			// a = b / (2^bit_max)
      a.d1 = mad24(b.d7, bit_max_mult, (b.d6 >> bit_max_bot))&0x7FFF;			// a = b / (2^bit_max)
      a.d2 = mad24(b.d8, bit_max_mult, (b.d7 >> bit_max_bot))&0x7FFF;			// a = b / (2^bit_max)
      a.d3 = mad24(b.d9, bit_max_mult, (b.d8 >> bit_max_bot))&0x7FFF;			// a = b / (2^bit_max)
      a.d4 = mad24(b.da, bit_max_mult, (b.d9 >> bit_max_bot))&0x7FFF;		 	// a = b / (2^bit_max)
      a.d5 = mad24(b.db, bit_max_mult, (b.da >> bit_max_bot));		       	// a = b / (2^bit_max)
    }
    else
    {
      a.d0 = mad24(b.d5, bit_max_mult, (b.d4 >> bit_max_bot))&0x7FFF;			// a = b / (2^bit_max)
      a.d1 = mad24(b.d6, bit_max_mult, (b.d5 >> bit_max_bot))&0x7FFF;			// a = b / (2^bit_max)
      a.d2 = mad24(b.d7, bit_max_mult, (b.d6 >> bit_max_bot))&0x7FFF;			// a = b / (2^bit_max)
      a.d3 = mad24(b.d8, bit_max_mult, (b.d7 >> bit_max_bot))&0x7FFF;			// a = b / (2^bit_max)
      a.d4 = mad24(b.d9, bit_max_mult, (b.d8 >> bit_max_bot))&0x7FFF;		 	// a = b / (2^bit_max)
      a.d5 = mad24(b.da, bit_max_mult, (b.d9 >> bit_max_bot));		       	// a = b / (2^bit_max)
    }
      // PERF: could be no_low_5
    mul_90_180_no_low3(&tmp180, a, u); // tmp180 = (b / 2 ^ (bits_in_f - 1)) * (2 ^ (89 + bits_in_f) / f)   

#if (TRACE_KERNEL > 3)
    if (tid==TRACE_TID) printf("loopl: a=%x:%x:%x:%x:%x:%x * u = %x:%x:%x:%x:%x:%x:%x:%x:...\n",
        a.d5.s0, a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0,
        tmp180.db.s0, tmp180.da.s0, tmp180.d9.s0, tmp180.d8.s0, tmp180.d7.s0, tmp180.d6.s0, tmp180.d5.s0, tmp180.d4.s0);
#endif

    a.d0 = tmp180.d6;		             	// a = tmp180 / 2^90, which is b / f
    a.d1 = tmp180.d7;
    a.d2 = tmp180.d8;
    a.d3 = tmp180.d9;
    a.d4 = tmp180.da;
    a.d5 = tmp180.db;

    mul_90(&tmp90, a, f);						// tmp90 = (((b / (2^bit_max)) * u) / (2^bit_max)) * f

#if (TRACE_KERNEL > 3)
    if (tid==TRACE_TID) printf("loop: a=%x:%x:%x:%x:%x:%x * f = %x:%x:%x:%x:%x:%x (tmp)\n",
        a.d5.s0, a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0, tmp90.d5.s0, tmp90.d4.s0, tmp90.d3.s0, tmp90.d2.s0, tmp90.d1.s0, tmp90.d0.s0);
#endif
    a.d0 = (b.d0 - tmp90.d0) & 0x7FFF;
    a.d1 = (b.d1 - tmp90.d1 - AS_UINT_V((a.d0 > b.d0) ? 1 : 0 ));
    a.d2 = (b.d2 - tmp90.d2 - AS_UINT_V((a.d1 > b.d1) ? 1 : 0 ));
    a.d3 = (b.d3 - tmp90.d3 - AS_UINT_V((a.d2 > b.d2) ? 1 : 0 ));
    a.d4 = (b.d4 - tmp90.d4 - AS_UINT_V((a.d3 > b.d3) ? 1 : 0 ));
    a.d5 = (b.d5 - tmp90.d5 - AS_UINT_V((a.d4 > b.d4) ? 1 : 0 ));
    a.d1 &= 0x7FFF;
    a.d2 &= 0x7FFF;
    a.d3 &= 0x7FFF;
    a.d4 &= 0x7FFF;
    a.d5 &= 0x7FFF;
    
#if (TRACE_KERNEL > 3)
    if (tid==TRACE_TID) printf("loop: b=%x:%x:%x:%x:%x:%x - tmp = %x:%x:%x:%x:%x:%x (a)\n",
        b.d5.s0, b.d4.s0, b.d3.s0, b.d2.s0, b.d1.s0, b.d0.s0, a.d5.s0, a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0);
#endif

    if(exp&0x80000000)shl_90(&a);					// "optional multiply by 2" in Prime 95 documentation

    exp+=exp;
#if (TRACE_KERNEL > 1)
    if (tid==TRACE_TID) printf("loopend: exp=%x, tmp=%x:%x:%x:%x:%x mod f=%x:%x:%x:%x:%x = %x:%x:%x:%x:%x (a)\n",
        exp, tmp90.d4.s0, tmp90.d3.s0, tmp90.d2.s0, tmp90.d1.s0, tmp90.d0.s0,
        f.d4.s0, f.d3.s0, f.d2.s0, f.d1.s0, f.d0.s0, a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0 );
#endif
  }

#ifndef CHECKS_MODBASECASE
    mod_simple_90(&tmp90, a, f, ff
#if (TRACE_KERNEL > 1)
                   , tid
#endif
                 );					// adjustment, plain barrett returns N = AB mod M where N < 3M!
#else
    int limit = 6;
    if(bit_max_90 == 2) limit = 8;					// bit_max == 65, due to decreased accuracy of mul_96_192_no_low2() above we need a higher threshold
    if(bit_max_90 == 3) limit = 7;					// bit_max == 66, ...
    mod_simple_90(&tmp90, a, f, ff
#if (TRACE_KERNEL > 1)
                   , tid
#endif
                   , bit_max_90, limit, modbasecase_debug);
#endif

#ifndef CHECKS_MODBASECASE
  a = sub_if_gte_90(tmp90,f);	// final adjustment in case a >= f
#else
  tmp90 = sub_if_gte_90(tmp90,f);
  a = sub_if_gte_90(tmp90,f);
  if( tmp90.d0 != a.d0 )  // f is odd, so it is sufficient to compare the last part
  {
    printf("EEEEEK, final a was >= f\n");
  }
#endif

#if (TRACE_KERNEL > 3)
  if (tid==TRACE_TID) printf("after sub: a = %x:%x:%x:%x:%x:%x \n",
         a.d5.s0, a.d4.s0, a.d3.s0, a.d2.s0, a.d1.s0, a.d0.s0 );
#endif
  

/* finally check if we found a factor and write the factor to RES[] */
#if (BARRETT_VECTOR_SIZE == 1)
  if( ((a.d5|a.d4|a.d3|a.d2|a.d1)==0 && a.d0==1) )
  {
/* in contrast to the other kernels this barrett based kernel is only allowed for factors above 2^60 so there is no need to check for f != 1 */  
    tid=ATOMIC_INC(RES[0]);
    if(tid<10)				/* limit to 10 factors per class */
    {
      RES[tid*3 + 1]=mad24(f.d5,0x8000u, f.d4);
      RES[tid*3 + 2]=mad24(f.d3,0x8000u, f.d2);  // that's now 30 bits per int
      RES[tid*3 + 3]=mad24(f.d1,0x8000u, f.d0);  
    }
  }
#elif (BARRETT_VECTOR_SIZE == 2)
  EVAL_RES_90(x)
  EVAL_RES_90(y)
#elif (BARRETT_VECTOR_SIZE == 3)
  EVAL_RES_90(x)
  EVAL_RES_90(y)
  EVAL_RES_90(z)
#elif (BARRETT_VECTOR_SIZE == 4)
  EVAL_RES_90(x)
  EVAL_RES_90(y)
  EVAL_RES_90(z)
  EVAL_RES_90(w)
#elif (BARRETT_VECTOR_SIZE == 8)
  EVAL_RES_90(s0)
  EVAL_RES_90(s1)
  EVAL_RES_90(s2)
  EVAL_RES_90(s3)
  EVAL_RES_90(s4)
  EVAL_RES_90(s5)
  EVAL_RES_90(s6)
  EVAL_RES_90(s7)
#elif (BARRETT_VECTOR_SIZE == 16)
  EVAL_RES_90(s0)
  EVAL_RES_90(s1)
  EVAL_RES_90(s2)
  EVAL_RES_90(s3)
  EVAL_RES_90(s4)
  EVAL_RES_90(s5)
  EVAL_RES_90(s6)
  EVAL_RES_90(s7)
  EVAL_RES_90(s8)
  EVAL_RES_90(s9)
  EVAL_RES_90(sa)
  EVAL_RES_90(sb)
  EVAL_RES_90(sc)
  EVAL_RES_90(sd)
  EVAL_RES_90(se)
  EVAL_RES_90(sf)
#endif
 
}
