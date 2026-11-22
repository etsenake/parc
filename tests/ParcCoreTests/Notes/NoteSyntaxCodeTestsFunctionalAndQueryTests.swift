import Foundation
import Testing
@testable import ParcCore

struct NoteSyntaxCodeTestsFunctionalAndQueryTests {
    typealias TokenCase = NoteSyntaxCodeTestsSupport.TokenCase
    private typealias SyntaxProbe = NoteSyntaxCodeTestsSupport.SyntaxProbe

    private static let elixirSource = """
        defmodule Greeter do
          @moduledoc \"\"\"
          Says #{"hi"}
          \"\"\"
          def hello(name, opts \\\\ []) when is_binary(name) do
            pattern = ~r/^\\w+$/i
            words = ~w(a b c)
            IO.puts("Hello #{name}") |> then(fn _ -> :ok end)
            %{status: :done, valid?: true}
          end
        end
        """

    private static let elixirTokens = [
        TokenCase("defmodule", .keyword),
        TokenCase("Greeter", .type),
        TokenCase("@moduledoc", .attribute),
        TokenCase("Says ", .string),
        TokenCase("\"hi\"", .string),
        TokenCase("def", .keyword),
        TokenCase("hello", .function),
        TokenCase("when", .keyword),
        TokenCase("~r/^\\w+$/i", .regex),
        TokenCase("~w(a b c)", .string),
        TokenCase("IO", .builtin),
        TokenCase("puts", .function),
        TokenCase("|>", .operatorSymbol),
        TokenCase(":ok", .constant),
        TokenCase("status:", .constant),
        TokenCase(":done", .constant),
        TokenCase("valid?:", .constant),
        TokenCase("true", .constant),
    ]

    @Test(arguments: elixirTokens)
    func elixirFragmentsHaveTheExpectedHighlight(token: TokenCase) {
        SyntaxProbe("elixir", Self.elixirSource).expect(token)
    }

    @Test
    func elixirTokenRangesAreWellFormed() {
        SyntaxProbe("elixir", Self.elixirSource).expectWellFormed()
    }

    private static let haskellSource = """
        {-# LANGUAGE OverloadedStrings #-}
        module Main where
        {- outer {- nested -} still -}
        data Shape = Circle Double | Square Double deriving (Show)
        area :: Shape -> Double
        area (Circle r) = pi * r ^ 2 -- comment
        area' x = x --> y
        main = putStrLn "it's \\"fine\\"" >> print 'c'
        """

    private static let haskellTokens = [
        TokenCase("{-# LANGUAGE OverloadedStrings #-}", .meta),
        TokenCase("module", .keyword),
        TokenCase("{- outer {- nested -} still -}", .comment),
        TokenCase("data", .keyword),
        TokenCase("Shape", .type),
        TokenCase("Circle", .type),
        TokenCase("deriving", .keyword),
        TokenCase("area", .function),
        TokenCase("::", .operatorSymbol),
        TokenCase("-- comment", .comment),
        TokenCase("area'", .function),
        TokenCase("-->", .operatorSymbol),
        TokenCase("putStrLn", .builtin),
        TokenCase("\\\"", .escape),
        TokenCase("'c'", .string),
    ]

    @Test(arguments: haskellTokens)
    func haskellFragmentsHaveTheExpectedHighlight(token: TokenCase) {
        SyntaxProbe("haskell", Self.haskellSource).expect(token)
    }

    @Test
    func haskellTokenRangesAreWellFormed() {
        SyntaxProbe("haskell", Self.haskellSource).expectWellFormed()
    }

    private static let sqlSource = """
        -- top users
        SELECT u.name, COUNT(*) AS total FROM users u
        WHERE u.bio LIKE 'it''s -- fine' AND u.id = :id OR "Weird Col" > $1
        /* block */ GROUP BY u.name ORDER BY total DESC;
        CREATE FUNCTION f() RETURNS int AS $$ SELECT 1 $$ LANGUAGE sql;
        """

    private static let sqlTokens = [
        TokenCase("-- top users", .comment),
        TokenCase("SELECT", .keyword),
        TokenCase("name", .property),
        TokenCase("COUNT", .builtin),
        TokenCase("AS", .keyword),
        TokenCase("'it''s -- fine'", .string),
        TokenCase(":id", .variable),
        TokenCase("\"Weird Col\"", .variable),
        TokenCase("$1", .variable),
        TokenCase("/* block */", .comment),
        TokenCase("DESC", .keyword),
        TokenCase("int", .type),
        TokenCase("$$ SELECT 1 $$", .string),
    ]

    @Test(arguments: sqlTokens)
    func sqlFragmentsHaveTheExpectedHighlight(token: TokenCase) {
        SyntaxProbe("sql", Self.sqlSource).expect(token)
    }

    @Test
    func sqlTokenRangesAreWellFormed() {
        SyntaxProbe("sql", Self.sqlSource).expectWellFormed()
    }

    private static let graphqlSource = """
        # fetch a user
        query GetUser($id: ID!, $withPosts: Boolean = false) @cached {
          user(id: $id) { name ...UserFields posts @include(if: $withPosts) { title } }
        }
        type User implements Node { "doc" name: String! }
        """

    private static let graphqlTokens = [
        TokenCase("# fetch a user", .comment),
        TokenCase("query", .keyword),
        TokenCase("GetUser", .function),
        TokenCase("$id", .variable),
        TokenCase("ID", .type),
        TokenCase("false", .constant),
        TokenCase("@cached", .attribute),
        TokenCase("user", .function, 2),
        TokenCase("id", .property, 2),
        TokenCase("UserFields", .type),
        TokenCase("@include", .attribute),
        TokenCase("type", .keyword),
        TokenCase("implements", .keyword),
        TokenCase("\"doc\"", .string),
        TokenCase("name", .property, 2),
        TokenCase("ID", .type),
    ]

    @Test(arguments: graphqlTokens)
    func graphqlFragmentsHaveTheExpectedHighlight(token: TokenCase) {
        SyntaxProbe("graphql", Self.graphqlSource).expect(token)
    }

    @Test
    func graphqlTokenRangesAreWellFormed() {
        SyntaxProbe("graphql", Self.graphqlSource).expectWellFormed()
    }
}
