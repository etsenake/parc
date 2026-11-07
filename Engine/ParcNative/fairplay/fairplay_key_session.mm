#include "fairplay_key_session.h"

#import <AVFoundation/AVFoundation.h>

#include <algorithm>
#include <deque>
#include <map>
#include <set>

#include "fairplay_key_session_internal.h"

#if !__has_feature(objc_arc)
#error "This file requires ARC."
#endif

using parc::fairplay::FairPlayCdm;
using parc::fairplay::PostTask;

namespace {
// AVFoundation reports a response that produced a key whose output is
// restricted with this code; WebKit treats it as success plus
// output-restricted, and so does this session.
constexpr NSInteger kSecurityLevelError = -42811;
// Request options AVFoundation hands back on AVContentKeyRequest.options; they
// route each request to its EME session and plan entry.
NSString* const kSessionOption = @"ParcFairPlaySession";
NSString* const kCallOption = @"ParcFairPlayCall";
// WebKit's key for the init data type in the same dictionary.
NSString* const kInitDataTypeOption = @"InitializationDataType";
}  // namespace

@interface PCFairPlayContentKeyDelegate : NSObject <AVContentKeySessionDelegate>
- (instancetype)initWithImpl:(std::weak_ptr<FairPlayCdm::Impl>)impl
                      poster:(std::shared_ptr<const PostTask>)poster;
@end

namespace parc::fairplay {

const char* KeyStatusName(KeyStatus status) {
  switch (status) {
    case KeyStatus::kUsable:
      return "usable";
    case KeyStatus::kInternalError:
      return "internal-error";
    case KeyStatus::kExpired:
      return "expired";
    case KeyStatus::kOutputRestricted:
      return "output-restricted";
    case KeyStatus::kOutputDownscaled:
      return "output-downscaled";
    case KeyStatus::kStatusPending:
      return "status-pending";
    case KeyStatus::kReleased:
      return "released";
  }
  return "";
}

namespace {

NSData* ToNSData(const std::vector<uint8_t>& bytes) {
  return [NSData dataWithBytes:bytes.data() length:bytes.size()];
}

std::vector<uint8_t> ToVector(NSData* data) {
  const uint8_t* bytes = static_cast<const uint8_t*>(data.bytes);
  return std::vector<uint8_t>(bytes, bytes + data.length);
}

std::string DescribeError(NSError* error) {
  std::string text;
  for (int depth = 0; error && depth < 4; ++depth) {
    if (depth) {
      text += " <- ";
    }
    text += std::string(error.domain.UTF8String) + " " + std::to_string(error.code);
    if (error.localizedDescription.length) {
      text += " (" + std::string(error.localizedDescription.UTF8String) + ")";
    }
    if (NSString* reason = error.localizedFailureReason) {
      text += " [" + std::string(reason.UTF8String) + "]";
    }
    error = error.userInfo[NSUnderlyingErrorKey];
  }
  return text;
}

Result Failure(Exception exception, const std::string& what, NSError* error = nil) {
  std::string message = what;
  if (error) {
    message += ": " + DescribeError(error);
  }
  return Result::Error(exception, message, error ? static_cast<uint32_t>(error.code) : 0);
}

NSError* CancelledKeyRequestError() {
  return [NSError errorWithDomain:@"PCFairPlayError"
                             code:-5
                         userInfo:@{NSLocalizedDescriptionKey : @"key request cancelled"}];
}

bool HasReceivedResponse(AVContentKeyRequest* request) {
  AVContentKeyRequestStatus status = request.status;
  return status == AVContentKeyRequestStatusReceivedResponse ||
         status == AVContentKeyRequestStatusRenewed ||
         request.error.code == kSecurityLevelError;
}

void AddUnique(std::vector<std::vector<uint8_t>>* list, const std::vector<uint8_t>& item) {
  if (std::find(list->begin(), list->end(), item) == list->end()) {
    list->push_back(item);
  }
}

}  // namespace

class FairPlayCdm::Impl : public std::enable_shared_from_this<FairPlayCdm::Impl> {
 public:
  struct Request {
    AVContentKeyRequest* request = nil;  // The answered (or first) request.
    // A renewal in flight. The answered request and its key stay in use until
    // it succeeds (then it replaces them) or fails (then it is dropped).
    AVContentKeyRequest* renewal = nil;
    // A renewal whose response AVFoundation was processing when it started
    // another: its outcome still settles that update(), as WebKit's callback
    // settles on whichever request reports.
    AVContentKeyRequest* answered_renewal = nil;
    AVContentKey* key = nil;  // The last key a response produced.
    int call = -1;                               // Plan entry that produced it.
    std::vector<std::vector<uint8_t>> key_ids;  // 16-byte key IDs.
    std::vector<uint8_t> content_identifier;     // SPC content identifier.
    std::vector<uint8_t> reported_key_id;
    NSData* spc = nil;
    NSError* error = nil;
    bool awaiting_response = false;
    // Order of the message awaiting a response among the session's messages.
    uint64_t message_order = 0;
    // An HLS asset's skd loading request this entry answers (its own SPC and
    // CKC, fairplay_hls_keys.h); |request| is nil then.
    AVAssetResourceLoadingRequest* loading = nil;
    AssetKeyClient* loading_owner = nullptr;
    std::string loading_uri;
    bool loading_answered = false;
    bool loading_cancelled = false;  // Cancelled by AVFoundation, released or abandoned.
    bool loading_failed = false;     // Its SPC or answer failed.
  };

  struct Asset {
    AssetKeyClient* client = nullptr;
    AVURLAsset* asset = nil;
    bool output_obscured = false;
  };

  // Requests whose SPCs go out together in one message.
  struct Batch {
    std::vector<Request*> requests;
    size_t expected = 0;
    size_t pending_spcs = 0;
    MessageType type = MessageType::kLicenseRequest;
  };

  struct Session {
    std::string id;
    SessionType type = SessionType::kTemporary;
    InitDataPlan plan;
    std::vector<std::unique_ptr<Request>> requests;
    std::vector<Batch> batches;
    SessionCallback generate_done;
    ResultCallback update_done;
    // update("renew"), settled when the renewal message goes out (WebKit's
    // didProvideRenewingRequest) or the renewal fails.
    ResultCallback renew_done;
    uint64_t messages_sent = 0;  // License messages sent so far.
    // update() calls made while one is in flight run in order after it.
    std::deque<std::pair<std::vector<uint8_t>, ResultCallback>> queued_updates;
    std::set<Request*> update_pending;
    bool update_succeeded = false;
    NSError* update_error = nil;
    size_t last_usable_count = 0;
    std::vector<KeyInfo> last_keys;  // As last reported.
    bool keys_removed = false;
    std::string skd_uri;  // The init data of an skd session.
    // Expired-session reports matching this session, found by remove() (or
    // load()), as WebKit's m_expiredSessions; update("acknowledged") removes
    // them from the storage.
    std::vector<NSData*> expired_reports;
    // Made by LoadSession: its key statuses are the loaded reports' and stay
    // (it has no key requests of its own).
    bool loaded = false;
  };

  Impl(FairPlayCdmClient* client, PostTask post_task)
      : client_(client), poster_(std::make_shared<const PostTask>(std::move(post_task))) {}

  ~Impl() { Shutdown(); }

  // Promise and client callbacks always run in a later task on the owner
  // sequence, never inside a call into the key system, so they can call back
  // in (close the session, update it) without meeting half-updated state.
  ResultCallback Posted(ResultCallback done) const {
    std::shared_ptr<const PostTask> poster = poster_;
    return [poster, done](const Result& result) { (*poster)([done, result] { done(result); }); };
  }

  SessionCallback Posted(SessionCallback done) const {
    std::shared_ptr<const PostTask> poster = poster_;
    return [poster, done](const Result& result, const std::string& id) {
      (*poster)([done, result, id] { done(result, id); });
    };
  }

  void Deliver(std::function<void(FairPlayCdmClient*)> call) {
    std::weak_ptr<Impl> weak = weak_from_this();
    (*poster_)([weak, call] {
      if (auto impl = weak.lock()) {
        call(impl->client_);
      }
    });
  }

  // Expiring the shared session makes every recipient inoperable, so it
  // happens only when the key system goes away. Loading requests a session
  // took and didn't answer fail, so AVFoundation asks for them again.
  void Shutdown() {
    for (auto& [id, session] : sessions_) {
      ReleaseLoading(session.get());
    }
    sessions_.clear();
    assets_.clear();
    waiting_for_loading_.clear();
    [av_session_ expire];
    av_session_ = nil;
  }

  Result AttachRecipient(id<AVContentKeyRecipient> recipient) {
    if (!EnsureSession()) {
      return Result::Error(Exception::kNotSupported, "AVContentKeySession unavailable");
    }
    if (![av_session_.contentKeyRecipients containsObject:recipient]) {
      @try {
        [av_session_ addContentKeyRecipient:recipient];
      } @catch (NSException* exception) {
        return Result::Error(Exception::kInvalidState,
                             std::string("addContentKeyRecipient: ") +
                                 (exception.reason.UTF8String ?: ""));
      }
    }
    // Tracked once attached, for the key session a legacy secure stop makes
    // next (EnsureSession).
    if (![recipients_ containsObject:recipient]) {
      [recipients_ addObject:recipient];
    }
    return Result::Ok();
  }

  void DetachRecipient(id<AVContentKeyRecipient> recipient) {
    [recipients_ removeObject:recipient];
    @try {
      [av_session_ removeContentKeyRecipient:recipient];
    } @catch (NSException*) {
    }
  }

  void SetPersistentStateAllowed(bool allowed) { persistent_state_allowed_ = allowed; }

  // WebKit's setStorageDirectory, except that it also moves aside a file found
  // at the directory's path (its older storage layout), which Parc never wrote.
  void SetStorageDirectory(const std::string& directory) {
    storage_url_ = nil;
    if (directory.empty()) {
      return;
    }
    NSString* path = [NSFileManager.defaultManager
        stringWithFileSystemRepresentation:directory.c_str()
                                    length:directory.size()];
    BOOL is_directory = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&is_directory]) {
      if (![NSFileManager.defaultManager createDirectoryAtPath:path
                                   withIntermediateDirectories:YES
                                                    attributes:nil
                                                         error:nil]) {
        return;
      }
    } else if (!is_directory) {
      return;
    }
    storage_url_ = [NSURL fileURLWithPath:[path stringByAppendingPathComponent:@"SecureStop.plist"]
                              isDirectory:NO];
  }

  void SetServerCertificate(std::vector<uint8_t> certificate, ResultCallback done) {
    if (certificate.empty()) {
      done(Result::Error(Exception::kTypeError, "empty server certificate"));
      return;
    }
    certificate_ = ToNSData(certificate);
    done(Result::Ok());
  }

  void CreateSession(SessionType session_type,
                     InitDataType type,
                     std::vector<uint8_t> init_data,
                     SessionCallback done) {
    // WebKit checks the license type first (requestLicense,
    // isLicenseTypeSupported): persistent-usage-record needs persistent state
    // and AVFoundation's expired-session reports.
    if (session_type == SessionType::kPersistentUsageRecord &&
        !(persistent_state_allowed_ && SupportsPersistableState())) {
      done(Result::Error(Exception::kNotSupported,
                         "persistent-usage-record needs persistent state"),
           "");
      return;
    }
    // Every failure from here is WebKit's NotSupportedError: requestLicense
    // fails without a certificate, and init data its supportsInitData refuses
    // (sinf, skd and mpts are sanitized as they are) never reaches it.
    if (!certificate_) {
      done(Result::Error(Exception::kNotSupported, "server certificate not set"), "");
      return;
    }
    InitDataPlan plan = PlanContentKeyRequests(type, init_data);
    if (!plan.error.empty()) {
      done(Result::Error(Exception::kNotSupported, plan.error), "");
      return;
    }
    if (plan.legacy_secure_stop != LegacySecureStop::kNone) {
      CreateLegacySecureStopSession(session_type, plan.legacy_secure_stop, std::move(done));
      return;
    }
    if (!EnsureSession()) {
      done(Result::Error(Exception::kNotSupported, "AVContentKeySession unavailable"), "");
      return;
    }
    // An HLS asset asks for its key by the skd URI itself, so with an asset
    // attached the request is named by the URI with the URI (or a legacy
    // session's contentId) as content identifier (WebKit), not through the
    // key ID the MSE route's renderers match on. It takes the asset's held
    // loading request, or waits for the asset to ask.
    enum class Route { kPlan, kLoading, kAwaitLoading };
    Route route = Route::kPlan;
    std::string uri;
    AVAssetResourceLoadingRequest* loading = nil;
    AssetKeyClient* loading_owner = nullptr;
    if (type == InitDataType::kSkd && !assets_.empty() && !plan.skd_uri.empty() &&
        !plan.calls.empty()) {
      uri = plan.skd_uri;
      ContentKeyRequestPlan call;
      call.identifier = uri;
      call.content_identifier = plan.calls.front().content_identifier;
      plan.calls.assign(1, call);
      route = Route::kAwaitLoading;
      for (const Asset& asset : assets_) {
        if ((loading = asset.client->TakeLoadingRequest(uri))) {
          loading_owner = asset.client;
          route = Route::kLoading;
          break;
        }
      }
    }
    auto session = std::make_unique<Session>();
    session->id = NewSessionId();
    session->type = session_type;
    session->plan = std::move(plan);
    session->generate_done = std::move(done);
    session->skd_uri = session->plan.skd_uri;
    // Raw sessions send one SPC per message; JSON sessions batch every key the
    // init data names.
    if (session->plan.json_messages) {
      session->batches.push_back({{}, session->plan.calls.size(), 0, MessageType::kLicenseRequest});
    } else {
      for (size_t i = 0; i < session->plan.calls.size(); ++i) {
        session->batches.push_back({{}, 1, 0, MessageType::kLicenseRequest});
      }
    }
    Session* raw = session.get();
    sessions_[raw->id] = std::move(session);
    switch (route) {
      case Route::kPlan:
        break;
      case Route::kLoading:
        AdoptLoading(raw, loading_owner, uri, loading, MessageType::kLicenseRequest);
        break;
      case Route::kAwaitLoading:
        waiting_for_loading_[uri].push_back(raw->id);
        break;
    }
    for (size_t i = 0; route == Route::kPlan && i < raw->plan.calls.size(); ++i) {
      const ContentKeyRequestPlan& call = raw->plan.calls[i];
      NSString* identifier = call.identifier.empty() ? nil : @(call.identifier.c_str());
      NSData* initialization_data =
          call.initialization_data.empty() ? nil : ToNSData(call.initialization_data);
      NSDictionary* options = @{
        kSessionOption : @(raw->id.c_str()),
        kCallOption : @(i),
        kInitDataTypeOption : @(InitDataTypeName(type)),
      };
      [av_session_ processContentKeyRequestWithIdentifier:identifier
                                       initializationData:initialization_data
                                                  options:options];
    }
    // No timeout, as WebKit's requestLicense: generateRequest settles when
    // AVFoundation provides or fails the request, or, for a session waiting
    // on an HLS asset, whenever the asset asks for the URI. A request
    // AVFoundation drops without a delegate call (a FairPlay pssh naming no
    // key) stays pending, as in Safari.
  }

  // EME lets a page call update() again before the last one settled
  // (licenses fetched in parallel); those run in order.
  void UpdateSession(const std::string& session_id,
                     std::vector<uint8_t> response,
                     ResultCallback done) {
    Session* session = Find(session_id);
    if (session && (session->update_done || session->renew_done ||
                    !session->queued_updates.empty())) {
      session->queued_updates.push_back({std::move(response), std::move(done)});
      return;
    }
    UpdateSessionNow(session_id, std::move(response), std::move(done));
  }

  void StartQueuedUpdate(const std::string& session_id) {
    std::weak_ptr<Impl> weak = weak_from_this();
    (*poster_)([weak, session_id] {
      auto impl = weak.lock();
      Session* session = impl ? impl->Find(session_id) : nullptr;
      if (!session || session->update_done || session->renew_done ||
          session->queued_updates.empty()) {
        return;
      }
      auto [response, done] = std::move(session->queued_updates.front());
      session->queued_updates.pop_front();
      impl->UpdateSessionNow(session_id, std::move(response), std::move(done));
    });
  }

  void UpdateSessionNow(const std::string& session_id,
                        std::vector<uint8_t> response,
                        ResultCallback inner_done) {
    // Whatever way this update settles, the next queued one starts after it.
    std::weak_ptr<Impl> weak = weak_from_this();
    ResultCallback done = [weak, session_id, inner_done](const Result& result) {
      inner_done(result);
      if (auto impl = weak.lock()) {
        impl->StartQueuedUpdate(session_id);
      }
    };
    Session* session = Find(session_id);
    // WebKit's updateLicense: once remove() or load() found expired-session
    // reports, "acknowledged" removes them from the storage. They stay the
    // session's, so another "acknowledged" asks again. A failure is WebKit's
    // TypeError.
    static constexpr char kAcknowledged[] = "acknowledged";
    if (session && !session->expired_reports.empty() &&
        std::string(response.begin(), response.end()) == kAcknowledged) {
      if (!certificate_ || !storage_url_) {
        done(Result::Error(Exception::kTypeError, "no server certificate or storage"));
        return;
      }
      NSMutableArray<NSData*>* reports = [NSMutableArray array];
      for (NSData* report : session->expired_reports) {
        [reports addObject:report];
      }
      [AVContentKeySession removePendingExpiredSessionReports:reports
                                            withAppIdentifier:certificate_
                                        storageDirectoryAtURL:storage_url_];
      done(Result::Ok());
      return;
    }
    // A closed session is the IDL's InvalidStateError; every other failure
    // of update() is WebKit's TypeError (MediaKeySession::update rejects
    // whatever updateLicense fails with).
    if (!session) {
      done(Result::Error(Exception::kInvalidState, "session is closed"));
      return;
    }
    if (session->keys_removed) {
      done(Result::Error(Exception::kTypeError, "session is removed"));
      return;
    }
    static constexpr char kRenew[] = "renew";
    if (std::string(response.begin(), response.end()) == kRenew) {
      for (auto it = session->requests.rbegin(); it != session->requests.rend(); ++it) {
        if (HasReceivedResponse((*it)->request) && !(*it)->renewal) {
          session->renew_done = std::move(done);
          [av_session_ renewExpiringResponseDataForContentKeyRequest:(*it)->request];
          return;
        }
      }
      done(Result::Error(Exception::kTypeError, "no key to renew"));
      return;
    }
    // Oldest message first: a raw response answers the message that went out
    // first, as WebKit answers its current request and sends the next only
    // after it (CDMInstanceSessionFairPlayStreamingAVFObjC::nextRequest).
    std::vector<Request*> awaiting;
    for (auto& request : session->requests) {
      if (request->awaiting_response) {
        awaiting.push_back(request.get());
      }
    }
    std::stable_sort(awaiting.begin(), awaiting.end(), [](const Request* a, const Request* b) {
      return a->message_order < b->message_order;
    });
    if (awaiting.empty()) {
      done(Result::Error(Exception::kTypeError, "no license request awaits a response"));
      return;
    }
    if (response.empty()) {
      done(Result::Error(Exception::kTypeError, "empty license response"));
      return;
    }

    std::vector<std::pair<Request*, NSData*>> responses;
    std::vector<std::pair<Request*, NSInteger>> errors;
    if (!session->plan.json_messages) {
      responses.push_back({awaiting.front(), ToNSData(response)});
    } else {
      NSArray* entries = [NSJSONSerialization JSONObjectWithData:ToNSData(response)
                                                         options:0
                                                           error:nil];
      // The response comes from the page: validate every entry before acting
      // on any of them.
      if (![entries isKindOfClass:[NSArray class]] || !entries.count) {
        done(Result::Error(Exception::kTypeError, "license response is not a non-empty JSON array"));
        return;
      }
      std::set<std::vector<uint8_t>> named;
      std::set<Request*> answered;
      for (id item in entries) {
        if (![item isKindOfClass:[NSDictionary class]]) {
          done(Result::Error(Exception::kTypeError, "license response entry is not an object"));
          return;
        }
        NSDictionary* entry = item;
        NSString* key_id_string = entry[@"keyID"];
        NSData* key_id = [key_id_string isKindOfClass:[NSString class]]
                             ? [[NSData alloc] initWithBase64EncodedString:key_id_string options:0]
                             : nil;
        if (!key_id.length) {
          done(Result::Error(Exception::kTypeError, "license response entry has no keyID"));
          return;
        }
        std::vector<uint8_t> key = ToVector(key_id);
        if (!named.insert(key).second) {
          done(Result::Error(Exception::kTypeError, "license response names a key twice"));
          return;
        }
        // An entry answers the request whose message entry carried its keyID;
        // only a keyID no request reports falls back to a request whose init
        // data names it (one request standing for several keys).
        auto match = std::find_if(awaiting.begin(), awaiting.end(),
                                  [&](Request* request) { return request->reported_key_id == key; });
        if (match == awaiting.end()) {
          match = std::find_if(awaiting.begin(), awaiting.end(), [&](Request* request) {
            return std::find(request->key_ids.begin(), request->key_ids.end(), key) !=
                   request->key_ids.end();
          });
        }
        if (match == awaiting.end()) {
          done(Result::Error(Exception::kTypeError,
                             "license response names a key with no pending request"));
          return;
        }
        if (!answered.insert(*match).second) {
          done(Result::Error(Exception::kTypeError,
                             "license response answers one key request twice"));
          return;
        }
        id payload = entry[@"payload"];
        id error = entry[@"error"];
        if ((payload != nil) == (error != nil)) {
          done(Result::Error(Exception::kTypeError,
                             "license response entry needs exactly one of payload or error"));
          return;
        }
        if (error) {
          if (![error isKindOfClass:[NSNumber class]]) {
            done(Result::Error(Exception::kTypeError, "license response error is not a number"));
            return;
          }
          errors.push_back({*match, [error integerValue]});
          continue;
        }
        NSData* ckc = [payload isKindOfClass:[NSString class]]
                          ? [[NSData alloc] initWithBase64EncodedString:payload options:0]
                          : nil;
        if (!ckc.length) {
          done(Result::Error(Exception::kTypeError, "license response payload isn't base64"));
          return;
        }
        responses.push_back({*match, ckc});
      }
    }

    session->update_succeeded = false;
    session->update_error = nil;
    for (auto& [request, code] : errors) {
      request->awaiting_response = false;
      [Active(*request)
          processContentKeyResponseError:[NSError errorWithDomain:@"PCFairPlayLicenseError"
                                                             code:code
                                                         userInfo:nil]];
    }
    for (auto& [request, ckc] : responses) {
      request->awaiting_response = false;
      session->update_pending.insert(request);
    }
    if (session->update_pending.empty()) {
      NotifyKeyStatuses(session, /*always=*/true);
      done(Result::Ok());
      return;
    }
    // Settles when AVFoundation succeeds or fails each answered request, with
    // no timeout, as WebKit's updateLicense.
    session->update_done = std::move(done);
    std::vector<Request*> answered_loading;
    for (auto& [request, ckc] : responses) {
      if (request->loading) {
        AnswerLoading(request, ckc);
        answered_loading.push_back(request);
        continue;
      }
      AVContentKeyResponse* key_response =
          [AVContentKeyResponse contentKeyResponseWithFairPlayStreamingKeyResponseData:ckc];
      [Active(*request) processContentKeyResponse:key_response];
    }
    // A loading request has no later callback: AVFoundation takes the CKC
    // with the request's data, so it settles here.
    for (Request* request : answered_loading) {
      session = Find(session_id);
      if (!session) {
        return;
      }
      Settle(session, request,
             request->loading_answered ? nil : (request->error ?: CancelledKeyRequestError()));
    }
  }

  void CloseSession(const std::string& session_id, ResultCallback done) {
    auto it = sessions_.find(session_id);
    if (it == sessions_.end()) {
      done(Result::Error(Exception::kInvalidState, "unknown session"));
      return;
    }
    std::unique_ptr<Session> session = std::move(it->second);
    sessions_.erase(it);
    RejectPending(session.get(), "session closed");
    RevokeKeys(session.get());
    AbandonLoading(session.get());
    done(Result::Ok());
    Deliver([session_id](FairPlayCdmClient* client) { client->OnSessionClosed(session_id); });
    NotifyObservers();
  }

  void RemoveSession(const std::string& session_id, ResultCallback done) {
    Session* session = Find(session_id);
    if (!session) {
      done(Result::Error(Exception::kInvalidState, "unknown session"));
      return;
    }
    if (session->generate_done) {
      done(Result::Error(Exception::kInvalidState, "license request still pending"));
      return;
    }
    RejectPending(session, "session removed");
    // WebKit's CDMInstanceSessionFairPlayStreamingAVFObjC::removeSessionData:
    // the session's keys are expired (its key group revokes them), then a
    // persistent-usage-record session looks for AVFoundation's expired-session
    // reports whose PlaybackSessionID is its session ID. Each one found counts
    // as a released key with no key ID, and the reports go to the page as the
    // license-release message (one report's dictionary, or an array of them,
    // as a binary property list). Any other session type fails (NotSupported)
    // after reporting no keys.
    RevokeKeys(session);
    AbandonLoading(session);
    session->keys_removed = true;
    std::vector<KeyInfo> released;
    std::vector<uint8_t> release_message;
    Result result = Result::Error(Exception::kNotSupported,
                                  "only persistent-usage-record sessions have data to remove");
    if (session->type == SessionType::kPersistentUsageRecord) {
      if (!persistent_state_allowed_ || !storage_url_ || !certificate_) {
        result = Result::Error(Exception::kNotSupported,
                               "no persistent state, storage or server certificate");
      } else {
        NSMutableArray* matching = [NSMutableArray array];
        for (NSData* report : ExpiredSessionReports(session->id)) {
          released.push_back({{}, KeyStatus::kReleased, 0});
          // Appended as WebKit appends to m_expiredSessions, also after a
          // load() already holds the report; removing it twice is harmless.
          session->expired_reports.push_back(report);
          [matching addObject:[NSPropertyListSerialization propertyListWithData:report
                                                                        options:NSPropertyListImmutable
                                                                         format:nil
                                                                          error:nil]];
        }
        if (matching.count) {
          id property_list = matching.count == 1 ? matching.firstObject : matching;
          NSData* data =
              [NSPropertyListSerialization dataWithPropertyList:property_list
                                                         format:NSPropertyListBinaryFormat_v1_0
                                                        options:0
                                                          error:nil];
          release_message = ToVector(data);
        }
        result = Result::Ok();
      }
    }
    // WebKit runs the Update Key Statuses algorithm with those keys whether or
    // not any were found, so keystatuseschange always fires.
    session->last_keys = released;
    session->last_usable_count = 0;
    std::string id = session->id;
    Deliver([id, released](FairPlayCdmClient* client) {
      client->OnSessionKeysChange(id, false, released);
    });
    if (!release_message.empty()) {
      Deliver([id, release_message](FairPlayCdmClient* client) {
        client->OnSessionMessage(id, MessageType::kLicenseRelease, release_message);
      });
    }
    NotifyObservers();
    done(result);
  }

  void LoadSession(SessionType session_type, const std::string& session_id, SessionCallback done) {
    // WebKit's CDMInstanceSessionFairPlayStreamingAVFObjC::loadSession, which
    // loads only persistent-usage-record sessions.
    if (session_type != SessionType::kPersistentUsageRecord) {
      done(Result::Error(Exception::kNotSupported, "only persistent-usage-record sessions load"), "");
      return;
    }
    // SessionLoadFailure::MismatchedSessionType: a TypeError.
    if (!persistent_state_allowed_ || !storage_url_) {
      done(Result::Error(Exception::kTypeError, "no persistent state or storage"), "");
      return;
    }
    // SessionLoadFailure::NoSessionData: load() resolves false.
    if (!certificate_) {
      done(Result::Ok(), "");
      return;
    }
    // MediaKeySession::load's step 8.3, which Chromium leaves to the CDM.
    if (Find(session_id)) {
      done(Result::Error(Exception::kQuotaExceeded, "a session with this ID is open"), "");
      return;
    }
    std::vector<NSData*> reports = ExpiredSessionReports(session_id);
    if (reports.empty()) {
      done(Result::Ok(), "");
      return;
    }
    // Each report is a released key with no key ID (WebKit's FIXME: the
    // report's key values aren't available).
    std::vector<KeyInfo> released(reports.size(), KeyInfo{{}, KeyStatus::kReleased, 0});
    auto session = std::make_unique<Session>();
    session->id = session_id;
    session->type = SessionType::kPersistentUsageRecord;
    session->loaded = true;
    session->expired_reports = std::move(reports);
    session->last_keys = released;
    sessions_[session_id] = std::move(session);
    // The session ID first, so the page's session exists when the statuses
    // arrive (Blink routes them by ID); WebKit also resolves load() before
    // its keystatuseschange event runs.
    done(Result::Ok(), session_id);
    Deliver([session_id, released](FairPlayCdmClient* client) {
      client->OnSessionKeysChange(session_id, false, released);
    });
    NotifyObservers();
  }

  // WebKit's legacy secure stop (CDMSessionAVContentKeySession, through
  // parc_webkit_media_keys.h): a session holding one expired-session report,
  // sent raw as its license-release message, which "acknowledged" removes as
  // for remove(). kSession is releaseKeys: the key session expires, and the
  // report is the one whose PlaybackSessionID is that key session's
  // contentProtectionSessionIdentifier (WebKit's legacy session ID; each
  // legacy MediaKeys has its own key session). The next session gets a new
  // key session, which the attached renderers join. kFirst is
  // generateKeyReleaseMessage: the first pending report for the server
  // certificate. No report (none for the key session, none at all), or no
  // persistent state and storage (a private window), fails with WebKit's
  // KeySystemNotSupported '!mor' and leaves no session. A page reaching this
  // through modern EME expires only its own MediaKeys' key session.
  void CreateLegacySecureStopSession(SessionType session_type,
                                     LegacySecureStop operation,
                                     SessionCallback done) {
    static constexpr uint32_t kNoExpiredSessions = 0x216d6f72;  // '!mor'
    if (!persistent_state_allowed_ || !storage_url_ || !SupportsPersistableState()) {
      done(Result::Error(Exception::kNotSupported, "no expired-session storage",
                         kNoExpiredSessions),
           "");
      return;
    }
    NSString* playback_session_id = nil;
    if (operation == LegacySecureStop::kSession && av_session_) {
      NSData* identifier = av_session_.contentProtectionSessionIdentifier;
      if (identifier) {
        playback_session_id = [[NSString alloc] initWithData:identifier
                                                    encoding:NSUTF8StringEncoding];
      }
      [av_session_ expire];
      av_session_ = nil;
      delegate_ = nil;
    }
    NSData* report = nil;
    for (NSData* data in [AVContentKeySession pendingExpiredSessionReportsWithAppIdentifier:certificate_
                                                                    storageDirectoryAtURL:storage_url_]) {
      if (operation == LegacySecureStop::kFirst) {
        report = data;
        break;
      }
      id dictionary = [NSPropertyListSerialization propertyListWithData:data
                                                                options:NSPropertyListImmutable
                                                                 format:nil
                                                                  error:nil];
      id id_value = [dictionary isKindOfClass:[NSDictionary class]]
                        ? dictionary[@"PlaybackSessionID"]
                        : nil;
      if (playback_session_id && [id_value isKindOfClass:[NSString class]] &&
          [id_value isEqualToString:playback_session_id]) {
        report = data;
        break;
      }
    }
    if (!report) {
      done(Result::Error(Exception::kNotSupported, "no expired-session report",
                         kNoExpiredSessions),
           "");
      return;
    }
    auto session = std::make_unique<Session>();
    session->id = NewSessionId();
    session->type = session_type;
    session->keys_removed = true;  // It never asks for keys.
    session->expired_reports.push_back(report);
    std::string id = session->id;
    sessions_[id] = std::move(session);
    done(Result::Ok(), id);
    std::vector<uint8_t> message = ToVector(report);
    Deliver([id, message](FairPlayCdmClient* client) {
      client->OnSessionMessage(id, MessageType::kLicenseRelease, message);
    });
  }

  // AVFoundation's pending expired-session reports in this key system's
  // storage, for the server certificate (the app identifier), whose
  // PlaybackSessionID is |session_id|: WebKit compares that string with its
  // session ID exactly. Needs persistent state, storage and a certificate.
  std::vector<NSData*> ExpiredSessionReports(const std::string& session_id) const {
    std::vector<NSData*> found;
    if (!persistent_state_allowed_ || !storage_url_ || !certificate_ ||
        !SupportsPersistableState()) {
      return found;
    }
    NSString* wanted = @(session_id.c_str());
    for (NSData* data in [AVContentKeySession pendingExpiredSessionReportsWithAppIdentifier:certificate_
                                                                    storageDirectoryAtURL:storage_url_]) {
      id report = [NSPropertyListSerialization propertyListWithData:data
                                                             options:NSPropertyListImmutable
                                                              format:nil
                                                               error:nil];
      if (![report isKindOfClass:[NSDictionary class]]) {
        continue;
      }
      id playback_session_id = report[@"PlaybackSessionID"];
      if ([playback_session_id isKindOfClass:[NSString class]] &&
          [playback_session_id isEqualToString:wanted]) {
        found.push_back(data);
      }
    }
    return found;
  }

  uint64_t AddObserver(KeysChangedCallback callback) {
    observers_[++next_observer_] = std::move(callback);
    return next_observer_;
  }

  void RemoveObserver(uint64_t id) { observers_.erase(id); }

  // Recipients look keys up by the key ID in the sample's format description,
  // so only a received key whose request names |key_id| counts.
  AVContentKey* ContentKeyForKeyId(const std::vector<uint8_t>& key_id) const {
    for (const auto& [id, session] : sessions_) {
      if (session->keys_removed) {
        continue;
      }
      for (const auto& request : session->requests) {
        // The cached key covers a renewal in flight, which may reuse the
        // request object and clear its contentKey until it is answered.
        AVContentKey* key = request->key;
        if (!key && HasReceivedResponse(request->request)) {
          key = request->request.contentKey;
        }
        if (key && std::find(request->key_ids.begin(), request->key_ids.end(), key_id) !=
                       request->key_ids.end()) {
          return key;
        }
      }
    }
    return nil;
  }

  bool HasSessionForKeyIds(const std::vector<std::vector<uint8_t>>& key_ids) const {
    for (const auto& [id, session] : sessions_) {
      for (const auto& request : session->requests) {
        for (const auto& key_id : request->key_ids) {
          if (std::find(key_ids.begin(), key_ids.end(), key_id) != key_ids.end()) {
            return true;
          }
        }
      }
    }
    return false;
  }

  // Delegate entry points, on the owner sequence.

  void OnRequests(NSArray<AVContentKeyRequest*>* av_requests, bool renewal, bool grouped) {
    if (!av_requests.count) {
      return;
    }
    Session* session = SessionFor(av_requests.firstObject);
    if (!session) {
      return;  // Not ours (no session option and no matching request).
    }
    std::vector<Request*> added;
    for (AVContentKeyRequest* av_request in av_requests) {
      Request* request = nullptr;
      if (renewal) {
        for (auto& existing : session->requests) {
          if (existing->request == av_request ||
              [existing->request.identifier isEqual:av_request.identifier]) {
            request = existing.get();
            break;
          }
        }
      }
      if (request) {
        // Keep the answered request and its key; the renewal runs beside them.
        if (!request->key) {
          request->key = request->request.contentKey;
        }
        if (request->renewal && session->update_pending.count(request)) {
          request->answered_renewal = request->renewal;
        }
        request->renewal = av_request;
        request->spc = nil;
        added.push_back(request);
        continue;
      }
      session->requests.push_back(std::make_unique<Request>());
      request = session->requests.back().get();
      request->request = av_request;
      request->spc = nil;
      request->error = nil;
      NSNumber* call = av_request.options[kCallOption];
      if ([call isKindOfClass:[NSNumber class]]) {
        request->call = call.intValue;
      }
      DeriveIdentity(session, request);
      added.push_back(request);
    }

    // Initial requests fill the batches CreateSession laid out; anything else
    // (renewals, keys AVFoundation discovers later) is a batch of its own.
    // When one init data yields several requests at once (macOS 14.4+), a
    // JSON session sends them together.
    size_t group_batch = SIZE_MAX;
    for (Request* request : added) {
      size_t index = SIZE_MAX;
      if (grouped && session->plan.json_messages && group_batch != SIZE_MAX) {
        index = group_batch;
        ++session->batches[index].expected;
      } else {
        if (!renewal) {
          for (size_t i = 0; i < session->batches.size(); ++i) {
            const Batch& candidate = session->batches[i];
            if (candidate.type == MessageType::kLicenseRequest &&
                candidate.requests.size() < candidate.expected) {
              index = i;
              break;
            }
          }
        }
        if (index == SIZE_MAX) {
          session->batches.push_back(
              {{}, 1, 0, renewal ? MessageType::kLicenseRenewal : MessageType::kLicenseRequest});
          index = session->batches.size() - 1;
        }
      }
      group_batch = index;
      session->batches[index].requests.push_back(request);
      ++session->batches[index].pending_spcs;
    }
    for (Request* request : added) {
      MakeSpc(session, request);
    }
  }

  void OnSpc(AVContentKeyRequest* av_request, NSData* spc, NSError* error) {
    if (Session* session = SessionFor(av_request)) {
      FillSpc(session, [av_request](const Request& request) { return Active(request) == av_request; },
              spc, error);
    }
  }

  void OnLoadingSpc(const std::string& session_id,
                    AVAssetResourceLoadingRequest* loading,
                    NSData* spc,
                    NSError* error) {
    Session* session = Find(session_id);
    if (!session) {
      return;
    }
    // AVFoundation cancelled it (or it was released) while the SPC was
    // posted: no message goes out for it. Otherwise no SPC is a failure.
    for (const auto& request : session->requests) {
      if (request->loading != loading) {
        continue;
      }
      if (request->loading_cancelled) {
        spc = nil;
        error = error ?: CancelledKeyRequestError();
      } else if (!spc) {
        request->loading_failed = true;
      }
    }
    FillSpc(session, [loading](const Request& request) { return request.loading == loading; }, spc, error);
  }

  void FillSpc(Session* session,
               const std::function<bool(const Request&)>& matches,
               NSData* spc,
               NSError* error) {
    for (Batch& batch : session->batches) {
      for (Request* request : batch.requests) {
        if (matches(*request) && !request->spc && !request->error) {
          request->spc = spc;
          request->error = spc ? nil : (error ?: [NSError errorWithDomain:@"PCFairPlayError"
                                                                     code:-1
                                                                 userInfo:nil]);
          --batch.pending_spcs;
          SendReadyBatches(session);
          return;
        }
      }
    }
  }

  void OnRequestSucceeded(AVContentKeyRequest* av_request) {
    Session* session = SessionFor(av_request);
    if (Request* request = session ? FindRequest(session, av_request) : nullptr) {
      if (request->answered_renewal == av_request) {
        // Its key replaces the answered one; the newer renewal keeps running.
        request->request = av_request;
        request->answered_renewal = nil;
      } else if (request->renewal == av_request) {
        request->request = av_request;
        request->renewal = nil;
      }
      request->error = nil;
      if (AVContentKey* key = request->request.contentKey) {
        request->key = key;
      }
      Settle(session, request, nil);
    }
  }

  void OnRequestFailed(AVContentKeyRequest* av_request, NSError* error) {
    Session* session = SessionFor(av_request);
    if (!session) {
      return;
    }
    Request* request = FindRequest(session, av_request);
    if (!request) {
      // A request that failed before AVFoundation provided it: count it as a
      // failed SPC of the session's license request so generateRequest settles.
      if (session->generate_done) {
        AddFailedRequest(session, av_request, error);
      }
      return;
    }
    if (request->answered_renewal == av_request) {
      // The answered key stays in use; the newer renewal keeps running.
      request->answered_renewal = nil;
      Settle(session, request, error.code == kSecurityLevelError ? nil : error);
      return;
    }
    if (error.code == kSecurityLevelError) {
      // WebKit's requestDidSucceed: the request (a renewal too, which
      // replaced the answered one) reports output-restricted.
      if (request->renewal == av_request) {
        request->request = av_request;
        request->renewal = nil;
      }
      Settle(session, request, nil);
      return;
    }
    std::string session_id = session->id;
    const bool renewal = request->renewal == av_request;
    // A failure before the SPC exists fails that SPC (and may end the session).
    OnSpc(av_request, nil, error);
    if (!Find(session_id)) {
      return;
    }
    if (renewal) {
      // The answered request and its key stay in use.
      request->renewal = nil;
    } else {
      request->error = error;
    }
    Settle(session, request, error);
  }

  void AddFailedRequest(Session* session, AVContentKeyRequest* av_request, NSError* error) {
    session->requests.push_back(std::make_unique<Request>());
    Request* request = session->requests.back().get();
    request->request = av_request;
    request->error = error ?: [NSError errorWithDomain:@"PCFairPlayError" code:-4 userInfo:nil];
    for (Batch& batch : session->batches) {
      if (batch.type == MessageType::kLicenseRequest && batch.requests.size() < batch.expected) {
        batch.requests.push_back(request);
        break;
      }
    }
    SendReadyBatches(session);
  }

  void OnProtectionStatusChanged() {
    std::vector<std::string> ids;
    for (auto& [id, session] : sessions_) {
      ids.push_back(id);
    }
    for (const std::string& id : ids) {
      if (Session* session = Find(id)) {
        NotifyKeyStatuses(session);
      }
    }
  }

  // HLS assets (FairPlayHlsKeyLoader through fairplay_key_session_internal.h).

  Result AttachAsset(AssetKeyClient* client, AVURLAsset* asset) {
    if (FindAsset(client)) {
      return Result::Error(Exception::kInvalidState, "asset already attached");
    }
    if (!EnsureSession()) {
      return Result::Error(Exception::kNotSupported, "AVContentKeySession unavailable");
    }
    assets_.push_back({client, asset, false});
    return Result::Ok();
  }

  void DetachAsset(AssetKeyClient* client) {
    auto it = std::find_if(assets_.begin(), assets_.end(),
                           [client](const Asset& asset) { return asset.client == client; });
    if (it == assets_.end()) {
      return;
    }
    // Requests a session took and hasn't answered stay pending, as WebKit
    // leaves a detached CDM's key requests (AVFoundation doesn't ask again);
    // answered keys keep their status.
    for (auto& [id, session] : sessions_) {
      for (auto& request : session->requests) {
        if (request->loading_owner == client) {
          AbandonLoadingRequest(session.get(), request.get());
          request->loading_owner = nullptr;
        }
      }
    }
    assets_.erase(std::find_if(assets_.begin(), assets_.end(),
                               [client](const Asset& entry) { return entry.client == client; }));
    UpdateOutputObscured();
    OnProtectionStatusChanged();
  }

  bool OfferLoadingRequest(AssetKeyClient* client,
                           const std::string& uri,
                           AVAssetResourceLoadingRequest* loading) {
    if (!FindAsset(client)) {
      return false;
    }
    // A session that asked for this URI before AVFoundation did.
    auto waiting = waiting_for_loading_.find(uri);
    while (waiting != waiting_for_loading_.end() && !waiting->second.empty()) {
      std::string id = waiting->second.front();
      waiting->second.pop_front();
      Session* session = Find(id);
      if (session && session->generate_done && session->requests.empty()) {
        if (waiting->second.empty()) {
          waiting_for_loading_.erase(waiting);
        }
        AdoptLoading(session, client, uri, loading, MessageType::kLicenseRequest);
        return true;
      }
    }
    if (waiting != waiting_for_loading_.end()) {
      waiting_for_loading_.erase(waiting);
    }
    // AVFoundation asking again for a key a session took from this asset
    // after AVFoundation cancelled the earlier request (a seek, a variant
    // switch): that session sends a new license request, since pages drop
    // init data a live session already has. Asking again for a key a session
    // answered is a request no session expects, as WebKit treats it: the
    // page gets a new encrypted and answers it with a new session.
    for (auto& [id, session] : sessions_) {
      if (session->keys_removed) {
        continue;
      }
      bool answered = false;
      bool cancelled = false;
      bool pending = false;
      for (auto& request : session->requests) {
        if (request->loading_owner == client && request->loading_uri == uri) {
          answered |= request->loading_answered;
          cancelled |= !request->loading_answered && request->loading_cancelled &&
                       !request->loading_failed;
          pending |= !request->loading_answered && !request->loading_cancelled;
        }
      }
      if (!pending && !answered && cancelled) {
        AdoptLoading(session.get(), client, uri, loading, MessageType::kLicenseRequest);
        return true;
      }
    }
    // A session for this URI made before the asset was attached planned its
    // request for the MSE route; it gets the asset's request as a further
    // license request instead of the page getting a second encrypted event.
    if (Session* session = SkdSessionWithoutAssetRequest(uri)) {
      AdoptLoading(session, client, uri, loading, MessageType::kLicenseRequest);
      return true;
    }
    return false;
  }

  void CancelLoadingRequest(AssetKeyClient* client, AVAssetResourceLoadingRequest* loading) {
    for (auto& [id, session] : sessions_) {
      for (auto& request : session->requests) {
        if (request->loading == loading && request->loading_owner == client &&
            !request->loading_answered && !request->loading_cancelled) {
          if (session->generate_done) {
            // Its license request hasn't gone out (a seek during startup):
            // drop it, and the session waits for AVFoundation to ask again
            // instead of failing generateRequest.
            std::string uri = request->loading_uri;
            DropRequest(session.get(), request.get());
            waiting_for_loading_[uri].push_back(session->id);
            return;
          }
          request->loading_cancelled = true;
          request->awaiting_response = false;
          Settle(session.get(), request.get(), CancelledKeyRequestError());
          return;
        }
      }
    }
  }

  void SetAssetOutputObscured(AssetKeyClient* client, bool obscured) {
    if (Asset* asset = FindAsset(client)) {
      asset->output_obscured = obscured;
      if (UpdateOutputObscured()) {
        OnProtectionStatusChanged();
      }
    }
  }

 private:
  // WebKit's CDMInstanceFairPlayStreamingAVFObjC::supportsPersistableState.
  static bool SupportsPersistableState() {
    SEL selector = @selector(pendingExpiredSessionReportsWithAppIdentifier:storageDirectoryAtURL:);
    return [AVContentKeySession respondsToSelector:selector];
  }

  // WebKit names a session after its key group's identifier, a random UUID,
  // as uppercase hex (WebAVContentKeyGroup.contentProtectionSessionIdentifier
  // through CDMInstanceSessionFairPlayStreamingAVFObjC::
  // sessionIdentifierChanged).
  std::string NewSessionId() const {
    static constexpr char kHexDigits[] = "0123456789ABCDEF";
    while (true) {
      uuid_t bytes;
      [[NSUUID UUID] getUUIDBytes:bytes];
      std::string id;
      id.reserve(sizeof(bytes) * 2);
      for (unsigned char byte : bytes) {
        id += kHexDigits[byte >> 4];
        id += kHexDigits[byte & 0xF];
      }
      if (!Find(id)) {
        return id;
      }
    }
  }

  Asset* FindAsset(AssetKeyClient* client) {
    for (Asset& asset : assets_) {
      if (asset.client == client) {
        return &asset;
      }
    }
    return nullptr;
  }

  // True if the key system's obscured state changed.
  bool UpdateOutputObscured() {
    bool obscured = std::any_of(assets_.begin(), assets_.end(),
                                [](const Asset& asset) { return asset.output_obscured; });
    bool changed = obscured != output_obscured_;
    output_obscured_ = obscured;
    return changed;
  }

  // An open skd session for |uri| holding no request an asset made.
  Session* SkdSessionWithoutAssetRequest(const std::string& uri) {
    for (auto& [id, session] : sessions_) {
      if (session->keys_removed || session->skd_uri != uri || session->generate_done) {
        continue;
      }
      bool has_asset_request = std::any_of(session->requests.begin(), session->requests.end(),
                                           [](const auto& request) { return request->loading != nil; });
      if (!has_asset_request) {
        return session.get();
      }
    }
    return nullptr;
  }

  void AdoptLoading(Session* session,
                    AssetKeyClient* owner,
                    const std::string& uri,
                    AVAssetResourceLoadingRequest* loading,
                    MessageType type) {
    session->requests.push_back(std::make_unique<Request>());
    Request* request = session->requests.back().get();
    request->loading = loading;
    request->loading_owner = owner;
    request->loading_uri = uri;
    request->call = 0;
    request->content_identifier = session->plan.calls.empty()
                                      ? std::vector<uint8_t>(uri.begin(), uri.end())
                                      : session->plan.calls.front().content_identifier;
    request->reported_key_id = request->content_identifier;
    size_t index = SIZE_MAX;
    for (size_t i = 0; type == MessageType::kLicenseRequest && i < session->batches.size(); ++i) {
      if (session->batches[i].type == MessageType::kLicenseRequest &&
          session->batches[i].requests.size() < session->batches[i].expected) {
        index = i;
        break;
      }
    }
    if (index == SIZE_MAX) {
      session->batches.push_back({{}, 1, 0, type});
      index = session->batches.size() - 1;
    }
    session->batches[index].requests.push_back(request);
    ++session->batches[index].pending_spcs;
    MakeSpc(session, request);
  }

  // The SPC comes from the loading request itself (WebKit's legacy
  // CDMSessionAVFoundationObjC), which AVFoundation allows only while the
  // asset isn't a content key recipient (it never is). Posted like the
  // content key path.
  void MakeLoadingSpc(Session* session, Request* request) {
    NSData* spc = nil;
    NSError* error = nil;
    @try {
      // Deprecated in macOS 15 for AVContentKeySession, which a loading
      // request on this route can't use.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
      spc = [request->loading streamingContentKeyRequestDataForApp:certificate_
                                                 contentIdentifier:ToNSData(request->content_identifier)
                                                           options:nil
                                                             error:&error];
#pragma clang diagnostic pop
    } @catch (NSException* exception) {
      error = [NSError errorWithDomain:@"PCFairPlayError"
                                  code:-3
                              userInfo:@{NSLocalizedDescriptionKey : exception.reason ?: @""}];
    }
    if (!spc && !error) {
      error = [NSError errorWithDomain:@"PCFairPlayError" code:-1 userInfo:nil];
    }
    std::weak_ptr<Impl> weak = weak_from_this();
    std::string session_id = session->id;
    AVAssetResourceLoadingRequest* loading = request->loading;
    (*poster_)([weak, session_id, loading, spc, error] {
      if (auto impl = weak.lock()) {
        impl->OnLoadingSpc(session_id, loading, spc, error);
      }
    });
  }

  static void AnswerLoading(Request* request, NSData* ckc) {
    if (request->loading_cancelled) {
      return;
    }
    AVAssetResourceLoadingRequest* loading = request->loading;
    @try {
      loading.contentInformationRequest.contentType = AVStreamingKeyDeliveryContentKeyType;
      [loading.dataRequest respondWithData:ckc];
      [loading finishLoading];
      request->loading_answered = true;
    } @catch (NSException* exception) {
      request->error = [NSError errorWithDomain:@"PCFairPlayError"
                                           code:-6
                                       userInfo:@{NSLocalizedDescriptionKey : exception.reason ?: @""}];
      request->loading_cancelled = true;
      request->loading_failed = true;
      @try {
        [loading finishLoadingWithError:request->error];
      } @catch (NSException*) {
      }
    }
  }

  // An unanswered loading request fails: it gave its one SPC to this
  // session, so no other session can answer it, and AVFoundation asks for the
  // key again rather than failing the item. Settles an update waiting on it.
  void ReleaseLoadingRequest(Session* session, Request* request) {
    if (!request->loading || request->loading_answered || request->loading_cancelled) {
      return;
    }
    request->loading_cancelled = true;
    request->awaiting_response = false;
    @try {
      [request->loading
          finishLoadingWithError:[NSError errorWithDomain:@"PCFairPlayError"
                                                     code:-7
                                                 userInfo:@{NSLocalizedDescriptionKey : @"key request withdrawn"}]];
    } @catch (NSException*) {
    }
    if (session->update_pending.erase(request) && session->update_pending.empty() &&
        session->update_done) {
      ResultCallback done = std::move(session->update_done);
      done(Result::Error(Exception::kTypeError, "key request withdrawn"));
    }
  }

  void ReleaseLoading(Session* session) {
    for (auto& request : session->requests) {
      ReleaseLoadingRequest(session, request.get());
    }
  }

  // A session closed or removed, or its CDM detached, before answering: the
  // loading request stays pending, as WebKit leaves its key requests (legacy
  // releaseKeys does nothing; closing a modern session drops its requests
  // without failing them), so AVFoundation doesn't ask again. Nothing answers
  // it later. Settles an update waiting on it.
  void AbandonLoadingRequest(Session* session, Request* request) {
    if (!request->loading || request->loading_answered || request->loading_cancelled) {
      return;
    }
    request->loading_cancelled = true;
    request->awaiting_response = false;
    if (session->update_pending.erase(request) && session->update_pending.empty() &&
        session->update_done) {
      ResultCallback done = std::move(session->update_done);
      done(Result::Error(Exception::kTypeError, "key request withdrawn"));
    }
  }

  void AbandonLoading(Session* session) {
    for (auto& request : session->requests) {
      AbandonLoadingRequest(session, request.get());
    }
  }

  // Removes a request whose license request hasn't gone out.
  static void DropRequest(Session* session, Request* request) {
    for (Batch& batch : session->batches) {
      auto it = std::find(batch.requests.begin(), batch.requests.end(), request);
      if (it != batch.requests.end()) {
        if (!request->spc && !request->error && batch.pending_spcs) {
          --batch.pending_spcs;
        }
        batch.requests.erase(it);
      }
    }
    session->update_pending.erase(request);
    session->requests.erase(
        std::remove_if(session->requests.begin(), session->requests.end(),
                       [request](const std::unique_ptr<Request>& entry) { return entry.get() == request; }),
        session->requests.end());
  }
  static dispatch_queue_t DelegateQueue() {
    static dispatch_queue_t queue =
        dispatch_queue_create("parc.fairplay.content-key-session", DISPATCH_QUEUE_SERIAL);
    return queue;
  }

  bool EnsureSession() {
    if (av_session_) {
      return true;
    }
    // As WebKit's contentKeySession(): with storage only when the
    // configuration allows persistent state and there is a directory.
    if (persistent_state_allowed_ && storage_url_) {
      av_session_ =
          [AVContentKeySession contentKeySessionWithKeySystem:AVContentKeySystemFairPlayStreaming
                                        storageDirectoryAtURL:storage_url_];
    } else {
      av_session_ =
          [AVContentKeySession contentKeySessionWithKeySystem:AVContentKeySystemFairPlayStreaming];
    }
    if (!av_session_) {
      return false;
    }
    delegate_ = [[PCFairPlayContentKeyDelegate alloc] initWithImpl:weak_from_this() poster:poster_];
    [av_session_ setDelegate:delegate_ queue:DelegateQueue()];
    // A key session made after a legacy secure stop expired the last one
    // takes the renderers already attached, as WebKit's renderers join each
    // new legacy session (AudioVideoRendererAVFObjC::setCDMSession).
    for (id<AVContentKeyRecipient> recipient in recipients_) {
      @try {
        [av_session_ addContentKeyRecipient:recipient];
      } @catch (NSException*) {
      }
    }
    return true;
  }

  // The EME session a request belongs to: from its options, else (renewals,
  // which may come back without them) by matching an earlier request.
  Session* SessionFor(AVContentKeyRequest* av_request) const {
    NSString* id = av_request.options[kSessionOption];
    if ([id isKindOfClass:[NSString class]]) {
      return Find(id.UTF8String);
    }
    // The request object itself first: several sessions may hold requests
    // with one identifier.
    for (const auto& [session_id, session] : sessions_) {
      for (const auto& request : session->requests) {
        if (request->request && (request->request == av_request || request->renewal == av_request ||
                                 request->answered_renewal == av_request)) {
          return session.get();
        }
      }
    }
    for (const auto& [session_id, session] : sessions_) {
      for (const auto& request : session->requests) {
        if (request->request.identifier &&
            [request->request.identifier isEqual:av_request.identifier]) {
          return session.get();
        }
      }
    }
    return nullptr;
  }

  // Keys stay in the shared AVContentKeySession until revoked (macOS 14.4+);
  // before that a closed session's keys remain usable until the key system is
  // destroyed.
  static void RevokeKeys(Session* session) {
    for (auto& request : session->requests) {
      if (@available(macOS 14.4, *)) {
        [request->request.contentKey revoke];
        if (request->key != request->request.contentKey) {
          [request->key revoke];
        }
      }
      request->key = nil;
    }
  }

  Session* Find(const std::string& session_id) const {
    auto it = sessions_.find(session_id);
    return it == sessions_.end() ? nullptr : it->second.get();
  }

  static Request* FindRequest(Session* session, AVContentKeyRequest* av_request) {
    for (auto& request : session->requests) {
      if (request->request == av_request || request->renewal == av_request ||
          request->answered_renewal == av_request) {
        return request.get();
      }
    }
    return nullptr;
  }

  // The request an SPC and response belong to: the renewal while one runs.
  static AVContentKeyRequest* Active(const Request& request) {
    return request.renewal ?: request.request;
  }

  // Key IDs and SPC content identifier for a request. Requests made through
  // sinf or a FairPlay pssh come back named by their 16-byte key ID; WebKit's
  // CDMPrivateFairPlayStreaming::keyIDsForRequest uses that (or the UTF-8
  // identifier string) as the content identifier unless the plan names one.
  // A request named by a key ID carries that key alone, even when its call's
  // init data names several: AVFoundation makes one request per key (macOS
  // 14.4+ hands them over together), and each gets its own CKC.
  static void DeriveIdentity(Session* session, Request* request) {
    request->key_ids.clear();
    request->content_identifier.clear();
    const ContentKeyRequestPlan* call =
        request->call >= 0 && size_t(request->call) < session->plan.calls.size()
            ? &session->plan.calls[request->call]
            : nullptr;
    id identifier = request->request.identifier;
    if ([identifier isKindOfClass:[NSData class]] && [identifier length] == 16) {
      request->key_ids.push_back(ToVector(identifier));
    } else if (call) {
      for (const auto& key_id : call->key_ids) {
        AddUnique(&request->key_ids, key_id);
      }
    }
    if (call) {
      request->content_identifier = call->content_identifier;
    }
    if (request->content_identifier.empty()) {
      if ([identifier isKindOfClass:[NSString class]]) {
        const char* utf8 = [identifier UTF8String];
        request->content_identifier.assign(utf8, utf8 + strlen(utf8));
      } else if ([identifier isKindOfClass:[NSData class]]) {
        request->content_identifier = ToVector(identifier);
      } else if (!request->key_ids.empty()) {
        request->content_identifier = request->key_ids.front();
      }
    }
    request->reported_key_id =
        request->key_ids.empty() ? request->content_identifier : request->key_ids.front();
  }

  void MakeSpc(Session* session, Request* request) {
    if (request->loading) {
      MakeLoadingSpc(session, request);
      return;
    }
    AVContentKeyRequest* av_request = Active(*request);
    // Failures are posted: OnSpc can end the session, and callers loop over
    // its requests.
    auto fail = [this, av_request](NSInteger code, NSString* description) {
      std::weak_ptr<Impl> weak = weak_from_this();
      NSError* error = [NSError errorWithDomain:@"PCFairPlayError"
                                           code:code
                                       userInfo:@{NSLocalizedDescriptionKey : description ?: @""}];
      (*poster_)([weak, av_request, error] {
        if (auto impl = weak.lock()) {
          impl->OnSpc(av_request, nil, error);
        }
      });
    };
    if (request->content_identifier.empty()) {
      fail(-2, @"no content identifier");
      return;
    }
    std::weak_ptr<Impl> weak = weak_from_this();
    std::shared_ptr<const PostTask> poster = poster_;
    @try {
      [av_request makeStreamingContentKeyRequestDataForApp:certificate_
                                         contentIdentifier:ToNSData(request->content_identifier)
                                                   options:nil
                                         completionHandler:^(NSData* spc, NSError* error) {
                                           (*poster)([weak, av_request, spc, error] {
                                             if (auto impl = weak.lock()) {
                                               impl->OnSpc(av_request, spc, error);
                                             }
                                           });
                                         }];
    } @catch (NSException* exception) {
      fail(-3, exception.reason);
    }
  }

  void SendReadyBatches(Session* session) {
    while (!session->batches.empty()) {
      Batch& batch = session->batches.front();
      if (batch.requests.size() < batch.expected || batch.pending_spcs) {
        return;
      }
      Batch ready = std::move(batch);
      session->batches.erase(session->batches.begin());
      std::vector<Request*> produced;
      NSError* first_error = nil;
      for (Request* request : ready.requests) {
        if (request->spc) {
          produced.push_back(request);
        } else if (!first_error) {
          first_error = request->error;
        }
      }
      std::string session_id = session->id;
      // A loading request without an SPC fails (AVFoundation asks again).
      for (Request* request : ready.requests) {
        if (!request->spc) {
          ReleaseLoadingRequest(session, request);
        }
      }
      if (produced.empty()) {
        if (session->generate_done) {
          SessionCallback done = std::move(session->generate_done);
          ReleaseLoading(session);
          sessions_.erase(session_id);
          done(Failure(Exception::kNotSupported, "license request failed", first_error), "");
          return;
        }
        if (ready.type == MessageType::kLicenseRenewal && session->renew_done) {
          ResultCallback renewed = std::move(session->renew_done);
          renewed(Failure(Exception::kTypeError, "license renewal failed", first_error));
          session = Find(session_id);
          if (!session) {
            return;
          }
        }
        NotifyKeyStatuses(session);
        continue;
      }
      NSData* message = nil;
      if (session->plan.json_messages) {
        NSMutableArray* entries = [NSMutableArray array];
        for (Request* request : produced) {
          [entries addObject:@{
            @"keyID" : [ToNSData(request->reported_key_id) base64EncodedStringWithOptions:0],
            @"payload" : [request->spc base64EncodedStringWithOptions:0],
          }];
        }
        message = [NSJSONSerialization dataWithJSONObject:entries options:0 error:nil];
      } else {
        message = produced.front()->spc;
      }
      ++session->messages_sent;
      for (Request* request : produced) {
        request->awaiting_response = true;
        request->message_order = session->messages_sent;
        request->spc = nil;
      }
      if (session->generate_done) {
        SessionCallback done = std::move(session->generate_done);
        done(Result::Ok(), session_id);
        // The callback may have closed the session.
        session = Find(session_id);
        if (!session) {
          return;
        }
      }
      std::vector<uint8_t> bytes = ToVector(message);
      MessageType type = ready.type;
      Deliver([session_id, type, bytes](FairPlayCdmClient* client) {
        client->OnSessionMessage(session_id, type, bytes);
      });
      if (type == MessageType::kLicenseRenewal && session->renew_done) {
        ResultCallback renewed = std::move(session->renew_done);
        renewed(Result::Ok());
      }
      session = Find(session_id);
      if (!session) {
        return;
      }
    }
  }

  void Settle(Session* session, Request* request, NSError* error) {
    bool was_pending = session->update_pending.erase(request) > 0;
    if (was_pending) {
      if (error) {
        session->update_error = session->update_error ?: error;
      } else {
        session->update_succeeded = true;
      }
    }
    std::string session_id = session->id;
    const bool update_resolves = was_pending && session->update_pending.empty() &&
                                 session->update_done &&
                                 (session->update_succeeded || session->plan.json_messages);
    NotifyKeyStatuses(session, update_resolves);
    session = Find(session_id);
    if (!session || !was_pending || !session->update_pending.empty() || !session->update_done) {
      return;
    }
    ResultCallback done = std::move(session->update_done);
    // A JSON session's update() resolves once every entry settled, failed or
    // not (WebKit's UpdateResponseCollector counts errors as responses); a
    // raw one fails with WebKit's TypeError.
    if (session->update_succeeded || session->plan.json_messages) {
      done(Result::Ok());
    } else {
      done(Failure(Exception::kTypeError, "license response rejected", session->update_error));
    }
  }

  // As WebKit's closeSession: a pending generateRequest fails with
  // NotSupportedError and a pending update() with TypeError.
  void RejectPending(Session* session, const char* reason) {
    if (session->generate_done) {
      SessionCallback done = std::move(session->generate_done);
      done(Result::Error(Exception::kNotSupported, reason), "");
    }
    if (session->update_done) {
      session->update_pending.clear();
      ResultCallback done = std::move(session->update_done);
      done(Result::Error(Exception::kTypeError, reason));
    }
    if (session->renew_done) {
      ResultCallback done = std::move(session->renew_done);
      done(Result::Error(Exception::kTypeError, reason));
    }
    while (!session->queued_updates.empty()) {
      ResultCallback done = std::move(session->queued_updates.front().second);
      session->queued_updates.pop_front();
      done(Result::Error(Exception::kTypeError, reason));
    }
  }

  KeyStatus StatusOf(const Session& session, const Request& request) const {
    if (session.keys_removed) {
      return KeyStatus::kReleased;
    }
    if (request.loading) {
      // AVFoundation takes the CKC with the loading request and reports
      // nothing more about the key; the player's obscured output is the only
      // protection signal (WebKit's fallback).
      if (request.loading_answered) {
        return output_obscured_ ? KeyStatus::kOutputRestricted : KeyStatus::kUsable;
      }
      if (request.loading_failed) {
        return KeyStatus::kInternalError;
      }
      if (request.loading_cancelled) {
        return KeyStatus::kReleased;
      }
      return request.error ? KeyStatus::kInternalError : KeyStatus::kStatusPending;
    }
    AVContentKeyRequest* av_request = request.request;
    if (av_request.error.code == kSecurityLevelError) {
      return KeyStatus::kOutputRestricted;
    }
    // The answered key stays in use while a renewal is in flight and after
    // one fails, also when AVFoundation reuses the request object for it (its
    // status then reads requesting or failed): report what HasUsableKey uses.
    const bool key_kept = request.key && !request.error;
    KeyStatus status = KeyStatus::kStatusPending;
    switch (av_request.status) {
      case AVContentKeyRequestStatusRequestingResponse:
      case AVContentKeyRequestStatusRetried:
        status = KeyStatus::kStatusPending;
        break;
      case AVContentKeyRequestStatusReceivedResponse:
      case AVContentKeyRequestStatusRenewed:
        status = KeyStatus::kUsable;
        break;
      case AVContentKeyRequestStatusCancelled:
        status = KeyStatus::kReleased;
        break;
      case AVContentKeyRequestStatusFailed:
        status = KeyStatus::kInternalError;
        break;
    }
    if (key_kept && (status == KeyStatus::kStatusPending || status == KeyStatus::kInternalError)) {
      status = KeyStatus::kUsable;
    }
    if (status == KeyStatus::kUsable) {
      if (@available(macOS 14.4, *)) {
        if (AVContentKey* key = request.key ?: av_request.contentKey) {
          switch (key.externalContentProtectionStatus) {
            case AVExternalContentProtectionStatusPending:
              status = KeyStatus::kStatusPending;
              break;
            case AVExternalContentProtectionStatusSufficient:
              status = KeyStatus::kUsable;
              break;
            case AVExternalContentProtectionStatusInsufficient:
              status = KeyStatus::kOutputRestricted;
              break;
          }
        }
      } else if (output_obscured_) {
        status = KeyStatus::kOutputRestricted;
      }
    }
    return status;
  }

  // |always|: a successful update() reports the statuses even when none
  // changed, as WebKit's MediaKeySession::update runs Update Key Statuses with
  // every success (requestDidSucceed's copyKeyStatuses, the cenc collector's
  // keyStatuses), so keystatuseschange fires each time.
  void NotifyKeyStatuses(Session* session, bool always = false) {
    if (session->keys_removed || session->loaded) {
      // remove() or load() reported the statuses, which stay: WebKit replaces
      // them with removeSessionData's or loadSession's keys.
      NotifyObservers();
      return;
    }
    std::vector<KeyInfo> keys;
    size_t usable = 0;
    for (const auto& request : session->requests) {
      KeyStatus status = StatusOf(*session, *request);
      uint32_t code = request->request.error ? static_cast<uint32_t>(request->request.error.code)
                                             : 0;
      std::vector<std::vector<uint8_t>> ids = request->key_ids;
      if (ids.empty()) {
        ids.push_back(request->reported_key_id);
      }
      for (const auto& id : ids) {
        auto existing = std::find_if(keys.begin(), keys.end(),
                                     [&](const KeyInfo& key) { return key.key_id == id; });
        if (existing != keys.end()) {
          // A renewal of a key answered through its loading request is a
          // further entry for the same URI; until it is answered the
          // answered key stays in use.
          bool keep = request->loading && !request->loading_answered &&
                      (existing->status == KeyStatus::kUsable ||
                       existing->status == KeyStatus::kOutputRestricted);
          if (!keep) {
            *existing = {id, status, code};
          }
        } else {
          keys.push_back({id, status, code});
        }
      }
    }
    for (const KeyInfo& key : keys) {
      usable += key.status == KeyStatus::kUsable;
    }
    bool additional = usable > session->last_usable_count;
    session->last_usable_count = usable;
    bool changed = keys.size() != session->last_keys.size();
    for (size_t i = 0; !changed && i < keys.size(); ++i) {
      changed = keys[i].key_id != session->last_keys[i].key_id ||
                keys[i].status != session->last_keys[i].status ||
                keys[i].system_code != session->last_keys[i].system_code;
    }
    if (changed || additional || always) {
      session->last_keys = keys;
      std::string session_id = session->id;
      Deliver([session_id, additional, keys](FairPlayCdmClient* client) {
        client->OnSessionKeysChange(session_id, additional, keys);
      });
    }
    NotifyObservers();
  }

  // Posted like client callbacks. Observers registered when it runs are told
  // (they may unregister themselves while being notified).
  void NotifyObservers() {
    std::weak_ptr<Impl> weak = weak_from_this();
    (*poster_)([weak] {
      auto impl = weak.lock();
      if (!impl) {
        return;
      }
      std::vector<KeysChangedCallback> callbacks;
      for (auto& [id, callback] : impl->observers_) {
        callbacks.push_back(callback);
      }
      for (auto& callback : callbacks) {
        callback();
      }
    });
  }

  FairPlayCdmClient* client_;
  std::shared_ptr<const PostTask> poster_;
  AVContentKeySession* av_session_ = nil;  // Shared by every EME session.
  PCFairPlayContentKeyDelegate* delegate_ = nil;
  // Content key recipients (renderers) attached through AttachRecipient.
  NSMutableArray<id<AVContentKeyRecipient>>* recipients_ = [NSMutableArray array];
  NSData* certificate_ = nil;
  std::map<std::string, std::unique_ptr<Session>> sessions_;
  bool persistent_state_allowed_ = false;
  // <storage directory>/SecureStop.plist, or nil.
  NSURL* storage_url_ = nil;
  std::map<uint64_t, KeysChangedCallback> observers_;
  uint64_t next_observer_ = 0;
  // HLS assets attached through FairPlayHlsKeyLoader.
  std::vector<Asset> assets_;
  // skd sessions waiting for a resource loader asset to ask for their URI.
  std::map<std::string, std::deque<std::string>> waiting_for_loading_;
  bool output_obscured_ = false;
};

bool FairPlayCdm::IsSupported() {
  return [AVContentKeySession class] != nil && AVContentKeySystemFairPlayStreaming != nil &&
         [AVSampleBufferDisplayLayer conformsToProtocol:@protocol(AVContentKeyRecipient)] &&
         [AVSampleBufferAudioRenderer conformsToProtocol:@protocol(AVContentKeyRecipient)];
}

bool FairPlayCdm::IsKeySystemSupported(const std::string& key_system) {
  static constexpr char kPrefix[] = "com.apple.fps.";
  constexpr size_t kPrefixSize = sizeof(kPrefix) - 1;
  return key_system == "com.apple.fps" ||
         key_system.compare(0, kPrefixSize, kPrefix) == 0;
}

bool FairPlayCdm::IsInitDataTypeSupported(const std::string& init_data_type) {
  return InitDataTypeFromName(init_data_type).has_value();
}

FairPlayCdm::FairPlayCdm(FairPlayCdmClient* client, PostTask post_task)
    : impl_(std::make_shared<Impl>(client, std::move(post_task))) {}

FairPlayCdm::~FairPlayCdm() {
  impl_->Shutdown();
}

void FairPlayCdm::SetServerCertificate(std::vector<uint8_t> certificate, ResultCallback done) {
  impl_->SetServerCertificate(std::move(certificate), impl_->Posted(std::move(done)));
}

void FairPlayCdm::SetPersistentStateAllowed(bool allowed) {
  impl_->SetPersistentStateAllowed(allowed);
}

void FairPlayCdm::SetStorageDirectory(const std::string& directory) {
  impl_->SetStorageDirectory(directory);
}

void FairPlayCdm::CreateSessionAndGenerateRequest(SessionType session_type,
                                                  InitDataType type,
                                                  std::vector<uint8_t> init_data,
                                                  SessionCallback done) {
  impl_->CreateSession(session_type, type, std::move(init_data),
                       impl_->Posted(std::move(done)));
}

void FairPlayCdm::CreateSessionAndGenerateRequest(InitDataType type,
                                                  std::vector<uint8_t> init_data,
                                                  SessionCallback done) {
  CreateSessionAndGenerateRequest(SessionType::kTemporary, type, std::move(init_data),
                                  std::move(done));
}

void FairPlayCdm::LoadSession(SessionType session_type,
                              const std::string& session_id,
                              SessionCallback done) {
  impl_->LoadSession(session_type, session_id, impl_->Posted(std::move(done)));
}

void FairPlayCdm::UpdateSession(const std::string& session_id,
                                std::vector<uint8_t> response,
                                ResultCallback done) {
  impl_->UpdateSession(session_id, std::move(response), impl_->Posted(std::move(done)));
}

void FairPlayCdm::CloseSession(const std::string& session_id, ResultCallback done) {
  impl_->CloseSession(session_id, impl_->Posted(std::move(done)));
}

void FairPlayCdm::RemoveSession(const std::string& session_id, ResultCallback done) {
  impl_->RemoveSession(session_id, impl_->Posted(std::move(done)));
}

bool FairPlayCdm::HasUsableKey(const std::vector<uint8_t>& key_id) const {
  return impl_->ContentKeyForKeyId(key_id) != nil;
}

bool FairPlayCdm::HasSessionForInitData(InitDataType type,
                                        const std::vector<uint8_t>& init_data) const {
  InitDataPlan plan = PlanContentKeyRequests(type, init_data);
  if (!plan.error.empty()) {
    return false;
  }
  std::vector<std::vector<uint8_t>> key_ids;
  for (const ContentKeyRequestPlan& call : plan.calls) {
    key_ids.insert(key_ids.end(), call.key_ids.begin(), call.key_ids.end());
  }
  return !key_ids.empty() && impl_->HasSessionForKeyIds(key_ids);
}

uint64_t FairPlayCdm::AddKeysChangedObserver(KeysChangedCallback callback) {
  return impl_->AddObserver(std::move(callback));
}

void FairPlayCdm::RemoveKeysChangedObserver(uint64_t id) {
  impl_->RemoveObserver(id);
}

Result AttachContentKeyRecipient(FairPlayCdm::Impl* cdm, id<AVContentKeyRecipient> recipient) {
  return cdm->AttachRecipient(recipient);
}

void DetachContentKeyRecipient(FairPlayCdm::Impl* cdm, id<AVContentKeyRecipient> recipient) {
  cdm->DetachRecipient(recipient);
}

Result AttachAsset(FairPlayCdm::Impl* cdm, AssetKeyClient* client, AVURLAsset* asset) {
  return cdm->AttachAsset(client, asset);
}

void DetachAsset(FairPlayCdm::Impl* cdm, AssetKeyClient* client) {
  cdm->DetachAsset(client);
}

bool OfferLoadingRequest(FairPlayCdm::Impl* cdm,
                         AssetKeyClient* client,
                         const std::string& uri,
                         AVAssetResourceLoadingRequest* request) {
  return cdm->OfferLoadingRequest(client, uri, request);
}

void CancelLoadingRequest(FairPlayCdm::Impl* cdm,
                          AssetKeyClient* client,
                          AVAssetResourceLoadingRequest* request) {
  cdm->CancelLoadingRequest(client, request);
}

void SetAssetOutputObscured(FairPlayCdm::Impl* cdm, AssetKeyClient* client, bool obscured) {
  cdm->SetAssetOutputObscured(client, obscured);
}

}  // namespace parc::fairplay

@implementation PCFairPlayContentKeyDelegate {
  std::weak_ptr<FairPlayCdm::Impl> _impl;
  std::shared_ptr<const PostTask> _poster;
}

- (instancetype)initWithImpl:(std::weak_ptr<FairPlayCdm::Impl>)impl
                      poster:(std::shared_ptr<const PostTask>)poster {
  if ((self = [super init])) {
    _impl = std::move(impl);
    _poster = std::move(poster);
  }
  return self;
}

// Runs |task| on the owner sequence if the key system still exists.
- (void)post:(std::function<void(FairPlayCdm::Impl&)>)task {
  std::weak_ptr<FairPlayCdm::Impl> weak = _impl;
  (*_poster)([weak, task] {
    if (auto impl = weak.lock()) {
      task(*impl);
    }
  });
}

- (void)contentKeySession:(AVContentKeySession*)session
    didProvideContentKeyRequest:(AVContentKeyRequest*)keyRequest {
  [self post:[keyRequest](FairPlayCdm::Impl& impl) {
    impl.OnRequests(@[ keyRequest ], false, false);
  }];
}

- (void)contentKeySession:(AVContentKeySession*)session
    didProvideContentKeyRequests:(NSArray<AVContentKeyRequest*>*)keyRequests
           forInitializationData:(NSData*)initializationData API_AVAILABLE(macos(14.4)) {
  [self post:[keyRequests](FairPlayCdm::Impl& impl) {
    impl.OnRequests(keyRequests, false, true);
  }];
}

- (void)contentKeySession:(AVContentKeySession*)session
    didProvideRenewingContentKeyRequest:(AVContentKeyRequest*)keyRequest {
  [self post:[keyRequest](FairPlayCdm::Impl& impl) {
    impl.OnRequests(@[ keyRequest ], true, false);
  }];
}

- (void)contentKeySession:(AVContentKeySession*)session
    contentKeyRequestDidSucceed:(AVContentKeyRequest*)keyRequest {
  [self post:[keyRequest](FairPlayCdm::Impl& impl) { impl.OnRequestSucceeded(keyRequest); }];
}

- (void)contentKeySession:(AVContentKeySession*)session
        contentKeyRequest:(AVContentKeyRequest*)keyRequest
         didFailWithError:(NSError*)error {
  [self post:[keyRequest, error](FairPlayCdm::Impl& impl) {
    impl.OnRequestFailed(keyRequest, error);
  }];
}

- (BOOL)contentKeySession:(AVContentKeySession*)session
    shouldRetryContentKeyRequest:(AVContentKeyRequest*)keyRequest
                          reason:(AVContentKeyRequestRetryReason)retryReason {
  return NO;
}

- (void)contentKeySession:(AVContentKeySession*)session
    externalProtectionStatusDidChangeForContentKey:(AVContentKey*)contentKey
    API_AVAILABLE(macos(14.4)) {
  [self post:[](FairPlayCdm::Impl& impl) { impl.OnProtectionStatusChanged(); }];
}

@end
