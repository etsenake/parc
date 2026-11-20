# Notes Mermaid renderer

`mermaid.min.js` draws Mermaid code blocks in Notes. It is the unmodified
`dist/mermaid.min.js` from the npm package
[mermaid 12.3.0](https://www.npmjs.com/package/mermaid/v/12.3.0)
(tarball integrity
`sha512-4113TdXeLAsMruJ79OpFL5O8+LTFXhQqZ260rF3tgUmiNAtRm4Uume04I+65PRN6yZ69J4f8rVYWW8zRk65UYw==`,
file SHA-256
`336df803d87a38b70a01e736e666c8f7601d2ce42f5e47c8fafe5d721074b9a3`).
Mermaid is by Knut Sveidqvist and contributors under the MIT License, in
[LICENSE-mermaid.txt](LICENSE-mermaid.txt). The libraries it bundles keep
their license notices inside the file.

`harness.html` is Parc's page around it. Parc loads it in one windowless
WebKit view with read access to `Resources` only, so the `@font-face` rules
reach the bundled Nunito, EB Garamond, Space Mono and ParcWide files. Its
content security policy refuses every network request, and Mermaid runs at
`securityLevel: strict`.

To update, download the package tarball, check its integrity against the npm
registry, copy `package/dist/mermaid.min.js` and `package/LICENSE` here, and
refresh the version and hashes above.
