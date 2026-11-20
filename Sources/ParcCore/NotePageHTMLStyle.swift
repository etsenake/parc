import Foundation

enum NotePageHTMLStyle {
    struct Swatch {
        var text: String
        var background: String
        var darkText: String
        var darkBackground: String
    }

    static let palette: [NoteColor: Swatch] = [
        .gray: Swatch(text: "787774", background: "F1F1EF", darkText: "9B9B9B", darkBackground: "2F2F2F"),
        .brown: Swatch(text: "9F6B53", background: "F4EEEE", darkText: "BA856F", darkBackground: "4A3228"),
        .orange: Swatch(text: "D9730D", background: "FBECDD", darkText: "C77D48", darkBackground: "5C3B23"),
        .yellow: Swatch(text: "CB912F", background: "FBF3DB", darkText: "CA9849", darkBackground: "564328"),
        .green: Swatch(text: "448361", background: "EDF3EC", darkText: "529E72", darkBackground: "243D30"),
        .blue: Swatch(text: "337EA9", background: "E7F3F8", darkText: "379AD3", darkBackground: "143A4E"),
        .purple: Swatch(text: "9065B0", background: "F6F3F9", darkText: "9D68D3", darkBackground: "3C2D49"),
        .pink: Swatch(text: "C14C8A", background: "FAF1F5", darkText: "D15796", darkBackground: "4E2C3C"),
        .red: Swatch(text: "D44C47", background: "FDEBEC", darkText: "DF5452", darkBackground: "522E2A")
    ]

    static let mimeTypes: [String: String] = [
        "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif", "webp": "image/webp",
        "svg": "image/svg+xml", "heic": "image/heic", "heif": "image/heif", "tif": "image/tiff", "tiff": "image/tiff",
        "bmp": "image/bmp", "avif": "image/avif", "ico": "image/x-icon"
    ]

    private static func variables(dark: Bool) -> String {
        NoteColor.allCases.map { color in
            let swatch = palette[color]!
            return "--" + color.rawValue + ":#" + (dark ? swatch.darkText : swatch.text) + ";--" + color.rawValue
                + "-bg:#" + (dark ? swatch.darkBackground : swatch.background) + ";"
        }.joined()
    }

    private static var colorRules: String {
        NoteColor.allCases.map { color in
            let name = color.rawValue
            return ".highlight-\(name),.block-color-\(name){color:var(--\(name))}"
                + ".highlight-\(name)_background{background:var(--\(name)-bg);color:inherit;border-radius:3px;padding:0 .1em}"
                + ".block-color-\(name)_background{background:var(--\(name)-bg);border-radius:6px}\n"
        }.joined()
    }

    static let css: String = """
    :root{--ink:#1F1B2E;--title:#220C7F;--muted:rgba(31,27,46,.62);--faint:rgba(31,27,46,.38);\
    --line:rgba(31,27,46,.12);--accent:#2702C2;--link:#220C7F;--paper:#FFFFFF;--fill:rgba(31,27,46,.045);\
    --callout:rgba(31,27,46,.045);--code-ink:#C0306A;--code-fill:rgba(39,2,194,.07);--check:#2702C2;\
    --font:"Nunito",ui-rounded,"SF Pro Rounded",-apple-system,BlinkMacSystemFont,"Segoe UI","Helvetica Neue",Arial,sans-serif;\
    --mono:"Space Mono",ui-monospace,"SF Mono",Menlo,Consolas,"Liberation Mono",monospace;\
    --math:"STIX Two Math","Latin Modern Math","Cambria Math","Times New Roman",serif;\(variables(dark: false))}
    @media screen and (prefers-color-scheme:dark){:root{--ink:#EDEBFA;--title:#E6E6FF;--muted:rgba(237,235,250,.62);\
    --faint:rgba(237,235,250,.38);--line:rgba(255,255,255,.14);--accent:#9380E0;--link:#E6E6FF;--paper:#16141F;\
    --fill:rgba(255,255,255,.06);--callout:rgba(255,255,255,.06);--code-ink:#FF8FB8;--code-fill:rgba(147,128,224,.18);\
    --check:#9380E0;\(variables(dark: true))}}
    *{box-sizing:border-box}
    html{background:var(--paper);-webkit-text-size-adjust:100%}
    body{margin:0;background:var(--paper);color:var(--ink);font-family:var(--font);font-size:17px;line-height:1.6;\
    -webkit-font-smoothing:antialiased;text-rendering:optimizeLegibility}
    body.page-font-serif{--font:"EB Garamond","Iowan Old Style","Palatino Linotype",Palatino,Georgia,serif;font-size:19px}
    body.page-font-mono{--font:"Space Mono",ui-monospace,"SF Mono",Menlo,Consolas,monospace;font-size:15.5px}
    body.page-font-wide{--font:"Parc Wide","Mona Sans","Helvetica Neue",Arial,sans-serif;font-stretch:125%}
    body.small-text{font-size:15px}
    body.small-text.page-font-serif{font-size:17px}
    body.small-text.page-font-mono{font-size:14px}
    .page{max-width:780px;margin:0 auto;padding:72px 48px 120px}
    body.full-width .page{max-width:none;padding-left:72px;padding-right:72px}
    .page-cover{display:block;width:100%;height:30vh;min-height:180px;max-height:320px;object-fit:cover}
    body.has-cover .page{padding-top:0}
    body.has-cover.has-icon .page-icon{margin-top:-0.55em}
    body.has-cover:not(.has-icon) .page-header{padding-top:48px}
    .page-icon{font-size:78px;line-height:1.1;margin:0 0 8px;position:relative}
    .page-icon-image{display:block;width:96px;height:96px;object-fit:cover;border-radius:14px;font-size:0}
    body.has-cover.has-icon .page-icon-image{margin-top:-48px;box-shadow:0 0 0 4px var(--paper)}
    .page-title{font-size:2.4em;line-height:1.15;font-weight:800;color:var(--title);letter-spacing:-.01em;margin:.25em 0 .5em}
    .page-properties{margin:0 0 1.6em;padding:0 0 1em;border-bottom:1px solid var(--line);font-size:.9em}
    .page-properties div{display:flex;gap:1em;padding:.15em 0}
    .page-properties dt{flex:0 0 9em;color:var(--muted)}
    .page-properties dd{margin:0}
    .property-chip{display:inline-block;padding:0 .5em;border-radius:4px;background:var(--fill)}
    .page-body>:first-child{margin-top:0}
    p{margin:.25em 0;min-height:1em}
    h1,h2,h3,h4,h5,h6{font-weight:800;line-height:1.3;margin:1.5em 0 .35em;scroll-margin-top:24px}
    h1{font-size:1.85em}h2{font-size:1.45em}h3{font-size:1.2em}h4{font-size:1.05em}h5,h6{font-size:1em}
    strong{font-weight:800}
    a{color:var(--link);text-decoration:underline;text-decoration-color:var(--faint);text-underline-offset:.18em}
    a:hover{text-decoration-color:currentColor}
    ul,ol{margin:.25em 0;padding-left:1.6em}
    li{margin:.15em 0;padding-left:.15em}
    li>ul,li>ol{margin:.1em 0}
    ul ul{list-style-type:circle}ul ul ul{list-style-type:square}
    ol ol{list-style-type:lower-alpha}ol ol ol{list-style-type:lower-roman}
    ul.contains-task-list{list-style:none;padding-left:.2em}
    .task-list-item{display:block;position:relative;padding-left:1.75em}
    .task-list-item>input[type=checkbox]{-webkit-appearance:none;appearance:none;position:absolute;left:0;top:.28em;\
    width:1.05em;height:1.05em;margin:0;border:1.5px solid var(--faint);border-radius:.3em;background:transparent}
    .task-list-item.checked>input[type=checkbox]{background:var(--check);border-color:var(--check)}
    .task-list-item.checked>input[type=checkbox]::after{content:"";position:absolute;left:.3em;top:.08em;width:.28em;\
    height:.55em;border:solid #fff;border-width:0 .14em .14em 0;transform:rotate(45deg)}
    .task-list-item.checked>.todo-text{color:var(--faint);text-decoration:line-through}
    blockquote{margin:.5em 0;padding:.05em 0 .05em 1em;border-left:3px solid currentColor;font-size:1.08em}
    aside.callout{display:flex;gap:.7em;margin:.6em 0;padding:14px 18px;border-radius:12px;background:var(--callout)}
    aside.callout[class*=block-color-]:not([class*=_background]){background:transparent;box-shadow:inset 0 0 0 1px var(--line)}
    .callout-icon{flex:0 0 auto;font-size:1.25em;line-height:1.3}
    img.callout-icon{width:1.4em;height:1.4em;object-fit:cover;border-radius:4px}
    .callout-body{flex:1 1 auto;min-width:0}
    .callout-body>:first-child{margin-top:0}.callout-body>:last-child{margin-bottom:0}
    details.toggle{margin:.25em 0}
    details>summary{cursor:pointer;list-style:none;position:relative;padding-left:1.5em}
    details>summary::-webkit-details-marker{display:none}
    details>summary::before{content:"";position:absolute;left:.3em;top:.5em;border-style:solid;border-width:.32em 0 .32em .5em;\
    border-color:transparent transparent transparent currentColor;transition:transform .2s cubic-bezier(.34,1.56,.64,1)}
    details[open]>summary::before{transform:rotate(90deg)}
    details>summary>h1,details>summary>h2,details>summary>h3,details>summary>h4,details>summary>h5,details>summary>h6{\
    display:inline;margin:0}
    details>summary:has(h1,h2,h3,h4,h5,h6){margin:1.2em 0 .3em}
    .toggle-body{padding-left:1.5em}
    .indented{padding-left:1.5em}
    hr{border:0;border-top:1px solid var(--line);margin:1.4em 0}
    code{font-family:var(--mono);font-size:.84em;color:var(--code-ink);background:var(--code-fill);border-radius:5px;\
    padding:.12em .36em}
    pre{position:relative;margin:.7em 0;padding:18px 20px;border-radius:10px;background:var(--fill);overflow-x:auto;\
    font-family:var(--mono);font-size:.84em;line-height:1.55;tab-size:4;white-space:pre-wrap;word-break:break-word}
    pre code{font-size:1em;color:inherit;background:none;padding:0;border-radius:0}
    pre[data-language]::before{content:attr(data-language);position:absolute;top:8px;right:12px;font-family:var(--font);\
    font-size:.78em;color:var(--faint);text-transform:capitalize}
    figure{margin:.9em 0}
    figure.image{text-align:center}figure.image.align-left{text-align:left}figure.image.align-right{text-align:right}
    figure.image img{max-width:100%;height:auto;border-radius:8px}
    figure.image[style*=width] img{width:100%}
    figure.image[style*=width]{margin-left:auto;margin-right:auto}
    video,audio{display:block;max-width:100%;border-radius:8px}
    audio{width:100%}
    figcaption{margin-top:.45em;color:var(--muted);font-size:.86em;text-align:left}
    figure.image figcaption{text-align:center}
    figure.diagram{margin:.7em 0}
    .diagram-art{padding:18px 20px;border-radius:10px;background:var(--fill);overflow-x:auto;text-align:center;line-height:0}
    .diagram-art svg{display:inline-block;max-width:none;height:auto;vertical-align:top}
    figure.diagram.split pre{margin:0;border-radius:10px 10px 0 0}
    figure.diagram.split .diagram-art{border-radius:0 0 10px 10px;border-top:1px solid var(--line)}
    .diagram-dark{display:none}
    @media screen and (prefers-color-scheme:dark){.diagram-light{display:none}.diagram-dark{display:block}}
    .file-link,.embed-link{display:inline-flex;gap:.4em;align-items:center;padding:.35em .7em;border-radius:8px;\
    background:var(--fill);text-decoration:none;color:var(--ink)}
    .bookmark-card{display:flex;align-items:stretch;border:1px solid var(--line);border-radius:10px;overflow:hidden;\
    text-decoration:none;color:var(--ink)}
    .bookmark-text{flex:1 1 auto;min-width:0;padding:12px 16px;display:flex;flex-direction:column;gap:.2em}
    .bookmark-title{font-weight:700;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
    .bookmark-summary{color:var(--muted);font-size:.86em;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
    .bookmark-url{display:flex;align-items:center;gap:.4em;font-size:.82em;color:var(--muted)}
    .bookmark-favicon{width:16px;height:16px;border-radius:3px}
    .bookmark-image{flex:0 0 32%;max-width:220px;object-fit:cover}
    .page-link a{text-decoration:none;font-weight:700;border-bottom:1px solid var(--line)}
    .page-mention{font-weight:700;text-decoration:none;border-bottom:1px solid var(--line)}
    .page-mention::before{content:"\\1F4C4\\00A0"}
    .date-mention{color:var(--muted)}
    .link-mention{font-weight:600}
    .equation .tex{font-family:var(--math);font-style:italic;color:var(--accent);background:var(--code-fill);\
    border-radius:5px;padding:.05em .35em}
    div.equation{margin:.8em 0;text-align:center;overflow-x:auto}
    div.equation .tex{display:inline-block;padding:.5em 1em;font-size:1.1em}
    img.equation{vertical-align:middle;max-width:100%}
    div.equation img{max-width:100%}
    div.equation img[usemap],img.equation[usemap]{max-width:none}
    div.equation:target{border-radius:8px;background:var(--code-fill)}
    table{border-collapse:collapse;margin:.8em 0;font-size:.95em;display:block;overflow-x:auto;max-width:100%}
    th,td{border:1px solid var(--line);padding:7px 12px;text-align:left;vertical-align:top;min-width:4em}
    thead th,tbody th{background:var(--fill);font-weight:700}
    nav.table-of-contents{margin:.6em 0}
    nav.table-of-contents ul{list-style:none;padding:0;margin:0}
    nav.table-of-contents li{margin:.1em 0}
    nav.table-of-contents a{color:var(--muted);text-decoration:none;border-bottom:1px solid var(--line)}
    .toc-level-2{padding-left:1.4em}.toc-level-3{padding-left:2.8em}.toc-level-4,.toc-level-5,.toc-level-6{padding-left:4.2em}
    .columns{display:flex;gap:2em;margin:.4em 0}
    .column{flex:1 1 0;min-width:0}
    .column>:first-child{margin-top:0}
    p[class*=block-color-][class*=_background],h1[class*=_background],h2[class*=_background],h3[class*=_background],\
    li[class*=_background]{padding:.1em .35em}
    \(colorRules)\
    @media (max-width:640px){.page{padding:40px 20px 80px}body.full-width .page{padding-left:20px;padding-right:20px}\
    .columns{flex-direction:column;gap:.4em}.page-icon{font-size:60px}}
    @media print{@page{margin:18mm 16mm}body{font-size:12pt}.page{max-width:none;padding:0}.page-cover{max-height:220px;margin-bottom:24px}\
    body.has-cover .page-header{padding-top:0}pre,aside,figure,table,blockquote,.bookmark-card{break-inside:avoid}\
    h1,h2,h3,h4{break-after:avoid}a{color:inherit}pre{white-space:pre-wrap}\
    .diagram-art{overflow:visible}.diagram-art svg{max-width:100%}}

    """
}
