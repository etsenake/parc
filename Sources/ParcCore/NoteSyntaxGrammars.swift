import Foundation

package enum NoteSyntaxGrammars {
    package static func grammar(for id: String) -> NoteSyntaxGrammar? {
        switch id {
        case "swift": return swift
        case "javascript": return javascript
        case "jsx": return jsx
        case "typescript": return typescript
        case "tsx": return tsx
        case "python": return python
        case "ruby": return ruby
        case "go": return go
        case "rust": return rust
        case "c": return c
        case "cpp": return cpp
        case "csharp": return csharp
        case "objectivec": return objectiveC
        case "java": return java
        case "kotlin": return kotlin
        case "scala": return scala
        case "dart": return dart
        case "json": return json
        case "sql": return sql
        case "bash": return bash
        case "powershell": return powershell
        case "lua": return lua
        case "r": return r
        case "haskell": return haskell
        case "elixir": return elixir
        case "graphql": return graphql
        case "mermaid": return mermaid
        case "zig": return zig
        default: return nil
        }
    }

    private static let slashComments = ["//"]
    private static let starComment = [NoteSyntaxBlockComment("/*", "*/")]
    private static let nestedStarComment = [NoteSyntaxBlockComment("/*", "*/", nests: true)]
    private static let quoted = [NoteSyntaxStringRule("\""), NoteSyntaxStringRule("'")]
    private static let classic: NoteSyntaxFeatures = [.callsAreFunctions, .memberProperties, .capitalizedTypes, .capsConstants]

    package static let swift = NoteSyntaxGrammar(
        keywords: """
        associatedtype deinit extension fileprivate import init inout internal let open operator private \
        precedencegroup public rethrows static subscript var break case catch continue default defer do else \
        fallthrough for guard if in repeat return throw switch where while as is try throws async await \
        nonisolated isolated some any consuming borrowing mutating nonmutating override required convenience \
        dynamic final lazy optional unowned weak indirect willSet didSet macro package sending each
        """,
        constants: "true false nil",
        builtins: "print debugPrint fatalError precondition preconditionFailure assert assertionFailure min max abs zip stride swap withAnimation",
        operands: "self Self super",
        functionDeclarators: "func",
        typeDeclarators: "class struct enum protocol actor typealias",
        lineComments: slashComments, blockComments: nestedStarComment,
        strings: [NoteSyntaxStringRule("\"\"\"", multiline: true, interpolation: .backslashParen),
                  NoteSyntaxStringRule("\"", interpolation: .backslashParen)],
        features: classic.union([.swiftLiterals, .backtickIdentifiers]),
        dollarKind: .variable, atKind: .attribute)

    private static let javascriptKeywords = """
        break case catch class const continue debugger default delete do else export extends finally for function \
        if import in instanceof let new of return static switch throw try typeof var void while with yield async \
        await from as get set
        """
    private static let javascriptStrings = [NoteSyntaxStringRule("\""), NoteSyntaxStringRule("'"),
                                            NoteSyntaxStringRule("`", multiline: true, interpolation: .dollarBrace)]
    private static let javascriptFeatures = classic.union([.regexLiterals, .taggedTemplates, .privateNames])
    private static let typescriptKeywords = javascriptKeywords + """
         interface type enum implements namespace module declare abstract readonly private protected public keyof \
        infer is asserts satisfies override unique accessor
        """
    private static let typescriptTypes = "string number boolean any unknown never void object symbol bigint"

    private static func javascriptFamily(typescript: Bool, jsx: Bool) -> NoteSyntaxGrammar {
        NoteSyntaxGrammar(
            keywords: typescript ? typescriptKeywords : javascriptKeywords,
            types: typescript ? typescriptTypes : "",
            constants: "true false null undefined NaN Infinity",
            builtins: "console window document globalThis require module exports process",
            operands: "this super",
            functionDeclarators: "function",
            typeDeclarators: typescript ? "class interface type enum" : "class",
            lineComments: slashComments, blockComments: starComment, strings: javascriptStrings,
            features: jsx ? javascriptFeatures.union(.jsx) : javascriptFeatures,
            wordExtras: "$", wordStartExtras: "$", atKind: .attribute)
    }

    package static let javascript = javascriptFamily(typescript: false, jsx: false)
    package static let jsx = javascriptFamily(typescript: false, jsx: true)
    package static let typescript = javascriptFamily(typescript: true, jsx: false)
    package static let tsx = javascriptFamily(typescript: true, jsx: true)

    package static let python = NoteSyntaxGrammar(
        keywords: """
        and as assert async await break continue del elif else except finally for from global if import in is \
        lambda nonlocal not or pass raise return try while with yield match case
        """,
        constants: "True False None Ellipsis NotImplemented __name__ __file__ __doc__",
        builtins: """
        abs all any ascii bin bool breakpoint bytearray bytes callable chr classmethod compile complex delattr dict \
        dir divmod enumerate eval exec filter float format frozenset getattr globals hasattr hash help hex id input \
        int isinstance issubclass iter len list locals map max memoryview min next object oct open ord pow print \
        property range repr reversed round set setattr slice sorted staticmethod str sum super tuple type vars zip \
        __import__
        """,
        variables: "self cls",
        functionDeclarators: "def",
        typeDeclarators: "class",
        lineComments: ["#"],
        strings: [NoteSyntaxStringRule("\"\"\"", multiline: true), NoteSyntaxStringRule("'''", multiline: true),
                  NoteSyntaxStringRule("\""), NoteSyntaxStringRule("'")],
        prefixes: .python,
        features: classic.union(.decoratorsAtLineStart),
        atKind: .attribute)

    package static let ruby = NoteSyntaxGrammar(
        keywords: """
        BEGIN END alias and begin break case defined? do else elsif end ensure for if in next not or redo rescue \
        retry return super then undef unless until when while yield __method__ __FILE__ __LINE__ __dir__
        """,
        constants: "true false nil",
        builtins: """
        puts print p pp require require_relative attr_accessor attr_reader attr_writer include extend prepend \
        private protected public raise lambda proc loop catch throw format sprintf gets module_function
        """,
        operands: "self",
        functionDeclarators: "def",
        typeDeclarators: "class module",
        lineComments: ["#"],
        strings: [NoteSyntaxStringRule("\"", multiline: true, interpolation: .hashBrace),
                  NoteSyntaxStringRule("'", multiline: true, rawEscapes: true),
                  NoteSyntaxStringRule("`", multiline: true, interpolation: .hashBrace)],
        features: [.callsAreFunctions, .memberProperties, .capitalizedTypes, .regexLiterals, .rubyLiterals, .symbols],
        wordSuffixes: "?!", dollarKind: .variable, atKind: .variable)

    package static let go = NoteSyntaxGrammar(
        keywords: """
        break case chan const continue default defer else fallthrough for go goto if import interface map package \
        range return select struct switch var
        """,
        types: """
        bool byte complex64 complex128 error float32 float64 int int8 int16 int32 int64 rune string uint uint8 \
        uint16 uint32 uint64 uintptr any comparable
        """,
        constants: "true false nil iota",
        builtins: "append cap clear close complex copy delete imag len make max min new panic print println real recover",
        functionDeclarators: "func",
        typeDeclarators: "type",
        lineComments: slashComments, blockComments: starComment,
        strings: [NoteSyntaxStringRule("\""), NoteSyntaxStringRule("'"),
                  NoteSyntaxStringRule("`", multiline: true, escapes: false)],
        features: [.callsAreFunctions, .memberProperties])

    package static let rust = NoteSyntaxGrammar(
        keywords: """
        as async await break const continue crate dyn else extern for if impl in let loop match mod move mut pub \
        ref return static super unsafe use where while yield macro_rules
        """,
        types: "i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str",
        constants: "true false Some None Ok Err",
        operands: "self Self",
        functionDeclarators: "fn",
        typeDeclarators: "struct enum trait type union",
        lineComments: slashComments, blockComments: nestedStarComment,
        strings: [NoteSyntaxStringRule("\"", multiline: true)],
        prefixes: .rust,
        features: classic.union(.rustLiterals))

    private static let cKeywords = """
        auto break case const continue default do else enum extern for goto if inline register restrict return \
        sizeof static struct switch typedef union volatile while _Alignas _Alignof _Atomic _Bool _Complex _Generic \
        _Imaginary _Noreturn _Static_assert _Thread_local alignas alignof static_assert thread_local typeof constexpr
        """
    private static let cTypes = """
        char double float int long short signed unsigned void bool size_t ssize_t ptrdiff_t intptr_t uintptr_t \
        int8_t int16_t int32_t int64_t uint8_t uint16_t uint32_t uint64_t wchar_t FILE
        """
    private static let cBuiltins = """
        printf fprintf sprintf snprintf scanf malloc calloc realloc free memcpy memmove memset memcmp strlen strcmp \
        strncmp strcpy strncpy strcat puts fputs fopen fclose fread fwrite exit abort assert
        """
    private static let cFeatures = classic.union([.preprocessor, .arrowMembers])

    package static let c = NoteSyntaxGrammar(
        keywords: cKeywords, types: cTypes,
        constants: "NULL true false EOF stdin stdout stderr nullptr",
        builtins: cBuiltins,
        typeDeclarators: "struct enum union",
        lineComments: slashComments, blockComments: starComment, strings: quoted, prefixes: .cpp,
        features: cFeatures)

    package static let cpp = NoteSyntaxGrammar(
        keywords: cKeywords + """
         and and_eq asm bitand bitor catch co_await co_return co_yield compl concept consteval constinit const_cast \
        decltype delete dynamic_cast explicit export friend mutable namespace new noexcept not not_eq operator or \
        or_eq private protected public reinterpret_cast requires static_cast template throw try typeid typename \
        using virtual xor xor_eq override final import module
        """,
        types: cTypes + " char8_t char16_t char32_t string vector map unordered_map set array optional unique_ptr shared_ptr",
        constants: "NULL true false nullptr",
        builtins: cBuiltins + " std cout cerr endl move forward make_unique make_shared",
        operands: "this",
        typeDeclarators: "class struct enum union",
        lineComments: slashComments, blockComments: starComment, strings: quoted, prefixes: .cpp,
        features: cFeatures, digitSeparators: "'")

    package static let csharp = NoteSyntaxGrammar(
        keywords: """
        abstract as break case catch checked const continue default delegate do else event explicit extern finally \
        fixed for foreach goto if implicit in internal is lock new operator out override params private protected \
        public readonly ref return sealed sizeof stackalloc static switch throw try typeof unchecked unsafe using \
        virtual volatile while async await var dynamic get set init value yield when where nameof global partial \
        required with and or not file scoped
        """,
        types: "bool byte char decimal double float int long object sbyte short string uint ulong ushort void nint nuint",
        constants: "true false null",
        operands: "this base",
        typeDeclarators: "class struct interface enum record namespace",
        lineComments: slashComments, blockComments: starComment,
        strings: [NoteSyntaxStringRule("\"\"\"", multiline: true, escapes: false), NoteSyntaxStringRule("\""),
                  NoteSyntaxStringRule("'")],
        features: classic.union([.csharpLiterals, .preprocessor]))

    package static let objectiveC = NoteSyntaxGrammar(
        keywords: cKeywords + """
         nonatomic atomic strong weak copy assign retain readonly readwrite nullable nonnull __block __weak \
        __strong __unsafe_unretained _Nullable _Nonnull __kindof
        """,
        types: cTypes + " id instancetype Class SEL IMP BOOL NSInteger NSUInteger CGFloat",
        constants: "NULL true false nil Nil YES NO",
        builtins: cBuiltins + " NSLog",
        operands: "self super",
        typeDeclarators: "struct enum union",
        lineComments: slashComments, blockComments: starComment, strings: quoted, prefixes: .cpp,
        features: cFeatures.union(.objcLiterals))

    package static let java = NoteSyntaxGrammar(
        keywords: """
        abstract assert break case catch const continue default do else extends final finally for goto if \
        implements import instanceof native new package private protected public return static strictfp switch \
        synchronized throw throws transient try volatile while var sealed permits yield module requires exports
        """,
        types: "boolean byte char double float int long short void",
        constants: "true false null",
        operands: "this super",
        typeDeclarators: "class interface enum record",
        lineComments: slashComments, blockComments: starComment,
        strings: [NoteSyntaxStringRule("\"\"\"", multiline: true), NoteSyntaxStringRule("\""), NoteSyntaxStringRule("'")],
        features: classic, atKind: .attribute)

    package static let kotlin = NoteSyntaxGrammar(
        keywords: """
        as break continue do else for if in interface is package return throw try typeof val var when while by \
        catch constructor finally import init where actual abstract annotation companion const crossinline data \
        package enum expect external final infix inline inner internal lateinit noinline open operator out override \
        private protected public reified sealed suspend tailrec vararg value
        """,
        constants: "true false null",
        builtins: "println print listOf mutableListOf mapOf mutableMapOf setOf arrayOf require check error lazy repeat",
        operands: "this super it",
        functionDeclarators: "fun",
        typeDeclarators: "class object typealias",
        lineComments: slashComments, blockComments: nestedStarComment,
        strings: [NoteSyntaxStringRule("\"\"\"", multiline: true, escapes: false, interpolation: .dollarName),
                  NoteSyntaxStringRule("\"", interpolation: .dollarName), NoteSyntaxStringRule("'")],
        features: classic.union(.backtickIdentifiers), atKind: .attribute)

    package static let scala = NoteSyntaxGrammar(
        keywords: """
        abstract case catch do else extends final finally for forSome if implicit import lazy match new override \
        package private protected return sealed throw try val var while with yield given using export then end \
        derives extension inline opaque transparent open infix
        """,
        constants: "true false null None Nil",
        builtins: "println print Some Seq List Map Set Vector Option",
        operands: "this super",
        functionDeclarators: "def",
        typeDeclarators: "class trait object type enum",
        lineComments: slashComments, blockComments: nestedStarComment,
        strings: [NoteSyntaxStringRule("\"\"\"", multiline: true, escapes: false), NoteSyntaxStringRule("\""),
                  NoteSyntaxStringRule("'")],
        prefixes: .scala,
        features: classic.union(.backtickIdentifiers), atKind: .attribute)

    package static let dart = NoteSyntaxGrammar(
        keywords: """
        abstract as assert async await base break case catch const continue covariant default deferred do dynamic \
        else export extends external factory final finally for Function hide if implements import in interface is \
        late library new of on operator part required rethrow return sealed show static switch sync throw try var \
        void when while with yield
        """,
        types: "int double num String bool List Map Set Object Never Null Future Stream Iterable",
        constants: "true false null",
        builtins: "print",
        operands: "this super",
        typeDeclarators: "class enum mixin extension typedef",
        lineComments: slashComments, blockComments: nestedStarComment,
        strings: [NoteSyntaxStringRule("'''", multiline: true, interpolation: .dollarName),
                  NoteSyntaxStringRule("\"\"\"", multiline: true, interpolation: .dollarName),
                  NoteSyntaxStringRule("'", interpolation: .dollarName),
                  NoteSyntaxStringRule("\"", interpolation: .dollarName)],
        prefixes: .dart,
        features: classic, atKind: .attribute)

    package static let json = NoteSyntaxGrammar(
        constants: "true false null NaN Infinity",
        lineComments: slashComments, blockComments: starComment, strings: quoted,
        features: [.keysBeforeColon, .signedNumbers], operators: "+-", punctuation: "{}[],:")

    package static let sql = NoteSyntaxGrammar(
        keywords: """
        select from where insert into values update set delete create table drop alter add column index view as \
        join inner left right full outer cross on using group by order having limit offset union all distinct and \
        or not is in exists between like ilike case when then else end primary key foreign references unique \
        default check constraint if begin commit rollback transaction with recursive returning asc desc database \
        schema grant revoke to truncate replace explain analyze over partition window cascade restrict trigger \
        procedure function returns language declare row rows fetch next only first last nulls do nothing conflict \
        lateral natural top temporary temp materialized sequence extension owner collate filter within except \
        intersect for each execute instead of before after any some cast
        """,
        types: """
        int integer smallint bigint tinyint decimal numeric real float double precision varchar char character \
        text boolean bool date time timestamp timestamptz interval uuid json jsonb blob bytea serial bigserial money
        """,
        constants: "true false null unknown current_date current_time current_timestamp",
        builtins: """
        count sum avg min max coalesce nullif now lower upper length substring trim round abs concat date_trunc \
        extract to_char row_number rank dense_rank lag lead first_value last_value string_agg array_agg json_agg \
        greatest least ifnull isnull
        """,
        caseInsensitive: true,
        lineComments: ["--"], blockComments: starComment,
        strings: [NoteSyntaxStringRule("'", multiline: true, escapes: false, doubledClose: true),
                  NoteSyntaxStringRule("\"", multiline: true, escapes: false, doubledClose: true, kind: .variable),
                  NoteSyntaxStringRule("`", escapes: false, doubledClose: true, kind: .variable)],
        prefixes: .sql,
        features: [.callsAreFunctions, .memberProperties, .sqlLiterals],
        operators: "+-*/%=<>!|&^~", dollarKind: .variable)

    package static let bash = NoteSyntaxGrammar(
        keywords: "fi esac done in coproc select case for",
        constants: "true false",
        builtins: """
        echo printf read cd pwd pushd popd dirs export unset local declare typeset readonly let eval exec exit \
        return shift source alias unalias set shopt trap wait kill jobs bg fg disown umask ulimit getopts hash type \
        command builtin enable help history logout mapfile readarray test break continue caller compgen complete . :
        """,
        functionDeclarators: "function",
        commandStarters: "if then else elif do while until time",
        lineComments: ["#"],
        strings: [NoteSyntaxStringRule("\"", multiline: true, interpolation: .shell),
                  NoteSyntaxStringRule("'", multiline: true, escapes: false)],
        features: [.shell],
        wordExtras: "-./~+%@:,", wordStartExtras: "./~-+%@:",
        operators: "|&;<>=!", punctuation: "(){}[]", digitSeparators: "")

    package static let powershell = NoteSyntaxGrammar(
        keywords: """
        begin break catch class continue data define do dynamicparam else elseif end enum exit filter finally for \
        foreach from function hidden if in param process return static switch throw trap try until using var \
        while workflow parallel sequence inlinescript
        """,
        caseInsensitive: true,
        lineComments: ["#"], blockComments: [NoteSyntaxBlockComment("<#", "#>")],
        strings: [NoteSyntaxStringRule("\"", multiline: true, interpolation: .powershell, escape: NoteSyntaxChar.backtick),
                  NoteSyntaxStringRule("'", multiline: true, escapes: false, doubledClose: true)],
        features: [.callsAreFunctions, .memberProperties, .powershell],
        operators: "+-*/%=<>!|&", punctuation: "(){}[];,.")

    package static let powershellOperators: Set<String> = [
        "eq", "ne", "gt", "ge", "lt", "le", "like", "notlike", "match", "notmatch", "contains", "notcontains", "in",
        "notin", "replace", "split", "join", "and", "or", "not", "xor", "band", "bor", "bxor", "bnot", "shl", "shr",
        "is", "isnot", "as", "f", "ceq", "cne", "clike", "cmatch", "creplace", "ieq", "ine", "ilike", "imatch",
    ]

    package static let lua = NoteSyntaxGrammar(
        keywords: "and break do else elseif end for goto if in local not or repeat return then until while",
        constants: "nil true false",
        builtins: """
        assert collectgarbage dofile error getmetatable ipairs load loadfile next pairs pcall print rawequal rawget \
        rawlen rawset require select setmetatable tonumber tostring type xpcall string table math io os coroutine \
        utf8 debug package _G _ENV
        """,
        variables: "self",
        functionDeclarators: "function",
        lineComments: ["--"],
        strings: quoted,
        features: [.callsAreFunctions, .memberProperties, .luaLongBrackets],
        operators: "+-*/%^#=<>~&|:")

    package static let r = NoteSyntaxGrammar(
        keywords: "if else repeat while function for in next break return",
        constants: "TRUE FALSE NULL Inf NaN NA NA_integer_ NA_real_ NA_character_ NA_complex_ T F",
        builtins: """
        c list print cat paste paste0 library require data.frame matrix vector length sum mean median sd var min \
        max seq rep apply lapply sapply vapply mapply invisible stop warning message is.na nrow ncol names head \
        tail summary str factor levels table unique sort order rev which ifelse identical
        """,
        lineComments: ["#"],
        strings: [NoteSyntaxStringRule("\"", multiline: true), NoteSyntaxStringRule("'", multiline: true)],
        prefixes: .r,
        features: [.callsAreFunctions, .backtickIdentifiers, .percentOperators],
        wordExtras: ".", wordStartExtras: ".", operators: "+-*/^=<>!&|~?:$@", punctuation: "(){}[];,")

    package static let haskell = NoteSyntaxGrammar(
        keywords: """
        case class data default deriving do else foreign if import in infix infixl infixr instance let module \
        newtype of then type where qualified as hiding forall mdo family pattern
        """,
        constants: "True False Nothing otherwise",
        builtins: """
        map filter foldr foldl head tail print putStrLn putStr show read return pure fmap mapM mapM_ length reverse \
        concat concatMap zip zipWith lookup error undefined sum product elem take drop not fst snd id const flip \
        maybe either seq
        """,
        lineComments: ["--"],
        blockComments: [NoteSyntaxBlockComment("{-#", "#-}", kind: .meta), NoteSyntaxBlockComment("{-", "-}", nests: true)],
        strings: [NoteSyntaxStringRule("\""), NoteSyntaxStringRule("'")],
        features: [.capitalizedTypes, .haskellDashes, .lineStartFunctions, .backtickIdentifiers],
        wordExtras: "'", operators: "+-*/%=&|^!<>~?:.$#@\\", punctuation: "(){}[];,")

    package static let elixir = NoteSyntaxGrammar(
        keywords: """
        do end fn case cond with when if else unless receive try rescue catch after raise import alias require use \
        quote unquote unquote_splicing for in and or not throw super defstruct defexception defoverridable \
        defdelegate
        """,
        constants: "true false nil __MODULE__ __DIR__ __ENV__ __CALLER__ __STACKTRACE__",
        builtins: "IO Enum Map List String Kernel Agent Task GenServer Supervisor Process",
        functionDeclarators: "def defp defmacro defmacrop defguard defguardp",
        typeDeclarators: "defmodule defprotocol defimpl",
        lineComments: ["#"],
        strings: [NoteSyntaxStringRule("\"\"\"", multiline: true, interpolation: .hashBrace),
                  NoteSyntaxStringRule("'''", multiline: true, interpolation: .hashBrace),
                  NoteSyntaxStringRule("\"", multiline: true, interpolation: .hashBrace),
                  NoteSyntaxStringRule("'", multiline: true, interpolation: .hashBrace)],
        features: [.callsAreFunctions, .memberProperties, .capitalizedTypes, .symbols, .elixirSigils],
        wordSuffixes: "?!", atKind: .attribute)

    package static let mermaid = NoteSyntaxGrammar(
        keywords: """
        graph flowchart subgraph end direction sequenceDiagram participant actor as Note note over left right of loop \
        alt else opt par and rect critical break autonumber activate deactivate box create destroy link links \
        classDiagram class namespace interface annotation stateDiagram state erDiagram gantt title dateFormat \
        axisFormat tickInterval excludes includes weekday todayMarker section pie showData journey gitGraph commit \
        branch checkout merge cherry mindmap timeline quadrantChart sankey xychart line bar block columns space \
        C4Context C4Container C4Component C4Dynamic C4Deployment requirementDiagram requirement element kanban \
        architecture group service junction packet radar classDef style linkStyle click call href callback \
        accTitle accDescr id type tag order
        """,
        types: """
        Person Person_Ext System System_Ext SystemDb SystemQueue Container ContainerDb ContainerQueue Component \
        ComponentDb ComponentQueue Boundary Enterprise_Boundary System_Boundary Container_Boundary Rel BiRel \
        Rel_Up Rel_Down Rel_Left Rel_Right UpdateElementStyle UpdateRelStyle
        """,
        constants: "TB TD BT RL LR true false",
        lineComments: ["%%"],
        strings: [NoteSyntaxStringRule("\"", escapes: false)],
        features: [.callsAreFunctions],
        operators: "-=<>.|~:&*+!", punctuation: "()[]{};,")

    package static let graphql = NoteSyntaxGrammar(
        keywords: """
        query mutation subscription fragment on type interface union enum input scalar schema extend directive \
        implements repeatable
        """,
        types: "Int Float String Boolean ID",
        constants: "true false null",
        lineComments: ["#"],
        strings: [NoteSyntaxStringRule("\"\"\"", multiline: true, escapes: false), NoteSyntaxStringRule("\"")],
        features: [.callsAreFunctions, .capitalizedTypes, .keysBeforeColon],
        operators: "=!|&:", punctuation: "(){}[],.", dollarKind: .variable, atKind: .attribute)

    package static let zig = NoteSyntaxGrammar(
        keywords: """
        addrspace align allowzero and anyframe anytype asm async await break callconv catch comptime const continue \
        defer else enum errdefer error export extern for if inline linksection noalias noinline nosuspend opaque or \
        orelse packed pub resume return struct suspend switch test threadlocal try union unreachable usingnamespace \
        package var volatile while
        """,
        types: """
        isize usize c_short c_ushort c_int c_uint c_long c_ulong c_longlong c_ulonglong c_char f16 f32 f64 f80 f128 \
        bool void noreturn type anyerror comptime_int comptime_float anyopaque
        """,
        constants: "true false null undefined",
        functionDeclarators: "fn",
        lineComments: slashComments,
        strings: quoted,
        features: classic.union(.zigLiterals))

    package static let php = NoteSyntaxGrammar(
        keywords: """
        abstract and as break callable case catch clone const continue declare default do echo else elseif empty \
        enddeclare endfor endforeach endif endswitch endwhile extends final finally fn for foreach global goto if \
        implements include include_once instanceof insteadof isset list match namespace new or print private \
        protected public readonly require require_once return static switch throw try unset use var while xor \
        yield die exit
        """,
        types: "int float string bool array object mixed void iterable never null self parent",
        constants: "true false null __CLASS__ __DIR__ __FILE__ __FUNCTION__ __LINE__ __METHOD__ __NAMESPACE__ __TRAIT__ PHP_EOL PHP_VERSION",
        builtins: """
        count strlen str_replace explode implode array_map array_filter array_keys array_values array_merge in_array \
        json_encode json_decode sprintf printf var_dump print_r is_null is_array htmlspecialchars trim strtolower \
        strtoupper substr strpos
        """,
        functionDeclarators: "function",
        typeDeclarators: "class interface trait enum",
        caseInsensitive: true,
        lineComments: ["//", "#"], blockComments: starComment,
        strings: [NoteSyntaxStringRule("\"", multiline: true, interpolation: .php),
                  NoteSyntaxStringRule("'", multiline: true, rawEscapes: true),
                  NoteSyntaxStringRule("`", multiline: true, interpolation: .php)],
        features: [.callsAreFunctions, .capitalizedTypes, .capsConstants, .arrowMembers, .memberProperties, .phpLiterals],
        operators: "+-*/%=&|^!<>~?:.@", punctuation: "(){}[];,", dollarKind: .variable)

    package static let dockerInstructions: Set<String> = [
        "FROM", "RUN", "CMD", "LABEL", "MAINTAINER", "EXPOSE", "ENV", "ADD", "COPY", "ENTRYPOINT", "VOLUME", "USER",
        "WORKDIR", "ARG", "ONBUILD", "STOPSIGNAL", "HEALTHCHECK", "SHELL",
    ]

    package static let makeDirectives: Set<String> = [
        "include", "-include", "sinclude", "ifeq", "ifneq", "ifdef", "ifndef", "else", "endif", "define", "endef",
        "export", "unexport", "override", "private", "vpath", "undefine",
    ]

    package static let makeFunctions: Set<String> = [
        "wildcard", "patsubst", "subst", "shell", "call", "foreach", "if", "or", "and", "filter", "filter-out", "sort",
        "word", "words", "wordlist", "dir", "notdir", "suffix", "basename", "addsuffix", "addprefix", "join",
        "realpath", "abspath", "error", "warning", "info", "origin", "flavor", "eval", "value", "file", "strip",
        "findstring", "firstword", "lastword", "let", "intcmp",
    ]
}
