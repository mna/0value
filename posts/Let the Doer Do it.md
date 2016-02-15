---
Author: Martin Angers
Title: Let the Doer Do it
Date: 2016-02-16
Description: There are lots of Go packages out there that make HTTP requests, maybe because they wrap a RESTful API or they do web crawling, etc. Regardless of the reason, at some point they use an *http.Client to make those requests. This article is a recommendation on how I believe this client should be managed.
Lang: en
---

# Let the Doer Do it

<small>(a humble recommendation for Go packages that make HTTP requests)</small>

There are lots of Go packages out there that make HTTP requests, maybe because they wrap a RESTful API or they do web crawling, etc. Regardless of the reason, at some point they use an `*http.Client` to make those requests. This article is a recommendation on how I believe this client should be managed in the context of reusable packages. But let's start by looking at various common ways it is used, and why this isn't optimal.

## Directly using http.DefaultClient

Go's `net/http` package provides a `DefaultClient` variable that is a `*http.Client`. The package-level function helpers `http.Get`, `http.Post`, etc. use this default value. By default, this value is a zero-value `&http.Client{}` struct, which means [it has no timeout set][godefclient] (which is not *totally* exact, the zero-valued client uses the `http.DefaultTransport` which has a connection timeout, but it doesn't have a timeout for slow responses).

This default client is just a value, and may be changed and configured as desired. Some packages may be tempted to use this value and be done with it. HTTP client problem solved. Well, that's not such a great idea, because:

* As mentioned, by default, this value has no response timeout;
* There is only one such default client, so all packages that use it are necessarily configured the same way;
* The user application cannot easily mock the calls to this package to test the response- and error-handling logic - if it uses the default HTTP client, it *will* make HTTP requests (one could mock at the [http.RoundTripper level][rt] if really needed, but I believe there is a better way).

A reusable package should not hijack the default Client like this and behave as if it was the only one doing HTTP requests in an application. The `DefaultClient` makes for a fine **default value** if the caller doesn't care and doesn't provide anything better, but the package should support other options.

## Creating its own `*http.Client`

An alternative approach is for the package to create its own `*http.Client` so it doesn't rely on the shared `DefaultClient` value (note that there is [nothing wrong in sharing an HTTP client in a concurrent way][clientthreadsafe] - that is not the point here, the "sharing" issue in this context is that the configuration of the client is shared).

This is marginally better, but unless it provides a bunch of options to set client-level and transport-level timeouts and configuration, it means that the package decides for the caller how it should behave, when it is the caller that knows best for its specific use-case what timeout values make sense.

And if the package provides all the options to configure the client, well here again, I believe there is a better way, and one that drastically simplifies the API of the package.

## Accepting an `*http.Client` as a parameter

Now this looks like a great solution. Let the caller provide the `*http.Client` value that the package will use to make requests. And why not fallback on the `http.DefaultClient` if `nil` is provided. That's it, right? That's the *right way*?

Well... It is significantly better than the previous alternatives. The caller gets to fully configure the client as it sees fit, and various packages can use different clients, each with its own specific configuration. There are still a couple of issues with this approach:

* The application still can't easily mock the network calls;
* You can't *compose* behaviour for the client.

Wait, where did that last one come from?

You know how the `io.Reader` and `io.Writer` interfaces are such cool flexible abstractions? Like, you can [take any `io.Reader` and make it an `io.LimitedReader`][limitedreader]? Or the `http.Handler` interface for web servers, how you can do crazy things with middleware, combining them in various ways as presented by [Tomás Senart at Gophercon 2015][tomas]?

The interface enables that composition and separation of concerns. The same can be done for the HTTP client. What for? Maybe to add logging, or to sign the requests going through this client, etc. And of course, it also means that the client, being an interface, can easily be mocked to return pre-determined values to test the handling of responses and errors by the caller application without having to do the network calls.

I mentioned earlier that, if there is no other way, the `http.RoundTripper` interface could be used to mock requests. It is at a lower level than the HTTP client - at the "transport" level, and the Go documentation mentions this about it:

> RoundTrip should not modify the request, except for consuming and closing the Body, including on errors.

So although it could work for mocking responses, this is clearly not the level where we want to compose HTTP clients, since we want to have the possibility to modify the request (e.g. for signing a request before executing it).

Enter the Doer...

## Accept a `Doer` as a parameter

The Doer is a single-method interface, as is often the case in Go:

```
type Doer interface {
    Do(*http.Request) (*http.Response, error)
}
```

It does not really exist - it is not defined anywhere in the stdlib - but it is trivial to summon it from thin air in a package. Just do as I did above, and because Go implicitly satisfies interfaces, any type that implements this method will be a valid `Doer`.

Speaking of which, if this method looks familiar, it's probably because this is implemented by the `*http.Client`. This is the general-purpose method to make HTTP requests. Other methods of the client, such as `Get` or `Post`, are just helpers built on top of `Do` (at least conceptually - internally they end up calling a common unexported method). Why not provide all the methods of the `*http.Client`? Because they are just helpers and all you really need is `Do`. Take one for the team, and minimize the API surface by using just this one (it's really not that hard), making life easier for the users of your package.

You can then have your package initialized like this or something similar:

```
func NewFooBar(client Doer /*, other options*/) *FooBar{
    httpClient := client
    if httpClient == nil {
        // Using DefaultClient as a fallback default makes sense, the caller
        // explicitly said it doesn't care.
        httpClient = http.DefaultClient
    }
    // rest of initialization
    return &FooBar{
        doer: httpClient,
        // other stuff...
    }
}
```

Users of your package can now configure the client as needed, setting a specific timeout, transport, etc., the community can build interesting "decorators" or wrappers around that interface the same way it has for `http.Handler` and `io.Reader/Writer`, and network calls can easily be mocked for tests.

## One last thing... about retries

Another thing that is quite common is for those packages to implement retries in case of temporary failures, each in subtly (or vastly) different ways, or sometimes not at all, leaving the calling application to implement its retry strategy if needed. Now if you've read this far, you may think that I will suggest implementing a `Doer` middleware that takes care of it, and that would make a ton of sense. But I believe this is one of those rare cases that is more interesting to do at the `http.RoundTripper` level. This way, the `http.Client.Timeout` value applies to the request as a whole, including any retries, making it easier to reason about, and a retry really only needs to consume and close the request body, which is exactly what the Go documentation claims a `RoundTripper` should limit itself to.

I have written such a package, hopefully a good step in the direction of avoiding multiple different and unreusable implementations of HTTP retries scattered everywhere. It is [called rehttp and is available as a BSD-licensed open-source package on Github][rehttp]. Give it a try and raise issues if anything doesn't work as advertised (it is only Go1.6+ though, because of the recent changes in how to cancel a request). I hope you like it and find it useful.

[godefclient]: https://medium.com/@nate510/don-t-use-go-s-default-http-client-4804cb19f779#.7yoflw59x
[rt]: https://golang.org/pkg/net/http/#RoundTripper
[tomas]: https://www.youtube.com/watch?v=xyDkyFjzFVc
[clientthreadsafe]: https://godoc.org/net/http#Client
[limitedreader]: https://golang.org/pkg/io/#LimitReader
[rehttp]: https://github.com/PuerkitoBio/rehttp

