// Copyright 2026 Parc contributors.
#ifndef PARC_WEB_PUSH_H_
#define PARC_WEB_PUSH_H_
#include <memory>
namespace gcm { class GCMClient; }
namespace parc { std::unique_ptr<gcm::GCMClient> CreateWebPushClient(); }
#endif
