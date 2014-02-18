# Throttled: Guardian Of The Web Server

I just put the finishing touches for the release of [throttled][], a Go package that implements various strategies to control access to HTTP handlers. Out-of-the-box, it supports rate-limiting of requests, constant interval flow of requests and memory usage thresholds to grant or deny access, but it also provides mechanisms to extend its functionality.

## How It Works

At the heart of the package is the `Throttler` structure and the `Limiter` interface. The throttler offers a single method, `Throttle(h http.Handler) http.Handler`, that wraps the given handler `h` and returns a new handler that throttles access to `h`. How it does the throttling is up to the `Limiter`.

The `Limiter` interface is defined as follows:

```
type Limiter interface {
    Start()
        Limit(http.ResponseWriter, *http.Request) (<-chan bool, error)
}
```

The `Start` method tells the limiter to get to work, initializing any internal state as needed, and `Limit` does the actual work of applying the limiter's strategy for this specific request. It returns a receive-only channel of boolean that will indicate to the `Throttler` if it should allow or deny the request (if the channel returns true or false). It may also return an error, in which case the throttler will call the function assigned to the package-level `Error` variable.

When a request is granted access, the wrapped handler is called. But what happens when the access is denied? Well, there is a package-level `DefaultDeniedHandler` that can be used. By default it returns a status 429 with a generic message, but it is a humble `http.Handler` and can be set to do whatever needs to be done.

But since some throttlers may require specific handling of those requests, there is also a `DeniedHandler` field on the `Throttler` struct. If it is nil, the package-level `DefaultDeniedHandler` is used, otherwise the throttler-specific handler is called.

## What It Does

The package usage revolves around three main functions: `Interval`, `RateLimit` and `MemStats`. There's also `Custom`, but this is a hook for extensibility, it doesn't do anything special on its own.

### Interval

`Interval(delay Delayer, bursts int, vary *VaryBy, maxKeys int) *Throttler`

As the name implies, this function allows requests to proceed at a given constant interval. The `Delayer` interface specifies this interval:

```
type Delayer interface {
    Delay() time.Duration
}
```

With this interface in place, it is possible to set intervals in expressive ways, using the `PerSec`, `PerMin`, `PerHour` or `PerDay` types, or the `D` type, which is simply a `time.Duration` that fulfills the `Delayer` interface by returning its own value.

An example would surely help:

```
// Allow 10 requests per second, or one each 100ms
Interval(PerSec(10), 0, nil, 0)
// Allow 30 requests per minute, or one each 2s
Interval(PerMin(30), 0, nil, 0)
// Allow one request each 7 minute
Interval(D(7*time.Minute), 0, nil, 0)
```

What look like function calls are actually conversions of integers - or time.Duration in the last case - to the specific type that fulfills the `Delayer` interface.

Back to the `Interval` function signature, the `bursts` argument sets how many exceeding requests can be queued to proceed when their time comes. `vary` tells the throttler to apply the interval separately based on some criteria on the request. The `VaryBy` struct is defined like this:

```
type VaryBy struct {
    // Vary by the RemoteAddr as specified by the net/http.Request field.
    RemoteAddr bool

    // Vary by the HTTP Method as specified by the net/http.Request field.
    Method bool

    // Vary by the URL's Path as specified by the Path field of the net/http.Request
    // URL field.
    Path bool

    // Vary by this list of header names, read from the net/http.Request Header field.
    Headers []string

    // Vary by this list of parameters, read from the net/http.Request FormValue method.
    Params []string

    // Vary by this list of cookie names, read from the net/http.Request Cookie method.
    Cookies []string

    // Use this separator string to concatenate the various criteria of the VaryBy struct.
    // Defaults to a newline character if empty (\n).
    Separator string
}
```

Finally, the `maxKeys` argument sets the maximum number of vary-by keys to keep in memory, using an LRU cache (because internally each vary-by key gets its own channel and goroutine to control the flow).

[Using `siege`][siege] and the example applications in the /examples/ subdirectory of the repository, let's see the interval throttler in action:

```
# Run the example app (in examples/interval-vary/)
$ ./interval-vary -delay 100ms -bursts 100 -output ok
# In another terminal window, start siege with the URL file to hit various URLs
$ siege -b -f siege-urls
# Output from the example app:
2014/02/18 17:23:47 /a: ok: 1.050021944s
2014/02/18 17:23:47 /b: ok: 1.050646811s
2014/02/18 17:23:47 /c: ok: 1.051085882s
2014/02/18 17:23:47 /a: ok: 1.15102831s
2014/02/18 17:23:47 /b: ok: 1.151841098s
2014/02/18 17:23:47 /c: ok: 1.152307554s
2014/02/18 17:23:47 /a: ok: 1.252140208s
2014/02/18 17:23:47 /b: ok: 1.253117856s
2014/02/18 17:23:47 /c: ok: 1.253621192s
```

Each path receives requests at 100ms intervals.

### RateLimit

`RateLimit(quota Quota, vary *VaryBy, store Store) *Throttler`

This function creates a throttler that limits the number of requests allowed in a time window, which is a very common need in public RESTful APIs.

The Quota interface defines a single method:

```
type Quota interface {
    Quota() (int, time.Duration)
}
```

It returns the number of requests and the duration of the time window. Conveniently, the `PerXxx` types that implement the `Delayer` interface also implement the `Quota` interface, and there is a `Q` type to define custom quotas:

```
// Allow 10 requests per second
RateLimit(PerSec(10), &VaryBy{RemoteAddr: true}, store.NewMemStore(0))
    // Allow 30 requests per minute
RateLimit(PerMin(30), &VaryBy{RemoteAddr: true}, store.NewMemStore(0))
    // Allow 15 requests each 30 minute
RateLimit(Q{15, 30*time.Minute}, &VaryBy{RemoteAddr: true}, store.NewMemStore(0))
    ```

    The `vary` argument plays the same role as in `Interval`. The `store` is used to save the rate-limiting state. The `Store` interface is:

    ```
    type Store interface {
        Incr(key string, window time.Duration) (cnt int, secs int, e error)
            Reset(key string, window time.Duration) error
    }
```

The `throttled/store` package offers an in-memory store, and a Redis-based store.

The rate-limiter automatically adds the `X-RateLimit-Limit`, `X-RateLimit-Remaining` and `X-RateLimit-Reset` headers on the response. The Limit indicates the number of requests allowed in the window, Remaining is the number of requests remaining in the current window, and Reset indicates the number of seconds remaining until the end of the current window.

When the limit is busted, the header `Retry-After` is also added to the response, with the same value as the Reset header.

Using `curl` and the example app, let's see it in action:

### MemStats

`MemStats(thresholds *runtime.MemStats, refreshRate time.Duration) *Throttler`

This function accepts a struct of memory stats with the desired thresholds, and a refresh rate indicating when to refresh the current memory stats values (0 means read on each request). Any integer field in the MemStats struct can be used as a threshold value, and zero-valued fields are ignored.

The thresholds must be in absolute value (i.e. Allocs = 10 000 means 10 000 bytes, not 10 000 bytes more than some previous reading), but there is the helper function `MemThresholds(offsets *runtime.MemStats) *runtime.MemStats` that  translates offsets to absolute values.

Using [`boom`][boom] and the memstats example app (that fully loads in memory a 64Kb file on each request), we can test its behaviour:

//TODO

Obviously, some memory stats just go up and never down, so once the threshold is reached, no other request will ever be allowed. But since the DroppedHandler is just a Handler, it is possible to build a routing strategy such that once the threshold is reached, requests are sent to a throttled handler that allows requests to go through at a slow interval, for example, or a handler that restarts the process, why not!

### Custom

`Custom(l Limiter) *Throttler`

A quick word on the Custom function, it accepts any `Limiter` as argument and returns a throttler that uses this limiter. There is an example of a custom limiter in the /examples/custom/ subdirectory.

## Miscellaneous Closing Thoughts

As alluded to in the MemStats section, the package manipulates plain old HTTP handlers, so combining them in useful and creative ways is definitely possible. The DroppedHandler is just that, a Handler, it doesn't have to return a 429 or 503 error, it can do whatever is needed to do, like call a differently throttled (or non-throttled) handler.

The examples are also useful for testing with the data race detector in real-world (or not-so-real-world) usage. Just `go build -race` the app, and see how it goes.

Inspired by [Go's pre-commit hook example][gogit] in its misc/git/ folder, I usually add a pre-commit hook in my Go repositories that run both [`golint`][lint] and [`go vet`][vet] on my packages. Both programs have proved very helpful in finding different categories of bugs (vet) and consistency/style errors (lint). You can find my hook in the /misc/ subdirectory of the repository. Note that the linter output is purely informational, it doesn't return an exit code != 0 and thus does not prevent the commit from happening if it finds some problems.

That's it for now, hope you like it! [Fork, star, test and PR at will][throttled]!

[throttled]: https://github.com/PuerkitoBio/throttled
[siege]: http://www.joedog.org/siege-home/
[gogit]: http://golang.org/misc/git/pre-commit
[lint]: https://github.com/golang/lint
[vet]: http://godoc.org/code.google.com/p/go.tools/cmd/vet
[boom]: https://github.com/rakyll/boom']''''
