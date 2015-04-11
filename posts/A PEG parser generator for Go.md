---
Author: Martin Angers
Title: A PEG parser generator for Go
Date: 2015-01-01
Description: Parsing expression grammars (PEGs) are an interesting alternative to the traditional context-free grammars (CFGs) often seen in the field of programming languages - usually in some flavor of Backus-Naur form. Attributed to Bryan Ford and his 2004 paper, this is a relatively new theory. I spent the last few weeks working on a PEG-based parser generator for Go (think compiler-compiler, a-la yacc/bison). This gave birth to pigeon.
Lang: en
---

# A PEG parser generator for Go

[Parsing expression grammars (PEGs)][peg] are an interesting alternative to the traditional [context-free grammars (CFGs)][cfg] often seen in the field of programming languages - usually in some flavor of [Backus-Naur form][BNF]. Attributed to [Bryan Ford and his 2004 paper][ford], this is a relatively new theory. PEGs are unambiguous and offer unlimited lookahead, which also means potentially exponential time performance in pathological cases - something that can be mitigated in practice with memoization of results, guaranteeing linear time. No lexer is required, the grammar is "self-contained", which is another distinguishing characteristic.

This piqued my interest, and I spent the last few weeks working on a PEG-based parser generator for Go (think compiler-compiler, *à la* yacc/bison). It [gave birth to `pigeon`][pigeon], a Go command-line tool that parses a PEG file and generates Go code that can parse input based on the source grammar.

## A quick taste of PEG, pigeon-style

It is not the goal of this article to teach parsing expression grammars, but just to give a quick idea of what it looks like, a valid calculator grammar can look like this (full listing available in the [github repository][pigeon], under `pigeon/examples/calculator`):

```
// helper function `eval` omitted for brevity

Expr ⟵ _ first:Term rest:( _ AddOp _ Term )* _ {
    return eval(first, rest), nil
}

Term ⟵ first:Factor rest:( _ MulOp _ Factor )* {
    return eval(first, rest), nil
}

Factor ⟵ '(' expr:Expr ')' {
    return expr, nil
} / integer:Integer {
    return integer, nil
}

AddOp ⟵ ( '+' / '-' ) {
    return string(c.text), nil
}

MulOp ⟵ ( '*' / '/' ) {
    return string(c.text), nil
}

Integer ⟵ '-'? [0-9]+ {
    return strconv.Atoi(string(c.text))
}

_ "whitespace" ⟵ [ \n\t\r]*
```

It's fairly easy to see that there's a rule (non-terminal) on the left side of the arrow, associated with a definition (expressions, other non-terminals or terminals) on the right-hand side. Between curly braces are the code blocks associated with the expression - if there's a match, this code gets called. It returns the result of the expression and a (possibly nil) error. This is Go code, obviously.

Many constructs look a lot like regular expressions - indeed, character classes and repetition operators are pretty much what you'd expect (`?` is zero or one, `*` is zero or more and `+` is one or more). String and character literals are simple too - there must be an exact match in the input text. The `/` separator is the ordered choice expression, the first expression that matches is used, so the result of parsing a given input text is always deterministic and unambiguous.

The `"whitespace"` string literal on the left side of the last rule is what is called a display name in pigeon - it can be used to give a friendlier name to a rule and will appear in error messages instead of the rule identifier.

But what is that strange `c.text` reference in the code blocks? Each code block gets generated as a method on the `*current` type, which is defined like this:

```
type current struct {
    pos  position
    text []byte
}
```

By default, the receiver variable is named `c`, but that is configurable via a command-line flag. The `position` type gives the current position in the parser with `line`, `col` and `offset` fields (the first two are 1-based, `col` being a count of runes since the beginning of the line, and `offset` is a 0-based count of bytes since the start of the data). The `text` field is the slice of matching bytes in the current expression. This is a slice of the original source text, so it should not be modified.

A labeled expression, where an identifier is followed by `:` before an expression (like `first` and `rest` in the calculator grammar above), is a variable that "captures" the value of the associated expression, and makes that value available in the corresponding code block. It is converted to an argument (an empty interface) in the generated method for the code block. By default, the value of an expression is a slice of bytes, but if the expression is a sequence or a `*` or `+` repeating expression, then the value in the `interface{}` will be a `[]interface{}` of the corresponding length. Of course all this can be overridden with a code block that returns something else (often an [abstract syntax tree][ast] - node).

## Looks like Go, outputs Go

Although the features and syntax were inspired by the javascript project [PEG.js][pegjs], `pigeon` is made for Go and it shows. The identifiers, string and character literals and comments all follow the same rules as in the Go language, and Go's keywords and predeclared identifiers are disallowed as PEG labels. Also, thanks to Go's great Unicode support, `pigeon` fully supports Unicode code points. The grammars and source text must be UTF-8-encoded text, and it is easy to match against specific Unicode values or classes of values.

```
// this is a single-line comment

/* this is
a multi-line
comment */

'a' // a single character with the same escape sequences as in Go

"a double-quoted string with the same escape sequences as in Go, e.g. \n or \u2190"

`a raw string
where \ are just \,
no escapes, as in Go`
```

In addition to string and character literals, as seen above, character classes can be used in square brackets, similar to regular expressions:

```
[abc]       // a, b or c
[a-z]       // a to z (a range where any character within the integral value of the characters can be used, inclusively)
[\n\r\t]    // the same escape sequences as in Go strings, but " and ' cannot be escaped, although ] must be escaped
[\pL]       // single-letter Unicode class
[\p{Latin}] // Unicode class name
```

Literals and character classes can have a lowercase `"i"` suffix to indicate that the matching should be case-insensitive. There was no obvious syntax to make this Go-like, so the same syntax as PEG.js is used.

```
'A'i
"A String"i
`A raw string`i
[a-z]i
```

And character classes can start with a `^` to invert the condition, so `[^a-z]` means "match anything that is not `a...z`".

Even though pigeon outputs generated code, care has been taken to make this good, readable and idiomatic code. In particular, provided the code blocks in the grammar do the same, the generated code passes both [`golint`][lint] and [`go vet`][vet]. It uses no external dependency.

## Dogfooding

The pigeon command-line tool is itself a parser generated by pigeon. Somehow this feels like Inception, and is just as easy to reason about as the movie. The initial issue of generating the first parser generator is called [bootstrapping][boot] and is a common concept in compilers (as a matter of fact, [Go recently switched][goboot] to a compiler written in Go for version 1.5, after using a C compiler for the previous versions).

To bootstrap pigeon, I use a traditional hand-written lexer and recursive top-down parser found in the `pigeon/bootstrap` package. It only parses the necessary subset of the PEG syntax to create the initial parser generator (the bootstrap-specific grammar can be found in `pigeon/grammar/bootstrap.peg`). The `bootstrap-build` command is the command-line front-end to this bootstrapping parser, and generates the initial parser generator called `bootstrap-pigeon`.

Then, `bootstrap-pigeon` is able to parse the full grammar (found in `pigeon/grammar/pigeon.peg`), and the final, official `pigeon` tool is built this way. As a sanity check, the output of running `bootstrap-pigeon` and `pigeon` on its own grammar can be compared and should be identical, as internally both use the same logic: the grammar is parsed into an AST defined in package `pigeon/ast` and the code is generated using `pigeon/builder`.

The [complete pigeon documentation can be found on the godoc page][godoc], please do [file an issue][issue] if something is not clear or is clearly wrong. And if you use it and like it, [star it on github][pigeon] and talk about it - that's probably the easiest way to contribute to the success of an open source project. You can also [follow me on Twitter][twit], that's where I will mention significant updates to my open source projects.

[peg]: http://en.wikipedia.org/wiki/Parsing_expression_grammar
[cfg]: http://en.wikipedia.org/wiki/Context-free_grammar
[bnf]: http://en.wikipedia.org/wiki/Backus%E2%80%93Naur_Form
[ford]: http://pdos.csail.mit.edu/~baford/packrat/popl04/peg-popl04.pdf
[pigeon]: https://github.com/PuerkitoBio/pigeon
[pegjs]: http://pegjs.org/
[lint]: https://github.com/golang/lint
[vet]: http://godoc.org/golang.org/x/tools/cmd/vet
[boot]: http://en.wikipedia.org/wiki/Bootstrapping_(compilers)
[goboot]: https://docs.google.com/document/d/1OaatvGhEAq7VseQ9kkavxKNAfepWy2yhPUBs96FGV28/edit
[ast]: http://en.wikipedia.org/wiki/Abstract_syntax_tree
[godoc]: https://godoc.org/github.com/PuerkitoBio/pigeon
[issue]: https://github.com/PuerkitoBio/pigeon/issues
[twit]: https://twitter.com/PuerkitoBio
