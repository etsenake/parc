// Copyright 2026 Parc contributors.
#include "parc/importer/import_service.h"
#include "base/functional/bind.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/thread_pool.h"
namespace parc::importer {
namespace {
Batch Read(ReadOptions options, uint32_t category, Cancellation cancelled) {
  Batch result;
  switch (options.family) {
    case Family::kChromium:
      result = ReadChromiumCategory(options, category, cancelled);
      break;
    case Family::kSafari:
      result = ReadSafariCategory(options, category, cancelled);
      break;
    case Family::kFirefox:
      result = ReadFirefoxCategory(options, category, cancelled);
      break;
  }
  std::fill(options.source_key.begin(), options.source_key.end(), '\0');
  return result;
}
DecryptedFile Decrypt(ReadOptions options,
                      base::FilePath file,
                      SidebarFormat format,
                      Cancellation cancelled) {
  auto result = DecryptSidebarFile(options, file, format, cancelled);
  std::fill(options.source_key.begin(), options.source_key.end(), '\0');
  return result;
}
ReadOptions Options(mojom::Source& source) {
  ReadOptions options;
  options.family = static_cast<Family>(source.family);
  options.profile_path = base::FilePath(source.profile_path);
  options.app_path = base::FilePath(source.app_path);
  options.source_name = std::move(source.source_name);
  options.source_key.assign(source.source_key.begin(),
                            source.source_key.end());
  std::fill(source.source_key.begin(), source.source_key.end(), 0);
  options.extension_ids = std::move(source.extension_ids);
  return options;
}
}
ImportService::ImportService(mojo::PendingReceiver<mojom::Reader> receiver)
    : receiver_(this, std::move(receiver)),
      cancelled_(std::make_shared<std::atomic_bool>(false)) {}
ImportService::~ImportService() {
  Cancel();
}
void ImportService::Cancel() {
  cancelled_->store(true);
  weak_factory_.InvalidateWeakPtrs();
}
void ImportService::ReadCategory(mojom::SourcePtr source,
                                 uint32_t category,
                                 ReadCategoryCallback callback) {
  if (busy_ || cancelled_->load() || !source || category == 0 ||
      (category & (category - 1)) || category > kExtensions) {
    auto failed = mojom::Batch::New();
    failed->category = category;
    failed->error = "The import reader is unavailable.";
    std::move(callback).Run(std::move(failed));
    return;
  }
  busy_ = true;
  base::ThreadPool::PostTaskAndReplyWithResult(
      FROM_HERE, {base::MayBlock(), base::TaskPriority::USER_VISIBLE},
      base::BindOnce(&Read, Options(*source), category, cancelled_),
      base::BindOnce(&ImportService::Complete, weak_factory_.GetWeakPtr(),
                     std::move(callback)));
}
void ImportService::DecryptSidebarFile(mojom::SourcePtr source,
                                       const std::string& path,
                                       mojom::SidebarFormat format,
                                       DecryptSidebarFileCallback callback) {
  if (busy_ || cancelled_->load() || !source ||
      source->family != mojom::Family::kChromium) {
    if (source)
      std::fill(source->source_key.begin(), source->source_key.end(), 0);
    std::move(callback).Run(mojom::DecryptedFile::New(
        false, "The import reader is unavailable.", std::vector<uint8_t>()));
    return;
  }
  busy_ = true;
  base::ThreadPool::PostTaskAndReplyWithResult(
      FROM_HERE, {base::MayBlock(), base::TaskPriority::USER_VISIBLE},
      base::BindOnce(&Decrypt, Options(*source), base::FilePath(path),
                     format == mojom::SidebarFormat::kDiaTabs
                         ? SidebarFormat::kDiaTabs
                         : SidebarFormat::kChromiumSession,
                     cancelled_),
      base::BindOnce(&ImportService::Decrypted, weak_factory_.GetWeakPtr(),
                     std::move(callback)));
}
void ImportService::Decrypted(DecryptSidebarFileCallback callback,
                              DecryptedFile file) {
  busy_ = false;
  std::move(callback).Run(mojom::DecryptedFile::New(
      file.success, std::move(file.error), std::move(file.data)));
}
void ImportService::Complete(ReadCategoryCallback callback, Batch batch) {
  busy_ = false;
  auto out = mojom::Batch::New();
  out->category = batch.category;
  out->success = batch.success;
  out->error = std::move(batch.error);
  out->warnings = std::move(batch.warnings);
  for (auto& x : batch.history)
    out->history.push_back(
        mojom::History::New(std::move(x.url), base::UTF16ToUTF8(x.title),
                            x.visits, x.typed, x.last_visit, x.hidden));
  for (auto& x : batch.bookmarks)
    out->bookmarks.push_back(mojom::Bookmark::New(
        std::move(x.id), std::move(x.parent), base::UTF16ToUTF8(x.title),
        std::move(x.url), x.folder));
  for (auto& x : batch.cookies)
    out->cookies.push_back(mojom::Cookie::New(
        std::move(x.domain), std::move(x.name), std::move(x.value),
        std::move(x.path), x.creation, x.expiry, x.last_access, x.secure,
        x.http_only, x.same_site, x.priority, x.source_scheme, x.source_port,
        std::move(x.top_frame_site), x.ancestor_cross_site));
  for (auto& x : batch.passwords)
    out->passwords.push_back(mojom::Password::New(
        std::move(x.realm), std::move(x.url), std::move(x.action),
        base::UTF16ToUTF8(x.username_element), base::UTF16ToUTF8(x.username),
        base::UTF16ToUTF8(x.password_element), base::UTF16ToUTF8(x.password),
        x.scheme, x.blocked));
  for (auto& x : batch.autofill) {
    auto a = mojom::Autofill::New();
    a->kind = static_cast<int32_t>(x.kind);
    for (auto& [k, v] : x.fields)
      a->fields[k] = base::UTF16ToUTF8(v);
    a->created = x.created;
    a->last_used = x.last_used;
    a->use_count = x.use_count;
    out->autofill.push_back(std::move(a));
  }
  for (auto& x : batch.extensions)
    out->extensions.push_back(
        mojom::Extension::New(std::move(x.id), base::UTF16ToUTF8(x.name)));
  std::move(callback).Run(std::move(out));
}
}
