// Installed by the reviewed overlay at
// //third_party/blink/renderer/platform/media/fairplay_hls_loader.h.
//
// Render-process network side of Safari's native HLS route (NATIVE_HLS.md
// beside this file's source in the Parc repository). The AVPlayer in the GPU
// process has no network of its own: every load AVFoundation makes (playlists,
// segments, key certificates) arrives here as a
// media.mojom.FairPlayHlsPlayerClient.StartLoad call. Each becomes one
// WebAssociatedURLLoader made by the element's ResourceFetchContext, the same
// factory ResourceMultiBufferDataProvider uses for every <video src> load, so
// the request carries the page's cookies and referrer and the page's user
// agent, passes CORS in the element's CORS mode, uses the profile's proxy and
// shows in DevTools as one of the element's media requests: what WebKit's
// WebCoreNSURLSession gives AVFoundation in Safari.
//
// Per load:
//  - Only GET and HEAD of http and https URLs are fetched. Of AVFoundation's
//    request headers only Range goes out; its own User-Agent and
//    X-Playback-Session-Id would make cross-origin CORS loads preflight. A
//    Range request gets an identity encoding as Chromium's media loads do
//    (added by the network layer, kDeferMediaAcceptEncodingInjection).
//  - Redirects are followed (cross-origin ones as any fresh media load
//    follows them; the loader enforces CORS in CORS mode), and the response
//    reports the URL after them, which relative playlist URIs resolve
//    against.
//  - The response's status, MIME type and headers go back as they are. A body
//    the network stack decoded (a Content-Encoding other than identity) has
//    an unknown length, and its Content-Length and Content-Encoding headers
//    are dropped.
//  - The body streams over the load's data pipe; loading pauses while the
//    pipe is full. OnComplete follows the last byte.
//  - FairPlayHlsLoad.Cancel(), or either pipe closing, cancels the load.
//    Destroying the loader cancels every load.
#ifndef THIRD_PARTY_BLINK_RENDERER_PLATFORM_MEDIA_FAIRPLAY_HLS_LOADER_H_
#define THIRD_PARTY_BLINK_RENDERER_PLATFORM_MEDIA_FAIRPLAY_HLS_LOADER_H_

#include <stddef.h>
#include <stdint.h>

#include <memory>
#include <vector>

#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/scoped_refptr.h"
#include "base/memory/weak_ptr.h"
#include "base/sequence_checker.h"
#include "base/task/sequenced_task_runner.h"
#include "media/mojo/mojom/renderer_extensions.mojom.h"
#include "mojo/public/cpp/bindings/pending_receiver.h"
#include "mojo/public/cpp/bindings/pending_remote.h"
#include "third_party/blink/renderer/platform/media/url_index.h"
#include "third_party/blink/renderer/platform/platform_export.h"

namespace blink {

class ResourceFetchContext;

class PLATFORM_EXPORT FairPlayHlsLoader {
 public:
  using StartLoadCallback = base::RepeatingCallback<void(
      media::mojom::FairPlayHlsRequestPtr request,
      mojo::PendingReceiver<media::mojom::FairPlayHlsLoad> load,
      mojo::PendingRemote<media::mojom::FairPlayHlsLoadClient> client)>;

  // Each body pipe's capacity.
  static constexpr uint32_t kBodyPipeCapacity = 512 * 1024;

  // Runs on the current sequence, the render thread. |fetch_context| (the
  // element's UrlIndex's) must outlive the loader, or be replaced
  // (SetFetchContext) before it goes. |cors_mode| is the
  // element's crossorigin state; |is_audio_element| picks the audio request
  // destination over video.
  FairPlayHlsLoader(ResourceFetchContext* fetch_context,
                    UrlData::CorsMode cors_mode,
                    bool is_audio_element);
  FairPlayHlsLoader(const FairPlayHlsLoader&) = delete;
  FairPlayHlsLoader& operator=(const FairPlayHlsLoader&) = delete;
  ~FairPlayHlsLoader();

  // Serves one load (FairPlayHlsPlayerClient.StartLoad).
  void StartLoad(media::mojom::FairPlayHlsRequestPtr request,
                 mojo::PendingReceiver<media::mojom::FairPlayHlsLoad> load,
                 mojo::PendingRemote<media::mojom::FairPlayHlsLoadClient>
                     client);

  // StartLoad for any thread: the call is posted to the loader's sequence
  // and dropped (closing its pipes) once the loader is gone.
  StartLoadCallback GetStartLoadCallback();

  // Makes later loads with |fetch_context|: the element moved its player to
  // another frame (WebMediaPlayerImpl::ParcMoveToFrame).
  void SetFetchContext(ResourceFetchContext* fetch_context);

  size_t load_count_for_testing() const { return loads_.size(); }

 private:
  class Load;

  // Destroys |load|, which has stopped.
  void RemoveLoad(Load* load);

  raw_ptr<ResourceFetchContext> fetch_context_;
  const UrlData::CorsMode cors_mode_;
  const bool is_audio_element_;
  const scoped_refptr<base::SequencedTaskRunner> task_runner_;

  std::vector<std::unique_ptr<Load>> loads_;

  SEQUENCE_CHECKER(sequence_checker_);
  base::WeakPtrFactory<FairPlayHlsLoader> weak_factory_{this};
};

}  // namespace blink

#endif  // THIRD_PARTY_BLINK_RENDERER_PLATFORM_MEDIA_FAIRPLAY_HLS_LOADER_H_
