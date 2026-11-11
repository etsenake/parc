// Installed by the reviewed overlay at
// //content/renderer/media/fairplay/fairplay_media_host_connection.h.
//
// A frame's pipe to its document's FairPlay host in the browser
// (media.mojom.FairPlayMediaHost), bound on the frame's main thread and
// callable from any thread, as content's MediaInterfaceFactory is for the
// frame's InterfaceFactory. It goes with the frame. Like that pipe, which
// carries the CDM requests, it rebinds only after a disconnect, so a new
// document's requests take the same path as its CDMs.
#ifndef CONTENT_RENDERER_MEDIA_FAIRPLAY_FAIRPLAY_MEDIA_HOST_CONNECTION_H_
#define CONTENT_RENDERER_MEDIA_FAIRPLAY_FAIRPLAY_MEDIA_HOST_CONNECTION_H_

#include "base/memory/scoped_refptr.h"
#include "base/memory/weak_ptr.h"
#include "base/task/single_thread_task_runner.h"
#include "content/public/renderer/render_frame_observer.h"
#include "content/public/renderer/render_frame_observer_tracker.h"
#include "mojo/public/cpp/bindings/remote.h"
#include "third_party/parc_fairplay/chromium/fairplay_media.mojom.h"

namespace parc::fairplay {

class FairPlayMediaHostConnection final
    : public content::RenderFrameObserver,
      public content::RenderFrameObserverTracker<FairPlayMediaHostConnection>,
      public media::mojom::FairPlayMediaHost {
 public:
  // The frame's, made on first use. Main thread.
  static FairPlayMediaHostConnection* ForFrame(
      content::RenderFrame* render_frame);

  FairPlayMediaHostConnection(const FairPlayMediaHostConnection&) = delete;
  FairPlayMediaHostConnection& operator=(const FairPlayMediaHostConnection&) =
      delete;

  // media::mojom::FairPlayMediaHost, on any thread:
  void CreateRenderer(
      mojo::PendingReceiver<media::mojom::Renderer> receiver,
      mojo::PendingRemote<media::mojom::FairPlayRendererClientExtension>
          client_extension) override;
  void CreateHlsPlayer(
      mojo::PendingReceiver<media::mojom::FairPlayHlsPlayer> player,
      mojo::PendingRemote<media::mojom::FairPlayHlsPlayerClient> client)
      override;
  void CreateMuteStateHandoff(CreateMuteStateHandoffCallback callback) override;

 private:
  explicit FairPlayMediaHostConnection(content::RenderFrame* render_frame);
  ~FairPlayMediaHostConnection() override;

  // content::RenderFrameObserver:
  void OnDestruct() override;

  media::mojom::FairPlayMediaHost* Host();

  const scoped_refptr<base::SingleThreadTaskRunner> task_runner_;
  mojo::Remote<media::mojom::FairPlayMediaHost> host_;
  base::WeakPtr<FairPlayMediaHostConnection> weak_this_;
  base::WeakPtrFactory<FairPlayMediaHostConnection> weak_factory_{this};
};

}  // namespace parc::fairplay

#endif  // CONTENT_RENDERER_MEDIA_FAIRPLAY_FAIRPLAY_MEDIA_HOST_CONNECTION_H_
