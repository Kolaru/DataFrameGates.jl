module DataFrameGates

using DataFrames
using Intervals
using MacroTools
using ThreadSafeDicts

export Interval

include("gates.jl")

export AbstractGate, AlwaysGate, NeverGate, SelectionGate, MemberGate, ConditionGate
export GateIntersection, GateUnion, InvertedGate
export selectedby, select_groups, isapplicable
export @gate

include("group_gates.jl")
export GroupGate, GroupGateIntersection

#== Common functionnalities ==#

# Note
# ====
# missing values appear in the cache columns when the cache is generated from a view.
# This has two consequences:
# 1. When using selectedby on a DataFrame, after using it on a view of it,
#    there may be missing in the list of indices. This is incorrect, and
#    the list of indices must be recomputed on the whole DataFrame.
# 2. The cache columns will have Union{Missing, Int} as element type.
#    It must be converted to pure Int to allow indexing with it.
# TODO Maybe lock around to make it thread safe
function selectedby(gate, df::AbstractDataFrame)
    id = idstring(gate)
    if !hasproperty(df, id) || any(ismissing, df[!, id])
        df[!, id] = _selectedby(gate, df)
    end
    return disallowmissing(df[!, id])
end

selectedby(gate::Union{AlwaysGate, NeverGate}, df::AbstractDataFrame) = _selectedby(gate, df)

# TODO add filter! for in place filtering
"""
    filter(gate::AbstractGate, df::AbstractDataFrame)

Return a new DataFrame containing only the rows that respect the gating conditions.
"""
Base.filter(gate::Union{AbstractGate, AbstractGroupGate}, df::AbstractDataFrame) = @view df[selectedby(gate, df), :]

remove_cache_columns(df::AbstractDataFrame) = select(df, [col for col in names(df) if first(col) != '_']...)
remove_cache_columns!(df::AbstractDataFrame) = select!(df, [col for col in names(df) if first(col) != '_']...)

export remove_cache_columns, remove_cache_columns!

end