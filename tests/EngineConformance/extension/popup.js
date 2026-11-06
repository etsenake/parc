let report = null;
const status = document.getElementById("status");
const output = document.getElementById("report");
const buttons = [...document.querySelectorAll("button[data-operation]")];
async function run(operation) {
  buttons.forEach(button => { button.disabled = true; });
  status.textContent = `Running ${operation}…`;
  try {
    if (typeof globalThis.chrome?.runtime?.sendMessage !== "function") throw new Error("UNSUPPORTED: runtime.sendMessage is absent");
    const response = await Promise.race([
      chrome.runtime.sendMessage({fixture: 1, operation, expected: document.getElementById("expected").value}),
      new Promise((_, reject) => setTimeout(() => reject(new Error("FAIL: worker response timed out; inspect local results before retrying a create operation")), 20000))
    ]);
    if (!response) throw new Error("FAIL: worker returned no response");
    if (response.state) {
      report = {fixture: "Parc Engine Conformance", version: 1, ...response.state};
      output.value = JSON.stringify(report, null, 2);
    }
    status.textContent = response.ok ? (operation === "snapshot" ? "Local report loaded; this is not a conformance pass." : `${operation}: PASS. See the exact assertion scope below.`)
      : `${response.status}: ${response.message}`;
  } catch (error) { status.textContent = error.message; }
  finally { buttons.forEach(button => { button.disabled = false; }); }
}
for (const button of buttons) button.addEventListener("click", () => run(button.dataset.operation));
document.getElementById("export").addEventListener("click", () => {
  if (!report) { status.textContent = "No report is available yet."; return; }
  const url = URL.createObjectURL(new Blob([JSON.stringify(report, null, 2)], {type: "application/json"}));
  const link = document.createElement("a");
  link.href = url; link.download = "parc-engine-conformance.json"; link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
});
run("snapshot");
