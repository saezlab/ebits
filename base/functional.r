#' Functional programming helpers
#' @name functional
NULL

# This module re-creates quite a few fundamental tools from `pryr`. Why not
# `require(pryr)` instead? The only reason is that pryr contains many more
# utilities which have no place at all in this module. In addition, it does
# some things subtly different.
# Once I manage to put proper name isolation into place, this decision should
# be revisited.

#' Create a local binding for one or more names
#'
#' @usage let(..., .expr)
#' @param ... one or more variable assignments of the form \code{name = value},
#'  where \code{value} can be an arbitrary expression
#' @param .expr an expression to evaluate in a local environment consisting of
#'  the provided variables
#' @return The result of evaluating \code{.expr}.
#'
#' @examples
#' result = let(x = 1, x + 2)
#'
#' # equivalent to
#' result = local({
#'     x = 1
#'     x + 2
#' })

# This uses R's peculiarities in argument matching explained here:
# <http://stat.ethz.ch/R-manual/R-devel/doc/manual/R-lang.html#Argument-matching>
# `.expr` starts with a dot to allow `expr` being used in the actual
# expression.
let = function (.expr, ...)
    eval(substitute(.expr), list2env(list(...), parent = parent.frame()))

#' Create a closure over a given environment for the specified formals and body.
#'
#' Helper function to facilitate the creation of functions from quoted
#' expressions at runtime.
#'
#' @param formals list of formal arguments; list names correspond to parameter
#'  names, list values correspond to quoted parameter defaults
#' @param body quoted expression to use as function body
#' @param env the environment in which to define the function
#' @return A function defined in \code{env}.
#'
#' @examples
#' x = new.env()
#' closure(list(a = quote(expr = )), call('+', quote(a), 1), x)
#' # function (a)
#' # a + 1
#' # <environment: 0x7feec6390b8>
closure = function (formals, body, env)
    eval(call('function', as.pairlist(formals), body), env)

#' A shortcut to create a function
#'
#' @usage f(params -> body)
#' @note Using \code{f(params -> body)} is analogous to using
#' \code{function (params) body}.
f = function (...) {
    params = match.call(expand.dots = FALSE)$...
    len = length(params)

    # Parameters either have default values or not. There are three cases:
    #  1. No default values: `names(params)` is `NULL`, `params` contains
    #   parameter names
    #  2. Some default values: `names(params)` is a vector of appropriate length,
    #   `names(params)[len]` is `''`; `params[i]` contains default value
    #  3. Last parameter has default: `params[[len]]` is `default -> body`.

    if (! inherits(params[[len]], '<-'))
        stop('Must be invoked as `f(params -> expr)`')

    names = if (is.null(names(params))) rep('', len) else names(params)

    # Ensure that last parameter is a name
    if (names[len] == '' && ! inherits(params[[len]][[3]], 'name'))
        stop('Must be invoked as `f(params -> expr)`')

    name_from = function (name, value)
        if (name == '') value else name

    default_from = function (name, value)
        if (name == '') quote(expr = ) else value

    param_names = c(mapply(name_from, names[-len], params[-len]),
                    if (names[len] == '') params[[len]][[3]] else names[len])
    param_defaults = c(mapply(default_from, names[-len], params[-len]),
                       if (names[len] == '') quote(expr = ) else params[[len]][[3]])

    formals  = setNames(param_defaults, param_names)
    body = params[[len]][[2]]
    closure(formals, body, parent.frame())
}

# Tools for function composition and chaining {{{

#' Partial function application
#'
#' \code{partial} and \code{p} apply a function patially over some arguments,
#' matching them from right to left; \code{lpartial} and \code{lp} match them
#' from left to right.
#'
#' @param f a function
#' @param ... partial arguments to the function \code{f}
#' @return A function calling \code{f}, with the provided arguments bound to
#' \code{f}’s parameters, and having as parameters the remaining, un-specified
#' arguments.
#'
#' @note \code{partial} applies the arguments in the opposite order to the
#' (somewhat misnamed) \code{\link{functional::Curry}}.
#' See \link{Examples} for a code comparison.
#' @note \code{p} and \code{lp} are shortcuts for \code{partial} and
#' \code{lpartial}, respectively.
#'
#' @examples
#' # Use partial application to create a function which adds 5 to its argument
#'
#' add5 = p(`+`, 5)
#' # or: add5 = partial(`+`, 5)
#'
#' add5(1 : 4)
#' # 6 7 8 9
#'
#' # The difference between partial and lpartial
#'
#' minus = function (x, y) x - y
#' p(minus, 5)(1)
#' # -4
#'
#' # But:
#'
#' lp(minus, 5)(1)
#' # 4
#' p(minus, x = 5)(1)
#' # 4
#' \dontrun{functional::Curry(minus, 5)(1)}
#' # 4
partial = function (f, ...)
    let(capture = list(...),
        function (...) do.call(f, c(list(...), capture)))

#' @rdname partial
lpartial = function(f, ...)
    let(capture = list(...),
        function (...) do.call(f, c(capture, list(...))))

ppartial = function (f, arg, ...)
    let(capture = list(...), arg = as.character(substitute(arg)),
        function (x) do.call(f, c(setNames(x, arg), capture)))


# Define shortcuts because these functions are so commonly used and constitute
# syntactic noise.
# Not something I would normally do but there's precedence in R; consider `c`.

#' @rdname partial
p = partial
#' @rdname partial
lp = lpartial
pp = ppartial

#' Compose functions \code{g} and \code{f}.
#'
#' @param g a function taking as its argument the return value from \code{f}
#' @param f a function with arbitrary arguments
#' @return A fuction which takes the same arguments as \code{f} and returns the
#' same return type as \code{g}
#'
#' @note Functions are applied in the inverse order of
#' \code{\link{functional::Compose}}:
#' \url{http://tolstoy.newcastle.edu.au/R/e9/help/10/02/4529.html}
#'
#' @note The semantics of \code{compose} are given by the equivalence
#' \code{compose(g, f)(...) = g(f(...))}.
#'
#' @note All three forms of this function (\code{compose}, \code{\%.\%} and
#' \code{\%|>\%}) are exactly identical. The only difference is the order of the
#' arguments, which is reversed in \code{\%|>\%}. \code{\%|>\%} is thus the
#' higher-order function counterpart to \code{\link{\%>\%}}.
compose = function (g, f)
    function (...) g(f(...))

#' @rdname compose
`%.%` = compose

#' @rdname compose
`%|>%` = function (f, g) compose(g, f)

#' Pipe operator like in F#, Bash …
#' @seealso \code{\link{magrittr::\%>\%}}
`%>%` = magrittr::`%>%`

# }}}

# Higher-order list functions {{{

#' @rdname functional
#' @seealso \code{\link{base::Map}}
map = base::Map

#' @rdname functional
#' @seealso \code{\link{base::Reduce}}
reduce = base::Reduce

#' @rdname functional
#' @seealso \code{\link{base::Filter}}
filter = base::Filter

# }}}

# Function objects {{{

#' Higher-order variant of \code{[} and \code{[[}
#'
#' Create a function which, given a list or vector, extracts a given element.
#'
#' @param i index which to extract
#' @return A function taking a vector or list.
#'
#' @note \code{item} corresponds to the extraction operator \code{[[}.
#' \code{items} corresponds to \code{[}.
#' @note The semantics are such that writing \code{item(i)(x)} is the same as
#' \code{x[[i]]}.
#'
#' @examples
#' values = replicate(5, rpois(5, 1), simplify = FALSE)
#' # Get the third value from each generated Poisson distribution:
#' unlist(map(item(3), values))
#' # [1] 1 1 0 3 1
#'
#' # Same as unlist(map(function (x) x[[3]], values))
#'
#' @name Extract
#' @rdname Extract
#' @usage item(i)
item = lp(p, `[[`)

#' @rdname Extract
#' @usage items(i)
items = lp(p, `[`)

#' Negate a function
#'
#' @usage neg(f)
#' @seealso \code{\link{base::Negate}}
neg = p(compose, `!`)

# TODO: Add `and` and `or` analogously

# }}}