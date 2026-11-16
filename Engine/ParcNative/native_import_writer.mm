// Copyright 2026 Parc contributors.
#import "native_import_writer.h"
#include <map>
#include <set>
#include <tuple>
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/string_util.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/bind_post_task.h"
#include "base/task/cancelable_task_tracker.h"
#include "base/task/sequenced_task_runner.h"
#include "base/time/time.h"
#include "base/uuid.h"
#include "chrome/browser/history/history_service_factory.h"
#include "chrome/browser/password_manager/factories/profile_password_store_factory.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/webdata_services/web_data_service_factory.h"
#include "chrome/common/pref_names.h"
#include "components/autofill/core/browser/data_model/addresses/autofill_profile.h"
#include "components/autofill/core/browser/data_model/payments/credit_card.h"
#include "components/autofill/core/browser/field_types.h"
#include "components/autofill/core/browser/webdata/addresses/address_autofill_table.h"
#include "components/autofill/core/browser/webdata/autocomplete/autocomplete_entry.h"
#include "components/autofill/core/browser/webdata/autocomplete/autocomplete_table.h"
#include "components/autofill/core/browser/webdata/autofill_webdata_backend.h"
#include "components/autofill/core/browser/webdata/autofill_webdata_service.h"
#include "components/autofill/core/browser/webdata/payments/payments_autofill_table.h"
#include "components/autofill/core/common/autofill_prefs.h"
#include "components/history/core/browser/history_backend.h"
#include "components/history/core/browser/history_database.h"
#include "components/history/core/browser/history_db_task.h"
#include "components/history/core/browser/history_service.h"
#include "components/history/core/browser/history_types.h"
#include "components/history/core/common/pref_names.h"
#include "components/password_manager/core/browser/password_form.h"
#include "components/password_manager/core/browser/password_store/password_form_converters.h"
#include "components/password_manager/core/browser/password_store/password_store_consumer.h"
#include "components/password_manager/core/browser/password_store/password_store_interface.h"
#include "components/password_manager/core/common/password_manager_pref_names.h"
#include "components/prefs/pref_service.h"
#include "components/webdata/common/web_database.h"
#include "content/public/browser/storage_partition.h"
#include "mojo/public/cpp/bindings/remote.h"
#include "net/cookies/canonical_cookie.h"
#include "net/cookies/cookie_options.h"
#include "net/cookies/cookie_partition_key.h"
#include "net/cookies/unique_cookie_key.h"
#include "services/network/public/mojom/cookie_manager.mojom.h"
namespace parc::importer {
namespace {
base::Time Time(int64_t value) {
  return value > 0
             ? base::Time::FromDeltaSinceWindowsEpoch(base::Microseconds(value))
             : base::Time();
}
class HistoryImport final : public history::HistoryDBTask {
 public:
  HistoryImport(history::URLRows rows,
                history::VisitSource source,
                std::shared_ptr<std::atomic_bool> cancelled,
                WriteReply reply)
      : rows_(std::move(rows)),
        source_(source),
        cancelled_(std::move(cancelled)),
        reply_(std::move(reply)) {}
  bool RunOnDBThread(history::HistoryBackend* backend,
                     history::HistoryDatabase* db) override {
    if (!backend || !db) {
      result_ = {false, 0, "History storage is unavailable."};
      return true;
    }
    const auto result = backend->ImportPagesWithDetails(
        rows_, source_,
        base::BindRepeating(
            [](std::shared_ptr<std::atomic_bool> cancelled) {
              return cancelled->load();
            },
            cancelled_));
    if (!result.committed) {
      result_ = {false, 0,
                 result.cancelled
                     ? "History import was cancelled before commit."
                     : "History import did not commit."};
    } else {
      result_ = {true, result.imported, {}};
    }
    return true;
  }
  void DoneRunOnMainThread() override {
    std::move(reply_).Run(std::move(result_));
  }

 private:
  history::URLRows rows_;
  history::VisitSource source_;
  std::shared_ptr<std::atomic_bool> cancelled_;
  WriteReply reply_;
  WriteResult result_;
};
WriteResult WriteAutofill(std::vector<mojom::AutofillPtr> rows,
                          std::shared_ptr<std::atomic_bool> cancelled,
                          autofill::AutofillWebDataBackend* backend) {
  if (!backend || !backend->GetDatabase())
    return {false, 0, "Autofill storage is unavailable."};
  auto* db = backend->GetDatabase();
  auto* addresses = autofill::AddressAutofillTable::FromWebDatabase(db);
  auto* payments = autofill::PaymentsAutofillTable::FromWebDatabase(db);
  auto* forms = autofill::AutocompleteTable::FromWebDatabase(db);
  if (!addresses || !payments || !forms)
    return {false, 0, "Autofill storage is unavailable."};
  std::vector<autofill::AutofillProfile> profiles;
  std::vector<autofill::CreditCard> cards;
  std::vector<autofill::AutocompleteEntry> entries;
  size_t invalid = 0, duplicate = 0;
  const bool committed = db->RunAtomicImport(base::BindOnce(
      [](std::vector<mojom::AutofillPtr>* input,
         std::shared_ptr<std::atomic_bool> cancelled,
         autofill::AddressAutofillTable* addresses,
         autofill::PaymentsAutofillTable* payments,
         autofill::AutocompleteTable* forms,
         std::vector<autofill::AutofillProfile>* profiles,
         std::vector<autofill::CreditCard>* cards,
         std::vector<autofill::AutocompleteEntry>* entries, size_t* invalid,
         size_t* duplicate) {
        auto& rows = *input;
        std::set<std::u16string> saved;
        bool loaded = false;
        auto identity = [](const autofill::CreditCard& card) {
          std::u16string result;
          for (char16_t c : card.number())
            if (base::IsAsciiDigit(c))
              result.push_back(c);
          if (result.empty())
            return result;
          return result + u"/" +
                 card.GetRawInfo(autofill::CREDIT_CARD_EXP_MONTH) + u"/" +
                 card.GetRawInfo(autofill::CREDIT_CARD_EXP_4_DIGIT_YEAR);
        };
        for (auto& row : rows) {
          if (cancelled->load())
            return false;
          auto field = [&](const char* name) {
            auto i = row->fields.find(name);
            return i == row->fields.end() ? std::u16string()
                                          : base::UTF8ToUTF16(i->second);
          };
          if (row->kind == 0) {
            entries->emplace_back(
                autofill::AutocompleteKey(field("name"), field("value")),
                Time(row->created), Time(row->last_used));
          } else if (row->kind == 1) {
            autofill::AutofillProfile profile(autofill::AddressCountryCode(""));
            for (const auto& [key, value] : row->fields) {
              int type;
              if (!base::StringToInt(key, &type) ||
                  type <= autofill::UNKNOWN_TYPE ||
                  type >= autofill::MAX_VALID_FIELD_TYPE)
                continue;
              profile.SetRawInfo(static_cast<autofill::FieldType>(type),
                                 base::UTF8ToUTF16(value));
            }
            if (!addresses->AddAutofillProfile(profile))
              return false;
            profiles->push_back(std::move(profile));
          } else if (row->kind == 2) {
            autofill::CreditCard card;
            card.SetRawInfo(autofill::CREDIT_CARD_NAME_FULL, field("name"));
            card.SetRawInfo(autofill::CREDIT_CARD_NUMBER, field("number"));
            card.SetRawInfo(autofill::CREDIT_CARD_EXP_MONTH, field("month"));
            card.SetRawInfo(autofill::CREDIT_CARD_EXP_4_DIGIT_YEAR,
                            field("year"));
            card.SetNickname(field("nickname"));
            if (!card.HasValidCardNumber()) {
              ++*invalid;
              continue;
            }
            if (!loaded) {
              std::vector<std::unique_ptr<autofill::CreditCard>> existing;
              if (payments->GetCreditCards(&existing))
                for (const auto& stored : existing)
                  saved.insert(identity(*stored));
              loaded = true;
            }
            const auto key = identity(card);
            if (!key.empty() && !saved.insert(key).second) {
              ++*duplicate;
              continue;
            }
            if (!payments->AddCreditCard(card))
              return false;
            cards->push_back(std::move(card));
          } else
            return false;
        }

        return !cancelled->load() &&
               forms->UpdateAutocompleteEntries(*entries) && !cancelled->load();
      },
      &rows, cancelled, addresses, payments, forms, &profiles, &cards,
      &entries, &invalid, &duplicate));
  if (!committed)
    return {false, 0,
            cancelled->load() ? "Import was cancelled before autofill commit."
                              : "Autofill import did not commit."};
  for (const auto& p : profiles)
    backend->NotifyOfAutofillProfileChanged(autofill::AutofillProfileChange(
        autofill::AutofillProfileChange::ADD, p.guid(), p));
  for (const auto& c : cards)
    backend->NotifyOfCreditCardChanged(autofill::CreditCardChange(
        autofill::CreditCardChange::ADD, c.guid(), c));
  return {true, rows.size() - invalid - duplicate, {},
          invalid ? "Payment cards with invalid card numbers were skipped." : ""};
}
class Writer final : public ImportWriter,
                     public password_manager::PasswordStoreConsumer,
                     public std::enable_shared_from_this<Writer> {
 public:
  Writer(Profile& profile, int family, WriteReply reply)
      : family_(family),
        profile_(profile.GetWeakPtr()),
        reply_(std::move(reply)),
        cancelled_(std::make_shared<std::atomic_bool>(false)) {}
  ~Writer() override { cancelled_->store(true); }
  void Cancel() override { cancelled_->store(true); }
  void OnProfileDestroyed() override {
    cancelled_->store(true);
    Done({false, written_,
          "The destination Profile closed. Pending writes "
          "could not be confirmed; already saved data remains."});
  }
  void OnGetPasswordStoreResultsOrErrorFrom(
      password_manager::PasswordStoreInterface* store,
      base::expected<std::vector<password_manager::StoredCredential>,
                     password_manager::PasswordStoreBackendError> result)
      override {
    if (!reply_)
      return;
    if (store != passwords_.get() || !result.has_value()) {
      Done({false, 0,
            "Password import could not be verified. Some accepted "
            "writes may have been saved."});
      return;
    }
    size_t confirmed = 0;
    for (const auto& stored : result.value()) {
      auto expected = expected_passwords_.find(PasswordKey(stored));
      if (expected == expected_passwords_.end())
        continue;
      const auto& requested = expected->second;
      if (stored.scheme == requested.scheme &&
          stored.action == requested.action &&
          stored.blocked_by_user == requested.blocked_by_user &&
          stored.password_value == requested.password_value) {
        ++confirmed;
        expected_passwords_.erase(expected);
      }
    }
    written_ = confirmed;
    Done({expected_passwords_.empty(), confirmed,
          expected_passwords_.empty() ? ""
                                      : "Some requested passwords could not be "
                                        "verified in the destination. "
                                        "Confirmed passwords remain saved."});
  }
  void Start(mojom::BatchPtr batch, bool skip) {
    batch_ = std::move(batch);
    if (!profile_ || profile_->IsOffTheRecord() ||
        profile_->ShutdownStarted()) {
      Done({false, 0, "The destination profile is unavailable."});
      return;
    }
    switch (batch_->category) {
      case 1:
        History();
        break;
      case 4:
        Cookies(skip);
        break;
      case 8:
        Passwords();
        break;
      case 16:
        Autofill();
        break;
      default:
        Done({false, 0, "Unsupported native write category."});
    }
  }

 private:
  void Done(WriteResult result) {
    if (!reply_)
      return;
    auto callback = std::move(reply_);
    cookies_.reset();
    weak_factory_.InvalidateWeakPtrs();
    expected_passwords_.clear();
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(std::move(callback), std::move(result)));
  }
  void History() {
    if (profile_->GetPrefs()->GetBoolean(
            prefs::kSavingBrowserHistoryDisabled)) {
      Done({false, 0, "History saving is disabled by policy."});
      return;
    }
    auto* service = HistoryServiceFactory::GetForProfile(
        profile_.get(), ServiceAccessType::EXPLICIT_ACCESS);
    if (!service) {
      Done({false, 0, "History storage is unavailable."});
      return;
    }
    history::URLRows rows;
    for (const auto& h : batch_->history) {
      GURL url(h->url);
      if (!url.is_valid() || h->last_visit <= 0 || h->visits < 0 ||
          h->typed < 0)
        continue;
      history::URLRow row(url);
      row.set_title(base::UTF8ToUTF16(h->title));
      row.set_visit_count(h->visits);
      row.set_typed_count(h->typed);
      row.set_last_visit(Time(h->last_visit));
      row.set_hidden(h->hidden);
      rows.push_back(std::move(row));
    }
    if (cancelled_->load()) {
      Done({false, 0, "Import was cancelled."});
      return;
    }
    auto task = std::make_unique<HistoryImport>(
        std::move(rows),
        family_ == 2   ? history::SOURCE_FIREFOX_IMPORTED
        : family_ == 1 ? history::SOURCE_SAFARI_IMPORTED
                       : history::SOURCE_OS_MIGRATION_IMPORTED,
        cancelled_, base::BindOnce(&Writer::Done, shared_from_this()));
    if (service->ScheduleDBTask(FROM_HERE, std::move(task), &tasks_) ==
        base::CancelableTaskTracker::kBadTaskId)
      Done({false, 0, "History completion could not be scheduled."});
  }
  void Passwords() {
    if (!profile_->GetPrefs()->GetBoolean(
            password_manager::prefs::kCredentialsEnableService)) {
      Done({false, 0, "Password saving is disabled."});
      return;
    }
    passwords_ = ProfilePasswordStoreFactory::GetForProfile(
        profile_.get(), ServiceAccessType::EXPLICIT_ACCESS);
    if (!passwords_) {
      Done({false, 0, "Password storage is unavailable."});
      return;
    }
    std::vector<password_manager::StoredCredential> forms;
    for (auto& p : batch_->passwords) {
      if (p->scheme < 0 || p->scheme > 2 || p->realm.empty() ||
          !GURL(p->url).is_valid() ||
          (p->blocked && (!p->username.empty() || !p->password.empty()))) {
        Done({false, 0,
              "The source contains an invalid password record. "
              "No passwords were imported."});
        return;
      }
      password_manager::PasswordForm form;
      form.scheme =
          static_cast<password_manager::PasswordForm::Scheme>(p->scheme);
      form.signon_realm = p->realm;
      form.url = GURL(p->url);
      form.action = GURL(p->action);
      form.username_element = base::UTF8ToUTF16(p->username_element);
      form.username_value = base::UTF8ToUTF16(p->username);
      form.password_element = base::UTF8ToUTF16(p->password_element);
      form.password_value =
          password_manager::PasswordString(base::UTF8ToUTF16(p->password));
      form.blocked_by_user = p->blocked;
      auto expected = password_manager::FromPasswordForm(form);
      auto key = PasswordKey(expected);
      expected_passwords_.insert_or_assign(std::move(key), std::move(expected));
      forms.push_back(password_manager::FromPasswordForm(form));
    }
    if (cancelled_->load()) {
      Done({false, 0, "Import was cancelled."});
      return;
    }
    passwords_->AddLogins(
        std::move(forms),
        base::BindOnce(
            [](std::shared_ptr<Writer> self) {
              if (!self->reply_)
                return;
              if (!self->profile_ || self->profile_->ShutdownStarted()) {
                self->OnProfileDestroyed();
                return;
              }
              self->passwords_->GetAllLogins(self->weak_factory_.GetWeakPtr());
            },
            shared_from_this()));
  }

  void Autofill() {
    const bool addresses = autofill::prefs::IsAutofillProfileEnabled(
                   profile_->GetPrefs()),
               cards = autofill::prefs::IsAutofillPaymentMethodsEnabled(
                   profile_->GetPrefs());
    for (const auto& row : batch_->autofill)
      if ((row->kind == 2 && !cards) || (row->kind != 2 && !addresses)) {
        Done({false, 0,
              "Requested autofill data is disabled by policy or preference."});
        return;
      }
    auto service = WebDataServiceFactory::GetAutofillWebDataForProfile(
        profile_.get(), ServiceAccessType::EXPLICIT_ACCESS);
    if (!service) {
      Done({false, 0, "Autofill storage is unavailable."});
      return;
    }
    auto reply = base::BindPostTaskToCurrentDefault(
        base::BindOnce(&Writer::Done, shared_from_this()));
    service->GetAutofillBackend(base::BindOnce(
        [](std::vector<mojom::AutofillPtr> rows,
           std::shared_ptr<std::atomic_bool> cancelled, WriteReply reply,
           autofill::AutofillWebDataBackend* backend) {
          std::move(reply).Run(
              WriteAutofill(std::move(rows), std::move(cancelled), backend));
        },
        std::move(batch_->autofill), cancelled_, std::move(reply)));
  }
  using CredentialKey = std::
      tuple<std::string, GURL, std::u16string, std::u16string, std::u16string>;
  static CredentialKey PasswordKey(
      const password_manager::StoredCredential& credential) {
    return password_manager::StoredCredentialUniqueKey(credential);
  }
  void Cookies(bool skip) {
    auto* manager = profile_->GetDefaultStoragePartition()
                        ->GetCookieManagerForBrowserProcess();
    if (!manager) {
      Done({false, 0, "Cookie storage is unavailable."});
      return;
    }
    manager->CloneInterface(cookies_.BindNewPipeAndPassReceiver());
    cookies_.set_disconnect_handler(base::BindOnce(
        [](std::weak_ptr<Writer> weak) {
          if (auto self = weak.lock()) {
            self->Done(
                {false, self->written_,
                 "Cookie storage disconnected. The last write or flush could "
                 "not be confirmed; already saved cookies remain."});
          }
        },
        weak_from_this()));
    if (skip)
      cookies_->GetAllCookies(base::BindOnce(
          [](std::shared_ptr<Writer> self, const net::CookieList& existing) {
            for (const auto& c : existing)
              self->existing_.insert(c.UniqueKey());
            self->NextCookie();
          },
          shared_from_this()));
    else
      NextCookie();
  }
  void ContinueCookies() {
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(&Writer::NextCookie, shared_from_this()));
  }
  void NextCookie() {
    if (!reply_)
      return;
    if (cancelled_->load() || !profile_ || profile_->ShutdownStarted()) {
      Done({false, written_,
            "Import was cancelled; already saved cookies remain."});
      return;
    }
    if (index_ >= batch_->cookies.size()) {
      cookies_->FlushCookieStore(base::BindOnce(
          &Writer::Done, shared_from_this(),
          WriteResult{!cookie_failed_, written_,
                      cookie_failed_ ? "Some cookies were rejected by the "
                                       "destination's cookie rules."
                                     : ""}));
      return;
    }
    const auto& c = batch_->cookies[index_++];
    if (c->same_site < -1 || c->same_site > 2 || c->priority < 0 ||
        c->priority > 2 || c->source_scheme < 0 || c->source_scheme > 2 ||
        c->source_port < -1 || c->source_port > 65535) {
      cookie_failed_ = true;
      ContinueCookies();
      return;
    }
    std::optional<net::CookiePartitionKey> partition;
    if (!c->top_frame_site.empty()) {
      auto parsed = net::CookiePartitionKey::FromStorage(
          c->top_frame_site, c->ancestor_cross_site);
      if (!parsed.has_value()) {
        cookie_failed_ = true;
        ContinueCookies();
        return;
      }
      partition = parsed.value();
    }
    std::string host = c->domain;
    while (host.starts_with('.'))
      host.erase(0, 1);
    const bool secure_source =
        c->source_scheme == 2 || (c->source_scheme == 0 && c->secure);
    const std::string port =
        c->source_port < 0 ? "" : ":" + std::to_string(c->source_port);
    GURL url(std::string(secure_source ? "https://" : "http://") + host + port +
             c->path);
    net::CookieInclusionStatus status;
    auto cookie = net::CanonicalCookie::CreateSanitizedCookie(
        url, c->name, c->value, c->domain, c->path, Time(c->creation),
        Time(c->expiry), Time(c->last_access), c->secure, c->http_only,
        static_cast<net::CookieSameSite>(c->same_site),
        static_cast<net::CookiePriority>(c->priority), partition, &status);
    if (!cookie || !status.IsInclude()) {
      cookie_failed_ = true;
      ContinueCookies();
      return;
    }
    cookie->SetSourceScheme(
        static_cast<net::CookieSourceScheme>(c->source_scheme));
    cookie->SetSourcePort(c->source_port);
    if (existing_.contains(cookie->UniqueKey())) {
      ContinueCookies();
      return;
    }
    net::CookieOptions options;
    options.set_include_httponly();
    options.set_same_site_cookie_context(
        net::CookieOptions::SameSiteCookieContext::MakeInclusive());
    cookies_->SetCanonicalCookie(
        *cookie, url, options,
        base::BindOnce(
            [](std::shared_ptr<Writer> self, net::CookieAccessResult result) {
              if (result.status.IsInclude())
                ++self->written_;
              else
                self->cookie_failed_ = true;
              self->NextCookie();
            },
            shared_from_this()));
  }
  int family_;
  base::WeakPtr<Profile> profile_;
  WriteReply reply_;
  std::shared_ptr<std::atomic_bool> cancelled_;
  mojom::BatchPtr batch_;
  base::CancelableTaskTracker tasks_;
  scoped_refptr<password_manager::PasswordStoreInterface> passwords_;
  mojo::Remote<network::mojom::CookieManager> cookies_;
  std::set<net::UniqueCookieKey> existing_;
  std::map<CredentialKey, password_manager::StoredCredential>
      expected_passwords_;
  size_t index_ = 0, written_ = 0;
  bool cookie_failed_ = false;
  base::WeakPtrFactory<Writer> weak_factory_{this};
};
}
std::shared_ptr<ImportWriter> WriteImportBatch(Profile& profile,
                                               int family,
                                               mojom::BatchPtr batch,
                                               bool skip,
                                               WriteReply reply) {
  auto writer = std::make_shared<Writer>(profile, family, std::move(reply));
  writer->Start(std::move(batch), skip);
  return writer;
}
}
