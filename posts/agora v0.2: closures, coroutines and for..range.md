---
Author: Martin Angers
Title: Agora v0.2: Closures, Coroutines and For-Range
Date: 2013-10-08
Description: A few weeks ago, I introduced agora, a small and simple programming language built with Go. It's a dynamically typed, dynamically loaded, garbage collected and embeddable language with a small footprint and a familiar Go-like syntax. Oh, and it is open source and available on GitHub. Well, today I'm pleased to announce the release v0.2!
Lang: en
---

# Agora v0.2: Closures, Coroutines and For-Range

A few weeks ago, I [introduced agora][1], a small and simple programming language built with Go. It's a dynamically typed, dynamically loaded, garbage collected and embeddable language with a small footprint and a familiar Go-like syntax. Oh, and it is open source and [available on GitHub][2].

Well, today I'm pleased to announce the release v0.2! The complete changelog can be found in the [closed issues list for the v0.2 milestone][3], but along with many bug fixes, the release introduces three new language features: closures, coroutines and a versatile `for..range` construct.

Before diving head first in the presentation of these features, let me reiterate the obvious disclosure: this is another very **alpha-grade** release that focuses on the language itself, **not** on the compiler, performance / optimizations, nor the stdlib - which is still very minimal. Things may still change, and things *will* change. Don't mention *agora* and *production* in the same sentence. Kittens and all that jazz.

## Closures

With v0.1 you couldn't use such a module:

```
fmt := import("fmt")
func fn(str) {
    fmt.Println(str)
}
return fn
```

Because there was no closure support, the lexical environment of the function `fn` was not kept along with the function value, so when the caller module would import this module and call `fn`, it would get an error because the `fmt` variable would not be defined. Ugly workarounds were needed. This is a thing of the past.

With v0.2, the environment is stored along with the function value, making patterns like currying possible:

```
func makeAdder(n) {
	return func(x) {
		return n + x
	}
}

add2 := makeAdder(2)
add10 := makeAdder(10)

return add2(3) + add10(9) + add2(2)
```

The `n` variable is closed over and stored along with the returned function value in `makeAdder`, so that `add2` and `add10` have different `n`s.

However, the current implementation of closures is kind of dumb and inefficient, as it closes over the whole environment of the function, instead of just the variables required to run the function. This is something that will be addressed when the compiler gets rewritten (probably v0.4). It will be its responsibility to give more information to the runtime regarding the variables required by a given function (there's already an open issue to address this).

## Coroutines

> "Subroutines are special cases of more general program components, called coroutines." - Donald Knuth

Building on the citation of Mr Knuth, subroutines in agora are really just a special case of coroutine. One way to look at it is that all functions are coroutines, although some simply never yield. A coroutine is a function that calls the new agora keyword `yield` to return a value to the caller. The difference with `return` is that `yield` stores the state of the execution (current instruction, local variables, stack, etc.) and makes it possible to resume execution where it left off when `yield` was called.

For now, yield can return at most one value (which is similar to the current limit of a single return value). The next version (v0.3) will address this limitation so that multiple return values are possible.

To resume a coroutine, it just has to be called again. Like any normal function. If the first call yielded a value, the second call resumes execution after the yield. Once a `return` statement is reached, the coroutine is terminated, and a subsequent call to the same function will restart execution from the start.

```
func fn(n) {
	i := yield n + 1
	i = (yield i * 2) + 1
	return i * 3
}

fmt := import("fmt")
fmt.Println(fn(1))
fmt.Println(fn(2))
fmt.Println(fn(3))
fmt.Println(fn(4))
// Output: 2, 4, 12, 5
```

As seen in the example above, it is possible to send back new arguments (only one for now, same as the "one return value" limitation) when a function is resumed. But how about if you need to know whether the function will resume or start anew? Or if you want to force it to restart?

Enter two new built-in functions: `status(fn)` and `reset(fn)`. Both receive a single argument that must be a function. The `status` returns either an empty string if the function is not a coroutine or has not yet been called, or "suspended" if the coroutine has yielded and is waiting to resume, or "running" if the coroutine is currently running.

`reset`, on the other hand, clears the execution state so that the status is back to an empty string. The next call of the function will be like an initial call.

You can run and check the module "testdata/src/68-cons-prod.agora" for a more complex coroutine example implementing the consumer-producer relationship.

## For..range

The new `for..range` construct is similar to Go's but is very versatile, allowing the `range` keyword to act on strings, numbers, objects as well as coroutines, so that custom iterators can be implemented.

The range on numbers can take 1, 2 or 3 arguments (see "testdata/src/74-range-number.agora" for more examples) and as such can be seen as syntactic sugar for the usual three-part for loop:

```
// Output: 0, 1, 2, 3, 4
// Single arg is the non-inclusive top limit
for i := range 5 {
	fmt.Println(i)
}

// Output: 2, 3, 4, 5, 6
// First arg is the start index, second is the non-inclusive top limit
for i = range 2, 7 {
	fmt.Println(i)
}

// Output: -2, 3, 8
// Same as two-args form, and third arg is the increment
for i = range -2, 13, 5 {
	fmt.Println(i)
}
```

The range on strings can also take 1, 2 or 3 arguments (see "testdata/src/76-range-string.agora" for more examples):

```
// Output: t, e, s, t
// Single arg loops over each byte
for s := range "test" {
	fmt.Println(s)
}

// Output: this, is, a, word
// First arg is the source string, second arg is the separator, loops over
// each segments. If second arg is falsy, same as single arg form (loops over each byte).
for s = range "this is a word", " " {
	fmt.Println(s)
}

// Output this, is
// Same as two-args form, third arg is the maximum number of segments.
for s = range "this is a word", " ", 2 {
	fmt.Println(s)
}
```

The range on objects takes a single argument (see "testdata/src/78-range-object.agora" for more examples):

```
// Output: a, 0
// The loop variable is an object with two keys, `k` (key) and `v` (value).
// If the object has a "__keys" meta-method, it is called, otherwise it loops
// on all keys.
for kv = range {a: 0} {
	fmt.Println(kv.k, kv.v)
}
```

The last range is on a function, more specifically a coroutine, since a function that never yields will not enter the loop (the value returned by a `return` statement is not part of the iteration). See "testdata/src/80-range-func.agora" for examples.

```
// Define the (silly) coroutine
func rangeFn(n) {
	for i := 0; i < n; i++ {
		yield i
	}
}
// Use it in a range loop (additional arguments - such 
// as 4 in this case - are passed to the function)
for i := range rangeFn, 4 {
	fmt.Println(i)
}
```

The implementation of the range over a function is syntactic sugar for:

```
reset(fn)
for v := fn(); status(fn) == "suspended"; v = fn() {
	// Use v in loop body
}
```

More information on all three new features - and agora in general - can be found in [the wiki][4], and more specifically in the [language reference][5] article.

## What's next?

If everything goes as smoothly as it went for v0.2, v0.3 should be the last version to focus solely on the language features. Expected to land in the next version is the array literal notation, so that objects can be created using `ob := [12, true, "value"]`, and be equivalent to:

```
ob := {}
ob[0] = 12
ob[1] = true
ob[2] = "value"
```

This would still be an `object` type, but it would be internally optimized when all (or most) keys are dense integers.

Another big thing will be to support multiple return values (and yield values). Also expect the introduction of the `switch` statement and something like Go's anonymous struct embedding is among the things I ponder upon. The [tentative roadmap][6] is available on GitHub.

Until then, have fun with v0.2!

[1]: http://0value.com/introducing-agora--a-dynamic--embeddable-programming-language-built-with-Go
[2]: https://github.com/PuerkitoBio/agora
[3]: https://github.com/PuerkitoBio/agora/issues?milestone=2&state=closed
[4]: https://github.com/PuerkitoBio/agora/wiki
[5]: https://github.com/PuerkitoBio/agora/wiki/Language-reference
[6]: https://github.com/PuerkitoBio/agora/wiki/Roadmap
