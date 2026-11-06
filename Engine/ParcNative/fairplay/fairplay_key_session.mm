#include "fairplay_key_session.h"

#import <AVFoundation/AVFoundation.h>

#include <algorithm>
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
    AVContentKeyRequest* request = nil;
    int call = -1;                               // Plan entry that produced it.
    std::vector<std::vector<uint8_t>> key_ids;  // 16-byte key IDs.
    std::vector<uint8_t> content_identifier;     // SPC content identifier.
    std::vector<uint8_t> reported_key_id;
    NSData* spc = nil;
    NSError* error = nil;
    bool awaiting_response = false;
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
    InitDataPlan plan;
    std::vector<std::unique_ptr<Request>> requests;
    std::vector<Batch> batches;
    SessionCallback generate_done;
    ResultCallback update_done;
    std::set<Request*> update_pending;
    bool update_succeeded = false;
    NSError* update_error = nil;
    size_t last_usable_count = 0;
    std::vector<KeyInfo> last_keys;  // As last reported.
    bool keys_removed = false;
  };

  Impl(FairPlayCdmClient* client, PostTask post_task)
      : client_(client), poster_(std::make_shared<const PostTask>(std::move(post_task))) {}

  ~Impl() { Shutdown(); }

  // Expiring the shared session makes every recipient inoperable, so it
  // happens only when the key system goes away.
  void Shutdown() {
    sessions_.clear();
    [av_session_ expire];
    av_session_ = nil;
  }

  Result AttachRecipient(id<AVContentKeyRecipient> recipient) {
    if (!EnsureSession()) {
      return Result::Error(Exception::kNotSupported, "AVContentKeySession unavailable");
    }
    if ([av_session_.contentKeyRecipients containsObject:recipient]) {
      return Result::Ok();
    }
    @try {
      [av_session_ addContentKeyRecipient:recipient];
    } @catch (NSException* exception) {
      return Result::Error(Exception::kInvalidState,
                           std::string("addContentKeyRecipient: ") +
                               (exception.reason.UTF8String ?: ""));
    }
    return Result::Ok();
  }

  void DetachRecipient(id<AVContentKeyRecipient> recipient) {
    @try {
      [av_session_ removeContentKeyRecipient:recipient];
    } @catch (NSException*) {
    }
  }

  void SetServerCertificate(std::vector<uint8_t> certificate, ResultCallback done) {
    if (certificate.empty()) {
      done(Result::Error(Exception::kTypeError, "empty server certificate"));
      return;
    }
    certificate_ = ToNSData(certificate);
    done(Result::Ok());
  }

  void CreateSession(InitDataType type, std::vector<uint8_t> init_data, SessionCallback done) {
    if (!certificate_) {
      done(Result::Error(Exception::kInvalidState, "server certificate not set"), "");
      return;
    }
    InitDataPlan plan = PlanContentKeyRequests(type, init_data);
    if (!plan.error.empty()) {
      done(Result::Error(Exception::kTypeError, plan.error), "");
      return;
    }
    if (!EnsureSession()) {
      done(Result::Error(Exception::kNotSupported, "AVContentKeySession unavailable"), "");
      return;
    }
    auto session = std::make_unique<Session>();
    session->id = "fps-" + std::to_string(++next_session_number_);
    session->plan = std::move(plan);
    session->generate_done = std::move(done);
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
    for (size_t i = 0; i < raw->plan.calls.size(); ++i) {
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
  }

  void UpdateSession(const std::string& session_id,
                     std::vector<uint8_t> response,
                     ResultCallback done) {
    Session* session = Find(session_id);
    if (!session || session->keys_removed) {
      done(Result::Error(Exception::kInvalidState, "session is closed or removed"));
      return;
    }
    if (session->update_done) {
      done(Result::Error(Exception::kInvalidState, "an update is already in progress"));
      return;
    }
    static const std::string kRenew = "renew";
    if (std::string(response.begin(), response.end()) == kRenew) {
      for (auto it = session->requests.rbegin(); it != session->requests.rend(); ++it) {
        if (HasReceivedResponse((*it)->request)) {
          [av_session_ renewExpiringResponseDataForContentKeyRequest:(*it)->request];
          done(Result::Ok());
          return;
        }
      }
      done(Result::Error(Exception::kInvalidState, "no key to renew"));
      return;
    }
    std::vector<Request*> awaiting;
    for (auto& request : session->requests) {
      if (request->awaiting_response) {
        awaiting.push_back(request.get());
      }
    }
    if (awaiting.empty()) {
      done(Result::Error(Exception::kInvalidState, "no license request awaits a response"));
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
      if (![entries isKindOfClass:[NSArray class]]) {
        done(Result::Error(Exception::kTypeError, "license response is not a JSON array"));
        return;
      }
      for (NSDictionary* entry in entries) {
        NSString* key_id_string =
            [entry isKindOfClass:[NSDictionary class]] ? entry[@"keyID"] : nil;
        NSData* key_id = [key_id_string isKindOfClass:[NSString class]]
                             ? [[NSData alloc] initWithBase64EncodedString:key_id_string options:0]
                             : nil;
        if (!key_id) {
          done(Result::Error(Exception::kTypeError, "license response entry has no keyID"));
          return;
        }
        std::vector<uint8_t> key = ToVector(key_id);
        auto match = std::find_if(awaiting.begin(), awaiting.end(), [&](Request* request) {
          return request->reported_key_id == key ||
                 std::find(request->key_ids.begin(), request->key_ids.end(), key) !=
                     request->key_ids.end();
        });
        if (match == awaiting.end()) {
          done(Result::Error(Exception::kTypeError,
                             "license response names a key with no pending request"));
          return;
        }
        id payload = entry[@"payload"];
        id error = entry[@"error"];
        if ([payload isKindOfClass:[NSString class]] == [error isKindOfClass:[NSNumber class]]) {
          done(Result::Error(Exception::kTypeError,
                             "license response entry needs exactly one of payload or error"));
          return;
        }
        if (error) {
          errors.push_back({*match, [error integerValue]});
          continue;
        }
        NSData* ckc = [[NSData alloc] initWithBase64EncodedString:payload options:0];
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
      [request->request
          processContentKeyResponseError:[NSError errorWithDomain:@"PCFairPlayLicenseError"
                                                             code:code
                                                         userInfo:nil]];
    }
    for (auto& [request, ckc] : responses) {
      request->awaiting_response = false;
      session->update_pending.insert(request);
    }
    if (session->update_pending.empty()) {
      NotifyKeyStatuses(session);
      done(Result::Ok());
      return;
    }
    session->update_done = std::move(done);
    for (auto& [request, ckc] : responses) {
      AVContentKeyResponse* key_response =
          [AVContentKeyResponse contentKeyResponseWithFairPlayStreamingKeyResponseData:ckc];
      [request->request processContentKeyResponse:key_response];
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
    done(Result::Ok());
    client_->OnSessionClosed(session_id);
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
    RevokeKeys(session);
    session->keys_removed = true;
    NotifyKeyStatuses(session);
    done(Result::Ok());
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
        AVContentKey* key = request->request.contentKey;
        if (key && HasReceivedResponse(request->request) &&
            std::find(request->key_ids.begin(), request->key_ids.end(), key_id) !=
                request->key_ids.end()) {
          return key;
        }
      }
    }
    return nil;
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
      if (!request) {
        session->requests.push_back(std::make_unique<Request>());
        request = session->requests.back().get();
      }
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
      MakeSpc(request);
    }
  }

  void OnSpc(AVContentKeyRequest* av_request, NSData* spc, NSError* error) {
    Session* session = SessionFor(av_request);
    if (!session) {
      return;
    }
    for (Batch& batch : session->batches) {
      for (Request* request : batch.requests) {
        if (request->request == av_request && !request->spc && !request->error) {
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
      request->error = nil;
      Settle(session, request, nil);
    }
  }

  void OnRequestFailed(AVContentKeyRequest* av_request, NSError* error) {
    Session* session = SessionFor(av_request);
    Request* request = session ? FindRequest(session, av_request) : nullptr;
    if (!request) {
      return;
    }
    if (error.code == kSecurityLevelError) {
      Settle(session, request, nil);
      return;
    }
    std::string session_id = session->id;
    // A failure before the SPC exists fails that SPC (and may end the session).
    OnSpc(av_request, nil, error);
    if (Find(session_id)) {
      request->error = error;
      Settle(session, request, error);
    }
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

 private:
  static dispatch_queue_t DelegateQueue() {
    static dispatch_queue_t queue =
        dispatch_queue_create("parc.fairplay.content-key-session", DISPATCH_QUEUE_SERIAL);
    return queue;
  }

  bool EnsureSession() {
    if (av_session_) {
      return true;
    }
    av_session_ =
        [AVContentKeySession contentKeySessionWithKeySystem:AVContentKeySystemFairPlayStreaming];
    if (!av_session_) {
      return false;
    }
    delegate_ = [[PCFairPlayContentKeyDelegate alloc] initWithImpl:weak_from_this() poster:poster_];
    [av_session_ setDelegate:delegate_ queue:DelegateQueue()];
    return true;
  }

  // The EME session a request belongs to: from its options, else (renewals,
  // which may come back without them) by matching an earlier request.
  Session* SessionFor(AVContentKeyRequest* av_request) const {
    NSString* id = av_request.options[kSessionOption];
    if ([id isKindOfClass:[NSString class]]) {
      return Find(id.UTF8String);
    }
    for (const auto& [session_id, session] : sessions_) {
      for (const auto& request : session->requests) {
        if (request->request == av_request ||
            (request->request.identifier &&
             [request->request.identifier isEqual:av_request.identifier])) {
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
    if (@available(macOS 14.4, *)) {
      for (auto& request : session->requests) {
        [request->request.contentKey revoke];
      }
    }
  }

  Session* Find(const std::string& session_id) const {
    auto it = sessions_.find(session_id);
    return it == sessions_.end() ? nullptr : it->second.get();
  }

  static Request* FindRequest(Session* session, AVContentKeyRequest* av_request) {
    for (auto& request : session->requests) {
      if (request->request == av_request) {
        return request.get();
      }
    }
    return nullptr;
  }

  // Key IDs and SPC content identifier for a request, as WebKit's
  // CDMPrivateFairPlayStreaming::keyIDsForRequest derives them: the UTF-8
  // identifier string, the identifier data, or the sinf key ID.
  // Key IDs and SPC content identifier for a request. Requests made through
  // sinf or a FairPlay pssh come back named by their 16-byte key ID; WebKit's
  // CDMPrivateFairPlayStreaming::keyIDsForRequest uses that (or the UTF-8
  // identifier string) as the content identifier unless the plan names one.
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
    }
    if (call) {
      for (const auto& key_id : call->key_ids) {
        AddUnique(&request->key_ids, key_id);
      }
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

  void MakeSpc(Request* request) {
    AVContentKeyRequest* av_request = request->request;
    if (request->content_identifier.empty()) {
      OnSpc(av_request, nil,
            [NSError errorWithDomain:@"PCFairPlayError"
                                code:-2
                            userInfo:@{NSLocalizedDescriptionKey : @"no content identifier"}]);
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
      OnSpc(av_request, nil,
            [NSError errorWithDomain:@"PCFairPlayError"
                                code:-3
                            userInfo:@{NSLocalizedDescriptionKey : exception.reason ?: @""}]);
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
      if (produced.empty()) {
        if (session->generate_done) {
          SessionCallback done = std::move(session->generate_done);
          sessions_.erase(session_id);
          done(Failure(Exception::kNotSupported, "license request failed", first_error), "");
          return;
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
      for (Request* request : produced) {
        request->awaiting_response = true;
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
      client_->OnSessionMessage(session_id, ready.type, ToVector(message));
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
    NotifyKeyStatuses(session);
    session = Find(session_id);
    if (!session || !was_pending || !session->update_pending.empty() || !session->update_done) {
      return;
    }
    ResultCallback done = std::move(session->update_done);
    if (session->update_succeeded) {
      done(Result::Ok());
    } else {
      done(Failure(Exception::kNotSupported, "license response rejected", session->update_error));
    }
  }

  void RejectPending(Session* session, const char* reason) {
    if (session->generate_done) {
      SessionCallback done = std::move(session->generate_done);
      done(Result::Error(Exception::kInvalidState, reason), "");
    }
    if (session->update_done) {
      session->update_pending.clear();
      ResultCallback done = std::move(session->update_done);
      done(Result::Error(Exception::kInvalidState, reason));
    }
  }

  static KeyStatus StatusOf(const Session& session, const Request& request) {
    if (session.keys_removed) {
      return KeyStatus::kReleased;
    }
    AVContentKeyRequest* av_request = request.request;
    if (av_request.error.code == kSecurityLevelError) {
      return KeyStatus::kOutputRestricted;
    }
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
    if (status == KeyStatus::kUsable) {
      if (@available(macOS 14.4, *)) {
        if (AVContentKey* key = av_request.contentKey) {
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
      }
    }
    return status;
  }

  void NotifyKeyStatuses(Session* session) {
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
          *existing = {id, status, code};
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
    if (changed || additional) {
      session->last_keys = keys;
      std::string session_id = session->id;
      client_->OnSessionKeysChange(session_id, additional, keys);
    }
    NotifyObservers();
  }

  void NotifyObservers() {
    // Observers may unregister themselves while being notified.
    std::vector<KeysChangedCallback> callbacks;
    for (auto& [id, callback] : observers_) {
      callbacks.push_back(callback);
    }
    for (auto& callback : callbacks) {
      callback();
    }
  }

  FairPlayCdmClient* client_;
  std::shared_ptr<const PostTask> poster_;
  AVContentKeySession* av_session_ = nil;  // Shared by every EME session.
  PCFairPlayContentKeyDelegate* delegate_ = nil;
  NSData* certificate_ = nil;
  std::map<std::string, std::unique_ptr<Session>> sessions_;
  uint64_t next_session_number_ = 0;
  std::map<uint64_t, KeysChangedCallback> observers_;
  uint64_t next_observer_ = 0;
};

bool FairPlayCdm::IsSupported() {
  return [AVContentKeySession class] != nil && AVContentKeySystemFairPlayStreaming != nil &&
         [AVSampleBufferDisplayLayer conformsToProtocol:@protocol(AVContentKeyRecipient)] &&
         [AVSampleBufferAudioRenderer conformsToProtocol:@protocol(AVContentKeyRecipient)];
}

FairPlayCdm::FairPlayCdm(FairPlayCdmClient* client, PostTask post_task)
    : impl_(std::make_shared<Impl>(client, std::move(post_task))) {}

FairPlayCdm::~FairPlayCdm() {
  impl_->Shutdown();
}

void FairPlayCdm::SetServerCertificate(std::vector<uint8_t> certificate, ResultCallback done) {
  impl_->SetServerCertificate(std::move(certificate), std::move(done));
}

void FairPlayCdm::CreateSessionAndGenerateRequest(InitDataType type,
                                                  std::vector<uint8_t> init_data,
                                                  SessionCallback done) {
  impl_->CreateSession(type, std::move(init_data), std::move(done));
}

void FairPlayCdm::UpdateSession(const std::string& session_id,
                                std::vector<uint8_t> response,
                                ResultCallback done) {
  impl_->UpdateSession(session_id, std::move(response), std::move(done));
}

void FairPlayCdm::CloseSession(const std::string& session_id, ResultCallback done) {
  impl_->CloseSession(session_id, std::move(done));
}

void FairPlayCdm::RemoveSession(const std::string& session_id, ResultCallback done) {
  impl_->RemoveSession(session_id, std::move(done));
}

bool FairPlayCdm::HasUsableKey(const std::vector<uint8_t>& key_id) const {
  return impl_->ContentKeyForKeyId(key_id) != nil;
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
