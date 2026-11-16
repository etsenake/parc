#pragma once

#include <stdio.h>
#include <stdlib.h>

__attribute__((noreturn)) static inline void ParcTestFailure(const char* file, int line, const char* expression) {
  fflush(NULL);
  fprintf(stderr, "%s:%d: Check failed: %s\n", file, line, expression);
  exit(1);
}

#define PARC_EXPECT(condition) ((condition) ? (void)0 : ParcTestFailure(__FILE__, __LINE__, #condition))

#ifdef __OBJC__
#import <Foundation/Foundation.h>

static inline void ParcUncaughtException(NSException* exception) {
  fflush(NULL);
  fprintf(stderr, "Uncaught %s: %s\n", exception.name.UTF8String,
          exception.reason ? exception.reason.UTF8String : "no reason");
  exit(1);
}

static inline void ParcExitOnUncaughtExceptions(void) {
  NSSetUncaughtExceptionHandler(&ParcUncaughtException);
}
#endif
