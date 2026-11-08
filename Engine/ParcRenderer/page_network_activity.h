// Copyright 2026 Parc contributors.
#ifndef THIRD_PARTY_BLINK_RENDERER_CORE_FRAME_PARC_PAGE_NETWORK_ACTIVITY_H_
#define THIRD_PARTY_BLINK_RENDERER_CORE_FRAME_PARC_PAGE_NETWORK_ACTIVITY_H_

#include <cstdint>
#include <optional>

#include "base/memory/scoped_refptr.h"
#include "base/task/single_thread_task_runner.h"
#include "third_party/blink/public/common/parc/page_network_activity_count.h"
#include "third_party/blink/public/mojom/parc/page_network_activity.mojom-blink.h"
#include "third_party/blink/renderer/core/core_export.h"
#include "third_party/blink/renderer/platform/heap/garbage_collected.h"
#include "third_party/blink/renderer/platform/heap/member.h"
#include "third_party/blink/renderer/platform/mojo/heap_mojo_associated_receiver.h"
#include "third_party/blink/renderer/platform/mojo/heap_mojo_associated_remote.h"
#include "third_party/blink/renderer/platform/supplementable.h"
#include "third_party/blink/renderer/platform/timer.h"

namespace blink {

class Document;
class LocalFrame;
class ResourceRequest;

// Tells the browser whether an ordinary page's main document has requests in
// flight, for Parc's page-loading indicator. Counts what the document's
// resource load observer sees (where Blink's IdlenessDetector hears of
// requests) except requests that stay open: media, EventSource, pings,
// beacons and keepalive sends, and any request open longer than
// parc::page_network::kLongLivedMs (long-polls). WebSockets don't use the
// fetcher. Only changes between none and some in flight are sent.
class CORE_EXPORT PageNetworkActivity final
    : public GarbageCollected<PageNetworkActivity>,
      public Supplement<LocalFrame>,
      public parc::mojom::blink::PageNetworkActivityAgent {
 public:
  static const char kSupplementName[];

  // An ordinary page's outermost main frame, from LocalFrame's constructor.
  static void Install(LocalFrame&);
  static PageNetworkActivity* From(LocalFrame&);

  explicit PageNetworkActivity(LocalFrame&);

  // DocumentLoader::CommitNavigation: the new document has nothing in
  // flight; the old one's requests no longer count.
  void DidCommitNavigation(const Document&);
  // ResourceLoadObserverForFrame: a request's first send, and its finish or
  // failure.
  void WillSendRequest(const Document&, const ResourceRequest&);
  void DidFinishRequest(const Document&, uint64_t identifier);

  void Trace(Visitor*) const override;

 private:
  void BindAgent(mojo::PendingAssociatedReceiver<
                 parc::mojom::blink::PageNetworkActivityAgent>);
  // parc::mojom::blink::PageNetworkActivityAgent:
  void SetObserver(mojo::PendingAssociatedRemote<
                   parc::mojom::blink::PageNetworkActivityObserver>) override;
  void Update();
  void ExpiryTimerFired(TimerBase*);
  void Send(TimerBase*);

  scoped_refptr<base::SingleThreadTaskRunner> task_runner_;
  // Fires by the time the last counted request becomes long-lived.
  HeapTaskRunnerTimer<PageNetworkActivity> expiry_timer_;
  int64_t expiry_due_ = 0;
  // Sends after the current task, so a request that starts and finishes in
  // one task (a memory-cache hit) sends nothing.
  HeapTaskRunnerTimer<PageNetworkActivity> send_timer_;
  HeapMojoAssociatedReceiver<parc::mojom::blink::PageNetworkActivityAgent,
                             PageNetworkActivity>
      agent_{this, nullptr};
  HeapMojoAssociatedRemote<parc::mojom::blink::PageNetworkActivityObserver>
      observer_{nullptr};
  WeakMember<const Document> document_;
  parc::page_network::InFlightRequests in_flight_;
  std::optional<int64_t> busy_until_;
  bool sent_busy_ = false;
};

}  // namespace blink

#endif  // THIRD_PARTY_BLINK_RENDERER_CORE_FRAME_PARC_PAGE_NETWORK_ACTIVITY_H_
