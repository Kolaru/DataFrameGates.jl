# DataFrameGates

[![Build Status](https://github.com/Kolaru/DataFrameGates.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/Kolaru/DataFrameGates.jl/actions/workflows/CI.yml?query=branch%3Amain)

This package provide small utilities to more conveniently filter values in a `DataFrame`.

The idea is to define "gates" that represent a filtering operation,
for example

```julia
gate = @gate x == 2
```

is a gate that select all rows for wich the `x` column is equal to 2.

The effective operation is then performed with `filter`

```julia
df = DataFrame(; x = rand(1:3, 100), y = rand(100))

subdf = filter(gate, df)
```

Defining a new object type for gates has multiple advantages:

1. The gates are defined through a cute and concise `@gate` macro.
2. The gates can be composed.
3. The gating operation is cached, reducing its cost on very large datasets when repeated.


## `@gate` macro

The `@gate` macro describes the gating operation as a combination
of boolean operation,
where the variables are the name of the columns of the DataFrame.

For example for the following DataFrame

```julia
julia> df = DataFrame(; x = rand(100), y = rand(-10:5, 100), z = rand(["foo", "bar", "baz"], 100))
100×3 DataFrame
 Row │ x          y      z      
     │ Float64    Int64  String 
─────┼──────────────────────────
   1 │ 0.367867      -2  baz
   2 │ 0.703514      -1  foo
   3 │ 0.601461      -4  foo
   4 │ 0.634581       0  foo
   5 │ 0.141402       2  bar
  ⋮  │     ⋮        ⋮      ⋮
  96 │ 0.454924      -9  foo
  97 │ 0.967125       2  baz
  98 │ 0.236152       0  baz
  99 │ 0.0679799     -9  foo
 100 │ 0.54899        3  foo
                 90 rows omitted
```

The available symbols are `x`, `y` and `z`,
and we can write a gate such as

```julia
julia> gate = @gate (x in Interval(0, 0.2) && y in 0:5) || z == "foo"
(Gate(x ∈ [0.0 .. 0.2]) ∩ Gate(y ∈ 0:5)) ∪ Gate(z == foo)
```

which represent all rows where either `0 <= x <= 0.2` and
`0 <= y <= 5`, or `z == "foo"`.

Selecting them is done through the `filter` function

```julia
julia> filter(gate, df)
42×3 SubDataFrame
 Row │ x          y      z      
     │ Float64    Int64  String 
─────┼──────────────────────────
   1 │ 0.703514      -1  foo
   2 │ 0.601461      -4  foo
   3 │ 0.634581       0  foo
   4 │ 0.141402       2  bar
   5 │ 0.165646       5  bar
  ⋮  │     ⋮        ⋮      ⋮
  38 │ 0.161969     -10  foo
  39 │ 0.259732     -10  foo
  40 │ 0.454924      -9  foo
  41 │ 0.0679799     -9  foo
  42 │ 0.54899        3  foo
                 32 rows omitted
```

Currently, the supported operation are `in`, `==`, and `!`,
and `||` and `&&` allow to compose them in more complicated gates.


## Composition

Two existing gates can also be composed using `∪` or `∩`
for union of conditions ("or")
or intersection of conditions ("and"), respectively.

```julia
julia> g1 = @gate foo == 2
Gate(foo == 2)

julia> g2 = @gate bar in 1:10
Gate(bar ∈ 1:10)

julia> g1 ∩ g2
Gate(foo == 2) ∩ Gate(bar ∈ 1:10)

julia> (g1 ∩ g2) == @gate(foo == 2 && bar in 1:10)
true
```

Alternatively, existing gates can also be used
as condition in the macro directly

```julia
julia> @gate(foo == 2 && g2)
Gate(foo == 2) ∩ Gate(bar ∈ 1:10)
```