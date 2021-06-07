// A more standard division, compact, 1 cycle per bit
// see also https://projectf.io/posts/division-in-verilog/
// define: div_width    for the division bit width
// define: div_unsigned if unsigned, for a more compact result

$$if not div_width then
$$error('please provide the bit width by defining the preprocessor var div_width')
$$end

$$div_width_pow2=0
$$tmp = div_width
$$while tmp > 1 do
$$  div_width_pow2 = div_width_pow2 + 1
$$  tmp = (tmp/2)
$$end

algorithm div$div_width$(
  input  int$div_width$ inum,
  input  int$div_width$ iden,
  output int$div_width$ ret = 0)
{
  uint$div_width+1$ ac = uninitialized;
  uint$div_width+1$ diff <:: ac - den;
  
  uint$div_width_pow2+1$ i = 0;
  
$$if not div_unsigned then
  uint1           inum_neg <:: inum[$div_width-1$,1];
  uint1           iden_neg <:: iden[$div_width-1$,1];
  uint$div_width$ num      <:: inum_neg ? -inum : inum;
  uint$div_width$ den      <:: iden_neg ? -iden : iden;
$$else
  uint$div_width$ num  <:: inum;
  uint$div_width$ den  <:: iden;
$$end

$$if FORMAL then
  // Preconditions:
  // (*) x/0 = error
  #restrict(iden != 0);
$$end
 
  ac  = {{$div_width-1${1b0}},num[$div_width-1$,1]};
  ret = {num[0,$div_width-1$],1b0};
  while (i != $div_width$) {
    if (diff[$div_width$,1] == 0) { // positive
      ac  = {diff[0,$div_width-1$],ret[$div_width-1$,1]};
      ret = {ret [0,$div_width-1$],1b1};
    } else {
      ac  = {ac  [0,$div_width-1$],ret[$div_width-1$,1]};
      ret = {ret [0,$div_width-1$],1b0};
    }
    i = i + 1;
  }
$$if not div_unsigned then
  ret = ((inum_neg) ^ (iden_neg)) ? -ret : ret;
$$end
}
