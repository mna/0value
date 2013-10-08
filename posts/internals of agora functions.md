---
Author: Martin Angers
Title: Internals of agora functions
Date
Description: 
Lang: en
---

# Internals of agora functions

A few weeks ago, I [introduced agora][1], a simple and small dynamically-typed, garbage-collected, embedded [programming language built with Go][3]. Today I'm pleased to announce the v0.2 release, which is still a release that focuses on the runtime and the features of the language, *not* on the compiler (that will be v0.4), optimizations (v0.5), nor the stdlib (v0.6). I must insist that the language is still very rough, alpha-grade, and should not be used for anything remotely related to production environments. Things may change, and things *will* change.

With this disclosure out of the way, I must say that the added features make the language much more usable. The complete list of changes can be [found on GitHub][2], but the Big Three new features are probably closures, coroutines and the `for..range` construct.

All three are closely related to how functions are handled in agora. Since top-level code in a module is implicitly part of a top-level function, all executable code in agora is inside a function, this makes for a very uniform implementation. This article will dive into the internals of functions in agora to introduce those 3 new features.

## The Three States of the Function

The function has 3 different categories of state to maintain. There's the static information that the compiler produces about a function - its number of expected arguments, its parent function, its list of instructions, etc. This is the prototype of the function, it is common to all function values created from this function prototype, and is stored in the `agoraFuncDef` structure.

Then there's the function value (`agoraFuncVal`), which implements the `runtime.Val` interface so that it is a valid agora value that can be passed around like any other value, and it stores its *environment* and its *execution state*. This is directly related to how *closures* and *coroutines*, respectively, are supported.

Finally, there's the VM (`agoraFuncVM`), which is created to run a specific function value, and maintains this function's execution state. It holds its local variables, its stack and stack pointer, its program counter, etc.

For example, in this agora module taken from `testdata/src/61-curry.agora`:

```Go
func makeAdder(n) {
	return func(x) {
		return n + x
	}
}

add2 := makeAdder(2)
add10 := makeAdder(10)

return add2(3) + add10(9) + add2(2)
```

The compiler generates a single function prototype for the anonymous function returned by `makeAdder`. However, at runtime, the variables `add2` and `add10` hold two different function values, based on the same function prototype. Then, when the final `return` statement is executed, three different function VMs get created for the three calls to `add2`, `add10`, and another `add2`.

## The Prototype

The `agoraFuncDef` structure is simple enough, it currently looks like this:

```Go
type agoraFuncDef struct {
	ctx *Ctx
	mod *agoraModule
	// Internal fields filled by the compiler
	name    string
	stackSz int64
	expArgs int64
	kTable  []Val
	lTable  []string
	code    []bytecode.Instr
}
```

So it holds a reference to its execution context (`ctx`), to its parent module (`mod`), and the next fields hold information filled by the compiler. The `name`, `stackSz` and `expArgs` are straightforward enough (the stack size is an approximation, it doesn't take into account loops, so the stack may need to expand at runtime).

The `kTable` holds all symbolic constants encountered by the compiler. Those are literal values, but also identifiers such as variables and function names (which are variables too). The `lTable` holds only the local variable names, so it is a subset of the `kTable` (in fact, in the bytecode it is even encoded as a list of indices into the K table). Finally, the `code` holds all instructions that make up this function.

## The Value

The `agoraFuncVal` is defined like this:

```Go
type agoraFuncVal struct {
	*funcVal
	proto     *agoraFuncDef
	env       *env
	coroState *agoraFuncVM
}

type env struct {
	upvals map[string]Val
	parent *env
}
```

The embedded `funcVal` pointer is a common implementation of the `runtime.Val` for functions, and it is the same for native Go functions exposed to agora. The `proto` field is a reference to this function's prototype. The `env` field is what makes closures possible: it is a linked list of upvalues. The `map[string]Val` is the same map that is used in the VM to store local variables, and in fact this environment structure points to the map of locals of the VM that created the function value, all the way to the top-level module.

And that's the downside of the current closure implementation: it is dumb (or lazy, but mostly dumb). It closes over *all* the environment of the function, instead of closing over just the values that are, you know, used by the function. There's already an open issue about this, the idea is that the current compiler is messy and just an excuse to make the code run, so I will make a decent implementation of closures when I rewrite the compiler and make him contribute some information as to what variables are required, cause he knows, believe me.

Back to the `agoraFuncVal`, the last field is the `coroState`, which as its name reveals stores the execution state of the function so that it can re-enter at the right place for coroutines. The `agoraFuncVM` simply stores itself in this field when a `yield` keyword is encountered, before returning to the calling function. When the function is called again, it checks for the presence of coroutine state, and if it is non-null, it reuses this same `agoraFuncVM` and resumes execution where it left off. When a `return` statement is executed, it clears the `coroState` off of the value, so that the next call starts anew with a new VM. The `agoraFuncVal.Call()` implementation looks like this:

```Go
func (a *agoraFuncVal) Call(this Val, args ...Val) Val {
	// If the function value already has a vm, reuse it, this is a coroutine
	vm := a.coroState
	if vm == nil {
		vm = newFuncVM(a)
	}
	// Set the `this` each time, the same value may have been assigned to an object and called
	vm.this = this
	a.ctx.pushFn(a, vm)
	defer a.ctx.popFn()
	return vm.run(args...)
}
```

## The VM

The final piece of the puzzle is the `agoraFuncVM`:

```Go
type agoraFuncVM struct {
	// Func info
	val   *agoraFuncVal
	proto *agoraFuncDef
	debug bool
	
	// Stacks and counters
	pc     int   // program counter
	stack  []Val // function stack
	sp     int
	rstack []gocoro.Caller // range native coroutine stack
	rsp    int
	
	// Variables
	vars map[string]Val
	this Val
	args Val
}
```

Besides the references to the function value and prototype, there's the expected program counter, stack and stack pointer, and jumping over the range stack, there's the local variables map and the predefined `this` and `args` variables.

The range stack is special and is used to implement the last of the big three features, the `for range` construct. Agora's `for range` is quite versatile and can be used to range over numbers, strings, objects and coroutines - so that custom iterators can be built.

[1]: http://www.0value.com/introducing-agora--a-dynamic--embeddable-programming-language-built-with-Go
[2]: https://github.com/PuerkitoBio/agora/issues?milestone=2&page=1&state=closed
[3]: https://github.com/PuerkitoBio/agora
