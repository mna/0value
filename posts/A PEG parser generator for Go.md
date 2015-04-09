---
Author: Martin Angers
Title: A PEG parser generator for Go
Date
Description: Parsing expression grammars (PEGs) are an interesting alternative to the traditional context-free grammars (CFGs) often seen in the field of programming languages - usually in some variety of Backus-Naur form. Attributed to Bryan Ford and his 2004 paper, this is a relatively new theory. I spent the last few weeks working on a PEG-based parser generator for Go (think compiler-compiler, a-la yacc/bison). This gave birth to pigeon.
Lang: en
---

# A PEG parser generator for Go

[Parsing expression grammars (PEGs)][peg] are an interesting alternative to the traditional [context-free grammars (CFGs)][cfg] often seen in the field of programming languages - usually in some variety of [Backus-Naur form][BNF]. Attributed to [Bryan Ford and his 2004 paper][ford], this is a relatively new theory. PEGs are unambiguous and offer unlimited lookahead, which also means potentially exponential time performance in pathological cases - something that can be mitigated in practice with memoization of results, guaranteeing linear time.

Intrigued and attracted by this grammar, I spent the last few weeks working on a PEG-based parser generator for Go (think compiler-compiler, *a-la* yacc/bison). This gave birth to [`pigeon`][pigeon], a Go command-line tool that parses a PEG file and generates Go code that can parse input based on the source grammar.

## A quick taste of PEG

...

## Looks like Go, outputs Go

Although the features and syntax were based on the javascript project [PEG.js][pegjs], `pigeon` is made for Go and it shows. The identifiers, string and character literals and comments all follow the same rules as in the Go language, and Go's keywords and predeclared identifiers are disallowed as PEG labels (variables that can be referenced in code blocks, more on that later). Also, thanks to Go's great Unicode support, `pigeon` also fully supports Unicode characters. The grammars and source text must be UTF-8-encoded text, and it is easy to match against specific Unicode code points or classes of code points.

```
// this is a single-line comment

/* this is 
a multi-line
comment */

'a' // a single character with the same escape sequences as in Go

"a double-quoted string with the same escape sequences as in Go"

`a raw string
where \ are just \,
no escapes, as in Go`
```

In addition to string and character literals, character classes can be used in square brackets, similar to regular expressions:

```
[abc]       // a, b or c
[a-z]       // a to z (a range where any character within the integral value of the characters can be used, inclusively)
[\n\r\t]    // the same escape sequences as in Go strings, but " and ' cannot be escaped, although ] must be escaped
[\pL]       // single-letter Unicode class
[\p{Latin}] // Unicode class name
```

Literals and character classes can have a lowercase `"i"` suffix to indicate that the matching should be case-insensitive:

```
'A'i
"A String"i
`A raw string"i
[a-z]i
```

And character classes can start with a `"^"` to invert the condition, so `[^a-z]` means "match anything that is not `a...z`".

[peg]: http://en.wikipedia.org/wiki/Parsing_expression_grammar
[cfg]: http://en.wikipedia.org/wiki/Context-free_grammar
[bnf]: http://en.wikipedia.org/wiki/Backus%E2%80%93Naur_Form
[ford]: http://pdos.csail.mit.edu/~baford/packrat/popl04/peg-popl04.pdf
[pigeon]: https://github.com/PuerkitoBio/pigeon
[pegjs]: http://pegjs.org/
