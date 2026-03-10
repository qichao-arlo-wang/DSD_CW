#include <system.h>
#include <stdio.h>


int main()
{
  printf("Hello from Nios II!\n");

  int a, b, c, d;
  a = 2;
  b = 4;
  c = a*b;
  printf("Multiplication result: %d\n", c);

  d = ALT_CI_MUL_0(a,b);
  printf("Multiplication result from custom instr: %d", d);

  return 0;
}
