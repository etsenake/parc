"""Cache native macOS compilation without changing GN arguments or commands."""

load("@builtin//encoding.star", "json")
load("@builtin//struct.star", "module")
load("./main.star", upstream_init = "init")
load("./clang_unix.star", "clang_unix")
load("./gn_logs.star", "gn_logs")

def init(ctx):
    upstream = upstream_init(ctx)
    steps = json.decode(upstream.step_config)
    filegroups = dict(upstream.filegroups)
    sdk = ctx.fs.canonpath("./" + gn_logs.read(ctx)["mac_sdk_path"])
    # -MMD omits system headers. Hash the entire SDK, including module maps.
    filegroups[sdk + ":parc_sdk"] = {"type": "glob", "includes": ["*"]}
    rules = []
    for rule in clang_unix.rules(ctx):
        if rule["name"] not in ["clang/cc", "clang/cxx", "clang/cxx_module", "clang/objc", "clang/objcxx"]:
            continue
        rule["inputs"].extend([
            "third_party/llvm-build/Release+Asserts:headers",
            sdk + ":parc_sdk",
        ])
        rule["platform_ref"] = "parc_mac"
        rules.append(rule)
    steps["platforms"]["parc_mac"] = {"OSFamily": "Darwin", "ISA": "arm64"}
    steps["input_deps"].update(clang_unix.input_deps(ctx))
    steps["rules"] = rules + steps["rules"]
    return module("config", step_config = json.encode(steps),
                  filegroups = filegroups, handlers = upstream.handlers)
