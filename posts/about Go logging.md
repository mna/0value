---
Author: Martin Angers
Title: About Go Logging
Date: 
Description: 
Lang: en
---

# About Go logging

<small>(a humble proposal on how to handle the logger for reusable packages)</small>

TODO : intro...

## Current state of Go loggers

I checked many popular logging packages - those that had over 100 stars at that moment - based on the [awesome-go list][loggers], in addition to the standard library's `log` package. I omitted the `log/syslog` package as [it can be wrapped in a standard `*log.Logger`][syslog].

That means the following packages:

- [log][1]
- [Sirupsen/logrus][2]
- [golang/glog][3]
- [cihub/seelog][4]
- [op/go-logging][5]
- [apex/log][6]
- [inconshreveable/log15][7]
- [mgutz/logxi][8]

Note that there are many more logging packages, and I'm sorry for not including them in that list, I had to draw a line somewhere. Now if you're building a reusable package that needs to log some information, you're faced with an interesting problem - what should be the type of the logger accepted by your package?

The stdlib itself uses, naturally, a `*log.Logger` value when it needs to support this (e.g. in `http.Server`, the `ErrorLog` field is such a value). But with so many fragmentation in the community, and even a package `golang/glog` provided in the language's official repositories, chances are good that the caller of your package does not use the stdlib's `log` package.

Let's look at the various APIs offered by those packages to log an event, starting with the standard library for reference.

- **log**
    * Print(...interface{}), Printf(string, ...interface{}), Println(...interface{})
    * Panic(...interface{}), Panicf(string, ...interface{}), Panicln(...interface{})
    * Fatal(...interface{}), Fatalf(string, ...interface{}), Fatalln(...interface{})

Let's just focus on the signature for now using the `Print` family (the same comment applies to `Panic` and `Fatal` too). It's unclear to me why there's a `Print` and a `Println` variant, given that the `log` package adds a newline after the message if there was none. The difference is subtle and is the same as the one between `Sprint`:

> Spaces are added between operands when neither is a string.

and `Sprintln`:

> Spaces are always added between operands [...]

I guess it may be useful sometimes. So take note of the signature of the various functions, and let's check what the community-provided logging packages have to offer.

- **Sirupsen/logrus** : logrus supports leveled logging, but all method signatures are the same as the stdlib's logger, so I'll just list the method names.
    * Debug, Debugf, Debugln
    * Error, Errorf, Errorln
    * Fatal, Fatalf, Fatalln
    * Info, Infof, Infoln
    * Panic, Panicf, Panicln
    * Print, Printf, Println
    * Warn, Warnf, Warnln (and Warning, Warningf, Warningln, aliases to the `Warn*` family)

Logrus acknowledges the issue of compatibility with the stdlib's logger (and the fragmentation of the logging abstraction) with the [StdLogger interface][stdiface].

- **golang/glog** : glog also supports leveled logging, and again it supports the same signatures as the stdlib's logger, but each "family" of functions has an additional member: `XDepth(depth int, args ...interface{})`, where "X" is "Error", "Info", "Fatal", etc. The `depth` determines the call frame to log.
    * Error, Errorf, Errorln, ErrorDepth
    * Exit, Exitf, Exitln, ExitDepth
    * Fatal, Fatalf, Fatalln, FatalDepth
    * Info, Infof, Infoln, InfoDepth
    * Warning, Warningf, Warningln, WarningDepth

- **cihub/seelog** : seelog also provides leveled logging, but is inconsistent in the function signatures - while the argument list is the same as the stdlib's logger, some functions return an error (I haven't looked into it to see why it was done this way, I assume it has a good reason).
    * Critical, Criticalf (both have the expected arguments, but return an error)
    * Debug, Debugf (signature compatible with the stdlib's logger)
    * Error, Errorf (both return an error)
    * Info, Infof (compatible)
    * Trace, Tracef (compatible)
    * Warn, Warnf (both return an error)

- **op/go-logging** : go-logging also provides leveled logging, and all methods have the compatible signature.
    * Critical, Criticalf
    * Debug, Debugf
    * Error, Errorf
    * Fatal, Fatalf
    * Info, Infof
    * Notice, Noticef
    * Panic, Panicf
    * Warning, Warningf

- **apex/log** : here again, leveled logging is provided and all methods have the compatible signature.
    * Debug, Debugf
    * Error, Errorf
    * Fatal, Fatalf
    * Info, Infof
    * Warn, Warnf

- **inconshreveable/log15** : leveled logging, in this case only the `Printf`-style of method signature is provided, in a compatible way.
    * Crit (conceptually, "Critf")
    * Error (conceptually, "Errorf")
    * Debug (you get the idea...)
    * Info
    * Warn

- **mgutz/logxi** : leveled logging, and mostly stdlib's logger-compatible method signatures, except some return an error. But there's a twist : although the signature is compatible, the way this logger treats the string argument and the variadic list of `interface{}` values is different. It is not a `fmt.Sprintf` behaviour, instead it prints the string argument as-is, and treats the variadic values as a list of key-value pairs.
    * Debug (compatible, but with a twist)
    * Error (returns an error)
    * Fatal (compatible, but with a twist)
    * Info (compatible with a twist)
    * Trace (compatible with a twist)
    * Warn (returns an error)

What stands out is that althout logrus is interface-level compatible with the stdlib's logger, no other package is (the "Print" family is lacking, generally replaced by leveled logging with "Info", "Debug", "Error" and such). What the wide majority of packages do support, however, is the signature of the logging function, especially the "Printf"-style: `func(string, ...interface{})`.

## Accept a `LogFunc`

In this situation, the most flexible option seems to be to accept a `LogFunc` parameter in your package, with the "Printf"-style signature. For example (variable type added for clarity, if you initialize it with `log.Printf` you can get rid of the type):

```
package mypkg

// LogFunc is a function that logs the provided message with optional
// fmt.Sprintf-style arguments. By default, logs to the default log.Logger.
var LogFunc func(string, ...interface{}) = log.Printf
```

And setting it to `nil` can be used to disable logging for this package. This doesn't enforce a coupling with any specific package and is already widely supported by existing loggers. To paraphrase Mr Carmack, sometimes, the elegant abstraction is just a function.

I don't think a reusable package should worry about the level of logging, it should either log something clearly important (e.g. the `http.Server` logs panics in a handler) or not log at all. Let the caller of the package worry about which level this should be logged to (e.g. pass in `seelog.Debugf` or a `glog.Infof`).

Similarly, the package should not worry about the formatting and the "backend" of the logger. Again, it's up to the caller to provide the method from a properly configured logger that will take care of rendering the logged message as desired, be it JSON in a file or plain text to some logging-as-a-service platform.

The downside is that some logging packages do not play well with that approach - logxi being the outsider in this list, treating the arguments as key-value pairs instead of `fmt.Sprintf` style.

## Closing thoughts

I've kept this article focused on the abstraction of the logger in the context of a reusable package regardless of the relative merits of the various approaches, but more generally and on a more philosophical (???) note, you should question yourself about the complexity of your logging solution. The proliferation of logging levels has been addressed in [this blog post by Dave Cheney][dch]. The [12-factor app][tfa] manifesto touches on the role of the app regarding logging.

Both tackle a different angle of logging, but both argue for a simpler, more straightforward approach. From the 12-factor app manifest:

> A twelve-factor app never concerns itself with routing or storage of its output stream. It should not attempt to write to or manage logfiles. Instead, each running process writes its event stream, unbuffered, to stdout.

From Dave's post:

> I believe that there are only two things you should log:
>
> - Things that developers care about when they are developing or debugging software.
> - Things that users care about when using your software.
> 
> Obviously these are debug and info levels, respectively.

[1]: https://golang.org/pkg/log/
[2]: https://github.com/Sirupsen/logrus
[3]: https://github.com/golang/glog
[4]: https://github.com/cihub/seelog
[5]: https://github.com/op/go-logging
[6]: https://github.com/apex/log
[7]: https://github.com/inconshreveable/log15
[8]: https://github.com/mgutz/logxi
[loggers]: https://github.com/avelino/awesome-go#logging
[syslog]: https://godoc.org/log/syslog#NewLogger
[stdiface]: https://godoc.org/github.com/Sirupsen/logrus#StdLogger
[dch]: http://dave.cheney.net/2015/11/05/lets-talk-about-logging
[tfa]: http://12factor.net/logs
