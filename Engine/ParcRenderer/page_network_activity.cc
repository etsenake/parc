// Copyright 2026 Parc contributors.
#include "third_party/blink/renderer/core/frame/parc_page_network_activity.h"

#include <utility>

#include "base/time/time.h"
#include "third_party/blink/public/mojom/fetch/fetch_api_request.mojom-blink.h"
#include "third_party/blink/public/platform/interface_registry.h"
#include "third_party/blink/public/platform/task_type.h"
#include "third_party/blink/renderer/core/dom/document.h"
#include "third_party/blink/renderer/core/frame/local_frame.h"
#include "third_party/blink/renderer/platform/loader/fetch/resource_request.h"
#include "third_party/blink/renderer/platform/wtf/functional.h"

namespace blink {

namespace {

// IdlenessDetector's never-ending requests: streamed media, event streams
// and fire-and-forget sends.
bool StaysOpen(const ResourceRequest& request) {
  using Context = mojom::blink::RequestContextType;
  switch (request.GetRequestContext()) {
    case Context::AUDIO:
    case Context::VIDEO:
    case Context::TRACK:
    case Context::EVENT_SOURCE:
    case Context::BEACON:
    case Context::PING:
    case Context::CSP_REPORT:
      return true;
    default:
      return request.GetKeepalive();
  }
}

int64_t NowMs() {
  return (base::TimeTicks::Now() - base::TimeTicks()).InMilliseconds();
}

}  // namespace

const char PageNetworkActivity::kSupplementName[] = "PageNetworkActivity";

void PageNetworkActivity::Install(LocalFrame& frame) {
  ProvideTo(frame, MakeGarbageCollected<PageNetworkActivity>(frame));
}

PageNetworkActivity* PageNetworkActivity::From(LocalFrame& frame) {
  return Supplement<LocalFrame>::From<PageNetworkActivity>(frame);
}

PageNetworkActivity::PageNetworkActivity(LocalFrame& frame)
    : Supplement<LocalFrame>(frame),
      task_runner_(frame.GetTaskRunner(TaskType::kInternalLoading)),
      expiry_timer_(task_runner_,
                    this,
                    &PageNetworkActivity::ExpiryTimerFired),
      send_timer_(task_runner_, this, &PageNetworkActivity::Send) {
  frame.GetInterfaceRegistry()->AddAssociatedInterface(BindRepeating(
      &PageNetworkActivity::BindAgent, WrapWeakPersistent(this)));
}

void PageNetworkActivity::Trace(Visitor* visitor) const {
  Supplement<LocalFrame>::Trace(visitor);
  visitor->Trace(expiry_timer_);
  visitor->Trace(send_timer_);
  visitor->Trace(agent_);
  visitor->Trace(observer_);
  visitor->Trace(document_);
}

void PageNetworkActivity::BindAgent(
    mojo::PendingAssociatedReceiver<
        parc::mojom::blink::PageNetworkActivityAgent> receiver) {
  if (GetSupplementable()->IsDetached()) {
    return;
  }
  agent_.reset();
  agent_.Bind(std::move(receiver), task_runner_);
}

void PageNetworkActivity::SetObserver(
    mojo::PendingAssociatedRemote<
        parc::mojom::blink::PageNetworkActivityObserver> observer) {
  if (GetSupplementable()->IsDetached()) {
    return;
  }
  observer_.reset();
  observer_.Bind(std::move(observer), task_runner_);
  // The expiry timer may have been frozen with the page.
  Update();
  sent_busy_ = busy_until_.has_value();
  observer_->DidChangeNetworkBusy(sent_busy_);
}

void PageNetworkActivity::DidCommitNavigation(const Document& document) {
  document_ = &document;
  in_flight_.Reset();
  Update();
}

void PageNetworkActivity::WillSendRequest(const Document& document,
                                          const ResourceRequest& request) {
  // A document installed without a commit (an XSLT result) replaces the
  // committed one.
  if (document_ != &document) {
    if (GetSupplementable()->GetDocument() != &document) {
      return;
    }
    document_ = &document;
    in_flight_.Reset();
  }
  if (!request.InspectorId() || StaysOpen(request)) {
    return;
  }
  in_flight_.Start(request.InspectorId(), NowMs());
  Update();
}

void PageNetworkActivity::DidFinishRequest(const Document& document,
                                           uint64_t identifier) {
  if (document_ != &document) {
    return;
  }
  in_flight_.Finish(identifier);
  Update();
}

void PageNetworkActivity::ExpiryTimerFired(TimerBase*) {
  Update();
}

void PageNetworkActivity::Update() {
  const int64_t now = NowMs();
  const std::optional<int64_t> until = in_flight_.BusyUntil(now);
  // A later start only moves `until` on, and the timer rechecks when it
  // fires; a finish can move it back.
  if (!until) {
    expiry_timer_.Stop();
  } else if (!expiry_timer_.IsActive() || expiry_due_ > *until) {
    expiry_due_ = *until;
    expiry_timer_.StartOneShot(base::Milliseconds(*until - now), FROM_HERE);
  }
  busy_until_ = until;
  if (until.has_value() != sent_busy_ && !send_timer_.IsActive()) {
    send_timer_.StartOneShot(base::TimeDelta(), FROM_HERE);
  }
}

void PageNetworkActivity::Send(TimerBase*) {
  const bool busy = busy_until_.has_value();
  if (busy == sent_busy_ || !observer_.is_bound()) {
    return;
  }
  sent_busy_ = busy;
  observer_->DidChangeNetworkBusy(busy);
}

}  // namespace blink
