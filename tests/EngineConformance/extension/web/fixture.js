const params = new URL(location.href).searchParams;
for (const key of ["run", "role", "step"]) document.getElementById(key).textContent = params.get(key) ?? "Missing — create the page using the extension";
document.title = `Fixture ${params.get("role") ?? "unknown"} · step ${params.get("step") ?? "unknown"}`;
