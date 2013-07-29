---
Author: Martin Angers
Title: Implementing Lua coroutines in Go
Date: 2013-07-30
Description: I have a funny-weird relationship with the Lua language, I have never written anything remotely useful with it and am unfamiliar with its syntax, but I know its internals quite well, thanks to my obsession with virtual machines and my unfinished attempt at building the Lua VM in Go. Anyway, Lua has this nice feature called coroutines, and I'll let wikipedia introduce it to those unfamiliar with the concept...
Lang: en
---

# Implementing Lua Coroutines in Go

I have a funny-weird relationship with the Lua language, I have never written anything remotely useful with it and am unfamiliar with its syntax, but I know its internals quite well, thanks to my obsession with virtual machines and my unfinished attempt at [building the Lua VM in Go][lune]. Anyway, Lua has this nice feature called [coroutines][coro], and I'll let [wikipedia introduce it][wiki] to those unfamiliar with the concept:

> Coroutines are computer program components that generalize subroutines to allow multiple entry points for suspending and resuming execution at certain locations.

Now, I can already hear the gophers scream "CHANNELS"! Yes, spoiler alert, channels will be summoned, but the goal is to build a higher-level abstraction that mimics as close as possible Lua's `coroutine.*` API and features.

## Please Allow Me To Introduce Myself

Here's a quick overview of Lua's features that I'll try to replicate using Go's primitives. For a more exhaustive explanation, take a look at [Lua's chapter on coroutines][coro].

*    **coroutine.create(fn)** : This is the call that creates a coroutine from an existing function (the function is the code that will run when the coroutine executes).

*    **coroutine.status(co)** : This function returns the current status of the specified coroutine (can be suspended, running or dead).

*    **coroutine.yield( )** : This function suspends the current coroutine, returning any arguments passed to yield to the calling function (as return values for the matching `coroutine.resume()` call).

*    **coroutine.resume( )** : This function is the *yin* to `coroutine.yield`'s *yang*. Or vice-versa. This is the call that actually starts the coroutine the first time, and re-starts it after a call to `coroutine.yield`. Like its yield counterpart, any arguments passed to resume are returned inside the coroutine by the corresponding `coroutine.yield()` call.

*    **coroutine.wrap(fn)** : This function creates an iterator function, so instead of returning a coroutine, it returns a function that, when called, resumes the coroutine created from the `fn` argument and returns its yielded value(s), allowing for its use in *for loops* as iterator.

An important point to remember is that Lua coroutines are **not** about parallel execution - only one block of code is executing at any given time. It's about *collaborative* execution of distinct blocks of code.

## Go Your Own Way

Let's think for a second about what is needed to implement a coroutine. Basically, when `resume()` is called, the caller blocks on this call until a matching `yield()` (or `return`, which is semantically equivalent to a final `yield()` before the coroutine dies) is called from within the coroutine. Similarly, a call to `yield()` from within the coroutine blocks its execution at this point until a call to `resume()` is made by the caller. Additionally, values can be exchanged at these meeting points.

The Go Way to do this is with an [unbuffered channel][chan]. It allows sending and receiving values, and when unbuffered, it blocks on receive until a value is available on the channel (or until the channel is closed). So let's build a Go implementation that yields an integer. The data structure could look like this:

``` go
type *Coroutine struct {
	fn      func () int  // The function to run as a coro
	yld     chan int     // The yield synchronisation channel
	status  int        	 // The current status of the coro
}
```

That's a start. We know there are three possible statuses, so it would be nice to make this a little more expressive.

``` go
// The status of the coroutine is an "enum" (there are no enums per se in Go)
type Status int
const (
	// Possible values of the status of the coroutine
	StDead      Status = iota - 1
	StSuspended        // Zero value is StSuspended when a coro is created
	StRunning
)

var (
	// Lookup map to pretty-print the status
	statusNms = map[Status]string{
		StDead:      "Dead",
		StSuspended: "Suspended",
		StRunning:   "Running",
	}
)

// Bonus: fmt.Stringer interface implementation for human-readable formatting
func (s Status) String() string {
	// Will return empty string for unknown statuses
	return statusNms[s]
}
```

Now we can change the type of the `status int` field to `status Status`.

## Before They Make Me Run

How could we make this Go coroutine run? A skeleton of the `Resume()` method could look like this, with notes about what it should do in the comments:

``` go
// Resumes (or starts) execution of the coro.
func (c *Coroutine) Resume() (int, error) {
	switch c.status {
	case StSuspended:
		// For the initial start, the yld channel should be created, and the 
		// coroutine function called. On subsequent calls, it should "unblock"
		// the coroutine function until it yields another value.
	case StDead:
		// Resume on a Dead coro returns an error ("coro terminated" or something).
	default:
		// Any other state is invalid to call Resume on.
	}

	// Wait for a yield
	i := <-c.yld
	return i, nil
}
```

So we see that we should be able to distinguish between the initial start and subsequent calls. We should also probably define some common errors, so that the callers can understand what is happening. Now here's a skeleton of the `Yield()` method, commented:

``` go
// Yields execution to the caller, sending values along the way.
func (c *Coroutine) Yield(i int) {
	// Yield is called from within the coroutine function.
	// It sets the status to Suspended.
	c.status = StSuspended
	// Sends the value
	c.yld <- i
	// Waits for resume: how?
}
```

To block until it must resume, the same `c.yld` channel could possibly be used, but I think it's cleaner to have separate channels that are intended to always work in the same direction: `c.yld` to send to the caller, `c.rsm` to send to the coroutine.

Another thing to consider is that unlike Lua, [whose garbage collector can track zombie coroutines][luagc] and eventually wipe them off, Go will [leak goroutines that are stuck forever][goleak]. It would be nice to provide a way to explicitly kill a Go coroutine (which as we'll see in a second is built using a goroutine) when it is no longer needed.

Here's a rewrite of the basic implementation, taking these points into account:

``` go
var (
	// Common errors returned by the coroutine
	ErrEndOfCoro    = errors.New("coroutine terminated")
	ErrInvalidState = errors.New("coroutine is in invalid state")
	ErrCancel       = errors.New("coroutine canceled")
)

type Coroutine struct {
	fn      func() int    // The function to run as a coro
	rsm     chan struct{} // The resume synchronisation channel
	yld     chan int      // The yield synchronisation channel
	status  Status        // The current status of the coro
	started bool          // Whether or not the coro has started
	err     error         // The last error
}

func New(fn func() int) *Coroutine {
	return &Coroutine{
		fn: fn,
	}
}

// Resumes (or starts) execution of the coro.
func (c *Coroutine) Resume() (int, error) {
	switch c.status {
	case StSuspended:
		if !c.started {
			// Never started, so create the channels and run the coro.
			c.started = true
			c.rsm = make(chan struct{})
			c.yld = make(chan int)
			c.run() // run sets the status as Running
		} else {
			// Restart, so simply set status back to Running and unblock the waiting
			// goroutine by sending on the resume channel.
			c.status = StRunning
			c.rsm <- struct{}{}
		}
	case StDead:
		// Resume on a Dead coro returns an error (either EndOfCoro, or the previous error
		// that caused the coro to die).
		if c.err == nil {
			c.err = ErrEndOfCoro
		}
		return 0, c.err
	default:
		// Any other state is invalid to call Resume on.
		return 0, ErrInvalidState
	}

	// Wait for a yield
	i := <-c.yld
	return i, c.err
}

// Cancels execution of a coro. Can only be called on suspended coros,
// returns an error otherwise.
func (c *Coroutine) Cancel() error {
	if c.status != StSuspended {
		return ErrInvalidState
	}
	if c.started {
		// Signal the end by closing the resume channel
		close(c.rsm)
		// Wait for confirmation
		<-c.yld
	} else {
		// Coro was never started, so simply set its status to Dead.
		c.status = StDead
	}
	return nil
}

// Yields execution to the caller, sending values along the way.
func (c *Coroutine) Yield(i int) {
	// Yield is called from within the func. It sets the status to Suspended,
	// unless the coro is dying (Yield from a call to Cancel).
	isDead := c.status == StDead
	if !isDead {
		c.status = StSuspended
	}
	// Send the value
	c.yld <- i
	if !isDead {
		// Wait for resume
		if _, ok := <-c.rsm; !ok {
			// c.rsm is closed, cancel by panicking, will be caught in c.run's defer statement.
			panic(ErrCancel)
		}
	}
}

// Executes the coroutine function and catches any error, and returns the final
// return value.
func (c *Coroutine) run() {
	// set status as running, now that the coro goroutine is running.
	c.status = StRunning
	// Start the goroutine that runs the actual coro function.
	go func() {
		var i int
		defer func() {
			// Catches any panic inside the coroutine's function, or the panic from
			// a call to Cancel().
			if err := recover(); err != nil {
				if e, ok := err.(error); !ok {
					// Turn the panic into an error type if it isn't
					c.err = fmt.Errorf("%s", err)
				} else {
					c.err = e
				}
			}
			// Return the last value and die
			c.status = StDead
			c.Yield(i)
		}()

		// Trap the return value of the coroutine's function, and in the defer,
		// yield it like any normally Yielded value.
		i = c.fn(c)
	}()
}
```

There's still a major problem with this implementation. How does the coroutine function call `Yield()`? In Lua, `coroutine.yield()` has hooks into the C runtime and knows what is the current coroutine and yields it. To implement this in Go as a userland library, a different approach is required. I thought about making the coroutine function accept a `*Coroutine` type as first argument, but then it means that it can call `Yield()` just fine, but also `Resume()` and `Cancel()`, which are meant to be called from the coroutine's caller. Turns out there's a simple fix for this.

## Here We Stand, Worlds Apart

Even though the methods `Yield()`, `Resume()` and `Cancel()` all manipulate our `*Coroutine` structure, they're really meant to be used in distinct contexts. Using interfaces and a private, unexported type, we can expose just the right stuff in each context. Here are the relevant parts of the same implementation, rearranged with this segregation in mind:

``` go
// The Yielder interface is to be used only from inside a coroutine's
// function.
type Yielder interface {
	// Yield sends the specified value to the caller of the coro.
	// This is the equivalent of `coroutine.yield()` in Lua.
	Yield(int)
}

// The Caller interface is to be used anywhere where a coro needs to be
// called.
type Caller interface {
	// Resume (re)starts the coroutine and returns the value yielded by this run,
	// or an error. This is the equivalent of `coroutine.resume()` in Lua.
	Resume() (int, error)
	// Status returns the current status of the coro. This is the equivalent of
	// `coroutine.status()` in Lua.
	Status() Status
	// Cancel kills the coroutine. Because Go leaks dangling goroutines (and a goroutine
	// is used internally to implement the coro), it must be explicitly killed if it
	// is not to be used again, unlike in Lua where coroutines are eventually garbage-collected.
	Cancel() error
}

// The signature of a coro-ready function, in Lua this is built into
// the language via the global coroutine variable, here the Yielder is passed
// as a parameter.
type Fn func(Yielder) int

// The coroutine struct is now private, the outside world only sees the contextually
// relevant portions of it, via the Yielder or Caller interfaces.
type coroutine struct {
	fn      Fn            // The function to run as a coro
	rsm     chan struct{} // The resume synchronisation channel
	yld     chan int      // The yield synchronisation channel
	status  Status        // The current status of the coro
	started bool          // Whether or not the coro has started
	err     error         // The last error
}

// Internal constructor for a coroutine, used to create all coroutine structs.
func newCoroutine(fn Fn) *coroutine {
	// Use as little initial memory as possible, zero value other fields
	return &coroutine{
		fn: fn,
	}
}

// Public constructor of a coroutine Caller. The matching Yielder will automatically
// be given to the function once the coro is started. This is equivalent to
// `coroutine.create()` in Lua.
func New(fn Fn) Caller {
	return newCoroutine(fn)
}
```

The rest of the implementation stays the same. You can find this source code on github, in my [gocoro][] repo. This simple integer-yielding implementation is in the [`simple-int` branch][sibr].

## The Call Of Cthulua

From a caller's perspective, here's a very simple (and silly) example of how the *gocoro* implementation is used:

``` go
package main

import (
	"github.com/PuerkitoBio/gocoro"
	"fmt"
)

func corofn(y Yielder) int {
	for i := 1; i <= 10; i++ {
		y.Yield(i)
	}
	// Just for fun...
	return 1000
}

func main() {
	c := gocoro.New(corofn)
	for i, err := c.Resume(); err == nil; i, err = c.Resume() {
		fmt.Println(i)
	}  
}
```

Nice, no? Of course you have to imagine the `corofn` doing something a little more involved, but you get the feeling. Wouldn't it be better, though, to capitalize on Go's `range` keyword when the coroutine is used to loop over the values like this? That's the point of `coroutine.wrap()` in Lua, to return an iterator.

## Here Comes The Range Again

In Go, [the `range` keyword works only on a select few built-in types][range], namely: arrays, slices, maps, strings and (receivable) channels. Maps and strings make no sense in this case. Slices could be tempting, but that defeats the whole purpose of collaborative execution (the coroutine would need to fill the whole slice before iteration can take place). So I guess channels will be relied upon once again!

Building on our current implementation of coroutines, adding an iterator function is surprisingly easy by returning a channel to iterate upon. After, it's simply a matter of having a function automatically resume the coroutine once the value is read from the channel. Once again, an unbuffered channel will be our friend, since it will block on a send until a read is ready.

``` go
// Public constructor of an Iterator coroutine.
// Cannot be canceled, should be drained or goroutine will leak.
// This is equivalent to `coroutine.wrap()` in Lua.
func NewIter(fn Fn) <-chan int {
	c := newCoroutine(fn)
	ch := make(chan int)
	go c.iter(ch)
	return ch
}

// Implements the iterator behaviour by looping over all values returned by the coro
// and sending them over the channel used to iterate.
func (c *coroutine) iter(ch chan int) {
	var (
		i   int
		err error
	)
	for i, err = c.Resume(); err == nil; i, err = c.Resume() {
		ch <- i
	}
	close(ch)
	if err != ErrEndOfCoro {
		// That's the downside of the iterator version, cannot return errors
		// if we want to allow for v := range NewIter(fn), and the panic is
		// inside a goroutine, so it cannot be caught by the caller.
		panic(err)
	}
}
```

I haven't tried it, but maybe it could've been implemented by exposing the existing `c.yld` channel. Still, I like the idea to build this on top of the available coroutine API (exposing `c.yld` would've meant tweaking the internals, since a call to `Resume()` consumes the value of the yield channel). The big downside, as noted in the comments, is the impossibility to cancel the coroutine, nor to handle errors conveniently, unless the `for v := range NewIter(fn)` goal is abandoned in order to return multiple values or a richer, range-unfriendly data structure which yet again defeats the whole purpose.

## Running On Empty

Up until now, this has been a very specific implementation of coroutines in Go. It yields a single integer. Unlike Lua, it doesn't allow passing additional values in calls `Yield()` or `Resume()`. Lua being a dynamically-typed language, any number of any type of arguments can be used in those calls, and the coroutine's function can have any number of arguments and return values too.

Well, Go is statically-typed, but if you want to achieve this kind of "anything goes" behaviour, you have to sprinkle variadic empty interface arguments over those method signatures. And then you use [type assertions][type] just about everywhere. I've implemented such a generic version based on the simple integer one, in the [*generic* branch of the gocoro repo][genbr]. The main differences are:

``` go
// The generic signature of the coroutine function now accepts any
// number of arguments, of any type. It returns any value (can be
// a slice of empty interfaces if multiple values are to be returned,
// since variadic return values do not exist in Go).
type Fn func(Yielder, ...interface{}) interface{}

type coroutine struct {
	fn      Fn               
	rsm     chan interface{} // The resume channel passes any value
	yld     chan interface{} // The yield channel passes any value
	status  Status           
	started bool            
	err     error          
}

// Yield now accepts variadic arguments of any type, returns any type
Yield(...interface{}) interface{}

// Same goes for Resume, obviously
Resume(...interface{}) (interface{}, error)
```

Since unbuffered channels must pass a single value, they pass en empty interface, which would be the slice of empty interface values passed to either `Yield()` or `Resume()` (because [variadic parameters are basically syntactic sugar for a slice of the specified type][vargo]). However, to make handling the case of a single value more convenient, I send the single value into the channel directly in this case instead of sending the slice of empty interfaces. It makes type assertions easier on the caller:

``` go
func (c *coroutine) Resume(args ...interface{}) (interface{}, error) {
	switch c.status {
	case StSuspended:
		if !c.started {
			// -truncated-
		} else {
			// Restart, so simply set status back to Running and unblock the waiting
			// goroutine by sending on the resume channel.
			c.status = StRunning
			if len(args) == 1 {
				// Slightly more convenient: send the one and only arg instead of a
				// slice of empty interfaces.
				c.rsm <- args[0]
			} else {
				c.rsm <- args
			}
		}
		// -truncated-
}
```

Thanks to this, instead of having assertions that look like `val.([]interface{})[0].(int)` you can do `val.(int)`. You can see examples of how to use this version in `generic_test.go` in the generic branch.

Another implementation option would be to use [Go's `reflect` package][reflect]. I've started experimenting with the `MakeFunc()` function, and something could probably be built to make the coroutine pattern more generic while still being strongly-typed, something along the lines of:

``` go
// func New(func(Tin) Tout, yldPtr interface{}, rsmPtr interface{}) Caller =>
// - Creates a Yield function with signature `func(Tout) Tin`, stores it in yldPtr
// - Creates a Resume function with signature `func(Tin) (Tout, error)`, stores it in rsmPtr
// - Creates an in channel `chan Tin`
// - Creates an out channel `chan Tout`
// - Returns a Caller interface that implements `Cancel() error` and `Status() Status`
// - It is the calling code's responsibility to provide the yield function to the coroutine's function
```

But I haven't taken it any further yet (see [the `make-func` branch][mfbr] of the repo for *eventual* progress on this front). Feel free to [send pull requests][pr] or [file an issue][issue] for discussion if you want to share other ways to implement this.

[coro]: http://www.lua.org/pil/9.html
[lune]: https://github.com/PuerkitoBio/lune
[goleak]: https://groups.google.com/forum/#!topic/golang-nuts/uiySuH8_3Y4
[luagc]: http://stackoverflow.com/questions/3642808/abandoning-coroutines
[wiki]: https://en.wikipedia.org/wiki/Coroutine
[chan]: http://golang.org/ref/spec#Channel_types
[gocoro]: https://github.com/PuerkitoBio/gocoro
[range]: http://golang.org/ref/spec#For_statements
[type]: http://golang.org/ref/spec#Type_assertions
[pr]: https://github.com/PuerkitoBio/gocoro/pulls
[sibr]: https://github.com/PuerkitoBio/gocoro/tree/simple-int
[genbr]: https://github.com/PuerkitoBio/gocoro/tree/generic
[vargo]: http://golang.org/ref/spec#Passing_arguments_to_..._parameters
[mfbr]: https://github.com/PuerkitoBio/gocoro/tree/make-func
[issue]: https://github.com/PuerkitoBio/gocoro/issues
[reflect]: http://golang.org/pkg/reflect/

