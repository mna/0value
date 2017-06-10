---
Author: Martin Angers
Title: Introducing agora: a dynamic, embeddable programming language built with Go
Date: 2013-09-17
Description: I've been toying with this idea for a while. To bring a simple, dynamic language to complement Go - somewhat like what Lua is to C. I've built to some working state various virtual machines in Go, but for the last few months, I've focused on designing from scratch a simple and clean virtual machine to run a new programming language, agora, that will feel right at home for Go developers.
Lang: en
---
# Introducing agora: a dynamic, embeddable programming language built with Go

I've been toying with this idea for a while. To bring a simple, dynamic language to complement Go - somewhat like what Lua is to C. I've built to some working state various virtual machines in Go, but for the last few months, I've focused on designing from scratch a simple and clean virtual machine to run a [new programming language, agora][agora], that will feel right at home for Go developers.

Now, I'm somewhat a *dilettante* when it comes to compiler and programming language design, and I'm sure there are a few things that will look weird or plain wrong, but this is merely a `v0.1` release and my goal at this point was just to get this project off the ground and prove that it can fly (technically, at least!).

## Design goals

The high-level goals of the language are clear and set in stone. Everything else isn't - meaning things may change just about everywhere in the language: the compiler, the syntax, the stdlib, the runtime, etc.

Those goals are:

* A dynamically-typed language
* An embeddable language
* A garbage-collected language
* Dynamically-loaded modules
* A syntax similar to Go

Here is how it looks as of v0.1:

```
// Output: Hello, Agora !
fmt := import("fmt")
func greet(name) {
    fmt.Println("Hello,", name, "!")
}
greet("Agora")
```

There is a [getting started][start] article on the wiki that provides other useful introductory information. Much more source code examples can be found in [/testdata/src][src].

### Dynamically-typed

Variables, arguments and functions' return value have no types in agora, only values are typed. And values may be any one of those types:

* Number (represented as Go's `float64`)
* String (same as Go's `string`)
* Bool (same as Go's `bool`)
* Nil (roughly like Go's `nil`)
* Func (can be an agora function, or a native Go function)
* Object (an associative array, roughly like Go's `map` but feeling more like a Lua table or a Javascript object)

### Embedded

Agora is a collection of Go packages, and may easily be imported and embedded in a Go program. There is a [native Go API][api] available for Go programs to initialize, configure and run agora code. The agora command-line interface is an example of a Go host running agora programs.

A Go program could embed agora to allow for dynamically-loaded plugins, for example.

### Garbage-collected

Agora is garbage-collected using the native Go GC. All variables are released as soon as they go out of scope in the agora runtime, so that Go's GC can collect them.

### Dynamically-loaded

An agora source code file is called a *module*, and modules are loaded dynamically via the `import` built-in function that takes a string identifier as argument, similar to Go's `import` keyword.

A `ModuleResolver` interface allows for plugging custom resolvers into agora, but out-of-the-box the runtime provides a `FileResolver` type to look for the module in the file system.

Everything in a module is private, there is no uppercase rule for exported symbols. The only thing exposed by a module is its return value, because a module is implicitly a function so it can return a value. The uppercase is still used as a convention for publicly exported values in the stdlib.

### Syntax similar to Go...

The syntax is very similar to Go, and where it makes sense, the same notation is used. In fact, the current scanner is adapted from Go's scanner package.

### ...but not a clone

The goal is obviously not to make a clone, so  it differs in some places too, and not just regarding the types.

The idea is to provide a *looser* and simple companion to the statically-typed and statically-linked Go code. So agora also offers:

* A ternary operator (`?:`)
* The `args` reserved identifier. A caller may pass more or less arguments than expected by the callee. Missing arguments are set to `nil`, and in any case, the full list of received arguments are available via the `args` reserved identifier (an array-like object).
* *Truthy* and *falsy* values, other than boolean `true` and `false`. The falsy values are `nil`, empty string and `0`.
* Overloaded operators via objects meta-methods (i.e. `__add`, `__bool`, etc.).

There's an article on the [similarities and differences between agora and Go][simdiff] in the wiki.

## The CLI

Agora provides a command-line interface to build and run programs without having to write a custom Go host.

The `agora` command offers a few sub-commands, most importantly `agora run FILE` to execute an agora source code file.

The *shebang* (#!) notation is also supported by the compiler (the scanning stage treats the line as a comment), so that shell scripts can be written in agora:

```
#!/usr/bin/env agora run -R
fmt := import("fmt")
fmt.Println("Hello from agora!")
```

See the article on the [command-line tool][cli] on the wiki for more details.

## The stdlib

The standard library offers minimal support at the moment. This is because things are likely to change and evolve quite a bit, with some features that may alter how best to write the API, so I don't want to invest too heavily in it for now.

Also, it is currently unknown how people may use this language (or *if* it will be used, period - although regardless I will surely keep at it, it's just too much fun!), so I focused on building the minimal set to be able to write useful programs, but really not much more. The native API makes it trivial to write modules in userland, so it seems like a good option to see what's needed before vetting them into the stdlib.

## The future

As mentioned in a few places in the [wiki documentation][wiki] (that I encourage you to read if you have questions about the language, I think the doc is fairly exhaustive for such an early release), this v0.1 was about building and testing a decent runtime environment.

There are zero benchmarks, zero optimizations, performance is **not** a concern at this point. The same goes for the compiler, arguably the sorryest package in the project. The current compiler is *barely* good enough to run code and test the runtime, which is what is needed right now. There are probably syntactically or semantically valid statements that will not compile, and there are probably syntactically or semantically invalid statements that will compile (and panic at runtime). Please file an issue if you find such cases, but the priority for the short-term next versions (v0.2 and v0.3) is to complete the missing features of the language, live with it and test it and stabilize it before moving on to refactor (rewrite, honestly) the compiler and work on optimizations.

There is a wiki article for [the roadmap][roadmap] of the project.

## 'til v0.2

I had a blast writing this v0.1 release. Go is truly my language of choice nowadays, and I think it played a big part in what I feel is a simple and clean design of the runtime and the native API.

There are a few things I haven't talked about, this is merely an overview of the language, so I guess there will be other blog posts on agora in the future. Until then, hopefully you'll feel compelled to give it a try!

[simdiff]: https://github.com/mna/agora/wiki/Similarities-and-differences-with-Go
[agora]: https://github.com/mna/agora
[start]: https://github.com/mna/agora/wiki/Getting-started
[api]: https://github.com/mna/agora/wiki/Native-Go-API
[cli]: https://github.com/mna/agora/wiki/Command-line-tool
[wiki]: https://github.com/mna/agora/wiki
[roadmap]: https://github.com/mna/agora/wiki/Roadmap
[src]: https://github.com/mna/agora/tree/master/testdata/src

