import Foundation
import Testing
@testable import ParcCore

struct NoteSyntaxMarkupTestsBuildFileTests {
    typealias TokenCase = NoteSyntaxMarkupTestsSupport.TokenCase
    private typealias SyntaxProbe = NoteSyntaxMarkupTestsSupport.SyntaxProbe

    private static let dockerfileSource = """
        # syntax=docker/dockerfile:1
        FROM --platform=$BUILDPLATFORM node:20-alpine AS build
        ARG VERSION=1.0
        ENV APP_HOME=/app PATH="$APP_HOME/bin:${PATH}"
        WORKDIR $APP_HOME
        # install
        RUN apk add --no-cache git \\
            && echo "built ${VERSION}" > /version.txt
        COPY --from=build /src ./
        EXPOSE 8080/tcp
        CMD ["node", "server.js"]
        """

    private static let dockerfileTokens = [
        TokenCase("# syntax=docker/dockerfile:1", .meta),
        TokenCase("FROM", .keyword),
        TokenCase("--platform", .attribute),
        TokenCase("AS", .keyword),
        TokenCase("ARG", .keyword),
        TokenCase("VERSION", .property),
        TokenCase("APP_HOME", .property),
        TokenCase("\"", .string, 1),
        TokenCase("$APP_HOME", .variable),
        TokenCase("${PATH}", .variable),
        TokenCase("$APP_HOME", .variable, 2),
        TokenCase("# install", .comment),
        TokenCase("RUN", .keyword),
        TokenCase("apk", .function),
        TokenCase("echo", .builtin),
        TokenCase("\"built ", .string),
        TokenCase("${VERSION}", .variable),
        TokenCase("--from", .attribute),
        TokenCase("8080/tcp", .number),
        TokenCase("CMD", .keyword),
        TokenCase("\"node\"", .string),
    ]

    @Test(arguments: dockerfileTokens)
    func dockerfileFragmentsHaveTheExpectedHighlight(token: TokenCase) {
        SyntaxProbe("dockerfile", Self.dockerfileSource).expect(token)
    }

    @Test
    func dockerfileTokenRangesAreWellFormed() {
        SyntaxProbe("dockerfile", Self.dockerfileSource).expectWellFormed()
    }

    private static let makefileSource = """
        # build things
        CC ?= clang
        SOURCES := $(wildcard src/*.c)
        .PHONY: all clean
        all: build/app ## default
        build/%.o: src/%.c $(HEADERS)
        \t@echo "compiling $<" && $(CC) -c $< -o $@ $$HOME
        ifeq ($(DEBUG),1)
        CFLAGS += -g
        endif
        clean:
        \trm -rf build
        """

    private static let makefileTokens = [
        TokenCase("# build things", .comment),
        TokenCase("CC", .variable),
        TokenCase("?=", .operatorSymbol),
        TokenCase("SOURCES", .variable),
        TokenCase(":=", .operatorSymbol),
        TokenCase("wildcard", .builtin),
        TokenCase(".PHONY", .builtin),
        TokenCase("all", .function, 2),
        TokenCase("build/%.o", .function),
        TokenCase("$(HEADERS)", .variable),
        TokenCase("@", .operatorSymbol),
        TokenCase("echo", .builtin),
        TokenCase("$<", .variable),
        TokenCase("$(CC)", .variable),
        TokenCase("$@", .variable),
        TokenCase("$$HOME", .variable),
        TokenCase("ifeq", .keyword),
        TokenCase("$(DEBUG)", .variable),
        TokenCase("CFLAGS", .variable),
        TokenCase("endif", .keyword),
        TokenCase("clean", .function, 2),
        TokenCase("rm", .function),
    ]

    @Test(arguments: makefileTokens)
    func makefileFragmentsHaveTheExpectedHighlight(token: TokenCase) {
        SyntaxProbe("makefile", Self.makefileSource).expect(token)
    }

    @Test
    func makefileTokenRangesAreWellFormed() {
        SyntaxProbe("makefile", Self.makefileSource).expectWellFormed()
    }
}
