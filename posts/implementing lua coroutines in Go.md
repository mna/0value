---
Author: Martin Angers
Title: Implementing Lua coroutines in Go
Date
Lang: en
---

# Implementing Lua Coroutines in Go

I have a funny-weird relationship with the Lua language, I have never written anything remotely useful with it and am unfamiliar with its syntax, but I know its internals quite well, thanks to my obsession with virtual machines and my half-assed attempt at [building the Lua VM in Go][lune]. Anyway, Lua has this nice feature called [coroutines][coro], and I'll let [wikipedia introduce it][wiki] to those unfamiliar with the concept:

> Coroutines are computer program components that generalize subroutines to allow multiple entry points for suspending and resuming execution at certain locations.

Now, I hear you already, Go has channels! Yes, this is partly academic and partly for a challenge, and spoiler alert: channels will be summoned, but I think it still has some interest and merit as a useful feature on its own, as we'll see.
