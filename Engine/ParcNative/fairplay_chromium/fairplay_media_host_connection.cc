#include "content/renderer/media/fairplay/fairplay_media_host_connection.h"

#include <utility>

#include "base/check.h"
#include "base/functional/bind.h"
#include "content/public/renderer/render_frame.h"
#include "third_party/blink/public/platform/browser_interface_broker_proxy.h"

namespace parc::fairplay {

// static
FairPlayMediaHostConnection* FairPlayMediaHostConnection::ForFrame(
    content::RenderFrame* render_frame) {
  if (FairPlayMediaHostConnection* connection = Get(render_frame)) {
    return connection;
  }
  // Owned by the frame it observes.
  return new FairPlayMediaHostConnection(render_frame);
}

FairPlayMediaHostConnection::FairPlayMediaHostConnection(
    content::RenderFrame* render_frame)
    : RenderFrameObserver(render_frame),
      RenderFrameObserverTracker<FairPlayMediaHostConnection>(render_frame),
      task_runner_(base::SingleThreadTaskRunner::GetCurrentDefault()) {
  weak_this_ = weak_factory_.GetWeakPtr();
}

FairPlayMediaHostConnection::~FairPlayMediaHostConnection() {
  DCHECK(task_runner_->BelongsToCurrentThread());
}

void FairPlayMediaHostConnection::OnDestruct() {
  delete this;
}

void FairPlayMediaHostConnection::CreateRenderer(
    int32_t player_id,
    mojo::PendingReceiver<media::mojom::Renderer> receiver,
    mojo::PendingRemote<media::mojom::FairPlayRendererClientExtension>
        client_extension) {
  if (!task_runner_->BelongsToCurrentThread()) {
    task_runner_->PostTask(
        FROM_HERE, base::BindOnce(&FairPlayMediaHostConnection::CreateRenderer,
                                  weak_this_, player_id, std::move(receiver),
                                  std::move(client_extension)));
    return;
  }
  Host()->CreateRenderer(player_id, std::move(receiver),
                         std::move(client_extension));
}

void FairPlayMediaHostConnection::CreateHlsPlayer(
    int32_t player_id,
    mojo::PendingReceiver<media::mojom::FairPlayHlsPlayer> player,
    mojo::PendingRemote<media::mojom::FairPlayHlsPlayerClient> client) {
  if (!task_runner_->BelongsToCurrentThread()) {
    task_runner_->PostTask(
        FROM_HERE, base::BindOnce(&FairPlayMediaHostConnection::CreateHlsPlayer,
                                  weak_this_, player_id, std::move(player),
                                  std::move(client)));
    return;
  }
  Host()->CreateHlsPlayer(player_id, std::move(player), std::move(client));
}

void FairPlayMediaHostConnection::CreateMuteStateHandoff(
    CreateMuteStateHandoffCallback callback) {
  if (!task_runner_->BelongsToCurrentThread()) {
    task_runner_->PostTask(
        FROM_HERE,
        base::BindOnce(&FairPlayMediaHostConnection::CreateMuteStateHandoff,
                       weak_this_, std::move(callback)));
    return;
  }
  Host()->CreateMuteStateHandoff(std::move(callback));
}

media::mojom::FairPlayMediaHost* FairPlayMediaHostConnection::Host() {
  DCHECK(task_runner_->BelongsToCurrentThread());
  if (!host_) {
    render_frame()->GetBrowserInterfaceBroker().GetInterface(
        host_.BindNewPipeAndPassReceiver());
    host_.reset_on_disconnect();
  }
  return host_.get();
}

}  // namespace parc::fairplay
