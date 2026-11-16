#pragma once

#include <stdio.h>
#include <stdlib.h>

__attribute__((noreturn)) static inline void ParcTestFailure(const char* file, int line, const char* expression) {
  fflush(NULL);
  fprintf(stderr, "%s:%d: Check failed: %s\n", file, line, expression);
  exit(1);
}

#define PARC_EXPECT(condition) ((condition) ? (void)0 : ParcTestFailure(__FILE__, __LINE__, #condition))
