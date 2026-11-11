// Copyright 2026 Parc contributors.
#ifndef PARC_CONTENT_MAIN_H_
#define PARC_CONTENT_MAIN_H_

#include "content/public/app/content_main.h"

namespace content {
// Staged RunContentProcess preamble, implemented in content/app/content_main.cc.
// A negative result continues with runner->Run(), then runner->Shutdown().
// Otherwise the result is a process exit code, including zero. A supplied
// params.autorelease_pool belongs to the caller and must survive Run().
CONTENT_EXPORT int ContentMainInitialize(ContentMainParams params,
                                         ContentMainRunner* runner);
}  // namespace content

#endif  // PARC_CONTENT_MAIN_H_
