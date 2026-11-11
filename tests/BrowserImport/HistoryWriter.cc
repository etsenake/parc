#include <cstdio>
#include <cstdlib>
#include "base/at_exit.h"
#include "base/command_line.h"
#include "base/feature_list.h"
#include "base/files/scoped_temp_dir.h"
#include "base/functional/bind.h"
#include "base/run_loop.h"
#include "base/task/single_thread_task_executor.h"
#include "base/task/thread_pool/thread_pool_instance.h"
#include "base/test/allow_check_is_test_for_testing.h"
#include "components/history/core/browser/history_backend.h"
#include "components/history/core/browser/history_backend_client.h"
#include "components/history/core/browser/history_database_params.h"
#include "components/history/core/browser/in_memory_history_backend.h"
#include "components/version_info/channel.h"
#include "components/webdata/common/web_database.h"
#include "sql/database.h"
#include "sql/initialization.h"
#include "sql/statement.h"
#include "sql/transaction.h"
namespace {
int checks = 0;
void Require(bool value, const char* what) {
  ++checks;
  if (!value) {
    std::fprintf(stderr, "FAIL: %s\n", what);
    std::exit(1);
  }
}
class Delegate final : public history::HistoryBackend::Delegate {
 public:
  bool CanAddURL(const GURL&) const override { return true; }
  void NotifyProfileError(sql::InitStatus, const std::string&) override {
    Require(false, "history initialized");
  }
  void SetInMemoryBackend(
      std::unique_ptr<history::InMemoryHistoryBackend>) override {}
  void NotifyFaviconsChanged(const std::set<GURL>&, const GURL&) override {}
  void NotifyURLVisited(history::VisitedURLInfo) override {}
  void NotifyURLsModified(const history::URLRows& rows) override {
    changes += rows.size();
  }
  void NotifyDeletions(history::DeletionInfo) override {}
  void NotifyVisitedLinksAdded(const history::HistoryAddPageArgs&) override {}
  void NotifyVisitedLinksDeleted(
      const std::vector<history::DeletedVisitedLink>&) override {}
  void NotifyKeywordSearchTermUpdated(const history::URLRow&,
                                      history::KeywordID,
                                      const std::u16string&) override {}
  void NotifyKeywordSearchTermDeleted(history::URLID) override {}
  void DBLoaded() override {}
  size_t changes = 0;
};
history::URLRow Row(const char* path, base::Time time) {
  history::URLRow row(GURL(std::string("https://fixture.invalid/") + path));
  row.set_last_visit(time);
  row.set_visit_count(3);
  row.set_typed_count(1);
  row.set_title(u"Actual imported title");
  return row;
}
int Count(sql::Database& db, const char* path) {
  sql::Statement query(
      db.GetUniqueStatement("SELECT count(*) FROM urls WHERE url=?"));
  query.BindString(0, std::string("https://fixture.invalid/") + path);
  Require(query.Step(), "actual history row query");
  return query.ColumnInt(0);
}
}
int main(int argc, char** argv) {
  base::AtExitManager exit;
  base::test::AllowCheckIsTestForTesting();
  base::CommandLine::Init(argc, argv);
  const bool scoped =
      base::CommandLine::ForCurrentProcess()->HasSwitch("scoped");
  base::FeatureList::InitInstance(
      scoped ? "SqlScopedTransactionWebDatabase" : "",
      scoped ? "" : "SqlScopedTransactionWebDatabase");
  base::SingleThreadTaskExecutor executor;
  base::ThreadPoolInstance::CreateAndStartWithDefaultParams(
      "ImportWriterFixture");
  sql::EnsureSqliteInitialized(false);
  base::ScopedTempDir temp;
  Require(temp.CreateUniqueTempDir(), "disposable directory");
  auto delegate = std::make_unique<Delegate>();
  auto* observer = delegate.get();
  auto backend = base::MakeRefCounted<history::HistoryBackend>(
      std::move(delegate), nullptr,
      base::SingleThreadTaskRunner::GetCurrentDefault());
  backend->Init(false,
                history::HistoryDatabaseParams(temp.GetPath(), 0, 1,
                                               version_info::Channel::UNKNOWN));
  auto& db = backend->GetDBForTesting();
  auto never = base::BindRepeating([] { return false; });
  const auto now = base::Time::Now();
  auto result = backend->ImportPagesWithDetails(
      {Row("recent", now), Row("expired", now - base::Days(1000))},
      history::SOURCE_FIREFOX_IMPORTED, never);
  Require(result.committed && result.imported == 1 && result.expired == 1,
          "recent accepted, expired skipped under actual policy");
  Require(Count(db, "recent") == 1 && Count(db, "expired") == 0,
          "actual history contents");
  Require(observer->changes == 1, "only committed row notified");
  result =
      backend->ImportPagesWithDetails({Row("recent", now + base::Seconds(1))},
                                      history::SOURCE_SAFARI_IMPORTED, never);
  Require(result.committed && result.imported == 1,
          "existing URL gains actual visit");
  sql::Statement visits(db.GetUniqueStatement("SELECT count(*) FROM visits"));
  Require(visits.Step() && visits.ColumnInt(0) == 2,
          "existing URL is not a fake existence success");
  visits.Clear();
  result = backend->ImportPagesWithDetails(
      {Row("pre-cancel", now)}, history::SOURCE_FIREFOX_IMPORTED,
      base::BindRepeating([] { return true; }));
  Require(result.cancelled && !result.committed && result.imported == 0,
          "cancel before category performs no write");
  int cancel_checks = 0;
  backend->AddPagesWithDetails({Row("ordinary", now)}, history::SOURCE_BROWSED);
  result = backend->ImportPagesWithDetails(
      {Row("rollback", now)}, history::SOURCE_FIREFOX_IMPORTED,
      base::BindRepeating([](int* n) { return ++*n == 2; }, &cancel_checks));
  Require(result.cancelled && !result.committed && result.imported == 0,
          "precommit cancellation rolls back exact import batch");
  Require(Count(db, "rollback") == 0 && Count(db, "ordinary") == 1,
          "cancel preserves earlier ordinary history");
  const auto notified = observer->changes;
  Require(
      db.Execute("ALTER TABLE visit_source RENAME TO fixture_saved_source") &&
          db.Execute("CREATE TABLE visit_source(id INTEGER PRIMARY KEY, "
                     "source INTEGER NOT NULL CHECK(source < 0))"),
      "failure constraint installed");
  db.reset_error_callback();
  db.set_error_callback(base::BindRepeating([](int, sql::Statement*) {}));
  result = backend->ImportPagesWithDetails(
      {Row("failed-visit", now)}, history::SOURCE_FIREFOX_IMPORTED, never);
  Require(!result.committed && !result.imported,
          "write failure is not reported saved");
  Require(Count(db, "failed-visit") == 0 && observer->changes == notified,
          "failed visit rolls back newly inserted URL and emits no change");
  Require(
      db.Execute("DROP TABLE visit_source") &&
          db.Execute("ALTER TABLE fixture_saved_source RENAME TO visit_source"),
      "failure injection removed");
  result = backend->ImportPagesWithDetails(
      {Row("retry", now)}, history::SOURCE_FIREFOX_IMPORTED, never);
  Require(result.committed && result.imported == 1,
          "retry after failure commits");
  backend->Closing();
  backend = nullptr;
  base::RunLoop().RunUntilIdle();
  sql::Database reopened(sql::Database::Tag{"Test"});
  Require(reopened.Open(temp.GetPath().AppendASCII("History")),
          "reopen committed database");
  Require(Count(reopened, "recent") == 1 && Count(reopened, "retry") == 1 &&
              Count(reopened, "rollback") == 0 &&
              Count(reopened, "failed-visit") == 0,
          "durable exact transaction outcomes after reopen");
  reopened.Close();
  const auto web_path = temp.GetPath().AppendASCII("Web Data");
  {
    WebDatabase web;
    Require(web.Init(web_path) == sql::INIT_OK,
            "actual WebDatabase initialized");
    auto* sql = web.GetSQLConnection();
    Require(sql->Execute("PRAGMA foreign_keys=ON"), "foreign key enforcement");
    sql->reset_error_callback();
    sql->set_error_callback(base::BindRepeating([](int, sql::Statement*) {}));
    web.BeginTransaction();
    Require(sql->Execute("CREATE TABLE retained(id INTEGER PRIMARY KEY)"),
            "earlier table");
    Require(sql->Execute("INSERT INTO retained VALUES(1)"),
            "earlier pending row");
    Require(web.RunAtomicImport(base::BindOnce(
                [](sql::Database* db) {
                  return db->Execute("INSERT INTO retained VALUES(2)");
                },
                sql)),
            "actual outer import commit");
    Require(sql->HasActiveTransactions() == !scoped,
            "restore native transaction mode");
    Require(!web.RunAtomicImport(base::BindOnce(
                [](sql::Database* db) {
                  Require(db->Execute("INSERT INTO retained VALUES(3)"),
                          "insert before cancellation");
                  return false;
                },
                sql)),
            "cancelled callback rolls back exact WebDatabase batch");
    Require(web.RunAtomicImport(base::BindOnce(
                [](sql::Database* db) {
                  return db->Execute(
                             "CREATE TABLE parent(id INTEGER PRIMARY KEY)") &&
                         db->Execute(
                             "CREATE TABLE child(id INTEGER REFERENCES "
                             "parent(id) DEFERRABLE INITIALLY DEFERRED)");
                },
                sql)),
            "prepare deferred real commit failure");
    Require(!web.RunAtomicImport(base::BindOnce(
                [](sql::Database* db) {
                  return db->Execute("INSERT INTO child VALUES(777)");
                },
                sql)),
            "outer commit failure cannot report success");
    Require(sql->HasActiveTransactions() == !scoped,
            "restore transaction after commit failure");
    sql::Statement count(sql->GetUniqueStatement("SELECT count(*) FROM child"));
    Require(count.Step() && count.ColumnInt(0) == 0,
            "failed outer commit rolled back");
    count.Clear();
    sql::Statement retained(
        sql->GetUniqueStatement("SELECT count(*) FROM retained"));
    Require(retained.Step() && retained.ColumnInt(0) == 2,
            "only prior and committed work retained");
    retained.Clear();
    sql::Transaction nested(sql);
    Require(nested.Begin(), "open unrelated scoped caller");
    bool called = false;
    Require(!web.RunAtomicImport(base::BindOnce(
                [](bool* called) {
                  *called = true;
                  return true;
                },
                &called)) &&
                !called,
            "refuse unrelated or nested transaction owner");
  }
  sql::Database web_reopened(sql::Database::Tag{"Test"});
  Require(web_reopened.Open(web_path), "reopen actual WebDatabase");
  sql::Statement retained(
      web_reopened.GetUniqueStatement("SELECT count(*) FROM retained"));
  Require(retained.Step() && retained.ColumnInt(0) == 2,
          "real WebDatabase results survive reopen");
  retained.Clear();
  web_reopened.Close();
  base::ThreadPoolInstance::Get()->Shutdown();
  std::printf(
      "History/WebDatabase writer: %d actual backend assertions passed\n",
      checks);
}
