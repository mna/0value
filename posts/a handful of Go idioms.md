---
Author: Martin Angers
Title: A Handful of Go Idioms
Description:
Date:
Lang: en
---

# A Handful of Go Idioms

Go is a simple language. The [complete language specification][spec] is a relatively short and accessible read. A strong focus has been put on *orthogonality* of features by its designers:

> "[...] we tried to design a language in which the various elements - the type system, the package system, the syntax, concurrency, and so on - were completely "orthogonal", by which I mean that they never interact in surprising ways, making the language easy to understand but also easy to implement."
>
> *Rob Pike, ["Rob Pike, Geek of the Week"][pike2011], January 17th 2011.*

Although this may mean some popular syntactic constructs are not present, it also makes for a very elegant language that brings back the feeling of the ["quiet conversation"][faq].

This blog post will present and explain a handful of Go idioms that have their roots in the standard library, but can be applied in userland packages as well.

## Side-Effect Imports

database/sql, hashes, pprof, talk about init/ no cyclic deps ...

## Package-Level Variables

net/http (default mux, client, transport, makes http.ServeAndListen possible, also link with side-effect import for pprof).

## Streams

io.Reader & io.Writer.

[spec]: http://golang.org/ref/spec
[pike2011]: https://www.simple-talk.com/opinion/geek-of-the-week/rob-pike-geek-of-the-week/
[faq]: http://golang.org/doc/faq#principles
