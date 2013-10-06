---
Author: Martin Angers
Title: Agora v0.2: Closures, Coroutines and for..range
Date: 2013-10-07
Description: 
Lang: en
---
# Agora v0.2: Closures, Coroutines and for..range

A few weeks ago, I [introduced agora][1], a new dynamically-typed, garbage-collected, embedded programming language built with Go. Today I'm pleased to announce the v0.2 release, which is still a release that focuses on the runtime and the features of the language, *not* on the compiler, optimizations, nor the stdlib. I must insist that the language is still very rough, alpha-grade, and should not be used for anything remotely related to production environments.

With this disclosure out of the way, I must say that the added features make the language much more usable. The complete list of changes can be [found on GitHub][2], but the Big Three new features are probably closures, coroutines and the `for..range` construct.

All three are closely related to how functions are handled in agora. Since top-level code in a module is implicitly part of a top-level function, all executable code in agora is inside a function, this makes for a very uniform implementation. This article will dive into the internals of functions in agora to introduce those 3 new features.

[1]: http://www.0value.com/introducing-agora--a-dynamic--embeddable-programming-language-built-with-Go
[2]: https://github.com/PuerkitoBio/agora/issues?milestone=2&page=1&state=closed

