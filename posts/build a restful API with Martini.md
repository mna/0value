---
Author: Martin Angers
Title: Build a RESTful API with Martini
Description: 
Date: 2013-11-27
Lang: en
---

# Build a RESTful API with Martini

I've been looking for an excuse to try [Martini][] ever since it was announced on the golang-nuts mailing list. Martini is a Go package for web server development that skyrocketed to close to 2000 stars on GitHub in just a few weeks (the first public commit is a month old). So I decided to build an example application that implements a (pragmatic) RESTful API, based on [mostly-agreed-upon best practices][api]. The companion code for this article [can be found on GitHub][mapiex].

## Why Martini?

Martini has many things going for it, chief among them is the very elegant API using only a thin layer of abstraction over the stdlib's excellent `net/http` package, and the fact that it understands [the ubiquitous `http.Handler` interface][handler].

Another key point is that if Martini ever feels magical to you (me no like magic), you absolutely should peek at the code. It is a very slim and manageable ~400 lines of code (it was this morning anyway), with a single external dependency, the [inject][] package, another skinny ~100 lines of code.

Please note that it is currently under active development, and some examples may be broken due to recent changes. I'll try to keep my source code repository up-to-date.

## Use cases

The example application will expose a single resource, music albums, under the `/albums` URI. It will support:

* `GET /albums` : list all available albums, with optional filtering based on band, title or year using query string parameters
* `GET /albums/:id` : fetch a specific album
* `POST /albums` : create an album
* `PUT /albums/:id` : update an album
* `DELETE /albums/:id` : delete an album.

To make things interesting, responses can be requested in JSON, XML or plain text. Response format will be determined based on the endpoint's extension (`.json`, `.xml` or `.text`, defaulting to JSON).

Because the data store is not the goal of the app, a (read-write) mutex-controlled map is used as in-memory "database", and it implements an interface that defines the required actions:

```
type DB interface {
	Get(id int) *Album
	GetAll() []*Album
	Find(band, title string, year int) []*Album
	Add(a *Album) (int, error)
	Update(a *Album) error
	Delete(id int)
}
```
 
The album data structure is defined like this:

```
type Album struct {
	XMLName xml.Name `json:"-" xml:"album"`
	Id      int      `json:"id" xml:"id,attr"`
	Band    string   `json:"band" xml:"band"`
	Title   string   `json:"title" xml:"title"`
	Year    int      `json:"year" xml:"year"`
}

func (a *Album) String() string {
	return fmt.Sprintf("%s - %s (%d)", a.Band, a.Title, a.Year)
}
```

The field tags control the marshaling of the structure to JSON and XML. The `XMLName` field gives the structure its element name in XML, and is ignored in JSON. The `Id` field is set as an attribute in XML. The other tags simply give a lower-cased name to the serialized fields. The plain text format will use the `fmt.Stringer` interface - that is, the `func String() string` function.

With this out of the way, let's see how Martini is actually used.

## DRY Martini

At the heart of the martini package is the `martini.Martini` type, which implements the `http.Handler` interface, so that it can be passed to `http.ListenAndServe()` like any stdlib handler. Another important notion is that martini uses a middleware-based approach - meaning that you can configure a list of functions to be called in a specific order before the actual route handler is executed. This is very useful to setup things like logging, authentication, session management, etc., and it helps keep things [DRY][].

The package provides the `martini.Classic()` function that creates an instance with sane defaults - common middleware like panic recovery, logging and static file support. This is great for a web site, but for an API, we don't care much about serving static pages, so we won't use the Classic Martini.

Thankfully this is just a convenience function, it is always possible to create a bare Martini instance and configure it manually as needed. Our version looks like this:

```
var m *martini.Martini

func init() {
	m = martini.New()

	// Setup middleware
	m.Use(martini.Recovery())
	m.Use(martini.Logger())
	m.Use(auth.Basic(AuthToken, ""))
	m.Use(MapEncoder)

	// Setup routes
	r := martini.NewRouter()
	r.Get(`/albums`, GetAlbums)
	r.Get(`/albums/:id`, GetAlbum)
	r.Post(`/albums`, AddAlbum)
	r.Put(`/albums/:id`, UpdateAlbum)
	r.Delete(`/albums/:id`, DeleteAlbum)

	// Inject database
	m.MapTo(db, (*DB)(nil))

	// Add the router action
	m.Action(r.Handle)
}
```

The panic recovery and logger middleware are fairly obvious. `auth.Basic()` is a handler provided by the userland add-ons repository [martini-contrib][contrib], and it is a little bit too naive for an API, since we can only feed it a single username-password, and all requests are checked against this tuple. In a more realistic scenario, we would need to support any number of valid access tokens, so this basic auth handler wouldn't fit.

Let's skip over the `MapEncoder` middleware for now, we'll come back to it in a minute. The next step is to setup the routes, and martini provides a nice clean way to do this. It supports placeholders for parameters, and you can even throw some regular expressions in there, that's how the path will end up anyway. The second parameter to the `Get, Post, Put` and co. is the handler to call for this route. Many handlers can be passed on the same route definition (this is a variadic parameter), and they will be executed in order, until one of them writes a response.

Then we define a global dependency. This is a very neat feature of martini (wait, or is it [*icky*][icky] ? :-), it supports global- and request-scoped dependencies, and when it encounters a handler (middleware function or route handler) that asks for a parameter of that type, the dependency injector will feed it the right value. In this case, `m.MapTo()` maps the `db` package variable (the instance of our in-memory database) to the `DB` interface that we defined earlier. This particular case doesn't get much added value versus using the thread-safe, package-global `db` variable directly, but in other cases (like the encoder, see below) it can prove very useful.

The syntax for the second parameter may seem weird, it is just converting `nil` to the pointer-to-DB-interface type, because all the injector needs is the type to map the first parameter to.

The final step, `m.Action()`, adds the router's configuration to the list of handlers that Martini will call.

## The MapEncoder middleware

Back to the `MapEncoder` middleware function, it sets the `Encoder` interface dependency for the current request based on the requested encoding format:

```
// An Encoder implements an encoding format of values to be sent as response to
// requests on the API endpoints.
type Encoder interface {
	Encode(v ...interface{}) (string, error)
}

// The regex to check for the requested format (allows an optional trailing
// slash).
var rxExt = regexp.MustCompile(`(\.(?:xml|text|json))\/?$`)

// MapEncoder intercepts the request's URL, detects the requested format,
// and injects the correct encoder dependency for this request. It rewrites
// the URL to remove the format extension, so that routes can be defined
// without it.
func MapEncoder(c martini.Context, w http.ResponseWriter, r *http.Request) {
	// Get the format extension
	matches := rxExt.FindStringSubmatch(r.URL.Path)
	ft := ".json"
	if len(matches) > 1 {
		// Rewrite the URL without the format extension
		l := len(r.URL.Path) - len(matches[1])
		if strings.HasSuffix(r.URL.Path, "/") {
			l--
		}
		r.URL.Path = r.URL.Path[:l]
		ft = matches[1]
	}
	// Inject the requested encoder
	switch ft {
	case ".xml":
		c.MapTo(xmlEncoder{}, (*Encoder)(nil))
		w.Header().Set("Content-Type", "application/xml")
	case ".text":
		c.MapTo(textEncoder{}, (*Encoder)(nil))
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	default:
		c.MapTo(jsonEncoder{}, (*Encoder)(nil))
		w.Header().Set("Content-Type", "application/json")
	}
}
```

Here, the `MapTo()` injector function is called on a `martini.Context`, meaning that the dependency is scoped to this particular request. The code also sets the correct "Content-Type" header, since even errors will be returned using the requested format.

## The route handlers

I won't go into details of all route handlers (they are defined in the file `api.go` in the example repository), but I'll show one to talk about how martini handles the return values. The single-album GET handler looks like this:

```
func GetAlbum(enc Encoder, db DB, parms martini.Params) (int, string) {
	id, err := strconv.Atoi(parms["id"])
	al := db.Get(id)
	if err != nil || al == nil {
		return http.StatusNotFound, Must(enc.Encode(
			NewError(ErrCodeNotExist, fmt.Sprintf("the album with id %s does not exist", parms["id"]))))
	}
	return http.StatusOK, Must(enc.Encode(al))
}
```

First, we can see that `martini.Params` can be used as parameter to get a map of named parameters defined on the route pattern. If the `id` is not an integer, or if it doesn't exist in the database (I know for a fact that there's no id=0 in the database, which is why I use this dual-purpose `if`), a 404 status code is returned with a correctly-encoded error message. Note the use of the `Must()` function, since we have a `Recovery()` middleware that will trap panics and return a 500, we can safely panic in case of server-side errors. More serious projects would probably want to return a custom message along with the 500, though.

Finally, if all goes well, a code 200 is returned, along with the encoded album. If a route handler returns two values, and the first is an `int`, Martini will use this first value as the status code, and will write the second value as a string to the `http.ResponseWriter`. If the first value is not an `int`, or if there is only one return value, it will write the first value to the `http.ResponseWriter`.

## curl calls

Let's see how it goes with some actual calls to the API.

```
$ curl -i -k -u token: "https://localhost:8001/albums"
HTTP/1.1 200 OK
Content-Type: application/json
Date: Wed, 27 Nov 2013 02:31:46 GMT
Content-Length: 201

[{"id":1,"band":"Slayer","title":"Reign In Blood","year":1986},{"id":2,"band":"Slayer","title":"Seasons In The Abyss","year":1990},{"id":3,"band":"Bruce Springsteen","title":"Born To Run","year":1975}]
```

The `-k` option is required if you use a self-signed certificate. The `-u` option specifies the user:password, which in our case is simply `token:` (empty password). The `-i` option prints the whole response, including headers. The response includes the full list of albums (the database is initialized with those 3 albums).

```
$ curl -i -k -u token: "https://localhost:8001/albums.text?band=Slayer"
HTTP/1.1 200 OK
Content-Type: text/plain; charset=utf-8
Date: Wed, 27 Nov 2013 02:36:46 GMT
Content-Length: 68

Slayer - Reign In Blood (1986)
Slayer - Seasons In The Abyss (1990)
```

In this case, the text format is requested, and a filter is used on the band Slayer. Let's try a POST:

```
$ curl -i -k -u token: -X POST --data "band=Carcass&title=Heartwork&year=1994" "https://localhost:8001/albums"
HTTP/1.1 201 Created
Content-Type: application/json
Location: /albums/4
Date: Wed, 27 Nov 2013 02:38:55 GMT
Content-Length: 57

{"id":4,"band":"Carcass","title":"Heartwork","year":1994}
```

The status code is 201 - Created, the "Location" header is specified with the URL to the newly created resource (note that the URL should be absolute, I was lazy there), and the resource is returned in the default format (JSON). If we try to create the same resource again, in XML for a change:

```
$ curl -i -k -u token: -X POST --data "band=Carcass&title=Heartwork&year=1994" "https://localhost:8001/albums.xml"
HTTP/1.1 409 Conflict
Content-Type: application/xml
Date: Wed, 27 Nov 2013 02:41:36 GMT
Content-Length: 171

<?xml version="1.0" encoding="UTF-8"?>
<albums><error code="2"><message>the album &#39;Heartwork&#39; from &#39;Carcass&#39; already exists</message></error></albums>
```

The error is returned in the correct format, with a status code 409. Updates (PUT) work fine too (I mean, everybody knows Heartwork was released in 1993, right?):

```
$ curl -i -k -u token: -X PUT --data "band=Carcass&title=Heartwork&year=1993" "https://localhost:8001/albums/4"
HTTP/1.1 200 OK
Content-Type: application/json
Date: Wed, 27 Nov 2013 02:45:29 GMT
Content-Length: 57

{"id":4,"band":"Carcass","title":"Heartwork","year":1993}
```

And finally, the delete operation:

```
$ curl -i -k -u token: -X DELETE "https://localhost:8001/albums/1"
HTTP/1.1 204 No Content
Content-Type: application/json
Date: Wed, 27 Nov 2013 02:46:59 GMT
Content-Length: 0
```

## https required

You don't want to expose a basic-authenticated API (or any but the most basic public API) over http, and it is recommended to return an error in case of a clear-text call instead of silently redirecting to https, so that the API consumer can take notice. There are many ways to do this, if you have a reverse proxy in front of your API server, this may be a good place to do it. In the example app, I start two listeners, one on `http` and another on `https`, and the `http` server always returns an error:

```
func main() {
	go func() {
		// Listen on http: to raise an error and indicate that https: is required.
		if err := http.ListenAndServe(":8000", http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			http.Error(w, "https scheme is required", http.StatusBadRequest)
		})); err != nil {
			log.Fatal(err)
		}
	}()

	// Listen on https: with the preconfigured martini instance. The certificate files
	// can be created using this command in this repository's root directory:
	//
	// go run /path/to/goroot/src/pkg/crypto/tls/generate_cert.go --host="localhost"
	//
	if err := http.ListenAndServeTLS(":8001", "cert.pem", "key.pem", m); err != nil {
		log.Fatal(err)
	}
}
```

## What's missing

This is a simple API example application, but it still handles many common API tasks. Martini makes this easy and elegant, thanks to its routing and dependency injection mechanisms. In the short time I took to write this article, it already evolved quite a bit, and some handlers got added to the [martini-contrib][contrib] repository too.

If you intend to build a production-quality API, be aware that there are a few important things missing from this small example application, though:

* A more powerful authentication mechanism, obviously (a single access token won't do!)
* Support for JSON- (and/or XML-) encoded request bodies for POST and PUT verbs (and PATCH)
* Support for 405 - Method not allowed response code (currently, the API will return 404 when an unsupported method is used on a supported route)
* Support for GZIP compression of responses (I see that there is now a Gzip middleware on the martini-contrib repository)
* Probably more depending on your requirements!

However, this article should've given you a taste of how it can be done with Martini. Most features are just a handler away!

[martini]: http://martini.codegangsta.io
[mapiex]: https://github.com/PuerkitoBio/martini-api-example
[inject]: https://github.com/codegangsta/inject
[handler]: http://golang.org/pkg/net/http/#Handler
[api]: http://www.vinaysahni.com/best-practices-for-a-pragmatic-restful-api
[dry]: http://en.wikipedia.org/wiki/Don't_repeat_yourself
[contrib]: https://github.com/codegangsta/martini-contrib
[icky]: https://twitter.com/enneff/status/405603366568329216
