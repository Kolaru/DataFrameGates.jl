#== Gates ==#
abstract type AbstractGate end

isapplicable(gate::AbstractGate, df::Union{AbstractDataFrame, DataFrameRow}) = hasproperty(df, gate.field)

#== Base Gates ==#
#== AlwaysGate ==#
struct AlwaysGate <: AbstractGate end
(gate::AlwaysGate)(row) = true
idstring(::AlwaysGate) = "_always_gate"
_selectedby(::AlwaysGate, df::AbstractDataFrame) = ones(Bool, nrow(df))
isapplicable(::AlwaysGate, df::Union{AbstractDataFrame, DataFrameRow}) = true

#== NeverGate ==#

struct NeverGate <: AbstractGate end
(gate::NeverGate)(row) = false
idstring(::NeverGate) = "_never_gate"
_selectedby(::NeverGate, df::AbstractDataFrame) = zeros(Bool, nrow(df))
isapplicable(::NeverGate, df::Union{AbstractDataFrame, DataFrameRow}) = true

#== SelectionGate (==) ==#
struct SelectionGate{T} <: AbstractGate
    field::Symbol
    value::T
end

(gate::SelectionGate)(row::DataFrameRow) = (row[gate.field] == gate.value)

function _selectedby(gate::SelectionGate, df::AbstractDataFrame)
    return map(df[!, gate.field]) do value
        coalesce(value == gate.value, false)
    end
end

Base.:(==)(g1::SelectionGate, g2::SelectionGate) = g1.field == g2.field && g1.value == g2.value
idstring(gate::SelectionGate) = "_selection_gate_$(gate.field)_$(gate.value)"

function Base.show(io::IO, gate::SelectionGate)
    print(io, "Gate($(gate.field) == $(gate.value))")
end

#== MemberGate (in) ==#
struct MemberGate{T} <: AbstractGate
    field::Symbol
    ensemble::T
end

(gate::MemberGate)(row) = (row[gate.field] in gate.ensemble)

function _selectedby(gate::MemberGate, df::AbstractDataFrame)
    return map(df[!, gate.field]) do value
        coalesce(value in gate.ensemble, false)
    end
end

Base.:(==)(g1::MemberGate, g2::MemberGate) = g1.field == g2.field && g1.ensemble == g2.ensemble
idstring(gate::MemberGate) = "_member_gate_$(gate.field)_$(hash(gate.ensemble))"

function Base.show(io::IO, gate::MemberGate)
    print(io, "Gate($(gate.field) ∈ $(gate.ensemble))")
end

#== ConditionGate (function) ==#
struct ConditionGate{F} <: AbstractGate
    field::Symbol
    condition::F
end

(gate::ConditionGate)(row) = (gate.condition(row[gate.field]))

function _selectedby(gate::ConditionGate, df::AbstractDataFrame)
    return gate.condition.(df[!, gate.field])
end

Base.:(==)(g1::ConditionGate, g2::ConditionGate) = (g1.field == g2.field && g1.condition == g2.condition)
idstring(gate::ConditionGate) = "_condition_gate_$(gate.field)_$(gate.condition)"

function Base.show(io::IO, gate::ConditionGate)
    print(io, "Gate($(gate.condition)($(gate.field)))")
end


#== Compound Gates ==#
#== GateUnion (∪) ==#
struct GateUnion <: AbstractGate
    gates::Vector{AbstractGate}

    function GateUnion(gates)
        union_gates = filter(g -> isa(g, GateUnion), gates)

        isempty(union_gates) && return new(gates)

        subgates = reduce(vcat, gate.gates for gate in union_gates)
        other_gates = filter(g -> !isa(g, GateUnion), gates)
        return new(vcat(subgates, other_gates))
    end
end

GateUnion(gates...) = GateUnion(collect(gates))

function (gate::GateUnion)(row)
    any(isapplicable(g, row) && g(row) for g in gate.gates)
end

function Base.union(gates::Vararg{AbstractGate})
    return GateUnion(collect(gates))
end

function _selectedby(gate::GateUnion, df::AbstractDataFrame)
    return mapreduce(.|, gate.gates) do gate
        !isapplicable(gate, df) && return falses(nrow(df))
        return selectedby(gate, df)
    end
end

idstring(gate::GateUnion) = "_union_gate" * join(idstring.(gate.gates))

isapplicable(gate::GateUnion, df::Union{AbstractDataFrame, DataFrameRow}) = any(isapplicable.(gate.gates, Ref(df)))

function Base.show(io::IO, gate::GateUnion)
    strs = map(gate.gates) do g
        g isa Union{SelectionGate, MemberGate, GateUnion} && return string(g)
        return "($g)"
    end

    print(io, join(strs, " ∪ "))
end

#== GateIntersection (∩) ==#
struct GateIntersection{T <: Tuple} <: AbstractGate
    gates::T
end

GateIntersection(gates...) = GateIntersection(gates)

(gate::GateIntersection)(row) = all(g(row) for g in gate.gates)

function _selectedby(gate::GateIntersection, df::AbstractDataFrame)
    return reduce((.&), selectedby.(gate.gates, Ref(df)))
end

idstring(gate::GateIntersection) = "_instersection_gate" * join(idstring.(gate.gates))

isapplicable(gate::GateIntersection, df::Union{AbstractDataFrame, DataFrameRow}) = all(isapplicable.(gate.gates, Ref(df)))

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

#== InvertedGate (!) ==#
struct InvertedGate{T <: AbstractGate} <: AbstractGate
    base_gate::T
end

(gate::InvertedGate)(row) = !gate.base_gate(row)

function _selectedby(gate::InvertedGate, df::AbstractDataFrame)
    return .!(selectedby(gate.base_gate, df))
end

idstring(gate::InvertedGate) = "_inverted_gate$(idstring(gate.base_gate))"

isapplicable(gate::InvertedGate, df::Union{AbstractDataFrame, DataFrameRow}) = isapplicable(gate.base_gate, df)

function Base.:(!)(gate::AbstractGate)
    return InvertedGate(gate)
end

function Base.show(io::IO, gate::InvertedGate)
    print(io, "!($(gate.base_gate))")
end

"""
    select_groups(gate::AbstractGate, grouped::GroupedDataFrame ; combine = true)

Return a new DataFrame containing all groups for which at least one row
respect the gating condition.
"""
function select_groups(gate::AbstractGate, grouped::GroupedDataFrame ; combine = true)
    Base.depwarn("select_groups is deprecated in favor of the GroupGate (or PerShot for CEIAnalysis) gates", :select_groups ; force = true)
    groups = grouped[groups_selectedby(gate, grouped)]
    !combine && return groups
    return DataFrames.combine(groups, All())
end

"""
    @gate expr

Create a Gate using the same syntax as boolean comparisons.

For example, the following creates a gate ensuring that the `x` column is `1`:
```
@gate x == 1
```

The macro supports equality operators (`==`, `!=`), comparison operators (`<`, `>` `<=`, `>=`) and `in`.

The conditions can be composed using `&&`, `||` and `!`, for example
```
@gate (x < 1) && !(y in [11, 22, 33])
```
"""
macro gate(expr)
    res = MacroTools.postwalk(expr) do ex
        @capture(ex, key_ == val_) && return :(SelectionGate($(QuoteNode(key)), $val))
        @capture(ex, key_ != val_) && return :(!SelectionGate($(QuoteNode(key)), $val))

        @capture(ex, key_ in ensemble_) && return :(MemberGate($(QuoteNode(key)), $ensemble))
        @capture(ex, key_ ∈ ensemble_) && return :(MemberGate($(QuoteNode(key)), $ensemble))

        @capture(ex, lo_ <= key_ <= hi_) && return :(MemberGate($(QuoteNode(key)), $Interval{$Closed, $Closed}($lo, $hi)))
        @capture(ex, lo_ < key_ <= hi_) && return :(MemberGate($(QuoteNode(key)), $Interval{$Open, $Closed}($lo, $hi)))
        @capture(ex, lo_ <= key_ < hi_) && return :(MemberGate($(QuoteNode(key)), $Interval{$Closed, $Open}($lo, $hi)))
        @capture(ex, lo_ < key_ < hi_) && return :(MemberGate($(QuoteNode(key)), $Interval{$Open, $Open}($lo, $hi)))

        @capture(ex, key_ <= hi_) && return return :(MemberGate($(QuoteNode(key)), $Interval{$Closed, $Closed}(typemin($hi), $hi)))
        @capture(ex, key_ < hi_) && return return :(MemberGate($(QuoteNode(key)), $Interval{$Closed, $Open}(typemin($hi), $hi)))

        @capture(ex, key_ >= lo_) && return return :(MemberGate($(QuoteNode(key)), $Interval{$Closed, $Closed}($lo, typemax($lo))))
        @capture(ex, key_ > lo_) && return return :(MemberGate($(QuoteNode(key)), $Interval{$Open, $Closed}($lo, typemax($lo))))

        @capture(ex, cond1_ || cond2_) && return :(GateUnion($cond1, $cond2))
        @capture(ex, cond1_ && cond2_) && return :(GateIntersection($cond1, $cond2))
        @capture(ex, !cond_) && return :(InvertedGate($cond))
        return ex
    end

    return esc(res)
end

macro gate()
    return :(AlwaysGate())
end