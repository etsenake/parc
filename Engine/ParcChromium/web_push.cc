// Copyright 2026 Parc contributors.
#include "parc/web_push.h"

#include <string>
#include <utility>

#include "base/memory/raw_ptr.h"
#include "components/gcm_driver/gcm_client_impl.h"
#include "components/gcm_driver/registration_info.h"
#include "google_apis/gcm/base/encryptor.h"

namespace parc {
namespace {
class WebPushClient final : public gcm::GCMClientImpl {
 public:
  WebPushClient() : GCMClientImpl(std::make_unique<gcm::GCMInternalsBuilder>()) {}
  void Initialize(
      const ChromeBuildInfo& build_info, const base::FilePath& store_path,
      const scoped_refptr<base::SequencedTaskRunner>& blocking_runner,
      scoped_refptr<base::SequencedTaskRunner> io_runner,
      base::RepeatingCallback<void(
          mojo::PendingReceiver<network::mojom::ProxyResolvingSocketFactory>)>
          socket_factory,
      const scoped_refptr<network::SharedURLLoaderFactory>& loader_factory,
      network::NetworkConnectionTracker* connection_tracker,
      std::unique_ptr<gcm::Encryptor> encryptor, gcm::GCMClient::Delegate* delegate) override {
    delegate_ = delegate;
    GCMClientImpl::Initialize(build_info, store_path, blocking_runner,
                             std::move(io_runner), std::move(socket_factory),
                             loader_factory, connection_tracker,
                             std::move(encryptor), delegate);
  }
  void Register(scoped_refptr<gcm::RegistrationInfo> info) override {
    // The sender-ID endpoint is retired; Instance ID and transport stay upstream.
    if (gcm::GCMRegistrationInfo::FromRegistrationInfo(info.get())) {
      delegate_->OnRegisterFinished(info, std::string(), GCM_DISABLED);
      return;
    }
    GCMClientImpl::Register(std::move(info));
  }
 private:
  raw_ptr<gcm::GCMClient::Delegate> delegate_ = nullptr;
};
}
std::unique_ptr<gcm::GCMClient> CreateWebPushClient() {
  return std::make_unique<WebPushClient>();
}
}
