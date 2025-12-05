module DataFrameGates

using DataFrames
using Intervals
using MacroTools
using Memoization

export AbstractGate,SelectionGate, MemberGate, GateIntersection, GateUnion, InvertedGate
export selectedby, select_groups
export @gate

export Interval

#== Gates ==#
abstract type AbstractGate end

#== Base Gates ==#
struct SelectionGate{T} <: AbstractGate
    field::Symbol
    value::T
end

(gate::SelectionGate)(row) = (row[gate.field] == gate.value)

@memoize Dict function selectedby(gate::SelectionGate, df::DataFrame)
    return map(df[!, gate.field]) do value
        value == gate.value
    end
end

function Base.show(io::IO, gate::SelectionGate)
    print(io, "Gate($(gate.field) == $(gate.value))")
end


struct MemberGate{T} <: AbstractGate
    field::Symbol
    ensemble::T
end

(gate::MemberGate)(row) = (row[gate.field] in gate.ensemble)

@memoize Dict function selectedby(gate::MemberGate, df::DataFrame)
    return map(df[!, gate.field]) do value
        value in gate.ensemble
    end
end

Base.:(==)(g1::MemberGate, g2::MemberGate) = g1.field == g2.field && g1.ensemble == g2.ensemble

function Base.show(io::IO, gate::MemberGate)
    print(io, "Gate($(gate.field) ∈ $(gate.ensemble))")
end


#== Compound Gates ==#

struct GateUnion{T <: Tuple} <: AbstractGate
    gates::T
end

GateUnion(gates...) = GateUnion(gates)

(gate::GateUnion)(row) = any(g(row) for g in gate.gates)

function Base.union(gates::Vararg{AbstractGate})
    return GateUnion(gates)
end

function selectedby(gate::GateUnion, df::DataFrame)
    return reduce((.|), selectedby.(gate.gates, Ref(df)))
end

function Base.show(io::IO, gate::GateUnion)
    strs = map(gate.gates) do g
        g isa Union{SelectionGate, MemberGate, GateUnion} && return string(g)
        return "($g)"
    end

    print(io, join(strs, " ∪ "))
end


struct GateIntersection{T <: Tuple} <: AbstractGate
    gates::T
end

GateIntersection(gates...) = GateIntersection(gates)

(gate::GateIntersection)(row) = all(g(row) for g in gate.gates)

function selectedby(gate::GateIntersection, df::DataFrame)
    return reduce((.&), selectedby.(gate.gates, Ref(df)))
end

function Base.intersect(gates::Vararg{AbstractGate})
    return GateIntersection(gates)
end

function Base.show(io::IO, gate::GateIntersection)
    strs = map(gate.gates) do g
        g isa Union{SelectionGate, MemberGate, GateIntersection} && return string(g)
        return "($g)"
    end

    print(io, join(strs, " ∩ "))
end


struct InvertedGate{T <: AbstractGate} <: AbstractGate
    base_gate::T
end

(gate::InvertedGate)(row) = !gate.base_gate(row)

function selectedby(gate::InvertedGate, df::DataFrame)
    return .!(selectedby(gate.base_gate, df))
end

function Base.:(!)(gate::AbstractGate)
    return InvertedGate(gate)
end

function Base.show(io::IO, gate::InvertedGate)
    print(io, "!($(gate.base_gate))")
end


#== Functionnalities ==#

"""
    filter(gate::AbstractGate, df::DataFrame)

Return a new DataFrame containing only the rows that respect the gating conditions.
"""
Base.filter(gate::AbstractGate, df::DataFrame) = @view df[selectedby(gate, df), :]

@memoize Dict function groups_selectedby(gate::AbstractGate, grouped::GroupedDataFrame)
    groups = combine(grouped) do group
        (; selected = any(gate, eachrow(group)))
    end
    return groups.selected
end


"""
    select_groups(gate::AbstractGate, grouped::GroupedDataFrame ; combine = true)

Return a new DataFrame containing all groups for which at least one row
respect the gating condition.
"""
function select_groups(gate::AbstractGate, grouped::GroupedDataFrame ; combine = true)
    groups = grouped[groups_selectedby(gate, grouped)]
    !combine && return groups
    return DataFrames.combine(groups, All())
end

#== Macro ==#
# TODO comparisons e.g. x < 0.3, -10 <= x <= 10

macro gate(expr)
    res = MacroTools.postwalk(expr) do ex
        @capture(ex, key_ == val_) && return :(SelectionGate($(QuoteNode(key)), $val))
        @capture(ex, key_ in ensemble_) && return :(MemberGate($(QuoteNode(key)), $ensemble))
        @capture(ex, key_ ∈ ensemble_) && return :(MemberGate($(QuoteNode(key)), $ensemble))

        @capture(ex, cond1_ || cond2_) && return :(GateUnion($cond1, $cond2))
        @capture(ex, cond1_ && cond2_) && return :(GateIntersection($cond1, $cond2))
        @capture(ex, !cond_) && return :(InvertedGate($cond))
        return ex
    end

    # Second pass to turn use the local definitions for the remaining symbols
    return MacroTools.postwalk(res) do ex
        ex isa Symbol && first(string(ex)) != '@' && return esc(ex)
        return ex
    end
end

end
