module DataFrameGates

using DataFrames
using Intervals
using MacroTools
using Memoization

export Interval

include("gates.jl")

export AbstractGate, AlwaysGate, SelectionGate, MemberGate, ConditionGate
export GateIntersection, GateUnion, InvertedGate
export selectedby, select_groups, isapplicable
export @gate

include("group_gates.jl")
export PerGroup


end